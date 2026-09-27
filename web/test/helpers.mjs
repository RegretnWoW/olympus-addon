// Shared test helpers: the vectors, Ed25519 keys from seeds (node:crypto), and a D1 stand-in
// over node:sqlite that runs web/worker/schema.sql and the Worker's SQL for real.

import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const WEB = fileURLToPath(new URL('..', import.meta.url));
export const REPO = fileURLToPath(new URL('../..', import.meta.url));
export const vectors = JSON.parse(readFileSync(new URL('./fixtures/vectors.json', import.meta.url), 'utf8'));

const PKCS8_ED25519 = Buffer.from('302e020100300506032b657004220420', 'hex');
const SPKI_ED25519 = Buffer.from('302a300506032b6570032100', 'hex');

export function privateKey(seedHex) {
	return crypto.createPrivateKey({ key: Buffer.concat([PKCS8_ED25519, Buffer.from(seedHex, 'hex')]), format: 'der', type: 'pkcs8' });
}

export function publicKey(publicHex) {
	return crypto.createPublicKey({ key: Buffer.concat([SPKI_ED25519, Buffer.from(publicHex, 'hex')]), format: 'der', type: 'spki' });
}

export function publicHexOf(seedHex) {
	return crypto.createPublicKey(privateKey(seedHex)).export({ format: 'der', type: 'spki' }).subarray(12).toString('hex');
}

export function sign(seedHex, message) {
	return crypto.sign(null, Buffer.from(message), privateKey(seedHex));
}

export function verify(publicHex, message, signature) {
	try {
		return crypto.verify(null, Buffer.from(message), publicKey(publicHex), Buffer.from(signature));
	} catch {
		return false;
	}
}

// The vectors web/WORKER.md prints (web/test/docs.test.mjs keeps it equal to vectors.json).
export function guideVectors() {
	const v = vectors;
	return {
		backend: { public_hex: v.backend.public_hex, token: v.backend.tokens[0].token, signed: v.backend.tokens[0].payload },
		codes: v.backend.tokens.map((t) => ({ R: t.R, discord_id: t.discord_id, username: t.username, mode: t.mode, created: t.created, exp: t.exp })),
		keys: v.keys.slice(0, 4).map((k) => ({ key_id: k.key_id, kind: k.kind, bootstrap: k.bootstrap, owner_discord_id: k.owner_discord_id, created: k.created, public_hex: k.public_hex })),
		bundles: v.bundles.slice(0, 2).map((b) => ({ name: b.name, bundle: b.bundle, signed: b.messages })),
		ed25519: v.ed25519.slice(0, 5).map((e) => ({ name: e.name, seed_hex: e.seed_hex, public_hex: e.public_hex, ...(e.message !== undefined ? { message: e.message } : { message_hex: e.message_hex }), signature_b64url: e.signature_b64url })),
		must_fail: { name: v.rejects[0].name, public_hex: v.rejects[0].public_hex, message_hex: v.rejects[0].message_hex, signature_hex: v.rejects[0].signature_hex },
	};
}

export function b64url(bytes) {
	return Buffer.from(bytes).toString('base64url');
}

// D1's API (prepare/bind/first/all/run, batch, exec) over node:sqlite, or null when this Node
// has no node:sqlite (the Worker tests are skipped then).
export async function makeD1() {
	let DatabaseSync;
	try {
		({ DatabaseSync } = await import('node:sqlite'));
	} catch {
		return null;
	}
	const db = new DatabaseSync(':memory:');
	db.exec(readFileSync(new URL('../worker/schema.sql', import.meta.url), 'utf8'));
	const statement = (sql, args = []) => ({
		sql,
		args,
		bind: (...a) => statement(sql, a),
		first: async () => {
			const row = db.prepare(sql).get(...args);
			return row ? { ...row } : null;
		},
		all: async () => ({ success: true, results: db.prepare(sql).all(...args).map((r) => ({ ...r })) }),
		run: async () => {
			const r = db.prepare(sql).run(...args);
			return { success: true, meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } };
		},
	});
	return {
		sqlite: db,
		prepare: (sql) => statement(sql),
		exec: async (sql) => db.exec(sql),
		batch: async (list) => {
			db.exec('BEGIN');
			try {
				const out = [];
				for (const s of list) out.push(await s.run());
				db.exec('COMMIT');
				return out;
			} catch (err) {
				db.exec('ROLLBACK');
				throw err;
			}
		},
	};
}
