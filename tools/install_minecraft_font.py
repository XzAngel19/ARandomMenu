#!/usr/bin/env python3
"""Install the Minecraft 1.18.1 font as a local pack the runtime can load.

One command, end to end, on a machine that can reach Mojang:

    python3 tools/install_minecraft_font.py --update
    python3 tools/install_minecraft_font.py --check

`--update` drives tools/fetch_minecraft_font.py --update (official
version manifest → client.jar, SHA1-verified against
assets/font/minecraft-1.18.1.manifest.json), reads the *real*
`assets/minecraft/font/default.json` out of the verified extract, and
processes the 1.18.1 provider stack:

  - bitmap `ascii.png` (ASCII, the runtime's working set);
  - bitmap `accented.png`;
  - bitmap `nonlatin_european.png` (written as `european.png`);
  - `legacy_unicode` is recorded (sizes/template) but its pages live in
    the asset objects CDN and are only fetched with `--unicode`.

For every bitmap provider it measures per-glyph advances the way
Minecraft's own BitmapProvider does — rightmost column holding any
alpha, +1; the empty U+0020 cell is the hard 4 — and records ascent and
the 9-pixel logical line. It also re-grids the ASCII glyphs 32..126
into the 16-column layout the Roblox renderer indexes
(`runtime-ascii.png`), so `state.bitmapText.loadExactAtlas` can use the
pack without translation.

Output (never committed — Mojang pixels stay out of Git):

    MinecraftFont/
      manifest.json      format wurst-minecraft-font-v1; hashes, metrics
      ascii.png          provider copies, reference layout
      accented.png
      european.png
      runtime-ascii.png  32..126 re-gridded for the runtime renderer

Copy that folder into the executor's workspace root; the runtime
verifies the manifest and flips the font source to `minecraft-exact`.
Without it the menu keeps rendering on the committed Monocraft
fallback, which is OFL and is never labelled Minecraft.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXTRACT = os.path.join(ROOT, "cache/minecraft-1.18.1/extract")
FONT_DIR = os.path.join(EXTRACT, "assets/minecraft/font")
TEXTURE_DIR = os.path.join(EXTRACT, "assets/minecraft/textures/font")
PIN = os.path.join(ROOT, "assets/font/minecraft-1.18.1.manifest.json")
DEFAULT_OUTPUT = os.path.join(ROOT, "cache/MinecraftFont")
SPACE_ADVANCE = 4
LINE_HEIGHT = 9  # Minecraft's logical line: 8-pixel glyphs on a 9-pixel line
SHADOW = {"offsetX": 1, "offsetY": 1, "colorFactor": 0.25}

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None  # type: ignore[assignment]


def sha1_of(path: str) -> str:
    return hashlib.sha1(open(path, "rb").read()).hexdigest()


def measure_provider(provider: dict, image: "Image.Image") -> dict:
    """Per-glyph advances, Minecraft's BitmapProvider rule."""
    chars: list[str] = provider.get("chars") or []
    rows = len(chars)
    columns = max((len(row) for row in chars), default=0)
    cell_w = image.width // max(columns, 1)
    cell_h = image.height // max(rows, 1)
    height = provider.get("height", 8)
    ascent = provider.get("ascent")
    scale = height / cell_h if cell_h else 1
    pixels = image.convert("RGBA").load()
    advances: dict[str, int] = {}
    for row_index, row in enumerate(chars):
        for col_index, char in enumerate(row):
            if char == "\u0000":
                continue
            if char == " ":
                advances[char] = SPACE_ADVANCE
                continue
            x0, y0 = col_index * cell_w, row_index * cell_h
            width = 0
            for dx in range(cell_w - 1, -1, -1):
                if any(pixels[x0 + dx, y0 + dy][3] != 0 for dy in range(cell_h)):
                    width = dx + 1
                    break
            advances[char] = int(0.5 + width * scale) + 1
    return {
        "rows": rows,
        "columns": columns,
        "cellWidth": cell_w,
        "cellHeight": cell_h,
        "height": height,
        "ascent": ascent,
        "advances": advances,
    }


