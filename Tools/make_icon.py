#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Draw InkKey's 1024x1024 AppIcon (RGB, no alpha): an ink-wash ensō with a
3x3 T9 dot grid inside and a small red seal.  Pure Pillow, deterministic-ish."""

import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
SCALE = 2
W = SIZE * SCALE
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..",
                                   "InkKey", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"))

PAPER = (243, 238, 228)
PAPER_DARK = (228, 220, 205)
INK = (28, 27, 25)
SEAL = (158, 43, 37)

random.seed(20261119)


def paper_background() -> Image.Image:
    img = Image.new("RGB", (W, W), PAPER)
    px = img.load()
    rnd = random.Random(7)
    # soft radial shading towards the edges
    for y in range(W):
        for x in range(0, W, 1):
            dx = (x - W / 2) / (W / 2)
            dy = (y - W / 2) / (W / 2)
            d = min(1.0, math.sqrt(dx * dx + dy * dy) / 1.35)
            t = d ** 2
            r = int(PAPER[0] * (1 - t) + PAPER_DARK[0] * t)
            g = int(PAPER[1] * (1 - t) + PAPER_DARK[1] * t)
            b = int(PAPER[2] * (1 - t) + PAPER_DARK[2] * t)
            if rnd.random() < 0.02:
                n = rnd.randint(-8, 6)
                r, g, b = r + n, g + n, b + n
            px[x, y] = (max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    return img


def brush_enso(size: int) -> Image.Image:
    """A ring of overlapping blobs with varying pressure plus ink-density noise
    and a few bristle streaks — reads as a wet brush stroke, not a donut."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy = size / 2, size / 2
    radius = size * 0.315
    rnd = random.Random(3)
    start = math.radians(-32)
    end = math.radians(316)
    steps = 420
    for i in range(steps):
        t = i / (steps - 1)
        angle = start + (end - start) * t
        pressure = 0.32 + 0.68 * math.sin(math.pi * min(1.0, t * 1.04)) ** 0.6
        # dry-brush gaps near the tail
        dryness = 1.0
        if t > 0.9:
            dryness = max(0.25, 1.0 - (t - 0.9) * 6.0 * rnd.random())
        wobble = math.sin(t * math.pi * 4.3) * size * 0.009 + rnd.uniform(-1, 1) * size * 0.003
        r = radius + wobble
        x = cx + math.cos(angle) * r
        y = cy + math.sin(angle) * r
        blob = size * (0.014 + 0.034 * pressure)
        alpha = int((120 + 120 * pressure) * dryness)
        # bristle spread perpendicular to the stroke
        for k in range(4):
            off = (k - 1.5) * blob * 0.55
            bx = x + math.cos(angle) * off
            by = y + math.sin(angle) * off
            rr = blob * (0.85 if k in (0, 3) else 1.0)
            draw.ellipse([bx - rr, by - rr, bx + rr, by + rr],
                         fill=(INK[0], INK[1], INK[2], max(0, min(255, alpha - k * 12))))
    # ink density noise, keeps the wash uneven
    noise = Image.new("L", (48, 48))
    nrnd = random.Random(11)
    noise.putdata([nrnd.randint(120, 255) for _ in range(48 * 48)])
    noise = noise.resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(size * 0.012))
    alpha_channel = layer.split()[3]
    denser = ImageChops.multiply(alpha_channel, noise)
    layer.putalpha(denser)
    return layer.filter(ImageFilter.GaussianBlur(size * 0.0025))


def dot_grid(size: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy = size / 2, size / 2
    step = size * 0.115
    r = size * 0.026
    for row in range(3):
        for col in range(3):
            x = cx + (col - 1) * step
            y = cy + (row - 1) * step
            if row == 1 and col == 1:
                draw.ellipse([x - r * 1.25, y - r * 1.25, x + r * 1.25, y + r * 1.25],
                             fill=(SEAL[0], SEAL[1], SEAL[2], 255))
            else:
                draw.ellipse([x - r, y - r, x + r, y + r],
                             fill=(INK[0], INK[1], INK[2], 235))
    return layer.filter(ImageFilter.GaussianBlur(size * 0.0018))


def seal(size: int) -> Image.Image:
    """A red carved seal with a white 九, slightly worn."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    box = size * 0.20
    x0 = size * 0.655
    y0 = size * 0.655
    draw.rounded_rectangle([x0, y0, x0 + box, y0 + box],
                           radius=box * 0.12,
                           fill=(SEAL[0], SEAL[1], SEAL[2], 246))
    # carved character
    font_path = "/usr/share/fonts/pickle-hwp/NotoSansCJKkr-Regular.otf"
    glyph_size = int(box * 0.74)
    try:
        font = ImageFont.truetype(font_path, glyph_size)
        text = "九"
        bbox = draw.textbbox((0, 0), text, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        tx = x0 + (box - tw) / 2 - bbox[0]
        ty = y0 + (box - th) / 2 - bbox[1]
        draw.text((tx, ty), text, font=font, fill=(PAPER[0], PAPER[1], PAPER[2], 248))
    except Exception:
        m = box * 0.22
        draw.line([x0 + m, y0 + m, x0 + box - m, y0 + m], fill=PAPER + (240,), width=int(box * 0.08))
        draw.line([x0 + box * 0.5, y0 + m, x0 + box * 0.36, y0 + box - m], fill=PAPER + (240,), width=int(box * 0.08))
    # worn stamp edges
    wrnd = random.Random(21)
    for _ in range(26):
        px = x0 + wrnd.uniform(0, box)
        py = y0 + wrnd.uniform(0, box)
        r = wrnd.uniform(box * 0.01, box * 0.03)
        draw.ellipse([px - r, py - r, px + r, py + r],
                     fill=(PAPER[0], PAPER[1], PAPER[2], wrnd.randint(40, 120)))
    return layer.filter(ImageFilter.GaussianBlur(size * 0.0012))


def main():
    base = paper_background().convert("RGBA")
    base.alpha_composite(brush_enso(W))
    base.alpha_composite(dot_grid(W))
    base.alpha_composite(seal(W))
    # gentle warm highlight top-left
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-W * 0.25, -W * 0.35, W * 0.7, W * 0.55], fill=(255, 252, 244, 46))
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.09))
    base.alpha_composite(glow)

    icon = base.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    icon.save(OUT, "PNG")
    print("wrote", OUT, icon.size, icon.mode)


if __name__ == "__main__":
    main()
