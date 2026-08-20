#!/usr/bin/env bash
#
# Every check the repository holds itself to, in one place.
#
# The GitHub workflow runs the same list; this script exists so the whole set
# can be run locally before pushing, and so adding a check means editing one
# file instead of two.
#
# Usage:  bash tools/validate.sh
#         LUAU_DIR=/path/to/luau bash tools/validate.sh
#
# LUAU_DIR must contain `luau-compile` and `luau`. When it is unset the script
# looks for them on PATH, then in /tmp/luau (where the workflow unpacks the
# release archive).

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

resolve_binary() {
    local name="$1"
    if [ -n "${LUAU_DIR:-}" ] && [ -x "$LUAU_DIR/$name" ]; then
        echo "$LUAU_DIR/$name"
        return 0
    fi
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    if [ -x "/tmp/luau/$name" ]; then
        echo "/tmp/luau/$name"
        return 0
    fi
    if [ -x "/tmp/luau-src/build/$name" ]; then
        echo "/tmp/luau-src/build/$name"
        return 0
    fi
    return 1
}

luau_compile="$(resolve_binary luau-compile || true)"
luau_run="$(resolve_binary luau || true)"
luau_analyze="$(resolve_binary luau-analyze || true)"

# Locally a missing toolchain is an inconvenience and the script says so.
# On a runner it is a broken job: skipping compilation and the tests there
# would report a green tick for checks that never ran.
require_luau="${REQUIRE_LUAU:-${CI:-0}}"
missing_toolchain() {
    echo
    echo "$1"
    echo "Set LUAU_DIR to a directory containing luau-compile and luau."
    case "$require_luau" in
        1 | true | TRUE | yes)
            exit 1
            ;;
    esac
    exit 0
}

step() {
    printf '\n== %s\n' "$1"
}

# Source files, excluding reference/ (third-party code kept for reading) and
# declaration files (which are types, not programs).
source_files() {
    find . -path ./.git -prune -o -path ./reference -prune -o -type f \
        \( -name "*.lua" -o -name "*.luau" \) ! -name "*.d.luau" -print
}

step "JSON manifests"
python3 -m json.tool src/gui/Current/Images/manifest.json >/dev/null
python3 -m json.tool src/gui/Current/Assets/manifest.json >/dev/null
echo "ok"

step "Source layout"
for path in \
    src/games/Universal.luau \
    src/games/MM2.luau \
    src/games/TRS.luau \
    src/games/VD.luau \
    src/core/Framework.luau \
    src/core/Manifest.luau \
    src/library/Entity.luau \
    src/library/AssetRegistry.luau \
    src/library/ProfileRegistry.luau \
    src/gui/Current/gui.lua \
    tools/test/run.luau
do
    test -f "$path" || {
        echo "missing $path"
        exit 1
    }
done
echo "ok"

step "Module contracts"
# Game modules and every downloadable framework file export the same pair.
while IFS= read -r file; do
    grep -q 'return Module' "$file" || { echo "$file: no 'return Module'"; exit 1; }
    grep -q 'function Module.init' "$file" || { echo "$file: no init"; exit 1; }
    grep -q 'function Module.destroy' "$file" || { echo "$file: no destroy"; exit 1; }
done < <(
    find src/games src/modules -type f -name "*.luau"
    echo src/core/Framework.luau
    echo src/library/Entity.luau
)
echo "ok"

step "Manifest matches the runtime fallback"
# The runtime embeds a copy of the manifest for the case where the manifest
# download itself fails; the two must not drift apart.
while IFS= read -r path; do
    test -f "$path" || { echo "manifest lists a missing file: $path"; exit 1; }
    grep -q "\"$path\"" ARandomMenu.luau || {
        echo "runtime fallback is missing: $path"
        exit 1
    }
done < <(grep -oE '"src/[^"]+\.luau"' src/core/Manifest.luau | tr -d '"' | sort -u)
echo "ok"

step "Asset manifests point at files that exist"
python3 - <<'PYTHON'
import json
import os

base = "src/gui/Current/"
failures = []
with open(base + "Assets/manifest.json") as handle:
    for key, entry in json.load(handle)["assets"].items():
        path = entry.get("path")
        if path and not os.path.exists(base + path):
            failures.append(key + " -> " + path)
with open(base + "Images/manifest.json") as handle:
    for key, name in json.load(handle)["images"].items():
        if name and not os.path.exists(base + "Images/" + name):
            failures.append(key + " -> " + name)
if failures:
    raise SystemExit("missing assets:\n  " + "\n  ".join(failures))
PYTHON
echo "ok"

step "Text objects are contained"
# A label that fits in one typeface overflows in another, so every text object
# has to say what happens when it does not fit. The three helpers set this for
# everything they build; this catches the ones built by hand.
python3 - <<'PYTHON'
import re
import subprocess

