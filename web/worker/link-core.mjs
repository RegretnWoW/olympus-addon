// Olympus Link: the core, for the Olympus bot's Worker. Everything the bot needs to issue codes,
// check the proofs the game makes, give the role through your own promote(), and keep the
// confirmers' keys, as plain functions over a D1 database. No framework, no npm package: WebCrypto
// (Ed25519, SHA-256) and fetch only, so it runs on Cloudflare Workers and on Node 20 or newer.
// web/FERN.md says how to wire it in, web/WORKER.md explains every check, web/worker/link-worker.js
// is a complete Worker built on it, and web/test runs all of it against the shared vectors.
//
// What it reads from `env` (your Worker's bindings):
//   LINK_DB              the D1 database with web/worker/schema.sql (DB when there is no LINK_DB)
//   LINK_BACKEND_SEED    secret: your bot's Ed25519 seed, base64url (scripts/link-keys.py backend)
//   LINK_BACKEND_PUBLIC  its public key, 64 hex: the addon holds the same one (ns.LINK_BACKEND_KEYS)
//   LINK_CA_PUBLIC       the council authority's public key, 64 hex (two, comma-separated, while it
//                        changes): the addon author's client certifies High Councillors' keys with it
//   LINK_COUNCIL_CHARACTERS  the High Councillors' characters you accept from the council authority
//                        ("Name-Realm", comma-separated): its certificate for any other character
//                        counts for nothing. Closed by default: left out or empty, none counts
//   LINK_MODE            "c" councillors only (launch), "a" one councillor or three drawn players
//   LINK_GUILD_POLICY    "verified" (the default) or "claimed" (web/WORKER.md, "The guild check")
//   LINK_ORIGIN          the page's origin, "https://dnl-gentile.github.io" (CORS of POST /proof)
//   DISCORD_CLIENT_ID    your Discord application's id: a sign-in the page sends must be for it
//   LINK_SITE_TOKEN      optional: the token the page sends with POST /proof (a switch, not a secret)
//   LINK_ADMIN_TOKEN     secret, 32 characters or more: your own tools' (watcher inbox, keys)
//
// The functions, by what they are for:
//   codes      issueCode(env, user) -> { ok, token, command, reply }        (your /verify)
//   proofs     checkProof(env, text, { discordId })   reads only: the verdict
//              acceptProof(env, text, { discordId, promote, demote })   checks, claims the code,
//              calls your promote(discordId), records the link (and frees the code if promote fails)
//              handleProof(request, env, { promote, demote })   the whole POST /proof, CORS included
//   watcher    acceptInbox(env, body, { promote }) / handleInbox(request, env, { promote })
//   keys       manageKeys(env, body) / handleKeys(request, env), registerKey, renewKey, revokeKey,
//              revokeCharacter, councilCharacters(env)
//   people     discordUser(accessToken, { clientId }), forgetUser(env, discordId)
//   answers    httpStatus(answer), respond(answer, headers), corsHeaders(request, env)

export const LINK = {
	TOKEN_LIFE: 24 * 3600, // a code works for a day...
	REUSE_LEFT: 12 * 3600, // ...and is handed out again while it has this long left
	CODES_PER_DAY: 3,
	DELIVERY_GRACE: 7 * 24 * 3600, // a link is taken until its code's expiry + this: the addon hands it to a
	// watcher until 5 days after the expiry, so the watcher's keeper has 2 days to upload it
	CLOCK_SKEW: 300, // game server clock vs ours
	WINDOW: 300, // three player proofs within 5 minutes of each other
	PLAYERS_NEEDED: 3,
	KEY_MIN_AGE: 7 * 24 * 3600, // a player key counts for codes issued 7 days after it...
	ACCOUNT_MIN_AGE: 30 * 24 * 3600, // ...and its owner's Discord account is 30 days older than the code
	SUBMITS_PER_HOUR: 10,
	MAX_BUNDLES: 500,
	CERT_DAYS: 365, // a councillor key's certificate life, unless the request says otherwise...
	CERT_DAYS_PLAYER: 90, // ...a player key's: a revoked or replaced one stays in the addons' draw until it ends...
	CERT_DAYS_MAX: 3650, // ...up to this
	CA_DAYS: 365, // the life of a council authority's certificate (the addon's Link.CA_DAYS): one
	// ending at exp was signed at exp - this, which is how a character's revocation finds the older ones
};

// Every reason POST /proof can answer (web/public/i18n.js has words for each, in both languages).
export const PROOF_REASONS = [
	'linked', // status "linked": done
	'already', // status "linked": that link had counted before, nothing new
	'format', // "rejected" from here on: the code stays unused
	'unknown-code',
	'other-user',
	'tag',
	'code-used',
	'expired',
	'not-enough',
	'guild-unverified',
	'not-in-server',
	'login', // "error" from here on: nothing was used, the same link works again
	'origin',
	'site',
	'limit',
	'discord',
	'server',
];

const R_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const R_RE = /^[0-9A-HJKMNP-TV-Z]{10}$/;
const USERNAME_RE = /^[a-z0-9_.]{2,32}$/;
const DISCORD_ID_RE = /^[0-9]{5,25}$/;
const KEYID_RE = /^[a-z0-9]{6,16}$/;
const NONCE_RE = /^[0-9a-f]{16}$/;
const TAG_RE = /^[0-9a-f]{16}$/;
const ISSUED_RE = /^[1-9][0-9]{0,11}$/;
const SIG_RE = /^[A-Za-z0-9_-]{86}$/;
const PUBLIC_HEX_RE = /^[0-9a-f]{64}$/;
const PUBLIC_B64_RE = /^[A-Za-z0-9_-]{43}$/;
const ACCESS_TOKEN_RE = /^[A-Za-z0-9._~+/-]{10,256}={0,2}$/;
const FORBIDDEN = /[|~;,\u0000-\u001f\u007f]/;
const GV_RE = /^[rwc]$/; // how a confirmer checked the guild: r its own roster, w a recent /who, c claimed only
const CHECKED = (gv) => gv === 'r' || gv === 'w';
const GUILD_KNOWN = { r: 'roster', w: 'who', c: 'claimed' };
const CA_KEYID_RE = /^[0-9a-f]{12}$/; // a council authority's key: the first 12 hex of SHA-256 of the key
const MAX_PROOFS = 4;
const MAX_BUNDLE_BYTES = 2400; // four proofs, each with its certificate (the addon's Link.MAX_BUNDLE)
const MAX_CERT_BYTES = 240; // a certificate fits one chat line: DV~1~<certificate> (the addon's Link.MAX_CERT)
const NO_DRAW = '00000000'; // T of a mode "c" code: no player key is drawn
const ALL_DRAWN = 'ffffffff'; // T when there are M player keys or fewer
const DISCORD_API = 'https://discord.com/api/v10';

const enc = new TextEncoder();
const now = () => Math.floor(Date.now() / 1000);
const database = (env) => env.LINK_DB || env.DB;

// ---------------------------------------------------------------------------
// Answers: { ok, status, reason, message, ... }. status "rejected" (the link is refused, the code
// stays unused) or "error" (nothing happened: try again); a success has ok: true.

export function reject(reason, message, R) {
	return { ok: false, status: 'rejected', reason, message, R: R || null };
}

export function failure(reason, message, extra = {}) {
	return { ok: false, status: 'error', reason, message, ...extra };
}

const HTTP = {
	format: 400,
	username: 400,
	auth: 401,
	login: 401,
	site: 401,
	origin: 403,
	'unknown-key': 404,
	method: 405,
	'key-id-used': 409,
	'public-key-used': 409,
	'owner-has-key': 409,
	'character-not-linked': 409,
	revoked: 409,
	replaced: 409,
	'too-early': 409,
	limit: 429,
	server: 500,
};

// The HTTP status of an answer: 200 for anything but an error of the request itself (a refused or
// failed link is a 200 with its reason, so the page reads it).
export function httpStatus(answer) {
	if (!answer || answer.status !== 'error') return 200;
	return HTTP[answer.reason] || 200;
}

// An answer as a JSON Response, with its HTTP status and extra headers (CORS, for the page).
export function respond(answer, headers = {}, status = httpStatus(answer)) {
	return new Response(JSON.stringify(answer), {
		status,
		headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...headers },
	});
}

