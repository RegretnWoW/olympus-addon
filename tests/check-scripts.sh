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

# 1.2: the Blood Arena's companion folder is checked too: its syntax, its TOC's files, its lint.
fixture 'companion checks'
mkdir -p "$case_root/Olympus_Arena"
printf 'return {}\n' > "$case_root/Olympus_Arena/Handoff.lua"
printf '## Interface: 16001\r\n\r\nHandoff.lua\r\nMissing.lua\r\n' > "$case_root/Olympus_Arena/Olympus_Arena.toc"
expect_failure 'missing companion TOC file' 'Cannot read TOC entry: Olympus_Arena/Missing.lua'
printf '## Interface: 16001\r\n\r\nHandoff.lua\r\n' > "$case_root/Olympus_Arena/Olympus_Arena.toc"
printf 'local =\n' > "$case_root/Olympus_Arena/Broken.lua"
expect_failure 'syntax error in the companion' 'Broken.lua'
printf 'local function readValue() return laterValue end\nlocal laterValue = 1\n' > "$case_root/Olympus_Arena/Broken.lua"
expect_failure 'local/global lint failure in the companion' "Olympus_Arena/Broken.lua: 'laterValue' is read as a global"

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

# 1.2 (the Blood Arena): scripts/package.sh in a temporary copy. The release zip holds both folders,
# Olympus and Olympus_Arena, and no test build; --test N writes TestBuild.lua after Core.lua and the
# -test.N version in its copy of Olympus.toc alone (the repository's untouched), the companion keeping
# the base version, which its handoff accepts; a release is refused while Olympus/TestBuild.lua exists.
package_fail() {
	printf 'FAIL: package.sh: %s\n' "$1" >&2
	exit 1
}
package_manifest_matches() {
	local zip=$1 manifest=${1%.zip}.files.txt actual="$pkg/actual-files.txt"
	[ -f "$manifest" ] || package_fail "no $manifest"
	unzip -Z1 "$zip" | sed '/\/$/d' | LC_ALL=C sort > "$actual"
	cmp -s "$manifest" "$actual" || package_fail "$(basename "$manifest") does not match its zip"
}
package_checksum_matches() {
	local zip=$1 checksum=${1%.zip}.sha256 expected actual named
	[ -f "$checksum" ] || package_fail "no $checksum"
	expected=$(awk 'NF { print $1; exit }' "$checksum")
	named=$(awk 'NF { print $2; exit }' "$checksum")
	[ "$named" = "$(basename "$zip")" ] || package_fail "$(basename "$checksum") names $named"
	if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum "$zip" | awk '{ print $1 }')
	elif command -v shasum >/dev/null 2>&1; then actual=$(shasum -a 256 "$zip" | awk '{ print $1 }')
	else actual=$(openssl dgst -sha256 "$zip" | awk '{ print $NF }')
	fi
	[ "$expected" = "$actual" ] || package_fail "$(basename "$checksum") does not match its zip"
}
have_sha=false
for sha_tool in sha256sum shasum openssl; do
	if command -v "$sha_tool" >/dev/null 2>&1; then have_sha=true; break; fi
