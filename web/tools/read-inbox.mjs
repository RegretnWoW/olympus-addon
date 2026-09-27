#!/usr/bin/env node
// Olympus Link: the watcher's inbox, read from its SavedVariables file (Node 18+, no packages).
//
//   node web/tools/read-inbox.mjs <path to Olympus.lua>                  # prints {"bundles": [...]}
//   node web/tools/read-inbox.mjs <Olympus.lua> --post https://<site>/api/link/inbox
//                                                     # sends them; the token from LINK_ADMIN_TOKEN
//
// A High Councillor in watcher mode ("/oly discord watcher on") keeps the finished links players
// deliver to it in OlympusDB.discord.inbox[R] = { bundle, from, t }. WoW writes that file when
// the game saves (a /reload, logging out or quitting). The output is exactly the body that
// POST /api/link/inbox takes (web/WORKER.md), oldest first:
//   {"bundles": [{"R": "...", "bundle": "OLB4~...", "from": "Name-Realm", "t": 1790000000}]}
// Nothing else of the file is printed: not the confirmer key a councillor keeps in the same file.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const R_RE = /^[0-9A-HJKMNP-TV-Z]{10}$/;

// ---------------------------------------------------------------------------
// A reader for what WoW writes in SavedVariables: `Name = value` statements whose values are
// Lua 5.1 constants (strings, numbers, booleans, nil) and table constructors, with the
// "-- [1]" comments WoW puts after array entries. Strings are decoded as UTF-8.