// ---------------------------------------------------------------------------
// Codes: your /verify. The player pastes "/oly discord <token>" in the game; the addon checks the
// token with your public key and shows "@username" before the player accepts.
//   const code = await issueCode(env, { id: user.id, username: user.username });
//   reply ephemerally with code.reply (it holds the command, or why there is none)
// { ok: true, token, command, exp, mode, reply } or { ok: false, reason: 'login' | 'username' | 'limit', message, reply }.

export async function issueCode(env, user, source = 'discord') {
	const id = String(user && user.id);
	const username = String(user && user.username);
	if (!DISCORD_ID_RE.test(id)) return codeFailure('login');
	if (!USERNAME_RE.test(username)) return codeFailure('username');
	const DB = database(env);
	const t = now();
	const open = await DB.prepare('SELECT token, exp, mode FROM codes WHERE discord_id = ? AND username = ? AND used IS NULL AND exp > ? ORDER BY created DESC LIMIT 1')
		.bind(id, username, t + LINK.REUSE_LEFT)
		.first();
	if (open) return codeSuccess({ token: open.token, exp: open.exp, mode: open.mode });
	const count = await DB.prepare('SELECT COUNT(*) AS n FROM codes WHERE discord_id = ? AND created > ?').bind(id, t - 86400).first();
	if (count && count.n >= LINK.CODES_PER_DAY) return codeFailure('limit');
	const mode = env.LINK_MODE === 'a' ? 'a' : 'c';
	const exp = t + LINK.TOKEN_LIFE;
	const pool = mode === 'a' ? await drawPool(env, t) : null;
	for (let attempt = 0; attempt < 5; attempt++) {
		const R = randomR();
		const T = pool ? await thresholdOf(R, pool) : NO_DRAW;
		const payload = `OLC2.${R}.${username}.${exp}.${mode}.${T}`;
		const token = `${payload}.${await backendSign(env, payload)}`;
		try {
			await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(R, id, username, mode, T, t, exp, token, source)
				.run();
			return codeSuccess({ token, exp, mode, R, T });
		} catch (err) {
			if (!/unique|constraint/i.test(String(err && err.message))) throw err; // an R taken: draw again
		}
	}
	throw new Error('could not draw a free code');
}

function codeSuccess(r) {
	const out = { ok: true, status: 'ok', ...r, command: `/oly discord ${r.token}` };
	out.reply = codeReply(out);
	return out;
}

function codeFailure(reason) {
	const message = codeError(reason);
	return { ok: false, status: 'error', reason, message, reply: message };
}

function randomR() {
	const bytes = crypto.getRandomValues(new Uint8Array(10));
	return Array.from(bytes, (b) => R_ALPHABET[b & 31]).join(''); // 256 = 8 * 32: no bias
}

// The reply to /verify, for the player's eyes only (an ephemeral message).
export function codeReply(r) {
	const hours = Math.max(1, Math.round((r.exp - now()) / 3600));
	return [
		'Your Olympus Link code. Paste this line in the WoW chat, press Enter, then click Accept:',
		'```',
		`/oly discord ${r.token}`,
		'```',
		`It works once, for your account only, for the next ${hours} h. Keep it to yourself: not on stream, not in a screenshot, and neither the game's Olympus Link window. The confirmations happen in game; your role arrives when the link reaches the bot.`,
	].join('\n');
}

export function codeError(reason) {
	if (reason === 'limit') return 'You already got 3 codes today: use the last one, or try again tomorrow.';
	if (reason === 'username') return 'Your Discord username cannot be used in a code. Change it to the new style (lowercase, no #1234) and try again.';
	return 'Sign in with Discord first.';
}

// The signature at the end of a code token: what each link's tag is made from.
function tokenSig(token) {
	return String(token).slice(String(token).lastIndexOf('.') + 1);
}

// ---------------------------------------------------------------------------
// The draw: a player key's prefix for code R is the first 8 hex of SHA-256(R~keyId). At issue,
// T is the prefix at index M (0-based) of the active player keys' sorted prefixes, with
// M = max(20, ceil(3% of them)), or "ffffffff" when there are M keys or fewer: the key is drawn
// when its prefix < T. T is signed into the code and stored with it, and the addon asks every
// certified player key T draws, so a player key is certified only once it counts (certFrom).

export async function drawPrefix(R, keyId) {
	return (await sha256Hex(`${R}~${keyId}`)).slice(0, 8);
}

export function drawLimit(activePlayerKeys) {
	return Math.max(20, Math.ceil((activePlayerKeys * 3) / 100));
}

// The active player keys at time t: not revoked or replaced, a certificate valid now, old
// enough and from an old enough Discord account (the ones that could count for a new code).
export async function drawPool(env, t) {
	const rows = (
		await database(env)
			.prepare("SELECT key_id, owner_discord_id, created FROM keys WHERE kind = 'p' AND revoked = 0 AND replaced_at IS NULL AND cert_exp > ?")
			.bind(t)
			.all()
	).results || [];
	return rows.filter((k) => !tooYoung(k, t)).map((k) => k.key_id);
}

export async function thresholdOf(R, keyIds) {
	const prefixes = (await Promise.all(keyIds.map((id) => drawPrefix(R, id)))).sort();
	const m = drawLimit(prefixes.length);
	return prefixes.length > m ? prefixes[m] : ALL_DRAWN;
}

export async function drawThreshold(env, R, t = now()) {
	return thresholdOf(R, await drawPool(env, t));
}

// Why a player key is too young to count at time `at` (a code's issue), or null.
function tooYoung(key, at) {
	if (key.created + LINK.KEY_MIN_AGE > at) return 'key younger than 7 days';
	if (snowflakeTime(key.owner_discord_id) + LINK.ACCOUNT_MIN_AGE * 1000 > at * 1000) return 'Discord account younger than 30 days';
	return null;
}

export function snowflakeTime(id) {
	return Number((BigInt(id) >> 22n) + 1420070400000n);
}

// When a key may get its first certificate. The addon asks every player key with a valid
// certificate that a code's T draws, and cannot tell a key this Worker would refuse as too
// young: so a player key is certified only once it counts for every code a proof signed from
// then on can belong to, the oldest one still open included (issued TOKEN_LIFE earlier, and
// CLOCK_SKEW more for a game clock behind ours): 7 days old and its owner's account 30 days old
// at that code's issue. A councillor's key counts at once.
export function certFrom(key) {
	if (key.kind !== 'p') return key.created;
	const account = Math.ceil(snowflakeTime(key.owner_discord_id) / 1000) + LINK.ACCOUNT_MIN_AGE;
	return Math.max(key.created + LINK.KEY_MIN_AGE, account) + LINK.TOKEN_LIFE + LINK.CLOCK_SKEW;
}

// ---------------------------------------------------------------------------
// Links (bundles): what the game's QR code, copy box and SavedVariables carry.

// The link in whatever the page read: the bundle itself (OLB5~...), the address of the QR code or
// of the game's copy box (<page>#b=<bundle, percent-encoded>), or that fragment alone. Null when
// there is none. (The page reads Olympus.lua itself and sends only the link the player picked.)
export function proofText(input) {
	if (typeof input !== 'string') return null;
	let s = input.trim();
	const at = s.indexOf('#b=');
	if (at >= 0) s = s.slice(at + 3);
	else if (s.startsWith('b=')) s = s.slice(2);
	s = s.split('&')[0].trim();
	if (/%[0-9A-Fa-f]{2}/.test(s) || s.includes('+')) {
		try {
			s = decodeURIComponent(s.replace(/\+/g, ' '));
		} catch {
			return null;
		}
	}
	s = s.trim();
	return s.startsWith('OLB5~') ? s : null;
}

