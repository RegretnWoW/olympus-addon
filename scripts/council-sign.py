#!/usr/bin/env python3
"""Signs the High Council's lists for the Olympus addon.

  python3 scripts/council-sign.py keygen                                  # once: ~/.olympus/council-key.json
  python3 scripts/council-sign.py sign "Name One,Name Two" [realm group]  # the names alone: dist/CouncilList.lua
  python3 scripts/council-sign.py council [council.json]                  # names, departments and titles: dist/CouncilList.lua
  python3 scripts/council-sign.py steward "<Name-Realm>" [Alliance|Horde] # mark the King's Steward, then sign as "council"
  python3 scripts/council-sign.py steward --remove "<Name-Realm>"         # end it: sign again without him
  python3 scripts/council-sign.py check [CouncilList.lua]                 # (or --check) read back what was signed

The private key never leaves ~/.olympus. The addon carries only the public key (Sign.lua) and
checks the signature: RSA-2048, e = 3, PKCS#1 v1.5 over SHA-256. CouncilList.lua holds the lists:
it is copied to the author's own game only (never in the repository or the public zip).

"sign" writes the name list alone (HS1, ns.COUNCIL_SIGNED), as before 0.9.9. "council" reads
the council from a JSON file (~/.olympus/council.json unless a path is given):

  {"realm": "optional realm group", "public": false,
   "departments": [{"name": "Department of War", "icon": "INV_Sword_04",
                    "members": [{"name": "First Surname", "title": "Operations Director"}]}],
   "members": [{"name": "First Surname", "title": "optional"}]}

and writes two lists: the names (HS1, every name of the departments and of "members", which
0.9.8 clients read too) and the departments and titles (HT1, ns.COUNCIL_TITLES, 0.9.9):
  HT1~<time>~<realm group>~<public 0|1>~<departments>~<signature>
  <departments>: <name>^<icon>^<First Surname>=<title>,...;...   ("members": the entry with no name)
"members" are the councillors outside any department; a title and a department's icon (a game
icon's name under Interface\\Icons, or its file number) may be left out. "public": whether
everyone sees the council in the census (until then, the councillors and the author alone).

The King's Steward (1.0.0): an optional "stewards" list in the same file names the characters
who name Hands of their own beside the King's, set up for the King what only he could set up
(the treasury's keepers and what the army sees of it) and send the Crown's decrees on every
client:

  "stewards": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde"}]

A plain name is the Alliance King's Steward; the Horde gets one only when the list names one
for it. The titles list carries them in an entry of its own after the departments, one per
faction ("^steward^<faction>^<First Surname-Realm>,..."): three "^" where a department has two,
so 0.9.9 clients leave it out unread and still take, show and pass on the whole list. At most 3
per faction; a name of letters with one space at most, its realm (that realm's group) or none
(any realm of the list's group). "steward" adds one to the council file (rewritten whole, the
rest kept) and signs the council at once; "steward --remove" takes him off and signs again: the
newer list ends it on every client. "check" (or --check) reads a written CouncilList.lua back,
checks both signatures with the key and prints the names, departments and Stewards it holds.

Every list gets a newer time than the last one signed with the key (kept in the key file as
"last_at"): clients keep a list only if it is newer than theirs, so two lists signed in the
same second both reach them. Anything the addon would not take is refused here, before anything
is signed: a "~" or "|" or a control character anywhere; a "," in a name; a "^", ";", "=" or
"," in a name, title or department of the titles list; a name or title of more than 48 bytes, a
department of more than 40; more than 30 names, or a name twice; more than 8 departments; an icon
that is not a game icon's name or number; a list longer than the addon takes.
OLYMPUS_COUNCIL_KEY, OLYMPUS_COUNCIL_OUT and OLYMPUS_COUNCIL_JSON give other paths for the key,
the lists and the council (the tests use a throwaway key in a temporary folder).
"""
import hashlib, json, os, re, secrets, sys, time

