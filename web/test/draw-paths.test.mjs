// The draw (prefixes, the threshold T), the Discord account age, the SavedVariables path per
// system and the system detection (web/public/core.js; the Worker's draw functions agree).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { drawOrder, drawLimit, drawPrefix, drawThreshold, isDrawn, sha256Hex, snowflakeTime, savedVariablesPath, detectOS, isMobileOS, canShareScreen, pathSystem, GAMES } from '../public/core.js';
import { drawLimit as workerLimit, drawPrefix as workerPrefix, thresholdOf, snowflakeTime as workerSnowflake } from '../worker/link-worker.js';
import { vectors } from './helpers.mjs';

test('draw: the prefixes of SHA-256(R~keyId) and the order match python\'s', async () => {
	const d = vectors.draw;
	for (const id of d.key_ids) {
		assert.equal(await sha256Hex(`${d.R}~${id}`), d.sha256_hex[id], id);
		assert.equal(await drawPrefix(d.R, id), d.prefix[id], id);
		assert.equal(await workerPrefix(d.R, id), d.prefix[id], id);
	}
	assert.deepEqual(await drawOrder(d.R, d.key_ids), d.order);
	assert.deepEqual(await drawOrder(d.R, [...d.key_ids].reverse()), d.order);
	// Another code draws another order.
	assert.notDeepEqual(await drawOrder('7K3M9QX2TB', d.key_ids), d.order);
});

test('draw: M = max(20, ceil(3% of the active player keys))', () => {
	for (const [n, m] of [[0, 20], [5, 20], [666, 20], [667, 21], [700, 21], [1000, 30], [1001, 31], [10000, 300], [10001, 301]]) {
		assert.equal(drawLimit(n), m, `n=${n}`);
		assert.equal(workerLimit(n), m, `worker n=${n}`);
	}
});

test('draw: T for pools of several sizes matches python\'s, and draws the M lowest', async () => {
	const d = vectors.draw;
	for (const v of d.thresholds) {
		const pool = Array.from({ length: v.n }, (_, i) => `pool${String(i).padStart(4, '0')}`);
		assert.equal(await drawThreshold(d.R, pool), v.T, `n=${v.n}`);
		assert.equal(await thresholdOf(d.R, pool), v.T, `worker n=${v.n}`);
		const prefixes = await Promise.all(pool.map((id) => drawPrefix(d.R, id)));
		assert.equal(prefixes.filter((p) => isDrawn(p, v.T)).length, v.drawn, `n=${v.n}`);
		assert.equal(v.drawn, Math.min(v.n, v.M));
	}
	// Up to M keys: everyone is drawn. Mode c: nobody.
	assert.equal(await drawThreshold(d.R, ['player01']), 'ffffffff');
	assert.equal(isDrawn(d.prefix.player01, '00000000'), false);
	assert.equal(isDrawn(d.prefix.player01, 'ffffffff'), true);
	assert.equal(isDrawn('FFFFFFFF', 'ffffffff'), false);
	// The vectors' mode a code: its T is python's for its five player keys.
	const a = vectors.backend.tokens.find((t) => t.mode === 'a');
	assert.equal(await drawThreshold(a.R, vectors.keys.filter((k) => k.kind === 'p').map((k) => k.key_id)), a.T);
});

test('Discord account age from the snowflake', () => {
	// Discord's documented example: 175928847299117063 was created 2016-04-30 11:18:25.796 UTC.
	assert.equal(snowflakeTime('175928847299117063'), Date.UTC(2016, 3, 30, 11, 18, 25, 796));
	assert.equal(workerSnowflake('175928847299117063'), snowflakeTime('175928847299117063'));
});

