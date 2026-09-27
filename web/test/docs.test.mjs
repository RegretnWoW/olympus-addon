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
import { parseBundle, parseToken, signedMessage } from '../public/core.js';

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

	test('the guide\'s vectors verify: the code token and every proof of the sample bundles', () => {
		const v = JSON.parse(blocks.vectors);
		const t = parseToken(v.backend.token);
		assert.ok(t.ok);
		assert.equal(t.token.payload, v.backend.signed);
		assert.ok(verify(v.backend.public_hex, Buffer.from(v.backend.signed, 'ascii'), Buffer.from(t.token.sig, 'base64url')));
		const keys = Object.fromEntries(v.keys.map((k) => [k.key_id, k.public_hex]));
		assert.ok(v.bundles.length >= 2);
		for (const b of v.bundles) {
			const parsed = parseBundle(b.bundle);
			assert.ok(parsed.ok, b.name);
			assert.ok(v.codes.some((c) => c.R === parsed.bundle.R), b.name);
			parsed.bundle.proofs.forEach((p, i) => {
				assert.equal(signedMessage(parsed.bundle, p), b.signed[i]);
				assert.ok(verify(keys[p.keyId], Buffer.from(b.signed[i], 'utf8'), Buffer.from(p.sig, 'base64url')), `${b.name} #${i + 1}`);
			});
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
