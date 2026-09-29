// `node --test web/test` (from the repository root) or `npm test` (in web/): Node 22 and newer
// take a folder given to --test as a file to run, and run this one (the folder's index.js).
// It runs every *.test.mjs here with node --test, each file in its own process as usual, and
// fails when one of them fails. When a glob already picked the test files (`node --test` with
// no argument), it does nothing: they run on their own.

import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const byGlob = process.env.NODE_TEST_CONTEXT !== undefined && basename(process.argv[1] || '') === 'index.js';

if (!byGlob) {
	const files = readdirSync(here)
		.filter((f) => f.endsWith('.test.mjs'))
		.sort()
		.map((f) => join(here, f));
	// NODE_TEST_CONTEXT tells a test process it runs under another runner; this one runs its own.
	const env = { ...process.env };
	delete env.NODE_TEST_CONTEXT;
	const run = spawnSync(process.execPath, ['--test', ...files], { stdio: 'inherit', env });
	process.exitCode = run.status === 0 ? 0 : 1;
}
