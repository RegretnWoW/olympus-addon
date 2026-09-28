// The reference Worker (web/worker/link-worker.js) end to end: D1 is node:sqlite with the real
// schema, Discord is a stub that records calls, and the bundles are the shared vectors (plus
// new ones signed here with the same throwaway test seeds).

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { afterEach, beforeEach, describe, test } from 'node:test';
import { handleLink, drawThreshold, drawPrefix, drawLimit, verifyCertificate, parseCertificate, councilKeyId, LINK } from '../worker/link-worker.js';
import { parseToken, buildBundle, parseBundle, signedMessage, linkTag, utf8Length } from '../public/core.js';
import { vectors, makeD1, sign, verify, b64url, publicHexOf } from './helpers.mjs';

const probe = await makeD1();
const ORIGIN = 'https://link.example.org';
const ADMIN = 'test-admin-token-0123456789abcdefghijklmnop';
const [TOKEN_C, TOKEN_A] = vectors.backend.tokens;
const [B1, B3, B4, B2, B5] = vectors.bundles;
const KEYS = Object.fromEntries(vectors.keys.map((k) => [k.key_id, k]));
// The High Councillor's key the council authority certified (never registered in D1).
const CA = vectors.council_authority;
const CK = vectors.council_keys[0];
const COUNCIL_KEYS = Object.fromEntries(vectors.council_keys.map((k) => [k.key_id, { ...k, kind: 'c', ca: true }]));
const TOKENS = Object.fromEntries(vectors.backend.tokens.map((t) => [t.R, t]));
const USER_C = { id: TOKEN_C.discord_id, username: TOKEN_C.username, global_name: 'Some Player', avatar: null };
const USER_A = { id: TOKEN_A.discord_id, username: TOKEN_A.username, global_name: 'Tester Two', avatar: null };
const NOW = 1799990400; // a few minutes after the vectors' proofs
const COUNCILLOR = 'Test Councillor-ClassicBetaPvP';
const OWN = { player01: 'Other Player-ClassicBetaPvP', player02: 'Third Player-ClassicBetaPvP2', player03: 'Fourth Player-ClassicBetaPvP', player04: 'Fifth Player-ClassicBetaPvP' };

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

