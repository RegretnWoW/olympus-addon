#!/usr/bin/env python3
"""Builds Bone Throw's textures (1.2, the Blood Arena's dice game) for the companion addon.

The sources are PNGs in media/farkle/src, each the exact pixels of the texture the game loads:
- faces.png (1024 x 512): the aged bone die at rest, seen from above: 8 columns x 4 rows of
  128 x 128 cells, column = face 1..6 (7 and 8 empty), row = one of four turns;
- tumble.png (512 x 512): 16 frames of the die spinning in the air, 4 x 4, for FlipBook;
- glow.png (128 x 128): a soft amber ring, for ADD blending;
- icons.png (1024 x 128): the same die with each face square to the frame, face v in column v of
  8, for the rules' pop-up (never rotated: the shadow is baked in);
- table.png (1024 x 512): the tavern table, the board's background.
They come from the dice renders (their README: one geometry for every cell, the die's centre at
the cell's centre, its edge half the cell, the outermost pixel of every cell clear).

Each becomes Olympus_Arena/media/farkle/<name>.tga in the format of the addon's other textures:
32-bit uncompressed true colour with an 8-bit alpha channel (TGA type 2), bottom-left origin,
the TGA 2.0 footer, written by the same writer as scripts/make-borders.py, so the same PNGs always
give the same bytes. Every size is a power of two.

Usage, from anywhere (needs Pillow: python3 -m pip install pillow):
  python3 scripts/make-farkle-art.py          build the .tga files
  python3 scripts/make-farkle-art.py --check  fail unless the .tga files are what it would build
"""

import os
import struct
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SOURCES = os.path.join(ROOT, "media", "farkle", "src")
OUTPUT = os.path.join(ROOT, "Olympus_Arena", "media", "farkle")

# Each texture and its size (FarkleBoard.lua's texture coordinates depend on them).
TEXTURES = {
    "faces": (1024, 512),
    "tumble": (512, 512),
    "glow": (128, 128),
    "icons": (1024, 128),
    "table": (1024, 512),
}


def tga(width, height, rgba_rows):
    """A 32-bit uncompressed TGA with alpha: rows given top first, each width * 4 bytes of RGBA."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    rows = []
    for row in reversed(rgba_rows):
        bgra = bytearray(row)
        bgra[0::4], bgra[2::4] = row[2::4], row[0::4]
        rows.append(bytes(bgra))
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    return header + b"".join(rows) + footer


def build(name):
    width, height = TEXTURES[name]
    image = Image.open(os.path.join(SOURCES, name + ".png")).convert("RGBA")
    if image.size != (width, height):
        raise SystemExit("%s.png is %dx%d, not %dx%d" % (name, image.size[0], image.size[1], width, height))
    data = image.tobytes()
    rows = [data[y * width * 4:(y + 1) * width * 4] for y in range(height)]
    return tga(width, height, rows)


def main():
    check = "--check" in sys.argv[1:]
    failed = False
    if not check:
        os.makedirs(OUTPUT, exist_ok=True)
    for name in sorted(TEXTURES):
        data = build(name)
        path = os.path.join(OUTPUT, name + ".tga")
        if check:
            try:
                with open(path, "rb") as f:
                    held = f.read()
            except OSError:
                held = None
            if held != data:
                print("%s differs from what media/farkle/src/%s.png builds" % (os.path.relpath(path, ROOT), name))
                failed = True
        else:
            with open(path, "wb") as f:
                f.write(data)
            print("wrote %s (%d bytes)" % (os.path.relpath(path, ROOT), len(data)))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
