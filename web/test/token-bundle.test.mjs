// Code tokens and bundles as the page reads them (web/public/core.js), against the vectors and
// the Worker's own parser (they must agree).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
	parseToken,
	tokenCommand,
	maskedCommand,
	worstCaseCommandLength,
	CHAT_LINE_MAX,
	parseBundle,
	buildBundle,
	signedMessage,
	linkTag,
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
import { parseBundle as workerParse, signedMessage as workerMessage, linkTag as workerTag } from '../worker/link-worker.js';
import { vectors } from './helpers.mjs';

const [TOKEN_C, TOKEN_A] = vectors.backend.tokens;
const [B1, B3, B4] = vectors.bundles;

test('tokens: the vectors parse, from both ends (usernames may hold dots)', () => {
	const c = parseToken(TOKEN_C.token);
	assert.ok(c.ok);
	assert.deepEqual(
		{ R: c.token.R, username: c.token.username, exp: c.token.exp, mode: c.token.mode, T: c.token.T },
		{ R: '7K3M9QX2TB', username: 'some.player', exp: TOKEN_C.exp, mode: 'c', T: '00000000' },
	);
	assert.equal(c.token.payload, TOKEN_C.payload);
	assert.equal(c.token.sig, TOKEN_C.signature_b64url);
	const a = parseToken(TOKEN_A.token);
	assert.ok(a.ok);
	assert.equal(a.token.username, 'tester.two');
	assert.equal(a.token.mode, 'a');
	assert.equal(a.token.T, TOKEN_A.T);
	assert.equal(a.token.payload, TOKEN_A.payload);
});

test('tokens: spaces around it and the whole command are fine, /oly or /olympus, any case', () => {
	assert.equal(parseToken(`   ${TOKEN_C.token}\t\n`).token.raw, TOKEN_C.token);
	assert.equal(parseToken(`/oly discord ${TOKEN_C.token}`).token.raw, TOKEN_C.token);
	assert.equal(parseToken(`  /OLY DISCORD   ${TOKEN_C.token} `).token.raw, TOKEN_C.token);
	assert.equal(parseToken(`/olympus discord ${TOKEN_C.token}`).token.raw, TOKEN_C.token);
	assert.equal(parseToken(`/Olympus Discord ${TOKEN_C.token}`).token.raw, TOKEN_C.token);
	assert.equal(parseToken(`/oly ${TOKEN_C.token}`).error, 'prefix');
	assert.equal(tokenCommand(TOKEN_C.token), `/oly discord ${TOKEN_C.token}`);
});

test('tokens: the page shows none of the token until it is clicked', () => {
	const masked = maskedCommand();
	assert.match(masked, /^\/oly discord OLC2\.•+$/);
	for (const t of vectors.backend.tokens) {
		assert.ok(!masked.includes(t.R));
		assert.ok(!masked.includes(t.signature_b64url.slice(0, 8)));
	}
});

test('tokens: malformed ones are refused, each for its reason', () => {
	const sig = TOKEN_C.signature_b64url;
	const head = 'OLC2.7K3M9QX2TB.some.player.1800000000.c.00000000';
	const cases = [
		['', 'empty'],
		['/oly discord ', 'empty'],
		[`OLC1.7K3M9QX2TB.some.player.1800000000.c.${sig}`, 'prefix'], // the old format
		[`OLC2.7K3M9QX2TB.1800000000.c.00000000.${sig}`, 'fields'],
		[`OLC2.7K3M9QX2TO.some.player.1800000000.c.00000000.${sig}`, 'code'], // O is not in the alphabet
		[`OLC2.7k3m9qx2tb.some.player.1800000000.c.00000000.${sig}`, 'code'],
		[`OLC2.7K3M9QX2TB.Some.Player.1800000000.c.00000000.${sig}`, 'username'],
		[`OLC2.7K3M9QX2TB.a.1800000000.c.00000000.${sig}`, 'username'],
		[`OLC2.7K3M9QX2TB.${'x'.repeat(33)}.1800000000.c.00000000.${sig}`, 'username'],
		[`OLC2.7K3M9QX2TB.some-player.1800000000.c.00000000.${sig}`, 'username'],
		[`OLC2.7K3M9QX2TB.some.player.0180000000.c.00000000.${sig}`, 'exp'],
		[`OLC2.7K3M9QX2TB.some.player.1800000000.x.00000000.${sig}`, 'mode'],
		[`OLC2.7K3M9QX2TB.some.player.1800000000.c.0000000.${sig}`, 'draw'],
		[`OLC2.7K3M9QX2TB.some.player.1800000000.c.FFFFFFFF.${sig}`, 'draw'],
		[`OLC2.7K3M9QX2TB.some.player.1800000000.c.${sig}`, 'exp'], // no T: read from the end, every field is one off
		[`${head}.${sig.slice(1)}`, 'sig'],
		[`${head}.${sig}=`, 'sig'],
		[`${head}.${sig.slice(0, 85)}B`, 'sig'], // stray low bits
	];
	for (const [input, error] of cases) assert.deepEqual(parseToken(input), { ok: false, error }, input);
});

