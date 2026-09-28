// The addon's own shared vectors (tests/fixtures/ed25519-vectors.txt and link-sample.txt, made
// by tests/fixtures/make-link-vectors.py and Olympus/Ed25519.lua): node:crypto signs them byte
// for byte, the keys made from the same throwaway labels are the ones in vectors.json, and the
// page and the reference Worker read, verify and accept the addon's sample codes, certificates
// and links. They run wherever those files are in the checkout (the repository once both
// branches are in); OLYMPUS_ADDON_FIXTURES=<folder> points at another copy of them.

import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, test } from 'node:test';
import { parseToken, parseBundle, signedMessage, checkBundle, linkTag, buildBundle, utf8Length } from '../public/core.js';
import { acceptBundle, parseBundle as workerParse, parseCertificate, verifyCertificate } from '../worker/link-worker.js';
import { REPO, makeD1, publicHexOf, sign, verify, vectors } from './helpers.mjs';

const DIR = process.env.OLYMPUS_ADDON_FIXTURES || join(REPO, 'tests', 'fixtures');
const VECTORS = join(DIR, 'ed25519-vectors.txt');
const SAMPLE = join(DIR, 'link-sample.txt');
const skipVectors = existsSync(VECTORS) ? false : `no ${VECTORS} in this checkout`;
const skipSample = existsSync(SAMPLE) ? false : `no ${SAMPLE} in this checkout`;
const hex = (h) => Buffer.from(h, 'hex');
const seedHex = (b64) => Buffer.from(b64, 'base64url').toString('hex');

test('the addon\'s Ed25519 vectors: the same keys and signatures here, the v5 texts read as here', { skip: skipVectors }, async () => {
	const lines = readFileSync(VECTORS, 'utf8').split('\n').filter((l) => l.trim() && !l.startsWith('#'));
	assert.ok(lines.length >= 5, 'expected vectors');
	let confirmations = 0;
	for (const line of lines) {
		const [name, seed, pub, msg, sig] = line.trim().split(/\s+/);
		const message = msg === '-' ? Buffer.alloc(0) : hex(msg);
		assert.equal(publicHexOf(seed), pub, name);
		assert.equal(sign(seed, message).toString('hex'), sig, name);
		assert.ok(verify(pub, message, hex(sig)), name);
		// The Olympus Link texts among them (the others are only bytes to sign) read as this side
		// reads them: a v5 confirmation, a code, a certificate.
		const text = message.toString('utf8');
		const signed = `${text}.${hex(sig).toString('base64url')}`;
		const f = text.split('~');
		if (f[0] === 'OLY4' && f.length === 11) {
			confirmations++;
			const b = { requester: f[1], guild: f[2], faction: f[4], nonce: f[5], R: f[6], tag: f[7] };
			const p = { gv: f[3], issued: f[8], keyId: f[9], confirmer: f[10], sig: hex(sig).toString('base64url') };
			assert.equal(signedMessage(b, p), text, name);
			const parsed = parseBundle(buildBundle({ ...b, proofs: [p] }));
			assert.ok(parsed.ok, `${name}: ${parsed.error}`);
		} else if (text.startsWith('OLC2.')) {
			assert.ok(parseToken(signed).ok, `${name}: ${parseToken(signed).error}`);
		} else if (text.startsWith('OLK1.')) {
			assert.ok(await verifyCertificate(pub, signed), `${name}: a certificate`);
		}
	}
	assert.ok(confirmations >= 1, 'a confirmation in the v5 format (OLY4 with gv and tag) among the vectors');
});

function sample() {
	const out = {};
	for (const line of readFileSync(SAMPLE, 'utf8').split('\n')) {
		const m = /^([A-Za-z0-9_]+)=(.*)$/.exec(line.trim());
		if (m) out[m[1]] = m[2];
	}
	return out;
}

