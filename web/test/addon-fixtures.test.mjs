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
import { parseToken, parseBundle, signedMessage, checkBundle, linkTag, buildBundle, utf8Length, proofCertificate, drawThreshold, drawPrefix, isDrawn } from '../public/core.js';
import { acceptBundle, parseBundle as workerParse, parseCertificate, verifyCertificate, councilCertificate, thresholdOf, drawLimit } from '../worker/link-worker.js';
import { readInbox } from '../tools/read-inbox.mjs';
import { REPO, makeD1, publicHexOf, sign, verify, vectors } from './helpers.mjs';

const DIR = process.env.OLYMPUS_ADDON_FIXTURES || join(REPO, 'tests', 'fixtures');
const VECTORS = join(DIR, 'ed25519-vectors.txt');
const SAMPLE = join(DIR, 'link-sample.txt');
const DRAW = join(DIR, 'link-draw.txt');
const INBOX = join(DIR, 'link-inbox.lua');
const skipVectors = existsSync(VECTORS) ? false : `no ${VECTORS} in this checkout`;
const skipSample = existsSync(SAMPLE) ? false : `no ${SAMPLE} in this checkout`;
const hex = (h) => Buffer.from(h, 'hex');
const seedHex = (b64) => Buffer.from(b64, 'base64url').toString('hex');

test('the addon\'s Ed25519 vectors: the same keys and signatures here, the texts read as here (the addon\'s own council authority certificate too)', { skip: skipVectors }, async () => {
	const lines = readFileSync(VECTORS, 'utf8').split('\n').filter((l) => l.trim() && !l.startsWith('#'));
	assert.ok(lines.length >= 5, 'expected vectors');
	let confirmations = 0;
	const certificates = [];
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
			// (Carried with a certificate for its key: its fields well formed, whoever signed it.)
			const p = { gv: f[3], issued: f[8], keyId: f[9], confirmer: f[10], sig: hex(sig).toString('base64url'), pub: hex(pub).toString('base64url'), tier: 'c', certExp: 1830000000, certSig: hex(sig).toString('base64url') };
			assert.equal(signedMessage(b, p), text, name);
			const parsed = parseBundle(buildBundle({ ...b, proofs: [p] }));
			assert.ok(parsed.ok, `${name}: ${parsed.error}`);
		} else if (text.startsWith('OLC2.')) {
			assert.ok(parseToken(signed).ok, `${name}: ${parseToken(signed).error}`);
		} else if (text.startsWith('OLK2.')) {
			// Signed by the line's key: the backend's, or the council authority's (python-ca-cert, and
			// lua-ca-cert, which the addon's own council authority code made in tests/run.lua).
			const c = await verifyCertificate(pub, signed);
			assert.ok(c, `${name}: a certificate`);
			if (c.tier === 'c' && /^[0-9a-f]{12}$/.test(c.keyId)) assert.ok(await councilCertificate({ LINK_CA_PUBLIC: pub }, c), `${name}: the council authority's`);
			certificates.push(name);
		}
	}
	assert.ok(confirmations >= 1, 'a confirmation in the v5 format (OLY4 with gv and tag) among the vectors');
	assert.ok(certificates.includes('lua-ca-cert'), 'the certificate the addon\'s council authority made (Lua), verified here with node:crypto');
	assert.ok(certificates.includes('python-ca-cert'), 'and Python\'s');
});

