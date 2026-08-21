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
        \( -name "*.lua" -o -name "*.luau" \) ! -name "*.d.luau" \
        ! -name "_shell_source.luau" ! -name "_bundle_source.luau" -print
}

step "Licence and attribution"
# Wurst7 is GPL-3.0. Nothing from it may land here without the licence text
# and a NOTICE that names every copied file. An asset under assets/wurst/
# that is not listed there is an unattributed copy.
test -f LICENSE || { echo "LICENSE is missing"; exit 1; }
grep -q "GNU GENERAL PUBLIC LICENSE" LICENSE || {
    echo "LICENSE is not the GNU GPL"
    exit 1
}
test -f NOTICE.md || { echo "NOTICE.md is missing"; exit 1; }
python3 - <<'PYTHON'
import os

notice = open("NOTICE.md").read()
root = "assets/wurst"
if not os.path.isdir(root):
    raise SystemExit(0)
missing = []
for dirpath, _dirnames, filenames in os.walk(root):
    for name in filenames:
        if name == "manifest.json":
            continue
        path = os.path.join(dirpath, name).replace("\\", "/")
        if path not in notice and name not in notice:
            missing.append(path)
if missing:
    raise SystemExit(
        "vendored files not listed in NOTICE.md:\n  " + "\n  ".join(sorted(missing))
    )
PYTHON
echo "ok"

step "Wurst asset checksums"
# A PNG that drifted from the pinned Wurst7 commit is an unattributed edit.
# The fetch script records sha256 per file; this step re-hashes the tree.
if [ -f assets/wurst/manifest.json ]; then
    python3 tools/fetch_wurst_assets.py --check
else
    echo "ok (nothing vendored)"
fi

step "ClickGUI spec matches the Luau widgets"
# spec.json is generated from the prototype (pixels) and from
# tools/wurst_features.py (official Wurst setting defaults). This step
# refuses a stale JSON, checks ThemeEngine.shape and any named widget
# constants, and fails a UI Settings default that does not match Wurst.
python3 tools/extract_prototype_spec.py --check

step "No hail over the blur"
# The old menu put fifty-four falling stones between the player and the
# game. Wurst does not. A comment that remembers they were deleted is
# fine; a layer that draws them again is not.
python3 - <<'PYTHON'
import re
import subprocess

pattern = re.compile(
    r'Name\s*=\s*"(BlurHail|HailLayer)"|HAIL_STONE_COUNT|HAIL_COLOR'
)
offenders = []
for path in subprocess.run(
    ["git", "ls-files", "*.luau", "*.lua"],
    capture_output=True,
    text=True,
).stdout.split():
    if path.startswith("reference/"):
        continue
    text = open(path, encoding="utf-8", errors="replace").read()
    for match in pattern.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        offenders.append(f"{path}:{line}: {match.group(0)}")
if offenders:
    raise SystemExit(
        "hail / blur-decoration layer reintroduced:\n  "
        + "\n  ".join(offenders)
    )
print("ok")
PYTHON

step "No blur effect in the live shell"
# A removed the BlurEffect. A comment that remembers it is fine;
# constructing one in the shell or a library is the old menu coming back.
# src/gui/Current/gui.lua is leftover and is not loaded.
python3 - <<'PYTHON'
import re
import subprocess

pattern = re.compile(r'(Instance\.new|create)\(\s*"BlurEffect"')
offenders = []
for path in subprocess.run(
    ["git", "ls-files", "ARandomMenu.luau", "src/library", "src/core"],
    capture_output=True,
    text=True,
).stdout.split():
    if not path.endswith((".luau", ".lua")):
        continue
    text = open(path, encoding="utf-8", errors="replace").read()
    for match in pattern.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        offenders.append(f"{path}:{line}: {match.group(0)}")
if offenders:
    raise SystemExit(
        "BlurEffect reintroduced:\n  " + "\n  ".join(offenders)
    )
print("ok")
PYTHON

step "Old brand assets stay out of the ClickGUI"
# menu-logo.jpg and the Brand/Nav/Window artwork belong to the previous
# product. ClickGui, Furniture, Cards, Widgets and the bundle must not
# name them. The shell may still load brandLogo onto the phone circle.
python3 - <<'PYTHON'
import subprocess

