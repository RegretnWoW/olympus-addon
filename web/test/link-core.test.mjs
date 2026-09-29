// web/worker/link-core.mjs, the functions the Olympus bot's own Worker calls (web/FERN.md): D1 is
// node:sqlite with the real schema, Discord is a stub, promote() and demote() are the bot's (here,
// recorders), and the links are the shared vectors. Nothing touches the network.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, test } from 'node:test';
import * as core from '../worker/link-core.mjs';
import { parseToken, linkTag, buildBundle, parseBundle as pageParse, utf8Length } from '../public/core.js';
import { REPO, b64url, makeD1, publicHexOf, sign, vectors, verify } from './helpers.mjs';

const {
	LINK,
	PROOF_REASONS,
	issueCode,
	checkProof,
	acceptProof,
	acceptInbox,
	handleProof,
	handleInbox,
	handleKeys,
	manageKeys,
	registerKey,
	renewKey,
	revokeKey,
	revokeCharacter,
	discordUser,
	forgetUser,
	proofText,
	httpStatus,
	respond,
	corsHeaders,
	verifyCertificate,
	councilKeyId,
	councilCharacters,
	signedMessage,
} = core;

const probe = await makeD1();
const PAGE_ORIGIN = 'https://dnl-gentile.github.io';
const CLIENT_ID = '300000000000000123';
const ADMIN = 'test-admin-token-0123456789abcdefghijklmnop';
const [TOKEN_C, TOKEN_A] = vectors.backend.tokens;
const [B1, B3, , B2, B5] = vectors.bundles;
const KEYS = Object.fromEntries(vectors.keys.map((k) => [k.key_id, k]));
const CK = vectors.council_keys[0];
const USER_C = { id: TOKEN_C.discord_id, username: TOKEN_C.username };
const USER_A = { id: TOKEN_A.discord_id, username: TOKEN_A.username };
const NOW = 1799990400; // a few minutes after the vectors' proofs
const OWN = { player01: 'Other Player-ClassicBetaPvP', player02: 'Third Player-ClassicBetaPvP2', player03: 'Fourth Player-ClassicBetaPvP', player04: 'Fifth Player-ClassicBetaPvP' };
const DISCORD_TOKENS = { 'token-of-some-player-0001': USER_C, 'token-of-tester-two-00002': USER_A };

let env;
let realNow;
let realError;
let roles; // what promote() and demote() were asked
let discordCalls;

async function setup({ mode = 'c', binding = 'DB' } = {}) {
	const DB = await makeD1();
	env = {
		[binding]: DB,
		LINK_BACKEND_SEED: vectors.backend.seed_b64url,
		LINK_BACKEND_PUBLIC: vectors.backend.public_hex,
		LINK_CA_PUBLIC: vectors.council_authority.public_hex,
		LINK_COUNCIL_CHARACTERS: CK.character, // the vectors' High Councillor of the council authority
		LINK_MODE: mode,
		LINK_ORIGIN: PAGE_ORIGIN,
		LINK_ADMIN_TOKEN: ADMIN,
		DISCORD_CLIENT_ID: CLIENT_ID,
	};
	for (const t of vectors.backend.tokens) {
		await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(t.R, t.discord_id, t.username, t.mode, t.T, t.created, t.exp, t.token, 'discord')
			.run();
	}
	for (const k of vectors.keys) {
		await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, character, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(k.key_id, k.public_hex, k.owner_discord_id, k.owner_username, k.character, k.kind, k.bootstrap, k.created, k.cert_exp)
			.run();
	}
	for (const [id, character] of Object.entries(OWN)) {
		await DB.prepare('INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?)')
			.bind(character, KEYS[id].owner_discord_id, 'Olympus Vanguard', 'r', 'Horde', '0000000000', 1780000000)
			.run();
	}
	return DB;
}

const row = (sql, ...args) => (env.DB || env.LINK_DB).prepare(sql).bind(...args).first();
const promote = async (discordId, verdict) => {
	roles.push(['promote', discordId, verdict && verdict.character]);
};
const demote = async (discordId) => {
	roles.push(['demote', discordId]);
};

// Discord's GET /oauth2/@me for the made-up tokens above: this application's, scope identify.
function discordStub({ app = CLIENT_ID, scopes = ['identify'], status = 200, expires = '2027-06-01T00:00:00+00:00', fail = false } = {}) {
	return async (url, init) => {
		discordCalls.push({ url: String(url), auth: init && init.headers && init.headers.Authorization });
		if (fail) throw new TypeError('fetch failed');
		const token = String(init.headers.Authorization).replace(/^Bearer /, '');
		const user = DISCORD_TOKENS[token];
		if (status !== 200) return new Response(JSON.stringify({ message: 'x' }), { status });
		if (!user) return new Response(JSON.stringify({ message: '401: Unauthorized', code: 0 }), { status: 401 });
		return Response.json({ application: { id: app, name: 'Olympus' }, scopes, expires, user: { id: user.id, username: user.username, avatar: null, global_name: 'X' } });
	};
}

