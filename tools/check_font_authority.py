#!/usr/bin/env python3
"""Hold the font pipeline to the 1.18.1 authority.

Normal validate is offline: it reads the authored pin
(`assets/font/minecraft-1.18.1.manifest.json`), the Monocraft
fallback atlas, NOTICE / OFL, and refuses Mojang pixels in git.
It does not download the client jar. `tools/fetch_minecraft_font.py
--update` is the explicit network path.

Usage:
    python3 tools/check_font_authority.py
    python3 tools/check_font_authority.py --check   # same
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets/font/minecraft-1.18.1.manifest.json")
MONO_JSON = os.path.join(ROOT, "assets/font/monocraft-16.json")
MONO_PNG = os.path.join(ROOT, "assets/font/monocraft-16.png")
MONO_OTF = os.path.join(ROOT, "src/gui/Current/Assets/Typography/Monocraft.otf")
MONO_OFL = os.path.join(ROOT, "src/gui/Current/Assets/Typography/Monocraft-OFL.txt")
NOTICE = os.path.join(ROOT, "NOTICE.md")
AUTHORITY = os.path.join(ROOT, "docs/minecraft-1.18.1-font.md")

# Pinned here as well as in the JSON so a hand-edit of one side fails.
PINNED_VERSION = "1.18.1"
PINNED_CLIENT_SHA1 = "7e46fb47609401970e2818989fa584fd467cd036"
PINNED_VERSION_JSON_SHA1 = "b0bdc637e4c4cbf0501500cbaad5a757b04848ed"

# Reproducibility of the OFL fallback atlas (16 cols × 11, 6 rows × 17).
MONO_PNG_SHA256 = (
    "6b4009abd1d64fcf922cffbb78068834ab963536c176e5e00a47fdf6e708994b"
)
MONO_PNG_SIZE = (176, 102)
MONO_GLYPHS = 95  # 32..126 inclusive

BANNED_LABELS = (
    "minecraft exact",
    "mc.font",
    "mojangles",
    "ascii.png exact",
)


def fail(message: str) -> None:
    raise SystemExit(message)


def png_size(path: str) -> tuple[int, int]:
    with open(path, "rb") as handle:
        signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            fail(f"{path}: not a PNG")
        length, chunk = struct.unpack(">I4s", handle.read(8))
        if chunk != b"IHDR" or length < 8:
            fail(f"{path}: missing IHDR")
        width, height = struct.unpack(">II", handle.read(8))
    return width, height


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.split()


def check_manifest() -> dict:
    if not os.path.exists(MANIFEST):
        fail(f"{MANIFEST} is missing")
    data = json.load(open(MANIFEST, encoding="utf-8"))
    version = (data.get("minecraft") or {}).get("versionId")
    if version != PINNED_VERSION:
        fail(f"font target is {version!r}, not {PINNED_VERSION}")
    official = data.get("official") or {}
    got_client = official.get("clientJarSha1")
    if got_client != PINNED_CLIENT_SHA1:
        fail(
            f"clientJarSha1 {got_client} != pinned {PINNED_CLIENT_SHA1}"
        )
    got_json = official.get("versionJsonSha1")
    if got_json != PINNED_VERSION_JSON_SHA1:
        fail(
            f"versionJsonSha1 {got_json} != pinned {PINNED_VERSION_JSON_SHA1}"
        )
    providers = data.get("defaultProviders") or []
    types = [row.get("type") for row in providers]
    if types != ["bitmap", "bitmap", "bitmap", "legacy_unicode"]:
        fail(f"1.18.1 default providers drifted: {types}")
    absent = set(data.get("absentIn1181") or [])
    for name in ("space", "ttf", "unihex", "reference", "include"):
        if name not in absent:
            fail(f"manifest must record that 1.18.1 has no {name} provider")
    if (data.get("metrics") or {}).get("lineHeight") != 9:
        fail("manifest lineHeight must stay 9")
    if (data.get("fallback") or {}).get("exactMinecraft") is not False:
        fail("fallback.exactMinecraft must be false")
    authority = os.path.join(ROOT, "docs/wurst-gui-authority.json")
    if os.path.exists(authority):
        gui = json.load(open(authority, encoding="utf-8"))
        if (gui.get("identity") or {}).get("minecraft") != "1.18.1":
            fail("GUI identity minecraft must stay 1.18.1; 7.54.1 is not the font baseline")
    return data


def check_no_mojang_pixels(manifest: dict) -> None:
    needles = list(manifest.get("doNotVendor") or [])
    # The authored pin names default.json as a Mojang file. Our own
    # docs may mention the name; git contents of *assets* must not
    # be the file.
    tracked = tracked_files()
    offenders = []
    for path in tracked:
        base = os.path.basename(path)
        lowered = path.replace("\\", "/").lower()
        if lowered.endswith("minecraft-1.18.1.manifest.json"):
            continue
        if lowered.endswith("minecraft-1.18.1-font.md"):
            continue
        for needle in needles:
            token = needle.lower()
            if token == "default.json" and "/font/default.json" in lowered:
                offenders.append(path)
            elif token.endswith(".json") and base.lower() == token:
                if "minecraft" in lowered and "manifest" not in lowered:
                    offenders.append(path)
            elif token and token in lowered:
                # client.jar, ascii.png, unicode_page_, glyph_sizes.bin…
                offenders.append(f"{path} ({needle})")
    if offenders:
        fail(
            "Mojang font assets must not be vendored:\n  "
            + "\n  ".join(sorted(set(offenders)))
        )


def check_monocraft_not_minecraft() -> None:
    if not os.path.exists(MONO_JSON):
        fail(f"{MONO_JSON} is missing")
    metrics = json.load(open(MONO_JSON, encoding="utf-8"))
    label = str(metrics.get("font") or "")
    if "Monocraft" not in label:
        fail(f"{MONO_JSON}: font label must name Monocraft, got {label!r}")
    blob = json.dumps(metrics).lower() + label.lower()
    for banned in BANNED_LABELS:
        if banned in blob:
            fail(
                f"{MONO_JSON} labels the OFL fallback as {banned!r}; "
                "that name is reserved for a generated 1.18.1 atlas"
            )
    if metrics.get("first") != 32 or metrics.get("last") != 126:
        fail(f"{MONO_JSON}: coverage must be ASCII 32..126")
    if metrics.get("columns") != 16:
        fail(f"{MONO_JSON}: columns must be 16")
    count = metrics["last"] - metrics["first"] + 1
    if count != MONO_GLYPHS:
        fail(f"{MONO_JSON}: expected {MONO_GLYPHS} glyphs, got {count}")
    if (
        metrics.get("cellWidth") != 11
        or metrics.get("cellHeight") != 17
        or metrics.get("advance") != 11
    ):
        fail(
            f"{MONO_JSON}: Monocraft cell must stay 11×17 / advance 11 "
            f"(got {metrics.get('cellWidth')}x{metrics.get('cellHeight')} "
            f"adv {metrics.get('advance')})"
        )
    if not os.path.exists(MONO_PNG):
        fail(f"{MONO_PNG} is missing")
    digest = hashlib.sha256(open(MONO_PNG, "rb").read()).hexdigest()
    if digest != MONO_PNG_SHA256:
        fail(
            f"{MONO_PNG} sha256 {digest} != pinned {MONO_PNG_SHA256}; "
            "regenerate with tools/make_font_atlas.py and update the pin "
            "only if the OFL source changed"
        )
    width, height = png_size(MONO_PNG)
    if (width, height) != MONO_PNG_SIZE:
        fail(f"{MONO_PNG} is {width}x{height}, expected {MONO_PNG_SIZE}")


def check_licence() -> None:
    if not os.path.exists(MONO_OTF):
        fail(f"{MONO_OTF} is missing")
    if not os.path.exists(MONO_OFL):
        fail(f"{MONO_OFL} is missing")
    ofl = open(MONO_OFL, encoding="utf-8", errors="replace").read()
    if "SIL OPEN FONT LICENSE" not in ofl:
        fail(f"{MONO_OFL} is not the SIL OFL")
    if "Idrees Hassan" not in ofl:
        fail(f"{MONO_OFL} must name the Monocraft author")
    notice = open(NOTICE, encoding="utf-8").read()
    if "Monocraft" not in notice or "OFL" not in notice:
        fail("NOTICE.md must name the vendored Monocraft OFL fallback")
    if not os.path.exists(AUTHORITY):
        fail(f"{AUTHORITY} is missing")


def check_atlas_script() -> None:
    script = os.path.join(ROOT, "tools/make_font_atlas.py")
    result = subprocess.run(
        [sys.executable, script, "--check"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(
            "make_font_atlas.py --check failed:\n"
            + (result.stdout + result.stderr)
        )
    print(result.stdout.strip() or "atlas ok")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="accepted; this is always a check")
    parser.parse_args()

    os.chdir(ROOT)
    manifest = check_manifest()
    check_no_mojang_pixels(manifest)
    check_monocraft_not_minecraft()
    check_licence()
    check_atlas_script()
    print(
        f"ok · font target {PINNED_VERSION} · "
        f"client {PINNED_CLIENT_SHA1[:12]} · "
        "Monocraft fallback (not Minecraft exact)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
