# The PNG fixtures for test/png: small images written the way GIMP 3
# writes them, zlib at level 9 and IDATs of 8192 bytes, one of every
# colour type and depth the kernel decodes with every filter type
# reached, one cut into IDATs of a single byte, one big enough for
# several IDATs, one wrapped in ancillary chunks, and the files the
# kernel must refuse; then the directories jab.sprite.load reads, a
# sprite of four frames and two that must refuse. Writes each into the
# directory given and prints, as JSON, what the kernel should make of
# each: the size its header says and its pixels in the kernel's own
# format, four bytes a pixel, blue, green, red, alpha.
#
#     python3 encode.py <directory>

import json
import os
import random
import struct
import sys
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
GIMP_IDAT = 8192
GIMP_LEVEL = 9


def be32(n):
    return struct.pack(">I", n)


def chunk(kind, data):
    return be32(len(data)) + kind + data + be32(zlib.crc32(kind + data) & 0xFFFFFFFF)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def filter_row(kind, row, prev, bpp):
    out = bytearray()
    for i, x in enumerate(row):
        a = row[i - bpp] if i >= bpp else 0
        b = prev[i] if prev is not None else 0
        c = prev[i - bpp] if (prev is not None and i >= bpp) else 0
        if kind == 1:
            v = x - a
        elif kind == 2:
            v = x - b
        elif kind == 3:
            v = x - ((a + b) >> 1)
        elif kind == 4:
            v = x - paeth(a, b, c)
        else:
            v = x
        out.append(v & 0xFF)
    return bytes(out)


def pack(samples, depth):
    if depth == 8:
        return bytes(samples)
    out = bytearray()
    acc, bits = 0, 0
    for s in samples:
        acc = (acc << depth) | s
        bits += depth
        if bits == 8:
            out.append(acc)
            acc, bits = 0, 0
    if bits:
        out.append(acc << (8 - bits))
    return bytes(out)


def encode(width, height, depth, ctype, rows, filters, plte=None, trns=None,
           idat=GIMP_IDAT, interlace=0, extras=False, declared_height=None,
           break_adler=False):
    bpp = max(1, CHANNELS[ctype] * depth // 8)
    filtered = b""
    prev = None
    for row, kind in zip(rows, filters):
        filtered += bytes([kind]) + filter_row(kind, row, prev, bpp)
        prev = row
    stream = zlib.compress(filtered, GIMP_LEVEL)
    if break_adler:
        stream = stream[:-1] + bytes([stream[-1] ^ 0xFF])
    h = height if declared_height is None else declared_height
    out = SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, h, depth, ctype, 0, 0, interlace))
    if extras:
        out += chunk(b"tEXt", b"Comment\x00made for test/png")
        out += chunk(b"pHYs", struct.pack(">IIB", 2835, 2835, 1))
    if plte is not None:
        out += chunk(b"PLTE", plte)
    if trns is not None:
        out += chunk(b"tRNS", trns)
    for i in range(0, len(stream), idat):
        out += chunk(b"IDAT", stream[i:i + idat])
    if extras:
        out += chunk(b"tIME", struct.pack(">HBBBBB", 2026, 9, 25, 0, 0, 0))
    out += chunk(b"IEND", b"")
    return out


def native(pixels):
    # pixels: rows of (r, g, b, a)
    out = bytearray()
    for row in pixels:
        for r, g, b, a in row:
            out += bytes([b, g, r, a])
    return out.hex()


def spans(pixels):
    # a row's first and last column with any alpha, little-endian
    # 16-bit each; the first past the last for a row with none
    out = bytearray()
    for row in pixels:
        cols = [x for x, p in enumerate(row) if p[3] != 0]
        first = cols[0] if cols else len(row)
        last = cols[-1] if cols else 0
        out += struct.pack("<HH", first, last)
    return out.hex()


def cycle_filters(height):
    return [i % 5 for i in range(height)]


def rgba_image(rng, width, height):
    pixels = []
    for y in range(height):
        row = []
        for x in range(width):
            a = rng.choice([0, 255, 255, rng.randrange(256)])
            row.append((rng.randrange(256), rng.randrange(256), rng.randrange(256), a))
        pixels.append(row)
    rows = [bytes(v for p in row for v in p) for row in pixels]
    return pixels, rows


