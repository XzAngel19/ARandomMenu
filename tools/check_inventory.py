#!/usr/bin/env python3
"""Freeze the deliberate universal inventory snapshot.

A 7.54.1 GUI APPLY is not allowed to grow, shrink or rename
Manifest.modules. Updating this snapshot is a deliberate inventory
change and must not ride along with a chrome patch.
"""

from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAPSHOT = os.path.join(ROOT, "tools/inventory_snapshot.json")
MANIFEST = os.path.join(ROOT, "src/core/Manifest.luau")
AUTHORITY = os.path.join(ROOT, "docs/wurst-gui-authority.json")
MODULES_DIR = os.path.join(ROOT, "src/modules")

OFFICIAL = (
    "Combat",
    "Render",
    "Blocks",
    "Movement",
    "Chat",
    "Fun",
    "Items",
    "Other",
)


def parse_manifest(text: str) -> list[dict]:
    return [
        {"path": path, "name": name, "category": category}
        for path, name, category in re.findall(
            r'path = "([^"]+)",\s*name = "([^"]+)",\s*category = "([^"]+)"',
            text,
        )
    ]


def main() -> int:
    snap = json.load(open(SNAPSHOT, encoding="utf-8"))
    wanted = snap["modules"]
    got = parse_manifest(open(MANIFEST, encoding="utf-8").read())
    failures = []
    if len(got) != snap["count"] or len(wanted) != snap["count"]:
        failures.append(
            f"inventory count {len(got)} (manifest) / {len(wanted)} "
            f"(snapshot) != frozen {snap['count']}"
        )
    if got != wanted:
        failures.append(
            "Manifest.modules drifted from tools/inventory_snapshot.json. "
            "A 7.54.1 GUI change must not edit this list. If the inventory "
            "changed on purpose, update the snapshot in its own commit."
        )
        for index, (left, right) in enumerate(zip(wanted, got)):
            if left != right:
                failures.append(f"  #{index}: wanted {left} got {right}")
        if len(got) != len(wanted):
            failures.append(f"  lengths {len(wanted)} vs {len(got)}")

    rel = []
    root_prefix = ROOT.rstrip("/\\") + os.sep
    for dirpath, _dirs, files in os.walk(MODULES_DIR):
        for name in files:
            if not name.endswith(".luau"):
                continue
            full = os.path.join(dirpath, name)
            if full.startswith(root_prefix):
                full = full[len(root_prefix) :]
            rel.append(full.replace("\\", "/"))
    rel = sorted(rel)
    wanted_paths = [row["path"] for row in wanted]
    if rel != sorted(wanted_paths):
        extra = sorted(set(rel) - set(wanted_paths))
        missing = sorted(set(wanted_paths) - set(rel))
        if extra:
            failures.append("unlisted module files: " + ", ".join(extra))
        if missing:
            failures.append("snapshot paths missing on disk: " + ", ".join(missing))

    used = {row["category"] for row in got}
    if not used.issubset(set(OFFICIAL)):
        failures.append(f"non-official categories: {sorted(used - set(OFFICIAL))}")
    occupied = {row["category"] for row in got}
    for empty in snap["emptyOfficial"]:
        if empty in occupied:
            failures.append(f"{empty} must stay empty until a current module lands in it")

    authority = json.load(open(AUTHORITY, encoding="utf-8"))
    if authority.get("identity", {}).get("universalModules") != snap["count"]:
        failures.append("wurst-gui-authority.json must keep universalModules must match the snapshot")
    if authority.get("identity", {}).get("portVersion") != "0.1 Beta":
        failures.append("portVersion must stay 0.1 Beta")
    if authority.get("identity", {}).get("wurstRelease") != "7.19":
        failures.append("identity release must stay 7.19")

    explicit = snap.get("explicitConfigKeys") or {}
    for path, key in explicit.items():
        text = open(os.path.join(ROOT, path), encoding="utf-8").read()
        if f'configKey = "{key}"' not in text:
            failures.append(f"{path} must keep configKey {key}")

    if failures:
        print("inventory freeze broken:")
        for line in failures:
            print("  " + line)
        return 1
    print(f"ok · {snap['count']} universal modules frozen · empty {', '.join(snap['emptyOfficial'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
