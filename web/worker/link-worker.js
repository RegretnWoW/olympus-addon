// Olympus Link: the reference Cloudflare Worker (D1 + Discord). web/WORKER.md explains every
// part; the tests in web/test/worker.test.mjs run this exact file against the shared vectors.
//
// Bindings and settings (wrangler.toml / dashboard):
//   DB                   D1 database with web/worker/schema.sql
//   LINK_BACKEND_SEED    secret: the backend's Ed25519 seed, base64url (scripts/link-keys.py backend)
//   LINK_BACKEND_PUBLIC  var: its public key, 64 hex (the same one is in the addon's ns.LINK_BACKEND_KEYS)
//   LINK_CA_PUBLIC       var: the council authority's public key, 64 hex (scripts/link-keys.py ca; the same
//                        one is in the addon's ns.LINK_CA_KEYS; two, comma-separated, while it changes):
//                        the author's client certifies High Councillors' keys with it, and this Worker
//                        takes those keys without registering them
//   LINK_MODE            var: "c" councillors only (launch), "a" councillors or three drawn players
//   LINK_GUILD_POLICY    var: "verified" (the default): a link needs a confirmer who checked the
//                        guild in game (its roster or a recent /who); "claimed": the guild is taken as named
//   LINK_ORIGIN          var: the page's origin, e.g. "https://example.org" (checked on the page's POSTs)
//   LINK_ADMIN_TOKEN     secret: bearer token of your tools: the watcher inbox (/inbox), a gateway
//                        bot (/bot-code) and the confirmer keys (/keys)
//   DISCORD_BOT_TOKEN    secret: the bot that gives the role (Manage Roles, above ROLE_ID)
//   DISCORD_PUBLIC_KEY   var: the application's public key, for the /link slash command over HTTP
//   GUILD_ID, ROLE_ID    vars: the Olympus server and the role linked members get
//
// Routes: GET /api/link/me, POST /api/link/code, POST /api/link/submit, POST /api/link/inbox,
// POST /api/link/bot-code, POST /api/link/keys, POST /api/discord/interactions. Anything else
// returns null from handleLink, so it can sit in front of an existing Worker's router.

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
};

const R_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const R_RE = /^[0-9A-HJKMNP-TV-Z]{10}$/;
const USERNAME_RE = /^[a-z0-9_.]{2,32}$/;
const DISCORD_ID_RE = /^[0-9]{5,25}$/;
const KEYID_RE = /^[a-z0-9]{6,16}$/;
const NONCE_RE = /^[0-9a-f]{16}$/;
const TAG_RE = /^[0-9a-f]{16}$/;
const DRAW_RE = /^[0-9a-f]{8}$/;
const ISSUED_RE = /^[1-9][0-9]{0,11}$/;
const SIG_RE = /^[A-Za-z0-9_-]{86}$/;
const PUBLIC_HEX_RE = /^[0-9a-f]{64}$/;
const PUBLIC_B64_RE = /^[A-Za-z0-9_-]{43}$/;
const FORBIDDEN = /[|~;,\u0000-\u001f\u007f]/;
const GV_RE = /^[rwc]$/; // how a confirmer checked the guild: r its own roster, w a recent /who, c claimed only
const CHECKED = (gv) => gv === 'r' || gv === 'w';
const CA_KEYID_RE = /^[0-9a-f]{12}$/; // a council authority's key: the first 12 hex of SHA-256 of the key
const MAX_PROOFS = 4;
const MAX_BUNDLE_BYTES = 2400; // four proofs, each with its certificate (the addon's Link.MAX_BUNDLE)
const MAX_CERT_BYTES = 240; // a certificate fits one chat line: DV~1~<certificate> (the addon's Link.MAX_CERT)
const NO_DRAW = '00000000'; // T of a mode "c" code: no player key is drawn
const ALL_DRAWN = 'ffffffff'; // T when there are M player keys or fewer

const enc = new TextEncoder();
const now = () => Math.floor(Date.now() / 1000);

