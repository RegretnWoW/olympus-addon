// Olympus Link: the page's own logic, with no DOM and no network, so the page and the tests
// (web/test, node --test) run the same code. The formats are the addon's (Olympus/Link.lua)
// and the Worker's (web/worker/link-worker.js, web/WORKER.md): change one, change all three.

// ---------------------------------------------------------------------------
// Code tokens, issued by the backend and pasted in game:
//   OLC1.<R>.<username>.<exp>.<mode>.<sig>
// R: 10 Crockford base32 characters; username: the Discord username, [a-z0-9_.]{2,32} (it may
// hold dots, so the token is read from both ends); exp: unix time; mode: "c" councillors only,
// "a" councillors or drawn players; sig: base64url Ed25519 by the backend over the ASCII bytes
// of everything before the last dot.

export const R_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export const R_RE = /^[0-9A-HJKMNP-TV-Z]{10}$/;
export const USERNAME_RE = /^[a-z0-9_.]{2,32}$/;
export const SIG_RE = /^[A-Za-z0-9_-]{86}$/;
export const COMMAND = '/oly discord';
export const CHAT_LINE_MAX = 255; // bytes the game's chat box takes

// { ok: true, token } or { ok: false, error }.
export function parseToken(input) {
	if (typeof input !== 'string') return { ok: false, error: 'empty' };
	let s = input.trim();
	if (s.toLowerCase().startsWith(`${COMMAND} `)) s = s.slice(COMMAND.length).trim();
	if (s === '') return { ok: false, error: 'empty' };
	if (!s.startsWith('OLC1.')) return { ok: false, error: 'prefix' };
	const f = s.split('.');
	if (f.length < 6) return { ok: false, error: 'fields' };
	const R = f[1];
	const sig = f[f.length - 1];
	const mode = f[f.length - 2];
	const exp = f[f.length - 3];
	const username = f.slice(2, f.length - 3).join('.');
	if (!R_RE.test(R)) return { ok: false, error: 'code' };
	if (!USERNAME_RE.test(username)) return { ok: false, error: 'username' };
	if (!/^[1-9][0-9]{0,11}$/.test(exp)) return { ok: false, error: 'exp' };
	if (mode !== 'c' && mode !== 'a') return { ok: false, error: 'mode' };
	if (!SIG_RE.test(sig) || !canonicalB64url(sig, 64)) return { ok: false, error: 'sig' };
	const payload = s.slice(0, s.length - sig.length - 1);
	return { ok: true, token: { raw: s, R, username, exp: Number(exp), mode, sig, payload } };
}

export function tokenCommand(token) {
	return `${COMMAND} ${token}`;
}

// The longest "/oly discord <token>" there can be: must fit the chat line.
export function worstCaseCommandLength() {
	return utf8Length(tokenCommand(['OLC1', 'Z'.repeat(10), 'z'.repeat(32), '9'.repeat(12), 'a', 'A'.repeat(86)].join('.')));
}

// ---------------------------------------------------------------------------
// Bundles: OLB4~<requester>~<guild>~<faction>~<nonce>~<R>~<p1>;<p2>;...
// with each proof <issued>,<keyId>,<confirmer Name-Realm>,<sig>, at most 4. Each sig is the
// confirmer's Ed25519 over the UTF-8 bytes of
//   OLY4~<requester>~<guild>~<faction>~<nonce>~<R>~<issued>~<keyId>~<confirmer>

export const MAX_PROOFS = 4;
export const MAX_BUNDLE_BYTES = 1600;
export const FACTIONS = ['Alliance', 'Horde'];
export const NONCE_RE = /^[0-9a-f]{16}$/;
export const KEYID_RE = /^[a-z0-9]{6,16}$/;
export const ISSUED_RE = /^[1-9][0-9]{0,11}$/;
const FORBIDDEN = /[|~;,\u0000-\u001f\u007f]/;

const encoder = new TextEncoder();
export function utf8Length(s) {
	return encoder.encode(s).length;
}

// A field of the signed text, as the addon checks it: not empty, at most `max` bytes, no
// separator (~ ; ,), pipe or control character.
function field(s, max) {
	return typeof s === 'string' && s !== '' && !FORBIDDEN.test(s) && utf8Length(s) <= max;
}

// "Name-Realm" as the game writes it: the realm follows the last dash and has no dash or space.
const CHARACTER_RE = /^[^-].*-[^- ]+$/s;
export function validCharacter(s) {
	return field(s, 64) && CHARACTER_RE.test(s);
}

export function validGuild(s) {
	return field(s, 40);
}

