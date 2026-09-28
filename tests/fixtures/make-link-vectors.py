#!/usr/bin/env python3
"""Olympus Link's shared test vectors (0.9.10), made with Python's "cryptography".

    python3 tests/fixtures/make-link-vectors.py          # rewrite the files below
    python3 tests/fixtures/make-link-vectors.py --check  # verify them, change nothing

The addon's tests (tests/run.lua) and the Olympus Link page's and Worker's (web/test) read these
same files, so both sides sign, parse and check the same bytes.

tests/fixtures/ed25519-vectors.txt: name, seed, public key, message, signature (hex; "-" for
an empty message). rfc8032-*: RFC 8032 section 7.1. python-*: Ed25519PrivateKey from the fixed
seeds below. lua-*: made by the addon's Olympus/Ed25519.lua; kept as they are, checked here.

tests/fixtures/link-sample.txt: key=value lines. The bot's codes (OLC2, with the draw threshold
T), the confirmers' certificates (OLK2, each for one character: signed by the backend key, or a
councillor's by the council authority's key), the tags that bind a link to the code's signature
and the requester, and finished links (OLB5, each proof with its guild flag gv and its
certificate), all signed with the throwaway keys below.

tests/fixtures/link-draw.txt: the draw of decision 4 for two sets of keys: each key's place
(the first 8 hex of SHA-256(R~keyId)), M, the threshold T and who is drawn (place < T): the M
lowest, as the Worker and the page draw them.

tests/fixtures/link-inbox.lua: a watcher's SavedVariables as the addon writes its inbox,
OlympusDB.discord.inbox[R][sender] = { bundle, from, t, keep }, holding the sample's links.

The lua-* lines of ed25519-vectors.txt are the addon's own (Olympus/Ed25519.lua; lua-ca-cert is
the certificate the addon's council authority makes, which tests/run.lua makes again byte for
byte): kept as they are here, and checked.

Every key here is made from a public label for these tests alone: never use one of them for
anything real.
"""
import base64
import hashlib
import math
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives import serialization

HERE = Path(__file__).resolve().parent
VECTORS = HERE / "ed25519-vectors.txt"
SAMPLE = HERE / "link-sample.txt"
DRAW = HERE / "link-draw.txt"
INBOX = HERE / "link-inbox.lua"

