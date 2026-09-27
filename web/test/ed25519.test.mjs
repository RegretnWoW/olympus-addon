// Ed25519 and SHA-512 against the shared vectors, with node:crypto: RFC 8032, NIST, the
// cross-language vectors made by python3 cryptography (web/test/fixtures/make-vectors.py), and
// the signatures the addon's own Lua made (web/test/fixtures/lua-signatures.json).

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import { parseBundle, parseToken, signedMessage } from '../public/core.js';
import { vectors, sign, verify, publicHexOf } from './helpers.mjs';

const hex = (h) => Buffer.from(h, 'hex');

test('RFC 8032 section 7.1: TEST 1, 2, 3 and 1024', () => {
	assert.deepEqual(vectors.rfc8032.map((v) => v.name), ['TEST 1', 'TEST 2', 'TEST 3', 'TEST 1024']);
	for (const v of vectors.rfc8032) {
		assert.equal(publicHexOf(v.seed_hex), v.public_hex, v.name);
		assert.equal(sign(v.seed_hex, hex(v.message_hex)).toString('hex'), v.signature_hex, v.name);
		assert.ok(verify(v.public_hex, hex(v.message_hex), hex(v.signature_hex)), v.name);
	}
	assert.equal(vectors.rfc8032[3].message_hex.length, 2046);
});

test('SHA-512: NIST examples', () => {
	for (const v of vectors.sha512) {
		const msg = v.repeat ? v.repeat.repeat(v.count) : v.message;
		assert.equal(crypto.createHash('sha512').update(msg, 'utf8').digest('hex'), v.digest_hex, v.name);
	}
	assert.equal(vectors.sha512.find((v) => v.name === 'abc').digest_hex.slice(0, 16), 'ddaf35a193617aba');
});

test('cross-language vectors: byte-identical signatures, and Python\'s verify', () => {
	assert.ok(vectors.ed25519.length >= 6);
	for (const v of vectors.ed25519) {
		assert.equal(Buffer.from(v.seed_b64url, 'base64url').toString('hex'), v.seed_hex, v.name);
		assert.equal(v.seed_b64url.length, 43, v.name);
		assert.equal(v.signature_b64url.length, 86, v.name);
		assert.equal(Buffer.from(v.signature_b64url, 'base64url').toString('hex'), v.signature_hex, v.name);
		assert.equal(publicHexOf(v.seed_hex), v.public_hex, v.name);
		if (v.message !== undefined) assert.equal(Buffer.from(v.message, 'utf8').toString('hex'), v.message_hex, v.name);
		assert.equal(sign(v.seed_hex, hex(v.message_hex)).toString('hex'), v.signature_hex, v.name);
		assert.ok(verify(v.public_hex, hex(v.message_hex), hex(v.signature_hex)), v.name);
	}
});

test('rejections: non-canonical S, altered message, signature or key', () => {
	assert.equal(vectors.rejects[0].name, 'non-canonical S (S + L)');
	for (const r of vectors.rejects) assert.equal(verify(r.public_hex, hex(r.message_hex), hex(r.signature_hex)), false, r.name);
	// WebCrypto (what the Worker uses) refuses the same.
	return Promise.all(
		vectors.rejects.map(async (r) => {
			const key = await crypto.webcrypto.subtle.importKey('raw', hex(r.public_hex), { name: 'Ed25519' }, false, ['verify']);
			assert.equal(await crypto.webcrypto.subtle.verify('Ed25519', key, hex(r.signature_hex), hex(r.message_hex)), false, r.name);
		}),
	);
});

test('the backend\'s tokens verify with its public key', () => {
	for (const t of vectors.backend.tokens) {
		const parsed = parseToken(t.token);
		assert.ok(parsed.ok, parsed.error);
		assert.equal(parsed.token.payload, t.payload);
		assert.ok(verify(vectors.backend.public_hex, Buffer.from(t.payload, 'ascii'), Buffer.from(parsed.token.sig, 'base64url')));
		assert.equal(sign(vectors.backend.seed_hex, t.payload).toString('base64url'), t.signature_b64url);
		// Any change to the signed part breaks it.
		const other = t.payload.replace(/\.[ca]$/, (m) => (m === '.c' ? '.a' : '.c'));
		assert.equal(verify(vectors.backend.public_hex, Buffer.from(other, 'ascii'), Buffer.from(parsed.token.sig, 'base64url')), false);
	}
});

test('every proof of the sample bundles verifies with its confirmer key', () => {
	const keys = Object.fromEntries(vectors.keys.map((k) => [k.key_id, k]));
	for (const v of vectors.bundles) {
		const parsed = parseBundle(v.bundle);
		assert.ok(parsed.ok, `${v.name}: ${parsed.error}`);
		const b = parsed.bundle;
		b.proofs.forEach((p, i) => {
			const msg = signedMessage(b, p);
			assert.equal(msg, v.messages[i]);
			assert.ok(verify(keys[p.keyId].public_hex, Buffer.from(msg, 'utf8'), Buffer.from(p.sig, 'base64url')), `${v.name} #${i + 1}`);
			const otherFaction = msg.replace(`~${b.faction}~`, `~${b.faction === 'Horde' ? 'Alliance' : 'Horde'}~`);
			assert.notEqual(otherFaction, msg);
			assert.equal(verify(keys[p.keyId].public_hex, Buffer.from(otherFaction, 'utf8'), Buffer.from(p.sig, 'base64url')), false);
		});
	}
});

// Signatures made by Olympus/Ed25519.lua (web/test/fixtures/make-lua-signatures.lua writes
// the file from the addon's code): node must verify them, and they must equal the vectors.
const LUA = new URL('./fixtures/lua-signatures.json', import.meta.url);
test('signatures made by the addon\'s Lua verify with node:crypto', { skip: existsSync(LUA) ? false : 'no lua-signatures.json yet (run make-lua-signatures.lua)' }, () => {
	const lua = JSON.parse(readFileSync(LUA, 'utf8'));
	assert.ok(lua.signatures.length >= 3);
	const byName = Object.fromEntries(vectors.ed25519.map((v) => [v.name, v]));
	for (const s of lua.signatures) {
		assert.equal(s.signature_b64url.length, 86, s.name);
		const sig = Buffer.from(s.signature_b64url, 'base64url');
		assert.ok(verify(s.public_hex, hex(s.message_hex), sig), s.name);
		assert.equal(publicHexOf(s.seed_hex), s.public_hex, s.name);
		if (byName[s.name]) assert.equal(sig.toString('hex'), byName[s.name].signature_hex, s.name);
	}
});
