// The reference Worker (web/worker/link-worker.js) end to end: D1 is node:sqlite with the real
// schema, Discord is a stub that records calls, and the bundles are the shared vectors (plus
// new ones signed here with the same throwaway test seeds).

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { afterEach, beforeEach, describe, test } from 'node:test';
import { handleLink, drawRanks, drawLimit, LINK } from '../worker/link-worker.js';
import { parseToken, buildBundle, parseBundle, signedMessage } from '../public/core.js';
import { vectors, makeD1, sign, verify, b64url } from './helpers.mjs';

const probe = await makeD1();
const ORIGIN = 'https://link.example.org';
const ADMIN = 'test-admin-token-0123456789abcdefghijklmnop';
const [TOKEN_C, TOKEN_A] = vectors.backend.tokens;
const [B1, B3, B4] = vectors.bundles;
const KEYS = Object.fromEntries(vectors.keys.map((k) => [k.key_id, k]));
const USER_C = { id: TOKEN_C.discord_id, username: TOKEN_C.username, global_name: 'Some Player', avatar: null };
const USER_A = { id: TOKEN_A.discord_id, username: TOKEN_A.username, global_name: 'Tester Two', avatar: null };
const NOW = 1790000400; // a few minutes after the vectors' proofs

let env;
let discord;
let clock;
let realFetch;
let realNow;
let realError;
let logged; // what the Worker wrote with console.error (kept out of the test output)
const appKey = crypto.generateKeyPairSync('ed25519'); // a throwaway "Discord application" key

function discordPublicHex() {
	return appKey.publicKey.export({ format: 'der', type: 'spki' }).subarray(12).toString('hex');
}

async function setup({ mode = 'c' } = {}) {
	const DB = await makeD1();
	env = {
		DB,
		LINK_BACKEND_SEED: vectors.backend.seed_b64url,
		LINK_BACKEND_PUBLIC: vectors.backend.public_hex,
		LINK_MODE: mode,
		LINK_ORIGIN: ORIGIN,
		LINK_ADMIN_TOKEN: ADMIN,
		DISCORD_BOT_TOKEN: 'bot-token-for-tests',
		DISCORD_PUBLIC_KEY: discordPublicHex(),
		GUILD_ID: '300000000000000001',
		ROLE_ID: '300000000000000002',
	};
	for (const t of vectors.backend.tokens) {
		await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(t.R, t.discord_id, t.username, t.mode, t.created, t.exp, t.token, 'site')
			.run();
	}
	for (const k of vectors.keys) {
		await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, kind, bootstrap, created) VALUES (?, ?, ?, ?, ?, ?, ?)')
			.bind(k.key_id, k.public_hex, k.owner_discord_id, k.owner_username, k.kind, k.bootstrap, k.created)
			.run();
	}
	// The drawn players' own characters, linked earlier (their keys only count for those).
	const own = { testplayer01: 'Other Player-ClassicBetaPvP', testplayer02: 'Third Player-ClassicBetaPvP2', testplayer03: 'Fourth Player-ClassicBetaPvP', testplayer04: 'Fifth Player-ClassicBetaPvP' };
	for (const [id, character] of Object.entries(own)) {
		await DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
			.bind(character, KEYS[id].owner_discord_id, 'Olympus Vanguard', 'Horde', '0000000000', 1780000000)
			.run();
	}
}

function call(method, path, { body, user, origin = ORIGIN, headers = {} } = {}) {
	const init = { method, headers: { ...headers } };
	if (origin) init.headers.Origin = origin;
	if (body !== undefined) {
		init.body = typeof body === 'string' ? body : JSON.stringify(body);
		init.headers['Content-Type'] = 'application/json';
	}
	const request = new Request(`${ORIGIN}${path}`, init);
	return handleLink(request, env, {}, { getUser: async () => user || null });
}

async function submit(bundle, user) {
	const res = await call('POST', '/api/link/submit', { body: { bundle }, user });
	return { http: res.status, ...(await res.json()) };
}

