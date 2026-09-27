// Olympus.lua as the page reads it (bundles found by their text, the one of this code
// preferred) and as the watcher tool reads it (the inbox only, never the key).

import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { bundlesFromSavedVariables, pickBundle, unescapeLua, MAX_FILE_BYTES } from '../public/core.js';
import { parseSavedVariables, inboxBundles, readInbox } from '../tools/read-inbox.mjs';
import { vectors } from './helpers.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/Olympus.lua', import.meta.url));
const TOOL = fileURLToPath(new URL('../tools/read-inbox.mjs', import.meta.url));
const text = readFileSync(FIXTURE, 'utf8');
const [B1, B3, B4] = vectors.bundles;
const SEED = vectors.keys.find((k) => k.key_id === 'testcouncil1').seed_b64url;

test('the page: every bundle in the file, in order, once', () => {
	const found = bundlesFromSavedVariables(text);
	assert.deepEqual(found.map((f) => f.text), [B3.bundle, B1.bundle, B4.bundle]);
	assert.equal(found[0].bundle.requester, 'Tëst Plâyer-ClassicBetaPvP');
	assert.ok(text.includes('"OLB4~not-a-bundle"') || text.includes('\\"OLB4~not-a-bundle\\"'));
});

test('the page: the bundle of this code first, else the only one, else a choice', () => {
	const found = bundlesFromSavedVariables(text);
	const mine = pickBundle(found, '7K3M9Q2XWD');
	assert.equal(mine.kind, 'one');
	assert.equal(mine.choice.text, B1.bundle);
	const two = pickBundle(found, 'H4N8PZ6R1B'); // two requests made with one code
	assert.equal(two.kind, 'many');
	assert.deepEqual(two.choices.map((c) => c.text), [B3.bundle, B4.bundle]);
	assert.equal(pickBundle(found, null).kind, 'many');
	assert.equal(pickBundle(found, null).choices.length, 3);
	assert.equal(pickBundle([found[1]], 'ZZZZZZZZZZ').kind, 'one');
	assert.equal(pickBundle([], 'ZZZZZZZZZZ').kind, 'none');
	assert.equal(MAX_FILE_BYTES, 30 * 1024 * 1024);
});

test('the page: Lua string escapes as WoW writes them', () => {
	assert.equal(unescapeLua('a\\"b\\\\c\\nd\\9e'), 'a"b\\c\nd\te');
	assert.equal(unescapeLua('\\195\\171'), 'ë'); // UTF-8 bytes written as decimal escapes
	assert.equal(unescapeLua('raw ë'), 'raw ë');
	assert.equal(unescapeLua('\\q'), 'q');
	assert.equal(unescapeLua('\\300'), null);
	assert.equal(unescapeLua('\\255'), null); // not UTF-8
	const escaped = B3.bundle.replace('ë', '\\195\\171');
	assert.deepEqual(bundlesFromSavedVariables(`X = { "${escaped}" }`).map((f) => f.text), [B3.bundle]);
});

test('the tool: a SavedVariables parser for what WoW writes', () => {
	const sv = parseSavedVariables(text);
	const db = sv.OlympusDB;
	assert.equal(db.configVersion, 3);
	assert.equal(db.ratio, 0.75);
	assert.equal(db.negative, -12);
	assert.equal(db.off, false);
	assert.equal(db.discord.watcher, true);
	assert.equal(db.log[1], '---- session 42, v0.9.10, realm ClassicBetaPvP, census ClassicBetaPvP, Horde ----');
	assert.equal(db.log[2], 'said "hello"\nand left, with a \\ in it\t(tab)');
	assert.equal(db.discord.chars['Ëlüñé Stârwhîspêr-ClassicBetaPvP2'].bundle, B4.bundle);
	// As in Lua, the positional "z" is [1] and wins over the earlier [1] = "x".
	const more = parseSavedVariables('A = { [1] = "x", y = 2, "z", "w", [ [[long]] ] = [==[a]]b]==], } -- end\nB = nil\nC = 0x1F\n');
	assert.deepEqual(more.A, { 1: 'z', 2: 'w', y: 2, long: 'a]]b' });
	assert.equal(more.B, null);
	assert.equal(more.C, 31);
	assert.throws(() => parseSavedVariables('A = { "unfinished }'), SyntaxError);
	assert.throws(() => parseSavedVariables('A = { 1 2 }'), SyntaxError);
});

