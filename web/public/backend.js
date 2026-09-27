// Olympus Link: every call this page makes to the backend - the Worker of web/WORKER.md, on
// the same site as the page. Four functions:
//   me()           the signed-in Discord user { id, username, global_name, avatar }, or null
//   loginUrl(back) the site's Discord login, coming back to `back`
//   code()         a code token for the signed-in user (a string: OLC2...)
//   submit(bundle) { status: 'linked' | 'rejected' | 'error', reason, message, characters }
// With ?demo=<state> in the page's address a demo answers instead: fake data, and nothing is
// ever sent anywhere (for screenshots and trying the page).

// Where your site has these (change them here if yours differ).
export const API = '/api/link';
export const LOGIN = '/login';
export const LOGOUT = '/logout';

export class BackendError extends Error {
	constructor(reason, message, status = 0) {
		super(message || reason);
		this.reason = reason;
		this.status = status;
	}
}

export function createBackend({ demo = null, fetchImpl = globalThis.fetch && globalThis.fetch.bind(globalThis), api = API, login = LOGIN, logout = LOGOUT } = {}) {
	if (demo) return demoBackend(demo);

	async function call(path, body) {
		let res;
		try {
			res = await fetchImpl(`${api}${path}`, {
				method: body === undefined ? 'GET' : 'POST',
				credentials: 'same-origin',
				cache: 'no-store',
				headers: body === undefined ? { Accept: 'application/json' } : { Accept: 'application/json', 'Content-Type': 'application/json' },
				body: body === undefined ? undefined : JSON.stringify(body),
			});
		} catch {
			throw new BackendError('server', 'network');
		}
		let data = null;
		try {
			data = await res.json();
		} catch {
			data = null;
		}
		return { res, data };
	}

	return {
		demo: null,
		loginUrl: (back) => `${login}?next=${encodeURIComponent(back || '/')}`,
		logoutUrl: () => logout,
		async me() {
			const { res, data } = await call('/me');
			if (res.status === 401) return null;
			if (!res.ok || !data) throw new BackendError('server', data && data.message, res.status);
			return data.user || null;
		},
		async code() {
			const { res, data } = await call('/code', {});
			if (!res.ok || !data || typeof data.token !== 'string') throw new BackendError((data && data.reason) || 'server', data && data.message, res.status);
			return data.token;
		},
		async submit(bundle) {
			const { res, data } = await call('/submit', { bundle });
			if (data && typeof data.status === 'string') return { characters: [], ...data };
			return { status: 'error', reason: res.status === 401 ? 'login' : 'server', message: '', characters: [] };
		},
	};
}

// ---------------------------------------------------------------------------
// The demo: made-up answers from the shared test vectors (throwaway test keys).

export const DEMO_STATES = ['login', 'scanned', 'start', 'code', 'wait', 'screen', 'scanning', 'phone', 'other', 'pick', 'found', 'done', 'error'];

export const DEMO_DATA = {
	user: { id: '100000000000000099', username: 'some.player', global_name: 'Some Player', avatar: null },
	token: 'OLC2.7K3M9QX2TB.some.player.1800000000.c.00000000.TmJVCJJtjs5W_sOXnQm3G10J3y5xwVQkii6zRhi0EO-5AmL__PtEg1Ao7VaiUivi1Jslf4i1OJUxMDDNXtG4Ag',
	bundles: [
		'OLB4~Some Player-ClassicBetaPvP~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990100,council01,Test Councillor-ClassicBetaPvP,w,wYG_TW3fCOBxV9hteWMsnq2R8sBus8YaG-Dyb4SePjkl9a9Ub27i1okdpFxUh5aQASIZKKcXQbv0ocuXxvObBA',
		'OLB4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~9c5ac51afcd0bbee~1799990200,player01,Other Player-ClassicBetaPvP,r,jRr01ESNDrVEohLRRZYhLAVPD9ue32uDrRA2GQByQq2dsCQ-6o79nFWcL__shopaQ2Umy1aV9f8sDIaMQLzyBw;1799990245,player02,Third Player-ClassicBetaPvP2,c,K7sW12b4A_uTxycWnR8rRE1Ip3wzAxA2GYOgNMitKtbx1KfI6IxWMJLEu2oEoJ042TuWxlbk_RU6k81b4kuEAA;1799990301,player03,Fourth Player-ClassicBetaPvP,c,7sEYRUmeAZOZyqJUGu8_hZ_O2Mn8mFuWIKdWMTJ_0Zs4KYzelPEDfnjfq3bcU-uYal7tiPtuBY6zijo0mJCqDQ',
	],
};

function demoBackend(state) {
	const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
	const never = () => new Promise(() => {});
	return {
		demo: state,
		loginUrl: () => '#demo-login',
		logoutUrl: () => '#demo-logout',
		async me() {
			return state === 'login' || state === 'scanned' ? null : { ...DEMO_DATA.user };
		},
		async code() {
			await wait(400);
			return DEMO_DATA.token;
		},
		async submit(bundle) {
			if (state === 'found') return never(); // the screenshot shows it sending
			await wait(700);
			if (state === 'error') {
				return { status: 'rejected', reason: 'expired', message: 'This code expired more than 7 days ago.', characters: [] };
			}
			const requester = String(bundle).split('~')[1] || 'Some Player-ClassicBetaPvP';
			return { status: 'linked', reason: 'linked', message: `${requester} is now linked.`, characters: [requester, 'Some Alt-ClassicBetaPvP'] };
		},
	};
}

// The page's backend: the demo when the address asks for one.
const params = new URLSearchParams((globalThis.location && globalThis.location.search) || '');
const demo = params.get('demo');
export const backend = createBackend({ demo: demo && DEMO_STATES.includes(demo) ? demo : null });
export const DEMO = backend.demo;
export const me = () => backend.me();
export const code = () => backend.code();
export const submit = (bundle) => backend.submit(bundle);
export const loginUrl = (back) => backend.loginUrl(back);
export const logoutUrl = () => backend.logoutUrl();
