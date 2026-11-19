#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build InkKey's offline Chinese handwriting template set.

Input:
  Tools/_data/graphics.txt   Make Me a Hanzi stroke medians (LGPL/Arphic license,
                             https://github.com/skishore/makemeahanzi)

Output:
  Resources/handwriting.bin

Binary layout (little endian):
  magic   4 bytes  "IKHX"
  version UInt16   1
  points   UInt8   POINTS_PER_STROKE (6)
  reserved UInt8   0
  count    UInt32  number of characters
  records  count * 16 bytes:
      codepoint  UInt32
      strokes    UInt8
      aspect     UInt8   (width / height * 50, clamped to 255)
      direction  UInt8   (first stroke direction, 0-7, in 45° steps)
      quadrant   UInt8   (first stroke start: bit0 right half, bit1 bottom half)
      offset     UInt32  (index into the point block, in points)
      reserved2  UInt32
  points   count blocks of strokes*POINTS_PER_STROKE, each point 2 bytes (x, y)
           quantised to 0-255 inside the character box, y already flipped for
           UIKit (top-left origin).

Every stroke is resampled to exactly POINTS_PER_STROKE points along its own
arc length, so a character occupies strokes*6*2 bytes: ~110 bytes on average,
about 750 KB for 6,700+ characters.  The keyboard reads this file memory-mapped
and never parses it into objects.
"""
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "_data")
DICT = os.path.abspath(os.path.join(HERE, "..", "Resources", "dictionary.tsv"))
OUT = os.path.abspath(os.path.join(HERE, "..", "Resources", "handwriting.bin"))

POINTS_PER_STROKE = 6
MIN_FREQ = 10           # single characters kept from the jieba frequency list
BOX = 255.0


def resample(points, n):
    """Uniform arc-length resampling of a polyline to exactly n points."""
    pts = [(float(p[0]), float(p[1])) for p in points]
    if not pts:
        return [(0.0, 0.0)] * n
    if len(pts) == 1:
        return [pts[0]] * n
    dists = [0.0]
    total = 0.0
    for i in range(1, len(pts)):
        d = math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
        total += d
        dists.append(total)
    if total <= 1e-6:
        return [pts[0]] * n
    out = []
    step = total / (n - 1)
    target = 0.0
    seg = 1
    for k in range(n):
        target = step * k
        while seg < len(dists) and dists[seg] < target:
            seg += 1
        if seg >= len(dists):
            out.append(pts[-1])
            continue
        d0, d1 = dists[seg - 1], dists[seg]
        t = 0.0 if d1 - d0 <= 1e-9 else (target - d0) / (d1 - d0)
        x = pts[seg - 1][0] + (pts[seg][0] - pts[seg - 1][0]) * t
        y = pts[seg - 1][1] + (pts[seg][1] - pts[seg - 1][1]) * t
        out.append((x, y))
    return out


def normalize(strokes):
    """Fit every stroke of one character into the 0-255 box, keeping aspect."""
    xs = [p[0] for s in strokes for p in s]
    ys = [p[1] for s in strokes for p in s]
    if not xs:
        return [], 1.0
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    w = max(maxx - minx, 1.0)
    h = max(maxy - miny, 1.0)
    scale = (BOX - 8.0) / max(w, h)
    cx = (minx + maxx) / 2.0
    cy = (miny + maxy) / 2.0
    out = []
    for stroke in strokes:
        placed = []
        for x, y in stroke:
            nx = (x - cx) * scale + BOX / 2.0
            ny = BOX / 2.0 - (y - cy) * scale          # flip to UIKit's y-down
            placed.append((min(BOX, max(0.0, nx)), min(BOX, max(0.0, ny))))
        out.append(placed)
    return out, w / h


def first_stroke_features(stroke):
    (x0, y0), (x1, y1) = stroke[0], stroke[-1]
    dx, dy = x1 - x0, y1 - y0
    angle = math.atan2(dy, dx)
    direction = int(round(angle / (math.pi / 4.0))) % 8
    quadrant = (1 if x0 > BOX / 2 else 0) | (2 if y0 > BOX / 2 else 0)
    return direction, quadrant


def dictionary_chars():
    chars = set()
    with open(DICT, encoding="utf-8") as fh:
        header = fh.readline().split("\t")
        if len(header) < 2 or header[0] != "v2":
            sys.exit("dictionary.tsv is not v2 — build the dictionary first")
        count = int(header[1])
        for i, line in enumerate(fh):
            if i >= count:
                break
            word = line.split("\t", 1)[0]
            if len(word) == 1:
                chars.add(word)
    return chars


def jieba_single_chars():
    freq = {}
    path = os.path.join(DATA, "jieba_dict.txt")
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 2 or len(parts[0]) != 1:
                continue
            try:
                n = int(parts[1])
            except ValueError:
                continue
            if n > freq.get(parts[0], 0):
                freq[parts[0]] = n
    return freq


def main():
    wanted = set(dictionary_chars())
    freq = jieba_single_chars()
    wanted |= {ch for ch, n in freq.items() if n >= MIN_FREQ}

    records = []
    points = []
    with open(os.path.join(DATA, "graphics.txt"), encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except ValueError:
                continue
            ch = item.get("character") or ""
            medians = item.get("medians") or []
            if len(ch) != 1 or ch not in wanted:
                continue
            strokes = [s for s in medians if s]
            if not strokes or len(strokes) > 33:
                continue
            placed, aspect = normalize(strokes)
            if not placed:
                continue
            offset = len(points)
            for stroke in placed:
                points.extend(resample(stroke, POINTS_PER_STROKE))
            direction, quadrant = first_stroke_features(placed[0])
            records.append((
                ord(ch),
                len(placed),
                max(1, min(255, int(round(aspect * 50)))),
                direction,
                quadrant,
                offset,
            ))

    # The recogniser walks this file linearly, but a codepoint order keeps the
    # file stable between builds (nice diffs, easy lookup while debugging).
    records.sort(key=lambda r: r[0])

    # offsets are only meaningful once the order is final
    cursor = 0
    fixed = []
    for cp, strokes, aspect, direction, quadrant, _ in records:
        fixed.append((cp, strokes, aspect, direction, quadrant, cursor))
        cursor += strokes * POINTS_PER_STROKE

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as fh:
        fh.write(b"IKHX")
        fh.write(struct.pack("<HBB", 1, POINTS_PER_STROKE, 0))
        fh.write(struct.pack("<I", len(fixed)))
        for cp, strokes, aspect, direction, quadrant, offset in fixed:
            fh.write(struct.pack("<IBBBBI", cp, strokes, aspect, direction, quadrant, offset))
            fh.write(struct.pack("<I", 0))
        for x, y in points:
            fh.write(struct.pack("<BB", max(0, min(255, int(round(x)))),
                                 max(0, min(255, int(round(y))))))

    size = os.path.getsize(OUT)
    print(f"characters={len(fixed)} points={len(points)} bytes={size} ({size/1024:.0f} KB)")
    print("sample:", [(chr(cp), strokes) for cp, strokes, *_ in fixed[:6]])
    print("stroke buckets:",
          sorted({s: sum(1 for r in fixed if r[1] == s) for s in range(1, 34)}.items())[:12])


if __name__ == "__main__":
    main()