test('paths: the default SavedVariables path per system and game folder', () => {
	assert.deepEqual(GAMES.map((g) => g.folder), ['_classic_beta_', '_classic_era_', '_anniversary_']);
	assert.equal(
		savedVariablesPath({ os: 'windows', game: 'forever' }).full,
		'C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_\\WTF\\Account\\<YOUR ACCOUNT>\\SavedVariables\\Olympus.lua',
	);
	assert.equal(savedVariablesPath({ os: 'windows', game: 'forever' }).folder, 'C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_\\WTF\\Account');
	assert.equal(savedVariablesPath({ os: 'mac', game: 'era' }).full, '/Applications/World of Warcraft/_classic_era_/WTF/Account/<YOUR ACCOUNT>/SavedVariables/Olympus.lua');
	assert.equal(savedVariablesPath({ os: 'mac', game: 'anniversary' }).folder, '/Applications/World of Warcraft/_anniversary_/WTF/Account');
	assert.equal(savedVariablesPath({ os: 'linux', game: 'nope' }).folder, 'C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_\\WTF\\Account');
});

test('paths: "WoW is somewhere else?" rebuilds the path from the player\'s folder', () => {
	const p = (root, os = 'windows', game = 'forever') => savedVariablesPath({ os, game, root }).folder;
	assert.equal(p('D:\\Games\\World of Warcraft'), 'D:\\Games\\World of Warcraft\\_classic_beta_\\WTF\\Account');
	assert.equal(p('"D:\\Games\\World of Warcraft\\"'), 'D:\\Games\\World of Warcraft\\_classic_beta_\\WTF\\Account');
	assert.equal(p('D:/Games/WoW', 'windows', 'era'), 'D:/Games/WoW/_classic_era_/WTF/Account');
	// Already inside a game folder, or deeper: that game folder stays.
	assert.equal(p('D:\\Games\\World of Warcraft\\_anniversary_\\Interface\\AddOns'), 'D:\\Games\\World of Warcraft\\_anniversary_\\WTF\\Account');
	assert.equal(p('E:\\WoW\\_classic_\\WTF\\Account\\ABC'), 'E:\\WoW\\_classic_\\WTF\\Account');
	// A game folder with another name: the part before WTF.
	assert.equal(p('/Volumes/Games/WoW Classic/WTF/Account', 'mac'), '/Volumes/Games/WoW Classic/WTF/Account');
	assert.equal(p('/Users/me/Games/World of Warcraft', 'mac', 'anniversary'), '/Users/me/Games/World of Warcraft/_anniversary_/WTF/Account');
	assert.equal(p('   ', 'mac', 'era'), '/Applications/World of Warcraft/_classic_era_/WTF/Account');
	assert.equal(savedVariablesPath({ os: 'mac', game: 'era', root: 'D:\\WoW' }).sep, '\\');
});

test('systems: detection, phones, screen sharing and the path shown first', () => {
	const cases = [
		[{ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0 Safari/537.36', platform: 'Win32' }, 'windows'],
		[{ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15', platform: 'MacIntel', maxTouchPoints: 0 }, 'mac'],
		[{ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15', platform: 'MacIntel', maxTouchPoints: 5 }, 'ios'],
		[{ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148', platform: 'iPhone', maxTouchPoints: 5 }, 'ios'],
		[{ userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36', platform: 'Linux armv81' }, 'android'],
		[{ userAgent: 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 Chrome/140.0 Safari/537.36', platform: 'Linux x86_64' }, 'chromeos'],
		[{ userAgent: 'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0', platform: 'Linux x86_64' }, 'linux'],
		[{ userAgent: '', platform: 'macOS' }, 'mac'],
		[{ userAgent: '', platform: 'Windows' }, 'windows'],
		[{}, 'other'],
	];
	for (const [nav, os] of cases) assert.equal(detectOS(nav), os, JSON.stringify(nav));
	assert.equal(isMobileOS('ios'), true);
	assert.equal(isMobileOS('android'), true);
	assert.equal(isMobileOS('mac'), false);
	const media = { getDisplayMedia() {} };
	assert.equal(canShareScreen('windows', media), true);
	assert.equal(canShareScreen('mac', media), true);
	assert.equal(canShareScreen('ios', media), false);
	assert.equal(canShareScreen('android', media), false);
	assert.equal(canShareScreen('windows', {}), false);
	assert.equal(canShareScreen('windows', undefined), false);
	assert.equal(pathSystem('mac'), 'mac');
	assert.equal(pathSystem('windows'), 'windows');
	assert.equal(pathSystem('linux'), 'windows');
});
