// The page's settings (web/public/config.js), the one request it makes and the Discord sign-in
// (web/public/backend.js), the demo that never touches the network, and the two languages of the
// page. No network here: fetch is a stub that records what the page would send.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { CONFIG } from '../public/config.js';
import { createBackend, isConfigured, proofRequest, forgetRequest, authorizeUrl, redirectUri, newState, readSignIn, hasSignIn, DEMO_STATES, DEMO_DATA, TOKEN_LIFE_MAX } from '../public/backend.js';
import { strings, pickLang, fill } from '../public/i18n.js';
import { checkBundle } from '../public/core.js';
import { PROOF_REASONS } from '../worker/link-core.mjs';
import { REPO, vectors } from './helpers.mjs';

const PAGE = 'https://dnl-gentile.github.io/olympus-addon/';
const READY = { ...CONFIG, PROOF_URL: 'https://bot.example.workers.dev/proof', DISCORD_CLIENT_ID: '300000000000000123', SITE_TOKEN: '' };
const TOKEN = 'dGVzdC1hY2Nlc3MtdG9rZW4tZm9yLXRoZS1wYWdl'; // a made-up access token
const STATE = '0123456789abcdef0123456789abcdef';

function stubFetch(answer) {
	const calls = [];
	const fetchImpl = async (url, init) => {
		calls.push({ url, init });
		if (!answer) throw new TypeError('network down');
		return new Response(answer.body === undefined ? null : JSON.stringify(answer.body), { status: answer.status || 200 });
	};
	return { calls, fetchImpl };
}

test('config.js: the page\'s address is the addon\'s, and the bot\'s settings are placeholders or real ones', () => {
	assert.deepEqual(Object.keys(CONFIG).sort(), ['DISCORD_CLIENT_ID', 'PAGE_URL', 'PROOF_URL', 'SITE_TOKEN', 'VERIFY_COMMAND']);
	assert.equal(CONFIG.PAGE_URL, PAGE);
	// The QR code and the copy box open the same address (Olympus/Link.lua), with the link after #.
	const lua = readFileSync(join(REPO, 'Olympus', 'Link.lua'), 'utf8');
	assert.equal(/^ns\.LINK_SITE = "([^"]*)"$/m.exec(lua)[1], CONFIG.PAGE_URL);
	assert.equal(redirectUri(`${PAGE}index.html?lang=pt#b=OLB5~x`), PAGE, 'the Discord redirect is the page\'s folder');
	assert.match(CONFIG.VERIFY_COMMAND, /^\/[a-z0-9_-]{1,32}$/);
	assert.equal(typeof CONFIG.SITE_TOKEN, 'string');
	// Either the bot is not named yet (the page says Olympus Link is not open) or it is, all of it.
	const placeholders = /^PASTE-/.test(CONFIG.PROOF_URL) && /^PASTE-/.test(CONFIG.DISCORD_CLIENT_ID);
	assert.ok(placeholders || isConfigured(CONFIG), 'PROOF_URL (https) and DISCORD_CLIENT_ID (digits) together');
	assert.equal(isConfigured(CONFIG), !placeholders);
});

