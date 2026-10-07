#!/usr/bin/env python3
"""Cleans Bones' table texture, Olympus_Arena/media/games/farkle-table.tga (1024 x 512, 32-bit,
uncompressed, bottom-left origin), in place: the same bytes every time it runs (idempotent).

The owner saw thin coloured dashed lines across the table in the arena build. The Frame Lab split
the table in two halves to leave out the texture's rows 251-259, a faint seam the client drew as a
broken line of coloured dashes. So that no sampling (a texture coordinate near a seam, the client's
filtering or its mip levels) can reach a seam or an edge again, this script:
- repaints the seam, rows 251-259, as a blend of rows 250 and 260 (the wood above and below it);
- repaints the four outer rows and columns at each edge with the fifth one in, so the texture's
  edges carry the wood itself (no dark rim or speck for a filter to pull in);
- repaints any pixel off the wood's hues (blue over green, or green over red, by more than 12) with
  the median of its neighbours;
and writes the TGA 2.0 footer (as make-borders.py's textures have). Farkle.lua and Games.lua keep
their texture coordinates 4 texels or more away from any seam or edge as well.

Usage, from anywhere: python3 scripts/make-table-texture.py
"""
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "Olympus_Arena", "media", "games", "farkle-table.tga")
SEAM = (251, 259)  # inclusive, rows from the top
EDGE = 4


def main():
    data = open(PATH, "rb").read()
    idlen, cmap, itype = data[0], data[1], data[2]
    w, h = struct.unpack("<HH", data[12:16])
    bpp, desc = data[16], data[17]
    if itype != 2 or cmap != 0 or bpp != 32:
        sys.exit("farkle-table.tga: expected an uncompressed 32-bit true-colour TGA")
    top_origin = bool(desc & 0x20)
    off = 18 + idlen
    px = [bytearray(data[off + (y if top_origin else h - 1 - y) * w * 4: off + ((y if top_origin else h - 1 - y) + 1) * w * 4])
          for y in range(h)]  # rows from the top, BGRA

    def get(x, y):
        r = px[y]
        return r[x * 4], r[x * 4 + 1], r[x * 4 + 2], r[x * 4 + 3]

    def put(x, y, bgra):
        r = px[y]
        r[x * 4:x * 4 + 4] = bytes(bgra)

    # the seam: a blend of the rows round it
    a, b = SEAM[0] - 1, SEAM[1] + 1
    for y in range(SEAM[0], SEAM[1] + 1):
        t = (y - a) / (b - a)
        for x in range(w):
            p, q = get(x, a), get(x, b)
            put(x, y, [int(round(p[i] + (q[i] - p[i]) * t)) for i in range(3)] + [255])
    # the edges: the wood of the fifth row or column in
    for y in range(EDGE):
        px[y][:] = px[EDGE]
        px[h - 1 - y][:] = px[h - 1 - EDGE]
    for y in range(h):
        for x in range(EDGE):
            put(x, y, get(EDGE, y))
            put(w - 1 - x, y, get(w - 1 - EDGE, y))
    # stray pixels off the wood's hues: their neighbours' median
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            bl, gr, rd, _ = get(x, y)
            if bl > gr + 12 or gr > rd + 12:
                nb = [get(x + dx, y + dy) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy]
                put(x, y, [sorted(n[i] for n in nb)[4] for i in range(3)] + [255])
    # every pixel opaque
    for y in range(h):
        r = px[y]
        for x in range(w):
            r[x * 4 + 3] = 255

    header = bytes([0, 0, 2]) + bytes(5) + struct.pack("<HHHH", 0, 0, w, h) + bytes([32, 8])
    body = b"".join(bytes(px[h - 1 - y]) for y in range(h))  # bottom-left origin
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    open(PATH, "wb").write(header + body + footer)
    print("farkle-table.tga: cleaned (%d x %d)" % (w, h))


if __name__ == "__main__":
    main()
