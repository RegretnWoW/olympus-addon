// Olympus Link: the reference Cloudflare Worker (D1 + Discord). web/WORKER.md explains every
// part; the tests in web/test/worker.test.mjs run this exact file against the shared vectors.
//
// Bindings and settings (wrangler.toml / dashboard):
//   DB                   D1 database with web/worker/schema.sql
//   LINK_BACKEND_SEED    secret: the backend's Ed25519 seed, base64url (scripts/link-keys.py backend)
//   LINK_BACKEND_PUBLIC  var: its public key, 64 hex (the same one is in the addon's ns.LINK_BACKEND_KEYS)
//   LINK_MODE            var: "c" councillors only (launch), "a" councillors or three drawn players
//   LINK_ORIGIN          var: the page's origin, e.g. "https://example.org" (checked on the page's POSTs)
//   LINK_ADMIN_TOKEN     secret: bearer token of the watcher tool (/inbox) and of a gateway bot (/bot-code)
//   DISCORD_BOT_TOKEN    secret: the bot that gives the role (Manage Roles, above ROLE_ID)
//   DISCORD_PUBLIC_KEY   var: the application's public key, for the /link slash command over HTTP
//   GUILD_ID, ROLE_ID    vars: the Olympus server and the role linked members get
//
// Routes: GET /api/link/me, POST /api/link/code, POST /api/link/submit, POST /api/link/inbox,
// POST /api/link/bot-code, POST /api/discord/interactions. Anything else returns null from
// handleLink, so it can sit in front of an existing Worker's router.

export const LINK = {
	TOKEN_LIFE: 24 * 3600, // a code works for a day...
	REUSE_LEFT: 12 * 3600, // ...and is handed out again while it has this long left
	CODES_PER_DAY: 3,
	DELIVERY_GRACE: 7 * 24 * 3600, // the addon holds a finished link 7 days for the watcher
	CLOCK_SKEW: 300, // game server clock vs ours
	WINDOW: 300, // three player proofs within 5 minutes of each other
	PLAYERS_NEEDED: 3,
	KEY_MIN_AGE: 7 * 24 * 3600,
	ACCOUNT_MIN_AGE: 30 * 24 * 3600,
	SUBMITS_PER_HOUR: 10,
	MAX_BUNDLES: 500,
};

