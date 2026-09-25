# The oracle for example/logo's test: decode a PNG on the host with
# python's zlib and the five filters, composite it over black the way
# the kernel blends, and write the result as rows of red, green, blue
# bytes, so the screen can be held against it pixel for pixel.
#
#     python3 decode.py <png> <out.rgb>

import struct
import sys
import zlib

CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def round255(x):
    t = x + 128
    return (t + (t >> 8)) >> 8


def main(png_path, out_path):
    with open(png_path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and interlace == 0 and ctype in CHANNELS
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    bpp = CHANNELS[ctype]
    stride = width * bpp
    prev = bytearray(stride)
    out = bytearray()
    at = 0
    for _ in range(height):
        kind = raw[at]
        row = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if kind == 1:
                row[i] = (row[i] + a) & 0xFF
            elif kind == 2:
                row[i] = (row[i] + b) & 0xFF
            elif kind == 3:
                row[i] = (row[i] + ((a + b) >> 1)) & 0xFF
            elif kind == 4:
                row[i] = (row[i] + paeth(a, b, c)) & 0xFF
        for x in range(width):
            p = row[x * bpp:(x + 1) * bpp]
            if ctype == 6:
                r, g, b, a = p
            elif ctype == 2:
                r, g, b = p
                a = 255
            elif ctype == 4:
                r = g = b = p[0]
                a = p[1]
            else:
                r = g = b = p[0]
                a = 255
            if a == 0:
                out += b"\x00\x00\x00"
            elif a == 255:
                out += bytes([r, g, b])
            else:
                out += bytes([round255(r * a), round255(g * a), round255(b * a)])
        prev = row
    with open(out_path, "wb") as f:
        f.write(out)
    print(f"{width} {height}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
