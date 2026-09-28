// Olympus Link: reading the QR code. A shared window (getDisplayMedia) or a camera
// (getUserMedia) is read a few times a second; a screenshot once. The browser's own
// BarcodeDetector reads when it knows QR codes, jsQR (in qr-worker.js) otherwise. Every frame
// stays in this page: it is read and dropped, and the stream stops the moment a link is found,
// after 10 minutes, or on Stop.

export const SCAN_LIMIT_MS = 10 * 60 * 1000;
const FRAME_MS = 300; // at most ~3 reads a second

let detectorPromise;
function getDetector() {
	if (!detectorPromise) {
		detectorPromise = (async () => {
			try {
				if (!('BarcodeDetector' in globalThis)) return null;
				const formats = await globalThis.BarcodeDetector.getSupportedFormats();
				return formats.includes('qr_code') ? new globalThis.BarcodeDetector({ formats: ['qr_code'] }) : null;
			} catch {
				return null;
			}
		})();
	}
	return detectorPromise;
}

let worker = null;
let nextId = 0;
const waiting = new Map();

function qrWorker() {
	if (!worker) {
		worker = new Worker(new URL('./qr-worker.js', import.meta.url));
		worker.onmessage = (event) => {
			const done = waiting.get(event.data.id);
			waiting.delete(event.data.id);
			if (done) done(event.data.text);
		};
		worker.onerror = () => {
			for (const done of waiting.values()) done(null);
			waiting.clear();
			worker = null;
		};
	}
	return worker;
}

function workerRead(image, invert) {
	return new Promise((resolve) => {
		const id = ++nextId;
		waiting.set(id, resolve);
		qrWorker().postMessage({ id, width: image.width, height: image.height, buffer: image.data.buffer, invert }, [image.data.buffer]);
	});
}

let canvas = null;
function pixels(source, width, height) {
	if (!canvas) canvas = typeof OffscreenCanvas === 'function' ? new OffscreenCanvas(width, height) : document.createElement('canvas');
	if (canvas.width !== width) canvas.width = width;
	if (canvas.height !== height) canvas.height = height;
	const ctx = canvas.getContext('2d', { willReadFrequently: true });
	ctx.drawImage(source, 0, 0, width, height);
	return ctx.getImageData(0, 0, width, height);
}

// Every QR text found in a picture (video element, image bitmap). `thorough`: a still image
// tries both readers and inverted colours; a video frame tries the fastest one only.
export async function readSource(source, width, height, thorough = false) {
	if (!width || !height) return [];
	const detector = await getDetector();
	if (detector) {
		try {
			const codes = await detector.detect(source);
			const texts = codes.map((c) => c.rawValue).filter(Boolean);
			if (texts.length || !thorough) return texts;
		} catch {
			// fall through to jsQR
		}
	}
	const text = await workerRead(pixels(source, width, height), thorough);
	return text ? [text] : [];
}

export async function readImageFile(blob) {
	const bitmap = await createImageBitmap(blob);
	try {
		return await readSource(bitmap, bitmap.width, bitmap.height, true);
	} finally {
		if (bitmap.close) bitmap.close();
	}
}

// A running scan of the shared window or a camera. onTexts(texts) returns true when one of them
// was the link (the scan then stops); onStop(why) says why it stopped:
// 'found' | 'cancel' | 'ended' | 'timeout'.
export class Scanner {
	constructor({ onTexts, onStop }) {
		this.onTexts = onTexts;
		this.onStop = onStop;
		this.video = document.createElement('video');
		this.video.muted = true;
		this.video.playsInline = true;
		this.video.setAttribute('playsinline', '');
		this.video.setAttribute('aria-hidden', 'true');
		this.stream = null;
		this.kind = null;
		this.run = null;
		this.timer = null;
	}

	get active() {
		return !!this.stream;
	}

	async start(kind) {
		this.stop(null);
		const media = navigator.mediaDevices;
		const stream =
			kind === 'screen'
				? await media.getDisplayMedia({ video: { displaySurface: 'window' }, audio: false })
				: await media.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
		this.stream = stream;
		this.kind = kind;
		for (const track of stream.getTracks()) track.addEventListener('ended', () => this.stop('ended'));
		this.video.srcObject = stream;
		try {
			await this.video.play();
		} catch {
			// muted inline video plays; if not, frames still arrive for reading
		}
		this.timer = setTimeout(() => this.stop('timeout'), SCAN_LIMIT_MS);
		this.loop();
	}

	async loop() {
		const run = {};
		this.run = run;
		while (this.run === run) {
			const started = performance.now();
			const v = this.video;
			let texts = [];
			if (v.readyState >= 2 && v.videoWidth) {
				try {
					texts = await readSource(v, v.videoWidth, v.videoHeight, false);
				} catch {
					texts = [];
				}
			}
			if (this.run !== run) return;
			if (texts.length && this.onTexts(texts)) {
				this.stop('found');
				return;
			}
			await new Promise((resolve) => setTimeout(resolve, Math.max(40, FRAME_MS - (performance.now() - started))));
		}
	}

	stop(why = 'cancel') {
		const had = !!this.stream;
		this.run = null;
		clearTimeout(this.timer);
		this.timer = null;
		if (this.stream) for (const track of this.stream.getTracks()) track.stop();
		this.stream = null;
		this.video.srcObject = null;
		if (had && why && this.onStop) this.onStop(why, this.kind);
	}
}