KEY = os.environ.get("OLYMPUS_COUNCIL_KEY") or os.path.expanduser("~/.olympus/council-key.json")
OUT = os.environ.get("OLYMPUS_COUNCIL_OUT") or os.path.join("dist", "CouncilList.lua")
COUNCIL = os.environ.get("OLYMPUS_COUNCIL_JSON") or os.path.expanduser("~/.olympus/council.json")
REALM = "ClassicBetaPvP+ClassicBetaPvP2"
PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")
BASE, BITS = 1 << 24, 2048
MAX_NAMES, MAX_NAME, MAX_BLOB = 30, 48, 2000 # what the addon takes (Workshop.TakeCouncil)
MAX_TITLE, MAX_DEPT, MAX_DEPTS, MAX_TITLES_BLOB = 48, 40, 8, 3000 # and of the titles (Workshop.TakeTitles)
MAX_STEWARDS, MAX_REALM, FACTIONS = 3, 40, ("Alliance", "Horde") # the King's Steward (Core.lua: ns.ReadStewards)
SIG_LEN = 512 # hex digits of a signature, always (Sign.Verify)

def is_prime(n, rounds=40):
    if n < 2: return False
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0: return n == p
    d, r = n - 1, 0
    while d % 2 == 0: d //= 2; r += 1
    for _ in range(rounds):
        a = secrets.randbelow(n - 3) + 2
        x = pow(a, d, n)
        if x in (1, n - 1): continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1: break
        else: return False
    return True

def prime(bits):
    while True:
        p = secrets.randbits(bits) | (1 << (bits - 1)) | 1
        if p % 3 == 2 and is_prime(p): return p

def limbs(n):
    k = 0
    while BASE ** k <= n: k += 1
    return k

