local ADDON, ns = ...

-- 1.2, the Blood Arena: Debts.lua. A stub the arena's core created for the money part (money) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- The account key and its claims (ZT), signed IOUs and results, debt marks and details (ZX, ZY),
-- receipts (ZR, ZF), the debt freeze on alt links (Alts.freezers), standing points, the
-- bank-signed standing token and the caps. Registers ZT ZX ZY ZR ZF.
-- API (the design):
--   Debts.SendClaim(to); Debts.Verified(name) -> gk, fp, how ("unit"|"info") or nil (the design)
--   Debts.SameOwner(a, b); Debts.Blocked(name, gk, fp) -> blocked, why
--   Debts.Iou(mid, payee, copper); Debts.CheckIou(text, sig, pk)
--   Debts.SignResult(fid, round, winnerGk, loserGk)
--   Debts.Owe{ id, debtor, gk, creditor, copper, kind = "bet"|"fee"|"payout"|"withdrawal"|"refund"|
--     "change"|"item", due, ref }; Debts.Mailed(id, recipient, subject, ref); Debts.Paid(id, copper, how)
--   Debts.Disputed(id, evidence); Debts.Mark(name) -> "open" or nil
--   Debts.Open() -> this character's open obligations (Arena.SetOff refuses while any)
--   Standing.Points(name), Standing.Cap(kind, name) (bet|balance|daily|direct|hold),
--   Standing.Earn(name, kind, peerKey, copper), Standing.Late(name), Standing.Record(name),
--   Standing.Token(), Standing.CheckToken(text, sig)
-- Hooks it fills in the arena's core's files: Alts.freezers (an open debt mark freezes the debtor's links),
-- Backup.arenaChecks (mine, key), ArenaRoles.stillOwing is Wallet's.
--
-- the money part's full contract (every name the other packages and the screens use):
--   The account key (db.arenaKey = { seed, pk, at, claims = { [guid] = { name, sig } } }, base64url):
--     Debts.MyKey() -> gk, pk (32 bytes), fp; made once per account, a claim signed once per
--       character ("OLYA1|<guid>|<Name-Realm>").
--     Debts.SendClaim(to) whispers ZT~<gk>~<pk>~<sig>~<level> once per peer and session (an
--       obligation: it goes with the arena off too).
--     Debts.Verified(name) -> gk, fp, how; Debts.KeyOf(name) -> pk (32 bytes) of a verified claim.
--       A GUID counts only from a unit token (the trade's "NPC", the target, the group, a
--       nameplate) or GetPlayerInfoByGUID once it answers, its name rebuilt as ns.UnitFullName does.
--   Signing (Ed25519.lua, the account's key; nothing with an amount ever goes where others read):
--     Debts.Iou(mid, payee, copper, salt) -> { mid, payerGk, payeeGk, commit, sig, text, wire }:
--       "OLYD1|<mid>|<payerGk>|<payeeGk>|<commit>", commit = hex of the first 8 bytes of
--       SHA256(copper .. "|" .. salt) (the match's salt: the amount is never readable). wire:
--       "<commit>.<sig>". mid is the id the signed result also names (the fight's, the table's).
--     Debts.ReadIou(wire, mid, payerGk, payeeGk) -> the iou table (for CheckIou), or nil.
--     Debts.Commit(copper, salt); Debts.CheckIou(text, sig, pk) -> true|false (sig and pk raw or
--       base64url).
--     Debts.SignResult(fid, round, winnerGk, loserGk) -> sig (base64url) of
--       "OLYW1|<fid>|<round>|<winnerGk>|<loserGk>"; Debts.CheckResult(fid, round, w, l, sig, pk).
--   Obligations (this character's, in Arena.Store(mode).mine[me].obligations):
--     Debts.Owe(t) with t.mode ("L" default), t.due (server time; default by kind: bet 600 s,
--       fee 24 h, payout 600 s, withdrawal 72 h, refund 24 h, change 24 h, item 72 h) -> the
--       obligation, or nil, why. Its id: t.id, else 8 base-36 characters of its creditor, ref and
--       debtor. Kinds map to the mark's letters b f p w r n i.
--     Debts.Mailed(id, recipient, subject, ref): the clock stops ("m", sent, awaiting receipt);
--       Debts.Returned(id): the mail came back, the clock runs again.
--     Debts.Paid(id, copper, how) -> the obligation (cleared once paid in full).
--     Debts.Disputed(id, evidence), Debts.WriteOff(id) (an auditor's, through the details).
--     Debts.Open(mode) -> { obligation, ... } not cleared or written off.
--     Debts.Credit(t): the creditor's side of a direct debt, t = { id, debtor, copper, ref, due,
--       mode, iou = { commit, sig }, result = { fid, round, sig } }: what it waits for, and the proof
--       it publishes if the payment is late.
--   Marks (ZX, every client keeps them, Arena.Store(mode).debts; no amount ever):
--     Debts.Mark(name) -> "open" or nil; Debts.Marks(name) -> the marks on him; Debts.Busy(name)
--       (an auditor's kind "h" mark: an arbiter at his cap).
--     Debts.LeaderMark(t): an auditor's word (source "l"): t = { id, debtor, gk, kind, state }.
--   Receipts: Debts.Receipt(t) whispers ZR~<ref>~<payer>~<payee>~<copper>~<t|m>~<time>~<1|0>, t =
--     { ref, payer, payee, copper, how, time, onTime, to = { names } }. Debts.FeeReceipt(payer,
--     copper, ref, mode) (the fee receiver's client): ZF to the payer and the auditors.
--     Debts.PayFee(id) -> { to, copper, subject, fill } (one of this character's guild fees filled
--       in the mail: its ref, exactly what is owed; refused while the receiver is not updated).
--     Debts.Waiting() -> anything owed, due to this character, or a fee receipt to send;
--       Debts.Resend() (at login: every open obligation's messages again).
--   Payments seen (ArenaMoney's watcher): a debtor's payment to his creditor sends his receipt;
--     a creditor who receives gold sends his (it clears the debt there); Debts.Landed(partner,
--     copper, how): a payee confirms a payer's receipt once his own watcher saw that gold.
--     Debts.receiptHooks: fn(r, sender, mode) for every receipt heard (Wallet, Stakes).
--   Auditors: Debts.Auditors() (heard lately), Debts.Ledger(mode) -> { marks (each with its
--     details), claims (details with no public mark), disputes, fees, receipts }. Auditors repeat
--     the open marks they hold, 3 a minute at most, each every 30 minutes (Debts.Repeating).
--   Views: Debts.View(mode) -> { obligations, credits, marks = my marks, blocked, why }.
--   Backup: Debts.BackupChecks.key, .mine (Backup.arenaChecks: a restored mine keeps no token).
--   Buttons: "debt.payfee" (id). Events: ARENA_DEBTS, ARENA_SAVE_NOW (a new obligation: /reload
--     saves it), ARENA_KEY (name: a claim verified), ARENA_RECEIVED (payer, copper, ref),
--     ARENA_FEE_CLEARED (ref, copper).
--   Crypto helpers the other money files share: Debts.SHA(text), Debts.Hex(bytes),
--     Debts.First(bytes, n), Debts.B64(bytes), Debts.UnB64(text).
-- Standing (ns.Standing): records per account key on banks and auditors (Store(mode).standing),
--   and each player's own view (mine[me].record):
--     Standing.Record(name) -> the ArenaMath record { points, probation, open, dispute, paidMax }.
--     Standing.Earn(name, kind "wallet"|"arbiter"|"direct", peerKey, copper) -> true when it earned.
--     Standing.Late(name); Standing.Points(name); Standing.Cap(kind, name) -> copper.
--     Standing.Issue(gk, bankName) (a bank's client): the token's text and signature;
--       Standing.Token() -> this character's valid token { bank, gk, tier, volume, paidMax, expiry,
--       text, sig, wire } or nil; Standing.TokenWire() -> "<bank>.<tier>.<vol>.<paidMax>.<exp>.<sig>";
--       Standing.CheckWire(wire, owner) -> token or nil, why (kept for Cap("direct", owner));
--       Standing.CheckToken(text, sig, bank) -> token or nil, why.

local L = ns.L
local Debts = {}
ns.Debts = Debts
local Standing = {}
ns.Standing = Standing

Debts.CLAIMS_MAX = 50
Debts.MARKS_MAX = 2000
Debts.CLEARED_KEEP = 30 * 86400    -- a cleared mark goes this long after
Debts.LATE_OPEN = 86400            -- late this long: an open debt ("o")
Debts.MAILED_WAIT = 30 * 86400     -- a mail sent and no receipt this long: the clock runs again
Debts.AUDITOR_FRESH = 20 * 60      -- an auditor's hello this recent: online
Debts.REPEAT_GAP = 20              -- an auditor repeats an open mark every 20 s at most (3 a minute)
Debts.CHECK_EVERY = 30             -- the due clock, while anything is owed here
Debts.PROBATION = 7 * 86400
Debts.TOKEN_LIFE = 24 * 3600
Debts.DUE = { b = 600, f = 24 * 3600, p = 600, w = 72 * 3600, r = 24 * 3600, n = 24 * 3600, i = 72 * 3600 }
Debts.KIND = { bet = "b", fee = "f", payout = "p", withdrawal = "w", refund = "r", change = "n", item = "i" }
Debts.KIND_NAME = { b = "bet", f = "fee", p = "payout", w = "withdrawal", r = "refund", n = "change", i = "item", h = "busy" }
local MARK_KINDS = { b = true, f = true, p = true, w = true, r = true, n = true, i = true, h = true }
local STATES = { l = true, o = true, m = true, c = true, w = true, d = true }
local OPEN = { l = true, o = true }
local SOURCE_RANK = { s = 1, c = 2, l = 3 }

local function A() return ns.Arena end
local function Now() return ns.Arena.Now() end
local function Lower(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function Same(a, b) return Lower(a) ~= nil and Lower(a) == Lower(b) end
local function B36(n) return ns.Arena.B36(n) end

---------------------------------------------------------------------------
-- Crypto helpers (Sign.lua's SHA-256, Ed25519.lua's keys and base64url)
---------------------------------------------------------------------------

function Debts.SHA(text) return ns.Sign.SHA256(tostring(text)) end
function Debts.Hex(bytes) return (tostring(bytes):gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
-- The first n bytes (n <= 6) as a whole number.
function Debts.First(bytes, n)
	local v = 0
	for i = 1, n do v = v * 256 + (bytes:byte(i) or 0) end
	return v
end
function Debts.B64(bytes) return ns.Ed25519.ToB64(bytes) end
function Debts.UnB64(text) return ns.Ed25519.FromB64(text) end
local function Raw(v, len)
	if type(v) ~= "string" then return nil end
	if #v == len then return v end
	local r = Debts.UnB64(v)
	return r and #r == len and r or nil
end
-- A key's fingerprint: the first 6 bytes of its SHA-256, in base 36.
function Debts.Fp(pk) return B36(Debts.First(Debts.SHA(pk), 6)) end

---------------------------------------------------------------------------
-- The stores
---------------------------------------------------------------------------

local function Store(mode) return ns.Arena.Store(mode == "T" and "T" or "L") end
-- A store as it is, never made here: a rehearsal's exists only while one runs (the design), and a
-- passive path (a login, a view) must not make one.
local function Peek(mode)
	if mode ~= "T" or ns.Arena.Sim() then return ns.Arena.Store(mode == "T" and "T" or "L") end
	return type(ns.rdb) == "table" and type(ns.rdb.arenaTest) == "table" and ns.rdb.arenaTest or nil
end
Debts.Peek = Peek
-- This character's wallet view and obligations (create: made when missing; else nil when none).
local function Mine(mode, create)
	local s = create and Store(mode) or Peek(mode)
	if not s or not ns.me then return nil end
	local m = type(s.mine) == "table" and s.mine[ns.me] or nil
	if type(m) ~= "table" then
		if not create then return nil end
		s.mine = type(s.mine) == "table" and s.mine or {}
		m = {}
		s.mine[ns.me] = m
	end
	for _, k in ipairs({ "banks", "direct", "ious", "obligations", "credits", "record", "tokens" }) do
		if type(m[k]) ~= "table" then m[k] = {} end
	end
	return m
end
Debts.Mine = Mine
local Details, PruneDetails -- (below: an auditor's details of a debt)
local function Marks(mode, create)
	local s = create and Store(mode) or Peek(mode)
	if not s then return {} end
	if type(s.debts) ~= "table" then
		if not create then return {} end
		s.debts = {}
	end
	return s.debts
end

---------------------------------------------------------------------------
-- The account key (the design): one Ed25519 key per WoW account, made once; each character
-- signs its claim once. Nobody can join another account's key without its seed, nor put another
-- character under his own.
---------------------------------------------------------------------------

local function Entropy()
	local parts = {}
	for _ = 1, 8 do
		local Link = ns.Link
		parts[#parts + 1] = type(Link) == "table" and type(Link.EntropySample) == "function" and Link.EntropySample() or ""
		parts[#parts + 1] = tostring(math.random()) .. tostring({}) .. tostring(Now())
	end
	return Debts.SHA(table.concat(parts, "|"))
end

local function KeyTable()
	if not ns.db then return nil end
	local k = ns.db.arenaKey
	local seed = type(k) == "table" and Raw(k.seed, 32)
	if not seed then
		seed = Entropy()
		k = { seed = Debts.B64(seed), pk = Debts.B64(ns.Ed25519.PublicKey(seed)), at = Now(), claims = {} }
		ns.db.arenaKey = k
	end
	if type(k.claims) ~= "table" then k.claims = {} end
	if not Raw(k.pk, 32) then k.pk = Debts.B64(ns.Ed25519.PublicKey(seed)) end
	return k, seed, Raw(k.pk, 32)
end

local function MyGuid()
	local g = UnitGUID and UnitGUID("player") or nil
	if issecretvalue and g ~= nil and issecretvalue(g) then return nil end
	return type(g) == "string" and g or nil
end

-- This character's gk, public key (32 bytes) and fingerprint; nil before the game says its GUID.
function Debts.MyKey()
	local guid = MyGuid()
	local gk = guid and ns.Arena.GK(guid)
	local k, _, pk = KeyTable()
	if not gk or not k then return nil end
	return gk, pk, Debts.Fp(pk)
end

-- Signs with the account's key (tens of milliseconds in the game: on a click, a few times a match).
function Debts.Sign(msg)
	local _, seed, pk = KeyTable()
	if not seed then return nil end
	return ns.Ed25519.Sign(seed, msg, pk)
end

local function Claim()
	local guid = MyGuid()
	local k, seed, pk = KeyTable()
	if not guid or not k or not ns.me then return nil end
	local c = k.claims[guid]
	if type(c) ~= "table" or not Same(c.name, ns.me) or not Raw(c.sig, 64) then
		local n = 0
		for _ in pairs(k.claims) do n = n + 1 end
		if n >= Debts.CLAIMS_MAX then
			for g2 in pairs(k.claims) do if g2 ~= guid then k.claims[g2] = nil break end end
		end
		c = { name = ns.me, sig = Debts.B64(ns.Ed25519.Sign(seed, "OLYA1|" .. guid .. "|" .. ns.me, pk)) }
		k.claims[guid] = c
	end
	return ns.Arena.GK(guid), Debts.B64(pk), c.sig
end
Debts.ClaimParts = Claim

local claimSent = {} -- [target lower] = true: once per peer and session
function Debts.SendClaim(to, mode)
	local key = Lower(to)
	if not key or claimSent[key .. (mode or "L")] then return false end
	local gk, pk, sig = Claim()
	if not gk then return false end
	local level = UnitLevel and tonumber(UnitLevel("player")) or 0
	local ok = ns.Arena.Send("ZT", mode == "T" and "T" or "L", ("%s~%s~%s~%s"):format(gk, pk, sig, B36(level)), { to = to })
	if ok then claimSent[key .. (mode or "L")] = true end
	return ok
end

---------------------------------------------------------------------------
-- Verifying another character's claim (the design)
---------------------------------------------------------------------------

local verified = {} -- [name lower] = { name, gk, pk, fp, how, at }
local pending = {}  -- [name lower] = { name, gk, pk, sig, level, sigOk }
local byFp = {}     -- [fp] = { [name lower] = true }

-- The name GetPlayerInfoByGUID gives, rebuilt as ns.UnitFullName does (Forever splits the surname
-- into the realm's place).
local function InfoName(guid)
	if not GetPlayerInfoByGUID then return nil end
	local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not ok or type(name) ~= "string" or name == "" then return nil end
	if issecretvalue and (issecretvalue(name) or (realm ~= nil and issecretvalue(realm))) then return nil end
	if type(realm) == "string" and realm ~= "" and ns.splitNames and not ns.IsRealmName(realm) then name, realm = name .. " " .. realm, nil end
	return ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)
end
Debts.InfoName = InfoName

local TOKENS = { "NPC", "target", "focus", "mouseover" }
for i = 1, 4 do TOKENS[#TOKENS + 1] = "party" .. i end
for i = 1, 40 do TOKENS[#TOKENS + 1] = "raid" .. i end
-- How this client knows that guid is `name`: "unit" (a unit token the game gives), "info"
-- (GetPlayerInfoByGUID answered), or nil (not yet: asked again later).
function Debts.Bind(name, guid)
	if type(name) ~= "string" or type(guid) ~= "string" then return nil end
	local want = Lower(name)
	local function Unit(token)
		local ok, g = pcall(UnitGUID, token)
		if not ok or g ~= guid or (issecretvalue and issecretvalue(g)) then return false end
		return Lower(ns.UnitFullName(token)) == want
	end
	if UnitGUID then
		if UnitTokenFromGUID then
			local ok, token = pcall(UnitTokenFromGUID, guid)
			if ok and type(token) == "string" and Unit(token) then return "unit" end
		end
		for _, token in ipairs(TOKENS) do
			if Unit(token) then return "unit" end
		end
	end
	if Lower(InfoName(guid)) == want then return "info" end
	return nil
end

local function Keep(rec)
	local key = Lower(rec.name)
	local was = verified[key]
	if was and byFp[was.fp] then byFp[was.fp][key] = nil end
	verified[key] = rec
	byFp[rec.fp] = byFp[rec.fp] or {}
	byFp[rec.fp][key] = true
	-- A bank keeps the pairs it verified in its saved data (its slips never wait on a signature).
	local W = ns.Wallet
	if type(W) == "table" and type(W.KeepKey) == "function" then ns.SafeCall("arena key", W.KeepKey, rec) end
	ns.Fire("ARENA_KEY", rec.name)
end

-- A pending claim whose signature checked: bound now if a unit or the game's lookup says so.
local function TryBind(key)
	local p = pending[key]
	if not p or not p.sigOk then return nil end
	local how = Debts.Bind(p.name, ns.Arena.GuidOf(p.gk))
	if not how then return nil end
	pending[key] = nil
	local rec = { name = p.name, gk = p.gk, pk = p.pk, fp = Debts.Fp(p.pk), how = how, at = Now(), level = p.level, sig = Debts.B64(p.sig) }
	Keep(rec)
	return rec
end

function Debts.Verified(name)
	local key = Lower(name)
	if not key then return nil end
	local rec = verified[key]
	if not rec and pending[key] then rec = TryBind(key) end
	if not rec then
		local W = ns.Wallet
		local kept = type(W) == "table" and type(W.KnownKey) == "function" and W.KnownKey(name) or nil
		if kept and kept.gk and kept.pk then
			rec = { name = kept.name or name, gk = kept.gk, pk = Raw(kept.pk, 32) or kept.pk, fp = kept.fp, how = kept.how or "kept", at = kept.at }
			if rec.pk and #rec.pk == 32 then Keep(rec) else rec = nil end
		end
	end
	if not rec then return nil end
	return rec.gk, rec.fp, rec.how
end
function Debts.KeyOf(name)
	Debts.Verified(name)
	local rec = verified[Lower(name) or ""]
	return rec and rec.pk or nil
end
-- A verified claim as its owner signed it (a creditor's proof carries it): { gk, pk, sig } in
-- base64url, or nil.
function Debts.ClaimOf(name)
	Debts.Verified(name)
	local rec = verified[Lower(name) or ""]
	if not rec or not rec.sig then return nil end
	return { gk = rec.gk, pk = Debts.B64(rec.pk), sig = rec.sig }
end
function Debts.Pending(name) return pending[Lower(name) or ""] ~= nil end
-- (Tests and the bank's reload.)
function Debts.Forget(name)
	local key = Lower(name)
	if key then verified[key], pending[key] = nil, nil end
end

local function OnClaim(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local gk, pk64, sig64, level = ns.Arena.Fields(body, 4)
	local guid = ns.Arena.GuidOf(gk)
	local pk, sig = Raw(pk64, 32), Raw(sig64, 64)
	if not guid or not pk or not sig or not ns.Ed25519.ValidPublicKey(pk) then return end
	local key = Lower(sender)
	local have = verified[key]
	if have and have.gk == gk and have.pk == pk then return end
	pending[key] = { name = ns.FullName(sender), gk = gk, pk = pk, sig = sig, level = ns.Arena.N(level, 0, 100) }
	ns.Arena.Verify(sender, { pk = pk, msg = "OLYA1|" .. guid .. "|" .. ns.FullName(sender), sig = sig, key = gk .. "|" .. pk64 }, function(ok)
		local p = pending[key]
		if not p or p.gk ~= gk then return end
		if not ok then pending[key] = nil return end
		p.sigOk = true
		TryBind(key)
		ns.Arena.Changed()
	end)
end
ns.Comm.Handle("ZT", ns.Arena.Handle("ZT", OnClaim))

-- The same player: linked alts (Alts.Linked), this account's own characters, or one verified key.
function Debts.SameOwner(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	if Same(a, b) then return true end
	local Alts = ns.Alts
	if type(Alts) == "table" and type(Alts.Linked) == "function" then
		for _, n in ipairs(Alts.Linked(ns.FullName(a))) do if Same(n, b) then return true end end
	end
	local mine = ns.db and ns.db.myCharacters
	if type(mine) == "table" and mine[Lower(a)] and mine[Lower(b)] then return true end
	local ga, fa = Debts.Verified(a)
	local gb, fb = Debts.Verified(b)
	return fa ~= nil and fa == fb
end

---------------------------------------------------------------------------
-- IOUs and signed results (the design): no amount where others can read it (a salted commitment).
---------------------------------------------------------------------------

function Debts.Commit(copper, salt)
	return Debts.Hex(Debts.SHA(tostring(math.floor(tonumber(copper) or 0)) .. "|" .. tostring(salt or ""))):sub(1, 16)
end
local function IouText(mid, payerGk, payeeGk, commit) return ("OLYD1|%s|%s|%s|%s"):format(mid, payerGk, payeeGk, commit) end

function Debts.Iou(mid, payee, copper, salt)
	local payerGk = Debts.MyKey()
	local payeeGk = type(payee) == "table" and payee.gk or Debts.Verified(payee)
	if type(mid) ~= "string" or mid == "" or not payerGk or not payeeGk then return nil, "key" end
	local commit = Debts.Commit(copper, salt)
	local text = IouText(mid, payerGk, payeeGk, commit)
	local sig = Debts.Sign(text)
	if not sig then return nil, "key" end
	local iou = { mid = mid, payerGk = payerGk, payeeGk = payeeGk, commit = commit, sig = Debts.B64(sig), text = text }
	iou.wire = commit .. "." .. iou.sig
	local m = Mine("L", true)
	if m then
		m.ious[mid] = { mid = mid, payeeGk = payeeGk, commit = commit, at = Now() }
		local n, oldest = 0, nil
		for k, v in pairs(m.ious) do
			n = n + 1
			if not oldest or (v.at or 0) < (m.ious[oldest].at or 0) then oldest = k end
		end
		if n > 20 then m.ious[oldest] = nil end
	end
	return iou
end
function Debts.ReadIou(wire, mid, payerGk, payeeGk)
	if type(wire) ~= "string" then return nil end
	local commit, sig = wire:match("^(%x+)%.([%w%-_]+)$")
	if not commit or #commit ~= 16 or not Raw(sig, 64) then return nil end
	return { mid = mid, payerGk = payerGk, payeeGk = payeeGk, commit = commit, sig = sig, text = IouText(mid, payerGk, payeeGk, commit), wire = wire }
end
function Debts.CheckIou(text, sig, pk)
	sig, pk = Raw(sig, 64), Raw(pk, 32)
	if type(text) ~= "string" or not text:find("^OLYD1|") or not sig or not pk then return false end
	return ns.Ed25519.Verify(pk, text, sig) == true
end

local function ResultText(fid, round, winnerGk, loserGk) return ("OLYW1|%s|%s|%s|%s"):format(fid, tostring(round), winnerGk, loserGk) end
function Debts.SignResult(fid, round, winnerGk, loserGk)
	if type(fid) ~= "string" or not winnerGk or not loserGk then return nil end
	local sig = Debts.Sign(ResultText(fid, round, winnerGk, loserGk))
	return sig and Debts.B64(sig) or nil
end
function Debts.CheckResult(fid, round, winnerGk, loserGk, sig, pk)
	sig, pk = Raw(sig, 64), Raw(pk, 32)
	if not sig or not pk then return false end
	return ns.Ed25519.Verify(pk, ResultText(fid, round, winnerGk, loserGk), sig) == true
end

---------------------------------------------------------------------------
-- Who is told: the auditors heard lately (their hello, ZQ~H), and the fee receiver for fees
---------------------------------------------------------------------------

local auditorsHeard = {} -- [name] = time
function Debts.HeardAuditor(name) if type(name) == "string" then auditorsHeard[ns.FullName(name)] = Now() end end
function Debts.Auditors(mode)
	local out = {}
	local R = ns.ArenaRoles
	for name, t in pairs(auditorsHeard) do
		if Now() - t <= Debts.AUDITOR_FRESH and R and R.Auditor(name, mode or "L") and not Same(name, ns.me) then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end
local function ToAuditors(kind, mode, body, o)
	for _, name in ipairs(Debts.Auditors(mode)) do
		local opt = { to = name }
		for k, v in pairs(o or {}) do opt[k] = v end
		ns.Arena.Send(kind, mode, body, opt)
	end
end
Debts.ToAuditors = ToAuditors

---------------------------------------------------------------------------
-- Marks (the design, as amended): on the channel, never an amount. A debtor's own ("s"),
-- an auditor's ("l"), or the creditor's with the debtor's signed IOU and result ("c").
---------------------------------------------------------------------------

function Debts.Id(creditor, ref, debtor, kind)
	local n = Debts.First(Debts.SHA(("%s|%s|%s|%s"):format(Lower(creditor) or "-", tostring(ref or ""), Lower(debtor) or "-", tostring(kind or ""))), 5)
	local s = B36(n)
	return ("0"):rep(math.max(0, 8 - #s)) .. s
end

local function MarkBody(m)
	local body = ("%s~%s~%s~%s~%s~%s~%s~%s"):format(m.id, m.state, m.gk or "-", ns.FullName(m.name), m.kind, B36(m.since or 0), m.fp or "-", m.src)
	if m.proof then body = body .. "~" .. m.proof end
	return body
end

-- Is a mark an open debt (blocks)? Its state l or o; a creditor's only once its proof checked.
local function IsOpen(m)
	if type(m) ~= "table" or not OPEN[m.state] or m.kind == "h" then return false end
	if m.src == "c" and m.proofOk ~= true then return false end
	return true
end
Debts.IsOpen = IsOpen

-- The names a mark reaches: its own, its linked alts.
local function Reaches(m, name)
	if Same(m.name, name) then return true end
	local Alts = ns.Alts
	if type(Alts) == "table" and type(Alts.Linked) == "function" then
		for _, n in ipairs(Alts.Linked(ns.FullName(m.name))) do if Same(n, name) then return true end end
	end
	return false
end

function Debts.Marks(name, mode)
	local out = {}
	for _, m in pairs(Marks(mode)) do
		if type(m) == "table" and Reaches(m, name) then out[#out + 1] = m end
	end
	table.sort(out, function(a, b) return (a.since or 0) < (b.since or 0) end)
	return out
end

-- Blocked (the design): an open debt on him, a linked alt, his GUID (where it is his), or his
-- verified account key. Returns true, why ("debt", "alt", "guid", "key"), or false.
function Debts.Blocked(name, gk, fp, mode)
	local vgk, vfp = nil, nil
	if type(name) == "string" then vgk, vfp = Debts.Verified(name) end
	gk, fp = gk or vgk, fp or vfp
	for _, m in pairs(Marks(mode)) do
		if IsOpen(m) then
			if type(name) == "string" and Same(m.name, name) then return true, "debt" end
			if type(name) == "string" and Reaches(m, name) then return true, "alt" end
			if gk and m.gk == gk and m.gkOk then return true, "guid" end
			if fp and m.fp == fp and m.fpOk then return true, "key" end
			if type(name) == "string" and vfp and m.name and select(2, Debts.Verified(m.name)) == vfp then return true, "key" end
		end
	end
	return false
end
function Debts.Mark(name, mode)
	if Debts.Blocked(name, nil, nil, mode) then return "open" end
	return nil
end
-- An auditor's "h" mark: an arbiter at his cap shows busy to everyone.
function Debts.Busy(name, mode)
	for _, m in pairs(Marks(mode)) do
		if type(m) == "table" and m.kind == "h" and OPEN[m.state] and Same(m.name, name) then return true end
	end
	return false
end

local function Prune(list)
	local n, cleared = 0, {}
	for id, m in pairs(list) do
		n = n + 1
		if type(m) ~= "table" then list[id] = nil
		elseif not OPEN[m.state] and m.state ~= "d" and m.state ~= "m" then
			if Now() - (m.heard or 0) > Debts.CLEARED_KEEP then list[id] = nil n = n - 1 else cleared[#cleared + 1] = m end
		end
	end
	if n > Debts.MARKS_MAX then
		table.sort(cleared, function(a, b) return (a.heard or 0) < (b.heard or 0) end)
		for i = 1, math.min(#cleared, n - Debts.MARKS_MAX) do list[cleared[i].id] = nil end
	end
end

-- Whether a new word replaces the one kept (a leader's over the debtor's own; among equals, the newest).
local function Replaces(kept, m, sender)
	if not kept then return m.src ~= "c" or OPEN[m.state] end
	local rk, rn = SOURCE_RANK[kept.src] or 0, SOURCE_RANK[m.src] or 0
	-- A creditor's own mark: only he or an auditor changes it (a debtor's "c" alone is "says paid").
	if kept.src == "c" and m.src == "s" then return false end
	if kept.src == "c" and m.src == "c" and not Same(kept.from, sender) then return false end
	-- A creditor's word that the debt is over counts only over his own open mark: nobody clears a
	-- debtor's own (or an auditor's) with a mark of another source.
	if m.src == "c" and not OPEN[m.state] and kept.src ~= "c" then return false end
	if rn ~= rk then return rn > rk end
	return (m.since or 0) >= (kept.since or 0)
end

-- A creditor's proof: the payer's claim, IOU and signed result, all under the key in the mark.
local proofQueue = {}
local function PumpProofs()
	local Ed = ns.Ed25519
	while proofQueue[1] and Ed and Ed.Busy() < ns.Arena.VERIFY_BUSY do
		local job = table.remove(proofQueue, 1)
		local started = Ed.Run(job.fn, function(ok, res) ns.SafeCall("arena proof", job.cb, ok and res == true) end)
		if not started then table.insert(proofQueue, 1, job) break end
	end
	-- (Ed25519.lua runs each job on its own frames; a job that waits for room is offered again in a
	-- second, and nothing is kept going once none waits.)
	if proofQueue[1] then ns.Arena.After(1, "debts proofs", PumpProofs) end
end
Debts.ProofsWaiting = function() return #proofQueue end
function Debts.ProofParts(proof)
	if type(proof) ~= "string" then return nil end
	local mid, payeeGk, commit, iouSig, fid, round, resSig, pk, claimSig = proof:match(
		"^([%w%.%-]+):([0-9a-z]+%.%x+):(%x+):([%w%-_]+):([%w%.%-]+):([0-9a-z]+):([%w%-_]+):([%w%-_]+):([%w%-_]+)$")
	if not mid or #commit ~= 16 then return nil end
	return { mid = mid, payeeGk = payeeGk, commit = commit, iouSig = iouSig, fid = fid, round = round, resSig = resSig, pk = pk, claimSig = claimSig }
end
function Debts.MakeProof(credit)
	local c = credit
	if type(c) ~= "table" or not c.iou or not c.result or not c.claim then return nil end
	return ("%s:%s:%s:%s:%s:%s:%s:%s:%s"):format(c.mid, c.creditorGk, c.iou.commit, c.iou.sig, c.result.fid, tostring(c.result.round),
		c.result.sig, c.claim.pk, c.claim.sig)
end
local function CheckProof(m, cb)
	local p = Debts.ProofParts(m.proof)
	local guid = ns.Arena.GuidOf(m.gk)
	local pk = p and Raw(p.pk, 32)
	if not p or not guid or not pk or m.fp ~= Debts.Fp(pk) or p.mid ~= p.fid then return cb(false) end
	proofQueue[#proofQueue + 1] = { fn = function()
		local Ed = ns.Ed25519
		if not Ed.Verify(pk, "OLYA1|" .. guid .. "|" .. ns.FullName(m.name), Raw(p.claimSig, 64) or "") then return false end
		if not Ed.Verify(pk, IouText(p.mid, m.gk, p.payeeGk, p.commit), Raw(p.iouSig, 64) or "") then return false end
		return Ed.Verify(pk, ResultText(p.fid, p.round, p.payeeGk, m.gk), Raw(p.resSig, 64) or "")
	end, cb = cb }
	PumpProofs()
end

local function TakeMark(sender, m, mode)
	local list = Marks(mode, true)
	local kept = list[m.id]
	if not Replaces(kept, m, sender) then
		if kept and m.src == "s" and m.state == "c" and kept.src ~= "s" then kept.saysPaid = Now() end
		return false
	end
	m.from, m.heard = ns.FullName(sender), Now()
	m.details = kept and kept.details or nil
	-- A self mark's GUID and key count only as far as this client can tell they are his (the design).
	if m.src == "s" then
		local gk, fp = Debts.Verified(m.name)
		m.gkOk = m.gk ~= "-" and (gk == m.gk or Lower(InfoName(ns.Arena.GuidOf(m.gk) or "")) == Lower(m.name)) or nil
		m.fpOk = (m.fp ~= "-" and fp == m.fp) or nil
	elseif m.src == "l" then
		m.gkOk, m.fpOk = m.gk ~= "-" or nil, m.fp ~= "-" or nil
	end
	if m.src == "c" and OPEN[m.state] then
		m.proofOk = nil
		list[m.id] = m
		CheckProof(m, function(ok)
			local now = list[m.id]
			if now ~= m then return end
			m.proofOk = ok
			if ok then m.gkOk, m.fpOk = true, true end
			ns.Arena.Changed()
			ns.Fire("ARENA_DEBTS")
		end)
	else
		list[m.id] = m
	end
	Prune(list)
	if OPEN[m.state] and Debts.Repeating then Debts.Repeating(mode) end
	ns.Arena.Changed()
	ns.Fire("ARENA_DEBTS")
	return true
end
Debts.TakeMark = TakeMark

local function OnMark(dist, sender, mode, body)
	if dist ~= "CHANNEL" and dist ~= "RAID" and dist ~= "PARTY" then return end
	if ns.Arena.RealmOf(sender) ~= ns.realm then return end
	local id, state, gk, name, kind, since, fp, src, proof = ns.Arena.Fields(body, 9)
	if not id then
		id, state, gk, name, kind, since, fp, src = ns.Arena.Fields(body, 8)
	end
	if not id or not id:find("^[0-9a-z]+$") or #id > 12 or not STATES[state] or not MARK_KINDS[kind] then return end
	name = ns.Arena.Name(name)
	since = ns.Arena.N(since, 0)
	if not name or not since then return end
	if gk ~= "-" and not ns.Arena.GuidOf(gk) then return end
	if fp ~= "-" and not (type(fp) == "string" and fp:find("^[0-9a-z]+$") and #fp <= 12) then return end
	local R = ns.ArenaRoles
	local m = { id = id, state = state, gk = gk, name = name, kind = kind, since = since, fp = fp, src = src }
	if src == "s" then
		-- The debtor's own, or relayed as it was by an auditor (who repeats the open marks, so a
		-- debtor who quit stays marked for new clients; its source kept, his own clearing clears it).
		if kind == "h" or not (Same(sender, name) or (R and R.Auditor(sender, mode))) then return end
	elseif src == "l" then
		if not (R and R.Auditor(sender, mode)) then return end
	elseif src == "c" then
		if OPEN[state] then
			if type(proof) ~= "string" or proof == "" then return end
			m.proof = proof
		end
	else
		return
	end
	TakeMark(sender, m, mode)
end
ns.Comm.Handle("ZX", ns.Arena.Handle("ZX", OnMark))

-- Sends a mark on the public lane: a debtor's own is an obligation (it goes with the arena off,
-- must-deliver: the design).
local function SendMark(m, mode)
	local o = { must = true }
	if m.src == "s" then o.obligation = true end
	return ns.Arena.Send("ZX", mode, MarkBody(m), o)
end
Debts.SendMark = SendMark

-- An auditor's mark (source "l"): t = { id, debtor, gk, kind, state, fp }.
function Debts.LeaderMark(t, mode)
	local R = ns.ArenaRoles
	mode = mode == "T" and "T" or "L"
	if type(t) ~= "table" or not (R and R.Auditor(ns.me, mode)) then return false, "auditor" end
	local name = ns.Arena.Name(t.debtor)
	if not name or not MARK_KINDS[t.kind] or not STATES[t.state or "o"] then return false, "shape" end
	local m = { id = t.id or Debts.Id(ns.me, t.ref or "", name, t.kind), state = t.state or "o", gk = t.gk or "-", name = name, kind = t.kind,
		since = t.since or Now(), fp = t.fp or "-", src = "l" }
	TakeMark(ns.me, m, mode)
	SendMark(m, mode)
	return true, m.id
end

---------------------------------------------------------------------------
-- Auditors repeat the open marks they hold (the design): 3 a minute each at most, each mark
-- again after REPEAT_AGAIN, as it was (a relayed debtor's mark keeps its source), so a debtor who
-- quits the game or leaves Olympus stays marked for clients that come later.
---------------------------------------------------------------------------

Debts.REPEAT_AGAIN = 1800
local repeating = false
local function RepeatTick()
	local R = ns.ArenaRoles
	local any, best = false, nil
	local mode = "L"
	if R and R.Auditor(ns.me, mode) then
		for _, m in pairs(Marks(mode)) do
			if type(m) == "table" and OPEN[m.state] and (m.src ~= "c" or m.proofOk) then
				any = true
				local last = m.repeated or m.heard or 0
				if Now() - last >= Debts.REPEAT_AGAIN and (not best or last < (best.repeated or best.heard or 0)) then best = m end
			end
		end
	end
	if not any then
		repeating = false
		ns.Arena.Every(Debts.REPEAT_GAP, "debts repeat", nil)
		ns.Arena.Involve("debts repeat", false)
		return
	end
	if best then
		best.repeated = Now()
		SendMark({ id = best.id, state = best.state, gk = best.gk, name = best.name, kind = best.kind, since = best.since, fp = best.fp, src = best.src,
			proof = best.proof }, mode)
	end
end
Debts.RepeatTick = RepeatTick
function Debts.Repeating(mode)
	local R = ns.ArenaRoles
	if (mode or "L") ~= "L" or not (R and R.Auditor(ns.me, "L")) then return false end
	-- (Armed once: a new mark heard does not put the next repeat off.)
	if repeating then return true end
	repeating = true
	ns.Arena.Involve("debts repeat", true)
	ns.Arena.Every(Debts.REPEAT_GAP, "debts repeat", RepeatTick)
	return true
end

---------------------------------------------------------------------------
-- This character's obligations (the design): nothing hides one. Each prompts "Save now"
-- once; the due clock turns it late; every open one's messages go again at login.
---------------------------------------------------------------------------

local savePrompted = false
local function SaveNow()
	if savePrompted then return end
	savePrompted = true
	ns.Print(L.DEBTS_SAVE_NOW)
	ns.Fire("ARENA_SAVE_NOW")
end

local function DetailBody(o, mode)
	local creditor = o.kind == "f" and "G" or (ns.Arena.Name(o.creditor) or "G")
	return ("%s~D~%s~%s~%s~%s~%s"):format(o.id, B36(math.max(0, o.copper - (o.paid or 0))), creditor, tostring(o.ref or "-"), B36(o.due or 0), o.state)
end
local function TellDetails(o, mode)
	ToAuditors("ZY", mode, DetailBody(o, mode), { low = true })
	if o.kind == "f" then
		local R = ns.ArenaRoles
		local to = R and R.FeeReceiver()
		if to and not Same(to, ns.me) then ns.Arena.Send("ZY", mode, DetailBody(o, mode), { to = to, low = true }) end
	end
end

local function SelfMark(o, mode)
	local gk, _, fp = Debts.MyKey()
	return { id = o.id, state = o.state == "open" and "l" or o.state, gk = gk or "-", name = ns.me, kind = o.kind, since = o.lateAt or o.created, fp = fp or "-", src = "s" }
end

local Watch -- (below)

function Debts.Owe(t)
	if type(t) ~= "table" then return nil, "shape" end
	local mode = t.mode == "T" and "T" or "L"
	local kind = Debts.KIND[t.kind] or (MARK_KINDS[t.kind] and t.kind ~= "h" and t.kind) or nil
	if not kind then return nil, "kind" end
	local copper = math.floor(tonumber(t.copper) or 0)
	if copper <= 0 then return nil, "copper" end
	if t.debtor and not Same(t.debtor, ns.me) then return nil, "debtor" end
	local m = Mine(mode, true)
	if not m then return nil, "store" end
	local ref = t.ref and tostring(t.ref) or nil
	local id = t.id or Debts.Id(t.creditor or "G", ref, ns.me, kind)
	local o = m.obligations[id]
	if o and o.state ~= "c" and o.state ~= "w" then
		-- (The same obligation again: it grows, as a bank's guild fee does between two mails.)
		if t.grow then o.copper = o.copper + copper end
		return o
	end
	local gk = Debts.MyKey()
	o = { id = id, kind = kind, creditor = t.creditor and ns.FullName(t.creditor) or nil, gk = t.gk or gk, copper = copper, paid = 0,
		due = tonumber(t.due) or (Now() + Debts.DUE[kind]), ref = ref, mode = mode, state = "open", created = Now(), test = mode == "T" or nil }
	m.obligations[id] = o
	TellDetails(o, mode)
	if mode == "L" then SaveNow() end
	Debts.WatchPayments()
	Watch()
	ns.Arena.Changed()
	ns.Fire("ARENA_DEBTS")
	return o
end

local function Find(id)
	for _, mode in ipairs({ "L", "T" }) do
		local m = Mine(mode)
		local o = m and m.obligations[id]
		if o then return o, mode end
	end
	return nil
end
Debts.Find = Find

function Debts.Mailed(id, recipient, subject, ref)
	local o, mode = Find(id)
	if not o or o.state == "c" or o.state == "w" then return false end
	o.mailed = { to = ns.FullName(recipient), subject = subject, ref = ref, at = Now() }
	local wasLate = OPEN[o.state]
	o.state = "m"
	if wasLate then SendMark(SelfMark(o, mode), mode) end
	TellDetails(o, mode)
	ns.Arena.Changed()
	return true
end
function Debts.Returned(id)
	local o, mode = Find(id)
	if not o or o.state ~= "m" then return false end
	o.mailed = nil
	o.state = "open"
	TellDetails(o, mode)
	Watch()
	return true
end

function Debts.Paid(id, copper, how)
	local o, mode = Find(id)
	if not o or o.state == "c" or o.state == "w" then return nil end
	o.paid = (o.paid or 0) + math.max(0, math.floor(tonumber(copper) or 0))
	o.how = how
	if o.paid >= o.copper then
		ns.ArenaMoney.Forget("debt:" .. o.id)
		local wasPublic = OPEN[o.state] or o.marked
		local onTime = Now() <= o.due or o.state == "m"
		o.state, o.cleared = "c", Now()
		if wasPublic then SendMark(SelfMark(o, mode), mode) end
		if onTime and mode == "L" and o.kind == "b" then
			local rec = Mine(mode).record
			rec.paidMax = math.max(tonumber(rec.paidMax) or 0, o.copper)
		end
	end
	TellDetails(o, mode)
	ns.Arena.Changed()
	ns.Fire("ARENA_DEBTS")
	return o
end

-- The fill for one of this character's guild fees (an arbiter's "A<id>", a direct winner's
-- "D<id>"): exactly what is owed, to the fee receiver, with its ref; the player presses Send (the
-- postage is his, on top). Refused while the receiver's 1.2 client was not heard (the fee stays
-- owed without turning late), the design.
function Debts.PayFee(id)
	local o, mode = Find(id)
	if not o or o.kind ~= "f" or o.state == "c" or o.state == "w" then return nil, "fee" end
	local R = ns.ArenaRoles
	local to = R and R.FeeReceiver()
	if not to then ns.Print(L.WALLET_NO_RECEIVER) return nil, "receiver" end
	local W = ns.Wallet
	if mode == "L" and W and W.ReceiverUpdated and not W.ReceiverUpdated() then ns.Print(L.WALLET_RECEIVER_OLD) return nil, "updated" end
	local copper = o.copper - (o.paid or 0)
	local subject = ns.ArenaMoney.Subject("fee", o.ref, mode == "T")
	return { to = to, copper = copper, subject = subject, fill = ns.ArenaMoney.FillMail(to, subject, copper) }
end

function Debts.Disputed(id, evidence)
	local o, mode = Find(id)
	if not o then return false end
	o.state = "d"
	o.dispute = tostring(evidence or ""):gsub("[~|%c]", " "):sub(1, 120)
	local body = ("%s~X~%s~%s"):format(o.id, ns.FullName(ns.me), o.dispute ~= "" and o.dispute or "-")
	ToAuditors("ZY", mode, body)
	local R = ns.ArenaRoles
	for _, b in ipairs(R and R.Banks(mode) or {}) do
		if not Same(b.name, ns.me) then ns.Arena.Send("ZY", mode, body, { to = b.name, low = true }) end
	end
	ns.Arena.Changed()
	return true
end

function Debts.Open(mode)
	local out = {}
	local m = Mine(mode or "L")
	for _, o in pairs(m and m.obligations or {}) do
		if type(o) == "table" and o.state ~= "c" and o.state ~= "w" then out[#out + 1] = o end
	end
	table.sort(out, function(a, b) return (a.created or 0) < (b.created or 0) end)
	return out
end

---------------------------------------------------------------------------
-- The creditor's side of a direct debt (the design): what it waits for; late, it publishes the
-- debtor's own signatures, which any client checks, and the debt is open everywhere.
---------------------------------------------------------------------------

function Debts.Credit(t)
	if type(t) ~= "table" then return nil, "shape" end
	local mode = t.mode == "T" and "T" or "L"
	local m = Mine(mode, true)
	local debtor = ns.Arena.Name(t.debtor)
	local copper = math.floor(tonumber(t.copper) or 0)
	if not m or not debtor or copper <= 0 then return nil, "shape" end
	local id = t.id or Debts.Id(ns.me, t.ref, debtor, "b")
	local c = m.credits[id]
	if not c then
		c = { id = id, mid = t.mid or (t.result and t.result.fid) or t.ref, debtor = debtor, copper = copper, received = 0, ref = t.ref,
			due = tonumber(t.due) or (Now() + Debts.DUE.b), mode = mode, state = "open", created = Now(), feeBp = t.feeBp, how = t.how }
		m.credits[id] = c
	end
	c.creditorGk = Debts.MyKey()
	c.debtorGk = t.debtorGk or Debts.Verified(debtor)
	if t.iou then c.iou = { commit = t.iou.commit, sig = t.iou.sig } end
	if t.result then c.result = { fid = t.result.fid, round = t.result.round, sig = t.result.sig } end
	-- The debtor's claim as this client verified it (his signature over his GUID and name).
	c.claim = t.claim or Debts.ClaimOf(debtor) or c.claim
	Debts.WatchPayments()
	Watch()
	return c
end

---------------------------------------------------------------------------
-- Receipts (ZR): the second record of every payment, from both sides.
---------------------------------------------------------------------------

-- t = { ref, payer, payee, copper, how = "t"|"m", time, onTime, to = { names }, mode }
function Debts.Receipt(t)
	if type(t) ~= "table" then return false end
	local mode = t.mode == "T" and "T" or "L"
	local payer, payee = ns.Arena.Name(t.payer), ns.Arena.Name(t.payee)
	local copper = math.floor(tonumber(t.copper) or 0)
	if not payer or not payee or copper <= 0 or type(t.ref) ~= "string" then return false end
	local body = ("%s~%s~%s~%s~%s~%s~%s"):format(t.ref, payer, payee, B36(copper), t.how == "m" and "m" or "t", B36(t.time or Now()),
		t.onTime == false and "0" or "1")
	local sent = {}
	for _, name in ipairs(t.to or {}) do
		if type(name) == "string" and not Same(name, ns.me) and not sent[Lower(name)] then
			sent[Lower(name)] = true
			ns.Arena.Send("ZR", mode, body, { to = name, must = true })
		end
	end
	if t.auditors ~= false then
		for _, name in ipairs(Debts.Auditors(mode)) do
			if not sent[Lower(name)] then
				sent[Lower(name)] = true
				ns.Arena.Send("ZR", mode, body, { to = name, must = true })
			end
		end
	end
	-- A direct bet's payment and an arbiter's payout also go to the banks: the standing token a
	-- bank signs counts them (the design).
	if t.ref:find("^[DP]") and mode == "L" then
		local R = ns.ArenaRoles
		for _, b in ipairs(R and R.Banks(mode) or {}) do
			if b.state == "o" and not sent[Lower(b.name)] and not Same(b.name, ns.me) then
				sent[Lower(b.name)] = true
				ns.Arena.Send("ZR", mode, body, { to = b.name, must = true, low = true })
			end
		end
	end
	return true
end

-- A keeper's excluded "arena" line (Treasury.Record): the auditors see it.
function Debts.KeeperReceipt(name, copper, how, out)
	local payer, payee = out and ns.me or name, out and name or ns.me
	return Debts.Receipt({ ref = "K" .. B36(Now()), payer = payer, payee = payee, copper = copper, how = how == "mail" and "m" or "t" })
end

-- The payee's side of a payment: the payer says he paid (his receipt); the payee's own client
-- confirms it once its watcher saw that gold land from him (an arbiter's payout or refund), and
-- that confirmation is what clears the payer's obligation. Kept 10 minutes either way round.
Debts.ECHO_FOR = 600
local echoes, landed = {}, {} -- [payer lower] = { receipts waiting }, { flows seen }
local function Echo(r, how)
	r.echoed = true
	Debts.Receipt({ ref = r.ref, payer = r.payer, payee = ns.me, copper = r.copper, how = how or r.how, mode = r.mode, to = { r.payer } })
	-- (A match's payout or refund is its last: the party's watch for it ends, Stakes.Open.)
	local id = r.ref:match("^[PR](.+)$")
	if id then ns.ArenaMoney.Forget("back:" .. id) end
	ns.Fire("ARENA_RECEIVED", r.payer, r.copper, r.ref)
end
local function Fresh(list)
	for i = #list, 1, -1 do if Now() - (list[i].heard or list[i].t or 0) > Debts.ECHO_FOR then table.remove(list, i) end end
	return list
end
-- A flow in from `partner` (the watcher): a receipt of his waiting for it is confirmed.
function Debts.Landed(partner, copper, how)
	local key = Lower(partner)
	if not key then return end
	for _, r in ipairs(Fresh(echoes[key] or {})) do
		if not r.echoed and r.copper == copper then Echo(r, how) return end
	end
	landed[key] = Fresh(landed[key] or {})
	table.insert(landed[key], { copper = copper, how = how, t = Now() })
end

-- Receipts heard (auditors: exposure and evidence; banks: the token's history).
Debts.receiptHooks = {} -- fn(r, sender, mode)
local function OnReceipt(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local ref, payer, payee, copper, how, time, onTime = ns.Arena.Fields(body, 7)
	payer, payee = ns.Arena.Name(payer), ns.Arena.Name(payee)
	copper, time = ns.Arena.Copper(copper), ns.Arena.N(time, 0)
	if not ref or not ref:find("^[%w%.%-]+$") or #ref > 32 or not payer or not payee or not copper or not time then return end
	-- A party of that payment, speaking for himself.
	if not Same(sender, payer) and not Same(sender, payee) then return end
	local r = { ref = ref, payer = payer, payee = payee, copper = copper, how = how == "m" and "m" or "t", time = time, onTime = onTime ~= "0",
		from = ns.FullName(sender), heard = Now() }
	-- The creditor's receipt clears the debtor's obligation of that ref.
	if Same(payer, ns.me) and Same(sender, payee) then
		local m = Mine(mode)
		for _, o in pairs(m and m.obligations or {}) do
			if type(o) == "table" and o.ref == ref and Same(o.creditor, payee) and o.state ~= "c" and o.state ~= "w" then
				Debts.Paid(o.id, copper, r.how)
			end
		end
	end
	local R = ns.ArenaRoles
	if R and R.Auditor(ns.me, mode) then
		local s = Store(mode)
		s.receipts = type(s.receipts) == "table" and s.receipts or {}
		local list = s.receipts
		list[#list + 1] = r
		while #list > 2000 do table.remove(list, 1) end
	end
	-- The payer's word to me, the payee: confirmed once I saw the gold (before or after this).
	r.mode = mode
	if Same(payee, ns.me) and Same(sender, payer) and not ref:find("^[WK]") then
		local key = Lower(payer)
		local seen = Fresh(landed[key] or {})
		local match
		for i, f in ipairs(seen) do if f.copper == copper then match = i break end end
		if match then
			local f = table.remove(seen, match)
			Echo(r, f.how)
		else
			echoes[key] = Fresh(echoes[key] or {})
			table.insert(echoes[key], r)
		end
	end
	for _, fn in ipairs(Debts.receiptHooks) do ns.SafeCall("arena receipt", fn, r, sender, mode) end
	ns.Arena.Changed()
end
ns.Comm.Handle("ZR", ns.Arena.Handle("ZR", OnReceipt))

---------------------------------------------------------------------------
-- Details (ZY): to auditors (a fee's also to the fee receiver; a dispute also to the banks)
---------------------------------------------------------------------------

Details = function(mode)
	local s = Store(mode)
	if not s then return {} end
	s.details = type(s.details) == "table" and s.details or {}
	return s.details
end
PruneDetails = function(d)
	local n, list = 0, {}
	for id, e in pairs(d) do n = n + 1 list[#list + 1] = e end
	if n <= Debts.MARKS_MAX then return end
	table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
	for i = 1, n - Debts.MARKS_MAX do d[list[i].id] = nil end
end

local function OnDetails(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local id, what, rest = ns.Arena.Fields(body, 3)
	if not id or not id:find("^[0-9a-z]+$") or #id > 12 then return end
	local R = ns.ArenaRoles
	local auditor = R and R.Auditor(ns.me, mode)
	local receiver = R and R.IsFeeReceiver(ns.me)
	local bank = R and R.IsBank(ns.me, mode)
	if what == "D" then
		local copper, creditor, ref, due, state = ns.Arena.Fields(rest, 5)
		copper, due = ns.Arena.Copper(copper), ns.Arena.N(due, 0)
		if not copper or not due or not (STATES[state] or state == "open") then return end
		if not auditor and not (receiver and creditor == "G") then return end
		-- Kept apart from the public marks: a claim alone never blocks anyone (the design).
		local d = Details(mode)
		local was = d[id]
		d[id] = { id = id, copper = copper, creditor = creditor == "G" and "G" or ns.Arena.Name(creditor), ref = ref, due = due, state = state,
			from = ns.FullName(sender), at = Now(), key = was and was.key }
		PruneDetails(d)
	elseif what == "K" then
		if not auditor then return end
		local gk, pk, sig = ns.Arena.Fields(rest, 3)
		local d = Details(mode)
		d[id] = d[id] or { id = id, from = ns.FullName(sender), at = Now() }
		d[id].key = { gk = gk, pk = pk, sig = sig, from = ns.FullName(sender) }
	elseif what == "X" then
		if not auditor and not bank then return end
		local acting, evidence = ns.Arena.Fields(rest, 2)
		local s = Store(mode)
		s.disputes = type(s.disputes) == "table" and s.disputes or {}
		s.disputes[id] = { acting = ns.Arena.Name(acting) or ns.FullName(sender), evidence = evidence, from = ns.FullName(sender), at = Now(), open = true }
	end
	ns.Arena.Changed()
end
ns.Comm.Handle("ZY", ns.Arena.Handle("ZY", OnDetails))

-- An open dispute against him (his direct cap is 0 until an auditor clears it, the design).
function Debts.InDispute(name, mode)
	local s = Peek(mode)
	for _, d in pairs(s and type(s.disputes) == "table" and s.disputes or {}) do
		if type(d) == "table" and d.open and Same(d.acting, name) then return true end
	end
	return false
end
function Debts.ClearDispute(id, mode)
	local s = Peek(mode)
	local d = s and type(s.disputes) == "table" and s.disputes[id]
	if d then d.open = false return true end
	return false
end

---------------------------------------------------------------------------
-- Fee receipts (ZF): the fee receiver's client says it took the guild's fee, by ref. The payer's
-- obligation of that ref clears when the copper covers it; a smaller one leaves the rest owed.
---------------------------------------------------------------------------

Debts.FEES_MAX = 200
local function FeeBody(f) return ("%s~%s~%s~%s"):format(ns.FullName(f.payer), B36(f.copper), f.ref, B36(f.t)) end

-- Sends what waits in db.arenaFees (the account's): from a character in an Olympus guild only
-- (outside one the addon sends nothing: the Treasurer's main relays his mail character's).
function Debts.SendFees()
	local fees = ns.db and ns.db.arenaFees
	if type(fees) ~= "table" then return 0 end
	local R = ns.ArenaRoles
	if not (R and R.IsFeeReceiver(ns.me)) or not ns.IsMember() then return 0 end
	local n = 0
	for key, f in pairs(fees) do
		if type(f) == "table" and not f.sent then
			local mode = f.mode == "T" and "T" or "L"
			if ns.Arena.Send("ZF", mode, FeeBody(f), { to = f.payer, must = true }) then
				for _, name in ipairs(Debts.Auditors(mode)) do ns.Arena.Send("ZF", mode, FeeBody(f), { to = name }) end
				f.sent = Now()
				n = n + 1
			end
		end
	end
	-- (Sent ones are kept a day, then go.)
	for key, f in pairs(fees) do
		if type(f) ~= "table" or (f.sent and Now() - f.sent > 86400) then fees[key] = nil end
	end
	return n
end

function Debts.FeeReceipt(payer, copper, ref, mode)
	if not ns.db or type(payer) ~= "string" or type(ref) ~= "string" then return false end
	copper = math.floor(tonumber(copper) or 0)
	if copper <= 0 then return false end
	ns.db.arenaFees = type(ns.db.arenaFees) == "table" and ns.db.arenaFees or {}
	local fees = ns.db.arenaFees
	local key = ("%s|%s|%d"):format(Lower(payer), ref, copper)
	if fees[key] then return false end
	local n = 0
	for _ in pairs(fees) do n = n + 1 end
	if n >= Debts.FEES_MAX then ns.Log("arena fee receipts full") return false end
	fees[key] = { payer = ns.FullName(payer), copper = copper, ref = ref, t = Now(), mode = mode == "T" and "T" or "L" }
	Debts.SendFees()
	return true
end

-- The fee mail as the treasury recorded it (the Treasurer's characters: Treasury.Record fires
-- TREASURY_FEE), or as the watcher saw it taken (a named receiver without a treasury).
ns.On("TREASURY_FEE", function(sender, copper, ref, test)
	Debts.FeeReceipt(sender, copper, ref, test and "T" or "L")
end)

local function OnFee(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local R = ns.ArenaRoles
	if not (R and R.IsFeeReceiver(sender)) then return end
	local payer, copper, ref, time = ns.Arena.Fields(body, 4)
	payer, copper, time = ns.Arena.Name(payer), ns.Arena.Copper(copper), ns.Arena.N(time, 0)
	if not payer or not copper or not ref or not ref:find("^[%w%.%-]+$") then return end
	if R.Auditor(ns.me, mode) then
		local s = Store(mode)
		s.fees = type(s.fees) == "table" and s.fees or {}
		s.fees[#s.fees + 1] = { payer = payer, copper = copper, ref = ref, time = time, from = ns.FullName(sender) }
		while #s.fees > 500 do table.remove(s.fees, 1) end
	end
	if not Same(payer, ns.me) then return end
	local m = Mine(mode)
	for _, o in pairs(m and m.obligations or {}) do
		if type(o) == "table" and o.kind == "f" and o.ref == ref and o.state ~= "c" and o.state ~= "w" then
			local owed = o.mailed and o.mailed.copper or (o.copper - (o.paid or 0))
			Debts.Paid(o.id, math.min(copper, o.copper - (o.paid or 0)), "m")
			if copper < owed then ns.Log("arena fee %s: %d of %d received", ref, copper, owed) end
			ns.Fire("ARENA_FEE_CLEARED", ref, copper)
		end
	end
end
ns.Comm.Handle("ZF", ns.Arena.Handle("ZF", OnFee))

---------------------------------------------------------------------------
-- Payments as this client sees them land (ArenaMoney's watcher): a debtor paying his creditor, a
-- creditor receiving it, a fee mailed or come back, the fee receiver taking one.
---------------------------------------------------------------------------

local function How(r) return r.kind == "trade" and "t" or "m" end

-- The creditor received gold from his debtor: his receipt goes to the debtor (it clears the
-- debt there) and the auditors; in direct mode the winner now owes the guild its fee on what he
-- received, and on nothing else (the design).
local function Received(c, copper, r, mode)
	local take = math.min(copper, c.copper - (c.received or 0))
	if take <= 0 then return 0 end
	local before = c.received or 0
	c.received = before + take
	Debts.Receipt({ ref = c.ref or c.id, payer = c.debtor, payee = ns.me, copper = take, how = How(r), mode = mode, to = { c.debtor },
		onTime = Now() <= c.due })
	if c.feeBp and c.feeBp > 0 and mode == "L" then
		local M = ns.ArenaMath
		local fee = (M.IDiv(c.received * c.feeBp, 10000) or 0) - (M.IDiv(before * c.feeBp, 10000) or 0)
		local R = ns.ArenaRoles
		if fee > 0 and R and R.FeeReceiver() then
			local id = Debts.Id("G", "D" .. tostring(c.mid or c.id), ns.me, "f")
			local o = Mine(mode).obligations[id]
			if o and o.state ~= "c" and o.state ~= "w" then
				o.copper = o.copper + fee
				TellDetails(o, mode)
			else
				Debts.Owe({ id = id, kind = "fee", copper = fee, creditor = nil, ref = "D" .. tostring(c.mid or c.id), due = Now() + Debts.DUE.f, mode = mode })
			end
		end
	end
	if c.received >= c.copper then
		c.state, c.paidAt = "paid", Now()
		ns.ArenaMoney.Forget("credit:" .. c.id)
		if c.published and c.debtorGk then
			local mark = { id = c.id, state = "c", gk = c.debtorGk, name = c.debtor, kind = "b", since = Now(), fp = "-", src = "c" }
			TakeMark(ns.me, mark, mode)
			SendMark(mark, mode)
		end
		if mode == "L" then Standing.Earn(ns.me, "direct", c.debtorGk or c.debtor, c.copper) end
	end
	ns.Arena.Changed()
	return take
end

local function OnFlow(r)
	local Money = ns.ArenaMoney
	local out, copper = Money.Net(r)
	if copper <= 0 then return end
	local kind, ref, test = Money.ReadSubject(r.subject)
	if not out and (r.kind == "trade" or r.kind == "mailTaken") then Debts.Landed(r.partner, copper, How(r)) end
	-- The fee receiver took a fee mail (a named receiver; the Treasurer's characters get theirs
	-- from the treasury's own record, TREASURY_FEE).
	if r.kind == "mailTaken" and kind == "fee" and ref and not ns.IsTreasurerCharacter(ns.me) then
		local R = ns.ArenaRoles
		if R and R.IsFeeReceiver(ns.me) then Debts.FeeReceipt(r.partner, copper, ref, test and "T" or "L") end
		return
	end
	for _, mode in ipairs({ "L", "T" }) do
		local m = Mine(mode)
		if m then
			if r.kind == "mailSent" and kind == "fee" and ref then
				-- A fee mailed: the clock stops at the send, for exactly that recipient and ref.
				for _, o in pairs(m.obligations) do
					if o.kind == "f" and o.ref == ref and o.state ~= "c" and o.state ~= "w" then
						Debts.Mailed(o.id, r.partner, r.subject, ref)
						o.mailed.copper = copper
					end
				end
			elseif r.kind == "mailReturned" and kind == "fee" and ref then
				for _, o in pairs(m.obligations) do
					if o.kind == "f" and o.ref == ref and o.state == "m" then Debts.Returned(o.id) end
				end
			elseif out then
				-- A payment to a creditor: this side's receipt goes; his clears it.
				for _, o in pairs(m.obligations) do
					if copper > 0 and o.kind ~= "f" and o.state ~= "c" and o.state ~= "w" and o.creditor and Same(o.creditor, r.partner) then
						local part = math.min(copper, o.copper - (o.paid or 0) - (o.sent or 0))
						if part > 0 then
							o.sent = (o.sent or 0) + part
							copper = copper - part
							Debts.Receipt({ ref = o.ref or o.id, payer = ns.me, payee = o.creditor, copper = part, how = How(r), mode = mode, to = { o.creditor },
								onTime = Now() <= o.due })
						end
					end
				end
			else
				for _, c in pairs(m.credits) do
					if copper > 0 and c.state == "open" and Same(c.debtor, r.partner) then copper = copper - Received(c, copper, r, mode) end
				end
			end
		end
	end
end
ns.ArenaMoney.Subscribe(function(r) OnFlow(r) end)

-- What this client watches for: each open debt's payment, each credit's, and the fee receiver's
-- fee mails (installed only where one exists: the weight rule).
function Debts.WatchPayments()
	local Money = ns.ArenaMoney
	for _, mode in ipairs({ "L", "T" }) do
		local m = Mine(mode)
		for _, o in pairs(m and m.obligations or {}) do
			if type(o) == "table" and o.state ~= "c" and o.state ~= "w" and o.creditor and o.kind ~= "f" then
				Money.Expect("debt:" .. o.id, { partner = o.creditor, dir = "out", upTo = o.copper, mode = mode, ref = o.ref })
			elseif type(o) == "table" and o.kind == "f" and o.state ~= "c" and o.state ~= "w" then
				local R = ns.ArenaRoles
				local to = R and R.FeeReceiver()
				if to then Money.Expect("debt:" .. o.id, { partner = to, dir = "out", subjectPrefix = "Arena fee", mode = mode, ref = o.ref }) end
			else
				Money.Forget("debt:" .. tostring(o and o.id))
			end
		end
		for _, c in pairs(m and m.credits or {}) do
			if type(c) == "table" and c.state == "open" then
				Money.Expect("credit:" .. c.id, { partner = c.debtor, dir = "in", upTo = c.copper, mode = mode, ref = c.ref })
			end
		end
	end
	local R = ns.ArenaRoles
	if R and R.IsFeeReceiver(ns.me) and not ns.IsTreasurerCharacter(ns.me) then
		Money.Expect("fee receiver", { dir = "in", subjectPrefix = "Arena fee" })
	else
		Money.Forget("fee receiver")
	end
end
ns.On("ARENA_CHANGED", function()
	local R = ns.ArenaRoles
	local Money = ns.ArenaMoney
	local want = R and R.IsFeeReceiver(ns.me) and not ns.IsTreasurerCharacter(ns.me)
	if (want and not Money.Expects("fee receiver")) or (not want and Money.Expects("fee receiver")) then Debts.WatchPayments() end
end)

---------------------------------------------------------------------------
-- The due clock and the login resend (the design): while anything is owed here, every 30 s.
---------------------------------------------------------------------------

local function Tick()
	local any = false
	for _, mode in ipairs({ "L", "T" }) do
		local m = Mine(mode)
		for _, o in pairs(m and m.obligations or {}) do
			if type(o) == "table" and o.state ~= "c" and o.state ~= "w" then
				any = true
				local W = ns.Wallet
				local receiverOk = o.kind ~= "f" or not (type(W) == "table" and W.ReceiverUpdated) or W.ReceiverUpdated()
				if o.state == "open" and Now() > o.due and receiverOk then
					o.state, o.lateAt = "l", Now()
					o.marked = true
					if mode == "L" then Standing.Late(ns.me) end
					SendMark(SelfMark(o, mode), mode)
					TellDetails(o, mode)
				elseif o.state == "l" and Now() > (o.lateAt or 0) + Debts.LATE_OPEN then
					o.state = "o"
					SendMark(SelfMark(o, mode), mode)
				elseif o.state == "m" and Now() > (o.mailed and o.mailed.at or 0) + Debts.MAILED_WAIT then
					o.state = "open"
					TellDetails(o, mode)
				end
			end
		end
		for _, c in pairs(m and m.credits or {}) do
			if type(c) == "table" and c.state == "open" then
				any = true
				if Now() > c.due and not c.published then
					c.published = Now()
					local proof = c.iou and c.result and c.claim and c.claim.sig and Debts.MakeProof(c) or nil
					if proof and c.debtorGk then
						local dfp = Debts.Fp(Raw(c.claim.pk, 32) or "")
						local mark = { id = c.id, state = "l", gk = c.debtorGk, name = c.debtor, kind = "b", since = Now(), fp = dfp, src = "c", proof = proof }
						TakeMark(ns.me, mark, mode)
						SendMark(mark, mode)
					end
					-- The auditors get the claim whatever: an auditor can mark it without a proof, with the
					-- debtor's own signed key claim (ZY K: anyone can check it; nobody else can make it).
					ToAuditors("ZY", mode, ("%s~D~%s~%s~%s~%s~%s"):format(c.id, B36(c.copper - c.received), ns.FullName(ns.me), tostring(c.ref or "-"),
						B36(c.due), "l"))
					if c.claim and c.debtorGk then ToAuditors("ZY", mode, ("%s~K~%s~%s~%s"):format(c.id, c.debtorGk, c.claim.pk, tostring(c.claim.sig))) end
				end
			end
		end
	end
	if not any then
		ns.Arena.Every(Debts.CHECK_EVERY, "debts", nil)
		ns.Arena.Involve("debts", false)
	end
end
Debts.Tick = Tick
Watch = function()
	ns.Arena.Involve("debts", true)
	ns.Arena.Every(Debts.CHECK_EVERY, "debts", Tick)
end

-- At login: every open obligation's messages go again (a mark that was public, the details), and
-- the fee receipts that wait.
function Debts.Resend()
	local any = false
	for _, mode in ipairs({ "L", "T" }) do
		local m = Mine(mode)
		for _, o in pairs(m and m.obligations or {}) do
			if type(o) == "table" and o.state ~= "c" and o.state ~= "w" then
				any = true
				if OPEN[o.state] or o.marked then SendMark(SelfMark(o, mode), mode) end
				TellDetails(o, mode)
			end
		end
		for _, c in pairs(m and m.credits or {}) do
			if type(c) == "table" and c.state == "open" then any = true end
		end
	end
	if any then Watch() Tick() end
	Debts.WatchPayments()
	Debts.SendFees()
end
-- Anything this character owes, is owed, or holds for others to send (the fee receipts).
function Debts.Waiting()
	for _, mode in ipairs({ "L", "T" }) do
		local m = Mine(mode)
		for _, o in pairs(m and m.obligations or {}) do if type(o) == "table" and o.state ~= "c" and o.state ~= "w" then return true end end
		for _, c in pairs(m and m.credits or {}) do if type(c) == "table" and c.state == "open" then return true end end
	end
	for _, f in pairs(ns.db and type(ns.db.arenaFees) == "table" and ns.db.arenaFees or {}) do
		if type(f) == "table" and not f.sent then return true end
	end
	return false
end
ns.On("LOGIN", function()
	-- (After the guild and the channel settle, as the King's words wait; only where something
	-- waits: an idle client runs no arena timer.)
	if Debts.Waiting() then ns.Arena.After(45, "debts login", Debts.Resend) end
	-- An auditor holding open marks repeats them (the loop stops by itself once none is open).
	local R0 = ns.ArenaRoles
	if R0 and R0.Auditor(ns.me, "L") then
		for _, m in pairs(Marks("L")) do
			if type(m) == "table" and OPEN[m.state] then Debts.Repeating("L") break end
		end
	end
	-- The fee receiver's own watch (a named receiver without a treasury).
	local R = ns.ArenaRoles
	if R and R.IsFeeReceiver(ns.me) and not ns.IsTreasurerCharacter(ns.me) then Debts.WatchPayments() end
end)

---------------------------------------------------------------------------
-- The freeze (the design): while a linked name has an open mark, the debtor's alt links stay.
---------------------------------------------------------------------------

if ns.Alts and type(ns.Alts.freezers) == "table" then
	table.insert(ns.Alts.freezers, function(names)
		for _, mode in ipairs({ "L" }) do
			for _, name in ipairs(names) do
				for _, m in pairs(Marks(mode)) do
					if IsOpen(m) and Same(m.name, name) then return true end
				end
				-- This character's own open obligations freeze too.
				if Same(name, ns.me) then
					for _, o in ipairs(Debts.Open(mode)) do
						if OPEN[o.state] then return true end
					end
				end
			end
		end
		return false
	end)
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------

function Debts.View(mode)
	mode = mode == "T" and "T" or "L"
	local m = Mine(mode) or { obligations = {}, credits = {} }
	local obligations, credits = {}, {}
	for _, o in pairs(m.obligations) do
		if type(o) == "table" then
			obligations[#obligations + 1] = { id = o.id, kind = Debts.KIND_NAME[o.kind] or o.kind, creditor = o.creditor, copper = o.copper, paid = o.paid or 0,
				due = o.due, ref = o.ref, state = o.state, late = OPEN[o.state] or false, mailed = o.mailed and true or false, test = o.test }
		end
	end
	for _, c in pairs(m.credits) do
		if type(c) == "table" then
			credits[#credits + 1] = { id = c.id, debtor = c.debtor, copper = c.copper, received = c.received or 0, due = c.due, ref = c.ref, state = c.state,
				published = c.published and true or false }
		end
	end
	table.sort(obligations, function(a, b) return (a.due or 0) < (b.due or 0) end)
	table.sort(credits, function(a, b) return (a.due or 0) < (b.due or 0) end)
	local blocked, why = Debts.Blocked(ns.me, nil, nil, mode)
	return { obligations = obligations, credits = credits, marks = Debts.Marks(ns.me, mode), blocked = blocked, why = why }
end

-- Auditors only (the design): every mark with its details, the disputes, the fee receipts.
function Debts.Ledger(mode)
	mode = mode == "T" and "T" or "L"
	local R = ns.ArenaRoles
	if not (R and R.Auditor(ns.me, mode)) then return nil end
	local s = Store(mode)
	local marks, d = {}, Details(mode)
	for _, m in pairs(Marks(mode)) do
		if type(m) == "table" then
			local e = d[m.id] or {}
			marks[#marks + 1] = { id = m.id, name = ns.Arena.Mask(m.name), state = m.state, kind = Debts.KIND_NAME[m.kind] or m.kind, src = m.src, since = m.since,
				proofOk = m.proofOk, saysPaid = m.saysPaid, copper = e.copper, creditor = e.creditor and e.creditor ~= "G" and ns.Arena.Mask(e.creditor) or e.creditor,
				ref = e.ref, due = e.due, open = IsOpen(m) }
		end
	end
	table.sort(marks, function(a, b) return (a.since or 0) > (b.since or 0) end)
	-- Claims and obligations the auditors know of that are no public mark (yet).
	local claims = {}
	for id, e in pairs(d) do
		if not Marks(mode)[id] then
			claims[#claims + 1] = { id = id, debtor = e.from and ns.Arena.Mask(e.from), copper = e.copper, creditor = e.creditor, ref = e.ref, due = e.due,
				state = e.state, key = e.key and true or false }
		end
	end
	table.sort(claims, function(a, b) return (a.due or 0) < (b.due or 0) end)
	return { marks = marks, claims = claims, disputes = s.disputes or {}, fees = s.fees or {}, receipts = s.receipts or {} }
end

---------------------------------------------------------------------------
-- Standing (the design, as amended): points count volume; a late payment halves them and
-- puts a tier on probation for 7 days; any open debt makes every cap 0. The bank's record decides
-- its own caps and the token it signs; nobody trusts a number a player reports of himself.
---------------------------------------------------------------------------

Standing.DAILY = { wallet = 3, arbiter = 3, direct = 2 }

local function DayKey(t) return math.floor((t or Now()) / 86400) end

-- The record kept for a key (a bank's or an auditor's), or this character's own view.
local function RecordOf(name, mode, create)
	mode = mode == "T" and "T" or "L"
	if Same(name, ns.me) then
		local m = Mine(mode, create)
		return m and m.record
	end
	local gk = Debts.Verified(name)
	local s = create and Store(mode) or Peek(mode)
	if not s then return nil end
	if type(s.standing) ~= "table" then
		if not create then return nil end
		s.standing = {}
	end
	local key = gk or ("n:" .. (Lower(name) or "?"))
	local rec = s.standing[key]
	-- (Kept by name before his key was verified: it becomes the key's.)
	if not rec and gk and s.standing["n:" .. (Lower(name) or "?")] then
		rec = s.standing["n:" .. Lower(name)]
		s.standing["n:" .. Lower(name)], s.standing[gk] = nil, rec
		rec.gk = gk
	end
	if not rec and create then
		rec = { gk = gk, name = ns.FullName(name), points = 0 }
		s.standing[key] = rec
		local n = 0
		for _ in pairs(s.standing) do n = n + 1 end
		if n > 5000 then
			local oldest, ot
			for k, r in pairs(s.standing) do
				if type(r) == "table" and (not ot or (r.active or 0) < ot) then oldest, ot = k, r.active or 0 end
			end
			if oldest then s.standing[oldest] = nil end
		end
	end
	return rec
end
Standing.RecordOf = RecordOf

-- The ArenaMath record: { points, probation, open, dispute, paidMax }.
function Standing.Record(name, mode)
	local rec = RecordOf(name, mode) or {}
	return { points = math.max(0, math.floor(tonumber(rec.points) or 0)), probation = (tonumber(rec.probation) or 0) > Now() or nil,
		open = Debts.Blocked(name, nil, nil, mode) or nil, dispute = Debts.InDispute(name, mode) or nil,
		paidMax = math.max(0, math.floor(tonumber(rec.paidMax) or 0)) }
end
function Standing.Points(name, mode) return Standing.Record(name, mode).points end

local function Settings()
	local R = ns.ArenaRoles
	return R and R.Settings() or {}
end

-- A settled stake earns a point (the design): at least max(minBet, a quarter of the tier's cap for
-- that kind), within the day's limits, against different keys (never his own alts).
function Standing.Earn(name, kind, peerKey, copper, mode)
	if Standing.DAILY[kind] == nil then return false, "kind" end
	local rec = RecordOf(name, mode, true)
	if not rec then return false, "store" end
	local M = ns.ArenaMath
	local s = Settings()
	local capKind = kind == "direct" and "direct" or "bet"
	local record = Standing.Record(name, mode)
	record.open, record.dispute = nil, nil
	local tierCap
	if capKind == "direct" then
		local tier = M.DirectTier(record)
		tierCap = tier == M.NO_DIRECT and M.CAPS.direct.tiers[1] or M.CAPS.direct.tiers[tier + 1]
	else
		tierCap = M.CAPS.bet.tiers[(M.Tier("bet", record) or 0) + 1]
	end
	local earns, why = M.Earns(math.floor(tonumber(copper) or 0), tierCap, s.minBet)
	rec.volume = (tonumber(rec.volume) or 0) + math.max(0, math.floor(tonumber(copper) or 0))
	rec.active = Now()
	if not earns then return false, why end
	local day = DayKey()
	if type(rec.day) ~= "table" or rec.day.key ~= day then rec.day = { key = day, peers = {} } end
	if (rec.day[kind] or 0) >= Standing.DAILY[kind] then return false, "day" end
	if kind ~= "wallet" then
		if peerKey == nil or rec.day.peers[kind .. ":" .. tostring(peerKey)] then return false, "peer" end
		if kind == "direct" and type(peerKey) == "string" and Debts.SameOwner(name, peerKey) then return false, "same" end
		rec.day.peers[kind .. ":" .. tostring(peerKey)] = true
	end
	rec.day[kind] = (rec.day[kind] or 0) + 1
	rec.points = (tonumber(rec.points) or 0) + 1
	return true
end

function Standing.Late(name, mode)
	local rec = RecordOf(name, mode, true)
	if not rec then return end
	rec.points = math.floor((tonumber(rec.points) or 0) / 2)
	rec.probation = Now() + Debts.PROBATION
	rec.late = Now()
end

-- A cap in copper (0 with an open debt): kind "bet" (per market), "balance", "daily", "direct"
-- (from a bank-signed token only: his own, or the one he showed this client), "hold" (the King's
-- T1~M cap).
function Standing.Cap(kind, name, mode)
	local M = ns.ArenaMath
	local R = ns.ArenaRoles
	local s = Settings()
	name = name or ns.me
	if kind == "hold" then return R and R.ArbiterCap(name) or 0 end
	if Debts.Blocked(name, nil, nil, mode) then return 0, "open" end
	if kind == "direct" then
		local tok = Same(name, ns.me) and Standing.Token() or Standing.Shown(name)
		if not tok or tok.tier == M.NO_DIRECT then return 0, "token" end
		if Debts.InDispute(name, mode) then return 0, "dispute" end
		return M.DirectCap(tok.tier, tok.paidMax, s.scalePct, s.directMax)
	end
	local limit = kind == "bet" and s.maxBet or nil
	return M.BetCap(Standing.Record(name, mode), kind, s.scalePct, limit)
end

-- The token (the design): "OLYT1|<gk>|<tier>|<volume36>|<paidMax36>|<expiry36>", signed with the
-- bank's account key, valid 24 h. tier: 0-5, or "x" (no direct bets).
local function TokenText(gk, tier, volume, paidMax, expiry)
	local M = ns.ArenaMath
	return ("OLYT1|%s|%s|%s|%s|%s"):format(gk, tier == M.NO_DIRECT and "x" or tostring(tier), B36(volume), B36(paidMax), B36(expiry))
end
function Standing.Issue(gk, name, mode)
	local M = ns.ArenaMath
	if type(gk) ~= "string" then return nil end
	local rec = RecordOf(name, mode, true) or {}
	local record = Standing.Record(name, mode)
	local tier = M.DirectTier(record)
	local expiry = Now() + Debts.TOKEN_LIFE
	local text = TokenText(gk, tier, tonumber(rec.volume) or 0, record.paidMax, expiry)
	local sig = Debts.Sign(text)
	local _, _, pk = KeyTable()
	if not sig or not pk then return nil end
	return { text = text, sig = Debts.B64(sig), tier = tier, volume = tonumber(rec.volume) or 0, paidMax = record.paidMax, expiry = expiry,
		wire = ("%s.%s.%s.%s.%s.%s"):format(tier == M.NO_DIRECT and "x" or tostring(tier), B36(tonumber(rec.volume) or 0), B36(record.paidMax), B36(expiry),
			Debts.B64(sig), Debts.B64(pk)) }
end

local function ParseText(text)
	if type(text) ~= "string" then return nil end
	local gk, tier, vol, paid, exp = text:match("^OLYT1|([0-9a-z]+%.%x+)|([0-5x])|([0-9a-z]+)|([0-9a-z]+)|([0-9a-z]+)$")
	if not gk then return nil end
	local M = ns.ArenaMath
	return { gk = gk, tier = tier == "x" and M.NO_DIRECT or tonumber(tier), volume = ns.Arena.N(vol, 0), paidMax = ns.Arena.N(paid, 0),
		expiry = ns.Arena.N(exp, 0) }
end

-- A token's text and signature under a bank of T1~B: its key the one that bank's heads name (the
-- fingerprint in every ZH it sends), or its verified claim's.
function Standing.CheckToken(text, sig, bank, mode, pk)
	local t = ParseText(text)
	if not t or not t.volume or not t.paidMax or not t.expiry then return nil, "shape" end
	if t.expiry < Now() then return nil, "expired" end
	local R = ns.ArenaRoles
	mode = mode == "T" and "T" or "L"
	if type(bank) ~= "string" or not (R and R.IsBank(bank, mode)) then return nil, "bank" end
	local known = Debts.KeyOf(bank)
	pk = Raw(pk, 32) or known
	if not pk then return nil, "key" end
	if pk ~= known then
		local s = Store(mode)
		local head = type(s.heads) == "table" and s.heads[Lower(bank)]
		if not head or head.fp ~= Debts.Fp(pk) then return nil, "key" end
	end
	local raw = Raw(sig, 64)
	if not raw or not ns.Ed25519.Verify(pk, text, raw) then return nil, "signature" end
	t.bank, t.text, t.sig, t.pk = ns.FullName(bank), text, sig, Debts.B64(pk)
	return t
end

-- This character's tokens (from the banks' statements): the best one still valid.
function Standing.Token(mode)
	local m = Mine(mode or "L")
	local best
	for bank, b in pairs(m and m.banks or {}) do
		local tok = type(b) == "table" and b.token
		if type(tok) == "table" and (tonumber(tok.expiry) or 0) > Now() and ParseText(tok.text) then
			if not best or (tok.tier or -1) > (best.tier or -1) then best = tok end
		end
	end
	if best then best.bank = best.bank or "?" end
	return best
end
-- "<bank>.<tier>.<volume36>.<paidMax36>.<expiry36>.<sig>.<bank's key>" (the AS and KI fields).
function Standing.TokenWire(mode)
	local t = Standing.Token(mode)
	if not t or not t.wire then return nil end
	return ns.FullName(t.bank) .. "." .. t.wire
end
local shown = {} -- [name lower] = token another player showed this client
function Standing.CheckWire(wire, owner, mode)
	if type(wire) ~= "string" or type(owner) ~= "string" then return nil, "shape" end
	local bank, tier, vol, paid, exp, sig, pk = wire:match("^(.-)%.([0-5x])%.([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)%.([%w%-_]+)%.([%w%-_]+)$")
	local gk = Debts.Verified(owner)
	if not bank or not gk then return nil, not bank and "shape" or "key" end
	local text = ("OLYT1|%s|%s|%s|%s|%s"):format(gk, tier, vol, paid, exp)
	local t, why = Standing.CheckToken(text, sig, bank, mode, pk)
	if not t then return nil, why end
	shown[Lower(owner)] = t
	return t
end
function Standing.Shown(name)
	local t = shown[Lower(name) or ""]
	if t and t.expiry >= Now() then return t end
	return nil
end
-- (The bank's statement brought this character's token: kept with that bank's wallet view.)
function Standing.Keep(bank, wire, mode)
	local m = Mine(mode or "L", true)
	if not m or type(wire) ~= "string" or wire == "-" then return nil end
	local tier, vol, paid, exp, sig, pk = wire:match("^([0-5x])%.([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)%.([%w%-_]+)%.([%w%-_]+)$")
	local gk = Debts.MyKey()
	if not tier or not gk then return nil end
	local text = ("OLYT1|%s|%s|%s|%s|%s"):format(gk, tier, vol, paid, exp)
	local t = ParseText(text)
	if not t then return nil end
	t.text, t.sig, t.bank, t.wire, t.pk = text, sig, ns.FullName(bank), wire, pk
	m.banks[ns.FullName(bank)] = type(m.banks[ns.FullName(bank)]) == "table" and m.banks[ns.FullName(bank)] or {}
	m.banks[ns.FullName(bank)].token = t
	return t
end

---------------------------------------------------------------------------
-- Backup (the design): the key and "mine" come back only as plain, well-shaped data; a restored
-- "mine" never raises a direct cap (the token is the bank's signature, checked again).
---------------------------------------------------------------------------

Debts.BackupChecks = {
	key = function(v)
		if type(v) ~= "table" or not Raw(v.seed, 32) then return nil end
		return v
	end,
	mine = function(v)
		if type(v) ~= "table" then return nil end
		-- (A restored record's points and tokens are the player's own word: tokens are dropped.)
		for _, b in pairs(type(v.banks) == "table" and v.banks or {}) do if type(b) == "table" then b.token = nil end end
		return v
	end,
}
local B = ns.Backup
if type(B) == "table" and type(B.arenaChecks) == "table" then
	B.arenaChecks.key = Debts.BackupChecks.key
	B.arenaChecks.mine = Debts.BackupChecks.mine
end

---------------------------------------------------------------------------
-- The buttons (the design): "debt.payfee" (id): one of this character's guild fees, filled.
---------------------------------------------------------------------------

ns.Arena.Action("debt.payfee", function(id)
	local o = Find(id)
	if not o or o.kind ~= "f" or o.state == "c" or o.state == "w" then return false, "fee" end
	return true
end, function(id) return Debts.PayFee(id) end)
