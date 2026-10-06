-- 1.2, the fights part (fights and honours): what the fights' and honours' tests need of the test world beyond
-- the arena's foundation's (tests/arena/lib/world.lua, frozen), by composition (the design): unit tokens and
-- positions per client, the game's duel and roll lines, census reports with their top levels, the
-- live switch and the companion. Every name is invented (World.NAMES and the ones below).
local H = ...
local World = H.World
local W3 = {}

W3.DUEL_KO = "%s has defeated %s in a duel"        -- ArenaParse.EN's DUEL_WINNER_KNOCKOUT, argument order kept
W3.DUEL_FLED = "%s has fled from %s in a duel"      -- (the retreat: the loser first)
W3.ROLL = "%s rolls %d (%d-%d)"

-- A world with the King (and the live switch on unless live = false), the signed arbiter, the two
-- fighters and a spectator; opts.more: more clients, { name, where } each.
function W3.New(opts)
	opts = opts or {}
	local w = World.New(opts.world)
	local cast = {}
	cast.king = w:Role("king")
	cast.arbiter = w:Role("arbiter")
	cast.A = w:Role("fighterA")
	cast.B = w:Role("fighterB")
	cast.spectator = w:Role("bettor1")
	for _, m in ipairs(opts.more or {}) do cast[m[1]] = w:Client(m[2], m[3]) end
	if opts.live ~= false then W3.Live(w, cast.king) end
	for _, c in ipairs(w.clients) do W3.Rules(w, c) end
	return w, cast
end

-- The King's settings word: live on (gold by default: the world's Treasurer realm has its receiver).
function W3.Live(w, king, t)
	local ok, why = king.Roles.SetSettings(t or { live = 1 })
	assert(ok, "settings: " .. tostring(why))
	w:Run(0)
end
-- The arena's rules said yes to (the account's).
function W3.Rules(w, c) w:As(c, function() c.ns.Arena.SetRules(true) end) end
-- The companion loaded (its heavy tables: the ledger, profiles).
function W3.Companion(w, c) return w:As(c, function() return c.ns.Arena.LoadUI() end) end

