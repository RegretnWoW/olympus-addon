#!/usr/bin/env python3
"""Brings the honours' finished frames and marks into the addon: Olympus/media/honors/ (1.2).

The frames were finished in the frame lab (the throwaway OlympusFrameLab addon, where each was
seen in game on a portrait and a nameplate) as WoW-ready textures, the format of the addon's other
art (Olympus/media/borders, scripts/make-borders.py): 32-bit uncompressed true colour with an
8-bit alpha channel (TGA type 2), bottom-left origin, the TGA 2.0 footer; a frame on a 256 x 256
canvas with its art at the top left (winged 220 x 180, plain 200 x 200: Borders.lua's texture
coordinates), a nameplate mark on 32 x 32. The lab names each frame <name>.tga (gold; the
Paladin's gold is paladin-new.tga), <name>-silver.tga and <name>-bronze.tga, and each mark
<name>-<metal>-mark.tga.

Only the ones the honours use come in (the design), renamed <name>-<metal>.tga and
<name>-<metal>-mark.tga, the stems Honors.ArtOf gives (the Lua tests check the two lists agree):
the arena champion's gryphon, the nine class beasts, the eight racial mounts, the cornucopia (all
time donors), the koi (the month's donors), the raven (the Oracle) and the comet (the level race),
each in gold, silver and bronze; the best guild's owl in gold alone. The lab's other files (the
raw and colour drafts, the phoenix, the dragon, the owl's silver and bronze) stay out, so the
package carries 67 frames and 67 marks and nothing else:
67 x 262,188 + 67 x 4,140 bytes = 17,843,976 bytes (17.0 MiB) on disk, about 3.2 MB in the zip
(the transparent canvas packs well). The files are copied byte for byte, never re-encoded.

Their provenance stays in the repository without a second copy of 17 MB: media/honors/src/SHA256SUMS
(outside the package, like media/borders/src) records each lab file's SHA-256, its lab name and the
addon name it ships as, written by --from. --check compares every shipped file with it byte for
byte (through the hash), so the art can be checked again after the throwaway lab is gone.

Usage, from anywhere (no Pillow needed):
  python3 scripts/make-honors.py --from <lab media folder>   copy and rename them in, and write
                                                             media/honors/src/SHA256SUMS
  python3 scripts/make-honors.py --check                     fail unless the shipped set is whole,
                                                             each file has the right shape and is
                                                             the lab file SHA256SUMS records
  python3 scripts/make-honors.py --check --from <folder>     ...and is byte for byte its source
"""

import hashlib
import os
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUTPUT = os.path.join(ROOT, "Olympus", "media", "honors")
MANIFEST = os.path.join(ROOT, "media", "honors", "src", "SHA256SUMS")

METALS = ("gold", "silver", "bronze")
# Each beast of the honours table, and the metals it comes in.
BEASTS = [
    "gryphon",                                              # the arena champion (winged)
    "boar", "paladin", "hunter", "rogue", "priest",         # the class champions' beasts
    "shaman", "mage", "warlock", "druid",
    "lion", "ram", "nightsaber", "mechanostrider",          # the race champions' mounts
    "orc-wolf", "skeletal-horse", "kodo", "raptor",
    "cornucopia", "koi", "raven", "comet",                  # donors, the month's, the Oracle, the level race
]
GOLD_ONLY = ["owl"]                                          # the best guild's leader (winged)
# The lab's name for a gold frame, where it is not <name>.tga.
GOLD_SOURCE = {"paladin": "paladin-new"}
FRAME_SIZE, MARK_SIZE = 256, 32


def files():
    """(addon file name, lab file name, square size) for every file the honours ship."""
    out = []
    for beast in BEASTS + GOLD_ONLY:
        for metal in (METALS if beast in BEASTS else ("gold",)):
            frame = GOLD_SOURCE.get(beast, beast) if metal == "gold" else beast + "-" + metal
            out.append(("%s-%s.tga" % (beast, metal), frame + ".tga", FRAME_SIZE))
            out.append(("%s-%s-mark.tga" % (beast, metal), "%s-%s-mark.tga" % (beast, metal), MARK_SIZE))
    return out


