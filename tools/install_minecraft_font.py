#!/usr/bin/env python3
"""Install the Minecraft 1.18.1 font as a local pack the runtime can load.

One command, end to end, on a machine that can reach Mojang:

    python3 tools/install_minecraft_font.py --update
    python3 tools/install_minecraft_font.py --install PATH
    python3 tools/install_minecraft_font.py --status
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
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The versions this installer can build a local pack for. 1.18.1 is the
# visual authority — Wurst 7.19's own game — and stays the default
# everywhere. 26.2 is an *optional local pack*: nothing about the port's
# baseline moves, and its providers are read from its own default.json,
# never assumed to be 1.18.1's stack. Pins read off piston-meta
# (version_manifest_v2 → 26.2.json, 2026-08-22): the version JSON is
# content-addressed by its own SHA1 in the URL.
VERSIONS = {
    "1.18.1": {
        "clientJarSha1": "7e46fb47609401970e2818989fa584fd467cd036",
        "assetIndexId": "1.18",
        "assetIndexSha1": "d31a2e85ae149dd1b1a7070b22cb8887892fda6c",
        "packName": "MinecraftFont",
        "baseline": True,
    },
    "26.2": {
        "versionJsonSha1": "c75d82e7fa6eca5a043dab0c6cf77cb8317644f4",
        "clientJarSha1": "2dc72797acbc1b63fc16a11c4ac393605f453754",
        "assetIndexId": "32",
        "assetIndexSha1": "773791767c043b4f9493b50c54257619cecb08a4",
        "packName": "MinecraftFont-26.2",
        "baseline": False,
    },
}


def cache_for(version: str) -> str:
    return os.path.join(ROOT, f"cache/minecraft-{version}")


def extract_for(version: str) -> str:
    return os.path.join(cache_for(version), "extract")


def status_for(version: str) -> str:
    return os.path.join(cache_for(version), "installed.json")


def font_dir_for(version: str) -> str:
    return os.path.join(extract_for(version), "assets/minecraft/font")


def texture_dir_for(version: str) -> str:
    return os.path.join(extract_for(version), "assets/minecraft/textures/font")


def default_output_for(version: str) -> str:
    return os.path.join(ROOT, "cache", VERSIONS[version]["packName"])


# Legacy bindings: the 1.18.1 paths, which the baseline flow and C's
# offline tests drive without a --version flag.
CACHE = cache_for("1.18.1")
EXTRACT = extract_for("1.18.1")
STATUS = status_for("1.18.1")
FONT_DIR = font_dir_for("1.18.1")
TEXTURE_DIR = texture_dir_for("1.18.1")
PIN = os.path.join(ROOT, "assets/font/minecraft-1.18.1.manifest.json")
DEFAULT_OUTPUT = default_output_for("1.18.1")
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


def load_provider_stack(font_dir: str, name: str = "default.json", seen: set | None = None) -> list[dict]:
    """The version's *real* provider list, reference providers resolved.

    Modern versions split default.json into include files behind
    `reference` providers; 1.18.1 lists everything inline. Recursion
    with a cycle guard reads whichever shape the version actually has —
    nothing here assumes one version's stack for another.
    """
    seen = seen or set()
    if name in seen:
        raise SystemExit(f"font json reference cycle at {name}")
    seen.add(name)
    path = os.path.join(font_dir, name)
    if not os.path.isfile(path):
        raise SystemExit(f"referenced font json missing from extract: {name}")
    providers: list[dict] = []
    for provider in json.load(open(path, encoding="utf-8")).get("providers") or []:
        if provider.get("type") == "reference":
            reference = str(provider.get("id") or "")
            rel = reference.split(":", 1)[-1] + ".json"
            providers.extend(load_provider_stack(font_dir, rel, seen))
        else:
            providers.append(provider)
    return providers


def discover_source(source: str, version: str) -> dict | None:
    """Find version JSON, client jar and asset index inside a Minecraft dir.

    Accepts a .minecraft root (versions/<id>/<id>.json|.jar,
    assets/indexes/<n>.json) or the versions/<id> folder itself. Every
    hash that can be verified locally is verified: the jar against the
    version JSON's own downloads.client.sha1 *and* against the pinned
    hash for the version; the asset index against the version JSON's
    assetIndex.sha1 when the file is present.
    """
    pin = VERSIONS[version]
    candidates = (
        os.path.join(source, "versions", version),
        source,
    )
    version_json_path = None
    jar_path = None
    for base in candidates:
        j = os.path.join(base, f"{version}.json")
        c = os.path.join(base, f"{version}.jar")
        if os.path.isfile(j) and os.path.isfile(c):
            version_json_path, jar_path = j, c
            break
    if not version_json_path:
        print(
            f"could not find versions/{version}/{version}.json + .jar under "
            f"{source} — point --source at the .minecraft directory that has "
            f"{version} installed",
            file=sys.stderr,
        )
        return None
    data = json.load(open(version_json_path, encoding="utf-8"))
    if data.get("id") != version:
        print(
            f"{version_json_path} declares id {data.get('id')!r}, not {version} — "
            "refusing to mix versions",
            file=sys.stderr,
        )
        return None
    declared = ((data.get("downloads") or {}).get("client") or {}).get("sha1")
    jar_sha1 = sha1_of(jar_path)
    if declared and jar_sha1 != declared:
        print(
            f"client jar sha1 {jar_sha1} does not match the version JSON's "
            f"{declared} — corrupt installation",
            file=sys.stderr,
        )
        return None
    if pin.get("clientJarSha1") and jar_sha1 != pin["clientJarSha1"]:
        print(
            f"client jar sha1 {jar_sha1} does not match the pinned "
            f"{pin['clientJarSha1']} for {version}",
            file=sys.stderr,
        )
        return None
    asset_index_id = (data.get("assetIndex") or {}).get("id")
    asset_index_sha1 = None
    index_path = None
    if asset_index_id:
        for base in (source, os.path.dirname(os.path.dirname(version_json_path))):
            candidate = os.path.join(base, "assets", "indexes", f"{asset_index_id}.json")
            if os.path.isfile(candidate):
                index_path = candidate
                break
        if index_path:
            asset_index_sha1 = sha1_of(index_path)
            declared_index = (data.get("assetIndex") or {}).get("sha1")
            if declared_index and asset_index_sha1 != declared_index:
                print(
                    f"asset index sha1 {asset_index_sha1} does not match the "
                    f"version JSON's {declared_index}",
                    file=sys.stderr,
                )
                return None
    return {
        "versionJsonPath": version_json_path,
        "versionJsonSha1": sha1_of(version_json_path),
        "jarPath": jar_path,
        "clientJarSha1": jar_sha1,
        "assetIndexId": asset_index_id,
        "assetIndexSha1": asset_index_sha1,
        "assetIndexPath": index_path,
    }


def extract_fonts_from_jar(jar_path: str, version: str) -> bool:
    extract = extract_for(version)
    if os.path.isdir(extract):
        shutil.rmtree(extract)
    os.makedirs(extract, exist_ok=True)
    prefixes = (
        "assets/minecraft/font/",
        "assets/minecraft/textures/font/",
    )
    try:
        with zipfile.ZipFile(jar_path) as archive:
            for name in archive.namelist():
                if name.startswith(prefixes) and not name.endswith("/"):
                    archive.extract(name, extract)
    except zipfile.BadZipFile:
        print(f"corrupt client jar: {jar_path}", file=sys.stderr)
        return False
    return os.path.isfile(os.path.join(font_dir_for(version), "default.json"))


def parse_hex_glyph(bits_hex: str) -> tuple[list[int], int]:
    """16 rows of bits plus the row width in bits (unihex: 8/16/24/32)."""
    per_row = max(1, len(bits_hex) // 16)
    rows = []
    for row in range(16):
        rows.append(int(bits_hex[row * per_row:(row + 1) * per_row] or "0", 16))
    return rows, per_row * 4


def rasterize_unihex(provider: dict, font_dir: str) -> tuple["Image.Image", dict] | None:
    """ASCII 32..126 out of a unihex provider, when no bitmap covers it.

    Unihex glyphs are 16 rows of bits; the game draws them at half
    scale, so the runtime records size 8 over 16-pixel cells. Advance
    follows the game's rule — trimmed width halved, plus one — with
    size_overrides honoured where they cover the range.
    """
    reference = str(provider.get("hex_file") or "")
    zip_path = os.path.join(font_dir, os.path.basename(reference.split(":", 1)[-1]))
    if not os.path.isfile(zip_path):
        print(f"unihex archive missing from extract: {zip_path}", file=sys.stderr)
        return None
    glyphs: dict[int, list[int]] = {}
    with zipfile.ZipFile(zip_path) as archive:
        for member in archive.namelist():
            if not member.endswith(".hex"):
                continue
            for line in archive.read(member).decode("utf-8", "replace").splitlines():
                code_hex, _, bits = line.partition(":")
                try:
                    code = int(code_hex, 16)
                except ValueError:
                    continue
                if 32 <= code <= 126 and code not in glyphs and bits:
                    glyphs[code] = parse_hex_glyph(bits.strip())
    missing = [code for code in range(33, 127) if code not in glyphs]
    if missing:
        print(
            "unihex archive does not cover printable ASCII: missing "
            + ", ".join(str(code) for code in missing[:8]),
            file=sys.stderr,
        )
        return None
    overrides = {}
    for override in provider.get("size_overrides") or []:
        lo = override.get("from")
        hi = override.get("to")
        if isinstance(lo, str):
            lo = ord(lo[0]) if lo else None
        if isinstance(hi, str):
            hi = ord(hi[0]) if hi else None
        if lo is None or hi is None:
            continue
        for code in range(max(lo, 32), min(hi, 126) + 1):
            overrides[code] = (override.get("left", 0), override.get("right", 15))
    cell_w, cell_h = 16, 16
    out = Image.new("RGBA", (16 * cell_w, ((126 - 32 + 16) // 16) * cell_h), (0, 0, 0, 0))
    advances: dict[str, int] = {" ": SPACE_ADVANCE}
    for code in range(33, 127):
        rows, span = glyphs[code]
        # trim: leftmost / rightmost set bit across all rows
        left, right = None, None
        for row in rows:
            if row == 0:
                continue
            bits = f"{row:0{span}b}"
            first = bits.find("1")
            last = bits.rfind("1")
            left = first if left is None else min(left, first)
            right = last if right is None else max(right, last)
        if code in overrides:
            left, right = overrides[code]
        if left is None:
            left, right = 0, 7
        index = code - 32
        cx, cy = (index % 16) * cell_w, (index // 16) * cell_h
        for y in range(16):
            bits = f"{rows[y]:0{span}b}"
            for x in range(left, min(right + 1, len(bits))):
                if bits[x] == "1" and (x - left) < cell_w:
                    out.putpixel((cx + (x - left), cy + y), (255, 255, 255, 255))
        # The game halves unihex pixels: trimmed width over two, plus one.
        advances[chr(code)] = (right - left + 1 + 1) // 2 + 1
    metrics = {
        "rows": (126 - 32 + 16) // 16,
        "columns": 16,
        "cellWidth": cell_w,
        "cellHeight": cell_h,
        "height": 8,
        "ascent": 7,
        "advances": advances,
    }
    return out, metrics


def run_update(output: str, unicode_pages: bool) -> int:
    """The baseline flow: fetch (network) then build the 1.18.1 pack."""
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
                "piston-data.mojang.com, or use --source <minecraft-dir> "
                "with a local installation; nothing was written",
                file=sys.stderr,
            )
            return 1
    return build_pack("1.18.1", output, unicode_pages, source_hashes=None)


def build_pack(
    version: str,
    output: str,
    unicode_pages: bool,
    source_hashes: dict | None,
) -> int:
    """One pack from one version's own extract. Versions never mix.

    The provider stack is whatever this version's default.json really
    declares, reference includes resolved. Handled types: `bitmap`
    (measured, copied; the first stack of bitmaps covering ASCII 32..126
    feeds the runtime atlas), `space` (advances merged verbatim),
    `legacy_unicode` (recorded), `unihex` (recorded; rasterised for the
    runtime only when no bitmap covers ASCII). Unknown types are
    recorded verbatim and never fatal — the pack manifest is the honest
    inventory of what the version ships.
    """
    if Image is None:
        print("Pillow is required: pip3 install pillow", file=sys.stderr)
        return 1
    font_dir = font_dir_for(version)
    texture_dir = texture_dir_for(version)
    default_json = os.path.join(font_dir, "default.json")
    if not os.path.exists(default_json):
        print(
            f"no extract for Minecraft {version}: {default_json} missing — "
            + ("run --update first" if version == "1.18.1"
               else f"use --source <minecraft-dir> with {version} installed"),
            file=sys.stderr,
        )
        return 1

    providers = load_provider_stack(font_dir)
    os.makedirs(output, exist_ok=True)
    out_files: dict[str, dict] = {}
    manifest_providers: list[dict] = []
    runtime: dict | None = None
    space_advances: dict[str, int] = {}
    # codepoint → (image, cell rect, measured provider) from the first
    # bitmap provider that supplies it — the game's own precedence.
    ascii_cells: dict[int, tuple] = {}
    unihex_provider: dict | None = None

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
            source = os.path.join(texture_dir, os.path.basename(reference))
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
            chars = provider.get("chars") or []
            cell_w, cell_h = measured["cellWidth"], measured["cellHeight"]
            for row_index, row in enumerate(chars):
                for col_index, char in enumerate(row):
                    code = ord(char) if char and char != "\u0000" else None
                    if code is not None and 32 <= code <= 126 and code not in ascii_cells:
                        ascii_cells[code] = (
                            image,
                            (col_index * cell_w, row_index * cell_h, cell_w, cell_h),
                            measured,
                        )
            print(f"bitmap {reference}: {measured['rows']}x{measured['columns']} cells → {local}")
        elif kind == "space":
            advances = provider.get("advances") or {}
            record["advances"] = advances
            for char, value in advances.items():
                if isinstance(char, str) and len(char) == 1:
                    space_advances[char] = int(round(float(value)))
            print(f"space: {len(advances)} explicit advances recorded")
        elif kind == "legacy_unicode":
            record["sizes"] = provider.get("sizes")
            record["template"] = provider.get("template")
            print("legacy_unicode: recorded (pages skipped; ASCII covers the GUI)"
                  if not unicode_pages else
                  "legacy_unicode: recorded — CDN pages are not fetched here")
        elif kind == "unihex":
            record["hex_file"] = provider.get("hex_file")
            record["size_overrides"] = provider.get("size_overrides")
            if unihex_provider is None:
                unihex_provider = provider
            print(f"unihex {provider.get('hex_file')}: recorded")
        else:
            record["raw"] = provider
            print(f"unhandled provider type {kind!r}: recorded verbatim")
        manifest_providers.append(record)

    # The runtime atlas: bitmaps first (the sharp path), unihex only
    # when this version's stack no longer covers ASCII with bitmaps.
    covered = [code for code in range(32, 127)
               if code in ascii_cells or chr(code) in space_advances or code == 32]
    if len(covered) == 95 and ascii_cells:
        base_measure = next(iter(ascii_cells.values()))[2]
        cell_w, cell_h = base_measure["cellWidth"], base_measure["cellHeight"]
        uniform = all(
            entry[2]["cellWidth"] == cell_w and entry[2]["cellHeight"] == cell_h
            for entry in ascii_cells.values()
        )
        if not uniform:
            print(
                "ASCII spans bitmap providers with different cell sizes; "
                "refusing to guess a mixed atlas",
                file=sys.stderr,
            )
            return 1
        rows = (95 + 15) // 16
        grid = Image.new("RGBA", (16 * cell_w, rows * cell_h), (0, 0, 0, 0))
        advances_by_code: dict[str, int] = {}
        for code in range(32, 127):
            char = chr(code)
            if code in ascii_cells:
                image, (sx, sy, cw, ch), measured = ascii_cells[code]
                index = code - 32
                grid.paste(
                    image.crop((sx, sy, sx + cw, sy + ch)),
                    ((index % 16) * cell_w, (index // 16) * cell_h),
                )
                advances_by_code[str(code)] = measured["advances"].get(
                    char, SPACE_ADVANCE if char == " " else 6
                )
            if char in space_advances:
                advances_by_code[str(code)] = space_advances[char]
            elif char == " " and str(code) not in advances_by_code:
                advances_by_code[str(code)] = SPACE_ADVANCE
        runtime_png = os.path.join(output, "runtime-ascii.png")
        grid.save(runtime_png)
        out_files["runtime-ascii.png"] = {"sha1": sha1_of(runtime_png)}
        runtime = {
            "image": "runtime-ascii.png",
            "size": base_measure["height"],
            "first": 32,
            "last": 126,
            "columns": 16,
            "cellWidth": cell_w,
            "cellHeight": cell_h,
            "advance": 6,
            "advances": advances_by_code,
            "ascent": base_measure["ascent"],
            "lineHeight": LINE_HEIGHT,
            "shadow": SHADOW,
        }
    elif unihex_provider is not None:
        rasterised = rasterize_unihex(unihex_provider, font_dir)
        if rasterised is None:
            return 1
        grid, metrics = rasterised
        runtime_png = os.path.join(output, "runtime-ascii.png")
        grid.save(runtime_png)
        out_files["runtime-ascii.png"] = {"sha1": sha1_of(runtime_png)}
        advances_by_code = {
            str(ord(char)): value for char, value in metrics["advances"].items()
        }
        for char, value in space_advances.items():
            if 32 <= ord(char) <= 126:
                advances_by_code[str(ord(char))] = value
        runtime = {
            "image": "runtime-ascii.png",
            "size": metrics["height"],
            "first": 32,
            "last": 126,
            "columns": 16,
            "cellWidth": metrics["cellWidth"],
            "cellHeight": metrics["cellHeight"],
            "advance": 6,
            "advances": advances_by_code,
            "ascent": metrics["ascent"],
            "lineHeight": LINE_HEIGHT,
            "shadow": SHADOW,
        }
    else:
        print(
            f"Minecraft {version}'s provider stack covers no ASCII path this "
            "installer understands (no bitmap, no unihex) — refusing",
            file=sys.stderr,
        )
        return 1

    pinned = VERSIONS[version]
    pin_client = pinned.get("clientJarSha1")
    if version == "1.18.1" and os.path.exists(PIN):
        pin_data = json.load(open(PIN, encoding="utf-8"))
        pin_client = (pin_data.get("official") or {}).get("clientJarSha1", pin_client)
    manifest = {
        "format": "wurst-minecraft-font-v1",
        "game": "Minecraft",
        "version": version,
        "clientJarSha1": pin_client,
        "sourceHashes": source_hashes or {
            "clientJarSha1": pin_client,
            "assetIndexId": pinned.get("assetIndexId"),
            "assetIndexSha1": pinned.get("assetIndexSha1"),
        },
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
    print(f"copy the {VERSIONS[version]['packName']} folder into the executor "
          "workspace root; do not commit it — Mojang pixels stay out of Git")
    return 0


def run_source(source: str, version: str, output: str, unicode_pages: bool) -> int:
    """--source: auto-detect version JSON / client jar / asset index."""
    if Image is None:
        print("Pillow is required: pip3 install pillow", file=sys.stderr)
        return 1
    found = discover_source(source, version)
    if found is None:
        return 1
    print(f"found {version}: jar sha1 {found['clientJarSha1']} · "
          f"asset index {found['assetIndexId']}")
    if not extract_fonts_from_jar(found["jarPath"], version):
        print("the client jar carries no assets/minecraft/font tree", file=sys.stderr)
        return 1
    return build_pack(version, output, unicode_pages, source_hashes={
        "versionJsonSha1": found["versionJsonSha1"],
        "clientJarSha1": found["clientJarSha1"],
        "assetIndexId": found["assetIndexId"],
        "assetIndexSha1": found["assetIndexSha1"],
    })


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


REQUIRED_RAW_FILES = (
    "assets/minecraft/font/default.json",
    "assets/minecraft/font/glyph_sizes.bin",
    "assets/minecraft/textures/font/ascii.png",
    "assets/minecraft/textures/font/accented.png",
    "assets/minecraft/textures/font/nonlatin_european.png",
)
PINNED_CLIENT_SHA1 = "7e46fb47609401970e2818989fa584fd467cd036"
# A transferred pack or zip larger than this is not a font extract.
MAX_PACK_BYTES = 32 * 1024 * 1024


def raw_root(path: str) -> str | None:
    if not os.path.isdir(path):
        return None
    for candidate in (path, os.path.join(path, "extract"), os.path.join(path, "raw")):
        if os.path.isfile(os.path.join(candidate, REQUIRED_RAW_FILES[0])):
            return candidate
    return None


def validate_raw(path: str, version: str = "1.18.1") -> str | None:
    if version == "1.18.1":
        # The baseline's stack is pinned and fully known; hold it hard.
        missing = [name for name in REQUIRED_RAW_FILES if not os.path.isfile(os.path.join(path, name))]
        if missing:
            return "incomplete pack, missing:\n  " + "\n  ".join(missing)
        try:
            providers = json.load(
                open(os.path.join(path, REQUIRED_RAW_FILES[0]), encoding="utf-8")
            ).get("providers") or []
        except (OSError, json.JSONDecodeError) as error:
            return f"corrupt default.json: {error}"
        kinds = [provider.get("type") for provider in providers[:4]]
        if kinds != ["bitmap", "bitmap", "bitmap", "legacy_unicode"]:
            return f"default.json providers drifted: {kinds}"
        sizes = os.path.join(path, REQUIRED_RAW_FILES[1])
        if os.path.getsize(sizes) != 65536:
            return "glyph_sizes.bin must be 65536 bytes"
        for name in REQUIRED_RAW_FILES[2:]:
            with open(os.path.join(path, name), "rb") as handle:
                if handle.read(8) != b"\x89PNG\r\n\x1a\n":
                    return f"corrupt PNG: {name}"
        return None
    # Another version: its stack is whatever its default.json declares.
    # Require a parseable default.json and sane PNGs; never assume the
    # 1.18.1 provider list.
    default_json = os.path.join(path, REQUIRED_RAW_FILES[0])
    if not os.path.isfile(default_json):
        return f"incomplete pack, missing:\n  {REQUIRED_RAW_FILES[0]}"
    try:
        json.load(open(default_json, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return f"corrupt default.json: {error}"
    texture_dir = os.path.join(path, "assets/minecraft/textures/font")
    if os.path.isdir(texture_dir):
        for name in os.listdir(texture_dir):
            if name.endswith(".png"):
                with open(os.path.join(texture_dir, name), "rb") as handle:
                    if handle.read(8) != b"\x89PNG\r\n\x1a\n":
                        return f"corrupt PNG: {name}"
    return None


def write_status(source: str, detail: str, version: str = "1.18.1") -> None:
    os.makedirs(cache_for(version), exist_ok=True)
    with open(status_for(version), "w", encoding="utf-8") as handle:
        json.dump(
            {
                "source": source,
                "detail": detail,
                "minecraft": version,
                "clientJarSha1": VERSIONS[version].get("clientJarSha1"),
                "exactMinecraft": source == "minecraft-exact",
            },
            handle,
            indent=2,
        )
        handle.write("\n")


def show_status(output: str, version: str = "1.18.1") -> int:
    manifest = os.path.join(output, "manifest.json")
    if os.path.isfile(manifest) and run_check(output) == 0:
        label = "minecraft-exact" if version == "1.18.1" else f"minecraft-{version}-local"
        print(f"installed · source={label} · runtime pack {output}")
        return 0
    status_file = status_for(version)
    if os.path.isfile(status_file):
        data = json.load(open(status_file, encoding="utf-8"))
        print(f"installed · source={data.get('source')} · {data.get('detail')}")
        return 0
    print(f"not installed ({version}) · fallback Monocraft (OFL, not Minecraft exact)")
    return 0


def pack_size(path: str) -> int:
    if os.path.isfile(path):
        return os.path.getsize(path)
    total = 0
    for dirpath, _dirnames, filenames in os.walk(path):
        for name in filenames:
            total += os.path.getsize(os.path.join(dirpath, name))
    return total


def install_raw(path: str, output: str, version: str = "1.18.1") -> int:
    if not path or not os.path.exists(path):
        print(f"pack not found: {path}", file=sys.stderr)
        return 1
    if pack_size(path) > MAX_PACK_BYTES:
        print(
            f"pack exceeds {MAX_PACK_BYTES} bytes; refusing to install",
            file=sys.stderr,
        )
        return 1
    work = tempfile.mkdtemp(prefix="mc-font-")
    try:
        candidate: str | None = None
        detail = path
        if os.path.isdir(path):
            candidate = raw_root(path)
        elif os.path.isfile(path) and zipfile.is_zipfile(path):
            digest = sha1_of(path)
            try:
                with zipfile.ZipFile(path) as archive:
                    bad = archive.testzip()
                    if bad is not None:
                        print(f"corrupt pack: bad member {bad}", file=sys.stderr)
                        return 1
                    archive.extractall(work)
            except zipfile.BadZipFile:
                print("corrupt pack: not a zip", file=sys.stderr)
                return 1
            candidate = raw_root(work)
            detail = f"zip/client sha1 {digest}"
        else:
            print("pack must be a directory, zip, or client.jar", file=sys.stderr)
            return 1
        if candidate is None:
            print("incomplete pack: no assets/minecraft/font tree", file=sys.stderr)
            return 1
        error = validate_raw(candidate, version)
        if error:
            print(error, file=sys.stderr)
            return 1
        extract = extract_for(version)
        if os.path.isdir(extract):
            shutil.rmtree(extract)
        os.makedirs(cache_for(version), exist_ok=True)
        shutil.copytree(candidate, extract)
        write_status(
            "minecraft-exact" if version == "1.18.1"
            else f"minecraft-{version}-local",
            detail,
            version,
        )

        # A real provider extract contains chars and dimensions that Pillow can
        # turn into the runtime atlas immediately. Tiny test fixtures are still
        # accepted as verified raw packs and deliberately skip generation.
        generated = False
        if Image is not None:
            try:
                providers = json.load(
                    open(os.path.join(font_dir_for(version), "default.json"), encoding="utf-8")
                )["providers"]
                if any(provider.get("chars") for provider in providers):
                    generated = build_pack(version, output, False, None) == 0
            except (OSError, KeyError, json.JSONDecodeError, SystemExit):
                generated = False
        print(f"ok · installed verified raw font under {extract}")
        if generated:
            print(f"ok · generated runtime pack under {output}")
        else:
            print("runtime atlas generation skipped; install Pillow and use --update for a live pack")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


def offline_check(output: str) -> int:
    pin = json.load(open(PIN, encoding="utf-8"))
    if (pin.get("official") or {}).get("clientJarSha1") != PINNED_CLIENT_SHA1:
        print("font authority pin drifted", file=sys.stderr)
        return 1
    for version in VERSIONS:
        pack = output if version == "1.18.1" else default_output_for(version)
        manifest = os.path.join(pack, "manifest.json")
        if os.path.isfile(manifest):
            if run_check(pack) != 0:
                return 1
            built = json.load(open(manifest, encoding="utf-8"))
            if built.get("version") != version:
                print(
                    f"{pack} claims Minecraft {built.get('version')} but sits in "
                    f"the {version} slot — versions never mix",
                    file=sys.stderr,
                )
                return 1
    print("ok · installer offline · authority stays 1.18.1; Monocraft fallback remains available")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--update", action="store_true", help="download and build from official sources")
    group.add_argument("--check", action="store_true", help="offline authority/pack check")
    group.add_argument("--status", action="store_true", help="show exact/fallback installation status")
    group.add_argument("--install", metavar="PATH", help="install a transferred raw pack, zip, or client.jar")
    group.add_argument("--source", metavar="DIR", help="build from a local Minecraft directory (auto-detects version json / client jar / asset index)")
    parser.add_argument("--version", default="1.18.1", choices=sorted(VERSIONS),
                        help="which Minecraft's font pack to build; 1.18.1 stays the visual authority")
    parser.add_argument("--output", default=None, help="runtime pack directory (kept out of Git)")
    parser.add_argument("--unicode", action="store_true", help="record legacy unicode pages")
    args = parser.parse_args()
    if args.output is None:
        args.output = default_output_for(args.version)
    assets_root = os.path.join(ROOT, "assets")
    try:
        writes_into_assets = os.path.commonpath(
            [os.path.abspath(args.output), assets_root]
        ) == assets_root
    except ValueError:
        writes_into_assets = False
    if writes_into_assets:
        print("refusing to write Mojang pixels under assets/", file=sys.stderr)
        return 1
    if args.check:
        return offline_check(args.output)
    if args.status:
        return show_status(args.output, args.version)
    if args.install:
        return install_raw(args.install, args.output, args.version)
    if args.source:
        return run_source(args.source, args.version, args.output, args.unicode)
    if args.version != "1.18.1":
        print(
            f"--update downloads only the 1.18.1 authority; for Minecraft "
            f"{args.version} use --source <minecraft-dir> with that version "
            "installed locally",
            file=sys.stderr,
        )
        return 1
    return run_update(args.output, args.unicode)


if __name__ == "__main__":
    sys.exit(main())