def keygen():
    if os.path.exists(KEY): sys.exit("key exists: " + KEY)
    os.makedirs(os.path.dirname(os.path.abspath(KEY)), mode=0o700, exist_ok=True)
    while True:
        p, q = prime(BITS // 2), prime(BITS // 2)
        n = p * q
        if p != q and n.bit_length() == BITS: break
    lam = (p - 1) * (q - 1)
    d = pow(3, -1, lam)
    k = limbs(n)
    mu = BASE ** (2 * k) // n
    with open(os.open(KEY, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as f:
        json.dump({"n": hex(n), "d": hex(d), "mu": hex(mu), "k": k}, f)
    print("N =", format(n, "x")); print("MU =", format(mu, "x")); print("K =", k)

# The key file, rewritten whole or not at all (it holds the private key), readable by its owner only.
def save_key(key):
    tmp = KEY + ".tmp"
    if os.path.exists(tmp): os.unlink(tmp)
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as f:
        json.dump(key, f)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, KEY)

# What the addon keeps of a name or a realm group: anything else would be dropped, cut or
# stripped on the way ("|" and control characters never cross the channel), and the list
# would no longer match its signature, or name someone else.
def plain(s, extra=""):
    return not any(c in "~|" + extra or ord(c) < 32 or ord(c) == 127 for c in s)

def check(names, realm):
    if len(names) > MAX_NAMES: sys.exit("%d names: the addon takes %d" % (len(names), MAX_NAMES))
    seen = set()
    for x in names:
        if not plain(x, ",") or len(x.encode()) > MAX_NAME: sys.exit("not a name the addon takes: %r" % x)
        if x.lower() in seen: sys.exit("named twice: %r" % x)
        seen.add(x.lower())
    if not plain(realm): sys.exit("not a realm group the addon takes: %r" % realm)

# Newer than the last list this key signed, whatever the clock says.
def next_at(key, at=None):
    return max(int(time.time() if at is None else at), int(key.get("last_at", 0)) + 1)

# A signed list must fit what the addon takes, its signature included (always SIG_LEN digits).
def fits(text, limit, what):
    if len(text.encode()) + 1 + SIG_LEN > limit: sys.exit("%s is too long for the addon (%d bytes at most)" % (what, limit))

def signature(text, key):
    n, d = int(key["n"], 16), int(key["d"], 16)
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    return format(pow(int.from_bytes(em, "big"), d, n), "0%dx" % SIG_LEN)

def sign(names, realm=REALM, at=None):
    with open(KEY) as f: key = json.load(f)
    names = [x.strip() for x in names.split(",") if x.strip()]
    check(names, realm)
    at = next_at(key, at)
    text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    fits(text, MAX_BLOB, "the list")
    sig = signature(text, key)
    key["last_at"] = at
    save_key(key)
    return text, sig

# The council file (see the top): every field checked as the addon reads it, before anything is
# signed. Returns the realm group, public, the councillors outside any department and the
# departments, as ([(name, title)], [(department, icon, [(name, title)])]).
def text_field(v, what, limit, required):
    if v is None: v = ""
    if not isinstance(v, str): sys.exit("%s is not text: %r" % (what, v))
    v = v.strip()
    if required and not v: sys.exit("%s is empty" % what)
    # Separators of the titles list: "^" between a department's parts, ";" between departments,
    # "=" and "," inside a department's list of names.
    if not plain(v, "^;=,") or len(v.encode()) > limit: sys.exit("not a %s the addon takes: %r" % (what, v))
    return v

# A game icon as ns.CouncilIconValue takes it: a file number (1 to 2^31 - 1), or a plain name.
def icon_field(v, what):
    if v is None or v == "": return ""
    if isinstance(v, int) and not isinstance(v, bool): v = str(v)
    if isinstance(v, str) and re.fullmatch(r"[0-9]+", v):
        if len(v) <= 10 and 1 <= int(v) < 2 ** 31: return str(int(v))
    elif isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9_]{1,64}", v): return v
    sys.exit("not an icon the addon takes (a game icon's name or file number): %s %r" % (what, v))

def fields(obj, what, allowed):
    if not isinstance(obj, dict): sys.exit("%s is not an object: %r" % (what, obj))
    extra = sorted(set(obj) - set(allowed))
    if extra: sys.exit("%s: unknown field %r (a typo?)" % (what, extra[0]))
    return obj

def people(v, what):
    if v is None: return []
    if not isinstance(v, list): sys.exit("%s is not a list" % what)
    out = []
    for m in v:
        fields(m, what, ("name", "title"))
        out.append((text_field(m.get("name"), "name", MAX_NAME, True), text_field(m.get("title"), "title", MAX_TITLE, False)))
    return out

# A Steward's name as the addon takes it (Core.lua, StewardName): "First Surname-Realm" or
# "First Surname"; the name letters with one space at most (48 bytes), the realm letters and
# digits (40 bytes). Returned trimmed.
def steward_name(v):
    if not isinstance(v, str): sys.exit("a Steward is a name, not %r" % (v,))
    v = v.strip()
    short, dash, realm = v.partition("-")
    words = short.split(" ")
    good = plain(v, "^;=,") and 1 <= len(words) <= 2 and all(w and all(c.isalpha() for c in w) for w in words)
    good = good and len(short.encode()) <= MAX_NAME
    if dash: good = good and realm != "" and all(c.isalnum() for c in realm) and len(realm.encode()) <= MAX_REALM
    if not good: sys.exit("not a Steward's name the addon takes (First Surname-Realm): %r" % v)
    return v

# The council file's "stewards": each a name (the Alliance King's) or {"name", "faction"}.
# Returns {faction: [names]}, each faction MAX_STEWARDS at most, nobody twice, each realm one of
# the list's realm group (a Steward elsewhere would be nobody's on every client).
def read_stewards(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("stewards is not a list")
    out, seen = {}, set()
    for s in v:
        if isinstance(s, dict):
            fields(s, "a steward", ("name", "faction"))
            name, faction = s.get("name"), s.get("faction", "Alliance")
        else:
            name, faction = s, "Alliance"
        name = steward_name(name)
        if faction not in FACTIONS: sys.exit("a Steward's faction is Alliance or Horde, not %r" % (faction,))
        home = name.partition("-")[2]
        if home and realm and home not in realm.split("+"):
            sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
        if name.lower() in seen: sys.exit("a Steward twice: %r" % name)
        seen.add(name.lower())
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_STEWARDS: sys.exit("more than %d Stewards for the %s" % (MAX_STEWARDS, faction))
    return out

def read_council(data):
    fields(data, "the council", ("realm", "public", "departments", "members", "stewards"))
    realm = data.get("realm", REALM)
    if not isinstance(realm, str): sys.exit("not a realm group the addon takes: %r" % (realm,))
    public = data.get("public", False)
    if not isinstance(public, bool): sys.exit("public is true or false, not %r" % (public,))
    loose = people(data.get("members"), "members")
    listed = data.get("departments") or []
    if not isinstance(listed, list): sys.exit("departments is not a list")
    if len(listed) > MAX_DEPTS: sys.exit("%d departments: the addon takes %d" % (len(listed), MAX_DEPTS))
    depts, seen = [], set()
    for d in listed:
        fields(d, "a department", ("name", "icon", "members"))
        name = text_field(d.get("name"), "department", MAX_DEPT, True)
        if name.lower() in seen: sys.exit("a department twice: %r" % name)
        seen.add(name.lower())
        depts.append((name, icon_field(d.get("icon"), name), people(d.get("members"), name)))
    return realm, public, loose, depts, read_stewards(data.get("stewards"), realm)

def load_council(path):
    try:
        with open(path, encoding="utf-8") as f: data = json.load(f)
    except (OSError, ValueError) as e: sys.exit("cannot read the council file %s: %s" % (path, e))
    return data

# Both lists from the council file: the names (HS1) and, one second newer, the titles (HT1).
def sign_council(path):
    return sign_council_data(load_council(path))

def sign_council_data(data):
    realm, public, loose, depts, stewards = read_council(data)
    names = [m[0] for m in loose] + [m[0] for d in depts for m in d[2]]
    check(names, realm)
    with open(KEY) as f: key = json.load(f)
    at = next_at(key)
    names_text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    entries = ["^^" + ",".join("%s=%s" % m for m in loose)] if loose else []
    entries += ["%s^%s^%s" % (name, icon, ",".join("%s=%s" % m for m in members)) for name, icon, members in depts]
    # The King's Stewards after the departments: an entry per faction with three "^".
    entries += ["^steward^%s^%s" % (faction, ",".join(stewards[faction])) for faction in FACTIONS if stewards.get(faction)]
    titles_text = "HT1~%d~%s~%d~%s" % (at + 1, realm, 1 if public else 0, ";".join(entries))
    fits(names_text, MAX_BLOB, "the name list")
    fits(titles_text, MAX_TITLES_BLOB, "the titles list")
    signed = names_text + "~" + signature(names_text, key), titles_text + "~" + signature(titles_text, key)
    key["last_at"] = at + 1
    save_key(key)
    return signed

# A Lua string literal of s, byte for byte: Lua 5.1 has no \u escapes (an accented name
# written as JSON's "\u00e0" would reach the game as "u00e0", and its signature fail).
def lua_string(s):
    return '"' + "".join(chr(b) if 32 <= b < 127 and chr(b) not in '"\\' else "\\%03d" % b for b in s.encode()) + '"'

def write_out(names, titles=None):
    if os.path.dirname(OUT): os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("-- Local only: the High Council's lists, signed. Never commit or publish this file.\n")
        f.write("local _, ns = ...\nns.COUNCIL_SIGNED = %s\n" % lua_string(names))
        if titles: f.write("ns.COUNCIL_TITLES = %s\n" % lua_string(titles))

# The council file rewritten whole or not at all, readable by its owner as before.
def save_council(path, data):
    tmp = path + ".tmp"
    if os.path.exists(tmp): os.unlink(tmp)
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o600
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)

# steward <Name-Realm> [faction] | steward --remove <Name-Realm>: the council file's "stewards"
# changed, the council signed from it at once (nothing written if anything is refused).
def steward(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = steward_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("a Steward's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("stewards") or []
    if not isinstance(listed, list): sys.exit("stewards is not a list")
    def who(s): return (s.get("name") if isinstance(s, dict) else s) or ""
    kept = [s for s in listed if not (isinstance(who(s), str) and who(s).strip().lower() == name.lower())]
    if remove and len(kept) == len(listed): sys.exit("not a Steward in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already a Steward: %r" % name)
        kept.append(name if faction == "Alliance" else {"name": name, "faction": faction})
    data["stewards"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# A Lua string literal as lua_string writes it (plain bytes and \ddd), back to its text.
def lua_unstring(s):
    out, i = bytearray(), 0
    while i < len(s):
        if s[i] == "\\":
            out.append(int(s[i + 1:i + 4])); i += 4
        else:
            out += s[i].encode(); i += 1
    return out.decode()

def verified(text, sig, n):
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    return len(sig) == SIG_LEN and pow(int(sig, 16), 3, n) == int.from_bytes(em, "big")

# check [CouncilList.lua]: what a written file holds, each list's signature checked with the key.
def check_out(path=OUT):
    try:
        with open(path, encoding="utf-8") as f: lua = f.read()
    except OSError as e: sys.exit("cannot read %s: %s" % (path, e))
    with open(KEY) as f: n = int(json.load(f)["n"], 16)
    lists = {k: lua_unstring(v) for k, v in re.findall(r'^ns\.(COUNCIL_SIGNED|COUNCIL_TITLES) = "((?:[^"\\]|\\[0-9]{3})*)"$', lua, re.M)}
    if "COUNCIL_SIGNED" not in lists: sys.exit("%s holds no name list" % path)
    bad = False
    for kind in ("COUNCIL_SIGNED", "COUNCIL_TITLES"):
        blob = lists.get(kind)
        if blob is None: continue
        text, _, sig = blob.rpartition("~")
        good = verified(text, sig, n)
        bad = bad or not good
        parts = text.split("~")
        print("%s: %s, time %s, realm group %s" % ("names" if kind == "COUNCIL_SIGNED" else "titles",
            "signature good" if good else "SIGNATURE BAD", parts[1], parts[2] or "(any)"))
        if kind == "COUNCIL_SIGNED":
            print("  names:", parts[3] or "-")
            continue
        print("  public:", parts[3] == "1")
        stewards = {}
        for entry in parts[4].split(";"):
            if entry.startswith("^steward^"):
                _, _, faction, names = entry.split("^", 3)
                stewards[faction] = names
            elif entry:
                part = entry.split("^")
                print("  %s: %s" % (part[0] or "(outside any department)", part[-1] or "-"))
        for faction in FACTIONS:
            print("  the %s King's Steward: %s" % (faction, stewards.get(faction) or "none"))
    if bad: sys.exit("a signature does not hold with %s" % KEY)

if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "keygen": keygen()
    elif len(sys.argv) >= 3 and sys.argv[1] == "sign":
        text, sig = sign(sys.argv[2], *sys.argv[3:4])
        write_out(text + "~" + sig)
        print(OUT, "written:", text)
    elif len(sys.argv) in (2, 3) and sys.argv[1] == "council":
        names, titles = sign_council(sys.argv[2] if len(sys.argv) == 3 else COUNCIL)
        write_out(names, titles)
        print(OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) >= 3 and sys.argv[1] == "steward":
        names, titles = steward(sys.argv[2:])
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) in (2, 3) and sys.argv[1] in ("check", "--check"):
        check_out(sys.argv[2] if len(sys.argv) == 3 else OUT)
    else: sys.exit(__doc__)
