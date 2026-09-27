// scripts/link-keys.py: the keys and certificates it prints work with node:crypto, the Worker
// and D1, it writes nothing to disk and never prints the backend seed it signs with. Skipped
// where python3 or its "cryptography" package is missing.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { handleLink, verifyCertificate } from '../worker/link-worker.js';
import { parseToken, utf8Length } from '../public/core.js';
import { REPO, makeD1, publicHexOf, sign, verify, vectors } from './helpers.mjs';

const SCRIPT = join(REPO, 'scripts', 'link-keys.py');
const probe = spawnSync('python3', ['-c', 'import cryptography'], { encoding: 'utf8' });
const skip = probe.status === 0 ? false : 'python3 with the "cryptography" package is not available';
const BACKEND_SEED = vectors.backend.seed_b64url; // throwaway test seed
const BACKEND_PUB = vectors.backend.public_hex;

function run(args, { input, cwd, env = {} } = {}) {
	const base = { ...process.env, PYTHONDONTWRITEBYTECODE: '1' };
	delete base.LINK_BACKEND_SEED;
	delete base.LINK_BACKEND_SEED_FILE;
	return spawnSync('python3', [SCRIPT, ...args], { encoding: 'utf8', input, cwd, env: { ...base, ...env } });
}

const seedHex = (b64) => Buffer.from(b64, 'base64url').toString('hex');
const lineAfter = (out, re) => out.split('\n').find((l) => re.test(l));

