// Olympus Link: every request this page makes, and the Discord sign-in. The page is static (GitHub
// Pages); the Olympus bot's Worker checks each link and gives the role (web/FERN.md). One request
// leaves the browser, when the player sends a link:
//   POST <CONFIG.PROOF_URL>  {"text": "<the link>", "discordToken": "<the Discord sign-in>"}
// or, to the same address, when the player deletes his own link ("Delete my link"):
//   POST <CONFIG.PROOF_URL>  {"forget": true, "discordToken": "<the Discord sign-in>"}
//   (with "Authorization: Bearer <CONFIG.SITE_TOKEN>" when config.js has one; never a cookie)
// The sign-in is Discord's own page (OAuth2, the implicit grant, scope identify): it comes back to
// this page with a token in the address's fragment, which the page reads, checks against the
// state it sent, removes from the address at once, and keeps for this tab only (sessionStorage).
// With ?demo=<state> in the address a demo answers instead: fake data, and nothing is ever sent.

import { CONFIG } from './config.js';

export const DISCORD_AUTHORIZE = 'https://discord.com/oauth2/authorize';
export const TOKEN_LIFE_MAX = 7 * 86400; // Discord's implicit grant: a week at most, no refresh
const TOKEN_RE = /^[A-Za-z0-9._~+/-]{10,256}={0,2}$/;
const CLIENT_ID_RE = /^[0-9]{5,25}$/;
const STATE_RE = /^[0-9a-f]{32}$/;

// True once config.js names the bot's /proof (https; http only on this computer, for a local
// test with wrangler dev) and its Discord application.
export function isConfigured(config = CONFIG) {
	return proofUrl(config) !== null && CLIENT_ID_RE.test(String(config.DISCORD_CLIENT_ID || ''));
}

function proofUrl(config) {
	try {
		const u = new URL(String(config.PROOF_URL || ''));
		const local = u.protocol === 'http:' && (u.hostname === 'localhost' || u.hostname === '127.0.0.1');
		return (u.protocol === 'https:' || local) && !u.username && !u.password && !u.hash ? u : null;
	} catch {
		return null;
	}
}

// The one request: { url, init } for fetch. No cookie, no referrer, nothing but the link and the
// sign-in in the body (and the site token, when there is one, in its header).
export function proofRequest(config, text, discordToken) {
	return request(config, { text, discordToken });
}

// "Delete my link": the same request to the same address, with {"forget": true} for the link.
export function forgetRequest(config, discordToken) {
	return request(config, { forget: true, discordToken });
}

function request(config, body) {
	const headers = { Accept: 'application/json', 'Content-Type': 'application/json' };
	if (config.SITE_TOKEN) headers.Authorization = `Bearer ${config.SITE_TOKEN}`;
	return {
		url: String(config.PROOF_URL),
		init: {
			method: 'POST',
			mode: 'cors',
			credentials: 'omit',
			cache: 'no-store',
			referrerPolicy: 'no-referrer',
			headers,
			body: JSON.stringify(body),
		},
	};
}

// The bot's answer to one of them, as the page reads it; a network or bot failure says so.
async function answerOf(fetchImpl, { url, init }) {
	let res;
	try {
		res = await fetchImpl(url, init);
	} catch {
		return { status: 'error', reason: 'server', message: '', characters: [] };
	}
	let data = null;
	try {
		data = await res.json();
	} catch {
		data = null;
	}
	if (data && typeof data.status === 'string') return { characters: [], ...data };
	const reason = res.status === 401 ? 'login' : res.status === 429 ? 'limit' : 'server';
	return { status: 'error', reason, message: '', characters: [] };
}

// The page's own folder (no query, no fragment): the redirect registered with Discord.
export function redirectUri(href) {
	const u = new URL('./', href);
	return `${u.origin}${u.pathname}`;
}

// Discord's sign-in page for this page: the token comes back in the fragment (response_type=token).
export function authorizeUrl(config, { state, redirect }) {
	const q = new URLSearchParams({ client_id: String(config.DISCORD_CLIENT_ID), response_type: 'token', scope: 'identify', redirect_uri: redirect, state });
	return `${DISCORD_AUTHORIZE}?${q}`;
}

// A fresh state: 128 random bits, kept in this tab until Discord sends it back.
export function newState(cryptoImpl = globalThis.crypto) {
	return Array.from(cryptoImpl.getRandomValues(new Uint8Array(16)), (b) => b.toString(16).padStart(2, '0')).join('');
}