test('tokens: the longest "/oly discord <token>" fits the chat line', () => {
	assert.ok(worstCaseCommandLength() <= CHAT_LINE_MAX, `${worstCaseCommandLength()} > ${CHAT_LINE_MAX}`);
	assert.equal(worstCaseCommandLength(), 172);
	assert.ok(utf8Length(tokenCommand(TOKEN_A.token)) < 170);
});

test('the tag: SHA-256 of the token\'s signature and the requester, as python makes it, here and in the Worker', async () => {
	for (const b of vectors.bundles) {
		const token = vectors.backend.tokens.find((t) => t.R === b.R);
		assert.equal(b.tag_input, `${token.signature_b64url}~${b.requester}`);
		assert.equal(await linkTag(token.signature_b64url, b.requester), b.tag, b.name);
		assert.equal(await workerTag(token.signature_b64url, b.requester), b.tag, b.name);
		assert.equal(parseBundle(b.bundle).bundle.tag, b.tag);
	}
	// Another requester, or another code's command, gives another tag.
	assert.notEqual(await linkTag(TOKEN_C.signature_b64url, 'Someone Else-ClassicBetaPvP'), B1.tag);
	assert.notEqual(await linkTag(TOKEN_A.signature_b64url, B1.requester), B1.tag);
	assert.match(B1.tag, /^[0-9a-f]{16}$/);
});

test('bundles: the vectors parse and rebuild byte for byte, here and in the Worker', () => {
	for (const v of vectors.bundles) {
		const parsed = parseBundle(v.bundle);
		assert.ok(parsed.ok, `${v.name}: ${parsed.error}`);
		assert.equal(buildBundle(parsed.bundle), v.bundle);
		assert.equal(parsed.bundle.proofs.length, v.proofs.length);
		assert.deepEqual(parsed.bundle.proofs.map((p) => p.gv), v.proofs.map((p) => p.gv));
		assert.deepEqual(parsed.bundle.proofs.map((p) => signedMessage(parsed.bundle, p)), v.messages);
		const w = workerParse(v.bundle);
		assert.ok(w.ok);
		assert.deepEqual(w.bundle, parsed.bundle);
		assert.deepEqual(w.bundle.proofs.map((p) => workerMessage(w.bundle, p)), v.messages);
		assert.equal(utf8Length(v.bundle), v.bytes);
	}
	// The signed text: OLY4~requester~guild~gv~faction~nonce~R~tag~issued~keyId~confirmer.
	assert.equal(B1.messages[0], `OLY4~Some Player-ClassicBetaPvP~Olympus II~w~Alliance~0123456789abcdef~7K3M9QX2TB~${B1.tag}~1799990100~council01~Test Councillor-ClassicBetaPvP`);
	assert.equal(splitCharacter(B3.requester).name, 'Tëst Plâyer');
	assert.equal(splitCharacter(B3.requester).realm, 'ClassicBetaPvP');
});

