#!/usr/bin/env python3
"""Generate (or verify) the single-file Speed Hub X bundle.

The modular sources live in src/guis/SpeedHubX/Modules/. Executors run a
single script, so this tool inlines every module into
src/guis/SpeedHubX/SpeedHubX.lua behind a tiny factory registry. The
generated file needs no HttpGet / require / external assets at runtime.

Usage:
    python3 tools/build_speedhubx_bundle.py           # regenerate
    python3 tools/build_speedhubx_bundle.py --check   # exit 1 when stale
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES_DIR = ROOT / "src" / "guis" / "SpeedHubX" / "Modules"
BUNDLE = ROOT / "src" / "guis" / "SpeedHubX" / "SpeedHubX.lua"

# Dependency order (also the order factories are wired in the footer).
MODULES: list[tuple[str, str]] = [
    ("Theme", "Theme.luau"),
    ("Util", "Util.luau"),
    ("Features", "Features.luau"),
    ("Controls", "Controls.luau"),
    ("Window", "Window.luau"),
    ("Pages/Home", "Pages/Home.luau"),
    ("Pages/Main", "Pages/Main.luau"),
    ("Pages/Farming", "Pages/Farming.luau"),
    ("Pages/Killer", "Pages/Killer.luau"),
    ("Pages/Misc", "Pages/Misc.luau"),
    ("Bootstrap", "Bootstrap.luau"),
]

HEADER = """-- Speed Hub X | Version: 3.7.0 -- standalone executor GUI (UI replica)
-- GENERATED FILE -- do not edit by hand.
-- Sources: src/guis/SpeedHubX/Modules/  |  Regenerate:
--   python3 tools/build_speedhubx_bundle.py
--
-- Run in a live Roblox client via a script executor, e.g.:
--   loadstring(game:HttpGet("<url to this file>"))()
-- or paste/execute the whole file directly. Re-running replaces the old menu.
-- All feature callbacks are EMPTY STUBS (Modules/Features.luau): this is a
-- GUI replica only, no gameplay/combat/farming/automation logic is included.
"""

FOOTER = """
-- ---------------------------------------------------------------------------
-- Composition root: wire module factories with their dependencies.
-- (Mirrors the manual wiring documented in README.md.)
-- ---------------------------------------------------------------------------
local Theme = __factories["Theme"]({})
local Util = __factories["Util"]({})
local Bucket = Util.connectionBucket()
local Features = __factories["Features"]({})
local Controls = __factories["Controls"]({ Theme = Theme, Util = Util, Bucket = Bucket })
local Window = __factories["Window"]({ Theme = Theme, Util = Util, Bucket = Bucket })
local Pages = {
    Home = __factories["Pages/Home"]({ Controls = Controls, Features = Features }),
    Main = __factories["Pages/Main"]({ Controls = Controls, Features = Features }),
    Farming = __factories["Pages/Farming"]({ Controls = Controls, Features = Features }),
    Killer = __factories["Pages/Killer"]({ Controls = Controls, Features = Features }),
    Misc = __factories["Pages/Misc"]({ Controls = Controls, Features = Features }),
}
local Bootstrap = __factories["Bootstrap"]({
    Theme = Theme, Util = Util, Features = Features,
    Window = Window, Pages = Pages, Bucket = Bucket,
})

return Bootstrap()
"""


def render() -> str:
    out = [HEADER, "local __factories = {}\n"]
    for name, rel in MODULES:
        source = (MODULES_DIR / rel).read_text(encoding="utf-8").rstrip("\n")
        out.append(f'\n-- ===== Module: {name} (Modules/{rel}) =====')
        out.append(f'__factories["{name}"] = (function()')
        out.append(source)
        out.append("end)()")
    out.append(FOOTER)
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if bundle is stale")
    args = parser.parse_args()

    expected = render()
    if args.check:
        current = BUNDLE.read_text(encoding="utf-8") if BUNDLE.exists() else ""
        if current != expected:
            print(f"STALE: {BUNDLE.relative_to(ROOT)} -- run: python3 tools/build_speedhubx_bundle.py")
            return 1
        print(f"OK: {BUNDLE.relative_to(ROOT)} is up to date")
        return 0

    BUNDLE.write_text(expected, encoding="utf-8")
    print(f"Wrote {BUNDLE.relative_to(ROOT)} ({len(expected.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
