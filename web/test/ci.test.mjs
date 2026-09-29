// CI runs these tests (Konig's review of 1.0.0: they ran only where someone typed the command).
// .github/workflows/tests.yml must set up a Node that has node:sqlite without a flag (22.13 or
// newer), make sure of it, and run every web/test/*.test.mjs; and every action any workflow uses
// is pinned by its commit, as the existing ones are.

import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { REPO } from './helpers.mjs';

const WORKFLOWS = join(REPO, '.github', 'workflows');
const tests = readFileSync(join(WORKFLOWS, 'tests.yml'), 'utf8');

// The steps of the workflow, each as its text (from "- name:" to the next one).
const steps = tests.split(/\n(?=\s+- name: )/).slice(1);

test('tests.yml sets up Node 22.13 or newer with a pinned setup-node', () => {
	const setup = steps.find((s) => /uses: actions\/setup-node@/.test(s));
	assert.ok(setup, 'a step uses actions/setup-node');
	assert.match(setup, /uses: actions\/setup-node@[0-9a-f]{40} # v\d+\.\d+\.\d+\n/, 'pinned by its commit, with the release in a comment');
	const spec = /node-version: '?([^'\n]+)'?/.exec(setup);
	assert.ok(spec, 'a node-version');
	const major = Number(/^\D*(\d+)/.exec(spec[1])[1]);
	assert.ok(major >= 22, `Node ${spec[1]}: node:sqlite needs 22.13 or newer`);
	if (major === 22) assert.match(spec[1], /^(22|22\.x|>=\s*22\.(1[3-9]|[2-9]\d)[^\n]*)$/, `Node ${spec[1]}: the newest 22, or 22.13 and up`);
});

test('tests.yml fails when node:sqlite is missing, then runs every web test after the Node setup', () => {
	const at = (re) => steps.findIndex((s) => re.test(s));
	const setup = at(/uses: actions\/setup-node@/);
	const run = at(/node --test web\/test/);
	assert.ok(run > setup && setup >= 0, 'the web tests run after the Node setup');
	// Without node:sqlite the D1 tests skip themselves: CI must stop instead.
	const sqlite = at(/node -e "require\('node:sqlite'\)"/);
	assert.ok(sqlite > setup && sqlite <= run, 'CI checks node:sqlite before the tests');
	assert.match(steps[run], /node --test web\/test\/\*\.test\.mjs/, 'every *.test.mjs, this file included');
	const files = readdirSync(join(REPO, 'web', 'test')).filter((f) => f.endsWith('.test.mjs'));
	assert.ok(files.includes('ci.test.mjs') && files.length >= 10);
	// The key tool's tests need Python's "cryptography": from the distribution, as LuaJIT is.
	assert.match(tests, /apt-get install --yes --no-install-recommends [^\n]*\bpython3-cryptography\b/);
});

test('every action a workflow uses is pinned by its commit', () => {
	for (const file of readdirSync(WORKFLOWS).filter((f) => /\.ya?ml$/.test(f))) {
		const text = readFileSync(join(WORKFLOWS, file), 'utf8');
		for (const [, ref] of text.matchAll(/uses: ([^\s#]+)/g)) assert.match(ref, /^[\w.-]+\/[\w.-]+@[0-9a-f]{40}$/, `${file}: ${ref}`);
	}
});
