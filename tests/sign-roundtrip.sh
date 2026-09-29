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

# The council with its departments and titles (0.9.9): both lists from a JSON file, the default
# one (OLYMPUS_COUNCIL_JSON here, never the author's) or one given. The first as the author would
# write it (names and titles with spaces around them, an accented name, Forever's realm group by
# default); the second as much as the addon takes (30 names, 8 departments, the longest titles
# and department names, an icon's highest file number), public.
export OLYMPUS_COUNCIL_JSON="$scratch/council.json"
cat > "$OLYMPUS_COUNCIL_JSON" <<'JSON'
{"public": false,
 "departments": [
  {"name": "Department of War", "icon": "INV_Sword_04",
   "members": [{"name": "Other Mod", "title": "Operations Director"}, {"name": "Fàladoriel Test"}]},
  {"name": "Department of Coin", "icon": 133784, "members": [{"name": "Third Mod", "title": "Keeper of Coin"}]}],
 "members": [{"name": " Test Councillor ", "title": " Council Speaker "}]}
JSON
OLYMPUS_COUNCIL_OUT="$scratch/council1.lua" python3 "$signer" council > /dev/null
python3 - "$scratch/limits.json" <<'PY'
import json, sys
names = ["Limit Mod %02d" % i for i in range(1, 30)] + ["L" * 48]
members = [{"name": n, "title": ("Title of %s " % n + "x" * 48)[:48]} for n in names]
depts = [{"name": ("Department %d " % i + "y" * 40)[:40], "icon": 2147483647 if i == 0 else "INV_Misc_%02d" % i,
          "members": members[2 + i::8]} for i in range(8)]
council = {"realm": "Realm", "public": True, "members": members[:2], "departments": depts}
json.dump(council, open(sys.argv[1], "w"))
PY
OLYMPUS_COUNCIL_OUT="$scratch/council2.lua" python3 "$signer" council "$scratch/limits.json" > /dev/null
printf 'ok: two councils signed, names and titles\n'

# A council the addon would not take: refused before anything is signed, nothing written, and
# the key's last time unchanged.
last_at() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("last_at"))' "$OLYMPUS_COUNCIL_KEY"; }
before=$(last_at)
refused_council() {
	printf '%s' "$1" > "$scratch/bad.json"
	if OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" council "$scratch/bad.json" > refused.txt 2>&1; then fail "signed: $2"; fi
	[ ! -e "$scratch/refused.lua" ] || fail "a list was written for: $2"
	if grep -Fq 'Traceback' refused.txt; then fail "a crash, not a refusal: $2"; fi
	printf 'ok: refused, %s\n' "$2"
}
member() { printf '{"members": [{"name": "%s", "title": "%s"}]}' "$1" "$2"; }
dept() { printf '{"departments": [{"name": "%s", "icon": %s, "members": [{"name": "Good Name"}]}]}' "$1" "$2"; }
for c in '^' ';' '=' ',' '~' '|' '\t'; do
	refused_council "$(member 'Good Name' "Boss${c}Man")" "a title with \"$c\""
	refused_council "$(member "Bad${c}Name" 'Boss')" "a name with \"$c\""
	refused_council "$(dept "War${c}Peace" '""')" "a department with \"$c\""
done
refused_council "$(member 'Good Name' "$(printf 't%.0s' $(seq 1 49))")" 'a title longer than 48 bytes'
refused_council "$(member "$(printf 'n%.0s' $(seq 1 49))" 'Boss')" 'a name longer than 48 bytes'
refused_council "$(dept "$(printf 'd%.0s' $(seq 1 41))" '""')" 'a department longer than 40 bytes'
refused_council "$(dept ' ' '""')" 'a department without a name'
for icon in '"a b"' '"..\\x"' '"Interface\\\\Icons\\\\X"' '"0"' '0' '2147483648' '"12345678901"' '1.5' 'true' "\"$(printf 'i%.0s' $(seq 1 65))\""; do
	refused_council "$(dept 'War' "$icon")" "an icon $icon"
done
refused_council '{"members": [{"name": "Same Name"}], "departments": [{"name": "War", "members": [{"name": "same name"}]}]}' 'a name twice'
refused_council '{"departments": [{"name": "War", "members": []}, {"name": "war", "members": []}]}' 'a department twice'
refused_council "$(python3 -c 'import json; print(json.dumps({"departments": [{"name": "D%d" % i} for i in range(9)]}))')" '9 departments'
refused_council "$(python3 -c 'import json; print(json.dumps({"members": [{"name": "Name %d" % i} for i in range(31)]}))')" '31 names'
refused_council "$(python3 - "$scratch/limits.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
for d in c["departments"]: d["icon"] = ("INV_" + "z" * 64)[:64]
print(json.dumps(c))
PY
)" 'a titles list longer than the addon takes'
refused_council '{"public": "yes"}' 'public that is not true or false'
refused_council '{"realm": "Realm~X"}' 'a realm group with the separator'
refused_council '{"members": [{"name": "Good Name", "tittle": "Boss"}]}' 'an unknown field (a typo)'
refused_council '{"members": {"name": "Good Name"}}' 'members that are not a list'
refused_council '{"departments": {"name": "War"}}' 'departments that are not a list'
refused_council 'not json' 'a file that is not JSON'
if OLYMPUS_COUNCIL_JSON="$scratch/missing.json" OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" council > refused.txt 2>&1; then fail 'signed: no council file'; fi
if grep -Fq 'Traceback' refused.txt; then fail 'a crash, not a refusal: no council file'; fi
printf 'ok: refused, no council file\n'
[ "$(last_at)" = "$before" ] || fail "a refused council moved the key's last time"
printf 'ok: nothing refused was signed\n'

