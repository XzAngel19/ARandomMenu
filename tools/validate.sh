#!/usr/bin/env bash
# Reproducible local/CI checks for the modular Wurst runtime.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The toolchain is vendored in this branch: tools/luau/vendor holds the pinned
# wasm package and tools/luau/setup.sh unpacks it into tools/luau/node_modules.
# A fresh clone (or a wiped sandbox) only needs node, not npm and not network.
if [ ! -x tools/luau/bin/luau ] && [ -f tools/luau/vendor/luau-rs-luau-0.739.0.tgz ]; then
    bash tools/luau/setup.sh >/dev/null
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

# A release boot must not build the developer capture card. This runs the
# bundle with WURST_DEBUG=false and checks the card is absent, not hidden.
python3 tools/audit_menu.py --release >build/menu_release.md 2>&1 || { cat build/menu_release.md; exit 1; }
release_cards="$(grep -E '^[0-9]+ cards total' build/menu_release.md | cut -d' ' -f1)"
[ -n "$release_cards" ] || { cat build/menu_release.md; exit 1; }
# The only difference between the two boots is the debug capture card.
if [ "$release_cards" -ne "$((cards - 1))" ]; then
    cat build/menu_release.md
    echo "release boot has $release_cards cards, expected $((cards - 1))" >&2
    exit 1
fi
if grep -q 'Calibration' build/menu_release.md; then
    cat build/menu_release.md
    echo "release boot built the debug Calibration card" >&2
    exit 1
fi
echo "PASS release menu: $release_cards cards, no Calibration card"
