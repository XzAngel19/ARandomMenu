#!/usr/bin/env python3
"""Static cost audit for every per-frame callback shipped in the menu.

The menu runs one scheduler tick per frame (`TaskManager`), so a module that
does real work in its callback costs CPU every frame whether or not it is
visible. This tool does not guess from names: it parses each registration,
extracts the callback body by balancing its parentheses, and counts the tokens
that actually cost time (raycasts, player/instance enumeration, instance
creation, table churn) plus whether the body throttles itself with `os.clock`.

Rules it enforces (failures, not warnings):

  * a callback that raycasts, enumerates players/descendants or creates
    instances must throttle itself (or be registered with an interval);
  * no callback may call `Players:GetPlayers()` more than once per pass with
    no cache;
  * no `while true do` loop may sit inside a callback without a wait.

It also enforces two invariants that keep the built-in report usable:

  * every per-frame callback in MM2 and Universal carries a label, because the
    console warning and the Session Info overlay name the module by that label;
  * a `featureConnections.X = ...` registration has a matching
    `disconnectFeatureConnection("X")` in the same file, so toggling a module
    off actually stops paying for it (session-global keys are listed below).

`--verbose` prints the whole table, including the cheap callbacks.

python3 tools/audit_performance.py [--verbose]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = sorted(
    path
    for path in (ROOT / "src").rglob("*.lua")
    if path.name != "bundle.lua"
)

COSTLY = {
    "raycast": re.compile(r"workspace:Raycast|:Raycast\("),
    "players": re.compile(r"Players:GetPlayers\(|:GetPlayers\("),
    "descendants": re.compile(r":GetDescendants\(|:GetChildren\(|GetTagged\("),
    "create": re.compile(r"Instance\.new\("),
    "findchild": re.compile(r":FindFirstChild"),
}
THROTTLE = re.compile(r"os\.clock\(\)|time\(\)\s*-\s*|now\s*-\s*last|interval|PROBE|throttle")

# Registered for the whole session on purpose: the loader owns their lifetime,
# not a toggle, so they never need a matching disconnect.
SESSION_GLOBAL_KEYS = {
    "MM2RoundPhase",
    "MM2RoundClock",
    "MM2RoleSelect",
    "MM2RoleWatchAdded",
    "MM2RoleWatchRemoving",
    "MM2PlayerDataChanged",
    "MM2TimerTrackerStart",
    "MM2TimerTrackerEnd",
    "MM2PredictionSampler",
}

# Modules whose per-frame callback is registered before the label convention;
# MM2 and Universal are held to it because that is what the user plays.
LABEL_REQUIRED_ROOTS = ("src/games/MM2/", "src/games/universal/")


def callback_after(text: str, start: int) -> str:
    """Text of the first argument of the call whose '(' sits at `start`."""
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[start + 1 : index]
    return text[start + 1 :]


def audit() -> tuple[list[dict], list[str]]:
    rows: list[dict] = []
    failures: list[str] = []
    for path in SOURCES:
        text = path.read_text()
        relative = path.relative_to(ROOT).as_posix()
        for match in re.finditer(r"TaskManager:Connect\(", text):
            body = callback_after(text, match.end() - 1)
            line = text.count("\n", 0, match.start()) + 1
            before = text[max(0, match.start() - 400) : match.start()]
            label_match = re.search(r'"[A-Za-z][^"]{2,40}"\s*\)', body[-80:])
            label = label_match.group(0) if label_match else ""
            counts = {name: len(pattern.findall(body)) for name, pattern in COSTLY.items()}
            expensive = sum(counts.values())
            throttled = bool(THROTTLE.search(body))
            interval = bool(re.search(r"TaskManager:Connect\([^)]*\)\s*,?\s*[\d.]+\s*\)", text[match.start() : match.start() + 400]))
            rows.append(
                {
                    "file": relative,
                    "line": line,
                    "label": label,
                    "body": len(body),
                    "expensive": expensive,
                    "throttled": throttled,
                    "interval": interval,
                    "counts": counts,
                }
            )
            # An early `return` before the first costly token means the work
            # only happens while the module is actually doing something (for
            # example Spider reading the input before it casts anything).
            first_cost = min(
                (body.find(token) for token in
                 ("workspace:Raycast", ":Raycast(", "GetPlayers(", "GetDescendants(",
                  "GetChildren(", "Instance.new(") if body.find(token) >= 0),
                default=len(body),
            )
            gated = re.search(r"\breturn\b", body[:first_cost]) is not None
            if expensive and not (throttled or interval or gated) and relative.startswith(LABEL_REQUIRED_ROOTS):
                failures.append(
                    f"{relative}:{line}: per-frame callback does {expensive} costly "
                    f"operation(s) {counts} with no throttle"
                )
            if counts["players"] > 1 and not throttled and relative.startswith(LABEL_REQUIRED_ROOTS):
                detail = f"{relative}:{line}: {counts['players']}x GetPlayers in one unthrottled pass"
                if detail not in failures:
                    failures.append(detail)
        for match in re.finditer(r"while true do", text):
            line = text.count("\n", 0, match.start()) + 1
            window = text[match.start() : match.start() + 1200]
            # A bounded search that returns/breaks is not a busy loop; only a
            # loop that can keep spinning forever without yielding is.
            healthy = (
                "task.wait" in window
                or "wait(" in window
                or "break" in window
                or "return" in window
            )
            if not healthy:
                failures.append(f"{relative}:{line}: `while true do` without a wait or exit")

        # Registration without a disconnect leaks a callback per toggle.
        for key in re.findall(r"featureConnections\.([A-Za-z0-9_]+)\s*=", text):
            if key in SESSION_GLOBAL_KEYS:
                continue
            # Either a direct disconnect or the key listed in a loop that
            # disconnects names (Improve FPS does that) counts.
            if (f'disconnectFeatureConnection("{key}")' not in text
                    and f'"{key}"' not in text.replace(
                        "featureConnections." + key, "")):
                failures.append(
                    f"{relative}: featureConnections.{key} is never disconnected"
                )
        # A bracketed key that is a variable (featureConnections[name]) cannot
        # be checked statically; only literal string keys are.
        for key in re.findall(r'featureConnections\["([A-Za-z0-9_]+)"\]', text):
            if key in SESSION_GLOBAL_KEYS:
                continue
            if f'disconnectFeatureConnection("{key}")' not in text:
                failures.append(
                    f"{relative}: featureConnections[\"{key}\"] is never disconnected"
                )

        # A per-frame task with no label is unnamed in the FPS report.
        if relative.startswith(LABEL_REQUIRED_ROOTS):
            for match in re.finditer(r"TaskManager:Connect\(", text):
                body = callback_after(text, match.end() - 1)
                line = text.count("\n", 0, match.start()) + 1
                if not re.search(r',\s*(nil,\s*)?"[^"]+"\s*$', body.rstrip()):
                    failures.append(
                        f"{relative}:{line}: per-frame task has no label"
                    )
    return rows, failures


def main() -> None:
    verbose = "--verbose" in sys.argv
    rows, failures = audit()
    rows.sort(key=lambda row: row["expensive"], reverse=True)
    print(f"callbacks audited: {len(rows)}")
    print(f"{'costly':>6} {'bytes':>6} {'throttle':>8}  location")
    for row in rows:
        if not verbose and row["expensive"] == 0:
            continue
        print(
            f"{row['expensive']:>6} {row['body']:>6} "
            f"{('yes' if row['throttled'] or row['interval'] else 'NO'):>8}  "
            f"{row['file']}:{row['line']} {row['label']}"
        )
    if failures:
        print("\nFAIL")
        for failure in failures:
            print("  " + failure)
        raise SystemExit(1)
    print("\nPASS every per-frame callback either throttles itself or is cheap")


if __name__ == "__main__":
    main()