// What the addon's Link.Parse reads (Olympus/Link.lua; the page's web/public/core.js reads the
// same). Whether the proofs count is the check's call below: a key or owner is counted once.
// Each proof carries its key's certificate for its confirmer: <public key>,<tier>,<cert exp>,<cert sig>.
export function parseBundle(text) {
	if (typeof text !== 'string' || !text.startsWith('OLB5~')) return { ok: false, error: 'prefix' };
	if (enc.encode(text).length > MAX_BUNDLE_BYTES) return { ok: false, error: 'size' };
	const f = text.split('~');
	if (f.length !== 8) return { ok: false, error: 'fields' };
	const [, requester, guild, faction, nonce, R, tag, proofText] = f;
	if (!validCharacter(requester)) return { ok: false, error: 'requester' };
	if (!field(guild, 40)) return { ok: false, error: 'guild' };
	if (faction !== 'Alliance' && faction !== 'Horde') return { ok: false, error: 'faction' };
	if (!NONCE_RE.test(nonce)) return { ok: false, error: 'nonce' };
	if (!R_RE.test(R)) return { ok: false, error: 'code' };
	if (!TAG_RE.test(tag)) return { ok: false, error: 'tag' };
	const parts = proofText ? proofText.split(';') : [];
	if (parts.length < 1 || parts.length > MAX_PROOFS) return { ok: false, error: 'proofs' };
	const proofs = [];
	for (const part of parts) {
		const p = part.split(',');
		if (p.length !== 9) return { ok: false, error: 'proof' };
		const [issued, keyId, confirmer, gv, sig, pub, tier, certExp, certSig] = p;
		if (!ISSUED_RE.test(issued) || !KEYID_RE.test(keyId) || !validCharacter(confirmer) || !GV_RE.test(gv)) return { ok: false, error: 'proof' };
		if (!SIG_RE.test(sig) || b64urlEncode(b64urlDecode(sig)) !== sig) return { ok: false, error: 'sig' };
		if (!PUBLIC_B64_RE.test(pub) || b64urlEncode(b64urlDecode(pub)) !== pub || (tier !== 'c' && tier !== 'p') || !ISSUED_RE.test(certExp)) return { ok: false, error: 'cert' };
		if (!SIG_RE.test(certSig) || b64urlEncode(b64urlDecode(certSig)) !== certSig) return { ok: false, error: 'cert' };
		proofs.push({ issued: Number(issued), keyId, confirmer, gv, sig, pub, tier, certExp: Number(certExp), certSig });
	}
	return { ok: true, bundle: { requester, guild, faction, nonce, R, tag, proofs } };
}

// A field of the signed text: not empty, at most `max` bytes, no separator, pipe or control.
function field(s, max) {
	return typeof s === 'string' && s !== '' && !FORBIDDEN.test(s) && enc.encode(s).length <= max;
}

// "Name-Realm": the realm follows the last dash and has no dash or space.
function validCharacter(s) {
	return field(s, 64) && /^[^-].*-[^- ]+$/s.test(s);
}

// The exact text a confirmer's addon signed for one proof.
export function signedMessage(b, p) {
	return ['OLY4', b.requester, b.guild, p.gv, b.faction, b.nonce, b.R, b.tag, p.issued, p.keyId, p.confirmer].join('~');
}

// The certificate a proof carries: its key's, for its confirmer (a parsed certificate, below).
export function proofCertificate(p) {
	return parseCertificate(`OLK2.${p.keyId}.${p.pub}.${p.tier}.${p.certExp}.${p.confirmer}.${p.certSig}`);
}

// The tag that binds a link to the command it was made with: the first 16 hex of
// SHA-256(<the token's sig>~<requester>). The QR code and the copy box never carry the token,
// so whoever sees them cannot make a link of their own with the code.
export async function linkTag(sig, requester) {
	return (await sha256Hex(`${sig}~${requester}`)).slice(0, 16);
}

export function guildPolicy(env) {
	return env.LINK_GUILD_POLICY === 'claimed' ? 'claimed' : 'verified';
}

// ---------------------------------------------------------------------------
// The check

// The verdict on a link, reading only: nothing is written, nobody gets a role. opts.discordId: the
// signed-in Discord account, who must own the code (the page's POST /proof); leave it out for the
// watcher's inbox (the code's owner is the one linked). The link may come as the bundle, the QR
// code's address, or its fragment (proofText). Either
//   { ok: true, already, R, discordId, username, character, guild, faction, guildCheck, guildKnown,
//     by, confirmers, message }
// (guildCheck "r" the guild's roster, "w" a /who, "c" claimed; guildKnown the same in words; by
// "councillor" or "players"; already: this exact link counted before, nothing more to do), or a
// refusal { ok: false, status: 'rejected', reason, message, R } (PROOF_REASONS).
export async function checkProof(env, text, opts = {}) {
	return (await examine(env, text, opts)).verdict;
}

async function examine(env, input, opts = {}) {
	const t = opts.t || now();
	const DB = database(env);
	const text = proofText(input) || (typeof input === 'string' ? input.trim() : '');
	const parsed = parseBundle(text);
	if (!parsed.ok) return { verdict: reject('format', `This is not a complete Olympus link (${parsed.error}).`) };
	const b = parsed.bundle;
	const code = await DB.prepare('SELECT * FROM codes WHERE r = ?').bind(b.R).first();
	if (!code) return { verdict: reject('unknown-code', 'This link was made with a code the bot never issued.', b.R) };
	const userId = opts.discordId === undefined || opts.discordId === null ? null : String(opts.discordId);
	if (userId && code.discord_id !== userId) return { verdict: reject('other-user', 'This link was made with a code of another Discord account.', b.R) };
	if (b.tag !== (await linkTag(tokenSig(code.token), b.requester))) {
		return { verdict: reject('tag', 'This link was not made by the player who typed this code in the game.', b.R) };
	}
	if (code.used !== null && code.used !== undefined) {
		const same = await DB.prepare('SELECT guild, gv, faction FROM members WHERE character = ? AND discord_id = ? AND r = ?').bind(b.requester, code.discord_id, b.R).first();
		if (same) {
			const verdict = linkVerdict(code, b, same.gv, [], `${b.requester} is already linked.`);
			return { verdict: { ...verdict, already: true, guild: same.guild, faction: same.faction, by: null }, b, code };
		}
		return { verdict: reject('code-used', 'This code was already used.', b.R) };
	}
	if (t > code.exp + LINK.DELIVERY_GRACE) return { verdict: reject('expired', 'This code expired more than 7 days ago.', b.R) };

	const checks = [];
	for (const p of b.proofs) checks.push(await checkConfirmation(env, b, p, code, t));
	const valid = checks.filter((c) => c.ok);
	let why = checks.filter((c) => !c.ok).map((c) => `${c.proof.keyId}: ${c.why}`);
	// Councillors: one is enough (one that checked the guild is recorded first). Every
	// councillor and every drawn player that could count vouches for the guild.
	const councillors = valid.filter((c) => c.key.kind === 'c').sort((x, y) => CHECKED(y.proof.gv) - CHECKED(x.proof.gv));
	let counted = councillors.length ? [councillors[0]] : null;
	let vouching = councillors;
	if (code.mode === 'a') {
		const drawn = await drawnPlayers(code, valid.filter((c) => c.key.kind === 'p'));
		vouching = vouching.concat(drawn.eligible);
		if (!counted) {
			counted = drawn.picked;
			why = why.concat(drawn.why);
		}
	}
	if (!counted) {
		const need = code.mode === 'a' ? `one councillor or ${LINK.PLAYERS_NEEDED} drawn players` : 'one councillor';
		return { verdict: reject('not-enough', `Not enough valid confirmations (needs ${need}).${why.length ? ` ${why.join('; ')}.` : ''}`, b.R) };
	}
	const checked = vouching.find((c) => CHECKED(c.proof.gv));
	const gv = checked ? checked.proof.gv : 'c';
	if (!checked && guildPolicy(env) === 'verified') {
		return {
			verdict: reject('guild-unverified', `None of the confirmations checked ${b.guild} in game (a confirmer of that guild with its roster, or one who saw the player in it in a /who).`, b.R),
		};
	}
	const verdict = linkVerdict(code, b, gv, counted, `${b.requester} can be linked to @${code.username}.`);
	return { verdict, b, code, counted, valid, gv };
}

function linkVerdict(code, b, gv, counted, message) {
	return {
		ok: true,
		status: 'ok',
		already: false,
		R: b.R,
		discordId: code.discord_id,
		username: code.username,
		character: b.requester,
		guild: b.guild,
		faction: b.faction,
		guildCheck: gv,
		guildKnown: GUILD_KNOWN[gv] || 'claimed',
		by: counted.length ? (counted[0].key.kind === 'c' ? 'councillor' : 'players') : null,
		confirmers: counted.map((c) => c.proof.confirmer),
		message,
	};
}

