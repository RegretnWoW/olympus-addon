// Olympus Link: the reference Cloudflare Worker (D1 + Discord), complete, built on link-core.mjs
// (every check lives there). web/FERN.md is the short way into your own bot, web/WORKER.md
// explains every part; the tests in web/test run this exact file against the shared vectors.
//
// Bindings and settings (wrangler.toml / dashboard): link-core.mjs lists what it reads, and
//   DISCORD_BOT_TOKEN    secret: the bot that gives the role (Manage Roles, above ROLE_ID)
//   DISCORD_PUBLIC_KEY   var: the application's public key, for the /verify slash command over HTTP
//   GUILD_ID, ROLE_ID    vars: the Olympus server and the role linked members get
//
// Routes:
//   POST /api/link/proof             the page (static, on GitHub Pages): {"text", "discordToken"}, CORS
//   POST /api/link/inbox             your watcher's inbox (read-inbox.mjs --post), admin token
//   POST /api/link/keys              the confirmer keys, admin token
//   POST /api/link/bot-code          a gateway bot asking for a member's code, admin token
//   POST /api/discord/interactions   /verify over HTTP interactions (Discord signs every request)
//   GET /api/link/me, POST /api/link/code, POST /api/link/submit: only for a page served from
//   this Worker's own site behind your own login (sessionUser); the GitHub Pages page uses /proof.
// Anything else returns null from handleLink, so it can sit in front of an existing router.

import {
	acceptProof,
	codeError,
	failure,
	handleInbox,
	handleKeys,
	handleProof,
	issueCode,
	logProof,
	readJson,
	adminAuthorized,
	allowedOrigins,
	ed25519Verify,
	hexToBytes,
	tooManyProofs,
	respond,
} from './link-core.mjs';

export {
	LINK,
	PROOF_REASONS,
	issueCode,
	checkProof,
	acceptProof,
	acceptInbox,
	parseBundle,
	proofText,
	signedMessage,
	proofCertificate,
	linkTag,
	guildPolicy,
	drawPrefix,
	drawLimit,
	drawPool,
	thresholdOf,
	drawThreshold,
	snowflakeTime,
	certFrom,
	makeCertificate,
	parseCertificate,
	verifyCertificate,
	councilAuthorityKeys,
	councilKeyId,
	councilCertificate,
	manageKeys,
	ed25519Verify,
} from './link-core.mjs';

const enc = new TextEncoder();
const now = () => Math.floor(Date.now() / 1000);

// ---------------------------------------------------------------------------
// Entry points

export default {
	async fetch(request, env, ctx) {
		return (await handleLink(request, env, ctx)) || new Response('Not found', { status: 404 });
	},
};

// ADAPT (only for the same-site routes /me, /code and /submit): the signed-in Discord user of this
// request, from YOUR login, as { id, username, global_name, avatar } - the fields of Discord's
// GET /users/@me - or null when nobody is signed in. The GitHub Pages page never needs it: it sends
// the player's Discord token to /proof, which asks Discord (web/WORKER.md, "Who is sending").
export async function sessionUser(request, env) {
	throw new Error('Olympus Link: connect sessionUser() to your Discord login (web/WORKER.md, "Who is sending")');
}

// The role, given and taken by the bot (your promote() and demote() in the terms of handleProof).
export const giveRole = (env) => (discordId) => discordRole(env, 'PUT', discordId);
export const takeRole = (env) => (discordId) => discordRole(env, 'DELETE', discordId);

export async function handleLink(request, env, ctx, { getUser = sessionUser } = {}) {
	const url = new URL(request.url);
	const route = `${request.method} ${url.pathname.replace(/\/+$/, '')}`;
	const roles = { promote: giveRole(env), demote: takeRole(env) };
	try {
		switch (route) {
			case 'OPTIONS /api/link/proof':
			case 'POST /api/link/proof':
				return await handleProof(request, env, roles);
			case 'POST /api/link/inbox':
				return await handleInbox(request, env, roles);
			case 'POST /api/link/keys':
				return await handleKeys(request, env);
			case 'POST /api/link/bot-code':
				return await routeBotCode(request, env);
			case 'POST /api/discord/interactions':
				return await routeInteractions(request, env);
			case 'GET /api/link/me':
				return await routeMe(request, env, getUser);
			case 'POST /api/link/code':
				return await routeCode(request, env, getUser);
			case 'POST /api/link/submit':
				return await routeSubmit(request, env, getUser);
			default:
				return null;
		}
	} catch (err) {
		console.error('olympus-link', route, err && err.stack ? err.stack : err);
		return respond(failure('server', 'Something went wrong on our side.'), {}, 500);
	}
}

