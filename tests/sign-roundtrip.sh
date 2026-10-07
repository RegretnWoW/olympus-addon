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
 "members": [{"name": " Test Councillor ", "title": " Council Speaker "}],
 "leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance"],
  "guilds": [{"guild": "Olympus Zeus", "leader": "Test Lord-ClassicBetaPvP",
               "officers": ["Test Captain-ClassicBetaPvP2"]}]}}
JSON
OLYMPUS_COUNCIL_OUT="$scratch/council1.lua" python3 "$signer" council > /dev/null
grep -Fq 'ns.COUNCIL_AUTHORITY = {' "$scratch/council1.lua" || fail 'leadership was not written as a separate signed authority set'
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
refused_council '{"leaders": []}' 'the old implicit leaders field (enforcement must be explicit)'
refused_council '{"leadership": {"mode": "legacy", "epoch": 1, "factions": ["Alliance"], "guilds": []}}' 'a leadership mode other than enforce'
refused_council '{"leadership": {"mode": "enforce", "epoch": 0, "factions": ["Alliance"], "guilds": []}}' 'leadership epoch zero'
refused_council '{"leadership": {"mode": "enforce", "epoch": 1, "factions": [], "guilds": []}}' 'leadership without an enforced faction'
refused_council '{"leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance", "Alliance"], "guilds": []}}' 'a leadership faction twice'
refused_council '{"realm": "Realm", "leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance"], "guilds": [{"guild": "Olympus Zeus", "leader": "Lord Name"}]}}' 'a leader without an exact realm'
refused_council '{"realm": "Realm", "leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance"], "guilds": [{"guild": "Olympus Zeus", "leader": "Lord Name-Other"}]}}' 'a leader on another realm'
refused_council '{"realm": "Realm", "leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance"], "guilds": [{"guild": "Olympus Zeus", "leader": "Lord Name-Realm", "officers": ["Lord Name-Realm"]}]}}' 'a signed leader twice'
refused_council '{"realm": "Realm", "leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance"], "guilds": [{"guild": "Olympus Zeus", "leader": "Lord Name-Realm", "side": "Horde"}]}}' 'a leadership guild with an unknown field'
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
[ "$(grep -c 'signature good' check.txt)" = 3 ] || fail 'check does not say the names, titles and authority signatures hold'
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

# The approved guilds (1.1): "guild" adds one to the council file and signs the council at once,
# printing the titles list whole to paste in game; "guild --remove" signs a newer one without it.
cp "$OLYMPUS_COUNCIL_JSON" "$scratch/council-before-guild.json"
OLYMPUS_COUNCIL_OUT="$scratch/council5.lua" python3 "$signer" guild "  Test Guild " > guild.txt
python3 - "$OLYMPUS_COUNCIL_JSON" "$scratch/council-before-guild.json" <<'PY' || fail 'the council file after "guild"'
import json, sys
after, before = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert after.pop("guilds") == ["Test Guild"], "the guild, trimmed"
assert after == before, "everything else kept"
PY
grep -Fq 'to paste in game with /oly approved paste:' guild.txt || fail 'guild does not print the list to paste'
pasted=$(tail -n 1 guild.txt)
python3 - "$scratch/council5.lua" "$pasted" <<'PY' || fail 'the printed list is not the one written'
import re, sys
lua, pasted = open(sys.argv[1]).read(), sys.argv[2]
m = re.search(r'^ns\.COUNCIL_TITLES = "(.*)"$', lua, re.M)
body = m.group(1)
out, i = bytearray(), 0
while i < len(body):
    if body[i] == "\\": out.append(int(body[i + 1:i + 4])); i += 4
    else: out += body[i].encode(); i += 1
