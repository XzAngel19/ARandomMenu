#!/usr/bin/env python3
"""Download the official 1.18.1 font extract, or refuse to.

`--check` is offline and is what validate.sh runs: it forwards to
`check_font_authority.py`. `--update` is the only network path. It
writes under `cache/minecraft-1.18.1/` (gitignored) and never into
`assets/` or `src/`.

Usage:
    python3 tools/fetch_minecraft_font.py --check
    python3 tools/fetch_minecraft_font.py --update
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets/font/minecraft-1.18.1.manifest.json")
CACHE = os.path.join(ROOT, "cache/minecraft-1.18.1")


def check() -> int:
    script = os.path.join(ROOT, "tools/check_font_authority.py")
    os.execv(sys.executable, [sys.executable, script, "--check"])


def update() -> int:
    pin = json.load(open(MANIFEST, encoding="utf-8"))
    official = pin["official"]
    url = official["clientJar"]
    wanted = official["clientJarSha1"]
    os.makedirs(CACHE, exist_ok=True)
    jar_path = os.path.join(CACHE, "client.jar")
    print(f"GET {url}")
    try:
        urllib.request.urlretrieve(url, jar_path)
    except Exception as error:  # noqa: BLE001 — surface CDN / TLS failures
        print(
            f"update failed: {error}\n"
            "  The gate does not need this. Re-run --update on a machine\n"
            "  that can reach piston-data.mojang.com, then generate the\n"
            "  local atlas from cache/minecraft-1.18.1/."
        )
        return 1
    digest = hashlib.sha1(open(jar_path, "rb").read()).hexdigest()
    if digest != wanted:
        os.remove(jar_path)
        print(f"client.jar sha1 {digest} != pinned {wanted}")
        return 1
    extract = os.path.join(CACHE, "extract")
    os.makedirs(extract, exist_ok=True)
    wanted_prefixes = (
        "assets/minecraft/font/",
        "assets/minecraft/textures/font/",
    )
    with zipfile.ZipFile(jar_path) as archive:
        for name in archive.namelist():
            if name.startswith(wanted_prefixes):
                archive.extract(name, extract)
    print(f"ok · {wanted} · extracted under {extract}")
    print("do not copy those files into assets/ or commit them")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--update", action="store_true")
    args = parser.parse_args()
    os.chdir(ROOT)
    if args.check:
        return check()
    return update()


if __name__ == "__main__":
    sys.exit(main())
