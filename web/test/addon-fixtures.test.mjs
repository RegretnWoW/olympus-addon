// The addon's own shared vectors (tests/fixtures/ed25519-vectors.txt and link-sample.txt, made
// by tests/fixtures/make-link-vectors.py and Olympus/Ed25519.lua): node:crypto signs them byte
// for byte, and the page and the reference Worker read, verify and accept the addon's sample
// code and links. Skipped where those files are not in this checkout (the addon's branch adds
// them); OLYMPUS_ADDON_FIXTURES=<folder> points at another copy of them.

import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, test } from 'node:test';
import { parseToken, parseBundle, signedMessage, checkBundle } from '../public/core.js';
import { acceptBundle, parseBundle as workerParse } from '../worker/link-worker.js';
import { REPO, makeD1, publicHexOf, sign, verify } from './helpers.mjs';

const DIR = process.env.OLYMPUS_ADDON_FIXTURES || join(REPO, 'tests', 'fixtures');
const VECTORS = join(DIR, 'ed25519-vectors.txt');
const SAMPLE = join(DIR, 'link-sample.txt');
const skipVectors = existsSync(VECTORS) ? false : `no ${VECTORS} in this checkout`;
const skipSample = existsSync(SAMPLE) ? false : `no ${SAMPLE} in this checkout`;
const hex = (h) => Buffer.from(h, 'hex');
const seedHex = (b64) => Buffer.from(b64, 'base64url').toString('hex');

test('the addon\'s Ed25519 vectors: the same keys and signatures here', { skip: skipVectors }, () => {
	const lines = readFileSync(VECTORS, 'utf8').split('\n').filter((l) => l.trim() && !l.startsWith('#'));
	assert.ok(lines.length >= 5, 'expected vectors');
	for (const line of lines) {
		const [name, seed, pub, msg, sig] = line.trim().split(/\s+/);
		const message = msg === '-' ? Buffer.alloc(0) : hex(msg);
		assert.equal(publicHexOf(seed), pub, name);
		assert.equal(sign(seed, message).toString('hex'), sig, name);
		assert.ok(verify(pub, message, hex(sig)), name);
	}
});

function sample() {
	const out = {};
	for (const line of readFileSync(SAMPLE, 'utf8').split('\n')) {
		const m = /^([a-z0-9_]+)=(.*)$/.exec(line.trim());
		if (m) out[m[1]] = m[2];
	}
	return out;
}

test('the addon\'s sample code and links read and verify on the page', { skip: skipSample }, () => {
	const s = sample();
	assert.equal(publicHexOf(seedHex(s.backend_seed)), s.backend_pub);
	for (const key of ['token_a', 'token_c']) {
		const t = parseToken(s[key]);
		assert.ok(t.ok, `${key}: ${t.error}`);
		assert.equal(t.token.exp, Number(s.token_exp));
		assert.ok(verify(s.backend_pub, Buffer.from(t.token.payload, 'ascii'), Buffer.from(t.token.sig, 'base64url')), key);
	}
	for (const key of ['bundle_council', 'bundle_players']) {
		const parsed = parseBundle(s[key]);
		assert.ok(parsed.ok, `${key}: ${parsed.error}`);
		assert.ok(workerParse(s[key]).ok, key);
		assert.ok(checkBundle(s[key], parseToken(s.token_c).token.R).matchesCode, key);
		for (const p of parsed.bundle.proofs) {
			const pub = s[`confirmer_${p.keyId}_pub`];
			assert.equal(publicHexOf(seedHex(s[`confirmer_${p.keyId}_seed`])), pub, p.keyId);
			assert.ok(verify(pub, Buffer.from(signedMessage(parsed.bundle, p), 'utf8'), Buffer.from(p.sig, 'base64url')), `${key} ${p.keyId}`);
		}
	}
});

// The Worker, D1 on node:sqlite, the addon's sample keys registered as the guide says.
let realFetch;
let realNow;
beforeEach(() => {
	realFetch = globalThis.fetch;
	realNow = Date.now;
	globalThis.fetch = async () => new Response(null, { status: 204 }); // Discord takes the role
});
afterEach(() => {
	globalThis.fetch = realFetch;
	Date.now = realNow;
});

test('the reference Worker links the addon\'s sample links', { skip: skipSample }, async (t) => {
	const DB = await makeD1();
	if (!DB) return t.skip('node:sqlite is not available in this Node');
	const s = sample();
	const exp = Number(s.token_exp);
	const env = { DB, GUILD_ID: '300000000000000001', ROLE_ID: '300000000000000002', DISCORD_BOT_TOKEN: 'x' };
	const player = { id: '200000000000000009', username: parseToken(s.token_c).token.username };
	const owners = { council01: '100000000000000201', player01: '100000000000000202', player02: '100000000000000203', player03: '100000000000000204' };
	const load = async (mode) => {
		await DB.exec('DELETE FROM codes; DELETE FROM keys; DELETE FROM members; DELETE FROM used;');
		const token = parseToken(s[mode === 'c' ? 'token_c' : 'token_a']).token;
		await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(token.R, player.id, token.username, mode, exp - 86400, exp, token.raw, 'discord')
			.run();
		for (const [keyId, owner] of Object.entries(owners)) {
			const kind = keyId.startsWith('council') ? 'c' : 'p';
			await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, kind, bootstrap, created) VALUES (?, ?, ?, ?, ?, ?)')
				.bind(keyId, s[`confirmer_${keyId}_pub`], owner, kind, kind === 'c' ? 1 : 0, exp - 60 * 86400)
				.run();
		}
		// Each drawn player's confirmer character is one of their own linked characters.
		const players = parseBundle(s.bundle_players).bundle.proofs;
		for (const p of players) {
			await DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
				.bind(p.confirmer, owners[p.keyId], 'Olympus II', 'Alliance', '0000000000', exp - 30 * 86400)
				.run();
		}
	};
	Date.now = () => (exp - 9000) * 1000; // a while after the sample's proofs were signed

	await load('c');
	let r = await acceptBundle(env, s.bundle_council, { userId: player.id });
	assert.equal(r.status, 'linked', r.message);
	r = await acceptBundle(env, s.bundle_players, { userId: player.id });
	assert.notEqual(r.reason, 'linked'); // the code is used now

	await load('c');
	r = await acceptBundle(env, s.bundle_players, { userId: player.id });
	assert.equal(r.reason, 'not-enough', 'a code in mode c takes no player proofs');

	await load('a');
	r = await acceptBundle(env, s.bundle_players, { userId: player.id });
	assert.equal(r.status, 'linked', r.message);
	assert.deepEqual(r.characters, [parseBundle(s.bundle_players).bundle.requester]);
});
