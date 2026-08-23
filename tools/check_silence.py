#!/usr/bin/env python3
"""Refuse console-noise escapes outside the shell's own silence gate.

print/warn inside bootstrap() are local shadows gated on
getgenv().ARANDOMMENU_DEBUG. A module or library that reaches for
realPrint/realWarn (or an equivalent getfenv().print capture) bypasses
that gate. The gate itself lives in ARandomMenu.luau and is the only
file allowed to name those locals.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The shell owns the shadows. Everything else — including the packed
# bundle — talking to the real printers is a leak.
ALLOWED = {"ARandomMenu.luau"}

# realPrint / realWarn, and a getfenv().print / getfenv().warn grab that
# would skip the injected shadows.
PATTERN = re.compile(
    r"\breal(?:Print|Warn)\b"
    r"|(?:getfenv\s*\(\s*\)\s*(?:::\s*any\s*)?\.)\s*(?:print|warn)\b"
)


def iter_sources() -> list[str]:
    paths = ["runtime/bundle.luau"]
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "src")):
        for name in files:
            if name.endswith(".luau"):
                full = os.path.join(dirpath, name)
                paths.append(os.path.relpath(full, ROOT).replace("\\", "/"))
    return paths


def main() -> int:
    offenders: list[str] = []
    for rel in iter_sources():
        if rel in ALLOWED:
            continue
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        for match in PATTERN.finditer(text):
            # A comment that remembers the gate is not an escape.
            line_start = text.rfind("\n", 0, match.start()) + 1
            line = text[line_start : text.find("\n", match.start())]
            stripped = line.lstrip()
            if stripped.startswith("--"):
                continue
            number = text.count("\n", 0, match.start()) + 1
            offenders.append(f"{rel}:{number}: {match.group(0)}")
    if offenders:
        print("console-noise escape outside the shell gate:")
        for row in offenders:
            print("  " + row)
        return 1
    print("ok · no realPrint/realWarn escape outside the shell gate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
