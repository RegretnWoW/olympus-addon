// web/WORKER.md carries the schema, the test vectors and the whole reference Worker in its
// own text (Fernmelder copies from it): they must stay the files the tests run. After a change
// to one of those files, rewrite the guide's copies with
//   node web/test/docs.test.mjs --write
// The guide's vectors must verify too, and the paths it names must exist.

import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { REPO, guideVectors, verify } from './helpers.mjs';
import { parseBundle, parseToken, signedMessage, linkTag, drawThreshold } from '../public/core.js';
import { verifyCertificate } from '../worker/link-worker.js';

const GUIDE = join(REPO, 'web', 'WORKER.md');

// <!-- block: <name> --> then a fenced block: the block is replaced by what the name gives.
const BLOCKS = {
	'web/worker/schema.sql': () => readFileSync(join(REPO, 'web/worker/schema.sql'), 'utf8'),
	'web/worker/link-worker.js': () => readFileSync(join(REPO, 'web/worker/link-worker.js'), 'utf8'),
	vectors: () => `${JSON.stringify(guideVectors(), null, 2)}\n`,
};

// The closing fence is a line of its own (the Worker has ``` inside a string: not at a line's start).
const BLOCK_RE = /<!-- block: ([^ ]+) -->\n```([a-z]*)\n([\s\S]*?)^```\n/gm;

export function guideBlocks(md) {
	const out = {};
	for (const m of md.matchAll(BLOCK_RE)) out[m[1]] = m[3];
	return out;
}

export function fillGuide(md) {
	return md.replace(BLOCK_RE, (all, name, lang) => {
		if (!BLOCKS[name]) throw new Error(`unknown block ${name}`);
		return `<!-- block: ${name} -->\n\`\`\`${lang}\n${BLOCKS[name]()}\`\`\`\n`;
	});
}

if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv.includes('--write')) {
	writeFileSync(GUIDE, fillGuide(readFileSync(GUIDE, 'utf8')));
	console.log(`${GUIDE}: blocks rewritten`);
} else {
	const md = readFileSync(GUIDE, 'utf8');
	const blocks = guideBlocks(md);

	test('WORKER.md carries the exact schema, vectors and reference Worker', () => {
		assert.deepEqual(Object.keys(blocks).sort(), Object.keys(BLOCKS).sort());
		for (const [name, make] of Object.entries(BLOCKS)) {
			assert.ok(blocks[name] === make(), `WORKER.md's copy of ${name} is out of date: run node web/test/docs.test.mjs --write`);
		}
	});

	test('the guide\'s vectors verify: the code tokens, the certificates, the tags and every proof of the sample bundles', async () => {
		const v = JSON.parse(blocks.vectors);
		const t = parseToken(v.backend.token);
		assert.ok(t.ok);
		assert.equal(t.token.payload, v.backend.signed);
		assert.ok(verify(v.backend.public_hex, Buffer.from(v.backend.signed, 'ascii'), Buffer.from(t.token.sig, 'base64url')));
		for (const c of v.codes) {
			const p = parseToken(c.token);
			assert.ok(p.ok, c.R);
			assert.deepEqual([p.token.R, p.token.username, p.token.mode, p.token.T, p.token.exp], [c.R, c.username, c.mode, c.draw_t, c.exp]);
			assert.ok(verify(v.backend.public_hex, Buffer.from(p.token.payload, 'ascii'), Buffer.from(p.token.sig, 'base64url')), c.R);
		}
		for (const k of v.keys) {
			const cert = await verifyCertificate(v.backend.public_hex, k.cert);
			assert.ok(cert, k.key_id);
			assert.deepEqual([cert.keyId, cert.publicHex, cert.tier, cert.exp], [k.key_id, k.public_hex, k.kind, k.cert_exp]);
		}
		const keys = Object.fromEntries(v.keys.map((k) => [k.key_id, k.public_hex]));
		assert.ok(v.bundles.length >= 2);
		for (const b of v.bundles) {
			const parsed = parseBundle(b.bundle);
			assert.ok(parsed.ok, b.name);
			const code = v.codes.find((c) => c.R === parsed.bundle.R);
			assert.ok(code, b.name);
			assert.equal(b.tag_of, `${parseToken(code.token).token.sig}~${parsed.bundle.requester}`);
			assert.equal(await linkTag(parseToken(code.token).token.sig, parsed.bundle.requester), b.tag);
			assert.equal(parsed.bundle.tag, b.tag);
			parsed.bundle.proofs.forEach((p, i) => {
				assert.equal(signedMessage(parsed.bundle, p), b.signed[i]);
				assert.ok(verify(keys[p.keyId], Buffer.from(b.signed[i], 'utf8'), Buffer.from(p.sig, 'base64url')), `${b.name} #${i + 1}`);
			});
		}
		for (const x of v.draw.thresholds) {
			const pool = Array.from({ length: x.n }, (_, i) => `pool${String(i).padStart(4, '0')}`);
			assert.equal(await drawThreshold(v.draw.R, pool), x.T, `n=${x.n}`);
		}
		for (const e of v.ed25519) {
			const msg = e.message !== undefined ? Buffer.from(e.message, 'utf8') : Buffer.from(e.message_hex, 'hex');
			assert.ok(verify(e.public_hex, msg, Buffer.from(e.signature_b64url, 'base64url')), e.name);
		}
		assert.equal(verify(v.must_fail.public_hex, Buffer.from(v.must_fail.message_hex, 'hex'), Buffer.from(v.must_fail.signature_hex, 'hex')), false);
	});

	test('every web/ and scripts/ path the guide names exists', () => {
		const paths = new Set([...md.matchAll(/\b((?:web|scripts)\/[A-Za-z0-9_./-]*[A-Za-z0-9_])/g)].map((m) => m[1]));
		assert.ok(paths.size > 5);
		for (const p of paths) assert.ok(existsSync(join(REPO, p)), p);
	});
}
