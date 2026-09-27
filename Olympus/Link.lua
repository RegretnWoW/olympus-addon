local ADDON, ns = ...
local L = ns.L

-- Olympus Link (0.9.10): a character's Discord role, proved by players in game.
-- The Olympus bot on Discord gives a player a code: OLC1.<R>.<username>.<exp>.<mode>.<sig>, signed
-- with the bot's Ed25519 key (ns.LINK_BACKEND_KEYS, Ed25519.lua checks it). /oly discord <code>
-- checks that signature and the expiry, shows the Discord account the code belongs to, and after
-- the player's Accept (nothing is sent before it) asks confirmers in game for proofs that this
-- character asked: each proof is an Ed25519 signature made by a confirmer's addon with a key of
-- its own (/oly discord key), whose public half only the bot knows. The server stamps who whispers
-- whom, so a proof names the character that really asked.
-- Who confirms:
--   * a High Councillor (the signed list, Workshop.lua): one proof is enough, asked one at a time;
--   * mode "a" only, none online: verified players drawn by SHA-256(R~keyId), five at once, three
--     must confirm. Nobody can choose who is drawn: R is known only once the request is made.
-- The finished proof reaches the bot two ways: the Olympus Link page reads it from this window
-- (a QR code, or the link in the copy box), or the addon hands it to a watcher (a High Councillor
-- in watcher mode) the next time both are online, whose SavedVariables the bot's keeper uploads.
-- It waits in the addon for 7 days: nothing is lost while the bot or the watcher is away.
-- Messages (Comm.lua; each dispatched only as "<type>~"):
--   DV~1~<keyId>~<c|p>    a confirmer is online (CHANNEL, every 5 minutes); DV~0 its key is gone
--   DR~<nonce>~<guild>~<faction>~<R>      a request (WHISPER, requester -> confirmer)
--   DA~<issued>~<keyId>~<sig>             a proof (WHISPER, confirmer -> requester)
--   DW~1 | DW~0          a watcher is online, or not any more (CHANNEL, every 5 minutes)
--   DB~<bundle>          a finished proof (WHISPER, requester -> watcher; in Codec.Chunk pieces
--                        "DB~C<id>:<i>:<n>:<piece>" when longer than one message)
--   DK~<R>               the watcher kept it (WHISPER, watcher -> requester)
-- Signed: OLY4~<requester>~<guild>~<faction>~<nonce>~<R>~<issued>~<keyId>~<confirmer>
-- Carried: OLB4~<requester>~<guild>~<faction>~<nonce>~<R>~<issued>,<keyId>,<confirmer>,<sig>;...
-- (4 proofs at most), in the URL <ns.LINK_SITE>#b=<the bundle, URL-encoded>: a fragment, never
-- sent to any server by the browser.
-- A confirmer's key never leaves OlympusDB.discord.key: it is never printed, sent, logged, or
-- written in /oly status and the bug report.

