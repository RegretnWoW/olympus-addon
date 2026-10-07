local ADDON, ns = ...
local L = ns.L

-- 1.2: crafting requests (who can make an item?). A request is public only while it is a board
-- card, and the card says nothing of what follows: not who took it, not the terms, not the end.
-- A claim and every later word travel as logged addon whispers between the requester and the one
-- accepted crafter, and, on the guild-mediated rail, the named treasury keeper who holds the goods
-- and the gold (the custodian), or the reviewer a party asked to judge a dispute.
--
--   CQ~2~...  the board card: one logged CHANNEL message, the requester's alone
--   CR~1~...  a claim and the two parties' words (WHISPER, logged)
--   CJ~1~...  a line of the private request chat (WHISPER, logged)
--   CK~1~...  the mediated rail and the human review: parties, custodian, reviewer (WHISPER, logged)
--
-- Nothing here clicks Trade, Send or Take, fills a window, or pays on its own. Trade and mail
-- observations annotate the record. On the direct rail completion is always the requester's
-- explicit confirmation of the delivery the crafter recorded; on the mediated rail custody follows
-- the custodian's own observations of what reached him. Whatever has Olympus hold gold or owe it
-- on someone's behalf (the mediated rail, the Wallet adapter, the custodian's own payout and
-- refund debts) sits behind the switches of the Arena's live gold (Requests.GoldGate): off where
-- saved data does not survive, as the Wallet is.
--
-- The guild's 6% of a direct sale (the owner's answer) is the seller's own debt to the guild, in
-- the game's gold (never the Arena's chips), whatever the Arena's switches say: Olympus holds none
-- of it, it only records it. The seller owes it by a deadline and is warned once it is late (no
-- new claims until it is paid); both parties' clients tell the fee desk (the Treasurer's
-- characters, where the fee mail goes) of the sale, so the seller's own client alone cannot hide
-- it; the desk sees the fee mail land in its treasury book. A sale the buyer never confirms owes
-- it all the same, CONFIRM_WAIT on (the delivery the seller recorded, or a trade both addons saw),
-- unless a party disputed it. The Treasurer's characters and the King's, the High Council and the
-- author (the real ones, never a preview of anyone's view) read the debtors' ranking and every fee
-- owed, for the collection (the Treasurer's and the King's reminders) and the Watch's own ladder;
-- nothing here removes anyone. Only a fee the seller's own word confirms (or the desk confirmed by
-- hand) is ranked: the buyer's word alone, or a buyer's figure above the seller's, waits apart for
-- a human, the higher figure kept as the fee.
--   CK~1~<id>~<seq>~fee~<s|b>~<requester>~<crafter>~<gross>~<item>~<qty>~<crafter's guild>
--                                     a party's word of a direct sale, to the desk
--   CK~1~<id>~<seq>~feestate~<fee>~<paid>~<due>~<due|paid|waived>   the desk's answer to it
--   CK~1~fees~<seq>~debtors           a reader's ask (ReadsDebtors); the desk answers, paced:
--   CK~1~<id>~<seq>~debt~<crafter>~<requester>~<gross>~<fee>~<paid>~<due>~<by>~<item>~<qty>~<guild>
--                                     by: s, b or sb (whose word), then c (the desk confirmed it by
--                                     hand) and d (the buyer's figure is above the seller's)
--   CK~1~fees~<seq>~debtend~<sent>~<open>
--   CK~1~fees~<seq>~debtwait~<seconds>   or, asked too soon, when to ask again
--   CK~1~<id>~<seq>~feeremind~<owed>~<due>   the desk's or the King's reminder to a debtor
-- The guarantee fund is postponed (the owner's answer): there is no insurance, claim or guarantee payout here.

local Requests = {}
ns.CraftRequests = Requests

-- 1.1.6: a sanctioned player (WatchChat.Barred "crafting": a moderator's timeout, a hold while his
-- case is decided, a net-off word) uses no Crafting tab while it lasts: his client publishes no
-- card, claims nothing and sends no deal's word; the others drop his cards, claims, words and
-- chat. The mediated rail's custody, fees, debts and reviews (CK) go on: what is held for anyone
-- or owed is never stuck by it.
function Requests.Barred(name)
	local WC = ns.WatchChat
	return type(WC) == "table" and not WC.missing and type(WC.Barred) == "function" and WC.Barred("crafting", name) or nil
end

Requests.BOARD_MAX = 120
Requests.HISTORY_MAX = 100
Requests.AUDIT_MAX = 80
Requests.CHAT_MAX = 100
Requests.DETAILS_MAX = 180 -- what the composer keeps; the card carries what fits its one message
Requests.ITEM_NAME_MAX = 60
Requests.GUILD_MAX = 72
Requests.QUANTITY_MAX = 1000
Requests.PRICE_MAX = 2147483647
Requests.MESSAGE_MAX = 255
Requests.REQUEST_TTL = 72 * 60 * 60
Requests.RETAIN = 90 * 86400
Requests.SEEN_KEEP = 60 * 60          -- someone else's taken or closed card, before it goes
Requests.PUBLISH_GAP = 20 * 60
Requests.PUBLISH_PER_10MIN = 8
Requests.CARDS_PER_10MIN = 12         -- cards heard from one requester
Requests.OPEN_PER_REQUESTER = 10
Requests.ACTION_PER_MIN = 12
Requests.CHAT_PER_MIN = 8
Requests.CHAT_GAP = 1.5
Requests.CLAIM_WAIT = 120
Requests.QUOTE_FRESH = 2 * 60 * 60
Requests.SAMPLES_MAX = 100
Requests.QUOTE_MIN_SAMPLES = 3
Requests.GUILD_DISCOUNT_BP = 2000
Requests.GUILD_FEE_BP = 600
Requests.QUANTITY_STEP = 5
Requests.QUANTITY_STEP_BP = 100
Requests.QUANTITY_DISCOUNT_CAP_BP = 1000
Requests.CURE_WINDOW = 72 * 60 * 60
Requests.APPEAL_WINDOW = 72 * 60 * 60
Requests.SETTLEMENT_TTL = 14 * 86400
Requests.EVIDENCE_MAX = 40
Requests.INVITE_TTL = 60 * 60
Requests.INVITES_PER_SENDER = 10
Requests.CASES_MAX = 40               -- open disputes put to one reviewer
Requests.CUSTODIES_PER_PARTY = 5      -- open contracts one custodian holds naming the same player
Requests.ASK_GAP = 30 * 60            -- a party's copy of a quiet mediated deal asks its custodian
Requests.TAKE_WAIT = 30
Requests.MAIL_DAYS = 30 * 86400        -- what a mail keeps: gold on its way may land this late
Requests.FEE_DUE = 72 * 60 * 60       -- the seller's deadline for the guild's 6% of a direct sale
Requests.CONFIRM_WAIT = 72 * 60 * 60  -- a sale the buyer neither confirmed nor disputed: its fee is owed after this all the same
Requests.FEE_WARN_GAP = 86400         -- an overdue fee's warning, once a session and a day
Requests.FEES_MAX = 1000              -- fees on the desk's ledger at most
Requests.FEES_BUYER_ONLY = 20         -- open fees on the buyer's word alone, per buyer, at most
Requests.FEES_PER_SELLER = 50         -- open fees on a seller's own word, per seller, at most
Requests.FEES_KEEP = 30 * 86400       -- a paid or waived fee stays on the ledger this long
Requests.DEBTS_ANSWER_MAX = 40        -- fees one answer to the King names at most
Requests.DEBTS_ASK_GAP = 300          -- the King asks the desk, and is answered, this often at most
Requests.DEBTS_RETRY = 150            -- an ask the desk never answered may go again this soon (an answer takes 2 min at most)
Requests.DEBTS_PACE = 1.5             -- one word of that answer each 1.5 seconds...
Requests.DEBTS_QUEUE = 10             -- ...while the desk's send queue holds this many at most
Requests.REMIND_GAP = 86400           -- one reminder to one debtor a day at most

local STATES = { draft = 0, open = 1, accepted = 2, terms = 3, in_progress = 4,
	delivered = 5, completed = 6, cancelled = 7, expired = 8 }
Requests.STATES = STATES
-- The card's states. Everything after a claim is private, so a taken card stays "a" whatever
-- becomes of the deal; "x" and "e" close a card nobody took.
local CARD_STATE = { o = "open", a = "accepted", x = "cancelled", e = "expired" }
local CARD_RANK = { open = 0, accepted = 1, cancelled = 2, expired = 2 }
local PAY_CODE = { trade = "t", mail = "m", wallet = "w" }
local CODE_PAY = { t = "trade", m = "mail", w = "wallet" }
local function WalletShown() return ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet() == true end
local SUBJECT = "Olympus craft "
local FEE_SUBJECT = "Olympus craft fee "

local composer
local openedId
local pageMode = "board"
local nextId = math.random and math.random(0, 46655) or 0
local publishTimes, cardBuckets, actionBuckets, chatBuckets, alertTimes = {}, {}, {}, {}, {}
local priceSamples, adapters, escrowAdapters = {}, {}, {}
local itemsAsked = {}    -- items the composer asked the game's cache for, this session
local moneySubscribed = false
local exchangeInstalled, exactTrade, exactMailOut = false, nil, nil
local exactInbox = {}
local asked = {}         -- the mediated deals whose custodian this session already asked (a login's ask)
local PublicAdvance, DisputeSettlement, InstallMoneyWatch, InstallExchangeHooks, FinishRequest, Owing, LateGold
local QueueFeeReport, SendFeeReport, FeeOpen
-- The guild fees' section: its session state and the functions the rest of the file calls.
--   view: a reader's copy of the desk's last answer (the King's, a councillor's, the author's);
--   seq: the fee words' sequence; warned: the overdue fees warned of this session; reminded,
--   answered: when each debtor was reminded and each reader answered; jobs, pumping: the desk's
--   answers going out, paced.
local Fee = { view = { entries = {} }, seq = 0, warned = {}, reminded = {}, answered = {}, jobs = {}, pumping = false }

local function Now() return ns.Now() end
local function Full(name) return type(name) == "string" and name ~= "" and ns.FullName(ns.Normal(name)) or nil end
local function Lower(name) local n = Full(name) return n and n:lower() or nil end
local function Same(a, b) return Lower(a) ~= nil and Lower(a) == Lower(b) end
local function Clamp(v, lo, hi)
	v = tonumber(v)
	if not v or v ~= v then return nil end
	v = math.floor(v)
	if v < lo or v > hi then return nil end
	return v
end
local function Clean(s, max)
	s = ns.Codec.Plain(tostring(s or "")):gsub("[~|%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, max)
end
-- Restricted UI events and APIs may hand addons a secret value: never compared or cut.
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function B36(n) return ns.Codec.Base36(math.max(0, math.floor(tonumber(n) or 0))) or "0" end
local function UnB36(s, lo, hi)
	if type(s) ~= "string" or s == "" or #s > 8 or not s:find("^[0-9a-z]+$") then return nil end
	return Clamp(tonumber(s, 36), lo, hi)
end
local function Recent(list, seconds, now)
	now = now or Now()
	for i = #list, 1, -1 do if now - list[i] >= seconds then table.remove(list, i) end end
	return #list
end
local function Bucket(t, key, seconds, limit, now)
	now = now or Now()
	local list = t[key] or {}
	t[key] = list
	if Recent(list, seconds, now) >= limit then return false end
	list[#list + 1] = now
	return true
end
local function Copy(t)
	local out = {}
	for k, v in pairs(type(t) == "table" and t or {}) do out[k] = v end
	return out
end
local function Grey(s) return "|cff9d9d9d" .. tostring(s) .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s) .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s) .. "|r" end
local function Red(s) return "|cffff6060" .. tostring(s) .. "|r" end
local function Coins(copper)
	local T = ns.Treasury
	return T and T.Coins and T.Coins(copper) or tostring(copper) .. "c"
end
-- A player's words come with the logged API where the client has it, as the chat rooms' do. A copy
-- that arrived unlogged (a modified client) changes nothing.
local function Unlogged()
	return C_ChatInfo ~= nil and C_ChatInfo.SendAddonMessageLogged ~= nil and type(ns.Comm.DeliveredLogged) == "function"
		and not ns.Comm.DeliveredLogged()
end

local function NewStore() return { records = {}, invites = {} } end
local transient = NewStore()
local function Store()
	if not ns.rdb then return transient end
	if type(ns.rdb.craftRequests) ~= "table" then ns.rdb.craftRequests = {} end
	local s = ns.rdb.craftRequests
	if type(s.records) ~= "table" then s.records = {} end
	if type(s.invites) ~= "table" then s.invites = {} end
	return s
end

local function Audit(r, kind, actor, detail)
	if type(r) ~= "table" then return end
	r.audit = type(r.audit) == "table" and r.audit or {}
	r.audit[#r.audit + 1] = { t = Now(), kind = kind, actor = Full(actor) or actor, detail = Clean(detail, 120) }
	while #r.audit > Requests.AUDIT_MAX do table.remove(r.audit, 1) end
end

local function Changed()
	ns.Fire("CRAFT_REQUESTS_CHANGED")
	ns.Fire("REALM_PAGE_CHANGED", "crafters")
end

local function Mine(r)
	return type(r) == "table" and (Same(r.requester, ns.me) or Same(r.crafter, ns.me))
end
local function Party(r, name)
	return type(r) == "table" and name ~= nil and (Same(r.requester, name) or Same(r.crafter, name))
end
local function Other(r)
	if Same(r.requester, ns.me) then return r.crafter end
	if Same(r.crafter, ns.me) then return r.requester end
end
-- This client holds the goods or the gold of a mediated request (its custodian).
local function Custody(r)
	local s = type(r) == "table" and r.settlement
	return s ~= nil and s ~= false and s.rail == "guild" and Same(s.custodian, ns.me) and not Mine(r)
end
-- This client is the reviewer a dispute was put to (never a party of it).
local function Reviewing(r)
	local d = type(r) == "table" and r.settlement and r.settlement.dispute
	return d ~= nil and d ~= false and Same(d.reviewer, ns.me) and not Mine(r)
end
local function Involved(r)
	return Mine(r) or Custody(r) or Reviewing(r) or (type(r) == "table" and r.claimNonces ~= nil and r.state == "open")
end
local function Terminal(r)
	return r and (r.state == "completed" or r.state == "cancelled" or r.state == "expired")
end
local function Active(r) return r and not Terminal(r) and STATES[r.state] and STATES[r.state] >= STATES.accepted end

function Requests.Get(id) return type(id) == "string" and Store().records[id] or nil end

-- A reviewed debt not cured yet: its record is the ladder's, however old the deal is.
local function DebtDue(r)
	local d = type(r) == "table" and type(r.settlement) == "table" and r.settlement.dispute
	return type(d) == "table" and d.state == "final" and d.decision == "debt" and d.debtState == "due"
end

-- A completed direct sale whose guild fee this client still owes, still has to tell the desk of,
-- or mailed while that mail may still come back (its days there and back).
local function FeeHeld(r)
	local s = type(r) == "table" and r.settlement
	if type(s) ~= "table" or s.rail ~= "direct" then return false end
	return FeeOpen(s) or (s.feeState == "mailed" and Now() - (tonumber(s.feeMailedAt) or 0) <= 2 * Requests.MAIL_DAYS)
		or (type(s.feeReport) == "table" and not s.feeReport.acked) or false
end

local function Prune()
	local s, now = Store(), Now()
	local list = {}
	for id, r in pairs(s.records) do
		if type(r) ~= "table" then
			s.records[id] = nil
		else
			if r.state == "open" and now >= (tonumber(r.expires) or 0) then
				r.state, r.updated = "expired", now
				Audit(r, "expired", r.requester)
			end
			if r.claimPending and now - r.claimPending >= Requests.CLAIM_WAIT then r.claimPending = nil end
			local age = now - (tonumber(r.updated) or tonumber(r.created) or now)
			if (not Involved(r) and r.state ~= "open" and age > Requests.SEEN_KEEP) or (Terminal(r) and age > Requests.RETAIN and not DebtDue(r) and not FeeHeld(r)) then
				s.records[id] = nil
			else
				list[#list + 1] = r
			end
		end
	end
	local cap = Requests.BOARD_MAX + Requests.HISTORY_MAX
	if #list > cap then
		-- Other people's cards make room first. A record this client is a party, the custodian or
		-- the reviewer of never goes for a flood of cards; only once nothing else is left do its
		-- closed ones (the oldest first, none that owes something or still may, nor a debt still
		-- due), so a flood of contracts made and cancelled cannot grow a keeper's saved data
		-- without end. An open one never goes.
		local spare, closed = {}, {}
		for _, r in ipairs(list) do
			if not Involved(r) then spare[#spare + 1] = r
			elseif Terminal(r) and not Owing(r) and not LateGold(r) and not DebtDue(r) and not FeeHeld(r) then closed[#closed + 1] = r end
		end
		table.sort(spare, function(a, b)
			if (a.state == "open") ~= (b.state == "open") then return b.state == "open" end
			return (a.updated or a.created or 0) < (b.updated or b.created or 0)
		end)
		table.sort(closed, function(a, b) return (a.updated or a.created or 0) < (b.updated or b.created or 0) end)
		local over = #list - cap
		for i = 1, math.min(#spare, over) do s.records[spare[i].id] = nil end
		over = over - math.min(#spare, over)
		for i = 1, math.min(#closed, over) do s.records[closed[i].id] = nil end
	end
	for id, p in pairs(s.invites) do
		if type(p) ~= "table" or now - (tonumber(p.at) or 0) > Requests.INVITE_TTL then s.invites[id] = nil end
	end
end
Requests.Prune = Prune

--------------------------------------------------------------------------
-- Known item search: only outputs actually read from consented professions.
--------------------------------------------------------------------------

-- Forever's UI documents C_Item.GetItemInfo; the global is only a fallback for older clients.
local function ItemInfo(id)
	local fn = type(C_Item) == "table" and C_Item.GetItemInfo or GetItemInfo
	if not id or type(fn) ~= "function" then return nil end
	local ok, name, link, _, _, _, itemType, subType, _, _, icon, sell = pcall(fn, id)
	if not ok or type(name) ~= "string" or Secret(name) or name == "" then return nil end
	return { id = id, name = Clean(name, Requests.ITEM_NAME_MAX), link = link, itemType = itemType, subType = subType,
		icon = icon, vendor = tonumber(sell) or 0 }
end

-- Materials a gatherer brings rather than a crafter makes, by the gathering profession's id
-- (Herbalism, Mining, Skinning): the classic items' ids. Each client names them in its own language
-- once its item cache has them; until then the English name here stands in, marked as unverified.
Requests.GATHERED = {
	["182"] = { [2447] = "Peacebloom", [765] = "Silverleaf", [2449] = "Earthroot", [785] = "Mageroyal", [2450] = "Briarthorn",
		[2452] = "Swiftthistle", [3820] = "Stranglekelp", [2453] = "Bruiseweed", [3355] = "Wild Steelbloom", [3369] = "Grave Moss",
		[3356] = "Kingsblood", [3357] = "Liferoot", [3818] = "Fadeleaf", [3821] = "Goldthorn", [3358] = "Khadgar's Whisker",
		[3819] = "Wintersbite", [4625] = "Firebloom", [8831] = "Purple Lotus", [8836] = "Arthas' Tears", [8838] = "Sungrass",
		[8839] = "Blindweed", [8845] = "Ghost Mushroom", [8846] = "Gromsblood", [13464] = "Golden Sansam", [13463] = "Dreamfoil",
		[13465] = "Mountain Silversage", [13466] = "Plaguebloom", [13467] = "Icecap", [13468] = "Black Lotus" },
	["186"] = { [2770] = "Copper Ore", [2771] = "Tin Ore", [2772] = "Iron Ore", [2775] = "Silver Ore", [2776] = "Gold Ore",
		[3858] = "Mithril Ore", [7911] = "Truesilver Ore", [10620] = "Thorium Ore", [11370] = "Dark Iron Ore", [2835] = "Rough Stone",
		[2836] = "Coarse Stone", [2838] = "Heavy Stone", [7912] = "Solid Stone", [12365] = "Dense Stone" },
	["393"] = { [2934] = "Ruined Leather Scraps", [2318] = "Light Leather", [2319] = "Medium Leather", [4234] = "Heavy Leather",
		[4304] = "Thick Leather", [8170] = "Rugged Leather", [783] = "Light Hide", [4232] = "Medium Hide", [4235] = "Heavy Hide",
		[8169] = "Thick Hide", [8171] = "Rugged Hide" },
}

-- What the composer offers: the outputs of our own listed professions, of the recipe lists other
-- crafters on the board sent us (a click on "Show his recipes") and of the answers to our own "who
-- can make it?", each with the professions that make it; and the gathered materials above. An item
-- the cache does not hold yet is asked of the game once a session (it names itself on a later draw).
function Requests.KnownItems()
	local out, byId = {}, {}
	local C = ns.Crafters
	if not C then return out end
	local function Add(id, kind, canonical, label, fallback)
		id = Clamp(id, 1, 999999999)
		if not id then return end
		local item = byId[id]
		if not item then
			item = ItemInfo(id)
			if not item then
				item = { id = id, name = Clean(fallback, Requests.ITEM_NAME_MAX), cacheMiss = true }
				if item.name == "" then item.name = L.CRAFTER_ITEM_N:format(id) end
				if not itemsAsked[id] and type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
					itemsAsked[id] = true
					pcall(C_Item.RequestLoadItemDataByID, id)
				end
			end
			item.kind, item.professions = kind, {}
			byId[id], out[#out + 1] = item, item
		end
		if kind == "gather" and not item.gatherKey then item.gatherKey = canonical end
		item.professions[canonical] = label
	end
	for key, p in pairs(C.Mine and C.Mine() or {}) do
		if C.Choices()[key] == true then
			local canonical = C.CanonicalProfessionKey(key, p.name)
			for _, recipe in ipairs(p.recipes or {}) do Add(recipe.i, "craft", canonical, C.ProfessionLabel(canonical, p.name), recipe.n) end
		end
	end
	for _, crafter in ipairs(C.Board and C.Board() or {}) do
		for _, p in ipairs(crafter.profs or {}) do
			local list = C.ListOf and C.ListOf(crafter.name, p.key)
			local canonical = C.CanonicalProfessionKey(p.key, p.name)
			for _, recipe in ipairs(list or {}) do Add(recipe.i, "craft", canonical, C.ProfessionLabel(canonical, p.name)) end
		end
	end
	local ask = C.MyAsk and C.MyAsk()
	for _, answer in pairs(ask and ask.answers or {}) do
		local canonical = C.CanonicalProfessionKey(nil, answer.prof)
		for _, recipe in ipairs(answer.recipes or {}) do Add(recipe.i, "craft", canonical, C.ProfessionLabel(canonical, answer.prof)) end
	end
	for key, items in pairs(Requests.GATHERED) do
		for id, name in pairs(items) do Add(id, "gather", key, C.ProfessionLabel(key, key), name) end
	end
	table.sort(out, function(a, b) return ns.Fold(a.name or "") < ns.Fold(b.name or "") end)
	return out
end

function Requests.SearchItems(query, filters)
	query, filters = ns.Fold(Clean(query, 80)), type(filters) == "table" and filters or {}
	local out = {}
	for _, item in ipairs(Requests.KnownItems()) do
		local prof = filters.profession
		local hasProf = not prof or prof == "all" or item.professions[prof] ~= nil
		if (query == "" or ns.Fold(item.name):find(query, 1, true)) and hasProf
			and (not filters.kind or filters.kind == "all" or filters.kind == item.kind)
			and (not filters.itemType or filters.itemType == item.itemType)
			and (not filters.subType or filters.subType == item.subType) then out[#out + 1] = item end
	end
	return out
end

-- A gathering profession of this character's own (Herbalism and Skinning open no trade skill
-- window, so the Crafters board never lists them): its skill line, as Forever's character pane reads
-- it (C_SkillInfo.GetSkillLineInfoByID, Blizzard_UIPanels_Game/Camelot). Read here, sent nowhere.
local function Gathers(key)
	local id = Clamp(key, 1, 999999)
	local S = C_SkillInfo
	if not id or not Requests.GATHERED[tostring(id)] or type(S) ~= "table" or type(S.GetSkillLineInfoByID) ~= "function" then return false end
	local ok, info = pcall(S.GetSkillLineInfoByID, id)
	if not ok or type(info) ~= "table" or Secret(info.rank) or Secret(info.isHeader) or info.isHeader then return false end
	return (tonumber(info.rank) or 0) > 0
end

function Requests.CanFulfill(r)
	if type(r) ~= "table" or r.state ~= "open" or Same(r.requester, ns.me) then return false end
	if r.kind == "g" and r.profession ~= "" and Gathers(r.profession) then return true end
	local C = ns.Crafters
	for key, p in pairs(C and C.Mine and C.Mine() or {}) do
		if C.Choices()[key] == true then
			local canonical = C.CanonicalProfessionKey(key, p.name)
			if r.kind == "g" and r.profession ~= "" and canonical == r.profession then return true end
			for _, recipe in ipairs(p.recipes or {}) do if r.itemID and recipe.i == r.itemID then return true end end
		end
	end
	return false
end

function Requests.All()
	Prune()
	local out = {}
	for _, r in pairs(Store().records) do out[#out + 1] = r end
	local fit = {}
	for _, r in ipairs(out) do fit[r] = Requests.CanFulfill(r) end
	table.sort(out, function(a, b)
		if fit[a] ~= fit[b] then return fit[a] end
		if Terminal(a) ~= Terminal(b) then return not Terminal(a) end
		if (a.updated or a.created or 0) ~= (b.updated or b.created or 0) then return (a.updated or a.created or 0) > (b.updated or b.created or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	return out
end

--------------------------------------------------------------------------
-- Market observations and deterministic quote/terms calculation.
--------------------------------------------------------------------------

-- One listing (or one add-on's summary) is one sample: read again, it replaces itself, so a price
-- seen twice never counts twice towards the quote's minimum.
function Requests.AddPriceSample(itemID, unit, source, at, quantity, key)
	itemID, unit = Clamp(itemID, 1, 999999999), Clamp(unit, 1, Requests.PRICE_MAX)
	if not itemID or not unit then return false end
	source = Clean(source, 40)
	local list = priceSamples[itemID] or {}
	priceSamples[itemID] = list
	local sample = { unit = unit, source = source, at = Clamp(at or Now(), 1, 9999999999) or Now(),
		quantity = Clamp(quantity or 1, 1, 100000) or 1, key = key ~= nil and Clean(key, 40) or nil }
	if sample.key then
		for i, old in ipairs(list) do
			if old.key == sample.key and old.source == source then list[i] = sample return true end
		end
	end
	list[#list + 1] = sample
	while #list > Requests.SAMPLES_MAX do table.remove(list, 1) end
	return true
end

function Requests.RegisterPriceAdapter(name, fn)
	name = Clean(name, 30)
	if name == "" or type(fn) ~= "function" then return false end
	adapters[name] = fn
	return true
end

local function AddResult(itemID, source, value)
	if type(value) == "number" then
		if not Secret(value) then Requests.AddPriceSample(itemID, value, source, nil, 1, "summary") end
		return
	end
	for _, one in ipairs(type(value) == "table" and value or {}) do
		if type(one) == "number" then
			if not Secret(one) then Requests.AddPriceSample(itemID, one, source, nil, 1, "summary") end
		elseif type(one) == "table" and not Secret(one.unit or one.price) then
			Requests.AddPriceSample(itemID, one.unit or one.price, source, one.at, one.quantity, one.key)
		end
	end
end

-- Forever's auction house (Blizzard_AuctionHouseUI, C_AuctionHouse): read only, and only while the
-- window shows a result set the player searched for. GetNum*SearchResults and the matching
-- Get*SearchResultInfo are the documented pair; each listing is one sample, by its auction ID.
local function BlizzardPrices(itemID)
	local A, frame = C_AuctionHouse, AuctionHouseFrame
	if type(A) ~= "table" or type(frame) ~= "table" or type(frame.IsShown) ~= "function" or not frame:IsShown() then return nil end
	local out = {}
	local function Keep(unit, quantity, auction)
		if Secret(unit) or Secret(quantity) or Secret(auction) then return end
		unit = Clamp(unit, 1, Requests.PRICE_MAX)
		if unit then out[#out + 1] = { unit = unit, quantity = Clamp(quantity or 1, 1, 100000) or 1, key = auction and ("ah" .. tostring(auction)) or nil } end
	end
	if type(A.GetNumCommoditySearchResults) == "function" and type(A.GetCommoditySearchResultInfo) == "function" then
		local ok, n = pcall(A.GetNumCommoditySearchResults, itemID)
		if ok and type(n) == "number" and not Secret(n) then
			for i = 1, math.min(n, 50) do
				local okRow, row = pcall(A.GetCommoditySearchResultInfo, itemID, i)
				if okRow and type(row) == "table" then Keep(row.unitPrice, row.quantity, row.auctionID) end
			end
		end
	end
	if #out == 0 and type(A.MakeItemKey) == "function" and type(A.GetNumItemSearchResults) == "function"
		and type(A.GetItemSearchResultInfo) == "function" then
		local okKey, key = pcall(A.MakeItemKey, itemID)
		if okKey and type(key) == "table" then
			local ok, n = pcall(A.GetNumItemSearchResults, key)
			if ok and type(n) == "number" and not Secret(n) then
				for i = 1, math.min(n, 50) do
					local okRow, row = pcall(A.GetItemSearchResultInfo, key, i)
					local buyout = okRow and type(row) == "table" and row.buyoutAmount or nil
					if buyout ~= nil and not Secret(buyout) and type(buyout) == "number" then
						local q = Clamp(row.quantity or 1, 1, 100000) or 1
						Keep(math.floor(buyout / q), q, row.auctionID)
					end
				end
			end
		end
	end
	return out
end
Requests.RegisterPriceAdapter("Blizzard AH", BlizzardPrices)

-- Other add-ons' summaries: one number each, one sample per add-on however often it is read.
Requests.RegisterPriceAdapter("Auctionator", function(itemID)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	local fn = api and api.GetAuctionPriceByItemID
	if type(fn) ~= "function" then return nil end
	local ok, price = pcall(fn, "Olympus", itemID)
	return ok and price or nil
end)
-- (Auctioneer's GetMarketValue reads an item link, not an id: the cache's link, or nothing.)
Requests.RegisterPriceAdapter("Auctioneer", function(itemID)
	local api = AucAdvanced and AucAdvanced.API
	local fn = api and api.GetMarketValue
	local info = ItemInfo(itemID)
	if type(fn) ~= "function" or not info or type(info.link) ~= "string" or Secret(info.link) then return nil end
	local ok, price = pcall(fn, info.link)
	return ok and price or nil
end)

function Requests.ObservePrices(itemID)
	itemID = Clamp(itemID, 1, 999999999)
	if not itemID then return 0 end
	local before = #(priceSamples[itemID] or {})
	for name, fn in pairs(adapters) do
		local ok, value = pcall(fn, itemID)
		if ok then AddResult(itemID, name, value) end
	end
	return #(priceSamples[itemID] or {}) - before
end

local function Median(values)
	local n = #values
	if n == 0 then return nil end
	if n % 2 == 1 then return values[(n + 1) / 2] end
	return (values[n / 2] + values[n / 2 + 1]) / 2
end

function Requests.Quote(itemID, now)
	itemID, now = Clamp(itemID, 1, 999999999), now or Now()
	if not itemID then return nil, "item" end
	local values, sources, newest = {}, {}, 0
	for _, sample in ipairs(priceSamples[itemID] or {}) do
		if now - sample.at >= 0 and now - sample.at <= Requests.QUOTE_FRESH then
			values[#values + 1], sources[sample.source ~= "" and sample.source or "unknown"] = sample.unit, true
			newest = math.max(newest, sample.at)
		end
	end
	if #values < Requests.QUOTE_MIN_SAMPLES then return nil, #values == 0 and "stale" or "samples" end
	table.sort(values)
	local median = Median(values)
	local reference, method = median, "median"
	if #values >= 5 then
		local trim = math.max(1, math.floor(#values * 0.1))
		local low, high, sum = values[trim + 1], values[#values - trim], 0
		for _, v in ipairs(values) do sum = sum + math.max(low, math.min(high, v)) end
		local winsor = sum / #values
		reference, method = (median + winsor) / 2, "median+winsorized mean"
	end
	reference = math.floor(reference + 0.5)
	local names = {}
	for source in pairs(sources) do names[#names + 1] = source end
	table.sort(names)
	local spread = median > 0 and (values[#values] - values[1]) / median or math.huge
	return { itemID = itemID, reference = reference, median = math.floor(median + 0.5), method = method,
		n = #values, source = table.concat(names, ", "), observedAt = newest, age = now - newest,
		confidence = #values >= 8 and spread <= 0.5 and "high" or "medium" }
end

local function Floors()
	if not ns.db then return {} end
	if type(ns.db.craftPriceFloors) ~= "table" then ns.db.craftPriceFloors = {} end
	return ns.db.craftPriceFloors
end
function Requests.SetFloor(itemID, copper, source)
	itemID, copper = Clamp(itemID, 1, 999999999), Clamp(copper, 0, Requests.PRICE_MAX)
	if not itemID or not copper then return false end
	Floors()[itemID] = copper > 0 and { copper = copper, source = Clean(source, 40), at = Now() } or nil
	return true
end
function Requests.Floor(itemID)
	local f = Floors()[tonumber(itemID)]
	return type(f) == "table" and f or nil
end

function Requests.SuggestTerms(r, quote)
	if type(r) ~= "table" then return nil, "request" end
	if r.materials == "buyer" then return nil, "manual_fee" end
	quote = quote or (r.quote and Copy(r.quote)) or (r.itemID and Requests.Quote(r.itemID))
	local now = Now()
	-- (A quote dated in the future is no fresher than one of now: it never stays fresh forever.)
	if not quote or not quote.observedAt or quote.observedAt > now + 300 or now - quote.observedAt > Requests.QUOTE_FRESH then return nil, "quote" end
	local qty = Clamp(r.quantity, 1, Requests.QUANTITY_MAX)
	if not qty then return nil, "quantity" end
	local extra = math.min(Requests.QUANTITY_DISCOUNT_CAP_BP, math.floor((qty - 1) / Requests.QUANTITY_STEP) * Requests.QUANTITY_STEP_BP)
	local discount = Requests.GUILD_DISCOUNT_BP + extra
	local floor = Requests.Floor(r.itemID)
	local floorCopper = floor and floor.copper or Clamp(r.floor, 0, Requests.PRICE_MAX) or 0
	local unit = math.floor(quote.reference * (10000 - discount) / 10000)
	if unit < floorCopper then unit = floorCopper end
	if unit * qty > Requests.PRICE_MAX then return nil, "price" end
	local total = unit * qty
	local fee = math.floor(total * Requests.GUILD_FEE_BP / 10000)
	return { version = 1, mode = "finished", quantity = qty, unit = unit, total = total,
		floor = floorCopper, floorSource = floor and floor.source or r.floorSource, reference = quote.reference,
		discountBP = discount, quantityDiscountBP = extra, quoteAt = quote.observedAt, source = quote.source,
		method = quote.method, confidence = quote.confidence, guildFeeBP = Requests.GUILD_FEE_BP,
		guildFee = fee, sellerNet = total - fee, rail = "direct", payment = "trade", agrees = {} }
end

--------------------------------------------------------------------------
-- The gold switches and the settlement contract. Gold and item clicks remain the player's. The
-- state machine records intent, guarded observations and explicit confirmations; it never equates
-- an API's presence with a completed transfer.
--------------------------------------------------------------------------

-- Nil when Olympus may hold or owe gold for a request, else why not: the Arena's own switches for
-- live gold (the Wallet's: the King's live switch on gold, saved data that survives, the arena
-- not off, no test build). The direct rail never needs it: there Olympus only records.
function Requests.GoldGate()
	local A, R = ns.Arena, ns.ArenaRoles
	if type(A) ~= "table" or type(A.Persists) ~= "function" or type(R) ~= "table" or type(R.Live) ~= "function" then return "arena" end
	if type(A.Off) == "function" and A.Off() then return "off" end
	if type(A.TestBuild) == "function" and A.TestBuild() ~= nil then return "test" end
	if not R.Live() then return "live" end
	if type(R.Currency) == "function" and R.Currency() ~= "g" then return "cur" end
	if not A.Persists() then return "persist" end
	return nil
end

local SETTLEMENT = {
	awaiting_funds = true, funds_reserved = true, awaiting_exchange = true,
	awaiting_items = true, custodian_received = true, outbound_prepared = true,
	outbound_sent = true, awaiting_receipt = true, ready_to_settle = true,
	payout_pending = true, settled = true, refund_pending = true, refunded = true,
	disputed = true, returned = true, cancelled = true, expired = true,
}
Requests.SETTLEMENT_STATES = SETTLEMENT
-- The custodian holds the buyer's gold and has handed nothing on: a cancel or the deadline refunds.
local HELD = { funds_reserved = true, awaiting_items = true, custodian_received = true, outbound_prepared = true }
-- A mediated deal's way forward. The custodian is its authority; a party's copy follows his words
-- forward only, so a word it missed never leaves it stuck, and none takes it back.
local CUSTODY_RANK = { awaiting_funds = 1, funds_reserved = 2, awaiting_items = 3, custodian_received = 4, outbound_prepared = 5,
	outbound_sent = 6, awaiting_receipt = 7, ready_to_settle = 8, payout_pending = 9, settled = 10 }
local function Forward(from, to) return CUSTODY_RANK[from] ~= nil and CUSTODY_RANK[to] ~= nil and CUSTODY_RANK[to] > CUSTODY_RANK[from] end
-- A settlement's ends: nothing moves it again.
local FINAL = { settled = true, refunded = true, cancelled = true, expired = true, returned = true }
-- Where the custodian may still give the buyer's gold back from: anywhere short of an end, the
-- seller's payout under way, or a refund already owed.
local function Refundable(state) return not FINAL[state] and state ~= "payout_pending" and state ~= "refund_pending" end
-- The custodian holds the buyer's gold (seen land, or a Wallet reserve the buyer made for him) and
-- has given it neither on to the seller nor back. Then a deal ends by a refund or a payout only.
local function FundsHeld(s)
	if type(s) ~= "table" or s.refundedAt or s.settledAt then return false end
	local claim = type(s.fundClaim) == "table" and s.fundClaim.receipt or nil
	return s.fundedAt ~= nil or (s.payment == "wallet" and (s.walletReceipt ~= nil or (claim ~= nil and claim ~= "")))
end
-- Gold of the buyer's the deal never took (paid twice, in parts, or after the deal closed), still
-- to go back to him; and goods of the crafter's still to go back.
local function ExtraOwed(s) return math.max(0, (tonumber(s.extraCopper) or 0) - (tonumber(s.extraReturned) or 0)) end
local function ItemsOwed(s) return math.max(0, (tonumber(s.returnItems) or 0) - (tonumber(s.itemsReturned) or 0)) end
-- A closed request in this client's custody that still owes its buyer gold or its crafter goods.
Owing = function(r)
	local s = type(r) == "table" and r.settlement
	return type(s) == "table" and Custody(r) and Terminal(r) and (ExtraOwed(s) > 0 or ItemsOwed(s) > 0) or false
end
-- One closed while the buyer said his gold was on its way (a mail its custodian had not opened):
-- it may still land, within a mail's days, and is then the buyer's to have back.
LateGold = function(r)
	local s = type(r) == "table" and r.settlement
	return type(s) == "table" and Custody(r) and Terminal(r) and s.fundClaim ~= nil and not s.fundedAt
		and Now() - (tonumber(r.updated) or 0) <= Requests.MAIL_DAYS or false
end

function Requests.FeeBreakdown(total, postage)
	total, postage = Clamp(total, 0, Requests.PRICE_MAX), Clamp(postage or 0, 0, Requests.PRICE_MAX)
	if not total or not postage then return nil, "shape" end
	local fee = math.floor(total * Requests.GUILD_FEE_BP / 10000)
	return { gross = total, guildFeeBP = Requests.GUILD_FEE_BP, guildFee = fee,
		sellerNet = total - fee, postage = postage, guildNet = math.max(0, fee - postage),
		postageShortfall = math.max(0, postage - fee) }
end

-- A keeper by name, as every client knows the list (the Treasurer's pins, the King's list).
local function CustodianKnown(name)
	local T = ns.Treasury
	return type(name) == "string" and type(T) == "table" and type(T.KeeperByName) == "function"
		and T.KeeperByName(Full(name)) == true
end
-- This character is a keeper now (its live guild).
local function KeeperHere()
	local T = ns.Treasury
	local guild = GetGuildInfo and GetGuildInfo("player") or nil
	return type(T) == "table" and type(T.IsKeeperName) == "function" and T.IsKeeperName(Full(ns.me), guild) == true
end
local function CustodianAuthority(r) return Custody(r) and KeeperHere() end
-- The custodian's addon heard lately (the treasury's own record of its keepers): a whisper to a
-- player who is offline is a line of the game's in the chat, so a party's quiet deal asks only then.
local function CustodianOnline(name)
	local T = ns.Treasury
	if type(T) ~= "table" or type(T.Online) ~= "function" then return false end
	for _, n in ipairs(T.Online() or {}) do if Same(n, name) then return true end end
	return false
end
-- The guild's fees: where they go (the Arena's fee receiver: on the Treasurer's realm group
-- his mail character, Dues.MailTo), and who keeps their ledger, the desk: a fee receiver's
-- character (the Treasurer's characters there). By the names the server stamps on a message, and
-- this client's own name: never the author's preview of the Treasurer's or the King's view.
local function FeeReceiver()
	local R = ns.ArenaRoles
	return Full(type(R) == "table" and type(R.FeeReceiver) == "function" and R.FeeReceiver() or nil)
end
local function FeeDeskName(name)
	local R = ns.ArenaRoles
	return type(name) == "string" and type(R) == "table" and type(R.IsFeeReceiver) == "function" and R.IsFeeReceiver(Full(name)) == true
end
local function FeeDesk() return FeeDeskName(ns.me) end
-- The collection is the desk's characters' and the King's (the owner's answer): their reminders
-- alone reach a debtor.
local function Collects(name)
	return FeeDeskName(name) or (type(name) == "string" and ns.IsKingCharacter(Full(name)) == true)
end
-- The debtors' ranking and every fee owed are read by them, the High Council and the author (the
-- owner's answer), by their own names (the signed council list, the author's name on his realm
-- group), and by nobody else: never a preview of anyone's view.
local function ReadsDebtors(name)
	if Collects(name) then return true end
	if type(name) ~= "string" then return false end
	local W = ns.Workshop
	return ns.IsHighCouncillor(Full(name)) == true
		or (type(W) == "table" and type(W.IsAuthorName) == "function" and W.IsAuthorName(Full(name)) == true)
end
-- A desk character whose addon was heard lately (a whisper to one who is not online is a line of
-- the game's in the chat): the fee words go only then.
local function OnlineDesk()
	local T = ns.Treasury
	if type(T) ~= "table" or type(T.Online) ~= "function" then return nil end
	for _, n in ipairs(T.Online() or {}) do if FeeDeskName(n) and not Same(n, ns.me) then return Full(n) end end
	return nil
end
-- A test build never touches live (Arena.TestBuild): there the fee is shown, never owed.
local function TestBuild()
	local A = ns.Arena
	return type(A) == "table" and type(A.TestBuild) == "function" and A.TestBuild() ~= nil
end

-- The custodian is neither of the parties: a keeper who sells cannot hold his own sale's gold.
local function Independent(custodian, requester, crafter)
	return custodian ~= nil and not Same(custodian, requester) and not Same(custodian, crafter)
end
-- A reviewer every party can check from its own client: a High Councillor or a listed keeper.
local function RemoteReviewer(name)
	return type(name) == "string" and ((ns.IsHighCouncillor and ns.IsHighCouncillor(Full(name)) == true) or CustodianKnown(name))
end

local function SettlementAudit(r, kind, actor, detail)
	local s = r and r.settlement
	if not s then return end
	s.audit = type(s.audit) == "table" and s.audit or {}
	s.audit[#s.audit + 1] = { t = Now(), kind = Clean(kind, 32), actor = Full(actor) or actor, detail = Clean(detail, 120) }
	while #s.audit > Requests.AUDIT_MAX do table.remove(s.audit, 1) end
	Audit(r, "settlement-" .. tostring(kind), actor, detail)
end

function Requests.RegisterEscrowAdapter(name, adapter)
	name = Clean(name, 20)
	if name == "" or type(adapter) ~= "table" or type(adapter.reserve) ~= "function"
		or type(adapter.release) ~= "function" or type(adapter.refund) ~= "function" then return false end
	escrowAdapters[name] = adapter
	return true
end

-- Only a Wallet that really has reserve, release and refund for crafting is an escrow.
local function WalletEscrowAdapter()
	local W = ns.Wallet
	if type(W) ~= "table" or type(W.ReserveCrafting) ~= "function" or type(W.ReleaseCrafting) ~= "function"
		or type(W.RefundCrafting) ~= "function" then return nil end
	return {
		reserve = function(r, s) return W.ReserveCrafting(r.id, r.requester, s.gross, s.custodian) end,
		verify = type(W.VerifyCraftingReserve) == "function" and function(r, s, receipt) return W.VerifyCraftingReserve(r.id, receipt, s.gross) end or nil,
		release = function(r, s) return W.ReleaseCrafting(r.id, r.crafter, s.sellerNet, s.guildFee) end,
		refund = function(r, s) return W.RefundCrafting(r.id, r.requester, s.gross) end,
	}
end

local function EscrowAdapter(s)
	if not s or s.payment ~= "wallet" then return nil end
	return escrowAdapters.wallet or WalletEscrowAdapter()
end

function Requests.WalletEscrowAvailable()
	return WalletShown() and EscrowAdapter({ payment = "wallet" }) ~= nil or false
end

local function NewSettlement(r, rail, payment, custodian, postage)
	if rail ~= "direct" and rail ~= "guild" then return nil, "rail" end
	if not PAY_CODE[payment] then return nil, "payment" end
	if rail == "direct" and payment == "wallet" then return nil, "rail" end
	if rail == "guild" then
		local gate = Requests.GoldGate()
		if gate then return nil, gate end
		custodian = Full(custodian)
		if not custodian or #custodian > 48 or not CustodianKnown(custodian) then return nil, "custodian" end
		if not Independent(custodian, r.requester, r.crafter) then return nil, "custodian-party" end
		if payment == "wallet" and not Requests.WalletEscrowAvailable() then return nil, "wallet-unsupported" end
	else
		custodian = nil
	end
	local total = r.terms and r.terms.total or 0
	local money, why = Requests.FeeBreakdown(total, rail == "guild" and postage or 0)
	if not money then return nil, why end
	return { version = 1, rail = rail, payment = payment, custodian = custodian,
		state = rail == "guild" and "awaiting_funds" or "awaiting_exchange", gross = money.gross, guildFeeBP = money.guildFeeBP,
		guildFee = money.guildFee, sellerNet = money.sellerNet, postage = money.postage,
		guildNet = money.guildNet, postageShortfall = money.postageShortfall,
		created = Now(), updated = Now(), deadline = Now() + Requests.SETTLEMENT_TTL,
		evidence = {}, seen = {}, audit = {}, direct = rail == "direct" and { item = false, gold = total == 0 } or nil }
end

function Requests.ConfigureSettlement(id, rail, payment, custodian, postage)
	local r = Requests.Get(id)
	if not r or not Same(r.crafter, ns.me) or r.state ~= "accepted" or r.terms then return false, "state" end
	local probe = { terms = { total = 0 }, requester = r.requester, crafter = r.crafter }
	local s, why = NewSettlement(probe, rail, payment, custodian, postage)
	if not s then return false, why end
	r.settlementDraft = { rail = s.rail, payment = s.payment, custodian = s.custodian, postage = s.postage }
	Changed()
	return true
end

-- No amount on the watch: ArenaMoney's own exclusion (Money.Flow) never takes a crafting line for
-- the arena's. A custodian's treasury book asks Requests.TreasuryFlow instead.
InstallMoneyWatch = function(r)
	if not r or not (Mine(r) or Custody(r)) or not r.crafter or (Terminal(r) and not Owing(r) and not LateGold(r)) then return false end
	if InstallExchangeHooks then InstallExchangeHooks() end
	local M = ns.ArenaMoney
	if type(M) ~= "table" or type(M.Expect) ~= "function" then return false end
	return M.Expect("craft:" .. r.id, { dir = "both" })
end

-- (A closed custody that owes the buyer or may still receive his gold keeps its watch.)
local function ForgetMoneyWatch(r)
	if Owing(r) or LateGold(r) then return end
	local M = ns.ArenaMoney
	if type(M) == "table" and type(M.Forget) == "function" and r then M.Forget("craft:" .. r.id) end
end

--------------------------------------------------------------------------
-- Ids, the board card and its publication.
--------------------------------------------------------------------------

-- Base 36 of the second and a counter, and two characters of this character's name: two requesters
-- in the same second do not make one id.
local function NameSalt()
	local n, me = 0, tostring(ns.me or "")
	for i = 1, #me do n = (n * 31 + me:byte(i)) % 1296 end
	local s = ns.Codec.Base36(n)
	return ("0"):rep(2 - #s) .. s
end
local function NewId()
	nextId = (nextId + 1) % 1679616
	return ns.Codec.Base36(math.floor(Now()) % 2176782336) .. ns.Codec.Base36(nextId) .. NameSalt()
end

local function CardState(r)
	if r.state == "open" then return "o" end
	if r.state == "expired" and not r.crafter then return "e" end
	if r.state == "cancelled" and not r.crafter then return "x" end
	return "a"
end

-- The card in one logged message: the free text last, cut to what is left of 255 bytes.
local function Card(r)
	local q = r.quote or {}
	local head = table.concat({ "CQ", "2", r.id, B36(r.rev), B36(r.created), B36((r.expires or 0) - (r.created or 0)),
		B36(r.itemID or 0), tostring(r.quantity), r.kind, r.profession or "", CardState(r), r.materials == "buyer" and "b" or "c",
		r.guild, B36(q.reference or 0), B36(q.observedAt or 0), B36(r.floor or 0), r.itemName }, "~") .. "~"
	if #head > Requests.MESSAGE_MAX then return nil end
	return head .. ns.Cut(r.details or "", Requests.MESSAGE_MAX - #head)
end
Requests.Card = Card

local function Publish(r, force)
	if not r or not Same(r.requester, ns.me) or not ns.IsMember() then return false, "authority" end
	if Requests.Barred() then return false, "sanction" end
	local now = Now()
	if not force and now - (r.lastPublished or -math.huge) < Requests.PUBLISH_GAP then return false, "fresh" end
	local msg = Card(r)
	if not msg then return false, "size" end
	-- Paced across every card of ours; a card the pace holds back is sent by the next Tick.
	if not Bucket(publishTimes, "all", 600, Requests.PUBLISH_PER_10MIN, now) then r.publishPending = true return false, "rate" end
	r.lastPublished, r.publishPending = now, nil
	local rev = r.rev
	local ok = ns.Comm.Send("CHANNEL", msg, "craft-card:" .. r.id, false, true, nil, { owner = Requests, guard = function()
		local current = Requests.Get(r.id)
		return ns.IsMember() and current ~= nil and Same(current.requester, ns.me) and current.rev == rev
	end })
	if not ok then r.publishPending = true end
	return ok and true or false, ok and "ok" or "busy"
end
Requests.Publish = Publish

-- A line and the "craft" sound switch's soft sound, as a treasury donation is told: never a window
-- or a tab that opens by itself (ns.Alert's show would switch the player's page at once). The one
-- exception is the deal's own room once a claim is won (Requests.OpenChat: the owner's pattern for
-- every pending conversation, ChatRooms.OpenMatter).
local function Notify(r, text)
	if not Bucket(alertTimes, "alerts", 600, 5) then return end
	ns.Print(text)
	if ns.PlayAlert then ns.PlayAlert("soft", "craft") end
end

local function Context(r)
	return L.CRAFT_REQUEST_CONTEXT:format(ns.DisplayName(r.requester), r.quantity, r.itemName, r.details ~= "" and r.details or L.CRAFT_REQUEST_NO_DETAILS)
end
local function AddContext(r)
	if not r or not r.crafter then return end
	r.chat = type(r.chat) == "table" and r.chat or {}
	if r.contextAdded then return end
	r.contextAdded = true
	r.chat[#r.chat + 1] = { t = r.created, sender = r.requester, guild = r.guild, text = Context(r), system = true }
	r.chat[#r.chat + 1] = { t = r.created, sender = r.crafter, guild = r.guild, text = L.CRAFT_REQUEST_NEGOTIATE, system = true }
end

-- Only the requester moves the card, and only while it says something public: taken, or closed
-- before anyone took it.
PublicAdvance = function(r, state)
	if not Same(r.requester, ns.me) then return end
	local before = CardState(r)
	r.state, r.updated = state, Now()
	if CardState(r) ~= before then
		r.rev = (r.rev or 0) + 1
		r.takenRepublish = CardState(r) == "a" or nil
		Publish(r, true)
	end
end

local function OpenFrom(sender)
	local n = 0
	for _, r in pairs(Store().records) do if r.state == "open" and Same(r.requester, sender) then n = n + 1 end end
	return n
end

function Requests.ReceiveSnapshot(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or #text > Requests.MESSAGE_MAX then return false, "lane" end
	local f = ns.Codec.Split(text, "~")
	if f[1] ~= "CQ" or f[2] ~= "2" or #f ~= 18 then return false, "version" end
	sender = Full(sender)
	if not sender or Same(sender, ns.me) then return false, "sender" end
	if Requests.Barred(sender) then return false, "sanction" end
	if not Bucket(cardBuckets, Lower(sender), 600, Requests.CARDS_PER_10MIN) then return false, "rate" end
	local now = Now()
	local id, rev = f[3], UnB36(f[4], 0, 2147483647)
	local created, ttl = UnB36(f[5], 1, 9999999999), UnB36(f[6], 1, Requests.REQUEST_TTL + 300)
	local itemID, quantity = UnB36(f[7], 0, 999999999), Clamp(f[8], 1, Requests.QUANTITY_MAX)
	local kind, profession, state = f[9], Clean(f[10], 24), CARD_STATE[f[11]]
	local materials = f[12] == "b" and "buyer" or (f[12] == "c" and "crafter" or nil)
	local guild = Clean(f[13], Requests.GUILD_MAX)
	local reference, quoteAt, floor = UnB36(f[14], 0, Requests.PRICE_MAX), UnB36(f[15], 0, 9999999999), UnB36(f[16], 0, Requests.PRICE_MAX)
	local itemName = Clean(f[17], Requests.ITEM_NAME_MAX)
	-- The requester's words show only as they came: logged.
	local details = Unlogged() and "" or Clean(f[18], Requests.DETAILS_MAX)
	if type(id) ~= "string" or #id < 3 or #id > 24 or not id:match("^[0-9a-z]+$") or not rev or not created or not ttl
		or created > now + 300 or now > created + ttl + Requests.RETAIN or not itemID or not quantity or (kind ~= "c" and kind ~= "g")
		or not state or not materials or guild == "" or not ns.IsFederation(guild) or itemName == ""
		or not reference or not quoteAt or not floor then return false, "shape" end
	if not ns.Data.ClaimGuild(sender, guild) then return false, "guild" end
	local old = Requests.Get(id)
	if old and not Same(old.requester, sender) then return false, "identity" end
	if old and rev <= (old.rev or 0) then return false, rev == old.rev and "duplicate" or "stale" end
	-- Once a request has a private side here (our deal, our custody, our review), only its private
	-- words move it: a card can neither close nor complete it.
	if old and (old.crafter or Custody(old) or Reviewing(old)) then return false, "private" end
	if old and CARD_RANK[state] < CARD_RANK[old.state] then return false, "rollback" end
	if not old then
		if state ~= "open" then return false, "closed" end
		if OpenFrom(sender) >= Requests.OPEN_PER_REQUESTER then return false, "cap" end
	end
	local r = old or { id = id, requester = sender, audit = {}, chat = {}, seenActions = {}, seenChat = {} }
	r.rev, r.created, r.expires, r.itemID, r.quantity, r.kind, r.profession = rev, created, created + ttl, itemID > 0 and itemID or nil, quantity, kind, profession
	r.guild, r.itemName, r.details, r.materials, r.state, r.crafter = guild, itemName, details, materials, state, nil
	r.floor, r.updated = floor, now
	r.quote = reference > 0 and quoteAt > 0 and quoteAt <= now + 300
		and { reference = reference, observedAt = quoteAt, source = L.CRAFT_QUOTE_PUBLISHED, confidence = "remote", method = "published quote" } or nil
	Store().records[id] = r
	Audit(r, old and "card" or "published", sender, state)
	if not old and Requests.CanFulfill(r) then Notify(r, L.CRAFT_REQUEST_MATCH_ALERT:format(quantity, itemName)) end
	Changed()
	return true, r
end

--------------------------------------------------------------------------
-- The private words (CR): one sequence per record and sender, whatever the verb.
--------------------------------------------------------------------------

local function NextSeq(r) r.outSeq = (tonumber(r.outSeq) or 0) + 1 return r.outSeq end

local function SendWord(r, to, verb, ...)
	if not to then return false, "party" end
	if Requests.Barred() then return false, "sanction" end
	local seq = NextSeq(r)
	local parts = { "CR", "1", r.id, tostring(seq), verb }
	for i = 1, select("#", ...) do parts[#parts + 1] = Clean(select(i, ...), 100) end
	local msg = table.concat(parts, "~")
	if #msg > Requests.MESSAGE_MAX then return false, "size" end
	local ok = ns.Comm.Whisper(to, msg, "craft-action:" .. r.id .. ":" .. seq, true, true, nil, { owner = Requests, guard = function()
		return Requests.Get(r.id) ~= nil and ns.IsMember()
	end })
	return ok and true or false, ok and "ok" or "busy"
end
local function SendPrivate(r, verb, ...)
	local to = Other(r)
	if not to then return false, "party" end
	return SendWord(r, to, verb, ...)
end

-- Did this client see goods or gold change hands with the other party, either way? Then the deal
-- ends by its confirmation or a reviewed dispute: a cancel would let one side keep what it got.
local function Performed(r)
	for _, e in ipairs(type(r.evidence) == "table" and r.evidence or {}) do
		if Same(e.observer, ns.me) and ((e.copper or 0) > 0 or next(e.itemsOut or {}) ~= nil or next(e.itemsIn or {}) ~= nil) then return true end
	end
	return false
end

-- A mediated deal its custodian never said he took (away, no longer a keeper, or he refused the
-- contract), with nothing of either party's on its way to him: nobody holds anything, so the
-- parties may end it themselves. (Otherwise only he can: he holds what reached him.)
local function Untaken(r)
	local s = r and r.settlement
	return type(s) == "table" and s.rail == "guild" and not s.contractAt and s.state == "awaiting_funds"
		and not FundsHeld(s) and not s.fundClaim and not s.itemClaim and not Performed(r)
end

-- The mediated rail and the review (CK): the same, to one named recipient.
local function SendMediation(r, to, verb, ...)
	to = Full(to)
	if not to or Same(to, ns.me) then return false, "target" end
	r.mediationSeq = (tonumber(r.mediationSeq) or 0) + 1
	local seq = r.mediationSeq
	local parts = { "CK", "1", r.id, tostring(seq), verb }
	for i = 1, select("#", ...) do parts[#parts + 1] = Clean(select(i, ...), 100) end
	local msg = table.concat(parts, "~")
	if #msg > Requests.MESSAGE_MAX then return false, "size" end
	local ok = ns.Comm.Whisper(to, msg, "craft-mediation:" .. r.id .. ":" .. seq, true, true, nil, { owner = Requests, guard = function()
		return Requests.Get(r.id) ~= nil and ns.IsMember()
	end })
	return ok and true or false, ok and "ok" or "busy"
end
Requests.SendMediation = SendMediation
-- The custodian's or the reviewer's word to both parties.
local function Tell(r, verb, ...)
	local sent = 0
	for _, to in ipairs({ r.requester, r.crafter }) do
		if to and not Same(to, ns.me) and SendMediation(r, to, verb, ...) then sent = sent + 1 end
	end
	return sent > 0
end
-- A party's word to the custodian (and, on a dispute, to its reviewer when that is someone else).
local function ToCustodian(r, verb, ...)
	local s = r and r.settlement
	if not s or s.rail ~= "guild" or not s.custodian then return false, "custodian" end
	return SendMediation(r, s.custodian, verb, ...)
end
-- A party's invite: the contract both parties name to the custodian, word for word. Sent again,
-- it changes nothing he holds; it only asks him to say again that he took it.
local function SendInvite(r)
	local s = r.settlement
	local guild = Clean(GetGuildInfo and GetGuildInfo("player"), Requests.GUILD_MAX)
	return ToCustodian(r, "invite", B36(s.gross), B36(s.sellerNet), B36(s.guildFee), B36(r.itemID or 0),
		tostring(r.quantity), PAY_CODE[s.payment], B36(s.postage), B36(s.deadline), r.requester, r.crafter, guild)
end

function Requests.Accept(id)
	local r = Requests.Get(id)
	if not r or r.state ~= "open" or Same(r.requester, ns.me) then return false, "state" end
	if not ns.IsMember() then return false, "member" end
	if Requests.Barred() then return false, "sanction" end
	if Requests.PrivilegeStatus(ns.me).canAccept == false then return false, "craft-debt" end
	if r.claimPending then return false, "pending" end
	local guild = Clean(GetGuildInfo("player"), Requests.GUILD_MAX)
	if guild == "" or not ns.IsFederation(guild) then return false, "guild" end
	local nonce = NewId()
	r.claimNonces = type(r.claimNonces) == "table" and r.claimNonces or {}
	r.claimNonces[nonce] = true
	r.claimPending = Now()
	local seq = NextSeq(r)
	local msg = ("CR~1~%s~%d~claim~%d~%s~%s"):format(r.id, seq, r.rev or 0, nonce, guild)
	local ok = ns.Comm.Whisper(r.requester, msg, "craft-claim:" .. r.id, true, true, nil, { owner = Requests, guard = function()
		local now = Requests.Get(r.id)
		return now ~= nil and now.state == "open" and ns.IsMember()
	end })
	if not ok then r.claimPending = nil end
	Audit(r, "claim-sent", ns.me)
	Changed()
	return ok and true or false, ok and "ok" or "busy"
end

local function Suggested(r)
	if not r.suggestedTerms then r.suggestedTerms = Requests.SuggestTerms(r) end
	return r.suggestedTerms
end

local function WinClaim(r, crafter, guild, nonce)
	r.crafter, r.crafterGuild, r.claimNonce, r.claimPending = crafter, Clean(guild, Requests.GUILD_MAX), nonce, nil
	PublicAdvance(r, "accepted")
	Suggested(r)
	AddContext(r)
	InstallMoneyWatch(r)
	Audit(r, "accepted", crafter)
	-- The answer is private and names no third party; the card only says "taken".
	SendPrivate(r, "accepted", r.rev, nonce)
	Notify(r, L.CRAFT_REQUEST_ACCEPTED_ALERT:format(ns.DisplayName(crafter), r.itemName))
	Changed()
	ns.SafeCall("craft request room", Requests.OpenChat, r.id, true)
	return true
end

local function TakeClaim(r, sender, seq, f)
	local key = Lower(sender)
	local rev, nonce, guild = Clamp(f[6], 0, 2147483647), f[7], Clean(f[8], Requests.GUILD_MAX)
	if not Same(r.requester, ns.me) or type(nonce) ~= "string" or #nonce > 16 or not nonce:match("^[0-9a-z]+$")
		or guild == "" or not ns.IsFederation(guild) or not ns.Data.ClaimGuild(sender, guild) then return false, "claim" end
	r.seenActions[key] = seq
	if r.state ~= "open" or rev ~= r.rev or Requests.PrivilegeStatus(sender).canAccept == false then
		-- The loser hears it at once; the one winning claim is unchanged.
		SendWord(r, sender, "taken", nonce)
		return false, "claimed"
	end
	return WinClaim(r, sender, guild, nonce)
end

-- The requester's answer to our own claim (the nonce we sent): we are the crafter, or we lost.
local function TakeAnswer(r, sender, seq, verb, f)
	local nonce = verb == "accepted" and f[7] or f[6]
	if not Same(sender, r.requester) or type(r.claimNonces) ~= "table" or type(nonce) ~= "string" or not r.claimNonces[nonce] then return false, "authority" end
	r.seenActions[Lower(sender)] = seq
	if verb == "taken" then
		r.claimPending, r.claimLost = nil, Now()
		Audit(r, "claim-lost", sender)
		Changed()
		return true
	end
	if (r.crafter and not Same(r.crafter, ns.me)) or (r.state ~= "open" and r.state ~= "accepted") then return false, "state" end
	r.crafter, r.claimNonce, r.claimPending, r.state = ns.me, nonce, nil, "accepted"
	r.rev, r.updated = math.max(r.rev or 0, Clamp(f[6], 0, 2147483647) or 0), Now()
	Suggested(r); AddContext(r); InstallMoneyWatch(r); Audit(r, "accepted", ns.me)
	Changed()
	ns.SafeCall("craft request room", Requests.OpenChat, r.id, true)
	return true
end

local function MaybeTerms(r)
	local t = r.terms
	if not t or not (t.agrees and t.agrees.requester and t.agrees.crafter) then return false end
	if r.state == "accepted" then
		local settlement, why = NewSettlement(r, t.rail or "direct", t.payment or "trade", t.custodian, t.postage)
		if not settlement then
			Audit(r, "terms-settlement-refused", ns.me, why)
			return false, why
		end
		r.settlement = settlement
		r.state, r.updated = "terms", Now()
		Audit(r, "terms-confirmed", ns.me, tostring(t.total))
		InstallMoneyWatch(r)
		if settlement.rail == "guild" then
			-- Both parties name the same contract to the custodian; he takes it only when both did.
			SendInvite(r)
		end
		Changed()
	end
	return true
end

local function ApplyOffer(r, sender, f)
	local version = Clamp(f[6], 1, 1000000)
	local mode = f[7] == "b" and "buyer" or (f[7] == "f" and "finished" or nil)
	local qty, unit, floor = Clamp(f[8], 1, Requests.QUANTITY_MAX), Clamp(f[9], 0, Requests.PRICE_MAX), Clamp(f[10], 0, Requests.PRICE_MAX)
	local reference, discount, quoteAt = Clamp(f[11], 0, Requests.PRICE_MAX), Clamp(f[12], 0, 10000), Clamp(f[13], 0, 9999999999)
	local source = Clean(f[14], 36)
	local rail = f[15] == "g" and "guild" or (f[15] == "d" and "direct" or nil)
	local payment = CODE_PAY[f[16] or ""]
	local custodian, postage = Full(f[17]), Clamp(f[18], 0, Requests.PRICE_MAX)
	if not version or not mode or (mode == "buyer") ~= (r.materials == "buyer") or not qty or qty ~= r.quantity
		or not unit or not floor or not reference or not discount or not quoteAt then return false, "terms" end
	if mode == "finished" and unit < floor then return false, "floor" end
	if qty * unit > Requests.PRICE_MAX then return false, "price" end
	if not rail or not payment or not postage or (rail == "direct" and payment == "wallet") then return false, "rail" end
	if rail == "guild" then
		local gate = Requests.GoldGate()
		if gate then return false, gate end
		if not custodian or #custodian > 48 or not CustodianKnown(custodian) or not Independent(custodian, r.requester, r.crafter) then return false, "custodian" end
	end
	r.terms = { version = version, mode = mode, quantity = qty, unit = unit, total = qty * unit, floor = floor,
		reference = reference, discountBP = discount, quoteAt = quoteAt, source = source, proposer = sender, agrees = {},
		rail = rail, payment = payment, custodian = rail == "guild" and custodian or nil,
		postage = rail == "guild" and postage or 0, guildFeeBP = Requests.GUILD_FEE_BP }
	local money = Requests.FeeBreakdown(r.terms.total, r.terms.postage)
	r.terms.guildFee, r.terms.sellerNet, r.terms.guildNet = money.guildFee, money.sellerNet, money.guildNet
	Audit(r, "terms-proposed", sender, tostring(r.terms.total))
	return true
end

local function ActionAllowed(r, sender, verb)
	if not Party(r, sender) or not Party(r, ns.me) then return false end
	local s = r.settlement
	if verb == "offer" then return Same(sender, r.crafter) and r.state == "accepted" end
	if verb == "termok" then return r.state == "accepted" or r.state == "terms" end
	if verb == "start" then return Same(sender, r.crafter) and r.state == "terms" end
	if verb == "deliver" then return Same(sender, r.crafter) and r.state == "in_progress" and s ~= nil and s.rail == "direct" end
	if verb == "complete" then return Same(sender, r.requester) and (r.state == "delivered" or r.state == "completed") and s ~= nil and s.rail == "direct" end
	if verb == "completeok" then return Same(sender, r.crafter) and r.state == "delivered" and r.completionPending == true end
	if verb == "receipt" then return Same(sender, r.requester) and s ~= nil and s.rail == "guild" and not Terminal(r) end
	-- (Or a deal this client cancelled while the other side had already handed something over: the
	-- other party turned the cancel into a dispute, and it reaches this client's record too.)
	if verb == "dispute" then return s ~= nil and (not Terminal(r) or (r.state == "cancelled" and Same(r.cancelledBy, ns.me) and not s.dispute)) end
	if verb == "escalate" or verb == "appeal" then return s ~= nil and s.dispute ~= nil and s.dispute.state == "open" end
	if verb == "cancelrefund" then return s ~= nil and s.rail == "guild" and not Terminal(r) end
	-- (On the mediated rail the custodian ends a deal he took; a party's word ends only one that,
	-- as this copy knows it, he never took and nothing went to.)
	if verb == "cancel" then return not Terminal(r) and (not s or s.rail ~= "guild" or Untaken(r)) end
	return false
end

function Requests.ReceiveAction(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > Requests.MESSAGE_MAX then return false, "lane" end
	if Unlogged() then return false, "unlogged" end
	local f = ns.Codec.Split(text, "~")
	if f[1] ~= "CR" or f[2] ~= "1" then return false, "version" end
	local r, seq, verb = Requests.Get(f[3]), Clamp(f[4], 1, 2147483647), f[5]
	sender = Full(sender)
	if not r or not seq or not sender or Same(sender, ns.me) then return false, "record" end
	if Requests.Barred(sender) then return false, "sanction" end
	if not Bucket(actionBuckets, Lower(sender), 60, Requests.ACTION_PER_MIN) then return false, "rate" end
	r.seenActions = type(r.seenActions) == "table" and r.seenActions or {}
	local seen = tonumber(r.seenActions[Lower(sender)]) or 0
	if seq <= seen or seq > seen + 1000 then return false, seq <= seen and "replay" or "sequence" end
	if verb == "claim" then return TakeClaim(r, sender, seq, f) end
	if verb == "accepted" or verb == "taken" then return TakeAnswer(r, sender, seq, verb, f) end
	if not ActionAllowed(r, sender, verb) then return false, "authority" end
	r.seenActions[Lower(sender)] = seq
	local s = r.settlement
	if verb == "offer" then
		local ok, why = ApplyOffer(r, sender, f)
		if not ok then return false, why end
	elseif verb == "termok" then
		local version = Clamp(f[6], 1, 1000000)
		if not r.terms or r.terms.version ~= version then return false, "terms" end
		r.terms.agrees = r.terms.agrees or {}
		r.terms.agrees[Same(sender, r.requester) and "requester" or "crafter"] = true
		Audit(r, "terms-agreed", sender)
		MaybeTerms(r)
	elseif verb == "start" then
		if not s or (s.rail == "guild" and s.state ~= "funds_reserved") then return false, "funds" end
		s.state, s.updated = s.rail == "guild" and "awaiting_items" or "awaiting_exchange", Now()
		r.state, r.updated = "in_progress", Now(); Audit(r, "started", sender)
	elseif verb == "deliver" then
		local qty, price, method = Clamp(f[6], 1, Requests.QUANTITY_MAX), Clamp(f[7], 0, Requests.PRICE_MAX), f[8]
		if not qty or qty > r.quantity or not price or (method ~= "mail" and method ~= "trade" and method ~= "other") then return false, "delivery" end
		r.delivery = { quantity = qty, price = price, method = method, by = sender, at = Now(), confidence = "self-reported" }
		r.state, r.updated = "delivered", Now(); Audit(r, "delivered", sender, method)
	elseif verb == "complete" then
		-- The requester confirms the crafter's own figures; any other figure books nothing.
		local qty, price = Clamp(f[6], 1, Requests.QUANTITY_MAX), Clamp(f[7], 0, Requests.PRICE_MAX)
		local d = r.delivery
		if not d or qty ~= d.quantity or price ~= d.price then return false, "figures" end
		if r.state == "completed" then
			SendPrivate(r, "completeok", d.price)
			Changed(); return true
		end
		d.confirmedBy, d.confirmedAt = sender, Now()
		local finished, why = FinishRequest(r, r.evidence and #r.evidence > 0 and "observed-and-bilateral" or "bilateral-self-confirmed")
		if not finished then return false, why end
		SendPrivate(r, "completeok", d.price)
	elseif verb == "completeok" then
		local actual = Clamp(f[6], 0, Requests.PRICE_MAX)
		if not actual or not r.delivery or actual ~= r.delivery.price then return false, "price" end
		r.completionPending = nil
		local finished, why = FinishRequest(r, r.evidence and #r.evidence > 0 and "observed-and-bilateral" or "bilateral-self-confirmed")
		if not finished then return false, why end
	elseif verb == "receipt" then
		s.buyerConfirmedAt = Now()
		if Forward(s.state, "ready_to_settle") then s.state = "ready_to_settle" end
		if r.state == "in_progress" then r.state = "delivered" end
		r.updated = Now()
		SettlementAudit(r, "buyer-receipt", sender, "custodian")
	elseif verb == "dispute" then
		-- On the mediated rail the custodian holds the dispute, and his word ("disputed") moves this
		-- copy: the other party's alone would leave it apart from his, out of his way.
		if s.rail == "guild" then
			SettlementAudit(r, "dispute-notice", sender, Clean(f[6], 120))
		elseif not DisputeSettlement(r, Clean(f[6], 120), Clean(f[7], 120), sender) then
			return false, "dispute"
		end
	elseif verb == "escalate" then
		local d, reviewer = s.dispute, Full(f[6])
		if s.rail ~= "direct" or not reviewer or Party(r, reviewer) or not RemoteReviewer(reviewer) then return false, "reviewer" end
		if d.reviewer and not Same(d.reviewer, reviewer) then return false, "reviewer" end
		d.reviewer = reviewer
		SettlementAudit(r, "escalated", sender, reviewer)
	elseif verb == "appeal" then
		local d = s.dispute
		if Now() > (d.appealUntil or 0) or d.appeals and d.appeals[Lower(sender)] then return false, "appeal" end
		d.appeals = d.appeals or {}
		d.appeals[Lower(sender)] = { by = sender, at = Now(), text = Clean(f[6], 180) }
		SettlementAudit(r, "appealed", sender, Clean(f[6], 180))
	elseif verb == "cancelrefund" then
		-- The custodian decides and tells both of us; here it is only the other party's ask.
		s.cancelAsked = { by = sender, at = Now(), reason = Clean(f[6], 80) }
		SettlementAudit(r, "refund-asked", sender, s.cancelAsked.reason)
	elseif verb == "cancel" then
		-- Once goods or gold changed hands (as this client saw it, or the crafter recorded), a cancel
		-- cannot end the deal: it becomes a dispute that a human reviews, and the other party's
		-- record holds it too (its client may have seen nothing yet: a mail on its way).
		if s and (r.delivery or r.state == "delivered" or Performed(r)) then
			if DisputeSettlement(r, "cancel-after-performance", Clean(f[6], 80), ns.me) then
				SendPrivate(r, "dispute", "cancel-after-performance", Clean(f[6], 80))
			end
		else
			r.state, r.updated, r.cancelledBy = "cancelled", Now(), sender; Audit(r, "cancelled", sender, Clean(f[6], 80))
			-- (A mediated deal nobody took: its settlement ends too, so no later word moves it.)
			if s and s.rail == "guild" then s.state, s.updated = "cancelled", Now() end
			ForgetMoneyWatch(r)
		end
	end
	Changed()
	return true
end

--------------------------------------------------------------------------
-- The two parties' actions.
--------------------------------------------------------------------------

function Requests.ProposeTerms(id, mode, unit, floor, quote, settlement)
	local r = Requests.Get(id)
	if not r or not Same(r.crafter, ns.me) or r.state ~= "accepted" then return false, "state" end
	-- Once he agreed to his own offer the requester's yes may already have closed it on the
	-- requester's side: a new offer would leave the two clients on different terms.
	if r.terms and r.terms.agrees and r.terms.agrees.crafter then return false, "agreed" end
	mode = r.materials == "buyer" and "buyer" or "finished"
	unit, floor = Clamp(unit, 0, Requests.PRICE_MAX), Clamp(floor or 0, 0, Requests.PRICE_MAX)
	if not unit or not floor or (mode == "finished" and unit < floor) or unit * r.quantity > Requests.PRICE_MAX then return false, "price" end
	quote = type(quote) == "table" and quote or r.quote or {}
	settlement = type(settlement) == "table" and settlement or r.settlementDraft or { rail = "direct", payment = "trade" }
	local rail = settlement.rail == "guild" and "guild" or (settlement.rail == "direct" and "direct" or nil)
	local payment = settlement.payment
	local custodian = rail == "guild" and Full(settlement.custodian) or nil
	local postage = rail == "guild" and Clamp(settlement.postage or 0, 0, Requests.PRICE_MAX) or 0
	if not rail or not PAY_CODE[payment or ""] or (rail == "direct" and payment == "wallet") or not postage then return false, "settlement" end
	if rail == "guild" then
		local gate = Requests.GoldGate()
		if gate then return false, gate end
		if not custodian or not CustodianKnown(custodian) or not Independent(custodian, r.requester, r.crafter) then return false, "custodian" end
	end
	local version = ((r.terms and r.terms.version) or 0) + 1
	r.terms = { version = version, mode = mode, quantity = r.quantity, unit = unit, total = unit * r.quantity,
		floor = floor, reference = Clamp(quote.reference, 0, Requests.PRICE_MAX) or 0,
		discountBP = Clamp(quote.discountBP, 0, 10000) or 0, quoteAt = Clamp(quote.observedAt or quote.quoteAt, 0, 9999999999) or 0,
		source = Clean(quote.source, 36), proposer = ns.me, agrees = {}, rail = rail, payment = payment,
		custodian = custodian, postage = postage, guildFeeBP = Requests.GUILD_FEE_BP }
	local money = Requests.FeeBreakdown(r.terms.total, postage)
	r.terms.guildFee, r.terms.sellerNet, r.terms.guildNet = money.guildFee, money.sellerNet, money.guildNet
	Audit(r, "terms-proposed", ns.me, tostring(r.terms.total))
	local t = r.terms
	local ok, why = SendPrivate(r, "offer", t.version, t.mode == "buyer" and "b" or "f", t.quantity, t.unit, t.floor, t.reference,
		t.discountBP, t.quoteAt, t.source, t.rail == "guild" and "g" or "d", PAY_CODE[t.payment], t.custodian or "", t.postage or 0)
	Changed()
	return ok, why
end

function Requests.UseSuggestedTerms(id)
	local r = Requests.Get(id)
	local t = r and Suggested(r) or nil
	if not t then return false, "request" end
	return Requests.ProposeTerms(id, t.mode, t.unit, t.floor, { reference = t.reference, discountBP = t.discountBP,
		observedAt = t.quoteAt, source = t.source }, r.settlementDraft or { rail = "direct", payment = "trade" })
end

function Requests.ConfirmTerms(id)
	local r = Requests.Get(id)
	if not r or not Party(r, ns.me) or r.state ~= "accepted" or not r.terms then return false, "state" end
	local role = Same(r.requester, ns.me) and "requester" or "crafter"
	if r.terms.agrees and r.terms.agrees[role] then return false, "duplicate" end
	r.terms.agrees = r.terms.agrees or {}; r.terms.agrees[role] = true
	Audit(r, "terms-agreed", ns.me)
	local ok, why = SendPrivate(r, "termok", r.terms.version)
	MaybeTerms(r); Changed()
	return ok, why
end

function Requests.Start(id)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not Same(r.crafter, ns.me) or r.state ~= "terms" or not s then return false, "state" end
	if s.rail == "guild" and s.state ~= "funds_reserved" then return false, "funds" end
	s.state, s.updated = s.rail == "guild" and "awaiting_items" or "awaiting_exchange", Now()
	SettlementAudit(r, "production-started", ns.me, s.rail)
	r.state, r.updated = "in_progress", Now(); Audit(r, "started", ns.me); Changed()
	return SendPrivate(r, "start")
end

function Requests.Deliver(id, quantity, price, method)
	local r = Requests.Get(id)
	local s = r and r.settlement
	quantity, price = Clamp(quantity, 1, Requests.QUANTITY_MAX), Clamp(price, 0, Requests.PRICE_MAX)
	if not r or not s or s.rail ~= "direct" or not Same(r.crafter, ns.me) or r.state ~= "in_progress" or not quantity or quantity > r.quantity or not price
		or (method ~= "mail" and method ~= "trade" and method ~= "other") then return false, "state" end
	r.delivery = { quantity = quantity, price = price, method = method, by = ns.me, at = Now(), confidence = "self-reported" }
	r.state, r.updated = "delivered", Now(); Audit(r, "delivered", ns.me, method); Changed()
	return SendPrivate(r, "deliver", quantity, price, method)
end

function Requests.ConfirmDelivery(id)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not s or not Same(r.requester, ns.me) then return false, "state" end
	if s.rail == "guild" then
		-- (Or the goods are in his bags from the custodian, though the word that they left him was
		-- missed: the custodian still accepts the receipt only once he saw them go.)
		local sent = s.state == "outbound_sent" or s.state == "awaiting_receipt"
			or (s.receiptObserved ~= nil and Forward(s.state, "ready_to_settle"))
		if not sent or (r.state ~= "terms" and r.state ~= "in_progress" and r.state ~= "delivered") then return false, "state" end
		s.state, s.buyerConfirmedAt, s.updated = "ready_to_settle", Now(), Now()
		r.delivery = r.delivery or { quantity = r.quantity, price = s.gross, method = "custodian", by = r.crafter, at = Now() }
		r.delivery.confirmedBy, r.delivery.confirmedAt = ns.me, Now()
		r.delivery.validation = s.receiptObserved and "observed-and-self-confirmed" or "self-confirmed"
		r.state, r.updated = "delivered", Now()
		SettlementAudit(r, "buyer-receipt", ns.me, r.delivery.validation)
		SendPrivate(r, "receipt")
		local ok, why = ToCustodian(r, "receipt")
		Changed()
		return ok, why
	end
	-- The direct rail: the requester confirms exactly what the crafter recorded, never a figure an
	-- observation made up.
	if r.state ~= "delivered" or not r.delivery or not Same(r.delivery.by, r.crafter) then return false, "state" end
	r.delivery.validation = r.evidence and #r.evidence > 0 and "observed-and-self-confirmed" or "self-confirmed"
	r.completionPending = true
	-- The buyer's word of the sale goes to the fee desk now, on the crafter's own figures: a
	-- seller's client that never answers with its "completeok" cannot keep the sale from it.
	-- (1.2.0: only while the Wallet's fee desk is on, Compliance.Wallet.)
	local C = ns.Compliance
	if type(C) == "table" and type(C.Wallet) == "function" and C.Wallet() == true then QueueFeeReport(r, "b", r.delivery.price) end
	local ok, why = SendPrivate(r, "complete", r.delivery.quantity, r.delivery.price)
	if not ok then r.completionLastError = Clean(why, 40) end
	Changed()
	return ok, why
end

function Requests.Cancel(id, reason)
	local r = Requests.Get(id)
	if not r or not Party(r, ns.me) or Terminal(r) then return false, "state" end
	reason = Clean(reason, 80)
	local s = r.settlement
	-- After a delivery the deal ends by confirmation or a reviewed dispute, never a cancel.
	if s and (r.delivery or r.state == "delivered") then return false, "delivered" end
	if s and s.rail == "guild" and Untaken(r) then
		-- Nobody holds anything yet: the deal ends here. The other party is told, and the
		-- custodian too (a contract he took meanwhile ends at his end; an invite waiting goes).
		s.state, s.updated = "cancelled", Now()
		r.state, r.updated, r.cancelledBy = "cancelled", Now(), ns.me
		Audit(r, "cancelled", ns.me, reason)
		local ok, why = SendPrivate(r, "cancel", reason)
		ToCustodian(r, "cancel", reason)
		ForgetMoneyWatch(r)
		Changed(); return ok, why
	end
	if s and s.rail == "guild" then
		if not (HELD[s.state] or s.state == "awaiting_funds" or s.state == "awaiting_items") then return false, "custody" end
		-- The custodian decides the refund and tells both parties; the other party hears the ask.
		s.cancelAsked = { by = ns.me, at = Now(), reason = reason }
		SettlementAudit(r, "refund-asked", ns.me, reason)
		SendPrivate(r, "cancelrefund", reason)
		local ok, why = ToCustodian(r, "cancel", reason)
		Changed(); return ok, why
	end
	if s and Performed(r) then return false, "performed" end
	local other = Other(r)
	-- A card nobody took closes in public; after a claim the end is the two parties' alone.
	if other then r.state, r.updated, r.cancelledBy = "cancelled", Now(), ns.me else PublicAdvance(r, "cancelled") end
	Audit(r, "cancelled", ns.me, reason)
	local ok, why = true, "ok"
	if other then ok, why = SendPrivate(r, "cancel", reason) end
	ForgetMoneyWatch(r)
	Changed()
	return ok, why
end

--------------------------------------------------------------------------
-- Completion and the guild's 6%.
--------------------------------------------------------------------------

-- A treasury keeper's book: what the custodian takes in or pays out for a request is the
-- parties' (excluded), and the 6% the guild keeps from it is the guild's (counted, never a gift).
-- (Gold that reached his bags only: a Wallet payout hands the Wallet the fee with the rest, and
-- the Wallet's own book counts it.)
local function BookRetainedFee(r)
	local s, T = r.settlement, ns.Treasury
	if not s or s.feeBooked or s.payment == "wallet" or not CustodianAuthority(r) or type(T) ~= "table" or type(T.Record) ~= "function"
		or (s.guildFee or 0) <= 0 then return end
	s.feeBooked = Now()
	ns.SafeCall("craft fee", T.Record, r.crafter, s.guildFee, "craft", false, { kind = "fee", quiet = true })
end

local function DateText(t) return date and date("%Y-%m-%d %H:%M", math.floor(tonumber(t) or 0)) or tostring(t) end

-- The guild's 6%. The mediated rail's custodian keeps it from the payout. On the direct rail
-- it is the seller's debt to the guild, once, on the sale the buyer confirmed: due FEE_DUE later,
-- paid by a mail to the fee receiver titled FEE_SUBJECT and the request (Requests.PayFee fills
-- it). Neither the Arena's switches nor its chips have a say: the game's gold, owed whatever they
-- are. Where nothing can take it (no fee receiver on this realm group, or a test build) it is
-- shown and owed to nobody. The buyer's copy only notes it is the seller's; both tell the desk.
local function RegisterGuildFee(r)
	local s = r and r.settlement
	if not s or s.guildFee == nil then return false, "settlement" end
	if s.rail == "guild" then
		s.feeState, s.feePaidAt = "retained", s.settledAt or Now()
		BookRetainedFee(r)
		return true
	end
	-- (Once: a completion heard again books nothing more.)
	if s.feeState then return true end
	if s.guildFee <= 0 then s.feeState = "paid" return true end
	-- 1.2.0 (Konig's review): no fee desk while the Wallet is off (Compliance.Wallet): nothing owed,
	-- nothing printed, no penalty, no report to the Treasurer.
	local C = ns.Compliance
	if not (type(C) == "table" and type(C.Wallet) == "function" and C.Wallet() == true) then
		s.feeState, s.feeWhy = "off", "wallet"
		return true
	end
	s.feeDue = (r.completedAt or Now()) + Requests.FEE_DUE
	local to = FeeReceiver()
	if not to or TestBuild() then
		s.feeState, s.feeWhy = "advisory", to and "test" or "receiver"
		SettlementAudit(r, "guild-fee-advisory", ns.me, tostring(s.guildFee))
		return true
	end
	if not Same(r.crafter, ns.me) then
		s.feeState = "crafter"
		QueueFeeReport(r, "b", s.gross)
		return true
	end
	s.feeState, s.feeTo = "due", to
	SettlementAudit(r, "guild-fee-due", ns.me, tostring(s.guildFee))
	ns.Print(L.CRAFT_FEE_DUE_NOW:format(Coins(s.guildFee), r.itemName, DateText(s.feeDue), ns.DisplayName(to), FEE_SUBJECT .. r.id))
	QueueFeeReport(r, "s", s.gross)
	ns.Fire("CRAFT_GUILD_FEE_DUE", r.id, r.crafter, s.guildFee, s.feeDue)
	return true
end

local function ApplyActualDirectSale(r)
	local s, delivery = r and r.settlement, r and r.delivery
	if not s or s.rail ~= "direct" or not delivery then return true end
	local price, quantity = Clamp(delivery.price, 0, Requests.PRICE_MAX), Clamp(delivery.quantity, 1, Requests.QUANTITY_MAX)
	if not price or not quantity or quantity > r.quantity then return false, "delivery" end
	local money = Requests.FeeBreakdown(price, 0)
	if not money then return false, "price" end
	s.agreedGross, s.actualQuantity = s.agreedGross or s.gross, quantity
	s.gross, s.guildFee, s.sellerNet, s.guildNet = money.gross, money.guildFee, money.sellerNet, money.guildNet
	s.actualPrice, s.guildFeeBP = price, Requests.GUILD_FEE_BP
	return true
end

FinishRequest = function(r, validation)
	if not r or r.state == "completed" then return false, "duplicate" end
	local s = r.settlement
	if not s then return false, "settlement" end
	if s.rail == "guild" and s.state ~= "settled" then return false, "payout" end
	if s.rail == "direct" and not r.delivery then return false, "delivery" end
	local priced, why = ApplyActualDirectSale(r)
	if not priced then return false, why end
	if s.rail == "direct" then s.state, s.settledAt = "settled", Now() end
	r.state, r.updated, r.completedAt = "completed", Now(), Now()
	if r.delivery then
		r.delivery.validation = validation or r.delivery.validation or "self-confirmed"
		r.delivery.confirmedAt = r.delivery.confirmedAt or Now()
	end
	RegisterGuildFee(r)
	Audit(r, "completed", ns.me, validation)
	ForgetMoneyWatch(r)
	Changed()
	return true
end

--------------------------------------------------------------------------
-- The moderation ladder: a cure window, then a restriction, then a human. Nothing here removes a
-- member, and only a debt this client can see paid or reviewed restricts anyone.
--------------------------------------------------------------------------

local TIERS = { [0] = "notice", [1] = "restricted", [2] = "severe", [3] = "final-review" }
-- A direct sale's fee its seller still owes: due. A fee mailed is paid as far as his client can
-- tell, however long ago (where no desk ever answers, nothing else would close it): only its mail
-- seen coming back opens it again (Fee.MailReturned). The desk's own ledger still says what it got.
FeeOpen = function(s)
	return type(s) == "table" and s.rail == "direct" and s.feeState == "due"
end
local function Ladder(due, now)
	local late = math.max(0, now - due)
	return late >= Requests.CURE_WINDOW * 2 and 3 or (late >= Requests.CURE_WINDOW and 2 or (now >= due and 1 or 0))
end

function Requests.PrivilegeStatus(name, now)
	name, now = Full(name), now or Now()
	local worst = { tier = "clear", level = 0, canAccept = true, canRequest = true }
	local function Take(level, t)
		if level > worst.level or (level == 0 and worst.tier == "clear") then
			t.level, t.tier, t.canAccept, t.canRequest = level, TIERS[level], level == 0, level == 0 or not t.debt
			worst = t
		end
	end
	if not name then return worst end
	for _, r in pairs(Store().records) do
		local s = r.settlement
		-- A guild fee: the crafter's own (his client sees it mailed; the desk tells it paid). Its
		-- ladder elsewhere is the Treasurer's and the King's (Requests.Debtors), by hand.
		if s and Same(name, ns.me) and Same(r.crafter, ns.me) and FeeOpen(s, now) then
			Take(Ladder(s.feeDue or now, now), { request = r.id, amount = s.guildFee, due = s.feeDue, reason = "guild-fee" })
		end
		-- A reviewed settlement debt: the reviewer's verdict, as both parties and the reviewer hold it.
		local d = s and s.dispute
		if d and d.state == "final" and d.decision == "debt" and d.debtState == "due" and Same(d.respondent, name) then
			Take(Ladder(d.debtDue or now, now), { request = r.id, due = d.debtDue, reason = "settlement-debt", debt = true })
		end
	end
	return worst
end

--------------------------------------------------------------------------
-- The guild's 6% of direct sales: each party's word of the sale to the fee desk, the desk's
-- ledger and the fee mails that reached it, the debtors for the Treasurer and the King.
--------------------------------------------------------------------------

-- (One block: its helpers are its own; what the rest of the file calls is in Fee.)
do
	-- The fee words' sequence: the second it is (it grows across sessions without being saved), and
	-- never the same number twice in one.
	local function NextFeeSeq()
		Fee.seq = math.max(Fee.seq + 1, math.floor(Now()))
		return Fee.seq
	end
	-- A fee word to one named player: outside any record's own sequence (the desk holds no deal).
	local function FeeWord(to, id, verb, ...)
		to = Full(to)
		if not to or Same(to, ns.me) then return false, "target" end
		local seq = NextFeeSeq()
		local parts = { "CK", "1", id, tostring(seq), verb }
		for i = 1, select("#", ...) do parts[#parts + 1] = Clean(select(i, ...), 100) end
		local msg = table.concat(parts, "~")
		if #msg > Requests.MESSAGE_MAX then return false, "size" end
		local ok = ns.Comm.Whisper(to, msg, "craft-fee:" .. id .. ":" .. seq, false, true, nil, { owner = Requests, guard = function() return ns.IsMember() end })
		return ok and true or false, ok and "ok" or "busy"
	end

	-- The desk's ledger (the realm store: the Treasurer's characters share it), keyed by the request,
	-- its seller and its buyer: a word naming other parties for the same request is a fee of its own,
	-- never a change to this one.
	local transientFees = { entries = {} }
	local function Ledger()
		if not ns.rdb then return transientFees end
		if type(ns.rdb.craftFees) ~= "table" then ns.rdb.craftFees = { entries = {} } end
		local l = ns.rdb.craftFees
		if type(l.entries) ~= "table" then l.entries = {} end
		return l
	end
	-- The ledger on the desk's own client (nil anywhere else).
	function Requests.FeeLedger() return FeeDesk() and Ledger() or nil end
	local function FeeKey(id, crafter, requester) return ("%s|%s|%s"):format(tostring(id), Lower(crafter) or "-", Lower(requester) or "-") end
	local function FeeSettled(e) return e.state == "paid" or e.state == "waived" end

	-- A fee the ladder may count: the seller's own word, with no buyer's figure above his, or the
	-- desk's confirmation by hand. Anything else (the buyer's word alone: anyone may name himself the
	-- buyer of a sale that never was; a buyer's figure above the seller's) waits apart for a human.
	-- (The King's copy has the desk's own flags: checked, differ.)
	function Fee.Confirmed(e)
		if type(e) ~= "table" then return false end
		if e.checkedBy or e.checked then return true end
		if type(e.by) ~= "table" or not e.by.s then return false end
		if e.differ ~= nil then return not e.differ end
		return (tonumber(e.grossB) or 0) <= (tonumber(e.grossS) or 0)
	end

	-- Room for one more: the paid, the waived and a payment no word of a sale ever named go after
	-- FEES_KEEP, then the oldest paid or waived; an open fee never goes. One member's words fill a
	-- bounded part of it (a modified client's flood of made-up sales): the buyer's word alone opens
	-- FEES_BUYER_ONLY fees at most per buyer, the seller's own FEES_PER_SELLER per seller.
	local function FeeRoom(led, role, requester, crafter, now)
		local n, settled, buyerOnly, sellers = 0, {}, 0, 0
		for key, e in pairs(led.entries) do
			if type(e) ~= "table" then
				led.entries[key] = nil
			elseif (FeeSettled(e) or not e.fee) and now - (tonumber(e.paidAt or e.created) or now) > Requests.FEES_KEEP then
				led.entries[key] = nil
			else
				n = n + 1
				if FeeSettled(e) then settled[#settled + 1] = e end
				if e.state == "due" and type(e.by) == "table" then
					if role == "b" and e.by.b and not e.by.s and Same(e.requester, requester) then buyerOnly = buyerOnly + 1 end
					if role == "s" and e.by.s and Same(e.crafter, crafter) then sellers = sellers + 1 end
				end
			end
		end
		if role == "b" and buyerOnly >= Requests.FEES_BUYER_ONLY then return false, "buyer-cap" end
		if role == "s" and sellers >= Requests.FEES_PER_SELLER then return false, "seller-cap" end
		if n < Requests.FEES_MAX then return true end
		table.sort(settled, function(a, b) return (a.paidAt or a.created or 0) < (b.paidAt or b.created or 0) end)
		for i = 1, math.min(#settled, n - Requests.FEES_MAX + 1) do
			led.entries[settled[i].key] = nil
			n = n - 1
		end
		return n < Requests.FEES_MAX, "full"
	end

	-- A party's word of a sale, on the desk. Each party's figure is kept, and the higher one is the
	-- fee's: a seller's lower word never shrinks what the buyer confirmed (the price the seller
	-- recorded, on an unmodified client), and a difference waits for the desk (Fee.Confirmed). The
	-- deadline is the desk's own clock's: the first word it heard, FEE_DUE later.
	local function BookFeeReport(id, role, requester, crafter, gross, itemID, qty, guild)
		local led, now = Ledger(), Now()
		local key = FeeKey(id, crafter, requester)
		local e = led.entries[key]
		if not e then
			-- The seller's fee mail came before any word of the sale: it was his, for this request.
			local early = FeeKey(id, crafter, nil)
			if type(led.entries[early]) == "table" then
				e, led.entries[early] = led.entries[early], nil
				e.key, e.requester = key, requester
				led.entries[key] = e
			end
		end
		if not e then
			local room, why = FeeRoom(led, role, requester, crafter, now)
			if not room then
				ns.Log("craft fee %s not booked: %s", tostring(id), tostring(why))
				return nil, why
			end
			e = { key = key, id = id, crafter = crafter, requester = requester, created = now, paid = 0, by = {}, state = "due" }
			led.entries[key] = e
		end
		e.by = type(e.by) == "table" and e.by or {}
		e.by[role] = e.by[role] or now
		if role == "s" then e.grossS = gross else e.grossB = gross end
		e.gross = math.max(tonumber(e.grossS) or 0, tonumber(e.grossB) or 0)
		e.fee = Requests.FeeBreakdown(e.gross, 0).guildFee
		e.due = e.due or (now + Requests.FEE_DUE)
		if itemID and itemID > 0 then e.item = itemID end
		e.qty = qty or e.qty
		if guild ~= "" and (role == "s" or not e.guild) then e.guild = guild end
		if e.state == "due" and (tonumber(e.paid) or 0) >= e.fee then e.state, e.paidAt = "paid", e.paidAt or now end
		e.heard = now
		Changed()
		return e
	end

	-- A fee mail sent may come back (its receiver returned it, or left it its days): while it may,
	-- the seller's gold mail takes are watched (ArenaMoney's take, flagged returned; no amount on
	-- the watch, so a keeper's book never takes it for the arena's), and Requests.OnMoney asks
	-- Fee.MailReturned of each.
	local function WatchReturn(r)
		local M = ns.ArenaMoney
		if type(M) ~= "table" or type(M.Expect) ~= "function" then return false end
		return M.Expect("craftfee:" .. r.id, { dir = "in", subjectPrefix = FEE_SUBJECT .. r.id })
	end
	local function ForgetReturn(r)
		local M = ns.ArenaMoney
		if type(M) == "table" and type(M.Forget) == "function" then M.Forget("craftfee:" .. r.id) end
	end
	Fee.WatchReturn = WatchReturn

	-- What the desk says of a fee, on a party's copy: the buyer's word was heard; the seller's fee is
	-- paid (its mail in the desk's book) or waived.
	local function ApplyFeeState(r, paid, due, state, from)
		local s = r.settlement
		if s.feeReport then s.feeReport.acked = Now() end
		s.feeDeskPaid, s.feeDeskDue = paid, due
		if Same(r.crafter, ns.me) and (s.feeState == "due" or s.feeState == "mailed") and (state == "paid" or state == "waived") then
			ForgetReturn(r)
			s.feeState, s.feePaidAt = state, Now()
			SettlementAudit(r, "guild-fee-" .. state, from, tostring(paid))
			ns.Print(state == "paid" and L.CRAFT_FEE_PAID_SEEN:format(Coins(paid), r.itemName) or L.CRAFT_FEE_WAIVED_SEEN:format(r.itemName))
			ns.Fire("CRAFT_PRIVILEGE_CHANGED", ns.me)
		end
		Changed()
	end

	-- A party's word of the sale, to the desk: queued once per figure (the buyer's on the crafter's
	-- recorded price, the seller's at completion), never where nothing can take the fee.
	QueueFeeReport = function(r, role, gross)
		local s = r and r.settlement
		gross = Clamp(gross, 1, Requests.PRICE_MAX)
		if not s or s.rail ~= "direct" or not gross or not FeeReceiver() or TestBuild() then return false end
		if Requests.FeeBreakdown(gross, 0).guildFee <= 0 then return false end
		local rep = s.feeReport
		if rep and rep.role == role and rep.gross == gross then return false end
		s.feeReport = { role = role, gross = gross, at = Now() }
		SendFeeReport(r, Now())
		return true
	end
	-- It goes while a desk character is heard online: then again each ASK_GAP, the seller's while his
	-- fee is open (the desk's answer says when it is paid), the buyer's until the desk answered once.
	SendFeeReport = function(r, now)
		local s = r and r.settlement
		local rep = s and s.feeReport
		if not rep then return false end
		if rep.acked and (rep.role ~= "s" or not (s.feeState == "due" or s.feeState == "mailed")) then return false end
		if rep.sentAt and now - rep.sentAt < Requests.ASK_GAP then return false end
		local guild = Same(r.crafter, ns.me) and Clean(GetGuildInfo and GetGuildInfo("player"), 40) or Clean(r.crafterGuild, 40)
		if FeeDesk() then
			-- (A sale of the desk's own, or a purchase: its own ledger.)
			rep.sentAt = now
			local e = BookFeeReport(r.id, rep.role, Full(r.requester), Full(r.crafter), rep.gross, r.itemID or 0, r.quantity, guild)
			if e then ApplyFeeState(r, e.paid or 0, e.due, e.state, ns.me) end
			return e ~= nil
		end
		local desk = OnlineDesk()
		if not desk then return false end
		rep.sentAt = now
		return FeeWord(desk, r.id, "fee", rep.role, r.requester, r.crafter, B36(rep.gross), B36(r.itemID or 0), tostring(r.quantity), guild)
	end

	-- The desk hears a party's word.
	local function TakeFeeReport(id, sender, f)
		if not FeeDesk() then return false, "authority" end
		local role, requester, crafter = f[6], Full(f[7]), Full(f[8])
		local gross, itemID, qty = UnB36(f[9], 1, Requests.PRICE_MAX), UnB36(f[10], 0, 999999999), Clamp(f[11], 1, Requests.QUANTITY_MAX)
		local guild = Clean(f[12], Requests.GUILD_MAX)
		if (role ~= "s" and role ~= "b") or not requester or not crafter or Same(requester, crafter) or not gross or not itemID or not qty
			or not Same(sender, role == "s" and crafter or requester) then return false, "report" end
		-- (The seller's guild in his own word, as the census checks a sender's; the buyer's as he saw it.)
		if guild ~= "" and (not ns.IsFederation(guild) or (role == "s" and not ns.Data.ClaimGuild(sender, guild))) then guild = "" end
		local e, why = BookFeeReport(id, role, requester, crafter, gross, itemID, qty, guild)
		if not e then return false, why end
		FeeWord(sender, id, "feestate", B36(e.fee), B36(e.paid or 0), B36(e.due), e.state)
		return true
	end

	-- A party's copy hears the desk's answer.
	local function TakeFeeState(id, sender, seq, f)
		local r = Requests.Get(id)
		local s = r and r.settlement
		if not s or s.rail ~= "direct" or not Mine(r) or not s.feeReport or not FeeDeskName(sender) then return false, "authority" end
		s.feeSeen = type(s.feeSeen) == "table" and s.feeSeen or {}
		if seq <= (tonumber(s.feeSeen[Lower(sender)]) or 0) then return false, "replay" end
		local fee, paid, due, state = UnB36(f[6], 0, Requests.PRICE_MAX), UnB36(f[7], 0, Requests.PRICE_MAX), UnB36(f[8], 0, 9999999999), f[9]
		if not fee or not paid or not due or (state ~= "due" and state ~= "paid" and state ~= "waived") then return false, "shape" end
		s.feeSeen[Lower(sender)] = seq
		ApplyFeeState(r, paid, due, state, sender)
		return true
	end

	-- A fee mail that reached the desk: booked against that seller's fee for that request (or kept
	-- for it, until the word of the sale comes).
	local function BookFeePayment(id, payer, copper)
		local led, now = Ledger(), Now()
		local e
		for _, x in pairs(led.entries) do
			if type(x) == "table" and x.id == id and Same(x.crafter, payer) and (not e or (x.created or 0) < (e.created or 0)) then e = x end
		end
		if not e then
			if not FeeRoom(led, "mail", nil, payer, now) then
				ns.Log("craft fee mail %s from %s not booked: full", tostring(id), tostring(payer))
				return nil
			end
			local key = FeeKey(id, payer, nil)
			e = { key = key, id = id, crafter = payer, created = now, paid = 0, by = {}, state = "due" }
			led.entries[key] = e
		end
		e.paid = (tonumber(e.paid) or 0) + copper
		e.payments = type(e.payments) == "table" and e.payments or {}
		e.payments[#e.payments + 1] = { copper = copper, t = now }
		while #e.payments > 10 do table.remove(e.payments, 1) end
		if e.state == "due" and e.fee and e.paid >= e.fee then e.state, e.paidAt = "paid", now end
		Changed()
		return e
	end

	local function FeeSubjectId(subject)
		if type(subject) ~= "string" or Secret(subject) then return nil end
		return subject:match("^" .. FEE_SUBJECT .. "([0-9a-z]+)%s*$")
	end

	-- Treasury.Record's question on a keeper's client: is this gold a seller's fee (a mail titled
	-- FEE_SUBJECT and the request)? Then it is the guild's money (in the balance, never a donation or
	-- dues); on the desk it is booked against that seller's fee.
	function Requests.FeeMail(name, copper, subject, how, out)
		local id = FeeSubjectId(subject)
		copper = Clamp(copper, 1, Requests.PRICE_MAX)
		if out or how ~= "mail" or not id or not copper or type(name) ~= "string" or Secret(name) then return false end
		if FeeDesk() then BookFeePayment(id, Full(name), copper) end
		return true
	end

	-- The desk's own click, with a note: a fee paid by hand (a trade, a mail Olympus could not read),
	-- forgiven, or one waiting apart confirmed (the ladder counts it from then: a fresh deadline). The
	-- seller's copy hears paid or waived at his next word. Paid by hand, the seller's gold for it in
	-- this character's book (that amount, since the sale) is the guild's fee there, never a gift or
	-- dues (Treasury.FeeLine).
	function Requests.SettleFee(key, how, note)
		if not FeeDesk() then return false, "authority" end
		local e = Ledger().entries[key]
		note = Clean(note, 80)
		if type(e) ~= "table" or e.state ~= "due" or not e.fee then return false, "state" end
		if (how ~= "paid" and how ~= "waived" and how ~= "confirmed") or note == "" then return false, "shape" end
		local now = Now()
		if how == "confirmed" then
			if Fee.Confirmed(e) then return false, "state" end
			e.checkedBy, e.checkedAt, e.checkNote = ns.me, now, note
			e.due = math.max(tonumber(e.due) or now, now + Requests.FEE_DUE)
			Changed()
			return true
		end
		local owed = math.max(0, e.fee - (tonumber(e.paid) or 0))
		e.state, e.paidAt, e.settledBy, e.note = how, now, ns.me, note
		if how == "paid" then
			e.paid = math.max(tonumber(e.paid) or 0, e.fee)
			local T = ns.Treasury
			local line = owed > 0 and type(T) == "table" and type(T.FeeLine) == "function" and T.FeeLine(e.crafter, owed, e.created or 0)
			ns.Print((line and L.CRAFT_FEE_BOOK_LINE or L.CRAFT_FEE_BOOK_NONE):format(Coins(owed), ns.DisplayName(e.crafter)))
		end
		Changed()
		return true
	end

	-- The fees still owed, as this client holds them (the desk's ledger, or the King's copy of its last
	-- answer), and the debtors ranked: the most gold overdue first, then the most owed. Each debtor's
	-- step on the ladder is the moderation's to take, by hand: late, no new claims (his own client);
	-- a deadline more, a Watch warning; two more, his guild's decision, up to removing him. Only a
	-- confirmed fee (Fee.Confirmed) is ranked; the others wait apart, in toCheck, for the desk.
	local function ByDue(a, b)
		if (a.due or 0) ~= (b.due or 0) then return (a.due or 0) < (b.due or 0) end
		return tostring(a.key) < tostring(b.key)
	end
	function Requests.Debtors(now)
		if not ReadsDebtors(ns.me) then return nil end
		now = now or Now()
		local own = FeeDesk()
		local byName, ranking, entries, toCheck = {}, {}, {}, {}
		for _, e in pairs(own and Ledger().entries or Fee.view.entries) do
			local owed = type(e) == "table" and e.state == "due" and e.fee and e.crafter and math.max(0, e.fee - (tonumber(e.paid) or 0)) or 0
			if owed > 0 and not Fee.Confirmed(e) then
				toCheck[#toCheck + 1] = e
			elseif owed > 0 then
				entries[#entries + 1] = e
				local k = Lower(e.crafter)
				local d = byName[k]
				if not d then
					d = { name = e.crafter, owed = 0, late = 0, count = 0 }
					byName[k], ranking[#ranking + 1] = d, d
				end
				d.owed, d.count, d.guild = d.owed + owed, d.count + 1, d.guild or e.guild
				if now >= (e.due or now) then d.late = d.late + owed end
				if not d.oldest or (e.due or now) < d.oldest then d.oldest = e.due or now end
			end
		end
		for _, d in ipairs(ranking) do d.level = Ladder(d.oldest, now) end
		table.sort(ranking, function(a, b)
			if a.late ~= b.late then return a.late > b.late end
			if a.owed ~= b.owed then return a.owed > b.owed end
			return Lower(a.name) < Lower(b.name)
		end)
		table.sort(entries, ByDue)
		table.sort(toCheck, ByDue)
		-- (The King's copy: how many fees the desk held when it answered, and how many it sent.)
		return { ranking = ranking, entries = entries, toCheck = toCheck, own = own, at = own and now or Fee.view.at, from = Fee.view.from,
			open = not own and Fee.view.open or nil, got = not own and Fee.view.got or nil }
	end

	-- A reader's ask (the King's, a councillor's, the author's): the desk's answer replaces his copy
	-- once it all came (a word each DEBTS_PACE).
	-- The desk answers a reader once each DEBTS_ASK_GAP, so an ask it answered goes again only after
	-- that, forced or not (it would go unanswered, and the page wait for nothing); one it never
	-- answered may go again DEBTS_RETRY on (its answer has come or stopped by then); its own "ask
	-- again in" (debtwait) holds the next one until then. A refusal says how long, in seconds.
	function Fee.AskWait(now)
		local v = Fee.view
		now = now or Now()
		local last = tonumber(v.askedAt)
		local wait = math.max(0, (tonumber(v.waitUntil) or 0) - now)
		if last and v.answeredAsk == last then wait = math.max(wait, last + Requests.DEBTS_ASK_GAP - now) end
		if last and v.asking then wait = math.max(wait, last + Requests.DEBTS_RETRY - now) end
		return wait
	end
	function Requests.AskDebtors(force)
		if FeeDesk() or not ReadsDebtors(ns.me) then return false, "authority" end
		local v, now = Fee.view, Now()
		local wait = Fee.AskWait(now)
		if not force and v.askedAt then wait = math.max(wait, v.askedAt + Requests.DEBTS_ASK_GAP - now) end
		if wait > 0 then return false, "fresh", math.ceil(wait) end
		local desk = OnlineDesk()
		if not desk then return false, "offline" end
		local ok, why = FeeWord(desk, "fees", "debtors")
		if ok then v.askedAt, v.asking, v.from, v.waitUntil = now, { entries = {}, n = 0 }, desk, nil end
		Changed()
		return ok, why
	end

	local function PumpDebts()
		local job = Fee.jobs[1]
		if not job then Fee.pumping = false return end
		if ns.Comm.QueueSize and ns.Comm.QueueSize() > Requests.DEBTS_QUEUE then
			job.stalls = (job.stalls or 0) + 1
			if job.stalls * Requests.DEBTS_PACE >= 60 then table.remove(Fee.jobs, 1) end
		else
			local word = table.remove(job.words, 1)
			if word then FeeWord(job.to, unpack(word)) end
			if #job.words == 0 then table.remove(Fee.jobs, 1) end
		end
		if not Fee.jobs[1] then Fee.pumping = false return end
		ns.After(Requests.DEBTS_PACE, "craft debts", PumpDebts)
	end

	-- The desk answers a reader of the debtors (by the name the server stamps), DEBTS_ASK_GAP apart:
	-- asked sooner, it says when to ask again (an answer still going out says it by itself). The
	-- confirmed fees first, the most overdue first, then those waiting apart, DEBTS_ANSWER_MAX in all.
	local function AnswerDebtors(sender)
		if not FeeDesk() or not ReadsDebtors(sender) then return false, "authority" end
		local now, key = Now(), Lower(sender)
		for _, job in ipairs(Fee.jobs) do if Same(job.to, sender) then return false, "busy" end end
		local since = now - (Fee.answered[key] or -math.huge)
		if since < Requests.DEBTS_ASK_GAP then
			FeeWord(sender, "fees", "debtwait", tostring(math.ceil(Requests.DEBTS_ASK_GAP - since)))
			return false, "rate"
		end
		Fee.answered[key] = now
		local d = Requests.Debtors(now)
		local rows = {}
		for _, e in ipairs(d.entries) do rows[#rows + 1] = e end
		for _, e in ipairs(d.toCheck) do rows[#rows + 1] = e end
		local words = {}
		for i = 1, math.min(#rows, Requests.DEBTS_ANSWER_MAX) do
			local e = rows[i]
			local by = (e.by and e.by.s and "s" or "") .. (e.by and e.by.b and "b" or "")
			by = (by ~= "" and by or "s") .. (e.checkedBy and "c" or "") .. ((tonumber(e.grossB) or 0) > (tonumber(e.grossS) or 0) and e.grossS and "d" or "")
			words[#words + 1] = { e.id, "debt", e.crafter, e.requester or "", B36(e.gross or 0), B36(e.fee), B36(e.paid or 0), B36(e.due or now),
				by, B36(e.item or 0), tostring(e.qty or 0), Clean(e.guild, 30) }
		end
		words[#words + 1] = { "fees", "debtend", tostring(#words), tostring(#rows) }
		Fee.jobs[#Fee.jobs + 1] = { to = sender, words = words }
		if not Fee.pumping then
			Fee.pumping = true
			PumpDebts()
		end
		return true
	end

	-- A reader's copy takes the desk's answer to his own ask only.
	local function TakeDebt(id, sender, verb, f)
		local v = Fee.view.asking
		if not v or FeeDesk() or not ReadsDebtors(ns.me) or not FeeDeskName(sender) or not Same(sender, Fee.view.from)
			or Now() - (tonumber(Fee.view.askedAt) or 0) > 600 then return false, "authority" end
		if verb == "debtwait" then
			-- (Asked too soon: his copy stays as it was, and the page says when to ask again.)
			local wait = Clamp(f[6], 1, Requests.DEBTS_ASK_GAP)
			if not wait then return false, "shape" end
			Fee.view.asking, Fee.view.waitUntil = nil, Now() + wait
			Changed()
			return true
		end
		if verb == "debtend" then
			Fee.view.entries, Fee.view.at, Fee.view.asking = v.entries, Now(), nil
			Fee.view.answeredAsk, Fee.view.got, Fee.view.open = Fee.view.askedAt, v.n, Clamp(f[7], 0, 1000000)
			Changed()
			return true
		end
		if v.n >= Requests.DEBTS_ANSWER_MAX then return false, "cap" end
		local crafter, requester = Full(f[6]), Full(f[7])
		local gross, fee, paid = UnB36(f[8], 0, Requests.PRICE_MAX), UnB36(f[9], 1, Requests.PRICE_MAX), UnB36(f[10], 0, Requests.PRICE_MAX)
		local due, item, qty = UnB36(f[11], 0, 9999999999), UnB36(f[13], 0, 999999999), Clamp(f[14], 0, Requests.QUANTITY_MAX)
		local s, b, c, d = (type(f[12]) == "string" and f[12] or ""):match("^(s?)(b?)(c?)(d?)$")
		local guild = Clean(f[15], Requests.GUILD_MAX)
		if not crafter or not gross or not fee or not paid or not due or not item or not qty or not s or (s == "" and b == "") then return false, "shape" end
		local key = FeeKey(id, crafter, requester)
		v.entries[key] = { key = key, id = id, crafter = crafter, requester = requester, gross = gross, fee = fee, paid = paid, due = due, state = "due",
			by = { s = s ~= "" or nil, b = b ~= "" or nil }, checked = c ~= "" or nil, differ = d ~= "", item = item > 0 and item or nil, qty = qty,
			guild = guild ~= "" and guild or nil }
		v.n = v.n + 1
		return true
	end

	-- The collection's reminder (the desk's or the King's, Collects), by whisper, to a debtor: once a
	-- day at most per debtor, for a confirmed fee alone (one waiting apart may be a sale that never
	-- was). The council and the author read the list; they remind nobody.
	function Requests.RemindDebtor(key)
		local d = Collects(ns.me) and Requests.Debtors()
		if not d then return false, "authority" end
		local e
		for _, x in ipairs(d.entries) do if x.key == key then e = x break end end
		if not e then
			for _, x in ipairs(d.toCheck) do if x.key == key then return false, "unconfirmed" end end
			return false, "state"
		end
		local now, who = Now(), Lower(e.crafter)
		if now - (Fee.reminded[who] or -math.huge) < Requests.REMIND_GAP then return false, "fresh" end
		local ok, why = FeeWord(e.crafter, e.id, "feeremind", B36(math.max(1, e.fee - (tonumber(e.paid) or 0))), B36(e.due or now))
		if ok then
			Fee.reminded[who] = now
			ns.Print(L.CRAFT_FEE_REMINDED:format(ns.DisplayName(e.crafter)))
		end
		return ok, why
	end

	-- The debtor's client hears the reminder: the warning, whatever its own records say.
	local function TakeFeeReminder(id, sender, f)
		if not Collects(sender) or not Bucket(actionBuckets, "remind:" .. Lower(sender), 600, 3) then return false, "authority" end
		local owed, due = UnB36(f[6], 1, Requests.PRICE_MAX), UnB36(f[7], 0, 9999999999)
		if not owed or not due then return false, "shape" end
		local r = Requests.Get(id)
		local s = r and r.settlement
		-- (Its copy tells the desk again where it stands here.)
		if s and Same(r.crafter, ns.me) and s.feeReport then s.feeReport.sentAt = nil end
		ns.Print(L.CRAFT_FEE_REMINDER:format(ns.DisplayName(sender), Coins(owed), DateText(due), ns.DisplayName(FeeReceiver() or sender), FEE_SUBJECT .. id))
		if ns.PlayAlert then ns.PlayAlert("soft", "craft") end
		Changed()
		return true
	end

	-- A reader who is also an officer of the Watch in his guild warns a debtor there: the Watch's own
	-- ladder (its rules check the guild and the roster) takes it from there. Only a ranked debtor
	-- (a confirmed fee) who is late.
	function Fee.Late(name)
		local d = Requests.Debtors()
		for _, x in ipairs(d and d.ranking or {}) do if Same(x.name, name) then return x.late > 0 end end
		return false
	end
	function Requests.WarnDebtor(name)
		local W = ns.Watch
		name = Full(name)
		if not name or not ReadsDebtors(ns.me) or type(W) ~= "table" or type(W.CanManage) ~= "function" or not W.CanManage()
			or type(W.IssueWarning) ~= "function" then return false, "authority" end
		if not Fee.Late(name) then return false, "unconfirmed" end
		return W.IssueWarning(name, L.CRAFT_FEES_WATCH_REASON)
	end

	-- The seller's own client: the fill of the fee mail (the player presses Send; the postage is his).
	function Requests.PayFee(id)
		local r = Requests.Get(id)
		local s = r and r.settlement
		if not s or not Same(r.crafter, ns.me) or not (FeeOpen(s) or s.feeState == "mailed") then return false, "fee" end
		local to = s.feeTo or FeeReceiver()
		if not to then return false, "receiver" end
		local owed = math.max(0, (s.guildFee or 0) - (tonumber(s.feeDeskPaid) or 0))
		if owed <= 0 then return false, "paid" end
		-- (The mail he sends is seen: once it goes, the clock stops.)
		if InstallExchangeHooks then InstallExchangeHooks() end
		local M = ns.ArenaMoney
		if type(M) == "table" and type(M.FillMail) == "function" then return M.FillMail(to, FEE_SUBJECT .. r.id, owed) end
		ns.Print(L.CRAFT_FEE_HOW:format(Coins(owed), ns.DisplayName(to), FEE_SUBJECT .. r.id))
		return "said"
	end

	-- The seller's fee mail sent (his own hooks saw it go, to a desk character, gold enough and no
	-- cash on delivery): the clock stops until the desk's book has it, or a mail's days passed.
	local function FeeMailSent(flow)
		local r = Requests.Get(flow.id)
		local s = r and r.settlement
		if not s or not Same(r.crafter, ns.me) or not (FeeOpen(s) or s.feeState == "mailed") then return end
		local owed = math.max(0, (s.guildFee or 0) - (tonumber(s.feeDeskPaid) or 0))
		if (flow.cod or 0) > 0 or (flow.copper or 0) < owed then
			SettlementAudit(r, "guild-fee-mail-short", ns.me, tostring(flow.copper))
			return
		end
		s.feeState, s.feeMailedAt, s.feeMailedTo = "mailed", flow.t or Now(), flow.partner
		SettlementAudit(r, "guild-fee-mailed", ns.me, tostring(flow.copper))
		WatchReturn(r)
		ns.Fire("CRAFT_PRIVILEGE_CHANGED", ns.me)
		Changed()
	end

	-- The seller's fee mail came back (his take of it, flagged returned: the receiver returned it, or
	-- left it its days): owed again, by a fresh deadline from then (the desk never had it).
	local function FeeMailReturned(id, flow)
		local r = Requests.Get(id)
		local s = r and r.settlement
		if not s or not Same(r.crafter, ns.me) or s.feeState ~= "mailed" or (tonumber(flow.copper) or 0) <= 0 then return false end
		ForgetReturn(r)
		local now = Now()
		s.feeState, s.feeMailedAt, s.feeReturnedAt = "due", nil, now
		s.feeDue = math.max(tonumber(s.feeDue) or now, now + Requests.FEE_DUE)
		Fee.warned[r.id], s.feeWarnedAt = nil, nil
		if s.feeReport then s.feeReport.sentAt = nil end
		SettlementAudit(r, "guild-fee-returned", ns.me, tostring(flow.copper))
		ns.Print(L.CRAFT_FEE_RETURNED:format(r.itemName, Coins(s.guildFee), DateText(s.feeDue), ns.DisplayName(s.feeTo or FeeReceiver() or "?"), FEE_SUBJECT .. r.id))
		ns.Fire("CRAFT_PRIVILEGE_CHANGED", ns.me)
		Changed()
		return true
	end

	-- A sale the buyer never confirmed owes the guild's 6% all the same (the owner's answer: the
	-- seller owes it on a direct sale made through the board, by a deadline): CONFIRM_WAIT after the
	-- delivery the seller recorded, or after the trade in which his addon saw the agreed gold reach
	-- him and the goods leave, unless a party disputed it (its reviewer decides then). On the seller's
	-- own client, on his own figures; the buyer's copy that saw that trade tells the desk of it, as
	-- its confirmation would. The deal itself still waits for the buyer's word.
	local function Arise(r, now)
		local s = r.settlement
		if type(s) ~= "table" or s.rail ~= "direct" or s.dispute or Terminal(r) or not STATES[r.state] or STATES[r.state] < STATES.terms then return false end
		local d = type(s.direct) == "table" and s.direct or {}
		local seenAt = d.gold and d.item and math.max(tonumber(d.goldAt) or now, tonumber(d.itemAt) or now) or nil
		if Same(r.crafter, ns.me) and not s.feeState then
			local recorded = r.state == "delivered" and r.delivery and Same(r.delivery.by, ns.me)
			local at = recorded and tonumber(r.delivery.at) or seenAt
			if not at or now - at < Requests.CONFIRM_WAIT then return false end
			if r.delivery and not ApplyActualDirectSale(r) then return false end
			RegisterGuildFee(r)
			if s.feeState == "due" then
				SettlementAudit(r, "guild-fee-unconfirmed", ns.me, recorded and "delivery" or "trade")
				ns.Print(L.CRAFT_FEE_UNCONFIRMED:format(r.itemName))
			end
			return true
		end
		if Same(r.requester, ns.me) and seenAt and not s.feeReport and now - seenAt >= Requests.CONFIRM_WAIT then
			local price = r.delivery and Same(r.delivery.by, r.crafter) and r.delivery.price or s.gross
			return QueueFeeReport(r, "b", price)
		end
		return false
	end

	-- The seller's warning while his fee is late: once a session, and again each FEE_WARN_GAP.
	local function WarnOverdue(r, now)
		local s = r.settlement
		if not Same(r.crafter, ns.me) or not FeeOpen(s, now) or now < (s.feeDue or now) then return false end
		if Fee.warned[r.id] and now - (tonumber(s.feeWarnedAt) or 0) < Requests.FEE_WARN_GAP then return false end
		Fee.warned[r.id], s.feeWarnedAt = true, now
		-- (The Treasurer's and the King's list has it only once the desk heard of the sale.)
		local listed = type(s.feeReport) == "table" and s.feeReport.acked and L.CRAFT_FEE_OVERDUE_LISTED or ""
		ns.Print(L.CRAFT_FEE_OVERDUE:format(r.itemName, Coins(s.guildFee), DateText(s.feeDue), ns.DisplayName(s.feeTo or FeeReceiver() or "?"), FEE_SUBJECT .. r.id) .. listed)
		if ns.PlayAlert then ns.PlayAlert("soft", "craft") end
		ns.Fire("CRAFT_GUILD_FEE_LATE", r.id, s.guildFee, s.feeDue)
		return true
	end
	Fee.TakeReport, Fee.TakeState, Fee.SubjectId, Fee.MailSent, Fee.WarnOverdue = TakeFeeReport, TakeFeeState, FeeSubjectId, FeeMailSent, WarnOverdue
	Fee.Answer, Fee.TakeDebt, Fee.TakeReminder, Fee.MailReturned, Fee.Arise = AnswerDebtors, TakeDebt, TakeFeeReminder, FeeMailReturned, Arise
end

-- (A real keeper: Treasury.IsKeeper is also true in the author's previews, on his screen only.)
local function SettlementAuthority()
	local W, T = ns.Watch, ns.Treasury
	local keeper = type(T) == "table" and type(T.RealKeeper) == "function" and T.RealKeeper() == true
	local council = ns.IsHighCouncillor and ns.IsHighCouncillor(ns.me) == true
	return keeper or council or (type(W) == "table" and type(W.CanManage) == "function" and W.CanManage() == true)
end

DisputeSettlement = function(r, reason, evidence, by)
	local s = r and r.settlement
	-- Once the seller's payout is under way (or done, or refunded) a dispute cannot reopen the
	-- gold: a payout and a refund are never both owed.
	if not s or s.state == "settled" or s.state == "refunded" or s.state == "payout_pending" or s.state == "cancelled"
		or (s.dispute and s.dispute.state == "open") then return false end
	s.previousState, s.state, s.updated = s.state, "disputed", Now()
	s.dispute = { openedAt = Now(), openedBy = Full(by) or ns.me, reason = Clean(reason, 180), evidence = Clean(evidence, 180),
		state = "open", cureUntil = Now() + Requests.CURE_WINDOW, appealUntil = Now() + Requests.CURE_WINDOW + Requests.APPEAL_WINDOW,
		reviewer = s.rail == "guild" and s.custodian or nil }
	SettlementAudit(r, "disputed", by or ns.me, reason)
	ns.Fire("CRAFT_DISPUTE", r.id, s.dispute)
	Changed(); return true
end

function Requests.OpenDispute(id, reason, evidence)
	local r = Requests.Get(id)
	if not r or not Party(r, ns.me) or Terminal(r) then return false, "state" end
	reason, evidence = Clean(reason, 120), Clean(evidence, 120)
	if reason == "" then return false, "reason" end
	if not DisputeSettlement(r, reason, evidence, ns.me) then return false, "state" end
	local ok, why = SendPrivate(r, "dispute", reason, evidence)
	if r.settlement.rail == "guild" then ToCustodian(r, "dispute", reason, evidence) end
	return ok, why
end

-- The direct rail's human review: a party puts the dispute to a High Councillor or a keeper whom
-- both parties can check, and tells the other party who it is.
function Requests.Escalate(id, reviewer)
	local r = Requests.Get(id)
	local s = r and r.settlement
	local d = s and s.dispute
	reviewer = Full(reviewer)
	if not r or not d or d.state ~= "open" or not Party(r, ns.me) or s.rail ~= "direct" then return false, "state" end
	if not reviewer or Party(r, reviewer) or not RemoteReviewer(reviewer) then return false, "reviewer" end
	if d.reviewer and not Same(d.reviewer, reviewer) then return false, "reviewer" end
	d.reviewer = reviewer
	SettlementAudit(r, "escalated", ns.me, reviewer)
	SendPrivate(r, "escalate", reviewer)
	-- (The case fits one message: the reason and the item's name are cut to what is left.)
	local ok, why = SendMediation(r, reviewer, "case", r.requester, r.crafter, B36(r.itemID or 0), tostring(r.quantity), B36(s.gross),
		ns.Cut(d.reason or "", 60), Clean(r.itemName, 30))
	Changed()
	return ok, why
end

function Requests.AppealDispute(id, text)
	local r = Requests.Get(id)
	local d = r and r.settlement and r.settlement.dispute
	if not r or not d or d.state ~= "open" or not Party(r, ns.me) or Now() > (d.appealUntil or 0) then return false, "state" end
	text = Clean(text, 180)
	d.appeals = d.appeals or {}
	if text == "" or d.appeals[Lower(ns.me)] then return false, "shape" end
	d.appeals[Lower(ns.me)] = { by = ns.me, at = Now(), text = text }
	SettlementAudit(r, "appealed", ns.me, text)
	local ok, why = SendPrivate(r, "appeal", text)
	if d.reviewer then SendMediation(r, d.reviewer, "appeal", text) end
	Changed(); return ok, why
end

-- held: the custodian holds the buyer's gold (his own word, which the parties' copies follow:
-- one of them may not have heard it reach him).
local function ApplyVerdict(r, decision, respondent, debtDue, note, by, held)
	local s = r.settlement
	local d = s.dispute
	d.state, d.decision, d.reviewedBy, d.reviewedAt, d.note = "final", decision, by, Now(), note
	d.respondent = respondent
	if decision == "resume" then
		s.state = s.previousState or (s.rail == "direct" and "awaiting_exchange" or "awaiting_items")
	elseif decision == "refund" and held then
		s.state, s.refundDue = "refund_pending", Now() + Requests.CURE_WINDOW
		s.returnItems = (s.itemQuantity or 0) > 0 and s.itemQuantity or nil
	elseif decision == "refund" then
		-- Nothing of the buyer's is held: the deal ends there, goods (if any) back to the crafter.
		s.state, r.state, r.updated = "cancelled", "cancelled", Now()
		s.returnItems = (s.itemQuantity or 0) > 0 and s.itemQuantity or nil
	elseif decision == "debt" then
		d.debtDue, d.debtState = debtDue, "due"
		if s.rail == "guild" then
			-- A debt is never ruled while the custodian holds the buyer's gold: the custody ends here
			-- (nothing would ever move it again), the crafter's goods (if any) go back to him, and
			-- the debt stays on the ladder.
			s.state, r.state, r.updated = "cancelled", "cancelled", Now()
			s.returnItems = (s.itemQuantity or 0) > 0 and s.itemQuantity or nil
			ForgetMoneyWatch(r)
		else
			s.state = "disputed"
		end
		ns.Fire("CRAFT_DEBT_NOTICE", r.id, respondent, d.debtDue, note)
	else
		s.state, r.state, r.updated = "cancelled", "cancelled", Now()
		ForgetMoneyWatch(r)
	end
	SettlementAudit(r, "dispute-reviewed", by, decision .. ":" .. note)
end

function Requests.ReviewDispute(id, decision, note, respondent)
	if not SettlementAuthority() then return false, "authority" end
	local r = Requests.Get(id)
	local s, d = r and r.settlement, r and r.settlement and r.settlement.dispute
	if not r or not d or d.state ~= "open" then return false, "state" end
	-- An office holder who is a party is still a party; the decision comes from the reviewer the
	-- dispute was put to, and punitive outcomes wait for the promised cure window. Nothing here
	-- removes a member, and only the custodian's own refund moves gold, by his own click.
	if Party(r, ns.me) then return false, "conflict" end
	if not Same(d.reviewer, ns.me) then return false, "reviewer" end
	if decision ~= "resume" and decision ~= "refund" and decision ~= "debt" and decision ~= "cancel" then return false, "decision" end
	note = Clean(note, 120)
	respondent = Full(respondent)
	if note == "" or (decision == "debt" and not Party(r, respondent)) then return false, "shape" end
	if decision == "refund" and not (s.rail == "guild" and Custody(r)) then return false, "custody" end
	if (decision == "refund" or decision == "debt") and Now() < (d.cureUntil or 0) then return false, "cure-window" end
	-- What the custodian holds goes back by a refund, or on by a resume: a cancel or a debt would
	-- leave the buyer's gold with him, owed to nobody.
	local held = s.rail == "guild" and FundsHeld(s)
	if (decision == "cancel" or decision == "debt") and held then return false, "funds" end
	if decision == "cancel" and s.rail == "guild" and (HELD[s.previousState or ""] or (s.itemQuantity or 0) > 0
		or s.previousState == "outbound_sent" or s.previousState == "awaiting_receipt" or s.previousState == "ready_to_settle") then return false, "funds" end
	local debtDue = decision == "debt" and Now() + Requests.CURE_WINDOW or 0
	ApplyVerdict(r, decision, decision == "debt" and respondent or nil, debtDue, note, ns.me, held)
	Tell(r, "verdict", decision, decision == "debt" and respondent or "", B36(debtDue), note, held and "1" or "0")
	Changed(); return true
end

function Requests.RecordDisputeCure(id, note)
	if not SettlementAuthority() then return false, "authority" end
	local r = Requests.Get(id)
	local d = r and r.settlement and r.settlement.dispute
	if not d or d.state ~= "final" or d.debtState ~= "due" or not Same(d.reviewer, ns.me) then return false, "state" end
	note = Clean(note, 120)
	if note == "" then return false, "note" end
	d.debtState, d.curedAt, d.curedBy, d.cureNote = "cured", Now(), ns.me, note
	if d.watchNoticeAt then d.watchCurePending = true end
	Tell(r, "cured", note)
	ns.Fire("CRAFT_PRIVILEGE_CHANGED", d.respondent)
	if d.watchCurePending then ns.Fire("CRAFT_WATCH_CURE_REVIEW", r.id, d.respondent, d.cureNote) end
	Changed()
	return true
end

-- The Watch's officer who reviewed the case warns its respondent once the cure window passed. The
-- Watch's own rules decide the rest (its own guild, its own ladder); no one is removed here.
function Requests.SubmitDisputeWatchNotice(id, note)
	local r, W = Requests.Get(id), ns.Watch
	local d = r and r.settlement and r.settlement.dispute
	if not d or d.state ~= "final" or d.debtState ~= "due" or not d.respondent or not Same(d.reviewer, ns.me) or type(W) ~= "table"
		or type(W.CanManage) ~= "function" or not W.CanManage() or type(W.IssueWarning) ~= "function" then return false, "authority" end
	if not d.debtDue or Now() < d.debtDue then return false, "cure-window" end
	note = Clean(note ~= "" and note or ("Uncured crafting settlement " .. r.id), 80)
	local ok, why = W.IssueWarning(d.respondent, note)
	if ok then d.watchNoticeAt, d.watchNoticeBy = Now(), ns.me end
	return ok, why
end

--------------------------------------------------------------------------
-- The mediated rail (CK): the custodian's view and the parties' mirror of it.
--------------------------------------------------------------------------

local function CustodyItemsReady(r)
	local s = r.settlement
	if s.fundedAt and (s.itemQuantity or 0) == r.quantity and (s.state == "funds_reserved" or s.state == "awaiting_items") then
		s.state, s.updated = "custodian_received", Now()
		SettlementAudit(r, "items-received", ns.me, tostring(s.itemQuantity))
		Tell(r, "items", B36(r.itemID or 0), tostring(s.itemQuantity))
		return true
	end
	return false
end

local function CustodyFunded(r, kind, copper)
	local s = r.settlement
	if s.state ~= "awaiting_funds" or copper ~= s.gross then return false end
	s.state, s.fundedAt, s.updated = "funds_reserved", Now(), Now()
	s.fundEvidence = { kind = kind, t = Now(), observer = ns.me, copper = copper }
	SettlementAudit(r, "funds-reserved", ns.me, kind)
	Tell(r, "funds", kind)
	CustodyItemsReady(r)
	return true
end

local function CustodySettled(r, how)
	local s = r.settlement
	if s.state ~= "payout_pending" then return false end
	s.state, s.settledAt, s.updated = "settled", Now(), Now()
	SettlementAudit(r, "settled", ns.me, how)
	FinishRequest(r, "custodian-payout-" .. tostring(how))
	Tell(r, "payout", how)
	return true
end

local function CustodyRefunded(r, how)
	local s = r.settlement
	if s.state ~= "refund_pending" then return false end
	s.state, s.refundedAt, s.updated = "refunded", Now(), Now()
	r.state, r.updated = "cancelled", Now()
	SettlementAudit(r, "refunded", ns.me, how)
	ForgetMoneyWatch(r)
	Tell(r, "refund", how)
	return true
end

-- A party's cancel, the reviewer's refund or the deadline: whatever is held goes back. (Before
-- the gold is seen, a Wallet reserve the buyer made for this custodian is held all the same: it
-- goes back by his refund, never left reserved.)
local function CustodyCancel(r, by, reason)
	local s = r.settlement
	if s.state == "awaiting_funds" and not FundsHeld(s) then
		s.state, s.updated, r.state, r.updated = "cancelled", Now(), "cancelled", Now()
		s.returnItems = (s.itemQuantity or 0) > 0 and s.itemQuantity or nil
		SettlementAudit(r, "cancelled", by, reason)
		Tell(r, "cancelled", reason)
		if s.returnItems then
			ns.Print(L.CRAFT_RETURN_READY:format(s.returnItems, r.itemName, ns.DisplayName(r.crafter), SUBJECT .. r.id))
		else
			ForgetMoneyWatch(r)
		end
		return true
	end
	if not HELD[s.state] and s.state ~= "awaiting_items" and s.state ~= "awaiting_funds" then return false end
	s.previousState, s.state, s.updated, s.cancelReason = s.state, "refund_pending", Now(), Clean(reason, 80)
	s.refundDue = Now() + Requests.CURE_WINDOW
	s.returnItems = (s.itemQuantity or 0) > 0 and s.itemQuantity or nil
	SettlementAudit(r, "refund-required", by, s.cancelReason)
	Tell(r, "refundpending", s.cancelReason)
	return true
end

local function CustodyDeadline(r, now)
	local s = r.settlement
	if not s or not s.deadline or now < s.deadline or s.overdue or Terminal(r) then return false end
	if s.state == "awaiting_funds" or HELD[s.state] or s.state == "awaiting_items" then
		return CustodyCancel(r, ns.me, "deadline")
	end
	if s.state == "outbound_sent" or s.state == "awaiting_receipt" then
		-- The goods left: nobody's gold moves on a timer. The case waits for a human.
		s.overdue = now
		SettlementAudit(r, "overdue", ns.me, s.state)
		Tell(r, "overdue", s.state)
		return true
	end
	return false
end

-- The custodian's word of where the deal stands, to one party's copy (its catching up).
local function StateWord(r, to)
	local s = r.settlement
	return SendMediation(r, to, "state", s.state, s.fundedAt and "1" or "0", tostring(s.itemQuantity or 0), B36(s.gross))
end

-- Both parties named the same contract; until then, an invite waits (bounded, an hour).
local function TakeInvite(id, sender, f)
	if not KeeperHere() or Requests.GoldGate() then return false, "authority" end
	local gross, net, fee = UnB36(f[6], 0, Requests.PRICE_MAX), UnB36(f[7], 0, Requests.PRICE_MAX), UnB36(f[8], 0, Requests.PRICE_MAX)
	local itemID, quantity, payment = UnB36(f[9], 1, 999999999), Clamp(f[10], 1, Requests.QUANTITY_MAX), CODE_PAY[f[11] or ""]
	local postage, deadline = UnB36(f[12], 0, Requests.PRICE_MAX), UnB36(f[13], 0, 9999999999)
	local requester, crafter, guild = Full(f[14]), Full(f[15]), Clean(f[16], Requests.GUILD_MAX)
	local money = gross and postage and Requests.FeeBreakdown(gross, postage) or nil
	if not money or net ~= money.sellerNet or fee ~= money.guildFee or not itemID or not quantity or not payment or not deadline
		or not requester or not crafter or Same(requester, crafter) or not Party({ requester = requester, crafter = crafter }, sender)
		or not Independent(ns.me, requester, crafter) or guild == "" or not ns.IsFederation(guild) or not ns.Data.ClaimGuild(sender, guild) then
		return false, "contract"
	end
	if payment == "wallet" and not Requests.WalletEscrowAvailable() then return false, "wallet-unsupported" end
	-- The contract is what both parties agreed. (Not the deadline each one wrote: each wrote it on
	-- its own clock when it saw both agree, a second apart as often as not. The custodian's clock
	-- sets the deadline he keeps.)
	local body = table.concat({ f[6], f[7], f[8], f[9], f[10], f[11], f[12], Lower(requester), Lower(crafter) }, ":")
	local r = Requests.Get(id)
	if r and r.settlement then
		-- A contract is taken once. The same invite again changes nothing: the party missed the
		-- word that it was taken, and hears again where the deal stands. Any other is refused.
		if r.inviteBody ~= body or not Custody(r) then return false, "settled" end
		StateWord(r, sender)
		return true, "settled"
	end
	if r and (not Same(r.requester, requester) or Mine(r)) then return false, "identity" end
	-- A bounded number of open contracts naming one player (each one a record this keeper keeps).
	local open = 0
	for _, other in pairs(Store().records) do
		if Custody(other) and not Terminal(other) and (Party(other, requester) or Party(other, crafter)) then open = open + 1 end
	end
	if open >= Requests.CUSTODIES_PER_PARTY then return false, "cap" end
	local invites = Store().invites
	local pending = 0
	for _, p in pairs(invites) do if type(p) == "table" and type(p.by) == "table" and p.by[Lower(sender)] then pending = pending + 1 end end
	local p = invites[id]
	if not (p and p.by and p.by[Lower(sender)]) and pending >= Requests.INVITES_PER_SENDER then return false, "cap" end
	p = type(p) == "table" and p or { at = Now(), by = {} }
	p.by[Lower(sender)] = { body = body, at = Now(), guild = guild }
	invites[id] = p
	local a, b = p.by[Lower(requester)], p.by[Lower(crafter)]
	if not (a and b and a.body == b.body) then return true, "waiting" end
	invites[id] = nil
	local info = ItemInfo(itemID)
	r = r or { id = id, requester = requester, guild = a.guild, created = Now(), expires = Now() + Requests.REQUEST_TTL,
		itemName = info and info.name or ("#" .. itemID), audit = {}, chat = {}, seenActions = {}, seenChat = {} }
	r.crafter, r.itemID, r.quantity, r.state, r.updated, r.inviteBody = crafter, itemID, quantity, "terms", Now(), body
	r.kind, r.materials = r.kind or "c", r.materials or "crafter"
	r.terms = { version = 1, quantity = quantity, total = gross, guildFeeBP = Requests.GUILD_FEE_BP, guildFee = fee, sellerNet = net,
		rail = "guild", payment = payment, custodian = ns.me, postage = postage, agrees = { requester = true, crafter = true } }
	r.settlement = { version = 1, rail = "guild", payment = payment, custodian = ns.me, state = "awaiting_funds",
		gross = gross, guildFeeBP = Requests.GUILD_FEE_BP, guildFee = fee, sellerNet = net,
		postage = postage, guildNet = money.guildNet, postageShortfall = money.postageShortfall,
		created = Now(), updated = Now(), deadline = Now() + Requests.SETTLEMENT_TTL, evidence = {}, seen = {}, audit = {} }
	Store().records[id] = r
	SettlementAudit(r, "custody-taken", ns.me, body)
	InstallMoneyWatch(r)
	-- Both parties hear that the custody exists before the buyer is told where to pay.
	Tell(r, "contract", B36(gross))
	Changed()
	return true, "taken"
end

-- A direct-rail dispute put to us as reviewer.
local function TakeCase(id, sender, seq, f)
	if not SettlementAuthority() then return false, "authority" end
	local requester, crafter = Full(f[6]), Full(f[7])
	local itemID, quantity, gross = UnB36(f[8], 0, 999999999), Clamp(f[9], 1, Requests.QUANTITY_MAX), UnB36(f[10], 0, Requests.PRICE_MAX)
	local reason, itemName = Clean(f[11], 120), Clean(f[12], 40)
	if not requester or not crafter or Same(requester, crafter) or not Party({ requester = requester, crafter = crafter }, sender)
		or Same(ns.me, requester) or Same(ns.me, crafter) or not quantity or not gross or not itemID then return false, "case" end
	local r = Requests.Get(id)
	if r and (Mine(r) or (r.settlement and r.settlement.dispute and not Reviewing(r))) then return false, "case" end
	if r and not Same(r.requester, requester) then return false, "identity" end
	if not (r and r.settlement and r.settlement.dispute) then
		-- A new case (on a card he saw, or not) counts against the open ones only: a case he ruled on
		-- stays in his records (its cure is his to record), and never takes the place of the next one.
		local n = 0
		for _, other in pairs(Store().records) do if Reviewing(other) and other.settlement.dispute.state == "open" then n = n + 1 end end
		if n >= Requests.CASES_MAX then return false, "cap" end
	end
	r = r or { id = id, requester = requester, created = Now(), expires = Now() + Requests.REQUEST_TTL, audit = {}, chat = {}, seenActions = {}, seenChat = {} }
	if r.settlement and r.settlement.dispute then
		r.seenMediation = r.seenMediation or {}
		r.seenMediation[Lower(sender)] = seq
		return true, "known"
	end
	r.crafter, r.itemID, r.quantity, r.itemName, r.state, r.updated = crafter, itemID > 0 and itemID or nil, quantity, itemName ~= "" and itemName or ("#" .. itemID), "in_progress", Now()
	r.settlement = { version = 1, rail = "direct", state = "disputed", gross = gross, audit = {}, evidence = {} }
	r.settlement.dispute = { openedAt = Now(), openedBy = sender, reason = reason, state = "open", reviewer = ns.me,
		cureUntil = Now() + Requests.CURE_WINDOW, appealUntil = Now() + Requests.CURE_WINDOW + Requests.APPEAL_WINDOW }
	r.review = true
	r.seenMediation = { [Lower(sender)] = seq }
	Store().records[id] = r
	SettlementAudit(r, "case-taken", sender, reason)
	Changed()
	return true, "case"
end

local function CustodianHears(r, sender, verb, f)
	local s = r.settlement
	if not Party(r, sender) then return false, "authority" end
	if verb == "ask" then
		-- A party's copy missed a word (it was offline): where the deal stands, to it alone.
		StateWord(r, sender)
		return true
	end
	if verb == "receipt" then
		if not Same(sender, r.requester) or (s.state ~= "outbound_sent" and s.state ~= "awaiting_receipt") then return false, "state" end
		s.state, s.buyerConfirmedAt, s.updated = "ready_to_settle", Now(), Now()
		SettlementAudit(r, "buyer-receipt", sender, "custodian")
	elseif verb == "claimfunds" then
		if not Same(sender, r.requester) then return false, "authority" end
		s.fundClaim = { by = sender, at = Now(), kind = Clean(f[6], 20), receipt = Clean(f[7], 80) }
	elseif verb == "claimitems" then
		if not Same(sender, r.crafter) then return false, "authority" end
		s.itemClaim = { by = sender, quantity = Clamp(f[6], 1, Requests.QUANTITY_MAX), at = Now(), kind = Clean(f[7], 20) }
	elseif verb == "payoutreceipt" then
		if not Same(sender, r.crafter) or not CustodySettled(r, "seller-receipt") then return false, "state" end
	elseif verb == "refundreceipt" then
		if not Same(sender, r.requester) or not CustodyRefunded(r, "buyer-receipt") then return false, "state" end
	elseif verb == "cancel" then
		if not CustodyCancel(r, sender, Clean(f[6], 80)) then return false, "state" end
	elseif verb == "dispute" then
		if not DisputeSettlement(r, Clean(f[6], 120), Clean(f[7], 120), sender) then
			-- Refused (the payout under way, or a dispute already open): the party's copy, which
			-- opened it on its own, hears where the deal stands and leaves it.
			StateWord(r, sender)
			return false, "state"
		end
		-- Both parties' copies hold the dispute he holds, whoever opened it.
		Tell(r, "disputed", Clean(f[6], 100), sender)
	elseif verb == "appeal" then
		local d = s.dispute
		if not d or d.state ~= "open" or Now() > (d.appealUntil or 0) then return false, "state" end
		d.appeals = d.appeals or {}
		d.appeals[Lower(sender)] = d.appeals[Lower(sender)] or { by = sender, at = Now(), text = Clean(f[6], 180) }
	else
		return false, "verb"
	end
	SettlementAudit(r, verb, sender, Clean(f[6], 80))
	Changed(); return true
end

-- A party's copy follows the custodian's word for where the deal stands: forward along the way,
-- or to the refund or the cancel he decided. A word it missed (it was offline) leaves it behind,
-- never stuck; nothing takes it back along the way, or out of an end.
local function Follow(r, theirs)
	local s = r.settlement
	local d, lapsed = s.dispute, false
	if s.state == "disputed" and theirs ~= "disputed" and d and d.state == "open" then
		-- A dispute this copy holds that his own state does not: he refused it (his deal had gone
		-- on, by a word this copy missed) or has not taken it yet. His state is the deal's: it
		-- lapses here, and his "disputed" opens it again once he takes it.
		d.state, s.state, s.updated, lapsed = "lapsed", s.previousState or "awaiting_funds", Now(), true
	end
	if theirs == s.state or FINAL[s.state] then return lapsed end
	if Forward(s.state, theirs) then
		s.state, s.updated = theirs, Now()
		-- The goods reached the custodian: the work is done, whether or not "start" was pressed.
		if CUSTODY_RANK[theirs] >= CUSTODY_RANK.custodian_received and r.state == "terms" then r.state, r.updated = "in_progress", Now() end
		if theirs == "settled" then
			s.settledAt = s.settledAt or Now()
			FinishRequest(r, "custodian-settlement-confirmed")
		end
		return true
	end
	if theirs == "refund_pending" and Refundable(s.state) then
		s.previousState, s.state, s.updated = s.state, "refund_pending", Now()
		return true
	end
	if theirs == "refunded" and s.state ~= "payout_pending" then
		s.state, s.refundedAt, s.updated, r.state, r.updated = "refunded", s.refundedAt or Now(), Now(), "cancelled", Now()
		ForgetMoneyWatch(r)
		return true
	end
	-- (He cancels only while he holds nothing: before the gold, or a dispute's ruling then.)
	if theirs == "cancelled" and (s.state == "awaiting_funds" or (s.state == "disputed" and s.previousState == "awaiting_funds")) then
		s.state, s.updated, r.state, r.updated = "cancelled", Now(), "cancelled", Now()
		ForgetMoneyWatch(r)
		return true
	end
	return false
end

local function PartyHears(r, sender, verb, f)
	local s = r.settlement
	if not s then return false, "settlement" end
	local d = s.dispute
	local fromCustodian = s.rail == "guild" and Same(sender, s.custodian) and CustodianKnown(sender)
	local fromReviewer = d and d.reviewer and Same(sender, d.reviewer) and (fromCustodian or RemoteReviewer(sender))
	if verb == "verdict" or verb == "cured" then
		if not fromReviewer then return false, "authority" end
		if verb == "verdict" then
			local decision, respondent = f[6], Full(f[7])
			if not d or d.state ~= "open" or (decision ~= "resume" and decision ~= "refund" and decision ~= "debt" and decision ~= "cancel")
				or (decision == "debt" and not Party(r, respondent)) or (decision == "refund" and s.rail ~= "guild") then return false, "verdict" end
			local held = f[10] == "1" or (f[10] ~= "0" and FundsHeld(s))
			ApplyVerdict(r, decision, decision == "debt" and respondent or nil, UnB36(f[8], 0, 9999999999) or Now(), Clean(f[9], 120), sender, held)
		else
			if not d or d.state ~= "final" or d.debtState ~= "due" then return false, "state" end
			d.debtState, d.curedAt, d.curedBy, d.cureNote = "cured", Now(), sender, Clean(f[6], 120)
			ns.Fire("CRAFT_PRIVILEGE_CHANGED", d.respondent)
		end
		Changed(); return true
	end
	if not fromCustodian then return false, "authority" end
	if verb == "funds" then
		if not Follow(r, "funds_reserved") then return false, "state" end
		s.fundedAt = s.fundedAt or Now()
	elseif verb == "items" then
		if not Follow(r, "custodian_received") then return false, "state" end
		s.itemQuantity = Clamp(f[7], 1, Requests.QUANTITY_MAX)
	elseif verb == "out" then
		if not Follow(r, "outbound_sent") then return false, "state" end
		s.outboundAt = Now()
	elseif verb == "payoutpending" then
		if not Follow(r, "payout_pending") then return false, "state" end
	elseif verb == "payout" then
		if not Follow(r, "settled") then return false, "state" end
	elseif verb == "refundpending" then
		if not Follow(r, "refund_pending") then return false, "state" end
	elseif verb == "refund" then
		if not Follow(r, "refunded") then return false, "state" end
	elseif verb == "cancelled" then
		if not Follow(r, "cancelled") then return false, "state" end
	elseif verb == "contract" then
		if UnB36(f[6], 0, Requests.PRICE_MAX) ~= s.gross then return false, "contract" end
		s.contractAt = Now()
	elseif verb == "state" then
		-- The custodian's answer to our ask (or to our invite sent again): the contract is his, and
		-- this copy catches up with whatever it missed.
		local theirs, items = f[6], Clamp(f[8], 0, Requests.QUANTITY_MAX)
		if not SETTLEMENT[theirs or ""] or UnB36(f[9], 0, Requests.PRICE_MAX) ~= s.gross then return false, "state" end
		s.contractAt = s.contractAt or Now()
		if f[7] == "1" then s.fundedAt = s.fundedAt or Now() end
		if items and items > 0 then s.itemQuantity = items end
		Follow(r, theirs)
	elseif verb == "overdue" then
		s.overdue = Now()
	elseif verb == "disputed" then
		-- He took a party's dispute: this copy holds it as he does (the other party's word alone
		-- never opens it here), with him as its reviewer.
		if not (d and d.state == "open" and s.state == "disputed")
			and not DisputeSettlement(r, Clean(f[6], 120), "", Full(f[7]) or sender) then return false, "state" end
	else
		return false, "verb"
	end
	s.heardAt = Now()
	SettlementAudit(r, verb, sender, Clean(f[6], 80))
	Changed(); return true
end

local function ReviewerHears(r, sender, verb, f)
	local d = r.settlement and r.settlement.dispute
	if not Party(r, sender) or not d then return false, "authority" end
	if verb ~= "appeal" or d.state ~= "open" or Now() > (d.appealUntil or 0) then return false, "verb" end
	d.appeals = d.appeals or {}
	d.appeals[Lower(sender)] = d.appeals[Lower(sender)] or { by = sender, at = Now(), text = Clean(f[6], 180) }
	SettlementAudit(r, "appealed", sender, Clean(f[6], 180))
	Changed(); return true
end

function Requests.ReceiveMediation(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > Requests.MESSAGE_MAX then return false, "lane" end
	if Unlogged() then return false, "unlogged" end
	local f = ns.Codec.Split(text, "~")
	if f[1] ~= "CK" or f[2] ~= "1" then return false, "version" end
	local id, seq, verb = f[3], Clamp(f[4], 1, 2147483647), f[5]
	sender = Full(sender)
	if type(id) ~= "string" or #id < 3 or #id > 24 or not id:match("^[0-9a-z]+$") or not seq or not sender or Same(sender, ns.me) then return false, "shape" end
	-- (The desk's answer to the King's own ask comes paced, DEBTS_ANSWER_MAX words at most: its own count.)
	if verb == "debt" or verb == "debtend" or verb == "debtwait" then return Fee.TakeDebt(id, sender, verb, f) end
	if not Bucket(actionBuckets, "ck:" .. Lower(sender), 60, Requests.ACTION_PER_MIN) then return false, "rate" end
	if verb == "invite" then return TakeInvite(id, sender, f) end
	if verb == "case" then return TakeCase(id, sender, seq, f) end
	-- The guild's fees: words outside any deal's sequence, each checked by its sender's name.
	if verb == "fee" then return Fee.TakeReport(id, sender, f) end
	if verb == "feestate" then return Fee.TakeState(id, sender, seq, f) end
	if verb == "feeremind" then return Fee.TakeReminder(id, sender, f) end
	if verb == "debtors" then return Fee.Answer(sender) end
	local r = Requests.Get(id)
	if verb == "cancel" and not (r and r.settlement) then
		-- A party ends a deal before this custodian took it: the invite waiting for the other
		-- party's goes, so a late one cannot take a contract nobody wants.
		local p = Store().invites[id]
		if type(p) == "table" and type(p.by) == "table" and p.by[Lower(sender)] then
			Store().invites[id] = nil
			return true, "dropped"
		end
		return false, "record"
	end
	if not r then return false, "record" end
	r.seenMediation = type(r.seenMediation) == "table" and r.seenMediation or {}
	local seen = tonumber(r.seenMediation[Lower(sender)]) or 0
	if seq <= seen or seq > seen + 1000 then return false, seq <= seen and "replay" or "sequence" end
	local ok, why
	if Custody(r) then ok, why = CustodianHears(r, sender, verb, f)
	elseif Reviewing(r) then ok, why = ReviewerHears(r, sender, verb, f)
	elseif Mine(r) then ok, why = PartyHears(r, sender, verb, f)
	else return false, "authority" end
	if ok then r.seenMediation[Lower(sender)] = seq end
	return ok, why
end

-- The custodian's own clicks: what he saw land, the forward, the payout and the refund. Each one
-- prints what to send; Olympus never presses Trade or Send.
function Requests.ReserveWallet(id)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not Same(r.requester, ns.me) or r.state ~= "terms" or not s or s.rail ~= "guild"
		or s.payment ~= "wallet" or s.state ~= "awaiting_funds" or not s.contractAt then return false, "state" end
	-- One reserve per contract: a second click would hold the buyer's gold twice.
	if s.walletReceipt then return false, "duplicate" end
	local gate = Requests.GoldGate()
	if gate then return false, gate end
	local a = EscrowAdapter(s)
	if not a then return false, "wallet-unsupported" end
	local ok, value, why = pcall(a.reserve, r, s)
	if not ok or not value then return false, ok and (why or "reserve") or "adapter" end
	local receipt = Clean(type(value) == "table" and (value.id or value.receipt) or value, 80)
	if receipt == "" then return false, "receipt" end
	s.walletReceipt, s.fundClaimAt = receipt, Now()
	SettlementAudit(r, "wallet-reserved", ns.me, "wallet:" .. receipt)
	-- The custodian confirms the reserve against the Wallet himself before it counts as held.
	ToCustodian(r, "claimfunds", "wallet", receipt)
	Changed()
	return true
end

function Requests.ConfirmWalletReserve(id, receipt)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not s or s.payment ~= "wallet" or s.state ~= "awaiting_funds" or not CustodianAuthority(r) then return false, "state" end
	local a = EscrowAdapter(s)
	if not a or type(a.verify) ~= "function" then return false, "wallet-unsupported" end
	receipt = Clean(receipt or (s.fundClaim and s.fundClaim.receipt), 80)
	local ok, value = pcall(a.verify, r, s, receipt)
	if not ok or value ~= true then return false, "evidence" end
	s.walletReceipt = receipt
	CustodyFunded(r, "wallet", s.gross)
	Changed(); return true
end

function Requests.ConfirmCustodianFunds(id, evidence)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not s or s.payment == "wallet" or s.state ~= "awaiting_funds" or not CustodianAuthority(r) then return false, "authority" end
	evidence = type(evidence) == "table" and evidence or {}
	if tonumber(evidence.copper) ~= s.gross or not Same(evidence.partner, r.requester)
		or (evidence.kind ~= "trade" and evidence.kind ~= "mailTaken") then return false, "evidence" end
	CustodyFunded(r, evidence.kind, s.gross)
	Changed(); return true
end

function Requests.PrepareCustodianForward(id, postage)
	local r = Requests.Get(id)
	local s = r and r.settlement
	postage = Clamp(postage or (ns.ArenaMoney and ns.ArenaMoney.Postage and ns.ArenaMoney.Postage()) or 0, 0, Requests.PRICE_MAX)
	if not r or not s or not postage or not CustodianAuthority(r) or s.state ~= "custodian_received" or not s.fundedAt then return false, "state" end
	local money = Requests.FeeBreakdown(s.gross, postage)
	if money.postageShortfall > 0 then return false, "postage-floor" end
	s.postage, s.guildNet, s.postageShortfall = postage, money.guildNet, money.postageShortfall
	s.state, s.updated = "outbound_prepared", Now()
	s.forward = { to = r.requester, subject = SUBJECT .. r.id, itemID = r.itemID, quantity = r.quantity }
	SettlementAudit(r, "outbound-prepared", ns.me, tostring(postage))
	ns.Print(L.CRAFT_FORWARD_READY:format(r.quantity, r.itemName, ns.DisplayName(r.requester), s.forward.subject))
	Changed(); return Copy(s.forward)
end

-- The seller's own word that the payout reached him, and the buyer's for his refund: what lands on
-- another character of theirs (or in a mail Olympus could not tie to the request) is never seen
-- here, and the custodian's deal would wait for it forever.
function Requests.ConfirmPayout(id)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not s or s.rail ~= "guild" or not Same(r.crafter, ns.me) or s.state ~= "payout_pending" then return false, "state" end
	s.state, s.settledAt, s.updated = "settled", Now(), Now()
	FinishRequest(r, "seller-self-confirmed")
	local ok, why = ToCustodian(r, "payoutreceipt", "self")
	Changed(); return ok, why
end
function Requests.ConfirmRefund(id)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not s or s.rail ~= "guild" or not Same(r.requester, ns.me) or s.state ~= "refund_pending" then return false, "state" end
	s.state, s.refundedAt, s.updated, r.state, r.updated = "refunded", Now(), Now(), "cancelled", Now()
	ForgetMoneyWatch(r)
	local ok, why = ToCustodian(r, "refundreceipt", "self")
	Changed(); return ok, why
end

function Requests.ReleaseSettlement(id)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not s or s.rail ~= "guild" or s.state ~= "ready_to_settle" or not CustodianAuthority(r) then return false, "state" end
	if s.payment == "wallet" then
		local a = EscrowAdapter(s)
		if not a then return false, "wallet-unsupported" end
		local ok, value, why = pcall(a.release, r, s)
		if not ok or not value then return false, ok and (why or "release") or "adapter" end
		s.releaseReceipt = Clean(type(value) == "table" and (value.id or value.receipt) or value, 80)
		s.state = "payout_pending"
		CustodySettled(r, "wallet")
		Changed(); return true
	end
	local D = ns.Debts
	s.payoutInstruction = { to = r.crafter, copper = s.sellerNet, subject = SUBJECT .. r.id }
	-- (Switched off since the contract, the payout is still owed and instructed; only the Arena's
	-- live ledger is not where it goes, as with the guild fee.)
	if not Requests.GoldGate() and type(D) == "table" and type(D.Owe) == "function" then
		-- The custodian's own debt to the seller: the Arena's ledger sees it paid, or late.
		local obligation = D.Owe({ debtor = ns.me, creditor = r.crafter, copper = s.sellerNet, kind = "payout", ref = "C" .. r.id, due = Now() + Requests.CURE_WINDOW })
		s.payoutObligation = obligation and obligation.id or nil
		s.payoutInstruction.obligation = s.payoutObligation
	end
	s.state, s.updated = "payout_pending", Now()
	SettlementAudit(r, "payout-pending", ns.me, tostring(s.sellerNet))
	ns.Print(L.CRAFT_PAYOUT_READY:format(Coins(s.sellerNet), ns.DisplayName(r.crafter), s.payoutInstruction.subject))
	Tell(r, "payoutpending", B36(s.sellerNet))
	Changed(); return true
end

function Requests.RefundSettlement(id)
	local r = Requests.Get(id)
	local s = r and r.settlement
	if not r or not s or s.state ~= "refund_pending" or not CustodianAuthority(r) then return false, "state" end
	if s.payment == "wallet" then
		local a = EscrowAdapter(s)
		if not a then return false, "wallet-unsupported" end
		local ok, value, why = pcall(a.refund, r, s)
		if not ok or not value then return false, ok and (why or "refund") or "adapter" end
		s.refundReceipt = Clean(type(value) == "table" and (value.id or value.receipt) or value, 80)
		CustodyRefunded(r, "wallet")
		Changed(); return true
	end
	if s.refundInstruction then return false, "duplicate" end
	local D = ns.Debts
	s.refundInstruction = { to = r.requester, copper = s.gross, subject = SUBJECT .. r.id }
	if not s.fundedAt then s.refundInstruction.copper = 0 end
	if s.refundInstruction.copper > 0 and not Requests.GoldGate() and type(D) == "table" and type(D.Owe) == "function" then
		local obligation = D.Owe({ debtor = ns.me, creditor = r.requester, copper = s.gross, kind = "refund", ref = "C" .. r.id, due = Now() + Requests.CURE_WINDOW })
		s.refundObligation = obligation and obligation.id or nil
		s.refundInstruction.obligation = s.refundObligation
	end
	SettlementAudit(r, "refund-instructed", ns.me, tostring(s.refundInstruction.copper))
	ns.Print(L.CRAFT_REFUND_READY:format(Coins(s.refundInstruction.copper), ns.DisplayName(r.requester), s.refundInstruction.subject))
	if s.returnItems then
		ns.Print(L.CRAFT_RETURN_READY:format(s.returnItems, r.itemName, ns.DisplayName(r.crafter), SUBJECT .. r.id))
	end
	Changed(); return true
end

--------------------------------------------------------------------------
-- Trade and mail evidence. This client's own trade window and mail (their item IDs and gold),
-- the inbox's gold takes from ArenaMoney's watcher. None of it clicks anything, and on the direct
-- rail none of it changes the deal's state.
--------------------------------------------------------------------------

local function ItemTotal(list, itemID)
	local matching, all = 0, 0
	for _, item in ipairs(type(list) == "table" and list or {}) do
		local id, count = Clamp(item.id, 1, 999999999), Clamp(item.count or 1, 1, Requests.QUANTITY_MAX)
		if id and count then all = all + count; if id == itemID then matching = matching + count end end
	end
	return matching, all
end

local function EvidenceKey(flow)
	local parts = { flow.kind, flow.partner, flow.out and "o" or "i", tostring(flow.copper or 0), tostring(flow.t or Now()) }
	for _, list in ipairs({ flow.itemsOut, flow.itemsIn }) do
		for _, item in ipairs(type(list) == "table" and list or {}) do parts[#parts + 1] = tostring(item.id) .. "x" .. tostring(item.count or 1) end
	end
	return table.concat(parts, ":")
end

local function KeepEvidence(r, flow, confidence)
	r.evidence = type(r.evidence) == "table" and r.evidence or {}
	local key = Clean(flow.key or EvidenceKey(flow), 180)
	for _, e in ipairs(r.evidence) do if e.key == key then return false end end
	local role = Same(ns.me, r.requester) and "requester" or (Same(ns.me, r.crafter) and "crafter" or "custodian")
	r.evidence[#r.evidence + 1] = { key = key, t = flow.t or Now(), observer = ns.me, role = role,
		kind = Clean(flow.kind, 24), partner = Full(flow.partner), copper = tonumber(flow.copper) or 0, out = flow.out == true,
		itemsOut = Copy(flow.itemsOut), itemsIn = Copy(flow.itemsIn), confidence = confidence or "observed", ambiguous = flow.ambiguous or nil,
		cod = (flow.cod or 0) > 0 and flow.cod or nil }
	while #r.evidence > Requests.EVIDENCE_MAX do table.remove(r.evidence, 1) end
	if not r.firstPerformance then
		r.firstPerformance = { role = role, kind = flow.kind, t = flow.t or Now() }
		Audit(r, "first-performance-observed", ns.me, role .. ":" .. tostring(flow.kind))
	else
		Audit(r, "counter-performance-observed", ns.me, role .. ":" .. tostring(flow.kind))
	end
	return true
end

-- The direct rail: annotations only.
local function ObserveDirect(r, flow, outMatch, outAll, inMatch, inAll)
	local s = r.settlement
	local buyer, seller = Same(ns.me, r.requester), Same(ns.me, r.crafter)
	s.direct = type(s.direct) == "table" and s.direct or {}
	local d = s.direct
	if flow.copper > 0 and ((buyer and flow.out and Same(flow.partner, r.crafter)) or (seller and not flow.out and Same(flow.partner, r.requester))) then
		d.copper = (d.copper or 0) + flow.copper
		d.gold, d.goldAt = d.copper >= (s.gross or 0), flow.t or Now()
	end
	local toBuyer = (seller and outAll > 0 and Same(flow.partner, r.requester)) or (buyer and inAll > 0 and Same(flow.partner, r.crafter))
	if toBuyer then
		local match = seller and outMatch or inMatch
		d.itemQuantity = (d.itemQuantity or 0) + match
		d.item, d.itemAt = d.itemQuantity >= r.quantity, flow.t or Now()
		if match < (seller and outAll or inAll) then d.otherItems = true end
	end
	return true
end

-- Gold of the buyer's the deal does not take (twice the total, a part of it, or any after the deal
-- closed) is his: the custodian is told to give it back, and its return is counted.
local function ExtraGold(r, copper)
	local s = r.settlement
	s.extraCopper = (tonumber(s.extraCopper) or 0) + copper
	SettlementAudit(r, "unexpected-gold", ns.me, tostring(copper))
	ns.Print(L.CRAFT_EXTRA_READY:format(Coins(copper), ns.DisplayName(r.requester), SUBJECT .. r.id))
end

-- The custodian: custody follows what he saw reach him, and nothing moves out of order. (Goods go
-- by the flow's lists, what this client gave and what it got; flow.out is the gold's direction.)
local function ObserveCustody(r, flow, outMatch, outAll, inMatch, inAll)
	local s = r.settlement
	local landed = flow.kind == "trade" or flow.kind == "mailTaken"
	-- A mail cash on delivery is a payment the deal never asked for: the crafter's goods the
	-- custodian paid for on taking them (the payout would pay him twice), or goods he sent the
	-- buyer to pay for again. It never moves a custody; he is told, and settles it by hand.
	if (flow.cod or 0) > 0 then
		SettlementAudit(r, "cod-ignored", ns.me, tostring(flow.cod))
		ns.Print(L.CRAFT_COD_IGNORED:format(Coins(flow.cod), SUBJECT .. r.id))
		return true
	end
	if Terminal(r) then
		-- A closed request: whatever still reaches its custodian goes back, and what he gives back
		-- is counted. Nothing else of it moves.
		if flow.copper > 0 and not flow.out and Same(flow.partner, r.requester) and landed then ExtraGold(r, flow.copper) end
		if flow.copper > 0 and flow.out and Same(flow.partner, r.requester) and ExtraOwed(s) > 0 then
			s.extraReturned = (tonumber(s.extraReturned) or 0) + math.min(flow.copper, ExtraOwed(s))
		end
		if Same(flow.partner, r.crafter) and inMatch > 0 and landed then
			s.returnItems = (tonumber(s.returnItems) or 0) + inMatch
			ns.Print(L.CRAFT_RETURN_READY:format(inMatch, r.itemName, ns.DisplayName(r.crafter), SUBJECT .. r.id))
		end
		if Same(flow.partner, r.crafter) and outMatch > 0 and ItemsOwed(s) > 0 then
			s.itemsReturned = (tonumber(s.itemsReturned) or 0) + math.min(outMatch, ItemsOwed(s))
		end
		return true
	end
	if flow.copper > 0 and not flow.out and Same(flow.partner, r.requester) and landed then
		if not CustodyFunded(r, flow.kind, flow.copper) then ExtraGold(r, flow.copper) end
	end
	if Same(flow.partner, r.crafter) and inAll > 0 and landed then
		s.itemQuantity = (s.itemQuantity or 0) + inMatch
		if inMatch < inAll then s.otherItems = (s.otherItems or 0) + (inAll - inMatch) end
		SettlementAudit(r, "items-in", ns.me, tostring(inMatch))
		if s.itemQuantity > r.quantity then
			DisputeSettlement(r, "wrong-quantity", tostring(s.itemQuantity), ns.me)
		else
			CustodyItemsReady(r)
		end
	end
	if Same(flow.partner, r.requester) and outAll > 0 and (flow.kind == "trade" or flow.kind == "mailSent") then
		if (s.state == "outbound_prepared" or s.state == "custodian_received") and outMatch == r.quantity then
			s.state, s.outboundAt, s.updated = "outbound_sent", flow.t or Now(), Now()
			s.outboundEvidence = { observer = ns.me, kind = flow.kind, quantity = outMatch }
			SettlementAudit(r, "outbound-sent", ns.me, flow.kind)
			Tell(r, "out", B36(r.itemID or 0), tostring(outMatch), flow.kind)
		else
			SettlementAudit(r, "forward-unexpected", ns.me, tostring(outMatch))
		end
	end
	if Same(flow.partner, r.crafter) and outMatch > 0 and ItemsOwed(s) > 0 then
		s.itemsReturned = (tonumber(s.itemsReturned) or 0) + math.min(outMatch, ItemsOwed(s))
	end
	if flow.out and flow.copper > 0 then
		if Same(flow.partner, r.crafter) and flow.copper == s.sellerNet and s.state == "payout_pending" and not s.payoutSentAt then
			-- A trade lands at once; a mail lands when the seller takes it (his receipt).
			if flow.kind == "trade" then CustodySettled(r, "trade") else s.payoutSentAt = flow.t or Now() end
		elseif Same(flow.partner, r.requester) and flow.copper == (s.refundInstruction and s.refundInstruction.copper or s.gross)
			and s.state == "refund_pending" and not s.refundSentAt then
			if flow.kind == "trade" then CustodyRefunded(r, "trade") else s.refundSentAt = flow.t or Now() end
		elseif Same(flow.partner, r.requester) and ExtraOwed(s) > 0 then
			s.extraReturned = (tonumber(s.extraReturned) or 0) + math.min(flow.copper, ExtraOwed(s))
		end
	end
	return true
end

-- A party of a mediated request: its own observations are claims for the custodian, or receipts.
local function ObserveParty(r, flow, outMatch, outAll, inMatch, inAll)
	local s = r.settlement
	local buyer, seller = Same(ns.me, r.requester), Same(ns.me, r.crafter)
	if not Same(flow.partner, s.custodian) then return true end
	if buyer and flow.out and flow.copper == s.gross and s.state == "awaiting_funds" then
		s.fundClaim = { by = ns.me, at = flow.t or Now(), kind = flow.kind }
		ToCustodian(r, "claimfunds", flow.kind)
	end
	if seller and outAll > 0 then
		s.itemClaim = { by = ns.me, quantity = outMatch, at = flow.t or Now(), kind = flow.kind }
		ToCustodian(r, "claimitems", tostring(outMatch), flow.kind)
	end
	if buyer and inAll > 0 and inMatch == r.quantity and (flow.cod or 0) == 0 then
		-- Seen in the bags; the buyer still confirms with his own click.
		s.receiptObserved = { at = flow.t or Now(), kind = flow.kind, quantity = inMatch }
	end
	-- The payout landing here is the custodian's own act, whichever of his words this copy missed
	-- on the way (it was offline): it ends the deal here, and he hears it. (The custodian sends the
	-- seller nothing else.) A refund counts only once the copy knows one is owed: the buyer's gold
	-- coming back may as well be a second payment of his given back.
	local landed = flow.kind == "trade" or flow.kind == "mailTaken"
	if seller and not flow.out and landed and flow.copper == s.sellerNet and Forward(s.state, "settled") then
		s.state, s.settledAt, s.updated = "settled", flow.t or Now(), Now()
		FinishRequest(r, "seller-received-payout")
		ToCustodian(r, "payoutreceipt", flow.kind)
	end
	if buyer and not flow.out and landed and flow.copper > 0 and flow.copper == (s.gross or 0) and s.state == "refund_pending" then
		s.state, s.refundedAt, r.state, r.updated = "refunded", flow.t or Now(), "cancelled", Now()
		ForgetMoneyWatch(r)
		ToCustodian(r, "refundreceipt", flow.kind)
	end
	return true
end

function Requests.ObserveExchange(id, flow)
	local r = Requests.Get(id)
	local s = r and r.settlement
	flow = type(flow) == "table" and flow or {}
	flow.partner = Full(flow.partner)
	flow.copper = Clamp(flow.copper or 0, 0, Requests.PRICE_MAX) or 0
	flow.cod = Clamp(flow.cod or 0, 0, Requests.PRICE_MAX) or 0
	if not r or not s or not flow.partner or (not Mine(r) and not Custody(r)) then return false, "access" end
	-- A closed request's custodian still sees what reaches him for it, and what he gives back.
	if Terminal(r) and not (Custody(r) and Party(r, flow.partner)) then return false, "access" end
	if not Party(r, flow.partner) and not Same(s.custodian, flow.partner) then return false, "partner" end
	if not KeepEvidence(r, flow, (flow.itemsOut or flow.itemsIn) and "exact-client-observation" or "gold-observation") then return false, "duplicate" end
	-- One trade with several open deals between the same two players: written down, decides nothing.
	if flow.ambiguous then Changed() return true end
	local outMatch, outAll = ItemTotal(flow.itemsOut, r.itemID)
	local inMatch, inAll = ItemTotal(flow.itemsIn, r.itemID)
	if s.rail == "direct" then ObserveDirect(r, flow, outMatch, outAll, inMatch, inAll)
	elseif Custody(r) then ObserveCustody(r, flow, outMatch, outAll, inMatch, inAll)
	else ObserveParty(r, flow, outMatch, outAll, inMatch, inAll) end
	Changed()
	return true
end

-- The records a flow with this partner may be about: active, ours or in our custody, and a closed
-- one in our custody while it still owes its buyer gold or its crafter goods.
local function Watching(partner)
	local out = {}
	for _, r in pairs(Store().records) do
		local s = r.settlement
		if s and ((Active(r) and (Mine(r) or Custody(r))) or Owing(r) or LateGold(r))
			and (partner == nil or Party(r, partner) or Same(s.custodian, partner)) then out[#out + 1] = r end
	end
	return out
end

local function SubjectId(subject)
	if type(subject) ~= "string" or Secret(subject) or subject:find("^" .. FEE_SUBJECT) then return nil end
	return subject:match("^" .. SUBJECT .. "([0-9a-z]+)")
end

local function LinkItemID(link)
	if type(link) ~= "string" or Secret(link) then return nil end
	return Clamp(link:match("item:(%d+)"), 1, 999999999)
end

local function ItemCount(id)
	local fn = type(C_Item) == "table" and C_Item.GetItemCount or GetItemCount
	if type(fn) ~= "function" then return nil end
	local ok, count = pcall(fn, id)
	if not ok or Secret(count) then return nil end
	return tonumber(count)
end

-- Forever's TradeFrame reads a slot's item ID as the 8th return of GetTradePlayerItemInfo and the
-- 7th of GetTradeTargetItemInfo; the link is a fallback. Slots 1-6 trade; 7 is "will not be traded".
local function TradeItems(target)
	local out = {}
	local info = target and GetTradeTargetItemInfo or GetTradePlayerItemInfo
	local link = target and GetTradeTargetItemLink or GetTradePlayerItemLink
	if type(info) ~= "function" then return out end
	for slot = 1, tonumber(MAX_TRADABLE_ITEMS) or 6 do
		local ok, name, _, count, _, _, _, r7, r8 = pcall(info, slot)
		if ok and type(name) == "string" and not Secret(name) and name ~= "" then
			local id = target and r7 or r8
			id = not Secret(id) and Clamp(id, 1, 999999999) or nil
			if not id and type(link) == "function" then
				local okLink, itemLink = pcall(link, slot)
				id = okLink and LinkItemID(itemLink) or nil
			end
			count = not Secret(count) and Clamp(count or 1, 1, Requests.QUANTITY_MAX) or nil
			if id and count then out[#out + 1] = { id = id, count = count } end
		end
	end
	return out
end

local function TradeMoney(fn)
	if type(fn) ~= "function" then return 0 end
	local ok, v = pcall(fn)
	return ok and not Secret(v) and tonumber(v) or 0
end

local function ExactTradeShow()
	if #Watching() == 0 then exactTrade = nil return end
	local partner = ns.UnitFullName and ns.UnitFullName("NPC") or nil
	exactTrade = type(partner) == "string" and not Secret(partner) and { partner = Full(partner), itemsOut = {}, itemsIn = {}, gave = 0, got = 0 } or nil
end

local function ExactTradeUpdate()
	if not exactTrade then return end
	exactTrade.itemsOut, exactTrade.itemsIn = TradeItems(false), TradeItems(true)
	exactTrade.gave, exactTrade.got = TradeMoney(GetPlayerTradeMoney), TradeMoney(GetTargetTradeMoney)
end

-- Does this trade (net gold in, the goods each way) do what one custody of ours waits for?
local function TradeFits(r, flow, net)
	local s = r.settlement
	local outMatch, inMatch = ItemTotal(flow.itemsOut, r.itemID), ItemTotal(flow.itemsIn, r.itemID)
	if Terminal(r) then
		return Same(flow.partner, r.requester) and ((net > 0 and LateGold(r)) or (net < 0 and -net <= ExtraOwed(s)))
			or Same(flow.partner, r.crafter) and outMatch > 0 and ItemsOwed(s) > 0
	end
	if Same(flow.partner, r.requester) then
		return (net > 0 and net == s.gross and s.state == "awaiting_funds")
			or (outMatch == r.quantity and (s.state == "outbound_prepared" or s.state == "custodian_received"))
			or (net < 0 and s.state == "refund_pending" and -net == (s.refundInstruction and s.refundInstruction.copper or s.gross))
			or (net < 0 and -net <= ExtraOwed(s))
	end
	if Same(flow.partner, r.crafter) then
		local rank = CUSTODY_RANK[s.state]
		return (inMatch > 0 and rank ~= nil and rank <= CUSTODY_RANK.awaiting_items and (s.itemQuantity or 0) + inMatch <= r.quantity)
			or (net < 0 and -net == s.sellerNet and s.state == "payout_pending")
			or (outMatch > 0 and ItemsOwed(s) > 0)
	end
	return false
end

-- One trade with a player in several of our deals. When all of them are custodies of ours, the
-- trade is the one deal it fits (the oldest of equals: the same two players, the same goods and
-- gold); the buyer's gold that fits none is still his, the oldest deal's to give back. Otherwise
-- it is written down for each and decides nothing (ambiguous).
local function TradeTargets(list, flow, net)
	if #list < 2 then return list end
	for _, r in ipairs(list) do if not Custody(r) then return list end end
	local best, buyer
	for _, r in ipairs(list) do
		if TradeFits(r, flow, net) and (not best or (r.created or 0) < (best.created or 0)) then best = r end
		if net > 0 and Same(flow.partner, r.requester) and (not buyer or (r.created or 0) < (buyer.created or 0)) then buyer = r end
	end
	best = best or buyer
	return best and { best } or list
end

local function ExactTradeComplete(a, b)
	local message = type(b) == "string" and b or a
	if type(message) ~= "string" or Secret(message) or not exactTrade or message ~= ERR_TRADE_COMPLETE then return end
	local flow = exactTrade
	exactTrade = nil
	local net = (flow.got or 0) - (flow.gave or 0)
	local list = TradeTargets(Watching(flow.partner), flow, net)
	for _, r in ipairs(list) do
		Requests.ObserveExchange(r.id, { kind = "trade", partner = flow.partner, out = net < 0, copper = math.abs(net),
			itemsOut = flow.itemsOut, itemsIn = flow.itemsIn, t = Now(), ambiguous = #list > 1 or nil,
			key = "trade:" .. tostring(Now()) .. ":" .. tostring(flow.gave) .. ":" .. tostring(flow.got) })
	end
end

local function MailItem(slot, inbox, mailIndex)
	local info = inbox and GetInboxItem or GetSendMailItem
	if type(info) ~= "function" then return nil end
	local ok, name, itemID, _, count
	if inbox then ok, name, itemID, _, count = pcall(info, mailIndex, slot) else ok, name, itemID, _, count = pcall(info, slot) end
	if not ok or type(name) ~= "string" or Secret(name) or name == "" or Secret(itemID) or Secret(count) then return nil end
	local id = Clamp(itemID, 1, 999999999)
	count = Clamp(count or 1, 1, Requests.QUANTITY_MAX)
	return id and count and { id = id, count = count } or nil
end

local function ExactMailSending(to, subject)
	-- A seller's guild fee, to a desk character: its own flow.
	local feeId = Fee.SubjectId(subject)
	if feeId then
		local r = Requests.Get(feeId)
		exactMailOut = r and Same(r.crafter, ns.me) and type(to) == "string" and not Secret(to) and FeeDeskName(to)
			and { fee = true, id = feeId, partner = Full(to), copper = TradeMoney(GetSendMailMoney), cod = TradeMoney(GetSendMailCOD), t = Now() } or nil
		return
	end
	local id = SubjectId(subject)
	local r = id and Requests.Get(id)
	if not r or not (Mine(r) or Custody(r)) or type(to) ~= "string" or Secret(to) then exactMailOut = nil return end
	local items = {}
	for i = 1, tonumber(ATTACHMENTS_MAX_SEND) or 12 do local item = MailItem(i, false) if item then items[#items + 1] = item end end
	exactMailOut = { id = id, partner = Full(to), itemsOut = items, copper = TradeMoney(GetSendMailMoney),
		cod = TradeMoney(GetSendMailCOD), t = Now() }
end

local function ExactMailSent()
	local flow = exactMailOut
	exactMailOut = nil
	if not flow then return end
	if flow.fee then return Fee.MailSent(flow) end
	Requests.ObserveExchange(flow.id, { kind = "mailSent", partner = flow.partner, out = true, copper = flow.copper,
		cod = flow.cod, itemsOut = flow.itemsOut, t = flow.t, key = "mail-sent:" .. flow.id .. ":" .. tostring(flow.t) })
end

-- An attachment taken counts once the mail no longer holds it and the bags hold that many more:
-- never on the bag count alone, which a trade or a loot could explain.
local function ExactInboxTaking(index, attachment)
	if type(index) ~= "number" or type(GetInboxHeaderInfo) ~= "function" then return end
	-- (The header's 6th value is the mail's cash on delivery, as MailFrame.lua reads it.)
	local ok, _, _, sender, subject, _, cod, _, _, _, returned = pcall(GetInboxHeaderInfo, index)
	local id = ok and SubjectId(subject) or nil
	local r = id and Requests.Get(id)
	if not r or type(sender) ~= "string" or Secret(sender) or not (Mine(r) or Custody(r)) then return end
	cod = not Secret(cod) and Clamp(cod or 0, 0, Requests.PRICE_MAX) or 0
	local first, last = attachment or 1, attachment or tonumber(ATTACHMENTS_MAX_RECEIVE) or 16
	for slot = first, last do
		local item = MailItem(slot, true, index)
		if item then exactInbox[#exactInbox + 1] = { id = id, partner = Full(sender), rawSender = sender, subject = subject, index = index,
			slot = slot, item = item, before = ItemCount(item.id), returned = returned and true or false, cod = cod, t = Now() } end
	end
end

local function StillInMail(p)
	if type(GetInboxHeaderInfo) ~= "function" then return false end
	local ok, _, _, sender, subject = pcall(GetInboxHeaderInfo, p.index)
	if not ok or sender ~= p.rawSender or subject ~= p.subject then return false end
	local item = MailItem(p.slot, true, p.index)
	return item ~= nil and item.id == p.item.id and item.count == p.item.count
end

local function ExactInboxChanged()
	for i = #exactInbox, 1, -1 do
		local p = exactInbox[i]
		local after = ItemCount(p.item.id)
		if p.before ~= nil and after ~= nil and after >= p.before + p.item.count and not StillInMail(p) then
			table.remove(exactInbox, i)
			Requests.ObserveExchange(p.id, { kind = p.returned and "mailReturned" or "mailTaken", partner = p.partner, out = false,
				itemsIn = { p.item }, cod = p.cod, t = p.t, key = "mail-taken:" .. p.id .. ":" .. tostring(p.t) .. ":" .. p.slot })
		elseif Now() - p.t > Requests.TAKE_WAIT then
			table.remove(exactInbox, i)
		end
	end
end

InstallExchangeHooks = function()
	if exchangeInstalled or type(ns.RegisterEvent) ~= "function" then return exchangeInstalled end
	exchangeInstalled = true
	ns.RegisterEvent("TRADE_SHOW", function() ns.SafeCall("craft trade", ExactTradeShow) end)
	for _, event in ipairs({ "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE" }) do
		ns.RegisterEvent(event, function() ns.SafeCall("craft trade", ExactTradeUpdate) end)
	end
	ns.RegisterEvent("UI_INFO_MESSAGE", function(a, b) ns.SafeCall("craft trade", ExactTradeComplete, a, b) end)
	-- The window closes before or after "trade complete", depending on the client (Treasury.lua):
	-- this trade is forgotten a little later, not the next one opened meanwhile.
	ns.RegisterEvent("TRADE_CLOSED", function()
		local closing = exactTrade
		ns.After(2, "craft trade", function() if exactTrade == closing then exactTrade = nil end end)
	end)
	ns.RegisterEvent("MAIL_SEND_SUCCESS", function() ns.SafeCall("craft mail", ExactMailSent) end)
	ns.RegisterEvent("MAIL_FAILED", function(itemID) if not itemID then exactMailOut = nil end end)
	ns.RegisterEvent("BAG_UPDATE_DELAYED", function() ns.SafeCall("craft mail", ExactInboxChanged) end)
	ns.RegisterEvent("MAIL_INBOX_UPDATE", function() ns.SafeCall("craft mail", ExactInboxChanged) end)
	if hooksecurefunc then -- gp:mail-hooks
		if SendMail then hooksecurefunc("SendMail", function(to, subject) ns.SafeCall("craft mail", ExactMailSending, to, subject) end) end -- gp:mail-hooks
		if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(i, a) ns.SafeCall("craft mail", ExactInboxTaking, i, a) end) end -- gp:mail-hooks
		if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) ns.SafeCall("craft mail", ExactInboxTaking, i) end) end -- gp:mail-hooks
	end
	return true
end

-- ArenaMoney's gold mail takes: the subject names the request, so a counterparty's gold mail for
-- another deal is never this one's. Trades and sent mail come from the exact watchers above.
function Requests.OnMoney(flow)
	if type(flow) ~= "table" or type(flow.partner) ~= "string" then return end
	-- (A seller's own fee mail come back: Fee.MailReturned.)
	local feeId = flow.kind == "mailReturned" and Fee.SubjectId(flow.subject)
	if feeId then return Fee.MailReturned(feeId, flow) end
	if flow.kind == "mailTaken" or flow.kind == "mailReturned" then
		local id = SubjectId(flow.subject)
		local r = id and Requests.Get(id)
		if r and (Mine(r) or Custody(r)) and (tonumber(flow.copper) or 0) > 0 then
			Requests.ObserveExchange(id, { kind = flow.kind, partner = flow.partner, out = false, copper = flow.copper, t = flow.t,
				key = "mail-gold:" .. id .. ":" .. tostring(flow.t) .. ":" .. tostring(flow.copper) })
		end
	end
end

local function SubscribeMoney()
	if moneySubscribed then return true end
	local M = ns.ArenaMoney
	if type(M) ~= "table" or type(M.Subscribe) ~= "function" then return false end
	M.Subscribe(Requests.OnMoney)
	moneySubscribed = true
	for _, r in pairs(Store().records) do
		if Active(r) or Owing(r) or LateGold(r) then InstallMoneyWatch(r) end
		-- (A fee of ours still owed: its mail, once sent, is seen; one mailed, its mail coming back.)
		local s = type(r.settlement) == "table" and r.settlement
		if s and Same(r.crafter, ns.me) and (FeeOpen(s) or s.feeState == "mailed") then InstallExchangeHooks() end
		if s and Same(r.crafter, ns.me) and FeeHeld(r) and s.feeState == "mailed" then Fee.WatchReturn(r) end
	end
	return true
end

-- Treasury.Record's question on a keeper's client: is this line a request's goods or gold he holds
-- as its custodian? Then it is the parties', never a donation, a payment or the arena's.
function Requests.TreasuryFlow(name, out, copper, subject, item)
	copper = tonumber(copper) or 0
	if type(name) ~= "string" or (copper <= 0 and not item) then return false end
	local now = Now()
	for _, r in pairs(Store().records) do
		local s = r.settlement
		-- An open custody, one closed within the day or still owing, or a mail that names it.
		if Custody(r) and s and (not Terminal(r) or now - (r.updated or now) <= 86400 or Owing(r) or LateGold(r) or SubjectId(subject) == r.id) then
			if item then
				if tonumber(item) == r.itemID and ((not out and Same(name, r.crafter)) or (out and (Same(name, r.requester) or Same(name, r.crafter)))) then return true end
			-- (The buyer's gold, whatever the amount: the deal's, or his to have back, as the custody
			-- counts it. Back to him: the total, the refund, or what of his came beyond it.)
			elseif (not out and Same(name, r.requester))
				or (out and Same(name, r.crafter) and copper == s.sellerNet)
				or (out and Same(name, r.requester) and (copper == s.gross or (s.refundInstruction and copper == s.refundInstruction.copper)
					or copper <= (tonumber(s.extraCopper) or 0))) then
				return true
			end
		end
	end
	return false
end


--------------------------------------------------------------------------
-- Private request chat provider for ChatRooms/ChatWindow.
--------------------------------------------------------------------------

local function RoomId(id) return "craft:" .. id end
local function IdFromRoom(room) return type(room) == "string" and room:match("^craft:([0-9a-z]+)$") or nil end

function Requests.ChatInfo(room)
	local r = Requests.Get(IdFromRoom(room))
	if not r or not Mine(r) or not r.crafter then return nil end
	-- (Its own kind: the chat page underlines a tab by kind, and each request is a room of its own.)
	return { id = room, kind = room, label = ns.Cut(r.itemName, 22), scope = "private", provider = Requests, alwaysOn = true }
end
function Requests.ChatCanAccess(room, name)
	local r = Requests.Get(IdFromRoom(room))
	return r ~= nil and r.crafter ~= nil and Mine(r) and Party(r, name or ns.me) or false
end
function Requests.ChatHistory(room)
	local r = Requests.Get(IdFromRoom(room))
	if not r or not Requests.ChatCanAccess(room, ns.me) then return {} end
	AddContext(r)
	return r.chat or {}
end
function Requests.ChatTabs()
	local out = {}
	for _, r in ipairs(Requests.All()) do
		if Mine(r) and r.crafter and not r.chatRemoved and (Active(r) or Terminal(r)) then
			out[#out + 1] = { kind = RoomId(r.id), id = RoomId(r.id), label = ns.Cut(r.itemName, 18) }
		end
	end
	return out
end

-- Plain words on both ends: Comm strips "|" from a whisper before anyone reads it, so the sender's
-- own copy keeps no link either and both sides show the same line.
local function ChatClean(text)
	text = ns.Codec.SanitizeChat(ns.Codec.Plain(tostring(text or ""))):gsub("~", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(text, 150)
end
local function KeepChat(r, e)
	r.chat = type(r.chat) == "table" and r.chat or {}
	r.chat[#r.chat + 1] = e
	while #r.chat > Requests.CHAT_MAX do table.remove(r.chat, 1) end
	ns.Fire("CHAT_ROOM_CHANGED", RoomId(r.id))
	if not e.mine then ns.Fire("CHAT_ROOM_LINE", RoomId(r.id), e.sender, e.text) end
end

function Requests.ChatSend(room, text)
	local r = Requests.Get(IdFromRoom(room))
	if not r or not Requests.ChatCanAccess(room, ns.me) or not Active(r) then return false, "access" end
	text = ChatClean(text)
	if text == "" then return false, "empty" end
	local now = GetTime and GetTime() or Now()
	r.chatSent = type(r.chatSent) == "table" and r.chatSent or {}
	if now - (r.lastChat or -math.huge) < Requests.CHAT_GAP or Recent(r.chatSent, 60, now) >= Requests.CHAT_PER_MIN then
		ns.Print(L.CHAN_TOO_FAST); return false, "fast"
	end
	r.chatSeq = (tonumber(r.chatSeq) or 0) + 1
	local msg = ("CJ~1~%s~%d~%s"):format(r.id, r.chatSeq, text)
	local to, seq = Other(r), r.chatSeq
	local ok = ns.Comm.Whisper(to, msg, "craft-chat:" .. r.id .. ":" .. seq, false, true, function(sent, why)
		if sent then KeepChat(r, { t = Now(), sender = ns.me, guild = GetGuildInfo("player"), text = text, id = seq, mine = true })
		else ns.Fire("CHAT_ROOM_SEND_FAILED", room, why or "failed", text, 0) end
	end, { owner = Requests, guard = function() local current = Requests.Get(r.id) return current ~= nil and Active(current) and Party(current, to) end })
	if ok then r.lastChat, r.chatSent[#r.chatSent + 1] = now, now end
	return ok and true or false, ok and "ok" or "busy"
end

function Requests.ReceiveChat(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > Requests.MESSAGE_MAX then return false, "lane" end
	if Unlogged() then return false, "unlogged" end
	local id, seq, words = text:match("^CJ~1~([0-9a-z]+)~(%d+)~(.+)$")
	local r = id and Requests.Get(id)
	seq, sender, words = Clamp(seq, 1, 2147483647), Full(sender), ChatClean(words)
	if not r or not seq or not sender or words == "" or not Active(r) or not Party(r, sender) or not Mine(r) or Same(sender, ns.me) then return false, "authority" end
	if Requests.Barred(sender) then return false, "sanction" end
	if not Bucket(chatBuckets, Lower(sender) .. ":" .. id, 60, Requests.CHAT_PER_MIN) then return false, "rate" end
	r.seenChat = type(r.seenChat) == "table" and r.seenChat or {}
	local seen = tonumber(r.seenChat[Lower(sender)]) or 0
	if seq <= seen or seq > seen + 1000 then return false, "replay" end
	r.seenChat[Lower(sender)] = seq
	KeepChat(r, { t = Now(), sender = sender, guild = r.guild, text = words, id = seq })
	return true
end

-- The deal's own room, as every pending conversation opens (ChatRooms.OpenMatter): its tab on the
-- Chat page with the Olympus window in front. By itself (`auto`) once a claim is won, on both
-- parties' clients (in an instance or Busy, a fight, or while the player writes in the Chat page's
-- box, it waits; its sound, the "craft" switch's); then from the request's page, where a tab the
-- player removed comes back.
function Requests.OpenChat(id, auto)
	local r = Requests.Get(id)
	if not r or not Mine(r) or not r.crafter then return false, "state" end
	local R = rawget(ns, "ChatRooms")
	if type(R) ~= "table" or type(R.OpenMatter) ~= "function" then return false, "window" end
	if not auto and r.chatRemoved then
		r.chatRemoved = nil
		ns.Fire("CHAT_ROOMS_CHANGED")
	end
	return R.OpenMatter({ room = RoomId(id), auto = auto == true, kind = "craft", live = function() return Active(Requests.Get(id)) == true end })
end
function Requests.RemoveChat(id)
	local r = Requests.Get(id)
	if not r or not Mine(r) or not Terminal(r) then return false end
	r.chatRemoved = true
	ns.Fire("CHAT_ROOMS_CHANGED")
	return true
end

local provider = {
	Info = Requests.ChatInfo, CanAccess = Requests.ChatCanAccess, History = Requests.ChatHistory,
	Send = Requests.ChatSend, Tabs = Requests.ChatTabs,
	Select = function(room) return Requests.ChatCanAccess(room, ns.me) end,
	IsOpen = function(room) local r = Requests.Get(IdFromRoom(room)) return r ~= nil and not r.chatRemoved end,
	-- Both parties chose this room by publishing and by claiming: it needs no topic consent.
	ChatOn = function() return true end,
}
Requests.ChatProvider = provider
if ns.ChatRooms and ns.ChatRooms.RegisterProvider then ns.ChatRooms.RegisterProvider(provider) end

--------------------------------------------------------------------------
-- Full-page composer and board rows in the existing Crafters destination.
--------------------------------------------------------------------------

local function ParseCopper(text)
	text = tostring(text or ""):lower():gsub("%s+", "")
	local plain = tonumber(text)
	if plain then return Clamp(plain, 0, Requests.PRICE_MAX) end
	if text == "" or text:gsub("%d+[gsc]", "") ~= "" then return nil end
	local gold, silver, copper = tonumber(text:match("(%d+)g")) or 0, tonumber(text:match("(%d+)s")) or 0, tonumber(text:match("(%d+)c")) or 0
	return Clamp(gold * 10000 + silver * 100 + copper, 0, Requests.PRICE_MAX)
end
Requests.ParseCopper = ParseCopper

function Requests.DefaultCustodian(r)
	local T = ns.Treasury
	for _, name in ipairs(type(T) == "table" and type(T.Keepers) == "function" and T.Keepers() or {}) do
		if CustodianKnown(name) and (not r or Independent(Full(name), r.requester, r.crafter)) then return Full(name) end
	end
	return nil
end

function Requests.SelectSettlement(id, rail, payment)
	if payment == "wallet" and not WalletShown() then return false, "wallet-unsupported" end
	if rail == "direct" then return Requests.ConfigureSettlement(id, "direct", payment == "mail" and "mail" or "trade") end
	local custodian = Requests.DefaultCustodian(Requests.Get(id))
	if not custodian then return false, "custodian" end
	return Requests.ConfigureSettlement(id, "guild", payment == "wallet" and "wallet" or (payment == "trade" and "trade" or "mail"), custodian, 0)
end

function Requests.AskManualTerms(id)
	local r = Requests.Get(id)
	if not r or not Same(r.crafter, ns.me) or r.state ~= "accepted" then return false end
	return ns.ShowDialog and ns.ShowDialog("OLYMPUS_CRAFT_PRICE", r.itemName, nil, r) ~= nil
end

function Requests.AskDelivery(id)
	local r = Requests.Get(id)
	if not r or not Same(r.crafter, ns.me) or r.state ~= "in_progress" or not r.settlement or r.settlement.rail ~= "direct" then return false end
	return ns.ShowDialog and ns.ShowDialog("OLYMPUS_CRAFT_DELIVERY", r.itemName, nil, r) ~= nil
end

function Requests.AskDispute(id)
	local r = Requests.Get(id)
	if not r or not Party(r, ns.me) or not r.settlement or Terminal(r) then return false end
	return ns.ShowDialog and ns.ShowDialog("OLYMPUS_CRAFT_DISPUTE", r.itemName, nil, r) ~= nil
end

function Requests.AskEscalate(id)
	local r = Requests.Get(id)
	local d = r and r.settlement and r.settlement.dispute
	if not d or d.state ~= "open" or d.reviewer or not Party(r, ns.me) then return false end
	return ns.ShowDialog and ns.ShowDialog("OLYMPUS_CRAFT_REVIEWER", r.itemName, nil, r) ~= nil
end

function Requests.AskReview(id, decision, respondent)
	local r = Requests.Get(id)
	if not r or not Reviewing(r) then return false end
	return ns.ShowDialog and ns.ShowDialog("OLYMPUS_CRAFT_REVIEW", r.itemName, nil, { id = id, decision = decision, respondent = respondent }) ~= nil
end

local function EditText(self)
	local eb = self and (self.editBox or self.EditBox)
	return eb and eb:GetText() or ""
end
local function EscapeHides(box) box:GetParent():Hide() end

StaticPopupDialogs["OLYMPUS_CRAFT_PRICE"] = {
	text = L.CRAFT_MANUAL_PRICE_PROMPT,
	button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnAccept = function(self, r)
		local unit = ParseCopper(EditText(self))
		if not unit then ns.Print(L.CRAFT_PRICE_INVALID) return true end
		local floor = r.materials ~= "buyer" and ((Requests.Floor(r.itemID) or {}).copper or r.floor or 0) or 0
		return not Requests.ProposeTerms(r.id, nil, unit, floor, { source = L.CRAFT_PRICE_MANUAL }, r.settlementDraft)
	end,
	EditBoxOnEscapePressed = EscapeHides,
}

-- quantity; amount charged; mail, trade or other (a comma separates as well as a semicolon).
function Requests.ParseDelivery(text)
	local quantity, price, method = tostring(text or ""):match("^%s*(%d+)%s*[;,]%s*([^;,]+)%s*[;,]%s*(%a+)%s*$")
	price, method = ParseCopper(price), tostring(method or ""):lower()
	if not quantity or not price or (method ~= "mail" and method ~= "trade" and method ~= "other") then return nil end
	return tonumber(quantity), price, method
end

StaticPopupDialogs["OLYMPUS_CRAFT_DELIVERY"] = {
	text = L.CRAFT_DELIVERY_PROMPT,
	button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnShow = function(self, r)
		local eb = self.editBox or self.EditBox
		if eb and r then eb:SetText(tostring(r.quantity) .. "; " .. tostring(r.terms and r.terms.total or 0) .. "; trade") end
	end,
	OnAccept = function(self, r)
		local quantity, price, method = Requests.ParseDelivery(EditText(self))
		if not quantity then ns.Print(L.CRAFT_DELIVERY_INVALID) return true end
		return not Requests.Deliver(r.id, quantity, price, method)
	end,
	EditBoxOnEscapePressed = EscapeHides,
}

StaticPopupDialogs["OLYMPUS_CRAFT_DISPUTE"] = {
	text = L.CRAFT_DISPUTE_PROMPT,
	button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnAccept = function(self, r)
		local reason = Clean(EditText(self), 120)
		if reason == "" then ns.Print(L.CRAFT_REASON_REQUIRED) return true end
		return not Requests.OpenDispute(r.id, reason, "")
	end,
	EditBoxOnEscapePressed = EscapeHides,
}

StaticPopupDialogs["OLYMPUS_CRAFT_REVIEWER"] = {
	text = L.CRAFT_REVIEWER_PROMPT,
	button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnAccept = function(self, r)
		local ok, why = Requests.Escalate(r.id, EditText(self))
		if not ok then ns.Print(L.CRAFT_REVIEWER_REFUSED:format(tostring(why or "?"))) return true end
	end,
	EditBoxOnEscapePressed = EscapeHides,
}

StaticPopupDialogs["OLYMPUS_CRAFT_REVIEW"] = {
	text = L.CRAFT_REVIEW_PROMPT,
	button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnAccept = function(self, data)
		local ok, why = Requests.ReviewDispute(data.id, data.decision, EditText(self), data.respondent)
		if not ok then ns.Print(L.CRAFT_REVIEW_REFUSED:format(tostring(why or "?"))) return true end
	end,
	EditBoxOnEscapePressed = EscapeHides,
}

StaticPopupDialogs["OLYMPUS_CRAFT_FEE_SETTLE"] = {
	text = L.CRAFT_FEE_SETTLE_PROMPT,
	button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnAccept = function(self, data)
		local ok, why = Requests.SettleFee(data.key, data.how, EditText(self))
		if not ok then ns.Print(L.CRAFT_FEE_SETTLE_REFUSED:format(tostring(why or "?"))) return true end
	end,
	EditBoxOnEscapePressed = EscapeHides,
}

-- Enter answers as the first button does: the definition's own OnAccept, the dialog closing unless
-- it says to stay. (Forever's popup keeps its buttons in a container, GetButton1, and Olympus's own
-- dialog names none: there is no dialog.button1 to click.)
for _, which in ipairs({ "OLYMPUS_CRAFT_PRICE", "OLYMPUS_CRAFT_DELIVERY", "OLYMPUS_CRAFT_DISPUTE", "OLYMPUS_CRAFT_REVIEWER", "OLYMPUS_CRAFT_REVIEW",
	"OLYMPUS_CRAFT_FEE_SETTLE" }) do
	local def = StaticPopupDialogs[which]
	def.EditBoxOnEnterPressed = function(box, data)
		local dialog = box:GetParent()
		if not def.OnAccept(dialog, data) then dialog:Hide() end
	end
end

function Requests.Composing() return composer ~= nil end
function Requests.OpenComposer(prefill)
	composer = { stage = "item", quantity = 1, kind = "all", profession = "all", materials = "crafter", details = "" }
	pageMode = "board"
	if ns.Views and ns.Views.SetFilter then ns.Views.SetFilter("crafters", tostring(prefill or "")) end
	if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("crafters") end
	Changed()
	return true
end
function Requests.CloseComposer()
	composer = nil
	if ns.Views and ns.Views.SetFilter then ns.Views.SetFilter("crafters", "") end
	Changed()
end

local function SelectItem(item, kind)
	if not composer then return end
	composer.item = Copy(item)
	composer.item.kind = kind or item.kind or "craft"
	composer.stage, composer.kind = "details", composer.item.kind
	if composer.item.id then Requests.ObservePrices(composer.item.id); composer.quote = Requests.Quote(composer.item.id) end
	if ns.Views and ns.Views.SetFilter then ns.Views.SetFilter("crafters", "") end
	Changed()
end
Requests.SelectItem = SelectItem

function Requests.SetComposerQuantity(quantity)
	if not composer then return false end
	quantity = Clamp(quantity, 1, Requests.QUANTITY_MAX)
	if not quantity then return false end
	composer.quantity = quantity; Changed(); return true
end
function Requests.SetComposerMaterials(materials)
	if not composer or (materials ~= "crafter" and materials ~= "buyer") then return false end
	composer.materials = materials; Changed(); return true
end
function Requests.SetComposerDetails(text)
	if not composer then return false end
	composer.details = Clean(text, Requests.DETAILS_MAX)
	return true
end

function Requests.PublishDraft()
	if not composer or composer.stage ~= "details" or not composer.item or not ns.IsMember() then return false, "draft" end
	local barred = Requests.Barred()
	if barred then ns.WatchChat.TellBarred(barred) return false, "sanction" end
	if Requests.PrivilegeStatus(ns.me).canRequest == false then return false, "craft-debt" end
	local item, now = composer.item, Now()
	local name = Clean(item.name, Requests.ITEM_NAME_MAX)
	local kind = composer.kind == "gather" and "g" or "c"
	local profession = composer.profession ~= "all" and Clean(composer.profession, 24) or ""
	-- (A gathered material names its gatherers' profession: they are the ones told.)
	if kind == "g" and profession == "" and item.gatherKey then profession = Clean(item.gatherKey, 24) end
	if name == "" or (not item.id and profession == "") then return false, "item" end
	local guild = Clean(GetGuildInfo("player"), Requests.GUILD_MAX)
	if guild == "" or not ns.IsFederation(guild) then return false, "guild" end
	local id = NewId()
	local floor = item.id and Requests.Floor(item.id) or nil
	local r = { id = id, rev = 1, requester = ns.me, guild = guild, itemID = item.id, itemName = name,
		quantity = composer.quantity, details = Clean(composer.details, Requests.DETAILS_MAX), kind = kind,
		profession = profession, materials = composer.materials, state = "open", created = now,
		expires = now + Requests.REQUEST_TTL, updated = now, quote = composer.quote, floor = floor and floor.copper or 0,
		floorSource = floor and floor.source or "", audit = {}, chat = {}, seenActions = {}, seenChat = {} }
	if not Card(r) then return false, "size" end
	Store().records[id] = r
	Audit(r, "published", ns.me)
	composer = nil
	if ns.Views and ns.Views.SetFilter then ns.Views.SetFilter("crafters", "") end
	local ok, why = Publish(r, true)
	Changed()
	return ok and r or false, why
end

local function Money(copper) return Coins(copper) end
local function StateLabel(state) return rawget(L, "CRAFT_REQUEST_STATE_" .. tostring(state):upper()) or tostring(state) end
local function SettlementLabel(state) return rawget(L, "CRAFT_SETTLEMENT_" .. tostring(state):upper()) or tostring(state) end
local function GateLabel(why) return rawget(L, "CRAFT_GATE_" .. tostring(why):upper()) or L.CRAFT_GATE_ARENA end

function Requests.ComposerLines()
	local c = composer
	if not c then return {} end
	local lines = { { header = true, text = L.CRAFT_REQUEST_COMPOSER },
		{ text = Gold(L.CRAFT_REQUEST_BACK), onClick = Requests.CloseComposer } }
	if c.stage == "item" then
		local function choose(field, value, reset)
			return function() c[field] = value; if reset then c[reset] = nil end; Changed() end
		end
		lines[#lines + 1] = { text = L.CRAFT_REQUEST_ITEM_SEARCH, input = {
			text = ns.Views and ns.Views.Filter("crafters") or "", onChange = function(text) ns.Views.SetFilter("crafters", text) end } }
		lines[#lines + 1] = { nav = {
			{ text = L.CRAFT_FILTER_ALL, selected = c.kind == "all", onClick = function() c.kind = "all" Changed() end },
			{ text = L.CRAFT_FILTER_CRAFTED, selected = c.kind == "craft", onClick = function() c.kind = "craft" Changed() end },
			{ text = L.CRAFT_FILTER_GATHERED, selected = c.kind == "gather", onClick = function() c.kind = "gather" Changed() end },
		} }
		-- (The professions of what the composer knows: ours, the board's lists we were sent, the gatherers'.)
		local professions, seenProf = {}, {}
		local known = Requests.KnownItems()
		for _, item in ipairs(known) do
			if c.kind == "all" or item.kind == c.kind then
				for key, label in pairs(item.professions or {}) do
					if not seenProf[key] then seenProf[key] = true; professions[#professions + 1] = { key = key, label = label } end
				end
			end
		end
		table.sort(professions, function(a, b) return ns.Fold(a.label) < ns.Fold(b.label) end)
		if #professions > 0 then
			local nav = { { text = L.CRAFT_FILTER_ALL_PROFESSIONS, selected = c.profession == "all", onClick = choose("profession", "all") } }
			for _, option in ipairs(professions) do nav[#nav + 1] = { text = option.label, selected = c.profession == option.key, onClick = choose("profession", option.key) } end
			lines[#lines + 1] = { text = Grey(L.CRAFT_FILTER_PROFESSION), nav = nav }
		end
		local typeNames, subtypeNames = {}, {}
		for _, one in ipairs(known) do
			if one.itemType then typeNames[one.itemType] = true end
			if one.subType and (not c.itemType or one.itemType == c.itemType) then subtypeNames[one.subType] = true end
		end
		local types = {}; for name in pairs(typeNames) do types[#types + 1] = name end; table.sort(types)
		if #types > 0 then
			local nav = { { text = L.CRAFT_FILTER_ALL_TYPES, selected = not c.itemType, onClick = choose("itemType", nil, "subType") } }
			for _, name in ipairs(types) do nav[#nav + 1] = { text = name, selected = c.itemType == name, onClick = choose("itemType", name, "subType") } end
			lines[#lines + 1] = { text = Grey(L.CRAFT_FILTER_TYPE), nav = nav }
		end
		local subtypes = {}; for name in pairs(subtypeNames) do subtypes[#subtypes + 1] = name end; table.sort(subtypes)
		if #subtypes > 0 then
			local nav = { { text = L.CRAFT_FILTER_ALL_SUBTYPES, selected = not c.subType, onClick = choose("subType", nil) } }
			for _, name in ipairs(subtypes) do nav[#nav + 1] = { text = name, selected = c.subType == name, onClick = choose("subType", name) } end
			lines[#lines + 1] = { text = Grey(L.CRAFT_FILTER_SUBTYPE), nav = nav }
		end
		local q = ns.Views and ns.Views.Filter("crafters") or ""
		local found = Requests.SearchItems(q, { kind = c.kind, profession = c.profession, itemType = c.itemType, subType = c.subType })
		for i = 1, math.min(#found, 30) do
			local item = found[i]
			local profs = {}; for _, label in pairs(item.professions or {}) do profs[#profs + 1] = label end; table.sort(profs)
			lines[#lines + 1] = { text = Gold(item.name), right = Grey(table.concat(profs, ", ") .. (item.cacheMiss and (" · " .. L.CRAFT_REQUEST_CACHE_MISS) or "")),
				onClick = function() SelectItem(item, item.kind) end }
		end
		local directID = tonumber(tostring(q):match("item:(%d+)"))
		local direct = directID and ItemInfo(directID)
		if q ~= "" and #found == 0 then
			-- (A link's own name, between its brackets: never its colour code or its item string.)
			local name = direct and direct.name or Clean(tostring(q):match("|h%[(.-)%]|h") or q, Requests.ITEM_NAME_MAX)
			if directID and not direct and type(C_Item) == "table" and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, directID) end
			lines[#lines + 1] = { text = Gold(L.CRAFT_REQUEST_USE_FALLBACK:format(name)),
				right = Grey(direct and (direct.itemType or "") or L.CRAFT_REQUEST_CACHE_MISS),
				onClick = function() SelectItem(direct or { id = directID, name = name, cacheMiss = true }, c.kind == "gather" and "gather" or "craft") end }
		end
		lines[#lines + 1] = { text = Grey(L.CRAFT_REQUEST_CATALOGUE_LIMIT) }
		return lines, L.CRAFT_REQUEST_COMPOSER, L.CRAFT_REQUEST_CATALOGUE_LIMIT
	end
	local item = c.item
	lines[#lines + 1] = { header = true, text = item.name, right = item.id and ("#" .. item.id) or Grey(L.CRAFT_REQUEST_NAME_ONLY) }
	lines[#lines + 1] = { nav = {
		{ text = "-", onClick = function() Requests.SetComposerQuantity(c.quantity - 1) end },
		{ text = L.CRAFT_REQUEST_QUANTITY:format(c.quantity), selected = true },
		{ text = "+", onClick = function() Requests.SetComposerQuantity(c.quantity + 1) end },
	} }
	lines[#lines + 1] = { nav = {
		{ text = L.CRAFT_MATERIALS_CRAFTER, selected = c.materials == "crafter", onClick = function() Requests.SetComposerMaterials("crafter") end },
		{ text = L.CRAFT_MATERIALS_BUYER, selected = c.materials == "buyer", onClick = function() Requests.SetComposerMaterials("buyer") end },
	} }
	local quote = c.quote
	if quote then
		local sample = { quantity = c.quantity, materials = c.materials, itemID = item.id, quote = quote }
		local suggested = Requests.SuggestTerms(sample, quote)
		lines[#lines + 1] = { text = L.CRAFT_QUOTE_REFERENCE:format(Money(quote.reference)),
			right = Grey(L.CRAFT_QUOTE_SOURCE:format(quote.source, ns.Ago(quote.observedAt), quote.method)) }
		if suggested then lines[#lines + 1] = { text = Green(L.CRAFT_QUOTE_GUILD:format(Money(suggested.unit), Money(suggested.total))),
			right = Grey(L.CRAFT_QUOTE_DISCOUNT:format(math.floor(suggested.discountBP / 100), Money(suggested.floor))) } end
	else
		lines[#lines + 1] = { text = Grey(L.CRAFT_QUOTE_MANUAL) }
	end
	lines[#lines + 1] = { text = L.CRAFT_REQUEST_DETAILS, input = { text = c.details, onChange = Requests.SetComposerDetails,
		maxLetters = Requests.DETAILS_MAX } }
	lines[#lines + 1] = { text = Green(L.CRAFT_REQUEST_PUBLISH), onClick = Requests.PublishDraft }
	return lines, L.CRAFT_REQUEST_COMPOSER, L.CRAFT_REQUEST_COMPOSER_ABOUT
end

local function Relevant(r)
	if pageMode == "mine" then return Same(r.requester, ns.me) and not Terminal(r) end
	if pageMode == "accepted" then return Same(r.crafter, ns.me) and not Terminal(r) end
	if pageMode == "history" then return Mine(r) and Terminal(r) end
	if pageMode == "duty" then return Custody(r) or Reviewing(r) end
	-- The board: open cards. Someone else's taken card is nobody's business here.
	return r.state == "open"
end

local function DutyLines(lines, r)
	local s = r.settlement
	local d = s and s.dispute
	if CustodianAuthority(r) then
		if WalletShown() and s.state == "awaiting_funds" and s.payment == "wallet" and s.fundClaim then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_VERIFY_WALLET), onClick = function() Requests.ConfirmWalletReserve(r.id) end } end
		if s.state == "custodian_received" then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_PREPARE_FORWARD), onClick = function() Requests.PrepareCustodianForward(r.id) end } end
		if s.state == "ready_to_settle" then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_RELEASE_PAYOUT), onClick = function() Requests.ReleaseSettlement(r.id) end } end
		if s.state == "refund_pending" and not s.refundInstruction then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_PREPARE_REFUND), onClick = function() Requests.RefundSettlement(r.id) end } end
	end
	-- What is still his to give back, however the deal ended.
	if Custody(r) and ExtraOwed(s) > 0 then
		lines[#lines + 1] = { indent = 2, text = L.CRAFT_EXTRA_LINE:format(Money(ExtraOwed(s)), ns.DisplayName(r.requester)), right = Grey(SUBJECT .. r.id) }
	end
	if Custody(r) and ItemsOwed(s) > 0 then
		lines[#lines + 1] = { indent = 2, text = L.CRAFT_RETURN_LINE:format(ItemsOwed(s), r.itemName, ns.DisplayName(r.crafter)), right = Grey(SUBJECT .. r.id) }
	end
	if d and d.state == "open" and Reviewing(r) then
		lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_DISPUTE_LINE:format(ns.DisplayName(d.openedBy), d.reason ~= "" and d.reason or "-")) }
		lines[#lines + 1] = { indent = 1, nav = {
			{ text = L.CRAFT_REVIEW_RESUME, onClick = function() Requests.AskReview(r.id, "resume") end },
			{ text = L.CRAFT_REVIEW_DEBT_BUYER, onClick = function() Requests.AskReview(r.id, "debt", r.requester) end },
			{ text = L.CRAFT_REVIEW_DEBT_SELLER, onClick = function() Requests.AskReview(r.id, "debt", r.crafter) end },
			{ text = s.rail == "guild" and L.CRAFT_REVIEW_REFUND or L.CRAFT_REVIEW_CANCEL, onClick = function() Requests.AskReview(r.id, s.rail == "guild" and "refund" or "cancel") end },
		} }
	end
end

local function DetailLines(lines, r)
	lines[#lines + 1] = { indent = 1, text = Grey(r.details ~= nil and r.details ~= "" and r.details or L.CRAFT_REQUEST_NO_DETAILS) }
	if r.quote then lines[#lines + 1] = { indent = 1, text = L.CRAFT_QUOTE_REFERENCE:format(Money(r.quote.reference)),
		right = Grey(L.CRAFT_QUOTE_SOURCE:format(r.quote.source or L.CRAFT_QUOTE_PUBLISHED, ns.Ago(r.quote.observedAt), r.quote.method or "")) } end
	if r.suggestedTerms then local t = r.suggestedTerms; lines[#lines + 1] = { indent = 1,
		text = Green(L.CRAFT_QUOTE_GUILD:format(Money(t.unit), Money(t.total))),
		right = Grey(L.CRAFT_QUOTE_DISCOUNT:format(math.floor(t.discountBP / 100), Money(t.floor))) } end
	if r.terms then
		local t = r.terms
		lines[#lines + 1] = { indent = 1, text = L.CRAFT_TERMS_LINE:format(t.mode == "buyer" and L.CRAFT_MATERIALS_BUYER or L.CRAFT_MATERIALS_CRAFTER, t.quantity, Money(t.unit or 0), Money(t.total)),
			right = Grey(L.CRAFT_TERMS_SOURCE:format(t.source and t.source ~= "" and t.source or L.CRAFT_PRICE_MANUAL, (t.quoteAt or 0) > 0 and ns.Ago(t.quoteAt) or L.CRAFT_PRICE_MANUAL)) }
		if t.payment ~= "wallet" or WalletShown() then
			lines[#lines + 1] = { indent = 1, text = L.CRAFT_SETTLEMENT_LINE:format(t.rail == "guild" and L.CRAFT_RAIL_GUILD or L.CRAFT_RAIL_DIRECT, rawget(L, "CRAFT_PAY_" .. tostring(t.payment):upper()) or tostring(t.payment), Money(t.guildFee or 0), Money(t.sellerNet or t.total)) }
		end
	end
	local settlement = r.settlement
	if settlement then lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_SETTLEMENT_STATE:format(SettlementLabel(settlement.state))),
		right = settlement.custodian and Grey(ns.DisplayName(settlement.custodian)) or nil } end
	if settlement and settlement.rail == "direct" and settlement.feeState then Fee.Detail(lines, r) end
	if settlement and settlement.forward and settlement.state == "outbound_prepared" then
		lines[#lines + 1] = { indent = 2, text = L.CRAFT_FORWARD_LINE:format(settlement.forward.quantity, r.itemName, ns.DisplayName(settlement.forward.to)), right = Grey(settlement.forward.subject) }
	end
	if settlement and settlement.payoutInstruction and settlement.state == "payout_pending" then
		lines[#lines + 1] = { indent = 2, text = L.CRAFT_PAYOUT_LINE:format(Money(settlement.payoutInstruction.copper), ns.DisplayName(settlement.payoutInstruction.to)), right = Grey(settlement.payoutInstruction.subject) }
	end
	if settlement and settlement.refundInstruction and settlement.state == "refund_pending" then
		lines[#lines + 1] = { indent = 2, text = L.CRAFT_REFUND_LINE:format(Money(settlement.refundInstruction.copper), ns.DisplayName(settlement.refundInstruction.to)), right = Grey(settlement.refundInstruction.subject) }
	end
	if r.delivery then lines[#lines + 1] = { indent = 1, text = L.CRAFT_DELIVERY_LINE:format(r.delivery.quantity, Money(r.delivery.price), r.delivery.method),
		right = Grey(r.delivery.validation or r.delivery.confidence or "") } end
	if r.firstPerformance and not Terminal(r) then lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_WAIT_COUNTER:format(r.firstPerformance.role)) } end
	if r.state == "open" and not Same(r.requester, ns.me) then
		lines[#lines + 1] = { indent = 1, text = Gold(r.claimPending and L.CRAFT_CLAIM_PENDING or L.CRAFT_ACCEPT), onClick = not r.claimPending and function() Requests.Accept(r.id) end or nil }
	elseif r.state == "open" and Same(r.requester, ns.me) then
		lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_CANCEL), onClick = function() Requests.Cancel(r.id, "") end }
	elseif r.crafter and Mine(r) then
		lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_OPEN_CHAT), onClick = function() Requests.OpenChat(r.id) end }
		if Same(r.crafter, ns.me) and r.state == "accepted" and not r.terms then
			local draft = r.settlementDraft or { rail = "direct", payment = "trade" }
			local custodian = Requests.DefaultCustodian(r)
			local gate = Requests.GoldGate()
			local paymentOptions = {
				{ text = L.CRAFT_RAIL_DIRECT_TRADE, selected = draft.rail == "direct" and draft.payment == "trade", onClick = function() Requests.SelectSettlement(r.id, "direct", "trade") end },
				{ text = L.CRAFT_RAIL_DIRECT_MAIL, selected = draft.rail == "direct" and draft.payment == "mail", onClick = function() Requests.SelectSettlement(r.id, "direct", "mail") end },
				{ text = L.CRAFT_RAIL_GUILD, selected = draft.rail == "guild" and draft.payment ~= "wallet", onClick = not gate and custodian and function() Requests.SelectSettlement(r.id, "guild", "mail") end or nil },
			}
			if WalletShown() then paymentOptions[#paymentOptions + 1] = { text = L.CRAFT_RAIL_WALLET, selected = draft.payment == "wallet",
				onClick = not gate and custodian and Requests.WalletEscrowAvailable() and function() Requests.SelectSettlement(r.id, "guild", "wallet") end or nil } end
			lines[#lines + 1] = { indent = 1, nav = paymentOptions }
			if gate then lines[#lines + 1] = { indent = 1, text = Grey(GateLabel(gate)) } end
			if r.suggestedTerms then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_USE_SUGGESTED), onClick = function() Requests.UseSuggestedTerms(r.id) end } end
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_MANUAL_PRICE), onClick = function() Requests.AskManualTerms(r.id) end }
		end
		if r.state == "accepted" and r.terms then
			local role = Same(r.requester, ns.me) and "requester" or "crafter"
			if not (r.terms.agrees and r.terms.agrees[role]) then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_CONFIRM_TERMS), onClick = function() Requests.ConfirmTerms(r.id) end } end
		end
		if Same(r.crafter, ns.me) and r.state == "terms" then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_START), onClick = function() Requests.Start(r.id) end } end
		if Same(r.crafter, ns.me) and r.state == "in_progress" and settlement and settlement.rail == "direct" then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_MARK_DELIVERED), onClick = function() Requests.AskDelivery(r.id) end }
		end
		if WalletShown() and Same(r.requester, ns.me) and settlement and settlement.rail == "guild" and settlement.payment == "wallet" and settlement.state == "awaiting_funds" and settlement.contractAt and not settlement.walletReceipt then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_RESERVE_WALLET), onClick = function() Requests.ReserveWallet(r.id) end }
		end
		if Same(r.requester, ns.me) and settlement and settlement.rail == "guild" and settlement.payment ~= "wallet" and settlement.state == "awaiting_funds" and settlement.contractAt then
			lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_PAY_CUSTODIAN:format(Money(settlement.gross), ns.DisplayName(settlement.custodian), SUBJECT .. r.id)) }
		end
		if Same(r.requester, ns.me) and ((r.state == "delivered" and settlement and settlement.rail == "direct" and r.delivery and Same(r.delivery.by, r.crafter))
			or (settlement and settlement.rail == "guild" and (settlement.state == "outbound_sent" or settlement.state == "awaiting_receipt"
				or (settlement.receiptObserved and Forward(settlement.state, "ready_to_settle"))))) then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_CONFIRM_DELIVERY), onClick = function() Requests.ConfirmDelivery(r.id) end }
		end
		-- The seller's word that the payout reached him, the buyer's for his refund.
		if Same(r.crafter, ns.me) and settlement and settlement.rail == "guild" and settlement.state == "payout_pending" then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_CONFIRM_PAYOUT), onClick = function() Requests.ConfirmPayout(r.id) end }
		end
		if Same(r.requester, ns.me) and settlement and settlement.rail == "guild" and settlement.state == "refund_pending" then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_CONFIRM_REFUND), onClick = function() Requests.ConfirmRefund(r.id) end }
		end
		if settlement and not Terminal(r) and not (settlement.dispute and settlement.dispute.state == "open") then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_OPEN_DISPUTE), onClick = function() Requests.AskDispute(r.id) end }
		end
		if settlement and settlement.dispute and settlement.dispute.state == "open" and settlement.rail == "direct" and not settlement.dispute.reviewer then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_ESCALATE), onClick = function() Requests.AskEscalate(r.id) end }
		end
		if not Terminal(r) and r.state ~= "delivered" and not r.delivery then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_CANCEL), onClick = function() Requests.Cancel(r.id, "") end }
		end
		if Terminal(r) and not r.chatRemoved then lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_REMOVE_CHAT), onClick = function() Requests.RemoveChat(r.id) end } end
	end
	if settlement and (Custody(r) or Reviewing(r)) then DutyLines(lines, r) end
end

-- A completed direct sale's guild fee, on its record: the seller's to pay, with the mail's
-- fill; the buyer's copy only says it is the seller's.
function Fee.Detail(lines, r)
	local s, now = r.settlement, Now()
	local fee = s.guildFee or 0
	if s.feeState == "advisory" then lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_FEE_ADVISORY:format(Money(fee))) } return end
	if s.feeState == "crafter" then lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_FEE_SELLERS:format(Money(fee))) } return end
	if s.feeState == "paid" then lines[#lines + 1] = { indent = 1, text = Green(L.CRAFT_FEE_PAID:format(Money(fee))) } return end
	if s.feeState == "waived" then lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_FEE_WAIVED) } return end
	if not Same(r.crafter, ns.me) then return end
	local to = s.feeTo or FeeReceiver() or "?"
	if s.feeState == "mailed" and not FeeOpen(s, now) then
		lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_FEE_MAILED:format(Money(fee), ns.DisplayName(s.feeMailedTo or to))) }
		return
	end
	if not FeeOpen(s, now) then return end
	local text = L.CRAFT_FEE_OWED:format(Money(fee), DateText(s.feeDue))
	lines[#lines + 1] = { indent = 1, text = now >= (s.feeDue or now) and Red(text) or Gold(text), right = Grey(FEE_SUBJECT .. r.id) }
	lines[#lines + 1] = { indent = 1, text = Gold(L.CRAFT_FEE_PAY:format(ns.DisplayName(to))), onClick = function() Requests.PayFee(r.id) end }
end

-- The guild fees this character owes, all told: { copper, count, late }.
function Requests.FeesOwed(now)
	now = now or Now()
	local out = { copper = 0, count = 0, late = 0 }
	for _, r in pairs(Store().records) do
		local s = r.settlement
		if Same(r.crafter, ns.me) and FeeOpen(s, now) then
			out.copper, out.count = out.copper + (s.guildFee or 0), out.count + 1
			if now >= (s.feeDue or now) then out.late = out.late + 1 end
		end
	end
	return out
end

Fee.TIER_TEXT = { [0] = "CRAFT_DEBT_TIER_NOTICE", [1] = "CRAFT_DEBT_TIER_RESTRICTED", [2] = "CRAFT_DEBT_TIER_WATCH", [3] = "CRAFT_DEBT_TIER_GUILD" }
function Fee.Tier(level) return L[Fee.TIER_TEXT[level] or Fee.TIER_TEXT[0]] end
function Fee.By(e)
	local by = type(e) == "table" and type(e.by) == "table" and e.by or {}
	local text = (by.s and by.b) and L.CRAFT_FEES_BY_BOTH or (by.s and L.CRAFT_FEES_BY_SELLER or L.CRAFT_FEES_BY_BUYER)
	if e.checkedBy or e.checked then text = text .. ", " .. L.CRAFT_FEES_BY_DESK end
	return text
end
function Fee.Item(id)
	local info = id and ItemInfo(id)
	return info and info.name or (id and ("#" .. id) or "?")
end
-- The gap between the two parties' figures, as this client holds it (the King's copy: the desk's flag).
function Fee.Gap(e)
	if e.grossS and e.grossB and e.grossS ~= e.grossB then return L.CRAFT_FEES_MISMATCH:format(Money(e.grossS), Money(e.grossB)) end
	if e.differ then return L.CRAFT_FEES_HIGHER_BUYER end
end
-- The King's copy holds the desk's first DEBTS_ANSWER_MAX fees: said when it holds part of them.
function Fee.Partial(d)
	if d.open and d.got and d.open > d.got then return L.CRAFT_FEES_PARTIAL:format(d.got, d.open) end
end

-- The debtors as text, for a reader's copy (the collection, the guilds' Watch).
function Requests.DebtorsText(now)
	local d = Requests.Debtors(now)
	if not d then return nil end
	local T = ns.Treasury
	local function G(c) return T and T.GoldText and T.GoldText(c) or (tostring(c) .. "c") end
	local out = { L.CRAFT_FEES_COPY_HEAD:format(DateText(now or Now())) }
	local partial = Fee.Partial(d)
	if partial then out[#out + 1] = partial end
	for i, x in ipairs(d.ranking) do
		out[#out + 1] = L.CRAFT_FEES_COPY_RANK:format(i, x.name, x.guild or "?", G(x.owed), G(x.late), x.count, DateText(x.oldest), Fee.Tier(x.level))
	end
	local function Entry(e)
		out[#out + 1] = L.CRAFT_FEES_COPY_ENTRY:format(e.id, e.crafter, e.requester or "?", e.qty or 0, Fee.Item(e.item), G(e.gross or 0), G(e.fee or 0),
			G(e.paid or 0), DateText(e.due), Fee.By(e))
		local gap = Fee.Gap(e)
		if gap then out[#out + 1] = "    " .. gap end
	end
	for _, e in ipairs(d.entries) do Entry(e) end
	if #d.toCheck > 0 then out[#out + 1] = L.CRAFT_FEES_TO_CHECK end
	for _, e in ipairs(d.toCheck) do Entry(e) end
	return table.concat(out, "\n")
end

function Requests.AskSettleFee(key, how)
	local d = Requests.Debtors()
	if not d or not d.own then return false end
	local text = how == "paid" and L.CRAFT_FEE_SETTLE_PAID or (how == "confirmed" and L.CRAFT_FEE_SETTLE_CONFIRM or L.CRAFT_FEE_SETTLE_WAIVE)
	for _, list in ipairs({ d.entries, d.toCheck }) do
		for _, e in ipairs(list) do
			if e.key == key then
				local what = text:format(ns.DisplayName(e.crafter), Money(e.fee - (e.paid or 0)))
				return ns.ShowDialog and ns.ShowDialog("OLYMPUS_CRAFT_FEE_SETTLE", what, nil, { key = key, how = how }) ~= nil
			end
		end
	end
	return false
end

-- The readers' page (ReadsDebtors): the debtors ranked, then every fee owed, then those waiting
-- apart for the desk (the buyer's word alone, or the buyer's figure above the seller's).
function Fee.Page(lines)
	local own = FeeDesk()
	local now = Now()
	if not own then
		local v = Fee.view
		local wait = math.max(0, (tonumber(v.waitUntil) or 0) - now)
		local status
		if v.asking and now - (tonumber(v.askedAt) or 0) < Requests.DEBTS_RETRY then status = L.CRAFT_FEES_ASKING
		elseif v.asking then status = L.CRAFT_FEES_NO_ANSWER
		elseif wait > 0 then status = L.CRAFT_FEES_WAIT:format(math.ceil(wait / 60))
		elseif v.at then status = L.CRAFT_FEES_AS_OF:format(ns.Ago(v.at), ns.DisplayName(v.from or "?"))
		else status = OnlineDesk() and L.CRAFT_FEES_NOT_ASKED or L.CRAFT_FEES_DESK_OFFLINE end
		lines[#lines + 1] = { text = Grey(status) }
		lines[#lines + 1] = { text = Gold(L.CRAFT_FEES_ASK), onClick = function()
			local ok, why, seconds = Requests.AskDebtors(true)
			if ok then return end
			if why == "fresh" and seconds then ns.Print(L.CRAFT_FEES_WAIT:format(math.ceil(seconds / 60)))
			else ns.Print(L.CRAFT_FEES_ASK_REFUSED:format(tostring(why or "?"))) end
		end }
	end
	local d = Requests.Debtors() or { ranking = {}, entries = {}, toCheck = {} }
	local partial = Fee.Partial(d)
	if partial then lines[#lines + 1] = { text = Gold(partial) } end
	if own then
		local n = 0
		for _ in pairs((Requests.FeeLedger() or {}).entries or {}) do n = n + 1 end
		if n >= Requests.FEES_MAX then lines[#lines + 1] = { text = Red(L.CRAFT_FEES_FULL:format(n)) } end
	end
	local total = 0
	for _, x in ipairs(d.ranking) do total = total + x.owed end
	lines[#lines + 1] = { header = true, text = L.CRAFT_FEES_RANKING, right = L.CRAFT_FEES_TOTAL:format(Money(total)) }
	if #d.ranking == 0 then lines[#lines + 1] = { text = Grey(L.CRAFT_FEES_NONE) } end
	local W = ns.Watch
	local watch = type(W) == "table" and type(W.CanManage) == "function" and W.CanManage() == true
	for i, x in ipairs(d.ranking) do
		lines[#lines + 1] = { text = ("%d. %s"):format(i, ns.DisplayName(x.name)) .. "  " .. Grey("<" .. tostring(x.guild or "?") .. ">"),
			right = (x.late > 0 and Red(Money(x.owed)) or Money(x.owed)) .. "  " .. Grey(L.CRAFT_FEES_COUNT:format(x.count)) }
		local nav = {}
		for _, e in ipairs(Collects(ns.me) and d.entries or {}) do
			if Same(e.crafter, x.name) then
				nav[#nav + 1] = { text = L.CRAFT_FEES_REMIND, onClick = function() Requests.RemindDebtor(e.key) end }
				break
			end
		end
		if watch and x.late > 0 then nav[#nav + 1] = { text = L.CRAFT_FEES_WATCH, onClick = function()
			local ok, why = Requests.WarnDebtor(x.name)
			ns.Print(L.CRAFT_FEES_WARNED:format(ns.DisplayName(x.name), tostring(ok and "ok" or why or "?")))
		end } end
		lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_FEES_TIER:format(Fee.Tier(x.level), DateText(x.oldest))), nav = #nav > 0 and nav or nil }
	end
	local function Entry(e, waiting)
		local owed = math.max(0, e.fee - (e.paid or 0))
		lines[#lines + 1] = { text = L.CRAFT_FEES_ENTRY:format(ns.DisplayName(e.crafter), e.qty or 0, Fee.Item(e.item), Money(e.gross or 0)),
			right = ((not waiting and now >= (e.due or 0)) and Red or Gold)(L.CRAFT_FEES_ENTRY_OWED:format(Money(owed), DateText(e.due))) }
		local nav
		if own then
			nav = {}
			if waiting then nav[#nav + 1] = { text = L.CRAFT_FEES_CONFIRM, onClick = function() Requests.AskSettleFee(e.key, "confirmed") end } end
			nav[#nav + 1] = { text = L.CRAFT_FEES_MARK_PAID, onClick = function() Requests.AskSettleFee(e.key, "paid") end }
			nav[#nav + 1] = { text = L.CRAFT_FEES_WAIVE, onClick = function() Requests.AskSettleFee(e.key, "waived") end }
		end
		lines[#lines + 1] = { indent = 1, text = Grey(L.CRAFT_FEES_ENTRY_INFO:format(ns.DisplayName(e.requester or "?"), Fee.By(e), Money(e.paid or 0), e.id)), nav = nav }
		local gap = Fee.Gap(e)
		if gap then lines[#lines + 1] = { indent = 1, text = Red(gap) } end
	end
	lines[#lines + 1] = { header = true, text = L.CRAFT_FEES_DETAILS }
	for _, e in ipairs(d.entries) do Entry(e, false) end
	if #d.toCheck > 0 then
		lines[#lines + 1] = { header = true, text = L.CRAFT_FEES_TO_CHECK }
		for _, e in ipairs(d.toCheck) do Entry(e, true) end
	end
	lines[#lines + 1] = { text = Gold(L.CRAFT_FEES_COPY), onClick = function()
		if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy(L.CRAFT_FEES_COPY_TITLE, Requests.DebtorsText() or "") end
	end }
end

function Requests.BoardLines(q)
	local duty = false
	for _, r in pairs(Store().records) do if Custody(r) or Reviewing(r) then duty = true break end end
	if pageMode == "duty" and not duty then pageMode = "board" end
	-- (The guild's debtors: the Treasurer's characters and the King's, the High Council's and the
	-- author's, by their own names.)
	local readsFees = WalletShown() and ReadsDebtors(ns.me)
	if pageMode == "fees" and not readsFees then pageMode = "board" end
	local nav = {
		{ text = L.CRAFT_BOARD_OPEN, selected = pageMode == "board", onClick = function() pageMode = "board" Changed() end },
		{ text = L.CRAFT_BOARD_MINE, selected = pageMode == "mine", onClick = function() pageMode = "mine" Changed() end },
		{ text = L.CRAFT_BOARD_ACCEPTED, selected = pageMode == "accepted", onClick = function() pageMode = "accepted" Changed() end },
	}
	if duty then nav[#nav + 1] = { text = L.CRAFT_BOARD_DUTY, selected = pageMode == "duty", onClick = function() pageMode = "duty" Changed() end } end
	nav[#nav + 1] = { text = L.CRAFT_BOARD_HISTORY, selected = pageMode == "history", onClick = function() pageMode = "history" Changed() end }
	if readsFees then nav[#nav + 1] = { text = L.CRAFT_BOARD_FEES, selected = pageMode == "fees", onClick = function()
		pageMode = "fees"
		if not FeeDesk() then Requests.AskDebtors() end
		Changed()
	end } end
	local pageLabel
	for _, item in ipairs(nav) do if item.selected then pageLabel = item.text break end end
	local lines = { { header = true, text = L.CRAFT_BOARD_TITLE, right = pageLabel },
		{ text = Green(L.CRAFTER_ASK), onClick = function() Requests.OpenComposer() end,
			tooltip = function(tt) tt:AddLine(L.CRAFTER_ASK, 1, 0.82, 0); tt:AddLine(L.CRAFTER_ASK_TIP, 1, 1, 1, true) end } }
	-- 1.1.6: a sanctioned player's tab (WatchChat.Barred): what he cannot do, and until when.
	local barred = Requests.Barred()
	if barred then lines[2] = { text = Red(ns.WatchChat.BarredText(barred)) } end
	-- The seller's own fees still owed, above the board: late in red, a click to his history.
	local owed = Requests.FeesOwed()
	if WalletShown() and owed.count > 0 then
		local text = L.CRAFT_FEES_YOU_OWE:format(Money(owed.copper), owed.count)
		lines[#lines + 1] = { text = owed.late > 0 and Red(text) or Gold(text), onClick = function() pageMode = "history" Changed() end }
	end
	lines[#lines + 1] = { nav = nav, pageNav = true, id = "craft-navigation" }
	if pageMode == "fees" then
		Fee.Page(lines)
		lines[#lines].gapAfter = true
		return lines
	end
	local n = 0
	for _, r in ipairs(Requests.All()) do
		if Relevant(r) and (not q or ns.Holds(q, r.itemName, r.requester, r.guild, r.details, r.state)) then
			n = n + 1
			local match = Requests.CanFulfill(r)
			lines[#lines + 1] = { text = (openedId == r.id and "[-] " or "[+] ") .. r.quantity .. " x " .. r.itemName .. "  " .. Grey("<" .. tostring(r.guild or "?") .. ">"),
				right = (match and Green(L.CRAFT_CAN_FULFILL) .. "  " or "") .. Grey(StateLabel(r.state) .. " · " .. ns.Ago(r.updated or r.created)),
				onClick = function() openedId = openedId == r.id and nil or r.id Changed() end }
			if openedId == r.id then DetailLines(lines, r) end
		end
	end
	if n == 0 then lines[#lines + 1] = { text = Grey(L.CRAFT_BOARD_EMPTY) } end
	lines[#lines].gapAfter = true
	return lines
end

function Requests.Page() return pageMode end
function Requests.SetPage(mode) pageMode = mode; Changed() end
function Requests.Open(id) openedId = id; Changed() end

-- A party's copy of a mediated deal asks its custodian where it stands, only while his addon is
-- heard online (a whisper to a player who is not is a line of the game's in the chat): the first
-- time this session (it may have missed his words while offline), then whenever it heard nothing
-- from him for ASK_GAP. Before he said he took the contract, the invite goes again.
local function AskCustodian(r, now)
	local s = r.settlement
	if FINAL[s.state] or not s.custodian or not CustodianOnline(s.custodian) then return false end
	if asked[r.id] and now - math.max(s.heardAt or 0, s.askedAt or 0, s.created or 0) < Requests.ASK_GAP then return false end
	asked[r.id], s.askedAt = true, now
	if not s.contractAt then return SendInvite(r) end
	return ToCustodian(r, "ask")
end

function Requests.Tick()
	local s = Store()
	if next(s.records) == nil and next(s.invites) == nil then return end
	local now, changed = Now(), false
	-- (Our words of sales to the fee desk: a few a minute, well inside what one sender may send it.)
	local feeWords = 4
	Prune()
	for _, r in pairs(s.records) do
		if Same(r.requester, ns.me) then
			if r.publishPending then
				Publish(r, true)
			elseif r.state == "open" then
				Publish(r)
			elseif r.takenRepublish and now - (r.lastPublished or 0) >= Requests.PUBLISH_GAP then
				-- Once more for whoever missed it, then the card is left to expire on their side.
				r.takenRepublish = nil
				Publish(r, true)
			end
		end
		if Custody(r) and CustodyDeadline(r, now) then changed = true end
		if Mine(r) and not Terminal(r) and r.settlement and r.settlement.rail == "guild" then AskCustodian(r, now) end
		-- The guild's fee: owed on a sale the buyer never confirmed, our word of the sale to the desk,
		-- and the seller's warning once late.
		if Mine(r) and r.settlement and Fee.Arise(r, now) then changed = true end
		if feeWords > 0 and Mine(r) and r.settlement and r.settlement.feeReport and SendFeeReport(r, now) then feeWords = feeWords - 1 end
		if Mine(r) and r.settlement and Fee.WarnOverdue(r, now) then changed = true end
	end
	if changed then Changed() end
end

function Requests.Reset()
	transient = NewStore()
	if ns.rdb then ns.rdb.craftRequests = nil end
	composer, openedId, pageMode = nil, nil, "board"
	nextId = 0
	publishTimes, cardBuckets, actionBuckets, chatBuckets, alertTimes, priceSamples, escrowAdapters = {}, {}, {}, {}, {}, {}, {}
	exactTrade, exactMailOut, exactInbox, asked, itemsAsked = nil, nil, {}, {}, {}
	Fee.view, Fee.warned, Fee.reminded, Fee.answered, Fee.jobs, Fee.pumping = { entries = {} }, {}, {}, {}, {}, false
	if ns.rdb then ns.rdb.craftFees = nil end
end

ns.Comm.Handle("CQ", Requests.ReceiveSnapshot)
ns.Comm.Handle("CR", Requests.ReceiveAction)
ns.Comm.Handle("CJ", Requests.ReceiveChat)
ns.Comm.Handle("CK", Requests.ReceiveMediation)
ns.On("LOGIN", function()
	SubscribeMoney()
	ns.Every(60, "craft requests", Requests.Tick)
end)