function page(method, { body, origin = PAGE_ORIGIN, headers = {} } = {}) {
	const init = { method, headers: { ...headers } };
	if (origin) init.headers.Origin = origin;
	if (body !== undefined) {
		init.body = typeof body === 'string' ? body : JSON.stringify(body);
		init.headers['Content-Type'] = 'application/json';
	}
	return new Request('https://bot.example.workers.dev/proof', init);
}

async function proof(text, token, opts = {}) {
	const res = await handleProof(page('POST', { body: { text, discordToken: token }, ...opts }), env, { promote, demote, fetchImpl: opts.fetchImpl || discordStub() });
	return { http: res.status, headers: res.headers, ...(await res.json()) };
}

beforeEach(() => {
	roles = [];
	discordCalls = [];
	realNow = Date.now;
	Date.now = () => NOW * 1000;
	realError = console.error;
	console.error = () => {};
});

afterEach(() => {
	Date.now = realNow;
	console.error = realError;
});

test('link-core.mjs is one file with no import: WebCrypto, fetch and Response only', () => {
	const src = readFileSync(join(REPO, 'web', 'worker', 'link-core.mjs'), 'utf8');
	assert.doesNotMatch(src, /^\s*import\b/m);
	assert.doesNotMatch(src, /\brequire\(|process\.|Buffer\b|node:/);
	for (const name of ['issueCode', 'checkProof', 'acceptProof', 'handleProof', 'acceptInbox', 'handleInbox', 'manageKeys', 'handleKeys', 'discordUser', 'forgetUser']) {
		assert.equal(typeof core[name], 'function', name);
	}
});

test('proofText: the bundle, the QR code\'s address or its fragment; nothing else', () => {
	assert.equal(proofText(B1.bundle), B1.bundle);
	assert.equal(proofText(B1.url), B1.bundle);
	assert.equal(proofText(`https://dnl-gentile.github.io/olympus-addon/#b=${encodeURIComponent(B1.bundle)}`), B1.bundle);
	assert.equal(proofText(`#b=${encodeURIComponent(B1.bundle)}`), B1.bundle);
	assert.equal(proofText(`  ${B1.bundle}\n`), B1.bundle);
	for (const x of ['', 'hello', 'https://dnl-gentile.github.io/olympus-addon/', '#b=%E0%A4%A', null, 42]) assert.equal(proofText(x), null, String(x));
});

test('httpStatus and respond: a refused link is a 200 with its reason; a bad request is not', async () => {
	assert.equal(httpStatus({ status: 'linked', reason: 'linked' }), 200);
	assert.equal(httpStatus({ status: 'rejected', reason: 'format' }), 200);
	assert.equal(httpStatus({ status: 'error', reason: 'discord' }), 200);
	for (const [reason, code] of [['format', 400], ['login', 401], ['site', 401], ['auth', 401], ['origin', 403], ['unknown-key', 404], ['method', 405], ['too-early', 409], ['limit', 429], ['server', 500]]) {
		assert.equal(httpStatus({ status: 'error', reason }), code, reason);
	}
	const res = respond({ status: 'error', reason: 'limit' }, { Vary: 'Origin' });
	assert.equal(res.status, 429);
	assert.equal(res.headers.get('Cache-Control'), 'no-store');
	assert.equal(res.headers.get('Vary'), 'Origin');
	assert.match(res.headers.get('Content-Type'), /^application\/json/);
});

describe('with D1', { skip: probe ? false : 'node:sqlite is not available in this Node' }, () => {
	test('issueCode: your /verify, an OLC2 code signed with your key and the reply that carries it', async () => {
		await setup({ binding: 'LINK_DB' }); // LINK_DB is taken before DB
		Date.now = () => realNow();
		const user = { id: '123456789012345678', username: 'new.member_1' };
		const r = await issueCode(env, user);
		assert.equal(r.ok, true);
		const t = parseToken(r.token).token;
		assert.equal(t.username, 'new.member_1');
		assert.equal(t.mode, 'c');
		assert.ok(verify(vectors.backend.public_hex, t.payload, Buffer.from(t.sig, 'base64url')), 'signed with LINK_BACKEND_SEED');
		assert.equal(r.command, `/oly discord ${r.token}`);
		assert.ok(utf8Length(r.command) < 255);
		assert.ok(r.reply.includes(r.command), 'the reply holds the line to paste');
		assert.match(r.reply, /not on stream/);
		assert.equal((await row('SELECT source FROM codes WHERE r = ?', t.R)).source, 'discord');
		assert.equal((await issueCode(env, user)).token, r.token, 'the same code again while it is fresh');
		for (const [who, reason] of [[{ id: 'abc', username: 'x.y' }, 'login'], [{ id: '223456789012345678', username: 'Old Name#1234' }, 'username']]) {
			const bad = await issueCode(env, who);
			assert.deepEqual([bad.ok, bad.reason], [false, reason]);
			assert.equal(bad.reply, bad.message);
		}
		for (let i = 0; i < 2; i++) {
			await env.LINK_DB.prepare('UPDATE codes SET used = 1 WHERE discord_id = ?').bind(user.id).run();
			assert.equal((await issueCode(env, user)).ok, true);
		}
		await env.LINK_DB.prepare('UPDATE codes SET used = 1 WHERE discord_id = ?').bind(user.id).run();
		const limited = await issueCode(env, user);
		assert.deepEqual([limited.ok, limited.reason], [false, 'limit']);
		assert.match(limited.reply, /3 codes today/);
	});

	test('checkProof: the verdict on a link, reading only, whatever form it came in', async () => {
		const DB = await setup();
		for (const text of [B1.bundle, B1.url, `#b=${encodeURIComponent(B1.bundle)}`]) {
			const v = await checkProof(env, text, { discordId: USER_C.id });
			assert.deepEqual(v, {
				ok: true,
				status: 'ok',
				already: false,
				R: B1.R,
				discordId: USER_C.id,
				username: USER_C.username,
				character: 'Some Player-ClassicBetaPvP',
				guild: 'Olympus II',
				faction: 'Alliance',
				guildCheck: 'w',
				guildKnown: 'who',
				by: 'councillor',
				confirmers: ['Test Councillor-ClassicBetaPvP'],
				message: 'Some Player-ClassicBetaPvP can be linked to @some.player.',
			});
		}
		// Nothing written: the code unused, nobody linked, no proof counted.
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null);
		assert.equal(await row('SELECT 1 AS x FROM members WHERE character = ?', B1.requester), null);
		assert.equal((await row('SELECT COUNT(*) AS n FROM used')).n, 0);
		// Three drawn players (mode a), the council authority's councillor (never registered).
		const players = await checkProof(env, B3.bundle, { discordId: USER_A.id });
		assert.deepEqual([players.ok, players.by, players.guildCheck, players.guildKnown, players.confirmers.length], [true, 'players', 'r', 'roster', 3]);
		const ca = await checkProof(env, B5.bundle, { discordId: USER_C.id });
		assert.deepEqual([ca.ok, ca.by, ca.confirmers], [true, 'councillor', [CK.character]]);
		assert.equal((await row('SELECT COUNT(*) AS n FROM council_keys')).n, 0, 'recorded only with a link it helped accept');
		// The watcher's inbox has no Discord account: the code's owner is the one linked.
		assert.equal((await checkProof(env, B1.bundle)).discordId, USER_C.id);
		// Refusals, each with its reason.
		const swapped = B1.bundle.replace(`~${B1.tag}~`, `~${await linkTag(TOKEN_A.signature_b64url, B1.requester)}~`);
		for (const [text, opts, reason] of [
			[B1.bundle, { discordId: USER_A.id }, 'other-user'],
			['OLB5~nonsense', {}, 'format'],
			['not a link', {}, 'format'],
			[swapped, {}, 'tag'],
			[B2.bundle, {}, 'guild-unverified'],
			[B1.bundle.replace(`~${B1.R}~`, '~ZZZZZZZZZZ~'), {}, 'unknown-code'],
		]) {
			const v = await checkProof(env, text, opts);
			assert.deepEqual([v.ok, v.status, v.reason], [false, 'rejected', reason], `${reason}: ${v.message}`);
		}
		Date.now = () => (TOKEN_C.exp + LINK.DELIVERY_GRACE + 1) * 1000;
		assert.equal((await checkProof(env, B1.bundle)).reason, 'expired');
		assert.ok(DB);
	});

	test('acceptProof: checks, claims the code, calls your promote(), records the link', async () => {
		await setup();
		const r = await acceptProof(env, B1.bundle, { discordId: USER_C.id, promote, demote });
		assert.deepEqual(r, {
			ok: true,
			status: 'linked',
			reason: 'linked',
			message: 'Some Player-ClassicBetaPvP is now linked to @some.player.',
			R: B1.R,
			discordId: USER_C.id,
			username: USER_C.username,
			character: 'Some Player-ClassicBetaPvP',
			guild: 'Olympus II',
			faction: 'Alliance',
			guildCheck: 'w',
			guildKnown: 'who',
			characters: ['Some Player-ClassicBetaPvP'],
		});
		assert.deepEqual(roles, [['promote', USER_C.id, 'Some Player-ClassicBetaPvP']]);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, NOW);
		assert.deepEqual({ ...(await row('SELECT discord_id, guild, gv, faction, r FROM members WHERE character = ?', B1.requester)) }, { discord_id: USER_C.id, guild: 'Olympus II', gv: 'w', faction: 'Alliance', r: B1.R });
		// The same link again (the page and the watcher both deliver it): "already", no second promote.
		const again = await acceptProof(env, B1.bundle, { promote, demote });
		assert.deepEqual([again.status, again.reason, again.character, again.guildCheck], ['linked', 'already', B1.requester, 'w']);
		assert.equal(roles.length, 1);
		await assert.rejects(acceptProof(env, B1.bundle, {}), /promote/, 'no promote, no link');
	});

	test('acceptProof: when promote() fails the code is freed and nothing is recorded; the same link works next time', async () => {
		await setup();
		const outcomes = [
			[async () => { throw new Error('Discord 500'); }, 'error', 'discord'],
			[async () => false, 'error', 'discord'],
			[async () => ({ ok: false }), 'error', 'discord'],
			[async () => ({ ok: false, reason: 'not-in-server' }), 'rejected', 'not-in-server'],
			[async () => { throw Object.assign(new Error('Unknown Member'), { reason: 'not-in-server' }); }, 'rejected', 'not-in-server'],
		];
		for (const [fail, status, reason] of outcomes) {
			const r = await acceptProof(env, B1.bundle, { discordId: USER_C.id, promote: fail });
			assert.deepEqual([r.ok, r.status, r.reason, r.R], [false, status, reason, B1.R]);
			assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null, reason);
			assert.equal(await row('SELECT 1 AS x FROM members WHERE character = ?', B1.requester), null, reason);
			assert.equal((await row('SELECT COUNT(*) AS n FROM used')).n, 0, reason);
		}
		// A promote that says yes in any of these ways links.
		for (const yes of [async () => undefined, async () => true, async () => ({ ok: true })]) {
			await setup();
			assert.equal((await acceptProof(env, B1.bundle, { discordId: USER_C.id, promote: yes })).status, 'linked');
		}
	});

	test('acceptProof: a character linked to another account stays with it; one proof never moves it, and nobody is demoted (Konig\'s review)', async () => {
		const OLD = '500000000000000001';
		const linkedTo = async (id) => env.DB.prepare('INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(B1.requester, id, 'Olympus I', 'r', 'Alliance', '1111111111', 1780000000).run();
		await setup();
		await linkedTo(OLD);
		// One councillor's proof (a leaked seed would do) for a character someone already linked.
		const v = await checkProof(env, B1.bundle, { discordId: USER_C.id });
		assert.deepEqual([v.ok, v.status, v.reason], [false, 'rejected', 'linked-elsewhere'], v.message);
		const r = await acceptProof(env, B1.bundle, { discordId: USER_C.id, promote, demote });
		assert.deepEqual([r.ok, r.status, r.reason, r.R], [false, 'rejected', 'linked-elsewhere', B1.R]);
		assert.deepEqual(roles, [], 'no role given, none taken');
		assert.deepEqual({ ...(await row('SELECT discord_id, guild, r FROM members WHERE character = ?', B1.requester)) }, { discord_id: OLD, guild: 'Olympus I', r: '1111111111' });
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null, 'the code stays unused');
		assert.equal((await row('SELECT COUNT(*) AS n FROM used')).n, 0);
		// The same account linking its own character again (a new code, another guild): it updates.
		await setup();
		await linkedTo(USER_C.id);
		const again = await acceptProof(env, B1.bundle, { discordId: USER_C.id, promote, demote });
		assert.equal(again.status, 'linked', again.message);
		assert.deepEqual({ ...(await row('SELECT discord_id, guild, r FROM members WHERE character = ?', B1.requester)) }, { discord_id: USER_C.id, guild: 'Olympus II', r: B1.R });
		assert.deepEqual(roles, [['promote', USER_C.id, B1.requester]]);
		// Linked by another account between the check and the record (promote() runs in between):
		// nothing is recorded, the code is freed, and the character stays the other account's.
		await setup();
		roles = [];
		const racing = async (discordId, verdict) => {
			await promote(discordId, verdict);
			await linkedTo(OLD);
		};
		const raced = await acceptProof(env, B1.bundle, { discordId: USER_C.id, promote: racing, demote });
		assert.deepEqual([raced.status, raced.reason], ['rejected', 'linked-elsewhere'], raced.message);
		assert.equal((await row('SELECT discord_id FROM members WHERE character = ?', B1.requester)).discord_id, OLD);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null);
		assert.equal((await row('SELECT COUNT(*) AS n FROM used')).n, 0);
		assert.deepEqual(roles.map((x) => x[0]), ['promote'], 'never a demote');
	});

	test('handleProof: CORS for the page\'s origin only, exact, never a wildcard nor credentials', async () => {
		await setup();
		let res = await handleProof(page('OPTIONS', { headers: { 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'content-type' } }), env, { promote });
		assert.equal(res.status, 204);
		assert.equal(res.headers.get('Access-Control-Allow-Origin'), PAGE_ORIGIN);
		assert.equal(res.headers.get('Access-Control-Allow-Methods'), 'POST');
		assert.equal(res.headers.get('Access-Control-Allow-Headers'), 'Authorization, Content-Type');
		assert.equal(res.headers.get('Vary'), 'Origin');
		assert.equal(res.headers.get('Access-Control-Allow-Credentials'), null);
		for (const origin of ['https://evil.example', 'https://dnl-gentile.github.io.evil.example', 'http://dnl-gentile.github.io', null]) {
			res = await handleProof(page('OPTIONS', { origin }), env, { promote });
			assert.equal(res.status, 403, String(origin));
			assert.equal(res.headers.get('Access-Control-Allow-Origin'), null);
			const post = await proof(B1.bundle, 'token-of-some-player-0001', { origin });
			assert.deepEqual([post.http, post.reason], [403, 'origin'], String(origin));
			assert.equal(post.headers.get('Access-Control-Allow-Origin'), null);
		}
		assert.equal(discordCalls.length, 0, 'no Discord call for a request from elsewhere');
		assert.deepEqual(corsHeaders(page('POST'), { LINK_ORIGIN: `${PAGE_ORIGIN}, https://link.example.org` })['Access-Control-Allow-Origin'], PAGE_ORIGIN);
		assert.equal(corsHeaders(page('POST'), {}), null, 'no LINK_ORIGIN: nobody');
		res = await handleProof(page('GET'), env, { promote });
		assert.equal(res.status, 405);
	});

	test('handleProof: the page\'s link and the player\'s Discord sign-in link the character and give the role', async () => {
		await setup();
		const r = await proof(B1.url, 'token-of-some-player-0001');
		assert.equal(r.http, 200);
		assert.deepEqual([r.status, r.reason, r.character, r.username, r.guildCheck], ['linked', 'linked', B1.requester, 'some.player', 'w']);
		assert.equal(r.discordId, undefined, 'the page never gets the Discord id');
		assert.equal(r.headers.get('Access-Control-Allow-Origin'), PAGE_ORIGIN);
		assert.deepEqual(roles, [['promote', USER_C.id, B1.requester]]);
		assert.deepEqual(discordCalls, [{ url: 'https://discord.com/api/v10/oauth2/@me', auth: 'Bearer token-of-some-player-0001' }]);
		const log = await row("SELECT * FROM inbox_uploads WHERE source = 'site'");
		assert.deepEqual([log.r, log.discord_id, log.requester, log.status, log.reason], [B1.R, USER_C.id, B1.requester, 'linked', 'linked']);
		assert.equal(JSON.stringify(await env.DB.prepare('SELECT * FROM inbox_uploads').all()).includes('token-of'), false, 'the Discord token is stored nowhere');
		// Another account's sign-in: the code is not theirs.
		await setup();
		assert.equal((await proof(B1.bundle, 'token-of-tester-two-00002')).reason, 'other-user');
		assert.equal(roles.length, 1);
	});

	test('handleProof: the Discord sign-in must be your application\'s, with identify, and still valid', async () => {
		await setup();
		for (const [stub, token, http, reason] of [
			[discordStub(), 'not-a-token-anyone-made', 401, 'login'],
			[discordStub(), 'x', 401, 'login'],
			[discordStub({ app: '399999999999999999' }), 'token-of-some-player-0001', 401, 'login'], // another site's application
			[discordStub({ scopes: ['guilds'] }), 'token-of-some-player-0001', 401, 'login'],
			[discordStub({ expires: '2026-01-01T00:00:00+00:00' }), 'token-of-some-player-0001', 401, 'login'],
			[discordStub({ status: 500 }), 'token-of-some-player-0001', 200, 'discord'],
			[discordStub({ fail: true }), 'token-of-some-player-0001', 200, 'discord'],
		]) {
			const r = await proof(B1.bundle, token, { fetchImpl: stub });
			assert.deepEqual([r.http, r.status, r.reason], [http, 'error', reason], `${token} ${reason}`);
		}
		assert.equal(roles.length, 0);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null);
		// discordUser on its own, and a Worker without DISCORD_CLIENT_ID refuses everyone.
		const who = await discordUser('token-of-some-player-0001', { clientId: CLIENT_ID, fetchImpl: discordStub() });
		assert.deepEqual(who, { ok: true, user: { id: USER_C.id, username: USER_C.username, global_name: 'X', avatar: null } });
		await assert.rejects(discordUser('token-of-some-player-0001', { fetchImpl: discordStub() }), /DISCORD_CLIENT_ID/);
		delete env.DISCORD_CLIENT_ID;
		const r = await proof(B1.bundle, 'token-of-some-player-0001');
		assert.deepEqual([r.http, r.reason], [500, 'server']);
	});

	test('handleProof: the body, the link\'s form, the site token and 10 links an hour', async () => {
		await setup();
		for (const body of ['{', { bundle: B1.bundle }, { text: B1.bundle }, { text: 7, discordToken: 'token-of-some-player-0001' }]) {
			const res = await handleProof(page('POST', { body }), env, { promote, fetchImpl: discordStub() });
			assert.equal(res.status, 400, JSON.stringify(body));
			assert.equal((await res.json()).reason, 'format');
		}
		const bad = await proof('OLB5~nonsense', 'token-of-some-player-0001');
		assert.deepEqual([bad.http, bad.status, bad.reason], [200, 'rejected', 'format']);
		assert.equal(discordCalls.length, 0, 'a malformed link never reaches Discord');
		// The site token, when you set one: the page's header must carry it.
		env.LINK_SITE_TOKEN = 'site-token-for-the-page';
		for (const headers of [{}, { Authorization: 'Bearer wrong' }]) {
			const r = await proof(B1.bundle, 'token-of-some-player-0001', { headers });
			assert.deepEqual([r.http, r.reason], [401, 'site']);
		}
		const ok = await proof(B1.bundle, 'token-of-some-player-0001', { headers: { Authorization: 'Bearer site-token-for-the-page' } });
		assert.equal(ok.status, 'linked', ok.message);
		delete env.LINK_SITE_TOKEN;
		// 10 an hour per Discord account (every link counts, refused or not).
		await setup();
		for (let i = 0; i < LINK.SUBMITS_PER_HOUR; i++) {
			const r = await proof(B1.bundle.replace(`~${B1.R}~`, '~ZZZZZZZZZZ~'), 'token-of-some-player-0001');
			assert.equal(r.reason, 'unknown-code');
		}
		const limited = await proof(B1.bundle, 'token-of-some-player-0001');
		assert.deepEqual([limited.http, limited.reason], [429, 'limit']);
		Date.now = () => (NOW + 3601) * 1000;
		assert.equal((await proof(B1.bundle, 'token-of-some-player-0001', { fetchImpl: discordStub({ expires: '2028-01-01T00:00:00+00:00' }) })).status, 'linked');
	});

	test('acceptInbox and handleInbox: the watcher\'s links, the code\'s owner linked, each logged', async () => {
		await setup();
		const r = await acceptInbox(env, { bundles: [{ R: B1.R, bundle: B1.bundle, from: 'Some Player-ClassicBetaPvP', t: 1799990130 }, B3.bundle, { R: 'AAAAAAAAAA', bundle: B1.bundle }] }, { promote, demote });
		assert.deepEqual(r.results.map((x) => [x.R, x.status, x.reason]), [
			[B1.R, 'linked', 'linked'],
			[B3.R, 'linked', 'linked'],
			[B1.R, 'rejected', 'format'],
		]);
		assert.deepEqual(roles.map((x) => x[1]), [USER_C.id, USER_A.id]);
		const log = await row("SELECT * FROM inbox_uploads WHERE source = 'watcher' AND r = ? ORDER BY id LIMIT 1", B1.R);
		assert.deepEqual([log.discord_id, log.from_character, log.received], [USER_C.id, 'Some Player-ClassicBetaPvP', 1799990130]);
		assert.equal((await acceptInbox(env, { nope: 1 }, { promote })).reason, 'format');
		const admin = { Authorization: `Bearer ${ADMIN}` };
		let res = await handleInbox(new Request('https://bot.example/inbox', { method: 'POST', body: JSON.stringify({ bundles: [] }) }), env, { promote });
		assert.equal(res.status, 401);
		res = await handleInbox(new Request('https://bot.example/inbox', { method: 'POST', headers: admin, body: JSON.stringify({ bundles: [B1.bundle] }) }), env, { promote });
		assert.deepEqual((await res.json()).results.map((x) => x.reason), ['already']);
	});

	test('keys: register, renew and revoke confirmer keys; revoke a councillor\'s every key by character', async () => {
		await setup();
		Date.now = () => realNow();
		const fresh = (await import('node:crypto')).generateKeyPairSync('ed25519').publicKey.export({ format: 'der', type: 'spki' }).subarray(12).toString('hex');
		// ("renew" and "revoke" are not registerKey's: they are left out.)
		const r = await registerKey(env, { key_id: 'newcouncil1', public_key: fresh, owner_discord_id: '400000000000000001', character: 'New Councillor-ClassicBetaPvP', kind: 'c', bootstrap: true, days: 30, renew: true });
		assert.equal(r.status, 'ok', r.message);
		const cert = await verifyCertificate(vectors.backend.public_hex, r.cert);
		assert.deepEqual([cert.keyId, cert.publicHex, cert.tier, cert.character], ['newcouncil1', fresh, 'c', 'New Councillor-ClassicBetaPvP']);
		assert.equal(r.command, `/oly discord cert ${r.cert}`);
		assert.equal(httpStatus(await registerKey(env, { key_id: 'newcouncil1', public_key: fresh, owner_discord_id: '400000000000000001', character: 'New Councillor-ClassicBetaPvP', kind: 'c', bootstrap: true })), 409);
		assert.equal((await renewKey(env, 'newcouncil1', 10)).cert_exp, Math.floor(realNow() / 1000) + 10 * 86400);
		assert.equal(httpStatus(await renewKey(env, 'nosuchkey1')), 404);
		assert.equal((await revokeKey(env, 'newcouncil1')).revoked, true);
		assert.equal(httpStatus(await manageKeys(env, { key_id: 'Bad Id' })), 400);
		// A registered key revoked: its proofs stop counting.
		Date.now = () => NOW * 1000;
		await revokeKey(env, 'council01');
		assert.match((await checkProof(env, B1.bundle)).message, /revoked key/);
		// A High Councillor's every key, by character: the council authority's certificates for it too.
		const all = await revokeCharacter(env, CK.character);
		assert.deepEqual([all.status, all.revoked], ['ok', true]);
		assert.match((await checkProof(env, B5.bundle)).message, /its character was revoked/);
		assert.equal(await councilKeyId(CK.public_hex), CK.key_id);
		// Through handleKeys, with the admin token.
		const res = await handleKeys(new Request('https://bot.example/keys', { method: 'POST', headers: { Authorization: `Bearer ${ADMIN}` }, body: JSON.stringify({ key_id: CK.key_id, revoke: true }) }), env);
		assert.deepEqual([res.status, (await res.json()).council], [200, true]);
		assert.equal((await handleKeys(new Request('https://bot.example/keys', { method: 'POST', body: '{}' }), env)).status, 401);
	});

	test('the council authority links only the councillors LINK_COUNCIL_CHARACTERS lists (the trust FERN.md\'s FAQ describes)', async () => {
		await setup();
		// The review's case: a key the council authority certified for a character this Worker never
		// heard of confirms a character that is nobody's, for the account whose /verify code it holds.
		const seed = (await import('node:crypto')).randomBytes(32).toString('hex');
		const pub = publicHexOf(seed);
		const keyId = await councilKeyId(pub);
		const minted = 'Nobody Registered-ClassicBetaPvP';
		const exp = NOW + 365 * 86400;
		const payload = `OLK2.${keyId}.${b64url(Buffer.from(pub, 'hex'))}.c.${exp}.${minted}`;
		const b = { requester: 'Random Char-ClassicBetaPvP', guild: 'Olympus II', faction: 'Alliance', nonce: '0123456789abcdef', R: TOKEN_C.R };
		b.tag = await linkTag(TOKEN_C.signature_b64url, b.requester);
		const p = { issued: NOW - 60, keyId, confirmer: minted, gv: 'w' };
		p.sig = b64url(sign(seed, signedMessage(b, p)));
		b.proofs = [{ ...p, pub: b64url(Buffer.from(pub, 'hex')), tier: 'c', certExp: exp, certSig: b64url(sign(vectors.council_authority.seed_hex, Buffer.from(payload, 'utf8'))) }];
		const text = buildBundle(b);
		// No list: no character the authority certifies is a councillor here (closed by default,
		// Konig's review: this was open before 1.0.0).
		delete env.LINK_COUNCIL_CHARACTERS;
		assert.equal(councilCharacters(env).size, 0);
		assert.match((await checkProof(env, text, { discordId: USER_C.id })).message, /not on LINK_COUNCIL_CHARACTERS/);
		// Listed, one links (checked, nothing written).
		env.LINK_COUNCIL_CHARACTERS = minted;
		const trusted = await checkProof(env, text, { discordId: USER_C.id });
		assert.deepEqual([trusted.ok, trusted.by, trusted.confirmers, trusted.guildCheck], [true, 'councillor', [minted], 'w']);
		// Your list: a certificate for anyone else counts for nothing. Nothing is claimed, given or recorded.
		env.LINK_COUNCIL_CHARACTERS = ` ${CK.character} ,Someone Else-ClassicBetaPvP,`;
		assert.deepEqual([...councilCharacters(env)], [CK.character, 'Someone Else-ClassicBetaPvP']);
		const refused = await acceptProof(env, text, { discordId: USER_C.id, promote });
		assert.deepEqual([refused.status, refused.reason], ['rejected', 'not-enough']);
		assert.match(refused.message, new RegExp(`${keyId}: its character is not on LINK_COUNCIL_CHARACTERS`));
		assert.deepEqual(roles, []);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', TOKEN_C.R)).used, null);
		assert.equal((await row('SELECT COUNT(*) AS n FROM council_keys')).n, 0);
		// A councillor on the list still links alone; a councillor key you registered is yours, list or not.
		assert.equal((await checkProof(env, B5.bundle, { discordId: USER_C.id })).ok, true);
		env.LINK_COUNCIL_CHARACTERS = 'Someone Else-ClassicBetaPvP';
		assert.match((await checkProof(env, B5.bundle)).message, /not on LINK_COUNCIL_CHARACTERS/);
		assert.equal((await checkProof(env, B1.bundle, { discordId: USER_C.id })).ok, true);
		// Set but empty: no certificate of the authority counts.
		env.LINK_COUNCIL_CHARACTERS = '';
		assert.deepEqual([...councilCharacters(env)], []);
		assert.equal((await checkProof(env, B5.bundle)).reason, 'not-enough');
		// Revoking a listed character does not stick: a certificate signed after it counts again.
		env.LINK_COUNCIL_CHARACTERS = minted;
		await revokeCharacter(env, minted, NOW - 3600);
		assert.equal((await checkProof(env, text, { discordId: USER_C.id })).ok, true);
		// Listed, the character links, and its key is recorded for you to see.
		const linked = await acceptProof(env, text, { discordId: USER_C.id, promote });
		assert.equal(linked.status, 'linked', linked.message);
		assert.deepEqual(roles, [['promote', USER_C.id, b.requester]]);
		assert.deepEqual({ ...(await row('SELECT key_id, character, first_seen FROM council_keys')) }, { key_id: keyId, character: minted, first_seen: NOW });
		assert.deepEqual({ ...(await row('SELECT key_id FROM used WHERE r = ?', TOKEN_C.R)) }, { key_id: keyId });
	});

	test('LINK_COUNCIL_CHARACTERS left out: no certificate of the council authority counts, closed by default (Konig\'s review)', async () => {
		await setup();
		delete env.LINK_COUNCIL_CHARACTERS;
		// B5: a real councillor's proof, the authority's real certificate. Without the list, no.
		const v = await checkProof(env, B5.bundle, { discordId: USER_C.id });
		assert.deepEqual([v.ok, v.reason], [false, 'not-enough'], v.message);
		assert.match(v.message, new RegExp(`${CK.key_id}: its character is not on LINK_COUNCIL_CHARACTERS`));
		const r = await acceptProof(env, B5.bundle, { discordId: USER_C.id, promote });
		assert.deepEqual([r.status, r.reason], ['rejected', 'not-enough']);
		assert.deepEqual(roles, [], 'nobody gets a role');
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B5.R)).used, null, 'the code stays unused');
		assert.equal((await row('SELECT COUNT(*) AS n FROM council_keys')).n, 0, 'nothing recorded');
		for (const unset of [undefined, null, '', ' , ']) {
			env.LINK_COUNCIL_CHARACTERS = unset;
			assert.equal(councilCharacters(env).size, 0, String(unset));
			assert.equal((await checkProof(env, B5.bundle)).reason, 'not-enough', String(unset));
		}
		// Keys you register yourself are yours: the list never applies to them.
		assert.equal((await checkProof(env, B1.bundle, { discordId: USER_C.id })).ok, true);
		// Listed, the councillor counts.
		env.LINK_COUNCIL_CHARACTERS = CK.character;
		assert.equal((await acceptProof(env, B5.bundle, { discordId: USER_C.id, promote })).status, 'linked');
	});

	test('forgetUser: a Discord account\'s characters, codes and log lines gone, its keys revoked', async () => {
		await setup();
		await acceptProof(env, B1.bundle, { discordId: USER_C.id, promote });
		await core.logProof(env, 'site', B1.bundle, { status: 'linked', reason: 'linked' }, { discordId: USER_C.id });
		const owner = KEYS.council01.owner_discord_id;
		const gone = await forgetUser(env, USER_C.id);
		assert.deepEqual([gone.status, gone.characters, gone.keys], ['ok', [B1.requester], []]);
		for (const table of ['members', 'codes', 'inbox_uploads']) {
			assert.equal((await row(`SELECT COUNT(*) AS n FROM ${table} WHERE discord_id = ?`, USER_C.id)).n, 0, table);
		}
		assert.equal((await checkProof(env, B1.bundle)).reason, 'unknown-code');
		const confirmer = await forgetUser(env, owner);
		assert.deepEqual(confirmer.keys, ['council01']);
		assert.deepEqual({ ...(await row('SELECT revoked, owner_username FROM keys WHERE key_id = ?', 'council01')) }, { revoked: 1, owner_username: null });
		assert.equal((await forgetUser(env, 'someone')).reason, 'format');
	});

	test('every reason POST /proof answered here is in PROOF_REASONS', async () => {
		await setup();
		const seen = new Set();
		const add = (r) => seen.add(r.reason);
		add(await proof(B2.bundle, 'token-of-some-player-0001'));
		add(await proof(B1.bundle, 'token-of-some-player-0001'));
		add(await proof(B1.bundle, 'token-of-some-player-0001'));
		add(await proof('OLB5~x', 'token-of-some-player-0001'));
		add(await proof(B1.bundle, 'nobody-has-this-token-00'));
		add(await proof(B1.bundle, 'token-of-some-player-0001', { origin: 'https://evil.example' }));
		for (const r of seen) assert.ok(PROOF_REASONS.includes(r), r);
		assert.deepEqual([...seen].sort(), ['already', 'format', 'guild-unverified', 'linked', 'login', 'origin']);
		assert.ok(pageParse(B1.bundle).ok && buildBundle(pageParse(B1.bundle).bundle) === B1.bundle);
	});
});
