#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render a pixel-accurate mock of the InkKey keyboard using the same metrics
as KeyboardView.swift, so the layout can be reviewed without Xcode.

Writes docs/keyboard-preview.png (1179x1020 = iPhone 15 width @3x).
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 3  # @3x
W, H = 393, 369
WIDTH, HEIGHT = W * S, H * S

PAPER = (247, 243, 236)
PAPER_DEEP = (236, 230, 219)
KEY_FILL = (254, 253, 251)
KEY_PRESSED = (229, 225, 217)
KEY_STROKE = (201, 196, 186)
INK = (33, 32, 30)
INK_SOFT = (90, 87, 81)
SEAL = (165, 43, 37)
SECONDARY = (111, 106, 98)
CAND_BG = (241, 237, 229)
DIVIDER = (213, 208, 199)

CJK = "/usr/share/fonts/pickle-hwp/NotoSansCJKkr-Regular.otf"
CJK_BOLD = "/usr/share/fonts/pickle-hwp/NotoSansCJKkr-Regular.otf"

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "docs", "keyboard-preview.png"))


def font(size_pt, path=CJK):
    return ImageFont.truetype(path, int(size_pt * S))


def text(draw, xy, value, size_pt, fill, anchor="mm", path=CJK):
    draw.text(xy, value, font=font(size_pt, path), fill=fill, anchor=anchor)