// The draw as the addon's tests hold it (made by make-link-vectors.py, applied by Link.Drawn in
// tests/run.lua): one rule everywhere, T the place at index M of the sorted places, the M lowest drawn.
test('the addon\'s draw (tests/fixtures/link-draw.txt) is the Worker\'s and the page\'s: the same T, the M lowest drawn', { skip: existsSync(DRAW) ? false : `no ${DRAW} in this checkout` }, async () => {
	const cases = {};
	for (const line of readFileSync(DRAW, 'utf8').split('\n')) {
		let m = /^case (\S+) (\S+) (\d+) (\d+) ([0-9a-f]{8})$/.exec(line);
		if (m) cases[m[1]] = { R: m[2], n: Number(m[3]), M: Number(m[4]), T: m[5], keys: [] };
		m = /^key (\S+) (\S+) ([0-9a-f]{8}) ([01])$/.exec(line);
		if (m) cases[m[1]].keys.push({ id: m[2], place: m[3], drawn: m[4] === '1' });
	}
	assert.ok(Object.keys(cases).length >= 2);
	for (const [name, c] of Object.entries(cases)) {
		const ids = c.keys.map((k) => k.id);
		assert.equal(ids.length, c.n, name);
		assert.equal(drawLimit(c.n), c.M, name);
		assert.equal(await thresholdOf(c.R, ids), c.T, `${name}: the Worker's T`);
		assert.equal(await drawThreshold(c.R, ids), c.T, `${name}: the page's T`);
		for (const k of c.keys) {
			assert.equal(await drawPrefix(c.R, k.id), k.place, `${name} ${k.id}`);
			assert.equal(isDrawn(k.place, c.T), k.drawn, `${name} ${k.id}`);
		}
		assert.equal(c.keys.filter((k) => k.drawn).length, Math.min(c.n, c.M), `${name}: the M lowest`);
	}
});

function sample() {
	const out = {};
	for (const line of readFileSync(SAMPLE, 'utf8').split('\n')) {
		const m = /^([A-Za-z0-9_]+)=(.*)$/.exec(line.trim());
		if (m) out[m[1]] = m[2];
	}
	return out;
}