test('bundles: malformed ones are refused, here and in the Worker', () => {
	const f = B1.bundle.split('~');
	const proof = f[7].split(',');
	const withField = (i, value) => f.map((x, k) => (k === i ? value : x)).join('~');
	const withProof = (i, value) => withField(7, proof.map((x, k) => (k === i ? value : x)).join(','));
	const bad = [
		['OLB3' + B1.bundle.slice(4), 'prefix'],
		[B1.bundle + '~extra', 'fields'],
		[f.slice(0, 6).concat(f[7]).join('~'), 'fields'], // the old format: no tag
		[withField(1, 'NoRealm'), 'requester'],
		[withField(1, '-ClassicBetaPvP'), 'requester'],
		[withField(1, 'Some Player-'), 'requester'],
		[withField(1, 'Some Player-Classic BetaPvP'), 'requester'], // a realm as the game writes it has no space
		[withField(1, `${'x'.repeat(50)}-${'y'.repeat(14)}`), 'requester'], // 65 bytes
		[withField(1, 'Some\tPlayer-ClassicBetaPvP'), 'requester'],
		[withField(2, ''), 'guild'],
		[withField(2, 'x'.repeat(41)), 'guild'],
		[withField(2, 'Olympus|cff'), 'guild'],
		[withField(3, 'Neutral'), 'faction'],
		[withField(4, '0123456789ABCDEF'), 'nonce'],
		[withField(4, '0123456789abcde'), 'nonce'],
		[withField(5, '7K3M9QX2T'), 'code'],
		[withField(6, B1.tag.toUpperCase()), 'tag'],
		[withField(6, B1.tag.slice(1)), 'tag'],
		[withField(6, ''), 'tag'],
		[withField(7, ''), 'noProofs'],
		[withProof(0, '01799990100'), 'issued'],
		[withProof(1, 'COUNCIL01'), 'keyId'],
		[withProof(1, 'abc'), 'keyId'],
		[withProof(2, 'NoRealm'), 'confirmer'],
		[withProof(2, 'Test Councillor-Classic BetaPvP'), 'confirmer'],
		[withProof(3, 'x'), 'gv'],
		[withProof(3, 'R'), 'gv'],
		[withProof(3, 'toString'), 'gv'],
		[withProof(3, ''), 'gv'],
		[withProof(4, proof[4].slice(0, 85)), 'sig'],
		[withProof(4, proof[4].slice(0, 85) + 'B'), 'sig'],
		[withField(7, [proof[0], proof[1], proof[2], proof[4]].join(',')), 'proof'], // the old proof: no gv
		[withField(7, new Array(5).fill(f[7]).join(';')), 'proofs'],
		[withField(7, `${f[7]};`), 'proof'],
		[withField(7, `;${f[7]}`), 'proof'],
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
	const withField = (i, value) => f.map((x, k) => (k === i ? value : x)).join('~');
	const good = [
		withField(1, 'Two-Dashes-Realm'), // Link.ValidName: the realm is what follows the last dash
		withField(1, ' Some Player-ClassicBetaPvP'),
		withField(1, `${'x'.repeat(49)}-${'y'.repeat(14)}`), // 64 bytes
		withField(1, `${'é'.repeat(24)}-${'y'.repeat(15)}`), // 64 bytes of UTF-8
		withField(2, 'x'.repeat(40)),
		withField(2, ' Olympus '),
		// Proofs the addon would never pair (the same key twice, the requester as confirmer)
		// still read: the Worker counts each key and owner once and refuses the rest.
		withField(7, [f[7], f[7]].join(';')),
		withField(7, f[7].replace('Test Councillor-ClassicBetaPvP', f[1])),
		withField(7, f[7].replace(',w,', ',r,')),
		withField(7, f[7].replace(',w,', ',c,')),
	];
	for (const text of good) {
		assert.equal(parseBundle(text).ok, true, text);
		assert.equal(workerParse(text).ok, true, text);
		assert.equal(buildBundle(parseBundle(text).bundle), text);
	}
	assert.equal(checkBundle(good[6]).confirmations, 1);
	assert.equal(parseBundle(withField(1, `${'é'.repeat(25)}-${'y'.repeat(14)}`)).error, 'requester'); // 65 bytes
});

test('bundles: the largest there can be stays well under 1600 bytes', () => {
	const proof = ['9'.repeat(12), 'k'.repeat(16), `${'é'.repeat(24)}-${'y'.repeat(15)}`, 'r', 'A'.repeat(85) + 'A'].join(',');
	const text = ['OLB4', `${'é'.repeat(24)}-${'y'.repeat(15)}`, 'x'.repeat(40), 'Alliance', '0'.repeat(16), '7K3M9QX2TB', 'f'.repeat(16), new Array(4).fill(proof).join(';')].join('~');
	assert.equal(parseBundle(text).ok, true);
	assert.ok(utf8Length(text) <= 1000, `${utf8Length(text)} bytes`);
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
		// The link never carries the token: not its signature, the tag's secret.
		const token = vectors.backend.tokens.find((t) => t.R === v.R);
		assert.ok(!v.url.includes(token.signature_b64url) && !v.bundle.includes(token.signature_b64url));
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
	assert.equal(checkBundle(B3.bundle, '7K3M9QX2TB').matchesCode, false);
	assert.equal(checkBundle(B3.bundle, null).matchesCode, null);
	assert.equal(checkBundle(B4.bundle).confirmations, 4);
	assert.deepEqual(checkBundle('OLB4~x', null).ok, false);
	assert.equal(checkBundle(B1.bundle.split('~').slice(0, 7).join('~') + '~', null).error, 'noProofs');
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