// The check, then the link: claims the code (two deliveries of the same link may race), calls
// promote(discordId, verdict) to give the role, then records the character. When promote fails,
// or the record does, the code is freed again, so the same link works on the next try.
//   promote(discordId, verdict): yours. Resolve (with nothing, true or { ok: true }) when the role is
//     given; throw, or return false or { ok: false }, when it is not ({ ok: false, reason:
//     'not-in-server' } when the member is not in the server: the player is told to join first).
//   demote(discordId): optional. Called when the character was linked to another account that has
//     no other linked character left: take that account's role away. Its errors are only logged.
// Answers { ok, status: 'linked' | 'rejected' | 'error', reason, message, R, and for a link:
// discordId, username, character, guild, faction, guildCheck, guildKnown, characters }.
export async function acceptProof(env, text, opts = {}) {
	const { promote, demote } = opts;
	if (typeof promote !== 'function') throw new TypeError('Olympus Link: acceptProof needs promote(discordId), your function that gives the role');
	const t = opts.t || now();
	const DB = database(env);
	const x = await examine(env, text, { discordId: opts.discordId, t });
	const v = x.verdict;
	if (!v.ok) return v;
	const { b, code } = x;
	if (v.already) {
		return { ...linkedAnswer(v, 'already', v.message), characters: await charactersOf(env, code.discord_id) };
	}

	// Claim the code first (two deliveries of the same link may race), then the role. Anything
	// that fails after the claim releases it, so the same link works on the next try.
	const claim = await DB.prepare('UPDATE codes SET used = ? WHERE r = ? AND used IS NULL').bind(t, b.R).run();
	if (!claim.meta || claim.meta.changes !== 1) return reject('code-used', 'This code was already used.', b.R);
	const release = async () => {
		try {
			await DB.prepare('UPDATE codes SET used = NULL WHERE r = ? AND used = ?').bind(b.R, t).run();
		} catch (err) {
			console.error('olympus-link: could not release code', b.R, err && err.stack ? err.stack : err);
		}
	};
	const role = await promoted(promote, code.discord_id, v);
	if (!role.ok) {
		await release();
		if (role.reason === 'not-in-server') return reject('not-in-server', 'Join the Olympus Discord server first, then send the link again.', b.R);
		return failure('discord', 'Discord did not take the role change: try again in a minute.', { R: b.R });
	}
	let previous;
	try {
		previous = await DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(b.requester).first();
		await DB.batch([
			...x.counted.map((c) => DB.prepare('INSERT OR IGNORE INTO used (r, key_id, t) VALUES (?, ?, ?)').bind(b.R, c.proof.keyId, t)),
			// The council authority's keys whose proofs checked in this link: recorded now, not before.
			...x.valid.filter((c) => c.key.council).map((c) => recordCouncilKey(DB, c, t)),
			DB.prepare(
				'INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?) ' +
					'ON CONFLICT(character) DO UPDATE SET discord_id = excluded.discord_id, guild = excluded.guild, gv = excluded.gv, faction = excluded.faction, r = excluded.r, linked = excluded.linked',
			).bind(b.requester, code.discord_id, b.guild, x.gv, b.faction, b.R, t),
		]);
	} catch (err) {
		console.error('olympus-link: could not record the link', b.R, err && err.stack ? err.stack : err);
		await release();
		return failure('server', 'The link could not be recorded: send it again in a minute.', { R: b.R });
	}
	if (previous && previous.discord_id !== code.discord_id && typeof demote === 'function') {
		const left = await DB.prepare('SELECT COUNT(*) AS n FROM members WHERE discord_id = ?').bind(previous.discord_id).first();
		if (!left || left.n === 0) {
			// The character moved away, and the old account has no other.
			try {
				await demote(previous.discord_id);
			} catch (err) {
				console.error('olympus-link: demote failed for', previous.discord_id, err && err.stack ? err.stack : err);
			}
		}
	}
	return { ...linkedAnswer(v, 'linked', `${b.requester} is now linked to @${code.username}.`), characters: await charactersOf(env, code.discord_id) };
}

function linkedAnswer(v, reason, message) {
	const { discordId, username, character, guild, faction, guildCheck, guildKnown, R } = v;
	return { ok: true, status: 'linked', reason, message, R, discordId, username, character, guild, faction, guildCheck, guildKnown };
}

// promote()'s outcome as { ok } or { ok: false, reason }: it may resolve with nothing, a
// boolean or { ok, reason }, or throw.
async function promoted(promote, discordId, verdict) {
	let r;
	try {
		r = await promote(discordId, verdict);
	} catch (err) {
		console.error('olympus-link: promote failed for', discordId, err && err.stack ? err.stack : err);
		return { ok: false, reason: err && err.reason === 'not-in-server' ? 'not-in-server' : 'discord' };
	}
	if (r === false) return { ok: false, reason: 'discord' };
	if (r && typeof r === 'object' && r.ok === false) return { ok: false, reason: r.reason === 'not-in-server' ? 'not-in-server' : 'discord' };
	return { ok: true };
}

// One proof, checked whole (its key, time, signature and who confirms), reading only:
// { ok, proof, key } or { ok: false, proof, why }.
async function checkConfirmation(env, b, p, code, t) {
	const DB = database(env);
	const bad = (why) => ({ ok: false, proof: p, why });
	const found = await proofKey(env, p);
	if (found.why) return bad(found.why);
	const key = found.key;
	if (key.owner_discord_id && key.owner_discord_id === code.discord_id) return bad("the requester's own key");
	if (p.issued < code.created - LINK.CLOCK_SKEW || p.issued > code.exp) return bad('signed outside the code\'s life');
	if (p.issued > t + LINK.CLOCK_SKEW) return bad('signed in the future');
	if (!(await ed25519Verify(key.public_key, b64urlDecode(p.sig), enc.encode(signedMessage(b, p))))) return bad('bad signature');
	if (!key.council && !(key.kind === 'c' && key.bootstrap)) {
		const mine = await DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(p.confirmer, key.owner_discord_id).first();
		if (!mine) return bad("the confirmer is not a linked character of the key's owner");
	}
	if (p.confirmer === b.requester) return bad('the confirmer is the requester');
	if (key.owner_discord_id) {
		const own = await DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(b.requester, key.owner_discord_id).first();
		if (own) return bad("the requester is the key owner's own character");
	}
	const reused = await DB.prepare('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?').bind(b.R, p.keyId).first();
	if (reused) return bad('already counted');
	return { ok: true, proof: p, key };
}

// The key a proof is checked with: { key } or { why }. It only reads: nothing about a proof is
// written before the whole link is accepted (acceptProof). A key registered here (keys) is D1's:
// the certificate the proof carries must name its public key, tier and character, and D1 says
// whether it is revoked. A key this Worker never registered counts only as a High Councillor's
// certified by the council authority (the author's client, LINK_CA_PUBLIC): the certificate the
// proof carries is then checked here (tier c, the key's id the first 12 hex of SHA-256 of it,
// valid when the proof was signed), its character on LINK_COUNCIL_CHARACTERS (none when that list
// is left out), the revocation lists can end it (revoked_keys by its id, revoked_characters every
// certificate of a character signed before its revocation), and a key already recorded for
// another character (council_keys, by the key itself) is refused. The record is written with the
// first link it confirmed, once its signature checked: a certificate for someone else's public
// key, carried with a signature nobody made, records nothing.
async function proofKey(env, p) {
	const DB = database(env);
	const cert = proofCertificate(p);
	if (!cert) return { why: 'a certificate that does not read' };
	const row = await DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(p.keyId).first();
	if (row) {
		if (row.revoked) return { why: 'revoked key' };
		if (row.public_key !== cert.publicHex || row.kind !== cert.tier || row.character !== cert.character) {
			return { why: "its certificate is not the one registered for this key (public key, tier and character)" };
		}
		return { key: row };
	}
	if (!CA_KEYID_RE.test(p.keyId)) return { why: 'unknown key' };
	if (await DB.prepare('SELECT 1 AS x FROM revoked_keys WHERE key_id = ?').bind(p.keyId).first()) return { why: 'revoked key' };
	if (!(await councilCertificate(env, cert))) return { why: 'unknown key (not certified by the council authority)' };
	if (p.issued >= cert.exp) return { why: 'signed after its certificate ended' };
	// Your say over who is a councillor here: only the ones you list, whatever the authority signs.
	if (!councilCharacters(env).has(cert.character)) return { why: 'its character is not on LINK_COUNCIL_CHARACTERS' };
	// Its character revoked (a councillor off the list, or keys of theirs you can't name): every
	// certificate for it signed before then, whatever key it names.
	const gone = await DB.prepare('SELECT revoked_at FROM revoked_characters WHERE character = ?').bind(cert.character).first();
	if (gone && cert.exp - LINK.CA_DAYS * 86400 <= gone.revoked_at) return { why: 'its character was revoked (a certificate from before)' };
	const known = await DB.prepare('SELECT character FROM council_keys WHERE public_key = ?').bind(cert.publicHex).first();
	if (known && known.character !== cert.character) return { why: 'a council key recorded for another character' };
	// Its owner, when the councillor's character is linked: never confirms that account's codes or characters.
	const owner = await DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(cert.character).first();
	return {
		key: {
			key_id: p.keyId,
			public_key: cert.publicHex,
			kind: 'c',
			bootstrap: 1,
			council: true,
			character: cert.character,
			cert_exp: cert.exp,
			owner_discord_id: owner ? owner.discord_id : null,
		},
	};
}

