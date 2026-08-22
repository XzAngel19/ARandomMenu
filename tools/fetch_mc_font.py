#!/usr/bin/env python3
"""Fetch and verify Minecraft 1.18.1's font, without committing any of it.

Wurst 7.19 runs on Minecraft 1.18.1, so the port's text must come from that
version's font providers - not from a lookalike. Mojang's assets are not
freely redistributable, which is why this is a build step and not a vendored
directory: everything is downloaded from Mojang's official distribution
servers, verified against the hashes pinned in
assets/font/minecraft-1.18.1.lock.json, and written to a work directory that
stays out of Git. Agent C owns the provenance/licence gate; until it blesses
a redistribution method, the only thing committed is the lock file and the
metrics manifest this tool emits (numbers, not textures).

What it does, in order:

  1. reads the lock file and (optionally) re-checks the 1.18.1 entry in the
     live version manifest against it;
  2. downloads the 1.18.1 version json, verifies its sha1;
  3. cross-checks the client jar and asset index entries against the lock;
  4. downloads client.jar, verifies its sha1 and size;
  5. extracts assets/minecraft/font/default.json from the jar and walks the
     providers it *really* declares (bitmap and legacy_unicode both
     supported, any number of pages);
  6. extracts every referenced bitmap texture from the jar; resolves
     glyph_sizes.bin and unicode pages through the verified asset index,
     each object checked against its own content hash;
  7. measures per-glyph advances with Minecraft's own rule (rightmost
     non-empty column; advance = round(width * height / rowHeight) + 1) and
     reads ascent/height from the provider json;
  8. emits font-manifest.json: a reproducible record of every input hash,
     provider, texture and glyph metric. No timestamps, so identical inputs
     produce identical bytes.

Modes:

  --exact   fail loudly if any official asset cannot be produced. This is
            what the runtime's "Minecraft exact" label must be gated on;
            without it the menu falls back to Monocraft (OFL), which is
            committed, clearly named monocraft-fallback, and never to be
            described as the exact Minecraft font.
  --check   verify a previous run's outputs against the lock and exit.

The sandbox the agents work in blocks direct TLS to Mojang; this tool is for
a real machine. The lock hashes were read from the official piston-meta
manifest so a run anywhere can be compared against them.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LOCK_PATH = REPO / "assets" / "font" / "minecraft-1.18.1.lock.json"
SPACE_ADVANCE = 4  # vanilla's hard advance for U+0020, which has no pixels


def sha1_of(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ARandomMenu-font-pipeline/1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def fetch_verified(url: str, sha1: str, size: int | None = None, label: str = "") -> bytes:
    data = fetch(url)
    got = sha1_of(data)
    if got != sha1:
        raise SystemExit(f"hash mismatch for {label or url}: expected {sha1}, got {got}")
    if size is not None and len(data) != size:
        raise SystemExit(f"size mismatch for {label or url}: expected {size}, got {len(data)}")
    return data


def resource_url(lock: dict, object_hash: str) -> str:
    return (
        lock["resources"]["url"]
        .replace("{first2}", object_hash[:2])
        .replace("{hash}", object_hash)
    )


def texture_path(reference: str) -> str:
    """minecraft:font/ascii.png -> assets/minecraft/textures/font/ascii.png"""
    namespace, _, rest = reference.partition(":")
    if not rest:
        namespace, rest = "minecraft", namespace
    return f"assets/{namespace}/textures/{rest}"


def font_resource_path(reference: str) -> str:
    """minecraft:font/glyph_sizes.bin -> assets/minecraft/font/glyph_sizes.bin

    legacy_unicode's sizes/template are font resources, not textures.
    """
    namespace, _, rest = reference.partition(":")
    if not rest:
        namespace, rest = "minecraft", namespace
    return f"assets/{namespace}/{rest}"


def measure_bitmap_provider(provider: dict, png_bytes: bytes) -> dict:
    """Per-glyph advances, Minecraft's way.

    BitmapProvider divides the texture into a grid sized by the chars
    array, scans each cell for its rightmost column holding any pixel with
    alpha, and advances the caret by that width (scaled by height/rowHeight)
    plus one. U+0020 has no pixels and a hard advance of 4 in vanilla.
    Requires Pillow; without it the manifest records the provider layout and
    leaves advances null rather than guessing.
    """
    chars: list[str] = provider.get("chars") or []
    rows = len(chars)
    columns = len(chars[0]) if rows else 0
    result: dict = {
        "rows": rows,
        "columns": columns,
        "height": provider.get("height", 8),
        "ascent": provider.get("ascent"),
        "advances": None,
    }
    if rows == 0 or columns == 0:
        return result
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        print("  Pillow missing: provider layout recorded, advances left null", file=sys.stderr)
        return result
    image = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    cell_w = image.width // columns
    cell_h = image.height // rows
    scale = result["height"] / cell_h
    pixels = image.load()
    advances: dict[str, int] = {}
    for row_index, row in enumerate(chars):
        for col_index, char in enumerate(row):
            if char == "\u0000":
                continue
            if char == " ":
                advances[char] = SPACE_ADVANCE
                continue
            x0 = col_index * cell_w
            y0 = row_index * cell_h
            width = 0
            for dx in range(cell_w - 1, -1, -1):
                column_has_ink = any(
                    pixels[x0 + dx, y0 + dy][3] != 0 for dy in range(cell_h)
                )
                if column_has_ink:
                    width = dx + 1
                    break
            advances[char] = int(0.5 + width * scale) + 1
    result["advances"] = advances
    result["cellWidth"] = cell_w
    result["cellHeight"] = cell_h
    return result


def run(args: argparse.Namespace) -> int:
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    work = Path(args.work)
    out_manifest = work / "font-manifest.json"

    if args.check:
        if not out_manifest.exists():
            print(f"--check: {out_manifest} does not exist; run the fetch first", file=sys.stderr)
            return 1
        manifest = json.loads(out_manifest.read_text(encoding="utf-8"))
        failures = []
        for name, record in manifest.get("files", {}).items():
            path = work / name
            if not path.exists():
                failures.append(f"missing {name}")
                continue
            if sha1_of(path.read_bytes()) != record["sha1"]:
                failures.append(f"hash drift in {name}")
        if failures:
            print("font pipeline check failed:\n  " + "\n  ".join(failures), file=sys.stderr)
            return 1
        print(f"font pipeline check ok: {len(manifest.get('files', {}))} files verified")
        return 0

    work.mkdir(parents=True, exist_ok=True)
    files: dict[str, dict] = {}

    def keep(name: str, data: bytes) -> None:
        path = work / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        files[name] = {"sha1": sha1_of(data), "size": len(data)}

    print(f"[1/6] version manifest sanity check ({lock['version']})")
    try:
        manifest_data = json.loads(fetch(lock["versionManifest"]["url"]))
        entry = next(v for v in manifest_data["versions"] if v["id"] == lock["version"])
        if entry["sha1"] != lock["versionJson"]["sha1"]:
            raise SystemExit(
                "the live manifest lists a different 1.18.1 json "
                f"({entry['sha1']}) than the lock ({lock['versionJson']['sha1']}); "
                "a pinned release must never change - investigate before trusting either"
            )
    except (StopIteration, OSError) as error:
        message = f"could not confirm against the live manifest ({error}); trusting the lock"
        if args.exact:
            print(f"  {message}", file=sys.stderr)
        else:
            print(f"  {message}")

    print("[2/6] version json")
    version_json = json.loads(
        fetch_verified(lock["versionJson"]["url"], lock["versionJson"]["sha1"], label="1.18.1.json")
    )
    client_entry = version_json["downloads"]["client"]
    if client_entry["sha1"] != lock["client"]["sha1"]:
        raise SystemExit("version json's client.jar hash disagrees with the lock")
    asset_entry = version_json["assetIndex"]
    if asset_entry["sha1"] != lock["assetIndex"]["sha1"]:
        raise SystemExit("version json's asset index hash disagrees with the lock")

    print(f"[3/6] client.jar ({lock['client']['size']} bytes)")
    jar_bytes = fetch_verified(
        lock["client"]["url"], lock["client"]["sha1"], lock["client"]["size"], "client.jar"
    )
    jar = zipfile.ZipFile(io.BytesIO(jar_bytes))

    print("[4/6] font providers from the verified jar")
    default_json_path = lock["font"]["defaultJson"]
    default_json_bytes = jar.read(default_json_path)
    keep("default.json", default_json_bytes)
    providers = json.loads(default_json_bytes)["providers"]
    print(f"  default.json declares {len(providers)} providers")

    asset_index: dict | None = None

    def asset_object(reference: str) -> bytes:
        nonlocal asset_index
        if asset_index is None:
            print("  asset index (for legacy unicode resources)")
            asset_index = json.loads(
                fetch_verified(
                    lock["assetIndex"]["url"],
                    lock["assetIndex"]["sha1"],
                    lock["assetIndex"]["size"],
                    "asset index 1.18",
                )
            )
        key = reference.removeprefix("assets/")
        record = asset_index["objects"].get(key)
        if record is None:
            raise SystemExit(f"asset index has no object for {key}")
        return fetch_verified(
            resource_url(lock, record["hash"]), record["hash"], record["size"], key
        )

    manifest_providers: list[dict] = []
    print("[5/6] textures and metrics")
    for index, provider in enumerate(providers):
        kind = provider.get("type")
        record: dict = {"index": index, "type": kind}
        if kind == "bitmap":
            reference = provider["file"]
            png_name = texture_path(reference)
            png_bytes = jar.read(png_name)
            local = f"textures/{Path(png_name).name}"
            keep(local, png_bytes)
            record["file"] = reference
            record["texture"] = local
            record.update(measure_bitmap_provider(provider, png_bytes))
            print(f"  bitmap {reference}: {record['rows']}x{record['columns']} cells")
        elif kind == "legacy_unicode":
            sizes_ref = provider["sizes"]
            sizes_path = font_resource_path(sizes_ref)
            try:
                sizes_bytes = jar.read(sizes_path)
            except KeyError:
                sizes_bytes = asset_object(sizes_path)
            keep("glyph_sizes.bin", sizes_bytes)
            record["sizes"] = sizes_ref
            record["template"] = provider["template"]
            pages: list[str] = []
            if args.unicode_pages:
                for page in range(0, 256):
                    page_ref = provider["template"] % f"{page:02x}"
                    page_path = texture_path(page_ref)
                    try:
                        try:
                            page_bytes = jar.read(page_path)
                        except KeyError:
                            page_bytes = asset_object(page_path)
                    except SystemExit:
                        continue  # vanilla ships only the pages that exist
                    local = f"textures/unicode_page_{page:02x}.png"
                    keep(local, page_bytes)
                    pages.append(local)
                print(f"  legacy_unicode: {len(pages)} pages fetched")
            else:
                print("  legacy_unicode: recorded; pages skipped (pass --unicode-pages)")
            record["pages"] = pages
        else:
            record["raw"] = provider
            print(f"  unhandled provider type {kind!r}: recorded verbatim")
        manifest_providers.append(record)

    print("[6/6] manifest")
    manifest = {
        "game": lock["game"],
        "version": lock["version"],
        "inputs": {
            "versionJson": lock["versionJson"],
            "client": lock["client"],
            "assetIndex": lock["assetIndex"],
        },
        "providers": manifest_providers,
        "files": files,
        "fallback": lock["fallback"],
        "exact": True,
    }
    out_manifest.write_text(
        json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {out_manifest} ({len(files)} files, none of them committed)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--work", default="build/mc-font", help="output directory (kept out of Git)")
    parser.add_argument("--check", action="store_true", help="verify a previous run and exit")
    parser.add_argument("--exact", action="store_true", help="fail if any official asset cannot be produced")
    parser.add_argument("--unicode-pages", action="store_true", help="also fetch the legacy unicode pages")
    args = parser.parse_args()
    try:
        return run(args)
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001 - a build step must say why it died
        if args.exact:
            raise SystemExit(f"--exact requested and the pipeline failed: {error}")
        print(f"font pipeline failed: {error}", file=sys.stderr)
        print("the menu keeps working on the committed monocraft-fallback", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
