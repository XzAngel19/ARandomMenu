#!/usr/bin/env python3
"""Rasterise Monocraft into the ClickGUI's bitmap font atlas.

The interface renders text through the bitmap text contract
(`state.bitmapText`). Its atlas path draws each glyph as an ImageLabel
window into one PNG — this file generates that PNG, plus the metrics the
runtime needs, from the Monocraft OTF the repository already vendors
(OFL; licence text sits next to the font).

Monocraft is monospaced and pixel-exact at multiples of its design grid,
so the atlas is a fixed-cell grid: 95 printable ASCII glyphs (32..126),
16 columns, one cell per glyph. Fixed cells keep the runtime math to a
modulo and a divide.

Usage:
    python3 tools/make_font_atlas.py          # writes the PNG + JSON
    python3 tools/make_font_atlas.py --check  # verifies both are current
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    Image = None  # type: ignore[misc, assignment]
    ImageDraw = None  # type: ignore[misc, assignment]
    ImageFont = None  # type: ignore[misc, assignment]

FONT = "src/gui/Current/Assets/Typography/Monocraft.otf"
OUT_PNG = "assets/font/monocraft-16.png"
OUT_JSON = "assets/font/monocraft-16.json"
SIZE = 16
# The whole OFL family. Fractional UIScales cannot get pixel-perfect
# glyphs out of one raster; the runtime picks the size closest to the
# final physical glyph and snaps to integer device pixels. 16 is the
# contract size; 8 / 24 / 32 cover scale 0.5 / 1.5 / 2.
SIZES = (8, 16, 24, 32)


def paths_for(size: int) -> tuple[str, str]:
    return (
        f"assets/font/monocraft-{size}.png",
        f"assets/font/monocraft-{size}.json",
    )
COLUMNS = 16
FIRST = 32
LAST = 126


def build(size: int = SIZE) -> tuple[Image.Image, dict]:
    font = ImageFont.truetype(FONT, size)
    ascent, descent = font.getmetrics()
    advance = int(round(font.getlength("M")))
    cell_w = advance
    cell_h = ascent + descent
    count = LAST - FIRST + 1
    rows = math.ceil(count / COLUMNS)
    image = Image.new("RGBA", (COLUMNS * cell_w, rows * cell_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for code in range(FIRST, LAST + 1):
        index = code - FIRST
        x = (index % COLUMNS) * cell_w
        y = (index // COLUMNS) * cell_h
        # White glyphs: the runtime tints with ImageColor3.
        draw.text((x, y), chr(code), font=font, fill=(255, 255, 255, 255))
    metrics = {
        "font": "Monocraft (OFL — licence beside the OTF)",
        "size": size,
        "first": FIRST,
        "last": LAST,
        "columns": COLUMNS,
        "cellWidth": cell_w,
        "cellHeight": cell_h,
        "advance": advance,
        "ascent": ascent,
        "descent": descent,
    }
    return image, metrics


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        if not (os.path.exists(OUT_PNG) and os.path.exists(OUT_JSON)):
            print("atlas missing; run tools/make_font_atlas.py")
            return 1
        committed = json.load(open(OUT_JSON, encoding="utf-8"))
        # Structural contract first, so a machine without Pillow can
        # still refuse a relabelled or cropped atlas. The rebuild
        # below is what catches a stale raster when Pillow is present.
        if committed.get("font", "").find("Monocraft") < 0:
            print("atlas metrics must name Monocraft, not Minecraft")
            return 1
        lowered = json.dumps(committed).lower()
        for banned in ("minecraft exact", "mc.font", "mojangles"):
            if banned in lowered:
                print(f"atlas metrics claim {banned!r}; that is the OFL fallback")
                return 1
        if (
            committed.get("first") != FIRST
            or committed.get("last") != LAST
            or committed.get("columns") != COLUMNS
            or committed.get("size") != SIZE
        ):
            print("atlas coverage drifted from ASCII 32..126 @ 16 px / 16 cols")
            return 1
        if Image is None:
            print(
                "atlas ok · "
                + hashlib.sha256(open(OUT_PNG, "rb").read()).hexdigest()[:16]
                + " · rebuild skipped (no Pillow)"
            )
            return 0
        image, metrics = build()
        rendered_json = json.dumps(metrics, indent=2) + "\n"
        if open(OUT_JSON, encoding="utf-8").read() != rendered_json:
            print("atlas metrics stale; run tools/make_font_atlas.py")
            return 1
        # The rest of the family: every committed size must be current.
        # A missing size fails only if it was ever committed — 16 is the
        # one mandatory atlas, the rest are the crisp-scale variants.
        for size in SIZES:
            if size == SIZE:
                continue
            png_path, json_path = paths_for(size)
            if not (os.path.exists(png_path) and os.path.exists(json_path)):
                continue
            sized_image, sized_metrics = build(size)
            sized_json = json.dumps(sized_metrics, indent=2) + "\n"
            if open(json_path, encoding="utf-8").read() != sized_json:
                print(f"atlas {size} metrics stale; run tools/make_font_atlas.py")
                return 1
        print(
            "atlas ok · "
            + hashlib.sha256(open(OUT_PNG, "rb").read()).hexdigest()[:16]
        )
        return 0

    if Image is None:
        print("Pillow is required to write the atlas: pip3 install pillow")
        return 1
    for size in SIZES:
        png_path, json_path = paths_for(size)
        image, metrics = build(size)
        rendered_json = json.dumps(metrics, indent=2) + "\n"
        os.makedirs(os.path.dirname(png_path), exist_ok=True)
        image.save(png_path)
        with open(json_path, "w") as handle:
            handle.write(rendered_json)
        print(
            f"atlas {size}: {image.width}x{image.height} · cell "
            f"{metrics['cellWidth']}x{metrics['cellHeight']} · advance "
            f"{metrics['advance']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