async function setup({ mode = 'c', policy } = {}) {
	const DB = await makeD1();
	env = {
		DB,
		LINK_BACKEND_SEED: vectors.backend.seed_b64url,
		LINK_BACKEND_PUBLIC: vectors.backend.public_hex,
		LINK_CA_PUBLIC: CA.public_hex,
		LINK_MODE: mode,
		LINK_ORIGIN: ORIGIN,
		LINK_ADMIN_TOKEN: ADMIN,
		DISCORD_BOT_TOKEN: 'bot-token-for-tests',
		DISCORD_PUBLIC_KEY: discordPublicHex(),
		GUILD_ID: '300000000000000001',
		ROLE_ID: '300000000000000002',
	};
	if (policy) env.LINK_GUILD_POLICY = policy;
	for (const t of vectors.backend.tokens) {
		await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(t.R, t.discord_id, t.username, t.mode, t.T, t.created, t.exp, t.token, 'site')
			.run();
	}
	for (const k of vectors.keys) {
		await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, character, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(k.key_id, k.public_hex, k.owner_discord_id, k.owner_username, k.character, k.kind, k.bootstrap, k.created, k.cert_exp)
			.run();
	}
	// The drawn players' own characters, linked earlier (their keys only count for those).
	for (const [id, character] of Object.entries(OWN)) {
		await DB.prepare('INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?)')
			.bind(character, KEYS[id].owner_discord_id, 'Olympus Vanguard', 'r', 'Horde', '0000000000', 1780000000)
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

const admin = { Authorization: `Bearer ${ADMIN}` };
async function keys(body) {
	const res = await call('POST', '/api/link/keys', { body, origin: null, headers: admin });
	return { http: res.status, ...(await res.json()) };
}

// The certificate a proof carries, for its confirmer: the backend's (a registered key), or the
// council authority's (`ca`), as the confirmer's addon announced it. It fills p's certificate
// fields; `signer` (a seed) signs it instead, `exp` is its end, `kind` its tier.
function withCertificate(p, { seedHex, kind, ca = false, exp = 1830000000, signer }) {
	const pub = Buffer.from(publicHexOf(seedHex), 'hex').toString('base64url');
	const payload = `OLK2.${p.keyId}.${pub}.${kind}.${exp}.${p.confirmer}`;
	const by = signer || (ca ? CA.seed_hex : vectors.backend.seed_hex);
	return Object.assign(p, { pub, tier: kind, certExp: exp, certSig: b64url(sign(by, Buffer.from(payload, 'utf8'))) });
}

// A bundle signed here: the vectors' request with other proofs, each carrying its key's
// certificate for its confirmer. The tag is the one the requester's addon makes from the code's
// command, unless `tag` says otherwise.
async function makeBundle(base, proofs, { tag } = {}) {
	const b = { requester: base.requester, guild: base.guild, faction: base.faction, nonce: base.nonce, R: base.R, proofs: [] };
	b.tag = tag || (TOKENS[b.R] ? await linkTag(TOKENS[b.R].signature_b64url, b.requester) : '0123456789abcdef');
	for (const [issued, keyId, confirmer, gv = 'r', cert = {}] of proofs) {
		const k = KEYS[keyId] || COUNCIL_KEYS[keyId];
		const p = { issued, keyId, confirmer, gv };
		p.sig = b64url(sign(k.seed_hex, signedMessage(b, p)));
		b.proofs.push(withCertificate(p, { seedHex: k.seed_hex, kind: k.kind || 'c', ca: !!k.ca, ...cert }));
	}
	return buildBundle(b);
}

async function row(sql, ...args) {
	return env.DB.prepare(sql).bind(...args).first();
}

beforeEach(async () => {
	discord = { calls: [], status: 204, code: 0, fail: false };
	realFetch = globalThis.fetch;
	globalThis.fetch = async (url, init = {}) => {
		discord.calls.push({ url: String(url), method: init.method, headers: init.headers });
		if (discord.fail) throw new TypeError('fetch failed'); // the network, not an answer
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
		assert.deepEqual((await res.json()).user, { id: USER_C.id, username: 'some.player', global_name: 'Some Player', avatar: null });
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

	test('codes: OLC2 signed by the backend key, T 00000000 in mode c, reused while fresh, three a day', async () => {
		await setup({ mode: 'c' });
		clock = Math.floor(realNow() / 1000);
		const user = { id: '123456789012345678', username: 'new.member_1', global_name: 'New', avatar: 'a' };
		const res = await call('POST', '/api/link/code', { user });
		assert.equal(res.status, 200);
		const body = await res.json();
		const parsed = parseToken(body.token);
		assert.ok(parsed.ok, parsed.error);
		assert.match(body.token, /^OLC2\./);
		assert.equal(parsed.token.username, 'new.member_1');
		assert.equal(parsed.token.mode, 'c');
		assert.equal(parsed.token.T, '00000000');
		assert.equal(parsed.token.exp, clock + LINK.TOKEN_LIFE);
		assert.equal(body.command, `/oly discord ${body.token}`);
		assert.ok(utf8Length(body.command) < 255);
		assert.ok(verify(vectors.backend.public_hex, parsed.token.payload, Buffer.from(parsed.token.sig, 'base64url')));
		const stored = await row('SELECT * FROM codes WHERE r = ?', parsed.token.R);
		assert.equal(stored.discord_id, user.id);
		assert.equal(stored.draw_t, '00000000');
		assert.equal(stored.token, body.token);
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

		// Mode "a" when the bot allows it: five player keys, so every one is drawn (T ffffffff).
		env.LINK_MODE = 'a';
		const other = await (await call('POST', '/api/link/code', { user: { id: '223456789012345678', username: 'other_one' } })).json();
		const a = parseToken(other.token).token;
		assert.equal(a.mode, 'a');
		assert.equal(a.T, 'ffffffff');
		assert.equal((await row('SELECT draw_t FROM codes WHERE r = ?', a.R)).draw_t, 'ffffffff');
		// Usernames the token cannot carry are refused.
		const bad = await call('POST', '/api/link/code', { user: { id: '323456789012345678', username: 'Old Name#1234' } });
		assert.equal(bad.status, 400);
		assert.equal((await bad.json()).reason, 'username');
	});

	test('a mismatched backend seed and public key never sign a code', async () => {
		await setup();
		clock = Math.floor(realNow() / 1000);
		env.LINK_BACKEND_PUBLIC = KEYS.council01.public_hex;
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
		assert.ok(await row('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?', B1.R, 'council01'));
		const m = await row('SELECT * FROM members WHERE character = ?', B1.requester);
		assert.equal(m.discord_id, USER_C.id);
		assert.equal(m.guild, 'Olympus II');
		assert.equal(m.gv, 'w'); // the councillor saw the requester in that guild in a /who
		assert.equal(m.faction, 'Alliance');

		// The same link again (the page and the watcher both deliver it): fine, nothing new.
		const again = await submit(B1.bundle, USER_C);
		assert.equal(again.status, 'linked');
		assert.equal(again.reason, 'already');
		assert.equal(discord.calls.length, 1);
		// Another request on the used code is not.
		const other = await makeBundle({ ...B1, requester: 'Someone Else-ClassicBetaPvP' }, [[NOW - 60, 'council01', COUNCILLOR, 'w']]);
		assert.equal((await submit(other, USER_C)).reason, 'code-used');
		// Every submission is logged.
		assert.equal((await row("SELECT COUNT(*) AS n FROM inbox_uploads WHERE source = 'site'")).n, 3);
	});

	test('the tag: only the player who pasted the command can make a link with its code', async () => {
		await setup();
		// Someone who saw R (a QR code on stream) but never the command: their own character, a
		// councillor's real signature, any tag they can think of.
		const thief = { ...B1, requester: 'Code Thief-ClassicBetaPvP' };
		const guesses = [
			await linkTag('A'.repeat(86), thief.requester), // a made-up token signature
			B1.tag, // the victim's tag, from the QR code
			await linkTag(TOKEN_A.signature_b64url, thief.requester), // another code's command
		];
		for (const tag of guesses) {
			const forged = await makeBundle(thief, [[NOW - 60, 'council01', COUNCILLOR, 'w']], { tag });
			const r = await submit(forged, USER_C);
			assert.equal(r.status, 'rejected');
			assert.equal(r.reason, 'tag', r.message);
		}
		// A tag that names the right requester but another code's command, and the watcher path.
		const swapped = await makeBundle(B1, [[NOW - 60, 'council01', COUNCILLOR, 'w']], { tag: await linkTag(TOKEN_A.signature_b64url, B1.requester) });
		assert.equal((await submit(swapped, USER_C)).reason, 'tag');
		const res = await call('POST', '/api/link/inbox', { body: { bundles: [swapped] }, origin: null, headers: admin });
		assert.equal((await res.json()).results[0].reason, 'tag');
		assert.equal(discord.calls.length, 0);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null);
		// The real one still links.
		assert.equal((await submit(B1.bundle, USER_C)).status, 'linked');
	});

	test('the code must be the signed-in user\'s, known, and not long expired', async () => {
		await setup();
		assert.equal((await submit(B1.bundle, USER_A)).reason, 'other-user');
		const unknown = await makeBundle({ ...B1, R: 'ZZZZZZZZZZ' }, [[NOW - 60, 'council01', COUNCILLOR]]);
		assert.equal((await submit(unknown, USER_C)).reason, 'unknown-code');
		assert.equal((await submit('OLB5~nonsense', USER_C)).reason, 'format');
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
		const players = await makeBundle(B1, [
			[NOW - 100, 'player01', OWN.player01],
			[NOW - 90, 'player02', OWN.player02],
			[NOW - 80, 'player03', OWN.player03],
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
		for (const id of ['player01', 'player02', 'player03']) assert.ok(await row('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?', B3.R, id));
		assert.equal((await row('SELECT gv FROM members WHERE character = ?', B3.requester)).gv, 'r');
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
		const b3 = parseBundle(B3.bundle).bundle;
		const p = b3.proofs[0];
		const thrice = buildBundle({ ...b3, proofs: [p, p, p] });
		assert.equal(parseBundle(thrice).ok, true);
		let r = await submit(thrice, USER_A);
		assert.equal(r.reason, 'not-enough', r.message);
		// Two of the three from one owner's key are one player (and the database keeps one
		// active key per owner, so a second key cannot stand in for a second player).
		const twoOfOne = await makeBundle(B3, [
			[1799990200, 'player01', OWN.player01],
			[1799990210, 'player01', OWN.player01],
			[1799990245, 'player02', OWN.player02],
		]);
		r = await submit(twoOfOne, USER_A);
		assert.equal(r.reason, 'not-enough', r.message);
		assert.equal(discord.calls.length, 0);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B3.R)).used, null);
		// The same councillor proof twice: linked, counted once.
		const f = B1.bundle.split('~');
		const twice = f.slice(0, 7).concat([f[7], f[7]].join(';')).join('~');
		r = await submit(twice, USER_C);
		assert.equal(r.status, 'linked', r.message);
		assert.equal((await row('SELECT COUNT(*) AS n FROM used WHERE r = ?', B1.R)).n, 1);
		assert.equal(discord.calls.length, 1);
	});

	test('a councillor never confirms a code of their own Discord account', async () => {
		await setup();
		await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(KEYS.council01.owner_discord_id, B1.R).run();
		const r = await submit(B1.bundle, { id: KEYS.council01.owner_discord_id, username: 'some.player' });
		assert.equal(r.reason, 'not-enough');
		assert.match(r.message, /own key/);
		assert.equal(discord.calls.length, 0);
	});

	test('a key confirms from the one character its certificate names (A1): an alt of the same account is refused', async () => {
		await setup();
		// The finding's case: the main's key, the alt's name. The certificate the proof carries
		// names the alt (so the requester's addon took it from the alt): D1 has the key for the main.
		const alt = await makeBundle(B1, [[NOW - 60, 'council01', 'Test Alt-ClassicBetaPvP', 'w']]);
		let r = await submit(alt, USER_C);
		assert.equal(r.reason, 'not-enough', r.message);
		assert.match(r.message, /council01: its certificate is not the one registered/);
		// Nor another key's public half, nor another tier.
		r = await submit(await makeBundle(B1, [[NOW - 60, 'council01', COUNCILLOR, 'w', { seedHex: KEYS.council02.seed_hex }]]), USER_C);
		assert.match(r.message, /not the one registered/);
		r = await submit(await makeBundle(B1, [[NOW - 60, 'council01', COUNCILLOR, 'w', { kind: 'p' }]]), USER_C);
		assert.match(r.message, /not the one registered/);
		assert.equal(discord.calls.length, 0);
		// Its own character: linked.
		assert.equal((await submit(await makeBundle(B1, [[NOW - 60, 'council01', COUNCILLOR, 'w']]), USER_C)).status, 'linked');
	});

	test('a High Councillor\'s key certified by the council authority counts unregistered, recorded for its character the first time', async () => {
		await setup();
		assert.equal(await row('SELECT 1 AS x FROM keys WHERE key_id = ?', CK.key_id), null, 'never registered');
		assert.equal(await councilKeyId(CK.public_hex), CK.key_id, 'its id: the first 12 hex of SHA-256 of the key');
		const r = await submit(B5.bundle, USER_C);
		assert.equal(r.status, 'linked', r.message);
		const rec = await row('SELECT * FROM council_keys WHERE key_id = ?', CK.key_id);
		assert.deepEqual([rec.public_key, rec.character, rec.cert_exp, rec.first_seen], [CK.public_hex, CK.character, CK.cert_exp, NOW]);
		assert.ok(await row('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?', B5.R, CK.key_id));
		assert.equal((await row('SELECT gv FROM members WHERE character = ?', B5.requester)).gv, 'w');
		// Its renewed certificate (a later end) moves the recorded end; the same key certified for
		// another character (which the author's client never does) is refused.
		const later = await makeBundle({ ...B3, requester: 'Another Requester-ClassicBetaPvP' }, [[1799990200, CK.key_id, CK.character, 'w', { exp: CK.cert_exp + 86400 }]]);
		await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(USER_C.id, B3.R).run();
		assert.equal((await submit(later, USER_C)).status, 'linked');
		assert.equal((await row('SELECT cert_exp FROM council_keys WHERE key_id = ?', CK.key_id)).cert_exp, CK.cert_exp + 86400);
		await setup();
		await submit(B5.bundle, USER_C);
		const moved = await makeBundle({ ...B3, requester: 'Another Requester-ClassicBetaPvP' }, [[1799990200, CK.key_id, 'Someone Else-ClassicBetaPvP', 'w']]);
		await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(USER_C.id, B3.R).run();
		const x = await submit(moved, USER_C);
		assert.equal(x.reason, 'not-enough');
		assert.match(x.message, /recorded for another character/);
	});

	test('a council key is recorded only with a link it helped accept: a certificate for another councillor\'s key with a signature nobody made records nothing, and that councillor still links', async () => {
		// The review's case: a councillor reads CK's public key off its DV announcement and gets the
		// council authority's certificate for it under his own name; he cannot sign with it, so he
		// carries 86 characters of junk in a link for his alt, with a code of his own account.
		await setup();
		const EVIL = 'Evil Councillor-ClassicBetaPvP';
		const pub = Buffer.from(CK.public_hex, 'hex').toString('base64url');
		const exp = NOW + 365 * 86400;
		const payload = `OLK2.${CK.key_id}.${pub}.c.${exp}.${EVIL}`;
		const certSig = b64url(sign(CA.seed_hex, Buffer.from(payload, 'utf8')));
		assert.ok(parseCertificate(`${payload}.${certSig}`));
		const b = { requester: 'Evil Alt-ClassicBetaPvP', guild: 'Olympus II', faction: 'Alliance', nonce: '0123456789abcdef', R: TOKEN_A.R };
		b.tag = await linkTag(TOKEN_A.signature_b64url, b.requester);
		b.proofs = [{ issued: NOW - 60, keyId: CK.key_id, confirmer: EVIL, gv: 'r', sig: b64url(Buffer.alloc(64, 7)), pub, tier: 'c', certExp: exp, certSig }];
		const squat = await submit(buildBundle(b), USER_A);
		assert.equal(squat.reason, 'not-enough');
		assert.match(squat.message, /bad signature/);
		assert.equal((await row('SELECT COUNT(*) AS n FROM council_keys')).n, 0, 'nothing recorded for a proof that does not check');
		// A real proof of CK's in a link refused as a whole (no confirmer checked the guild) records nothing either.
		const claimed = await makeBundle(B1, [[NOW - 60, CK.key_id, CK.character, 'c']]);
		assert.equal((await submit(claimed, USER_C)).reason, 'guild-unverified');
		assert.equal((await row('SELECT COUNT(*) AS n FROM council_keys')).n, 0, 'nothing recorded for a link that was not accepted');
		// The real councillor's link links, and records CK for its own character.
		const r = await submit(B5.bundle, USER_C);
		assert.equal(r.status, 'linked', r.message);
		const rec = await row('SELECT key_id, character FROM council_keys WHERE public_key = ?', CK.public_hex);
		assert.deepEqual([rec.key_id, rec.character], [CK.key_id, CK.character]);
		// From then on, the other councillor's certificate for CK's key counts nowhere.
		assert.match((await submit(buildBundle(b), USER_A)).message, /recorded for another character/);
	});

	test('the council authority\'s word only: its key, tier c, the key\'s own id, a certificate valid when signed, never its own account', async () => {
		const alias = '0123456789ab';
		COUNCIL_KEYS[alias] = { ...COUNCIL_KEYS[CK.key_id], key_id: alias };
		try {
			const cases = [
				['no LINK_CA_PUBLIC', async () => { delete env.LINK_CA_PUBLIC; return B5.bundle; }, /not certified by the council authority/],
				['another authority', async () => { env.LINK_CA_PUBLIC = vectors.backend.public_hex; return B5.bundle; }, /not certified by the council authority/],
				['signed by the backend key instead', async () => makeBundle(B1, [[NOW - 60, CK.key_id, CK.character, 'w', { ca: false }]]), /not certified by the council authority/],
				['a player\'s tier', async () => makeBundle(B1, [[NOW - 60, CK.key_id, CK.character, 'w', { kind: 'p' }]]), /not certified by the council authority/],
				['an id that is not the key\'s hash', async () => makeBundle(B1, [[NOW - 60, alias, CK.character, 'w']]), /not certified by the council authority/],
				['an id that is not 12 hex digits', async () => {
					COUNCIL_KEYS.council99x = { ...COUNCIL_KEYS[CK.key_id], key_id: 'council99x' };
					return makeBundle(B1, [[NOW - 60, 'council99x', CK.character, 'w']]);
				}, /unknown key/],
				['a certificate that ended before the proof', async () => makeBundle(B1, [[NOW - 60, CK.key_id, CK.character, 'w', { exp: NOW - 61 }]]), /after its certificate ended/],
				['the councillor\'s own account', async () => {
					await env.DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)').bind(CK.character, USER_C.id, 'Olympus I', 'Alliance', '0000000000', 1780000000).run();
					return B5.bundle;
				}, /own key/],
				['a character of the councillor\'s account', async () => {
					for (const c of [CK.character, B5.requester]) {
						await env.DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)').bind(c, '500000000000000077', 'Olympus I', 'Alliance', '0000000000', 1780000000).run();
					}
					return B5.bundle;
				}, /own character/],
			];
			for (const [name, prepare, why] of cases) {
				await setup();
				const r = await submit(await prepare(), USER_C);
				assert.equal(r.reason, 'not-enough', `${name}: ${r.message}`);
				assert.match(r.message, why, name);
				assert.equal(discord.calls.length, 0, name);
			}
		} finally {
			delete COUNCIL_KEYS[alias];
			delete COUNCIL_KEYS.council99x;
		}
	});

	test('revoking a council authority\'s key: on the list at once, seen or not, and its proofs stop counting', async () => {
		// Never seen yet (a leaked key revoked ahead): its first link is refused.
		await setup();
		let r = await keys({ key_id: CK.key_id, revoke: true });
		assert.deepEqual([r.http, r.status, r.revoked, r.council, r.character], [200, 'ok', true, true, null]);
		r = await submit(B5.bundle, USER_C);
		assert.equal(r.reason, 'not-enough');
		assert.match(r.message, /revoked/);
		assert.equal(await row('SELECT 1 AS x FROM council_keys WHERE key_id = ?', CK.key_id), null, 'not even recorded');
		// Seen, then revoked: what it signs afterwards no longer counts.
		await setup();
		assert.equal((await submit(B5.bundle, USER_C)).status, 'linked');
		r = await keys({ key_id: CK.key_id, revoke: true });
		assert.equal(r.character, CK.character, 'the councillor it was recorded for');
		await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(USER_C.id, B3.R).run();
		const again = await makeBundle({ ...B3, requester: 'Another Requester-ClassicBetaPvP' }, [[1799990200, CK.key_id, CK.character, 'w']]);
		r = await submit(again, USER_C);
		assert.equal(r.reason, 'not-enough');
		assert.match(r.message, /revoked/);
		// An id that is neither registered nor one of the authority's: unknown.
		assert.equal((await keys({ key_id: 'nosuchkey1', revoke: true })).reason, 'unknown-key');
	});

	test('revoking a character: every council authority certificate for it signed until then stops counting, keys it rotated away and never showed included; one signed after counts', async () => {
		// The review's case: a councillor rotated (/oly discord key new) or left the list, and the
		// keeper can name only the current key; the old one's certificate runs for up to a year.
		await setup();
		assert.equal((await submit(B5.bundle, USER_C)).status, 'linked', 'CK (the old key) counted and was recorded');
		const seedHex = crypto.createHash('sha256').update('olympus-link-test:rotated-away').digest('hex');
		const newId = await councilKeyId(publicHexOf(seedHex));
		COUNCIL_KEYS[newId] = { key_id: newId, seed_hex: seedHex, kind: 'c', ca: true };
		try {
			let r = await keys({ character: CK.character, revoke: true });
			assert.deepEqual([r.http, r.status, r.character, r.revoked, r.keys, r.council_keys], [200, 'ok', CK.character, true, [], [CK.key_id]]);
			assert.equal((await row('SELECT revoked_at FROM revoked_characters WHERE character = ?', CK.character)).revoked_at, NOW);
			await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(USER_C.id, B3.R).run();
			const base = { ...B3, requester: 'Another Requester-ClassicBetaPvP' };
			const year = LINK.CA_DAYS * 86400;
			for (const [name, proof] of [
				['the recorded key', [1799990200, CK.key_id, CK.character, 'w']],
				['a key never seen here, certified an hour before the revocation', [1799990200, newId, CK.character, 'w', { exp: NOW + year - 3600 }]],
				['certified the second of the revocation', [1799990200, newId, CK.character, 'w', { exp: NOW + year }]],
			]) {
				r = await submit(await makeBundle(base, [proof]), USER_C);
				assert.equal(r.reason, 'not-enough', `${name}: ${r.message}`);
				assert.match(r.message, /its character was revoked/, name);
			}
			assert.equal(discord.calls.length, 1, 'only B5 gave a role');
			// A certificate the authority signs for that character afterwards (back on the list, a new key): counts.
			r = await submit(await makeBundle(base, [[1799990200, newId, CK.character, 'w', { exp: NOW + year + 60 }]]), USER_C);
			assert.equal(r.status, 'linked', r.message);
			// Revoking again later covers that one too.
			clock = NOW + 120;
			assert.equal((await keys({ character: CK.character, revoke: true })).status, 'ok');
			assert.equal((await row('SELECT revoked_at FROM revoked_characters WHERE character = ?', CK.character)).revoked_at, NOW + 120);
		} finally {
			delete COUNCIL_KEYS[newId];
		}
		// A character's registered keys are revoked with it.
		clock = NOW;
		await setup();
		const r = await keys({ character: COUNCILLOR, revoke: true });
		assert.deepEqual([r.status, r.keys, r.council_keys], ['ok', ['council01'], []]);
		assert.equal((await row('SELECT revoked FROM keys WHERE key_id = ?', 'council01')).revoked, 1);
		const x = await submit(B1.bundle, USER_C);
		assert.equal(x.reason, 'not-enough');
		assert.match(x.message, /revoked key/);
		// Only a character's name, as the game writes it.
		for (const character of ['NoRealm', '', 7, 'Some,One-Realm']) {
			const bad = await keys({ character, revoke: true });
			assert.deepEqual([bad.http, bad.reason], [400, 'format'], String(character));
		}
		assert.equal((await keys({ character: CK.character })).reason, 'format', 'without "revoke": true it is not a revocation');
	});

	test('mode a refusals: window, key age, account age, replaced, revoked, own key, unlinked confirmer', async () => {
		const three = [
			[1799990200, 'player01', OWN.player01, 'r'],
			[1799990245, 'player02', OWN.player02, 'c'],
			[1799990301, 'player03', OWN.player03, 'c'],
		];
		const cases = [
			['more than 5 minutes apart', async () => makeBundle(B3, [three[0], three[1], [1799990200 + LINK.WINDOW + 1, 'player03', OWN.player03]]), /5 minutes/],
			['a key younger than 7 days when the code was issued', async () => {
				// Registered after the code was issued: it could have been picked for this R.
				await env.DB.prepare('UPDATE keys SET created = ? WHERE key_id = ?').bind(TOKEN_A.created - 6 * 86400, 'player02').run();
				return B3.bundle;
			}, /younger than 7 days/],
			['a Discord account younger than 30 days when the code was issued', async () => {
				const young = String((BigInt((TOKEN_A.created - 10 * 86400) * 1000) - 1420070400000n) << 22n);
				await env.DB.prepare('UPDATE keys SET owner_discord_id = ? WHERE key_id = ?').bind(young, 'player03').run();
				await env.DB.prepare('UPDATE members SET discord_id = ? WHERE character = ?').bind(young, OWN.player03).run();
				return B3.bundle;
			}, /account younger than 30 days/],
			['a key replaced before the code was issued', async () => {
				await env.DB.prepare('UPDATE keys SET replaced_at = ? WHERE key_id = ?').bind(TOKEN_A.created - 60, 'player02').run();
				return B3.bundle;
			}, /replaced/],
			['a revoked key', async () => {
				await env.DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE key_id = ?').bind(NOW, 'player01').run();
				return B3.bundle;
			}, /revoked/],
			["the requester's own key", async () => {
				await env.DB.prepare('UPDATE codes SET discord_id = ? WHERE r = ?').bind(KEYS.player02.owner_discord_id, B3.R).run();
				return B3.bundle;
			}, /own key/, { id: KEYS.player02.owner_discord_id, username: 'tester.two' }],
			['a confirmer that is not a character of the key owner', async () => {
				await env.DB.prepare('DELETE FROM members WHERE character = ?').bind(OWN.player02).run();
				return B3.bundle;
			}, /not a linked character/],
			['the requester is a character of a key owner', async () => {
				await env.DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
					.bind(B3.requester, KEYS.player01.owner_discord_id, 'Olympus Vanguard', 'Horde', '0000000000', 1780000000)
					.run();
				return B3.bundle;
			}, /own character/],
			['a signature that does not match', async () => {
				const p = parseBundle(B3.bundle).bundle;
				p.proofs[1].sig = p.proofs[0].sig;
				return buildBundle(p);
			}, /bad signature/],
			['a guild check changed after signing', async () => {
				const p = parseBundle(B3.bundle).bundle;
				p.proofs[1].gv = 'r';
				return buildBundle(p);
			}, /bad signature/],
			['signed before the code existed', async () => makeBundle(B3, [[TOKEN_A.created - LINK.CLOCK_SKEW - 1, 'player01', OWN.player01], three[1], three[2]]), /outside the code/],
			['signed in the future', async () => makeBundle(B3, [three[0], three[1], [NOW + LINK.CLOCK_SKEW + 60, 'player03', OWN.player03]]), /in the future/],
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

	test('the draw: T matches python\'s for a pool, and only keys below the code\'s T count', async () => {
		await setup({ mode: 'a' });
		// 400 more player keys (certified, old enough): M = max(20, ceil(3% of 405)) = 20.
		const pool = [];
		for (let i = 0; i < 400; i++) {
			pool.push(env.DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, character, kind, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?)')
				.bind(`pool${String(i).padStart(4, '0')}`, crypto.randomBytes(32).toString('hex'), String(110000000000000000n + BigInt(i)), `Pool ${i}-ClassicBetaPvP`, 'p', 1780000000, 1830000000));
		}
		await env.DB.batch(pool);
		// The pool alone is python's (web/test/fixtures/make-vectors.py): the same T.
		const v400 = vectors.draw.thresholds.find((x) => x.n === 400);
		await env.DB.prepare("UPDATE keys SET cert_exp = 0 WHERE key_id LIKE 'player%'").run(); // out of the pool for now
		assert.equal(await drawThreshold(env, vectors.draw.R, NOW), v400.T);
		await env.DB.prepare("UPDATE keys SET cert_exp = ? WHERE key_id LIKE 'player%'").bind(1830000000).run();
		// With the five players: the code carries the T of 405 keys.
		const T = await drawThreshold(env, B3.R, NOW);
		assert.notEqual(T, 'ffffffff');
		assert.equal(drawLimit(405), 20);
		await env.DB.prepare('UPDATE codes SET draw_t = ? WHERE r = ?').bind(T, B3.R).run();
		const drawn = await Promise.all(['player01', 'player02', 'player03'].map(async (id) => (await drawPrefix(B3.R, id)) < T));
		// These fixed ids are not all drawn for this R among 405, so this run exercises the refusal.
		assert.ok(drawn.some((x) => !x), `drawn ${drawn}`);
		const r = await submit(B3.bundle, USER_A);
		assert.equal(r.reason, 'not-enough');
		assert.match(r.message, /not drawn for this code/);
		// The same bundle counts once the code's T draws them all.
		await env.DB.prepare('UPDATE codes SET draw_t = ? WHERE r = ?').bind('ffffffff', B3.R).run();
		assert.equal((await submit(B3.bundle, USER_A)).status, 'linked');
		// A code issued now carries the T of its own R over this pool.
		clock = NOW;
		const issued = parseToken((await (await call('POST', '/api/link/code', { user: { id: '823456789012345678', username: 'pool.tester' } })).json()).token).token;
		assert.equal(issued.T, await drawThreshold(env, issued.R, NOW));
		assert.equal((await row('SELECT draw_t FROM codes WHERE r = ?', issued.R)).draw_t, issued.T);
		// Keys without a valid certificate, revoked, replaced or too young are not in the pool.
		await env.DB.prepare("UPDATE keys SET cert_exp = 0 WHERE key_id = 'pool0000'").run();
		await env.DB.prepare("UPDATE keys SET revoked = 1 WHERE key_id = 'pool0001'").run();
		await env.DB.prepare("UPDATE keys SET replaced_at = 1 WHERE key_id = 'pool0002'").run();
		await env.DB.prepare("UPDATE keys SET created = ? WHERE key_id = 'pool0003'").bind(NOW - 86400).run();
		const expected = [];
		for (let i = 4; i < 400; i++) expected.push(await drawPrefix(issued.R, `pool${String(i).padStart(4, '0')}`));
		for (const id of ['player01', 'player02', 'player03', 'player04', 'player05']) expected.push(await drawPrefix(issued.R, id));
		expected.sort();
		assert.equal(await drawThreshold(env, issued.R, NOW), expected[drawLimit(expected.length)]);
	});

	test('the guild: "verified" needs a counting confirmer who checked it in game, "claimed" does not', async () => {
		// Two councillors who could only take the guild's name as said.
		await setup();
		let r = await submit(B2.bundle, USER_C);
		assert.equal(r.status, 'rejected');
		assert.equal(r.reason, 'guild-unverified', r.message);
		assert.equal(discord.calls.length, 0);
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B2.R)).used, null);
		// A player's roster check does not vouch in mode c: player keys do not count there.
		const mixed = await makeBundle(B1, [[NOW - 60, 'council01', COUNCILLOR, 'c'], [NOW - 50, 'player01', OWN.player01, 'r']]);
		assert.equal((await submit(mixed, USER_C)).reason, 'guild-unverified');
		// One of the councillors checked it (its guild's roster): linked, and recorded so.
		const oneChecked = await makeBundle(B1, [[NOW - 60, 'council01', COUNCILLOR, 'c'], [NOW - 50, 'council02', 'Other Councillor-ClassicBetaPvP', 'r']]);
		r = await submit(oneChecked, USER_C);
		assert.equal(r.status, 'linked', r.message);
		assert.equal((await row('SELECT gv FROM members WHERE character = ?', B1.requester)).gv, 'r');
		// "claimed": the same two unchecked confirmations link, recorded as claimed.
		await setup({ policy: 'claimed' });
		r = await submit(B2.bundle, USER_C);
		assert.equal(r.status, 'linked', r.message);
		assert.equal((await row('SELECT gv FROM members WHERE character = ?', B2.requester)).gv, 'c');
		// Mode a: a drawn player's /who vouches for the three.
		await setup();
		assert.equal((await submit(B4.bundle, USER_A)).status, 'linked');
		await setup();
		const unchecked = await makeBundle(B4, [
			[1799990200, 'player01', OWN.player01, 'c'],
			[1799990245, 'player02', OWN.player02, 'c'],
			[1799990301, 'player03', OWN.player03, 'c'],
		]);
		assert.equal((await submit(unchecked, USER_A)).reason, 'guild-unverified');
	});

	test('keys: the admin endpoint registers a key and signs its certificate', async () => {
		await setup();
		clock = Math.floor(realNow() / 1000);
		let res = await call('POST', '/api/link/keys', { body: { key_id: 'newkey01' }, origin: null });
		assert.equal(res.status, 401);
		const pub = crypto.generateKeyPairSync('ed25519').publicKey.export({ format: 'der', type: 'spki' }).subarray(12);
		const r = await keys({ key_id: 'newcouncil1', public_key: pub.toString('hex'), owner_discord_id: '400000000000000001', owner_username: 'new.councillor', character: 'New Councillor-ClassicBetaPvP', kind: 'c', bootstrap: true, days: 30 });
		assert.equal(r.http, 200, r.message);
		assert.equal(r.status, 'ok');
		assert.equal(r.cert_exp, clock + 30 * 86400);
		assert.equal(r.character, 'New Councillor-ClassicBetaPvP');
		const cert = await verifyCertificate(vectors.backend.public_hex, r.cert);
		assert.ok(cert, 'the backend key signed it');
		assert.deepEqual([cert.keyId, cert.publicHex, cert.tier, cert.exp, cert.character], ['newcouncil1', pub.toString('hex'), 'c', r.cert_exp, 'New Councillor-ClassicBetaPvP']);
		assert.equal(r.command, `/oly discord cert ${r.cert}`);
		// The two chat lines fit the game's 255 bytes, and so does the announcement.
		assert.ok(utf8Length(r.command) < 255);
		assert.ok(utf8Length(`DV~1~${r.cert}`) < 255);
		assert.ok(utf8Length(`/oly discord key newcouncil1 ${'A'.repeat(43)}`) < 255);
		const stored = await row('SELECT * FROM keys WHERE key_id = ?', 'newcouncil1');
		assert.deepEqual([stored.public_key, stored.kind, stored.bootstrap, stored.cert_exp, stored.owner_username, stored.character], [pub.toString('hex'), 'c', 1, r.cert_exp, 'new.councillor', 'New Councillor-ClassicBetaPvP']);
		// The same key in base64url; a key that is not a bootstrap one confirms from one of its
		// owner's linked characters only; refusals.
		const p2 = crypto.generateKeyPairSync('ed25519').publicKey.export({ format: 'der', type: 'spki' }).subarray(12);
		const playerBody = { key_id: 'newplayer1', public_key: p2.toString('base64url'), owner_discord_id: '400000000000000002', character: 'New Player-ClassicBetaPvP', kind: 'p' };
		const unlinked = await keys(playerBody);
		assert.deepEqual([unlinked.http, unlinked.reason], [409, 'character-not-linked']);
		await env.DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
			.bind('New Player-ClassicBetaPvP', '400000000000000002', 'Olympus II', 'Alliance', '0000000000', 1780000000)
			.run();
		const player = await keys(playerBody);
		assert.equal(player.status, 'ok');
		assert.equal((await row('SELECT public_key FROM keys WHERE key_id = ?', 'newplayer1')).public_key, p2.toString('hex'));
		// A player key's certificate waits until the key counts (the test above).
		assert.deepEqual([player.cert, player.cert_exp, player.command], [null, null, null]);
		assert.ok(player.cert_from > clock + LINK.KEY_MIN_AGE);
		const who = { character: 'Another One-ClassicBetaPvP', bootstrap: true };
		for (const [body, reason, status] of [
			[{ key_id: 'newcouncil1', public_key: p2.toString('hex'), owner_discord_id: '400000000000000009', kind: 'c', ...who }, 'key-id-used', 409],
			[{ key_id: 'another01', public_key: pub.toString('hex'), owner_discord_id: '400000000000000009', kind: 'c', ...who }, 'public-key-used', 409],
			[{ key_id: 'another02', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: '400000000000000001', kind: 'c', ...who }, 'owner-has-key', 409],
			[{ key_id: 'another03', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: '400000000000000009', kind: 'p', ...who }, 'format', 400],
			[{ key_id: 'another04', public_key: 'xyz', owner_discord_id: '400000000000000009', kind: 'c', ...who }, 'format', 400],
			[{ key_id: 'another05', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: 'abc', kind: 'c', ...who }, 'format', 400],
			[{ key_id: 'another06', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: '400000000000000009', kind: 'x', ...who }, 'format', 400],
			[{ key_id: 'another07', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: '400000000000000009', kind: 'c', days: 0, ...who }, 'format', 400],
			[{ key_id: 'another08', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: '400000000000000009', kind: 'c', bootstrap: true }, 'format', 400], // no character
			[{ key_id: 'another09', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: '400000000000000009', kind: 'c', bootstrap: true, character: 'No Realm' }, 'format', 400],
			[{ key_id: 'a1b2c3d4e5f6', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: '400000000000000009', kind: 'c', ...who }, 'format', 400], // the council authority's ids
			[{ key_id: 'Bad Id', kind: 'p' }, 'format', 400],
			[{ key_id: 'unknown1', renew: true }, 'unknown-key', 404],
		]) {
			const x = await keys(body);
			assert.equal(x.reason, reason, JSON.stringify(body));
			assert.equal(x.http, status, JSON.stringify(body));
		}
		// Renewing: a new certificate for the same key (365 days for a councillor unless "days"
		// says otherwise; a player key's 90, once it counts); revoking.
		clock += 100;
		const renewed = await keys({ key_id: 'newcouncil1', renew: true });
		assert.equal(renewed.status, 'ok');
		assert.equal(renewed.replaced, null);
		assert.equal(parseCertificate(renewed.cert).exp, clock + LINK.CERT_DAYS * 86400);
		assert.equal(parseCertificate(renewed.cert).character, 'New Councillor-ClassicBetaPvP', 'for the same character');
		assert.equal((await row('SELECT cert_exp FROM keys WHERE key_id = ?', 'newcouncil1')).cert_exp, clock + LINK.CERT_DAYS * 86400);
		assert.equal(parseCertificate((await keys({ key_id: 'newcouncil1', renew: true, days: 10 })).cert).exp, clock + 10 * 86400);
		assert.equal((await keys({ key_id: 'newplayer1', renew: true })).reason, 'too-early');
		clock = player.cert_from;
		assert.equal(parseCertificate((await keys({ key_id: 'newplayer1', renew: true })).cert).exp, clock + LINK.CERT_DAYS_PLAYER * 86400);
		assert.equal((await keys({ key_id: 'newplayer1', revoke: true })).revoked, true);
		assert.equal((await row('SELECT revoked FROM keys WHERE key_id = ?', 'newplayer1')).revoked, 1);
		assert.equal((await keys({ key_id: 'newplayer1', renew: true })).reason, 'revoked');
	});

	test('rotating a councillor key: the new key in game first, the old one revoked after', async () => {
		const k = KEYS.council01;
		const fresh = crypto.generateKeyPairSync('ed25519');
		const pub = fresh.publicKey.export({ format: 'der', type: 'spki' }).subarray(12).toString('hex');
		KEYS.council01b = { seed_hex: fresh.privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(16).toString('hex'), kind: 'c' };
		try {
			const signedNew = await makeBundle(B1, [[NOW - 30, 'council01b', COUNCILLOR, 'w']]);
			const rotate = async () => {
				await setup();
				const r = await keys({ key_id: 'council01b', public_key: pub, owner_discord_id: k.owner_discord_id, character: COUNCILLOR, kind: 'c', bootstrap: true, replace: true });
				assert.equal(r.status, 'ok', r.message);
				assert.equal(r.replaced, 'council01');
			};
			// The new key is registered while the old one stays: a link the old key signed (it
			// waits for the watcher) still counts...
			await rotate();
			const old = await row('SELECT * FROM keys WHERE key_id = ?', 'council01');
			assert.deepEqual([old.revoked, old.replaced_at], [0, NOW]);
			assert.equal((await submit(B1.bundle, USER_C)).status, 'linked', 'the old key still counts');
			// ...and so does what the new one signs, once the confirmer typed it in game.
			await rotate();
			assert.equal((await submit(signedNew, USER_C)).status, 'linked', 'the new key counts');
			// Revoking the old key afterwards ends it (a leaked key: revoke it at once instead).
			await rotate();
			assert.equal((await keys({ key_id: 'council01', revoke: true })).revoked, true);
			const after = await submit(B1.bundle, USER_C);
			assert.equal(after.reason, 'not-enough');
			assert.match(after.message, /revoked/);
			assert.equal((await submit(signedNew, USER_C)).status, 'linked');
			// Still one active key per owner: a third one without "replace" is refused, and the
			// database takes no second certified key (a new key without a certificate may wait
			// next to it: its first certificate replaces the old one).
			const third = await keys({ key_id: 'council01c', public_key: crypto.randomBytes(32).toString('hex'), owner_discord_id: k.owner_discord_id, character: COUNCILLOR, kind: 'c', bootstrap: true });
			assert.equal(third.reason, 'owner-has-key');
			await assert.rejects(
				env.DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, character, kind, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?)').bind('council01d', crypto.randomBytes(32).toString('hex'), k.owner_discord_id, COUNCILLOR, 'c', NOW, NOW + 86400).run(),
				/UNIQUE/,
			);
			await env.DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, character, kind, created) VALUES (?, ?, ?, ?, ?, ?)').bind('council01e', crypto.randomBytes(32).toString('hex'), k.owner_discord_id, COUNCILLOR, 'c', NOW).run();
			await assert.rejects(env.DB.prepare('UPDATE keys SET cert_exp = ? WHERE key_id = ?').bind(NOW + 86400, 'council01e').run(), /UNIQUE/);
		} finally {
			delete KEYS.council01b;
		}
	});

	// The addon asks every player key that has a valid certificate and that the code's T draws
	// (Link.lua's Online): so a certificate the Worker hands out must be for a key it counts, or
	// the same code typed again asks the same refused key every time.
	test('a player key gets its certificate only once this Worker counts it for every open code', async () => {
		await setup({ mode: 'a' });
		const t0 = 1800100000;
		const seeds = {};
		const chars = {};
		const register = async (keyId, owner, extra = {}) => {
			seeds[keyId] = crypto.randomBytes(32).toString('hex');
			chars[keyId] = `Conf ${keyId}-ClassicBetaPvP`;
			await env.DB.prepare('INSERT OR IGNORE INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?)')
				.bind(chars[keyId], owner, 'Olympus Vanguard', 'r', 'Horde', '0000000000', 1780000000)
				.run();
			return keys({ key_id: keyId, public_key: publicHexOf(seeds[keyId]), owner_discord_id: owner, character: chars[keyId], kind: 'p', ...extra });
		};
		for (const id of ['player01', 'player02', 'player03']) {
			seeds[id] = KEYS[id].seed_hex;
			chars[id] = OWN[id];
		}
		let users = 0;
		const newCode = async () => {
			users += 1;
			const user = { id: String(500000000000000000n + BigInt(users)), username: `fresh.user${users}` };
			const res = await call('POST', '/api/link/code', { user });
			assert.equal(res.status, 200);
			return { user, token: parseToken((await res.json()).token).token };
		};
		// A link on `code` with these keys' proofs, signed from `issued` on, sent now.
		const link = async (code, ids, issued) => {
			const b = { requester: 'Fresh Requester-ClassicBetaPvP', guild: 'Olympus Vanguard', faction: 'Horde', nonce: '0011223344556677', R: code.token.R, proofs: [] };
			b.tag = await linkTag(code.token.sig, b.requester);
			ids.forEach((keyId, i) => {
				const p = { issued: issued + i, keyId, confirmer: chars[keyId], gv: 'r' };
				p.sig = b64url(sign(seeds[keyId], signedMessage(b, p)));
				b.proofs.push(withCertificate(p, { seedHex: seeds[keyId], kind: 'p' }));
			});
			return submit(buildBundle(b), code.user);
		};
		const oldOwner = (n) => String(100000000000000030n + BigInt(n)); // accounts from 2015
		const ownerBorn = (t) => String((BigInt(t * 1000) - 1420070400000n) << 22n); // an account made at unix time t
		const expectFrom = (created, account = 0) => Math.max(created + LINK.KEY_MIN_AGE, account + LINK.ACCOUNT_MIN_AGE) + LINK.TOKEN_LIFE + LINK.CLOCK_SKEW;
		// What the requester's addon does with a certificate: it draws the key for a code when the
		// certificate is the backend's, for a player key, not ended, and the key's place is below T.
		const addonDraws = async (cert, code, at) => {
			const c = await verifyCertificate(vectors.backend.public_hex, cert);
			return !!c && c.tier === 'p' && c.exp > at && (await drawPrefix(code.token.R, c.keyId)) < code.token.T;
		};

		// A new player key: registered, but no certificate yet, and not in the draw.
		clock = t0;
		const fresh = await register('fresh0001', oldOwner(1));
		assert.equal(fresh.status, 'ok', fresh.message);
		assert.equal(fresh.cert, null, 'no certificate for a key that does not count yet');
		assert.equal(fresh.command, null);
		assert.equal(fresh.cert_from, expectFrom(t0));
		assert.match(fresh.message, /renew/);
		assert.equal((await row('SELECT cert_exp FROM keys WHERE key_id = ?', 'fresh0001')).cert_exp, null);
		// Two days later (the finding): the pool is small, so T draws every key. Had it a
		// certificate, the addon would ask it, and this Worker would refuse it on every try.
		clock = t0 + 2 * 86400;
		let code = await newCode();
		assert.equal(code.token.T, 'ffffffff');
		let r = await link(code, ['fresh0001', 'player01', 'player02'], clock - 60);
		assert.equal(r.reason, 'not-enough');
		assert.match(r.message, /fresh0001: key younger than 7 days/);
		r = await keys({ key_id: 'fresh0001', renew: true });
		assert.deepEqual([r.http, r.reason, r.cert_from], [409, 'too-early', expectFrom(t0)]);
		assert.equal(r.cert, undefined);
		// Seven days old, but a code issued just before is still open and does not count it.
		clock = t0 + LINK.KEY_MIN_AGE - 60;
		const before = await newCode();
		clock = t0 + LINK.KEY_MIN_AGE + 3600;
		assert.equal((await keys({ key_id: 'fresh0001', renew: true })).reason, 'too-early');
		r = await link(before, ['fresh0001', 'player01', 'player02'], clock - 60);
		assert.match(r.message, /fresh0001: key younger than 7 days/);
		clock = fresh.cert_from - 1;
		assert.equal((await keys({ key_id: 'fresh0001', renew: true })).reason, 'too-early');
		// From cert_from on: the certificate (a player's lasts 90 days), and every code a proof
		// signed from now on can belong to counts the key, even the oldest still open.
		clock = t0 + LINK.KEY_MIN_AGE;
		const oldest = await newCode();
		clock = fresh.cert_from;
		const certified = await keys({ key_id: 'fresh0001', renew: true });
		assert.equal(certified.status, 'ok', certified.message);
		const c = await verifyCertificate(vectors.backend.public_hex, certified.cert);
		assert.deepEqual([c.keyId, c.tier, c.exp], ['fresh0001', 'p', clock + LINK.CERT_DAYS_PLAYER * 86400]);
		assert.equal(LINK.CERT_DAYS_PLAYER, 90);
		assert.equal(certified.command, `/oly discord cert ${certified.cert}`);
		assert.ok(await addonDraws(certified.cert, oldest, clock));
		const lastIssued = oldest.token.exp; // a proof signed at the code's end, by a clock 5 minutes behind
		assert.equal(lastIssued, clock - LINK.CLOCK_SKEW);
		r = await link(oldest, ['player01', 'player02', 'fresh0001'], lastIssued - 2);
		assert.equal(r.status, 'linked', r.message);

		// A young Discord account: the key waits for the account's 30 days too.
		clock = t0;
		const born = t0 - 10 * 86400;
		const young = await register('fresh0002', ownerBorn(born));
		assert.equal(young.cert, null);
		assert.equal(young.cert_from, expectFrom(t0, born));
		clock = expectFrom(t0);
		assert.equal((await keys({ key_id: 'fresh0002', renew: true })).reason, 'too-early');
		clock = young.cert_from - LINK.TOKEN_LIFE; // the account is 30 days old, but not at the open codes' issue
		assert.equal((await keys({ key_id: 'fresh0002', renew: true })).reason, 'too-early');
		clock = born + LINK.ACCOUNT_MIN_AGE;
		const oldestForYoung = await newCode();
		clock = young.cert_from;
		const youngCert = await keys({ key_id: 'fresh0002', renew: true });
		assert.equal(youngCert.status, 'ok', youngCert.message);
		assert.ok(await addonDraws(youngCert.cert, oldestForYoung, clock));
		r = await link(oldestForYoung, ['player01', 'player02', 'fresh0002'], oldestForYoung.token.exp - 2);
		assert.equal(r.status, 'linked', r.message);

		// Rotating a player key: the new key waits for its certificate like any other, and the old
		// one keeps counting (the confirmer still has it in game) until then.
		clock = t0;
		const owner01 = KEYS.player01.owner_discord_id;
		// (Registered for the same character as the old key: the confirmer's own, linked.)
		seeds.player01r = crypto.randomBytes(32).toString('hex');
		chars.player01r = OWN.player01;
		const rot = await keys({ key_id: 'player01r', public_key: publicHexOf(seeds.player01r), owner_discord_id: owner01, character: OWN.player01, kind: 'p', replace: true });
		assert.equal(rot.status, 'ok', rot.message);
		assert.deepEqual([rot.cert, rot.replaced], [null, null]);
		assert.equal((await row('SELECT replaced_at FROM keys WHERE key_id = ?', 'player01')).replaced_at, null);
		clock = t0 + 86400;
		code = await newCode();
		r = await link(code, ['player01', 'player02', 'player03'], clock - 60);
		assert.equal(r.status, 'linked', `the old key still counts: ${r.message}`);
		clock = rot.cert_from - 1;
		assert.equal((await keys({ key_id: 'player01r', renew: true })).reason, 'too-early');
		// Its first certificate replaces the old key, which gets no new certificate after that.
		clock = rot.cert_from;
		const rotCert = await keys({ key_id: 'player01r', renew: true });
		assert.equal(rotCert.status, 'ok', rotCert.message);
		assert.equal(rotCert.replaced, 'player01');
		assert.equal((await row('SELECT replaced_at FROM keys WHERE key_id = ?', 'player01')).replaced_at, rot.cert_from);
		const renewOld = await keys({ key_id: 'player01', renew: true });
		assert.deepEqual([renewOld.http, renewOld.reason], [409, 'replaced']);
		clock += 60;
		code = await newCode();
		assert.ok(await addonDraws(rotCert.cert, code, clock));
		r = await link(code, ['player01r', 'player02', 'player03'], clock - 30);
		assert.equal(r.status, 'linked', `the new key counts at once: ${r.message}`);

		// A second new key for an owner whose first never got a certificate replaces it at once.
		clock = t0;
		assert.equal((await register('fresh0003', oldOwner(3))).status, 'ok');
		assert.equal((await register('fresh0004', oldOwner(3))).reason, 'owner-has-key');
		assert.equal((await register('fresh0005', oldOwner(3), { replace: true })).status, 'ok');
		assert.equal((await row('SELECT replaced_at FROM keys WHERE key_id = ?', 'fresh0003')).replaced_at, t0);
		clock = expectFrom(t0);
		assert.equal((await keys({ key_id: 'fresh0003', renew: true })).reason, 'replaced');
		assert.equal((await keys({ key_id: 'fresh0005', renew: true })).status, 'ok');
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

	test('Discord unreachable (fetch throws): the code is released, and the watcher\'s other links go on', async () => {
		await setup();
		discord.fail = true;
		const r = await submit(B1.bundle, USER_C);
		assert.equal(r.http, 200);
		assert.equal(r.status, 'error');
		assert.equal(r.reason, 'discord');
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null, 'the code is not left used');
		assert.equal(await row('SELECT 1 AS x FROM members WHERE character = ?', B1.requester), null);
		assert.ok(logged.some((l) => l.includes('fetch failed')));
		const res = await call('POST', '/api/link/inbox', { body: { bundles: [B1.bundle, B3.bundle] }, origin: null, headers: admin });
		assert.equal(res.status, 200);
		assert.deepEqual((await res.json()).results.map((x) => x.reason), ['discord', 'discord']);
		discord.fail = false;
		assert.equal((await submit(B1.bundle, USER_C)).status, 'linked');
	});

	test('D1 fails to record the link: the claim is released and the same link works again', async () => {
		await setup();
		const batch = env.DB.batch;
		env.DB.batch = async () => {
			throw new Error('D1_ERROR: storage unavailable');
		};
		const r = await submit(B1.bundle, USER_C);
		assert.equal(r.status, 'error');
		assert.equal(r.reason, 'server');
		assert.equal((await row('SELECT used FROM codes WHERE r = ?', B1.R)).used, null);
		assert.ok(logged.some((l) => l.includes('could not record the link')));
		env.DB.batch = batch;
		const again = await submit(B1.bundle, USER_C);
		assert.equal(again.status, 'linked', again.message);
		assert.equal((await row('SELECT discord_id FROM members WHERE character = ?', B1.requester)).discord_id, USER_C.id);
	});

	test('a character linked again moves to the new account; the old one loses the role if it has no other', async () => {
		await setup();
		await env.DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
			.bind(B1.requester, '500000000000000001', 'Olympus II', 'Alliance', '1111111111', 1780000000)
			.run();
		assert.equal((await submit(B1.bundle, USER_C)).status, 'linked');
		assert.equal((await row('SELECT discord_id FROM members WHERE character = ?', B1.requester)).discord_id, USER_C.id);
		assert.deepEqual(discord.calls.map((c) => c.method), ['PUT', 'DELETE']);
		assert.match(discord.calls[1].url, /members\/500000000000000001\/roles\//);
	});

	test('the page may submit 10 times an hour per account', async () => {
		await setup();
		for (let i = 0; i < LINK.SUBMITS_PER_HOUR; i++) assert.equal((await submit('OLB5~bad', USER_C)).reason, 'format');
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
		const bundles = [
			{ R: B1.R, bundle: B1.bundle, from: 'Some Player-ClassicBetaPvP', t: 1799990130 },
			{ R: B3.R, bundle: B3.bundle, from: 'Tëst Plâyer-ClassicBetaPvP', t: 1799990310 },
			{ R: 'AAAAAAAAAA', bundle: B1.bundle, from: 'Some Player-ClassicBetaPvP', t: 1799990131 },
			{ R: 'BBBBBBBBBB', bundle: 'OLB5~broken', from: 'x', t: 1 },
			B1.bundle,
		];
		res = await call('POST', '/api/link/inbox', { body: { bundles }, origin: null, headers: admin });
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
		assert.equal(log.received, 1799990310);
		res = await call('POST', '/api/link/inbox', { body: { bundles: new Array(LINK.MAX_BUNDLES + 1).fill('x') }, origin: null, headers: admin });
		assert.equal(res.status, 400);
	});

	test('a gateway bot gets a member\'s code with the admin token', async () => {
		await setup();
		clock = Math.floor(realNow() / 1000);
		let res = await call('POST', '/api/link/bot-code', { body: { id: '623456789012345678', username: 'bot.user' }, origin: null });
		assert.equal(res.status, 401);
		res = await call('POST', '/api/link/bot-code', { body: { id: '623456789012345678', username: 'bot.user' }, origin: null, headers: admin });
		const body = await res.json();
		assert.ok(parseToken(body.token).ok);
		assert.match(body.reply, /\/oly discord OLC2\./);
		assert.match(body.reply, /not on stream/);
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
		// /verify (the bot's command) answers the same: the same fresh code for the same member.
		const verifyReply = await (await send({ type: 2, data: { name: 'verify' }, member: { user: { id: '723456789012345678', username: 'slash.user' } } })).json();
		assert.equal(parseToken(verifyReply.data.content.split('\n').find((l) => l.startsWith('/oly discord '))).token.raw, parsed.token.raw);
		assert.equal(verifyReply.data.flags, 64, 'only the member sees it');
	});

	test('POST /api/link/proof: the static page\'s route (GitHub Pages), with CORS, the player\'s Discord sign-in, and the role', async () => {
		await setup();
		env.LINK_ORIGIN = 'https://dnl-gentile.github.io';
		env.DISCORD_CLIENT_ID = '300000000000000003';
		const roleStub = globalThis.fetch;
		globalThis.fetch = async (url, init) => {
			if (String(url) === 'https://discord.com/api/v10/oauth2/@me') {
				const ok = init.headers.Authorization === 'Bearer token-of-some-player-0001';
				if (!ok) return new Response('{"message": "401: Unauthorized"}', { status: 401 });
				return Response.json({ application: { id: env.DISCORD_CLIENT_ID }, scopes: ['identify'], expires: '2027-06-01T00:00:00+00:00', user: { id: USER_C.id, username: USER_C.username } });
			}
			return roleStub(url, init);
		};
		const at = (method, init = {}) => handleLink(new Request(`${ORIGIN}/api/link/proof`, { method, ...init }), env, {});
		const pre = await at('OPTIONS', { headers: { Origin: env.LINK_ORIGIN, 'Access-Control-Request-Method': 'POST' } });
		assert.equal(pre.status, 204);
		assert.equal(pre.headers.get('Access-Control-Allow-Origin'), env.LINK_ORIGIN);
		const post = (token, origin = env.LINK_ORIGIN) =>
			at('POST', { headers: { Origin: origin, 'Content-Type': 'application/json' }, body: JSON.stringify({ text: B1.url, discordToken: token }) });
		assert.equal((await post('token-of-some-player-0001', ORIGIN)).status, 403, 'the Worker\'s own origin is not the page\'s');
		let res = await post('token-of-nobody-at-all-000');
		assert.deepEqual([res.status, (await res.json()).reason], [401, 'login']);
		res = await post('token-of-some-player-0001');
		assert.equal(res.status, 200);
		assert.equal(res.headers.get('Access-Control-Allow-Origin'), env.LINK_ORIGIN);
		const r = await res.json();
		assert.deepEqual([r.status, r.reason, r.character, r.username], ['linked', 'linked', B1.requester, USER_C.username]);
		assert.deepEqual(discord.calls.map((c) => [c.method, c.url]), [['PUT', `https://discord.com/api/v10/guilds/${env.GUILD_ID}/members/${USER_C.id}/roles/${env.ROLE_ID}`]]);
	});
});