RFC8032 = [
    ("rfc8032-test1",
     "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
     "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
    ("rfc8032-test2",
     "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
     "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
    ("rfc8032-test3",
     "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
     "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
     "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
    ("rfc8032-test1024", "f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5",
     "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e",
     (
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
     "c60c905c15fc910840b94c00a0b9d0"),
     "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03"),
    ("rfc8032-sha-abc",
     "833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42",
     "ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf",
     "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
     "dc2a4459e7369633a52b1bf277839a00201009a3efbf3ecb69bea2186c26b58909351fc9ac90b3ecfdfbc7c66431e0303dca179c138ac17ad9bef1177331a704"),
]


def seed(label):
    """A throwaway seed: SHA-256 of a public label."""
    return hashlib.sha256(("olympus-link-test:" + label).encode()).digest()


def key(label):
    return Ed25519PrivateKey.from_private_bytes(seed(label))


def pub(k):
    return k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def unb64(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def sha256hex(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# The formats (Olympus/Link.lua, web/WORKER.md).
def token_payload(R, username, exp, mode, T):
    return "OLC2.%s.%s.%d.%s.%s" % (R, username, exp, mode, T)


def cert_payload(key_id, pub_b64, tier, exp, character):
    """OLK2.<keyId>.<public key, base64url>.<tier>.<exp>.<Name-Realm>: signed (UTF-8) by the backend
    key, or a councillor's (tier c) by the council authority's key."""
    return "OLK2.%s.%s.%s.%d.%s" % (key_id, pub_b64, tier, exp, character)


def ca_key_id(pub_bytes):
    """The id of a key the council authority certifies: the first 12 hex of SHA-256(its 32 bytes)."""
    return hashlib.sha256(pub_bytes).hexdigest()[:12]


def parse_cert(text):
    """(key_id, pub_b64, tier, exp, character, signed, sig) of an OLK2 certificate: the character is
    what lies between the expiry and the last dot (read from both ends)."""
    signed, sig = text.rsplit(".", 1)
    head = signed.split(".", 4)
    assert head[0] == "OLK2" and len(head) == 5, text
    exp, character = head[4].split(".", 1)
    return head[1], head[2], head[3], int(exp), character, signed, sig


def tag_of(token_sig, requester):
    """The first 16 hex of SHA-256(<the code's signature, base64url> ~ <requester Name-Realm>)."""
    return sha256hex(token_sig + "~" + requester)[:16]


def signed_text(head, p):
    """What a confirmer signs: OLY4~requester~guild~gv~faction~nonce~R~tag~issued~keyId~confirmer."""
    return "~".join(["OLY4", head["requester"], head["guild"], p["gv"], head["faction"], head["nonce"], head["R"],
                     head["tag"], str(p["issued"]), p["key_id"], p["confirmer"]])


def bundle_text(head, proofs):
    """OLB5: each proof <issued>,<keyId>,<confirmer>,<gv>,<sig>,<public key>,<tier>,<cert exp>,<cert sig>."""
    parts = [",".join([str(p["issued"]), p["key_id"], p["confirmer"], p["gv"], p["sig"], p["pub"], p["tier"], str(p["cert_exp"]),
                       p["cert_sig"]]) for p in proofs]
    return "~".join(["OLB5", head["requester"], head["guild"], head["faction"], head["nonce"], head["R"], head["tag"], ";".join(parts)])


def rank(R, key_id):
    """A key's place in the draw of R: the first 8 hex of SHA-256(R~keyId)."""
    return sha256hex(R + "~" + key_id)[:8]


def draw_threshold(R, key_ids, mode="a"):
    """T of decision 4: M = max(20, ceil(3% of the active "p" keys)); the place at index M of the
    sorted places (counting from 0: the (M+1)th lowest), "ffffffff" with M keys or fewer,
    "00000000" in mode c. Drawn: place < T, so the M lowest are drawn (the Worker's thresholdOf)."""
    if mode == "c":
        return "00000000", 0
    m = max(20, math.ceil(len(key_ids) * 3 / 100))
    if len(key_ids) <= m:
        return "ffffffff", m
    return sorted(rank(R, k) for k in key_ids)[m], m


NAME = "Some Player-ClassicBetaPvP"
OTHER = "Other Player-ClassicBetaPvP"
ACCENTED = "Sômé Plâyer-ClassicBetaPvP"   # a made-up name with accented letters (UTF-8)
COUNCILLORS = {"council01": "Test Councillor-ClassicBetaPvP", "council02": "Other Councillor-ClassicBetaPvP"}
PLAYERS = {"player01": "Some Player Two-ClassicBetaPvP", "player02": "Some Player Three-ClassicBetaPvP",
           "player03": "Some Player Four-ClassicBetaPvP"}
# A councillor whose key its own addon made, certified by the council authority (the author's
# client): its id is the first 12 hex of SHA-256 of its public key, made from the label "council03".
CA_COUNCILLOR = ("council03", "Third Councillor-ClassicBetaPvP")
R = "7K3M9QX2TB"
USERNAME = "some.player"
TOKEN_EXP = 1800000000
CERT_EXP = 1830000000
GUILD, FACTION, NONCE = "Olympus II", "Alliance", "0123456789abcdef"

PYTHON = [
    ("python-empty", "vector-a", b""),
    ("python-token", "vector-b", token_payload(R, USERNAME, TOKEN_EXP, "a", "ffffffff").encode()),
    ("python-oly4", "vector-c", ("OLY4~" + NAME + "~Olympus II~r~Alliance~0123456789abcdef~7K3M9QX2TB~0011223344556677~1799990100~council01~"
                                 + COUNCILLORS["council01"]).encode()),
    ("python-oly4-accented", "vector-d", ("OLY4~" + ACCENTED + "~Ólympus Ørder~w~Horde~fedcba9876543210~ABCDEFGHJK~8899aabbccddeeff~1799990200~player01~"
                                          + PLAYERS["player01"]).encode()),
    ("python-cert", "vector-f", cert_payload("council01", b64(pub(key("council01"))), "c", CERT_EXP, COUNCILLORS["council01"]).encode()),
    # The council authority's key (label "ca") signing a councillor's certificate, as the author's
    # client does it in game (the lua-ca-cert line is the addon's own, for the same key and text).
    ("python-ca-cert", "ca", cert_payload(ca_key_id(pub(key(CA_COUNCILLOR[0]))), b64(pub(key(CA_COUNCILLOR[0]))), "c", CERT_EXP,
                                          CA_COUNCILLOR[1]).encode()),
    ("python-1000", "vector-e", bytes((i * 7 + 3) % 256 for i in range(1000))),
]


def vector_lines(keep):
    out = [
        "# Ed25519 vectors shared by the addon's tests (tests/run.lua) and the Olympus Link page's (web/test).",
        "# name seed public-key message signature, in hex (\"-\": an empty message). Made and checked by",
        "# tests/fixtures/make-link-vectors.py: rfc8032-* are RFC 8032 section 7.1, python-* come from Python's",
        "# \"cryptography\" with throwaway seeds, lua-* from the addon's Olympus/Ed25519.lua. Test keys only.",
    ]
    for name, sd, pk, msg, sig in RFC8032:
        out.append(" ".join([name, sd, pk, msg or "-", sig]))
    for name, label, msg in PYTHON:
        k = key(label)
        out.append(" ".join([name, seed(label).hex(), pub(k).hex(), msg.hex() or "-", k.sign(msg).hex()]))
    out.extend(keep)
    return out


def check_line(line):
    name, sd, pk, msg, sig = line.split()
    msg = b"" if msg == "-" else bytes.fromhex(msg)
    k = Ed25519PrivateKey.from_private_bytes(bytes.fromhex(sd))
    assert pub(k).hex() == pk, name + ": public key"
    assert k.sign(msg).hex() == sig, name + ": signature"
    Ed25519PublicKey.from_public_bytes(bytes.fromhex(pk)).verify(bytes.fromhex(sig), msg)


def make_sample():
    """The sample's values, in order, and the inbox the addon keeps for the links in it."""
    backend = key("backend")
    ca = key("ca")
    v = {}
    v["backend_seed"] = b64(seed("backend"))
    v["backend_pub"] = pub(backend).hex()
    v["ca_seed"] = b64(seed("ca"))
    v["ca_pub"] = pub(ca).hex()
    v["requester"], v["guild"], v["faction"], v["nonce"], v["R"] = NAME, GUILD, FACTION, NONCE, R
    v["token_exp"] = str(TOKEN_EXP)
    v["cert_exp"] = str(CERT_EXP)
    # The code in mode a carries T for the sample's active "p" keys (three: all drawn).
    T_a, _ = draw_threshold(R, list(PLAYERS))
    v["token_a_T"] = T_a
    tokens = {}
    for mode, T in (("a", T_a), ("c", "00000000")):
        payload = token_payload(R, USERNAME, TOKEN_EXP, mode, T)
        sig = b64(backend.sign(payload.encode()))
        tokens[mode] = sig
        v["token_" + mode] = payload + "." + sig
    v["tag_a"] = tag_of(tokens["a"], NAME)
    v["tag_c"] = tag_of(tokens["c"], NAME)
    labels = {}
    for key_id in list(COUNCILLORS) + list(PLAYERS):
        tier = "c" if key_id in COUNCILLORS else "p"
        k = key(key_id)
        labels[key_id] = key_id
        payload = cert_payload(key_id, b64(pub(k)), tier, CERT_EXP, COUNCILLORS.get(key_id) or PLAYERS[key_id])
        v["confirmer_%s_seed" % key_id] = b64(seed(key_id))
        v["confirmer_%s_pub" % key_id] = pub(k).hex()
        v["confirmer_%s_cert" % key_id] = payload + "." + b64(backend.sign(payload.encode()))
    # The councillor certified by the council authority: its id comes from its public key.
    label, character = CA_COUNCILLOR
    k = key(label)
    ca_id = ca_key_id(pub(k))
    labels[ca_id] = label
    payload = cert_payload(ca_id, b64(pub(k)), "c", CERT_EXP, character)
    v["confirmer_%s_seed" % ca_id] = b64(seed(label))
    v["confirmer_%s_pub" % ca_id] = pub(k).hex()
    v["confirmer_%s_cert" % ca_id] = payload + "." + b64(ca.sign(payload.encode()))

    def head(tag, requester=NAME):
        return {"requester": requester, "guild": GUILD, "faction": FACTION, "nonce": NONCE, "R": R, "tag": tag}

    def proof(h, key_id, gv, issued):
        _, pub_b64, tier, exp, confirmer, _, cert_sig = parse_cert(v["confirmer_%s_cert" % key_id])
        p = {"issued": issued, "key_id": key_id, "confirmer": confirmer, "gv": gv, "pub": pub_b64, "tier": tier, "cert_exp": exp,
             "cert_sig": cert_sig}
        p["sig"] = b64(key(labels[key_id]).sign(signed_text(h, p).encode()))
        return p

    hc, ha = head(v["tag_c"]), head(v["tag_a"])
    v["bundle_council"] = bundle_text(hc, [proof(hc, "council01", "r", 1799990100)])
    v["bundle_council_ca"] = bundle_text(hc, [proof(hc, ca_id, "w", 1799990120)])
    v["bundle_council_two"] = bundle_text(hc, [proof(hc, "council01", "c", 1799990100), proof(hc, "council02", "w", 1799990110)])
    v["bundle_players"] = bundle_text(ha, [proof(ha, "player01", "w", 1799990200), proof(ha, "player02", "c", 1799990230),
                                           proof(ha, "player03", "c", 1799990260)])
    v["bundle_players_claimed"] = bundle_text(ha, [proof(ha, "player01", "c", 1799990200), proof(ha, "player02", "c", 1799990230),
                                                   proof(ha, "player03", "c", 1799990260)])
    # Someone who saw R (on a stream) asks for their own character: a councillor signs it, but
    # without the code's signature the tag can't be right, and the Worker refuses the link.
    hi = head(tag_of(b64(b"\0" * 64), OTHER), OTHER)
    v["bundle_impostor"] = bundle_text(hi, [proof(hi, "council02", "c", 1799990150)])
    return v


def sample_lines(v):
    lines = [
        "# A sample Olympus Link (0.9.10): the bot's codes, confirmers' certificates and finished links, signed",
        "# with throwaway test keys (made by tests/fixtures/make-link-vectors.py from public labels): never use",
        "# them for anything real. key=value; *_seed are base64url (as /oly discord key takes them), *_pub hex.",
        "# ca_seed, ca_pub: the council authority's key (the author's client; ns.LINK_CA_KEYS, LINK_CA_PUBLIC).",
        "# token_a (mode a) and token_c (mode c): OLC2.<R>.<username>.<exp>.<mode>.<T>.<sig>, signed by the",
        "#   backend key over all but the last field; token_a_T is T of the sample's three player keys.",
        "# tag_a, tag_c: the first 16 hex of SHA-256(<that token's signature>~<requester>).",
        "# confirmer_<id>_cert: OLK2.<id>.<public key base64url>.<tier c|p>.<exp>.<Name-Realm>.<sig>, signed by",
        "#   the backend key; the one whose id is 12 hex (the first of SHA-256 of its key) by the council authority.",
        "# bundle_council, bundle_council_two, bundle_council_ca: links made with token_c (tag_c); bundle_players",
        "#   (one gv w) and bundle_players_claimed (all gv c): with token_a (tag_a); bundle_impostor: another",
        "#   character's request for the same R, with a tag made without the code's signature (the Worker must",
        "#   refuse it). Each proof carries its certificate: ...,<sig>,<public key>,<tier>,<cert exp>,<cert sig>.",
    ]
    lines += ["%s=%s" % (k, val) for k, val in v.items()]
    return lines


def check_sample(lines):
    values = dict(line.split("=", 1) for line in lines if line and not line.startswith("#"))
    backend = Ed25519PublicKey.from_public_bytes(bytes.fromhex(values["backend_pub"]))
    ca = Ed25519PublicKey.from_public_bytes(bytes.fromhex(values["ca_pub"]))
    for name in ("backend", "ca"):
        assert Ed25519PrivateKey.from_private_bytes(unb64(values[name + "_seed"])).public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex() == values[name + "_pub"], name + " key"
    sigs = {}
    for mode in ("a", "c"):
        token = values["token_" + mode]
        signed, sig = token.rsplit(".", 1)
        backend.verify(unb64(sig), signed.encode())
        fields = signed.split(".")
        assert fields[0] == "OLC2" and fields[-2] == mode, token
        sigs[mode] = sig
        assert values["tag_" + mode] == tag_of(sig, values["requester"]), "tag " + mode
    pubs, certs = {}, {}
    for k, val in values.items():
        if k.startswith("confirmer_") and k.endswith("_cert"):
            key_id = k[len("confirmer_"):-len("_cert")]
            cid, pub_b64, tier, exp, character, signed, sig = parse_cert(val)
            by_ca = key_id == ca_key_id(unb64(pub_b64))
            (ca if by_ca else backend).verify(unb64(sig), signed.encode())
            assert cid == key_id and unb64(pub_b64).hex() == values["confirmer_%s_pub" % key_id], k
            assert tier == ("c" if key_id.startswith("council") or by_ca else "p") and str(exp) == values["cert_exp"], k
            pubs[key_id], certs[key_id] = unb64(pub_b64), val
    assert any(key_id == ca_key_id(p) for key_id, p in pubs.items()), "a certificate of the council authority"
    for name, tag in (("bundle_council", "tag_c"), ("bundle_council_two", "tag_c"), ("bundle_council_ca", "tag_c"),
                      ("bundle_players", "tag_a"), ("bundle_players_claimed", "tag_a"), ("bundle_impostor", None)):
        f = values[name].split("~")
        assert f[0] == "OLB5" and len(f) == 8, name
        h = dict(zip(["requester", "guild", "faction", "nonce", "R", "tag"], f[1:7]))
        assert tag is None or h["tag"] == values[tag], name
        assert tag is not None or h["tag"] not in (values["tag_a"], values["tag_c"]), name
        for part in f[7].split(";"):
            issued, key_id, confirmer, gv, sig, pub_b64, tier, cert_exp, cert_sig = part.split(",")
            # The certificate it carries is the sample's, for its confirmer.
            assert "OLK2.%s.%s.%s.%s.%s.%s" % (key_id, pub_b64, tier, cert_exp, confirmer, cert_sig) == certs[key_id], name
            p = {"issued": issued, "key_id": key_id, "confirmer": confirmer, "gv": gv}
            Ed25519PublicKey.from_public_bytes(pubs[key_id]).verify(unb64(sig), signed_text(h, p).encode())


# The draw: two sets of "p" keys, one of 30 (M = 20) and one of 700 (M = 21).
DRAW_CASES = [("thirty", "7K3M9QX2TB", 30), ("sevenhundred", "ABCDEFGHJK", 700)]


def draw_lines():
    out = [
        "# Olympus Link's draw (decision 4), shared by the addon (Link.Rank, Link.Drawn) and the Worker.",
        "# A \"p\" key's place for code R: the first 8 lowercase hex of SHA-256(R~keyId). At issuance the",
        "# Worker takes M = max(20, ceil(3% of the active \"p\" keys)) and T = the place at index M of the sorted",
        "# places, counting from 0 (\"ffffffff\" with M keys or fewer, \"00000000\" in mode c); a key is drawn",
        "# iff its place < T: the M lowest.",
        "# case <name> <R> <keys> <M> <T>, then key <case> <keyId> <place> <drawn 1|0>. Made by make-link-vectors.py.",
    ]
    for name, R_, n in DRAW_CASES:
        ids = ["draw%04d" % i for i in range(1, n + 1)]
        T, m = draw_threshold(R_, ids)
        out.append("case %s %s %d %d %s" % (name, R_, n, m, T))
        for k in ids:
            place = rank(R_, k)
            out.append("key %s %s %s %d" % (name, k, place, 1 if place < T else 0))
    return out


def check_draw(lines):
    cases, keys = {}, {}
    for line in lines:
        f = line.split()
        if f and f[0] == "case":
            cases[f[1]] = (f[2], int(f[3]), int(f[4]), f[5])
            keys[f[1]] = []
        elif f and f[0] == "key":
            keys[f[1]].append((f[2], f[3], f[4]))
    for name, (R_, n, m, T) in cases.items():
        ids = [k for k, _, _ in keys[name]]
        assert len(ids) == n and draw_threshold(R_, ids) == (T, m), name
        drawn = 0
        for k, place, d in keys[name]:
            assert place == rank(R_, k) and d == ("1" if place < T else "0"), k
            drawn += d == "1"
        assert drawn == min(n, m), name  # the M lowest: T is the (M+1)th lowest place


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


# The watcher's inbox: the sample's links as the addon keeps them (their times are the clock of the
# addon's test, tests/run.lua).
# Until when a watcher keeps a link: the latest proof's time + a code's life (a day) + the clocks'
# difference (5 minutes) + the 7 days the bot takes a link after its code expired (Link.KeepUntil).
def keep_until(bundle):
    latest = max(int(part.split(",")[0]) for part in bundle.split("~")[7].split(";"))
    return latest + 86400 + 300 + 7 * 86400


def inbox_lines(v):
    entries = [(v["R"], v["requester"], v["bundle_council"], 1799990400), (v["R"], OTHER, v["bundle_impostor"], 1799990460)]
    out = [
        "-- A watcher's SavedVariables (WTF/Account/<account>/SavedVariables/Olympus.lua) as the addon writes its",
        "-- Olympus Link inbox (0.9.10): OlympusDB.discord.inbox[R][sender] = { bundle, from, t, keep }. One per",
        "-- sender (its latest), any number per code, 500 in all, each checked first; nothing another sender",
        "-- sent is dropped while its code can still be used (keep: until when, Link.KeepUntil).",
        "-- Made by tests/fixtures/make-link-vectors.py from link-sample.txt; tests/run.lua checks the addon keeps",
        "-- exactly this, and web/tools/read-inbox.mjs reads it. Throwaway test keys only.",
        "OlympusDB = {",
        "\t[\"discord\"] = {",
        "\t\t[\"inbox\"] = {",
    ]
    by_r = {}
    for R_, sender, bundle, t in entries:
        by_r.setdefault(R_, []).append((sender, bundle, t))
    for R_ in sorted(by_r):
        out.append("\t\t\t[%s] = {" % lua_string(R_))
        for sender, bundle, t in sorted(by_r[R_]):
            out.append("\t\t\t\t[%s] = {" % lua_string(sender))
            out.append("\t\t\t\t\t[\"bundle\"] = %s," % lua_string(bundle))
            out.append("\t\t\t\t\t[\"from\"] = %s," % lua_string(sender))
            out.append("\t\t\t\t\t[\"keep\"] = %d," % keep_until(bundle))
            out.append("\t\t\t\t\t[\"t\"] = %d," % t)
            out.append("\t\t\t\t},")
        out.append("\t\t\t},")
    out += ["\t\t},", "\t\t[\"watch\"] = {", "\t\t\t[%s] = true," % lua_string(COUNCILLORS["council01"]), "\t\t},", "\t},", "}"]
    return out


def main():
    keep = []
    if VECTORS.exists():
        keep = [line for line in VECTORS.read_text().splitlines() if line.startswith("lua-")]
    if "--check" in sys.argv:
        vec = [line for line in VECTORS.read_text().splitlines() if line and not line.startswith("#")]
        sample = SAMPLE.read_text().splitlines()
        draw = DRAW.read_text().splitlines()
        values = dict(line.split("=", 1) for line in sample if line and not line.startswith("#"))
        assert INBOX.read_text().splitlines() == inbox_lines(values), "link-inbox.lua is not what the sample makes"
        assert values == make_sample(), "link-sample.txt is not what this script makes"
    else:
        vec_all = vector_lines(keep)
        VECTORS.write_text("\n".join(vec_all) + "\n")
        values = make_sample()
        sample = sample_lines(values)
        SAMPLE.write_text("\n".join(sample) + "\n")
        draw = draw_lines()
        DRAW.write_text("\n".join(draw) + "\n")
        INBOX.write_text("\n".join(inbox_lines(values)) + "\n")
        vec = [line for line in vec_all if line and not line.startswith("#")]
    for line in vec:
        check_line(line)
    names = [line.split()[0] for line in vec]
    assert "lua-ca-cert" in names or "--check" not in sys.argv, "the addon's own council authority certificate (lua-ca-cert)"
    check_sample(sample)
    check_draw(draw)
    print("%d vectors, the sample, the draw and the inbox check out" % len(vec))


if __name__ == "__main__":
    main()
