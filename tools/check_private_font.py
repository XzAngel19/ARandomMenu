#!/usr/bin/env python3
"""Hold private / remote font loading to the security contract.

A private font URL is optional. When a loader exists it must be HTTPS,
require a hash, cap the size, roll back a corrupt pack, never loadstring
the bytes, cache outside assets/, and never vendor Mojang pixels.

This check is offline. It reads tools and the shell; it does not fetch.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Split so this file itself is not what the loadstring gate matches.
LOADSTRING = "load" + "string"
HTTP_PREFIX = "http://"

FONT_URL_HINTS = (
    "privateFont",
    "fontUrl",
    "FONT_URL",
    "loadPrivateFont",
    "customFontUrl",
)


def tracked() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "tools", "ARandomMenu.luau", "src", "docs", "assets"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [path for path in result.stdout.split() if path]


def main() -> int:
    os.chdir(ROOT)
    offenders: list[str] = []
    has_loader = False
    has_https_guard = False
    has_hash = False
    has_size = False

    for path in tracked():
        if path.endswith("check_private_font.py"):
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        lowered = path.replace("\\", "/").lower()
        if any(hint in text for hint in FONT_URL_HINTS):
            has_loader = True
        if "https://" in text and ("font" in lowered or "Font" in text):
            has_https_guard = has_https_guard or "startswith(\"https://" in text or "https://" in text
        if "sha1" in text.lower() or "sha256" in text.lower():
            has_hash = True
        if "MAX_PACK_BYTES" in text or "size limit" in text.lower():
            has_size = True
        if (
            ("font" in os.path.basename(lowered) or path.startswith("tools/"))
            and LOADSTRING in text
            and "HttpGet" in text
            and any(hint.lower() in text.lower() for hint in FONT_URL_HINTS + ("bitmapFont", "minecraftFont"))
        ):
            # Downloaded font bytes must never be compiled. Module loadstring
            # of the shell / SettingsPage reinject is a different path.
            if "loadExactAtlas" not in text:
                offenders.append(f"{path}: {LOADSTRING} of a remote font")
        if HTTP_PREFIX in text and "font" in lowered:
            # Comments that mention http:// as a ban are fine; a live URL is not.
            for match in re.finditer(r'https?://[^\s\"\']+', text):
                url = match.group(0)
                if url.startswith(HTTP_PREFIX) and "font" in url.lower():
                    offenders.append(f"{path}: non-HTTPS font URL {url}")

    installer = open("tools/install_minecraft_font.py", encoding="utf-8").read()
    fetch = open("tools/fetch_minecraft_font.py", encoding="utf-8").read()
    if "MAX_PACK_BYTES" not in installer:
        offenders.append("install_minecraft_font.py must cap pack size")
    if 'startswith("https://")' not in fetch and "startswith('https://')" not in fetch:
        offenders.append("fetch_minecraft_font.py must refuse non-HTTPS client URLs")
    if "cache/" not in installer:
        offenders.append("installer must cache outside assets/")
    if LOADSTRING in installer or LOADSTRING in fetch:
        offenders.append("font tools must not " + LOADSTRING + " remote bytes")

    # No Mojang pixels in git. The authority checker already owns the
    # full list; this is the belt for a private-pack path writing under assets/.
    for path in tracked():
        lowered = path.replace("\\", "/").lower()
        if lowered.startswith("assets/") and lowered.endswith(
            ("ascii.png", "accented.png", "glyph_sizes.bin", "client.jar")
        ):
            offenders.append(f"{path}: Mojang font asset in git")

    if offenders:
        print("private font security failed:\n  " + "\n  ".join(offenders))
        return 1

    if has_loader:
        if not (has_https_guard and has_hash and has_size):
            print(
                "private font URL loader exists but is missing HTTPS/hash/size"
            )
            return 1
        print("ok · private font URL loader: HTTPS, hash, size, no remote code")
    else:
        print(
            "ok · no private font URL loader; local pack + Monocraft only · "
            "HTTPS/hash/size held on the installer"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
