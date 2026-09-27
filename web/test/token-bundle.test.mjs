// Code tokens and bundles as the page reads them (web/public/core.js), against the vectors and
// the Worker's own parser (they must agree).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
	parseToken,
	tokenCommand,
	worstCaseCommandLength,
	CHAT_LINE_MAX,
	parseBundle,
	buildBundle,
	signedMessage,
	linkUrl,
	bundleFromText,
	parseFragment,
	checkBundle,
	splitCharacter,
	b64urlEncode,
	b64urlDecode,
	canonicalB64url,
	utf8Length,
} from '../public/core.js';
import { parseBundle as workerParse, signedMessage as workerMessage } from '../worker/link-worker.js';
import { vectors } from './helpers.mjs';

const [TOKEN_C, TOKEN_A] = vectors.backend.tokens;
const [B1, B3, B4] = vectors.bundles;

test('tokens: the vectors parse, from both ends (usernames may hold dots)', () => {
	const c = parseToken(TOKEN_C.token);
	assert.ok(c.ok);
	assert.deepEqual({ R: c.token.R, username: c.token.username, exp: c.token.exp, mode: c.token.mode }, { R: '7K3M9Q2XWD', username: 'some_player', exp: TOKEN_C.exp, mode: 'c' });
	assert.equal(c.token.payload, TOKEN_C.payload);
	const a = parseToken(TOKEN_A.token);
	assert.ok(a.ok);
	assert.equal(a.token.username, 'tester.two');
	assert.equal(a.token.mode, 'a');
	assert.equal(a.token.payload, TOKEN_A.payload);
});

test('tokens: spaces around it and the whole command are fine', () => {
	assert.equal(parseToken(`   ${TOKEN_C.token}\t\n`).token.raw, TOKEN_C.token);
	assert.equal(parseToken(`/oly discord ${TOKEN_C.token}`).token.raw, TOKEN_C.token);
	assert.equal(parseToken(`  /OLY DISCORD   ${TOKEN_C.token} `).token.raw, TOKEN_C.token);
	assert.equal(tokenCommand(TOKEN_C.token), `/oly discord ${TOKEN_C.token}`);
});

test('tokens: malformed ones are refused, each for its reason', () => {
	const t = TOKEN_C;
	const sig = t.signature_b64url;
	const cases = [
		['', 'empty'],
		['OLC2.7K3M9Q2XWD.some_player.1790086400.c.' + sig, 'prefix'],
		['OLC1.7K3M9Q2XWD.1790086400.c.' + sig, 'fields'],
		['OLC1.7K3M9Q2XWO.some_player.1790086400.c.' + sig, 'code'], // O is not in the alphabet
		['OLC1.7k3m9q2xwd.some_player.1790086400.c.' + sig, 'code'],
		['OLC1.7K3M9Q2XWD.Some_Player.1790086400.c.' + sig, 'username'],
		['OLC1.7K3M9Q2XWD.a.1790086400.c.' + sig, 'username'],
		[`OLC1.7K3M9Q2XWD.${'x'.repeat(33)}.1790086400.c.${sig}`, 'username'],
		['OLC1.7K3M9Q2XWD.some-player.1790086400.c.' + sig, 'username'],
		['OLC1.7K3M9Q2XWD.some_player.0179008640.c.' + sig, 'exp'],
		['OLC1.7K3M9Q2XWD.some_player.1790086400.x.' + sig, 'mode'],
		['OLC1.7K3M9Q2XWD.some_player.1790086400.c.' + sig.slice(1), 'sig'],
		['OLC1.7K3M9Q2XWD.some_player.1790086400.c.' + sig + '=', 'sig'],
		['OLC1.7K3M9Q2XWD.some_player.1790086400.c.' + sig.slice(0, 85) + 'B', 'sig'], // stray low bits
	];
	for (const [input, error] of cases) assert.deepEqual(parseToken(input), { ok: false, error }, input);
});

test('tokens: the longest "/oly discord <token>" fits the chat line', () => {
	assert.ok(worstCaseCommandLength() <= CHAT_LINE_MAX, `${worstCaseCommandLength()} > ${CHAT_LINE_MAX}`);
	assert.equal(worstCaseCommandLength(), 163);
	assert.ok(utf8Length(tokenCommand(TOKEN_A.token)) < 160);
});

