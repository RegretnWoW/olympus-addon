#!/usr/bin/env bash
# Builds dist/Olympus-<version>.zip with both folders, Olympus and Olympus_Arena (1.2: the Blood
# Arena's load-on-demand screens); unzip it into World of Warcraft/<flavor>/Interface/AddOns.
# Every zip also gets a sorted .files.txt manifest and a .sha256 checksum.
#   scripts/package.sh            the release; refused while Olympus/TestBuild.lua exists
#   scripts/package.sh --test N   arena test build N (1-999) of the TOC's version, into dist/testN/
#                                 and dist/Olympus-<version>-testN.zip; the repository is not touched
#   scripts/package.sh --release116
#                                 1.1.6: the release without the files only the bets need
#                                 (scripts/bets-only.txt, as HEAD has it), into
#                                 dist/release116/Olympus-<version>.zip; refused like the release
# A test build: dist/testN/Olympus/TestBuild.lua (ns.TEST_BUILD: its number, the base version, the
# build time, an expiry 21 days later, the short commit), and only that copy of Olympus.toc edited
# (its Version and Title, TestBuild.lua after Core.lua). The companion's Version stays the base
# version, ns.VERSION, which its handoff compares (Olympus_Arena/Handoff.lua).
# The 1.1.6 profile: each file bets-only.txt names is left out of the stage and its line out of its
# folder's TOC (the repository is not touched); every line left in each TOC must name a file of
# the stage. Everything else ships, the bets refused by the compliance gate (Olympus/Compliance.lua).
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf '%s\n' "$*" >&2; exit 1; }

# A package is evidence for one commit, not a snapshot of an unknown worktree. Tracked changes
# anywhere make that evidence ambiguous. Untracked or ignored files under an addon folder are also
# refused because a recursive copy could otherwise publish one silently. Finder's .DS_Store is the
# sole exception: it is never staged or listed in the zip.
clean_source() {
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "package.sh requires a Git worktree"
	git rev-parse --verify HEAD >/dev/null 2>&1 || fail "package.sh requires a Git commit"
	if ! git diff --quiet -- || ! git diff --cached --quiet --; then
		fail "package.sh requires a clean worktree: commit or remove tracked changes first"
	fi
	local path found=false
	while IFS= read -r -d '' path; do
		case "$path" in
			.DS_Store|*/.DS_Store) ;;
			*) printf 'package.sh refuses untracked or ignored addon file: %s\n' "$path" >&2; found=true ;;
		esac
	done < <(
		git ls-files -z --others --exclude-standard -- Olympus Olympus_Arena
		git ls-files -z --others --ignored --exclude-standard -- Olympus Olympus_Arena
	)
	if $found; then exit 1; fi
}

sha256_file() {
	local file=$1
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{ print $1 }'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{ print $1 }'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$file" | awk '{ print $NF }'
	else
		fail "package.sh requires sha256sum, shasum, or openssl"
	fi
}

VERSION=$(grep '^## Version:' Olympus/Olympus.toc | awk '{print $3}' | tr -d '\r')
FOLDERS=(Olympus)
if git cat-file -e HEAD:Olympus_Arena/Olympus_Arena.toc 2>/dev/null; then FOLDERS+=(Olympus_Arena); fi