// { ok: true, bundle } or { ok: false, error } where error names what is wrong. It reads
// exactly what the addon's Link.Parse reads; whether the proofs count is the Worker's call.
export function parseBundle(text) {
	if (typeof text !== 'string' || text === '') return { ok: false, error: 'empty' };
	if (!text.startsWith('OLB4~')) return { ok: false, error: 'prefix' };
	if (utf8Length(text) > MAX_BUNDLE_BYTES) return { ok: false, error: 'size' };
	const f = text.split('~');
	if (f.length !== 7) return { ok: false, error: 'fields' };
	const [, requester, guild, faction, nonce, R, proofText] = f;
	if (!validCharacter(requester)) return { ok: false, error: 'requester' };
	if (!validGuild(guild)) return { ok: false, error: 'guild' };
	if (!FACTIONS.includes(faction)) return { ok: false, error: 'faction' };
	if (!NONCE_RE.test(nonce)) return { ok: false, error: 'nonce' };
	if (!R_RE.test(R)) return { ok: false, error: 'code' };
	if (proofText === '') return { ok: false, error: 'noProofs' };
	const parts = proofText.split(';');
	if (parts.length > MAX_PROOFS) return { ok: false, error: 'proofs' };
	const proofs = [];
	for (const part of parts) {
		const p = part.split(',');
		if (p.length !== 4) return { ok: false, error: 'proof' };
		const [issued, keyId, confirmer, sig] = p;
		if (!ISSUED_RE.test(issued)) return { ok: false, error: 'issued' };
		if (!KEYID_RE.test(keyId)) return { ok: false, error: 'keyId' };
		if (!validCharacter(confirmer)) return { ok: false, error: 'confirmer' };
		if (!SIG_RE.test(sig) || !canonicalB64url(sig, 64)) return { ok: false, error: 'sig' };
		proofs.push({ issued: Number(issued), keyId, confirmer, sig });
	}
	return { ok: true, bundle: { requester, guild, faction, nonce, R, proofs } };
}

export function buildBundle(b) {
	const proofs = b.proofs.map((p) => [p.issued, p.keyId, p.confirmer, p.sig].join(',')).join(';');
	return ['OLB4', b.requester, b.guild, b.faction, b.nonce, b.R, proofs].join('~');
}

// The exact text a confirmer signed for one proof.
export function signedMessage(b, p) {
	return ['OLY4', b.requester, b.guild, b.faction, b.nonce, b.R, p.issued, p.keyId, p.confirmer].join('~');
}

export function confirmationCount(b) {
	return new Set(b.proofs.map((p) => p.confirmer)).size;
}

// "Name-Realm" -> { name, realm } for the page.
export function splitCharacter(s) {
	const at = String(s).lastIndexOf('-');
	return at > 0 ? { name: s.slice(0, at), realm: s.slice(at + 1) } : { name: String(s), realm: '' };
}

// The link of the QR and the copy box: <site>#b=<bundle, percent-encoded>. The fragment never
// reaches a server.
export function linkUrl(site, bundleText) {
	return `${site}#b=${encodeURIComponent(bundleText)}`;
}

// A bundle from what the player has: the link of the copy box or the QR (any site: the
// fragment is what counts), the fragment alone, or the bundle text itself. Null otherwise.
export function bundleFromText(input) {
	if (typeof input !== 'string') return null;
	let s = input.trim();
	const at = s.indexOf('#b=');
	if (at >= 0) s = s.slice(at + 3);
	else if (s.startsWith('b=')) s = s.slice(2);
	s = s.split('&')[0].trim();
	if (/%[0-9A-Fa-f]{2}/.test(s) || s.includes('+')) {
		try {
			s = decodeURIComponent(s.replace(/\+/g, ' '));
		} catch {
			return null;
		}
	}
	s = s.trim();
	return s.startsWith('OLB4~') ? s : null;
}

