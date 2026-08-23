#!/usr/bin/env python3
"""Refuse the Spanish runtime phrases the integrator already removed.

English is the product language (docs/design/PORT-DIRECTION.md). This
gate is not a Spanish dictionary: it only matches the concrete phrases
in tools/runtime_language_banned.txt, and only inside quoted string
literals of the files a player can actually hit.

To extend: add one phrase per line to the banned list. Comments start
with #. Do not add identifiers or third-party reference files.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANNED_FILE = os.path.join(ROOT, "tools/runtime_language_banned.txt")

STRING_LITERAL = re.compile(
    r'"(?:\\.|[^"\\])*"'
    r"|'(?:\\.|[^'\\])*'"
)

SCAN_FILES = ("ARandomMenu.luau", "loadstring")
SCAN_DIRS = (
    os.path.join(ROOT, "src/library"),
    os.path.join(ROOT, "src/modules"),
    os.path.join(ROOT, "src/games"),
)


def load_phrases() -> list[str]:
    phrases: list[str] = []
    for raw in open(BANNED_FILE, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        phrases.append(line)
    return phrases


def iter_targets() -> list[str]:
    paths: list[str] = []
    for name in SCAN_FILES:
        full = os.path.join(ROOT, name)
        if os.path.exists(full):
            paths.append(os.path.relpath(full, ROOT).replace("\\", "/"))
    for folder in SCAN_DIRS:
        if not os.path.isdir(folder):
            continue
        for dirpath, _dirs, files in os.walk(folder):
            for name in files:
                if name.endswith(".luau") or name.endswith(".lua"):
                    full = os.path.join(dirpath, name)
                    paths.append(os.path.relpath(full, ROOT).replace("\\", "/"))
    return paths


def main() -> int:
    phrases = load_phrases()
    if not phrases:
        print("runtime-language gate has no phrases; nothing to hold")
        return 1
    offenders: list[str] = []
    for rel in iter_targets():
        text = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
        for match in STRING_LITERAL.finditer(text):
            literal = match.group(0)
            for phrase in phrases:
                if phrase in literal:
                    line = text.count("\n", 0, match.start()) + 1
                    offenders.append(f"{rel}:{line}: {phrase!r}")
                    break
    if offenders:
        print("Spanish runtime phrase reintroduced:")
        for row in offenders:
            print("  " + row)
        print("  add a line to tools/runtime_language_banned.txt only when a")
        print("  player-visible Spanish string is deleted, not as a dictionary")
        return 1
    print(f"ok · {len(phrases)} banned Spanish runtime phrases held")
    return 0


if __name__ == "__main__":
    sys.exit(main())