// ---------------------------------------------------------------------------
// Entry points

export default {
	async fetch(request, env, ctx) {
		return (await handleLink(request, env, ctx)) || new Response('Not found', { status: 404 });
	},
};

// ADAPT: the signed-in Discord user of this request, from YOUR login (the one your site
// already has), as { id, username, global_name, avatar } - the fields of Discord's
// GET /users/@me - or null when nobody is signed in. See web/WORKER.md, "Your login".
export async function sessionUser(request, env) {
	throw new Error('Olympus Link: connect sessionUser() to your Discord login (web/WORKER.md, "Your login")');
}

export async function handleLink(request, env, ctx, { getUser = sessionUser } = {}) {
	const url = new URL(request.url);
	const route = `${request.method} ${url.pathname.replace(/\/+$/, '')}`;
	try {
		switch (route) {
			case 'GET /api/link/me':
				return await routeMe(request, env, getUser);
			case 'POST /api/link/code':
				return await routeCode(request, env, getUser);
			case 'POST /api/link/submit':
				return await routeSubmit(request, env, getUser);
			case 'POST /api/link/inbox':
				return await routeInbox(request, env);
			case 'POST /api/link/bot-code':
				return await routeBotCode(request, env);
			case 'POST /api/link/keys':
				return await routeKeys(request, env);
			case 'POST /api/discord/interactions':
				return await routeInteractions(request, env);
			default:
				return null;
		}
	} catch (err) {
		console.error('olympus-link', route, err && err.stack ? err.stack : err);
		return json({ status: 'error', reason: 'server', message: 'Something went wrong on our side.' }, 500);
	}
}

// ---------------------------------------------------------------------------
// Routes

async function routeMe(request, env, getUser) {
	const user = await getUser(request, env);
	if (!user) return json({ user: null }, 401);
	const { id, username, global_name = null, avatar = null } = user;
	return json({ user: { id, username, global_name, avatar } });
}

async function routeCode(request, env, getUser) {
	if (!sameOrigin(request, env)) return json({ status: 'error', reason: 'origin', message: 'Wrong origin.' }, 403);
	const user = await getUser(request, env);
	if (!user) return json({ status: 'error', reason: 'login', message: 'Sign in with Discord first.' }, 401);
	const r = await issueCode(env, user, 'site');
	if (r.error) return json({ status: 'error', reason: r.error, message: codeError(r.error) }, r.error === 'limit' ? 429 : 400);
	return json({ token: r.token, command: `/oly discord ${r.token}`, exp: r.exp, mode: r.mode });
}

async function routeSubmit(request, env, getUser) {
	if (!sameOrigin(request, env)) return json({ status: 'error', reason: 'origin', message: 'Wrong origin.' }, 403);
	const user = await getUser(request, env);
	if (!user) return json({ status: 'error', reason: 'login', message: 'Sign in with Discord first.' }, 401);
	const body = await readJson(request, 8 * 1024);
	if (!body || typeof body.bundle !== 'string') return json({ status: 'error', reason: 'format', message: 'No link in the request.' }, 400);
	const t = now();
	const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM inbox_uploads WHERE source = 'site' AND discord_id = ? AND uploaded > ?")
		.bind(String(user.id), t - 3600)
		.first();
	if (recent && recent.n >= LINK.SUBMITS_PER_HOUR) {
		return json({ status: 'error', reason: 'limit', message: 'Too many tries: wait a while and send it again.' }, 429);
	}
	const result = await acceptBundle(env, body.bundle.trim(), { userId: String(user.id), t });
	await logUpload(env, 'site', body.bundle, result, { discordId: String(user.id), uploaded: t });
	return json(result);
}