files = [
    path
    for path in subprocess.run(
        ["git", "ls-files"], capture_output=True, text=True
    ).stdout.split()
    if path.endswith((".lua", ".luau")) and not path.startswith("reference/")
]
pattern = re.compile(r'create\("(TextLabel|TextButton|TextBox)", \{')
offenders = []
for path in files:
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    for match in pattern.finditer(source):
        block = source[match.end() : match.end() + 900].split("})")[0]
        if "TextTruncate" not in block:
            line = source.count("\n", 0, match.start()) + 1
            offenders.append(f"{path}:{line}")
if offenders:
    raise SystemExit(
        "text objects without TextTruncate:\n  " + "\n  ".join(offenders)
    )
PYTHON
echo "ok"

step "Strict Luau headers"
while IFS= read -r file; do
    test "$(head -n 1 "$file")" = "--!strict" || {
        echo "$file does not start with --!strict"
        exit 1
    }
done < <(find . -path ./.git -prune -o -path ./reference -prune -o -type f \
    \( -name "*.lua" -o -name "*.luau" \) -print)
echo "ok"

step "Loader freshness guard"
grep -q 'REQUIRED_RUNTIME_MARKER' loadstring
grep -q 'RUNTIME_SAFETY_SOURCE_URL' ARandomMenu.luau
! grep -q 'corner.Enabled' ARandomMenu.luau
! grep -q 'corner.Enabled' src/gui/Current/gui.lua
echo "ok"

step "Module contracts II: options, state, builders, text boxes"
# Three whole classes of bug that only ever showed up in-game, checked here
# instead:
#
#   * a module reading `Options["Delay"]` after the row was renamed to
#     "Reaction" — the read returns nil and the module dies mid-frame;
#   * a module reading `state.something` that nothing anywhere assigns (the
#     projectile calibration read `.settings` after the field became `.tuning`);
#   * a game module calling a builder the shell forgot to put in
#     `createGameModuleEnvironment` — which is how Kill Aura once rendered a
#     "Weapon" heading and nothing under it;
#   * a label shorter than the line box of its own font, which clips the
#     descenders off its text (the page header shaved the tail off "Settings").
python3 tools/check_contracts.py
echo "ok"

if [ -z "$luau_compile" ]; then
    missing_toolchain "luau-compile not found; skipping compilation and tests."
fi

step "Compile"
while IFS= read -r file; do
    "$luau_compile" "$file" >/dev/null
    # -O0 keeps every local in a register, which is what catches the main
    # file drifting back over Luau's 200-local ceiling.
    "$luau_compile" -O0 "$file" >/dev/null
done < <(source_files)
"$luau_compile" loadstring >/dev/null
"$luau_compile" -O0 loadstring >/dev/null
echo "ok"

step "Lints"
if [ -n "$luau_analyze" ]; then
    # Only the lints that describe a real defect rather than a style opinion.
    # Every one of these has cost this repository a bug: a closure that named a
    # local declared further down read a *global* and was nil at runtime
    # (GlobalUsedAsLocal), a second `candidate` shadowed the first and the test
    # asserted against the wrong one (LocalShadow), and an unused local is
    # usually the leftover half of a change (LocalUnused).
    lint_output="$(mktemp)"
    while IFS= read -r file; do
        "$luau_analyze" --defs=env.d.luau "$file" 2>&1 \
            | grep -E "LocalUnused|LocalShadow|GlobalUsedAsLocal|DuplicateLocal|DuplicateFunction|UnreachableCode|DuplicateCondition" \
            >> "$lint_output" || true
    done < <(source_files)
    if [ -s "$lint_output" ]; then
        cat "$lint_output"
        rm -f "$lint_output"
        exit 1
    fi
    rm -f "$lint_output"
    echo "ok"
else
    echo "skipped (luau-analyze not found)"
fi

step "Register headroom"
# Three throwaway locals in the main file's largest scope must still compile:
# without the margin the next feature added is the one that fails to build.
probe="$(mktemp /tmp/rtm-probe-XXXXXX.luau)"
python3 - "$probe" <<'PYTHON'
import sys

anchor = "local Content: Frame = nil :: any"
source = open("ARandomMenu.luau").read()
if anchor not in source:
    raise SystemExit("probe anchor missing from ARandomMenu.luau")
padding = "\n".join(
    "local __probe%d: number = %d" % (index, index) for index in range(1, 4)
)
open(sys.argv[1], "w").write(source.replace(anchor, anchor + "\n" + padding, 1))
PYTHON
"$luau_compile" -O0 "$probe" >/dev/null
rm -f "$probe"
echo "ok"

if [ -z "$luau_run" ]; then
    missing_toolchain "luau interpreter not found; skipping the module tests."
fi

step "Headless module tests"
"$luau_run" tools/test/run.luau

echo
echo "All checks passed."
