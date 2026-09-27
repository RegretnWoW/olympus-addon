// The page's backend calls (web/public/backend.js) against the Worker's routes, the demo that
// never touches the network, and the two languages of the page.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createBackend, BackendError, DEMO_STATES, DEMO_DATA } from '../public/backend.js';
import { strings, pickLang, fill } from '../public/i18n.js';
import { parseToken, checkBundle } from '../public/core.js';
import { vectors } from './helpers.mjs';

function stubFetch(answers) {
	const calls = [];
	const fetchImpl = async (url, init) => {
		calls.push({ url, init });
		const a = answers[url];
		if (!a) throw new TypeError('network down');
		return new Response(a.body === undefined ? null : JSON.stringify(a.body), { status: a.status || 200 });
	};
	return { calls, fetchImpl };
}

test('backend: me() is the user, or null when signed out', async () => {
	const user = { id: '1', username: 'some_player', global_name: 'Some Player', avatar: null };
	let s = stubFetch({ '/api/link/me': { body: { user } } });
	assert.deepEqual(await createBackend({ fetchImpl: s.fetchImpl }).me(), user);
	assert.equal(s.calls[0].init.method, 'GET');
	assert.equal(s.calls[0].init.credentials, 'same-origin');
	s = stubFetch({ '/api/link/me': { status: 401, body: { user: null } } });
	assert.equal(await createBackend({ fetchImpl: s.fetchImpl }).me(), null);
	s = stubFetch({ '/api/link/me': { status: 500 } });
	await assert.rejects(createBackend({ fetchImpl: s.fetchImpl }).me(), BackendError);
	s = stubFetch({});
	await assert.rejects(createBackend({ fetchImpl: s.fetchImpl }).me(), (e) => e.reason === 'server');
	assert.equal(createBackend({ fetchImpl: s.fetchImpl }).loginUrl('/link/?lang=pt'), '/login?next=%2Flink%2F%3Flang%3Dpt');
});

test('backend: code() is the token, errors carry the Worker\'s reason', async () => {
	const token = vectors.backend.tokens[0].token;
	let s = stubFetch({ '/api/link/code': { body: { token, command: `/oly discord ${token}` } } });
	assert.equal(await createBackend({ fetchImpl: s.fetchImpl }).code(), token);
	assert.equal(s.calls[0].init.method, 'POST');
	assert.equal(s.calls[0].init.headers['Content-Type'], 'application/json');
	s = stubFetch({ '/api/link/code': { status: 429, body: { status: 'error', reason: 'limit', message: 'x' } } });
	await assert.rejects(createBackend({ fetchImpl: s.fetchImpl }).code(), (e) => e.reason === 'limit' && e.status === 429);
});

test('backend: submit(bundle) sends the bundle and returns the Worker\'s answer', async () => {
	const bundle = vectors.bundles[0].bundle;
	const answer = { status: 'linked', reason: 'linked', message: 'ok', characters: ['Some Player-ClassicBetaPvP'] };
	let s = stubFetch({ '/api/link/submit': { body: answer } });
	assert.deepEqual(await createBackend({ fetchImpl: s.fetchImpl }).submit(bundle), answer);
	assert.deepEqual(JSON.parse(s.calls[0].init.body), { bundle });
	s = stubFetch({ '/api/link/submit': { status: 200, body: { status: 'rejected', reason: 'expired', message: 'm' } } });
	assert.deepEqual(await createBackend({ fetchImpl: s.fetchImpl }).submit(bundle), { status: 'rejected', reason: 'expired', message: 'm', characters: [] });
	s = stubFetch({ '/api/link/submit': { status: 401 } });
	assert.equal((await createBackend({ fetchImpl: s.fetchImpl }).submit(bundle)).reason, 'login');
	s = stubFetch({ '/api/link/submit': { status: 502 } });
	assert.equal((await createBackend({ fetchImpl: s.fetchImpl }).submit(bundle)).reason, 'server');
});

test('demo: every state answers without a network call, with the vectors\' data', async () => {
	const fetchImpl = () => {
		throw new Error('the demo must not call the network');
	};
	for (const state of DEMO_STATES) {
		const b = createBackend({ demo: state, fetchImpl });
		assert.equal(b.demo, state);
		const user = await b.me();
		assert.equal(user === null, state === 'login' || state === 'scanned', state);
		assert.ok(!b.loginUrl('/').startsWith('/login'), state);
		if (state === 'found') continue; // it stays "sending" for its screenshot
		if (state === 'code') assert.ok(parseToken(await b.code()).ok);
		if (state === 'done' || state === 'error') {
			const r = await b.submit(DEMO_DATA.bundles[0]);
			assert.equal(r.status, state === 'done' ? 'linked' : 'rejected');
		}
	}
	assert.equal(DEMO_DATA.token, vectors.backend.tokens[0].token);
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
	for (const lang of ['en', 'pt']) {
		for (const [k, v] of Object.entries(strings[lang])) if (typeof v === 'string') assert.ok(v.trim() !== '', `${lang}.${k}`);
	}
	// The exact lines the page must say.
	assert.equal(strings.en.loginNote, 'We only see your Discord name and avatar.');
	assert.equal(strings.en.privacy, 'Your screen and files stay on your computer. Only the signed link is sent.');
	assert.match(strings.en.waitWatcher, /^You can also just wait: your role arrives when Fernmelder's watcher is online\./);
	assert.equal(fill('{n} of {total}', { n: 2, total: 5 }), '2 of 5');
	assert.equal(fill('{missing}', {}), '{missing}');
});
