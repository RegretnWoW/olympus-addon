#!/usr/bin/env python3
"""Writes web/test/fixtures/vectors.json: the Olympus Link test vectors shared by the page,
the Worker, the tools and the addon (Olympus/Ed25519.lua and Olympus/Link.lua).

  python3 web/test/fixtures/make-vectors.py        # rewrites vectors.json (needs "cryptography")

Every key here is a THROWAWAY test key: its seed is SHA-256 of a public label, the same labels
and the same rule as the addon's tests/fixtures/make-link-vectors.py ("olympus-link-test:" +
label, the label being the key id, "backend", "ca" or "council03"), so both sides hold the same
keys. Never register one of these public keys in D1, LINK_CA_PUBLIC, ns.LINK_BACKEND_KEYS or
ns.LINK_CA_KEYS.

What is in the file:
  rfc8032    RFC 8032 section 7.1 TEST 1, 2, 3 and 1024 (checked here with cryptography)
  sha512     NIST FIPS 180 examples (and the empty message)
  ed25519    cross-language vectors: fixed seed, public key, message, signature (Ed25519 is
             deterministic, so every correct implementation gives these exact bytes)
  rejects    a non-canonical S (S + L) and altered message/signature/key: all must fail
  backend    the test backend key and two code tokens it signed (OLC2, with the draw's T)
  keys       test confirmer keys with the D1 fields the Worker tests use (the character each
             is registered for among them) and their certificates (OLK2, signed by the backend
             key, each for its character)
  council_authority, council_keys
             the test council authority key (the author's client's) and a High Councillor's
             key it certified (OLK2 of tier c, the key's id the first 12 hex of SHA-256 of it):
             a key the Worker has never seen, taken on the authority's word
  bundles    signed bundles (OLB5) with 1 to 4 proofs, each carrying its certificate, their
             tag, messages and link URLs
  draw       the 8-hex draw prefixes of SHA-256(R .. "~" .. keyId) for one R, and the
             threshold T for pools of several sizes
"""
import base64, hashlib, json, math, os, urllib.parse

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vectors.json")
SITE = "https://link.example.org/olympus"  # a placeholder ns.LINK_SITE for the URL vectors
L = 2**252 + 27742317777372353535851937790883648493  # the order of the Ed25519 base point

