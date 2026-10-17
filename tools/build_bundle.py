#!/usr/bin/env python3
"""Regenerate (or verify) src/libraries/bundle.lua.

The runtime ships every source file inside a single Lua table so an executor
that cannot HttpGet still boots from memory. Whenever a module changes the
bundle has to be rebuilt *and* the stamp bumped, otherwise
`Wurst.fetchRepositorySource` keeps serving the previous copy and the user
silently runs stale code.

Usage:
    python3 tools/build_bundle.py --stamp v3-20261011-1800
    python3 tools/build_bundle.py --check          # exit 1 when out of date
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
BUNDLE = SRC / "libraries" / "bundle.lua"
EXCLUDED = {"src/libraries/bundle.lua", "src/Wurst.lua"}


def collect_sources() -> dict[str, str]:
    files: dict[str, str] = {}
    for path in sorted(SRC.rglob("*.lua")):
        rel = path.relative_to(ROOT).as_posix()
        if rel in EXCLUDED:
            continue
        files[rel] = path.read_text(encoding="utf-8")
    return files


def long_bracket(body: str) -> str:
    """Return a Lua long string that cannot be closed by the body itself."""
    level = 0
    while True:
        closing = "]" + "=" * level + "]"
        opening = "[" + "=" * level + "["
        if closing not in body and not body.startswith("="):
            # Lua also refuses `[===[` immediately followed by `=`, which is
            # only a problem for the opening sequence itself.
            if opening + "=" not in body:
                return f"{opening}\n{body}\n{closing}"
        level += 1


def render(files: dict[str, str], stamp: str) -> str:
    out = ["return {", f'    stamp = "{stamp}",', "    files = {"]
    for rel in sorted(files):
        out.append(f"        [{long_string_key(rel)}] = {long_bracket(files[rel])},")
    out.append("    },")
    out.append("}")
    return "\n".join(out) + "\n"


def long_string_key(key: str) -> str:
    return '"' + key.replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse_bundle(text: str) -> tuple[str | None, dict[str, str]]:
    stamp_match = re.search(r'stamp\s*=\s*"([^"]+)"', text)
    stamp = stamp_match.group(1) if stamp_match else None
    files: dict[str, str] = {}
    pattern = re.compile(
        r'\["([^"]+)"\]\s*=\s*\[(=*)\[\n(.*?)\n\]\2\],',
        re.DOTALL,
    )
    for match in pattern.finditer(text):
        files[match.group(1)] = match.group(3)
    return stamp, files


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stamp", default=None, help="stamp written into bundle.lua")
    parser.add_argument("--check", action="store_true", help="verify instead of writing")
    args = parser.parse_args()

    disk = collect_sources()

    if args.check:
        if not BUNDLE.exists():
            print("bundle.lua is missing")
            return 1
        bundle_stamp, bundled = parse_bundle(BUNDLE.read_text(encoding="utf-8"))
        problems: list[str] = []
        if bundle_stamp != args.stamp and args.stamp:
            problems.append(f"stamp {bundle_stamp} != {args.stamp}")
        for rel, body in disk.items():
            if rel not in bundled:
                problems.append(f"missing  {rel}")
            elif digest(bundled[rel]) != digest(body):
                problems.append(f"stale    {rel}")
        for rel in bundled:
            if rel not in disk:
                problems.append(f"orphan   {rel}")
        if problems:
            print("\n".join(problems))
            print(f"\n{len(problems)} problem(s): bundle is out of date")
            return 1
        print(f"bundle.lua is current: {len(disk)} files, stamp {bundle_stamp}")
        return 0

    stamp = args.stamp
    if not stamp:
        existing, _ = parse_bundle(BUNDLE.read_text(encoding="utf-8")) if BUNDLE.exists() else (None, {})
        stamp = existing or "dev"
    BUNDLE.write_text(render(disk, stamp), encoding="utf-8")
    print(f"wrote {BUNDLE.relative_to(ROOT)}: {len(disk)} files, stamp {stamp}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
