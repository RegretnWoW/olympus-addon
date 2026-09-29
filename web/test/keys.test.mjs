// scripts/link-keys.py: the keys and certificates it prints work with node:crypto, the Worker
// and D1, it writes nothing to disk and never prints the backend seed it signs with. Skipped
// where python3 or its "cryptography" package is missing.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { handleLink, verifyCertificate, certFrom, councilCertificate, parseCertificate } from '../worker/link-worker.js';
import { forgetUser } from '../worker/link-core.mjs';
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
const OLD_OWNER = '100000000000000011'; // a Discord account from 2015
const P01_CHAR = 'Other Player-ClassicBetaPvP'; // the character player01 is registered for in the vectors
const P01 = ['--created', '1780000000', '--owner', OLD_OWNER, '--character', P01_CHAR]; // player01 in the vectors: it counts long since
const nowS = () => Math.floor(Date.now() / 1000);
// The unix time a refused player certificate names: when the key counts.
const countsFrom = (r) => Number(/\(unix ([0-9]+)\)/.exec(r.stderr)?.[1]);
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
		assert.deepEqual([c.keyId, c.publicHex, c.tier, c.character], ['player01', pub, tier, P01_CHAR]);
		assert.ok(Math.abs(c.exp - (Date.now() / 1000 + 30 * 86400)) < 60);
		assert.match(r.stdout, new RegExp(`Signed with the backend key ${BACKEND_PUB}`));
		return { c, sql: lineAfter(r.stdout, /^UPDATE keys SET cert_exp/) };
	};
	await withSeedFile(async (file, dir) => {
		const { c, sql } = await check(run(['cert', 'player01', pub, 'p', '30', ...P01, '--backend-seed-file', file], { cwd: dir }), 'p');
		assert.deepEqual(readdirSync(dir), ['backend.seed']); // nothing else written
		// The SQL records the certificate's end in D1, for that key as D1 holds it only.
		const DB = await makeD1();
		if (DB) {
			await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, character, kind, created) VALUES (?, ?, ?, ?, ?, ?)').bind('player01', pub, OLD_OWNER, 'Some Alt-ClassicBetaPvP', 'p', 1780000000).run();
			assert.equal((await DB.prepare(sql).run()).meta.changes, 0, 'another character: nothing recorded');
			await DB.prepare('UPDATE keys SET character = ?, created = 1780000001').bind(P01_CHAR).run();
			assert.equal((await DB.prepare(sql).run()).meta.changes, 0, 'another creation time: nothing recorded');
			await DB.prepare('UPDATE keys SET created = 1780000000').run();
			assert.equal((await DB.prepare(sql).run()).meta.changes, 1);
			assert.equal((await DB.prepare('SELECT cert_exp FROM keys WHERE key_id = ?').bind('player01').first()).cert_exp, c.exp);
		}
		await check(run(['cert', 'player01', Buffer.from(pub, 'hex').toString('base64url'), 'c', '30', '--character', P01_CHAR], { env: { LINK_BACKEND_SEED_FILE: file } }), 'c');
	});
	await check(run(['cert', 'player01', pub, 'p', '30', ...P01], { env: { LINK_BACKEND_SEED: BACKEND_SEED } }), 'p');
	// A player key only once the Worker counts it for every open code (the Worker's certFrom): not
	// a key made 8 days ago, nor one of a Discord account made 29 days ago.
	const env = { LINK_BACKEND_SEED: BACKEND_SEED };
	for (const [created, owner] of [
		[nowS() - 8 * 86400, OLD_OWNER],
		[nowS() - 20 * 86400, String((BigInt((nowS() - 29 * 86400) * 1000) - 1420070400000n) << 22n)],
	]) {
		const early = run(['cert', 'player01', pub, 'p', '30', '--created', String(created), '--owner', owner, '--character', P01_CHAR], { env });
		assert.notEqual(early.status, 0);
		assert.equal(early.stdout, '');
		assert.match(early.stderr, /counts from/);
		assert.equal(countsFrom(early), certFrom({ kind: 'p', created, owner_discord_id: owner }));
		assert.ok(countsFrom(early) > nowS());
	}
	// From the second the Worker's certFrom names.
	const lag = certFrom({ kind: 'p', created: nowS(), owner_discord_id: OLD_OWNER }) - nowS(); // 8 days and 5 minutes
	const counted = nowS() - 5 - lag;
	assert.equal(certFrom({ kind: 'p', created: counted, owner_discord_id: OLD_OWNER }), nowS() - 5);
	await check(run(['cert', 'player01', pub, 'p', '30', '--created', String(counted), '--owner', OLD_OWNER, '--character', P01_CHAR], { env }), 'p');
	// No seed, or a bad one, or a player key without its creation and owner: nothing on stdout.
	for (const [args, env] of [
		[['cert', 'player01', pub, 'p', '30', ...P01], {}],
		[['cert', 'player01', pub, 'p', '30', ...P01], { LINK_BACKEND_SEED: 'not-a-seed' }],
		[['cert', 'player01', pub, 'p', '30', ...P01, '--backend-seed-file', join(tmpdir(), 'no-such-dir-olympus', 'seed')], {}],
		[['cert', 'player01', pub, 'p', '30', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '30', '--created', '1780000000', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '30', '--created', 'yesterday', '--owner', OLD_OWNER, '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '30', '--created', '1780000000', '--owner', 'abc', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '30', '--created', '1780000000', '--owner', OLD_OWNER], { LINK_BACKEND_SEED: BACKEND_SEED }], // no character
		[['cert', 'player01', pub, 'c', '30', '--character', 'No Realm'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'c', '30', '--character', 'Some~One-ClassicBetaPvP'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'a1b2c3d4e5f6', pub, 'c', '30', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }], // the council authority's ids
		[['cert', 'player01', pub, 'p', '30', ...P01, '--what'], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'Bad', pub, 'p', '30', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', 'abc', 'p', '30', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'x', '30', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '0', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '99999', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
		[['cert', 'player01', pub, 'p', '--character', P01_CHAR], { LINK_BACKEND_SEED: BACKEND_SEED }],
	]) {
		const r = run(args, { env });
		assert.notEqual(r.status, 0, args.join(' '));
		assert.equal(r.stdout, '', args.join(' '));
		assert.ok(!r.stderr.includes(BACKEND_SEED));
	}
});

// The "link-keys.py cert ..." command a player key's output names, and its arguments with another
// creation time (split as a shell would: the character's name is quoted).
function certCommand(stdout) {
	const line = lineAfter(stdout, /^python3 scripts\/link-keys.py cert /);
	const words = line
		.replace(/^python3 scripts\/link-keys.py /, '')
		.replace(/ --backend-seed-file <file>$/, '')
		.match(/'[^']*'|\S+/g)
		.map((w) => w.replace(/^'(.*)'$/, '$1'));
	const at = words.indexOf('--created') + 1;
	return { created: Number(words[at]), args: (created) => words.map((w, i) => (i === at ? String(created) : w)) };
}

// That command nine days later: the key's creation moved 9 days back in D1 and in the command.
async function certifyAged(DB, keyId, command) {
	const aged = command.created - 9 * 86400;
	await DB.prepare('UPDATE keys SET created = ? WHERE key_id = ?').bind(aged, keyId).run();
	return run(command.args(aged), { env: { LINK_BACKEND_SEED: BACKEND_SEED } });
}

const certOf = (r) => verifyCertificate(BACKEND_PUB, lineAfter(r.stdout, /^ {2}\/oly discord cert /).trim().slice('/oly discord cert '.length));

test('confirmer: the in-game lines, the public key, the Worker request and the SQL D1 takes', { skip }, async () => {
	const OWNER = '123456789012345678';
	const CHAR = 'Some One-ClassicBetaPvP';
	const r = run(['confirmer', 'testkey01', 'p', '--owner', OWNER, '--username', 'some.one', '--character', CHAR]);
	assert.equal(r.status, 0, r.stderr);
	const [, id, seed] = r.stdout.match(/\/oly discord key ([a-z0-9]+) ([A-Za-z0-9_-]{43})$/m);
	assert.equal(id, 'testkey01');
	const pub = r.stdout.match(/^ {2}([0-9a-f]{64})$/m)[1];
	assert.equal(publicHexOf(seedHex(seed)), pub);
	assert.ok(verify(pub, 'OLY4~x', sign(seedHex(seed), 'OLY4~x')));
	assert.ok(utf8Length(`/oly discord key ${id} ${seed}`) < 255);
	assert.ok(!/\/oly discord cert OLK/.test(r.stdout), 'no backend seed at hand: the Worker makes the certificate');
	const DB = await makeD1();
	if (!DB) return;
	// The Worker request it prints registers the key: a player key's certificate comes once it
	// counts (web/test/worker.test.mjs), at the time the tool names too.
	const body = JSON.parse(r.stdout.match(/-d '(\{.*\})'$/m)[1]);
	assert.deepEqual(body, { key_id: 'testkey01', public_key: pub, owner_discord_id: OWNER, character: CHAR, kind: 'p', owner_username: 'some.one' });
	assert.match(r.stdout, /must be one of the owner's linked characters/);
	const admin = 'test-admin-token-0123456789abcdefghijklmnop';
	const env = { DB, LINK_BACKEND_SEED: BACKEND_SEED, LINK_BACKEND_PUBLIC: BACKEND_PUB, LINK_ADMIN_TOKEN: admin };
	await DB.prepare('INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?)').bind(CHAR, OWNER, 'Olympus II', 'Alliance', '0000000000', 1780000000).run();
	const res = await handleLink(new Request('https://x.example/api/link/keys', { method: 'POST', headers: { Authorization: `Bearer ${admin}` }, body: JSON.stringify(body) }), env, {});
	const answer = await res.json();
	assert.equal(answer.status, 'ok', answer.message);
	assert.deepEqual([answer.cert, answer.command], [null, null]);
	assert.match(r.stdout, /"renew": true, "days": 90/);
	const later = certCommand(r.stdout);
	assert.ok(Math.abs(answer.cert_from - certFrom({ kind: 'p', created: later.created, owner_discord_id: OWNER })) < 60);
	await DB.exec('DELETE FROM keys');
	// Or the SQL, straight into D1: the key waits without a certificate...
	await DB.exec(lineAfter(r.stdout, /^INSERT INTO keys/));
	const row = await DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind('testkey01').first();
	assert.equal(row.public_key, pub);
	assert.equal(row.owner_discord_id, OWNER);
	assert.equal(row.owner_username, 'some.one');
	assert.equal(row.character, CHAR);
	assert.equal(row.kind, 'p');
	assert.equal(row.bootstrap, 0);
	assert.equal(row.revoked, 0);
	assert.equal(row.cert_exp, null);
	assert.equal(row.created, later.created); // the time its certificate command carries
	assert.ok(Math.abs(row.created - Date.now() / 1000) < 60);
	// ...and the certificate command it prints refuses until the key counts, then signs it.
	const early = run(later.args(later.created), { env: { LINK_BACKEND_SEED: BACKEND_SEED } });
	assert.notEqual(early.status, 0);
	assert.equal(early.stdout, '');
	assert.equal(countsFrom(early), certFrom(row));
	const first = await certifyAged(DB, 'testkey01', later);
	assert.equal(first.status, 0, first.stderr);
	await DB.exec(lineAfter(first.stdout, /^UPDATE keys SET cert_exp/));
	const cert1 = await certOf(first);
	assert.equal(cert1.keyId, 'testkey01');
	assert.equal(cert1.character, CHAR, 'for the character it was registered for');
	assert.ok(Math.abs(cert1.exp - (nowS() + 90 * 86400)) < 60);
	assert.equal((await DB.prepare('SELECT cert_exp FROM keys WHERE key_id = ?').bind('testkey01').first()).cert_exp, cert1.exp);
	// Rotation: the new key waits next to the old one, which keeps counting (no certificate yet,
	// even with the backend seed at hand)...
	const second = run(['confirmer', 'testkey02', 'p', '--owner', OWNER, '--days', '30', '--character', CHAR], { env: { LINK_BACKEND_SEED: BACKEND_SEED } });
	assert.equal(second.status, 0, second.stderr);
	assert.ok(!second.stdout.includes(BACKEND_SEED));
	assert.ok(!/\/oly discord cert OLK/.test(second.stdout), 'a new player key does not count yet');
	await DB.exec(lineAfter(second.stdout, /^INSERT INTO keys/));
	const certified = async () => (await DB.prepare('SELECT key_id FROM keys WHERE owner_discord_id = ? AND revoked = 0 AND replaced_at IS NULL AND cert_exp IS NOT NULL').bind(OWNER).all()).results.map((x) => x.key_id);
	assert.deepEqual(await certified(), ['testkey01']);
	// ...until its first certificate, which replaces it: D1 takes no second certified key, so the
	// rotation line goes first. The old key stays unrevoked (it checks what it signed) until revoked.
	const next = await certifyAged(DB, 'testkey02', certCommand(second.stdout));
	assert.equal(next.status, 0, next.stderr);
	const certSql = lineAfter(next.stdout, /^UPDATE keys SET cert_exp/);
	assert.throws(() => DB.sqlite.exec(certSql), /UNIQUE/);
	await DB.exec(lineAfter(next.stdout, /^UPDATE keys SET replaced_at/));
	await DB.exec(certSql);
	assert.deepEqual(await certified(), ['testkey02']);
	assert.ok(Math.abs((await certOf(next)).exp - (nowS() + 30 * 86400)) < 60);
	const old = await DB.prepare('SELECT revoked, replaced_at FROM keys WHERE key_id = ?').bind('testkey01').first();
	assert.equal(old.revoked, 0);
	assert.ok(old.replaced_at > 0);
	// Revoking.
	const revoke = run(['revoke', 'testkey01']);
	await DB.exec(revoke.stdout);
	assert.equal((await DB.prepare('SELECT revoked FROM keys WHERE key_id = ?').bind('testkey01').first()).revoked, 1);
	// A councillor key counts at once: with the backend seed at hand, both lines, and its INSERT
	// records the certificate's end (365 days).
	const council = run(['confirmer', 'council0x', 'c', '--owner', '123456789012345699', '--bootstrap', '--character', 'Some Councillor-ClassicBetaPvP'], { env: { LINK_BACKEND_SEED: BACKEND_SEED } });
	assert.equal(council.status, 0, council.stderr);
	assert.equal(JSON.parse(council.stdout.match(/-d '(\{.*\})'$/m)[1]).days, 365);
	const ccert = await certOf(council);
	assert.deepEqual([ccert.keyId, ccert.tier, ccert.character], ['council0x', 'c', 'Some Councillor-ClassicBetaPvP']);
	assert.ok(Math.abs(ccert.exp - (nowS() + 365 * 86400)) < 60);
	await DB.exec(lineAfter(council.stdout, /^INSERT INTO keys/));
	assert.equal((await DB.prepare('SELECT cert_exp FROM keys WHERE key_id = ?').bind('council0x').first()).cert_exp, ccert.exp);
	// A councillor bootstrap key; and the placeholder owner is refused by the table.
	const boot = run(['confirmer', 'council01', 'c', '--bootstrap', '--character', 'Test Councillor-ClassicBetaPvP']);
	assert.equal(boot.status, 0, boot.stderr);
	assert.match(boot.stdout, /REPLACE_WITH_DISCORD_ID/);
	assert.throws(() => DB.sqlite.exec(lineAfter(boot.stdout, /^INSERT INTO keys/)), /CHECK/);
});

test('confirmer: bad ids, kinds and options are refused', { skip }, () => {
	const who = ['--character', 'Some One-ClassicBetaPvP'];
	for (const args of [
		['confirmer', 'short', 'p', ...who],
		['confirmer', 'Upper01', 'p', ...who],
		['confirmer', 'waytoolongkeyid0123', 'p', ...who],
		['confirmer', 'a1b2c3d4e5f6', 'c', ...who], // 12 hex digits: the council authority's ids
		['confirmer', 'testkey01', 'x', ...who],
		['confirmer', 'testkey01', 'p', '--owner', 'abc', ...who],
		['confirmer', 'testkey01', 'p', '--username', 'Bad Name', ...who],
		['confirmer', 'testkey01', 'p', '--bootstrap', ...who],
		['confirmer', 'testkey01', 'p', '--days', '0', ...who],
		['confirmer', 'testkey01', 'p', '--what', ...who],
		['confirmer', 'testkey01', 'p'], // no character
		['confirmer', 'testkey01', 'p', '--character', 'NoRealm'],
		['confirmer', 'testkey01', 'p', '--character', 'Some,One-ClassicBetaPvP'],
		['confirmer', 'testkey01', 'p', '--character', `${'x'.repeat(60)}-Realm`], // 66 bytes
		['revoke', 'x'],
		['revoke', '--character', 'NoRealm'],
		['revoke', '--character'],
		['forget'],
		['forget', 'abc'],
		['forget', "1234567'; DROP TABLE members; --"],
		['forget', '123456', '789012'],
		['ca', 'what'],
		['nope'],
		[],
	]) {
		const r = run(args);
		assert.notEqual(r.status, 0, args.join(' '));
		assert.equal(r.stdout, '', args.join(' '));
	}
});

test('revoke --character: the SQL that revokes every key of a character (its council authority certificates until now, its registered keys), which D1 takes', { skip }, async () => {
	const DB = await makeD1();
	if (!DB) return;
	const character = "Sömë O'Councillor-ClassicBetaPvP"; // a quote and letters beyond ASCII, as SQL text
	await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, character, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
		.bind('testkey09', publicHexOf('09'.repeat(32)), OLD_OWNER, null, character, 'c', 1, 1780000000, 1830000000)
		.run();
	const r = run(['revoke', '--character', character]);
	assert.equal(r.status, 0, r.stderr);
	await DB.exec(r.stdout);
	const at = (await DB.prepare('SELECT revoked_at FROM revoked_characters WHERE character = ?').bind(character).first()).revoked_at;
	assert.ok(Math.abs(at - nowS()) < 60, 'revoked now');
	assert.equal((await DB.prepare('SELECT revoked FROM keys WHERE key_id = ?').bind('testkey09').first()).revoked, 1);
	// Again later: the time moves (certificates signed in between are revoked too).
	await DB.exec('UPDATE revoked_characters SET revoked_at = 1 WHERE 1');
	await DB.exec(run(['revoke', '--character', character]).stdout);
	assert.ok((await DB.prepare('SELECT revoked_at FROM revoked_characters WHERE character = ?').bind(character).first()).revoked_at > 1);
});

test('forget: the SQL that deletes an account\'s data, as forgetUser() does it, which D1 takes', { skip }, async () => {
	const [viaSql, viaCore] = [await makeD1(), await makeD1()];
	if (!viaSql) return;
	const GONE = '300000000000000077';
	const KEPT = '300000000000000088';
	for (const DB of [viaSql, viaCore]) {
		for (const [who, name, r] of [[GONE, 'Gone One', 'AAAAAAAAAA'], [KEPT, 'Kept One', 'BBBBBBBBBB']]) {
			await DB.prepare('INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?)')
				.bind(`${name}-ClassicBetaPvP`, who, 'Olympus II', 'w', 'Alliance', r, 1780000000)
				.run();
			await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(r, who, name.toLowerCase().replace(' ', '.'), 'c', '00000000', 1780000000, 1780086400, 'x', 'discord')
				.run();
			await DB.prepare('INSERT INTO inbox_uploads (source, r, discord_id, requester, uploaded, status, reason) VALUES (?, ?, ?, ?, ?, ?, ?)')
				.bind('site', r, who, `${name}-ClassicBetaPvP`, 1780000100, 'linked', 'linked')
				.run();
			// The proof that counted for its link, and the record of an authority's key for its character.
			await DB.prepare('INSERT INTO used (r, key_id, t) VALUES (?, ?, ?)').bind(r, 'council01', 1780000100).run();
			await DB.prepare('INSERT INTO council_keys (public_key, key_id, character, cert_exp, first_seen) VALUES (?, ?, ?, ?, ?)')
				.bind(publicHexOf(r.charCodeAt(0).toString(16).repeat(32)), r.charCodeAt(0).toString(16).repeat(6), `${name}-ClassicBetaPvP`, 1790000000, 1780000100)
				.run();
		}
		// Another account's try at the forgotten account's character: that log line names it too.
		await DB.prepare('INSERT INTO inbox_uploads (source, r, discord_id, requester, uploaded, status, reason) VALUES (?, ?, ?, ?, ?, ?, ?)')
			.bind('site', 'CCCCCCCCCC', KEPT, 'Gone One-ClassicBetaPvP', 1780000200, 'rejected', 'linked-elsewhere')
			.run();
		for (const [id, seed, who, revokedAt] of [['goneold1', '21', GONE, 1771000000], ['gonenew1', '22', GONE, null], ['keptkey1', '23', KEPT, null]]) {
			await DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, character, kind, bootstrap, created, cert_exp, revoked, revoked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(id, publicHexOf(seed.repeat(32)), who, 'some.one', `${id}-ClassicBetaPvP`, 'p', 0, 1770000000, 1790000000, revokedAt ? 1 : 0, revokedAt)
				.run();
		}
	}
	const r = run(['forget', GONE]);
	assert.equal(r.status, 0, r.stderr);
	await viaSql.exec(r.stdout);
	const t = nowS();
	assert.equal((await forgetUser({ DB: viaCore }, GONE, t)).status, 'ok');
	// "now" is unixepoch() in the SQL and t in forgetUser: the same minute.
	const dump = async (DB) => {
		const out = {};
		for (const table of ['members', 'codes', 'inbox_uploads', 'keys', 'used', 'council_keys', 'revoked_keys']) {
			const rows = (await DB.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all()).results;
			out[table] = rows.map((x) => (x.revoked_at && Math.abs(x.revoked_at - t) < 60 ? { ...x, revoked_at: 'now' } : x));
		}
		return out;
	};
	const [sql, core] = [await dump(viaSql), await dump(viaCore)];
	assert.deepEqual(sql, core);
	for (const table of ['members', 'codes', 'inbox_uploads']) assert.deepEqual(sql[table].map((x) => x.discord_id), [KEPT], table);
	assert.deepEqual(sql.inbox_uploads.map((x) => x.requester), ['Kept One-ClassicBetaPvP']);
	assert.deepEqual(sql.used.map((x) => x.r), ['BBBBBBBBBB']);
	assert.deepEqual(sql.council_keys.map((x) => x.character), ['Kept One-ClassicBetaPvP']);
	// Its keys: gone, their ids on the revocation list only (Konig's review: rows were left behind).
	assert.deepEqual(sql.keys.map((k) => [k.key_id, k.revoked, k.revoked_at, k.owner_username]), [['keptkey1', 0, null, 'some.one']]);
	assert.deepEqual(sql.revoked_keys.map((k) => [k.key_id, k.revoked_at]), [['goneold1', 1771000000], ['gonenew1', 'now']]);
	assert.equal(JSON.stringify(sql).includes(GONE), false, 'the forgotten account is named nowhere');
});

test('public: the public key of a seed on stdin', { skip }, () => {
	const seed = Buffer.alloc(32, 7).toString('base64url');
	const r = run(['public'], { input: `${seed}\n` });
	assert.equal(r.status, 0, r.stderr);
	assert.equal(r.stdout.trim(), publicHexOf(Buffer.alloc(32, 7).toString('hex')));
	assert.notEqual(run(['public'], { input: 'not a seed' }).status, 0);
});

test('ca: the council authority, once: its seed in dist/LinkCA.lua for the author\'s game alone, never printed; its public key for the addon and the Worker', { skip }, async () => {
	const dir = mkdtempSync(join(tmpdir(), 'olympus-ca-'));
	try {
		const r = run(['ca'], { cwd: dir });
		assert.equal(r.status, 0, r.stderr);
		assert.deepEqual(readdirSync(dir), ['dist']);
		assert.deepEqual(readdirSync(join(dir, 'dist')), ['LinkCA.lua']);
		const file = join(dir, 'dist', 'LinkCA.lua');
		assert.equal(statSync(file).mode & 0o777, 0o600, 'readable by its owner alone');
		const text = readFileSync(file, 'utf8');
		assert.match(text, /^-- Local only/);
		assert.match(text, /^local _, ns = \.\.\.$/m);
		const seed = /^ns\.LINK_CA_SEED = "([A-Za-z0-9_-]{43})"$/m.exec(text)[1];
		assert.ok(!r.stdout.includes(seed) && !r.stderr.includes(seed), 'the seed is never printed');
		assert.ok(!r.stdout.includes(seedHex(seed)));
		const pub = r.stdout.match(/^ {2}([0-9a-f]{64})$/m)[1];
		assert.equal(publicHexOf(seedHex(seed)), pub);
		assert.match(r.stdout, /ns\.LINK_CA_KEYS/);
		assert.match(r.stdout, /LINK_CA_PUBLIC/);
		assert.match(r.stdout, /Olympus\.toc/);
		// Made once: a second run changes nothing; "ca public" prints the same key again.
		const again = run(['ca'], { cwd: dir });
		assert.notEqual(again.status, 0);
		assert.equal(again.stdout, '');
		assert.equal(readFileSync(file, 'utf8'), text);
		const shown = run(['ca', 'public'], { cwd: dir });
		assert.equal(shown.status, 0, shown.stderr);
		assert.equal(shown.stdout.trim(), pub);
		assert.ok(!shown.stdout.includes(seed));
		assert.notEqual(run(['ca', 'public'], { cwd: join(dir, 'dist') }).status, 0, 'no file there');
		// The Worker takes a councillor's certificate signed with that seed (LINK_CA_PUBLIC = pub).
		const key = crypto.randomBytes(32).toString('hex');
		const kpub = publicHexOf(key);
		const keyId = crypto.createHash('sha256').update(Buffer.from(kpub, 'hex')).digest('hex').slice(0, 12);
		const payload = `OLK2.${keyId}.${Buffer.from(kpub, 'hex').toString('base64url')}.c.1830000000.Some Councillor-ClassicBetaPvP`;
		const cert = `${payload}.${sign(seedHex(seed), Buffer.from(payload, 'utf8')).toString('base64url')}`;
		assert.ok(await councilCertificate({ LINK_CA_PUBLIC: pub }, parseCertificate(cert)));
		assert.equal(await councilCertificate({ LINK_CA_PUBLIC: BACKEND_PUB }, parseCertificate(cert)), null);
		// The addon's Lua reads the file as the game loads it (a file of the toc: the addon's name and namespace).
		const lua = spawnSync('luajit', ['-e', `local ns = {} assert(loadfile(${JSON.stringify(file)}))("Olympus", ns) io.write(ns.LINK_CA_SEED)`], { encoding: 'utf8' });
		if (lua.error === undefined) assert.equal(lua.stdout, seed);
		// Revoking one of its keys: the revocation list, which D1 takes.
		const DB = await makeD1();
		if (DB) {
			const revoke = run(['revoke', keyId]);
			assert.equal(revoke.status, 0, revoke.stderr);
			await DB.exec(revoke.stdout);
			assert.ok(await DB.prepare('SELECT 1 AS x FROM revoked_keys WHERE key_id = ?').bind(keyId).first());
		}
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});
