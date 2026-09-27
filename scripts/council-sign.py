#!/usr/bin/env python3
"""Signs the High Council list for the Olympus addon.

  python3 scripts/council-sign.py keygen                                  # once: ~/.olympus/council-key.json
  python3 scripts/council-sign.py sign "Name One,Name Two" [realm group]  # writes dist/CouncilList.lua

The private key never leaves ~/.olympus. The addon carries only the public key (Sign.lua) and
checks the signature: RSA-2048, e = 3, PKCS#1 v1.5 over SHA-256. CouncilList.lua holds the names:
it is copied to the author's own game only (never in the repository or the public zip).

Every list gets a newer time than the last one signed with the key (kept in the key file as
"last_at"): clients keep a list only if it is newer than theirs, so two lists signed in the
same second both reach them. Names the addon would not take (a "~", "," or "|", a control
character, more than 48 bytes, more than 30 names) are refused here, before anything is signed.
OLYMPUS_COUNCIL_KEY and OLYMPUS_COUNCIL_OUT give other paths for the key and the list (the
tests use a throwaway key in a temporary folder).
"""
import hashlib, json, os, secrets, sys, time

KEY = os.environ.get("OLYMPUS_COUNCIL_KEY") or os.path.expanduser("~/.olympus/council-key.json")
OUT = os.environ.get("OLYMPUS_COUNCIL_OUT") or os.path.join("dist", "CouncilList.lua")
REALM = "ClassicBetaPvP+ClassicBetaPvP2"
PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")
BASE, BITS = 1 << 24, 2048
MAX_NAMES, MAX_NAME, MAX_BLOB = 30, 48, 2000 # what the addon takes (Workshop.TakeCouncil)

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

def sign(names, realm=REALM, at=None):
    with open(KEY) as f: key = json.load(f)
    n, d = int(key["n"], 16), int(key["d"], 16)
    names = [x.strip() for x in names.split(",") if x.strip()]
    check(names, realm)
    # Newer than the last list this key signed, whatever the clock says.
    at = max(int(time.time() if at is None else at), int(key.get("last_at", 0)) + 1)
    text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    s = pow(int.from_bytes(em, "big"), d, n)
    sig = format(s, "0512x")
    if len((text + "~" + sig).encode()) > MAX_BLOB: sys.exit("the list is too long for the addon (%d bytes at most)" % MAX_BLOB)
    key["last_at"] = at
    save_key(key)
    return text, sig

# A Lua string literal of s, byte for byte: Lua 5.1 has no \u escapes (an accented name
# written as JSON's "\u00e0" would reach the game as "u00e0", and its signature fail).
def lua_string(s):
    return '"' + "".join(chr(b) if 32 <= b < 127 and chr(b) not in '"\\' else "\\%03d" % b for b in s.encode()) + '"'

if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "keygen": keygen()
    elif len(sys.argv) >= 3 and sys.argv[1] == "sign":
        text, sig = sign(sys.argv[2], *sys.argv[3:4])
        if os.path.dirname(OUT): os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w") as f:
            f.write("-- Local only: the High Council list, signed. Never commit or publish this file.\n")
            f.write("local _, ns = ...\nns.COUNCIL_SIGNED = %s\n" % lua_string(text + "~" + sig))
        print(OUT, "written:", text)
    else: sys.exit(__doc__)