needles = (
    "menu-logo.jpg",
    "Assets/Brand/",
    "nav-settings",
    "window-favorites",
    "window-overlays",
    "profile-banner",
)
paths = [
    "src/library/ClickGui.luau",
    "src/library/Furniture.luau",
    "src/library/Cards.luau",
    "src/library/Widgets.luau",
    "runtime/bundle.luau",
]
offenders = []
for path in paths:
    text = open(path, encoding="utf-8", errors="replace").read()
    for needle in needles:
        if needle in text:
            offenders.append(f"{path}: {needle}")
if offenders:
    raise SystemExit(
        "old brand/nav/window asset referenced:\n  "
        + "\n  ".join(offenders)
    )
print("ok")
PYTHON

step "Product name"
# Display names of the previous product must not be hard-coded in tools/ or
# docs/. The filename ARandomMenu.luau stays: it is the loader entry point.
# The shell still logs a three-letter prefix and names its GUI after the old
# product; those live in one constant once the integrator publishes it.
python3 - <<'PYTHON'
import subprocess

# Split so this file itself does not contain the banned phrases.
banned = ("A " + "Random Menu", "Random " + "Testing Menu")
exempt = (
    "docs/agents/",
)
offenders = []
for path in subprocess.run(
    ["git", "ls-files", "tools", "docs", "README.md"],
    capture_output=True, text=True,
).stdout.split():
    if any(path.startswith(prefix) for prefix in exempt):
        continue
    text = open(path, encoding="utf-8", errors="replace").read()
    for needle in banned:
        if needle in text:
            offenders.append(f"{path}: {needle!r}")
if offenders:
    raise SystemExit(
        "old product name hard-coded:\n  " + "\n  ".join(offenders)
        + "\n  the display name is Wurst; the file ARandomMenu.luau keeps its name"
    )
PYTHON
echo "ok"

step "Tracked images stay in asset directories"
# A screenshot of the desktop is not an asset. Anything we ship as pixels
# lives under assets/, reference/ or docs/.
python3 - <<'PYTHON'
import subprocess

allowed = ("assets/", "reference/", "docs/", "src/gui/")
suffixes = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp")
offenders = []
for path in subprocess.run(
    ["git", "ls-files"], capture_output=True, text=True
).stdout.split():
    if not path.lower().endswith(suffixes):
        continue
    if any(path.startswith(prefix) for prefix in allowed):
        continue
    offenders.append(path)
if offenders:
    raise SystemExit(
        "tracked images outside assets/, reference/ and docs/:\n  "
        + "\n  ".join(offenders)
    )
PYTHON
echo "ok"

step "JSON manifests"
python3 -m json.tool src/gui/Current/Images/manifest.json >/dev/null
python3 -m json.tool src/gui/Current/Assets/manifest.json >/dev/null
echo "ok"

step "Source layout"
# Every .luau under src/ has to be reachable: named by the manifest, or a
# per-place game module the loader fetches by name. Nothing else runs.
#
# This step used to be a hand-written list of files that must exist, which is
# a check that cannot fail for any reason worth knowing about — and it was
# actively holding three dead files in place. `src/library/AssetRegistry.luau`
# and `src/library/ProfileRegistry.luau` were never in the manifest and never
# loaded by anything; `src/games/Universal.luau` exported a feature order the
# loader has no way to ask for. A hundred and eighty-six lines that looked
# like architecture and ran on no client, ever.
python3 - <<'PYTHON'
import glob
import re

manifest = open("src/core/Manifest.luau").read()
reachable = set(re.findall(r'"(src/[^"]+\.luau)"', manifest))
reachable.add("src/core/Manifest.luau")
# Game modules are fetched by name from src/games/ when a place is recognised,
# so they are reachable without appearing in the manifest.
reachable |= set(glob.glob("src/games/*.luau"))

