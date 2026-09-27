#!/usr/bin/env python3
"""Signs the High Council's lists for the Olympus addon.

  python3 scripts/council-sign.py keygen                                  # once: ~/.olympus/council-key.json
  python3 scripts/council-sign.py sign "Name One,Name Two" [realm group]  # the names alone: dist/CouncilList.lua
  python3 scripts/council-sign.py council [council.json]                  # names, departments and titles: dist/CouncilList.lua

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

def read_council(data):
    fields(data, "the council", ("realm", "public", "departments", "members"))
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
    return realm, public, loose, depts

# Both lists from the council file: the names (HS1) and, one second newer, the titles (HT1).
def sign_council(path):
    try:
        with open(path, encoding="utf-8") as f: data = json.load(f)
    except (OSError, ValueError) as e: sys.exit("cannot read the council file %s: %s" % (path, e))
    realm, public, loose, depts = read_council(data)
    names = [m[0] for m in loose] + [m[0] for d in depts for m in d[2]]
    check(names, realm)
    with open(KEY) as f: key = json.load(f)
    at = next_at(key)
    names_text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    entries = ["^^" + ",".join("%s=%s" % m for m in loose)] if loose else []
    entries += ["%s^%s^%s" % (name, icon, ",".join("%s=%s" % m for m in members)) for name, icon, members in depts]
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
    else: sys.exit(__doc__)