def regrid_ascii(provider: dict, image: "Image.Image", measured: dict) -> "Image.Image":
    """32..126 in the 16-column grid the Roblox renderer indexes."""
    chars: list[str] = provider["chars"]
    cell_w, cell_h = measured["cellWidth"], measured["cellHeight"]
    position: dict[str, tuple[int, int]] = {}
    for row_index, row in enumerate(chars):
        for col_index, char in enumerate(row):
            if char not in position:
                position[char] = (col_index * cell_w, row_index * cell_h)
    count = 126 - 32 + 1
    rows = (count + 15) // 16
    out = Image.new("RGBA", (16 * cell_w, rows * cell_h), (0, 0, 0, 0))
    missing = []
    for code in range(32, 127):
        char = chr(code)
        if char not in position:
            missing.append(char)
            continue
        sx, sy = position[char]
        index = code - 32
        out.paste(
            image.crop((sx, sy, sx + cell_w, sy + cell_h)),
            ((index % 16) * cell_w, (index // 16) * cell_h),
        )
    if missing:
        raise SystemExit(
            "ascii.png is missing printable ASCII glyphs: " + "".join(missing)
            + " — the extract is not 1.18.1's ascii.png"
        )
    return out


def run_update(output: str, unicode_pages: bool) -> int:
    if Image is None:
        print("Pillow is required: pip3 install pillow", file=sys.stderr)
        return 1
    default_json = os.path.join(FONT_DIR, "default.json")
    if not os.path.exists(default_json):
        print("no verified extract; running tools/fetch_minecraft_font.py --update")
        result = subprocess.run(
            [sys.executable, os.path.join(ROOT, "tools/fetch_minecraft_font.py"), "--update"],
            check=False,
        )
        if result.returncode != 0:
            print(
                "fetch failed — run this on a machine that reaches "
                "piston-data.mojang.com; nothing was written",
                file=sys.stderr,
            )
            return 1
    if not os.path.exists(default_json):
        print(f"extract incomplete: {default_json} missing", file=sys.stderr)
        return 1

    pin = json.load(open(PIN, encoding="utf-8"))
    providers = json.load(open(default_json, encoding="utf-8"))["providers"]
    os.makedirs(output, exist_ok=True)
    out_files: dict[str, dict] = {}
    manifest_providers: list[dict] = []
    runtime: dict | None = None

    friendly = {
        "minecraft:font/ascii.png": "ascii.png",
        "minecraft:font/accented.png": "accented.png",
        "minecraft:font/nonlatin_european.png": "european.png",
    }

    for index, provider in enumerate(providers):
        kind = provider.get("type")
        record: dict = {"index": index, "type": kind}
        if kind == "bitmap":
            reference = provider["file"]
            source = os.path.join(TEXTURE_DIR, os.path.basename(reference))
            if not os.path.exists(source):
                print(f"provider texture missing from extract: {source}", file=sys.stderr)
                return 1
            image = Image.open(source)
            measured = measure_provider(provider, image)
            local = friendly.get(reference, os.path.basename(reference))
            target = os.path.join(output, local)
            image.save(target)
            out_files[local] = {"sha1": sha1_of(target)}
            record.update({"file": reference, "texture": local, **measured})
            if reference == "minecraft:font/ascii.png":
                regridded = regrid_ascii(provider, image, measured)
                runtime_png = os.path.join(output, "runtime-ascii.png")
                regridded.save(runtime_png)
                out_files["runtime-ascii.png"] = {"sha1": sha1_of(runtime_png)}
                advances_by_code = {
                    str(ord(char)): value
                    for char, value in measured["advances"].items()
                    if 32 <= ord(char) <= 126
                }
                runtime = {
                    "image": "runtime-ascii.png",
                    "size": measured["height"],
                    "first": 32,
                    "last": 126,
                    "columns": 16,
                    "cellWidth": measured["cellWidth"],
                    "cellHeight": measured["cellHeight"],
                    "advance": 6,
                    "advances": advances_by_code,
                    "ascent": measured["ascent"],
                    "lineHeight": LINE_HEIGHT,
                    "shadow": SHADOW,
                }
            print(f"bitmap {reference}: {measured['rows']}x{measured['columns']} cells → {local}")
        elif kind == "legacy_unicode":
            record["sizes"] = provider.get("sizes")
            record["template"] = provider.get("template")
            if unicode_pages:
                print(
                    "legacy_unicode pages live in the asset-objects CDN; "
                    "fetching them is not implemented here — recorded only",
                    file=sys.stderr,
                )
            else:
                print("legacy_unicode: recorded (pages skipped; ASCII covers the GUI)")
        else:
            record["raw"] = provider
            print(f"unhandled provider type {kind!r}: recorded verbatim")
        manifest_providers.append(record)

    if runtime is None:
        print("default.json declared no ascii.png bitmap provider — refusing", file=sys.stderr)
        return 1

    manifest = {
        "format": "wurst-minecraft-font-v1",
        "game": "Minecraft",
        "version": "1.18.1",
        "clientJarSha1": pin["official"]["clientJarSha1"]
        if "official" in pin
        else pin.get("clientJarSha1"),
        "lineHeight": LINE_HEIGHT,
        "shadow": SHADOW,
        "providers": manifest_providers,
        "runtime": runtime,
        "files": out_files,
    }
    manifest_path = os.path.join(output, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"wrote {manifest_path}")
    print("copy the MinecraftFont folder into the executor workspace root;")
    print("do not commit it — Mojang pixels stay out of Git")
    return 0


def run_check(output: str) -> int:
    manifest_path = os.path.join(output, "manifest.json")
    if not os.path.exists(manifest_path):
        print(f"--check: {manifest_path} does not exist; run --update first", file=sys.stderr)
        return 1
    manifest = json.load(open(manifest_path, encoding="utf-8"))
    if manifest.get("format") != "wurst-minecraft-font-v1":
        print("manifest format is not wurst-minecraft-font-v1", file=sys.stderr)
        return 1
    failures = []
    for name, record in manifest.get("files", {}).items():
        path = os.path.join(output, name)
        if not os.path.exists(path):
            failures.append(f"missing {name}")
        elif sha1_of(path) != record["sha1"]:
            failures.append(f"hash drift in {name}")
    if failures:
        print("pack check failed:\n  " + "\n  ".join(failures), file=sys.stderr)
        return 1
    print(f"pack ok: {len(manifest.get('files', {}))} files verified · Minecraft "
          f"{manifest.get('version')} · runtime atlas {manifest['runtime']['image']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--update", action="store_true", help="build the pack from official sources")
    group.add_argument("--check", action="store_true", help="verify a built pack and exit")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="pack directory (kept out of Git)")
    parser.add_argument("--unicode", action="store_true", help="also record legacy unicode pages")
    args = parser.parse_args()
    if os.path.commonpath([os.path.abspath(args.output), os.path.join(ROOT, "assets")]) \
            == os.path.join(ROOT, "assets"):
        print("refusing to write Mojang pixels under assets/", file=sys.stderr)
        return 1
    if args.check:
        return run_check(args.output)
    return run_update(args.output, args.unicode)


if __name__ == "__main__":
    sys.exit(main())
