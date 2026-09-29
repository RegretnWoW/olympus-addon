#!/usr/bin/env python3
"""Builds the addon's border textures from Max's frames, and the member's star.

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

The member's star (Nameplates.lua: the mark next to the name of any other member of an Olympus
guild on a nameplate) is drawn here, not copied from the game's files: Olympus/media/borders/star.tga,
a plain four-point star with no ring, white fading to a pale silver at its points, its edge soft
(each pixel sampled 8 x 8 times, and a faint wider copy round it), on a 32 x 32 canvas (a power of
two; shown at 16 x 16, half its size, like Max's frames). Only square roots and plain arithmetic go
into it (exact to the last bit on every machine, unlike a power or a sine), so every machine builds
the same bytes.

Usage, from anywhere (needs Pillow: python3 -m pip install pillow):
  python3 scripts/make-borders.py          build the .tga files
  python3 scripts/make-borders.py --check  fail unless the .tga files are what it would build
"""

import math
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


# The star: its points' reach from the centre (px on the 32 x 32 canvas), the wider copy that
# softens its edge (its reach this many times the star's, at this opacity), and its colours: white
# at the heart, pale silver at the points (and in the clear pixels round it, so the edge the game's
# filtering blends in is silver, not black).
STAR = "star"
STAR_CANVAS = 32
STAR_REACH = 13.5
STAR_HALO = 1.18
STAR_HALO_ALPHA = 0.35
STAR_SAMPLES = 8
STAR_HEART = (255, 255, 255)
STAR_POINTS = (208, 216, 232)


def build_star():
    """The .tga bytes for the member's star: a four-point star (the points of |x|^0.5 + |y|^0.5
    no more than the reach's square root), no ring."""
    centre = STAR_CANVAS / 2.0
    edge = math.sqrt(STAR_REACH)
    halo = math.sqrt(STAR_REACH * STAR_HALO)
    total = STAR_SAMPLES * STAR_SAMPLES
    rows = []
    for y in range(STAR_CANVAS):
        row = bytearray()
        for x in range(STAR_CANVAS):
            star = soft = 0
            for j in range(STAR_SAMPLES):
                for i in range(STAR_SAMPLES):
                    dx = abs(x + (i + 0.5) / STAR_SAMPLES - centre)
                    dy = abs(y + (j + 0.5) / STAR_SAMPLES - centre)
                    reach = math.sqrt(dx) + math.sqrt(dy)
                    star += reach <= edge
                    soft += reach <= halo
            # Opacity in 255ths: the star's share of the pixel, and the wider copy's faintly beyond it.
            alpha = (star * 255 + (total - star) * soft * 255 * STAR_HALO_ALPHA / total) / total
            dx, dy = x + 0.5 - centre, y + 0.5 - centre
            t = min(1.0, math.sqrt(dx * dx + dy * dy) / STAR_REACH) if star else 1.0
            colour = [int(h + (p - h) * t + 0.5) for h, p in zip(STAR_HEART, STAR_POINTS)]
            row += bytes(colour + [min(255, int(alpha + 0.5))])
        rows.append(bytes(row))
    return tga(STAR_CANVAS, STAR_CANVAS, rows)


def build(name):
    """The .tga bytes for one frame."""
    if name == STAR:
        return build_star()
    path = os.path.join(SOURCES, name + ".png")
    with Image.open(path) as source:
        if source.size != FRAMES[name]:
            raise SystemExit("%s is %dx%d, expected %dx%d (the game's frame it was drawn over)"
                             % (path, source.size[0], source.size[1], FRAMES[name][0], FRAMES[name][1]))
        art = source.convert("RGBA")
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, (0, 0))
    pixels = canvas.tobytes("raw", "RGBA")
    stride = CANVAS * 4
    return tga(CANVAS, CANVAS, [pixels[y * stride:(y + 1) * stride] for y in range(CANVAS)])


def main(argv):
    check = argv[1:] == ["--check"]
    if argv[1:] and not check:
        raise SystemExit(__doc__)
    stale = []
    for name in sorted(FRAMES) + [STAR]:
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
        sys.stderr.write("Not what scripts/make-borders.py builds (run it): %s\n"
                         % ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