// The watcher tool: many bundles at once, from a High Councillor's inbox. The Discord user
// comes from each code (codes.discord_id).
async function routeInbox(request, env) {
	if (!(await adminAuthorized(request, env))) return json({ status: 'error', reason: 'auth' }, 401);
	const body = await readJson(request, 2 * 1024 * 1024);
	const list = body && Array.isArray(body.bundles) ? body.bundles : null;
	if (!list || list.length > LINK.MAX_BUNDLES) return json({ status: 'error', reason: 'format', message: `Send {"bundles": [...]} with at most ${LINK.MAX_BUNDLES}.` }, 400);
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
					: await acceptBundle(env, text, { t });
		} catch (err) {
			// One link that fails on our side does not stop the others: this one is sent again later.
			console.error('olympus-link: inbox entry', err && err.stack ? err.stack : err);
			result = { status: 'error', reason: 'server', message: 'Something went wrong on our side: send it again.', R: parsed.ok ? parsed.bundle.R : null };
		}
		try {
			await logUpload(env, 'watcher', text, result, {
				from: typeof entry.from === 'string' ? entry.from.slice(0, 100) : null,
				received: Number.isFinite(entry.t) ? Math.floor(entry.t) : null,
				uploaded: t,
			});
		} catch (err) {
			console.error('olympus-link: inbox log', err && err.stack ? err.stack : err);
		}
		results.push({ R: result.R || (typeof entry.R === 'string' ? entry.R : null), status: result.status, reason: result.reason, message: result.message });
	}
	return json({ results });
}

// For a bot that runs on the gateway (discord.js, discord.py...) instead of HTTP interactions:
// it asks the Worker for the member's code and replies with it, ephemeral.
async function routeBotCode(request, env) {
	if (!(await adminAuthorized(request, env))) return json({ status: 'error', reason: 'auth' }, 401);
	const body = await readJson(request, 4 * 1024);
	if (!body || typeof body.id !== 'string' || typeof body.username !== 'string') return json({ status: 'error', reason: 'format' }, 400);
	const r = await issueCode(env, { id: body.id, username: body.username }, 'discord');
	if (r.error) return json({ status: 'error', reason: r.error, message: codeError(r.error) }, r.error === 'limit' ? 429 : 400);
	return json({ token: r.token, command: `/oly discord ${r.token}`, exp: r.exp, mode: r.mode, reply: codeReply(r) });
}

// The /link slash command over HTTP interactions (Discord signs every request).
async function routeInteractions(request, env) {
	const sig = request.headers.get('X-Signature-Ed25519') || '';
	const ts = request.headers.get('X-Signature-Timestamp') || '';
	const body = await request.text();
	if (!/^[0-9a-fA-F]{128}$/.test(sig) || !/^[0-9]{1,20}$/.test(ts)) return new Response('Bad request signature', { status: 401 });
	if (!(await ed25519Verify(env.DISCORD_PUBLIC_KEY, hexToBytes(sig), enc.encode(ts + body)))) {
		return new Response('Bad request signature', { status: 401 });
	}
	const i = JSON.parse(body);
	if (i.type === 1) return json({ type: 1 }); // PING
	if (i.type === 2 && i.data && i.data.name === 'link') {
		const user = (i.member && i.member.user) || i.user;
		const r = user ? await issueCode(env, user, 'discord') : { error: 'login' };
		return json({ type: 4, data: { flags: 64, content: r.error ? codeError(r.error) : codeReply(r) } });
	}
	return json({ type: 4, data: { flags: 64, content: 'Unknown command.' } });
}

// ---------------------------------------------------------------------------
// Codes

