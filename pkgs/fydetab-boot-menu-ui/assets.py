#!/usr/bin/env python3
"""Build the font atlases and blurred background for the initrd boot menu.

Everything here is baked at build time so the initrd needs no freetype,
fontconfig, image decoders or other runtime dependencies.
"""

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FIRST = 32
LAST = 126

FONT_MAGIC = 0x464D4246  # "FBMF"
FONT_VERSION = 1

BG_MAGIC = 0x424D4246  # "FBMB"
BG_VERSION = 1


def build_font(ttf: Path, size: int, out: Path) -> None:
    font = ImageFont.truetype(str(ttf), size)
    ascent, descent = font.getmetrics()
    line_height = ascent + descent

    glyphs = []  # (advance_fp, xoff, yoff, w, h)
    images = []
    for code in range(FIRST, LAST + 1):
        ch = chr(code)
        advance = int(round(font.getlength(ch) * 16))
        x0, y0, x1, y1 = font.getbbox(ch, anchor="ls")
        w, h = max(0, x1 - x0), max(0, y1 - y0)
        glyphs.append((advance, x0, y0, w, h))
        if w == 0 or h == 0:
            images.append(None)
            continue
        img = Image.new("L", (w, h), 0)
        ImageDraw.Draw(img).text((-x0, -y0), ch, font=font, fill=255, anchor="ls")
        images.append(img)

    # Shelf packing; a single atlas texture keeps the loader trivial.
    atlas_w = 1024
    pos = []
    x = y = row_h = 0
    for img in images:
        if img is None:
            pos.append((0, 0))
            continue
        if x + img.width > atlas_w:
            x = 0
            y += row_h
            row_h = 0
        pos.append((x, y))
        x += img.width + 1
        row_h = max(row_h, img.height)
    atlas_h = y + row_h

    atlas = Image.new("L", (atlas_w, atlas_h), 0)
    for img, (ax, ay) in zip(images, pos):
        if img is not None:
            atlas.paste(img, (ax, ay))

    header = struct.pack(
        "<10I",
        FONT_MAGIC,
        FONT_VERSION,
        size,
        ascent,
        descent,
        line_height,
        FIRST,
        LAST - FIRST + 1,
        atlas_w,
        atlas_h,
    )
    table = b"".join(
        struct.pack("<iiiiIII", adv, xoff, yoff, w, h, ax, ay)
        for (adv, xoff, yoff, w, h), (ax, ay) in zip(glyphs, pos)
    )
    out.write_bytes(header + table + atlas.tobytes())


def build_background(theme: Path, out: Path) -> None:
    # Compose the splash artwork the way the Plymouth theme does: snowflake and
    # wordmark side by side, spinner below. Render it large, blur it hard, then
    # downscale, so the runtime upscale is nearly free.
    cw, ch = 1600, 1000
    canvas = Image.new("RGB", (cw, ch), (0, 0, 0))

    def load(name: str, scale: float) -> Image.Image:
        img = Image.open(theme / name).convert("RGBA")
        return img.resize(
            (max(1, int(img.width * scale)), max(1, int(img.height * scale))),
            Image.LANCZOS,
        )

    snow = load("nix-snowflake.png", 2.0)
    word = load("fydetab-wordmark.png", 2.0)
    spinner = load("spinner/animation-0001.png", 4.0)

    gap = 56
    total = snow.width + gap + word.width
    x = (cw - total) // 2
    block_h = max(snow.height, word.height)
    y = int(ch * 0.18) - block_h // 2
    canvas.paste(snow, (x, y + (block_h - snow.height) // 2), snow)
    canvas.paste(word, (x + snow.width + gap, y + (block_h - word.height) // 2), word)
    canvas.paste(spinner, ((cw - spinner.width) // 2, y + block_h + 56), spinner)

    canvas = canvas.filter(ImageFilter.GaussianBlur(90))
    canvas = canvas.resize((cw * 2 // 5, ch * 2 // 5), Image.LANCZOS)

    # Pack as RGB565, little endian.
    w, h = canvas.size
    raw = bytearray()
    for r, g, b in canvas.getdata():
        raw += struct.pack("<H", ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))

    out.write_bytes(struct.pack("<4I", BG_MAGIC, BG_VERSION, w, h) + bytes(raw))


def build_brand(wordmark: Path, theme: Path, out: Path) -> None:
    """Compose the snowflake + wordmark lockup at the exact display size."""
    snow = Image.open(theme / "nix-snowflake.png").convert("RGBA")
    word = Image.open(wordmark).convert("RGBA")

    height = 80
    snow_h = height
    word_h = height
    word_w = int(round(word.width * word_h / word.height))
    gap = 28
    total_w = snow_h + gap + word_w

    # Compose at 4x, then downsample, so the final raster is properly filtered.
    scale = 4
    canvas = Image.new("RGBA", (total_w * scale, height * scale), (0, 0, 0, 255))
    s = snow.resize((snow_h * scale, snow_h * scale), Image.LANCZOS)
    w = word.resize((word_w * scale, word_h * scale), Image.LANCZOS)
    canvas.alpha_composite(s, (0, 0))
    canvas.alpha_composite(w, ((snow_h + gap) * scale, 0))
    canvas = canvas.convert("RGB").resize((total_w, height), Image.LANCZOS)

    raw = bytearray()
    for r, g, b in canvas.getdata():
        raw += struct.pack("<H", ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))
    out.write_bytes(struct.pack("<4I", BG_MAGIC, BG_VERSION, total_w, height) + bytes(raw))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--theme", type=Path, required=True)
    parser.add_argument("--fonts", type=Path, required=True)
    parser.add_argument("--wordmark", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    mono = args.fonts / "DejaVuSansMono.ttf"
    if not mono.exists():
        print(f"missing font: {mono}", file=sys.stderr)
        return 1

    build_font(mono, 27, args.out / "font-mono-27.bin")
    build_font(mono, 33, args.out / "font-mono-33.bin")
    build_font(mono, 44, args.out / "font-mono-44.bin")
    build_background(args.theme, args.out / "background.bin")
    build_brand(args.wordmark, args.theme, args.out / "brand.bin")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