// The record of a council authority's key whose proof checked, written with the link it helped
// accept: its character the first time, a later end of its certificate after (never another
// character's: that stays the first one's).
function recordCouncilKey(DB, c, t) {
	return DB.prepare(
		'INSERT INTO council_keys (public_key, key_id, character, cert_exp, first_seen) VALUES (?, ?, ?, ?, ?) ' +
			'ON CONFLICT(public_key) DO UPDATE SET cert_exp = MAX(council_keys.cert_exp, excluded.cert_exp) WHERE council_keys.character = excluded.character',
	).bind(c.key.public_key, c.key.key_id, c.key.character, c.key.cert_exp, t);
}

// Mode "a": three drawn players from three owners, signed within 5 minutes of each other. A
// player key counts when it was 7 days old and its owner's Discord account 30 days old when the
// code was issued, it was not replaced before that, and it is drawn: its prefix < the code's T.
async function drawnPlayers(code, valid) {
	const why = [];
	const eligible = [];
	for (const c of valid) {
		const young = tooYoung(c.key, code.created);
		if (young) why.push(`${c.proof.keyId}: ${young}`);
		else if (c.key.replaced_at && c.key.replaced_at <= code.created) why.push(`${c.proof.keyId}: replaced by a newer key`);
		else if (!((await drawPrefix(code.r, c.proof.keyId)) < code.draw_t)) why.push(`${c.proof.keyId}: not drawn for this code`);
		else eligible.push(c);
	}
	const inDraw = [...eligible].sort((a, b) => a.proof.issued - b.proof.issued);
	for (let i = 0; i < inDraw.length; i++) {
		const picked = [];
		const owners = new Set();
		for (let j = i; j < inDraw.length && inDraw[j].proof.issued - inDraw[i].proof.issued <= LINK.WINDOW; j++) {
			if (owners.has(inDraw[j].key.owner_discord_id)) continue;
			owners.add(inDraw[j].key.owner_discord_id);
			picked.push(inDraw[j]);
			if (picked.length === LINK.PLAYERS_NEEDED) return { picked, eligible, why };
		}
	}
	if (inDraw.length >= LINK.PLAYERS_NEEDED) why.push('the player confirmations are more than 5 minutes apart');
	return { picked: null, eligible, why };
}

// The characters linked to a Discord account, oldest first.
export async function charactersOf(env, discordId) {
	const rows = (await database(env).prepare('SELECT character FROM members WHERE discord_id = ? ORDER BY linked').bind(String(discordId)).all()).results || [];
	return rows.map((r) => r.character);
}

// The page's limit: SUBMITS_PER_HOUR links an hour per Discord account (counted in inbox_uploads).
export async function tooManyProofs(env, discordId, t = now()) {
	const recent = await database(env)
		.prepare("SELECT COUNT(*) AS n FROM inbox_uploads WHERE source = 'site' AND discord_id = ? AND uploaded > ?")
		.bind(String(discordId), t - 3600)
		.first();
	return !!recent && recent.n >= LINK.SUBMITS_PER_HOUR;
}

// The audit trail: every link received, from the page ('site') or the watcher's inbox ('watcher'),
// and what became of it. extra: { discordId, from, received, uploaded }.
export async function logProof(env, source, text, result, extra = {}) {
	const DB = database(env);
	const parsed = parseBundle(typeof text === 'string' ? proofText(text) || text.trim() : '');
	const b = parsed.ok ? parsed.bundle : null;
	const code = b ? await DB.prepare('SELECT discord_id FROM codes WHERE r = ?').bind(b.R).first() : null;
	await DB.prepare(
		'INSERT INTO inbox_uploads (source, r, discord_id, requester, from_character, received, uploaded, status, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
	)
		.bind(source, b ? b.R : null, extra.discordId || (code && code.discord_id) || null, b ? b.requester : null, extra.from || null, extra.received || null, extra.uploaded || now(), result.status, result.reason || null)
		.run();
}

// ---------------------------------------------------------------------------
// The page: POST /proof, from the static page on GitHub Pages
//
// Body {"text": "<the link: OLB5~... or its address>", "discordToken": "<the player's Discord
// access token>"}; the page sends "Authorization: Bearer <LINK_SITE_TOKEN>" when you gave it one.
// The token is only shown to Discord (GET /oauth2/@me), never stored: it must be for your
// application (DISCORD_CLIENT_ID) with the identify scope, and it says who the player is.

// The CORS headers for a request from the page's origin (LINK_ORIGIN, exactly; several may be
// listed, comma-separated, while a new address comes in), or null for any other origin.
export function corsHeaders(request, env) {
	const origin = request.headers.get('Origin');
	if (!origin || !allowedOrigins(env).includes(origin)) return null;
	return {
		'Access-Control-Allow-Origin': origin,
		'Access-Control-Allow-Methods': 'POST',
		'Access-Control-Allow-Headers': 'Authorization, Content-Type',
		Vary: 'Origin',
	};
}

export function allowedOrigins(env) {
	return String((env && env.LINK_ORIGIN) || '')
		.split(/[\s,]+/)
		.filter((o) => /^https?:\/\/[^/]+$/.test(o));
}

// Who a Discord access token belongs to, asked of Discord itself: { ok: true, user: { id,
// username, global_name, avatar } }, or an error answer (reason "login": sign in again;
// "discord": Discord did not answer). Only a token made for your application (clientId) with the
// identify scope counts: a token another site got for its own application does not.
export async function discordUser(accessToken, { clientId, fetchImpl = globalThis.fetch } = {}) {
	if (!DISCORD_ID_RE.test(String(clientId || ''))) throw new Error('Olympus Link: set DISCORD_CLIENT_ID to your Discord application\'s id');
	if (typeof accessToken !== 'string' || !ACCESS_TOKEN_RE.test(accessToken)) return failure('login', 'Sign in with Discord first.');
	let res;
	try {
		res = await fetchImpl(`${DISCORD_API}/oauth2/@me`, { headers: { Authorization: `Bearer ${accessToken}` } });
	} catch (err) {
		console.error('olympus-link: Discord oauth2/@me fetch failed:', err && err.message ? err.message : err);
		return failure('discord', 'Discord did not answer: try again in a minute.');
	}
	if (res.status === 401 || res.status === 403) return failure('login', 'Your Discord sign-in expired: sign in again.');
	if (!res.ok) return failure('discord', 'Discord did not answer: try again in a minute.');
	let info = null;
	try {
		info = await res.json();
	} catch {
		info = null;
	}
	const app = info && info.application;
	const u = info && info.user;
	if (!app || String(app.id) !== String(clientId)) return failure('login', 'This Discord sign-in is not for the Olympus bot: sign in again on the Olympus Link page.');
	if (!Array.isArray(info.scopes) || !info.scopes.includes('identify') || !u || !DISCORD_ID_RE.test(String(u.id)) || typeof u.username !== 'string') {
		return failure('login', 'Sign in with Discord again.');
	}
	if (info.expires && Date.parse(info.expires) <= Date.now()) return failure('login', 'Your Discord sign-in expired: sign in again.');
	return { ok: true, user: { id: String(u.id), username: u.username, global_name: u.global_name ?? null, avatar: u.avatar ?? null } };
}