export async function issueCode(env, user, source) {
	const id = String(user && user.id);
	const username = String(user && user.username);
	if (!DISCORD_ID_RE.test(id)) return { error: 'login' };
	if (!USERNAME_RE.test(username)) return { error: 'username' };
	const t = now();
	const open = await env.DB.prepare('SELECT token, exp, mode FROM codes WHERE discord_id = ? AND username = ? AND used IS NULL AND exp > ? ORDER BY created DESC LIMIT 1')
		.bind(id, username, t + LINK.REUSE_LEFT)
		.first();
	if (open) return { token: open.token, exp: open.exp, mode: open.mode };
	const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM codes WHERE discord_id = ? AND created > ?').bind(id, t - 86400).first();
	if (count && count.n >= LINK.CODES_PER_DAY) return { error: 'limit' };
	const mode = env.LINK_MODE === 'a' ? 'a' : 'c';
	const exp = t + LINK.TOKEN_LIFE;
	const pool = mode === 'a' ? await drawPool(env, t) : null;
	for (let attempt = 0; attempt < 5; attempt++) {
		const R = randomR();
		const T = pool ? await thresholdOf(R, pool) : NO_DRAW;
		const payload = `OLC2.${R}.${username}.${exp}.${mode}.${T}`;
		const token = `${payload}.${await backendSign(env, payload)}`;
		try {
			await env.DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(R, id, username, mode, T, t, exp, token, source)
				.run();
			return { token, exp, mode, R, T };
		} catch (err) {
			if (!/unique|constraint/i.test(String(err && err.message))) throw err; // an R taken: draw again
		}
	}
	throw new Error('could not draw a free code');
}

function randomR() {
	const bytes = crypto.getRandomValues(new Uint8Array(10));
	return Array.from(bytes, (b) => R_ALPHABET[b & 31]).join(''); // 256 = 8 * 32: no bias
}

function codeReply(r) {
	const hours = Math.max(1, Math.round((r.exp - now()) / 3600));
	return [
		'Your Olympus Link code. Paste this line in the WoW chat, press Enter, then click Accept:',
		'```',
		`/oly discord ${r.token}`,
		'```',
		`It works once, for your account only, for the next ${hours} h. Keep it to yourself: not on stream, not in a screenshot, and neither the game's Olympus Link window. The confirmations happen in game; your role arrives when the link reaches the bot.`,
	].join('\n');
}

