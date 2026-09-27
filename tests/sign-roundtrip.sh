#!/usr/bin/env bash
# The High Council's signing script end to end (scripts/council-sign.py): a throwaway key made
# in a temporary folder, lists signed with it, and Sign.lua checking what the script wrote
# (tests/sign-roundtrip.lua). Never the author's key: HOME and the key path both point into the
# temporary folder, which is removed at the end. Skipped without python3 (CI has it).
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1; then
	printf 'python3 not found: signing round trip skipped\n'
	exit 0
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export HOME="$scratch/home"
export OLYMPUS_COUNCIL_KEY="$scratch/keys/council-key.json"
export OLYMPUS_COUNCIL_OUT="$scratch/unused.lua"
mkdir -p "$HOME"
cd "$scratch"
signer="$repo_root/scripts/council-sign.py"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

python3 "$signer" keygen > keygen.txt
mode=$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$OLYMPUS_COUNCIL_KEY")
[ "$mode" = "0o600" ] || fail "the key file is readable by others ($mode)"
if python3 "$signer" keygen > again.txt 2>&1; then fail 'a second keygen replaced the key'; fi
grep -Fq 'key exists' again.txt || fail 'a second keygen failed for an unexpected reason'
printf 'ok: a throwaway key, readable by its owner only, never replaced\n'

# Two lists one after the other (the same second, as a rule): each newer than the one before.
OLYMPUS_COUNCIL_OUT="$scratch/list1.lua" python3 "$signer" sign " Test Councillor, Other Mod,Fàladoriel Test " Realm > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/list2.lua" python3 "$signer" sign "Test Councillor" Realm > /dev/null
# A key whose last list carries a time ahead of this clock (a clock put right since): newer still.
future=$(python3 - "$OLYMPUS_COUNCIL_KEY" <<'PY'
import json, sys, time
path = sys.argv[1]
with open(path) as f: key = json.load(f)
key["last_at"] = int(time.time()) + 100000
with open(path, "w") as f: json.dump(key, f)
print(key["last_at"])
PY
)
OLYMPUS_COUNCIL_OUT="$scratch/list3.lua" python3 "$signer" sign "Test Councillor,Third Mod" > /dev/null
printf 'ok: three lists signed\n'

# Names the addon would not take are refused before anything is signed.
refused() {
	if OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" sign "$1" Realm > refused.txt 2>&1; then fail "signed: $2"; fi
	[ ! -e "$scratch/refused.lua" ] || fail "a list was written for: $2"
	printf 'ok: refused, %s\n' "$2"
}
refused 'Bad|Name' 'a name with an escape character'
refused 'Bad~Name' 'a name with the separator'
refused "$(printf 'Bad\tName')" 'a name with a control character'
refused "$(printf 'x%.0s' $(seq 1 49))" 'a name longer than 48 bytes'
refused 'Same Name,same name' 'a name twice'
refused "$(seq -s, -f 'Name %g' 1 31)" '31 names'
if OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" sign "Good Name" 'Realm~X' > refused.txt 2>&1; then fail 'signed: a realm group with the separator'; fi
printf 'ok: refused, a realm group with the separator\n'

luajit "$repo_root/tests/sign-roundtrip.lua" "$repo_root" "$OLYMPUS_COUNCIL_KEY" "$future" \
	"$scratch/list1.lua" "$scratch/list2.lua" "$scratch/list3.lua"