export function parseSavedVariables(text) {
	const src = typeof text === 'string' ? text : new TextDecoder().decode(text);
	let i = 0;
	const out = {};

	const fail = (what) => {
		const line = src.slice(0, i).split('\n').length;
		throw new SyntaxError(`${what} at line ${line}`);
	};
	const space = () => {
		for (;;) {
			const c = src[i];
			if (c === ' ' || c === '\t' || c === '\r' || c === '\n' || c === '﻿') i++;
			else if (c === '-' && src[i + 1] === '-') {
				if (src[i + 2] === '[' && /^\[=*\[/.test(src.slice(i + 2, i + 40))) {
					const eq = src.slice(i + 2).match(/^\[(=*)\[/)[1];
					const end = src.indexOf(`]${eq}]`, i);
					if (end < 0) fail('unfinished comment');
					i = end + eq.length + 2;
				} else {
					while (i < src.length && src[i] !== '\n') i++;
				}
			} else return;
		}
	};
	const name = () => {
		const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i, i + 256));
		if (!m) fail('name expected');
		i += m[0].length;
		return m[0];
	};
	const string = () => {
		const q = src[i++];
		const bytes = [];
		const enc = new TextEncoder();
		for (;;) {
			if (i >= src.length) fail('unfinished string');
			const c = src[i];
			if (c === q) {
				i++;
				break;
			}
			if (c === '\n') fail('newline in string');
			if (c !== '\\') {
				const cp = src.codePointAt(i);
				const ch = String.fromCodePoint(cp);
				bytes.push(...enc.encode(ch));
				i += ch.length;
				continue;
			}
			const n = src[i + 1];
			i += 2;
			const simple = { n: 10, t: 9, r: 13, a: 7, b: 8, f: 12, v: 11, '\\': 92, '"': 34, "'": 39, '\n': 10 };
			if (n in simple) bytes.push(simple[n]);
			else if (n === '\r') {
				bytes.push(10);
				if (src[i] === '\n') i++;
			} else if (n >= '0' && n <= '9') {
				let d = n;
				while (d.length < 3 && src[i] >= '0' && src[i] <= '9') d += src[i++];
				if (Number(d) > 255) fail('bad escape');
				bytes.push(Number(d));
			} else if (n === undefined) fail('unfinished string');
			else bytes.push(...enc.encode(n)); // Lua 5.1: an unknown escape is the character itself
		}
		return new TextDecoder().decode(new Uint8Array(bytes));
	};
	const longString = () => {
		const m = /^\[(=*)\[/.exec(src.slice(i, i + 64));
		const close = `]${m[1]}]`;
		let start = i + m[0].length;
		if (src[start] === '\r') start++;
		if (src[start] === '\n') start++;
		const end = src.indexOf(close, start);
		if (end < 0) fail('unfinished long string');
		i = end + close.length;
		return src.slice(start, end);
	};
	const number = () => {
		const m = /^-?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|inf|nan)/.exec(src.slice(i, i + 64));
		if (!m) fail('value expected');
		i += m[0].length;
		const t = m[0].replace(/^-/, '');
		const v = t === 'inf' ? Infinity : t === 'nan' ? NaN : /^0[xX]/.test(t) ? parseInt(t, 16) : Number(t);
		return m[0].startsWith('-') ? -v : v;
	};
	const value = (depth) => {
		space();
		const c = src[i];
		if (c === '{') return table(depth + 1);
		if (c === '"' || c === "'") return string();
		if (c === '[' && /^\[=*\[/.test(src.slice(i, i + 64))) return longString();
		for (const [word, v] of [['true', true], ['false', false], ['nil', null]]) {
			if (src.startsWith(word, i) && !/[A-Za-z0-9_]/.test(src[i + word.length] || '')) {
				i += word.length;
				return v;
			}
		}
		return number();
	};
	const table = (depth) => {
		if (depth > 100) fail('tables nested too deep');
		i++; // {
		const t = {};
		let n = 1;
		for (;;) {
			space();
			if (src[i] === '}') {
				i++;
				return t;
			}
			let key;
			if (src[i] === '[' && !/^\[=*\[/.test(src.slice(i, i + 64))) {
				i++;
				key = value(depth);
				space();
				if (src[i] !== ']') fail('"]" expected');
				i++;
				space();
				if (src[i] !== '=') fail('"=" expected');
				i++;
			} else if (/[A-Za-z_]/.test(src[i]) && /^[A-Za-z_][A-Za-z0-9_]*\s*=(?!=)/.test(src.slice(i, i + 300)) && !/^(true|false|nil)\b/.test(src.slice(i, i + 6))) {
				key = name();
				space();
				i++; // =
			} else {
				key = n++;
			}
			const v = value(depth);
			if (key !== null && v !== null) t[key] = v;
			space();
			if (src[i] === ',' || src[i] === ';') i++;
			else if (src[i] !== '}') fail('"," or "}" expected');
		}
	};

	for (;;) {
		space();
		if (i >= src.length) return out;
		const n = name();
		space();
		if (src[i] !== '=') fail('"=" expected');
		i++;
		out[n] = value(0);
	}
}

// The inbox of a parsed file: well-formed entries only, oldest first.
export function inboxBundles(saved) {
	const inbox = saved && saved.OlympusDB && saved.OlympusDB.discord && saved.OlympusDB.discord.inbox;
	const bundles = [];
	const skipped = [];
	if (!inbox || typeof inbox !== 'object') return { bundles, skipped };
	for (const [R, e] of Object.entries(inbox)) {
		const bundle = e && typeof e.bundle === 'string' ? e.bundle : '';
		const fields = bundle.split('~');
		if (!R_RE.test(R) || !bundle.startsWith('OLB4~') || fields.length !== 7 || fields[5] !== R) {
			skipped.push(R);
			continue;
		}
		bundles.push({
			R,
			bundle,
			from: typeof e.from === 'string' ? e.from : null,
			t: Number.isFinite(e.t) ? e.t : null,
		});
	}
	bundles.sort((a, b) => (a.t ?? 0) - (b.t ?? 0) || (a.R < b.R ? -1 : 1));
	return { bundles, skipped };
}

export function readInbox(path) {
	return inboxBundles(parseSavedVariables(readFileSync(path, 'utf8')));
}

async function main(argv) {
	const args = argv.slice(2);
	let url = null;
	const files = [];
	for (let k = 0; k < args.length; k++) {
		if (args[k] === '--post') url = args[++k] || '';
		else files.push(args[k]);
	}
	const file = files[0];
	if (!file || files.length > 1 || url === '') {
		process.stderr.write('usage: node web/tools/read-inbox.mjs <Olympus.lua> [--post https://<site>/api/link/inbox]\n');
		return 2;
	}
	let found;
	try {
		found = readInbox(file);
	} catch (err) {
		process.stderr.write(`Cannot read ${file}: ${err.message}\n`);
		return 1;
	}
	const { bundles, skipped } = found;
	process.stderr.write(`${bundles.length} link${bundles.length === 1 ? '' : 's'} in the inbox${skipped.length ? `, ${skipped.length} malformed entr${skipped.length === 1 ? 'y' : 'ies'} skipped` : ''}.\n`);
	const body = JSON.stringify({ bundles }, null, 1);
	if (!url) {
		process.stdout.write(`${body}\n`);
		return 0;
	}
	const token = process.env.LINK_ADMIN_TOKEN;
	if (!token) {
		process.stderr.write('Set LINK_ADMIN_TOKEN to the Worker\'s admin token first.\n');
		return 2;
	}
	if (!/^https:\/\//.test(url) && !/^http:\/\/(localhost|127\.0\.0\.1)(:|\/)/.test(url)) {
		process.stderr.write('The address must start with https:// (the token must not travel in the clear).\n');
		return 2;
	}
	const res = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body });
	const answer = await res.text();
	process.stdout.write(`${answer}\n`);
	if (!res.ok) {
		process.stderr.write(`The Worker answered ${res.status}.\n`);
		return 1;
	}
	return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main(process.argv).then((code) => {
		process.exitCode = code;
	});
}