// acceptProof with this Worker's role: the old name, kept for the tests and tools that use it.
// opts.userId: the signed-in user, who must own the code (the page); absent for the watcher.
export function acceptBundle(env, text, opts = {}) {
	return acceptProof(env, text, { discordId: opts.userId, t: opts.t, promote: giveRole(env) });
}

// ---------------------------------------------------------------------------
// Routes

// For a gateway bot (discord.js, discord.py...) instead of HTTP interactions: it asks the Worker
// for the member's code and replies with it, ephemeral.
async function routeBotCode(request, env) {
	if (!(await adminAuthorized(request, env))) return respond(failure('auth', 'Wrong admin token.'));
	const body = await readJson(request, 4 * 1024);
	if (!body || typeof body.id !== 'string' || typeof body.username !== 'string') return respond(failure('format', 'Send {"id", "username"}.'));
	const r = await issueCode(env, { id: body.id, username: body.username }, 'discord');
	if (!r.ok) return respond(r, {}, r.reason === 'limit' ? 429 : 400);
	return respond({ token: r.token, command: r.command, exp: r.exp, mode: r.mode, reply: r.reply });
}

// /verify over HTTP interactions (Discord signs every request). /link is answered the same way.
async function routeInteractions(request, env) {
	const sig = request.headers.get('X-Signature-Ed25519') || '';
	const ts = request.headers.get('X-Signature-Timestamp') || '';
	const body = await request.text();
	if (!/^[0-9a-fA-F]{128}$/.test(sig) || !/^[0-9]{1,20}$/.test(ts)) return new Response('Bad request signature', { status: 401 });
	if (!(await ed25519Verify(env.DISCORD_PUBLIC_KEY, hexToBytes(sig), enc.encode(ts + body)))) {
		return new Response('Bad request signature', { status: 401 });
	}
	const i = JSON.parse(body);
	if (i.type === 1) return respond({ type: 1 }); // PING
	if (i.type === 2 && i.data && (i.data.name === 'verify' || i.data.name === 'link')) {
		const user = (i.member && i.member.user) || i.user;
		const r = user ? await issueCode(env, user, 'discord') : { reply: codeError('login') };
		return respond({ type: 4, data: { flags: 64, content: r.reply } });
	}
	return respond({ type: 4, data: { flags: 64, content: 'Unknown command.' } });
}

// The same-site variant: a page served by this Worker's own site, with your login's cookie.
async function routeMe(request, env, getUser) {
	const user = await getUser(request, env);
	if (!user) return respond({ user: null }, {}, 401);
	const { id, username, global_name = null, avatar = null } = user;
	return respond({ user: { id, username, global_name, avatar } });
}

async function routeCode(request, env, getUser) {
	if (!sameOrigin(request, env)) return respond(failure('origin', 'Wrong origin.'));
	const user = await getUser(request, env);
	if (!user) return respond(failure('login', 'Sign in with Discord first.'));
	const r = await issueCode(env, user, 'site');
	if (!r.ok) return respond(r, {}, r.reason === 'limit' ? 429 : 400);
	return respond({ token: r.token, command: r.command, exp: r.exp, mode: r.mode });
}

async function routeSubmit(request, env, getUser) {
	if (!sameOrigin(request, env)) return respond(failure('origin', 'Wrong origin.'));
	const user = await getUser(request, env);
	if (!user) return respond(failure('login', 'Sign in with Discord first.'));
	const body = await readJson(request, 8 * 1024);
	if (!body || typeof body.bundle !== 'string') return respond(failure('format', 'No link in the request.'));
	const t = now();
	if (await tooManyProofs(env, user.id, t)) return respond(failure('limit', 'Too many tries: wait a while and send it again.'));
	const result = await acceptBundle(env, body.bundle.trim(), { userId: String(user.id), t });
	await logProof(env, 'site', body.bundle, result, { discordId: String(user.id), uploaded: t });
	return respond(result, {}, 200);
}

// The same-site page's POSTs carry the session cookie: only the page's own origin may send them.
function sameOrigin(request, env) {
	const origin = request.headers.get('Origin');
	const allowed = env.LINK_ORIGIN ? allowedOrigins(env) : [new URL(request.url).origin];
	return !!origin && allowed.includes(origin);
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