def main(directory):
    rng = random.Random(20260925)
    fixtures = []
    dirs = []

    def emit(name, data, width, height, pixels=None):
        with open(f"{directory}/{name}", "wb") as f:
            f.write(data)
        fixtures.append({
            "name": name,
            "width": width,
            "height": height,
            "native": native(pixels) if pixels is not None else "",
            "spans": spans(pixels) if pixels is not None else "",
        })

    w, h = 7, 5
    filters = cycle_filters(h)

    # RGBA, the logo's kind
    pixels, rows = rgba_image(rng, w, h)
    emit("rgba8.png", encode(w, h, 8, 6, rows, filters), w, h, pixels)

    # RGB with a transparent key, which some pixels carry
    key = (10, 200, 30)
    rgb = [[key if rng.random() < 0.3 else (rng.randrange(256), rng.randrange(256), rng.randrange(256))
            for _ in range(w)] for _ in range(h)]
    rows = [bytes(v for p in row for v in p) for row in rgb]
    pixels = [[(r, g, b, 0 if (r, g, b) == key else 255) for r, g, b in row] for row in rgb]
    trns = struct.pack(">HHH", *key)
    emit("rgb8.png", encode(w, h, 8, 2, rows, filters, trns=trns), w, h, pixels)

    # grey at every depth; the 8-bit one keyed
    for depth in (8, 4, 2, 1):
        top = (1 << depth) - 1
        scale = 255 // top
        samples = [[rng.randrange(top + 1) for _ in range(w)] for _ in range(h)]
        gkey = top // 2
        rows = [pack(row, depth) for row in samples]
        trns = struct.pack(">H", gkey) if depth == 8 else None
        pixels = [[(s * scale, s * scale, s * scale, 0 if (depth == 8 and s == gkey) else 255) for s in row]
                  for row in samples]
        emit(f"grey{depth}.png", encode(w, h, depth, 0, rows, filters, trns=trns), w, h, pixels)

    # grey with alpha
    ga = [[(rng.randrange(256), rng.choice([0, 255, rng.randrange(256)])) for _ in range(w)] for _ in range(h)]
    rows = [bytes(v for p in row for v in p) for row in ga]
    pixels = [[(g, g, g, a) for g, a in row] for row in ga]
    emit("ga8.png", encode(w, h, 8, 4, rows, filters), w, h, pixels)

    # indexed at every depth, the palette as large as the depth allows
    # and the transparency shorter than the palette
    for depth in (8, 4, 2, 1):
        colours = {8: 20, 4: 16, 2: 4, 1: 2}[depth]
        palette = [(rng.randrange(256), rng.randrange(256), rng.randrange(256)) for _ in range(colours)]
        alphas = [rng.randrange(256) for _ in range(max(1, colours - 1))]
        samples = [[rng.randrange(colours) for _ in range(w)] for _ in range(h)]
        rows = [pack(row, depth) for row in samples]
        plte = bytes(v for c in palette for v in c)
        trns = bytes(alphas)
        pixels = [[palette[s] + ((alphas[s] if s < len(alphas) else 255),) for s in row] for row in samples]
        emit(f"idx{depth}.png", encode(w, h, depth, 3, rows, filters, plte=plte, trns=trns), w, h, pixels)

    # a sheet of two frames stacked, decoded with frames=2
    pixels, rows = rgba_image(rng, w, 10)
    emit("sheet.png", encode(w, 10, 8, 6, rows, cycle_filters(10)), w, 10, pixels)

    # the stream cut into IDATs of one byte, so every boundary is crossed
    pixels, rows = rgba_image(rng, w, h)
    emit("split.png", encode(w, h, 8, 6, rows, filters, idat=1), w, h, pixels)

    # big enough for several IDATs of GIMP's size, and for stored blocks
    pixels, rows = rgba_image(rng, 64, 64)
    emit("big.png", encode(64, 64, 8, 6, rows, cycle_filters(64)), 64, 64, pixels)

    # ancillary chunks before and after the image data
    pixels, rows = rgba_image(rng, w, h)
    emit("extras.png", encode(w, h, 8, 6, rows, filters, extras=True), w, h, pixels)

    # what the kernel refuses
    rows16 = [bytes(rng.randrange(256) for _ in range(w * 6)) for _ in range(h)]
    emit("depth16.png", encode(w, h, 16, 2, rows16, filters), w, h)
    pixels, rows = rgba_image(rng, w, h)
    emit("interlaced.png", encode(w, h, 8, 6, rows, filters, interlace=1), w, h)

    pixels, rows = rgba_image(rng, w, h)
    good = encode(w, h, 8, 6, rows, filters)
    at = good.index(b"IDAT")
    length = struct.unpack(">I", good[at - 4:at])[0]
    crc_at = at + 4 + length
    bad = bytearray(good)
    bad[crc_at + 3] ^= 0x55
    emit("badcrc.png", bytes(bad), w, h)
    emit("badadler.png", encode(w, h, 8, 6, rows, filters, break_adler=True), w, h)
    emit("badfilter.png", encode(w, h, 8, 6, rows, [0, 1, 7, 3, 4]), w, h)
    emit("short.png", encode(w, h - 1, 8, 6, rows[:-1], filters[:-1], declared_height=h), w, h)
    emit("truncated.png", good[:at + 4 + 20], w, h)
    emit("notpng.png", b"hello, this is not a png\n", 0, 0)

    # the directories jab.sprite.load reads: a sprite of four frames, one
    # whose second frame is another size, and one with no 0.png
    def emit_dir(name, frames):
        os.mkdir(f"{directory}/{name}")
        record = {"name": name, "frames": len(frames), "native": "", "spans": ""}
        for k, (fw, fh, extra) in enumerate(frames):
            px, rw = rgba_image(rng, fw, fh)
            with open(f"{directory}/{name}/{k + extra}.png", "wb") as f:
                f.write(encode(fw, fh, 8, 6, rw, cycle_filters(fh)))
            record["native"] += native(px)
            record["spans"] += spans(px)
            if k == 0:
                record["width"], record["height"] = fw, fh
        dirs.append(record)

    emit_dir("walker", [(5, 6, 0)] * 4)
    emit_dir("mixed", [(5, 6, 0), (6, 6, 0)])
    emit_dir("nozero", [(5, 6, 1)])

    print(json.dumps({"fixtures": fixtures, "dirs": dirs}))


if __name__ == "__main__":
    main(sys.argv[1])