def rounded(draw, box, radius, fill, outline=None, width=0):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def key(draw, x, y, w, h, label=None, sub=None, size=18, function=False, image=None):
    box = [x, y, x + w, y + h]
    shadow = Image.new("RGBA", (int(w) + 20, int(h) + 20), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    rounded(sd, [10, 10, w + 10, h + 10], 8 * S, (0, 0, 0, 45))
    shadow = shadow.filter(ImageFilter.GaussianBlur(2 * S))
    draw._image.paste(shadow, (int(x) - 10, int(y) - 10), shadow)
    rounded(draw, box, 8 * S, KEY_PRESSED if function else KEY_FILL, KEY_STROKE, max(1, S // 2))
    if image == "delete":
        cx, cy = x + w / 2, y + h / 2
        d = 9 * S
        draw.rounded_rectangle([cx - d, cy - d * 0.62, cx + d * 0.45, cy + d * 0.62],
                               radius=3 * S, outline=INK, width=2 * S)
        draw.line([cx - d * 0.5, cy - d * 0.42, cx + d * 0.05, cy + d * 0.42], fill=INK, width=2 * S)
        draw.line([cx - d * 0.5, cy + d * 0.42, cx + d * 0.05, cy - d * 0.42], fill=INK, width=2 * S)
    elif image == "globe":
        cx, cy, r = x + w / 2, y + h / 2, 9 * S
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK, width=2 * S)
        draw.ellipse([cx - r * 0.45, cy - r, cx + r * 0.45, cy + r], outline=INK, width=max(1, S // 2))
        draw.line([cx - r, cy, cx + r, cy], fill=INK, width=max(1, S // 2))
    else:
        text(draw, (x + w / 2, y + h / 2 + (1 if sub else 0) * S), label or "", size, INK)
    if sub:
        text(draw, (x + w - 8 * S, y + 9 * S), sub, 9, SECONDARY)


def main():
    img = Image.new("RGB", (WIDTH, HEIGHT), PAPER)
    draw = ImageDraw.Draw(img)
    draw._image = img
    # vertical gradient
    for i in range(HEIGHT):
        t = i / HEIGHT
        c = tuple(int(PAPER_DEEP[k] * (1 - t) + PAPER[k] * t) for k in range(3))
        draw.line([(0, i), (WIDTH, i)], fill=c)

    margin = 5 * S
    gap = 6 * S
    content_w = WIDTH - margin * 2

    # candidate strip (height 80)
    cand_h = 80 * S
    top = 5 * S
    rounded(draw, [margin, top, margin + content_w, top + cand_h], 8 * S, CAND_BG, DIVIDER, max(1, S // 2))
    badge_w = 40 * S
    bx = margin + 7 * S
    rounded(draw, [bx, top + 8 * S, bx + badge_w, top + cand_h - 8 * S], 6 * S, KEY_FILL)
    text(draw, (bx + badge_w / 2, top + 26 * S), "中", 15, SEAL)
    text(draw, (bx + badge_w / 2, top + 52 * S), "9663", 9, SECONDARY)

    candidates = [
        ("我们", "wo men", "we; us"),
        ("握", "wo", "to hold"),
        ("窝", "wo", "nest"),
        ("卧", "wo", "to lie down"),
    ]
    cx = bx + badge_w + 8 * S
    for index, (word, pinyin, english) in enumerate(candidates):
        cw = min(150 * S, 96 * S + len(english) * 3 * S)
        m = 3 * S
        if index == 0:
            rounded(draw, [cx, top + m, cx + cw, top + cand_h - m], 7 * S, KEY_FILL, (SEAL[0], SEAL[1], SEAL[2], 90), S)
        text(draw, (cx + 8 * S, top + 18 * S), pinyin, 9, SECONDARY, anchor="lm")
        text(draw, (cx + 8 * S, top + 40 * S), word, 21, INK, anchor="lm")
        text(draw, (cx + 8 * S, top + 62 * S), english, 11, SECONDARY, anchor="lm")
        sx = cx + cw - 14 * S
        draw.polygon([(sx - 5 * S, top + 62 * S), (sx - 5 * S, top + 68 * S), (sx + 1 * S, top + 65 * S)], fill=SEAL)
        draw.arc([sx + 1 * S, top + 60 * S, sx + 7 * S, top + 70 * S], -60, 60, fill=SEAL, width=max(1, S // 2))
        cx += cw + gap

    # keys area
    # editing toolbar (height 26) — 粘贴 / 复制 / 剪切 / 清空 / 换行 + 手写
    edit_top = top + cand_h + 3 * S
    edit_h = 26 * S
    toggle_w = 62 * S
    action_w = (content_w - gap * 5 - toggle_w) / 5
    ex = margin
    for label in ["粘贴", "复制", "剪切", "清空", "换行"]:
        rounded(draw, [ex, edit_top, ex + action_w, edit_top + edit_h], 6 * S, KEY_FILL, DIVIDER, max(1, S // 2))
        text(draw, (ex + action_w / 2, edit_top + edit_h / 2), label, 12, INK_SOFT)
        ex += action_w + gap
    tx = margin + content_w - toggle_w
    rounded(draw, [tx, edit_top, tx + toggle_w, edit_top + edit_h], 6 * S,
            (SEAL[0], SEAL[1], SEAL[2]), SEAL, max(1, S // 2))
    text(draw, (tx + toggle_w / 2, edit_top + edit_h / 2), "手写", 12, PAPER)

    keys_top = edit_top + edit_h + 4 * S
    keys_h = HEIGHT - keys_top - 6 * S
    unit = max(28 * S, (content_w - gap * 4) / 4.76)
    punct_w = unit * 0.86
    fn_w = unit * 0.90
    bottom_h = max(36 * S, (keys_h - gap * 3) * 0.19)
    row_h = max(34 * S, (keys_h - gap * 3 - bottom_h) / 3)

    # left punctuation block: four marks across the 3-row height
    punct_h = row_h * 3 + gap * 2
    marks = ["，", "。", "？", "！"]
    key_h = (punct_h - gap * 0.5 * 3) / 4
    for i, mark in enumerate(marks):
        key(draw, margin, keys_top + i * (key_h + gap * 0.5), punct_w, key_h, mark, size=21, function=True)

    # T9 grid
    grid_x = margin + punct_w + gap
    keys = [("1", "@#"), ("2", "ABC"), ("3", "DEF"),
            ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
            ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")]
    for index, (digit, letters) in enumerate(keys):
        row, col = divmod(index, 3)
        x = grid_x + col * (unit + gap)
        y = keys_top + row * (row_h + gap)
        key(draw, x, y, unit, row_h, letters, sub=digit, size=18)

    # function column
    fx = WIDTH - margin - fn_w
    key(draw, fx, keys_top, fn_w, row_h, image="delete", function=True)
    key(draw, fx, keys_top + row_h + gap, fn_w, row_h, "重输", size=15, function=True)
    key(draw, fx, keys_top + 2 * (row_h + gap), fn_w, row_h + gap + bottom_h, "换行", size=15, function=True)

    # bottom row
    by = keys_top + row_h * 3 + gap * 3
    key(draw, margin, by, punct_w, bottom_h, "符号", size=15, function=True)
    key(draw, margin + punct_w + gap, by, unit * 0.62, bottom_h, "123", size=15, function=True)
    space_x = margin + punct_w + gap + unit * 0.62 + gap
    space_w = (fx - gap) - space_x
    key(draw, space_x, by, space_w, bottom_h, "空格", size=14)
    mode_x = fx - gap - unit * 0.62
    key(draw, mode_x, by, unit * 0.62, bottom_h, None, function=True)
    text(draw, (mode_x + unit * 0.31, by + bottom_h * 0.32), "中", 13, SEAL)
    text(draw, (mode_x + unit * 0.31, by + bottom_h * 0.70), "英", 13, SECONDARY)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("wrote", OUT, img.size)


if __name__ == "__main__":
    main()