assert out.decode() == pasted, "byte for byte"
PY
OLYMPUS_COUNCIL_OUT="$scratch/council5.lua" python3 "$signer" check > check.txt || fail 'check refused the list with the guild'
grep -Fq "the Alliance's approved guilds: Test Guild" check.txt || fail 'check does not show the approved guild'
printf 'ok: a guild approved, signed with the council, printed whole to paste, read back and checked\n'
before=$(last_at)
refused_guild() {
	if OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" guild "$@" > refused.txt 2>&1; then fail "signed: guild $*"; fi
	[ ! -e "$scratch/refused.lua" ] || fail "a list was written for: guild $*"
	if grep -Fq 'Traceback' refused.txt; then fail "a crash, not a refusal: guild $*"; fi
	printf 'ok: refused, guild %s\n' "$*"
}
refused_guild 'Test Guild'
refused_guild 'test guild'
refused_guild 'Guild5'
refused_guild 'Bad^Guild'
refused_guild 'Bad,Guild'
refused_guild ' '
refused_guild "$(printf 'g%.0s' $(seq 1 25))"
refused_guild 'Good Guild' Neutral
refused_guild --remove 'Nobody Guild'
refused_council "$(python3 -c 'import json; print(json.dumps({"guilds": ["Guild %s" % chr(65 + i) for i in range(21)]}))')" '21 approved guilds for one faction'
refused_council '{"guilds": [{"name": "Good Guild", "side": "Horde"}]}' 'a guild with an unknown field'
refused_council '{"guilds": "Good Guild"}' 'guilds that are not a list'
refused_council '{"guilds": ["Same Guild", "same guild"]}' 'a guild twice'
[ "$(last_at)" = "$before" ] || fail "a refused guild moved the key's last time"
OLYMPUS_COUNCIL_OUT="$scratch/council6.lua" python3 "$signer" guild --remove 'test guild' > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council6.lua" python3 "$signer" check > check.txt || fail 'check refused the list without the guild'
grep -Fq "the Alliance's approved guilds: none" check.txt || fail 'the guild is still in the newer list'
printf 'ok: the guild removed: a newer council without it\n'

# The Blood Arena's signed arbiters (1.2): "arbiter" (with --audit: an auditor too) adds one to the
# council file and signs the council at once; "arbiter --remove" signs a newer one without him.
cp "$OLYMPUS_COUNCIL_JSON" "$scratch/council-before-arbiter.json"
OLYMPUS_COUNCIL_OUT="$scratch/council7.lua" python3 "$signer" arbiter --audit " Test Arbiter-ClassicBetaPvP2 " > /dev/null
python3 - "$OLYMPUS_COUNCIL_JSON" "$scratch/council-before-arbiter.json" <<'PY2' || fail 'the council file after "arbiter"'
import json, sys
after, before = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert after.pop("arbiters") == [{"name": "Test Arbiter-ClassicBetaPvP2", "audit": True}], "the arbiter, trimmed, an auditor"
before.pop("arbiters", None)
assert after == before, "the rest of the council file kept"
PY2
OLYMPUS_COUNCIL_OUT="$scratch/council7.lua" python3 "$signer" check > check.txt || fail 'check refused the list with the arbiter'
grep -Fq "the Alliance's arena arbiters (+a: auditor): Test Arbiter-ClassicBetaPvP2+a" check.txt || fail 'check does not show the arbiter'
printf 'ok: an arena arbiter and auditor signed with the council, read back and checked\n'
before=$(last_at)
refused_arbiter() {
	if OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" arbiter "$@" > refused.txt 2>&1; then fail "signed: arbiter $*"; fi
	[ ! -e "$scratch/refused.lua" ] || fail "a list was written for: arbiter $*"
	if grep -Fq 'Traceback' refused.txt; then fail "a crash, not a refusal: arbiter $*"; fi
	printf 'ok: refused, arbiter %s\n' "$*"
}
refused_arbiter 'Test Arbiter-ClassicBetaPvP2'
refused_arbiter 'Bad-Name-ClassicBetaPvP'
refused_arbiter 'Good Name-OtherRealm'
refused_arbiter 'Good+Name-ClassicBetaPvP'
refused_arbiter 'Good Name-ClassicBetaPvP' Neutral
refused_arbiter --remove 'Nobody Here-ClassicBetaPvP'
refused_council '{"arbiters": ["A Aa", "B Bb", "C Cc", "D Dd", "E Ee", "F Ff"]}' 'six arbiters for one faction'
refused_council '{"arbiters": [{"name": "Good Name", "audit": "yes"}]}' 'an audit flag that is not true or false'
refused_council '{"arbiters": [{"name": "Good Name", "side": "Horde"}]}' 'an arbiter with an unknown field'
[ "$(last_at)" = "$before" ] || fail "a refused arbiter moved the key's last time"
OLYMPUS_COUNCIL_OUT="$scratch/council8.lua" python3 "$signer" arbiter --remove 'test arbiter-classicbetapvp2' > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council8.lua" python3 "$signer" check > check.txt || fail 'check refused the list without the arbiter'
grep -Fq "the Alliance's arena arbiters (+a: auditor): none" check.txt || fail 'the arbiter is still in the newer list'
printf 'ok: the arbiter removed: a newer council without him\n'