// A folder with the backend seed in a file, as an admin would keep it.
async function withSeedFile(fn) {
	const dir = mkdtempSync(join(tmpdir(), 'olympus-keys-'));
	try {
		const file = join(dir, 'backend.seed');
		writeFileSync(file, `${BACKEND_SEED}\n`);
		return await fn(file, dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

test('backend: a seed and its public key that sign codes the addon can check', { skip }, async () => {
	const dir = mkdtempSync(join(tmpdir(), 'olympus-keys-'));
	try {
		const r = run(['backend'], { cwd: dir });
		assert.equal(r.status, 0, r.stderr);
		assert.deepEqual(readdirSync(dir), []); // nothing written
		const seed = r.stdout.match(/^ {2}([A-Za-z0-9_-]{43})$/m)[1];
		const pub = r.stdout.match(/^ {2}([0-9a-f]{64})$/m)[1];
		assert.equal(publicHexOf(seedHex(seed)), pub);
		assert.notEqual(run(['backend']).stdout, r.stdout); // fresh every time
		// The Worker signs codes with it.
		const DB = await makeD1();
		if (!DB) return;
		const env = { DB, LINK_BACKEND_SEED: seed, LINK_BACKEND_PUBLIC: pub, LINK_MODE: 'c', LINK_ORIGIN: 'https://x.example' };
		const res = await handleLink(new Request('https://x.example/api/link/code', { method: 'POST', headers: { Origin: 'https://x.example' } }), env, {}, { getUser: async () => ({ id: '123456789012345678', username: 'keys.test' }) });
		const token = parseToken((await res.json()).token).token;
		assert.ok(verify(pub, token.payload, Buffer.from(token.sig, 'base64url')));
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('cert: signs a key\'s certificate with the backend seed from a file or the environment, never printing it', { skip }, async () => {
	const pub = vectors.keys.find((k) => k.key_id === 'player01').public_hex;
	const check = async (r, tier) => {
		assert.equal(r.status, 0, r.stderr);
		assert.ok(!r.stdout.includes(BACKEND_SEED) && !r.stderr.includes(BACKEND_SEED), 'the backend seed is never printed');
		const line = lineAfter(r.stdout, /^ {2}\/oly discord cert /).trim();
		assert.ok(utf8Length(line) < 255, `${utf8Length(line)} bytes`);
		const text = line.slice('/oly discord cert '.length);
		assert.ok(utf8Length(`DV~1~${text}`) < 255);
		const c = await verifyCertificate(BACKEND_PUB, text);
		assert.ok(c, 'the backend key signed it');
		assert.deepEqual([c.keyId, c.publicHex, c.tier], ['player01', pub, tier]);
		assert.ok(Math.abs(c.exp - (Date.now() / 1000 + 30 * 86400)) < 60);
		assert.match(r.stdout, new RegExp(`Signed with the backend key ${BACKEND_PUB}`));
		return { c, sql: lineAfter(r.stdout, /^UPDATE keys SET cert_exp/) };
	};
	await withSeedFile(async (file, dir) => {
		const { c, sql } = await check(run(['cert', 'player01', pub, 'p', '30', '--backend-seed-file', file], { cwd: dir }), 'p');
		assert.deepEqual(readdirSync(dir), ['backend.seed']); // nothing else written
		// The SQL records the certificate's end in D1.
		const DB = await makeD1();
		if (DB) {
			await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, kind, created) VALUES (?, ?, ?, ?, ?)').bind('player01', pub, '123456789012345678', 'p', 1).run();
			await DB.exec(sql);
			assert.equal((await DB.prepare('SELECT cert_exp FROM keys WHERE key_id = ?').bind('player01').first()).cert_exp, c.exp);
		}
		await check(run(['cert', 'player01', Buffer.from(pub, 'hex').toString('base64url'), 'c', '30'], { env: { LINK_BACKEND_SEED_FILE: file } }), 'c');
	});
	await check(run(['cert', 'player01', pub, 'p', '30'], { env: { LINK_BACKEND_SEED: BACKEND_SEED } }), 'p');
	// No seed, or a bad one: nothing printed on stdout.
	for (const [args, env] of [
		[['cert', 'player01', pub, 'p', '30'], {}],
		[['cert', 'player01', pub, 'p', '30'], { LINK_BACKEND_SEED: 'not-a-seed' }],
		[['cert', 'player01', pub, 'p', '30', '--backend-seed-file', join(tmpdir(), 'no-such-dir-olympus', 'seed')], {}],
		[['cert', 'Bad', pub, 'p', '30'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', 'abc', 'p', '30'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'x', '30'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '0'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '99999'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p'], { LINK_BACKEND_SEED: BACKEND_SEED }],
	]) {
		const r = run(args, { env });
		assert.notEqual(r.status, 0, args.join(' '));
		assert.equal(r.stdout, '', args.join(' '));
		assert.ok(!r.stderr.includes(BACKEND_SEED));
	}
});

test('confirmer: the in-game lines, the public key, the Worker request and the SQL D1 takes', { skip }, async () => {
	const r = run(['confirmer', 'testkey01', 'p', '--owner', '123456789012345678', '--username', 'some.one']);
	assert.equal(r.status, 0, r.stderr);
	const [, id, seed] = r.stdout.match(/\/oly discord key ([a-z0-9]+) ([A-Za-z0-9_-]{43})$/m);
	assert.equal(id, 'testkey01');
	const pub = r.stdout.match(/^ {2}([0-9a-f]{64})$/m)[1];
	assert.equal(publicHexOf(seedHex(seed)), pub);
	assert.ok(verify(pub, 'OLY4~x', sign(seedHex(seed), 'OLY4~x')));
	assert.ok(utf8Length(`/oly discord key ${id} ${seed}`) < 255);
	assert.ok(!/\/oly discord cert OLK1/.test(r.stdout), 'no backend seed at hand: the Worker makes the certificate');
	const DB = await makeD1();
	if (!DB) return;
	// The Worker request it prints registers the key and answers the certificate line.
	const body = JSON.parse(r.stdout.match(/-d '(\{.*\})'$/m)[1]);
	assert.deepEqual(body, { key_id: 'testkey01', public_key: pub, owner_discord_id: '123456789012345678', kind: 'p', days: 365, owner_username: 'some.one' });
	const admin = 'test-admin-token-0123456789abcdefghijklmnop';
	const env = { DB, LINK_BACKEND_SEED: BACKEND_SEED, LINK_BACKEND_PUBLIC: BACKEND_PUB, LINK_ADMIN_TOKEN: admin };
	const res = await handleLink(new Request('https://x.example/api/link/keys', { method: 'POST', headers: { Authorization: `Bearer ${admin}` }, body: JSON.stringify(body) }), env, {});
	const answer = await res.json();
	assert.equal(answer.status, 'ok', answer.message);
	assert.ok(await verifyCertificate(BACKEND_PUB, answer.command.replace('/oly discord cert ', '')));
	await DB.exec('DELETE FROM keys');
	// Or the SQL, straight into D1.
	const insert = lineAfter(r.stdout, /^INSERT INTO keys/);
	const rotate = lineAfter(r.stdout, /^UPDATE keys/);
	await DB.exec(insert);
	const row = await DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind('testkey01').first();
	assert.equal(row.public_key, pub);
	assert.equal(row.owner_discord_id, '123456789012345678');
	assert.equal(row.owner_username, 'some.one');
	assert.equal(row.kind, 'p');
	assert.equal(row.bootstrap, 0);
	assert.equal(row.revoked, 0);
	assert.equal(row.cert_exp, null); // until "cert" (or the Worker) makes its certificate
	assert.ok(Math.abs(row.created - Date.now() / 1000) < 60);
	// Rotation: a second key for the same owner needs the old one replaced first; it stays
	// unrevoked (it checks what it signed) until revoked.
	const second = run(['confirmer', 'testkey02', 'p', '--owner', '123456789012345678', '--days', '30'], { env: { LINK_BACKEND_SEED: BACKEND_SEED } });
	assert.equal(second.status, 0, second.stderr);
	const insert2 = lineAfter(second.stdout, /^INSERT INTO keys/);
	assert.throws(() => DB.sqlite.exec(insert2), /UNIQUE/);
	await DB.exec(rotate);
	await DB.exec(insert2);
	const active = await DB.prepare('SELECT key_id FROM keys WHERE owner_discord_id = ? AND revoked = 0 AND replaced_at IS NULL').bind('123456789012345678').all();
	assert.deepEqual(active.results.map((x) => x.key_id), ['testkey02']);
	assert.equal((await DB.prepare('SELECT revoked FROM keys WHERE key_id = ?').bind('testkey01').first()).revoked, 0);
	// With the backend seed at hand, both in-game lines and the certificate's end in the SQL.
	assert.ok(!second.stdout.includes(BACKEND_SEED));
	const certLine = lineAfter(second.stdout, /^ {2}\/oly discord cert /).trim();
	const cert = await verifyCertificate(BACKEND_PUB, certLine.slice('/oly discord cert '.length));
	assert.ok(cert);
	assert.equal(cert.keyId, 'testkey02');
	assert.equal((await DB.prepare('SELECT cert_exp FROM keys WHERE key_id = ?').bind('testkey02').first()).cert_exp, cert.exp);
	// Revoking.
	const revoke = run(['revoke', 'testkey01']);
	await DB.exec(revoke.stdout);
	assert.equal((await DB.prepare('SELECT revoked FROM keys WHERE key_id = ?').bind('testkey01').first()).revoked, 1);
	// A councillor bootstrap key; and the placeholder owner is refused by the table.
	const boot = run(['confirmer', 'council01', 'c', '--bootstrap']);
	assert.equal(boot.status, 0, boot.stderr);
	assert.match(boot.stdout, /REPLACE_WITH_DISCORD_ID/);
	assert.throws(() => DB.sqlite.exec(lineAfter(boot.stdout, /^INSERT INTO keys/)), /CHECK/);
});

test('confirmer: bad ids, kinds and options are refused', { skip }, () => {
	for (const args of [
		['confirmer', 'short', 'p'],
		['confirmer', 'Upper01', 'p'],
		['confirmer', 'waytoolongkeyid0123', 'p'],
		['confirmer', 'testkey01', 'x'],
		['confirmer', 'testkey01', 'p', '--owner', 'abc'],
		['confirmer', 'testkey01', 'p', '--username', 'Bad Name'],
		['confirmer', 'testkey01', 'p', '--bootstrap'],
		['confirmer', 'testkey01', 'p', '--days', '0'],
		['confirmer', 'testkey01', 'p', '--what'],
		['revoke', 'x'],
		['nope'],
		[],
	]) {
		const r = run(args);
		assert.notEqual(r.status, 0, args.join(' '));
		assert.equal(r.stdout, '', args.join(' '));
	}
});

test('public: the public key of a seed on stdin', { skip }, () => {
	const seed = Buffer.alloc(32, 7).toString('base64url');
	const r = run(['public'], { input: `${seed}\n` });
	assert.equal(r.status, 0, r.stderr);
	assert.equal(r.stdout.trim(), publicHexOf(Buffer.alloc(32, 7).toString('hex')));
	assert.notEqual(run(['public'], { input: 'not a seed' }).status, 0);
});