function codeError(reason) {
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
		await env.DB.prepare("SELECT key_id, owner_discord_id, created FROM keys WHERE kind = 'p' AND revoked = 0 AND replaced_at IS NULL AND cert_exp > ?")
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
// Bundles

// What the addon's Link.Parse reads (Olympus/Link.lua; the page's web/public/core.js reads the
// same). Whether the proofs count is acceptBundle's call: a key or owner is counted once. Each
// proof carries its key's certificate for its confirmer: <public key>,<tier>,<cert exp>,<cert sig>.
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

// The whole check. Returns { status: 'linked' | 'rejected' | 'error', reason, message, R, characters }.
// opts.userId: the signed-in user, who must own the code (the page); absent for the watcher.
export async function acceptBundle(env, text, opts = {}) {
	const t = opts.t || now();
	const parsed = parseBundle(text);
	if (!parsed.ok) return reject('format', `This is not a complete Olympus link (${parsed.error}).`);
	const b = parsed.bundle;
	const code = await env.DB.prepare('SELECT * FROM codes WHERE r = ?').bind(b.R).first();
	if (!code) return reject('unknown-code', 'This link was made with a code the bot never issued.', b.R);
	if (opts.userId && code.discord_id !== opts.userId) return reject('other-user', 'This link was made with a code of another Discord account.', b.R);
	if (b.tag !== (await linkTag(tokenSig(code.token), b.requester))) {
		return reject('tag', 'This link was not made by the player who typed this code in the game.', b.R);
	}
	if (code.used !== null && code.used !== undefined) {
		const same = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ? AND r = ?').bind(b.requester, code.discord_id, b.R).first();
		if (same) return { status: 'linked', reason: 'already', message: `${b.requester} is already linked.`, R: b.R, characters: await charactersOf(env, code.discord_id) };
		return reject('code-used', 'This code was already used.', b.R);
	}
	if (t > code.exp + LINK.DELIVERY_GRACE) return reject('expired', 'This code expired more than 7 days ago.', b.R);

	const checks = [];
	for (const p of b.proofs) checks.push(await checkProof(env, b, p, code, t));
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
		return reject('not-enough', `Not enough valid confirmations (needs ${need}).${why.length ? ` ${why.join('; ')}.` : ''}`, b.R);
	}
	const checked = vouching.find((c) => CHECKED(c.proof.gv));
	const gv = checked ? checked.proof.gv : 'c';
	if (!checked && guildPolicy(env) === 'verified') {
		return reject('guild-unverified', `None of the confirmations checked ${b.guild} in game (a confirmer of that guild with its roster, or one who saw the player in it in a /who).`, b.R);
	}

	// Claim the code first (two deliveries of the same link may race), then the role. Anything
	// that fails after the claim releases it, so the same link works on the next try.
	const claim = await env.DB.prepare('UPDATE codes SET used = ? WHERE r = ? AND used IS NULL').bind(t, b.R).run();
	if (!claim.meta || claim.meta.changes !== 1) return reject('code-used', 'This code was already used.', b.R);
	const release = async () => {
		try {
			await env.DB.prepare('UPDATE codes SET used = NULL WHERE r = ? AND used = ?').bind(b.R, t).run();
		} catch (err) {
			console.error('olympus-link: could not release code', b.R, err && err.stack ? err.stack : err);
		}
	};
	const role = await discordRole(env, 'PUT', code.discord_id);
	if (!role.ok) {
		await release();
		if (role.reason === 'not-in-server') return reject('not-in-server', 'Join the Olympus Discord server first, then send the link again.', b.R);
		return { status: 'error', reason: 'discord', message: 'Discord did not take the role change: try again in a minute.', R: b.R };
	}
	let previous;
	try {
		previous = await env.DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(b.requester).first();
		await env.DB.batch([
			...counted.map((c) => env.DB.prepare('INSERT OR IGNORE INTO used (r, key_id, t) VALUES (?, ?, ?)').bind(b.R, c.proof.keyId, t)),
			env.DB.prepare(
				'INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?) ' +
					'ON CONFLICT(character) DO UPDATE SET discord_id = excluded.discord_id, guild = excluded.guild, gv = excluded.gv, faction = excluded.faction, r = excluded.r, linked = excluded.linked',
			).bind(b.requester, code.discord_id, b.guild, gv, b.faction, b.R, t),
		]);
	} catch (err) {
		console.error('olympus-link: could not record the link', b.R, err && err.stack ? err.stack : err);
		await release();
		return { status: 'error', reason: 'server', message: 'The link could not be recorded: send it again in a minute.', R: b.R };
	}
	if (previous && previous.discord_id !== code.discord_id) {
		const left = await env.DB.prepare('SELECT COUNT(*) AS n FROM members WHERE discord_id = ?').bind(previous.discord_id).first();
		if (!left || left.n === 0) await discordRole(env, 'DELETE', previous.discord_id); // the character moved away
	}
	return {
		status: 'linked',
		reason: 'linked',
		message: `${b.requester} is now linked to @${code.username}.`,
		R: b.R,
		characters: await charactersOf(env, code.discord_id),
	};
}

async function checkProof(env, b, p, code, t) {
	const bad = (why) => ({ ok: false, proof: p, why });
	const found = await proofKey(env, p, t);
	if (found.why) return bad(found.why);
	const key = found.key;
	if (key.owner_discord_id && key.owner_discord_id === code.discord_id) return bad("the requester's own key");
	if (p.issued < code.created - LINK.CLOCK_SKEW || p.issued > code.exp) return bad('signed outside the code\'s life');
	if (p.issued > t + LINK.CLOCK_SKEW) return bad('signed in the future');
	if (!(await ed25519Verify(key.public_key, b64urlDecode(p.sig), enc.encode(signedMessage(b, p))))) return bad('bad signature');
	if (!key.council && !(key.kind === 'c' && key.bootstrap)) {
		const mine = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(p.confirmer, key.owner_discord_id).first();
		if (!mine) return bad("the confirmer is not a linked character of the key's owner");
	}
	if (p.confirmer === b.requester) return bad('the confirmer is the requester');
	if (key.owner_discord_id) {
		const own = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(b.requester, key.owner_discord_id).first();
		if (own) return bad("the requester is the key owner's own character");
	}
	const reused = await env.DB.prepare('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?').bind(b.R, p.keyId).first();
	if (reused) return bad('already counted');
	return { ok: true, proof: p, key };
}