MODE=release
N=
if [ "${1:-}" = "--test" ]; then
	MODE=test
	N="${2:-}"
	case "$N" in
		''|*[!0-9]*) echo "usage: scripts/package.sh --test N (N from 1 to 999)" >&2; exit 2 ;;
	esac
	N=$((10#$N))
	if [ "$N" -lt 1 ] || [ "$N" -gt 999 ]; then echo "usage: scripts/package.sh --test N (N from 1 to 999)" >&2; exit 2; fi
elif [ "${1:-}" = "--release116" ] && [ -z "${2:-}" ]; then
	MODE=release116
elif [ -n "${1:-}" ]; then
	echo "usage: scripts/package.sh [--test N | --release116]" >&2
	exit 2
fi

if [ "$MODE" != test ] && [ -e Olympus/TestBuild.lua ]; then
	fail "Olympus/TestBuild.lua exists: a release never carries a test build (delete it first)"
fi
clean_source
if ! command -v zip >/dev/null 2>&1; then fail "package.sh requires zip"; fi
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
	fail "package.sh requires sha256sum, shasum, or openssl"
fi
mkdir -p dist

# Only files recorded by HEAD become the package source. The manifest is the sorted list fed to
# zip, which makes its membership and ordering reviewable and independent of filesystem order.
stage_source() {
	local out=$1
	git archive --format=tar HEAD -- "${FOLDERS[@]}" | tar -xf - -C "$out"
	find "$out" -name '.DS_Store' -delete
}

write_package() {
	local tree=$1 zip=$2 stem manifest checksum zip_abs manifest_abs hash
	stem=${zip%.zip}
	manifest="$stem.files.txt"
	checksum="$stem.sha256"
	zip_abs="$(cd "$(dirname "$zip")" && pwd)/$(basename "$zip")"
	manifest_abs="$(cd "$(dirname "$manifest")" && pwd)/$(basename "$manifest")"
	(
		cd "$tree"
		find "${FOLDERS[@]}" \( -type f -o -type l \) -print | LC_ALL=C sort > "$manifest_abs"
		rm -f "$zip_abs"
		zip -q "$zip_abs" -@ < "$manifest_abs"
	)
	hash=$(sha256_file "$zip_abs")
	printf '%s  %s\n' "$hash" "$(basename "$zip")" > "$checksum"
}

if [ "$MODE" = test ]; then
	OUT="dist/test$N"
	rm -rf "$OUT"
	mkdir -p "$OUT"
	stage_source "$OUT"
	BUILT=$(date +%s)
	EXPIRES=$((BUILT + 21 * 86400))
	COMMIT=$(git rev-parse --short HEAD)
	cat > "$OUT/Olympus/TestBuild.lua" <<LUA
local ADDON, ns = ...
-- Written by scripts/package.sh --test $N: arena test build $N of $VERSION. Never committed.
ns.TEST_BUILD = { n = $N, base = "$VERSION", built = $BUILT, expires = $EXPIRES, commit = "$COMMIT", lane = "group" }
LUA
	awk -v v="$VERSION-test.$N" -v n="$N" '
		{ line = $0; sub(/\r$/, "", line) }
		line ~ /^## Version:/ { print "## Version: " v; next }
		line ~ /^## Title:/ { print "## Title: |cffe6c35cOlympus|r |cffff4040(arena test " n ")|r"; next }
		{ print }
		line == "Core.lua" { print "TestBuild.lua" }
	' Olympus/Olympus.toc > "$OUT/Olympus/Olympus.toc"
	ZIP="dist/Olympus-$VERSION-test$N.zip"
	write_package "$OUT" "$ZIP"
	cat > "dist/Olympus-$VERSION-test$N.txt" <<TXT
Olympus arena test build $N (of $VERSION), commit $COMMIT, expires $(date -r "$EXPIRES" +%Y-%m-%d 2>/dev/null || date -d "@$EXPIRES" +%Y-%m-%d)

For the named testers only: never put it on CurseForge or GitHub.
1. Quit the game.
2. Verify the zip against Olympus-$VERSION-test$N.sha256.
3. In the CurseForge app or WowUp, turn off auto-update for Olympus (or stop managing it).
4. Keep a copy of WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua (/oly backup works too).
5. Delete Interface/AddOns/Olympus and Interface/AddOns/Olympus_Arena, then unzip this zip in
   Interface/AddOns, so that Interface/AddOns/Olympus/Olympus.toc and
   Interface/AddOns/Olympus_Arena/Olympus_Arena.toc exist (the folders keep those names).
6. Start the game: /oly arena status says "arena test build $N".
Going back: quit, delete both folders, reinstall Olympus from the app, turn auto-update on again.
TXT
	echo "$ZIP"
	exit 0
fi

RELEASE_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/olympus-package.XXXXXX")
cleanup() { if [ -n "${RELEASE_STAGE:-}" ] && [ -d "$RELEASE_STAGE" ]; then rm -rf "$RELEASE_STAGE"; fi; }
trap cleanup EXIT
stage_source "$RELEASE_STAGE"

# 1.1.6: the files only the bets need, out of the stage and out of their folder's TOC.
leave_out_bets() {
	local stage=$1 list path folder file toc entry kept
	list=$(git show HEAD:scripts/bets-only.txt 2>/dev/null) || fail "--release116 needs scripts/bets-only.txt in HEAD"
	while IFS= read -r path; do
		path=${path%$'\r'}
		case "$path" in ''|'#'*) continue ;; esac
		case "$path" in
			Olympus/*.lua|Olympus_Arena/*.lua) ;;
			*) fail "bets-only.txt: $path is not a Lua file of Olympus or Olympus_Arena" ;;
		esac
		folder=${path%%/*}
		file=${path#*/}
		[ -f "$stage/$path" ] || fail "bets-only.txt names $path, which HEAD does not have"
		toc="$stage/$folder/$folder.toc"
		entry=${file//\//\\}
		grep -qxF "$entry" <(tr -d '\r' < "$toc") || fail "bets-only.txt names $path, which $folder.toc does not list"
		rm -f "$stage/$path"
		kept="$toc.kept"
		# (The entry through the environment: awk -v would read a backslash in it as an escape.)
		LEAVE_OUT="$entry" awk '{ line = $0; sub(/\r$/, "", line); if (line == ENVIRON["LEAVE_OUT"]) next; print }' "$toc" > "$kept"
		mv "$kept" "$toc"
	done <<< "$list"
	# Every line left in each TOC names a file of the stage.
	for folder in "${FOLDERS[@]}"; do
		toc="$stage/$folder/$folder.toc"
		while IFS= read -r entry; do
			entry=${entry%$'\r'}
			entry=$(printf '%s' "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
			case "$entry" in ''|'#'*) continue ;; esac
			[ -f "$stage/$folder/${entry//\\//}" ] || fail "--release116: $folder.toc lists $entry, which is not in the package"
		done < "$toc"
	done
}

if [ "$MODE" = release116 ]; then
	leave_out_bets "$RELEASE_STAGE"
	mkdir -p dist/release116
	ZIP="dist/release116/Olympus-$VERSION.zip"
	write_package "$RELEASE_STAGE" "$ZIP"
	echo "$ZIP"
	exit 0
fi

ZIP="dist/Olympus-$VERSION.zip"
write_package "$RELEASE_STAGE" "$ZIP"
echo "$ZIP"
