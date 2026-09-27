// scripts/link-keys.py: the keys it prints work with node:crypto, the Worker and D1, and it
// writes nothing to disk. Skipped where python3 or its "cryptography" package is missing.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { handleLink } from '../worker/link-worker.js';
import { parseToken } from '../public/core.js';
import { REPO, makeD1, publicHexOf, sign, verify } from './helpers.mjs';

const SCRIPT = join(REPO, 'scripts', 'link-keys.py');
const probe = spawnSync('python3', ['-c', 'import cryptography'], { encoding: 'utf8' });
const skip = probe.status === 0 ? false : 'python3 with the "cryptography" package is not available';

function run(args, input, cwd) {
	return spawnSync('python3', [SCRIPT, ...args], { encoding: 'utf8', input, cwd, env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' } });
}

const seedHex = (b64) => Buffer.from(b64, 'base64url').toString('hex');

test('backend: a seed and its public key that sign codes the addon can check', { skip }, async () => {
	const dir = mkdtempSync(join(tmpdir(), 'olympus-keys-'));
	try {
		const r = run(['backend'], undefined, dir);
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

test('confirmer: the in-game command, the public key and SQL that D1 takes', { skip }, async () => {
	const r = run(['confirmer', 'testkey01', 'p', '--owner', '123456789012345678', '--username', 'some.one']);
	assert.equal(r.status, 0, r.stderr);
	const [, id, seed] = r.stdout.match(/\/oly discord key ([a-z0-9]+) ([A-Za-z0-9_-]{43})$/m);
	assert.equal(id, 'testkey01');
	const pub = r.stdout.match(/^ {2}([0-9a-f]{64})$/m)[1];
	assert.equal(publicHexOf(seedHex(seed)), pub);
	assert.ok(verify(pub, 'OLY4~x', sign(seedHex(seed), 'OLY4~x')));
	const insert = r.stdout.split('\n').find((l) => l.startsWith('INSERT INTO keys'));
	const rotate = r.stdout.split('\n').find((l) => l.startsWith('UPDATE keys'));
	const DB = await makeD1();
	if (!DB) return;
	await DB.exec(insert);
	const row = await DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind('testkey01').first();
	assert.equal(row.public_key, pub);
	assert.equal(row.owner_discord_id, '123456789012345678');
	assert.equal(row.owner_username, 'some.one');
	assert.equal(row.kind, 'p');
	assert.equal(row.bootstrap, 0);
	assert.equal(row.revoked, 0);
	assert.ok(Math.abs(row.created - Date.now() / 1000) < 60);
	// Rotation: a second key for the same owner needs the old one revoked first.
	const second = run(['confirmer', 'testkey02', 'p', '--owner', '123456789012345678']);
	const insert2 = second.stdout.split('\n').find((l) => l.startsWith('INSERT INTO keys'));
	assert.throws(() => DB.sqlite.exec(insert2), /UNIQUE/);
	await DB.exec(rotate);
	await DB.exec(insert2);
	const active = await DB.prepare('SELECT key_id FROM keys WHERE owner_discord_id = ? AND revoked = 0').bind('123456789012345678').all();
	assert.deepEqual(active.results.map((x) => x.key_id), ['testkey02']);
	// Revoking.
	const revoke = run(['revoke', 'testkey02']);
	await DB.exec(revoke.stdout);
	assert.equal((await DB.prepare('SELECT revoked FROM keys WHERE key_id = ?').bind('testkey02').first()).revoked, 1);
	// A councillor bootstrap key; and the placeholder owner is refused by the table.
	const boot = run(['confirmer', 'council01', 'c', '--bootstrap']);
	assert.equal(boot.status, 0, boot.stderr);
	assert.match(boot.stdout, /REPLACE_WITH_DISCORD_ID/);
	assert.throws(() => DB.sqlite.exec(boot.stdout.split('\n').find((l) => l.startsWith('INSERT INTO keys'))), /CHECK/);
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
	const r = run(['public'], `${seed}\n`);
	assert.equal(r.status, 0, r.stderr);
	assert.equal(r.stdout.trim(), publicHexOf(Buffer.alloc(32, 7).toString('hex')));
	assert.notEqual(run(['public'], 'not a seed').status, 0);
});
