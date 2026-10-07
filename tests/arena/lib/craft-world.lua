-- 1.2, crafting requests (CraftRequests.lua): what the requests' tests need of the world beyond
-- the arena's foundation's (tests/arena/lib/world.lua, frozen) and the money part's (money-world.lua): extended by composition.
-- Each client also loads Crafters.lua, ChatRooms.lua and CraftRequests.lua into its own namespace,
-- so a requester, a crafter, a bystander and a custodian each keep their own records and talk only
-- through the world's lanes. Every name here is invented.
--
--   local K = assert(loadfile(H.ROOT .. "tests/arena/lib/craft-world.lua"))(H)
--   local w = World.New()
--   local a = K.Client(w, "Sage Owl")             -- c.Craft (CraftRequests), c.Rooms, c.Crafters
--   K.Recipes(w, b, { [14342] = "Mooncloth" })    -- b listed as a Tailor who makes these
--   K.Request(w, a, 14342, "Mooncloth", 2)        -- a's published request (its record on a)
local H = ...
local World = H.World
local M = assert(loadfile(H.ROOT .. "tests/arena/lib/money-world.lua"))(H)
local K = { M = M }

-- The files CraftRequests.lua needs of its own in each client, in Olympus.toc's order.
K.EXTRA = { "Crafters", "ChatRooms", "CraftRequests" }