// The whole POST /proof, CORS preflight included, as a Response: the origin, your site token
// (when you set LINK_SITE_TOKEN), the body, the link's form, who the player is (discordUser), 10
// links an hour per account, then acceptProof with your promote, and the audit trail.
//   if (url.pathname === '/proof') return handleProof(request, env, { promote, demote });
export async function handleProof(request, env, { promote, demote, fetchImpl } = {}) {
	const cors = corsHeaders(request, env);
	const reply = (answer) => respond(answer, cors || { Vary: 'Origin' });
	try {
		if (request.method === 'OPTIONS') {
			return new Response(null, { status: cors ? 204 : 403, headers: cors ? { ...cors, 'Access-Control-Max-Age': '600' } : { Vary: 'Origin' } });
		}
		if (request.method !== 'POST') return reply(failure('method', 'POST only.'));
		if (!cors) return reply(failure('origin', 'Wrong origin.'));
		if (env.LINK_SITE_TOKEN && !(await sameSecret(bearer(request), env.LINK_SITE_TOKEN))) {
			return reply(failure('site', 'This page is not allowed to send links right now.'));
		}
		const body = await readJson(request, 8 * 1024);
		if (!body || typeof body.text !== 'string' || typeof body.discordToken !== 'string') {
			return reply(failure('format', 'Send {"text": "<the link>", "discordToken": "<the Discord sign-in>"}.'));
		}
		const text = proofText(body.text);
		if (!text || !parseBundle(text).ok) {
			const why = text ? parseBundle(text).error : 'prefix';
			return reply(reject('format', `This is not a complete Olympus link (${why}).`));
		}
		const who = await discordUser(body.discordToken, { clientId: env.DISCORD_CLIENT_ID, fetchImpl });
		if (!who.ok) return reply(who);
		const t = now();
		if (await tooManyProofs(env, who.user.id, t)) return reply(failure('limit', 'Too many tries: wait a while and send it again.'));
		const result = await acceptProof(env, text, { discordId: who.user.id, promote, demote, t });
		try {
			await logProof(env, 'site', text, result, { discordId: who.user.id, uploaded: t });
		} catch (err) {
			console.error('olympus-link: could not log', err && err.stack ? err.stack : err);
		}
		return reply(pageAnswer(result));
	} catch (err) {
		console.error('olympus-link: /proof', err && err.stack ? err.stack : err);
		return reply(failure('server', 'Something went wrong on our side.'));
	}
}

// What the page gets back: the answer without the Discord id.
function pageAnswer(r) {
	const { discordId, ...rest } = r;
	return rest;
}

// ---------------------------------------------------------------------------
// The watcher (the whisper path): many links at once, from a High Councillor's inbox, uploaded by
// web/tools/read-inbox.mjs with your admin token. The Discord account is each code's owner.
//   body: {"bundles": [{"R", "bundle", "from", "t"}, ...]} (500 at most; a bare string is a bundle)
// { ok: true, status: 'ok', results: [{ R, status, reason, message }] } or a format error.
export async function acceptInbox(env, body, { promote, demote } = {}) {
	if (typeof promote !== 'function') throw new TypeError('Olympus Link: acceptInbox needs promote(discordId), your function that gives the role');
	const list = body && Array.isArray(body.bundles) ? body.bundles : null;
	if (!list || list.length > LINK.MAX_BUNDLES) return failure('format', `Send {"bundles": [...]} with at most ${LINK.MAX_BUNDLES}.`);
	const results = [];
	for (const item of list) {
		const entry = item && typeof item === 'object' ? item : {};
		const text = (typeof item === 'string' ? item : typeof entry.bundle === 'string' ? entry.bundle : '').trim();
		const t = now();
		const parsed = parseBundle(text);
		let result;
		try {
			result =
				parsed.ok && typeof entry.R === 'string' && entry.R !== parsed.bundle.R
					? reject('format', 'The inbox key does not match the link.', parsed.bundle.R)
					: await acceptProof(env, text, { t, promote, demote });
		} catch (err) {
			// One link that fails on our side does not stop the others: this one is sent again later.
			console.error('olympus-link: inbox entry', err && err.stack ? err.stack : err);
			result = failure('server', 'Something went wrong on our side: send it again.', { R: parsed.ok ? parsed.bundle.R : null });
		}
		try {
			await logProof(env, 'watcher', text, result, {
				from: typeof entry.from === 'string' ? entry.from.slice(0, 100) : null,
				received: Number.isFinite(entry.t) ? Math.floor(entry.t) : null,
				uploaded: t,
			});
		} catch (err) {
			console.error('olympus-link: inbox log', err && err.stack ? err.stack : err);
		}
		results.push({ R: result.R || (typeof entry.R === 'string' ? entry.R : null), status: result.status, reason: result.reason, message: result.message });
	}
	return { ok: true, status: 'ok', results };
}

// POST <your inbox route> for read-inbox.mjs --post: the admin token, then acceptInbox.
export async function handleInbox(request, env, { promote, demote } = {}) {
	if (!(await adminAuthorized(request, env))) return respond(failure('auth', 'Wrong admin token.'));
	const body = await readJson(request, 2 * 1024 * 1024);
	return respond(await acceptInbox(env, body, { promote, demote }));
}

// ---------------------------------------------------------------------------
// Confirmer keys and their certificates
//
// A certificate tells every requester's addon, without the bot online, that a key is
// certified, whether it is a councillor's (c) or a drawn player's (p), and for which character:
//   OLK2.<keyId>.<public key, 43 base64url>.<tier>.<exp>.<Name-Realm>.<sig>
// sig: Ed25519 over the UTF-8 bytes of everything before the last dot, by the backend key (a
// key registered here), or, tier c only and for a key whose id is the first 12 hex of SHA-256 of
// it, by the council authority's (a High Councillor's key made in game, certified by the
// author's client). The character is read from both ends (it may hold dots). Only that character
// announces it and confirms with it, and every proof carries it in the link.

export async function makeCertificate(env, keyId, publicHex, tier, exp, character) {
	const payload = `OLK2.${keyId}.${b64urlEncode(hexToBytes(publicHex))}.${tier}.${exp}.${character}`;
	return `${payload}.${await backendSign(env, payload)}`;
}

// { keyId, publicHex, tier, exp, character, sig, payload } or null.
export function parseCertificate(text) {
	const s = String(text);
	const m = /^OLK2\.([a-z0-9]{6,16})\.([A-Za-z0-9_-]{43})\.([cp])\.([1-9][0-9]{0,11})\.(.+)\.([A-Za-z0-9_-]{86})$/s.exec(s);
	if (!m || enc.encode(s).length > MAX_CERT_BYTES) return null;
	const [, keyId, pub, tier, exp, character, sig] = m;
	if (!validCharacter(character) || b64urlEncode(b64urlDecode(pub)) !== pub || b64urlEncode(b64urlDecode(sig)) !== sig) return null;
	return { keyId, publicHex: bytesToHex(b64urlDecode(pub)), tier, exp: Number(exp), character, sig, payload: s.slice(0, s.length - sig.length - 1) };
}

// The certificate when the key `publicHex` (the backend's, or the council authority's) signed
// it, else null.
export async function verifyCertificate(publicHex, text) {
	const c = typeof text === 'string' ? parseCertificate(text) : text;
	if (!c || !(await ed25519Verify(publicHex, b64urlDecode(c.sig), enc.encode(c.payload)))) return null;
	return c;
}

// The council authority's public keys (LINK_CA_PUBLIC: one, or two while it changes).
export function councilAuthorityKeys(env) {
	return String((env && env.LINK_CA_PUBLIC) || '')
		.split(/[\s,]+/)
		.map((k) => k.toLowerCase())
		.filter((k) => PUBLIC_HEX_RE.test(k));
}

// The High Councillors' characters you accept from the council authority (LINK_COUNCIL_CHARACTERS:
// "Name-Realm" as the game writes it, comma-separated), as a Set. Closed by default (Konig's review):
// left out or empty, the Set is empty and no certificate of the authority counts. Keys you register
// yourself (keys) are yours already: the list does not apply to them.
export function councilCharacters(env) {
	const list = env ? env.LINK_COUNCIL_CHARACTERS : undefined;
	return new Set(
		String(list ?? '')
			.split(/[,\n]/)
			.map((c) => c.trim())
			.filter((c) => c !== ''),
	);
}