// What the sample holds, found by its shape: the backend key, the confirmers' keys
// (confirmer_<id>_seed / _pub), and every code (OLC2), certificate (OLK1) and link (OLB4).
function contents(s) {
	const values = Object.entries(s);
	const pubs = {};
	for (const [k, v] of values) {
		const m = /^confirmer_([a-z0-9]{6,16})_pub$/.exec(k);
		if (m) pubs[m[1]] = v;
	}
	return {
		backend: s.backend_pub,
		pubs,
		seeds: Object.fromEntries(values.filter(([k]) => /^confirmer_[a-z0-9]+_seed$/.test(k)).map(([k, v]) => [k.slice(10, -5), v])),
		tokens: values.filter(([, v]) => v.startsWith('OLC')).map(([k, v]) => ({ name: k, ...parseToken(v) })),
		certs: values.filter(([, v]) => v.startsWith('OLK')).map(([k, v]) => ({ name: k, text: v })),
		bundles: values.filter(([, v]) => v.startsWith('OLB')).map(([k, v]) => ({ name: k, text: v })),
	};
}

// The code a link was made with: its R, and its tag made from that code's signature.
async function codeOf(c, b) {
	for (const t of c.tokens) {
		if (t.ok && t.token.R === b.R && (await linkTag(t.token.sig, b.requester)) === b.tag) return t.token;
	}
	return null;
}