orphans = sorted(set(glob.glob("src/**/*.luau", recursive=True)) - reachable)
if orphans:
    raise SystemExit(
        "source files nothing loads:\n  " + "\n  ".join(orphans)
        + "\n  add them to src/core/Manifest.luau or delete them"
    )

missing = sorted(path for path in reachable if not glob.glob(path))
if missing:
    raise SystemExit("the manifest names files that do not exist:\n  " + "\n  ".join(missing))
PYTHON
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

step "The staged workflow matches the live one"
# `tools/workflow-validate.yml` is where a change to CI is written, because an
# agent cannot push to `.github/workflows/`. A staged copy that has silently
# drifted from the live file is worse than no copy at all: it describes a
# pipeline that is not running.
python3 - <<'PYTHON'
# Both files are compared from the first line of the workflow itself. The
# comment block above it is allowed to differ: the staged copy explains why it
# exists, and the live one carries whatever the person who pasted it kept.
marker = "name: Validate repository"
def workflow(path: str) -> str:
    text = open(path).read()
    if marker not in text:
        raise SystemExit(path + " contains no workflow")
    return text[text.index(marker):]

if workflow("tools/workflow-validate.yml") != workflow(".github/workflows/validate.yml"):
    raise SystemExit(
        "tools/workflow-validate.yml and .github/workflows/validate.yml differ.\n"
        "  Copy everything from 'name: Validate repository' onwards across."
    )
PYTHON
echo "ok"

step "Every suite is actually run"
# A suite file the runner does not require is a hundred green checks that
# never execute, and the total at the end says nothing is wrong. Three of them
# arrived at once, written against a second runner that existed while the
# split was on another branch.
python3 - <<'PYTHON'
import os
import re

listed = set(re.findall(r'require\("\./suites/([\w-]+)"\)', open("tools/test/run.luau").read()))
present = {name[:-5] for name in os.listdir("tools/test/suites") if name.endswith(".luau")}
orphans = sorted(present - listed)
missing = sorted(listed - present)
if orphans:
    raise SystemExit(
        "suites nothing runs:\n  " + "\n  ".join(orphans)
        + "\n  add them to tools/test/run.luau or delete them"
    )
if missing:
    raise SystemExit("run.luau requires suites that do not exist:\n  " + "\n  ".join(missing))
PYTHON
echo "ok"