// The key a proof is checked with: { key } or { why }. A key registered here (keys) is D1's: the
// certificate the proof carries must name its public key, tier and character, and D1 says
// whether it is revoked. A key this Worker never registered counts only as a High Councillor's
// certified by the council authority (the author's client, LINK_CA_PUBLIC): the certificate the
// proof carries is then checked here (tier c, the key's id the first 12 hex of SHA-256 of it,
// valid when the proof was signed), the key is recorded for the character it names the first
// time it is seen (council_keys), and the revocation list (revoked_keys) can end it.
async function proofKey(env, p, t) {
	const cert = proofCertificate(p);
	if (!cert) return { why: 'a certificate that does not read' };
	const row = await env.DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(p.keyId).first();
	if (row) {
		if (row.revoked) return { why: 'revoked key' };
		if (row.public_key !== cert.publicHex || row.kind !== cert.tier || row.character !== cert.character) {
			return { why: "its certificate is not the one registered for this key (public key, tier and character)" };
		}
		return { key: row };
	}
	if (!CA_KEYID_RE.test(p.keyId)) return { why: 'unknown key' };
	if (await env.DB.prepare('SELECT 1 AS x FROM revoked_keys WHERE key_id = ?').bind(p.keyId).first()) return { why: 'revoked key' };
	if (!(await councilCertificate(env, cert))) return { why: 'unknown key (not certified by the council authority)' };
	if (p.issued >= cert.exp) return { why: 'signed after its certificate ended' };
	await env.DB.prepare('INSERT OR IGNORE INTO council_keys (key_id, public_key, character, cert_exp, first_seen) VALUES (?, ?, ?, ?, ?)')
		.bind(p.keyId, cert.publicHex, cert.character, cert.exp, t)
		.run();
	const known = await env.DB.prepare('SELECT * FROM council_keys WHERE key_id = ?').bind(p.keyId).first();
	if (!known || known.public_key !== cert.publicHex || known.character !== cert.character) return { why: 'a council key recorded for another character' };
	if (cert.exp > known.cert_exp) await env.DB.prepare('UPDATE council_keys SET cert_exp = ? WHERE key_id = ?').bind(cert.exp, p.keyId).run();
	// Its owner, when the councillor's character is linked: never confirms that account's codes or characters.
	const owner = await env.DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(cert.character).first();
	return { key: { key_id: p.keyId, public_key: cert.publicHex, kind: 'c', bootstrap: 1, council: true, character: cert.character, owner_discord_id: owner ? owner.discord_id : null } };
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

async function charactersOf(env, discordId) {
	const rows = (await env.DB.prepare('SELECT character FROM members WHERE discord_id = ? ORDER BY linked').bind(discordId).all()).results || [];
	return rows.map((r) => r.character);
}

function reject(reason, message, R) {
	return { status: 'rejected', reason, message, R: R || null };
}

async function logUpload(env, source, text, result, extra) {
	let b = null;
	const parsed = parseBundle(typeof text === 'string' ? text.trim() : '');
	if (parsed.ok) b = parsed.bundle;
	const code = b ? await env.DB.prepare('SELECT discord_id FROM codes WHERE r = ?').bind(b.R).first() : null;
	await env.DB.prepare(
		'INSERT INTO inbox_uploads (source, r, discord_id, requester, from_character, received, uploaded, status, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
	)
		.bind(source, b ? b.R : null, extra.discordId || (code && code.discord_id) || null, b ? b.requester : null, extra.from || null, extra.received || null, extra.uploaded, result.status, result.reason || null)
		.run();
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

// Your key tool (admin token): register a confirmer's public key for one character, get its
// certificate (a player key's once it counts: certFrom), renew it, or revoke a key (a High
// Councillor's key the council authority certified too: its id goes on the revocation list,
// seen here or not). The seed never comes here: it stays with the confirmer.
//   {"key_id", "public_key", "owner_discord_id", "owner_username", "character", "kind", "bootstrap", "days", "replace"}
//   {"key_id", "renew": true, "days"}
//   {"key_id", "revoke": true}
async function routeKeys(request, env) {
	if (!(await adminAuthorized(request, env))) return json({ status: 'error', reason: 'auth' }, 401);
	const body = await readJson(request, 4 * 1024);
	const t = now();
	const fail = (reason, message, status = 400, extra = {}) => json({ status: 'error', reason, message, ...extra }, status);
	if (!body || typeof body !== 'object' || typeof body.key_id !== 'string' || !KEYID_RE.test(body.key_id)) return fail('format', 'key_id: 6 to 16 of a-z and 0-9.');
	const keyId = body.key_id;
	if (body.days !== undefined && (!Number.isInteger(body.days) || body.days < 1 || body.days > LINK.CERT_DAYS_MAX)) {
		return fail('format', `days: a whole number from 1 to ${LINK.CERT_DAYS_MAX}.`);
	}
	const certExp = (kind) => t + (body.days !== undefined ? body.days : kind === 'p' ? LINK.CERT_DAYS_PLAYER : LINK.CERT_DAYS) * 86400;
	const existing = await env.DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(keyId).first();

	if (body.revoke === true) {
		if (!existing) {
			// A councillor's key the council authority certified (never registered here): on the
			// revocation list at once, whether a link has used it yet or not.
			if (!CA_KEYID_RE.test(keyId)) return fail('unknown-key', 'No such key.', 404);
			await env.DB.prepare('INSERT OR IGNORE INTO revoked_keys (key_id, revoked_at) VALUES (?, ?)').bind(keyId, t).run();
			const known = await env.DB.prepare('SELECT character FROM council_keys WHERE key_id = ?').bind(keyId).first();
			return json({ status: 'ok', key_id: keyId, revoked: true, council: true, character: known ? known.character : null });
		}
		await env.DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE key_id = ? AND revoked = 0').bind(t, keyId).run();
		return json({ status: 'ok', key_id: keyId, revoked: true });
	}
	if (body.renew === true) {
		if (!existing) return fail('unknown-key', 'No such key.', 404);
		if (existing.revoked) return fail('revoked', 'This key is revoked: make a new one.', 409);
		if (existing.replaced_at !== null && existing.replaced_at !== undefined) return fail('replaced', 'This key was replaced by a newer one of the same account: certify that one.', 409);
		const from = certFrom(existing);
		if (t < from) return fail('too-early', `This player key counts from ${when(from)}: ask for its certificate then.`, 409, { cert_from: from });
		const exp = certExp(existing.kind);
		const cert = await makeCertificate(env, keyId, existing.public_key, existing.kind, exp, existing.character);
		const first = existing.cert_exp === null || existing.cert_exp === undefined;
		// A key's first certificate replaces the older key of its owner (a rotation).
		const older = first ? await activeKeys(env, existing.owner_discord_id, keyId) : [];
		await env.DB.batch([
			...older.map((k) => env.DB.prepare('UPDATE keys SET replaced_at = ? WHERE key_id = ?').bind(t, k.key_id)),
			env.DB.prepare('UPDATE keys SET cert_exp = ? WHERE key_id = ?').bind(exp, keyId),
		]);
		return json(keyAnswer(existing, cert, exp, replacedId(older)));
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
	if (existing) return fail('key-id-used', 'This key id exists already: ids are never reused.', 409);
	if (await env.DB.prepare('SELECT 1 AS x FROM keys WHERE public_key = ?').bind(pub).first()) return fail('public-key-used', 'This public key is registered already.', 409);
	// The character confirms for its owner: one of the owner's linked characters (a bootstrap
	// councillor key excepted: at launch nobody has linked one yet).
	if (!bootstrap && !(await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(character, owner).first())) {
		return fail('character-not-linked', `${character} is not a linked character of this Discord account: a key confirms from one of its owner's linked characters.`, 409);
	}
	const mine = await activeKeys(env, owner, keyId);
	if (mine.length && body.replace !== true) {
		return fail('owner-has-key', `This account's key is ${replacedId(mine)}: send "replace": true to rotate it.`, 409);
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
	await env.DB.batch([
		...older.map((k) => env.DB.prepare('UPDATE keys SET replaced_at = ? WHERE key_id = ?').bind(t, k.key_id)),
		env.DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, character, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(keyId, pub, owner, username, character, kind, bootstrap, t, exp),
	]);
	return json(keyAnswer(key, cert, exp, ready ? replacedId(older) : null));
}

// The owner's keys neither revoked nor replaced, but `except`: the certified one first.
async function activeKeys(env, owner, except) {
	const rows = (await env.DB.prepare('SELECT key_id, cert_exp FROM keys WHERE owner_discord_id = ? AND key_id <> ? AND revoked = 0 AND replaced_at IS NULL').bind(owner, except).all()).results || [];
	return rows.sort((a, b) => (a.cert_exp === null) - (b.cert_exp === null));
}

function replacedId(keys) {
	return keys.length ? keys[0].key_id : null;
}

function keyAnswer(key, cert, certExp, replaced) {
	const from = certFrom(key);
	const answer = {
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
// Discord

// { ok } or { ok: false, reason }: never throws (a network error is Discord being down).
async function discordRole(env, method, discordId) {
	let res;
	try {
		res = await fetch(`https://discord.com/api/v10/guilds/${env.GUILD_ID}/members/${discordId}/roles/${env.ROLE_ID}`, {
			method,
			headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, 'X-Audit-Log-Reason': 'Olympus Link' },
		});
	} catch (err) {
		console.error('olympus-link: Discord role', method, 'fetch failed:', err && err.message ? err.message : err);
		return { ok: false, reason: 'discord' };
	}
	if (res.ok) return { ok: true };
	let code = 0;
	try {
		code = (await res.json()).code;
	} catch {}
	if (res.status === 404 && code === 10007) return { ok: false, reason: 'not-in-server' }; // Unknown Member
	console.error('olympus-link: Discord role', method, res.status, code);
	return { ok: false, reason: 'discord' };
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

async function sha256Hex(text) {
	return bytesToHex(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(text))));
}

// ---------------------------------------------------------------------------
// Small helpers

function json(data, status = 200) {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
	});
}

async function readJson(request, limit) {
	const text = await request.text();
	if (text.length > limit) return null;
	try {
		return JSON.parse(text);
	} catch {
		return null;
	}
}

// The page's POSTs carry the session cookie: only the page's own origin may send them.
function sameOrigin(request, env) {
	const origin = request.headers.get('Origin');
	return !!origin && origin === (env.LINK_ORIGIN || new URL(request.url).origin);
}

async function adminAuthorized(request, env) {
	const given = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
	if (!env.LINK_ADMIN_TOKEN || env.LINK_ADMIN_TOKEN.length < 32 || !given) return false;
	const [a, b] = await Promise.all([given, env.LINK_ADMIN_TOKEN].map((s) => crypto.subtle.digest('SHA-256', enc.encode(s))));
	const x = new Uint8Array(a);
	const y = new Uint8Array(b);
	let diff = 0;
	for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
	return diff === 0;
}

function hexToBytes(hex) {
	const out = new Uint8Array(hex.length / 2);
	for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
	return out;
}

function bytesToHex(bytes) {
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

function b64urlEncode(bytes) {
	let out = '';
	for (let i = 0; i < bytes.length; i += 3) {
		const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
		const chars = i + 2 < bytes.length ? 4 : i + 1 < bytes.length ? 3 : 2;
		for (let j = 0; j < chars; j++) out += B64[(n >> (18 - 6 * j)) & 63];
	}
	return out;
}

function b64urlDecode(s) {
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
