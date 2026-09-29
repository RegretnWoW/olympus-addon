// Olympus Link: the page, static (GitHub Pages). Get a code from the bot in Discord, type it in the
// game, then read the signed link the game shows (QR, text or Olympus.lua), sign in with Discord
// and send it to the bot, which checks it and gives the role. The formats live in core.js, the one
// request and the sign-in in backend.js, the settings in config.js, the QR reading in scanner.js,
// the words in i18n.js.

import {
	bundleFromText,
	parseFragment,
	checkBundle,
	splitCharacter,
	savedVariablesPath,
	detectOS,
	isMobileOS,
	canShareScreen,
	pathSystem,
	bundlesFromSavedVariables,
	pickBundle,
	GAMES,
	MAX_FILE_BYTES,
} from './core.js';
import { backend, DEMO, DEMO_DATA, newState, readSignIn, hasSignIn, redirectUri } from './backend.js';
import { CONFIG } from './config.js';
import { strings, pickLang, fill } from './i18n.js';
import { Scanner, readImageFile } from './scanner.js';

// ---------------------------------------------------------------------------
// Per-tab and per-browser conveniences (the page works without them, but for the sign-in, whose
// state and token live in this tab's sessionStorage only).

const store = {
	get(area, key) {
		try {
			const raw = globalThis[area].getItem(`olympus-link:${key}`);
			return raw ? JSON.parse(raw) : null;
		} catch {
			return null;
		}
	},
	set(area, key, value) {
		try {
			if (value === null || value === undefined) globalThis[area].removeItem(`olympus-link:${key}`);
			else globalThis[area].setItem(`olympus-link:${key}`, JSON.stringify(value));
		} catch {
			// private window or storage blocked: fine
		}
	},
};

// Back from Discord's sign-in: the address it came back to has no query, so the language (and the
// rest of the page's address) comes from what this tab kept when it left.
const RETURNING = hasSignIn(location) ? store.get('sessionStorage', 'signin') || {} : null;
const params = new URLSearchParams(RETURNING ? RETURNING.search || '' : location.search);
const lang = pickLang(params.get('lang'), navigator.language);
const T = strings[lang];
document.documentElement.lang = T.htmlLang;