# The Church's Twelve Apostles (1.1.6): "apostle" adds one to the council file and signs at once;
# "apostle --remove" signs a newer list without him; a thirteenth is refused before anything is signed.
OLYMPUS_COUNCIL_OUT="$scratch/council-apostle.lua" python3 "$signer" apostle " Test Apostle-ClassicBetaPvP " > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council-apostle.lua" python3 "$signer" check > check.txt || fail 'check refused the list with the apostle'
grep -Fq "the Alliance's Church Apostles (* the Head): Test Apostle-ClassicBetaPvP" check.txt || fail 'check does not show the apostle'
grep -Fq '^apostles^Alliance^Test Apostle-ClassicBetaPvP' "$scratch/council-apostle.lua" || fail 'the titles list has no apostles entry'
# An Apostle signed with "apostle" is no Head: nobody is Head for being signed first.
grep -Fq '^apostles^Alliance^*' "$scratch/council-apostle.lua" && fail 'an Apostle signed alone was marked Head'
# Asmongold is the Head, not a nominate-able signed Apostle. Refusal must not alter the key,
# private council file or signed output; older signed starred lists remain a runtime fixture.
before=$(last_at)
council_before=$(shasum -a 256 "$OLYMPUS_COUNCIL_JSON")
if OLYMPUS_COUNCIL_OUT="$scratch/refused-head.lua" python3 "$signer" apostle --head 'Test Head-ClassicBetaPvP' > refused.txt 2>&1; then fail 'a Head was nominated'; fi
grep -Fq 'Asmongold is Head of the Church' refused.txt || fail 'head refusal gave no reason'
[ ! -e "$scratch/refused-head.lua" ] || fail 'refused head wrote a signed list'
[ "$(last_at)" = "$before" ] || fail 'refused head moved the key time'
[ "$(shasum -a 256 "$OLYMPUS_COUNCIL_JSON")" = "$council_before" ] || fail 'refused head changed the council file'
refused_council '{"apostles": [{"name": "A Aa", "head": true}]}' 'a legacy Head nomination in a new list'
before=$(last_at)
refused_council '{"apostles": ["A Aa", "B Bb", "C Cc", "D Dd", "E Ee", "F Ff", "G Gg", "H Hh", "I Ii", "J Jj", "K Kk", "L Ll", "M Mm"]}' 'thirteen apostles for one faction'
refused_council '{"apostles": ["Same Name", "same name-ClassicBetaPvP"]}' 'an apostle twice'
[ "$(last_at)" = "$before" ] || fail "a refused apostle list moved the key's last time"
OLYMPUS_COUNCIL_OUT="$scratch/council-apostle.lua" python3 "$signer" apostle --remove 'test apostle-classicbetapvp' > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council-apostle.lua" python3 "$signer" check > check.txt || fail 'check refused the list without the apostle'
grep -Fq "the Alliance's Church Apostles (* the Head): none" check.txt || fail 'the apostle is still in the newer list'
printf 'ok: a Church Apostle signed with the council, read back, refused past twelve and removed\n'