done
if command -v git >/dev/null 2>&1 && command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v luajit >/dev/null 2>&1 && $have_sha; then
	pkg="$scratch_root/package"
	mkdir -p "$pkg/scripts"
	cp -R "$repo_root/Olympus" "$repo_root/Olympus_Arena" "$pkg/"
	cp "$repo_root/scripts/package.sh" "$repo_root/scripts/bets-only.txt" "$pkg/scripts/"
	rm -f "$pkg/Olympus/TestBuild.lua"
	(
		cd "$pkg"
		git init -q
		git config user.name "Package Test"
		git config user.email "package-test@example.invalid"
		git add Olympus Olympus_Arena scripts/package.sh scripts/bets-only.txt
		git commit -qm "package fixture"
	)
	version=$(grep '^## Version:' "$pkg/Olympus/Olympus.toc" | awk '{print $3}' | tr -d '\r')
	(cd "$pkg" && bash scripts/package.sh > out.txt) || package_fail 'the release did not build'
	release="$pkg/dist/Olympus-$version.zip"
	[ -f "$release" ] || package_fail "no $release"
	package_manifest_matches "$release"
	package_checksum_matches "$release"
	unzip -l "$release" > "$pkg/list.txt"
	grep -q ' Olympus/Olympus.toc$' "$pkg/list.txt" || package_fail 'the release lacks Olympus'
	grep -q ' Olympus_Arena/Olympus_Arena.toc$' "$pkg/list.txt" || package_fail 'the release lacks Olympus_Arena'
	grep -q 'TestBuild.lua' "$pkg/list.txt" && package_fail 'the release carries a test build'
	unzip -p "$release" Olympus/Olympus.toc | tr -d '\r' | grep -q "^## Version: $version$" || package_fail 'the release version'
	printf 'ok: package.sh: the release zip holds both folders and no test build; manifest and checksum match\n'

	(cd "$pkg" && bash scripts/package.sh --test 3 > out.txt) || package_fail 'the test build did not build'
	testzip="$pkg/dist/Olympus-$version-test3.zip"
	[ -f "$testzip" ] || package_fail "no $testzip"
	[ -f "$pkg/dist/Olympus-$version-test3.txt" ] || package_fail 'no install steps'
	package_manifest_matches "$testzip"
	package_checksum_matches "$testzip"
	grep -qx 'Olympus/TestBuild.lua' "${testzip%.zip}.files.txt" || package_fail 'the test manifest lacks TestBuild.lua'
	unzip -l "$testzip" > "$pkg/list.txt"
	grep -q ' Olympus_Arena/Olympus_Arena.toc$' "$pkg/list.txt" || package_fail 'the test build lacks Olympus_Arena'
	unzip -p "$testzip" Olympus/Olympus.toc | tr -d '\r' > "$pkg/toc.txt"
	grep -q "^## Version: $version-test.3$" "$pkg/toc.txt" || package_fail 'the test version'
	grep -q '(arena test 3)' "$pkg/toc.txt" || package_fail 'the test title'
	awk 'prev == "Core.lua" && $0 == "TestBuild.lua" { found = 1 } { prev = $0 } END { exit !found }' "$pkg/toc.txt" || package_fail 'TestBuild.lua after Core.lua'
	cmp -s "$repo_root/Olympus/Olympus.toc" "$pkg/Olympus/Olympus.toc" || package_fail 'the copy of the repository changed'
	[ ! -e "$pkg/Olympus/TestBuild.lua" ] || package_fail 'TestBuild.lua written into the repository'
	mkdir -p "$pkg/unzipped"
	(cd "$pkg/unzipped" && unzip -q "$testzip")
	luajit - "$pkg/unzipped" "$version" <<'LUA' || package_fail 'the test build is not one Olympus takes'
local dir, version = arg[1], arg[2]
local function Read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
-- The test build's shape, as ArenaNet.lua's Arena.TestBuild reads it.
local L = setmetatable({}, { __index = function(_, k) return k end })
local ns = { L = L, Comm = { Handle = function() end }, On = function() end, RegisterEvent = function() end,
	Now = os.time, Print = function() end, Log = function() end, statusLines = {} }
