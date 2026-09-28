#!/usr/bin/env python3
"""Olympus Link keys (Ed25519), made on your own computer. Needs python3 "cryptography".

  python3 scripts/link-keys.py backend                        # the Worker's signing key
  python3 scripts/link-keys.py confirmer <id> <c|p> [--owner <discord id>] [--username <name>] [--bootstrap] [--days <n>]
  python3 scripts/link-keys.py cert <id> <public key> <c|p> <days> [--created <unix time> --owner <discord id>]
  python3 scripts/link-keys.py public < seed.txt              # the public key of a seed (to compare)
  python3 scripts/link-keys.py revoke <id>                    # the SQL that revokes a key

"backend" prints a fresh seed for the Worker secret LINK_BACKEND_SEED and its public key, which
goes in the Worker var LINK_BACKEND_PUBLIC and in the addon (ns.LINK_BACKEND_KEYS, Link.lua).
"confirmer" prints a confirmer's seed (they type "/oly discord key <id> <seed>" in game), its
public key, and how to register it: with the Worker's POST /api/link/keys (it answers the
certificate), or the SQL for D1 (web/worker/schema.sql). <id>: 6 to 16 of a-z and 0-9, never
reused; c: a High Councillor, p: a drawn player. --owner: the confirmer's Discord id (one active
key per Discord account); --bootstrap: a councillor key trusted before its owner has linked a
character; --days: how long its certificate lasts (365 for a councillor, 90 for a player).
"cert" signs a key's certificate with the backend key: the line the confirmer types in game
("/oly discord cert <certificate>") and the SQL that records its end in D1. <public key>: 64 hex
or 43 base64url. A player key (p) gets its certificate only once the Worker counts it for every
code still open (7 days old and its owner's Discord account 30 days old, a day and 5 minutes
before): --created (the key's "created" in D1) and --owner (its owner_discord_id) say when, and
"confirmer" prints that command with them. "confirmer" also prints a councillor key's
certificate at once when the backend seed is at hand.
The backend seed for these comes from --backend-seed-file <path> (a file holding the seed),
or the environment: LINK_BACKEND_SEED_FILE (such a path) or LINK_BACKEND_SEED (the seed). It
is never printed. web/WORKER.md, "Confirmer keys", says how to rotate and revoke.

Nothing is written to disk: every seed is printed once. Keep them out of the repository, chats,
issues and screenshots. The backend seed lives only in the Worker's secrets (and a password
manager, to recover it); a confirmer's seed only in that confirmer's game (SavedVariables),
handed over privately (a direct message, not a channel). A lost or leaked seed is replaced,
never reused: revoke the key and make a new one.
"""
import base64, json, os, re, sys, time

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except ImportError:
    sys.exit("This needs the Python package cryptography: python3 -m pip install cryptography")

KEY_ID = re.compile(r"^[a-z0-9]{6,16}$")
DISCORD_ID = re.compile(r"^[0-9]{5,25}$")
USERNAME = re.compile(r"^[a-z0-9_.]{2,32}$")
SEED = re.compile(r"^[A-Za-z0-9_-]{43}$")
PUB_HEX = re.compile(r"^[0-9a-fA-F]{64}$")
CHAT_LINE_MAX = 255  # bytes the game's chat box takes
DAYS_MAX = 3650
DAYS = {"c": 365, "p": 90}  # a certificate's life unless --days says otherwise (the Worker's CERT_DAYS)
# The Worker's LINK: a player key counts for codes issued 7 days after it, from an account 30 days
# old; a code lives a day, and the game's clock may be 5 minutes behind the Worker's.
KEY_MIN_AGE, ACCOUNT_MIN_AGE, TOKEN_LIFE, CLOCK_SKEW = 7 * 86400, 30 * 86400, 86400, 300


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def b64url_bytes(text, length):
    """The bytes of a canonical base64url string of `length` bytes, or None."""
    if not re.match(r"^[A-Za-z0-9_-]*$", text):
        return None
    raw = base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
    return raw if len(raw) == length and b64url(raw) == text else None


def seed_bytes(text, what="A seed"):
    text = text.strip()
    raw = b64url_bytes(text, 32) if SEED.match(text) else None
    if raw is None:
        sys.exit(what + " is 43 characters of base64url.")
    return raw


def fresh():
    key = Ed25519PrivateKey.generate()
    seed = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    return seed, public_hex(key)


def public_hex(key):
    return key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex()


def sql_text(s):
    return "'" + s.replace("'", "''") + "'"


