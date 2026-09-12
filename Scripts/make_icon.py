#!/usr/bin/env python3
"""Renders HomeHub's app icon set from code — no design tool, no binary blobs
checked in that nobody can regenerate.

Usage: python3 Scripts/make_icon.py
Writes HomeHub/Resources/Assets.xcassets/AppIcon.appiconset/*.png
"""
import json
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "HomeHub", "Resources", "Assets.xcassets", "AppIcon.appiconset")

SS = 4                      # supersampling factor
BASE = 1024
N = BASE * SS

TOP = (0x1B, 0x22, 0x33)
BOTTOM = (0x0B, 0x0D, 0x12)
ROOF = (0x73, 0xB8, 0xFF)
BODY = (0xFF, 0xB8, 0x59)
DOOR = (0x0B, 0x0D, 0x12)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def fill_polygon(buf, width, height, points, color):
    """Even-odd scanline fill over an RGB bytearray."""
    ys = [p[1] for p in points]
    y0, y1 = max(0, int(min(ys))), min(height - 1, int(max(ys)) + 1)
    count = len(points)
    for y in range(y0, y1 + 1):
        center = y + 0.5
        crossings = []
        for i in range(count):
            ax, ay = points[i]
            bx, by = points[(i + 1) % count]
            if (ay <= center < by) or (by <= center < ay):
                crossings.append(ax + (center - ay) / (by - ay) * (bx - ax))
        crossings.sort()
        for i in range(0, len(crossings) - 1, 2):
            xa = max(0, int(round(crossings[i])))
            xb = min(width - 1, int(round(crossings[i + 1])))
            if xb < xa:
                continue
            offset = (y * width + xa) * 3
            row = bytes(color) * (xb - xa + 1)
            buf[offset:offset + len(row)] = row


def render_master():
    buf = bytearray(N * N * 3)
    for y in range(N):
        color = bytes(lerp(TOP, BOTTOM, y / (N - 1)))
        buf[y * N * 3:(y + 1) * N * 3] = color * N

    s = N / 1024.0

    # Roof: a wide chevron.
    fill_polygon(buf, N, N, [
        (512 * s, 210 * s), (852 * s, 470 * s), (852 * s, 560 * s),
        (512 * s, 300 * s), (172 * s, 560 * s), (172 * s, 470 * s),
    ], ROOF)

    # Body: the house walls, open at the top so the roof reads as separate.
    fill_polygon(buf, N, N, [
        (246 * s, 512 * s), (778 * s, 512 * s),
        (778 * s, 838 * s), (246 * s, 838 * s),
    ], BODY)

    # Door knocked out of the body.
    fill_polygon(buf, N, N, [
        (444 * s, 640 * s), (580 * s, 640 * s),
        (580 * s, 838 * s), (444 * s, 838 * s),
    ], DOOR)

    return buf


def downsample(master, size):
    """Box filter from the supersampled master to `size` px."""
    out = bytearray(size * size * 3)
    step = N / size
    for y in range(size):
        sy0, sy1 = int(y * step), int((y + 1) * step)
        for x in range(size):
            sx0, sx1 = int(x * step), int((x + 1) * step)
            r = g = b = n = 0
            for sy in range(sy0, sy1):
                base = sy * N * 3
                for sx in range(sx0, sx1):
                    o = base + sx * 3
                    r += master[o]
                    g += master[o + 1]
                    b += master[o + 2]
                    n += 1
            o = (y * size + x) * 3
            out[o] = r // n
            out[o + 1] = g // n
            out[o + 2] = b // n
    return out


def write_png(path, pixels, size):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw.extend(pixels[y * size * 3:(y + 1) * size * 3])

    def chunk(tag, data):
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


IMAGES = [
    ("iphone", "20x20", "2x", 40), ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58), ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80), ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120), ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20), ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29), ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40), ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76), ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    master = render_master()

    rendered = {}
    entries = []
    for idiom, size, scale, pixels in IMAGES:
        name = "icon-%d.png" % pixels
        if pixels not in rendered:
            write_png(os.path.join(OUT, name), downsample(master, pixels), pixels)
            rendered[pixels] = name
            print("wrote", name)
        entries.append({"filename": name, "idiom": idiom, "scale": scale, "size": size})

    with open(os.path.join(OUT, "Contents.json"), "w") as handle:
        json.dump({"images": entries, "info": {"author": "xcode", "version": 1}},
                  handle, indent=2)


if __name__ == "__main__":
    main()