test('index.html: the Content-Security-Policy lets the page reach the bot\'s /proof and nothing else', () => {
	const html = readFileSync(join(REPO, 'web', 'public', 'index.html'), 'utf8');
	const csp = /http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html)[1];
	const connect = (/(?:^|;\s*)connect-src ([^;]+)/.exec(csp) || [])[1].trim().split(/\s+/);
	const allowed = ["'self'"];
	if (isConfigured(CONFIG)) allowed.push(new URL(CONFIG.PROOF_URL).origin);
	assert.deepEqual(connect.sort(), allowed.sort(), 'connect-src: the page itself and the bot\'s /proof');
	assert.doesNotMatch(csp, /\*/, 'no wildcard anywhere');
	assert.match(csp, /(?:^|;\s*)default-src 'self'(?:;|$)/);
	assert.match(html, /<meta name="referrer" content="no-referrer">/);
	// Every address of the page's own files is relative: it runs under /olympus-addon/.
	for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
		const u = m[1];
		if (/^https:\/\/fonts\.(googleapis|gstatic)\.com(\/|$)/.test(u) || u.startsWith('#')) continue;
		assert.ok(!u.startsWith('/') && !/^[a-z]+:/i.test(u), `relative: ${u}`);
	}
	for (const file of ['app.js', 'backend.js', 'scanner.js', 'qr-worker.js', 'core.js']) {
		const src = readFileSync(join(REPO, 'web', 'public', file), 'utf8');
		assert.doesNotMatch(src, /(?:fetch|Worker|importScripts|assign)\(\s*['"`]\//, `${file}: no path from the site's root`);
	}
});

test('isConfigured: an https /proof and a Discord application id, or the page stays closed', () => {
	assert.equal(isConfigured(READY), true);
	assert.equal(isConfigured({ ...READY, PROOF_URL: 'PASTE-THE-PROOF-URL-HERE' }), false);
	assert.equal(isConfigured({ ...READY, PROOF_URL: 'http://bot.example/proof' }), false, 'never in the clear');
	assert.equal(isConfigured({ ...READY, PROOF_URL: 'http://localhost:8787/proof' }), true, 'but on this computer (wrangler dev)');
	assert.equal(isConfigured({ ...READY, PROOF_URL: 'https://user:pw@bot.example/proof' }), false);
	assert.equal(isConfigured({ ...READY, DISCORD_CLIENT_ID: 'PASTE-THE-DISCORD-CLIENT-ID-HERE' }), false);
	assert.equal(isConfigured({ ...READY, DISCORD_CLIENT_ID: '12ab' }), false);
});

test('the one request: POST {text, discordToken} to /proof, no cookie, no referrer, the site token only when there is one', () => {
	const bundle = vectors.bundles[0].bundle;
	let { url, init } = proofRequest(READY, bundle, TOKEN);
	assert.equal(url, READY.PROOF_URL);
	assert.equal(init.method, 'POST');
	assert.equal(init.mode, 'cors');
	assert.equal(init.credentials, 'omit');
	assert.equal(init.referrerPolicy, 'no-referrer');
	assert.equal(init.cache, 'no-store');
	assert.deepEqual(init.headers, { Accept: 'application/json', 'Content-Type': 'application/json' });
	assert.deepEqual(JSON.parse(init.body), { text: bundle, discordToken: TOKEN });
	assert.deepEqual(Object.keys(JSON.parse(init.body)), ['text', 'discordToken'], 'nothing else in the body');
	({ url, init } = proofRequest({ ...READY, SITE_TOKEN: 'page-token-123' }, bundle, TOKEN));
	assert.equal(init.headers.Authorization, 'Bearer page-token-123');
	assert.deepEqual(JSON.parse(init.body), { text: bundle, discordToken: TOKEN }, 'the site token never in the body');
});

test('submit(): sends that request and returns the bot\'s answer; a network or bot failure says so', async () => {
	const bundle = vectors.bundles[0].bundle;
	const answer = { status: 'linked', reason: 'linked', message: 'ok', username: 'some.player', characters: ['Some Player-ClassicBetaPvP'] };
	let s = stubFetch({ body: answer });
	assert.deepEqual(await createBackend({ config: READY, fetchImpl: s.fetchImpl }).submit(bundle, TOKEN), answer);
	assert.equal(s.calls.length, 1);
	assert.deepEqual(s.calls[0], proofRequest(READY, bundle, TOKEN));
	s = stubFetch({ body: { status: 'rejected', reason: 'expired', message: 'm' } });
	assert.deepEqual(await createBackend({ config: READY, fetchImpl: s.fetchImpl }).submit(bundle, TOKEN), { status: 'rejected', reason: 'expired', message: 'm', characters: [] });
	s = stubFetch({ status: 401, body: { status: 'error', reason: 'login', message: 'x' } });
	assert.equal((await createBackend({ config: READY, fetchImpl: s.fetchImpl }).submit(bundle, TOKEN)).reason, 'login');
	for (const [status, reason] of [[401, 'login'], [429, 'limit'], [502, 'server']]) {
		s = stubFetch({ status });
		assert.equal((await createBackend({ config: READY, fetchImpl: s.fetchImpl }).submit(bundle, TOKEN)).reason, reason, String(status));
	}
	s = stubFetch(null);
	assert.deepEqual(await createBackend({ config: READY, fetchImpl: s.fetchImpl }).submit(bundle, TOKEN), { status: 'error', reason: 'server', message: '', characters: [] });
	assert.equal(createBackend({ config: READY, fetchImpl: s.fetchImpl }).configured, true);
	assert.equal(createBackend({ config: { ...READY, PROOF_URL: '' }, fetchImpl: s.fetchImpl }).configured, false);
});

test('"Delete my link": the same request to the same address, with {"forget": true} and the sign-in only (Konig\'s review)', async () => {
	const { url, init } = forgetRequest(READY, TOKEN);
	assert.equal(url, READY.PROOF_URL, 'the bot\'s /proof: nothing new to allow in connect-src');
	assert.deepEqual([init.method, init.mode, init.credentials, init.referrerPolicy, init.cache], ['POST', 'cors', 'omit', 'no-referrer', 'no-store']);
	assert.deepEqual(JSON.parse(init.body), { forget: true, discordToken: TOKEN });
	assert.equal(forgetRequest({ ...READY, SITE_TOKEN: 'page-token-123' }, TOKEN).init.headers.Authorization, 'Bearer page-token-123');
	const answer = { status: 'forgotten', reason: 'forgotten', message: 'm', username: 'some.player', characters: ['Some Player-ClassicBetaPvP'] };
	let s = stubFetch({ body: answer });
	assert.deepEqual(await createBackend({ config: READY, fetchImpl: s.fetchImpl }).forget(TOKEN), answer);
	assert.deepEqual(s.calls, [forgetRequest(READY, TOKEN)]);
	for (const [status, reason] of [[401, 'login'], [429, 'limit'], [502, 'server']]) {
		s = stubFetch({ status });
		assert.equal((await createBackend({ config: READY, fetchImpl: s.fetchImpl }).forget(TOKEN)).reason, reason, String(status));
	}
	s = stubFetch(null);
	assert.deepEqual(await createBackend({ config: READY, fetchImpl: s.fetchImpl }).forget(TOKEN), { status: 'error', reason: 'server', message: '', characters: [] });
	// The demo answers without the network.
	const demo = createBackend({ demo: 'forget', fetchImpl: () => { throw new Error('no network in the demo'); } });
	assert.equal((await demo.forget('demo')).status, 'forgotten');
	// Its words, in both languages; a character linked elsewhere is told about it.
	for (const lang of ['en', 'pt']) {
		for (const k of ['forgetOpen', 'forgetTitle', 'forgetText', 'forgetWho', 'forgetSignIn', 'forgetButton', 'forgetCancel', 'forgetSending', 'forgetFailed', 'forgetLogin', 'forgetServer', 'forgetDoneTitle', 'forgetDoneText', 'forgetDoneNone', 'forgetDoneCharacters', 'forgetBack']) {
			assert.ok(typeof strings[lang][k] === 'string' && strings[lang][k].trim(), `${lang}.${k}`);
		}
		assert.ok(strings[lang].errors['linked-elsewhere'].includes(strings[lang].forgetOpen), `${lang}: linked-elsewhere names the page's "${strings[lang].forgetOpen}"`);
	}
});

test('the sign-in: Discord\'s own page, the implicit grant, identify only, back to the page\'s folder with this tab\'s state', () => {
	const u = new URL(authorizeUrl(READY, { state: STATE, redirect: PAGE }));
	assert.equal(`${u.origin}${u.pathname}`, 'https://discord.com/oauth2/authorize');
	assert.deepEqual(Object.fromEntries(u.searchParams), { client_id: READY.DISCORD_CLIENT_ID, response_type: 'token', scope: 'identify', redirect_uri: PAGE, state: STATE });
	assert.equal(createBackend({ config: READY }).loginUrl(STATE, PAGE), u.href);
	const a = newState();
	const b = newState();
	assert.match(a, /^[0-9a-f]{32}$/);
	assert.notEqual(a, b);
});

test('the answer from Discord: the token with this tab\'s state only, never another\'s, and nothing when there is none', () => {
	const now = 1_800_000_000_000;
	const back = (params) => ({ hash: `#${new URLSearchParams(params)}`, search: '' });
	const good = { token_type: 'Bearer', access_token: TOKEN, expires_in: '604800', scope: 'identify', state: STATE };
	assert.deepEqual(readSignIn(back(good), STATE, now), { kind: 'token', token: TOKEN, exp: now + 604800 * 1000 });
	assert.equal(hasSignIn(back(good)), true);
	// Another state, or none kept in this tab (a sign-in started elsewhere): the token is dropped.
	assert.deepEqual(readSignIn(back(good), 'ffffffffffffffffffffffffffffffff', now), { kind: 'bad-state' });
	assert.deepEqual(readSignIn(back(good), null, now), { kind: 'bad-state' });
	assert.deepEqual(readSignIn(back({ ...good, state: undefined }), STATE, now), { kind: 'bad-state' });
	// Refusals and oddities.
	assert.deepEqual(readSignIn(back({ error: 'access_denied', state: STATE }), STATE, now), { kind: 'denied' });
	assert.deepEqual(readSignIn({ hash: '', search: `?error=invalid_scope&state=${STATE}` }, STATE, now), { kind: 'error' });
	assert.deepEqual(readSignIn(back({ ...good, token_type: 'Basic' }), STATE, now), { kind: 'error' });
	assert.deepEqual(readSignIn(back({ ...good, access_token: 'x y' }), STATE, now), { kind: 'error' });
	assert.deepEqual(readSignIn(back({ ...good, scope: 'guilds' }), STATE, now), { kind: 'error' });
	assert.equal(readSignIn(back({ ...good, expires_in: String(30 * 86400) }), STATE, now).exp, now + TOKEN_LIFE_MAX * 1000, 'a week at most');
	// A link from the game, or nothing: not a sign-in.
	for (const where of [{ hash: '#b=OLB5~x', search: '' }, { hash: '', search: '?lang=pt' }, {}]) {
		assert.deepEqual(readSignIn(where, STATE, now), { kind: 'none' });
		assert.equal(hasSignIn(where), false);
	}
});

test('demo: every state answers without a network call, with the vectors\' data', async () => {
	const fetchImpl = () => {
		throw new Error('the demo must not call the network');
	};
	for (const state of DEMO_STATES) {
		const b = createBackend({ demo: state, fetchImpl });
		assert.equal(b.demo, state);
		assert.equal(b.configured, state !== 'closed', state);
		assert.ok(!b.loginUrl('s', PAGE).startsWith('https:'), state);
		if (state === 'found') continue; // it stays "sending" for its screenshot
		if (state === 'done' || state === 'error') {
			const r = await b.submit(DEMO_DATA.bundles[0], 'demo');
			assert.equal(r.status, state === 'done' ? 'linked' : 'rejected');
		}
	}
	assert.deepEqual(DEMO_DATA.bundles, [vectors.bundles[0].bundle, vectors.bundles[1].bundle]);
	for (const text of DEMO_DATA.bundles) assert.ok(checkBundle(text).ok);
});

test('languages: English by default, Portuguese for "pt", the same keys in both', () => {
	assert.equal(pickLang(null, 'pt-BR'), 'pt');
	assert.equal(pickLang(null, 'pt-PT'), 'pt');
	assert.equal(pickLang(null, 'en-US'), 'en');
	assert.equal(pickLang(null, 'es'), 'en');
	assert.equal(pickLang(null, undefined), 'en');
	assert.equal(pickLang('pt', 'en-US'), 'pt');
	assert.equal(pickLang('xx', 'pt-BR'), 'pt');
	const keys = (o, prefix = '') =>
		Object.entries(o)
			.flatMap(([k, v]) => (v && typeof v === 'object' && !Array.isArray(v) ? keys(v, `${prefix}${k}.`) : [`${prefix}${k}`]))
			.sort();
	assert.deepEqual(keys(strings.pt), keys(strings.en));
	assert.equal(strings.pt.steps.length, strings.en.steps.length);
	assert.equal(strings.en.steps.length, 4, 'your code, in game, read it, done');
	for (const lang of ['en', 'pt']) {
		for (const [k, v] of Object.entries(strings[lang])) if (typeof v === 'string') assert.ok(v.trim() !== '', `${lang}.${k}`);
		assert.match(strings[lang].codeStep1, /\{command\}/, `${lang}: the bot's command, from config.js`);
	}
	// The exact lines the page must say.
	assert.equal(strings.en.loginNote, 'We only see your Discord name and avatar.');
	assert.equal(strings.en.privacy, 'Your screen and files stay on your computer. Only the signed link is sent.');
	assert.match(strings.en.waitWatcher, /^You can also just wait: your role arrives when Fernmelder's watcher is online\./);
	assert.equal(fill('{n} of {total}', { n: 2, total: 5 }), '2 of 5');
	assert.equal(fill('{missing}', {}), '{missing}');
});

test('the code step warns about streams, in both languages', () => {
	assert.match(strings.en.codeStream, /on stream/);
	assert.match(strings.en.codeStream, /Olympus Link window/);
	assert.match(strings.pt.codeStream, /em live/);
	assert.match(strings.pt.codeStream, /janela do Olympus Link/);
	assert.match(strings.en.waitStream, /off the stream/);
	assert.match(strings.pt.waitStream, /fora da transmissão/);
});

test('every answer the bot\'s /proof can give has its words, in both languages', () => {
	for (const r of PROOF_REASONS) {
		if (r === 'linked' || r === 'already' || r === 'forgotten') continue; // success: the done step (the deleted one for forgotten)
		assert.ok(strings.en.errors[r], `en: ${r}`);
		assert.ok(strings.pt.errors[r], `pt: ${r}`);
	}
	// And every refusal or error the core and the reference Worker write is one of them, or a tool's.
	const tools = new Set(['auth', 'method', 'username', 'unknown-key', 'key-id-used', 'public-key-used', 'owner-has-key', 'character-not-linked', 'revoked', 'replaced', 'too-early']);
	const src = ['link-core.mjs', 'link-worker.js'].map((f) => readFileSync(join(REPO, 'web', 'worker', f), 'utf8')).join('\n');
	const reasons = new Set([...src.matchAll(/(?:reject|failure|fail)\('([a-z-]+)'/g), ...src.matchAll(/reason: '([a-z-]+)'/g)].map((m) => m[1]));
	for (const r of ['tag', 'guild-unverified', 'not-enough', 'discord', 'server', 'login', 'origin', 'site', 'limit']) assert.ok(reasons.has(r), r);
	for (const r of reasons) assert.ok(PROOF_REASONS.includes(r) || tools.has(r), `${r}: in PROOF_REASONS, or a tool's`);
});
