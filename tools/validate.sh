#!/usr/bin/env bash
# Reproducible local/CI checks for the modular Wurst runtime.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

LUAU="${LUAU:-${LUAU_DIR:+$LUAU_DIR/}luau}"
LUAU_COMPILE="${LUAU_COMPILE:-${LUAU_DIR:+$LUAU_DIR/}luau-compile}"
for tool in "$LUAU" "$LUAU_COMPILE"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing Luau tool: $tool. Set LUAU_DIR or LUAU/LUAU_COMPILE." >&2
        exit 1
    fi
done
export LUAU

stamp="$(python3 -c 'import re; from pathlib import Path; print(re.search(r"local SOURCE_STAMP: string = \"([^\"]+)\"", Path("src/Wurst.lua").read_text()).group(1))')"
python3 tools/build_bundle.py --check --stamp "$stamp"

sources=0
while IFS= read -r -d '' source; do
    "$LUAU_COMPILE" "$source" >/dev/null
    sources=$((sources + 1))
done < <(find src -name '*.lua' -print0)
echo "PASS $sources Lua sources compile"

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

# The menu that the bundle builds, not the names that appear in the source: a
# module can compile, ship and never register. Registering a card is a user
# visible change, so the count is asserted.
python3 tools/audit_menu.py >build/menu_audit.md 2>&1 || { cat build/menu_audit.md; exit 1; }
cards="$(grep -E '^[0-9]+ cards total$' build/menu_audit.md | cut -d' ' -f1)"
[ -n "$cards" ] || { cat build/menu_audit.md; exit 1; }
echo "PASS menu audit: $cards cards, every row dumped from the booted bundle"
