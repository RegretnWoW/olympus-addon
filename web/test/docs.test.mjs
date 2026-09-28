// web/WORKER.md carries the schema, the test vectors, the core and the whole reference Worker in
// its own text (Fernmelder copies from it): they must stay the files the tests run. After a change
// to one of those files, rewrite the guide's copies with
//   node web/test/docs.test.mjs --write
// The guide's vectors must verify too, and the paths it names must exist. web/FERN.md, the short
// way in, must name only what link-core.mjs exports, the settings the addon and the page hold, and
// files that exist.

import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { REPO, guideVectors, verify } from './helpers.mjs';
import { parseBundle, parseToken, signedMessage, linkTag, drawThreshold } from '../public/core.js';
import { verifyCertificate, councilCertificate, councilKeyId } from '../worker/link-worker.js';
import * as core from '../worker/link-core.mjs';
import { CONFIG } from '../public/config.js';
import { vectors } from './helpers.mjs';

const GUIDE = join(REPO, 'web', 'WORKER.md');
const FERN = join(REPO, 'web', 'FERN.md');

// <!-- block: <name> --> then a fenced block: the block is replaced by what the name gives.
const BLOCKS = {
	'web/worker/schema.sql': () => readFileSync(join(REPO, 'web/worker/schema.sql'), 'utf8'),
	'web/worker/link-core.mjs': () => readFileSync(join(REPO, 'web/worker/link-core.mjs'), 'utf8'),
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
			assert.deepEqual([cert.keyId, cert.publicHex, cert.tier, cert.exp, cert.character], [k.key_id, k.public_hex, k.kind, k.cert_exp, k.character]);
		}
		// The council authority's: a High Councillor's key, its id the key's hash, never registered.
		assert.ok(v.council_authority.keys.length >= 1);
		for (const k of v.council_authority.keys) {
			const cert = await verifyCertificate(v.council_authority.public_hex, k.cert);
			assert.ok(cert, k.key_id);
			assert.deepEqual([cert.keyId, cert.publicHex, cert.tier, cert.exp, cert.character], [k.key_id, k.public_hex, 'c', k.cert_exp, k.character]);
			assert.equal(await councilKeyId(k.public_hex), k.key_id);
			assert.ok(await councilCertificate({ LINK_CA_PUBLIC: v.council_authority.public_hex }, cert));
		}
		const keys = Object.fromEntries([...v.keys, ...v.council_authority.keys].map((k) => [k.key_id, k.public_hex]));
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

	const fern = readFileSync(FERN, 'utf8');

	test('FERN.md: the paths and links it names exist, and it and WORKER.md point at each other', () => {
		const paths = new Set([...fern.matchAll(/\b((?:web|scripts)\/[A-Za-z0-9_./-]*[A-Za-z0-9_])/g)].map((m) => m[1]));
		assert.ok(paths.size >= 5);
		for (const p of paths) assert.ok(existsSync(join(REPO, p)), p);
		for (const [, target] of fern.matchAll(/\]\(([^)#\s]+)(?:#[^)]*)?\)/g)) {
			if (/^https?:/.test(target)) continue;
			assert.ok(existsSync(join(REPO, 'web', target)), `link: ${target}`);
		}
		const anchors = new Set([...fern.matchAll(/^#+ (.+)$/gm)].map((m) => m[1].toLowerCase().replace(/[^a-z0-9 -]/g, '').replace(/ /g, '-')));
		for (const [, anchor] of fern.matchAll(/\]\(#([^)]+)\)/g)) assert.ok(anchors.has(anchor), `#${anchor}`);
		assert.match(fern, /\]\(WORKER\.md\)/, 'FERN.md links to WORKER.md');
		assert.match(md, /\]\(FERN\.md\)/, 'WORKER.md links to FERN.md');
	});

	test('FERN.md names only what link-core.mjs exports', () => {
		const imported = [...fern.matchAll(/import \{([^}]+)\} from '\.\/link-core\.mjs'/g)].flatMap((m) => m[1].split(',').map((x) => x.trim()));
		assert.ok(imported.length >= 4);
		const called = [...fern.matchAll(/`([a-z][A-Za-z]+)\(/g)].map((m) => m[1]);
		const named = [...fern.matchAll(/`([a-z][A-Za-z]+)`/g)].map((m) => m[1]).filter((n) => /[A-Z]/.test(n) && n !== 'keyId');
		for (const name of new Set([...imported, ...called, ...named])) {
			if (name === 'promote' || name === 'demote') continue; // the bot's own
			assert.equal(typeof core[name], 'function', `link-core.mjs exports ${name}`);
		}
	});

	test('FERN.md: the settings are the ones the addon and the page hold, and its fake proof is the fixtures\'', () => {
		const lua = readFileSync(join(REPO, 'Olympus', 'Link.lua'), 'utf8');
		const ca = /^ns\.LINK_CA_KEYS = \{ "([0-9a-f]{64})" \}$/m.exec(lua)[1];
		assert.ok(fern.includes(`LINK_CA_PUBLIC = "${ca}"`), 'the council authority\'s public key');
		assert.ok(md.includes(`LINK_CA_PUBLIC = "${ca}"`), 'WORKER.md\'s too');
		assert.ok(fern.includes(`\`${CONFIG.PAGE_URL}\``), 'the page\'s address, the Discord redirect');
		const origin = new URL(CONFIG.PAGE_URL).origin;
		assert.ok(fern.includes(`LINK_ORIGIN = "${origin}"`) && md.includes(`LINK_ORIGIN = "${origin}"`), 'the origin, in both');
		assert.ok(fern.includes(`\`${CONFIG.VERIFY_COMMAND}\``), 'the command the page names');
		const body = /--data '(\{[^']+\})'/.exec(fern);
		assert.ok(body, 'a curl with a body');
		const { text, discordToken } = JSON.parse(body[1]);
		assert.equal(text, vectors.bundles[0].bundle);
		assert.ok(parseBundle(text).ok && core.parseBundle(text).ok);
		assert.equal(typeof discordToken, 'string');
		for (const reason of core.PROOF_REASONS) assert.ok(md.includes(`\`${reason}\``), `WORKER.md names the reason ${reason}`);
	});
}
