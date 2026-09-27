#!/usr/bin/env python3
"""Olympus Link keys (Ed25519), made on your own computer. Needs python3 "cryptography".

  python3 scripts/link-keys.py backend                        # the Worker's signing key
  python3 scripts/link-keys.py confirmer <id> <c|p> [--owner <discord id>] [--username <name>] [--bootstrap]
  python3 scripts/link-keys.py public < seed.txt              # the public key of a seed (to compare)
  python3 scripts/link-keys.py revoke <id>                    # the SQL that revokes a key

"backend" prints a fresh seed for the Worker secret LINK_BACKEND_SEED and its public key, which
goes in the Worker var LINK_BACKEND_PUBLIC and in the addon (ns.LINK_BACKEND_KEYS, Link.lua).
"confirmer" prints a confirmer's seed (they paste "/oly discord key <id> <seed>" in game), its
public key and the SQL that registers it in D1 (web/worker/schema.sql). <id>: 6 to 16 of a-z and
0-9, never reused; c: a High Councillor, p: a drawn player. --owner: the confirmer's Discord id
(one active key per Discord account); --bootstrap: a councillor key trusted before its owner
has linked a character. web/WORKER.md, "Keys", says how to rotate and revoke.

Nothing is written to disk: every seed is printed once. Keep them out of the repository, chats,
issues and screenshots. The backend seed lives only in the Worker's secrets (and a password
manager, to recover it); a confirmer's seed only in that confirmer's game (SavedVariables),
handed over privately (a direct message, not a channel). A lost or leaked seed is replaced,
never reused: revoke the key and make a new one.
"""
import base64, re, sys

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except ImportError:
    sys.exit("This needs the Python package cryptography: python3 -m pip install cryptography")

KEY_ID = re.compile(r"^[a-z0-9]{6,16}$")
DISCORD_ID = re.compile(r"^[0-9]{5,25}$")
USERNAME = re.compile(r"^[a-z0-9_.]{2,32}$")
SEED = re.compile(r"^[A-Za-z0-9_-]{43}$")


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def seed_bytes(text):
    text = text.strip()
    if not SEED.match(text):
        sys.exit("A seed is 43 characters of base64url.")
    raw = base64.urlsafe_b64decode(text + "=")
    if b64url(raw) != text:
        sys.exit("A seed is 43 characters of base64url.")
    return raw


def fresh():
    key = Ed25519PrivateKey.generate()
    seed = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    return seed, public_hex(key)


def public_hex(key):
    return key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex()


def sql_text(s):
    return "'" + s.replace("'", "''") + "'"


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
    print("repository, a chat or a screenshot. Rotating: add the new public key to the addon's")
    print("list next to the old one, ship that version, then switch the Worker to the new seed.")


def confirmer(args):
    if len(args) < 2:
        sys.exit("usage: link-keys.py confirmer <id> <c|p> [--owner <discord id>] [--username <name>] [--bootstrap]")
    key_id, kind, rest = args[0], args[1], args[2:]
    if not KEY_ID.match(key_id):
        sys.exit("The id is 6 to 16 characters of a-z and 0-9.")
    if kind not in ("c", "p"):
        sys.exit("The kind is c (a High Councillor) or p (a drawn player).")
    owner, username, bootstrap = None, None, 0
    i = 0
    while i < len(rest):
        if rest[i] == "--owner" and i + 1 < len(rest):
            owner, i = rest[i + 1], i + 2
        elif rest[i] == "--username" and i + 1 < len(rest):
            username, i = rest[i + 1], i + 2
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
    seed, pub = fresh()
    owner_sql = sql_text(owner) if owner else "'REPLACE_WITH_DISCORD_ID'"
    print("Olympus Link confirmer key %s (%s, made just now, shown once)" % (key_id, "councillor" if kind == "c" else "player"))
    print()
    print("For the confirmer only, privately: type this in the game (it stays in their SavedVariables):")
    print("  /oly discord key %s %s" % (key_id, b64url(seed)))
    print()
    print("Public key (\"/oly discord key\" in game shows the same one):")
    print("  " + pub)
    print()
    print("D1 (wrangler d1 execute <database> --remote --command \"...\"):")
    print("INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, kind, bootstrap, created) VALUES "
          "(%s, %s, %s, %s, %s, %d, unixepoch());" % (
              sql_text(key_id), sql_text(pub), owner_sql, sql_text(username) if username else "NULL", sql_text(kind), bootstrap))
    print()
    print("Rotating (a new key for the same person): run this first, in the same batch:")
    print("UPDATE keys SET revoked = 1, revoked_at = unixepoch() WHERE owner_discord_id = %s AND revoked = 0;" % owner_sql)
    if not owner:
        print()
        print("Replace REPLACE_WITH_DISCORD_ID with the confirmer's Discord id (the table refuses anything else).")


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
    elif cmd == "public" and not args:
        public()
    elif cmd == "revoke":
        revoke(args)
    else:
        sys.exit(__doc__.strip().split("\n\n")[0])


if __name__ == "__main__":
    main(sys.argv)