test('bundles: the vectors parse and rebuild byte for byte, here and in the Worker', () => {
	for (const v of vectors.bundles) {
		const parsed = parseBundle(v.bundle);
		assert.ok(parsed.ok, `${v.name}: ${parsed.error}`);
		assert.equal(buildBundle(parsed.bundle), v.bundle);
		assert.equal(parsed.bundle.proofs.length, v.proofs.length);
		assert.deepEqual(parsed.bundle.proofs.map((p) => signedMessage(parsed.bundle, p)), v.messages);
		const w = workerParse(v.bundle);
		assert.ok(w.ok);
		assert.deepEqual(w.bundle, parsed.bundle);
		assert.deepEqual(w.bundle.proofs.map((p) => workerMessage(w.bundle, p)), v.messages);
		assert.equal(utf8Length(v.bundle), v.bytes);
	}
	assert.equal(splitCharacter(B3.requester).name, 'Tëst Plâyer');
	assert.equal(splitCharacter(B3.requester).realm, 'ClassicBetaPvP');
});

test('bundles: malformed ones are refused, here and in the Worker', () => {
	const f = B1.bundle.split('~');
	const proof = f[6].split(',');
	const with6 = (i, value) => f.map((x, k) => (k === i ? value : x)).join('~');
	const withProof = (i, value) => with6(6, proof.map((x, k) => (k === i ? value : x)).join(','));
	const bad = [
		['OLB3' + B1.bundle.slice(4), 'prefix'],
		[B1.bundle + '~extra', 'fields'],
		[with6(1, 'NoRealm'), 'requester'],
		[with6(1, '-ClassicBetaPvP'), 'requester'],
		[with6(1, 'Some Player-'), 'requester'],
		[with6(1, 'Some Player-Classic BetaPvP'), 'requester'], // a realm as the game writes it has no space
		[with6(1, `${'x'.repeat(50)}-${'y'.repeat(14)}`), 'requester'], // 65 bytes
		[with6(1, 'Some\tPlayer-ClassicBetaPvP'), 'requester'],
		[with6(2, ''), 'guild'],
		[with6(2, 'x'.repeat(41)), 'guild'],
		[with6(2, 'Olympus|cff'), 'guild'],
		[with6(3, 'Neutral'), 'faction'],
		[with6(4, '0123456789ABCDEF'), 'nonce'],
		[with6(4, '0123456789abcde'), 'nonce'],
		[with6(5, '7K3M9Q2XW'), 'code'],
		[with6(6, ''), 'noProofs'],
		[withProof(0, '01790000123'), 'issued'],
		[withProof(1, 'TESTCOUNCIL1'), 'keyId'],
		[withProof(1, 'abc'), 'keyId'],
		[withProof(2, 'NoRealm'), 'confirmer'],
		[withProof(2, 'Test Councillor-Classic BetaPvP'), 'confirmer'],
		[withProof(3, proof[3].slice(0, 85)), 'sig'],
		[withProof(3, proof[3].slice(0, 85) + 'B'), 'sig'],
		[with6(6, new Array(5).fill(f[6]).join(';')), 'proofs'],
		[with6(6, `${f[6]};`), 'proof'],
		[with6(6, `;${f[6]}`), 'proof'],
	];
	for (const [text, error] of bad) {
		assert.deepEqual(parseBundle(text), { ok: false, error }, text);
		assert.equal(workerParse(text).ok, false, text);
	}
	assert.equal(parseBundle('OLB4~' + 'x'.repeat(1600)).error, 'size');
	assert.equal(parseBundle(B4.bundle).ok, true);
});

