#!/usr/bin/env python3
"""Install a locally transferred Minecraft 1.18.1 font pack.

Never hits the network. The pack is a directory or zip the user copied
from a machine that ran `tools/fetch_minecraft_font.py --update`, or
the official `client.jar` itself. This script verifies the pin, the
1.18.1 provider files, and writes under gitignored
`cache/minecraft-1.18.1/`. It never copies Mojang pixels into `assets/`
or `src/`.

Usage:
    python3 tools/install_minecraft_font.py --check
    python3 tools/install_minecraft_font.py --status
    python3 tools/install_minecraft_font.py --install PATH

Windows: copy the verified `client.jar` (or the `extract/` folder) onto
this machine, then `--install` that path. Mobile: USB / Files app the
same pack into a folder the executor can read, then run this from the
repo checkout — do not paste PNGs into `assets/`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets/font/minecraft-1.18.1.manifest.json")
CACHE = os.path.join(ROOT, "cache/minecraft-1.18.1")
STATUS = os.path.join(CACHE, "installed.json")
PINNED_CLIENT_SHA1 = "7e46fb47609401970e2818989fa584fd467cd036"

REQUIRED_FILES = (
    "assets/minecraft/font/default.json",
    "assets/minecraft/font/glyph_sizes.bin",
    "assets/minecraft/textures/font/ascii.png",
    "assets/minecraft/textures/font/accented.png",
    "assets/minecraft/textures/font/nonlatin_european.png",
)

PROVIDER_TYPES = ("bitmap", "bitmap", "bitmap", "legacy_unicode")


def fail(message: str, code: int = 1) -> int:
    print(message)
    return code


def load_pin() -> dict:
    if not os.path.exists(MANIFEST):
        raise SystemExit(f"{MANIFEST} is missing")
    return json.load(open(MANIFEST, encoding="utf-8"))


def sha1_of(path: str) -> str:
    digest = hashlib.sha1()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def looks_like_png(path: str) -> bool:
    with open(path, "rb") as handle:
        return handle.read(8) == b"\x89PNG\r\n\x1a\n"


def extract_root_from(path: str) -> str | None:
    """Return the directory that contains assets/minecraft/font, or None."""
    if os.path.isdir(path):
        if os.path.isfile(os.path.join(path, REQUIRED_FILES[0])):
            return path
        nested = os.path.join(path, "extract")
        if os.path.isfile(os.path.join(nested, REQUIRED_FILES[0])):
            return nested
        return None
    return None


def validate_extract(root: str) -> str | None:
    missing = [
        name
        for name in REQUIRED_FILES
        if not os.path.isfile(os.path.join(root, name))
    ]
    if missing:
        return "incomplete pack, missing:\n  " + "\n  ".join(missing)
    default_path = os.path.join(root, REQUIRED_FILES[0])
    try:
        data = json.load(open(default_path, encoding="utf-8"))
    except json.JSONDecodeError as error:
        return f"corrupt default.json: {error}"
    providers = data.get("providers") or []
    types = [row.get("type") for row in providers[:4]]
    if types != list(PROVIDER_TYPES):
        return f"default.json providers drifted: {types}"
    sizes = os.path.join(root, REQUIRED_FILES[1])
    if os.path.getsize(sizes) != 65536:
        return f"glyph_sizes.bin must be 65536 bytes, got {os.path.getsize(sizes)}"
    for texture in REQUIRED_FILES[2:]:
        if not looks_like_png(os.path.join(root, texture)):
            return f"corrupt PNG: {texture}"
    return None


def write_status(kind: str, detail: str) -> None:
    os.makedirs(CACHE, exist_ok=True)
    payload = {
        "source": kind,
        "detail": detail,
        "minecraft": "1.18.1",
        "clientJarSha1": PINNED_CLIENT_SHA1,
        "exactMinecraft": kind == "minecraft-exact",
    }
    with open(STATUS, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def status() -> int:
    pin = load_pin()
    if (pin.get("fallback") or {}).get("exactMinecraft") is not False:
        return fail("authored fallback.exactMinecraft must stay false")
    if os.path.exists(STATUS):
        data = json.load(open(STATUS, encoding="utf-8"))
        print(
            f"installed · source={data.get('source')} · "
            f"{data.get('detail')}"
        )
        return 0
    print("not installed · fallback Monocraft (OFL, not Minecraft exact)")
    return 0


def check() -> int:
    """Offline gate. No urllib, no piston-meta."""
    source = open(__file__, encoding="utf-8").read()
    banned = ("import " + "urllib", "urllib" + ".request")
    if any(token in source for token in banned):
        return fail("installer must stay offline; do not import the HTTP client")
    pin = load_pin()
    official = pin.get("official") or {}
    if official.get("clientJarSha1") != PINNED_CLIENT_SHA1:
        return fail("installer pin drifted from the 1.18.1 client SHA1")
    types = [row.get("type") for row in (pin.get("defaultProviders") or [])]
    if types != list(PROVIDER_TYPES):
        return fail(f"manifest providers drifted: {types}")
    if (pin.get("fallback") or {}).get("exactMinecraft") is not False:
        return fail("fallback must never be labelled Minecraft exact")
    # A tracked Mojang pixel is a vendor. The authority checker owns the
    # full walk; this step refuses the obvious names next to us.
    for name in ("ascii.png", "client.jar", "glyph_sizes.bin"):
        tracked = os.path.join(ROOT, "assets/font", name)
        if os.path.exists(tracked):
            return fail(f"Mojang pixel tracked at {tracked}")
    print(
        "ok · install_minecraft_font.py offline · "
        f"client {PINNED_CLIENT_SHA1[:12]} · no network"
    )
    return 0


def install(path: str) -> int:
    if not path or not os.path.exists(path):
        return fail(f"pack not found: {path}")

    work = tempfile.mkdtemp(prefix="mc-font-")
    try:
        candidate = path
        if os.path.isfile(path) and zipfile.is_zipfile(path):
            digest = sha1_of(path)
            # Official client.jar is a zip. Anything else must still unzip.
            try:
                with zipfile.ZipFile(path) as archive:
                    # A truncated / junk zip throws here.
                    bad = archive.testzip()
                    if bad is not None:
                        return fail(f"corrupt pack: bad member {bad}")
                    archive.extractall(work)
            except zipfile.BadZipFile:
                return fail("corrupt pack: not a zip")
            extracted = extract_root_from(work)
            if extracted is None and digest == PINNED_CLIENT_SHA1:
                # Real client.jar: pull only the font paths.
                extract = os.path.join(work, "extract")
                os.makedirs(extract, exist_ok=True)
                with zipfile.ZipFile(path) as archive:
                    for name in archive.namelist():
                        if name.startswith(
                            (
                                "assets/minecraft/font/",
                                "assets/minecraft/textures/font/",
                            )
                        ):
                            archive.extract(name, extract)
                extracted = extract
            elif extracted is None:
                return fail("incomplete pack: no assets/minecraft/font tree")
            if digest == PINNED_CLIENT_SHA1:
                write_note = f"client.jar {digest}"
            else:
                write_note = f"zip extract (sha1 {digest})"
            candidate = extracted
        elif os.path.isdir(path):
            extracted = extract_root_from(path)
            if extracted is None:
                return fail("incomplete pack: no assets/minecraft/font tree")
            candidate = extracted
            write_note = path
        else:
            return fail("pack must be a directory, a zip, or client.jar")

        error = validate_extract(candidate)
        if error:
            return fail(error)

        dest = os.path.join(CACHE, "extract")
        os.makedirs(CACHE, exist_ok=True)
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(candidate, dest)
        write_status("minecraft-exact", write_note)
        print(f"ok · installed under {dest}")
        print("do not copy those files into assets/ or commit them")
        print("runtime source becomes minecraft-exact only when A loads this pack")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--status", action="store_true")
    group.add_argument("--install", metavar="PATH")
    args = parser.parse_args()
    os.chdir(ROOT)
    if args.check:
        return check()
    if args.status:
        return status()
    return install(args.install)


if __name__ == "__main__":
    sys.exit(main())