// What the sample holds, found by its shape: the backend key, the council authority's, the
// confirmers' keys (confirmer_<id>_seed / _pub), and every code (OLC2), certificate (OLK2) and link
// (OLB5).
function contents(s) {
	const values = Object.entries(s);
	const pubs = {};
	for (const [k, v] of values) {
		const m = /^confirmer_([a-z0-9]{6,16})_pub$/.exec(k);
		if (m) pubs[m[1]] = v;
	}
	return {
		backend: s.backend_pub,
		ca: s.ca_pub,
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
	const byKey = {};
	let authority = 0;
	for (const x of c.certs) {
		const cert = (await verifyCertificate(c.backend, x.text)) || (await councilCertificate({ LINK_CA_PUBLIC: c.ca }, parseCertificate(x.text)));
		assert.ok(cert, `${x.name}: signed by the backend key, or a councillor's by the council authority`);
		if (!(await verifyCertificate(c.backend, x.text))) authority++;
		if (c.pubs[cert.keyId]) assert.equal(cert.publicHex, c.pubs[cert.keyId], `${x.name}: the certificate names the key's own public half`);
		assert.ok(utf8Length(`/oly discord cert ${x.text}`) < 255 && utf8Length(`DV~1~${x.text}`) < 255 && utf8Length(`DE~${x.text}`) < 255, x.name);
		byKey[cert.keyId] = x.text;
	}
	assert.ok(authority >= 1, 'a certificate of the council authority in the sample');
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
			// The certificate it carries is its key's, for its confirmer, as the sample holds it.
			assert.equal(proofCertificate(p), byKey[p.keyId], `${x.name} ${p.keyId}: its certificate`);
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
	// A councillor's key the council authority certified is never registered: the Worker takes it
	// on the authority's word (LINK_CA_PUBLIC).
	const byAuthority = new Set();
	for (const [id, cert] of Object.entries(certs)) if (await councilCertificate({ LINK_CA_PUBLIC: c.ca }, cert)) byAuthority.add(id);
	assert.ok(byAuthority.size >= 1);
	// ...for the councillors the bot's keeper lists (LINK_COUNCIL_CHARACTERS: none when left out).
	const LINK_COUNCIL_CHARACTERS = [...byAuthority].map((id) => certs[id].character).join(', ');
	const ids = [...new Set([...Object.keys(c.pubs), ...Object.keys(certs)])].filter((id) => !byAuthority.has(id));
	const owner = (id) => String(100000000000000200n + BigInt(ids.indexOf(id) + 1));
	const load = async (token, b) => {
		await DB.exec('DELETE FROM codes; DELETE FROM keys; DELETE FROM members; DELETE FROM used; DELETE FROM council_keys;');
		await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(token.R, player, token.username, token.mode, token.T, token.exp - 86400, token.exp, token.raw, 'discord')
			.run();
		for (const id of ids) {
			const kind = certs[id] ? certs[id].tier : id.startsWith('council') ? 'c' : 'p';
			// Registered for the character its certificate names (the one that confirms with it).
			await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, character, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(id, c.pubs[id] || certs[id].publicHex, owner(id), certs[id].character, kind, kind === 'c' ? 1 : 0, token.exp - 60 * 86400, certs[id] ? certs[id].exp : token.exp + 86400)
				.run();
		}
		// Each drawn player's confirmer character is one of their own linked characters.
		for (const p of b.proofs.filter((x) => !byAuthority.has(x.keyId))) {
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
		let r = await acceptBundle({ DB, LINK_GUILD_POLICY: 'claimed', LINK_CA_PUBLIC: c.ca, LINK_COUNCIL_CHARACTERS }, x.text, { userId: player });
		assert.equal(r.status, 'linked', `${x.name}: ${r.message}`);
		assert.deepEqual(r.characters, [b.requester]);
		// "verified" (the default): only with a confirmer who checked the guild in game.
		await load(token, b);
		r = await acceptBundle({ DB, LINK_CA_PUBLIC: c.ca, LINK_COUNCIL_CHARACTERS }, x.text, { userId: player });
		if (checked) assert.equal(r.status, 'linked', `${x.name}: ${r.message}`);
		else assert.equal(r.reason, 'guild-unverified', `${x.name}: ${r.message}`);
		// The same proofs under another tag: not this code's link.
		await load(token, b);
		const other = x.text.replace(`~${b.tag}~`, `~${b.tag === '0'.repeat(16) ? '1'.repeat(16) : '0'.repeat(16)}~`);
		r = await acceptBundle({ DB, LINK_GUILD_POLICY: 'claimed', LINK_CA_PUBLIC: c.ca, LINK_COUNCIL_CHARACTERS }, other, { userId: player });
		assert.equal(r.reason, 'tag', `${x.name}: ${r.message}`);
		// A councillor's key of the council authority's: not without LINK_CA_PUBLIC, nor without
		// the councillor on LINK_COUNCIL_CHARACTERS.
		if (b.proofs.every((p) => byAuthority.has(p.keyId))) {
			for (const env of [{ LINK_COUNCIL_CHARACTERS }, { LINK_CA_PUBLIC: c.ca }]) {
				await load(token, b);
				r = await acceptBundle({ DB, LINK_GUILD_POLICY: 'claimed', ...env }, x.text, { userId: player });
				assert.equal(r.reason, 'not-enough', `${x.name}: ${r.message}`);
			}
		}
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

test('the watcher\'s inbox as the addon writes it (tests/fixtures/link-inbox.lua) is what the keeper\'s tool reads and the Worker parses', { skip: existsSync(INBOX) && existsSync(SAMPLE) ? false : `no ${INBOX} in this checkout` }, () => {
	const { bundles, skipped } = readInbox(INBOX);
	assert.deepEqual(skipped, []);
	assert.equal(bundles.length, 2);
	const s = sample();
	assert.deepEqual(bundles.map((b) => b.bundle).sort(), [s.bundle_council, s.bundle_impostor].sort());
	for (const b of bundles) {
		assert.ok(parseBundle(b.bundle).ok && workerParse(b.bundle).ok, b.R);
		assert.equal(b.R, parseBundle(b.bundle).bundle.R);
	}
});