RFC8032 = [
    ("TEST 1",
     "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
     "",
     "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
    ("TEST 2",
     "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
     "72",
     "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
    ("TEST 3",
     "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
     "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
     "af82",
     "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
    ("TEST 1024",
     "f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5",
     "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e",
     "08b8b2b733424243760fe426a4b54908632110a66c2f6591eabd3345e3e4eb98fa6e264bf09efe12ee50f8f54e9f77b1"
     "e355f6c50544e23fb1433ddf73be84d879de7c0046dc4996d9e773f4bc9efe5738829adb26c81b37c93a1b270b20329d"
     "658675fc6ea534e0810a4432826bf58c941efb65d57a338bbd2e26640f89ffbc1a858efcb8550ee3a5e1998bd177e93a"
     "7363c344fe6b199ee5d02e82d522c4feba15452f80288a821a579116ec6dad2b3b310da903401aa62100ab5d1a36553e"
     "06203b33890cc9b832f79ef80560ccb9a39ce767967ed628c6ad573cb116dbefefd75499da96bd68a8a97b928a8bbc10"
     "3b6621fcde2beca1231d206be6cd9ec7aff6f6c94fcd7204ed3455c68c83f4a41da4af2b74ef5c53f1d8ac70bdcb7ed1"
     "85ce81bd84359d44254d95629e9855a94a7c1958d1f8ada5d0532ed8a5aa3fb2d17ba70eb6248e594e1a2297acbbb39d"
     "502f1a8c6eb6f1ce22b3de1a1f40cc24554119a831a9aad6079cad88425de6bde1a9187ebb6092cf67bf2b13fd65f270"
     "88d78b7e883c8759d2c4f5c65adb7553878ad575f9fad878e80a0c9ba63bcbcc2732e69485bbc9c90bfbd62481d9089b"
     "eccf80cfe2df16a2cf65bd92dd597b0707e0917af48bbb75fed413d238f5555a7a569d80c3414a8d0859dc65a46128ba"
     "b27af87a71314f318c782b23ebfe808b82b0ce26401d2e22f04d83d1255dc51addd3b75a2b1ae0784504df543af8969b"
     "e3ea7082ff7fc9888c144da2af58429ec96031dbcad3dad9af0dcbaaaf268cb8fcffead94f3c7ca495e056a9b47acdb7"
     "51fb73e666c6c655ade8297297d07ad1ba5e43f1bca32301651339e22904cc8c42f58c30c04aafdb038dda0847dd988d"
     "cda6f3bfd15c4b4c4525004aa06eeff8ca61783aacec57fb3d1f92b0fe2fd1a85f6724517b65e614ad6808d6f6ee34df"
     "f7310fdc82aebfd904b01e1dc54b2927094b2db68d6f903b68401adebf5a7e08d78ff4ef5d63653a65040cf9bfd4aca7"
     "984a74d37145986780fc0b16ac451649de6188a7dbdf191f64b5fc5e2ab47b57f7f7276cd419c17a3ca8e1b939ae49e4"
     "88acba6b965610b5480109c8b17b80e1b7b750dfc7598d5d5011fd2dcc5600a32ef5b52a1ecc820e308aa342721aac09"
     "43bf6686b64b2579376504ccc493d97e6aed3fb0f9cd71a43dd497f01f17c0e2cb3797aa2a2f256656168e6c496afc5f"
     "b93246f6b1116398a346f1a641f3b041e989f7914f90cc2c7fff357876e506b50d334ba77c225bc307ba537152f3f161"
     "0e4eafe595f6d9d90d11faa933a15ef1369546868a7f3a45a96768d40fd9d03412c091c6315cf4fde7cb68606937380d"
     "b2eaaa707b4c4185c32eddcdd306705e4dc1ffc872eeee475a64dfac86aba41c0618983f8741c5ef68d3a101e8a3b8ca"
     "c60c905c15fc910840b94c00a0b9d0",
     "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03"),
]

NIST_896 = ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
            "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")

CREATED = 1799913600   # the codes' issue time...
EXP = 1800000000       # ...and expiry (24 hours later), as in the addon's link-sample.txt
KEYS_CREATED = 1780000000  # the confirmer keys: 230 days before the codes
CERT_EXP = 1830000000  # their certificates' expiry
MAX_BUNDLE_BYTES = 2400  # the addon's Link.MAX_BUNDLE: four proofs with their certificates


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def seed_of(label):
    """A throwaway seed: SHA-256 of a public label (the addon's make-link-vectors.py rule)."""
    return hashlib.sha256(("olympus-link-test:" + label).encode()).digest()


def key(seed):
    return Ed25519PrivateKey.from_private_bytes(seed)


def public_bytes(k):
    return k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def public_hex(k):
    return public_bytes(k).hex()


def verifies(pub_hex, sig, msg):
    try:
        Ed25519PublicKey.from_public_bytes(bytes.fromhex(pub_hex)).verify(sig, msg)
        return True
    except InvalidSignature:
        return False


def sha256_hex(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def draw_prefix(R, key_id):
    """A player key's place in the draw of code R: the first 8 hex of SHA-256(R~keyId)."""
    return sha256_hex(R + "~" + key_id)[:8]


def draw_limit(n):
    """M = max(20, ceil(3% of the active player keys))."""
    return max(20, math.ceil(n * 3 / 100))


def draw_threshold(R, key_ids):
    """T: the prefix at index M (0-based) of the sorted prefixes, so the M lowest are drawn
    (prefix < T); "ffffffff" when there are M keys or fewer."""
    m = draw_limit(len(key_ids))
    prefixes = sorted(draw_prefix(R, k) for k in key_ids)
    return prefixes[m] if len(prefixes) > m else "ffffffff"


def ca_key_id(public):
    """The id of a key the council authority certifies: the first 12 hex of SHA-256(its 32 bytes)."""
    return hashlib.sha256(public).hexdigest()[:12]


def cert_payload(key_id, public, tier, exp, character):
    """OLK2.<keyId>.<public key, base64url>.<tier>.<exp>.<Name-Realm>: what a certificate signs (UTF-8)."""
    return "OLK2.%s.%s.%s.%d.%s" % (key_id, b64url(public), tier, exp, character)


def link_tag(token_sig, requester):
    """The tag that binds a request to the command pasted: 16 hex of SHA-256(sig~requester)."""
    return sha256_hex(token_sig + "~" + requester)[:16]


def vector(name, seed, msg):
    k = key(seed)
    sig = k.sign(msg)
    v = {"name": name, "seed_hex": seed.hex(), "seed_b64url": b64url(seed), "public_hex": public_hex(k)}
    try:
        v["message"] = msg.decode("utf-8")
    except UnicodeDecodeError:
        pass
    v.update({"message_hex": msg.hex(), "signature_hex": sig.hex(), "signature_b64url": b64url(sig)})
    assert verifies(v["public_hex"], sig, msg)
    return v


def main():
    out = {"about": "Olympus Link v6 test vectors, written by web/test/fixtures/make-vectors.py with "
                    "python3 cryptography. Throwaway test keys only: never register them."}

    rfc = []
    for name, sk, pk, msg, sig in RFC8032:
        k = key(bytes.fromhex(sk))
        assert public_hex(k) == pk, name
        assert k.sign(bytes.fromhex(msg)).hex() == sig, name
        rfc.append({"name": name, "seed_hex": sk, "public_hex": pk, "message_hex": msg, "signature_hex": sig})
    out["rfc8032"] = rfc

    out["sha512"] = [
        {"name": "empty", "message": "", "digest_hex": hashlib.sha512(b"").hexdigest()},
        {"name": "abc", "message": "abc", "digest_hex": hashlib.sha512(b"abc").hexdigest()},
        {"name": "896-bit", "message": NIST_896, "digest_hex": hashlib.sha512(NIST_896.encode()).hexdigest()},
        {"name": "one million a", "repeat": "a", "count": 1000000,
         "digest_hex": hashlib.sha512(b"a" * 1000000).hexdigest()},
    ]
    assert out["sha512"][1]["digest_hex"].startswith("ddaf35a193617aba")

    backend_seed = seed_of("backend")
    backend = key(backend_seed)

    # Confirmer keys (kind c = councillor, p = drawn player) with their D1 fields. The owners
    # are fake Discord ids from 2015 (older than 30 days); created long before the codes (older
    # than 7 days). Each is registered for one character and carries the certificate the backend
    # signed for it and that character:
    #   OLK2.<keyId>.<public key, base64url>.<tier>.<exp>.<Name-Realm>.<sig over everything before it>
    keys = []
    characters = {"council01": "Test Councillor-ClassicBetaPvP", "council02": "Other Councillor-ClassicBetaPvP",
                  "player01": "Other Player-ClassicBetaPvP", "player02": "Third Player-ClassicBetaPvP2",
                  "player03": "Fourth Player-ClassicBetaPvP", "player04": "Fifth Player-ClassicBetaPvP",
                  "player05": "Sixth Player-ClassicBetaPvP"}
    specs = [("council01", "c", 1, "100000000000000001", "test_councillor")] + [
        ("player0%d" % i, "p", 0, "10000000000000001%d" % i, "test_player_%d" % i) for i in range(1, 6)] + [
        ("council02", "c", 1, "100000000000000002", "test_councillor_2")]
    for key_id, kind, bootstrap, owner, username in specs:
        s = seed_of(key_id)
        k = key(s)
        payload = cert_payload(key_id, public_bytes(k), kind, CERT_EXP, characters[key_id])
        cert = payload + "." + b64url(backend.sign(payload.encode("utf-8")))
        assert len(cert.encode()) <= 240 and len(("/oly discord cert " + cert).encode()) < 255 and len(("DV~1~" + cert).encode()) < 255
        keys.append({"key_id": key_id, "kind": kind, "bootstrap": bootstrap, "owner_discord_id": owner,
                     "owner_username": username, "character": characters[key_id], "created": KEYS_CREATED,
                     "seed_hex": s.hex(), "seed_b64url": b64url(s), "public_hex": public_hex(k),
                     "public_b64url": b64url(public_bytes(k)), "cert_exp": CERT_EXP,
                     "cert_payload": payload, "cert": cert})
    by_id = {k["key_id"]: k for k in keys}
    player_ids = [k["key_id"] for k in keys if k["kind"] == "p"]

    # The council authority (the author's client holds its seed, the Worker its public key in
    # LINK_CA_PUBLIC) and a High Councillor's key its addon made in game, certified by it: tier c,
    # its id the first 12 hex of SHA-256 of the key, never registered in D1.
    ca_seed = seed_of("ca")
    ca = key(ca_seed)
    council_keys = []
    for label, character in [("council03", "Third Councillor-ClassicBetaPvP")]:
        s = seed_of(label)
        k = key(s)
        key_id = ca_key_id(public_bytes(k))
        payload = cert_payload(key_id, public_bytes(k), "c", CERT_EXP, character)
        cert = payload + "." + b64url(ca.sign(payload.encode("utf-8")))
        assert len(("DV~1~" + cert).encode()) < 255 and len(("DE~" + cert).encode()) < 255
        council_keys.append({"key_id": key_id, "label": label, "character": character, "seed_hex": s.hex(), "seed_b64url": b64url(s),
                             "public_hex": public_hex(k), "public_b64url": b64url(public_bytes(k)), "cert_exp": CERT_EXP,
                             "cert_payload": payload, "cert": cert})
    certified = dict(by_id, **{k["key_id"]: k for k in council_keys})

    # Code tokens: OLC2.<R>.<username>.<exp>.<mode>.<T>.<sig>, sig over the ASCII bytes before
    # it. T: "00000000" in mode c; in mode a the draw threshold over the active player keys.
    tokens = []
    for R, username, mode, discord_id in [("7K3M9QX2TB", "some.player", "c", "200000000000000001"),
                                          ("H4N8PZ6R1B", "tester.two", "a", "200000000000000002")]:
        T = "00000000" if mode == "c" else draw_threshold(R, player_ids)
        payload = "OLC2.%s.%s.%d.%s.%s" % (R, username, EXP, mode, T)
        sig = backend.sign(payload.encode("ascii"))
        tokens.append({"R": R, "username": username, "created": CREATED, "exp": EXP, "mode": mode, "T": T,
                       "payload": payload, "signature_b64url": b64url(sig), "token": payload + "." + b64url(sig),
                       "discord_id": discord_id})
    assert tokens[1]["T"] == "ffffffff"  # 5 player keys: all of them drawn
    token_of = {t["R"]: t for t in tokens}
    out["backend"] = {"seed_hex": backend_seed.hex(), "seed_b64url": b64url(backend_seed),
                      "public_hex": public_hex(backend), "tokens": tokens}
    out["keys"] = keys
    out["council_authority"] = {"seed_hex": ca_seed.hex(), "seed_b64url": b64url(ca_seed), "public_hex": public_hex(ca)}
    out["council_keys"] = council_keys

    # Bundles: OLB5~<requester>~<guild>~<faction>~<nonce>~<R>~<tag>~<p1>;<p2>... with each proof
    # <issued>,<keyId>,<confirmer>,<gv>,<sig>,<public key>,<tier>,<cert exp>,<cert sig>: its
    # certificate travels with it (OLK2.<keyId>.<public key>.<tier>.<cert exp>.<confirmer>.<cert sig>),
    # and sig is over (UTF-8)
    #   OLY4~<requester>~<guild>~<gv>~<faction>~<nonce>~<R>~<tag>~<issued>~<keyId>~<confirmer>
    # tag: the first 16 hex of SHA-256(<the code token's sig>~<requester>).
    def bundle(name, requester, guild, faction, nonce, R, proofs):
        tag = link_tag(token_of[R]["signature_b64url"], requester)
        parts, messages = [], []
        for issued, key_id, confirmer, gv in proofs:
            k = certified[key_id]
            assert confirmer == k["character"], "a certificate names its confirmer"
            msg = "~".join(["OLY4", requester, guild, gv, faction, nonce, R, tag, str(issued), key_id, confirmer])
            sig = key(bytes.fromhex(k["seed_hex"])).sign(msg.encode("utf-8"))
            assert verifies(k["public_hex"], sig, msg.encode("utf-8"))
            cert_sig = k["cert"][len(k["cert_payload"]) + 1:]
            tier = k["cert_payload"].split(".")[3]
            parts.append(",".join([str(issued), key_id, confirmer, gv, b64url(sig), k["public_b64url"], tier, str(k["cert_exp"]), cert_sig]))
            messages.append(msg)
        text = "~".join(["OLB5", requester, guild, faction, nonce, R, tag, ";".join(parts)])
        assert len(text.encode("utf-8")) <= MAX_BUNDLE_BYTES
        return {"name": name, "requester": requester, "guild": guild, "faction": faction, "nonce": nonce,
                "R": R, "tag": tag, "tag_input": token_of[R]["signature_b64url"] + "~" + requester,
                "proofs": [{"issued": i, "key_id": k, "confirmer": c, "gv": g} for i, k, c, g in proofs],
                "messages": messages, "bundle": text, "bytes": len(text.encode("utf-8")),
                "url": SITE + "#b=" + urllib.parse.quote(text, safe="")}

    out["site"] = SITE
    out["bundles"] = [
        bundle("one councillor", "Some Player-ClassicBetaPvP", "Olympus II", "Alliance", "0123456789abcdef",
               "7K3M9QX2TB", [(1799990100, "council01", "Test Councillor-ClassicBetaPvP", "w")]),
        bundle("three drawn players, non-ASCII requester", "Tëst Plâyer-ClassicBetaPvP", "Olympus Vanguard",
               "Horde", "a1b2c3d4e5f60718", "H4N8PZ6R1B",
               [(1799990200, "player01", "Other Player-ClassicBetaPvP", "r"),
                (1799990245, "player02", "Third Player-ClassicBetaPvP2", "c"),
                (1799990301, "player03", "Fourth Player-ClassicBetaPvP", "c")]),
        bundle("four drawn players, long names", "Ëlüñé Stârwhîspêr-ClassicBetaPvP2", "Olympus Vanguard",
               "Horde", "ffeeddccbbaa9988", "H4N8PZ6R1B",
               [(1799990200, "player01", "Other Player-ClassicBetaPvP", "c"),
                (1799990245, "player02", "Third Player-ClassicBetaPvP2", "c"),
                (1799990301, "player03", "Fourth Player-ClassicBetaPvP", "w"),
                (1799990330, "player04", "Fifth Player-ClassicBetaPvP", "c")]),
        bundle("two councillors, the guild claimed only", "Some Player-ClassicBetaPvP", "Olympus II", "Alliance",
               "00ff00ff00ff00ff", "7K3M9QX2TB",
               [(1799990150, "council01", "Test Councillor-ClassicBetaPvP", "c"),
                (1799990170, "council02", "Other Councillor-ClassicBetaPvP", "c")]),
        bundle("a councillor certified by the council authority", "Some Player-ClassicBetaPvP", "Olympus II", "Alliance",
               "0123456789abcdef", "7K3M9QX2TB",
               [(1799990120, council_keys[0]["key_id"], council_keys[0]["character"], "w")]),
    ]

    # Cross-language Ed25519 vectors: fixed seeds, messages from empty to several SHA-512 blocks.
    ed = [
        vector("seed 00..1f, empty message", bytes(range(32)), b""),
        vector("seed 1f..00, one byte", bytes(range(31, -1, -1)), b"\x4f"),
        vector("backend key, code token", backend_seed, tokens[0]["payload"].encode("ascii")),
        vector("councillor key, OLY4 confirmation", seed_of("council01"),
               out["bundles"][0]["messages"][0].encode("utf-8")),
        vector("player key, OLY4 with non-ASCII requester", seed_of("player01"),
               out["bundles"][1]["messages"][0].encode("utf-8")),
        vector("seed ff..ff, 777 bytes", b"\xff" * 32, bytes((i * 7 + 3) % 256 for i in range(777))),
        vector("backend key, key certificate", backend_seed, by_id["council01"]["cert_payload"].encode("utf-8")),
        vector("council authority key, councillor certificate", ca_seed, council_keys[0]["cert_payload"].encode("utf-8")),
    ]
    out["ed25519"] = ed

    # Must fail: S + L (non-canonical S), and one bit changed in the message, signature or key.
    base = ed[0]
    sig = bytes.fromhex(base["signature_hex"])
    s = int.from_bytes(sig[32:], "little")
    assert s < L and s + L < 2**256
    noncanon = sig[:32] + (s + L).to_bytes(32, "little")
    msg = bytes.fromhex(ed[3]["message_hex"])
    good = bytes.fromhex(ed[3]["signature_hex"])
    rejects = [
        {"name": "non-canonical S (S + L)", "public_hex": base["public_hex"], "message_hex": "",
         "signature_hex": noncanon.hex()},
        {"name": "message altered", "public_hex": ed[3]["public_hex"],
         "message_hex": (msg[:-1] + bytes([msg[-1] ^ 1])).hex(), "signature_hex": good.hex()},
        {"name": "signature R altered", "public_hex": ed[3]["public_hex"], "message_hex": msg.hex(),
         "signature_hex": (bytes([good[0] ^ 0x10]) + good[1:]).hex()},
        {"name": "signature S altered", "public_hex": ed[3]["public_hex"], "message_hex": msg.hex(),
         "signature_hex": (good[:40] + bytes([good[40] ^ 1]) + good[41:]).hex()},
        {"name": "other key", "public_hex": ed[4]["public_hex"], "message_hex": msg.hex(),
         "signature_hex": good.hex()},
    ]
    for r in rejects:
        assert not verifies(r["public_hex"], bytes.fromhex(r["signature_hex"]), bytes.fromhex(r["message_hex"])), r["name"]
    out["rejects"] = rejects

    # The draw: each player key's prefix for one R, the order (lowest prefix first, then the id),
    # and T for pools "pool0000".. of several sizes with how many keys it draws.
    R = "H4N8PZ6R1B"
    ids = player_ids + ["abcdef", "zz9999zz", "player000042"]
    prefixes = {i: draw_prefix(R, i) for i in ids}
    thresholds = []
    for n in (5, 20, 21, 400, 700, 1000):
        pool = ["pool%04d" % i for i in range(n)]
        T = draw_threshold(R, pool)
        thresholds.append({"n": n, "M": draw_limit(n), "T": T, "drawn": sum(1 for k in pool if draw_prefix(R, k) < T)})
    assert all(t["drawn"] == min(t["n"], t["M"]) for t in thresholds)
    out["draw"] = {"R": R, "key_ids": ids, "sha256_hex": {i: sha256_hex(R + "~" + i) for i in ids},
                   "prefix": prefixes, "order": sorted(ids, key=lambda i: (prefixes[i], i)),
                   "pool": "pool%04d", "thresholds": thresholds}

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(OUT)


if __name__ == "__main__":
    main()