const nav = { userAgent: navigator.userAgent, platform: (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform, maxTouchPoints: navigator.maxTouchPoints };
const OS = (DEMO && params.get('os')) || detectOS(nav);
const MOBILE = isMobileOS(OS);
const CAN_SHARE = DEMO ? !MOBILE : canShareScreen(OS, navigator.mediaDevices);
const CAN_CAMERA = DEMO || !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
const STEPS = ['code', 'wait', 'read', 'done'];

// ---------------------------------------------------------------------------
// State

const state = {
	ready: false,
	auth: null, // { token, exp }: the Discord sign-in of this tab
	username: null, // the Discord username the bot linked (its answer)
	step: 'code',
	closed: false, // config.js does not name the bot yet
	framed: false, // the page is inside another page's frame: it shows nothing to click there
	tab: null,
	notice: null, // { kind: 'info' | 'error', text }
	scan: null, // { kind: 'screen' | 'camera' } while a stream is being read
	found: null, // checkBundle() of the link read
	choices: null, // several links in one file
	sending: false,
	result: null, // the backend's answer
	scanned: false, // the page was opened by a phone's camera with a link in its address
	pathOS: pathSystem(OS),
	game: 'forever',
	root: '',
	elsewhere: false,
	copied: null,
	demoPreview: false,
};

const scanner = new Scanner({
	onTexts: (texts) => texts.some((t) => takeText(t, { quiet: true })),
	onStop: (why) => {
		state.scan = null;
		if (why === 'timeout') note('error', T.screenTimeout);
		else if (why === 'ended' && !state.found) note('info', T.screenEnded);
		render();
	},
});

function note(kind, text) {
	state.notice = text ? { kind, text } : null;
}

function go(step) {
	if (step !== 'read') stopScan();
	state.step = step;
	state.notice = null;
	render({ focusStep: true });
}

function stopScan() {
	if (scanner.active) scanner.stop(null);
	state.scan = null;
	state.demoPreview = false;
}

// ---------------------------------------------------------------------------
// Flow

async function start() {
	if (window.top !== window.self) {
		state.ready = true;
		state.framed = true;
		return render();
	}
	// What the address brings: a link from a phone's camera (#b=), or Discord's sign-in answer.
	// Either is taken out of the address at once: it stays in this tab only.
	const answer = RETURNING ? readSignIn(location, RETURNING.state || null) : { kind: 'none' };
	const frag = parseFragment(location.hash);
	if (RETURNING) {
		history.replaceState(null, '', location.pathname + (RETURNING.search || ''));
		store.set('sessionStorage', 'signin', null);
	} else if (frag.kind !== 'none') {
		history.replaceState(null, '', location.pathname + location.search);
		if (frag.kind === 'bundle') {
			store.set('sessionStorage', 'pending', frag.text);
			state.scanned = true;
		}
	}
	if (answer.kind === 'token') store.set('sessionStorage', 'auth', { token: answer.token, exp: answer.exp });
	const failed = answer.kind === 'none' || answer.kind === 'token' ? null : T.signInFailed[answer.kind] || T.signInFailed.error;
	state.auth = currentAuth();
	const pending = store.get('sessionStorage', 'pending');
	const savedTab = store.get('localStorage', 'tab');
	state.tab = tabs().some((t) => t.id === savedTab) ? savedTab : tabs()[0].id;
	state.ready = true;
	if (DEMO) return demo(DEMO);
	if (!backend.configured) {
		state.closed = true;
		return render();
	}
	if (pending) {
		state.step = 'read';
		render();
		takeBundle(pending);
	} else {
		state.step = 'code';
	}
	// A sign-in that did not come back right: said on the step the page opens on.
	if (failed) note('error', failed);
	render();
}

// This tab's Discord sign-in, while it has a minute left.
function currentAuth() {
	const a = store.get('sessionStorage', 'auth');
	if (a && typeof a.token === 'string' && Number(a.exp) > Date.now() + 60000) return a;
	if (a) store.set('sessionStorage', 'auth', null);
	return null;
}

// Off to Discord's sign-in page, which comes back here with a token. The link found so far waits
// in this tab meanwhile, and the state this tab sends is the one the answer must carry.
function signIn() {
	if (DEMO) {
		state.auth = { token: 'demo', exp: Infinity };
		if (state.found) send();
		else render();
		return;
	}
	const s = newState();
	store.set('sessionStorage', 'signin', { state: s, search: location.search });
	if ((store.get('sessionStorage', 'signin') || {}).state !== s) {
		note('error', T.signInFailed.storage);
		return render();
	}
	if (state.found) store.set('sessionStorage', 'pending', state.found.text);
	location.assign(backend.loginUrl(s, redirectUri(location.href)));
}

function signOut() {
	store.set('sessionStorage', 'auth', null);
	state.auth = null;
	state.username = null;
	render();
}

// A code problem: back to the step that says how to get a new one in Discord.
function codeAgain() {
	state.result = null;
	state.found = null;
	store.set('sessionStorage', 'pending', null);
	go('code');
}

// Text from a QR code, the paste box or a pasted clipboard. True when it was an Olympus link.
function takeText(text, { quiet = false } = {}) {
	const bundle = bundleFromText(text);
	if (!bundle) {
		if (!quiet) {
			note('error', T.badLink);
			render();
		}
		return false;
	}
	return takeBundle(bundle);
}

function takeBundle(text) {
	const check = checkBundle(text, null);
	if (!check.ok) {
		note('error', check.error === 'noProofs' ? T.noProofs : T.badLink);
		render();
		return false;
	}
	stopScan();
	state.found = check;
	state.choices = null;
	state.result = null;
	state.notice = null;
	state.step = 'read';
	if (!state.auth) {
		store.set('sessionStorage', 'pending', text);
		render({ focus: 'found' });
		return true;
	}
	send();
	return true;
}

async function send() {
	if (!state.found || state.sending) return;
	state.sending = true;
	state.result = null;
	render({ focus: 'found' });
	let result;
	try {
		result = await backend.submit(state.found.text, state.auth ? state.auth.token : '');
	} catch {
		result = { status: 'error', reason: 'server' };
	}
	state.sending = false;
	state.result = result;
	if (result.status === 'linked') {
		store.set('sessionStorage', 'pending', null);
		if (typeof result.username === 'string') state.username = result.username;
		go('done');
		return;
	}
	if (result.reason === 'login') {
		// The sign-in expired (or is not one for this bot): sign in again, the link waits.
		store.set('sessionStorage', 'auth', null);
		store.set('sessionStorage', 'pending', state.found.text);
		state.auth = null;
	}
	render({ focus: 'result' });
}

async function takeFile(file) {
	if (!file) return;
	if (/^image\//.test(file.type)) return takeImage(file);
	if (file.size > MAX_FILE_BYTES) {
		note('error', T.fileTooBig);
		return render();
	}
	note('info', fill(T.fileReading, { name: file.name }));
	render();
	let text;
	try {
		text = await file.text();
	} catch {
		note('error', T.fileUnreadable);
		return render();
	}
	const pick = pickBundle(bundlesFromSavedVariables(text), null);
	text = null; // the file's text is dropped here
	if (pick.kind === 'none') {
		note('error', T.fileNone);
		return render();
	}
	if (pick.kind === 'one') return takeBundle(pick.choice.text);
	state.choices = pick.choices.map((c) => c.text);
	note(null);
	render({ focus: 'choices' });
}

async function takeImage(blob) {
	note('info', T.imageReading);
	render();
	let texts = [];
	try {
		texts = await readImageFile(blob);
	} catch {
		texts = [];
	}
	if (!texts.some((t) => takeText(t, { quiet: true }))) {
		note('error', T.imageNone);
		render();
	}
}

async function startScan(kind) {
	note(null);
	if (DEMO) {
		state.scan = { kind };
		state.demoPreview = true;
		return render();
	}
	try {
		state.scan = { kind };
		render();
		await scanner.start(kind);
		render();
	} catch (err) {
		state.scan = null;
		const name = err && err.name;
		if (kind === 'camera' && (name === 'NotFoundError' || name === 'OverconstrainedError')) note('error', T.cameraNone);
		else note('error', kind === 'screen' ? T.screenDenied : T.cameraDenied);
		render();
	}
}

// ---------------------------------------------------------------------------
// Demo states (?demo=...): the page as it looks at each step, with made-up data.

function demo(which) {
	state.auth = which === 'scanned' ? null : { token: 'demo', exp: Infinity };
	switch (which) {
		case 'closed':
			state.closed = true;
			break;
		case 'code':
			state.step = 'code';
			break;
		case 'wait':
			state.step = 'wait';
			break;
		case 'screen':
		case 'phone':
		case 'other':
			state.step = 'read';
			state.tab = tabs().some((t) => t.id === which) ? which : tabs()[0].id;
			break;
		case 'scanning':
			state.step = 'read';
			state.tab = tabs()[0].id;
			state.scan = { kind: state.tab === 'screen' ? 'screen' : 'camera' };
			state.demoPreview = true;
			break;
		case 'pick':
			state.step = 'read';
			state.tab = 'other';
			state.choices = DEMO_DATA.bundles;
			break;
		case 'scanned': // a link found, and nobody signed in
		case 'found':
		case 'done':
		case 'error':
			state.scanned = which === 'scanned';
			state.step = 'read';
			render();
			takeBundle(DEMO_DATA.bundles[0]);
			return;
		default:
			state.step = 'code';
	}
	render();
}

// ---------------------------------------------------------------------------
// DOM helpers. Text always goes in as text: names from a QR code never become markup.

function h(tag, props, ...children) {
	const el = document.createElement(tag);
	for (const [k, v] of Object.entries(props || {})) {
		if (v === null || v === undefined || v === false) continue;
		if (k === 'class') el.className = v;
		else if (k === 'text') el.textContent = v;
		else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
		else if (k === 'value') el.value = v;
		else el.setAttribute(k, v === true ? '' : v);
	}
	for (const c of children.flat(Infinity)) {
		if (c === null || c === undefined || c === false) continue;
		el.append(c instanceof Node ? c : document.createTextNode(String(c)));
	}
	return el;
}

const ICONS = {
	monitor: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
	phone: '<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M10.5 18.5h3"/>',
	more: '<circle cx="5.5" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="18.5" cy="12" r="1.4" fill="currentColor" stroke="none"/>',
	copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>',
	check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
	lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
	alert: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.2v.3"/>',
	file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
	image: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 9"/>',
	link: '<path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1"/>',
	scan: '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><path d="M7 12h10"/>',
	shield: '<path d="M12 3l7 3v5c0 5-3.5 8.5-7 10-3.5-1.5-7-5-7-10V6z"/><path d="M9 12l2 2 4-4"/>',
	qr: '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2"/>',
	clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
	arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
	folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
};
const DISCORD_MARK =
	'<svg viewBox="0 0 127.14 96.36" aria-hidden="true" focusable="false"><path fill="currentColor" d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/></svg>';

function icon(name, cls = 'icon') {
	const span = h('span', { class: cls, 'aria-hidden': 'true' });
	span.innerHTML = name === 'discord' ? DISCORD_MARK : `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" focusable="false">${ICONS[name]}</svg>`;
	return span;
}

function button(label, props = {}, iconName = null) {
	const { kind = 'primary', ...rest } = props;
	return h('button', { type: 'button', class: `btn btn-${kind}`, ...rest }, iconName ? icon(iconName) : null, h('span', { text: label }));
}

async function copyText(text, key) {
	try {
		await navigator.clipboard.writeText(text);
		state.copied = key;
	} catch {
		state.copied = null;
		note('error', T.copyFailed);
	}
	render({ focus: key });
	setTimeout(() => {
		if (state.copied === key) {
			state.copied = null;
			render({ focus: document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.key : null });
		}
	}, 1800);
}

function plural(forms, n) {
	return fill(forms[new Intl.PluralRules(T.locale).select(n)] || forms.other, { n });
}

// ---------------------------------------------------------------------------
// Views

function tabs() {
	const list = [];
	if (CAN_SHARE) list.push({ id: 'screen', label: T.tabScreen, icon: 'monitor' });
	list.push({ id: 'phone', label: T.tabPhone, icon: 'phone' });
	list.push({ id: 'other', label: T.tabOther, icon: 'more' });
	return list;
}

function userChip() {
	if (!state.auth) return null;
	const name = state.username ? `@${state.username}` : T.signedIn;
	return h(
		'div',
		{ class: 'user' },
		icon('discord', 'avatar avatar-letter avatar-discord'),
		h('span', { class: 'user-name', text: name }),
		h('button', { type: 'button', class: 'user-out', onclick: signOut, 'data-key': 'sign-out', text: T.signOut }),
	);
}

function stepper() {
	const current = STEPS.indexOf(state.step);
	const items = STEPS.map((id, i) => {
		const done = i < current;
		const here = i === current;
		// Any step but the last, until the link is sent.
		const canGo = (id === 'code' || id === 'wait' || id === 'read') && !here && state.step !== 'done';
		const finished = done || (here && id === 'done');
		const dot = h('span', { class: 'step-dot' }, finished ? icon('check', 'icon icon-sm') : String(i + 1));
		const label = h('span', { class: 'step-label', text: T.steps[i] });
		const inner = canGo ? h('button', { type: 'button', class: 'step-go', onclick: () => go(id) }, dot, label) : h('span', { class: 'step-go' }, dot, label);
		return h('li', { class: `step${done ? ' is-done' : ''}${here ? ' is-here' : ''}`, 'aria-current': here ? 'step' : null }, inner);
	});
	return h(
		'nav',
		{ class: 'steps', 'aria-label': T.stepsLabel },
		h('ol', {}, items),
		h('p', { class: 'steps-mobile', text: `${fill(T.stepOf, { n: current + 1, total: STEPS.length })} · ${T.steps[current]}` }),
	);
}

function noticeView() {
	if (!state.notice) return null;
	return h('p', { class: `notice notice-${state.notice.kind}`, role: state.notice.kind === 'error' ? 'alert' : 'status' }, icon(state.notice.kind === 'error' ? 'alert' : 'clock'), h('span', { text: state.notice.text }));
}

function discordButton(label) {
	return h('button', { type: 'button', class: 'btn btn-discord btn-lg', onclick: signIn, 'data-key': 'login' }, icon('discord', 'icon icon-discord'), h('span', { text: label }));
}

// A text with {command} in it, the command shown as code.
function withCommand(text) {
	const parts = String(text).split('{command}');
	return parts.flatMap((p, i) => (i ? [h('code', { class: 'inline-code', text: CONFIG.VERIFY_COMMAND }), p] : [p]));
}

function viewCode() {
	return [
		h('h2', { class: 'card-title', tabindex: '-1', text: T.codeTitle }),
		h('p', { class: 'lead', text: T.codeText }),
		h('p', { class: 'field-label', text: T.codeLabel }),
		h('div', { class: 'command' }, h('code', { class: 'command-text', text: CONFIG.VERIFY_COMMAND })),
		h('ol', { class: 'howto' }, h('li', {}, withCommand(T.codeStep1)), h('li', { text: T.codeStep2 }), h('li', { text: T.codeStep3 })),
		h('p', { class: 'notice notice-warn' }, icon('alert'), h('span', { text: T.codeStream })),
		noticeView(),
		h('div', { class: 'actions' }, button(T.codeNext, { kind: 'primary btn-lg', onclick: () => go('wait'), 'data-key': 'next' }, 'arrow')),
		h('div', { class: 'actions' }, button(T.codeHaveQr, { kind: 'ghost btn-sm', onclick: () => go('read'), 'data-key': 'have-qr' }, 'qr')),
	];
}

function viewWait() {
	return [
		h('h2', { class: 'card-title', tabindex: '-1', text: T.waitTitle }),
		h(
			'ul',
			{ class: 'timeline' },
			h('li', {}, icon('shield', 'tl-icon'), h('p', { text: T.waitCouncil })),
			h('li', {}, icon('qr', 'tl-icon'), h('p', { text: T.waitWindow })),
			h('li', { class: 'tl-soft' }, icon('clock', 'tl-icon'), h('p', { text: T.waitWatcher })),
		),
		h('p', { class: 'notice notice-warn' }, icon('alert'), h('span', { text: T.waitStream })),
		h('div', { class: 'actions' }, button(T.waitNext, { kind: 'primary btn-lg', onclick: () => go('read'), 'data-key': 'next' }, 'arrow')),
		h('p', { class: 'fine', text: T.waitTip }),
	];
}

function viewRead() {
	const out = [h('h2', { class: 'card-title', tabindex: '-1', text: state.found ? T.foundTitle : state.choices ? T.pickTitle : T.readTitle })];
	if (state.found) {
		out.push(foundView());
		return out;
	}
	if (state.result) {
		out.push(errorView());
		return out;
	}
	if (state.choices) {
		out.push(h('p', { class: 'lead', text: T.pickText }), choicesView(), noticeView(), h('div', { class: 'actions' }, button(T.readAnother, { kind: 'ghost', onclick: () => { state.choices = null; render(); } })));
		return out;
	}
	out.push(h('p', { class: 'lead', text: T.readText }));
	const list = tabs();
	const tabButtons = list.map((t) =>
		h(
			'button',
			{
				type: 'button',
				role: 'tab',
				id: `tab-${t.id}`,
				class: 'tab',
				'aria-selected': state.tab === t.id ? 'true' : 'false',
				'aria-controls': 'tabpanel',
				tabindex: state.tab === t.id ? '0' : '-1',
				'data-key': `tab-${t.id}`,
				onclick: () => selectTab(t.id),
				onkeydown: (e) => {
					const i = list.findIndex((x) => x.id === t.id);
					let j = null;
					if (e.key === 'ArrowRight') j = (i + 1) % list.length;
					else if (e.key === 'ArrowLeft') j = (i - 1 + list.length) % list.length;
					else if (e.key === 'Home') j = 0;
					else if (e.key === 'End') j = list.length - 1;
					if (j !== null) {
						e.preventDefault();
						selectTab(list[j].id, true);
					}
				},
			},
			icon(t.icon),
			h('span', { text: t.label }),
		),
	);
	out.push(h('div', { class: 'tabs', role: 'tablist', 'aria-label': T.readTitle }, tabButtons));
	const panel = state.tab === 'screen' ? screenPanel() : state.tab === 'phone' ? phonePanel() : otherPanel();
	out.push(h('div', { class: 'tabpanel', id: 'tabpanel', role: 'tabpanel', 'aria-labelledby': `tab-${state.tab}` }, panel));
	out.push(h('p', { class: 'privacy' }, icon('lock', 'icon icon-sm'), h('span', { text: T.privacy })));
	return out;
}

function selectTab(id, focus = false) {
	if (state.tab === id) return;
	stopScan();
	state.tab = id;
	state.notice = null;
	store.set('localStorage', 'tab', id);
	render({ focus: focus ? `tab-${id}` : null });
}

function scanView(kind) {
	const preview = h('div', { class: `preview preview-${kind}` });
	if (state.demoPreview) {
		preview.append(h('div', { class: 'preview-demo' }, icon('qr', 'preview-qr'), h('span', { text: kind === 'screen' ? T.previewDemo : T.previewCamera })));
	} else {
		preview.append(scanner.video);
	}
	preview.append(h('span', { class: 'scanline', 'aria-hidden': 'true' }));
	return h(
		'div',
		{ class: 'scanning' },
		preview,
		h('p', { class: 'scan-status', role: 'status' }, h('span', { class: 'pulse', 'aria-hidden': 'true' }), h('span', { text: kind === 'screen' ? T.screenScanning : T.cameraScanning })),
		kind === 'screen' ? h('p', { class: 'fine', text: T.screenKeep }) : null,
		h('div', { class: 'actions' }, button(T.stop, { kind: 'ghost', onclick: () => { stopScan(); render({ focus: kind === 'screen' ? 'start-screen' : 'start-camera' }); }, 'data-key': 'stop' })),
	);
}

function screenPanel() {
	if (state.scan && state.scan.kind === 'screen') return scanView('screen');
	return h(
		'div',
		{ class: 'panel-body' },
		h('p', { text: T.screenText }),
		h('div', { class: 'actions' }, button(T.screenButton, { kind: 'primary btn-lg', onclick: () => startScan('screen'), 'data-key': 'start-screen' }, 'monitor')),
		noticeView(),
		h('p', { class: 'fine' }, icon('lock', 'icon icon-sm'), h('span', { text: T.screenNote })),
	);
}

function phonePanel() {
	if (state.scan && state.scan.kind === 'camera') return scanView('camera');
	return h(
		'div',
		{ class: 'panel-body' },
		MOBILE ? null : h('div', { class: 'phone-hint' }, icon('phone', 'phone-hint-icon'), icon('arrow', 'phone-hint-arrow'), icon('qr', 'phone-hint-icon')),
		h('p', { text: MOBILE ? T.phoneMobile : T.phoneDesktop }),
		CAN_CAMERA
			? h('div', { class: 'actions' }, button(MOBILE ? T.phoneScan : T.phoneWebcam, { kind: MOBILE ? 'primary btn-lg' : 'ghost', onclick: () => startScan('camera'), 'data-key': 'start-camera' }, 'scan'))
			: null,
		noticeView(),
	);
}

function dropZone({ key, label, accept, buttonLabel, iconName, onFile }) {
	const input = h('input', { type: 'file', accept, class: 'sr-only', id: `file-${key}`, tabindex: '-1', onchange: (e) => { onFile(e.target.files[0]); e.target.value = ''; } });
	const zone = h(
		'div',
		{ class: 'drop', 'data-drop': key },
		icon(iconName, 'drop-icon'),
		h('p', { class: 'drop-label', text: label }),
		button(buttonLabel, { kind: 'ghost btn-sm', onclick: () => input.click(), 'data-key': `choose-${key}` }),
		input,
	);
	zone.addEventListener('dragover', (e) => {
		e.preventDefault();
		zone.classList.add('is-over');
	});
	zone.addEventListener('dragleave', () => zone.classList.remove('is-over'));
	zone.addEventListener('drop', (e) => {
		e.preventDefault();
		zone.classList.remove('is-over');
		const file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
		if (file) onFile(file);
	});
	return zone;
}

// A path that wraps only after its separators (never inside a folder's name).
function pathNodes(path) {
	const out = [];
	for (const part of path.full.split(path.sep)) {
		if (out.length) out.push(path.sep, h('wbr'));
		out.push(part);
	}
	return out;
}

function showPath(currentPath) {
	const code = document.querySelector('.path-text');
	if (code) code.replaceChildren(...pathNodes(currentPath()));
}

function otherPanel() {
	const currentPath = () => savedVariablesPath({ os: state.pathOS, game: state.game, root: state.elsewhere ? state.root : '' });
	const path = currentPath();
	const copied = state.copied === 'copy-path';
	const textarea = h('textarea', {
		id: 'paste',
		class: 'input',
		rows: '2',
		spellcheck: 'false',
		autocomplete: 'off',
		autocapitalize: 'off',
		placeholder: T.pastePlaceholder,
		'data-key': 'paste',
		onpaste: (e) => {
			const text = e.clipboardData && e.clipboardData.getData('text');
			if (text && bundleFromText(text)) {
				e.preventDefault();
				takeText(text);
			}
		},
	});
	const osToggle = h(
		'div',
		{ class: 'seg', role: 'radiogroup', 'aria-label': T.fileSystem },
		['windows', 'mac'].map((id) =>
			h('button', { type: 'button', role: 'radio', class: 'seg-btn', 'aria-checked': state.pathOS === id ? 'true' : 'false', 'data-key': `os-${id}`, onclick: () => { state.pathOS = id; render({ focus: `os-${id}` }); }, text: id === 'windows' ? 'Windows' : 'macOS' }),
		),
	);
	const gameSelect = h(
		'select',
		{ class: 'select', id: 'game', 'aria-label': T.fileGame, 'data-key': 'game', onchange: (e) => { state.game = e.target.value; render({ focus: 'game' }); } },
		GAMES.map((g) => h('option', { value: g.id, selected: state.game === g.id ? 'selected' : null, text: `${T.gameNames[g.id]} (${g.folder})` })),
	);
	// Olympus.lua is on the computer that runs the game: a phone gets a pointer instead.
	const fileWay = MOBILE
		? h('section', { class: 'way' }, h('h3', { class: 'way-title' }, icon('file'), h('span', { text: T.fileTitle })), h('p', { text: T.fileOnPhone }))
		: h(
				'section',
				{ class: 'way' },
				h('h3', { class: 'way-title' }, icon('file'), h('span', { text: T.fileTitle })),
				h(
					'ol',
					{ class: 'howto' },
					h('li', { text: T.fileStep1 }),
					h(
						'li',
						{},
						h('span', { text: T.fileStep2 }),
						h('div', { class: 'path-controls' }, osToggle, gameSelect),
						h('div', { class: 'path' }, h('code', { class: 'path-text' }, pathNodes(path)), button(copied ? T.copied : T.fileCopy, { kind: copied ? 'ok btn-sm' : 'ghost btn-sm', onclick: () => copyText(currentPath().folder, 'copy-path'), 'data-key': 'copy-path' }, copied ? 'check' : 'copy')),
						h('p', { class: 'fine', text: T.fileCopyNote }),
						h('p', { class: 'fine', text: state.pathOS === 'mac' ? T.fileTipMac : T.fileTipWindows }),
						state.game === 'forever' ? h('p', { class: 'fine', text: T.fileForeverNote }) : null,
						h(
							'details',
							{ class: 'elsewhere', open: state.elsewhere ? 'open' : null, ontoggle: (e) => {
									state.elsewhere = e.target.open;
									showPath(currentPath);
								} },
							h('summary', { text: T.fileElsewhere }),
							h('label', { class: 'field-label', for: 'root', text: T.fileElsewhereLabel }),
							h('input', {
								id: 'root',
								class: 'input',
								type: 'text',
								spellcheck: 'false',
								autocomplete: 'off',
								placeholder: state.pathOS === 'mac' ? '/Applications/World of Warcraft' : T.fileElsewherePlaceholder,
								value: state.root,
								'data-key': 'root',
								oninput: (e) => {
									state.root = e.target.value;
									showPath(currentPath);
								},
							}),
							h('p', { class: 'fine', text: T.fileBnet }),
						),
					),
					h('li', {}, h('span', { text: T.fileStep3 })),
				),
				dropZone({ key: 'lua', label: T.fileDrop, accept: '.lua,text/plain', buttonLabel: T.fileButton, iconName: 'file', onFile: takeFile }),
			);
	return h(
		'div',
		{ class: 'panel-body other' },
		noticeView(),
		h(
			'section',
			{ class: 'way' },
			h('h3', { class: 'way-title' }, icon('link'), h('span', { text: T.pasteTitle })),
			h('p', { text: T.pasteText }),
			h('label', { class: 'sr-only', for: 'paste', text: T.pasteLabel }),
			textarea,
			h('div', { class: 'actions' }, button(T.pasteButton, { kind: 'gold btn-sm', onclick: () => takeText(document.getElementById('paste').value), 'data-key': 'read-paste' })),
		),
		h(
			'section',
			{ class: 'way' },
			h('h3', { class: 'way-title' }, icon('image'), h('span', { text: T.shotTitle })),
			h('p', { text: T.shotText }),
			dropZone({ key: 'image', label: T.shotDrop, accept: 'image/*', buttonLabel: T.shotButton, iconName: 'image', onFile: takeImage }),
		),
		fileWay,
	);
}

function characterCard(check, extra = null) {
	const b = check.bundle;
	return h(
		'div',
		{ class: `char char-${b.faction.toLowerCase()}` },
		h('div', { class: 'char-crest', 'aria-hidden': 'true', text: (check.character || '?').charAt(0).toUpperCase() }),
		h(
			'div',
			{ class: 'char-body' },
			h('p', { class: 'char-name', text: check.character }),
			h('p', { class: 'char-meta', text: `${check.realm} · <${b.guild}> · ${b.faction}` }),
			extra,
		),
		h('p', { class: 'char-proofs' }, icon('shield', 'icon icon-sm'), h('span', { text: plural(T.confirmations, check.confirmations) })),
	);
}

function choicesView() {
	return h(
		'ul',
		{ class: 'choices', 'data-key': 'choices', tabindex: '-1' },
		state.choices.map((text, i) => {
			const check = checkBundle(text, null);
			if (!check.ok) return null;
			const code = h('p', { class: 'choice-code' }, h('span', { text: fill(T.code, { R: check.bundle.R }) }));
			return h('li', {}, h('button', { type: 'button', class: 'choice', 'data-key': `choice-${i}`, onclick: () => takeBundle(text) }, characterCard(check, code)));
		}),
	);
}

function foundView() {
	const f = state.found;
	const parts = [characterCard(f)];
	if (state.result && state.result.status !== 'linked') {
		parts.push(errorView());
	} else if (state.sending) {
		parts.push(h('p', { class: 'sending', role: 'status' }, h('span', { class: 'spinner', 'aria-hidden': 'true' }), h('span', { text: T.sending })));
	} else if (!state.auth) {
		parts.push(
			h('p', { class: 'lead', text: state.scanned ? T.loginScanned : T.sendSignIn }),
			h('div', { class: 'actions' }, discordButton(T.signInToSend)),
			noticeView(),
			h('p', { class: 'fine' }, icon('lock', 'icon icon-sm'), h('span', { text: T.loginNote })),
		);
	}
	return h('div', { class: 'found', 'data-key': 'found', tabindex: '-1' }, parts);
}

function readAnother() {
	state.found = null;
	state.result = null;
	state.choices = null;
	store.set('sessionStorage', 'pending', null);
	go('read');
}

function errorView() {
	const r = state.result || { reason: 'server' };
	const reason = T.errors[r.reason] ? r.reason : 'server';
	let action;
	const readAgain = ['not-enough', 'format', 'guild-unverified'].includes(reason);
	const elsewhere = reason === 'linked-elsewhere'; // nothing to retry: another character, or the other account
	if (reason === 'login') action = discordButton(T.loginButton);
	else if (elsewhere) action = button(T.readAnother, { kind: 'primary', onclick: readAnother, 'data-key': 'retry' });
	else if (['unknown-code', 'other-user', 'code-used', 'expired', 'tag'].includes(reason)) action = button(T.newCode, { kind: 'primary', onclick: codeAgain, 'data-key': 'retry' });
	else if (readAgain) action = button(T.readAgain, { kind: 'primary', onclick: readAnother, 'data-key': 'retry' });
	else action = button(T.retry, { kind: 'primary', onclick: () => (state.found ? send() : location.reload()), 'data-key': 'retry' });
	return h(
		'div',
		{ class: 'result result-error', role: 'alert', 'data-key': 'result', tabindex: '-1' },
		h('div', { class: 'result-head' }, icon('alert', 'result-icon'), h('p', { class: 'result-title', text: T.errorTitle })),
		h('p', { text: T.errors[reason] }),
		h('div', { class: 'actions' }, action, state.found && !readAgain && !elsewhere ? button(T.readAnother, { kind: 'ghost', onclick: readAnother }) : null),
	);
}

function viewDone() {
	const r = state.result || {};
	const chars = (r.characters || []).map((c) => splitCharacter(c));
	return [
		h('div', { class: 'done-mark', 'aria-hidden': 'true' }, icon('check', 'done-check')),
		h('h2', { class: 'card-title center', tabindex: '-1', text: T.doneTitle }),
		h('p', { class: 'lead center', text: r.reason === 'already' ? T.doneAlready : state.username ? fill(T.doneText, { user: state.username }) : T.doneTextAnon }),
		chars.length
			? h('div', { class: 'linked' }, h('p', { class: 'field-label center', text: T.doneCharacters }), h('ul', { class: 'chips' }, chars.map((c) => h('li', { class: 'chip' }, h('strong', { text: c.name }), h('span', { text: c.realm })))))
			: null,
		h('p', { class: 'fine center', text: T.doneNote }),
	];
}

// config.js does not name the bot yet: nothing to send to.
function viewClosed() {
	return [h('h2', { class: 'card-title', tabindex: '-1', text: T.closedTitle }), h('p', { class: 'lead', text: T.closedText })];
}

// Inside another page's frame: nothing to click here but the way out, to a tab of its own.
function viewFramed() {
	return [
		h('h2', { class: 'card-title', tabindex: '-1', text: T.framed }),
		h('div', { class: 'actions' }, h('a', { class: 'btn btn-primary', href: location.href.split('#')[0], target: '_blank', rel: 'noopener noreferrer', text: T.framedOpen })),
	];
}

// ---------------------------------------------------------------------------
// Render

const app = document.getElementById('app');
const who = document.getElementById('who');

function render({ focus = null, focusStep = false } = {}) {
	if (!state.ready) return;
	const keep = focus || (document.activeElement && document.activeElement.dataset && document.activeElement.dataset.key) || null;
	if (state.framed || state.closed) {
		document.body.dataset.step = 'closed';
		who.replaceChildren();
		app.replaceChildren(h('section', { class: 'card card-closed', 'aria-live': 'off' }, state.framed ? viewFramed() : viewClosed()));
		return;
	}
	document.body.dataset.step = state.step;
	who.replaceChildren(...[userChip()].filter(Boolean));
	let body;
	if (state.step === 'code') body = viewCode();
	else if (state.step === 'wait') body = viewWait();
	else if (state.step === 'done') body = viewDone();
	else body = viewRead();
	const card = h('section', { class: `card card-${state.step}`, 'aria-live': 'off' }, body);
	app.replaceChildren(stepper(), card);
	if (focusStep) {
		const title = card.querySelector('.card-title');
		if (title) title.focus({ preventScroll: false });
	} else if (keep) {
		const el = app.querySelector(`[data-key="${CSS.escape(keep)}"]`);
		if (el) el.focus({ preventScroll: true });
	}
}

function renderStatic() {
	document.title = T.title;
	document.getElementById('tagline').textContent = T.tagline;
	document.getElementById('skip').textContent = T.skip;
	document.getElementById('privacy-line').textContent = T.privacy;
	document.getElementById('footer-line').textContent = T.footer;
	const banner = document.getElementById('demo-banner');
	if (DEMO) {
		banner.textContent = T.demo;
		banner.hidden = false;
	}
}

// Ctrl+V anywhere on the reading step: a screenshot or the link text.
document.addEventListener('paste', (e) => {
	if (state.step !== 'read' || state.found || state.sending) return;
	const t = e.target;
	if (t && (t.tagName === 'TEXTAREA' || t.tagName === 'INPUT')) return;
	const items = (e.clipboardData && e.clipboardData.items) || [];
	for (const item of items) {
		if (item.kind === 'file' && /^image\//.test(item.type)) {
			e.preventDefault();
			takeImage(item.getAsFile());
			return;
		}
	}
	const text = e.clipboardData && e.clipboardData.getData('text');
	if (text) {
		e.preventDefault();
		takeText(text);
	}
});

// A file dropped on the page outside a drop zone does not navigate away from it.
window.addEventListener('dragover', (e) => e.preventDefault());
window.addEventListener('drop', (e) => {
	e.preventDefault();
	if (state.step !== 'read' || state.found) return;
	const file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
	if (file) takeFile(file);
});

window.addEventListener('pagehide', () => stopScan());

renderStatic();
app.replaceChildren(h('p', { class: 'loading', role: 'status', text: T.loading }));
start();
