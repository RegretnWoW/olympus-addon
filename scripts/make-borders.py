#!/usr/bin/env python3
"""Builds the addon's border textures from Max's frames.

Max drew the bronze frames over the game's own gold ones (Forever 1.60.1, uiunitframebossc602x,
at twice their size on screen): media/borders/src/bronze-plain.png (200 x 200, over the plain
gold elite frame) and bronze-winged.png (220 x 180, over the winged one). Each becomes
Olympus/media/borders/<name>.tga, the format of the addon's other textures (media/logo64.tga)
that Forever and the Classic clients load with SetTexture:

- a power-of-two canvas, 256 x 256, the PNG's art at its top left and transparent elsewhere
  (Borders.lua's texture coordinates are the art's area: 200/256, 220/256 and 180/256);
- 32-bit uncompressed true colour with an 8-bit alpha channel (TGA type 2), bottom-left origin,
  with the TGA 2.0 footer. The bytes are written here, not by Pillow's TGA writer, so the same
  PNGs always give the same files.

Usage, from anywhere (needs Pillow: python3 -m pip install pillow):
  python3 scripts/make-borders.py          build the .tga files
  python3 scripts/make-borders.py --check  fail unless the .tga files are what it would build
"""

import os
import struct
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SOURCES = os.path.join(ROOT, "media", "borders", "src")
OUTPUT = os.path.join(ROOT, "Olympus", "media", "borders")
CANVAS = 256

# Each frame and the size of the game's frame it was drawn over (Borders.lua's texture
# coordinates depend on them).
FRAMES = {
    "bronze-plain": (200, 200),
    "bronze-winged": (220, 180),
}


def build(name):
    """The .tga bytes for one frame."""
    path = os.path.join(SOURCES, name + ".png")
    with Image.open(path) as source:
        if source.size != FRAMES[name]:
            raise SystemExit("%s is %dx%d, expected %dx%d (the game's frame it was drawn over)"
                             % (path, source.size[0], source.size[1], FRAMES[name][0], FRAMES[name][1]))
        art = source.convert("RGBA")
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, (0, 0))
    # id length, colour map type, image type 2 (true colour), colour map spec (none), x and y
    # origin, width, height, 32 bits a pixel, descriptor 8 (8 alpha bits, bottom-left origin).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, CANVAS, CANVAS, 32, 8)
    pixels = canvas.tobytes("raw", "BGRA")
    stride = CANVAS * 4
    rows = [pixels[y * stride:(y + 1) * stride] for y in range(CANVAS - 1, -1, -1)]
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    return header + b"".join(rows) + footer


def main(argv):
    check = argv[1:] == ["--check"]
    if argv[1:] and not check:
        raise SystemExit(__doc__)
    stale = []
    for name in sorted(FRAMES):
        data = build(name)
        target = os.path.join(OUTPUT, name + ".tga")
        if check:
            try:
                with open(target, "rb") as f:
                    same = f.read() == data
            except OSError:
                same = False
            if not same:
                stale.append(os.path.relpath(target, ROOT))
        else:
            os.makedirs(OUTPUT, exist_ok=True)
            with open(target, "wb") as f:
                f.write(data)
            print(os.path.relpath(target, ROOT))
    if stale:
        sys.stderr.write("Not what scripts/make-borders.py builds from media/borders/src (run it): %s\n"
                         % ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
