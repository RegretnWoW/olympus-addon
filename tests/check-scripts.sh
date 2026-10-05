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
	printf 'printf "fixture round trip ran\\n"\n' > "$case_root/tests/sign-roundtrip.sh"
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
printf 'print("python must not run")\n' > "$case_root/scripts/tool.py"
"$bash_bin" "$case_root/scripts/check.sh" > "$case_root/result.txt" 2>&1
grep -Fq 'fixture suite ran' "$case_root/result.txt"
grep -Fq 'fixture round trip ran' "$case_root/result.txt"
grep -Fq 'All repository checks passed.' "$case_root/result.txt"
if grep -Fq 'python must not run' "$case_root/result.txt" || [ -e "$case_root/scripts/__pycache__" ]; then
	printf 'FAIL: the Python check ran a script or left bytecode in the project\n' >&2
	exit 1
fi
printf 'ok: valid project, CRLF TOC, Windows separators, spaces, no addon or script execution\n'

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

fixture 'stale answer bank'
mkdir -p "$case_root/docs"
cp "$repo_root/scripts/answers.lua" "$case_root/scripts/"
cp "$repo_root/docs/answers.json" "$case_root/docs/"
printf 'return {}\n' > "$case_root/Olympus/AnswerBank.lua"
expect_failure 'answer bank out of date with docs/answers.json' 'Olympus/AnswerBank.lua is not what docs/answers.json makes'

# The CurseForge store page and what it is made from (the TOC's version, for its recent versions).
store_fixture() {
	fixture "$1"
	mkdir -p "$case_root/docs"
	cp "$repo_root/scripts/curseforge-page.lua" "$repo_root/scripts/curseforge-size.lua" "$case_root/scripts/"
	cp "$repo_root/docs/CURSEFORGE.md" "$case_root/docs/"
	cp "$repo_root/README.md" "$repo_root/ROADMAP.md" "$case_root/"
	grep '^## Version:' "$repo_root/Olympus/Olympus.toc" >> "$case_root/Olympus/Olympus.toc"
}

store_fixture 'store page up to date'
(cd "$case_root" && luajit scripts/curseforge-page.lua > /dev/null)
"$bash_bin" "$case_root/scripts/check.sh" > "$case_root/result.txt" 2>&1
grep -Fq 'docs/CURSEFORGE-STORE.md matches docs/CURSEFORGE.md' "$case_root/result.txt"
grep -Fq 'All repository checks passed.' "$case_root/result.txt"
printf 'ok: store page made from docs/CURSEFORGE.md, within the budget\n'

store_fixture 'stale store page'
printf 'stale\n' > "$case_root/docs/CURSEFORGE-STORE.md"
expect_failure 'store page out of date with docs/CURSEFORGE.md' 'docs/CURSEFORGE-STORE.md is not what docs/CURSEFORGE.md makes'

store_fixture 'store page over budget'
# A section the page keeps whole, grown past the budget; the page then made from it, as it should be.
awk '{ print } /^## Who can use it$/ { for (i = 0; i < 1200; i++) print "A line of the fixture, long enough to fill the page past its budget." }' \
	"$repo_root/docs/CURSEFORGE.md" > "$case_root/docs/CURSEFORGE.md"
(cd "$case_root" && luajit scripts/curseforge-page.lua > /dev/null)
expect_failure 'store page over the CurseForge budget' 'docs/CURSEFORGE-STORE.md: '
if ! grep -Fq 'bytes over the budget' "$case_root/result.txt"; then
	printf 'FAIL: the store page over its budget failed for an unexpected reason\n' >&2
	cat "$case_root/result.txt" >&2
	exit 1
fi