const R_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const R_RE = /^[0-9A-HJKMNP-TV-Z]{10}$/;
const USERNAME_RE = /^[a-z0-9_.]{2,32}$/;
const DISCORD_ID_RE = /^[0-9]{5,25}$/;
const KEYID_RE = /^[a-z0-9]{6,16}$/;
const NONCE_RE = /^[0-9a-f]{16}$/;
const ISSUED_RE = /^[1-9][0-9]{0,11}$/;
const SIG_RE = /^[A-Za-z0-9_-]{86}$/;
const FORBIDDEN = /[|~;,\u0000-\u001f\u007f]/;
const MAX_PROOFS = 4;
const MAX_BUNDLE_BYTES = 1600;

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
		const result =
			parsed.ok && typeof entry.R === 'string' && entry.R !== parsed.bundle.R
				? reject('format', 'The inbox key does not match the link.', parsed.bundle.R)
				: await acceptBundle(env, text, { t });
		await logUpload(env, 'watcher', text, result, {
			from: typeof entry.from === 'string' ? entry.from.slice(0, 100) : null,
			received: Number.isFinite(entry.t) ? Math.floor(entry.t) : null,
			uploaded: t,
		});
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
	for (let attempt = 0; attempt < 5; attempt++) {
		const R = randomR();
		const payload = `OLC1.${R}.${username}.${exp}.${mode}`;
		const token = `${payload}.${await backendSign(env, payload)}`;
		try {
			await env.DB.prepare('INSERT INTO codes (r, discord_id, username, mode, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(R, id, username, mode, t, exp, token, source)
				.run();
			return { token, exp, mode, R };
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
		`It works once, for your account only, for the next ${hours} h. The confirmations happen in game; your role arrives when the link reaches the bot.`,
	].join('\n');
}

function codeError(reason) {
	if (reason === 'limit') return 'You already got 3 codes today: use the last one, or try again tomorrow.';
	if (reason === 'username') return 'Your Discord username cannot be used in a code. Change it to the new style (lowercase, no #1234) and try again.';
	return 'Sign in with Discord first.';
}

// ---------------------------------------------------------------------------
// Bundles

// What the addon's Link.Parse reads (Olympus/Link.lua; the page's web/public/core.js reads the
// same). Whether the proofs count is acceptBundle's call: a key or owner is counted once.
export function parseBundle(text) {
	if (typeof text !== 'string' || !text.startsWith('OLB4~')) return { ok: false, error: 'prefix' };
	if (enc.encode(text).length > MAX_BUNDLE_BYTES) return { ok: false, error: 'size' };
	const f = text.split('~');
	if (f.length !== 7) return { ok: false, error: 'fields' };
	const [, requester, guild, faction, nonce, R, proofText] = f;
	if (!validCharacter(requester)) return { ok: false, error: 'requester' };
	if (!field(guild, 40)) return { ok: false, error: 'guild' };
	if (faction !== 'Alliance' && faction !== 'Horde') return { ok: false, error: 'faction' };
	if (!NONCE_RE.test(nonce)) return { ok: false, error: 'nonce' };
	if (!R_RE.test(R)) return { ok: false, error: 'code' };
	const parts = proofText ? proofText.split(';') : [];
	if (parts.length < 1 || parts.length > MAX_PROOFS) return { ok: false, error: 'proofs' };
	const proofs = [];
	for (const part of parts) {
		const p = part.split(',');
		if (p.length !== 4) return { ok: false, error: 'proof' };
		const [issued, keyId, confirmer, sig] = p;
		if (!ISSUED_RE.test(issued) || !KEYID_RE.test(keyId) || !validCharacter(confirmer)) return { ok: false, error: 'proof' };
		if (!SIG_RE.test(sig) || b64urlEncode(b64urlDecode(sig)) !== sig) return { ok: false, error: 'sig' };
		proofs.push({ issued: Number(issued), keyId, confirmer, sig });
	}
	return { ok: true, bundle: { requester, guild, faction, nonce, R, proofs } };
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
	return ['OLY4', b.requester, b.guild, b.faction, b.nonce, b.R, p.issued, p.keyId, p.confirmer].join('~');
}

// The whole check. Returns { status: 'linked' | 'rejected', reason, message, R, characters }.
// opts.userId: the signed-in user, who must own the code (the page); absent for the watcher.
export async function acceptBundle(env, text, opts = {}) {
	const t = opts.t || now();
	const parsed = parseBundle(text);
	if (!parsed.ok) return reject('format', `This is not a complete Olympus link (${parsed.error}).`);
	const b = parsed.bundle;
	const code = await env.DB.prepare('SELECT * FROM codes WHERE r = ?').bind(b.R).first();
	if (!code) return reject('unknown-code', 'This link was made with a code the bot never issued.', b.R);
	if (opts.userId && code.discord_id !== opts.userId) return reject('other-user', 'This link was made with a code of another Discord account.', b.R);
	if (code.used !== null && code.used !== undefined) {
		const same = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ? AND r = ?').bind(b.requester, code.discord_id, b.R).first();
		if (same) return { status: 'linked', reason: 'already', message: `${b.requester} is already linked.`, R: b.R, characters: await charactersOf(env, code.discord_id) };
		return reject('code-used', 'This code was already used.', b.R);
	}
	if (t > code.exp + LINK.DELIVERY_GRACE) return reject('expired', 'This code expired more than 7 days ago.', b.R);

	const checks = [];
	for (const p of b.proofs) checks.push(await checkProof(env, b, p, code, t));
	const valid = checks.filter((c) => c.ok);
	const councillor = valid.find((c) => c.key.kind === 'c');
	let counted = councillor ? [councillor] : null;
	let why = checks.filter((c) => !c.ok).map((c) => `${c.proof.keyId}: ${c.why}`);
	if (!counted && code.mode === 'a') {
		const drawn = await drawnPlayers(env, b.R, valid.filter((c) => c.key.kind === 'p'), t);
		counted = drawn.picked;
		why = why.concat(drawn.why);
	}
	if (!counted) {
		const need = code.mode === 'a' ? `one councillor or ${LINK.PLAYERS_NEEDED} drawn players` : 'one councillor';
		return reject('not-enough', `Not enough valid confirmations (needs ${need}).${why.length ? ` ${why.join('; ')}.` : ''}`, b.R);
	}

	// Claim the code first (two deliveries of the same link may race), then the role.
	const claim = await env.DB.prepare('UPDATE codes SET used = ? WHERE r = ? AND used IS NULL').bind(t, b.R).run();
	if (!claim.meta || claim.meta.changes !== 1) return reject('code-used', 'This code was already used.', b.R);
	const role = await discordRole(env, 'PUT', code.discord_id);
	if (!role.ok) {
		await env.DB.prepare('UPDATE codes SET used = NULL WHERE r = ?').bind(b.R).run();
		if (role.reason === 'not-in-server') return reject('not-in-server', 'Join the Olympus Discord server first, then send the link again.', b.R);
		return { status: 'error', reason: 'discord', message: 'Discord did not take the role change: try again in a minute.', R: b.R };
	}
	const previous = await env.DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(b.requester).first();
	await env.DB.batch([
		...counted.map((c) => env.DB.prepare('INSERT OR IGNORE INTO used (r, key_id, t) VALUES (?, ?, ?)').bind(b.R, c.proof.keyId, t)),
		env.DB.prepare(
			'INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?) ' +
				'ON CONFLICT(character) DO UPDATE SET discord_id = excluded.discord_id, guild = excluded.guild, faction = excluded.faction, r = excluded.r, linked = excluded.linked',
		).bind(b.requester, code.discord_id, b.guild, b.faction, b.R, t),
	]);
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
	const key = await env.DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(p.keyId).first();
	if (!key) return bad('unknown key');
	if (key.revoked) return bad('revoked key');
	if (key.owner_discord_id === code.discord_id) return bad("the requester's own key");
	if (p.issued < code.created - LINK.CLOCK_SKEW || p.issued > code.exp) return bad('signed outside the code\'s life');
	if (p.issued > t + LINK.CLOCK_SKEW) return bad('signed in the future');
	if (!(await ed25519Verify(key.public_key, b64urlDecode(p.sig), enc.encode(signedMessage(b, p))))) return bad('bad signature');
	if (!(key.kind === 'c' && key.bootstrap)) {
		const mine = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(p.confirmer, key.owner_discord_id).first();
		if (!mine) return bad("the confirmer is not a linked character of the key's owner");
	}
	const own = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(b.requester, key.owner_discord_id).first();
	if (own) return bad("the requester is the key owner's own character");
	const reused = await env.DB.prepare('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?').bind(b.R, p.keyId).first();
	if (reused) return bad('already counted');
	return { ok: true, proof: p, key };
}

// Mode "a": three drawn players, all of them old enough, ranked < M in this code's draw, from
// three owners, signed within 5 minutes of each other.
async function drawnPlayers(env, R, valid, t) {
	const why = [];
	const old = [];
	for (const c of valid) {
		if (t - c.key.created < LINK.KEY_MIN_AGE) why.push(`${c.proof.keyId}: key younger than 7 days`);
		else if (t * 1000 - snowflakeTime(c.key.owner_discord_id) < LINK.ACCOUNT_MIN_AGE * 1000) why.push(`${c.proof.keyId}: Discord account younger than 30 days`);
		else old.push(c);
	}
	if (old.length < LINK.PLAYERS_NEEDED) return { picked: null, why };
	const rank = await drawRanks(env, R);
	const limit = drawLimit(rank.size);
	const inDraw = [];
	for (const c of old) {
		const r = rank.get(c.proof.keyId);
		if (r === undefined || r >= limit) why.push(`${c.proof.keyId}: not drawn for this code`);
		else inDraw.push(c);
	}
	inDraw.sort((a, b) => a.proof.issued - b.proof.issued);
	for (let i = 0; i < inDraw.length; i++) {
		const picked = [];
		const owners = new Set();
		for (let j = i; j < inDraw.length && inDraw[j].proof.issued - inDraw[i].proof.issued <= LINK.WINDOW; j++) {
			if (owners.has(inDraw[j].key.owner_discord_id)) continue;
			owners.add(inDraw[j].key.owner_discord_id);
			picked.push(inDraw[j]);
			if (picked.length === LINK.PLAYERS_NEEDED) return { picked, why };
		}
	}
	if (inDraw.length >= LINK.PLAYERS_NEEDED) why.push('the player confirmations are more than 5 minutes apart');
	return { picked: null, why };
}

// Every active player key's place in the draw of R: SHA-256(R .. "~" .. keyId), lowest first.
export async function drawRanks(env, R) {
	const rows = (await env.DB.prepare("SELECT key_id FROM keys WHERE kind = 'p' AND revoked = 0").all()).results || [];
	const hashed = await Promise.all(rows.map(async (row) => [row.key_id, await sha256Hex(`${R}~${row.key_id}`)]));
	hashed.sort((a, b) => (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0));
	return new Map(hashed.map(([id], i) => [id, i]));
}

export function drawLimit(activePlayerKeys) {
	return Math.max(20, Math.ceil(activePlayerKeys * 0.03));
}

export function snowflakeTime(id) {
	return Number((BigInt(id) >> 22n) + 1420070400000n);
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
// Discord

async function discordRole(env, method, discordId) {
	const res = await fetch(`https://discord.com/api/v10/guilds/${env.GUILD_ID}/members/${discordId}/roles/${env.ROLE_ID}`, {
		method,
		headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, 'X-Audit-Log-Reason': 'Olympus Link' },
	});
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