# Signed leadership's one-way boundary: a newer explicit empty manifest revokes every role; a
# still newer legacy HT1 without the extension cannot make an activated client trust census again.
python3 - "$OLYMPUS_COUNCIL_JSON" <<'PY3'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["leadership"]["epoch"] = 2
d["leadership"]["guilds"] = []
json.dump(d, open(p, "w"), indent=1)
PY3
OLYMPUS_COUNCIL_OUT="$scratch/council9.lua" python3 "$signer" council > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council9.lua" python3 "$signer" check > check.txt || fail 'check refused the empty leadership tombstone'
grep -Fq 'authority Alliance: 1 part(s), epoch 2, digest good, 1 bytes' check.txt || fail 'check does not show the separate leadership tombstone'
python3 - "$OLYMPUS_COUNCIL_JSON" <<'PY4'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.pop("leadership")
json.dump(d, open(p, "w"), indent=1)
PY4
OLYMPUS_COUNCIL_OUT="$scratch/council10.lua" python3 "$signer" council > /dev/null

# The scalable path: a realistic 92-guild federation and the exact 128-guild/512-person bounds
# both need several independently signed parts. A 129th guild is refused before the key time moves.
python3 - "$scratch/leadership-92.json" "$scratch/leadership-max.json" <<'PY5'
import json, sys
def letters(i):
    out = ""
    while i:
        i, r = divmod(i - 1, 26)
        out = chr(65 + r) + out
    return out
def council(count, epoch):
    guilds = []
    for i in range(1, count + 1):
        names = ["Player" + "Q" * 30 + letters((i - 1) * 4 + j) + "-R" for j in range(1, 5)]
        guilds.append({"guild": "Olympus " + letters(i), "leader": names[0], "officers": names[1:]})
    return {"realm": "R", "leadership": {"mode": "enforce", "epoch": epoch,
        "factions": ["Alliance"], "guilds": guilds}}
json.dump(council(92, 11), open(sys.argv[1], "w"))
json.dump(council(128, 12), open(sys.argv[2], "w"))
PY5
OLYMPUS_COUNCIL_OUT="$scratch/council11.lua" python3 "$signer" council "$scratch/leadership-92.json" > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council11.lua" python3 "$signer" check > check.txt || fail 'check refused the 92-guild authority set'
[ "$(grep -c '^authority Alliance [0-9]' check.txt)" -gt 1 ] || fail '92 realistic guilds did not exercise multiple signed parts'
OLYMPUS_COUNCIL_OUT="$scratch/council12.lua" python3 "$signer" council "$scratch/leadership-max.json" > /dev/null
OLYMPUS_COUNCIL_OUT="$scratch/council12.lua" python3 "$signer" check > check.txt || fail 'check refused the maximum authority set'
[ "$(grep -c '^authority Alliance [0-9]' check.txt)" -gt 1 ] || fail 'the maximum authority set did not exercise multiple signed parts'
before=$(last_at)
python3 - "$scratch/leadership-max.json" <<'PY6'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["leadership"]["guilds"].append({"guild": "O EXTRA", "leader": "P EXTRA-R"})
json.dump(d, open(p, "w"))
PY6
if OLYMPUS_COUNCIL_OUT="$scratch/refused.lua" python3 "$signer" council "$scratch/leadership-max.json" > refused.txt 2>&1; then fail 'signed: 129 leadership guilds'; fi
[ "$(last_at)" = "$before" ] || fail 'a refused maximum leadership list moved the key time'
printf 'ok: 92-guild and maximum multipart authority signed; one past the maximum refused\n'

luajit "$repo_root/tests/sign-roundtrip.lua" "$repo_root" "$OLYMPUS_COUNCIL_KEY" "$future" \
	"$scratch/list1.lua" "$scratch/list2.lua" "$scratch/list3.lua" "$scratch/council1.lua" "$scratch/council2.lua" \
	"$scratch/council3.lua" "$scratch/council4.lua" "$scratch/council5.lua" "$scratch/council6.lua" \
	"$scratch/council7.lua" "$scratch/council8.lua" "$scratch/council9.lua" "$scratch/council10.lua" "$scratch/council11.lua" "$scratch/council12.lua"
