-- 1.2, crafting requests (CraftRequests.lua): the board card, the one winning claim, the private
-- words and chat, the direct and the guild-mediated rails, disputes and their review, the gold
-- switches, the trade and mail evidence. On the test world: each client holds its own records and
-- hears the others only through the world's lanes. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local N = World.NAMES
local K = assert(loadfile(H.ROOT .. "tests/arena/lib/craft-world.lua"))(H)
local NoErrors = K.NoErrors
local ITEM, OTHER = 14342, 4338

local function Find(lines, text)
	for _, l in ipairs(lines or {}) do if type(l.text) == "string" and l.text:find(text, 1, true) then return l end end
end
local function Printed(c, text)
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return true end end
	return false
end

-- A requester, a crafter who makes ITEM, and a bystander who makes it too.
local function Cast(w, opts)
	opts = opts or {}
	local a = K.Client(w, "Sage Owl", { money = 500000, persists = opts.persists })
	local b = K.Client(w, "Wren Thistle", { money = 500000, persists = opts.persists })
	local c = K.Client(w, "Moss Harrow", { money = 500000, persists = opts.persists })
	K.Recipes(w, b, { [ITEM] = "Mooncloth" })
	K.Recipes(w, c, { [ITEM] = "Mooncloth" })
	return a, b, c
end

