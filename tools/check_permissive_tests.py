#!/usr/bin/env python3
"""Refuse new permissive historical greens in active suites.

A check whose label says "waits on A" / "not published yet" / "demonstrated
debt" converts missing behaviour into a passing number. C7 retired those
branches. This gate holds the retirement.

Allowlisted lines live in tools/test/permissive-allowlist.txt as
`suite-file:phrase`. Keep that file short. Do not add a dictionary of
Spanish or a list of identifiers.
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUITES = os.path.join(ROOT, "tools/test/suites")
ALLOWLIST = os.path.join(ROOT, "tools/test/permissive-allowlist.txt")

# Phrases that historically turned a gap into `check(..., true)`.
BANNED = (
    "waits on A",
    "not published yet",
    "demonstrated debt",
    "not on disk yet",
    "tests wait on",
    "wait on it",
    "waits on boot",
    "waits on a populated",
    "APPLY-4 waits",
    "waits on close",
    "waits on unpublished",
    "hide waits on A",
    "landing it on Cards",
    "full search waits on",
    "wiring KeyCode.",
)


def load_allowlist() -> set[tuple[str, str]]:
    allowed: set[tuple[str, str]] = set()
    if not os.path.exists(ALLOWLIST):
        return allowed
    for raw in open(ALLOWLIST, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise SystemExit(
                "permissive allowlist line must be suite:phrase: " + line
            )
        suite, phrase = line.split(":", 1)
        allowed.add((suite.strip(), phrase.strip()))
    return allowed


def main() -> int:
    allowed = load_allowlist()
    offenders: list[str] = []
    for name in sorted(os.listdir(SUITES)):
        if not name.endswith(".luau"):
            continue
        path = os.path.join(SUITES, name)
        text = open(path, encoding="utf-8", errors="replace").read()
        for phrase in BANNED:
            if phrase not in text:
                continue
            if (name, phrase) in allowed:
                continue
            line = text.count("\n", 0, text.index(phrase)) + 1
            offenders.append(f"{name}:{line}: {phrase!r}")
    if offenders:
        print("permissive historical green reintroduced:")
        for row in offenders:
            print("  " + row)
        print("  retire the branch, or add suite:phrase to")
        print("  tools/test/permissive-allowlist.txt for a real staged gap")
        return 1
    print("ok · no unallowlisted permissive suite phrases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
