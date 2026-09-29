// The page's QR reader (vendor/jsQR.js, what qr-worker.js runs) reads the QR codes the addon's
// encoder makes (web/test/fixtures/qr-matrices.txt, from make-qr-fixture.lua) back to the exact
// link, drawn as the game draws them: dark modules on white, a 4-module quiet zone, whole pixels.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';
import { bundleFromText, checkBundle } from '../public/core.js';
import { vectors } from './helpers.mjs';

const sandbox = {};
vm.runInNewContext(readFileSync(new URL('../public/vendor/jsQR.js', import.meta.url), 'utf8'), { self: sandbox });
const jsQR = sandbox.jsQR;

function blocks() {
	const out = [];
	let cur = null;
	for (const line of readFileSync(new URL('./fixtures/qr-matrices.txt', import.meta.url), 'utf8').split('\n')) {
		if (line.startsWith('# ')) out.push((cur = { name: line.slice(2), rows: [] }));
		else if (line.startsWith('url ')) cur.url = line.slice(4);
		else if (/^[01]+$/.test(line)) cur.rows.push(line);
	}
	return out;
}

// RGBA pixels of a matrix: `px` pixels a module, `quiet` modules of white around, on a larger
// grey "screen" so the reader has to find it.
function render(rows, px, quiet = 4, margin = 40) {
	const n = rows.length;
	const side = (n + 2 * quiet) * px;
	const width = side + 2 * margin + 17;
	const height = side + 2 * margin;
	const data = new Uint8ClampedArray(width * height * 4);
	for (let i = 0; i < data.length; i += 4) {
		data[i] = 38;
		data[i + 1] = 34;
		data[i + 2] = 30;
		data[i + 3] = 255;
	}
	for (let y = 0; y < side; y++) {
		for (let x = 0; x < side; x++) {
			const my = Math.floor(y / px) - quiet;
			const mx = Math.floor(x / px) - quiet;
			const dark = my >= 0 && mx >= 0 && my < n && mx < n && rows[my][mx] === '1';
			const i = ((y + margin) * width + (x + margin)) * 4;
			data[i] = data[i + 1] = data[i + 2] = dark ? 0 : 255;
		}
	}
	return { data, width, height };
}

test('the vendored jsQR reads the addon\'s QR codes to the exact link', () => {
	assert.equal(typeof jsQR, 'function');
	const list = blocks();
	assert.equal(list.length, vectors.bundles.length);
	// A version 23 code among them: jsQR 1.4.0 as published misplaces its alignment patterns and
	// reads none (the one line vendor/jsQR.js changes, qr-worker.js).
	assert.ok(list.some((b) => /\(version 23\)$/.test(b.name)), 'a version 23 code');
	for (const [i, b] of list.entries()) {
		assert.equal(b.url, vectors.bundles[i].url);
		assert.ok(b.rows.every((r) => r.length === b.rows.length), b.name);
		for (const px of [3, 4]) {
			const img = render(b.rows, px);
			const found = jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' });
			assert.ok(found, `${b.name}: nothing read at ${px} px`);
			assert.equal(found.data, b.url, `${b.name} at ${px} px`);
			assert.equal(bundleFromText(found.data), vectors.bundles[i].bundle);
			assert.ok(checkBundle(bundleFromText(found.data), vectors.bundles[i].R).matchesCode);
		}
	}
});
