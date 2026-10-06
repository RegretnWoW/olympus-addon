#!/usr/bin/env python3
"""Builds the Menagerie Lottery's beast images (Olympus_Arena/media/lottery/<beast>.tga).

The lottery's table (Olympus_Arena/LotteryBoard.lua) shows 25 beasts. Nineteen wear the gold marks the
owner's playable preview chose (the lab's OlympusFrameLab/Bicho.lua): the honours' 32 x 32 nameplate
marks (the Sheep is the mage's, the Cobra the rogue's, the Horse the paladin's, the Felhunter the
warlock's, the Tentacle the priest's, the Cheetah the hunter's, the Stag the druid's, the Wolf the
orc's), and the Dragon the mark made from the game's gold elite frame. The other six use the game's
own icons (Lottery.lua names them), so they have no file here.

Their sources are PNGs in media/lottery/src (outside the addon's folders, like media/borders/src),
taken once from the lab's TGA files with --import. Each becomes a 32 x 32 TGA the way
scripts/make-borders.py writes its textures: 32-bit uncompressed true colour with an 8-bit alpha
channel (type 2), bottom-left origin, the TGA 2.0 footer. The bytes are written here, not by Pillow's
TGA writer, so the same PNGs always give the same files (the lab's files come back byte for byte).

Usage, from anywhere (needs Pillow: python3 -m pip install pillow):
  python3 scripts/make-lottery-art.py                  build the .tga files from the PNG sources
  python3 scripts/make-lottery-art.py --check          fail unless the .tga files are what it would build
  python3 scripts/make-lottery-art.py --import DIR     write the PNG sources from the lab's marks in DIR
                                                       (OlympusFrameLab/media), then build
"""

import os
import struct
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SOURCES = os.path.join(ROOT, "media", "lottery", "src")
OUTPUT = os.path.join(ROOT, "Olympus_Arena", "media", "lottery")
SIZE = 32

# Each beast with a file, and the lab's mark it comes from.
BEASTS = {
    "mechanostrider": "mechanostrider-gold-mark",
    "gryphon": "gryphon-gold-mark",
    "wolf": "orc-wolf-gold-mark",
    "raptor": "raptor-gold-mark",
    "sheep": "mage-gold-mark",
    "cobra": "rogue-gold-mark",
    "koi": "koi-gold-mark",
    "horse": "paladin-gold-mark",
    "dragon": "original-mark",
    "raven": "raven-gold-mark",
    "nightsaber": "nightsaber-gold-mark",
    "lion": "lion-gold-mark",
    "boar": "boar-gold-mark",
    "owl": "owl-gold-mark",
    "felhunter": "warlock-gold-mark",
    "tentacle": "priest-gold-mark",
    "cheetah": "hunter-gold-mark",
    "stag": "druid-gold-mark",
    "kodo": "kodo-gold-mark",
}


def tga(width, height, rgba_rows):
    """A 32-bit uncompressed TGA with alpha: rows given top first, each width * 4 bytes of RGBA."""
    # id length, colour map type, image type 2 (true colour), colour map spec (none), x and y
    # origin, width, height, 32 bits a pixel, descriptor 8 (8 alpha bits, bottom-left origin).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    rows = []
    for row in reversed(rgba_rows):
        bgra = bytearray(row)
        bgra[0::4], bgra[2::4] = row[2::4], row[0::4]
        rows.append(bytes(bgra))
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    return header + b"".join(rows) + footer


def build(name):
    """The .tga bytes for one beast, from its PNG."""
    path = os.path.join(SOURCES, name + ".png")
    with Image.open(path) as source:
        if source.size != (SIZE, SIZE):
            raise SystemExit("%s is %dx%d, expected %dx%d" % (path, source.size[0], source.size[1], SIZE, SIZE))
        art = source.convert("RGBA")
    pixels = art.tobytes("raw", "RGBA")
    stride = SIZE * 4
    return tga(SIZE, SIZE, [pixels[y * stride:(y + 1) * stride] for y in range(SIZE)])


def import_lab(folder):
    """The PNG sources from the lab's TGA marks (lossless: the colour of clear pixels kept too)."""
    os.makedirs(SOURCES, exist_ok=True)
    for name, lab in sorted(BEASTS.items()):
        path = os.path.join(folder, lab + ".tga")
        with Image.open(path) as mark:
            if mark.size != (SIZE, SIZE):
                raise SystemExit("%s is %dx%d, expected %dx%d" % (path, mark.size[0], mark.size[1], SIZE, SIZE))
            mark.convert("RGBA").save(os.path.join(SOURCES, name + ".png"), optimize=True)
        print("imported %s from %s" % (name, lab))


def main(argv):
    check = "--check" in argv
    if "--import" in argv:
        at = argv.index("--import")
        if at + 1 >= len(argv):
            raise SystemExit("--import needs the lab's media folder")
        import_lab(argv[at + 1])
    os.makedirs(OUTPUT, exist_ok=True)
    wrong = []
    for name in sorted(BEASTS):
        data = build(name)
        out = os.path.join(OUTPUT, name + ".tga")
        if check:
            try:
                with open(out, "rb") as f:
                    if f.read() != data:
                        wrong.append(out)
            except OSError:
                wrong.append(out)
        else:
            with open(out, "wb") as f:
                f.write(data)
    if wrong:
        raise SystemExit("not what scripts/make-lottery-art.py builds: " + ", ".join(wrong))
    print("%s %d beast images" % ("checked" if check else "built", len(BEASTS)))


if __name__ == "__main__":
    main(sys.argv[1:])
