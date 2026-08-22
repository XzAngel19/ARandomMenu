#!/usr/bin/env python3
"""Vendor the Wurst assets this port actually uses, at one pinned commit.

Downloads from Wurst-Imperium/Wurst7 through the GitHub API (the raw CDN is
blocked in this environment) and writes them under assets/wurst/. Each file's
sha256, its upstream path and the pinned commit are recorded in
assets/wurst/manifest.json.

The script is idempotent: a file whose bytes already match is left alone. A
file that differs is reported and not overwritten unless --force is passed,
so a local edit cannot vanish silently.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

PINNED_COMMIT = "4a22e53d774b9a28e395874834f099e779685998"
UPSTREAM_REPO = "Wurst-Imperium/Wurst7"
UPSTREAM_ROOT = "src/main/resources/assets/wurst"
DEST_ROOT = "assets/wurst"
MANIFEST_PATH = os.path.join(DEST_ROOT, "manifest.json")

# Shaders and post_effect are Minecraft-specific and are not copied.
FILES = (
    "wurst_128.png",
    "icon.png",
    "colorpalette.png",
    "dancingtaco1.png",
    "dancingtaco2.png",
    "dancingtaco3.png",
    "dancingtaco4.png",
    "translations/en_us.json",
)

API = "https://api.github.com/repos/{repo}/contents/{path}?ref={commit}"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(path: str) -> bytes:
    url = API.format(repo=UPSTREAM_REPO, path=path, commit=PINNED_COMMIT)
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "ARandomMenu-asset-fetch",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit(f"download failed for {path}: HTTP {error.code}") from error
    if payload.get("encoding") != "base64" or not payload.get("content"):
        raise SystemExit(f"download failed for {path}: unexpected payload")
    return base64.b64decode(payload["content"])


def load_manifest() -> dict:
    if not os.path.exists(MANIFEST_PATH):
        return {
            "upstream": UPSTREAM_REPO,
            "commit": PINNED_COMMIT,
            "files": {},
        }
    return json.loads(open(MANIFEST_PATH).read())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite local files that differ from upstream",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify checksums only; do not download",
    )
    args = parser.parse_args()

    if args.check:
        return check_only()

    os.makedirs(DEST_ROOT, exist_ok=True)
    manifest = load_manifest()
    if manifest.get("commit") not in (None, PINNED_COMMIT) and not args.force:
        print(
            f"manifest is pinned to {manifest['commit']}, script wants "
            f"{PINNED_COMMIT}; pass --force to retarget",
            file=sys.stderr,
        )
        return 1

    files: dict = {}
    changed = 0
    identical = 0
    written = 0
    blocked = 0
    for relative in FILES:
        upstream = f"{UPSTREAM_ROOT}/{relative}"
        dest = os.path.join(DEST_ROOT, relative)
        data = fetch(upstream)
        digest = sha256(data)
        if os.path.exists(dest):
            existing = open(dest, "rb").read()
            existing_digest = sha256(existing)
            if existing == data:
                identical += 1
            elif args.force:
                os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
                open(dest, "wb").write(data)
                print(f"replaced {dest}")
                print(f"  was    {existing_digest}")
                print(f"  now    {digest}")
                changed += 1
            else:
                print(f"differs {dest} (not overwritten)")
                print(f"  local  {existing_digest}")
                print(f"  remote {digest}")
                blocked += 1
        else:
            os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
            open(dest, "wb").write(data)
            print(f"wrote {dest}  {digest}")
            written += 1
        files[relative] = {
            "upstream": upstream,
            "sha256": digest,
        }

    manifest = {
        "upstream": UPSTREAM_REPO,
        "commit": PINNED_COMMIT,
        "files": files,
    }
    os.makedirs(DEST_ROOT, exist_ok=True)
    open(MANIFEST_PATH, "w").write(json.dumps(manifest, indent=2) + "\n")
    print(
        f"{written} written, {identical} identical, {changed} replaced, "
        f"{blocked} blocked"
    )
    return 1 if blocked else 0


def check_only() -> int:
    if not os.path.exists(MANIFEST_PATH):
        print("assets/wurst/manifest.json is missing")
        return 1
    manifest = json.loads(open(MANIFEST_PATH).read())
    if manifest.get("commit") != PINNED_COMMIT:
        print(
            f"manifest commit {manifest.get('commit')} != pinned {PINNED_COMMIT}"
        )
        return 1
    failures = []
    listed = set(manifest.get("files", {}))
    for relative, entry in manifest.get("files", {}).items():
        dest = os.path.join(DEST_ROOT, relative)
        if not os.path.exists(dest):
            failures.append(f"missing {dest}")
            continue
        digest = sha256(open(dest, "rb").read())
        expected = entry.get("sha256")
        if digest != expected:
            failures.append(f"{dest}: sha256 {digest} != {expected}")
    for dirpath, _dirnames, filenames in os.walk(DEST_ROOT):
        for name in filenames:
            if name == "manifest.json":
                continue
            full = os.path.join(dirpath, name)
            relative = os.path.relpath(full, DEST_ROOT).replace("\\", "/")
            if relative not in listed:
                failures.append(f"{full} is not in the manifest")
    if failures:
        print("\n".join(failures))
        return 1
    print(f"ok · {len(listed)} files · commit {PINNED_COMMIT[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
