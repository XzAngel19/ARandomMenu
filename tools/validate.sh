#!/usr/bin/env bash
# Reproducible local/CI checks for the modular Wurst runtime.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build

# The toolchain is vendored in this branch: tools/luau/vendor holds the pinned
# wasm packages (Luau 739, StyLua 2.6, DarkLua 0.19, valibot) and
# tools/luau/setup.sh unpacks them into tools/luau/node_modules. A fresh clone
# (or a wiped sandbox) only needs node, not npm and not network.
if [ ! -x tools/luau/bin/luau ] || [ ! -d tools/luau/node_modules/@johnnymorganz/stylua ] \
    || [ ! -d tools/luau/node_modules/darklua-wasm ]; then
    if [ -f tools/luau/vendor/luau-rs-luau-0.739.0.tgz ]; then
        bash tools/luau/setup.sh >/dev/null
    fi
fi
if [ -z "${LUAU:-}" ] && [ -x tools/luau/bin/luau ]; then
    LUAU="tools/luau/bin/luau"
fi
if [ -z "${LUAU_COMPILE:-}" ] && [ -x tools/luau/bin/luau-compile ]; then
    LUAU_COMPILE="tools/luau/bin/luau-compile"
fi
LUAU="${LUAU:-${LUAU_DIR:+$LUAU_DIR/}luau}"
LUAU_COMPILE="${LUAU_COMPILE:-${LUAU_DIR:+$LUAU_DIR/}luau-compile}"
for tool in "$LUAU" "$LUAU_COMPILE"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing Luau tool: $tool. Set LUAU_DIR or LUAU/LUAU_COMPILE." >&2
        exit 1
    fi
done
export LUAU
# The source tree is UTF-8; on Windows Python otherwise opens it as cp1252.
export PYTHONUTF8=1

stamp="$(python3 -c 'import re; from pathlib import Path; print(re.search(r"local SOURCE_STAMP: string = \"([^\"]+)\"", Path("src/Wurst.lua").read_text()).group(1))')"
python3 tools/build_bundle.py --check --stamp "$stamp"

sources=0
while IFS= read -r -d '' source; do
    "$LUAU_COMPILE" "$source" >/dev/null
    sources=$((sources + 1))
done < <(find src -name '*.lua' -print0)
echo "PASS $sources Lua sources compile"

# Static analysis: the same Luau front end as luau-analyze, fed with the Roblox
# definitions (tools/luau/definitions/core.d.luau) and the executor/host globals
# (runtime.d.luau). Errors are the gate; lints print but never fail the build.
if [ -x tools/luau/bin/luau-analyze ]; then
    node tools/luau/analyze.mjs --baseline >build/analyze.txt 2>build/analyze.summary.txt || {
        grep -v "^warn" build/analyze.summary.txt >&2 || true
        cat build/analyze.txt
        echo "analyze: new type errors above (see tools/luau/analyze-baseline.json)" >&2
        exit 1
    }
    tail -1 build/analyze.summary.txt
fi

# Formatting is per-change, not per-tree: the sources predate StyLua and a full
# reformat rewrites constructs the Python suites assert on as text (a table type
# `{[string]: any}` becomes `{ [string]: any }`, and three suites match that
# text). The gate therefore checks only the files a change passes in
# STYLUA_FILES; a full-tree run is `tools/luau/bin/luau-format .
if [ -x tools/luau/bin/luau-format ] && [ -n "${STYLUA_FILES:-}" ]; then
    # shellcheck disable=SC2086
    node tools/luau/format.mjs --check $STYLUA_FILES >build/format.txt 2>&1 || {
        tail -20 build/format.txt
        echo "format: run tools/luau/bin/luau-format <file> on the files above" >&2
        exit 1
    }
    tail -1 build/format.txt
fi

# v138.9: one catalog. tools/card.py is the front door to it (add/remove/window)
# and this checks the catalog against the disk before anything else runs.
python3 tools/card.py check

# Per-frame cost audit: every callback that runs 60 times a second is counted,
# and one that raycasts or enumerates instances must throttle itself. Also
# checks that each toggle can actually disconnect what it registered and that
# every MM2/Universal task is named in the FPS report.
python3 tools/audit_performance.py >build/performance_audit.txt 2>&1 || {
    cat build/performance_audit.txt
    exit 1
}
tail -1 build/performance_audit.txt

suites=0
for suite in tools/test_*.py; do
    python3 "$suite"
    suites=$((suites + 1))
done
echo "PASS $suites Python/Luau suites"

python3 tools/gen_full_boot_harness.py
"$LUAU" build/full_boot.luau >build/full_boot.log 2>&1 || { cat build/full_boot.log; exit 1; }
grep -F 'Load complete · failures=0' build/full_boot.log
grep -F '[HARNESS] done' build/full_boot.log
echo 'PASS bundle boot, silent startup, native controls and cleanup assertions'

python3 tools/audit_module_api.py
echo 'PASS cross-module API: every core.*/prediction.* call resolves'

# The menu that the bundle builds, not the names that appear in the source: a
# module can compile, ship and never register. Registering a card is a user
# visible change, so the count is asserted.
python3 tools/audit_menu.py >build/menu_audit.md 2>&1 || { cat build/menu_audit.md; exit 1; }
cards="$(grep -E '^[0-9]+ cards total' build/menu_audit.md | cut -d' ' -f1)"
[ -n "$cards" ] || { cat build/menu_audit.md; exit 1; }
echo "PASS menu audit: $cards cards, every row dumped from the booted bundle"

# Release/debug build the same cards; Calibration is a popup, not a card.
python3 tools/audit_menu.py --release >build/menu_release.md 2>&1 || { cat build/menu_release.md; exit 1; }
release_cards="$(grep -E '^[0-9]+ cards total' build/menu_release.md | cut -d' ' -f1)"
[ -n "$release_cards" ] || { cat build/menu_release.md; exit 1; }
if [ "$release_cards" -ne "$cards" ]; then
    cat build/menu_release.md
    echo "release boot has $release_cards cards, debug boot has $cards" >&2
    exit 1
fi
if grep -q '^\- \*\*Calibration\*\*' build/menu_release.md; then
    cat build/menu_release.md
    echo "Calibration must not have a visible card" >&2
    exit 1
fi
echo "PASS release menu: $release_cards cards, Calibration is popup-only"

# Toolchain gates: the vendored Luau/StyLua/DarkLua toolchain itself. These run
# last because they are the ones that would explain a broken run above.
python3 tools/luau/definitions/build_definitions.py --check
echo 'PASS Roblox definitions: generated subset still matches the pinned dump'

python3 tools/test_luau_toolchain.py