# The King's Steward (1.0.0): "steward" adds him to the council file and signs the council at
# once; "check" reads the lists back and checks them with the key; "steward --remove" signs a
# newer council without him. The council file keeps everything else.
cp "$OLYMPUS_COUNCIL_JSON" "$scratch/council-before.json"
OLYMPUS_COUNCIL_OUT="$scratch/council3.lua" python3 "$signer" steward " Test Steward-ClassicBetaPvP2 " > steward.txt
python3 - "$OLYMPUS_COUNCIL_JSON" "$scratch/council-before.json" <<'PY' || fail 'the council file after "steward"'
import json, sys
after, before = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert after.pop("stewards") == ["Test Steward-ClassicBetaPvP2"], "the Steward, trimmed"
assert after == before, "everything else kept"
PY
OLYMPUS_COUNCIL_OUT="$scratch/council3.lua" python3 "$signer" check > check.txt || fail 'check refused a list the script signed'
grep -Fq "the Alliance King's Steward: Test Steward-ClassicBetaPvP2" check.txt || fail 'check does not show the Steward'
[ "$(grep -c 'signature good' check.txt)" = 2 ] || fail 'check does not say both signatures hold'
# A byte changed in the file: check says so, and fails.
sed 's/Test Steward/Test Stewart/' "$scratch/council3.lua" > "$scratch/tampered.lua"
if python3 "$signer" --check "$scratch/tampered.lua" > tampered.txt 2>&1; then fail 'check took a changed list'; fi
grep -Fq 'SIGNATURE BAD' tampered.txt || fail 'check does not say which signature failed'
printf 'ok: a Steward marked, signed with the council, read back and checked; a changed byte refused\n'
before=$(last_at)
refused_steward() {
	if OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" steward "$@" > refused.txt 2>&1; then fail "signed: steward $*"; fi
	[ ! -e "$scratch/refused.lua" ] || fail "a list was written for: steward $*"
	if grep -Fq 'Traceback' refused.txt; then fail "a crash, not a refusal: steward $*"; fi
	printf 'ok: refused, steward %s\n' "$*"
}
refused_steward 'Test Steward-ClassicBetaPvP2'
refused_steward 'Bad-Name-ClassicBetaPvP'
refused_steward 'Three Word Name-ClassicBetaPvP'
refused_steward 'Digit5 Name-ClassicBetaPvP'
refused_steward 'Good Name-Realm Two'
refused_steward 'Good Name-OtherRealm'
refused_steward 'Good^Name-ClassicBetaPvP'
refused_steward 'Good Name-ClassicBetaPvP' Neutral
refused_steward --remove 'Nobody Here-ClassicBetaPvP'
refused_council '{"stewards": ["A Aa-Realm", "B Bb-Realm", "C Cc-Realm", "D Dd-Realm"], "realm": "Realm"}' 'four Stewards for one King'
refused_council '{"stewards": ["Same Name-Realm", {"name": "same name-Realm", "faction": "Horde"}], "realm": "Realm"}' 'a Steward twice'
refused_council '{"stewards": [{"name": "Good Name-Realm", "side": "Horde"}], "realm": "Realm"}' 'a Steward with an unknown field'
refused_council '{"stewards": "Good Name-Realm"}' 'stewards that are not a list'
[ "$(last_at)" = "$before" ] || fail "a refused Steward moved the key's last time"
grep -Fq 'Test Steward' "$OLYMPUS_COUNCIL_JSON" || fail 'a refused Steward changed the council file'
OLYMPUS_COUNCIL_OUT="$scratch/council4.lua" python3 "$signer" steward --remove 'test steward-classicbetapvp2' > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council4.lua" python3 "$signer" check > check.txt || fail 'check refused the list without him'
grep -Fq "the Alliance King's Steward: none" check.txt || fail 'the Steward is still in the newer list'
printf 'ok: the Steward removed: a newer council without him\n'

luajit "$repo_root/tests/sign-roundtrip.lua" "$repo_root" "$OLYMPUS_COUNCIL_KEY" "$future" \
	"$scratch/list1.lua" "$scratch/list2.lua" "$scratch/list3.lua" "$scratch/council1.lua" "$scratch/council2.lua" \
	"$scratch/council3.lua" "$scratch/council4.lua"