def backend_key(path=None):
    """The backend's signing key from --backend-seed-file, LINK_BACKEND_SEED_FILE or
    LINK_BACKEND_SEED; None when none is given. The seed itself is never printed."""
    path = path or os.environ.get("LINK_BACKEND_SEED_FILE")
    if path:
        try:
            with open(path, "r", encoding="ascii") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError):
            sys.exit("Cannot read the backend seed file " + path + ".")
        return Ed25519PrivateKey.from_private_bytes(seed_bytes(text, "The backend seed file"))
    if os.environ.get("LINK_BACKEND_SEED"):
        return Ed25519PrivateKey.from_private_bytes(seed_bytes(os.environ["LINK_BACKEND_SEED"], "LINK_BACKEND_SEED"))
    return None


def certificate(backend, key_id, pub_hex, tier, exp):
    """OLK1.<keyId>.<public key, base64url>.<tier>.<exp>.<sig>, sig by the backend key over the
    ASCII bytes of everything before it."""
    payload = "OLK1.%s.%s.%s.%d" % (key_id, b64url(bytes.fromhex(pub_hex)), tier, exp)
    cert = payload + "." + b64url(backend.sign(payload.encode("ascii")))
    for line in ("/oly discord cert " + cert, "DV~1~" + cert):
        assert len(line.encode()) < CHAT_LINE_MAX, "a certificate line longer than the chat's 255 bytes"
    return cert


def days_arg(text):
    if not re.match(r"^[0-9]{1,4}$", text or "") or not 1 <= int(text) <= DAYS_MAX:
        sys.exit("The days are a whole number from 1 to %d." % DAYS_MAX)
    return int(text)


def day(t):
    return time.strftime("%Y-%m-%d", time.gmtime(t))