// A bundle signed here: the vectors' request with other proofs.
function makeBundle(base, proofs) {
	const b = { requester: base.requester, guild: base.guild, faction: base.faction, nonce: base.nonce, R: base.R, proofs: [] };
	for (const [issued, keyId, confirmer] of proofs) {
		const p = { issued, keyId, confirmer };
		p.sig = b64url(sign(KEYS[keyId].seed_hex, signedMessage(b, p)));
		b.proofs.push(p);
	}
	return buildBundle(b);
}

async function row(sql, ...args) {
	return env.DB.prepare(sql).bind(...args).first();
}

beforeEach(async () => {
	discord = { calls: [], status: 204, code: 0 };
	realFetch = globalThis.fetch;
	globalThis.fetch = async (url, init = {}) => {
		discord.calls.push({ url: String(url), method: init.method, headers: init.headers });
		if (discord.status === 204) return new Response(null, { status: 204 });
		return new Response(JSON.stringify({ code: discord.code, message: 'stub' }), { status: discord.status });
	};
	realNow = Date.now;
	clock = NOW;
	Date.now = () => clock * 1000;
	realError = console.error;
	logged = [];
	console.error = (...args) => logged.push(args.join(' '));
});

afterEach(() => {
	globalThis.fetch = realFetch;
	Date.now = realNow;
	console.error = realError;
});