-- The Olympus bot's public keys (64 hex digits each, from scripts/link-keys.py backend): a code
-- signed by any of them is accepted, so two can be listed while the key changes. Anything that is
-- not 64 hex digits is ignored: until the bot's key is pasted here, every code is refused.
ns.LINK_BACKEND_KEYS = { "PASTE-THE-BOT-PUBLIC-KEY-HEX-HERE" }
-- The Olympus Link page (on the bot's site): the QR code and the copy box open it.
ns.LINK_SITE = "https://olympus.example/link"
-- Whose watcher the texts name ("<name>'s watcher"); nil: "the bot's watcher".
ns.LINK_WATCHER_OWNER = nil

local Link = {}
ns.Link = Link
local Ed = ns.Ed25519

Link.CODE_TTL_MAX = 7 * 86400 -- a code valid for longer than this is refused (the bot's are 24 h)
Link.ANNOUNCE_EVERY = 300    -- a confirmer (DV) and a watcher (DW) say they are online this often...
Link.ANNOUNCE_FRESH = 700    -- ...and count as online this long after
Link.COUNCIL_WAIT = 10       -- each High Councillor asked has this long to answer
Link.COUNCIL_AGAIN = 600     -- a councillor who did not answer is asked again after this long
Link.DRAW_FIRST = 5          -- players asked at once
Link.DRAW_MAX = 10           -- ...and at most this many in one round
Link.DRAW_WAIT = 30          -- each batch has this long to answer
Link.NEEDED = 3              -- players' proofs that make a link
Link.MAX_PROOFS = 4          -- proofs carried at most
Link.FRESH = 240             -- players' proofs count together within 4 minutes (the bot: 5)
Link.ASK_AGAIN = 300         -- a player who did not answer is asked again after this long
Link.ROUND_GAP = 120         -- a new round at most this often
Link.DELIVER_FOR = 7 * 86400 -- a finished proof waits this long for a watcher
Link.ACK_WAIT = 30           -- a watcher has this long to say it kept the proof
Link.GIVE_GAP = 60           -- a confirmer: one proof per requesting character a minute...
Link.GIVE_DAY = 5            -- ...five a day...
Link.GIVE_MINUTE = 30        -- ...and thirty a minute in all
Link.INBOX_MAX = 500         -- a watcher keeps this many proofs (the oldest go)
Link.INBOX_GAP = 60          -- ...and one per requesting character a minute
Link.MAX_ANNOUNCERS = 3000
Link.M_MAX_BYTES = 412       -- the longest link a version 15 QR code holds at level M
Link.QUIET = 4               -- modules of white around the code
Link.CHROME = 190            -- UI units of the window around the code (title, name, hint, box)

local req                  -- this character's request while it waits: { rec, asked, told, round... }
local announcers, nAnnouncers = {}, 0 -- [Name-Realm] = { id, tier "c"|"p", t }
local watchers = {}        -- [Name-Realm] = t: High Councillors in watcher mode heard
local delivery             -- the proof on its way to a watcher: { to, due }
local waitWatcher = false  -- a delivery went unanswered: the next one when a watcher is heard
local sentTo = {}          -- watchers our proof was sent to, this session
local recent = {}          -- when our key confirmed, the last minute (every requester)
local inboxFrom = {}       -- watcher: [requester] = when their last proof was kept
local inAsm = ns.Codec.NewAssembler() -- watcher: proofs arriving in pieces
local bundleId = 0
local stats = { confirmed = 0, refused = 0, kept = 0 }
local lastAnnounce, lastWatch, lastPrune = -math.huge, -math.huge, -math.huge
local pubCache             -- { id, seed, pub }: our confirmer key's public half
local frame                -- the Olympus Link window, built the first time it opens
local qr = {}              -- the QR code last made: { url, matrix, level }
local qrJob                -- the URL whose QR code is being made

-- The server's clock (codes and proofs carry the server's time), else ours.
local function ServerTime()
	local t = GetServerTime and GetServerTime()
	return math.floor(tonumber(t) or ns.Now())
end
Link.ServerTime = ServerTime

---------------------------------------------------------------------------
-- Formats: what a field may hold, the code, the signed text and the carried link
---------------------------------------------------------------------------

local FACTIONS = { Alliance = true, Horde = true }

-- A field of the signed text: never empty, no separator (~ ; ,), pipe or control byte.
local function Field(s, max)
	return type(s) == "string" and s ~= "" and #s <= max and not s:find("[~|;,%c]")
end
-- "Name-Realm" as ns.FullName writes it (the name may hold spaces and accented letters).
function Link.ValidName(s) return Field(s, 64) and s:find("^[^%-].*%-[^%-%s]+$") ~= nil end
function Link.ValidGuild(s) return Field(s, 40) end
local function Nonce(s) return type(s) == "string" and #s == 16 and not s:find("[^0-9a-f]") end
local function KeyId(s) return type(s) == "string" and #s >= 6 and #s <= 16 and not s:find("[^a-z0-9]") end
local function Code(s) return type(s) == "string" and #s == 10 and not s:find("[^0-9A-HJKMNP-TV-Z]") end
local function Time(s) return type(s) == "string" and #s <= 12 and s:find("^[1-9]%d*$") ~= nil end
local function User(s) return type(s) == "string" and #s >= 2 and #s <= 32 and not s:find("[^a-z0-9_%.]") end
-- A signature: 86 characters of base64url that are exactly 64 bytes.
local function Sig(s)
	return type(s) == "string" and #s == 86 and not s:find("[^A-Za-z0-9_%-]") and Ed.FromB64(s) ~= nil
end
Link.KeyId, Link.Code, Link.Sig = KeyId, Code, Sig

-- The code the bot gave, as pasted (spaces around it are fine): { R, user, exp, mode, sig,
-- signed } or nil. The username may hold dots: the fields are read from both ends.
function Link.ParseToken(s)
	if type(s) ~= "string" then return nil end
	s = s:match("^%s*(.-)%s*$")
	if #s > 200 then return nil end
	local R, user, exp, mode, sig = s:match("^OLC1%.([^.]*)%.(.+)%.([^.]*)%.([^.]*)%.([^.]*)$")
	if not R or not Code(R) or not User(user) or not Time(exp) or (mode ~= "c" and mode ~= "a") or not Sig(sig) then return nil end
	return { R = R, user = user, exp = tonumber(exp), mode = mode, sig = sig, signed = s:sub(1, #s - 87) }
end

-- The bot's public keys this version knows (32-byte strings): 64 hex digits that are a key a
-- signature can be checked with (Ed.ValidPublicKey), made once for the list as it is.
local backendKeys = {}
function Link.BackendKeys()
	local list = type(ns.LINK_BACKEND_KEYS) == "table" and ns.LINK_BACKEND_KEYS or {}
	local id = table.concat(list, ",")
	if backendKeys.id ~= id then
		local out = {}
		for _, hex in ipairs(list) do
			local pk = type(hex) == "string" and #hex == 64 and Ed.FromHex(hex)
			if pk and Ed.ValidPublicKey(pk) then out[#out + 1] = pk end
		end
		backendKeys = { id = id, keys = out }
	end
	return backendKeys.keys
end

-- Did one of the bot's keys sign this code? (Heavy: run inside Ed.Run.)
function Link.VerifyToken(t)
	local sig = type(t) == "table" and Ed.FromB64(t.sig)
	if not sig then return false end
	for _, pk in ipairs(Link.BackendKeys()) do
		if Ed.Verify(pk, t.signed, sig) then return true end
	end
	return false
end

-- The text a confirmer signs for proof p of request b (UTF-8, as the names are).
function Link.Message(b, p)
	return table.concat({ "OLY4", b.requester, b.guild, b.faction, b.nonce, b.R, p.issued, p.keyId, p.confirmer }, "~")
end

-- The draw: a confirmer's place for this code, the hex of SHA-256(R~keyId) (lower is drawn
-- first). Kept per code: the online list is sorted again at each step.
local ranks = { of = {}, n = 0 }
function Link.Rank(R, keyId)
	if ranks.R ~= R then ranks = { R = R, of = {}, n = 0 } end
	local v = ranks.of[keyId]
	if not v then
		if ranks.n >= 5000 then ranks.of, ranks.n = {}, 0 end
		v = Ed.ToHex(ns.Sign.SHA256(R .. "~" .. keyId))
		ranks.of[keyId], ranks.n = v, ranks.n + 1
	end
	return v
end

local function ValidProof(p)
	return type(p) == "table" and Time(p.issued) and KeyId(p.keyId) and Link.ValidName(p.confirmer) and Sig(p.sig)
end
local function ValidHead(b)
	return type(b) == "table" and Link.ValidName(b.requester) and Link.ValidGuild(b.guild) and FACTIONS[b.faction] ~= nil
		and Nonce(b.nonce) and Code(b.R)
end

-- The link the page reads: the request and 1 to 4 proofs.
function Link.Build(b, proofs)
	if not ValidHead(b) or type(proofs) ~= "table" or #proofs < 1 or #proofs > Link.MAX_PROOFS then return nil end
	local parts = {}
	for i, p in ipairs(proofs) do
		if not ValidProof(p) then return nil end
		parts[i] = table.concat({ p.issued, p.keyId, p.confirmer, p.sig }, ",")
	end
	return table.concat({ "OLB4", b.requester, b.guild, b.faction, b.nonce, b.R, table.concat(parts, ";") }, "~")
end

-- The link read back: { requester, guild, faction, nonce, R, proofs = { ... } }, or nil.
function Link.Parse(s)
	if type(s) ~= "string" or #s > 1600 then return nil end
	local requester, guild, faction, nonce, R, list = s:match("^OLB4~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)$")
	local b = { requester = requester, guild = guild, faction = faction, nonce = nonce, R = R, proofs = {} }
	if not requester or not ValidHead(b) then return nil end
	for part in (list .. ";"):gmatch("([^;]*);") do
		local issued, keyId, confirmer, sig = part:match("^([^,]*),([^,]*),([^,]*),([^,]*)$")
		local p = { issued = issued, keyId = keyId, confirmer = confirmer, sig = sig }
		if not issued or not ValidProof(p) or #b.proofs >= Link.MAX_PROOFS then return nil end
		b.proofs[#b.proofs + 1] = p
	end
	if #b.proofs == 0 then return nil end
	return b
end

-- JavaScript's encodeURIComponent: letters, digits and - _ . ! ~ * ' ( ) as they are, every
-- other byte (UTF-8 included) as %XX.
function Link.EncodeURI(s)
	return (s:gsub("[^A-Za-z0-9%-_%.!~%*'%(%)]", function(c) return ("%%%02X"):format(c:byte()) end))
end

function Link.URL(bundle) return tostring(ns.LINK_SITE) .. "#b=" .. Link.EncodeURI(bundle) end

-- "the bot's watcher", or "<name>'s watcher" (ns.LINK_WATCHER_OWNER).
function Link.WatcherLabel()
	local owner = ns.LINK_WATCHER_OWNER
	if type(owner) == "string" and owner ~= "" then return L.LINK_WATCHER_OF:format(owner) end
	return L.LINK_WATCHER_GENERIC
end

---------------------------------------------------------------------------
-- Saved on the account (OlympusDB.discord): each character's request and proof (chars), the
-- confirmer key, whom that key confirmed (given), and a watcher's inbox and switch.
---------------------------------------------------------------------------

local function Store()
	local db = ns.db
	if type(db.discord) ~= "table" then db.discord = {} end
	local d = db.discord
	for _, k in ipairs({ "chars", "given", "inbox", "watch" }) do
		if type(d[k]) ~= "table" then d[k] = {} end
	end
	return d
end
Link.Store = Store

-- This character's record, without making the store for a player who never used Olympus Link.
local function MyRecord()
	local d = ns.db and ns.db.discord
	local chars = type(d) == "table" and d.chars
	return type(chars) == "table" and chars[ns.me] or nil
end

-- Our confirmer key: the saved record and its 32-byte seed, or nil.
function Link.Key()
	local d = ns.db and ns.db.discord
	local k = type(d) == "table" and d.key
	if type(k) ~= "table" or not KeyId(k.id) or type(k.seed) ~= "string" or #k.seed ~= 43 then return nil end
	local seed = Ed.FromB64(k.seed)
	if not seed or #seed ~= 32 then return nil end
	return k, seed
end

-- "c" when the signed list names us, else "p" (the bot knows each key's tier anyway).
local function MyTier() return ns.IsHighCouncillor(ns.me) and "c" or "p" end

local function OwnCharacter(name)
	if ns.Treasury and ns.Treasury.IsOwnCharacter and not ns.Treasury.missing then return ns.Treasury.IsOwnCharacter(name) end
	local mine = ns.db and ns.db.myCharacters
	return type(mine) == "table" and type(name) == "string" and mine[name:lower()] == true
end

---------------------------------------------------------------------------
-- Who is online: confirmers (DV) and watchers (DW)
---------------------------------------------------------------------------

function Link.Announce(force)
	local key = Link.Key()
	if not key then return false end
	local now = ns.Now()
	if not force and now - lastAnnounce < Link.ANNOUNCE_EVERY then return false end
	lastAnnounce = now
	ns.Comm.Send("CHANNEL", ("DV~1~%s~%s"):format(key.id, MyTier()), "linkannounce")
	return true
end

function Link.Watching()
	local d = ns.db and ns.db.discord
	return type(d) == "table" and type(d.watch) == "table" and d.watch[ns.me] == true and ns.IsHighCouncillor(ns.me)
end

function Link.AnnounceWatcher(force)
	if not Link.Watching() then return false end
	local now = ns.Now()
	if not force and now - lastWatch < Link.ANNOUNCE_EVERY then return false end
	lastWatch = now
	ns.Comm.Send("CHANNEL", "DW~1", "linkwatcher")
	return true
end

local function Prune(now)
	lastPrune = now
	for name, a in pairs(announcers) do
		if now - a.t > Link.ANNOUNCE_FRESH then announcers[name], nAnnouncers = nil, nAnnouncers - 1 end
	end
	for name, t in pairs(watchers) do
		if now - t > Link.ANNOUNCE_FRESH then watchers[name] = nil end
	end
	for name, t in pairs(inboxFrom) do
		if now - t >= Link.INBOX_GAP then inboxFrom[name] = nil end
	end
	ns.Codec.Gc(inAsm, now)
end

-- A "c" counts only from a councillor of the signed list: anyone else's is a "p".
local function IsCouncillor(name, a) return a.tier == "c" and ns.IsHighCouncillor(name) end

-- Online confirmers, the councillors or the others, lowest draw first: { name, id, c, rank }.
function Link.Online(councillors, R, now)
	local out = {}
	local own = Link.Key()
	for name, a in pairs(announcers) do
		if now - a.t <= Link.ANNOUNCE_FRESH and name ~= ns.me and not (own and own.id == a.id) then
			local c = IsCouncillor(name, a)
			if c == (councillors and true or false) then out[#out + 1] = { name = name, id = a.id, c = c, rank = Link.Rank(R, a.id) } end
		end
	end
	table.sort(out, function(x, y)
		if x.rank ~= y.rank then return x.rank < y.rank end
		return x.name < y.name
	end)
	return out
end

local function OnlineWatchers(now)
	local out = {}
	for name, t in pairs(watchers) do
		if now - t <= Link.ANNOUNCE_FRESH and name ~= ns.me and ns.IsHighCouncillor(name) then out[#out + 1] = { name = name, t = t } end
	end
	table.sort(out, function(x, y) return x.t > y.t end) -- the one heard last first
	return out
end

---------------------------------------------------------------------------
-- The requester
---------------------------------------------------------------------------

local SAY = { council = "LINK_ASKING_COUNCIL", draw = "LINK_DRAWING", waiting = "LINK_WAITING", waitingC = "LINK_WAITING_COUNCIL" }
local function Say(r, what)
	if r.told[what] then return end
	r.told[what] = true
	ns.Print(L[SAY[what]])
end

local function NewNonce(R)
	local seed = table.concat({ tostring(ns.me), R, tostring(time()), tostring(GetTime and GetTime() or 0), tostring(math.random()),
		tostring(math.random()), tostring(debugprofilestop and debugprofilestop() or 0), tostring({}) }, "~")
	return Ed.ToHex(ns.Sign.SHA256(seed)):sub(1, 16)
end

local function Head(rec) return { requester = ns.me, guild = rec.guild, faction = rec.faction, nonce = rec.nonce, R = rec.R } end

local function FreshP(p, now) return not p.c and now - (tonumber(p.got) or 0) <= Link.FRESH end

-- The proofs the link carries: councillors' alone when there is one; else the players' fresh
-- ones, one per key, lowest draw first; four at most.
local function Chosen(rec, now)
	local list, ids = {}, {}
	for _, p in pairs(rec.proofs) do
		if p.c and not ids[p.keyId] then
			ids[p.keyId] = true
			list[#list + 1] = p
		end
	end
	if #list == 0 then
		for _, p in pairs(rec.proofs) do
			if FreshP(p, now) and not ids[p.keyId] then
				ids[p.keyId] = true
				list[#list + 1] = p
			end
		end
	end
	table.sort(list, function(x, y)
		if (x.c and true or false) ~= (y.c and true or false) then return x.c and true or false end
		return Link.Rank(rec.R, x.keyId) < Link.Rank(rec.R, y.keyId)
	end)
	while #list > Link.MAX_PROOFS do table.remove(list) end
	return list
end

local function Enough(rec, now)
	local list = Chosen(rec, now)
	return #list > 0 and (list[1].c or (rec.mode == "a" and #list >= Link.NEEDED))
end

local function Expire(r)
	local d = Store()
	if d.chars[ns.me] == r.rec then d.chars[ns.me] = nil end
	if req == r then req = nil end
	ns.Print(L.LINK_EXPIRED)
	ns.Log("discord link: request expired")
end

local function Ready(r, now)
	local rec = r.rec
	local list = Chosen(rec, now)
	local proofs = {}
	for i, p in ipairs(list) do proofs[i] = { issued = p.issued, keyId = p.keyId, confirmer = p.confirmer, sig = p.sig } end
	local bundle = Link.Build(Head(rec), proofs)
	if not bundle then return end
	rec.state, rec.bundle, rec.readyAt, rec.n, rec.council = "ready", bundle, now, #proofs, list[1].c or nil
	rec.proofs = nil
	req, delivery, waitWatcher = nil, nil, false
	wipe(sentTo)
	ns.Print(L.LINK_READY)
	ns.Log("discord link: ready with %d proofs", #proofs)
	Link.ShowWindow()
	Link.Deliver(now)
end

local function Ask(r, e, now)
	local rec = r.rec
	r.asked[e.name] = { id = e.id, c = e.c, t = now }
	ns.Comm.Whisper(e.name, ("DR~%s~%s~%s~%s"):format(rec.nonce, rec.guild, rec.faction, rec.R), "linkask:" .. e.name, true)
end

-- Players who can be asked now, lowest draw first, one per key: online, not a councillor,
-- without a fresh proof, not asked within ASK_AGAIN.
local function Candidates(r, now)
	local out, ids = {}, {}
	for _, p in pairs(r.rec.proofs) do
		if FreshP(p, now) then ids[p.keyId] = true end
	end
	for _, e in ipairs(Link.Online(false, r.rec.R, now)) do
		local a = r.asked[e.name]
		if not ids[e.id] and not (a and now - a.t < Link.ASK_AGAIN) then
			ids[e.id] = true
			out[#out + 1] = e
		end
	end
	return out
end

-- The draw, in rounds: five at once, the next five after DRAW_WAIT if still short, then the
-- request waits. A round starts at the request, at each login and when a confirmer who was not
-- asked comes online (not sooner than ROUND_GAP after the last): players' proofs older than
-- FRESH are left out, so the ones carried were all made within minutes of each other. Every step
-- asks the lowest draws first, so the proofs come from the players the bot expects (it takes a
-- player's proof only from the first ranks of every key's draw, WORKER.md).
local function Draw(r, now)
	local round = r.round
	if round then
		if now < round.due then
			-- A batch short of five (few were online): confirmers who come online join it.
			local room = math.min(Link.DRAW_FIRST - round.batch, Link.DRAW_MAX - round.asked)
			if room > 0 then
				local cands = Candidates(r, now)
				for i = 1, math.min(room, #cands) do
					Ask(r, cands[i], now)
					round.batch, round.asked = round.batch + 1, round.asked + 1
				end
			end
			return
		end
		if round.asked < Link.DRAW_MAX then
			local cands = Candidates(r, now)
			local n = math.min(Link.DRAW_MAX - round.asked, #cands)
			if n > 0 then
				for i = 1, n do Ask(r, cands[i], now) end
				round.asked, round.batch, round.due = round.asked + n, n, now + Link.DRAW_WAIT
				return
			end
		end
		r.round, r.roundEnded = nil, now
		return Say(r, "waiting")
	end
	if not r.wantRound then return end
	if r.roundEnded and now - r.roundEnded < Link.ROUND_GAP then return end
	r.wantRound = nil
	for name, p in pairs(r.rec.proofs) do
		if not p.c and not FreshP(p, now) then r.rec.proofs[name] = nil end
	end
	local cands = Candidates(r, now)
	if #cands == 0 then return Say(r, "waiting") end
	local n = math.min(Link.DRAW_FIRST, #cands)
	for i = 1, n do Ask(r, cands[i], now) end
	r.round = { asked = n, batch = n, due = now + Link.DRAW_WAIT }
	Say(r, "draw")
end

-- One step of the request: at the start, at each answer, when a confirmer comes online and
-- every few seconds (Link.Tick).
function Link.Step(now)
	local r = req
	if not r then return end
	now = now or ns.Now()
	local rec = r.rec
	if rec.state ~= "waiting" then return end
	if ServerTime() >= rec.exp then return Expire(r) end
	if Enough(rec, now) then return Ready(r, now) end
	-- High Councillors first, one at a time: one proof is enough.
	if r.waitC and now < r.waitC then return end
	for _, e in ipairs(Link.Online(true, rec.R, now)) do
		local a = r.asked[e.name]
		if not a or now - a.t >= Link.COUNCIL_AGAIN then
			Ask(r, e, now)
			r.waitC = now + Link.COUNCIL_WAIT
			return Say(r, "council")
		end
	end
	if rec.mode ~= "a" then return Say(r, "waitingC") end
	Draw(r, now)
end

local function Runtime(rec) return { rec = rec, asked = {}, told = {}, wantRound = true } end

-- After the player's Accept: a new request for this character (an older one is replaced).
function Link.Start(t)
	if type(t) ~= "table" or not Code(t.R) or not User(t.user) or (t.mode ~= "c" and t.mode ~= "a") then return false end
	if (tonumber(t.exp) or 0) <= ServerTime() then return ns.Print(L.LINK_CODE_EXPIRED) end
	if not ns.IsMember() then return ns.Print(L.LINK_NOT_MEMBER) end
	local guild = GetGuildInfo("player")
	local faction = ns.faction
	if not Link.ValidName(ns.me) or not Link.ValidGuild(guild) or not FACTIONS[faction] then return ns.Print(L.LINK_CANT) end
	local now = ns.Now()
	local rec = { R = t.R, user = t.user, exp = t.exp, mode = t.mode, nonce = NewNonce(t.R), guild = guild, faction = faction,
		started = now, state = "waiting", proofs = {} }
	Store().chars[ns.me] = rec
	delivery, waitWatcher = nil, false
	Link.HideWindow()
	req = Runtime(rec)
	ns.Print(L.LINK_STARTED)
	ns.Log("discord link: request started (mode %s)", t.mode)
	Link.Step(now)
	return true
end

-- A confirmer online (DV): a request waiting asks it when it can.
function Link.HandleAnnounce(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" then return end
	local name = ns.FullName(sender)
	if name == ns.me then return end
	local now = ns.Now()
	if text == "DV~0" then
		if announcers[name] then announcers[name], nAnnouncers = nil, nAnnouncers - 1 end
		return
	end
	local id, tier = text:match("^DV~1~([^~]+)~([cp])$")
	if not KeyId(id) then return end
	local a = announcers[name]
	if not a then
		if nAnnouncers >= Link.MAX_ANNOUNCERS then Prune(now) end
		if nAnnouncers >= Link.MAX_ANNOUNCERS then return end
		nAnnouncers = nAnnouncers + 1
	end
	local known = a and a.id == id and now - a.t <= Link.ANNOUNCE_FRESH
	announcers[name] = { id = id, tier = tier, t = now }
	local r = req
	if r and r.rec.state == "waiting" and not known then
		local asked = r.asked[name]
		if not asked or now - asked.t >= Link.ASK_AGAIN then r.wantRound = true end
		Link.Step(now)
	end
end

-- A proof (DA): only from a confirmer we asked for this request, with the key we asked it for;
-- the confirmer is the name the server stamped. (Only the bot can check the signature: it alone
-- knows the confirmers' public keys.)
function Link.HandleAnswer(dist, sender, text)
	local r = req
	if dist ~= "WHISPER" or not r or type(text) ~= "string" or r.rec.state ~= "waiting" then return end
	local name, now = ns.FullName(sender), ns.Now()
	local a = r.asked[name]
	if not a or not Link.ValidName(name) then return end
	local issued, keyId, sig = text:match("^DA~([^~]*)~([^~]*)~([^~]*)$")
	if not Time(issued) or keyId ~= a.id or not Sig(sig) then return end
	if tonumber(issued) > r.rec.exp then return end
	r.rec.proofs[name] = { issued = issued, keyId = keyId, confirmer = name, sig = sig, c = a.c or nil, got = now }
	Link.Step(now)
end

---------------------------------------------------------------------------
-- The finished proof and the watchers
---------------------------------------------------------------------------

local function Deliverable(rec, now)
	return type(rec) == "table" and rec.state == "ready" and type(rec.bundle) == "string"
		and now - (tonumber(rec.readyAt) or 0) < Link.DELIVER_FOR
end

-- Our proof (as ourselves: a watcher keeps only the requester's own) to a watcher.
local function SendBundle(to, bundle)
	local msg = "DB~" .. bundle
	if #msg <= 255 then
		ns.Comm.Whisper(to, msg, "linkbundle", true)
		return
	end
	bundleId = (bundleId + 1) % 1000
	for _, piece in ipairs(ns.Codec.Chunk(bundle, "L" .. bundleId)) do ns.Comm.Whisper(to, "DB~" .. piece, nil, true) end
end

-- A watcher we are one of ourselves takes it at once.
local Keep

-- The proof of this character to an online watcher, until one says it kept it. An unanswered
-- one (the watcher left) waits until a watcher is heard again.
function Link.Deliver(now)
	now = now or ns.Now()
	local rec = MyRecord()
	if not Deliverable(rec, now) then return false end
	if Link.Watching() then
		if Keep(rec.bundle, ns.me, now) then
			rec.state, rec.deliveredAt = "delivered", now
			ns.Print(L.LINK_DELIVERED:format(Link.WatcherLabel()))
		end
		return true
	end
	if delivery then
		if now < delivery.due then return false end
		delivery, waitWatcher = nil, true
	end
	if waitWatcher then return false end
	local w = OnlineWatchers(now)[1]
	if not w then return false end
	SendBundle(w.name, rec.bundle)
	sentTo[w.name] = true
	delivery = { to = w.name, due = now + Link.ACK_WAIT }
	ns.Log("discord link: proof sent to a watcher")
	return true
end

-- A watcher online (DW): honoured from a High Councillor only.
function Link.HandleWatcher(dist, sender, text)
	if dist ~= "CHANNEL" or not ns.IsHighCouncillor(sender) then return end
	local name, now = ns.FullName(sender), ns.Now()
	if text == "DW~0" then
		watchers[name] = nil
		return
	end
	if text ~= "DW~1" then return end
	watchers[name] = now
	waitWatcher = false
	Link.Deliver(now)
end

-- The watcher kept our proof (DK).
function Link.HandleAck(dist, sender, text)
	if dist ~= "WHISPER" then return end
	local name, now = ns.FullName(sender), ns.Now()
	local rec = MyRecord()
	if not sentTo[name] or type(rec) ~= "table" or rec.state ~= "ready" or text ~= "DK~" .. tostring(rec.R) then return end
	rec.state, rec.deliveredAt = "delivered", now
	delivery = nil
	ns.Print(L.LINK_DELIVERED:format(Link.WatcherLabel()))
	ns.Log("discord link: proof kept by a watcher")
end

-- When an inbox entry was kept (anything that is not an entry: the oldest of all).
local function KeptAt(e) return type(e) == "table" and tonumber(e.t) or -math.huge end

-- A watcher keeps a proof: one per code (the first sender's), INBOX_MAX in all (the oldest go).
Keep = function(bundle, from, now)
	local b = Link.Parse(bundle)
	if not b or b.requester ~= from then return false end
	local inbox = Store().inbox
	local e = inbox[b.R]
	if type(e) == "table" and e.from ~= from then return false end
	inbox[b.R] = { bundle = bundle, from = from, t = now }
	local n = 0
	for _ in pairs(inbox) do n = n + 1 end
	while n > Link.INBOX_MAX do
		local oldest
		for k, x in pairs(inbox) do
			if not oldest or KeptAt(x) < KeptAt(inbox[oldest]) then oldest = k end
		end
		inbox[oldest], n = nil, n - 1
	end
	stats.kept = stats.kept + 1
	return b
end

-- A proof for our inbox (DB), whole or in pieces: only from the requester it names, one per
-- requester a minute; told back with DK.
function Link.HandleBundle(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or not Link.Watching() then return end
	local from, now = ns.FullName(sender), ns.Now()
	local payload = text:sub(4)
	local full = payload
	if payload:sub(1, 5) ~= "OLB4~" then full = ns.Codec.Feed(inAsm, from, payload, now) end
	if not full then return end
	local b = Link.Parse(full)
	if not b or b.requester ~= from then return end
	local e = Store().inbox[b.R]
	local same = type(e) == "table" and e.from == from and e.bundle == full
	if not same then
		if inboxFrom[from] and now - inboxFrom[from] < Link.INBOX_GAP then return end
		if not Keep(full, from, now) then return end
		inboxFrom[from] = now
		ns.Log("discord link: proof kept in the inbox")
	end
	ns.Comm.Whisper(from, "DK~" .. b.R, "linkack:" .. from, true)
end

-- /oly discord watcher on | off (High Councillors).
function Link.SetWatcher(on)
	if not ns.IsHighCouncillor(ns.me) then return ns.Print(L.LINK_WATCHER_ONLY) end
	local d = Store()
	d.watch[ns.me] = on and true or nil
	if on then
		local n = 0
		for _ in pairs(d.inbox) do n = n + 1 end
		ns.Print(L.LINK_WATCHER_ON:format(n))
		Link.AnnounceWatcher(true)
	else
		ns.Print(L.LINK_WATCHER_OFF)
		ns.Comm.Send("CHANNEL", "DW~0", "linkwatcher")
	end
end

---------------------------------------------------------------------------
-- The confirmer
---------------------------------------------------------------------------

-- Our key's limits: one proof per requesting character a minute and five a day (kept on the
-- account, as the key is), thirty a minute in all.
local function Allowed(requester, now)
	while recent[1] and now - recent[1] >= 60 do table.remove(recent, 1) end
	if #recent >= Link.GIVE_MINUTE then return false end
	local times = Store().given[requester]
	if type(times) ~= "table" then return true end
	for i = #times, 1, -1 do
		if type(times[i]) ~= "number" or now - times[i] >= 86400 then table.remove(times, i) end
	end
	if #times >= Link.GIVE_DAY then return false end
	return not times[#times] or now - times[#times] >= Link.GIVE_GAP
end

local function Given(requester, now)
	recent[#recent + 1] = now
	local given = Store().given
	local times = type(given[requester]) == "table" and given[requester] or {}
	times[#times + 1] = now
	given[requester] = times
end

-- Claims our own guild: then our roster must list them (once we have read it).
local function OwnGuildDenies(requester, guild)
	local own = GetGuildInfo("player")
	local roster = ns.Roster and ns.Roster.byName
	if type(own) ~= "string" or own:lower() ~= guild:lower() or type(roster) ~= "table" or next(roster) == nil then return false end
	return ns.Roster.RankOf(requester) == nil
end

-- Our key's public half (32 bytes) to done(pub), made once a session (in a job).
function Link.PublicKey(done)
	local k, seed = Link.Key()
	if not k then return false end
	if pubCache and pubCache.id == k.id and pubCache.seed == k.seed then
		done(pubCache.pub)
		return true
	end
	return Ed.Run(function() return Ed.PublicKey(seed) end, function(ok, pub)
		if not ok then return end
		pubCache = { id = k.id, seed = k.seed, pub = pub }
		done(pub)
	end)
end

-- A request (DR): signed for a player of an Olympus guild of our faction who asks it
-- themselves, within the limits, never one of our own account's characters. Anything else is
-- ignored without a word.
function Link.HandleRequest(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" then return end
	local key, seed = Link.Key()
	if not key then return end
	local requester, now = ns.FullName(sender), ns.Now()
	if requester == ns.me or OwnCharacter(requester) or not Link.ValidName(requester) or not Link.ValidName(ns.me) then return end
	local nonce, guild, faction, R = text:match("^DR~([^~]*)~([^~]*)~([^~]*)~([^~]*)$")
	if not Nonce(nonce) or not Link.ValidGuild(guild) or not FACTIONS[faction] or not Code(R) then return end
	if not ns.IsFederation(guild) or faction ~= ns.faction or OwnGuildDenies(requester, guild) then return end
	if not Allowed(requester, now) then
		stats.refused = stats.refused + 1
		return
	end
	Given(requester, now)
	local b = { requester = requester, guild = guild, faction = faction, nonce = nonce, R = R }
	local p = { issued = tostring(ServerTime()), keyId = key.id, confirmer = ns.me }
	local msg = Link.Message(b, p)
	local cached = pubCache and pubCache.id == key.id and pubCache.seed == key.seed and pubCache.pub or nil
	Ed.Run(function()
		local pub = cached or Ed.PublicKey(seed)
		return { sig = Ed.Sign(seed, msg, pub), pub = pub }
	end, function(ok, res)
		if not ok or type(res) ~= "table" then return end
		if not cached then pubCache = { id = key.id, seed = key.seed, pub = res.pub } end
		stats.confirmed = stats.confirmed + 1
		ns.Comm.Whisper(requester, ("DA~%s~%s~%s"):format(p.issued, p.keyId, Ed.ToB64(res.sig)), "linkanswer:" .. requester, true)
		ns.Log("discord link: confirmed a request")
	end)
end

-- /oly discord key [<id> <key> | off]. Nothing typed is ever repeated back.
function Link.ShowKey()
	local k = Link.Key()
	if not k then return ns.Print(L.LINK_KEY_NONE) end
	Link.PublicKey(function(pub)
		ns.Print(L.LINK_KEY_SHOW:format(k.id, MyTier() == "c" and L.LINK_TIER_C or L.LINK_TIER_P, Ed.ToHex(pub)))
	end)
end

function Link.SetKey(args)
	args = tostring(args or ""):match("^%s*(.-)%s*$")
	local d = Store()
	if args == "" then return Link.ShowKey() end
	if args:lower() == "off" then
		local had = Link.Key()
		d.key, pubCache = nil, nil
		if had then ns.Comm.Send("CHANNEL", "DV~0", "linkannounce") end
		return ns.Print(L.LINK_KEY_OFF)
	end
	local id, seed = args:match("^(%S+)%s+(%S+)$")
	id = id and id:lower()
	if not KeyId(id) or not seed or #seed ~= 43 or not Ed.FromB64(seed) then return ns.Print(L.LINK_KEY_BAD) end
	d.key, pubCache = { id = id, seed = seed }, nil
	ns.Print(L.LINK_KEY_SET:format(id))
	Link.ShowKey()
	lastAnnounce = -math.huge
	Link.Announce(true)
end

---------------------------------------------------------------------------
-- The window: the QR code of the link, drawn with textures on white, each module a whole
-- number of screen pixels (3 at least, 4 when it fits on the screen) at the player's UI scale,
-- and the link in a read-only copy box. Our own window on UIParent: movable, closed by its X
-- (and by Escape with mouse and keyboard, ns.EscapeCloses); not a UI panel, and its box takes
-- the keyboard only when clicked (the gamepad UI's rule, ns.Focus).
---------------------------------------------------------------------------

-- The QR code of a link: level M when it fits a version 15 code, else L. pause: Ed.Pause when
-- made inside a job.
function Link.Matrix(url, pause)
	if qr.url == url then return qr.matrix, qr.level end
	local enc = ns.QREncode
	if type(enc) ~= "table" or type(url) ~= "string" then return nil end
	local level = #url <= Link.M_MAX_BYTES and 2 or 1
	local ok, done, matrix = pcall(enc.qrcode, url, level, nil, pause)
	if not ok or not done or type(matrix) ~= "table" then return nil end
	qr = { url = url, matrix = matrix, level = level }
	return matrix, level
end

-- The dark modules as few rectangles: the runs of each row, a run the next row repeats
-- growing down. { x, y, w, h } in modules from the top left (0-based).
function Link.Rects(matrix)
	local n, out, open = #matrix, {}, {}
	for y = 1, n do
		local nextOpen, x = {}, 1
		while x <= n do
			if matrix[x][y] > 0 then
				local x2 = x
				while x2 < n and matrix[x2 + 1][y] > 0 do x2 = x2 + 1 end
				local k = x * 1000 + x2
				local rect = open[k]
				if rect then
					rect.h = rect.h + 1
				else
					rect = { x = x - 1, y = y - 1, w = x2 - x + 1, h = 1 }
					out[#out + 1] = rect
				end
				nextOpen[k] = rect
				x = x2 + 1
			else
				x = x + 1
			end
		end
		open = nextOpen
	end
	return out
end

-- UI units of one screen pixel for this frame, and the screen's height in pixels.
local function PixelSize(f)
	local h
	if GetPhysicalScreenSize then h = select(2, GetPhysicalScreenSize()) end
	h = tonumber(h) or 0
	if h <= 0 then h = 1080 end
	local scale = f and f.GetEffectiveScale and f:GetEffectiveScale() or 1
	if not scale or scale <= 0 then scale = 1 end
	return 768 / h / scale, h
end
Link.PixelSize = PixelSize

-- Screen pixels per module: about half the screen's height for the whole code; 4 at least when
-- the window still fits on the screen, else 3.
function Link.ModulePixels(modules, screenH, chromePx)
	screenH = tonumber(screenH) or 1080
	local want = math.max(4, math.floor(screenH * 0.5 / modules))
	local room = math.floor((screenH - (chromePx or 0)) / modules)
	return math.max(3, math.min(want, room))
end

-- The window's top left on a whole screen pixel, so each module's edges are too.
local function Snap(f)
	local px = PixelSize(f)
	local left, top = f:GetLeft(), f:GetTop()
	if not left or not top then return end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.floor(left / px + 0.5) * px, math.floor(top / px + 0.5) * px)
end

local function MakeWindow()
	local f = CreateFrame("Frame", "OlympusLinkFrame", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Snap(self)
	end)
	f:SetPoint("CENTER")
	f:Hide()
	local okBorder, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if not okBorder or not border then
		border = f:CreateTexture(nil, "BACKGROUND")
		border:SetColorTexture(0, 0, 0, 0.9)
	end
	border:SetAllPoints()
	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	f.title:SetPoint("TOP", 0, -18)
	f.title:SetText(L.LINK_TITLE)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	f.name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	f.name:SetPoint("TOP", 0, -42)
	f.canvas = CreateFrame("Frame", nil, f)
	f.canvas.bg = f.canvas:CreateTexture(nil, "BACKGROUND")
	f.canvas.bg:SetColorTexture(1, 1, 1, 1)
	f.canvas.bg:SetAllPoints()
	f.modules = {}
	f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	f.hint:SetPoint("TOP", f.canvas, "BOTTOM", 0, -12)
	f.hint:SetJustifyH("CENTER")
	f.copyLabel = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	f.copyLabel:SetPoint("TOP", f.hint, "BOTTOM", 0, -10)
	f.copyLabel:SetText(L.LINK_COPY)
	local okBox, eb = pcall(CreateFrame, "EditBox", "OlympusLinkCopyBox", f, "InputBoxTemplate")
	if not okBox or not eb then eb = CreateFrame("EditBox", nil, f) end
	eb:SetHeight(22)
	eb:SetPoint("TOP", f.copyLabel, "BOTTOM", 0, -6)
	eb:SetAutoFocus(false)
	eb:SetFontObject("ChatFontNormal")
	eb.olympusBox = true
	-- Read only: whatever is typed, the link comes back, selected for Ctrl+C.
	eb:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(f.url or "")
			self:HighlightText()
		end
	end)
	eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.copy = eb
	f:SetScript("OnHide", function(self)
		if self:IsShown() then return end -- the whole interface hidden (Alt+Z): still open
		self.copy:ClearFocus()
	end)
	return f
end

-- The window drawn for this link: the code at whole pixels, sized around it.
local function Fill(f, bundle, b, rec, matrix)
	local url = Link.URL(bundle)
	f.url, f.bundle = url, bundle
	local px, screenH = PixelSize(f)
	local modules = #matrix + 2 * Link.QUIET
	local mpx = Link.ModulePixels(modules, screenH, math.ceil(Link.CHROME / px))
	local m = mpx * px
	local sizePx = modules * mpx
	local widthPx = math.max(sizePx + 48, math.ceil(420 / px))
	local leftPx, topPx = math.floor((widthPx - sizePx) / 2), math.ceil(66 / px)
	f.modulePixels, f.codePixels = mpx, sizePx
	f:SetWidth(widthPx * px)
	f:SetHeight(topPx * px + sizePx * px + Link.CHROME - 66)
	local canvas = f.canvas
	canvas:ClearAllPoints()
	canvas:SetPoint("TOPLEFT", f, "TOPLEFT", leftPx * px, -topPx * px)
	canvas:SetSize(sizePx * px, sizePx * px)
	local rects = Link.Rects(matrix)
	for i, rect in ipairs(rects) do
		local t = f.modules[i]
		if not t then
			t = canvas:CreateTexture(nil, "ARTWORK")
			t:SetColorTexture(0, 0, 0, 1)
			f.modules[i] = t
		end
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (Link.QUIET + rect.x) * m, -(Link.QUIET + rect.y) * m)
		t:SetSize(rect.w * m, rect.h * m)
		t:Show()
	end
	for i = #rects + 1, #f.modules do f.modules[i]:Hide() end
	f.shownModules = #rects
	local by = rec.council and L.LINK_BY_COUNCIL or L.LINK_BY_PLAYERS:format(#b.proofs)
	f.name:SetText(ns.DisplayName(b.requester) .. "  |cff9d9d9d·  " .. by .. "|r")
	f.hint:SetWidth(widthPx * px - 40)
	f.hint:SetText(L.LINK_SCAN:format(Link.WatcherLabel()))
	f.copy:SetWidth(widthPx * px - 60)
	f.copy:SetText(url)
	f.copy:SetCursorPosition(0)
	return true
end

local function Open(bundle, b, rec, matrix)
	frame = frame or MakeWindow()
	Fill(frame, bundle, b, rec, matrix)
	local was = frame:IsShown()
	frame:Show()
	if not was then Snap(frame) end
	ns.EscapeCloses("OlympusLinkFrame")
end

-- /oly discord show, and when a proof is ready. The QR code is made in a job (a big one takes
-- a few frames), then the window opens.
function Link.ShowWindow(fromCommand)
	local rec = Store().chars[ns.me]
	local bundle = type(rec) == "table" and (rec.state == "ready" or rec.state == "delivered") and rec.bundle or nil
	local b = Link.Parse(bundle)
	if not b or b.requester ~= ns.me then
		if fromCommand then ns.Print(type(rec) == "table" and rec.state == "waiting" and L.LINK_STILL_WAITING or L.LINK_NOTHING) end
		return false
	end
	local url = Link.URL(bundle)
	if qr.url == url then
		Open(bundle, b, rec, qr.matrix)
		return true
	end
	if qrJob == url then return true end
	qrJob = url
	return Ed.Run(function() return Link.Matrix(url, Ed.Pause) end, function(ok, matrix)
		if qrJob == url then qrJob = nil end
		-- (Forgotten or replaced meanwhile: nothing to show.)
		if not ok or type(matrix) ~= "table" or Store().chars[ns.me] ~= rec or rec.bundle ~= bundle then return end
		Open(bundle, b, rec, matrix)
	end)
end

function Link.HideWindow()
	if frame then frame:Hide() end
end

function Link.Window() return frame end

---------------------------------------------------------------------------
-- Commands, dialogs, status
---------------------------------------------------------------------------

-- The code typed or pasted: checked first (the bot's signature, the expiry), then the player's
-- yes (nothing is sent before it).
function Link.Enter(text)
	local t = Link.ParseToken(text)
	if not t then return ns.Print(L.LINK_CODE_BAD) end
	if #Link.BackendKeys() == 0 then return ns.Print(L.LINK_NOT_OPEN) end
	local now = ServerTime()
	if t.exp <= now then return ns.Print(L.LINK_CODE_EXPIRED) end
	if t.exp > now + Link.CODE_TTL_MAX then return ns.Print(L.LINK_CODE_BAD) end
	ns.Print(L.LINK_CHECKING)
	local queued = Ed.Run(function() return Link.VerifyToken(t) end, function(ok, valid)
		if not ok or not valid then return ns.Print(L.LINK_CODE_BAD) end
		if t.exp <= ServerTime() then return ns.Print(L.LINK_CODE_EXPIRED) end
		if not ns.IsMember() then return ns.Print(L.LINK_NOT_MEMBER) end
		local who = ns.DisplayName(ns.me) or "?"
		ns.ShowDialog("OLYMPUS_LINK_CONSENT", L.LINK_CONSENT:format(who, t.user, t.user), nil, t)
	end)
	if not queued then ns.Print(L.LINK_BUSY) end
end

function Link.Forget()
	Store().chars[ns.me] = nil
	req, delivery, waitWatcher = nil, nil, false
	wipe(sentTo)
	Link.HideWindow()
	ns.Print(L.LINK_FORGOTTEN)
end

local function Hours(seconds) return math.max(1, math.ceil(seconds / 3600)) end
local function Days(seconds) return math.max(1, math.ceil(seconds / 86400)) end

-- /oly discord status: every character of the account with a request or a proof.
function Link.PrintStatus()
	local d, now, server = Store(), ns.Now(), ServerTime()
	local list = {}
	for name, rec in pairs(d.chars) do
		if type(rec) == "table" then list[#list + 1] = name end
	end
	table.sort(list)
	ns.Print(L.LINK_TITLE)
	for _, name in ipairs(list) do
		local rec = d.chars[name]
		local who = ns.DisplayName(name)
		if rec.state == "waiting" then
			local n = 0
			for _, p in pairs(type(rec.proofs) == "table" and rec.proofs or {}) do
				if p.c or FreshP(p, now) then n = n + 1 end
			end
			local need = rec.mode == "a" and L.LINK_NEED_PLAYERS:format(math.min(n, Link.NEEDED), Link.NEEDED) or L.LINK_NEED_COUNCIL
			print(L.LINK_STATUS_WAITING:format(who, need, Hours((tonumber(rec.exp) or server) - server)))
		elseif rec.state == "ready" then
			print(L.LINK_STATUS_READY:format(who, Link.WatcherLabel(), Days(Link.DELIVER_FOR - (now - (tonumber(rec.readyAt) or now)))))
		elseif rec.state == "delivered" then
			print(L.LINK_STATUS_DELIVERED:format(who, Link.WatcherLabel()))
		end
	end
	if #list == 0 then print(L.LINK_STATUS_NONE) end
	local key = Link.Key()
	print(key and L.LINK_STATUS_KEY:format(key.id, MyTier() == "c" and L.LINK_TIER_C or L.LINK_TIER_P) or L.LINK_STATUS_NOKEY)
	if ns.IsHighCouncillor(ns.me) then
		local n = 0
		for _ in pairs(d.inbox) do n = n + 1 end
		print(Link.Watching() and L.LINK_STATUS_WATCHER_ON:format(n) or L.LINK_STATUS_WATCHER_OFF)
	end
end

-- One line for /oly status and the bug report: never the key itself, the code or a proof.
function Link.StatusLine()
	local key, now = Link.Key(), ns.Now()
	local c, p = 0, 0
	for name, a in pairs(announcers) do
		if now - a.t <= Link.ANNOUNCE_FRESH then
			if IsCouncillor(name, a) then c = c + 1 else p = p + 1 end
		end
	end
	local rec = ns.db and type(ns.db.discord) == "table" and type(ns.db.discord.chars) == "table" and ns.db.discord.chars[ns.me]
	local state = type(rec) == "table" and tostring(rec.state) or "none"
	if req then
		local asked = 0
		for _ in pairs(req.asked) do asked = asked + 1 end
		state = state .. (" (mode %s, %d asked)"):format(tostring(req.rec.mode), asked)
	end
	local inbox = 0
	if ns.db and type(ns.db.discord) == "table" and type(ns.db.discord.inbox) == "table" then
		for _ in pairs(ns.db.discord.inbox) do inbox = inbox + 1 end
	end
	return ("key %s  |  this character %s  |  confirmers online c=%d p=%d  |  watchers online %d  |  watcher %s, inbox %d  |  confirmed %d, refused %d  |  jobs %d"):format(
		key and (key.id .. " as " .. MyTier()) or "none", state, c, p, #OnlineWatchers(now), Link.Watching() and "on" or "off",
		inbox, stats.confirmed, stats.refused, Ed.Busy())
end

-- /oly discord [code | show | status | forget | key [<id> <key> | off] | watcher on|off]
function Link.Slash(rest)
	rest = tostring(rest or ""):match("^%s*(.-)%s*$")
	local verb, arg = rest:match("^(%S*)%s*(.-)$")
	verb = (verb or ""):lower()
	if rest == "" then
		ns.ShowDialog("OLYMPUS_LINK_CODE")
	elseif verb == "show" and arg == "" then
		Link.ShowWindow(true)
	elseif verb == "status" and arg == "" then
		Link.PrintStatus()
	elseif verb == "forget" and arg == "" then
		Link.Forget()
	elseif verb == "key" then
		Link.SetKey(arg)
	elseif verb == "watcher" then
		local on = arg:lower()
		if on == "on" or on == "off" then
			Link.SetWatcher(on == "on")
		elseif Link.Watching() then
			local n = 0
			for _ in pairs(Store().inbox) do n = n + 1 end
			ns.Print(L.LINK_WATCHER_ON:format(n))
		else
			ns.Print(ns.IsHighCouncillor(ns.me) and L.LINK_WATCHER_OFF or L.LINK_WATCHER_ONLY)
		end
	else
		Link.Enter(rest)
	end
end

StaticPopupDialogs["OLYMPUS_LINK_CODE"] = {
	text = L.LINK_PASTE_PROMPT,
	button1 = L.LINK_CONTINUE,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = 200,
	editBoxWidth = 300,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		local text = eb and eb:GetText() or ""
		ns.SafeCall("discord code", Link.Enter, text)
	end,
	EditBoxOnEnterPressed = function(self)
		local text = self:GetText()
		self:GetParent():Hide()
		ns.SafeCall("discord code", Link.Enter, text)
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- The sentence comes whole (the username twice): "%s" and the text as its argument.
StaticPopupDialogs["OLYMPUS_LINK_CONSENT"] = {
	text = "%s",
	button1 = L.LINK_ACCEPT,
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data)
		ns.SafeCall("discord link", Link.Start, data or (self and self.data))
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Login and the ticker
---------------------------------------------------------------------------

local function Restore(rec, server)
	if type(rec) ~= "table" or rec.state ~= "waiting" or not Code(rec.R) or not User(rec.user) or not Nonce(rec.nonce)
		or not Link.ValidGuild(rec.guild) or not FACTIONS[rec.faction] or (rec.mode ~= "c" and rec.mode ~= "a") then return nil end
	if (tonumber(rec.exp) or 0) <= server then return nil end
	local proofs = {}
	for name, p in pairs(type(rec.proofs) == "table" and rec.proofs or {}) do
		if ValidProof(p) and p.confirmer == name and tonumber(p.got) then proofs[name] = p end
	end
	rec.proofs = proofs
	return Runtime(rec)
end

-- At login: this character's request waiting comes back; what expired goes.
function Link.Resume()
	if type(ns.db.discord) ~= "table" then return end -- never used on this account
	local d, now, server = Store(), ns.Now(), ServerTime()
	local expired = false
	for name, rec in pairs(d.chars) do
		local keep = type(rec) == "table"
		if keep and rec.state == "waiting" then
			keep = (tonumber(rec.exp) or 0) > server
			if not keep and name == ns.me then expired = true end
		elseif keep then
			keep = (rec.state == "ready" or rec.state == "delivered") and now - (tonumber(rec.readyAt) or 0) < Link.DELIVER_FOR
		end
		if not keep then d.chars[name] = nil end
	end
	for name, times in pairs(d.given) do
		if type(times) ~= "table" or type(times[#times]) ~= "number" or now - times[#times] >= 86400 then d.given[name] = nil end
	end
	local rec = d.chars[ns.me]
	req = Restore(rec, server)
	if req then
		ns.Print(L.LINK_RESUMED)
	elseif type(rec) == "table" and rec.state == "waiting" then
		d.chars[ns.me] = nil
	elseif type(rec) == "table" and rec.state == "ready" then
		ns.Print(L.LINK_READY_REMINDER:format(Link.WatcherLabel()))
	elseif expired then
		ns.Print(L.LINK_EXPIRED)
	end
end

function Link.Tick()
	local now = ns.Now()
	if now - lastPrune >= 60 then Prune(now) end
	Link.Announce()
	Link.AnnounceWatcher()
	if req then Link.Step(now) end
	Link.Deliver(now)
end

-- At login: the request or proof of this character back; the ticker says we are online (a key
-- holder, a watcher) at its first tick, then every ANNOUNCE_EVERY.
function Link.Login()
	Link.Resume()
	ns.Every(5, "discord link", Link.Tick)
end
ns.On("LOGIN", function() Link.Login() end)

ns.Comm.Handle("DV", function(...) Link.HandleAnnounce(...) end)
ns.Comm.Handle("DR", function(...) Link.HandleRequest(...) end)
ns.Comm.Handle("DA", function(...) Link.HandleAnswer(...) end)
ns.Comm.Handle("DW", function(...) Link.HandleWatcher(...) end)
ns.Comm.Handle("DB", function(...) Link.HandleBundle(...) end)
ns.Comm.Handle("DK", function(...) Link.HandleAck(...) end)

-- Tests start from a clean state.
function Link.Request() return req end
function Link.Announcers() return announcers end
function Link.Watchers() return watchers end
function Link.Delivery() return delivery end
function Link.Stats() return stats end
function Link.Reset()
	req, delivery, waitWatcher, pubCache, qrJob = nil, nil, false, nil, nil
	wipe(announcers); wipe(watchers); wipe(recent); wipe(sentTo); wipe(inboxFrom)
	inAsm = ns.Codec.NewAssembler()
	nAnnouncers, lastAnnounce, lastWatch, lastPrune = 0, -math.huge, -math.huge, -math.huge
	stats.confirmed, stats.refused, stats.kept = 0, 0, 0
	ranks = { of = {}, n = 0 }
	qr = {}
	if frame then frame:Hide() end
	frame = nil
end