// What Discord put in the address when it came back to the page:
//   { kind: 'none' }                   nothing of Discord's
//   { kind: 'token', token, exp }       signed in (exp in milliseconds)
//   { kind: 'bad-state' }               not the answer to this tab's sign-in: the token is dropped
//   { kind: 'denied' } / { kind: 'error' }
// `expected` is the state this tab sent (null when it has none: every answer is then refused).
export function readSignIn({ hash = '', search = '' } = {}, expected = null, nowMs = Date.now()) {
	const frag = new URLSearchParams(String(hash).replace(/^#/, ''));
	const query = new URLSearchParams(String(search).replace(/^\?/, ''));
	const src = frag.has('access_token') || frag.has('error') ? frag : query.has('error') ? query : null;
	if (!src) return { kind: 'none' };
	const state = src.get('state');
	if (!expected || !STATE_RE.test(expected) || state !== expected) return { kind: 'bad-state' };
	if (src.has('error')) return { kind: src.get('error') === 'access_denied' ? 'denied' : 'error' };
	const token = src.get('access_token') || '';
	const type = (src.get('token_type') || '').toLowerCase();
	const scopes = (src.get('scope') || 'identify').split(/[\s+]+/);
	if (!TOKEN_RE.test(token) || type !== 'bearer' || !scopes.includes('identify')) return { kind: 'error' };
	const life = Number(src.get('expires_in'));
	const seconds = Number.isFinite(life) && life > 0 ? Math.min(life, TOKEN_LIFE_MAX) : 3600;
	return { kind: 'token', token, exp: nowMs + seconds * 1000 };
}

// True when the address holds a sign-in answer (to take out of it at once).
export function hasSignIn({ hash = '', search = '' } = {}) {
	const frag = new URLSearchParams(String(hash).replace(/^#/, ''));
	return frag.has('access_token') || frag.has('error') || new URLSearchParams(String(search).replace(/^\?/, '')).has('error');
}

export function createBackend({ config = CONFIG, demo = null, fetchImpl = globalThis.fetch && globalThis.fetch.bind(globalThis) } = {}) {
	if (demo) return demoBackend(demo);
	return {
		demo: null,
		configured: isConfigured(config),
		loginUrl: (state, redirect) => authorizeUrl(config, { state, redirect }),
		// { status: 'linked' | 'rejected' | 'error', reason, message, username, characters }
		submit: (text, token) => answerOf(fetchImpl, proofRequest(config, text, token)),
		// { status: 'forgotten' | 'error', reason, message, username, characters (the ones removed) }
		forget: (token) => answerOf(fetchImpl, forgetRequest(config, token)),
	};
}

// ---------------------------------------------------------------------------
// The demo: made-up answers from the shared test vectors (throwaway test keys).

export const DEMO_STATES = ['code', 'wait', 'screen', 'scanning', 'phone', 'other', 'pick', 'scanned', 'found', 'done', 'error', 'forget', 'forgotten', 'closed'];

export const DEMO_DATA = {
	username: 'some.player',
	bundles: [
		'OLB5~Some Player-ClassicBetaPvP~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990100,council01,Test Councillor-ClassicBetaPvP,w,wYG_TW3fCOBxV9hteWMsnq2R8sBus8YaG-Dyb4SePjkl9a9Ub27i1okdpFxUh5aQASIZKKcXQbv0ocuXxvObBA,7IYl-lN-5QRTFG9QwpjrKSJZDGDe17VK3p6FcCpwIZs,c,1830000000,kuaVPJGR4ZwtCf2mtveDYem8nJmMfU-R4I-FndUaJCswUEoqDNECnB_oFNIj3DPMA18UgHkSK7L7X1oWZSMDCQ',
		'OLB5~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~9c5ac51afcd0bbee~1799990200,player01,Other Player-ClassicBetaPvP,r,jRr01ESNDrVEohLRRZYhLAVPD9ue32uDrRA2GQByQq2dsCQ-6o79nFWcL__shopaQ2Umy1aV9f8sDIaMQLzyBw,Yjfcw2R7CZXwgVo0oGVBVINj902ipPdUFBXVgiRdQho,p,1830000000,VVCteYcVvEC94tf4AYXgFoqVIMF3lwmT0Oa_wHjjDReZqnCqwc3dBRyRa2_lsdC82VETV6yC1ynAfYkO0218Aw;1799990245,player02,Third Player-ClassicBetaPvP2,c,K7sW12b4A_uTxycWnR8rRE1Ip3wzAxA2GYOgNMitKtbx1KfI6IxWMJLEu2oEoJ042TuWxlbk_RU6k81b4kuEAA,htzUCCfLy2CLRBnMSvsaaOs2uAArII8FmYoNuitPTLo,p,1830000000,AhXwg-IeO7pvCaCiMB99vAmq4z4LEIC2jOfExrd_baQIEOcGeh9O_oyPxJKQqioKuXc3Am3z_o4BsMtEa-EnAg;1799990301,player03,Fourth Player-ClassicBetaPvP,c,7sEYRUmeAZOZyqJUGu8_hZ_O2Mn8mFuWIKdWMTJ_0Zs4KYzelPEDfnjfq3bcU-uYal7tiPtuBY6zijo0mJCqDQ,JLeqzhWvuMSECSheqOK6rAiEtujmqmRBiSWaxXxgfH0,p,1830000000,C-wMIwi74DAQG3gPlNQTdiJZctpBv1fZWJs8XEPKWtOn6YjuNoZAOgYpIaGdnfUtQhdltBlfutRcejytbpdmAQ',
	],
};

function demoBackend(state) {
	const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
	const never = () => new Promise(() => {});
	return {
		demo: state,
		configured: state !== 'closed',
		loginUrl: () => '#demo-login',
		async submit(bundle) {
			if (state === 'found') return never(); // the screenshot shows it sending
			await wait(700);
			if (state === 'error') {
				return { status: 'rejected', reason: 'expired', message: 'This code expired more than 7 days ago.', characters: [] };
			}
			const requester = String(bundle).split('~')[1] || 'Some Player-ClassicBetaPvP';
			return { status: 'linked', reason: 'linked', message: `${requester} is now linked.`, username: DEMO_DATA.username, characters: [requester, 'Some Alt-ClassicBetaPvP'] };
		},
		async forget() {
			await wait(700);
			return { status: 'forgotten', reason: 'forgotten', message: '', username: DEMO_DATA.username, characters: ['Some Player-ClassicBetaPvP', 'Some Alt-ClassicBetaPvP'] };
		},
	};
}

// The page's backend: the demo when the address asks for one.
const params = new URLSearchParams((globalThis.location && globalThis.location.search) || '');
const demo = params.get('demo');
export const backend = createBackend({ demo: demo && DEMO_STATES.includes(demo) ? demo : null });
export const DEMO = backend.demo;
