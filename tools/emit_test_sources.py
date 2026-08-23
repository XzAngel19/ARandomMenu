#!/usr/bin/env python3
"""Emit the generated Luau modules the headless CLI tests require.

The Luau CLI has no filesystem API, so validate.sh writes the shell, the
bundle and the inventory snapshot as modules next to tools/test/run.luau.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def emit_string_module(src: Path, dest: Path) -> None:
    source = src.read_text()
    level = 0
    while ("]" + "=" * level + "]") in source:
        level += 1
    eq = "=" * level
    dest.write_text(
        "--!strict\n"
        "-- Emitted for the headless tests; the CLI has no file API.\n"
        f"return [{eq}[\n{source}\n]{eq}]\n"
    )


def emit_inventory(dest: Path) -> None:
    snap = json.loads((ROOT / "tools/inventory_snapshot.json").read_text())

    def lit(value: str) -> str:
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

    names = ", ".join(lit(module["name"]) for module in snap["modules"])
    paths = ", ".join(lit(module["path"]) for module in snap["modules"])
    dest.write_text(
        "--!strict\n"
        "-- Emitted from tools/inventory_snapshot.json; the CLI has no file API.\n"
        "return {\n"
        f"    count = {snap['count']},\n"
        f"    names = {{{names}}},\n"
        f"    paths = {{{paths}}},\n"
        "}\n"
    )


def main() -> None:
    test_dir = ROOT / "tools/test"
    emit_string_module(ROOT / "ARandomMenu.luau", test_dir / "_shell_source.luau")
    emit_string_module(ROOT / "runtime/bundle.luau", test_dir / "_bundle_source.luau")
    emit_inventory(test_dir / "_inventory_snapshot.luau")


if __name__ == "__main__":
    main()
