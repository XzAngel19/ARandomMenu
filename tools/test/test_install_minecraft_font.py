#!/usr/bin/env python3
"""Offline tests for tools/install_minecraft_font.py."""

from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INSTALLER = os.path.join(ROOT, "tools/install_minecraft_font.py")


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, INSTALLER, *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )


def tiny_png() -> bytes:
    # 1×1 opaque white PNG, enough for the signature check.
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff"))
        + chunk(b"IEND", b"")
    )


def write_complete_pack(root: str) -> None:
    font = os.path.join(root, "assets/minecraft/font")
    textures = os.path.join(root, "assets/minecraft/textures/font")
    os.makedirs(font, exist_ok=True)
    os.makedirs(textures, exist_ok=True)
    json.dump(
        {
            "providers": [
                {"type": "bitmap", "file": "minecraft:font/nonlatin_european.png", "ascent": 7},
                {"type": "bitmap", "file": "minecraft:font/accented.png", "height": 12, "ascent": 10},
                {"type": "bitmap", "file": "minecraft:font/ascii.png", "ascent": 7},
                {"type": "legacy_unicode", "sizes": "minecraft:font/glyph_sizes.bin", "template": "minecraft:font/unicode_page_%s.png"},
            ]
        },
        open(os.path.join(font, "default.json"), "w"),
    )
    open(os.path.join(font, "glyph_sizes.bin"), "wb").write(b"\x00" * 65536)
    png = tiny_png()
    for name in ("ascii.png", "accented.png", "nonlatin_european.png"):
        open(os.path.join(textures, name), "wb").write(png)


def main() -> int:
    os.chdir(ROOT)
    failures: list[str] = []

    checked = run("--check")
    if checked.returncode != 0:
        failures.append("--check failed:\n" + checked.stdout + checked.stderr)
    if "offline" not in checked.stdout:
        failures.append("--check must say it is offline")

    status = run("--status")
    if status.returncode != 0:
        failures.append("--status failed:\n" + status.stdout + status.stderr)
    if "Minecraft exact" in status.stdout and "not Minecraft exact" not in status.stdout:
        failures.append("--status labelled the fallback as Minecraft exact")

    missing = run("--install", os.path.join(ROOT, "does-not-exist-pack"))
    if missing.returncode == 0:
        failures.append("missing pack must be rejected")

    with tempfile.TemporaryDirectory() as tmp:
        junk = os.path.join(tmp, "junk.zip")
        open(junk, "wb").write(b"not a zip")
        corrupt = run("--install", junk)
        if corrupt.returncode == 0:
            failures.append("corrupt pack must be rejected")

        incomplete_dir = os.path.join(tmp, "incomplete")
        os.makedirs(incomplete_dir, exist_ok=True)
        incomplete = run("--install", incomplete_dir)
        if incomplete.returncode == 0:
            failures.append("incomplete directory must be rejected")

        incomplete_zip = os.path.join(tmp, "incomplete.zip")
        with zipfile.ZipFile(incomplete_zip, "w") as archive:
            archive.writestr("readme.txt", "no font files")
        incomplete_z = run("--install", incomplete_zip)
        if incomplete_z.returncode == 0:
            failures.append("incomplete zip must be rejected")

        complete = os.path.join(tmp, "complete")
        write_complete_pack(complete)
        installed = run("--install", complete)
        if installed.returncode != 0:
            failures.append("complete pack must install:\n" + installed.stdout + installed.stderr)
        else:
            after = run("--status")
            if "minecraft-exact" not in after.stdout:
                failures.append(
                    "installed pack must report source minecraft-exact:\n"
                    + after.stdout
                )

    if failures:
        print("FAIL")
        print("\n".join(failures))
        return 1
    print("ok · install_minecraft_font.py pack checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