def minute(t):
    """A time for people, rounded up to the minute (the Worker's words)."""
    return time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(-(-t // 60) * 60))


def cert_from(kind, created, owner):
    """When a key may get its first certificate: the Worker's certFrom. The addon asks every player
    key with a certificate that a code's T draws, so a player key is certified only once it counts
    for every code still open: 7 days old, its owner's account 30 days old (from the Discord id),
    at the issue of a code signed a day and the clocks' 5 minutes earlier."""
    if kind != "p":
        return created
    account = -(-((int(owner) >> 22) + 1420070400000) // 1000) + ACCOUNT_MIN_AGE
    return max(created + KEY_MIN_AGE, account) + TOKEN_LIFE + CLOCK_SKEW


def backend():
    seed, pub = fresh()
    print("Olympus Link backend key (made just now, shown once)")
    print()
    print("Seed, for the Worker secret LINK_BACKEND_SEED (paste it when wrangler asks):")
    print("  " + b64url(seed))
    print("  wrangler secret put LINK_BACKEND_SEED")
    print()
    print("Public key, for the Worker var LINK_BACKEND_PUBLIC and the addon's ns.LINK_BACKEND_KEYS:")
    print("  " + pub)
    print()
    print("Keep the seed in the Worker's secrets and a password manager only: never in the")
    print("repository, a chat or a screenshot. To sign certificates here (link-keys.py cert), put it")
    print("in a file only you can read and pass --backend-seed-file <that file>. Rotating: add the new")
    print("public key to the addon's list next to the old one, ship that version, then switch the")
    print("Worker to the new seed, and sign the confirmers' certificates again with it.")


def confirmer(args):
    if len(args) < 2:
        sys.exit("usage: link-keys.py confirmer <id> <c|p> [--owner <discord id>] [--username <name>] [--bootstrap] [--days <n>] [--backend-seed-file <path>]")
    key_id, kind, rest = args[0], args[1], args[2:]
    if not KEY_ID.match(key_id):
        sys.exit("The id is 6 to 16 characters of a-z and 0-9.")
    if kind not in ("c", "p"):
        sys.exit("The kind is c (a High Councillor) or p (a drawn player).")
    owner, username, bootstrap, days, seed_file = None, None, 0, DAYS[kind], None
    i = 0
    while i < len(rest):
        if rest[i] == "--owner" and i + 1 < len(rest):
            owner, i = rest[i + 1], i + 2
        elif rest[i] == "--username" and i + 1 < len(rest):
            username, i = rest[i + 1], i + 2
        elif rest[i] == "--days" and i + 1 < len(rest):
            days, i = days_arg(rest[i + 1]), i + 2
        elif rest[i] == "--backend-seed-file" and i + 1 < len(rest):
            seed_file, i = rest[i + 1], i + 2
        elif rest[i] == "--bootstrap":
            bootstrap, i = 1, i + 1
        else:
            sys.exit("Unknown option: " + rest[i])
    if owner is not None and not DISCORD_ID.match(owner):
        sys.exit("--owner is the confirmer's Discord id (digits; Discord: Copy User ID).")
    if username is not None and not USERNAME.match(username):
        sys.exit("--username is a Discord username: 2 to 32 of a-z, 0-9, _ and .")
    if bootstrap and kind != "c":
        sys.exit("Only a councillor key (c) can be a bootstrap key.")
    signer = backend_key(seed_file)
    seed, pub = fresh()
    created = int(time.time())
    exp = created + days * 86400
    # A player key counts 8 days from now at the soonest: its certificate comes then.
    cert = certificate(signer, key_id, pub, kind, exp) if signer and kind == "c" else None
    owner_sql = sql_text(owner) if owner else "'REPLACE_WITH_DISCORD_ID'"
    print("Olympus Link confirmer key %s (%s, made just now, shown once)" % (key_id, "councillor" if kind == "c" else "player"))
    print()
    print("For the confirmer only, privately: the line%s to type in the game (kept in their SavedVariables):" % ("s" if cert else ""))
    print("  /oly discord key %s %s" % (key_id, b64url(seed)))
    if cert:
        print("  /oly discord cert %s" % cert)
    elif kind == "c":
        print("  and the \"/oly discord cert ...\" line the Worker answers when you register the key (below).")
    else:
        print("  and, once the key counts (below), its \"/oly discord cert ...\" line: send both together then.")
    print()
    print("Public key (\"/oly discord key\" in game shows the same one):")
    print("  " + pub)
    print()
    body = {"key_id": key_id, "public_key": pub, "owner_discord_id": owner or "REPLACE_WITH_DISCORD_ID", "kind": kind}
    if kind == "c":
        body["days"] = days
    if username:
        body["owner_username"] = username
    if bootstrap:
        body["bootstrap"] = True
    if kind == "c":
        print("Register it with the Worker (its answer's \"command\" is the certificate line; add \"replace\": true to rotate):")
    else:
        print("Register it with the Worker (add \"replace\": true to rotate); its answer's \"cert_from\" says when to ask for")
        print("the certificate, with {\"key_id\": \"%s\", \"renew\": true, \"days\": %d}, whose \"command\" is the line:" % (key_id, days))
    print("curl -X POST https://<your site>/api/link/keys -H \"Authorization: Bearer $LINK_ADMIN_TOKEN\" -H \"Content-Type: application/json\" -d '%s'"
          % json.dumps(body, separators=(",", ":")))
    print()
    print("Or in D1 (wrangler d1 execute <database> --remote --command \"...\")%s:" % ("" if cert else ", then its certificate with link-keys.py cert"))
    print("INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, kind, bootstrap, created, cert_exp) VALUES "
          "(%s, %s, %s, %s, %s, %d, %d, %s);" % (
              sql_text(key_id), sql_text(pub), owner_sql, sql_text(username) if username else "NULL", sql_text(kind), bootstrap,
              created, str(exp) if cert else "NULL"))
    print()
    if kind == "c":
        print("Rotating (a new key for the same person): run this first, in the same batch. The old key leaves")
        print("the draw and still checks what it signed; revoke it (link-keys.py revoke <old id>) once the")
        print("confirmer typed the new lines in game. A leaked key: revoke it at once instead.")
        print("UPDATE keys SET replaced_at = unixepoch() WHERE owner_discord_id = %s AND revoked = 0 AND replaced_at IS NULL;" % owner_sql)
    else:
        start = cert_from(kind, created, owner) if owner else None
        print("A player key gets its certificate once the Worker counts it for every code still open, %s:" % (
            "from " + minute(start) if start else "8 days from now (later for a Discord account under 30 days)"))
        print("python3 scripts/link-keys.py cert %s %s p %d --created %d --owner %s --backend-seed-file <file>" % (
            key_id, pub, days, created, owner or "REPLACE_WITH_DISCORD_ID"))
        print("Until then it is not in the draw. Rotating (a new key for the same person): nothing to run now; the")
        print("old key keeps counting until this one's certificate, whose SQL replaces it.")
    if not owner:
        print()
        print("Replace REPLACE_WITH_DISCORD_ID with the confirmer's Discord id (the table refuses anything else).")


def cert(args):
    usage = "usage: link-keys.py cert <id> <public key> <c|p> <days> [--created <unix time> --owner <discord id>] [--backend-seed-file <path>]"
    seed_file, created, owner, pos, i = None, None, None, [], 0
    while i < len(args):
        if args[i] in ("--backend-seed-file", "--created", "--owner") and i + 1 < len(args):
            if args[i] == "--backend-seed-file":
                seed_file = args[i + 1]
            elif args[i] == "--created":
                if not re.match(r"^[1-9][0-9]{0,11}$", args[i + 1]):
                    sys.exit("--created is the key's creation time in D1, in unix seconds.")
                created = int(args[i + 1])
            else:
                owner = args[i + 1]
            i += 2
        elif args[i].startswith("--"):
            sys.exit(usage)
        else:
            pos.append(args[i])
            i += 1
    if len(pos) != 4:
        sys.exit(usage)
    key_id, pub_text, tier, days = pos[0], pos[1].strip(), pos[2], days_arg(pos[3])
    if not KEY_ID.match(key_id):
        sys.exit("The id is 6 to 16 characters of a-z and 0-9.")
    if tier not in ("c", "p"):
        sys.exit("The tier is c (a High Councillor) or p (a drawn player).")
    if PUB_HEX.match(pub_text):
        pub = pub_text.lower()
    else:
        raw = b64url_bytes(pub_text, 32) if len(pub_text) == 43 else None
        if raw is None:
            sys.exit("The public key is 64 hex digits or 43 characters of base64url.")
        pub = raw.hex()
    t = int(time.time())
    if tier == "p":
        if created is None or owner is None or not DISCORD_ID.match(owner):
            sys.exit("A player key's certificate needs --created <its created in D1> and --owner <its owner_discord_id>:\n"
                     "SELECT created, owner_discord_id FROM keys WHERE key_id = " + sql_text(key_id) + ";")
        start = cert_from(tier, created, owner)
        if t < start:
            sys.exit("This player key counts from %s (unix %d): sign its certificate then. Before, the addon would\n"
                     "ask it for codes the Worker does not count it for." % (minute(start), start))
    signer = backend_key(seed_file)
    if signer is None:
        sys.exit("The backend seed is needed: --backend-seed-file <path>, or LINK_BACKEND_SEED_FILE or LINK_BACKEND_SEED.")
    exp = t + days * 86400
    c = certificate(signer, key_id, pub, tier, exp)
    print("Olympus Link certificate of key %s (%s, until %s UTC)" % (key_id, "councillor" if tier == "c" else "player", day(exp)))
    print()
    print("For the confirmer (after their \"/oly discord key\" line): type this in the game:")
    print("  /oly discord cert %s" % c)
    print()
    guard = " AND created = %d AND owner_discord_id = %s" % (created, sql_text(owner)) if tier == "p" else ""
    print("D1 (the draw counts a key while its certificate lasts). Rotating (the key's first certificate, when")
    print("it replaces the owner's older key): run the first line too, before the second, in the same batch.")
    print("UPDATE keys SET replaced_at = unixepoch() WHERE owner_discord_id = (SELECT owner_discord_id FROM keys WHERE key_id = %s) "
          "AND key_id <> %s AND revoked = 0 AND replaced_at IS NULL;" % (sql_text(key_id), sql_text(key_id)))
    print("UPDATE keys SET cert_exp = %d WHERE key_id = %s AND public_key = %s AND kind = %s AND revoked = 0 AND replaced_at IS NULL%s;" % (
        exp, sql_text(key_id), sql_text(pub), sql_text(tier), guard))
    print("It changes one row; if none, D1 holds another key, time or owner for this id: do not hand the line out.")
    print()
    print("Signed with the backend key %s (it must be the Worker's LINK_BACKEND_PUBLIC)." % public_hex(signer))


def public():
    key = Ed25519PrivateKey.from_private_bytes(seed_bytes(sys.stdin.read()))
    print(public_hex(key))


def revoke(args):
    if len(args) != 1 or not KEY_ID.match(args[0]):
        sys.exit("usage: link-keys.py revoke <id>")
    print("UPDATE keys SET revoked = 1, revoked_at = unixepoch() WHERE key_id = %s;" % sql_text(args[0]))


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__.strip().split("\n\n")[0])
    cmd, args = argv[1], argv[2:]
    if cmd == "backend" and not args:
        backend()
    elif cmd == "confirmer":
        confirmer(args)
    elif cmd == "cert":
        cert(args)
    elif cmd == "public" and not args:
        public()
    elif cmd == "revoke":
        revoke(args)
    else:
        sys.exit(__doc__.strip().split("\n\n")[0])


if __name__ == "__main__":
    main(sys.argv)