test('the addon\'s sample codes, certificates and links read and verify here, with the same keys', { skip: skipSample }, async () => {
	const s = sample();
	const c = contents(s);
	// The same throwaway labels make the same keys on both sides.
	assert.equal(c.backend, vectors.backend.public_hex, 'backend_pub: the key of the label "backend"');
	if (s.backend_seed) assert.equal(publicHexOf(seedHex(s.backend_seed)), c.backend);
	for (const [id, pub] of Object.entries(c.pubs)) {
		if (c.seeds[id]) assert.equal(publicHexOf(seedHex(c.seeds[id])), pub, id);
		const ours = vectors.keys.find((k) => k.key_id === id);
		if (ours) assert.equal(pub, ours.public_hex, `${id}: the key of the label "${id}"`);
	}
	assert.ok(c.tokens.length >= 1, 'the sample has a code');
	for (const t of c.tokens) {
		assert.ok(t.ok, `${t.name}: ${t.error}`);
		assert.ok(verify(c.backend, Buffer.from(t.token.payload, 'ascii'), Buffer.from(t.token.sig, 'base64url')), t.name);
		if (t.token.mode === 'c') assert.equal(t.token.T, '00000000', `${t.name}: T of a mode c code`);
		assert.ok(utf8Length(`/oly discord ${t.token.raw}`) < 255);
	}
	for (const x of c.certs) {
		const cert = await verifyCertificate(c.backend, x.text);
		assert.ok(cert, `${x.name}: signed by the backend key`);
		if (c.pubs[cert.keyId]) assert.equal(cert.publicHex, c.pubs[cert.keyId], `${x.name}: the certificate names the key's own public half`);
		assert.ok(utf8Length(`/oly discord cert ${x.text}`) < 255 && utf8Length(`DV~1~${x.text}`) < 255, x.name);
	}
	let made = 0;
	for (const x of c.bundles) {
		const parsed = parseBundle(x.text);
		assert.ok(parsed.ok, `${x.name}: ${parsed.error}`);
		assert.ok(workerParse(x.text).ok, x.name);
		const b = parsed.bundle;
		// Made with a sample code: its tag is SHA-256(<that code's signature>~<requester>). One
		// made without (an impostor's) still reads; the Worker refuses it (below).
		if (await codeOf(c, b)) made++;
		assert.ok(c.tokens.some((t) => t.ok && t.token.R === b.R), `${x.name}: a sample code has its R`);
		assert.ok(checkBundle(x.text, b.R).matchesCode, x.name);
		for (const p of b.proofs) {
			const pub = c.pubs[p.keyId] || (c.certs.map((k) => parseCertificate(k.text)).find((k) => k && k.keyId === p.keyId) || {}).publicHex;
			assert.ok(pub, `${x.name}: the key ${p.keyId} is in the sample`);
			assert.ok(verify(pub, Buffer.from(signedMessage(b, p), 'utf8'), Buffer.from(p.sig, 'base64url')), `${x.name} ${p.keyId}`);
		}
	}
	assert.ok(made >= 1, 'the sample has a link made with one of its codes');
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

test('the reference Worker links the addon\'s sample links, and holds each to its code', { skip: skipSample }, async (t) => {
	const DB = await makeD1();
	if (!DB) return t.skip('node:sqlite is not available in this Node');
	const s = sample();
	const c = contents(s);
	const player = '200000000000000009';
	const certs = Object.fromEntries(c.certs.map((x) => parseCertificate(x.text)).filter(Boolean).map((x) => [x.keyId, x]));
	const ids = [...new Set([...Object.keys(c.pubs), ...Object.keys(certs)])];
	const owner = (id) => String(100000000000000200n + BigInt(ids.indexOf(id) + 1));
	const load = async (token, b) => {
		await DB.exec('DELETE FROM codes; DELETE FROM keys; DELETE FROM members; DELETE FROM used;');
		await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(token.R, player, token.username, token.mode, token.T, token.exp - 86400, token.exp, token.raw, 'discord')
			.run();
		for (const id of ids) {
			const kind = certs[id] ? certs[id].tier : id.startsWith('council') ? 'c' : 'p';
			await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?)')
				.bind(id, c.pubs[id] || certs[id].publicHex, owner(id), kind, kind === 'c' ? 1 : 0, token.exp - 60 * 86400, certs[id] ? certs[id].exp : token.exp + 86400)
				.run();
		}
		// Each drawn player's confirmer character is one of their own linked characters.
		for (const p of b.proofs) {
			await DB.prepare('INSERT OR IGNORE INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)')
				.bind(p.confirmer, owner(p.keyId), b.guild, b.faction, '0000000000', token.exp - 30 * 86400)
				.run();
		}
		Date.now = () => (Math.max(...b.proofs.map((p) => p.issued)) + 60) * 1000; // a minute after the last proof
	};
	for (const x of c.bundles) {
		const b = parseBundle(x.text).bundle;
		const token = await codeOf(c, b);
		if (!token) {
			// Not made with the command of any code of the sample (an impostor who saw R): refused
			// whatever the policy, the code unused.
			for (const t of c.tokens.filter((y) => y.ok && y.token.R === b.R)) {
				await load(t.token, b);
				const r = await acceptBundle({ DB, LINK_GUILD_POLICY: 'claimed' }, x.text, { userId: player });
				assert.equal(r.reason, 'tag', `${x.name}: ${r.message}`);
				assert.equal((await DB.prepare('SELECT used FROM codes WHERE r = ?').bind(b.R).first()).used, null);
			}
			continue;
		}
		const checked = b.proofs.some((p) => p.gv === 'r' || p.gv === 'w');
		// "claimed": the addon's sample links are good links.
		await load(token, b);
		let r = await acceptBundle({ DB, LINK_GUILD_POLICY: 'claimed' }, x.text, { userId: player });
		assert.equal(r.status, 'linked', `${x.name}: ${r.message}`);
		assert.deepEqual(r.characters, [b.requester]);
		// "verified" (the default): only with a confirmer who checked the guild in game.
		await load(token, b);
		r = await acceptBundle({ DB }, x.text, { userId: player });
		if (checked) assert.equal(r.status, 'linked', `${x.name}: ${r.message}`);
		else assert.equal(r.reason, 'guild-unverified', `${x.name}: ${r.message}`);
		// The same proofs under another tag: not this code's link.
		await load(token, b);
		const other = x.text.replace(`~${b.tag}~`, `~${b.tag === '0'.repeat(16) ? '1'.repeat(16) : '0'.repeat(16)}~`);
		r = await acceptBundle({ DB, LINK_GUILD_POLICY: 'claimed' }, other, { userId: player });
		assert.equal(r.reason, 'tag', `${x.name}: ${r.message}`);
	}
	// A mode c code takes no player proofs.
	const isPlayer = (p) => !(certs[p.keyId] ? certs[p.keyId].tier === 'c' : p.keyId.startsWith('council'));
	let players = null;
	for (const x of c.bundles) {
		const b = parseBundle(x.text).bundle;
		if (!players && b.proofs.every(isPlayer) && (await codeOf(c, b))) players = b;
	}
	if (players) {
		const token = await codeOf(c, players);
		await load({ ...token, mode: 'c', T: '00000000' }, players);
		const r = await acceptBundle({ DB, LINK_GUILD_POLICY: 'claimed' }, buildBundle(players), { userId: player });
		assert.equal(r.reason, 'not-enough', 'a code in mode c takes no player proofs');
	}
});
