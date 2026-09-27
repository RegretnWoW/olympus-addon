#!/usr/bin/env python3
"""Olympus Link's shared test vectors (0.9.10), made with Python's "cryptography".

    python3 tests/fixtures/make-link-vectors.py          # rewrite both files
    python3 tests/fixtures/make-link-vectors.py --check  # verify them, change nothing

tests/fixtures/ed25519-vectors.txt: name, seed, public key, message, signature (hex; "-" for
an empty message). rfc8032-*: RFC 8032 section 7.1. python-*: Ed25519PrivateKey from the fixed
seeds below. lua-*: made by the addon's Olympus/Ed25519.lua; kept as they are, checked here.

tests/fixtures/link-sample.txt: a code (OLC1) and proofs (OLB4) as the addon and the bot's
Worker handle them, signed with the throwaway keys below. Every key here is made from a public
label for these tests alone: never use one of them for anything real.
"""
import hashlib
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives import serialization

HERE = Path(__file__).resolve().parent
VECTORS = HERE / "ed25519-vectors.txt"
SAMPLE = HERE / "link-sample.txt"

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
    import base64
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


NAME = "Some Player-ClassicBetaPvP"
ACCENTED = "Sômé Plâyer-ClassicBetaPvP"   # a made-up name with accented letters (UTF-8)
COUNCILLOR = "Test Councillor-ClassicBetaPvP"
PLAYERS = ["Some Player Two-ClassicBetaPvP", "Some Player Three-ClassicBetaPvP", "Some Player Four-ClassicBetaPvP"]

PYTHON = [
    ("python-empty", "vector-a", b""),
    ("python-token", "vector-b", b"OLC1.7K3M9QX2TB.some.player.1800000000.a"),
    ("python-oly4", "vector-c", ("OLY4~" + NAME + "~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~1799990100~council01~" + COUNCILLOR).encode()),
    ("python-oly4-accented", "vector-d", ("OLY4~" + ACCENTED + "~Olympus II~Alliance~fedcba9876543210~ABCDEFGHJK~1799990200~player01~" + PLAYERS[0]).encode()),
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


def sample_lines():
    backend = key("backend")
    exp = 1800000000
    R = "7K3M9QX2TB"
    lines = [
        "# A sample Olympus Link code and proofs (0.9.10), signed with throwaway test keys (made by",
        "# tests/fixtures/make-link-vectors.py from public labels): never use them for anything real.",
        "# key=value; the *_seed values are base64url (as /oly discord key takes them), *_pub hex.",
        "backend_seed=" + b64(seed("backend")),
        "backend_pub=" + pub(backend).hex(),
    ]
    for mode in ("a", "c"):
        signed = "OLC1.%s.some.player.%d.%s" % (R, exp, mode)
        lines.append("token_%s=%s.%s" % (mode, signed, b64(backend.sign(signed.encode()))))
    lines.append("token_exp=%d" % exp)
    head = [NAME, "Olympus II", "Alliance", "0123456789abcdef", R]

    def proof(label, key_id, confirmer, issued):
        k = key(label)
        msg = "~".join(["OLY4"] + head + [str(issued), key_id, confirmer])
        sig = b64(k.sign(msg.encode()))
        return (label, key_id, pub(k).hex()), ",".join([str(issued), key_id, confirmer, sig])

    confirmers = []
    c, cproof = proof("council01", "council01", COUNCILLOR, 1799990100)
    confirmers.append(c)
    pproofs = []
    for i, name in enumerate(PLAYERS):
        kid = "player0%d" % (i + 1)
        p, text = proof(kid, kid, name, 1799990200 + 30 * i)
        confirmers.append(p)
        pproofs.append(text)
    for label, key_id, pk in confirmers:
        lines.append("confirmer_%s_seed=%s" % (key_id, b64(seed(label))))
        lines.append("confirmer_%s_pub=%s" % (key_id, pk))
    lines.append("bundle_council=" + "~".join(["OLB4"] + head + [cproof]))
    lines.append("bundle_players=" + "~".join(["OLB4"] + head + [";".join(pproofs)]))
    return lines


def check_sample(lines):
    import base64
    values = dict(line.split("=", 1) for line in lines if line and not line.startswith("#"))
    backend = Ed25519PublicKey.from_public_bytes(bytes.fromhex(values["backend_pub"]))
    for mode in ("a", "c"):
        token = values["token_" + mode]
        signed, sig = token.rsplit(".", 1)
        backend.verify(base64.urlsafe_b64decode(sig + "=="), signed.encode())
    pubs = {k[len("confirmer_"):-len("_pub")]: v for k, v in values.items() if k.startswith("confirmer_") and k.endswith("_pub")}
    for name in ("bundle_council", "bundle_players"):
        parts = values[name].split("~")
        head, proofs = parts[1:6], parts[6]
        for p in proofs.split(";"):
            issued, key_id, confirmer, sig = p.split(",")
            msg = "~".join(["OLY4"] + head + [issued, key_id, confirmer]).encode()
            Ed25519PublicKey.from_public_bytes(bytes.fromhex(pubs[key_id])).verify(base64.urlsafe_b64decode(sig + "=="), msg)


def main():
    keep = []
    if VECTORS.exists():
        keep = [line for line in VECTORS.read_text().splitlines() if line.startswith("lua-")]
    if "--check" in sys.argv:
        vec = [line for line in VECTORS.read_text().splitlines() if line and not line.startswith("#")]
        sample = SAMPLE.read_text().splitlines()
    else:
        vec_all = vector_lines(keep)
        VECTORS.write_text("\n".join(vec_all) + "\n")
        sample = sample_lines()
        SAMPLE.write_text("\n".join(sample) + "\n")
        vec = [line for line in vec_all if line and not line.startswith("#")]
    for line in vec:
        check_line(line)
    check_sample(sample)
    print("%d vectors and the sample check out" % len(vec))


if __name__ == "__main__":
    main()
