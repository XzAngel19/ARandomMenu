#!/usr/bin/env python3
"""Bundle violent-ui/src/*.lua into the single-file dist/Violent.lua.

The source stays modular for editing and review; the bundle is what a script
executor runs. Modules are wrapped in a tiny define/require registry, so the
output is fully self-contained and does not depend on the executor's require.

Usage:
    python3 violent-ui/build.py            # write dist/Violent.lua
    python3 violent-ui/build.py --check    # exit 1 if the bundle is stale
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "dist" / "Violent.lua"

# Dependency-safe order; factories run lazily, so this is documentation as
# much as it is build order.
MODULES = [
    "Theme",
    "Util",
    "State",
    "Stubs",
    "Controls",
    "Window",
    "Page",
    "Preview",
    "Menu",
    "Main",
]

HEADER = """--[[
    VIOLENT — standalone client-sided Luau menu (UI replica of the reference)

    GENERATED FILE. Edit violent-ui/src/*.lua and run:
        python3 violent-ui/build.py

    Usage (script executor):
        loadstring(game:HttpGet("<raw url to this file>"))()

    Or paste this whole file into the executor's editor and run it.

    Visibility : RightShift toggles both windows.
    Teardown   : getgenv().VIOLENT_UI.Destroy()

    Every feature callback is an intentionally empty stub (see Stubs.lua).
    The script draws the interface only; it performs no game actions.
]]

local __defs, __cache = {}, {}

local function define(name, factory)
    __defs[name] = factory
end

local function require(name)
    local cached = __cache[name]
    if cached ~= nil then
        return cached
    end
    local factory = __defs[name]
    assert(factory ~= nil, "[VIOLENT] missing module: " .. tostring(name))
    local module = factory()
    __cache[name] = module
    return module
end
"""

FOOTER = '\nreturn require("Main")\n'


def render() -> str:
    chunks = [HEADER]
    for name in MODULES:
        path = SRC / f"{name}.lua"
        if not path.is_file():
            raise SystemExit(f"missing module source: {path}")
        source = path.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")
        chunks.append(f'\ndefine("{name}", function()\n{source}\nend)\n')
    chunks.append(FOOTER)
    return "".join(chunks)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    bundle = render()
    if args.check:
        current = OUT.read_text(encoding="utf-8") if OUT.is_file() else ""
        if current != bundle:
            print("dist/Violent.lua is out of date; run python3 violent-ui/build.py", file=sys.stderr)
            return 1
        print("dist/Violent.lua is up to date")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(bundle, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT.parent)} ({len(bundle)} bytes, {len(MODULES)} modules)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
