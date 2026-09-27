// Olympus Link: reads QR codes off the page's main thread (a classic worker, so the page stays
// smooth while a large window or screenshot is searched). Pixels in, text out; nothing leaves.
// vendor/jsQR.js is jsQR 1.4.0 (github.com/cozmo/jsQR, Apache-2.0: vendor/jsQR.LICENSE), its
// dist/jsQR.js as published, unmodified.
/* global importScripts, jsQR */
importScripts('vendor/jsQR.js');

self.onmessage = (event) => {
	const { id, width, height, buffer, invert } = event.data || {};
	let text = null;
	try {
		const found = jsQR(new Uint8ClampedArray(buffer), width, height, { inversionAttempts: invert ? 'attemptBoth' : 'dontInvert' });
		text = found ? found.data : null;
	} catch {
		text = null;
	}
	self.postMessage({ id, text });
};