-- A taken request with agreed direct terms, the crafter started: a's record.
local function DirectDeal(w, a, b, quantity, unit)
	w:Run(61) -- (a minute apart: each party's words are bounded per minute)
	local r = K.Request(w, a, ITEM, "Mooncloth", quantity or 2)
	assert(b.Craft.Accept(r.id))
	w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", unit or 10000, 0, { source = "manual" }, { rail = "direct", payment = "trade" }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r.id)); assert(b.Craft.ConfirmTerms(r.id))
	w:Run(0)
	assert(b.Craft.Start(r.id))
	w:Run(0)
	assert(r.state == "in_progress", r.state)
	return r
end

print("CraftRequests: the board, the claim, the direct rail")

test("1.2 craft requests: one logged card, one winning claim answered in private, an offer not lost as a replay, a direct sale completed on the crafter's recorded figures with 6%", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local r = K.Request(w, a, ITEM, "Mooncloth", 2, "two bolts, please")
	-- The card: one logged CHANNEL message, the requester's words in it, never over 255 bytes.
	local cards = K.Words(w, "CQ", a)
	eq(#cards, 1); eq(cards[1].dist, "CHANNEL"); eq(cards[1].logged, true)
	assert(#cards[1].msg <= 255 and cards[1].msg:find("two bolts, please", 1, true), cards[1].msg)
	local rb, rc = K.Rec(w, b, r.id), K.Rec(w, c, r.id)
	assert(rb and rc, "both crafters hold the card")
	eq(rb.state, "open"); eq(rb.details, "two bolts, please"); eq(rb.crafter, nil)
	assert(Find(b.Craft.BoardLines(), "Mooncloth"), "on the board")
	assert(Printed(b, "Mooncloth"), "the matching crafter was told")
	-- Two claims; the first one the requester hears wins, the other hears it lost.
	eq(b.Craft.Accept(r.id), true)
	eq(c.Craft.Accept(r.id), true)
	w:Run(0)
	eq(r.crafter, b.name); eq(r.state, "accepted")
	eq(K.Rec(w, b, r.id).crafter, b.name, "the winner heard it in private")
	eq(K.Rec(w, c, r.id).crafter, nil, "the loser is told nothing of who won")
	assert(K.Rec(w, c, r.id).claimLost, "only that his claim lost")
	assert(not w:ChannelText():find("Wren", 1, true), "the channel never names the crafter")
	eq(Find(c.Craft.BoardLines(), "Mooncloth"), nil, "a taken card leaves the bystander's board")
	-- The crafter's first private word after his claim (the offer) is not swallowed as a replay.
	eq(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, { source = "manual" }, { rail = "direct", payment = "trade" }), true)
	w:Run(0)
	assert(r.terms, "the offer reached the requester")
	eq(r.terms.total, 20000)
	eq(a.Craft.ConfirmTerms(r.id), true); eq(b.Craft.ConfirmTerms(r.id), true)
	w:Run(0)
	eq(r.state, "terms"); eq(K.Rec(w, b, r.id).state, "terms"); eq(r.settlement.rail, "direct")
	eq(b.Craft.Start(r.id), true); w:Run(0)
	eq(r.state, "in_progress")
	-- The trade itself: gold one way, goods the other. Seen by both, it completes nothing.
	K.Trade(w, a, b, { aGives = 20000, bItems = { { id = ITEM, count = 2 } } })
	eq(r.state, "in_progress", "an observation decides nothing on the direct rail")
	eq(r.delivery, nil, "and invents no delivery figure")
	assert(r.settlement.direct.gold and r.settlement.direct.item, "both halves were seen by the buyer")
	rb = K.Rec(w, b, r.id)
	assert(rb.settlement.direct.gold and rb.settlement.direct.item, "and by the seller")
	-- The crafter records what he charged; the requester confirms exactly that.
	eq(b.Craft.Deliver(r.id, 2, 18000, "trade"), true); w:Run(0)
	eq(r.state, "delivered"); eq(r.delivery.price, 18000)
	eq(a.Craft.ConfirmDelivery(r.id), true); w:Run(0)
	eq(rb.state, "completed"); eq(r.state, "completed")
	eq(rb.settlement.guildFee, 1080, "6% of the recorded and confirmed 18000")
	eq(rb.settlement.sellerNet, 16920); eq(r.settlement.guildFee, 1080)
	-- (The owner's answer: the seller owes the guild its 6% of a direct sale whatever the Arena's switches say.)
	eq(rb.settlement.feeState, "due", "the gold switches are off here, and the fee is owed all the same")
	eq(r.settlement.feeState, "crafter", "the buyer's copy notes it is the seller's")
	for _, s in ipairs(w:Sent({ type = "CR" })) do eq(s.dist, "WHISPER"); eq(s.logged, true) end
	NoErrors(w)
end)

test("1.2 craft requests: after a claim only private words move a deal; a card cannot close or complete it, name a crafter, or a forged answer adopt a stranger", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local r = DirectDeal(w, a, b)
	local rb = K.Rec(w, b, r.id)
	-- The requester's client (modified) pushes a later card saying the request closed: the crafter's
	-- private deal is untouched, a bystander simply drops the card.
	local forged = w:As(a, function()
		local copy = {}
		for k, v in pairs(r) do copy[k] = v end
		copy.state, copy.crafter, copy.rev = "cancelled", nil, r.rev + 5
		return a.ns.CraftRequests.Card(copy)
	end)
	a.Comm.Send("CHANNEL", forged, nil, false, true)
	w:Run(0)
	eq(rb.state, "in_progress", "a card never moves a deal the crafter is in")
	eq(rb.settlement.state, "awaiting_exchange")
	-- 1.2 review: c1639e1's card had a crafter field anyone named was adopted from. That shape (21
	-- fields, version 1) is refused, and the new card has no such field at all.
	local old = ("CQ~1~zzzold1~1~%d~%d~14342~1~c~~Olympus Ember~Mooncloth~~crafter~a~%s~0~0~~0~"):format(w.clock, w.clock + 3600, c.name)
	eq(c.Craft.ReceiveSnapshot("CHANNEL", a.name, old), false)
	eq(K.Rec(w, c, "zzzold1"), nil, "no record, no private room for the named player")
	-- An "accepted" answer to a claim c never made: refused, nothing adopted.
	local r2 = K.Request(w, a, ITEM, "Mooncloth", 1)
	a.Comm.Whisper(c.name, ("CR~1~%s~50~accepted~%d~abcdef"):format(r2.id, r2.rev), nil, true, true)
	w:Run(0)
	eq(K.Rec(w, c, r2.id).crafter, nil, "no claim of his, no deal of his")
	eq(#c.Craft.ChatTabs(), 0, "and no private request room")
	-- A stranger cannot speak in the deal: not its chat, not its words.
	c.Comm.Whisper(a.name, ("CR~1~%s~1~cancel~gone"):format(r.id), nil, true, true)
	c.Comm.Whisper(a.name, ("CJ~1~%s~1~hello"):format(r.id), nil, false, true)
	w:Run(0)
	eq(r.state, "in_progress"); eq(#r.chat, 2, "only the two context lines")
	NoErrors(w)
end)

test("1.2 craft requests: a restricted crafter's claim loses on the requester's own record; a re-claim waits; a loser's card goes after an hour", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	eq(c.Craft.Accept(r.id), true)
	eq(c.Craft.Accept(r.id), false, "one claim at a time")
	w:Run(0)
	eq(r.crafter, c.name)
	-- A second request; the requester's own records show c owing a reviewed debt.
	local r2 = K.Request(w, a, ITEM, "Mooncloth", 1)
	w:As(a, function()
		r.settlement = { rail = "direct", state = "disputed", dispute = { state = "final", decision = "debt", debtState = "due",
			respondent = c.name, debtDue = w.clock - 10 } }
	end)
	eq(c.Craft.Accept(r2.id), true)
	w:Run(0)
	eq(r2.state, "open", "a requester never takes a claim from a crafter it saw restricted")
	assert(K.Rec(w, c, r2.id).claimLost)
	eq(b.Craft.Accept(r2.id), true); w:Run(0)
	eq(r2.crafter, b.name)
	-- The bystander's taken card is dropped after SEEN_KEEP; the parties' records stay.
	w.clock = w.clock + w:As(c, function() return c.ns.CraftRequests.SEEN_KEEP end) + 10
	c.Craft.Prune(); a.Craft.Prune(); b.Craft.Prune()
	eq(K.Rec(w, c, r2.id), nil)
	assert(K.Rec(w, a, r2.id) and K.Rec(w, b, r2.id))
	NoErrors(w)
end)

print("CraftRequests: the guild-mediated rail")

-- The requester, the crafter and the Treasurer as custodian, with the Arena's live gold on.
local function Mediated(w)
	local a, b = K.Client(w, "Sage Owl", { money = 500000 }), K.Client(w, "Wren Thistle", { money = 500000 })
	local t = K.Role(w, "treasurer", { money = 500000 })
	K.Recipes(w, b, { [ITEM] = "Mooncloth" })
	K.GoLive(w, { a, b, t })
	w:Run(10) -- (the keeper's book opens at his gold)
	return a, b, t
end

-- A mediated deal agreed (gross 10000, postage 30): a's record and the custodian's.
local function MediatedDeal(w, a, b, t, quantity)
	local r = K.Request(w, a, ITEM, "Mooncloth", quantity or 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, { source = "manual" }, { rail = "guild", payment = "trade", custodian = t.name, postage = 30 }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r.id)); assert(b.Craft.ConfirmTerms(r.id)); w:Run(0)
	local rt = K.Rec(w, t, r.id)
	assert(rt and rt.settlement, "the custodian took the contract both parties named")
	return r, rt
end

test("1.2 craft requests (mediated): custody follows what reached the custodian in order; goods before gold never forward; 94/6 settles; the keeper's book holds the escrow apart and counts the 6%", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local balance = t.Treasury.Balance()
	local r, rt = MediatedDeal(w, a, b, t)
	local st = rt.settlement
	eq(st.state, "awaiting_funds"); eq(st.custodian, t.name); eq(st.gross, 10000); eq(st.guildFee, 600); eq(st.sellerNet, 9400)
	-- The crafter hands the goods over before the buyer paid: held, but nothing can go on.
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	eq(st.state, "awaiting_funds"); eq(st.itemQuantity, 1)
	eq(t.Craft.PrepareCustodianForward(r.id), false, "no forward before the buyer's gold")
	-- The buyer pays the exact total: now the custodian holds both, and both parties hear it.
	K.Trade(w, a, t, { aGives = 10000 })
	eq(st.state, "custodian_received")
	eq(r.settlement.state, "custodian_received"); eq(K.Rec(w, b, r.id).settlement.state, "custodian_received")
	eq(r.state, "in_progress")
	-- A second payment of the same amount is the buyer's, never a step back in the deal.
	K.Trade(w, a, t, { aGives = 10000 })
	eq(st.state, "custodian_received"); eq(st.extraCopper, 10000)
	local forward = t.Craft.PrepareCustodianForward(r.id, 30)
	assert(forward and Printed(t, forward.subject), "the Send is the custodian's own, with exact words")
	K.Trade(w, t, a, { aItems = { { id = ITEM, count = 1 } } })
	eq(st.state, "outbound_sent")
	eq(r.settlement.state, "outbound_sent", "the buyer hears it")
	eq(a.Craft.ConfirmDelivery(r.id), true); w:Run(0)
	eq(st.state, "ready_to_settle")
	eq(t.Craft.ReleaseSettlement(r.id), true); w:Run(0)
	eq(st.state, "payout_pending"); eq(K.Rec(w, b, r.id).settlement.state, "payout_pending")
	assert(st.payoutObligation, "the custodian's payout is his own debt in the Arena's ledger")
	K.Trade(w, t, b, { aGives = 9400 })
	eq(st.state, "settled"); eq(rt.state, "completed")
	eq(r.state, "completed"); eq(K.Rec(w, b, r.id).state, "completed")
	eq(st.feeState, "retained")
	-- The book: the 10000 in and the 9400 out are the parties', the 600 the guild's.
	local kinds = {}
	for _, e in ipairs(t.Treasury.Lines()) do kinds[#kinds + 1] = tostring(e.kind) .. ":" .. tostring(e.money) .. (e.excluded and "x" or "") end
	local all = table.concat(kinds, " ")
	assert(all:find("craft:10000x", 1, true) and all:find("craft:9400x", 1, true) and all:find("fee:600", 1, true), all)
	assert(not all:find("arena", 1, true), "never the arena's: " .. all)
	eq(t.Treasury.Balance() - balance, 600, "the 6% alone: the buyer's extra payment is his, held apart too")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a contract is taken once (a resent invite resets nothing); a cancel reaches the custodian and refunds; the deadline refunds when everyone left", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	local st = rt.settlement
	K.Trade(w, a, t, { aGives = 10000 })
	eq(st.state, "funds_reserved")
	local fundedAt = st.fundedAt
	-- The requester's own invite again (a later one, the same words): the custody stays as it is.
	local invite = K.Words(w, "CK", a, t)[1].msg:gsub("^(CK~1~[^~]+~)%d+", "%199")
	a.Comm.Whisper(t.name, invite, nil, true, true)
	w:Run(0)
	eq(st.state, "funds_reserved"); eq(st.fundedAt, fundedAt)
	-- The buyer cancels before any goods: the custodian is told, and owes the exact refund.
	eq(a.Craft.Cancel(r.id, "changed my mind"), true); w:Run(0)
	eq(st.state, "refund_pending")
	eq(r.settlement.state, "refund_pending"); eq(K.Rec(w, b, r.id).settlement.state, "refund_pending")
	eq(t.Craft.RefundSettlement(r.id), true)
	assert(st.refundObligation, "his refund is his debt")
	eq(t.Craft.RefundSettlement(r.id), false, "one instruction")
	K.Trade(w, t, a, { aGives = 10000 })
	eq(st.state, "refunded"); eq(rt.state, "cancelled")
	eq(r.state, "cancelled"); eq(K.Rec(w, b, r.id).state, "cancelled")
	-- A second deal: the buyer pays, then both parties vanish. The custodian is never stuck.
	local r2, rt2 = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	eq(rt2.settlement.state, "funds_reserved")
	w:Logout(a); w:Logout(b)
	w.clock = rt2.settlement.deadline + 1
	t.Craft.Tick()
	eq(rt2.settlement.state, "refund_pending", "past the deadline the held gold goes back")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): once the payout is under way no dispute reopens the gold; a party cannot be the custodian; a crafter's goods never forward from the wrong state", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	assert(t.Craft.PrepareCustodianForward(r.id, 30))
	K.Trade(w, t, a, { aItems = { { id = ITEM, count = 1 } } })
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	assert(t.Craft.ReleaseSettlement(r.id)); w:Run(0)
	eq(rt.settlement.state, "payout_pending")
	-- Now a dispute (the buyer's, or a modified client's straight to the custodian) changes nothing:
	-- a payout and a refund are never both owed.
	eq(a.Craft.OpenDispute(r.id, "second thoughts", ""), false)
	a.Comm.Whisper(t.name, ("CK~1~%s~90~dispute~second thoughts~"):format(r.id), nil, true, true)
	w:Run(0)
	eq(rt.settlement.state, "payout_pending"); eq(rt.settlement.dispute, nil)
	-- A keeper who crafts cannot hold the gold of his own sale.
	local r2 = K.Request(w, a, ITEM, "Mooncloth", 1)
	K.Recipes(w, t, { [ITEM] = "Mooncloth" })
	assert(t.Craft.Accept(r2.id)); w:Run(0)
	eq(r2.crafter, t.name)
	local ok, why = t.Craft.ProposeTerms(r2.id, "finished", 10000, 0, {}, { rail = "guild", payment = "trade", custodian = t.name, postage = 30 })
	eq(ok, false); eq(why, "custodian")
	eq(t.Craft.ConfigureSettlement(r2.id, "guild", "trade", t.name, 0), false)
	NoErrors(w)
end)

print("CraftRequests: disputes, the review and the ladder")

test("1.2 craft requests: a direct-rail dispute reaches a reviewer both parties can check; the verdict waits the cure window, restricts after it on both clients, and a cure lifts it; nobody is removed", function()
	local w = World.New()
	local a, b = Cast(w)
	local k = K.Role(w, "councillor")
	local r = DirectDeal(w, a, b)
	-- The crafter delivered; the buyer never pays.
	assert(b.Craft.Deliver(r.id, 2, 20000, "trade")); w:Run(0)
	eq(b.Craft.OpenDispute(r.id, "buyer did not pay", "two bolts traded"), true); w:Run(0)
	local rb = K.Rec(w, b, r.id)
	eq(rb.settlement.dispute.state, "open"); eq(r.settlement.dispute.state, "open", "the other party holds the dispute too")
	eq(r.settlement.dispute.openedBy, b.name, "opened by the crafter, as both clients say")
	-- A party cannot be the reviewer, and the reviewer must be one both clients can check.
	eq(b.Craft.Escalate(r.id, a.name), false)
	eq(b.Craft.Escalate(r.id, "Nobody Special-Emberfall"), false)
	eq(b.Craft.Escalate(r.id, k.name), true); w:Run(0)
	eq(r.settlement.dispute.reviewer, k.name)
	local rk = K.Rec(w, k, r.id)
	assert(rk and rk.settlement.dispute.state == "open", "the reviewer holds the case")
	-- Not before the promised cure window; never by a party.
	local ok, why = k.Craft.ReviewDispute(r.id, "debt", "no gold seen", a.name)
	eq(ok, false); eq(why, "cure-window")
	ok, why = b.Craft.ReviewDispute(r.id, "debt", "my own case", a.name)
	eq(ok, false)
	w.clock = rk.settlement.dispute.cureUntil
	eq(k.Craft.ReviewDispute(r.id, "debt", "no gold seen", a.name), true); w:Run(0)
	local d = r.settlement.dispute
	eq(d.state, "final"); eq(d.decision, "debt"); eq(d.respondent, a.name)
	eq(rb.settlement.dispute.respondent, a.name, "both parties hold the verdict")
	-- The ladder: a notice inside the cure window, then restricted, on both parties' clients.
	local notice = a.Craft.PrivilegeStatus(a.name)
	eq(notice.tier, "notice"); eq(notice.canRequest, true)
	w.clock = d.debtDue
	local on = a.Craft.PrivilegeStatus(a.name)
	eq(on.tier, "restricted"); eq(on.canRequest, false); eq(on.canAccept, false)
	eq(b.Craft.PrivilegeStatus(a.name).tier, "restricted", "the counterparty sees it too")
	w:As(a, function()
		local R = a.ns.CraftRequests
		R.OpenComposer(); R.SelectItem({ id = ITEM, name = "Mooncloth" }, "craft")
		local rec, why2 = R.PublishDraft()
		eq(rec, false); eq(why2, "craft-debt", "a restricted buyer posts no new request")
		R.CloseComposer()
	end)
	-- Only the reviewer records the cure; both parties hear it.
	eq(b.Craft.RecordDisputeCure(r.id, "paid"), false)
	eq(k.Craft.RecordDisputeCure(r.id, "paid in full"), true); w:Run(0)
	eq(a.Craft.PrivilegeStatus(a.name).tier, "clear"); eq(b.Craft.PrivilegeStatus(a.name).tier, "clear")
	eq(rawget(a.ns.CraftRequests, "AuthorizeRemoval"), nil, "no removal action exists")
	NoErrors(w)
end)

test("1.2 craft requests: a verdict from anyone but the named reviewer is refused; a cancel after the goods changed hands becomes a dispute, never an escape", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local k = K.Role(w, "councillor")
	local r = DirectDeal(w, a, b)
	assert(b.Craft.OpenDispute(r.id, "late", "")); w:Run(0)
	assert(b.Craft.Escalate(r.id, k.name)); w:Run(0)
	-- c, a stranger, "rules": nothing changes.
	c.Comm.Whisper(a.name, ("CK~1~%s~9~verdict~debt~%s~0~forged"):format(r.id, b.name), nil, true, true)
	w:Run(0)
	eq(r.settlement.dispute.state, "open")
	-- A second deal: the crafter traded the goods (seen by both), then the buyer cancels.
	-- (Intended change in the review's second pass: the buyer's own client saw the goods arrive, so
	-- it refuses his cancel there, as it does the crafter's; a cancel word all the same, a modified
	-- client's, still becomes a dispute on the crafter's side, and the buyer's record holds it.)
	local r2 = DirectDeal(w, a, b, 1)
	K.Trade(w, a, b, { bItems = { { id = ITEM, count = 1 } } })
	local refused, refusedWhy = a.Craft.Cancel(r2.id, "never mind")
	eq(refused, false); eq(refusedWhy, "performed")
	eq(r2.state, "in_progress")
	a.Comm.Whisper(b.name, ("CR~1~%s~80~cancel~never mind"):format(r2.id), nil, true, true)
	w:Run(0)
	local rb2 = K.Rec(w, b, r2.id)
	eq(rb2.state, "in_progress", "the crafter's deal is not cancelled away")
	eq(rb2.settlement.state, "disputed"); eq(rb2.settlement.dispute.reason, "cancel-after-performance")
	eq(r2.settlement.dispute and r2.settlement.dispute.state, "open", "the buyer's record holds the dispute too")
	-- And the crafter, who handed his goods over, cannot cancel his own way out either.
	local r3 = DirectDeal(w, a, b, 1)
	K.Trade(w, b, a, { aItems = { { id = ITEM, count = 1 } } })
	local ok, why = b.Craft.Cancel(r3.id, "oops")
	eq(ok, false); eq(why, "performed")
	-- A requester confirms only the crafter's own figures; another figure books nothing.
	assert(b.Craft.Deliver(r3.id, 1, 9000, "trade")); w:Run(0)
	b.Comm.Whisper(a.name, ("CR~1~%s~90~deliver~1~1~trade"):format(r3.id), nil, true, true)
	a.Comm.Whisper(b.name, ("CR~1~%s~91~complete~1~1"):format(r3.id), nil, true, true)
	w:Run(0)
	eq(K.Rec(w, b, r3.id).state, "delivered", "a completion naming another figure books nothing")
	NoErrors(w)
end)

print("CraftRequests: the gold switches and the guild fee")

test("1.2 craft requests: the guild rail needs the Arena's live gold (live switch, gold, saved data that survives); off, it is refused at every door and the direct rail goes on", function()
	local w = World.New()
	local a, b = Cast(w)
	local t = K.Role(w, "treasurer")
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	eq(a.Craft.GoldGate(), "live", "the King's live switch is off")
	local ok, why = b.Craft.ConfigureSettlement(r.id, "guild", "trade", t.name, 0)
	eq(ok, false); eq(why, "live")
	ok, why = b.Craft.ProposeTerms(r.id, "finished", 10000, 0, {}, { rail = "guild", payment = "trade", custodian = t.name })
	eq(ok, false); eq(why, "live")
	-- A modified crafter's guild-rail offer: the requester's client refuses it.
	b.Comm.Whisper(a.name, ("CR~1~%s~40~offer~1~f~1~10000~0~0~0~0~manual~g~t~%s~30"):format(r.id, t.name), nil, true, true)
	w:Run(0)
	eq(r.terms, nil)
	-- The custodian refuses an invite while the switches are off.
	a.Comm.Whisper(t.name, ("CK~1~%s~1~invite~7ps~7ga~go~b2m~1~t~u~%s~%s~%s~Olympus Ember"):format(r.id, "1p9xyz", a.name, b.name), nil, true, true)
	w:Run(0)
	eq(K.Rec(w, t, r.id) and K.Rec(w, t, r.id).settlement, nil)
	eq(b.Craft.ConfigureSettlement(r.id, "direct", "trade"), true, "the direct rail needs no switch")
	-- Live, but saved data that does not survive a logout (the Forever beta): still off. Live with
	-- data that survives: on, until the player switches the Arena off.
	local w2 = World.New()
	local a2 = K.Client(w2, "Sage Owl", { persists = false })
	local b2 = K.Client(w2, "Wren Thistle")
	K.GoLive(w2, { b2 })
	eq(a2.Craft.GoldGate(), "persist")
	eq(b2.Craft.GoldGate(), nil)
	assert(b2.Arena.SetOff(true))
	eq(b2.Craft.GoldGate(), "off")
	NoErrors(w); NoErrors(w2)
end)

-- (The owner's answer: the 6% applies to direct sales too. It replaces the earlier test that the
-- fee was a debt only with the Arena's gold switches on, and advisory otherwise.)
local function Completed(w, a, b, unit)
	local r = DirectDeal(w, a, b, 1, unit)
	assert(b.Craft.Deliver(r.id, 1, unit or 10000, "trade")); w:Run(0)
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	return r, K.Rec(w, b, r.id)
end
local function OneEntry(desk)
	local led = desk.Craft.FeeLedger()
	local list = {}
	for _, e in pairs(led and led.entries or {}) do list[#list + 1] = e end
	eq(#list, 1, "one fee on the desk's ledger")
	return list[1]
end
local function NavHas(lines, text)
	for _, l in ipairs(lines or {}) do
		for _, n in ipairs(l.nav or {}) do if type(n.text) == "string" and n.text:find(text, 1, true) then return n end end
	end
end
local function HearsDesk(clients, desk)
	for _, c in ipairs(clients) do
		c.Treasury.Heard(desk.name)
		c.Treasury.MarkReader(desk.name)
	end
end
local function Count(c, text)
	local n = 0
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then n = n + 1 end end
	return n
end

test("1.2 craft requests (the guild fee): a direct sale's 6% is the seller's debt whatever the Arena's switches say: due by a deadline, late it warns him and stops his claims; the buyer's copy never restricts him", function()
	local w = World.New()
	local a, b = Cast(w)
	local r, rb = Completed(w, a, b)
	eq(a.Craft.GoldGate(), "live", "the King's live switch is off")
	eq(rb.state, "completed"); eq(rb.settlement.guildFee, 600)
	eq(rb.settlement.feeState, "due", "owed all the same")
	eq(rb.settlement.feeDue, rb.completedAt + b.Craft.FEE_DUE)
	assert(Printed(b, "Olympus craft fee " .. r.id), "he is told how much, by when, to whom and the mail's subject")
	eq(r.settlement.feeState, "crafter")
	eq(b.Craft.PrivilegeStatus(b.name).tier, "notice")
	eq(b.Craft.FeesOwed().count, 1)
	assert(Find(b.Craft.BoardLines(), "Guild fees you owe"), "above his board")
	-- Late: the warning, and no new claims.
	K.Jump(w, rb.settlement.feeDue + 1 - w.clock)
	w:Run(61)
	eq(Count(b, "Late:"), 1, "warned")
	eq(b.Craft.PrivilegeStatus(b.name).tier, "restricted")
	w:Run(61)
	local r2 = K.Request(w, a, ITEM, "Mooncloth", 1)
	local ok, why = b.Craft.Accept(r2.id)
	eq(ok, false); eq(why, "craft-debt")
	eq(a.Craft.PrivilegeStatus(b.name).tier, "clear", "the buyer's copy never restricts him on it")
	-- Once a session and a day, never every minute.
	w:Run(600)
	eq(Count(b, "Late:"), 1)
	K.Jump(w, 86400)
	w:Run(61)
	eq(Count(b, "Late:"), 2)
	-- A test build never owes it: shown, owed to nobody.
	local w2 = World.New()
	local a2 = K.Client(w2, "Sage Owl", { testBuild = { n = 3, base = "1.2.0", built = World.CLOCK - 60, expires = World.CLOCK + 86400 } })
	local b2 = K.Client(w2, "Wren Thistle", { testBuild = { n = 3, base = "1.2.0", built = World.CLOCK - 60, expires = World.CLOCK + 86400 } })
	K.Recipes(w2, b2, { [ITEM] = "Mooncloth" })
	local _, rb2 = Completed(w2, a2, b2)
	eq(rb2.settlement.feeState, "advisory")
	w2.clock = w2.clock + 30 * 86400
	eq(b2.Craft.PrivilegeStatus(b2.name).tier, "clear")
	NoErrors(w); NoErrors(w2)
end)

test("1.2 craft requests (the guild fee): both parties tell the fee desk of the sale; the buyer's word goes even when the seller's client never answers; one fee per sale however often a word comes; nobody else's word books one", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c }, desk)
	local r = DirectDeal(w, a, b, 1)
	assert(b.Craft.Deliver(r.id, 1, 10000, "trade")); w:Run(0)
	-- The seller's client goes quiet before the buyer confirms (a modified client never answers).
	w:Logout(b)
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	local e = OneEntry(desk)
	eq(e.crafter, b.name); eq(e.requester, a.name); eq(e.fee, 600); eq(e.state, "due")
	assert(e.by.b and not e.by.s, "the buyer's word alone")
	assert(r.settlement.feeReport.acked, "the desk answered the buyer")
	local said = #K.Words(w, "CK", a, desk)
	w:Run(31 * 60)
	eq(#K.Words(w, "CK", a, desk), said, "once answered, the buyer's word is not sent again")
	-- The same word again, and a word from someone who is neither party: one fee still.
	local word = K.Words(w, "CK", a, desk)[1].msg
	a.Comm.Whisper(desk.name, word, nil, true, true)
	c.Comm.Whisper(desk.name, (word:gsub("~b~", "~s~")), nil, true, true)
	w:Run(0)
	OneEntry(desk)
	-- The seller back: his own word joins the same fee.
	K.Relog(w, b)
	HearsDesk({ b }, desk)
	w:As(b, function()
		local rb = b.ns.CraftRequests.Get(r.id)
		assert(rb.state == "delivered", rb.state)
	end)
	a.Comm.Whisper(b.name, ("CR~1~%s~50~complete~1~10000"):format(r.id), nil, true, true)
	w:Run(61)
	eq(K.Rec(w, b, r.id).state, "completed")
	e = OneEntry(desk)
	assert(e.by.s and e.by.b, "both said so")
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): the fee mail lands in the desk's book as the guild's money, never a donation; the seller's next word hears it paid and his restriction goes", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	w:Run(10) -- (the keeper's book opens at his gold)
	HearsDesk({ a, b }, desk)
	local r, rb = Completed(w, a, b)
	local e = OneEntry(desk)
	assert(e.by.s and e.by.b, "both said so")
	K.Jump(w, rb.settlement.feeDue + 1 - w.clock)
	w:Run(61)
	eq(b.Craft.PrivilegeStatus(b.name).tier, "restricted")
	-- His fill names the desk and the subject; the mail he sends stops the clock.
	b.Craft.PayFee(r.id)
	assert(Printed(b, "Olympus craft fee " .. r.id))
	local balance = desk.Treasury.Balance()
	local i = w:Mail(b, desk, 600, "Olympus craft fee " .. r.id)
	eq(rb.settlement.feeState, "mailed")
	eq(b.Craft.PrivilegeStatus(b.name).tier, "clear", "mailed: the clock stops")
	w:Take(desk, i)
	eq(e.state, "paid"); eq(e.paid, 600)
	eq(desk.Treasury.Balance() - balance, 600, "the guild's money, in the balance")
	local kinds = {}
	for _, l in ipairs(desk.Treasury.Lines()) do kinds[#kinds + 1] = tostring(l.kind) .. ":" .. tostring(l.money) .. (l.excluded and "x" or "") end
	assert(table.concat(kinds, " "):find("fee:600", 1, true), table.concat(kinds, " "))
	for _, g in ipairs(desk.Treasury.Totals().ranking) do assert(g.money == 0 or not g.name:find("Wren", 1, true), "never a donation") end
	-- His next word to the desk (its addon heard again, as its asks are) hears it paid.
	w:Run(30 * 60)
	HearsDesk({ b }, desk)
	w:Run(61)
	eq(rb.settlement.feeState, "paid")
	eq(b.Craft.FeesOwed().count, 0)
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): the Treasurer's characters and the King read the debtors, ranked and in detail; the King's copy is the desk's answer, paced; nobody else, and never a preview of the Treasurer's or the King's view", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	local king = K.Role(w, "king")
	HearsDesk({ a, b, c, king }, desk)
	local r1 = Completed(w, a, b, 10000)
	w:Run(61)
	Completed(w, a, b, 20000)
	-- b's two are late past a second deadline; c's sale, later, is not due yet.
	K.Jump(w, 2 * b.Craft.FEE_DUE + 60)
	HearsDesk({ a, b, c, king }, desk)
	w:Run(61)
	Completed(w, a, c, 5000)
	local d = desk.Craft.Debtors()
	eq(#d.ranking, 2); eq(d.ranking[1].name, b.name, "the most overdue first")
	eq(d.ranking[1].owed, 1800); eq(d.ranking[1].count, 2); eq(d.ranking[1].late, 1800)
	eq(d.ranking[1].level, 2, "late past a second deadline: the Watch's step")
	eq(d.ranking[2].name, c.name); eq(d.ranking[2].late, 0); eq(d.ranking[2].level, 0)
	eq(#d.entries, 3)
	assert(desk.Craft.DebtorsText():find(b.name, 1, true), "the copy names him")
	-- The King asks: the desk answers a word at a time, and his copy is replaced at its end.
	eq(king.Craft.Debtors().entries[1], nil, "nothing before the answer")
	assert(king.Craft.AskDebtors())
	w:Run(30)
	local kd = king.Craft.Debtors()
	eq(#kd.entries, 3); eq(kd.ranking[1].name, b.name); eq(kd.ranking[1].owed, 1800)
	-- Asking again at once is refused; the desk answers a reader once each DEBTS_ASK_GAP.
	eq(king.Craft.AskDebtors(), false)
	-- Nobody else: a member reads none, and the desk answers none of his asks.
	eq(a.Craft.Debtors(), nil)
	a.Comm.Whisper(desk.name, "CK~1~fees~7~debtors", nil, true, true)
	w:Run(30)
	local toA = 0
	for _, m in ipairs(K.Words(w, "CK", desk, a)) do if m.msg:find("~debt", 1, true) then toA = toA + 1 end end
	eq(toA, 0)
	-- Debt words the King never asked for change nothing on his copy.
	desk.Comm.Whisper(king.name, ("CK~1~zz9~%d~debt~%s~%s~7ps~go~0~1~s~0~1~Olympus Ember"):format(w.clock + 99, c.name, a.name), nil, true, true)
	w:Run(0)
	eq(#king.Craft.Debtors().entries, 3)
	-- A preview of the Treasurer's or the King's view reads nothing, and has no page for it.
	local v = K.Client(w, "Fern Lantern")
	rawset(v.ns, "ViewAs", { Is = function(what) return what == "treasurer" or what == "king" end })
	eq(v.Treasury.IsKeeper(), true, "(the preview shows a keeper's pages)")
	eq(v.Craft.Debtors(), nil)
	eq(NavHas(v.Craft.BoardLines(), "Guild fees"), nil)
	assert(NavHas(desk.Craft.BoardLines(), "Guild fees"), "the desk's page has the tab")
	assert(NavHas(king.Craft.BoardLines(), "Guild fees"), "and the King's")
	for _, x in ipairs({ desk, king }) do
		x.Craft.SetPage("fees")
		local lines = x.Craft.BoardLines()
		assert(Find(lines, "Debtors"), "the ranking")
		assert(Find(lines, "1. Wren Thistle"), "the most overdue first")
		assert(Find(lines, "Every fee owed"), "and every fee")
		eq(NavHas(lines, "Paid by hand") ~= nil, x == desk, "the desk's own clicks, on the desk alone")
		x.Craft.SetPage("board")
	end
	eq(NavHas(a.Craft.BoardLines(), "Guild fees"), nil, "a member's has none")
	-- The desk's own click: paid by hand, with a note; the seller's next word hears it.
	local key
	for _, e in ipairs(desk.Craft.Debtors().entries) do if e.id == r1.id then key = e.key end end
	eq(desk.Craft.SettleFee(key, "paid", ""), false, "a note first")
	eq(desk.Craft.SettleFee(key, "paid", "traded at the bank"), true)
	eq(king.Craft.SettleFee(key, "waived", "no"), false, "the desk's alone")
	w:Run(30 * 60)
	HearsDesk({ b }, desk)
	w:Run(61)
	eq(K.Rec(w, b, r1.id).settlement.feeState, "paid")
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): a reminder from the desk or the King warns the debtor; anyone else's is ignored; one a day per debtor", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b }, desk)
	local r = Completed(w, a, b)
	local d = desk.Craft.Debtors()
	local key = d.entries[1].key
	assert(desk.Craft.RemindDebtor(key)); w:Run(0)
	eq(Count(b, "reminds you"), 1)
	eq(desk.Craft.RemindDebtor(key), false, "one a day")
	a.Comm.Whisper(b.name, ("CK~1~%s~%d~feeremind~go~1"):format(r.id, w.clock + 5), nil, true, true)
	w:Run(0)
	eq(Count(b, "reminds you"), 1, "a member's reminder is ignored")
	NoErrors(w)
end)

-- (The owner's answer, 2026-10-04: the debtors are the Treasurer's, the High Council's, the King's
-- and the author's to read, and nobody else's. Before it the desk answered the King alone.)
test("1.2 craft requests (the guild fee): a High Councillor and the author read the debtors too, ranked and in detail, from the desk's answer; they remind nobody; a Steward or an arbiter reads none", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	local hc, author = K.Role(w, "councillor"), K.Role(w, "author")
	local steward, arbiter = K.Role(w, "steward"), K.Role(w, "arbiter")
	HearsDesk({ a, b, hc, author, steward, arbiter }, desk)
	local r = Completed(w, a, b, 10000)
	for _, x in ipairs({ hc, author }) do
		eq(x.Craft.Debtors().entries[1], nil, x.short .. ": nothing before the answer")
		eq(x.Craft.AskDebtors(), true, x.short .. " asks the desk")
	end
	w:Run(30)
	for _, x in ipairs({ hc, author }) do
		local d = x.Craft.Debtors()
		eq(#d.entries, 1, x.short); eq(d.entries[1].id, r.id); eq(d.ranking[1].name, b.name); eq(d.ranking[1].owed, 600)
		assert(x.Craft.DebtorsText():find(b.name, 1, true), x.short .. ": the copy names him")
		assert(NavHas(x.Craft.BoardLines(), "Guild fees"), x.short .. ": the page has the tab")
		x.Craft.SetPage("fees")
		local lines = x.Craft.BoardLines()
		assert(Find(lines, "1. Wren Thistle"), x.short .. ": the ranking")
		assert(Find(lines, "Every fee owed"), x.short .. ": and every fee")
		eq(NavHas(lines, "Remind him"), nil, x.short .. ": the collection's reminders are the desk's and the King's")
		eq(x.Craft.RemindDebtor(d.entries[1].key), false, x.short .. " reminds nobody")
		x.Craft.SetPage("board")
	end
	w:Run(0)
	eq(Count(b, "reminds you"), 0)
	hc.Comm.Whisper(b.name, ("CK~1~%s~%d~feeremind~go~1"):format(r.id, w.clock + 5), nil, true, true)
	w:Run(0)
	eq(Count(b, "reminds you"), 0, "a councillor's reminder word changes nothing on the debtor")
	-- Nobody else: the Steward and an arbiter read none, ask none, and the desk answers none of theirs.
	for _, x in ipairs({ steward, arbiter }) do
		eq(x.Craft.Debtors(), nil, x.short)
		eq(x.Craft.AskDebtors(), false, x.short)
		eq(NavHas(x.Craft.BoardLines(), "Guild fees"), nil, x.short .. ": no page for it")
		x.Comm.Whisper(desk.name, "CK~1~fees~7~debtors", nil, true, true)
	end
	w:Run(30)
	for _, x in ipairs({ steward, arbiter }) do
		local words = 0
		for _, m in ipairs(K.Words(w, "CK", desk, x)) do if m.msg:find("~debt", 1, true) then words = words + 1 end end
		eq(words, 0, x.short .. ": the desk answered nothing")
	end
	NoErrors(w)
end)

-- The review of the guild fee (a modified client's words, the keepers' own mail, a mail's days,
-- the ledger's room, a sale the buyer never confirmed, the King's copy, a fee paid by hand).
local function Entry(desk, id)
	for _, e in pairs(desk.Craft.FeeLedger().entries) do if e.id == id then return e end end
end
local function FeeWordTo(w, from, desk, id, role, requester, crafter, gross36)
	from.Comm.Whisper(desk.name, ("CK~1~%s~%d~fee~%s~%s~%s~%s~b2m~1~"):format(id, w.clock + 7, role, requester, crafter, gross36), nil, true, true)
	w:Run(0)
end

test("1.2 craft requests (the guild fee): the buyer's word alone puts nobody on the ladder: it waits apart, with no reminder and no Watch warning, until the desk confirms it by hand", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	local king = K.Role(w, "king")
	HearsDesk({ a, b, c, king }, desk)
	-- c names himself the buyer of a sale b never made (a modified client's made-up word).
	FeeWordTo(w, c, desk, "fake01", "b", c.name, b.name, "8ow")
	local e = assert(Entry(desk, "fake01"), "kept for the desk to check")
	eq(e.fee, 675)
	local d = desk.Craft.Debtors()
	eq(#d.ranking, 0, "no debtor on a buyer's word alone")
	eq(#d.entries, 0, "and no fee owed in the ranked list")
	eq(#d.toCheck, 1, "it waits apart")
	local ok, why = desk.Craft.RemindDebtor(e.key)
	eq(ok, false); eq(why, "unconfirmed")
	eq(Count(b, "reminds you"), 0)
	-- (The desk's character an officer of the Watch, whose warning is recorded here.)
	local warned = {}
	rawset(desk.ns, "Watch", { CanManage = function() return true end, IssueWarning = function(name) warned[#warned + 1] = name return true end })
	desk.Craft.SetPage("fees")
	local lines = desk.Craft.BoardLines()
	eq(Find(lines, "1. Wren Thistle"), nil, "not ranked")
	assert(Find(lines, "To check"), "the section apart")
	eq(NavHas(lines, "Remind him"), nil)
	assert(NavHas(lines, "Confirm"), "the desk's own click")
	-- Three deadlines later still nobody on the ladder, and no Watch warning.
	K.Jump(w, 4 * desk.Craft.FEE_DUE)
	HearsDesk({ a, b, c, king }, desk)
	eq(#desk.Craft.Debtors().ranking, 0)
	eq(desk.Craft.WarnDebtor(b.name), false, "no Watch warning")
	eq(NavHas(desk.Craft.BoardLines(), "Warn (the Watch)"), nil)
	eq(#warned, 0)
	-- The King's copy keeps it apart too.
	assert(king.Craft.AskDebtors()); w:Run(30)
	local kd = king.Craft.Debtors()
	eq(#kd.ranking, 0); eq(#kd.toCheck, 1)
	-- The desk confirms it by hand, with a note: ranked from then, a fresh deadline.
	eq(desk.Craft.SettleFee(e.key, "confirmed", ""), false, "a note first")
	eq(king.Craft.SettleFee(e.key, "confirmed", "no"), false, "the desk's alone")
	eq(desk.Craft.SettleFee(e.key, "confirmed", "the buyer's trade, checked with both"), true)
	d = desk.Craft.Debtors()
	eq(#d.ranking, 1); eq(d.ranking[1].name, b.name); eq(d.ranking[1].level, 0, "a fresh deadline from the confirmation")
	assert(desk.Craft.RemindDebtor(e.key)); w:Run(0)
	eq(Count(b, "reminds you"), 1)
	-- Late on the confirmed fee: the Watch's warning is the reader's to give.
	K.Jump(w, desk.Craft.FEE_DUE + 1)
	assert(NavHas(desk.Craft.BoardLines(), "Warn (the Watch)"), "offered once he is late")
	eq(desk.Craft.WarnDebtor(b.name), true)
	eq(warned[1], b.name)
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): the higher of the two figures sets the fee; the seller's lower word leaves the gap for the desk, and a small mail pays none of it off", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	w:Run(10)
	HearsDesk({ a, b }, desk)
	local r = Completed(w, a, b)
	local e = OneEntry(desk)
	eq(e.fee, 600)
	w:Run(61)
	-- The seller's modified client says the sale was 1s.
	FeeWordTo(w, b, desk, r.id, "s", a.name, b.name, "2s")
	e = OneEntry(desk)
	eq(e.grossS, 100); eq(e.grossB, 10000)
	eq(e.fee, 600, "the buyer's higher figure")
	local i = w:Mail(b, desk, 6, "Olympus craft fee " .. r.id)
	w:Take(desk, i)
	eq(e.paid, 6); eq(e.state, "due", "6c pays none of the 600 off")
	local d = desk.Craft.Debtors()
	eq(#d.ranking, 0, "the gap is the desk's to decide")
	eq(#d.toCheck, 1)
	desk.Craft.SetPage("fees")
	assert(Find(desk.Craft.BoardLines(), "disagree"), "the gap shows")
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): the King's character's fee mail is booked on the desk (a transfer between keepers' books all the same); 31 days on he is clear", function()
	local w = World.New()
	local a = K.Client(w, "Sage Owl", { money = 500000 })
	local king = K.Role(w, "king", { money = 500000 })
	K.Recipes(w, king, { [ITEM] = "Mooncloth" })
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	w:Run(10)
	HearsDesk({ a, king }, desk)
	local r, rk = Completed(w, a, king)
	eq(rk.settlement.feeState, "due")
	local e = OneEntry(desk)
	local i = w:Mail(king, desk, 600, "Olympus craft fee " .. r.id)
	w:Take(desk, i)
	eq(e.state, "paid", "booked against his fee")
	local kinds = {}
	for _, l in ipairs(desk.Treasury.Lines()) do kinds[#kinds + 1] = tostring(l.kind) .. ":" .. tostring(l.money) end
	assert(table.concat(kinds, " "):find("transfer:600", 1, true), table.concat(kinds, " "))
	K.Jump(w, 31 * 86400)
	w:Run(61)
	eq(king.Craft.PrivilegeStatus(king.name).tier, "clear")
	eq(#desk.Craft.Debtors().ranking, 0)
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): a fee mailed is never owed again by the clock alone (where no desk ever answers); only its mail seen coming back opens it, with a fresh deadline", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	-- (The desk's addon is never heard: nothing can ever say the fee is paid.)
	local r, rb = Completed(w, a, b)
	eq(rb.settlement.feeState, "due")
	local i = w:Mail(b, desk, 600, "Olympus craft fee " .. r.id)
	eq(rb.settlement.feeState, "mailed")
	K.Jump(w, 31 * 86400)
	w:Run(61)
	eq(b.Craft.PrivilegeStatus(b.name).tier, "clear", "paid as far as his client can tell")
	eq(b.Craft.FeesOwed().count, 0)
	eq(Count(b, "Late:"), 0)
	-- The mail comes back: owed again, from the day it came back.
	w:Return(desk, i)
	w:Take(b, #b.inbox)
	eq(rb.settlement.feeState, "due")
	assert(Printed(b, "came back"), "he is told")
	eq(b.Craft.FeesOwed().count, 1)
	eq(b.Craft.PrivilegeStatus(b.name).tier, "notice", "a fresh deadline")
	K.Jump(w, b.Craft.FEE_DUE + 1)
	w:Run(61)
	eq(b.Craft.PrivilegeStatus(b.name).tier, "restricted")
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): one member's own words fill a bounded part of the desk's ledger; a real sale is still booked", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c }, desk)
	w:As(desk, function()
		desk.ns.CraftRequests.FEES_MAX = 5
		desk.ns.CraftRequests.FEES_PER_SELLER = 3
	end)
	-- c says he sold five things nobody bought, a copper of fee each.
	for n = 1, 5 do FeeWordTo(w, c, desk, "fk0" .. n, "s", a.name, c.name, "h") end
	local mine = 0
	for _, e in pairs(desk.Craft.FeeLedger().entries) do if e.crafter == c.name then mine = mine + 1 end end
	eq(mine, 3, "his own words open FEES_PER_SELLER fees at most")
	w:Run(61)
	local r = Completed(w, a, b)
	local e = assert(Entry(desk, r.id), "the real sale is booked")
	eq(e.fee, 600)
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): a delivery the buyer never confirms still owes the fee on the seller's own figures; so does a trade both clients saw; a dispute holds it for the reviewer", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c }, desk)
	local r = DirectDeal(w, a, b, 1)
	assert(b.Craft.Deliver(r.id, 1, 10000, "trade")); w:Run(0)
	local rb = K.Rec(w, b, r.id)
	local wait = b.Craft.CONFIRM_WAIT or 72 * 60 * 60
	K.Jump(w, wait - 60)
	w:Run(61)
	eq(rb.settlement.feeState, nil, "the buyer may still confirm or dispute")
	K.Jump(w, 120)
	HearsDesk({ a, b, c }, desk)
	w:Run(61)
	eq(rb.settlement.feeState, "due", "owed on his own recorded figures")
	eq(rb.settlement.guildFee, 600)
	assert(rb.settlement.feeDue >= w.clock + b.Craft.FEE_DUE - 120, "due from then")
	eq(rb.state, "delivered", "the deal still waits for the buyer")
	local e = OneEntry(desk)
	assert(e.by.s, "the desk heard the seller")
	-- The buyer confirms after all: one fee still.
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(61)
	eq(K.Rec(w, b, r.id).state, "completed")
	e = OneEntry(desk)
	assert(e.by.s and e.by.b, "both said so")
	-- A trade both clients saw, though nobody recorded the delivery.
	w:Run(61)
	local r2 = DirectDeal(w, a, c, 1)
	K.Trade(w, a, c, { aGives = 10000, bItems = { { id = ITEM, count = 1 } } })
	K.Jump(w, wait + 60)
	HearsDesk({ a, b, c }, desk)
	w:Run(61)
	eq(K.Rec(w, c, r2.id).settlement.feeState, "due")
	local e2 = assert(Entry(desk, r2.id))
	assert(e2.by.s and e2.by.b, "the seller's word and the buyer's (his addon saw the trade)")
	-- A dispute holds it: the reviewer decides. (b is late on his first fee by now: c sells.)
	w:Run(61)
	local r3 = DirectDeal(w, a, c, 1)
	assert(c.Craft.Deliver(r3.id, 1, 10000, "trade")); w:Run(0)
	assert(a.Craft.OpenDispute(r3.id, "not what we agreed")); w:Run(0)
	K.Jump(w, wait + 60)
	w:Run(61)
	eq(K.Rec(w, c, r3.id).settlement.feeState, nil)
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): the King's copy says when it holds part of the desk's list, on the page and in its copy", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	local king = K.Role(w, "king")
	HearsDesk({ a, b, king }, desk)
	w:As(desk, function() desk.ns.CraftRequests.DEBTS_ANSWER_MAX = 2 end)
	for _ = 1, 3 do Completed(w, a, b) w:Run(61) end
	HearsDesk({ a, b, king }, desk)
	assert(king.Craft.AskDebtors()); w:Run(30)
	king.Craft.SetPage("fees")
	assert(Find(king.Craft.BoardLines(), "2 of the 3"), "a part of the list, said")
	assert(king.Craft.DebtorsText():find("2 of the 3", 1, true), "and in its copy")
	desk.Craft.SetPage("fees")
	eq(Find(desk.Craft.BoardLines(), "of the 3"), nil, "the desk's own page has them all")
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): an ask the desk will not answer yet is refused at once, and the desk's refusal leaves no page waiting", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail")
	local king = K.Role(w, "king")
	HearsDesk({ a, b, king }, desk)
	Completed(w, a, b)
	assert(king.Craft.AskDebtors()); w:Run(30)
	king.Craft.SetPage("fees")
	local lines
	-- 70 seconds on: the desk answers him once each 5 minutes, so the ask waits.
	w:Run(70)
	local ok, why = king.Craft.AskDebtors(true)
	eq(ok, false); eq(why, "fresh")
	eq(Find(king.Craft.BoardLines(), "Asking the Treasurer"), nil)
	-- His client forgot (a reload): the desk's refusal comes back, and the page says when to ask.
	K.Relog(w, king)
	HearsDesk({ king }, desk)
	assert(king.Craft.AskDebtors(true)); w:Run(5)
	king.Craft.SetPage("fees")
	lines = king.Craft.BoardLines()
	eq(Find(lines, "Asking the Treasurer"), nil, "not left waiting")
	assert(Find(lines, "answers again"), "when to ask again")
	NoErrors(w)
end)

test("1.2 craft requests (the guild fee): a fee paid by trade and marked paid by hand is the guild's fee in the desk's book, never a donation or dues", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	w:Run(10)
	HearsDesk({ a, b }, desk)
	Completed(w, a, b)
	local e = OneEntry(desk)
	K.Trade(w, b, desk, { aGives = 600 })
	local function Gift()
		for _, g in ipairs(desk.Treasury.Totals().ranking) do if g.name:find("Wren", 1, true) then return g.money end end
		return 0
	end
	eq(Gift(), 600, "(a trade alone reads as a gift)")
	assert(desk.Craft.SettleFee(e.key, "paid", "traded at the bank"))
	eq(e.state, "paid")
	eq(Gift(), 0, "never a donation")
	local kinds = {}
	for _, l in ipairs(desk.Treasury.Lines()) do kinds[#kinds + 1] = tostring(l.kind) .. ":" .. tostring(l.money) end
	assert(table.concat(kinds, " "):find("fee:600", 1, true), table.concat(kinds, " "))
	assert(Printed(desk, "the guild's fee now"), "he is told which line")
	NoErrors(w)
end)

print("CraftRequests: what the composer knows, the card's end")

test("1.2 craft requests: the composer finds what the board's crafters sent this client and gathered materials under their gatherers' profession; an uncached item is asked of the game once and marked unverified", function()
	local w = World.New()
	local a, b = Cast(w)
	local asked = {}
	a.globals.C_Item.RequestLoadItemDataByID = function(id) asked[id] = (asked[id] or 0) + 1 end
	eq(#a.Craft.SearchItems("moon"), 0, "a buyer with no recipes knows no Mooncloth of his own")
	-- b's listing on the channel, and his recipes on a's click (Crafters.lua's own words).
	w:As(b, function() assert(b.ns.Crafters.SendListing(true)) end)
	w:Run(0)
	w:As(a, function() assert(a.ns.Crafters.AskList(b.name, "197")) end)
	w:Run(30)
	local found = a.Craft.SearchItems("moon")
	eq(#found, 1); eq(found[1].id, ITEM); eq(found[1].kind, "craft"); eq(found[1].professions["197"], "Tailoring")
	-- Gathered materials: their own filter, their gatherers' profession, the English name until the
	-- cache names them, and the game asked once for each, however often the page is drawn.
	local herbs = a.Craft.SearchItems("peacebloom", { kind = "gather" })
	eq(#herbs, 1); eq(herbs[1].id, 2447); eq(herbs[1].gatherKey, "182"); eq(herbs[1].cacheMiss, true)
	eq(herbs[1].name, "Peacebloom")
	a.Craft.SearchItems("", { kind = "gather" })
	eq(asked[2447], 1, "asked of the game once")
	for _, item in ipairs(a.Craft.SearchItems("", { kind = "craft" })) do eq(item.kind, "craft", item.name) end
	-- Requested from the composer: the card is a gathering one, for the herbalists, who are told.
	-- (Herbalism opens no trade skill window, so no Crafters listing ever holds it, and Crafters.Read
	-- drops a profession with no recipes: the herbalist is known by his own skill line, as Forever's
	-- character pane reads it, C_SkillInfo.GetSkillLineInfoByID. An earlier version of this test gave
	-- him a listed Herbalism with no recipes, which the addon cannot reach.)
	local c = K.Client(w, "Moss Harrow2")
	c.globals.C_SkillInfo = { GetSkillLineInfoByID = function(id)
		if id == 182 then return { skillID = 182, name = "Herbalism", isHeader = false, rank = 120, maxRank = 150 } end
	end }
	eq(next(w:As(c, function() return c.ns.Crafters.Mine() end)), nil, "nothing listed")
	-- A miner (his skill line is Mining's alone) is not told.
	local m = K.Client(w, "Moss Harrow3")
	m.globals.C_SkillInfo = { GetSkillLineInfoByID = function(id) if id == 186 then return { skillID = 186, name = "Mining", isHeader = false, rank = 80 } end end }
	w:As(a, function()
		local R = a.ns.CraftRequests
		R.OpenComposer()
		a.ns.Views.SetFilter("crafters", "peacebloom")
		local lines = R.ComposerLines()
		local line = assert(Find(lines, "Peacebloom"), "the composer's line")
		assert(type(line.right) == "string" and line.right:find("not verified", 1, true), "marked unverified")
		line.onClick()
		R.SetComposerQuantity(20)
		assert(R.PublishDraft())
	end)
	w:Run(0)
	local card = K.Words(w, "CQ", a)
	assert(card[#card].msg:find("~20~g~182~o~", 1, true), card[#card].msg)
	assert(Printed(c, "Peacebloom"), "the herbalist was told")
	local line = Find(c.Craft.BoardLines(), "Peacebloom")
	assert(line and line.right:find("You can make this", 1, true), "marked on his board")
	assert(Find(m.Craft.BoardLines(), "Peacebloom"), "the miner has the card")
	eq(Printed(m, "Peacebloom"), false, "but is not told")
	NoErrors(w)
end)

test("1.2 craft requests: an item link the cache does not hold is a marked fallback the requester may publish; an open card nobody took expires on every side after its time", function()
	local w = World.New()
	local a, b = Cast(w)
	local r = w:As(a, function()
		local R = a.ns.CraftRequests
		R.OpenComposer()
		a.ns.Views.SetFilter("crafters", "|cff1eff00|Hitem:99999::::::::60:::::|h[Strange Thing]|h|r")
		local line = assert(Find(R.ComposerLines(), "Strange Thing"), "the fallback's line")
		eq(line.right, "|cff9d9d9d" .. a.ns.L.CRAFT_REQUEST_CACHE_MISS .. "|r")
		line.onClick()
		return assert(R.PublishDraft())
	end)
	w:Run(0)
	eq(r.itemID, 99999); eq(r.itemName, "Strange Thing")
	local rb = K.Rec(w, b, r.id)
	assert(rb and rb.state == "open", "the card on the crafter's board")
	K.Jump(w, a.Craft.REQUEST_TTL + 1)
	a.Craft.All(); b.Craft.All()
	eq(r.state, "expired"); eq(rb.state, "expired")
	local ok, why = b.Craft.Accept(r.id)
	eq(ok, false); eq(why, "state")
	eq(Find(b.Craft.BoardLines(), "Strange Thing"), nil, "off the board")
	NoErrors(w)
end)

print("CraftRequests: limits, the lanes, the evidence")

test("1.2 craft requests: one requester's cards are capped and paced; a flood of other people's cards never evicts a deal this client is in; unlogged words change nothing", function()
	local w = World.New()
	local a, b = Cast(w)
	local r = DirectDeal(w, a, b, 1)
	local R = b.ns.CraftRequests
	local function CardFrom(sender, n)
		return w:As(b, function()
			return R.Card({ id = ("f%dx%d"):format(n, #sender), rev = 1, created = w.clock, expires = w.clock + 3600, itemID = ITEM, quantity = 1, kind = "c",
				profession = "", state = "open", materials = "crafter", guild = World.GUILD, itemName = "Mooncloth", details = "" })
		end)
	end
	-- One requester: ten open cards at most, twelve cards in ten minutes at most.
	local taken = 0
	for n = 1, 12 do
		if w:As(b, function() return R.ReceiveSnapshot("CHANNEL", "Flood Maker-Emberfall", CardFrom("Flood Maker-Emberfall", n)) end) then taken = taken + 1 end
	end
	eq(taken, 10)
	eq(w:As(b, function() return R.ReceiveSnapshot("CHANNEL", "Flood Maker-Emberfall", CardFrom("Flood Maker-Emberfall", 99)) end), false, "paced")
	-- Many requesters, past the board's capacity: other people's cards make room, our deal stays.
	for s = 1, 30 do
		local sender = ("Flood %s-Emberfall"):format(string.char(64 + s % 26 + 1) .. s)
		for n = 1, 9 do w:As(b, function() R.ReceiveSnapshot("CHANNEL", sender, CardFrom(sender, n)) end) end
	end
	b.Craft.Prune()
	assert(K.Rec(w, b, r.id), "the crafter's own deal survives the flood")
	local n = 0
	for _ in pairs(w:As(b, function() return b.ns.rdb.craftRequests.records end)) do n = n + 1 end
	assert(n <= R.BOARD_MAX + R.HISTORY_MAX, n)
	-- Unlogged copies of private words (a modified client's) are dropped before they act.
	a.Comm.Whisper(b.name, ("CR~1~%s~70~cancel~x"):format(r.id), nil, true, false)
	a.Comm.Whisper(b.name, ("CJ~1~%s~70~unlogged words"):format(r.id), nil, false, false)
	w:Run(0)
	eq(K.Rec(w, b, r.id).state, "in_progress"); eq(#K.Rec(w, b, r.id).chat, 2)
	-- A card that came unlogged keeps no words of its requester.
	local card = w:As(a, function() local copy = {} for k, v in pairs(r) do copy[k] = v end copy.id, copy.details, copy.state, copy.crafter = "unlog1", "my own words", "open", nil return a.ns.CraftRequests.Card(copy) end)
	a.Comm.Send("CHANNEL", card, nil, false, false)
	w:Run(0)
	local seen = K.Rec(w, b, "unlog1")
	assert(seen, "the card itself is taken"); eq(seen.details, "", "its words are not")
	NoErrors(w)
end)

test("1.2 craft requests: the auction house is read through the documented C_AuctionHouse pair only while it shows results; an add-on's one price counts once", function()
	local w = World.New()
	local a = K.Client(w, "Sage Owl")
	local g = a.globals
	local rows = { { unitPrice = 100, quantity = 20, auctionID = 1 }, { unitPrice = 104, quantity = 5, auctionID = 2 }, { unitPrice = 900000, quantity = 1, auctionID = 3 } }
	g.C_AuctionHouse = setmetatable({
		GetNumCommoditySearchResults = function(id) return id == ITEM and #rows or 0 end,
		GetCommoditySearchResultInfo = function(id, i) return rows[i] end,
	}, { __index = function(_, k) error("C_AuctionHouse." .. tostring(k) .. " is not Forever's API") end })
	g.AuctionHouseFrame = { IsShown = function() return g.ahShown == true end }
	g.ahShown = false
	eq(a.Craft.ObservePrices(ITEM), 0, "the window closed: nothing read")
	g.ahShown = true
	eq(a.Craft.ObservePrices(ITEM), 3)
	eq(a.Craft.ObservePrices(ITEM), 0, "the same listings again replace themselves")
	local quote = a.Craft.Quote(ITEM)
	eq(quote.median, 104); eq(quote.n, 3)
	-- Auctionator's single price, read three times, is one sample.
	g.ahShown = false
	g.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id) return id == OTHER and 500 or nil end } } }
	for _ = 1, 3 do a.Craft.ObservePrices(OTHER) end
	local none, why = a.Craft.Quote(OTHER)
	eq(none, nil); eq(why, "samples", "one add-on's number, read thrice, is not three samples")
	-- Auctioneer's GetMarketValue reads an item link: it is given the cache's, never the bare id.
	g.Auctionator = nil
	local given
	g.AucAdvanced = { API = { GetMarketValue = function(link) given = link return type(link) == "string" and 700 or nil end } }
	a.Craft.ObservePrices(OTHER)
	assert(type(given) == "string" and given:find("|Hitem:" .. OTHER, 1, true), "Auctioneer was given " .. tostring(given))
	NoErrors(w)
end)

test("1.2 craft requests: trades are read as Forever's TradeFrame does (six slots, the item's ID), whichever of the window's close and \"trade complete\" comes first; a secret message is ignored", function()
	local w = World.New()
	local a, b = Cast(w)
	local r = DirectDeal(w, a, b, 1)
	-- Slot 7 is "will not be traded": an item there is never counted as delivered.
	local seven = {}
	for i = 1, 6 do seven[i] = nil end
	seven[7] = { name = "Mooncloth", count = 1, link = "|cffffffff|Hitem:14342::::::::60:::::|h[Mooncloth]|h|r" }
	w:Trade(a, b, { bItems = seven, aGives = 0 })
	w:Run(3)
	eq((r.settlement.direct.itemQuantity or 0), 0, "slot 7 never counts")
	-- The window closes before the "trade complete" line on some clients: still one observation.
	a.trade = { with = b, gave = 10000, got = 0, gotItems = { { name = "Mooncloth", count = 1, link = "|cffffffff|Hitem:14342::::::::60:::::|h[Mooncloth]|h|r" } } }
	w:Fire(a, "TRADE_SHOW"); w:Fire(a, "TRADE_ACCEPT_UPDATE", 1, 1)
	w:Fire(a, "TRADE_CLOSED")
	w:Fire(a, "UI_INFO_MESSAGE", 0, a.globals.ERR_TRADE_COMPLETE)
	a.trade = nil
	w:Run(3)
	eq(r.settlement.direct.itemQuantity, 1, "seen after the window closed")
	eq(r.settlement.direct.copper, 10000)
	-- A secret UI message (restricted, tainted) is never compared or cut.
	local saved = rawget(_G, "issecretvalue")
	a.globals.issecretvalue = function(v) return v == "SECRET" end
	a.trade = { with = b, gave = 5, got = 0 }
	w:Fire(a, "TRADE_SHOW")
	w:Fire(a, "UI_INFO_MESSAGE", 0, "SECRET")
	a.globals.issecretvalue = saved
	a.trade = nil
	eq(#a.errors, 0, "no error from a secret message")
	NoErrors(w)
end)

test("1.2 craft requests: an idle client registers no trade or mail watcher for requests (the weight rule); a gold mail counts only for the request its subject names", function()
	local w = World.New()
	local a, b = Cast(w)
	local before = #(b.events.TRADE_SHOW or {})
	K.Request(w, a, ITEM, "Mooncloth", 1)
	eq(#(b.events.TRADE_SHOW or {}), before, "a card on the board watches nothing")
	eq(w:As(b, function() return b.ns.ArenaMoney.Installed() end), false, "nor does ArenaMoney's watcher wake for it")
	local r = DirectDeal(w, a, b, 1)
	-- A deal of his: ArenaMoney's watcher (its gold mail takes) and the requests' own (item IDs).
	eq(#(b.events.TRADE_SHOW or {}), before + 2)
	DirectDeal(w, a, b, 1)
	eq(#(b.events.TRADE_SHOW or {}), before + 2, "installed once")
	-- The buyer mails the crafter gold titled for another request: not this one's.
	local i = w:Mail(a, b, 7000, "Olympus craft zzz999")
	w:Take(b, i)
	eq(K.Rec(w, b, r.id).settlement.direct.copper, nil)
	i = w:Mail(a, b, 7000, "Olympus craft " .. r.id)
	w:Take(b, i)
	eq(K.Rec(w, b, r.id).settlement.direct.copper, 7000)
	-- An attachment counts once the mail no longer holds it and the bags hold it.
	local m = K.MailItems(w, b, a, { { id = ITEM, count = 1 } }, "Olympus craft " .. r.id)
	K.TakeItem(w, a, m, 1)
	eq(r.settlement.direct.itemQuantity, 1)
	NoErrors(w)
end)

test("1.2 craft requests: the private request room has no channel or topic fallback, needs no topic consent, and a stranger cannot use it", function()
	local w = World.New()
	local a, b, c = Cast(w)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	local room = "craft:" .. r.id
	w:As(b, function() b.ns.db.chatRooms = false end)
	eq(b.Rooms.ChatOn(), false, "the rooms' consent is unchanged")
	eq(b.Rooms.ChatOn(room), true, "the request's own room needs none")
	eq(b.Rooms.Select(room), true)
	eq(b.Rooms.Send(room, "Fellow-member price?"), true)
	w:Run(0)
	local cj = K.Words(w, "CJ", b)
	eq(#cj, 1); eq(cj[1].dist, "WHISPER"); eq(cj[1].logged, true); eq(cj[1].target, a.name)
	eq(#K.Words(w, "M2", b), 0, "never the chat rooms' M2")
	local hist = a.Rooms.History(room)
	eq(hist[#hist].text, "Fellow-member price?")
	eq(c.Rooms.CanAccess(room), false); eq(c.Rooms.Select(room), false)
	eq(#c.Rooms.History(room), 0)
	local tabs = 0
	for _, t in ipairs(a.Rooms.Tabs()) do if t.id == room then tabs = tabs + 1 end end
	eq(tabs, 1, "the requester's chat page has the room's tab")
	NoErrors(w)
end)

-- The Chat page as ChatRooms.OpenMatter uses it (its room and tab calls, ChatWindow.lua's), each
-- call written down: the window opened on its Chat tab, the room selected there, the window raised
-- (tests/arena/lib/chat-host.lua).
local CH = assert(loadfile(H.ROOT .. "tests/arena/lib/chat-host.lua"))(H)
local ChatHost = CH.Host
local function Tabbed(c, room)
	for _, t in ipairs(c.Rooms.Tabs()) do if t.id == room then return true end end
	return false
end

-- (The owner's decision, 2026-10-04: every pending conversation opens its own tab on the Chat page,
-- the Olympus window in front, kept while the matter is open, reopened from the matter's page.
-- Before it a claim opened nothing, and a tab removed from a finished deal never came back.)
test("1.2 craft requests: the claim won opens the deal's own tab on both parties' clients with the Olympus window in front; its page reopens it, a removed tab too; a fight holds it until the end", function()
	local w = World.New()
	local a, b = Cast(w)
	local ha, hb = ChatHost(a), ChatHost(b)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	eq(#ha.calls + #hb.calls, 0, "a card opens nothing")
	assert(b.Craft.Accept(r.id)); w:Run(0)
	local room = "craft:" .. r.id
	eq(table.concat(ha.calls, ","), "open,select " .. room .. ",raise", "the requester's window comes to the front on the deal's tab")
	eq(table.concat(hb.calls, ","), "open,select " .. room .. ",raise", "and the crafter's")
	assert(Tabbed(a, room) and Tabbed(b, room), "the tab is there")
	eq(a.Craft.RemoveChat(r.id), false, "kept while the deal is open")
	-- Over, the tab can be removed; the request's page brings it back, the window in front again.
	assert(a.Craft.Cancel(r.id, "")); w:Run(0)
	eq(a.Craft.RemoveChat(r.id), true)
	eq(Tabbed(a, room), false, "removed")
	ha.calls = {}
	assert(a.Craft.OpenChat(r.id), "reopened from its page")
	eq(Tabbed(a, room), true, "the removed tab is back")
	eq(table.concat(ha.calls, ","), "open,select " .. room .. ",raise")
	-- In a fight Olympus opens nothing by itself: the deal's tab comes when the fight ends, while the
	-- deal is still open. One that ended meanwhile opens nothing.
	w:Run(61)
	ha.calls, hb.calls = {}, {}
	local r2 = K.Request(w, a, ITEM, "Mooncloth", 2)
	a.combat = true
	assert(b.Craft.Accept(r2.id)); w:Run(0)
	eq(#ha.calls, 0, "nothing during the fight")
	eq(table.concat(hb.calls, ","), "open,select craft:" .. r2.id .. ",raise", "the crafter, out of combat, at once")
	CH.CombatOver(w, a)
	eq(table.concat(ha.calls, ","), "open,select craft:" .. r2.id .. ",raise", "at the fight's end")
	w:Run(61)
	ha.calls = {}
	local r3 = K.Request(w, a, ITEM, "Mooncloth", 3)
	a.combat = true
	assert(b.Craft.Accept(r3.id)); w:Run(0)
	assert(a.Craft.Cancel(r3.id, "")); w:Run(0)
	CH.CombatOver(w, a)
	eq(#ha.calls, 0, "a deal over before the fight ended opens nothing")
	NoErrors(w)
end)

-- (Review of the door: Olympus's own opening of a deal's room skipped the held-alerts rule (in an
-- instance or Busy no window of Olympus's opens by itself, ns.Alert), and it kept one matter alone
-- for a fight's end, its own copy of ns.OutOfCombat in which the newest overwrote the others.)
test("1.2 craft requests: a won claim's room waits as every window that opens by itself: in an instance with the held alerts, named on the Decrees tab, opened once he is out while the deal is open; two deals won in one fight both open at its end", function()
	local w = World.New()
	local a, b = Cast(w)
	local ha = ChatHost(a)
	ChatHost(b)
	local L = a.ns.L
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	a.instance = true
	assert(b.Craft.Accept(r.id)); w:Run(0)
	eq(K.Rec(w, a, r.id).state, "accepted", "the claim is his crafter's")
	eq(#ha.calls, 0, "nothing opens in the instance")
	local held = w:As(a, a.ns.Held)
	eq(#held, 1); eq(held[1].what, L.CHATROOM_MATTER_HELD:format("Mooncloth"), "the held line names the deal's room")
	w:Run(10)
	eq(#ha.calls, 0, "still in it")
	a.instance = nil
	w:Run(10) -- (the held alerts' look, every ten seconds)
	eq(table.concat(ha.calls, ","), "open,select craft:" .. r.id .. ",raise", "out of it: the deal's tab, the window in front")
	eq(#w:As(a, a.ns.Held), 0)
	-- A deal over before he is out opens nothing then, and its line goes.
	w:Run(61)
	ha.calls = {}
	local r2 = K.Request(w, a, ITEM, "Mooncloth", 2)
	a.instance = true
	assert(b.Craft.Accept(r2.id)); w:Run(0)
	assert(a.Craft.Cancel(r2.id, "")); w:Run(0)
	eq(#w:As(a, a.ns.Held), 0, "over: no longer waiting")
	a.instance = nil
	w:Run(10)
	eq(#ha.calls, 0, "an ended deal opens nothing")
	-- Two deals won during one fight: each waits on its own, and both open at its end.
	w:Run(61)
	local r3 = K.Request(w, a, ITEM, "Mooncloth", 3)
	w:Run(61)
	local r4 = K.Request(w, a, ITEM, "Mooncloth", 4)
	ha.calls = {}
	a.combat = true
	assert(b.Craft.Accept(r3.id)); w:Run(0)
	w:Run(61)
	assert(b.Craft.Accept(r4.id)); w:Run(0)
	eq(#ha.calls, 0, "nothing during the fight")
	CH.CombatOver(w, a)
	eq(table.concat(ha.calls, ","), ("open,select craft:%s,raise,open,select craft:%s,raise"):format(r3.id, r4.id), "both, in turn")
	NoErrors(w)
end)

-- (The owner's answer: the guarantee fund is postponed. Its inert model is gone, and with it the
-- test that it stayed off without the gold switches.)
test("1.2 craft requests: the Wallet is an escrow only with real reserve, release and refund; the guarantee fund is postponed: no insurance, claim or guarantee payout exists to call", function()
	local w = World.New()
	local a = K.Client(w, "Sage Owl")
	eq(a.Craft.WalletEscrowAvailable(), false, "this Wallet has no crafting escrow")
	w:As(a, function()
		a.ns.CraftRequests.RegisterEscrowAdapter("wallet", { reserve = function() end, release = function() end })
	end)
	eq(a.Craft.WalletEscrowAvailable(), false, "an adapter without refund is none")
	for _, name in ipairs({ "RegisterInsuranceBackend", "RequestInsurance", "ReviewInsurance", "RecordPremium", "FileClaim", "ReviewClaim",
		"AppealClaim", "FinalizeClaim", "ConfirmClaimDeparture", "AuthorizeGuaranteePayout", "ConfirmGuaranteeReceipt", "RecordInsuredMemberReturn", "Insurance" }) do
		eq(a.ns.CraftRequests[name], nil, name)
	end
	w:As(a, function() a.ns.CraftRequests.All() end)
	eq(a.rdb.craftRequests.insurance, nil, "no guarantee fund in the saved data")
	NoErrors(w)
end)

test("1.2 craft requests: the suggested price is the market reference less 20% and the bounded quantity discount, never under the cost floor, with 6% to the guild", function()
	local w = World.New()
	local a = K.Client(w, "Sage Owl")
	-- Five listings, one absurd: the median and a winsorized mean, blended (worked by hand).
	for i, price in ipairs({ 100, 105, 110, 115, 100000 }) do assert(a.Craft.AddPriceSample(ITEM, price, "fixture AH", w.clock, 1, "l" .. i)) end
	local quote = a.Craft.Quote(ITEM)
	eq(quote.median, 110); eq(quote.reference, 110, "(110 + (105+105+110+115+115)/5) / 2: the outlier is clamped to the second highest")
	-- 12 pieces: 20% plus 2 x 1% for each full 5 beyond the first.
	local t = a.Craft.SuggestTerms({ itemID = ITEM, quantity = 12, materials = "crafter" }, quote)
	eq(t.discountBP, 2200); eq(t.unit, 85, "110 x 0.78 = 85.8, down"); eq(t.total, 1020)
	eq(t.guildFee, 61); eq(t.sellerNet, 959)
	-- A thousand pieces: the quantity part stops at 10%.
	eq(a.Craft.SuggestTerms({ itemID = ITEM, quantity = 1000, materials = "crafter" }, quote).discountBP, 3000)
	-- The floor (what the materials cost) holds.
	assert(a.Craft.SetFloor(ITEM, 95, "materials"))
	eq(a.Craft.SuggestTerms({ itemID = ITEM, quantity = 12, materials = "crafter" }, quote).unit, 95)
	-- Buyer-supplied materials: no market suggestion, the crafter names his fee.
	local none, why = a.Craft.SuggestTerms({ itemID = ITEM, quantity = 1, materials = "buyer" }, quote)
	eq(none, nil); eq(why, "manual_fee")
	-- A quote from the future is no fresher than now: refused, not fresh forever.
	none, why = a.Craft.SuggestTerms({ itemID = ITEM, quantity = 1, materials = "crafter" }, { reference = 100, observedAt = w.clock + 86400 })
	eq(none, nil); eq(why, "quote")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a dispute is put to the custodian, who refunds after the cure window; both parties hear the verdict", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	eq(rt.settlement.state, "funds_reserved")
	eq(a.Craft.OpenDispute(r.id, "nothing made in two weeks", ""), true); w:Run(0)
	local d = rt.settlement.dispute
	eq(d.state, "open"); eq(d.reviewer, t.name, "on this rail the custodian reviews")
	local ok, why = t.Craft.ReviewDispute(r.id, "refund", "too early", nil)
	eq(ok, false); eq(why, "cure-window")
	w.clock = d.cureUntil
	eq(t.Craft.ReviewDispute(r.id, "refund", "no goods reached me", nil), true); w:Run(0)
	eq(rt.settlement.state, "refund_pending")
	eq(r.settlement.dispute.decision, "refund"); eq(K.Rec(w, b, r.id).settlement.dispute.decision, "refund")
	eq(t.Craft.RefundSettlement(r.id), true)
	K.Trade(w, t, a, { aGives = 10000 })
	eq(rt.settlement.state, "refunded"); eq(r.state, "cancelled")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): the buyer is told where to pay only once the custodian took the contract; a refund verdict with nothing held ends the deal; each request's chat tab is its own", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	-- The custodian is away: the invites never reach him, so no payment instruction shows.
	w:Logout(t)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, {}, { rail = "guild", payment = "trade", custodian = t.name, postage = 30 }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r.id)); assert(b.Craft.ConfirmTerms(r.id)); w:Run(0)
	eq(r.settlement.state, "awaiting_funds"); eq(r.settlement.contractAt, nil)
	a.Craft.Open(r.id)
	eq(Find(a.Craft.BoardLines(), t.short), nil, "no 'pay the custodian' before he holds the contract")
	-- With the custodian there, the contract is acknowledged to both parties.
	K.Relog(w, t); w:Run(10)
	w:Run(61)
	local r2, rt2 = MediatedDeal(w, a, b, t)
	assert(r2.settlement.contractAt and K.Rec(w, b, r2.id).settlement.contractAt, "both parties heard the custody exists")
	a.Craft.SetPage("mine"); a.Craft.Open(r2.id)
	assert(Find(a.Craft.BoardLines(), t.short), "now the buyer sees where to pay")
	-- A dispute before any gold: a refund verdict has nothing to give back, so the deal ends.
	assert(a.Craft.OpenDispute(r2.id, "changed terms", "")); w:Run(0)
	w.clock = rt2.settlement.dispute.cureUntil
	eq(t.Craft.ReviewDispute(r2.id, "refund", "nothing was paid", nil), true); w:Run(0)
	eq(rt2.settlement.state, "cancelled"); eq(rt2.state, "cancelled")
	eq(K.Rec(w, a, r2.id).state, "cancelled"); eq(K.Rec(w, b, r2.id).state, "cancelled")
	-- Two of the requester's requests taken: two chat tabs, each its own kind.
	local seen = {}
	for _, tab in ipairs(a.Rooms.Tabs()) do if tostring(tab.id):find("^craft:") then seen[#seen + 1] = tab end end
	assert(#seen >= 2, #seen)
	assert(seen[1].kind ~= seen[2].kind and seen[1].kind == seen[1].id, "one tab underlined at a time")
	NoErrors(w)
end)

print("CraftRequests: the review's second pass (escrow, missed words, the dialogs)")

-- A crafting escrow as a later Wallet could offer one (reserve, verify, release, refund), its calls
-- counted; registered on every client that needs it, as Requests.RegisterEscrowAdapter takes it.
local function FakeWallet(clients)
	local calls = { reserve = 0, release = 0, refund = 0 }
	local adapter = {
		reserve = function() calls.reserve = calls.reserve + 1 return { id = "rv" .. calls.reserve } end,
		verify = function() return true end,
		release = function() calls.release = calls.release + 1 return "rl" .. calls.release end,
		refund = function() calls.refund = calls.refund + 1 return "rf" .. calls.refund end,
	}
	for _, c in ipairs(clients) do assert(c.Craft.RegisterEscrowAdapter("wallet", adapter)) end
	return calls
end

-- A mediated deal agreed with this payment (gross 10000, postage 30): a's record and the custodian's.
local function MediatedOn(w, a, b, t, payment)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, { source = "manual" }, { rail = "guild", payment = payment, custodian = t.name, postage = 30 }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r.id)); assert(b.Craft.ConfirmTerms(r.id)); w:Run(0)
	local rt = K.Rec(w, t, r.id)
	assert(rt and rt.settlement, "the custodian took the contract")
	return r, rt
end

-- The custodian's addon heard on this client, as the treasury records its keepers (Treasury.Online).
local function HearsKeeper(c, t)
	c.Treasury.Heard(t.name)
	c.Treasury.MarkReader(t.name)
end

-- Gold, goods, the custodian's book: the funded, forwarded, confirmed deal up to the seller's payout.
local function ReadyToSettle(w, a, b, t, r)
	K.Trade(w, a, t, { aGives = 10000 })
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	assert(t.Craft.PrepareCustodianForward(r.id, 30))
	K.Trade(w, t, a, { aItems = { { id = ITEM, count = 1 } } })
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	eq(K.Rec(w, t, r.id).settlement.state, "ready_to_settle")
end

test("1.2 craft requests (mediated, Wallet): one reserve per contract; a second click holds nothing twice", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local calls = FakeWallet({ a, b, t })
	local r, rt = MediatedOn(w, a, b, t, "wallet")
	assert(r.settlement.contractAt, "the buyer heard the contract")
	eq(a.Craft.ReserveWallet(r.id), true); w:Run(0)
	local again, why = a.Craft.ReserveWallet(r.id)
	eq(again, false); eq(why, "duplicate")
	eq(calls.reserve, 1, "the buyer's gold is reserved once")
	eq(rt.settlement.fundClaim and rt.settlement.fundClaim.receipt, "rv1")
	NoErrors(w)
end)

test("1.2 craft requests (mediated, Wallet): a cancel before the custodian checked the reserve still gives it back, by his refund", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local calls = FakeWallet({ a, b, t })
	local r, rt = MediatedOn(w, a, b, t, "wallet")
	assert(a.Craft.ReserveWallet(r.id)); w:Run(0)
	eq(rt.settlement.state, "awaiting_funds", "not checked yet")
	assert(a.Craft.Cancel(r.id, "found one")); w:Run(0)
	eq(rt.settlement.state, "refund_pending", "a reserve made for him is held all the same: never left reserved")
	eq(r.settlement.state, "refund_pending", "the buyer's copy follows from before the gold was seen")
	eq(K.Rec(w, b, r.id).settlement.state, "refund_pending")
	eq(t.Craft.RefundSettlement(r.id), true); w:Run(0)
	eq(calls.refund, 1); eq(rt.settlement.state, "refunded")
	eq(r.state, "cancelled"); eq(K.Rec(w, b, r.id).state, "cancelled")
	NoErrors(w)
end)

test("1.2 craft requests (mediated, Wallet): a Wallet payout's 6% is the Wallet's, never a fee line in the keeper's book of his bags", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local calls = FakeWallet({ a, b, t })
	local before, balance = #t.Treasury.Lines(), t.Treasury.Balance()
	local r, rt = MediatedOn(w, a, b, t, "wallet")
	assert(a.Craft.ReserveWallet(r.id)); w:Run(0)
	eq(t.Craft.ConfirmWalletReserve(r.id), true); w:Run(0)
	eq(rt.settlement.state, "funds_reserved")
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	assert(t.Craft.PrepareCustodianForward(r.id, 30))
	K.Trade(w, t, a, { aItems = { { id = ITEM, count = 1 } } })
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	eq(t.Craft.ReleaseSettlement(r.id), true); w:Run(0)
	eq(calls.release, 1); eq(rt.settlement.state, "settled"); eq(rt.state, "completed")
	eq(r.state, "completed"); eq(K.Rec(w, b, r.id).state, "completed")
	local lines = t.Treasury.Lines()
	for i = before + 1, #lines do
		assert(lines[i].kind ~= "fee", "a fee line for gold that never reached his bags: " .. tostring(lines[i].money))
	end
	eq(t.Treasury.Balance(), balance, "his book holds what his bags hold")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): no debt ruling while the custodian holds the buyer's gold; a refund gives it back", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	eq(rt.settlement.state, "funds_reserved")
	assert(b.Craft.OpenDispute(r.id, "the buyer keeps changing the order", "")); w:Run(0)
	w.clock = rt.settlement.dispute.cureUntil
	local ok, why = t.Craft.ReviewDispute(r.id, "debt", "rude", a.name)
	eq(ok, false); eq(why, "funds", "a debt would leave the buyer's gold with the custodian, owed to nobody")
	eq(rt.settlement.dispute.state, "open")
	eq(t.Craft.ReviewDispute(r.id, "refund", "nothing made", nil), true); w:Run(0)
	eq(rt.settlement.state, "refund_pending")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a refund the buyer asked for, then disputed, cannot be ruled cancelled with his gold held", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	assert(a.Craft.Cancel(r.id, "changed my mind")); w:Run(0)
	eq(rt.settlement.state, "refund_pending")
	-- The crafter disputes the refund; the custodian reviews it.
	assert(b.Craft.OpenDispute(r.id, "I already bought the cloth", "")); w:Run(0)
	eq(rt.settlement.state, "disputed"); eq(rt.settlement.previousState, "refund_pending")
	w.clock = rt.settlement.dispute.cureUntil
	local ok, why = t.Craft.ReviewDispute(r.id, "cancel", "no refund", nil)
	eq(ok, false); eq(why, "funds")
	eq(t.Craft.ReviewDispute(r.id, "resume", "the refund stands", nil), true); w:Run(0)
	eq(rt.settlement.state, "refund_pending", "back to the refund he owes")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a refund ruling reaches a party's copy that missed the gold as the custodian's own word: a refund, not a cancel", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	local rb = K.Rec(w, b, r.id)
	-- (As a copy that was offline when the gold reached the custodian: it never heard "funds".)
	rb.settlement.fundedAt, rb.settlement.state = nil, "awaiting_funds"
	assert(a.Craft.OpenDispute(r.id, "nothing made", "")); w:Run(0)
	w.clock = rt.settlement.dispute.cureUntil
	eq(t.Craft.ReviewDispute(r.id, "refund", "no goods reached me", nil), true); w:Run(0)
	eq(rt.settlement.state, "refund_pending")
	eq(rb.settlement.state, "refund_pending", "the crafter's copy follows the custodian, not its own guess")
	eq(rb.state ~= "cancelled", true)
	NoErrors(w)
end)

test("1.2 craft requests (mediated): the buyer's gold beyond the deal is his: the custodian is told, it shows until he gives it back", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	K.Trade(w, a, t, { aGives = 2500 })
	local st = rt.settlement
	eq(st.state, "funds_reserved"); eq(st.extraCopper, 2500)
	assert(Printed(t, "Olympus craft " .. r.id), "the custodian is told what to give back, with the subject")
	local owedText = t.ns.L.CRAFT_EXTRA_LINE:match("^(.-)%%")
	t.Craft.SetPage("duty"); t.Craft.Open(r.id)
	assert(Find(t.Craft.BoardLines(), owedText), "his duty page shows it")
	-- He gives it back by trade: counted, and the line goes. The deal goes on as it was.
	K.Trade(w, t, a, { aGives = 2500 })
	eq(st.extraReturned, 2500); eq(st.state, "funds_reserved")
	eq(Find(t.Craft.BoardLines(), owedText), nil)
	eq(r.state ~= "cancelled", true, "the buyer's copy takes none of it for a refund")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): gold that reaches the custodian after the deal closed is the buyer's to have back, and its return is counted", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local balance = t.Treasury.Balance()
	local r, rt = MediatedDeal(w, a, b, t)
	-- The buyer mails the gold, then cancels before the custodian opened his mail.
	local i = w:Mail(a, t, 10000, "Olympus craft " .. r.id)
	assert(a.Craft.Cancel(r.id, "found one")); w:Run(0)
	eq(rt.state, "cancelled")
	w:Take(t, i)
	local st = rt.settlement
	eq(st.extraCopper, 10000, "late gold: his to have back")
	assert(Printed(t, t.ns.L.CRAFT_EXTRA_READY:match("^%%s (.-) %%s")), "the custodian is told")
	eq(t.Treasury.Balance(), balance, "never counted as a gift to the treasury")
	t.Craft.SetPage("duty"); t.Craft.Open(r.id)
	local owedText = t.ns.L.CRAFT_EXTRA_LINE:match("^(.-)%%")
	assert(Find(t.Craft.BoardLines(), owedText))
	w:Mail(t, a, 10000, "Olympus craft " .. r.id)
	eq(st.extraReturned, 10000)
	eq(Find(t.Craft.BoardLines(), owedText), nil)
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a seller offline when the payout was instructed still ends the deal when it lands, and the custodian hears it", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	ReadyToSettle(w, a, b, t, r)
	w:Logout(b)
	assert(t.Craft.ReleaseSettlement(r.id)); w:Run(0)
	eq(rt.settlement.state, "payout_pending")
	K.Relog(w, b)
	local rb = K.Rec(w, b, r.id)
	assert(rb.settlement.state ~= "payout_pending", "the word was missed")
	local i = w:Mail(t, b, 9400, "Olympus craft " .. r.id)
	w:Take(b, i)
	eq(K.Rec(w, b, r.id).settlement.state, "settled"); eq(K.Rec(w, b, r.id).state, "completed")
	eq(rt.settlement.state, "settled", "the seller's receipt reached the custodian"); eq(rt.state, "completed")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a buyer offline when the refund was owed asks the custodian once he is heard online, and his refund then counts", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	-- The buyer is away when the crafter gives up; the custodian owes the refund.
	w:Logout(a)
	assert(b.Craft.Cancel(r.id, "cannot make it")); w:Run(0)
	eq(rt.settlement.state, "refund_pending")
	assert(t.Craft.RefundSettlement(r.id)); w:Run(0)
	K.Relog(w, a)
	eq(K.Rec(w, a, r.id).settlement.state, "funds_reserved", "the refund's word was missed")
	-- While the treasury has not heard the custodian's addon: no ask (a whisper to an offline
	-- player is a line in the chat). (The treasury's own record, emptied here for the while.)
	local function Asks()
		local n = 0
		for _, s in ipairs(K.Words(w, "CK", a, t)) do if s.msg:find("~ask", 1, true) then n = n + 1 end end
		return n
	end
	local online = a.ns.Treasury.Online
	a.ns.Treasury.Online = function() return {} end
	w:Run(61)
	a.ns.Treasury.Online = online
	eq(Asks(), 0)
	w:Run(61)
	eq(Asks(), 1)
	eq(K.Rec(w, a, r.id).settlement.state, "refund_pending", "the custodian's answer brought the copy up to date")
	w:Run(61)
	eq(Asks(), 1, "once, then only after a quiet while")
	local i = w:Mail(t, a, 10000, "Olympus craft " .. r.id)
	w:Take(a, i)
	eq(K.Rec(w, a, r.id).settlement.state, "refunded"); eq(K.Rec(w, a, r.id).state, "cancelled")
	eq(rt.settlement.state, "refunded", "the buyer's receipt reached the custodian")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): the seller confirms a payout that landed where Olympus could not see it, the buyer his refund", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	ReadyToSettle(w, a, b, t, r)
	assert(t.Craft.ReleaseSettlement(r.id)); w:Run(0)
	eq(a.Craft.ConfirmPayout(r.id), false, "the seller's word alone")
	b.Craft.SetPage("accepted"); b.Craft.Open(r.id)
	assert(Find(b.Craft.BoardLines(), b.ns.L.CRAFT_CONFIRM_PAYOUT))
	eq(b.Craft.ConfirmPayout(r.id), true); w:Run(0)
	eq(rt.settlement.state, "settled"); eq(K.Rec(w, b, r.id).state, "completed")
	w:Run(61)
	local r2, rt2 = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	assert(a.Craft.Cancel(r2.id, "found one")); w:Run(0)
	eq(rt2.settlement.state, "refund_pending")
	eq(b.Craft.ConfirmRefund(r2.id), false, "the buyer's word alone")
	eq(a.Craft.ConfirmRefund(r2.id), true); w:Run(0)
	eq(rt2.settlement.state, "refunded"); eq(rt2.state, "cancelled")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): the two parties' terms closing seconds apart still name one contract", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, {}, { rail = "guild", payment = "trade", custodian = t.name, postage = 30 }))
	w:Run(0)
	assert(b.Craft.ConfirmTerms(r.id)); w:Run(0)
	-- The buyer agrees; his word reaches the crafter two seconds later. Each wrote its own deadline.
	assert(a.Craft.ConfirmTerms(r.id))
	w.clock = w.clock + 2
	w:Run(0)
	local rt = K.Rec(w, t, r.id)
	assert(rt and rt.settlement, "the custodian took the contract both parties named")
	eq(rt.settlement.deadline, rt.settlement.created + t.ns.CraftRequests.SETTLEMENT_TTL, "the custodian's own clock sets the deadline")
	assert(r.settlement.contractAt and K.Rec(w, b, r.id).settlement.contractAt, "both heard it")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): invites the custodian never got go again once he is heard online; he holds a bounded number of open contracts per player", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	w:As(t, function() t.ns.CraftRequests.CUSTODIES_PER_PARTY = 1 end)
	local r1, rt1 = MediatedDeal(w, a, b, t)
	w:Run(61)
	-- The second contract names the same two players: refused while the first is open.
	local r2 = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r2.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r2.id, "finished", 10000, 0, {}, { rail = "guild", payment = "trade", custodian = t.name, postage = 30 }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r2.id)); assert(b.Craft.ConfirmTerms(r2.id)); w:Run(0)
	local rt2 = K.Rec(w, t, r2.id)
	eq(rt2 and rt2.settlement or nil, nil, "one open contract per player here")
	eq(r2.settlement.contractAt, nil)
	-- The first ends; the parties' invites go again (the custodian heard online) and are taken.
	assert(a.Craft.Cancel(r1.id, "not needed")); w:Run(0)
	eq(rt1.state, "cancelled")
	HearsKeeper(a, t); HearsKeeper(b, t)
	w:Run(61)
	rt2 = K.Rec(w, t, r2.id)
	assert(rt2 and rt2.settlement, "taken once both invites came again")
	assert(K.Rec(w, a, r2.id).settlement.contractAt and K.Rec(w, b, r2.id).settlement.contractAt, "both parties heard it")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): the custodian's own debts follow the Arena's switches; switched off mid-deal, the payout is still instructed", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	ReadyToSettle(w, a, b, t, r)
	assert(t.Arena.SetOff(true))
	eq(t.Craft.GoldGate(), "off")
	eq(t.Craft.ReleaseSettlement(r.id), true); w:Run(0)
	eq(rt.settlement.state, "payout_pending")
	eq(rt.settlement.payoutObligation, nil, "no live obligation while the Arena is off")
	assert(Printed(t, rt.settlement.payoutInstruction.subject), "the payout's words are still his")
	NoErrors(w)
end)

test("1.2 craft requests: a reviewer's ruled cases never take the place of the next one", function()
	local w = World.New()
	local a, b = Cast(w)
	local k = K.Role(w, "councillor")
	k.onChannel = false -- (he never saw the cards: each case is a new record of his)
	w:As(k, function() k.ns.CraftRequests.CASES_MAX = 1 end)
	local r = DirectDeal(w, a, b)
	assert(b.Craft.Deliver(r.id, 2, 20000, "trade")); w:Run(0)
	assert(b.Craft.OpenDispute(r.id, "late", "")); w:Run(0)
	assert(b.Craft.Escalate(r.id, k.name)); w:Run(0)
	local rk = K.Rec(w, k, r.id)
	w.clock = rk.settlement.dispute.cureUntil
	eq(k.Craft.ReviewDispute(r.id, "resume", "both agreed to go on", nil), true); w:Run(0)
	w:Run(61)
	local r2 = DirectDeal(w, a, b, 1)
	assert(a.Craft.OpenDispute(r2.id, "wrong colour", "")); w:Run(0)
	assert(a.Craft.Escalate(r2.id, k.name)); w:Run(0)
	local rk2 = K.Rec(w, k, r2.id)
	assert(rk2 and rk2.settlement and rk2.settlement.dispute.state == "open", "the next case is taken")
	-- While that one is open, his one place is taken: a third waits.
	w:Run(61)
	local r3 = DirectDeal(w, a, b, 1)
	assert(a.Craft.OpenDispute(r3.id, "late again", "")); w:Run(0)
	assert(a.Craft.Escalate(r3.id, k.name)); w:Run(0)
	eq(K.Rec(w, k, r3.id), nil, "open cases are bounded")
	NoErrors(w)
end)

test("1.2 craft requests: a preview of the Treasurer's view is no reviewer: a case sent to it is not taken", function()
	local w = World.New()
	local a, b = Cast(w)
	local v = K.Client(w, "Fern Lantern")
	rawset(v.ns, "ViewAs", { Is = function(what) return what == "treasurer" end })
	eq(v.Treasury.IsKeeper(), true, "(the preview shows a keeper's pages)")
	local B36 = v.ns.Codec.Base36
	a.Comm.Whisper(v.name, ("CK~1~%s~1~case~%s~%s~%s~1~%s~late~Mooncloth"):format("z9case1", a.name, b.name, B36(ITEM), B36(10000)), nil, true, true)
	w:Run(0)
	eq(K.Rec(w, v, "z9case1"), nil)
	NoErrors(w)
end)

test("1.2 craft requests: Enter in the requests' dialogs answers as their first button (Forever's popup has no dialog.button1)", function()
	local w = World.New()
	local a, b = Cast(w)
	local r = DirectDeal(w, a, b)
	local rb = K.Rec(w, b, r.id)
	w:As(b, function()
		-- The game's dialog as Forever builds it: its buttons in a container, its box its child.
		local dialog = { ButtonContainer = { Buttons = {} }, hidden = false }
		function dialog:GetButton1() return self.ButtonContainer.Buttons[1] end
		function dialog:Hide() self.hidden = true end
		local box = { GetText = function() return "the buyer stopped answering" end, GetParent = function() return dialog end }
		dialog.EditBox = box
		b.popups.OLYMPUS_CRAFT_DISPUTE.EditBoxOnEnterPressed(box, rb)
		eq(dialog.hidden, true, "answered, then closed")
	end)
	eq(rb.settlement.dispute and rb.settlement.dispute.reason, "the buyer stopped answering")
	NoErrors(w)
end)

test("1.2 craft requests: a crafter who agreed to his own offer cannot change it under the requester's yes", function()
	local w = World.New()
	local a, b = Cast(w)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, {}, { rail = "direct", payment = "trade" })); w:Run(0)
	assert(b.Craft.ConfirmTerms(r.id)); w:Run(0)
	local ok, why = b.Craft.ProposeTerms(r.id, "finished", 20000, 0, {}, { rail = "direct", payment = "trade" })
	eq(ok, false); eq(why, "agreed")
	assert(a.Craft.ConfirmTerms(r.id)); w:Run(0)
	eq(r.state, "terms"); eq(K.Rec(w, b, r.id).state, "terms")
	eq(r.terms.total, 10000); eq(K.Rec(w, b, r.id).terms.total, 10000)
	NoErrors(w)
end)

test("1.2 craft requests: a buyer who cancelled while the goods were in the mail still answers for them: the dispute reaches his record, and its ruling restricts him", function()
	local w = World.New()
	local a, b = Cast(w)
	local k = K.Role(w, "councillor")
	local r = DirectDeal(w, a, b, 1)
	-- The crafter mails the goods (his client sees them go); the buyer has not opened his mail.
	b.bags[ITEM] = 1
	K.MailItems(w, b, a, { { id = ITEM, count = 1 } }, "Olympus craft " .. r.id)
	local rb = K.Rec(w, b, r.id)
	assert(#(rb.evidence or {}) > 0, "the crafter's client saw the goods go")
	eq(a.Craft.Cancel(r.id, "found one elsewhere"), true, "the buyer's client saw nothing yet"); w:Run(0)
	eq(r.state, "cancelled")
	eq(rb.settlement.state, "disputed", "for the crafter it is a dispute")
	eq(r.settlement.dispute and r.settlement.dispute.state, "open", "and the buyer's cancelled record holds it")
	eq(b.Craft.Escalate(r.id, k.name), true); w:Run(0)
	eq(r.settlement.dispute.reviewer, k.name)
	local rk = K.Rec(w, k, r.id)
	w.clock = rk.settlement.dispute.cureUntil
	eq(k.Craft.ReviewDispute(r.id, "debt", "kept the goods", a.name), true); w:Run(0)
	eq(r.settlement.dispute.decision, "debt")
	w.clock = r.settlement.dispute.debtDue
	eq(a.Craft.PrivilegeStatus(a.name).canRequest, false, "restricted on his own client")
	NoErrors(w)
end)

test("1.2 craft requests: a flood of contracts made and cancelled cannot grow a keeper's records without end; an open one or one still owing never goes", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	local cap
	w:As(t, function()
		local R = t.ns.CraftRequests
		cap = R.BOARD_MAX + R.HISTORY_MAX
		local records = t.ns.rdb.craftRequests.records
		-- (Fixture: closed custodies as a flood of cancelled contracts leaves them.)
		for i = 1, cap + 20 do
			local id = "zf" .. i
			records[id] = { id = id, requester = a.name, crafter = b.name, state = "cancelled", created = w.clock - 5000 + i, updated = w.clock - 5000 + i,
				settlement = { rail = "guild", custodian = t.name, state = "cancelled", gross = 10000 } }
		end
		records.zfowed = { id = "zfowed", requester = a.name, crafter = b.name, state = "cancelled", created = w.clock - 9000, updated = w.clock - 9000,
			settlement = { rail = "guild", custodian = t.name, state = "cancelled", gross = 10000, extraCopper = 500 } }
		R.Prune()
		local n = 0
		for _ in pairs(records) do n = n + 1 end
		eq(n, cap, "bounded")
		assert(records[r.id], "the open contract stays")
		assert(records.zfowed, "the closed one that still owes the buyer stays")
		eq(records.zf1, nil, "the oldest closed ones went first")
	end)
	NoErrors(w)
end)

print("CraftRequests: the review's third pass (cash on delivery, cancels and disputes the custodian holds, one trade among several deals)")

local function Audited(rec, kind)
	for _, e in ipairs(rec.settlement and rec.settlement.audit or {}) do if e.kind == kind then return true end end
	return false
end

test("1.2 craft requests (mediated): a cash-on-delivery mail never moves a custody: the crafter's goods the custodian paid for on taking them, or a forward the buyer would pay for again", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	local st = rt.settlement
	K.Trade(w, a, t, { aGives = 10000 })
	eq(st.state, "funds_reserved")
	-- The crafter mails the goods asking 94 g on delivery; the custodian takes them (the game's own
	-- confirmation, then TakeInboxItem). Counted, the payout would pay the crafter a second time.
	local m = K.MailItems(w, b, t, { { id = ITEM, count = 1 } }, "Olympus craft " .. r.id, 0, 9400)
	K.TakeItem(w, t, m, 1)
	eq(st.state, "funds_reserved", "goods taken cash on delivery are no part of the deal")
	eq(st.itemQuantity or 0, 0)
	assert(Audited(rt, "cod-ignored") and Printed(t, "Olympus craft " .. r.id), "the custodian is told")
	eq(t.Craft.PrepareCustodianForward(r.id, 30), false)
	-- The same goods by trade: now they count, and the forward is prepared.
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	eq(st.state, "custodian_received")
	assert(t.Craft.PrepareCustodianForward(r.id, 30))
	-- Mailed to the buyer cash on delivery: not the forward (he paid once already).
	K.MailItems(w, t, a, { { id = ITEM, count = 1 } }, "Olympus craft " .. r.id, 0, 5000)
	eq(st.state, "outbound_prepared", "a forward the buyer must pay for again is no forward")
	w:Run(1)
	K.MailItems(w, t, a, { { id = ITEM, count = 1 } }, "Olympus craft " .. r.id)
	eq(st.state, "outbound_sent")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): after the custodian took the contract a party's cancel (a modified client's) moves no copy; his word still does", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	local rb = K.Rec(w, b, r.id)
	eq(rb.settlement.state, "funds_reserved")
	-- The buyer's client tells the crafter the deal is off, though the custodian holds his gold.
	a.Comm.Whisper(b.name, ("CR~1~%s~900~cancel~bye"):format(r.id), nil, true, true)
	w:Run(0)
	eq(rb.state ~= "cancelled", true, "only the custodian ends a deal he holds")
	eq(rb.settlement.state, "funds_reserved")
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	eq(rb.settlement.state, "custodian_received", "the crafter's copy still follows him")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a deal the custodian never took ends by either party's cancel; an invite he holds for it goes, so a late one takes nothing", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	-- The custodian is away while the terms are agreed: neither invite reaches him.
	w:Logout(t)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, {}, { rail = "guild", payment = "trade", custodian = t.name, postage = 30 }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r.id)); assert(b.Craft.ConfirmTerms(r.id)); w:Run(0)
	eq(r.settlement.contractAt, nil)
	-- He is back, and the buyer's copy asks again: his invite waits there for the crafter's.
	K.Relog(w, t); w:Run(10)
	HearsKeeper(a, t)
	w:As(a, function() a.Craft.Tick() end); w:Run(0)
	eq(K.Rec(w, t, r.id) and K.Rec(w, t, r.id).settlement, nil, "one party's invite takes nothing")
	-- (The crafter's invite names the same contract word for word: one guild, the same terms.)
	local words = K.Words(w, "CK", a, t)
	local late = words[#words].msg
	assert(late:find("~invite~", 1, true), late)
	-- The buyer cancels: nothing is held anywhere, so the deal ends on both copies at once.
	eq(a.Craft.Cancel(r.id, "nobody took it"), true); w:Run(0)
	eq(r.state, "cancelled"); eq(r.settlement.state, "cancelled")
	local rb = K.Rec(w, b, r.id)
	eq(rb.state, "cancelled"); eq(rb.settlement.state, "cancelled")
	-- The crafter's invite from before reaches the custodian late: no contract is made of it.
	b.Comm.Whisper(t.name, (late:gsub("^(CK~1~[^~]+~)%d+", "%1950")), nil, true, true)
	w:Run(0)
	eq(K.Rec(w, t, r.id) and K.Rec(w, t, r.id).settlement, nil, "the buyer's cancel took his invite away")
	-- And the cancelled copies ask him nothing more.
	local asked = #K.Words(w, "CK", a, t)
	w.clock = w.clock + 3600
	w:As(a, function() a.Craft.Tick() end); w:Run(0)
	eq(#K.Words(w, "CK", a, t), asked)
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a dispute the custodian refuses leaves no copy stuck: it hears where the deal stands and follows", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	ReadyToSettle(w, a, b, t, r)
	assert(t.Craft.ReleaseSettlement(r.id)); w:Run(0)
	eq(rt.settlement.state, "payout_pending")
	-- (As a buyer's copy that was offline when the payout was instructed: it never heard it.)
	r.settlement.state = "ready_to_settle"
	eq(a.Craft.OpenDispute(r.id, "second thoughts", ""), true); w:Run(0)
	eq(rt.settlement.state, "payout_pending"); eq(rt.settlement.dispute, nil, "refused: the payout is under way")
	eq(r.settlement.state, "payout_pending", "the buyer's copy hears where the deal stands and follows")
	eq(r.settlement.dispute.state, "lapsed")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): only the custodian's word opens a dispute on the other party's copy; the other party's alone leaves it on his way", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	-- The buyer's client tells only the crafter of a dispute. The crafter's copy keeps following
	-- the custodian, who holds no dispute.
	local r, rt = MediatedDeal(w, a, b, t)
	K.Trade(w, a, t, { aGives = 10000 })
	local rb = K.Rec(w, b, r.id)
	a.Comm.Whisper(b.name, ("CR~1~%s~900~dispute~a lie~"):format(r.id), nil, true, true)
	w:Run(0)
	eq(rb.settlement.state, "funds_reserved"); eq(rb.settlement.dispute, nil)
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	eq(rb.settlement.state, "custodian_received")
	-- The crafter's own dispute, taken by the custodian: the buyer's copy holds it from his word.
	assert(b.Craft.OpenDispute(r.id, "the buyer asks for more", "")); w:Run(0)
	eq(rt.settlement.state, "disputed")
	eq(r.settlement.state, "disputed"); eq(r.settlement.dispute.reviewer, t.name)
	eq(r.settlement.dispute.openedBy, b.name)
	w.clock = rt.settlement.dispute.cureUntil
	assert(t.Craft.ReviewDispute(r.id, "resume", "go on", nil)); w:Run(0)
	eq(r.settlement.dispute.decision, "resume"); eq(rb.settlement.dispute.decision, "resume")
	eq(r.settlement.state, "custodian_received"); eq(rb.settlement.state, "custodian_received")
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a custodian of two deals with the same players ties each trade to the one it fits; a buyer's gold that fits none is his to have back", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r1, rt1 = MediatedDeal(w, a, b, t)
	w:Run(61)
	local r2, rt2 = MediatedDeal(w, a, b, t)
	-- The buyer pays one total by trade: the older deal's, once.
	K.Trade(w, a, t, { aGives = 10000 })
	eq(rt1.settlement.state, "funds_reserved"); eq(rt2.settlement.state, "awaiting_funds")
	eq(r1.settlement.state, "funds_reserved", "the buyer hears which")
	-- Then the second total: the other deal's.
	K.Trade(w, a, t, { aGives = 10000 })
	eq(rt2.settlement.state, "funds_reserved"); eq(rt1.settlement.extraCopper, nil)
	-- The crafter's goods, one trade each: the first fills the older deal, the second the other.
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	eq(rt1.settlement.state, "custodian_received"); eq(rt2.settlement.itemQuantity, nil)
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	eq(rt2.settlement.state, "custodian_received")
	-- An amount neither deal takes: the buyer's, shown to the custodian to give back.
	K.Trade(w, a, t, { aGives = 777 })
	eq((rt1.settlement.extraCopper or 0) + (rt2.settlement.extraCopper or 0), 777)
	NoErrors(w)
end)

test("1.2 craft requests (mediated): a debt ruled with none of the buyer's gold held ends the custody, the crafter's goods owed back; the debt stays on the ladder", function()
	local w = World.New()
	local a, b, t = Mediated(w)
	local r, rt = MediatedDeal(w, a, b, t)
	-- The crafter's goods reach the custodian; the buyer never pays.
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	eq(rt.settlement.state, "awaiting_funds"); eq(rt.settlement.itemQuantity, 1)
	assert(b.Craft.OpenDispute(r.id, "the buyer never paid", "")); w:Run(0)
	eq(r.settlement.state, "disputed", "the buyer's copy holds the dispute the custodian took")
	w.clock = rt.settlement.dispute.cureUntil
	eq(t.Craft.ReviewDispute(r.id, "debt", "ordered and never paid", a.name), true); w:Run(0)
	eq(rt.state, "cancelled"); eq(rt.settlement.state, "cancelled", "nothing would ever move it again")
	eq(rt.settlement.returnItems, 1, "the crafter's goods go back to him")
	eq(r.state, "cancelled"); eq(K.Rec(w, b, r.id).state, "cancelled")
	eq(r.settlement.dispute.decision, "debt")
	local owedText = t.ns.L.CRAFT_RETURN_LINE:match("^(.-)%%")
	t.Craft.SetPage("duty"); t.Craft.Open(r.id)
	assert(Find(t.Craft.BoardLines(), owedText), "his duty page shows the goods to return")
	-- The debt restricts the buyer after its own window, and a closed deal asks nobody anything.
	w.clock = r.settlement.dispute.debtDue
	eq(a.Craft.PrivilegeStatus(a.name).canRequest, false)
	HearsKeeper(a, t)
	local asked = #K.Words(w, "CK", a, t)
	w.clock = w.clock + 3600
	w:As(a, function() a.Craft.Tick() end); w:Run(0)
	eq(#K.Words(w, "CK", a, t), asked)
	-- Months later the uncured debt's record is still the ladder's.
	w.clock = w.clock + 91 * 86400
	a.Craft.Prune()
	assert(K.Rec(w, a, r.id), "a debt still due is never pruned with its deal")
	NoErrors(w)
end)