test('bundles: whatever the addon\'s Link.Parse takes, the page and the Worker take too', () => {
	const f = B1.bundle.split('~');
	const with6 = (i, value) => f.map((x, k) => (k === i ? value : x)).join('~');
	const good = [
		with6(1, 'Two-Dashes-Realm'), // Link.ValidName: the realm is what follows the last dash
		with6(1, ' Some Player-ClassicBetaPvP'),
		with6(1, `${'x'.repeat(49)}-${'y'.repeat(14)}`), // 64 bytes
		with6(1, `${'é'.repeat(24)}-${'y'.repeat(15)}`), // 64 bytes of UTF-8
		with6(2, 'x'.repeat(40)),
		with6(2, ' Olympus '),
		// Proofs the addon would never pair (the same key twice, the requester as confirmer)
		// still read: the Worker counts each key and owner once and refuses the rest.
		with6(6, [f[6], f[6]].join(';')),
		with6(6, f[6].replace('Test Councillor-ClassicBetaPvP', f[1])),
	];
	for (const text of good) {
		assert.equal(parseBundle(text).ok, true, text);
		assert.equal(workerParse(text).ok, true, text);
		assert.equal(buildBundle(parseBundle(text).bundle), text);
	}
	assert.equal(checkBundle(good[6]).confirmations, 1);
	assert.equal(parseBundle(with6(1, `${'é'.repeat(25)}-${'y'.repeat(14)}`)).error, 'requester'); // 65 bytes
});

test('links: the URL of the QR and copy box round-trips, whatever the encoding', () => {
	for (const v of vectors.bundles) {
		assert.equal(bundleFromText(v.url), v.bundle, v.name); // python's quote(safe='')
		const url = linkUrl(vectors.site, v.bundle); // the page's encodeURIComponent
		assert.equal(bundleFromText(url), v.bundle);
		assert.equal(bundleFromText(`  ${url}\n`), v.bundle);
		assert.equal(bundleFromText(v.bundle), v.bundle); // the bundle itself
		assert.equal(bundleFromText(`#b=${encodeURIComponent(v.bundle)}`), v.bundle);
		assert.equal(bundleFromText(`b=${encodeURIComponent(v.bundle)}`), v.bundle);
		// Spaces as "+", and non-ASCII left raw: both decode.
		assert.equal(bundleFromText(`${vectors.site}#b=${v.bundle.replace(/ /g, '+')}`), v.bundle);
		assert.deepEqual(parseFragment(`#b=${encodeURIComponent(v.bundle)}`), { kind: 'bundle', text: v.bundle });
	}
	assert.equal(bundleFromText('https://example.org/#b=%E0%A4%A'), null);
	assert.equal(bundleFromText('hello'), null);
	assert.deepEqual(parseFragment(''), { kind: 'none' });
	assert.deepEqual(parseFragment('#access_token=x'), { kind: 'none' });
	assert.deepEqual(parseFragment('#b=garbage'), { kind: 'bad-bundle' });
});

test('checkBundle: what the page shows, and the code check', () => {
	const r = checkBundle(B3.bundle, 'H4N8PZ6R1B');
	assert.equal(r.ok, true);
	assert.equal(r.character, 'Tëst Plâyer');
	assert.equal(r.realm, 'ClassicBetaPvP');
	assert.equal(r.confirmations, 3);
	assert.equal(r.matchesCode, true);
	assert.equal(checkBundle(B3.bundle, '7K3M9Q2XWD').matchesCode, false);
	assert.equal(checkBundle(B3.bundle, null).matchesCode, null);
	assert.equal(checkBundle(B4.bundle).confirmations, 4);
	assert.deepEqual(checkBundle('OLB4~x', null).ok, false);
	assert.equal(checkBundle(B1.bundle.split('~').slice(0, 6).join('~') + '~', null).error, 'noProofs');
});

test('base64url: canonical only', () => {
	const bytes = new Uint8Array(64).map((_, i) => (i * 37 + 11) & 255);
	const s = b64urlEncode(bytes);
	assert.equal(s, Buffer.from(bytes).toString('base64url'));
	assert.deepEqual(b64urlDecode(s), bytes);
	assert.ok(canonicalB64url(s, 64));
	assert.equal(canonicalB64url(s, 63), false);
	assert.equal(canonicalB64url(`${s.slice(0, 85)}B`, 64), false);
	for (let n = 0; n < 40; n++) {
		const b = new Uint8Array(n).map((_, i) => (i * 91 + n) & 255);
		assert.equal(b64urlEncode(b), Buffer.from(b).toString('base64url'));
		assert.deepEqual(Buffer.from(b64urlDecode(Buffer.from(b).toString('base64url'))), Buffer.from(b));
	}
});