// The id of a key the council authority certifies: the first 12 hex of SHA-256 of its 32 bytes.
export async function councilKeyId(publicHex) {
	return bytesToHex(new Uint8Array(await crypto.subtle.digest('SHA-256', hexToBytes(publicHex)))).slice(0, 12);
}

// A parsed certificate the council authority signed for a High Councillor's key, else null.
export async function councilCertificate(env, c) {
	if (!c || c.tier !== 'c' || c.keyId !== (await councilKeyId(c.publicHex))) return null;
	for (const pk of councilAuthorityKeys(env)) {
		if (await verifyCertificate(pk, c)) return c;
	}
	return null;
}

// Your key tool: register a confirmer's public key for one character, get its certificate (a
// player key's once it counts: certFrom), renew it, or revoke a key (a High Councillor's key the
// council authority certified too: its id goes on the revocation list, seen here or not), or every
// key of a character (a councillor off the signed list: every council authority certificate for
// that character signed until now, and its registered keys). The seed never comes here: it stays
// with the confirmer.
//   {"key_id", "public_key", "owner_discord_id", "owner_username", "character", "kind", "bootstrap", "days", "replace"}
//   {"key_id", "renew": true, "days"}
//   {"key_id", "revoke": true}
//   {"character", "revoke": true}
// { ok: true, status: 'ok', ... } or { ok: false, status: 'error', reason, message } (httpStatus).
export async function manageKeys(env, body, t = now()) {
	const DB = database(env);
	const fail = (reason, message, extra = {}) => failure(reason, message, extra);
	if (body && typeof body === 'object' && body.revoke === true && body.key_id === undefined && body.character !== undefined) {
		return revokeCharacter(env, body.character, t);
	}
	if (!body || typeof body !== 'object' || typeof body.key_id !== 'string' || !KEYID_RE.test(body.key_id)) return fail('format', 'key_id: 6 to 16 of a-z and 0-9.');
	const keyId = body.key_id;
	if (body.days !== undefined && (!Number.isInteger(body.days) || body.days < 1 || body.days > LINK.CERT_DAYS_MAX)) {
		return fail('format', `days: a whole number from 1 to ${LINK.CERT_DAYS_MAX}.`);
	}
	const certExp = (kind) => t + (body.days !== undefined ? body.days : kind === 'p' ? LINK.CERT_DAYS_PLAYER : LINK.CERT_DAYS) * 86400;
	const existing = await DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(keyId).first();

	if (body.revoke === true) {
		if (!existing) {
			// A councillor's key the council authority certified (never registered here): on the
			// revocation list at once, whether a link has used it yet or not.
			if (!CA_KEYID_RE.test(keyId)) return fail('unknown-key', 'No such key.');
			await DB.prepare('INSERT OR IGNORE INTO revoked_keys (key_id, revoked_at) VALUES (?, ?)').bind(keyId, t).run();
			const known = await DB.prepare('SELECT character FROM council_keys WHERE key_id = ?').bind(keyId).first();
			return { ok: true, status: 'ok', key_id: keyId, revoked: true, council: true, character: known ? known.character : null };
		}
		await DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE key_id = ? AND revoked = 0').bind(t, keyId).run();
		return { ok: true, status: 'ok', key_id: keyId, revoked: true };
	}
	if (body.renew === true) {
		if (!existing) return fail('unknown-key', 'No such key.');
		if (existing.revoked) return fail('revoked', 'This key is revoked: make a new one.');
		if (existing.replaced_at !== null && existing.replaced_at !== undefined) return fail('replaced', 'This key was replaced by a newer one of the same account: certify that one.');
		const from = certFrom(existing);
		if (t < from) return fail('too-early', `This player key counts from ${when(from)}: ask for its certificate then.`, { cert_from: from });
		const exp = certExp(existing.kind);
		const cert = await makeCertificate(env, keyId, existing.public_key, existing.kind, exp, existing.character);
		const first = existing.cert_exp === null || existing.cert_exp === undefined;
		// A key's first certificate replaces the older key of its owner (a rotation).
		const older = first ? await activeKeys(env, existing.owner_discord_id, keyId) : [];
		await DB.batch([
			...older.map((k) => DB.prepare('UPDATE keys SET replaced_at = ? WHERE key_id = ?').bind(t, k.key_id)),
			DB.prepare('UPDATE keys SET cert_exp = ? WHERE key_id = ?').bind(exp, keyId),
		]);
		return keyAnswer(existing, cert, exp, replacedId(older));
	}

	const pub = typeof body.public_key === 'string' ? publicKeyHex(body.public_key) : null;
	const owner = String(body.owner_discord_id || '');
	const username = body.owner_username === undefined || body.owner_username === null ? null : String(body.owner_username);
	const kind = body.kind;
	const bootstrap = body.bootstrap === true ? 1 : 0;
	const character = typeof body.character === 'string' ? body.character : '';
	if (CA_KEYID_RE.test(keyId)) return fail('format', 'key_id: 12 hex digits name the council authority\'s keys: pick another id.');
	if (!pub) return fail('format', 'public_key: 64 hex digits (or 43 of base64url).');
	if (!DISCORD_ID_RE.test(owner)) return fail('format', "owner_discord_id: the confirmer's Discord id.");
	if (username !== null && !USERNAME_RE.test(username)) return fail('format', 'owner_username: a Discord username.');
	if (!validCharacter(character)) return fail('format', 'character: the one character that confirms with this key, "Name-Realm" as the game writes it.');
	if (kind !== 'c' && kind !== 'p') return fail('format', 'kind: "c" (a High Councillor) or "p" (a drawn player).');
	if (bootstrap && kind !== 'c') return fail('format', 'Only a councillor key can be a bootstrap key.');
	if (existing) return fail('key-id-used', 'This key id exists already: ids are never reused.');
	if (await DB.prepare('SELECT 1 AS x FROM keys WHERE public_key = ?').bind(pub).first()) return fail('public-key-used', 'This public key is registered already.');
	// The character confirms for its owner: one of the owner's linked characters (a bootstrap
	// councillor key excepted: at launch nobody has linked one yet).
	if (!bootstrap && !(await DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(character, owner).first())) {
		return fail('character-not-linked', `${character} is not a linked character of this Discord account: a key confirms from one of its owner's linked characters.`);
	}
	const mine = await activeKeys(env, owner, keyId);
	if (mine.length && body.replace !== true) {
		return fail('owner-has-key', `This account's key is ${replacedId(mine)}: send "replace": true to rotate it.`);
	}
	const key = { key_id: keyId, public_key: pub, owner_discord_id: owner, character, kind, created: t, cert_exp: null };
	const ready = t >= certFrom(key);
	const exp = ready ? certExp(kind) : null;
	const cert = ready ? await makeCertificate(env, keyId, pub, kind, exp, character) : null;
	// Rotating: the older key is replaced when the new one gets its certificate (a councillor's at
	// once, a player's once it counts): until then the confirmer has only the old one in game, and
	// it keeps counting. A replaced key leaves the draw and still checks the proofs it signed until
	// you revoke it, once the confirmer typed the new key and certificate in game. A new key that
	// never got its certificate is replaced at once.
	const older = ready ? mine : mine.filter((k) => k.cert_exp === null);
	await DB.batch([
		...older.map((k) => DB.prepare('UPDATE keys SET replaced_at = ? WHERE key_id = ?').bind(t, k.key_id)),
		DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, character, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(keyId, pub, owner, username, character, kind, bootstrap, t, exp),
	]);
	return keyAnswer(key, cert, exp, ready ? replacedId(older) : null);
}

// The same, one thing each.
export function registerKey(env, key, t) {
	const { renew, revoke, ...body } = key || {};
	return manageKeys(env, body, t);
}

export function renewKey(env, keyId, days, t) {
	return manageKeys(env, days === undefined ? { key_id: keyId, renew: true } : { key_id: keyId, renew: true, days }, t);
}

export function revokeKey(env, keyId, t) {
	return manageKeys(env, { key_id: keyId, revoke: true }, t);
}