def shape_error(data, size):
    """Why the bytes are not a size x size 32-bit uncompressed TGA with alpha, or None."""
    if len(data) != 18 + size * size * 4 + 26:
        return "%d bytes, not %d" % (len(data), 18 + size * size * 4 + 26)
    idlen, cmap, kind, _, _, _, _, _, width, height, bits, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    if (idlen, cmap, kind, width, height, bits, desc) != (0, 0, 2, size, size, 32, 8):
        return "header %r" % ((idlen, cmap, kind, width, height, bits, desc),)
    if not data.endswith(b"TRUEVISION-XFILE.\0"):
        return "no TGA 2.0 footer"
    return None


def read(path):
    with open(path, "rb") as f:
        return f.read()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_manifest():
    """{ addon name: (sha256, lab name) } from SHA256SUMS, or None when it is missing."""
    if not os.path.exists(MANIFEST):
        return None
    out = {}
    with open(MANIFEST, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            digest, lab, name = line.split()
            out[name] = (digest, lab)
    return out


def write_manifest(rows):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        f.write("# The honours' art (Olympus/media/honors): each file's SHA-256, the frame lab's file it was\n")
        f.write("# copied from, and its name in the addon. Written by scripts/make-honors.py --from; checked by --check.\n")
        for name, lab, digest in sorted(rows):
            f.write("%s  %s  %s\n" % (digest, lab, name))


def main(argv):
    check = "--check" in argv
    source = None
    if "--from" in argv:
        i = argv.index("--from")
        if i + 1 >= len(argv):
            sys.exit("--from needs the lab's media folder")
        source = argv[i + 1]
    if not check and not source:
        sys.exit(__doc__)
    wanted = files()
    problems = []
    manifest = read_manifest() if check else None
    if check and manifest is None:
        problems.append("missing: media/honors/src/SHA256SUMS")
    rows = []
    if not check:
        os.makedirs(OUTPUT, exist_ok=True)
    for name, lab, size in wanted:
        target = os.path.join(OUTPUT, name)
        data = None
        if source:
            path = os.path.join(source, lab)
            if not os.path.exists(path):
                problems.append("missing in the source: " + lab)
                continue
            data = read(path)
            why = shape_error(data, size)
            if why:
                problems.append("%s: %s" % (lab, why))
                continue
        if check:
            if not os.path.exists(target):
                problems.append("missing: Olympus/media/honors/" + name)
                continue
            shipped = read(target)
            why = shape_error(shipped, size)
            recorded = manifest.get(name) if manifest is not None else None
            if why:
                problems.append("%s: %s" % (name, why))
            elif data is not None and shipped != data:
                problems.append("%s is not %s" % (name, lab))
            elif manifest is None:
                pass
            elif not recorded or recorded[1] != lab:
                problems.append("%s: not in media/honors/src/SHA256SUMS as %s" % (name, lab))
            elif recorded[0] != sha(shipped):
                problems.append("%s is not the lab's %s (SHA256SUMS)" % (name, lab))
        else:
            with open(target, "wb") as f:
                f.write(data)
            rows.append((name, lab, sha(data)))
    names = set(n for n, _, _ in wanted)
    if os.path.isdir(OUTPUT):
        for extra in sorted(os.listdir(OUTPUT)):
            if extra.endswith(".tga") and extra not in names:
                problems.append("not an honour's file: Olympus/media/honors/" + extra)
    for extra in sorted(set(manifest or {}) - names):
        problems.append("SHA256SUMS names a file the honours do not ship: " + extra)
    if problems:
        sys.exit("\n".join(problems))
    if not check:
        write_manifest(rows)
    total = sum(os.path.getsize(os.path.join(OUTPUT, n)) for n in names)
    print("%s %d honour files (%d frames, %d marks), %d bytes" % ("checked" if check else "wrote", len(names),
          len(names) // 2, len(names) // 2, total))


if __name__ == "__main__":
    main(sys.argv[1:])