# The gamepad gate's audit (1.1.5) on a project of one integration: a post-hook on a function of
# the game's, behind the gate and tagged, an Olympus tooltip counted in the ratchet, and the
# gamepad pass naming the entry. Each failure below breaks one rule.
gamepad_fixture() {
	fixture "$1"
	cp "$repo_root/scripts/gamepad-audit.lua" "$case_root/scripts/"
	cat > "$case_root/Olympus/GamepadRegistry.lua" <<'LUA'
local _, ns = ...
ns.GAMEPAD = {
	{ id = "fixture-hook", kind = "hook", files = { "Main.lua" },
		guard = "gate", toPad = "inert", toMouse = "on", safe = "off",
		why = "A fixture's post-hook on a function of the game's." },
}
LUA
	cat > "$case_root/Olympus/Main.lua" <<'LUA'
local ns = {}
function ns.Hook()
	if not ns.Gate.Allowed("fixture-hook") then return end
	hooksecurefunc("FixtureFunction", function() end) -- gp:fixture-hook
end
function ns.Tip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
end
return ns
LUA
	printf 'Main.lua tooltip 1\n' > "$case_root/scripts/gamepad-baseline.txt"
	printf 'local GP = {}\nGP.Covers("fixture-hook")\n' > "$case_root/tests/gamepad.lua"
}

gamepad_fixture 'gamepad gate passes'
"$bash_bin" "$case_root/scripts/check.sh" > "$case_root/result.txt" 2>&1
grep -Fq 'Gamepad audit: 1 integrations, 1 tagged sites, every one registered.' "$case_root/result.txt"
grep -Fq 'All repository checks passed.' "$case_root/result.txt"
printf 'ok: the gamepad audit passes a registered, tagged and gated integration\n'

gamepad_fixture 'gamepad gate: untagged reach'
printf 'hooksecurefunc("OtherFunction", function() end)\n' >> "$case_root/Olympus/nested folder/Extra.lua"
expect_failure 'gamepad audit: an untagged hooksecurefunc' "Olympus/nested folder/Extra.lua:2: hooksecurefunc reaches the game's UI without a gp: tag"

gamepad_fixture 'gamepad gate: unknown tag'
sed -i.bak 's/-- gp:fixture-hook/-- gp:fixture-hook,no-such-entry/' "$case_root/Olympus/Main.lua"
expect_failure 'gamepad audit: a tag with no entry' 'the tag gp:no-such-entry names no entry of Olympus/GamepadRegistry.lua'

gamepad_fixture 'gamepad gate: foreign global'
printf 'FixtureGlobal = true\n' >> "$case_root/Olympus/nested folder/Extra.lua"
expect_failure 'gamepad audit: a global write that is not Olympus'"'"'s' 'writes the global FixtureGlobal, which is not Olympus'"'"'s'

gamepad_fixture 'gamepad gate: no test'
printf 'local GP = {}\n' > "$case_root/tests/gamepad.lua"
expect_failure 'gamepad audit: an entry no test covers' 'no test covers fixture-hook'

gamepad_fixture 'gamepad gate: ratchet'
printf 'Main.lua tooltip 0\n' > "$case_root/scripts/gamepad-baseline.txt"
expect_failure 'gamepad audit: the tooltip ratchet raised' 'Olympus/Main.lua: 1 tooltip uses of the game'"'"'s GameTooltip, more than the 0 of scripts/gamepad-baseline.txt'

gamepad_fixture 'gamepad gate: no gate check'
sed -i.bak '/ns.Gate.Allowed("fixture-hook")/d' "$case_root/Olympus/Main.lua"
expect_failure 'gamepad audit: a gate entry'"'"'s site with no gate check' 'hooksecurefunc is gp:fixture-hook, a "gate" entry, with no gate check before it in its function'

fixture 'signing round trip failure'
printf 'echo "fixture round trip failed" >&2\nexit 1\n' > "$case_root/tests/sign-roundtrip.sh"
expect_failure 'signing round trip failure' 'fixture round trip failed'

if command -v python3 >/dev/null 2>&1; then
	fixture 'python syntax error'
	printf 'def deliberately_invalid_python(:\n' > "$case_root/scripts/broken.py"
	expect_failure 'Python syntax error in a script' 'broken.py'
else
	printf 'skip: Python syntax error (python3 not found)\n'
fi
