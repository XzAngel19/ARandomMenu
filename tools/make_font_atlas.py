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
    raise SystemExit(
        "Pillow is required: pip3 install --break-system-packages pillow"
    )

FONT = "src/gui/Current/Assets/Typography/Monocraft.otf"
OUT_PNG = "assets/font/monocraft-16.png"
OUT_JSON = "assets/font/monocraft-16.json"
SIZE = 16
COLUMNS = 16
FIRST = 32
LAST = 126


def build() -> tuple[Image.Image, dict]:
    font = ImageFont.truetype(FONT, SIZE)
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
        "size": SIZE,
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

    image, metrics = build()
    rendered_json = json.dumps(metrics, indent=2) + "\n"

    if args.check:
        if not (os.path.exists(OUT_PNG) and os.path.exists(OUT_JSON)):
            print("atlas missing; run tools/make_font_atlas.py")
            return 1
        if open(OUT_JSON).read() != rendered_json:
            print("atlas metrics stale; run tools/make_font_atlas.py")
            return 1
        print("atlas ok · " + hashlib.sha256(open(OUT_PNG, "rb").read()).hexdigest()[:16])
        return 0

    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    image.save(OUT_PNG)
    with open(OUT_JSON, "w") as handle:
        handle.write(rendered_json)
    print(
        f"atlas {image.width}x{image.height} · cell {metrics['cellWidth']}x"
        f"{metrics['cellHeight']} · advance {metrics['advance']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
