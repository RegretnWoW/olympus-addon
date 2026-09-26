#!/usr/bin/env bash
# Exercise the real check command on isolated fixtures, including deliberate failures.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
bash_bin=$(command -v bash)
scratch_root=$(mktemp -d)
trap 'rm -rf "$scratch_root"' EXIT

fixture() {
	case_root="$scratch_root/$1"
	case_path="$PATH"
	mkdir -p "$case_root/scripts" "$case_root/tests" "$case_root/Olympus/nested folder"
	cp "$repo_root/scripts/check.sh" "$repo_root/scripts/lint-globals.sh" "$case_root/scripts/"
	printf 'return {}\n' > "$case_root/Olympus/Main.lua"
	printf 'error("syntax checks must not execute addon code")\n' > "$case_root/Olympus/nested folder/Extra.lua"
	printf '## Interface: 16001\r\n\r\nMain.lua\r\nnested folder\\Extra.lua\r\n' > "$case_root/Olympus/Olympus.toc"
	printf 'print("fixture suite ran")\n' > "$case_root/tests/run.lua"
}

expect_failure() {
	if PATH="$case_path" "$bash_bin" "$case_root/scripts/check.sh" > "$case_root/result.txt" 2>&1; then
		printf 'FAIL: %s unexpectedly passed\n' "$1" >&2
		exit 1
	fi
	if ! grep -Fq "$2" "$case_root/result.txt"; then
		printf 'FAIL: %s failed for an unexpected reason\n' "$1" >&2
		cat "$case_root/result.txt" >&2
		exit 1
	fi
	printf 'ok: %s\n' "$1"
}

fixture 'valid project with spaces'
"$bash_bin" "$case_root/scripts/check.sh" > "$case_root/result.txt" 2>&1
grep -Fq 'fixture suite ran' "$case_root/result.txt"
grep -Fq 'All repository checks passed.' "$case_root/result.txt"
printf 'ok: valid project, CRLF TOC, Windows separators, spaces, no addon execution\n'

fixture 'missing dependency'
mkdir "$case_root/bin"
ln -s "$(command -v dirname)" "$case_root/bin/dirname"
case_path="$case_root/bin"
expect_failure 'missing LuaJIT' 'LuaJIT is required'

fixture 'syntax error'
printf 'local =\n' > "$case_root/Olympus/nested folder/Unlisted.lua"
expect_failure 'syntax error in an unlisted nested Lua file' 'Unlisted.lua'

fixture 'missing TOC entry'
printf 'Missing.lua\n' >> "$case_root/Olympus/Olympus.toc"
expect_failure 'missing TOC file' 'Cannot read TOC entry: Olympus/Missing.lua'

fixture 'lint error'
printf 'local function readValue() return laterValue end\nlocal laterValue = 1\n' > "$case_root/Olympus/Main.lua"
expect_failure 'local/global lint failure' "'laterValue' is read as a global"

fixture 'test failure'
printf 'error("fixture test failed")\n' > "$case_root/tests/run.lua"
expect_failure 'offline test failure' 'fixture test failed'
