#!/usr/bin/env python3
"""Architecture gates for src/modules/** (D's authoring contract).

Rejects, when armed:
  (a) ScreenGui / PopupLayer reach-ins
  (b) configData keys outside the documented namespaces
  (c) bare print / warn

The tree is not clean today (KillAura/AutoClicker parent onto host.ScreenGui;
ProjectileCalibration, RejoinServer and RemoteLogger still print). Report-only
until that commit; HARD_FAIL flips in the same commit the last finding dies.

docs/architecture/modules.md is D's to write. The namespaces below are the
ones the shell and the Spoof pair already persist under.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES = os.path.join(ROOT, "src/modules")

# Flip to True in the commit that clears the last finding below.
HARD_FAIL = False

ALLOWED_KEY_PREFIXES = (
    "Universal.",
    "UI.",
    "ClickGUI.",
    "Shortcut.",
    "WurstLogo.",
)

SCREEN = re.compile(r"\b(?:ScreenGui|PopupLayer)\b")
PRINT = re.compile(r"\b(?:print|warn)\s*\(")
SAVED_KEY = re.compile(r'(?:local\s+)?SAVED_KEY\s*:\s*string\s*=\s*"([^"]+)"')
CONFIG_INDEX = re.compile(
    r'(?:configData|store)\s*\.\s*(?:values|states)\s*\[\s*"([^"]+)"\s*\]'
)
CONFIG_SAVED = re.compile(
    r"(?:configData|store)\s*\.\s*(?:values|states)\s*\[\s*SAVED_KEY\s*\]"
)


def is_code(line: str) -> bool:
    stripped = line.lstrip()
    return stripped != "" and not stripped.startswith("--")


def module_files() -> list[str]:
    found: list[str] = []
    for dirpath, _dirs, files in os.walk(MODULES):
        for name in files:
            if name.endswith(".luau"):
                full = os.path.join(dirpath, name)
                found.append(os.path.relpath(full, ROOT).replace("\\", "/"))
    return sorted(found)


def scan(rel: str) -> list[str]:
    path = os.path.join(ROOT, rel)
    text = open(path, encoding="utf-8", errors="replace").read()
    findings: list[str] = []
    saved: dict[str, str] = {}
    for match in SAVED_KEY.finditer(text):
        saved[match.group(1)] = match.group(1)

    for match in SCREEN.finditer(text):
        line_no = text.count("\n", 0, match.start()) + 1
        line = text.splitlines()[line_no - 1]
        if not is_code(line):
            continue
        findings.append(f"{rel}:{line_no}: ScreenGui/PopupLayer reach-in ({match.group(0)})")

    for match in PRINT.finditer(text):
        line_no = text.count("\n", 0, match.start()) + 1
        line = text.splitlines()[line_no - 1]
        if not is_code(line):
            continue
        findings.append(f"{rel}:{line_no}: bare {match.group(0).strip()}")

    keys: list[tuple[int, str]] = []
    for match in CONFIG_INDEX.finditer(text):
        line_no = text.count("\n", 0, match.start()) + 1
        line = text.splitlines()[line_no - 1]
        if is_code(line):
            keys.append((line_no, match.group(1)))
    if CONFIG_SAVED.search(text):
        for key in saved:
            # Attribute the SAVED_KEY write to its declaration line.
            decl = text.find(f'"{key}"')
            line_no = text.count("\n", 0, decl) + 1 if decl >= 0 else 1
            keys.append((line_no, key))

    for line_no, key in keys:
        if any(key.startswith(prefix) for prefix in ALLOWED_KEY_PREFIXES):
            continue
        findings.append(
            f"{rel}:{line_no}: config key {key!r} is outside "
            + "/".join(ALLOWED_KEY_PREFIXES)
        )
    return findings


def main() -> int:
    findings: list[str] = []
    for rel in module_files():
        findings.extend(scan(rel))
    if not findings:
        print("ok · src/modules conforms; hard-fail is armed")
        return 0
    mode = "hard-fail" if HARD_FAIL else "report-only"
    print(f"{mode} · {len(findings)} module-contract finding(s):")
    for row in findings:
        print("  " + row)
    if HARD_FAIL:
        return 1
    print("  (report-only until the tree is clean; see docs/architecture/C-conformance.md)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