step "Option callbacks live in one place"
# Four suites each wrapped the builders. Two of them guessed the callback
# position wrong and recorded nothing, then passed anyway. The wrap belongs
# on run.luau; a suite that carries its own copy is the next silent miss.
if grep -n 'if not host.optionCallbacks' tools/test/suites/*.luau; then
    echo "a suite is wrapping option builders; that lives in tools/test/run.luau"
    exit 1
fi
echo "ok"

step "Bundle stamp matches the sources"
# A stale runtime/bundle.luau serving old code while the repo says otherwise is
# the class of silent rot the stamp exists to prevent.
python3 tools/bundle.py --check
echo "ok"

step "Module contracts II: options, state, builders, text boxes, slop"
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
#     descenders off its text (the page header shaved the tail off "Settings");
#   * an option nobody reads that carries no Function — a switch that lies
#     about having an effect, which is how a menu turns into a wall of them.
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

    # Free globals in a downloaded file.
    #
    # Every file under src/ runs with its environment set to the table the
    # shell builds, so a bare name that is not a local is read from that table
    # — and is nil when the shell does not publish it. Nothing complains: the
    # file compiles, loads, and dies the first time it reaches that line.
    #
    # Two real defects were sitting in the tree when this was added. The
    # settings page read `registeredText` and `executorGlobals`, two bootstrap
    # locals it used to sit beside. And Anti-Fling read `flingRunning` the same
    # way, so it never stood down during a fling of your own — it fought the
    # feature it was written to make room for.
    analyze_output="$(mktemp)"
    : > "$analyze_output"
    while IFS= read -r file; do
        case "$file" in ./src/*) ;; *) continue ;; esac
        # luau-analyze exits non-zero on any type error, and this repository
        # has many that are not defects: no Roblox type definitions are fed to
        # it. Only the unknown-global lines matter here.
        "$luau_analyze" --defs=env.d.luau "$file" 2>&1 \
            | sed -n "s#^\(\./[^(]*\)(.*Unknown global '\([^']*\)'.*#\1 \2#p" \
            >> "$analyze_output" || true
    done < <(source_files)
    global_output="$(mktemp)"
    ANALYZE_OUTPUT="$analyze_output" GLOBAL_OUTPUT="$global_output" \
        PYTHONDONTWRITEBYTECODE=1 python3 - <<'PYTHON'
import os
import re
import sys

sys.path.insert(0, "tools")
from check_contracts import environment_keys

# `luau-analyze` has no Roblox definitions here, so it reports every free
# global — `Enum` included. What Roblox itself puts in scope is listed once
# below; what the *executor* puts in scope is read from env.d.luau, which
# exists for exactly that purpose and is therefore the only place to add one.
ROBLOX = {
    "game", "workspace", "task", "warn", "print", "require", "shared", "script",
    "tick", "time", "typeof", "delay", "spawn", "wait", "unpack", "newproxy",
    "gcinfo", "settings", "utf8", "bit32", "buffer", "vector", "debug",
    "Enum", "Instance", "Color3", "ColorSequence", "ColorSequenceKeypoint",
    "NumberSequence", "NumberSequenceKeypoint", "NumberRange", "Vector2",
    "Vector3", "CFrame", "UDim", "UDim2", "TweenInfo", "Ray", "Rect", "Region3",
    "Font", "BrickColor", "Random", "Axes", "Faces", "PhysicalProperties",
    "OverlapParams", "RaycastParams", "DateTime", "CatalogSearchParams",
}
declarations = open("env.d.luau").read()
EXECUTOR = set(re.findall(r"^declare (?:function )?(\w+)", declarations, re.M))

published = environment_keys(open("ARandomMenu.luau").read()) | ROBLOX | EXECUTOR
failures = []
seen = set()
for line in open(os.environ["ANALYZE_OUTPUT"]):
    parts = line.split()
    if len(parts) != 2:
        continue
    path, name = parts
    if name in published or (path, name) in seen:
        continue
    seen.add((path, name))
    failures.append(f"{path}: reads the global '{name}', which the shell never publishes")
with open(os.environ["GLOBAL_OUTPUT"], "w") as handle:
    handle.write("\n".join(sorted(failures)))
    if failures:
        handle.write("\n")
PYTHON
    rm -f "$analyze_output"
    if [ -s "$global_output" ]; then
        cat "$global_output"
        rm -f "$global_output"
        exit 1
    fi
    rm -f "$global_output"
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

# Anchored on a line that is there because the menu needs it, not because
# this check does. The previous anchor was a page host; when the page host
# was deleted it was replaced with a nil local and an empty `if` block, kept
# alive purely so this grep would keep succeeding — which measured nothing
# and cost a real line of the file it was measuring.
anchor = "state.universalScroll = CardBin"
source = open("ARandomMenu.luau").read()
if anchor not in source:
    raise SystemExit(
        "probe anchor missing from ARandomMenu.luau — point it at another "
        "statement in the shell's largest scope, do not add one for it"
    )
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
# The CLI has no filesystem API, so the shell test loadstrings generated
# modules that return ARandomMenu.luau and runtime/bundle.luau as strings.
# Emitted here, not kept in git: a committed copy would drift the moment
# either file changed.
python3 - <<'PYTHON'
from pathlib import Path

def emit(src: str, dest: str) -> None:
    source = Path(src).read_text()
    level = 0
    while ("]" + "=" * level + "]") in source:
        level += 1
    eq = "=" * level
    Path(dest).write_text(
        "--!strict\n"
        "-- Emitted for the headless tests; the CLI has no file API.\n"
        f"return [{eq}[\n{source}\n]{eq}]\n"
    )

emit("ARandomMenu.luau", "tools/test/_shell_source.luau")
emit("runtime/bundle.luau", "tools/test/_bundle_source.luau")
PYTHON
"$luau_run" tools/test/run.luau
rm -f tools/test/_shell_source.luau tools/test/_bundle_source.luau

echo
echo "All checks passed."