describe('Worker', { skip: probe ? false : 'node:sqlite is not available in this Node' }, () => {
	test('routes: /me, unknown paths, origin and login checks', async () => {
		await setup();
		let res = await call('GET', '/api/link/me');
		assert.equal(res.status, 401);
		assert.deepEqual(await res.json(), { user: null });
		res = await call('GET', '/api/link/me', { user: USER_C });
		assert.deepEqual((await res.json()).user, { id: USER_C.id, username: 'some_player', global_name: 'Some Player', avatar: null });
		assert.equal(await call('GET', '/elsewhere'), null);
		res = await call('POST', '/api/link/code', { user: USER_C, origin: 'https://evil.example' });
		assert.equal(res.status, 403);
		res = await call('POST', '/api/link/code', { user: USER_C, origin: null });
		assert.equal(res.status, 403);
		res = await call('POST', '/api/link/code', {});
		assert.equal(res.status, 401);
		res = await call('POST', '/api/link/submit', { body: { bundle: B1.bundle }, origin: 'https://evil.example', user: USER_C });
		assert.equal(res.status, 403);
	});

	test('codes: signed by the backend key, reused while fresh, three a day', async () => {
		await setup({ mode: 'c' });
		clock = Math.floor(realNow() / 1000);
		const user = { id: '123456789012345678', username: 'new.member_1', global_name: 'New', avatar: 'a' };
		const res = await call('POST', '/api/link/code', { user });
		assert.equal(res.status, 200);
		const body = await res.json();
		const parsed = parseToken(body.token);
		assert.ok(parsed.ok, parsed.error);
		assert.equal(parsed.token.username, 'new.member_1');
		assert.equal(parsed.token.mode, 'c');
		assert.equal(parsed.token.exp, clock + LINK.TOKEN_LIFE);
		assert.equal(body.command, `/oly discord ${body.token}`);
		assert.ok(verify(vectors.backend.public_hex, parsed.token.payload, Buffer.from(parsed.token.sig, 'base64url')));
		const stored = await row('SELECT * FROM codes WHERE r = ?', parsed.token.R);
		assert.equal(stored.discord_id, user.id);
		assert.equal(stored.used, null);

		// A reload gets the same code: it does not spend the day's three.
		const again = await (await call('POST', '/api/link/code', { user })).json();
		assert.equal(again.token, body.token);
		// Used codes do not come back; the fourth code of the day is refused.
		for (let i = 0; i < 2; i++) {
			await env.DB.prepare('UPDATE codes SET used = ? WHERE discord_id = ?').bind(clock, user.id).run();
			const next = await (await call('POST', '/api/link/code', { user })).json();
			assert.notEqual(next.token, body.token);
			assert.ok(parseToken(next.token).ok);
		}
		await env.DB.prepare('UPDATE codes SET used = ? WHERE discord_id = ?').bind(clock, user.id).run();
		const limited = await call('POST', '/api/link/code', { user });
		assert.equal(limited.status, 429);
		assert.equal((await limited.json()).reason, 'limit');

		// Mode "a" when the bot allows it; usernames the token cannot carry are refused.
		env.LINK_MODE = 'a';
		const other = await (await call('POST', '/api/link/code', { user: { id: '223456789012345678', username: 'other_one' } })).json();
		assert.equal(parseToken(other.token).token.mode, 'a');
		const bad = await call('POST', '/api/link/code', { user: { id: '323456789012345678', username: 'Old Name#1234' } });
		assert.equal(bad.status, 400);
		assert.equal((await bad.json()).reason, 'username');
	});

	test('a mismatched backend seed and public key never sign a code', async () => {
		await setup();
		clock = Math.floor(realNow() / 1000);
		env.LINK_BACKEND_PUBLIC = KEYS.testcouncil1.public_hex;
		const res = await call('POST', '/api/link/code', { user: { id: '423456789012345678', username: 'someone' } });
		assert.equal(res.status, 500);
		assert.equal((await res.json()).reason, 'server');
	});

	test('one councillor proof links the character and gives the role', async () => {
		await setup();
		const r = await submit(B1.bundle, USER_C);
		assert.equal(r.status, 'linked', r.message);
		assert.deepEqual(r.characters, ['Some Player-ClassicBetaPvP']);
		assert.equal(discord.calls.length, 1);
		assert.equal(discord.calls[0].method, 'PUT');
		assert.equal(discord.calls[0].url, `https://discord.com/api/v10/guilds/${env.GUILD_ID}/members/${USER_C.id}/roles/${env.ROLE_ID}`);
		assert.equal(discord.calls[0].headers.Authorization, 'Bot bot-token-for-tests');
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, NOW);
		assert.ok(await row('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?', B1.R, 'testcouncil1'));
		const m = await row('SELECT * FROM members WHERE character = ?', B1.requester);
		assert.equal(m.discord_id, USER_C.id);
		assert.equal(m.guild, 'Olympus');
		assert.equal(m.faction, 'Alliance');

		// The same link again (the page and the watcher both deliver it): fine, nothing new.
		const again = await submit(B1.bundle, USER_C);
		assert.equal(again.status, 'linked');
		assert.equal(again.reason, 'already');
		assert.equal(discord.calls.length, 1);
		// Another request on the used code is not.
		const other = makeBundle({ ...B1, requester: 'Someone Else-ClassicBetaPvP' }, [[NOW - 60, 'testcouncil1', 'Test Councillor-ClassicBetaPvP']]);
		assert.equal((await submit(other, USER_C)).reason, 'code-used');
		// Every submission is logged.
		assert.equal((await row("SELECT COUNT(*) AS n FROM inbox_uploads WHERE source = 'site'")).n, 3);
	});

	test('the code must be the signed-in user\'s, known, and not long expired', async () => {
		await setup();
		assert.equal((await submit(B1.bundle, USER_A)).reason, 'other-user');
		const unknown = makeBundle({ ...B1, R: 'ZZZZZZZZZZ' }, [[NOW - 60, 'testcouncil1', 'Test Councillor-ClassicBetaPvP']]);
		assert.equal((await submit(unknown, USER_C)).reason, 'unknown-code');
		assert.equal((await submit('OLB4~nonsense', USER_C)).reason, 'format');
		// Delivered 3 days after the code expired (the watcher was away): still good...
		clock = TOKEN_C.exp + 3 * 86400;
		assert.equal((await submit(B1.bundle, USER_C)).status, 'linked');
		// ...but not after the 7 days the addon keeps it.
		await setup();
		clock = TOKEN_C.exp + LINK.DELIVERY_GRACE + 1;
		assert.equal((await submit(B1.bundle, USER_C)).reason, 'expired');
	});

	test('mode c needs a councillor: player proofs alone are not enough', async () => {
		await setup();
		const players = makeBundle(B1, [
			[NOW - 100, 'testplayer01', 'Other Player-ClassicBetaPvP'],
			[NOW - 90, 'testplayer02', 'Third Player-ClassicBetaPvP2'],
			[NOW - 80, 'testplayer03', 'Fourth Player-ClassicBetaPvP'],
		]);
		const r = await submit(players, USER_C);
		assert.equal(r.reason, 'not-enough');
		assert.match(r.message, /one councillor/);
		assert.equal(discord.calls.length, 0);
	});

	test('mode a: three drawn players from three owners within 5 minutes', async () => {
		await setup();
		const r = await submit(B3.bundle, USER_A);
		assert.equal(r.status, 'linked', r.message);
		assert.deepEqual(r.characters, ['Tëst Plâyer-ClassicBetaPvP']);
		for (const id of ['testplayer01', 'testplayer02', 'testplayer03']) assert.ok(await row('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?', B3.R, id));
		// The four-proof bundle of the same code (another request) now finds the code used.
		assert.equal((await submit(B4.bundle, USER_A)).reason, 'code-used');
	});

	test('mode a: four proofs, any three that fit the window count', async () => {
		await setup();
		const r = await submit(B4.bundle, USER_A);
		assert.equal(r.status, 'linked', r.message);
		assert.deepEqual(r.characters, ['Ëlüñé Stârwhîspêr-ClassicBetaPvP2']);
	});

	test('a key or an owner counts once, however often a bundle carries it', async () => {
		await setup();
		// One player key three times (the parser reads it: the addon's Link.Parse does too).
		const p = parseBundle(B3.bundle).bundle.proofs[0];
		const same = [p, p, p].map((x) => [x.issued, x.keyId, x.confirmer, x.sig].join(',')).join(';');
		const thrice = B3.bundle.split('~').slice(0, 6).concat(same).join('~');
		assert.equal(parseBundle(thrice).ok, true);
		let r = await submit(thrice, USER_A);
		assert.equal(r.reason, 'not-enough', r.message);
		// Two of the three from one owner's key are one player (and the database keeps one
		// active key per owner, so a second key cannot stand in for a second player).
		const twoOfOne = makeBundle(B3, [
			[1790000200, 'testplayer01', 'Other Player-ClassicBetaPvP'],
			[1790000210, 'testplayer01', 'Other Player-ClassicBetaPvP'],
			[1790000245, 'testplayer02', 'Third Player-ClassicBetaPvP2'],
		]);
		r = await submit(twoOfOne, USER_A);
		assert.equal(r.reason, 'not-enough', r.message);
		assert.equal(discord.calls.length, 0);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B3.R)).used, null);
		// The same councillor proof twice: linked, counted once.
		const twice = B1.bundle.split('~').slice(0, 6).concat([B1.bundle.split('~')[6], B1.bundle.split('~')[6]].join(';')).join('~');
		r = await submit(twice, USER_C);
		assert.equal(r.status, 'linked', r.message);
		assert.equal((await row('SELECT COUNT(*) AS n FROM used WHERE r = ?', B1.R)).n, 1);
		assert.equal(discord.calls.length, 1);
	});

	test('a councillor never confirms a code of their own Discord account', async () => {
		await setup();
		await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(KEYS.testcouncil1.owner_discord_id, B1.R).run();
		const r = await submit(B1.bundle, { id: KEYS.testcouncil1.owner_discord_id, username: 'some_player' });
		assert.equal(r.reason, 'not-enough');
		assert.match(r.message, /own key/);
		assert.equal(discord.calls.length, 0);
	});

	test('mode a refusals: window, key age, account age, revoked, own key, unlinked confirmer', async () => {
		const three = [
			[1790000200, 'testplayer01', 'Other Player-ClassicBetaPvP'],
			[1790000245, 'testplayer02', 'Third Player-ClassicBetaPvP2'],
			[1790000301, 'testplayer03', 'Fourth Player-ClassicBetaPvP'],
		];
		const cases = [
			['more than 5 minutes apart', async () => makeBundle(B3, [three[0], three[1], [1790000200 + LINK.WINDOW + 1, 'testplayer03', 'Fourth Player-ClassicBetaPvP']]), /5 minutes/],
			['a key younger than 7 days', async () => {
				await env.DB.prepare('UPDATE keys SET created = ? WHERE key_id = ?').bind(NOW - 6 * 86400, 'testplayer02').run();
				return B3.bundle;
			}, /younger than 7 days/],
			['a Discord account younger than 30 days', async () => {
				const young = String((BigInt((NOW - 10 * 86400) * 1000) - 1420070400000n) << 22n);
				await env.DB.prepare('UPDATE keys SET owner_discord_id = ? WHERE key_id = ?').bind(young, 'testplayer03').run();
				await env.DB.prepare('UPDATE members SET discord_id = ? WHERE character = ?').bind(young, 'Fourth Player-ClassicBetaPvP').run();
				return B3.bundle;
			}, /account younger than 30 days/],
			['a revoked key', async () => {
				await env.DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE key_id = ?').bind(NOW, 'testplayer01').run();
				return B3.bundle;
			}, /revoked/],
			["the requester's own key", async () => {
				await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(KEYS.testplayer02.owner_discord_id, B3.R).run();
				return B3.bundle;
			}, /own key/, { id: KEYS.testplayer02.owner_discord_id, username: 'tester.two' }],
			['a confirmer that is not a character of the key owner', async () => {
				await env.DB.prepare('DELETE FROM members WHERE character = ?').bind('Third Player-ClassicBetaPvP2').run();
				return B3.bundle;
			}, /not a linked character/],
			['the requester is a character of a key owner', async () => {
				await env.DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
					.bind(B3.requester, KEYS.testplayer01.owner_discord_id, 'Olympus Vanguard', 'Horde', '0000000000', 1780000000)
					.run();
				return B3.bundle;
			}, /own character/],
			['a signature that does not match', async () => {
				const p = parseBundle(B3.bundle).bundle;
				p.proofs[1].sig = p.proofs[0].sig;
				return buildBundle(p);
			}, /bad signature/],
			['signed before the code existed', async () => makeBundle(B3, [[TOKEN_A.created - LINK.CLOCK_SKEW - 1, 'testplayer01', 'Other Player-ClassicBetaPvP'], three[1], three[2]]), /outside the code/],
			['signed in the future', async () => makeBundle(B3, [three[0], three[1], [NOW + LINK.CLOCK_SKEW + 60, 'testplayer03', 'Fourth Player-ClassicBetaPvP']]), /in the future/],
		];
		for (const [name, prepare, why, user] of cases) {
			await setup();
			const bundle = await prepare();
			const r = await submit(bundle, user || USER_A);
			assert.equal(r.status, 'rejected', `${name}: ${r.message}`);
			assert.equal(r.reason, 'not-enough', name);
			assert.match(r.message, why, name);
			assert.equal(discord.calls.length, 0, name);
			assert.equal((await row('SELECT used FROM codes WHERE r = ?', B3.R)).used, null, name);
		}
	});

	test('mode a: only keys ranked < M in the draw count', async () => {
		await setup();
		// 400 more player keys: M = max(20, ceil(3% of 405)) = 20.
		const stmts = [];
		for (let i = 0; i < 400; i++) {
			stmts.push(env.DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, kind, created) VALUES (?, ?, ?, ?, ?)')
				.bind(`pool${String(i).padStart(4, '0')}`, KEYS.testplayer05.public_hex, String(110000000000000000n + BigInt(i)), 'p', 1780000000));
		}
		await env.DB.batch(stmts);
		const rank = await drawRanks(env, B3.R);
		assert.equal(rank.size, 405);
		assert.equal(drawLimit(rank.size), 20);
		const drawn = ['testplayer01', 'testplayer02', 'testplayer03'].map((id) => rank.get(id));
		const r = await submit(B3.bundle, USER_A);
		if (drawn.every((x) => x < 20)) assert.equal(r.status, 'linked');
		else {
			assert.equal(r.reason, 'not-enough');
			assert.match(r.message, /not drawn for this code/);
		}
		// These fixed ids are not all in the top 20 of 405, so this run exercises the refusal.
		assert.ok(drawn.some((x) => x >= 20), `ranks ${drawn}`);
	});

	test('keys: one active key per Discord account; rotation revokes the old one first', async () => {
		await setup();
		const k = KEYS.testplayer01;
		await assert.rejects(
			env.DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, kind, created) VALUES (?, ?, ?, ?, ?)').bind('newkey01', k.public_hex, k.owner_discord_id, 'p', NOW).run(),
			/UNIQUE/,
		);
		await env.DB.batch([
			env.DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE owner_discord_id = ? AND revoked = 0').bind(NOW, k.owner_discord_id),
			env.DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, kind, created) VALUES (?, ?, ?, ?, ?)').bind('newkey01', k.public_hex, k.owner_discord_id, 'p', NOW),
		]);
		assert.equal((await row('SELECT COUNT(*) AS n FROM keys WHERE owner_discord_id = ? AND revoked = 0', k.owner_discord_id)).n, 1);
	});

	test('Discord: not in the server, or down, leaves the code unused to try again', async () => {
		await setup();
		discord.status = 404;
		discord.code = 10007;
		const r = await submit(B1.bundle, USER_C);
		assert.equal(r.reason, 'not-in-server');
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null);
		assert.equal(await row('SELECT 1 AS x FROM members WHERE character = ?', B1.requester), null);
		discord.status = 500;
		discord.code = 0;
		const down = await submit(B1.bundle, USER_C);
		assert.equal(down.status, 'error');
		assert.equal(down.reason, 'discord');
		assert.ok(logged.some((l) => l.includes('Discord role PUT 500')), 'the refusal is logged for the admin');
		discord.status = 204;
		assert.equal((await submit(B1.bundle, USER_C)).status, 'linked');
	});

	test('a character linked again moves to the new account; the old one loses the role if it has no other', async () => {
		await setup();
		await env.DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
			.bind(B1.requester, '500000000000000001', 'Olympus', 'Alliance', '1111111111', 1780000000)
			.run();
		assert.equal((await submit(B1.bundle, USER_C)).status, 'linked');
		assert.equal((await row('SELECT discord_id FROM members WHERE character = ?', B1.requester)).discord_id, USER_C.id);
		assert.deepEqual(discord.calls.map((c) => c.method), ['PUT', 'DELETE']);
		assert.match(discord.calls[1].url, /members\/500000000000000001\/roles\//);
	});

	test('the page may submit 10 times an hour per account', async () => {
		await setup();
		for (let i = 0; i < LINK.SUBMITS_PER_HOUR; i++) assert.equal((await submit('OLB4~bad', USER_C)).reason, 'format');
		const r = await submit(B1.bundle, USER_C);
		assert.equal(r.http, 429);
		assert.equal(r.reason, 'limit');
		clock += 3601;
		assert.equal((await submit(B1.bundle, USER_C)).status, 'linked');
	});

	test('the watcher inbox: admin token, many bundles, the user from each code', async () => {
		await setup();
		let res = await call('POST', '/api/link/inbox', { body: { bundles: [] }, origin: null });
		assert.equal(res.status, 401);
		res = await call('POST', '/api/link/inbox', { body: { bundles: [] }, origin: null, headers: { Authorization: 'Bearer wrong-token-wrong-token-wrong-token-xx' } });
		assert.equal(res.status, 401);
		const auth = { Authorization: `Bearer ${ADMIN}` };
		const bundles = [
			{ R: B1.R, bundle: B1.bundle, from: 'Some Player-ClassicBetaPvP', t: 1790000130 },
			{ R: B3.R, bundle: B3.bundle, from: 'Tëst Plâyer-ClassicBetaPvP', t: 1790000310 },
			{ R: 'AAAAAAAAAA', bundle: B1.bundle, from: 'Some Player-ClassicBetaPvP', t: 1790000131 },
			{ R: 'BBBBBBBBBB', bundle: 'OLB4~broken', from: 'x', t: 1 },
			B1.bundle,
		];
		res = await call('POST', '/api/link/inbox', { body: { bundles }, origin: null, headers: auth });
		assert.equal(res.status, 200);
		const { results } = await res.json();
		assert.deepEqual(results.map((r) => [r.R, r.status, r.reason]), [
			[B1.R, 'linked', 'linked'],
			[B3.R, 'linked', 'linked'],
			[B1.R, 'rejected', 'format'],
			['BBBBBBBBBB', 'rejected', 'format'],
			[B1.R, 'linked', 'already'],
		]);
		assert.equal((await row('SELECT discord_id FROM members WHERE character = ?', B3.requester)).discord_id, USER_A.id);
		const log = await row("SELECT * FROM inbox_uploads WHERE source = 'watcher' AND r = ? ORDER BY id LIMIT 1", B3.R);
		assert.equal(log.discord_id, USER_A.id);
		assert.equal(log.from_character, 'Tëst Plâyer-ClassicBetaPvP');
		assert.equal(log.received, 1790000310);
		res = await call('POST', '/api/link/inbox', { body: { bundles: new Array(LINK.MAX_BUNDLES + 1).fill('x') }, origin: null, headers: auth });
		assert.equal(res.status, 400);
	});

	test('a gateway bot gets a member\'s code with the admin token', async () => {
		await setup();
		clock = Math.floor(realNow() / 1000);
		let res = await call('POST', '/api/link/bot-code', { body: { id: '623456789012345678', username: 'bot.user' }, origin: null });
		assert.equal(res.status, 401);
		res = await call('POST', '/api/link/bot-code', { body: { id: '623456789012345678', username: 'bot.user' }, origin: null, headers: { Authorization: `Bearer ${ADMIN}` } });
		const body = await res.json();
		assert.ok(parseToken(body.token).ok);
		assert.match(body.reply, /\/oly discord OLC1\./);
		assert.equal((await row('SELECT source FROM codes WHERE r = ?', parseToken(body.token).token.R)).source, 'discord');
	});

	test('the /link slash command over HTTP interactions', async () => {
		await setup();
		clock = Math.floor(realNow() / 1000);
		const send = (payload, { good = true } = {}) => {
			const body = JSON.stringify(payload);
			const ts = String(clock);
			const sig = crypto.sign(null, Buffer.from(ts + body), good ? appKey.privateKey : crypto.generateKeyPairSync('ed25519').privateKey);
			return call('POST', '/api/discord/interactions', { body, origin: null, headers: { 'X-Signature-Ed25519': sig.toString('hex'), 'X-Signature-Timestamp': ts } });
		};
		assert.equal((await send({ type: 1 }, { good: false })).status, 401);
		assert.deepEqual(await (await send({ type: 1 })).json(), { type: 1 });
		const res = await send({ type: 2, data: { name: 'link' }, member: { user: { id: '723456789012345678', username: 'slash.user', global_name: 'Slash' } } });
		const reply = await res.json();
		assert.equal(reply.type, 4);
		assert.equal(reply.data.flags, 64);
		const line = reply.data.content.split('\n').find((l) => l.startsWith('/oly discord '));
		const parsed = parseToken(line);
		assert.ok(parsed.ok);
		assert.equal(parsed.token.username, 'slash.user');
		assert.ok(verify(vectors.backend.public_hex, parsed.token.payload, Buffer.from(parsed.token.sig, 'base64url')));
	});
});