// Every key of a character, at once: the council authority's certificates for it signed until now
// (whatever key they name, seen here or not: the ones a councillor rotated away included) stop
// counting, and so do the keys registered for it. A certificate the authority signs for it later
// counts again (a councillor back on the list, after /oly discord key new).
export async function revokeCharacter(env, character, t = now()) {
	const DB = database(env);
	if (typeof character !== 'string' || !validCharacter(character)) return failure('format', 'character: "Name-Realm" as the game writes it.');
	const registered = (await DB.prepare('SELECT key_id FROM keys WHERE character = ? AND revoked = 0').bind(character).all()).results || [];
	await DB.batch([
		DB.prepare('INSERT INTO revoked_characters (character, revoked_at) VALUES (?, ?) ON CONFLICT(character) DO UPDATE SET revoked_at = excluded.revoked_at').bind(character, t),
		DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE character = ? AND revoked = 0').bind(t, character),
	]);
	const council = (await DB.prepare('SELECT key_id FROM council_keys WHERE character = ? ORDER BY first_seen').bind(character).all()).results || [];
	return { ok: true, status: 'ok', character, revoked: true, keys: registered.map((k) => k.key_id), council_keys: council.map((k) => k.key_id) };
}

// POST <your keys route>: the admin token, then manageKeys.
export async function handleKeys(request, env) {
	if (!(await adminAuthorized(request, env))) return respond(failure('auth', 'Wrong admin token.'));
	return respond(await manageKeys(env, await readJson(request, 4 * 1024)));
}

// The owner's keys neither revoked nor replaced, but `except`: the certified one first.
async function activeKeys(env, owner, except) {
	const rows = (await database(env).prepare('SELECT key_id, cert_exp FROM keys WHERE owner_discord_id = ? AND key_id <> ? AND revoked = 0 AND replaced_at IS NULL').bind(owner, except).all()).results || [];
	return rows.sort((a, b) => (a.cert_exp === null) - (b.cert_exp === null));
}

function replacedId(keys) {
	return keys.length ? keys[0].key_id : null;
}

function keyAnswer(key, cert, certExp, replaced) {
	const from = certFrom(key);
	const answer = {
		ok: true,
		status: 'ok',
		key_id: key.key_id,
		kind: key.kind,
		character: key.character,
		public_key: key.public_key,
		cert,
		cert_exp: certExp,
		cert_from: from,
		command: cert ? `/oly discord cert ${cert}` : null,
		replaced,
	};
	if (!cert) {
		answer.message = `A player key gets its certificate once it counts: from ${when(from)}, send {"key_id": "${key.key_id}", "renew": true} and give the confirmer both lines.`;
	}
	return answer;
}

// A time for people, rounded up to the minute: "2027-01-31 18:05 UTC".
function when(t) {
	return `${new Date(Math.ceil(t / 60) * 60000).toISOString().slice(0, 16).replace('T', ' ')} UTC`;
}

function publicKeyHex(s) {
	const t = s.trim();
	if (PUBLIC_HEX_RE.test(t.toLowerCase())) return t.toLowerCase();
	if (PUBLIC_B64_RE.test(t) && b64urlEncode(b64urlDecode(t)) === t) return bytesToHex(b64urlDecode(t));
	return null;
}

// ---------------------------------------------------------------------------
// People

// Everything kept about one Discord account, gone: its linked characters, its codes and its lines
// in the audit trail; the confirmer keys it owns are revoked (their rows stay, with no username,
// so an id is never used twice). Take its role away yourself. { ok, status, discord_id,
// characters, keys }. `python3 scripts/link-keys.py forget <id>` prints the same as SQL.
export async function forgetUser(env, discordId, t = now()) {
	const id = String(discordId);
	if (!DISCORD_ID_RE.test(id)) return failure('format', 'A Discord id: digits only.');
	const DB = database(env);
	const characters = await charactersOf(env, id);
	const keys = (await DB.prepare('SELECT key_id FROM keys WHERE owner_discord_id = ? AND revoked = 0').bind(id).all()).results || [];
	await DB.batch([
		DB.prepare('DELETE FROM members WHERE discord_id = ?').bind(id),
		DB.prepare('DELETE FROM codes WHERE discord_id = ?').bind(id),
		DB.prepare('DELETE FROM inbox_uploads WHERE discord_id = ?').bind(id),
		DB.prepare('UPDATE keys SET revoked = 1, revoked_at = COALESCE(revoked_at, ?), owner_username = NULL WHERE owner_discord_id = ?').bind(t, id),
	]);
	return { ok: true, status: 'ok', discord_id: id, characters, keys: keys.map((k) => k.key_id) };
}

// ---------------------------------------------------------------------------
// Crypto (WebCrypto Ed25519: Workers and Node 20+)

let backendKey = null;

async function backendSign(env, payload) {
	const id = `${env.LINK_BACKEND_SEED}.${env.LINK_BACKEND_PUBLIC}`;
	if (!backendKey || backendKey.id !== id) {
		const x = b64urlEncode(hexToBytes(env.LINK_BACKEND_PUBLIC));
		const jwk = { kty: 'OKP', crv: 'Ed25519', d: env.LINK_BACKEND_SEED, x, ext: false };
		const key = await crypto.subtle.importKey('jwk', jwk, { name: 'Ed25519' }, false, ['sign']);
		// A seed and a public key that do not belong together would sign codes nobody accepts.
		const probe = enc.encode('olympus-link self-check');
		const sig = new Uint8Array(await crypto.subtle.sign('Ed25519', key, probe));
		if (!(await ed25519Verify(env.LINK_BACKEND_PUBLIC, sig, probe))) throw new Error('LINK_BACKEND_SEED and LINK_BACKEND_PUBLIC do not match');
		backendKey = { id, key };
	}
	return b64urlEncode(new Uint8Array(await crypto.subtle.sign('Ed25519', backendKey.key, enc.encode(payload))));
}

export async function ed25519Verify(publicHex, sig, message) {
	if (typeof publicHex !== 'string' || !/^[0-9a-fA-F]{64}$/.test(publicHex) || sig.length !== 64) return false;
	try {
		const key = await crypto.subtle.importKey('raw', hexToBytes(publicHex), { name: 'Ed25519' }, false, ['verify']);
		return await crypto.subtle.verify('Ed25519', key, sig, message);
	} catch {
		return false;
	}
}

export async function sha256Hex(text) {
	return bytesToHex(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(text))));
}

// ---------------------------------------------------------------------------
// Small helpers

// The token after "Bearer " in the Authorization header ('' when there is none).
export function bearer(request) {
	return (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
}

// Two secrets compared in constant time (their SHA-256).
export async function sameSecret(given, expected) {
	if (typeof given !== 'string' || typeof expected !== 'string' || !given || !expected) return false;
	const [a, b] = await Promise.all([given, expected].map((s) => crypto.subtle.digest('SHA-256', enc.encode(s))));
	const x = new Uint8Array(a);
	const y = new Uint8Array(b);
	let diff = 0;
	for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
	return diff === 0;
}

// Your tools' requests: "Authorization: Bearer <LINK_ADMIN_TOKEN>" (32 characters at least).
export async function adminAuthorized(request, env) {
	if (!env.LINK_ADMIN_TOKEN || env.LINK_ADMIN_TOKEN.length < 32) return false;
	return sameSecret(bearer(request), env.LINK_ADMIN_TOKEN);
}

// The request's JSON body, or null (too big, or not JSON).
export async function readJson(request, limit) {
	const text = await request.text();
	if (text.length > limit) return null;
	try {
		return JSON.parse(text);
	} catch {
		return null;
	}
}

export function hexToBytes(hex) {
	const out = new Uint8Array(hex.length / 2);
	for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
	return out;
}

export function bytesToHex(bytes) {
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

export function b64urlEncode(bytes) {
	let out = '';
	for (let i = 0; i < bytes.length; i += 3) {
		const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
		const chars = i + 2 < bytes.length ? 4 : i + 1 < bytes.length ? 3 : 2;
		for (let j = 0; j < chars; j++) out += B64[(n >> (18 - 6 * j)) & 63];
	}
	return out;
}

export function b64urlDecode(s) {
	const out = new Uint8Array(Math.floor((s.length * 6) / 8));
	let bits = 0;
	let acc = 0;
	let o = 0;
	for (const c of s) {
		acc = ((acc << 6) | B64.indexOf(c)) & 0xffffff;
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			out[o++] = (acc >> bits) & 255;
		}
	}
	return out;
}