local function WithModules(fn, ...)
	local saved, list = World.MODULES, {}
	for _, m in ipairs(saved) do list[#list + 1] = m end
	for _, m in ipairs(K.EXTRA) do list[#list + 1] = m end
	World.MODULES = list
	local res = { pcall(fn, ...) }
	World.MODULES = saved
	if not res[1] then error(res[2], 0) end
	return unpack(res, 2, table.maxn(res))
end

-- The client's bags (C_Item.GetItemCount) and the mail's attachments (GetSendMailItem,
-- GetInboxItem, TakeInboxItem), which the world leaves out. Every call is the game's documented
-- shape: GetSendMailItem(i) -> name, itemID, texture, count; GetInboxItem(m, i) the same.
function K.Equip(w, c)
	M.Equip(w, c)
	local g = c.globals
	c.bags = c.bags or {}
	g.C_Item = { GetItemCount = function(id) return c.bags[id] or 0 end, GetItemInfo = function(id)
		local name = K.ITEMS[tonumber(id) or 0]
		if name then return name, "|Hitem:" .. id .. "|h[" .. name .. "]|h", 2, 1, 1, "Trade Goods", "Cloth", 20, "", 1, 100 end
	end }
	g.GetSendMailItem = function(i)
		local it = c.mailOut and c.mailOut.items and c.mailOut.items[i]
		if it then return it.name, it.id, nil, it.count or 1 end
	end
	g.GetInboxItem = function(m, i)
		local mail = c.inbox[m]
		local it = mail and mail.items and mail.items[i]
		if it then return it.name, it.id, nil, it.count or 1 end
	end
	g.TakeInboxItem = function(m, i) for _, fn in ipairs(c.hooks.TakeInboxItem or {}) do fn(m, i) end end
	g.MAX_TRADABLE_ITEMS, g.ATTACHMENTS_MAX_SEND, g.ATTACHMENTS_MAX_RECEIVE = 6, 12, 16
	-- The world's Comm queues without a word; Comm.lua's Send and Whisper return true once the
	-- message is admitted and nothing when refused (tests/run.lua checks that contract with the
	-- real Comm.lua). The same answer here: true unless the world refused it on the spot.
	local C = c.ns.Comm
	if C and not C.craftAdmits then
		C.craftAdmits = true
		for _, f in ipairs({ "Send", "Whisper" }) do
			local raw = C[f]
			C[f] = function(a1, msg, key, urgent, logged, done, options)
				local sync, refused = true, false
				raw(a1, msg, key, urgent, logged, function(ok, why)
					if sync and ok == false then refused = true end
					if done then done(ok, why) end
				end, options)
				sync = false
				if not refused then return true end
			end
		end
	end
	-- The window is not under test here: each client's page switches are written down (as the
	-- run.lua craft harness does), never the harness's own UI.lua over the world's stand-in frames.
	c.tabs = c.tabs or {}
	rawset(c.ns, "UI", { SelectTab = function(tab) c.tabs[#c.tabs + 1] = tab end })
	for _, m in ipairs({ "CraftRequests", "ChatRooms", "Crafters", "Treasury" }) do c[m] = M.P(w, c, m) end
	c.Craft = c.CraftRequests
	c.Rooms = c.ChatRooms
	return c
end

K.ITEMS = { [14342] = "Mooncloth", [4338] = "Mageweave Cloth", [2589] = "Linen Cloth" }

function K.Client(w, name, where) return WithModules(function() return K.Equip(w, w:Client(name, where)) end) end
function K.Role(w, role, where) return WithModules(function() return K.Equip(w, w:Role(role, where)) end) end
function K.Relog(w, c)
	w:Logout(c)
	WithModules(function() w:Login(c) end)
	return K.Equip(w, c)
end

-- A crafter listed for one profession, making these items (a consented, read profession).
function K.Recipes(w, c, items, key, name)
	w:As(c, function()
		local C = c.ns.Crafters
		local recipes = {}
		for id, n in pairs(items) do recipes[#recipes + 1] = { r = id + 100000, i = id, n = n } end
		C.Mine()[key or "197"] = { key = key or "197", name = name or "Tailoring", rank = 250, max = 300, recipes = recipes, t = w.clock }
		C.Choices()[key or "197"] = true
	end)
end

-- A's request published through the composer, as a click does; returns a's record.
function K.Request(w, a, itemID, itemName, quantity, details, materials)
	local r = w:As(a, function()
		local R = a.ns.CraftRequests
		R.OpenComposer()
		R.SelectItem({ id = itemID, name = itemName, kind = "craft" }, "craft")
		R.SetComposerQuantity(quantity or 1)
		if details then R.SetComposerDetails(details) end
		if materials then R.SetComposerMaterials(materials) end
		local rec, why = R.PublishDraft()
		assert(type(rec) == "table", "published: " .. tostring(why))
		return rec
	end)
	w:Run(0)
	return r
end

-- Days go by (a fee's deadline, a mail's days): the clock moves, and each client's tickers run
-- next at their first tick from then, never once for each one missed (what they did meanwhile is
-- not under test, and a catch-up of days fills World:Run's budget before anything else is due).
function K.Jump(w, seconds)
	w.clock = w.clock + seconds
	for _, t in ipairs(w.timers) do
		if not t.cancelled and t.every and t.at < w.clock then t.at = t.at + math.ceil((w.clock - t.at) / t.every) * t.every end
	end
end

-- A record as one client holds it.
function K.Rec(w, c, id) return w:As(c, function() return c.ns.CraftRequests.Get(id) end) end

-- The live gold switches as the Wallet needs them: the King's live word on gold, and every given
-- client relogged so its saved data is seen to survive (Arena.Persists).
function K.GoLive(w, clients)
	local king = w:Find(World.NAMES.king) or M.Role(w, "king")
	M.GoLive(w, king)
	for _, c in ipairs(clients) do K.Relog(w, c) end
	w:Run(0)
	return king
end

-- Gold or goods by trade between a and b, as both windows show it: { aGives, bGives (copper),
-- aItems, bItems = { { id, count } } } (the items get their names and links as the game's do).
function K.Trade(w, a, b, spec)
	local function Items(list)
		if not list then return nil end
		local out = {}
		for i, it in ipairs(list) do
			local name = K.ITEMS[it.id] or ("Item " .. it.id)
			out[i] = { name = name, count = it.count or 1, link = "|cffffffff|Hitem:" .. it.id .. "::::::::60:::::|h[" .. name .. "]|h|r" }
		end
		return out
	end
	w:Trade(a, b, { aGives = spec.aGives, bGives = spec.bGives, aItems = Items(spec.aItems), bItems = Items(spec.bItems), complete = spec.complete })
	for _, it in ipairs(spec.aItems or {}) do
		a.bags[it.id] = (a.bags[it.id] or 0) - (it.count or 1)
		b.bags[it.id] = (b.bags[it.id] or 0) + (it.count or 1)
	end
	for _, it in ipairs(spec.bItems or {}) do
		b.bags[it.id] = (b.bags[it.id] or 0) - (it.count or 1)
		a.bags[it.id] = (a.bags[it.id] or 0) + (it.count or 1)
	end
	w:Run(3) -- (past the 2 s a closed trade is kept)
end

-- A mail with attachments (and gold, or cash on delivery): the sender's hooks and
-- MAIL_SEND_SUCCESS; it reaches the recipient's inbox. Returns its index there.
function K.MailItems(w, from, to, items, subject, copper, cod)
	local list = {}
	for i, it in ipairs(items or {}) do list[i] = { name = K.ITEMS[it.id] or ("Item " .. it.id), id = it.id, count = it.count or 1 } end
	from.mailOut = { copper = copper or 0, cod = cod or 0, subject = subject or "", items = list }
	w:As(from, function() SendMail(to.name, subject or "", "") end)
	w:Fire(from, "MAIL_SEND_SUCCESS")
	from.mailOut = nil
	for _, it in ipairs(list) do from.bags[it.id] = (from.bags[it.id] or 0) - it.count end
	to.inbox[#to.inbox + 1] = { sender = from.short, from = from, subject = subject or "", money = copper or 0, cod = cod or 0, items = list }
	w:Fire(to, "MAIL_INBOX_UPDATE")
	w:Flush()
	return #to.inbox
end

-- The recipient takes attachment `slot` of mail i: the game's call, then the bags and the inbox.
function K.TakeItem(w, to, i, slot)
	local m = assert(to.inbox[i], "no mail " .. tostring(i))
	w:As(to, function() TakeInboxItem(i, slot) end)
	local it = table.remove(m.items, slot)
	to.bags[it.id] = (to.bags[it.id] or 0) + it.count
	w:Fire(to, "BAG_UPDATE_DELAYED")
	w:Fire(to, "MAIL_INBOX_UPDATE")
	w:Flush()
end

-- The messages of one type between two clients (from, optionally to), in order.
function K.Words(w, kind, from, to)
	local out = {}
	for _, s in ipairs(w:Sent({ type = kind, from = from })) do
		if not to or (s.target or ""):lower() == to.name:lower() then out[#out + 1] = s end
	end
	return out
end

K.NoErrors = M.NoErrors
return K
