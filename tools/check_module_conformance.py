#!/usr/bin/env python3
"""Architecture gates for src/modules/** (D's authoring contract).

Rejects, when armed:
  (a) ScreenGui / PopupLayer reach-ins
  (b) configData keys outside the documented namespaces
  (c) bare print / warn
  (d) direct host.state access
  (e) process-wide engine hooks outside the allowlist

(e) is the one that cannot be reviewed by reading a diff. A `hookmetamethod`
installed by one card sits on a surface every other caller in the client
shares, so "it is only in this module" is not an isolation argument — see
docs/architecture/targeting-and-learning.md. The gate scans src/modules only:
a game adapter under src/games may hook when it says so explicitly, and MVSD's
silent aim is the standing example of what that has to look like.

The gate is blocking. Modules use the shell-owned `isMenuOwned` predicate
instead of reaching into GUI roots, and user-facing diagnostics go through
card status or notifications instead of the executor console.

docs/architecture/modules.md owns the contract. The namespaces below are the
ones the shell and the Spoof pair persist under.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES = os.path.join(ROOT, "src/modules")

# This boundary is release-blocking. Never downgrade it to report-only.
HARD_FAIL = True

ALLOWED_KEY_PREFIXES = (
    "Universal.",
    "UI.",
    "ClickGUI.",
    "Shortcut.",
    "WurstLogo.",
)

SCREEN = re.compile(r"\b(?:ScreenGui|PopupLayer)\b")
# A hook by any of these names changes a closure or a metatable that every
# other caller in the process reads. `getrawmetatable` is a read and stays
# allowed; `newcclosure` wraps a closure without replacing anybody else's.
HOOK = re.compile(
    r"\b(?:hookfunction|hookmetamethod|hookproperty|hookconstructor"
    r"|replaceclosure|setrawmetatable)\b"
)

# One entry per module allowed to install a hook, with the owner and the
# condition that removes it. Adding a line here is the review, so it does not
# happen by accident in a diff.
HOOK_ALLOWLIST = {
    # Remote Logger exists to watch the game call its own remotes, which is
    # only observable from __namecall. Owner: D.
    # Removal condition: an observation path that does not need a metamethod,
    # or the card leaving the default inventory.
    "src/modules/Utility/RemoteLogger.luau",
}
PRINT = re.compile(r"\b(?:print|warn)\s*\(")
HOST_STATE = re.compile(r"\bhost\s*\.\s*state\b")
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

    for match in HOST_STATE.finditer(text):
        line_no = text.count("\n", 0, match.start()) + 1
        line = text.splitlines()[line_no - 1]
        if not is_code(line):
            continue
        findings.append(f"{rel}:{line_no}: direct host.state access")

    if rel not in HOOK_ALLOWLIST:
        for match in HOOK.finditer(text):
            line_no = text.count("\n", 0, match.start()) + 1
            line = text.splitlines()[line_no - 1]
            if not is_code(line):
                continue
            findings.append(
                f"{rel}:{line_no}: process-wide hook {match.group(0)} needs an "
                "allowlist entry with an owner and a removal condition"
            )

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