// The page's fragment: a bundle from a phone that scanned the QR with its camera.
export function parseFragment(hash) {
	const h = String(hash || '').replace(/^#/, '');
	if (!h.startsWith('b=')) return { kind: 'none' };
	const text = bundleFromText(`#${h}`);
	return text ? { kind: 'bundle', text } : { kind: 'bad-bundle' };
}

// What the page may send, and what it shows about it. `code` is the R of this browser's code,
// when it has one: a bundle made with another code is flagged (the Worker decides anyway).
export function checkBundle(text, code) {
	const parsed = parseBundle(text);
	if (!parsed.ok) return { ok: false, error: parsed.error === 'noProofs' ? 'noProofs' : 'invalid', detail: parsed.error };
	const b = parsed.bundle;
	const who = splitCharacter(b.requester);
	return {
		ok: true,
		bundle: b,
		text,
		character: who.name,
		realm: who.realm,
		confirmations: confirmationCount(b),
		matchesCode: code ? b.R === code : null,
	};
}

// ---------------------------------------------------------------------------
// Bytes, base64url, hex.

export function hexToBytes(hex) {
	if (typeof hex !== 'string' || !/^(?:[0-9a-fA-F]{2})*$/.test(hex)) throw new Error('bad hex');
	const out = new Uint8Array(hex.length / 2);
	for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
	return out;
}

export function bytesToHex(bytes) {
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

export function b64urlEncode(bytes) {
	let out = '';
	for (let i = 0; i < bytes.length; i += 3) {
		const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
		const chars = i + 2 < bytes.length ? 4 : i + 1 < bytes.length ? 3 : 2;
		for (let j = 0; j < chars; j++) out += B64[(n >> (18 - 6 * j)) & 63];
	}
	return out;
}

export function b64urlDecode(s) {
	if (typeof s !== 'string' || !/^[A-Za-z0-9_-]*$/.test(s) || s.length % 4 === 1) throw new Error('bad base64url');
	const out = new Uint8Array(Math.floor((s.length * 6) / 8));
	let bits = 0;
	let acc = 0;
	let o = 0;
	for (const c of s) {
		acc = (acc << 6) | B64.indexOf(c);
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			out[o++] = (acc >> bits) & 255;
		}
	}
	return out;
}

// True when s is the one base64url spelling of `length` bytes (no stray low bits).
export function canonicalB64url(s, length) {
	try {
		const b = b64urlDecode(s);
		return b.length === length && b64urlEncode(b) === s;
	} catch {
		return false;
	}
}

// ---------------------------------------------------------------------------
// The draw (mode "a"): players are ranked by SHA-256(R .. "~" .. keyId), lowest hex first.
// The addon asks online players in this order; the Worker accepts only keys ranked < M among
// all active player keys, M = max(20, ceil(3% of them)).

export async function sha256Hex(text) {
	const d = await globalThis.crypto.subtle.digest('SHA-256', encoder.encode(text));
	return bytesToHex(new Uint8Array(d));
}

export async function drawOrder(R, keyIds) {
	const ranked = await Promise.all(keyIds.map(async (id) => ({ id, h: await sha256Hex(`${R}~${id}`) })));
	ranked.sort((a, b) => (a.h < b.h ? -1 : a.h > b.h ? 1 : 0));
	return ranked.map((r) => r.id);
}

export function drawLimit(activePlayerKeys) {
	return Math.max(20, Math.ceil(activePlayerKeys * 0.03));
}

// A Discord id (snowflake) holds its account's creation time: milliseconds since 2015.
export function snowflakeTime(id) {
	return Number((BigInt(id) >> 22n) + 1420070400000n);
}

// ---------------------------------------------------------------------------
// Where Olympus.lua is: SavedVariables of the game folder, per system.

export const GAMES = [
	{ id: 'forever', folder: '_classic_beta_' },
	{ id: 'era', folder: '_classic_era_' },
	{ id: 'anniversary', folder: '_anniversary_' },
];
export const WOW_ROOT = {
	windows: 'C:\\Program Files (x86)\\World of Warcraft',
	mac: '/Applications/World of Warcraft',
};
export const ACCOUNT = '<YOUR ACCOUNT>';

function gameFolder(game) {
	return (GAMES.find((g) => g.id === game) || GAMES[0]).folder;
}

// { folder, full, sep }: `folder` is the part that can be pasted in a file window (up to
// WTF\Account), `full` the whole path with <YOUR ACCOUNT> in it. `root` is the player's own
// World of Warcraft folder when it is somewhere else; a path already inside a game folder
// (or one with a WTF folder) keeps that game folder.
export function savedVariablesPath({ os, game, root } = {}) {
	const custom = typeof root === 'string' ? root.trim().replace(/^["']+|["']+$/g, '').trim() : '';
	const mac = os === 'mac';
	let base = custom || (mac ? WOW_ROOT.mac : WOW_ROOT.windows);
	let sep = mac ? '/' : '\\';
	if (custom) {
		// The player's own spelling: backslashes, else slashes, else a drive letter's backslash.
		if (custom.includes('\\')) sep = '\\';
		else if (custom.includes('/')) sep = '/';
		else if (/^[A-Za-z]:/.test(custom)) sep = '\\';
	}
	const prefix = (base.match(/^[\\/]+/) || [''])[0];
	const parts = base.slice(prefix.length).split(/[\\/]+/).filter(Boolean);
	const at = parts.findIndex((p) => /^_[a-z0-9]+(?:_[a-z0-9]+)*_$/i.test(p));
	const wtf = parts.findIndex((p) => p.toLowerCase() === 'wtf');
	let head;
	if (at >= 0) head = parts.slice(0, at + 1);
	else if (wtf > 0) head = parts.slice(0, wtf);
	else head = [...parts, gameFolder(game)];
	base = prefix.replace(/[\\/]/g, sep) + head.join(sep);
	const folder = [base, 'WTF', 'Account'].join(sep);
	return { folder, full: [folder, ACCOUNT, 'SavedVariables', 'Olympus.lua'].join(sep), sep };
}

// ---------------------------------------------------------------------------
// The system the page runs on.

export function detectOS({ userAgent = '', platform = '', maxTouchPoints = 0 } = {}) {
	const ua = String(userAgent);
	const p = String(platform).toLowerCase();
	if (/android/i.test(ua) || p === 'android') return 'android';
	if (/iphone|ipad|ipod/i.test(ua) || p === 'ios' || p === 'iphone' || p === 'ipad') return 'ios';
	const macish = p.startsWith('mac') || p === 'macos' || /Macintosh|Mac OS X/.test(ua);
	if (macish && maxTouchPoints > 1) return 'ios'; // iPadOS says it is a Mac
	if (p.startsWith('win') || /Windows/.test(ua)) return 'windows';
	if (macish) return 'mac';
	if (/CrOS/.test(ua) || p === 'chrome os' || p === 'chromeos') return 'chromeos';
	if (p.startsWith('linux') || /Linux/.test(ua)) return 'linux';
	return 'other';
}

export function isMobileOS(os) {
	return os === 'ios' || os === 'android';
}

export function canShareScreen(os, mediaDevices) {
	return !isMobileOS(os) && !!mediaDevices && typeof mediaDevices.getDisplayMedia === 'function';
}

// The path shown first: the Mac's on a Mac, Windows' everywhere else (WoW runs on those two).
export function pathSystem(os) {
	return os === 'mac' ? 'mac' : 'windows';
}

// ---------------------------------------------------------------------------
// Olympus.lua (SavedVariables): every "OLB4~..." string in it, unescaped as Lua writes them.
// The file stays in the browser; only the bundle the player picks is sent.

export const MAX_FILE_BYTES = 30 * 1024 * 1024;

const LUA_ESCAPES = { n: 10, r: 13, t: 9, a: 7, b: 8, f: 12, v: 11, '\\': 92, '"': 34, "'": 39, '\n': 10, '\r': 13 };

function pushUtf8(bytes, cp) {
	if (cp < 0x80) bytes.push(cp);
	else if (cp < 0x800) bytes.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
	else if (cp < 0x10000) bytes.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
	else bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
}

// The body of a double-quoted Lua 5.1 string -> its text (null when it is not valid UTF-8).
export function unescapeLua(body) {
	const bytes = [];
	for (let i = 0; i < body.length; ) {
		const cp = body.codePointAt(i);
		i += cp > 0xffff ? 2 : 1;
		if (cp !== 92) {
			pushUtf8(bytes, cp);
			continue;
		}
		const n = body[i++];
		if (n === undefined) return null;
		if (n >= '0' && n <= '9') {
			let d = n;
			while (d.length < 3 && body[i] >= '0' && body[i] <= '9') d += body[i++];
			if (Number(d) > 255) return null;
			bytes.push(Number(d));
		} else if (n in LUA_ESCAPES) {
			bytes.push(LUA_ESCAPES[n]);
		} else {
			pushUtf8(bytes, n.codePointAt(0)); // Lua 5.1: an unknown escape is the character itself
		}
	}
	try {
		return new TextDecoder('utf-8', { fatal: true }).decode(new Uint8Array(bytes));
	} catch {
		return null;
	}
}

// Every valid bundle in the file's text, in file order, without repeats.
export function bundlesFromSavedVariables(text) {
	const out = [];
	const seen = new Set();
	const re = /"(OLB4~(?:[^"\\\r\n]|\\[\s\S])*)"/g;
	for (let m = re.exec(text); m; m = re.exec(text)) {
		const s = unescapeLua(m[1]);
		if (s === null || seen.has(s)) continue;
		seen.add(s);
		const parsed = parseBundle(s);
		if (parsed.ok) out.push({ text: s, bundle: parsed.bundle });
	}
	return out;
}

// Which of several bundles: the one made with this browser's code, else the only one, else
// the player picks (the ones with this browser's code first).
export function pickBundle(list, code) {
	if (!list.length) return { kind: 'none' };
	const mine = code ? list.filter((c) => c.bundle.R === code) : [];
	if (mine.length === 1) return { kind: 'one', choice: mine[0] };
	if (list.length === 1) return { kind: 'one', choice: list[0] };
	return { kind: 'many', choices: mine.length ? mine : list };
}