test('the tool: the inbox, oldest first, malformed entries skipped', () => {
	const { bundles, skipped } = inboxBundles(parseSavedVariables(text));
	assert.deepEqual(bundles, [
		{ R: B1.R, bundle: B1.bundle, from: 'Some Player-ClassicBetaPvP', t: 1790000130 },
		{ R: B3.R, bundle: B3.bundle, from: 'Tëst Plâyer-ClassicBetaPvP', t: 1790000310 },
	]);
	assert.deepEqual(skipped.sort(), ['QQQQQQQQQQ', 'RRRRRRRRRR']); // wrong R for its bundle; not a bundle
	assert.deepEqual(inboxBundles(parseSavedVariables('OlympusDB = { }')), { bundles: [], skipped: [] });
	assert.deepEqual(inboxBundles({}), { bundles: [], skipped: [] });
	assert.deepEqual(readInbox(FIXTURE).bundles.map((b) => b.R), [B1.R, B3.R]);
});

test('the tool: prints the POST body, never the key', () => {
	const r = spawnSync(process.execPath, [TOOL, FIXTURE], { encoding: 'utf8' });
	assert.equal(r.status, 0, r.stderr);
	const out = JSON.parse(r.stdout);
	assert.deepEqual(out.bundles.map((b) => b.bundle), [B1.bundle, B3.bundle]);
	assert.match(r.stderr, /2 links in the inbox, 2 malformed entries skipped/);
	assert.ok(!r.stdout.includes(SEED) && !r.stderr.includes(SEED));
	assert.ok(!r.stdout.includes('"key"'));
	const usage = spawnSync(process.execPath, [TOOL], { encoding: 'utf8' });
	assert.equal(usage.status, 2);
	const missing = spawnSync(process.execPath, [TOOL, join(tmpdir(), 'no-such-dir-olympus', 'Olympus.lua')], { encoding: 'utf8' });
	assert.equal(missing.status, 1);
	const dir = mkdtempSync(join(tmpdir(), 'olympus-inbox-'));
	try {
		writeFileSync(join(dir, 'Olympus.lua'), 'OlympusDB = { ["discord"] = { ["inbox"] = { "broken }');
		const broken = spawnSync(process.execPath, [TOOL, join(dir, 'Olympus.lua')], { encoding: 'utf8' });
		assert.equal(broken.status, 1);
		assert.match(broken.stderr, /Cannot read/);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('the tool: --post sends them with the admin token (https, or a local address)', async () => {
	let got;
	const server = createServer((req, res) => {
		let body = '';
		req.on('data', (c) => (body += c));
		req.on('end', () => {
			got = { auth: req.headers.authorization, type: req.headers['content-type'], body: JSON.parse(body), url: req.url };
			res.writeHead(200, { 'Content-Type': 'application/json' });
			res.end(JSON.stringify({ results: [{ R: B1.R, status: 'linked' }] }));
		});
	});
	await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
	const url = `http://127.0.0.1:${server.address().port}/api/link/inbox`;
	try {
		const run = (args, token) =>
			new Promise((resolve) => {
				const child = spawn(process.execPath, [TOOL, ...args], { env: { ...process.env, LINK_ADMIN_TOKEN: token || '' } });
				let stdout = '';
				let stderr = '';
				child.stdout.on('data', (c) => (stdout += c));
				child.stderr.on('data', (c) => (stderr += c));
				child.on('close', (status) => resolve({ status, stdout, stderr }));
			});
		const noToken = await run([FIXTURE, '--post', url]);
		assert.equal(noToken.status, 2);
		const plain = await run([FIXTURE, '--post', 'http://example.org/api/link/inbox'], 'secret-admin-token');
		assert.equal(plain.status, 2);
		assert.match(plain.stderr, /https/);
		const r = await run([FIXTURE, '--post', url], 'secret-admin-token');
		assert.equal(r.status, 0, r.stderr);
		assert.equal(got.auth, 'Bearer secret-admin-token');
		assert.equal(got.type, 'application/json');
		assert.equal(got.url, '/api/link/inbox');
		assert.deepEqual(got.body.bundles.map((b) => b.R), [B1.R, B3.R]);
		assert.match(r.stdout, /"linked"/);
	} finally {
		server.close();
	}
});