assert(loadfile(dir .. "/Olympus/TestBuild.lua"))("Olympus", ns)
assert(loadfile(dir .. "/Olympus/ArenaNet.lua"))("Olympus", ns)
local t = assert(ns.Arena.TestBuild(), "Arena.TestBuild refuses it")
assert(t.n == 3 and t.base == version and t.expires - t.built == 21 * 86400, "its fields")
-- The companion's handoff takes it: its Version is Olympus's base version, ns.VERSION.
ns.VERSION = assert(Read(dir .. "/Olympus/Core.lua"):match('\nns%.VERSION = "([^"]+)"'))
local companion = assert(Read(dir .. "/Olympus_Arena/Olympus_Arena.toc"):match("## Version:%s*([^\r\n]+)"))
C_AddOns = { GetAddOnMetadata = function(name, field) if name == "Olympus_Arena" and field == "Version" then return companion end end }
OlympusArenaHandoff = ns
local own = {}
assert(loadfile(dir .. "/Olympus_Arena/Handoff.lua"))("Olympus_Arena", own)
assert(OlympusArenaHandoff == nil, "the handoff is taken")
assert(ns.Arena.companionReady == true and own.host == ns, "the handoff refused the test build's companion")
LUA
	printf 'ok: package.sh --test 3: both folders, TestBuild.lua after Core.lua, manifest and checksum match, the handoff takes it\n'

	# 1.1.6: --release116 leaves out the files only the bets need (scripts/bets-only.txt) and their
	# TOC lines; both folders, the compliance gate and every other file the TOCs list ship.
	(cd "$pkg" && bash scripts/package.sh --release116 > out.txt) || package_fail 'the 1.1.6 package did not build'
	cut="$pkg/dist/release116/Olympus-$version.zip"
	[ -f "$cut" ] || package_fail "no $cut"
	package_manifest_matches "$cut"
	package_checksum_matches "$cut"
	unzip -Z1 "$cut" > "$pkg/list.txt"
	left_out=0
	while IFS= read -r path; do
		case "$path" in ''|'#'*) continue ;; esac
		left_out=$((left_out + 1))
		grep -qxF "$path" "$pkg/list.txt" && package_fail "the 1.1.6 package carries $path"
		unzip -p "$cut" "${path%%/*}/${path%%/*}.toc" | tr -d '\r' | grep -qxF "${path#*/}" && package_fail "the 1.1.6 TOC lists ${path#*/}"
		[ -f "$pkg/$path" ] || package_fail "the repository copy lost $path"
	done < "$repo_root/scripts/bets-only.txt"
	[ "$left_out" -ge 1 ] || package_fail 'bets-only.txt names no file'
	for need in Olympus/Olympus.toc Olympus/Compliance.lua Olympus/Locales/ComplianceText.lua Olympus/Lottery.lua Olympus/Stakes.lua Olympus_Arena/Olympus_Arena.toc; do
		grep -qxF "$need" "$pkg/list.txt" || package_fail "the 1.1.6 package lacks $need"
	done
	grep -q TestBuild.lua "$pkg/list.txt" && package_fail 'the 1.1.6 package carries a test build'
	for folder in Olympus Olympus_Arena; do
		unzip -p "$cut" "$folder/$folder.toc" | tr -d '\r' | while IFS= read -r entry; do
			case "$entry" in ''|'#'*) continue ;; esac
			grep -qxF "$folder/${entry//\\//}" "$pkg/list.txt" || { printf 'FAIL: package.sh: the 1.1.6 %s.toc lists %s, not in the zip\n' "$folder" "$entry" >&2; exit 1; }
		done || exit 1
	done
	cmp -s "$repo_root/Olympus/Olympus.toc" "$pkg/Olympus/Olympus.toc" || package_fail 'the 1.1.6 package changed the repository copy'
	cp "$pkg/scripts/bets-only.txt" "$pkg/bets-only.saved"
	printf 'Olympus/NotThere.lua\n' >> "$pkg/scripts/bets-only.txt"
	git -C "$pkg" commit -qam "a leave-out line naming no file"
	if (cd "$pkg" && bash scripts/package.sh --release116 > out.txt 2>&1); then package_fail 'a leave-out line naming no file built'; fi
	grep -Fq 'which HEAD does not have' "$pkg/out.txt" || package_fail 'the leave-out refusal says why'
	cp "$pkg/bets-only.saved" "$pkg/scripts/bets-only.txt"
	rm -f "$pkg/bets-only.saved"
	git -C "$pkg" commit -qam "the leave-out list back"
	printf 'ok: package.sh --release116: the 1.1.6 package without the files only the bets need, its TOCs naming only files it has\n'

	printf 'return {}\n' > "$pkg/Olympus/UntrackedWouldShip.lua"
	if (cd "$pkg" && bash scripts/package.sh > out.txt 2>&1); then package_fail 'an untracked addon file silently shipped'; fi
	grep -Fq 'refuses untracked or ignored addon file: Olympus/UntrackedWouldShip.lua' "$pkg/out.txt" || package_fail 'the untracked-file refusal says why'
	rm -f "$pkg/Olympus/UntrackedWouldShip.lua"
	printf 'ok: package.sh refuses an untracked file under an addon folder\n'

	printf '\n-- a tracked packaging-test change\n' >> "$pkg/Olympus/Core.lua"
	if (cd "$pkg" && bash scripts/package.sh > out.txt 2>&1); then package_fail 'a tracked change silently shipped'; fi
	grep -Fq 'requires a clean worktree' "$pkg/out.txt" || package_fail 'the tracked-change refusal says why'
	git -C "$pkg" checkout -- Olympus/Core.lua
	printf 'ok: package.sh refuses tracked worktree changes\n'

	cp "$pkg/unzipped/Olympus/TestBuild.lua" "$pkg/Olympus/TestBuild.lua"
	if (cd "$pkg" && bash scripts/package.sh > out.txt 2>&1); then package_fail 'a release built with Olympus/TestBuild.lua there'; fi
	grep -Fq 'TestBuild.lua exists' "$pkg/out.txt" || package_fail 'the refusal says why'
	if (cd "$pkg" && bash scripts/package.sh --test 0 > out.txt 2>&1); then package_fail 'test build 0'; fi
	if (cd "$pkg" && bash scripts/package.sh --test x > out.txt 2>&1); then package_fail 'test build x'; fi
	printf 'ok: package.sh refuses a release over a test build, and a test number not from 1 to 999\n'
else
	printf 'skip: package.sh (git, zip, unzip, luajit or a SHA-256 tool not found)\n'
fi