-- A module of a client, its functions run as that client (as World's proxies).
function W3.M(w, c, name)
	local t = c.ns[name]
	return setmetatable({}, { __index = function(_, k)
		local v = t[k]
		if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
		return v
	end, __newindex = function(_, k, v) t[k] = v end })
end

-- Where a client stands (UnitPosition: y, x, z, instance), and whether it sees another close
-- (a token for a GUID, CheckInteractDistance on it): sees = { [client] = true | "far" | "secret" }.
function W3.Stand(c, x, y, inst)
	c.globals.UnitPosition = function(unit)
		if unit ~= "player" then return nil end
		return y, x, 0, inst or 0
	end
end
function W3.Sees(c, sees)
	c.globals.UnitTokenFromGUID = function(guid)
		for other, how in pairs(sees) do
			if other.guid == guid then return "token:" .. other.short end
		end
		return nil
	end
	c.globals.CheckInteractDistance = function(token)
		for other, how in pairs(sees) do
			if token == "token:" .. other.short then
				if how == "secret" then return c.globals.SECRET end
				return how == true
			end
		end
		return false
	end
	-- That token's unit as the game gives it (the weigh-in reads its name, GUID and level: a gk's
	-- token is a fighter's only when its unit is him, ArenaFights.TokenOf).
	local function Seen(unit)
		local short = type(unit) == "string" and unit:match("^token:(.+)$")
		if not short then return nil end
		for other in pairs(sees) do if other.short == short then return other end end
		return nil
	end
	local base = {}
	for _, fn in ipairs({ "UnitFullName", "UnitName", "GetUnitName", "UnitGUID", "UnitLevel", "UnitExists", "UnitIsPlayer" }) do base[fn] = c.globals[fn] end
	c.globals.UnitFullName = function(unit) local o = Seen(unit) if o then return o.short, o.realm end return base.UnitFullName(unit) end
	c.globals.UnitName = function(unit) local o = Seen(unit) if o then return o.short, o.realm ~= c.realm and o.realm or nil end return base.UnitName(unit) end
	c.globals.GetUnitName = function(unit, withRealm)
		local o = Seen(unit)
		if o then return withRealm and (o.short .. "-" .. o.realm) or o.short end
		return base.GetUnitName(unit, withRealm)
	end
	c.globals.UnitGUID = function(unit) local o = Seen(unit) if o then return o.guid end return base.UnitGUID(unit) end
	c.globals.UnitLevel = function(unit) local o = Seen(unit) if o then return o.level end return base.UnitLevel(unit) end
	c.globals.UnitExists = function(unit) if Seen(unit) then return true end return base.UnitExists(unit) end
	-- (A fighter is a player: the game's UnitIsPlayer is true for his unit, ArenaFights.TokenOf asks it.)
	c.globals.UnitIsPlayer = function(unit) if Seen(unit) then return true end return base.UnitIsPlayer(unit) end
end

-- The game's duel line on these clients (the winner and loser as the game names them: short).
function W3.Duel(w, to, winner, loser, fled)
	local text = fled and W3.DUEL_FLED:format(loser.short, winner.short) or W3.DUEL_KO:format(winner.short, loser.short)
	w:System(to, text)
end
-- A /roll line (the roller's, as every raid member reads it).
function W3.Roll(w, to, roller, value, low, high)
	w:System(to, W3.ROLL:format(roller.short, value, low, high))
end

-- A census report of `guild` from `reporter`, as Data.Receive keeps it, on client c: its top
-- levels ({ { name, level, class } }), leader and size.
function W3.Report(c, guild, reporter, top, extra)
	local r = { guild = guild, reporter = reporter.short, reporterFull = reporter.name, t = c.ns.Now(), top = top, leader = extra and extra.leader,
		total = extra and extra.total, avgLevel = extra and extra.avgLevel, faction = "Alliance", realm = c.realm, heardOn = c.realm }
	c.rdb.guilds[guild] = r
	return r
end

-- The errors any client raised (handlers, timers, events): none expected.
function W3.NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end

-- the money part's money side as its contract says (its 1.2 branch: Stakes.Open/Result/Direct, Debts.Iou,
-- ReadIou, CheckIou, Commit, KeyOf, Verified, SignResult, Standing.Cap, TokenWire, CheckWire),
-- stood in on a client, its calls kept in the table returned: { open, result, direct }. The keys
-- and signatures are invented (a hash of the text and the signer's name), checked by the same
-- stand-ins on the other side. opts: { cap (copper), token = false (none), persists = false (saved
-- data that does not persist: Arena.Persists left alone) }.
function W3.Money(w, c, opts)
	opts = opts or {}
	local ns = c.ns
	local A = ns.Arena
	local calls = { open = {}, result = {}, direct = {} }
	local function Key(name) return "pk" .. A.Hash36(ns.FullName(name):lower(), 8) end
	local function Sig(text, pk) return A.Hash36(text .. "#" .. pk, 16) end
	local function GkOf(name) local o = w:Find(ns.FullName(name)) return o and A.GK(o.guid) or nil end
	ns.Standing.Cap = function(kind, name, mode) return opts.cap or 1000000 end
	ns.Standing.TokenWire = function(mode) if opts.token == false then return nil end return "Coffrey Vault-Emberfall.3.1.2.3.SIG.PK" end
	ns.Standing.CheckWire = function(wire, owner, mode)
		if type(wire) == "string" and wire:find("^Coffrey") then return { tier = 3 } end
		return nil, "shape"
	end
	ns.Debts.Verified = function(name) return GkOf(name) end
	ns.Debts.KeyOf = function(name) return Key(name) end
	ns.Debts.Commit = function(copper, salt) return A.Hash36(tostring(copper) .. "|" .. tostring(salt), 16) end
	ns.Debts.Iou = function(mid, payee, copper, salt)
		local text = ("OLYD1|%s|%s|%s|%s"):format(mid, tostring(GkOf(ns.me)), tostring(GkOf(payee)), ns.Debts.Commit(copper, salt))
		local commit = ns.Debts.Commit(copper, salt)
		local sig = Sig(text, Key(ns.me))
		return { mid = mid, commit = commit, sig = sig, text = text, wire = commit .. "." .. sig }
	end
	ns.Debts.ReadIou = function(wire, mid, payerGk, payeeGk)
		local commit, sig = tostring(wire):match("^(%w+)%.(%w+)$")
		if not commit then return nil end
		return { commit = commit, sig = sig, text = ("OLYD1|%s|%s|%s|%s"):format(mid, payerGk, payeeGk, commit), wire = wire }
	end
	ns.Debts.CheckIou = function(text, sig, pk) return Sig(text, pk) == sig end
	ns.Debts.SignResult = function(fid, round, wGk, lGk) return Sig(("OLYW1|%s|%s|%s|%s"):format(fid, round, wGk, lGk), Key(ns.me)) end
	ns.Stakes.Open = function(t) calls.open[#calls.open + 1] = t return true end
	ns.Stakes.Result = function(id, side, mode) calls.result[#calls.result + 1] = { id = id, side = side, mode = mode } return {} end
	ns.Stakes.Direct = function(t) calls.direct[#calls.direct + 1] = t return true end
	if opts.persists ~= false then A.Persists = function() return true end end
	return calls
end

-- The messages of a type sent by a client (World:Sent), their bodies.
function W3.Bodies(w, from, kind, dist)
	local out = {}
	for _, s in ipairs(w:Sent{ from = from, type = kind, dist = dist }) do out[#out + 1] = s.msg:gsub("^%w%w~[LT]1~", "") end
	return out
end

return W3
