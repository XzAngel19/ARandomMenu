#!/usr/bin/env python3
"""The vendored Luau toolchain: setup, analyzer, StyLua and DarkLua.

Every gate that `tools/validate.sh` relies on is asserted here, one level below
the tree it checks:

  * `tools/luau/setup.sh` rebuilds `node_modules` and `bin/` from `vendor/` and
    is idempotent (this is what a fresh clone or a wiped sandbox runs);
  * the analyzer loads `definitions/core.d.luau` + `definitions/runtime.d.luau`
    and reports zero errors outside `analyze-baseline.json`;
  * `luau-compile` rejects a syntax error (a gate that never fails is not a
    gate) and accepts the minified loader;
  * the definitions are a generated subset: pinned digest, no `--#METADATA#`
    header, every value root present, and `build_definitions.py --check` agrees;
  * StyLua formats Luau and its config comes from `stylua.toml`, not defaults;
  * DarkLua applies the release rules from `darklua.release.json`, the rules in
    the JSON and in `minify.mjs` agree, and the minified loader still compiles
    while being at least 40% smaller;
  * `runtime.d.luau` declares the executor and host globals the sources use.

Run with `python3 tools/test_luau_toolchain.py` (validate.sh does).
"""
from __future__ import annotations

import json
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUAU = ROOT / "tools" / "luau"
BIN = LUAU / "bin"
NODE = BIN / "luau"
DEFINITIONS = LUAU / "definitions"
BASELINE = LUAU / "analyze-baseline.json"

passed = 0


def pass_(message: str) -> None:
    global passed
    passed += 1
    print(f"PASS\t{message}")


def tool(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run one of the tools/luau/bin wrappers (bash shims around the wasm CLIs)."""
    return subprocess.run([str(arg) for arg in args], cwd=ROOT, capture_output=True, text=True, check=check)


def node(*script: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run `node -e <script>`, joining the fragments of a multi-line script."""
    return subprocess.run(
        ["node", "-e", "".join(script)], cwd=ROOT, capture_output=True, text=True, check=check
    )


def main() -> int:
    # --- setup ------------------------------------------------------------
    setup = subprocess.run(["bash", str(LUAU / "setup.sh")], capture_output=True, text=True)
    assert setup.returncode == 0, setup.stderr
    assert (LUAU / "node_modules" / "@luau-rs" / "luau" / "package.json").exists()
    assert (LUAU / "node_modules" / "@johnnymorganz" / "stylua" / "package.json").exists()
    assert (LUAU / "node_modules" / "darklua-wasm" / "package.json").exists()
    assert (LUAU / "node_modules" / "valibot" / "package.json").exists()
    for name in ("luau", "luau-compile", "luau-analyze", "luau-format", "luau-minify"):
        assert (BIN / name).exists() and (BIN / name).stat().st_mode & 0o111
    pass_("setup.sh rebuilds the wasm toolchain from vendor/ and produces every bin/ entry")

    second = subprocess.run(["bash", str(LUAU / "setup.sh")], capture_output=True, text=True)
    assert second.returncode == 0 and "ready" in second.stdout
    pass_("setup.sh is idempotent (second run is a no-op, not a re-extract)")

    # --- compile gate -----------------------------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        good = Path(tmp) / "good.lua"
        good.write_text('local function double(n: number): number\n    return n * 2\nend\nreturn double(21)\n')
        bad = Path(tmp) / "bad.lua"
        bad.write_text("local function broken(\n")
        assert tool(str(BIN / "luau-compile"), str(good)).returncode == 0
        rejected = tool(str(BIN / "luau-compile"), str(bad), check=False)
        assert rejected.returncode == 1 and "bad.lua" in rejected.stderr, rejected.stderr
    pass_("luau-compile accepts valid Luau and fails on a syntax error, naming the file")

    # --- analyzer ---------------------------------------------------------
    analyzed = tool("tools/luau/bin/luau-analyze", "--baseline", check=False)
    summary = analyzed.stderr.strip().splitlines()[-1]
    assert "0 error(s)" in summary, summary
    assert re.search(r"\d+ sources", summary), summary
    pass_(f"luau-analyze: {summary.replace('analyze: ', '')}")

    # The baseline has to stay honest: real, deduplicated, and non-empty.
    baseline = json.loads(BASELINE.read_text())
    entries = baseline["entries"]
    assert entries and len(entries) == len(set(entries))
    assert all(e.count("|") >= 2 for e in entries)
    known_codes = {e.split("|")[1] for e in entries}
    assert known_codes <= {"1000", "1001", "1002", "1005", "1018", "1021", "1045", "1008"}, known_codes
    assert any("Enum." in e for e in entries), "the Enum.* type gap should be recorded, not hidden"
    assert any("IsA" in e or "Part1" in e or "MeshId" in e for e in entries)
    pass_(f"analyze-baseline.json: {len(entries)} accepted reports, deduplicated, two known analyzer gaps")

    # A new error has to fail the gate, not blend into the baseline. The probe is an
    # unknown *global*: nonstrict mode does not reject `number = "string"` (that is
    # what --mode=strict is for, asserted right below), but it always reports globals.
    with tempfile.TemporaryDirectory() as tmp:
        broken = Path(tmp) / "broken.lua"
        broken.write_text("local x = SomeUndefinedGlobal(1)\nprint(x)\n")
        fresh = tool("tools/luau/bin/luau-analyze", "--baseline", str(broken), check=False)
        assert fresh.returncode == 1 and "NEW" in fresh.stdout, fresh.stdout + fresh.stderr
    pass_("a new error fails --baseline and is printed with NEW, not swallowed")

    # --mode=strict is available for a full type check of one file.
    with tempfile.TemporaryDirectory() as tmp:
        typed = Path(tmp) / "typed.lua"
        typed.write_text('local n: number = "not a number"\nreturn n\n')
        strict = tool("tools/luau/bin/luau-analyze", "--mode=strict", str(typed), check=False)
        assert strict.returncode == 1 and "number" in strict.stdout + strict.stderr
    pass_("--mode=strict rejects a value that violates its annotation")

    # --- definitions ------------------------------------------------------
    core = (DEFINITIONS / "core.d.luau").read_text()
    pinned = (DEFINITIONS / "source.sha256").read_text().strip()
    assert pinned in core, "core.d.luau does not carry the pinned dump digest"
    assert "--#METADATA#" not in core
    assert len(core.splitlines()) > 1000
    for needed in (
        "declare extern type CFrame with",
        "declare extern type Vector3 with",
        "declare extern type Enum with",
        "declare extern type EnumItem with",
        "declare extern type Instance extends Object with",
        "declare extern type ServiceProvider extends Instance with",
        "declare extern type DataModel extends ServiceProvider with",
        "declare extern type BasePart extends PVInstance with",
        "declare game: DataModel",
        "declare workspace: Workspace",
        "declare task: {",
        "declare CFrame:",
        "declare Enum: { [string]: any }",
    ):
        assert needed in core, f"core.d.luau is missing {needed!r}"
    # Order is load-bearing: a superclass before its subclass.
    assert core.index("declare extern type Object with") < core.index("declare extern type Instance extends Object")
    assert core.index("declare extern type Instance extends Object") < core.index(
        "declare extern type DataModel extends ServiceProvider"
    )
    check = subprocess.run(
        ["python3", str(DEFINITIONS / "build_definitions.py"), "--check"], capture_output=True, text=True
    )
    assert check.returncode == 0 and "definitions OK" in check.stdout, check.stderr
    pass_(
        f"core.d.luau: {len(core.splitlines())} lines from dump {pinned[:12]}…, "
        "superclasses ordered, Enum typed permissively"
    )

    runtime = (DEFINITIONS / "runtime.d.luau").read_text()
    for name in (
        "getgenv", "gethui", "getconnections", "firesignal", "hookmetamethod",
        "newcclosure", "setclipboard", "readfile", "writefile", "identifyexecutor",
        "request", "create", "Theme", "state", "notify", "configValue", "configData",
        "TaskManager", "Players", "LocalPlayer", "RunService", "UserInputService",
        "featureConnections", "addToggleOption", "addKeyOption",
    ):
        if name == "configValue":  # not a host global, kept out on purpose
            assert f"declare {name}" not in runtime
            continue
        assert f"declare {name}" in runtime or f"declare {name}:" in runtime, f"runtime.d.luau lacks {name}"
    pass_("runtime.d.luau declares the executor surface and the host globals the cards use")

    # --- StyLua -----------------------------------------------------------
    formatted = node(
        "import('./tools/luau/format.mjs').then((m) => {"
        "const out = m.formatSource('export type Q = {\\n    FOV: number?,\\n}\\nlocal x={a=1,b=2}\\n');"
        "console.log(JSON.stringify(out));",
        "});"
    )
    sample = json.loads(formatted.stdout.strip().splitlines()[-1])
    assert "FOV: number?," in sample, sample
    assert "{ a = 1, b = 2 }" in sample, sample
    config = (LUAU / "stylua.toml").read_text()
    for line in ('indent_type = "Spaces"', 'line_endings = "Unix"', 'syntax = "Luau"', "column_width ="):
        assert line in config, line
    mismatch = node(
        "import('./tools/luau/format.mjs').then((m) => {"
        "try { m.buildConfig(new Map([['indent_type', 'Diagonal']])); }"
        "catch (error) { console.log('rejected'); }"
        "console.log(m.buildConfig().column_width);",
        "});"
    )
    assert "rejected" in mismatch.stdout, mismatch.stdout + mismatch.stderr
    # Tab-indent config (what wasm StyLua calls IndentType.Tabs) is honoured.
    tabbed = node(
        "import('./tools/luau/format.mjs').then((m) => {"
        "const cfg = m.buildConfig(new Map([['indent_type', 'Tabs']]));"
        "console.log(JSON.stringify(m.formatSource('export type Q = {\\n    FOV: number?,\\n}\\n', cfg)));",
        "});"
    )
    assert "\tFOV" in json.loads(tabbed.stdout.strip().splitlines()[-1])
    pass_("StyLua: Luau types stay typed, spaces from stylua.toml, invalid enum value rejected, tabs honoured")

    # --- DarkLua ----------------------------------------------------------
    recipe = json.loads((LUAU / "darklua.release.json").read_text())
    rules = recipe["rules"]
    assert rules[0] == "remove_types" and "rename_variables" in rules and "remove_spaces" in rules
    listed = tool("tools/luau/bin/luau-minify", "--rules").stdout.split()
    assert set(rules) <= set(listed), set(rules) - set(listed)

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "Wurst.min.lua"
        minified = tool("tools/luau/bin/luau-minify", "src/Wurst.lua", "-o", str(out), check=False)
        assert minified.returncode == 0, minified.stderr
        source_size = (ROOT / "src" / "Wurst.lua").stat().st_size
        minified_size = out.stat().st_size
        assert minified_size < source_size * 0.6, (minified_size, source_size)
        assert ": string =" not in out.read_text(), "types survived remove_types"
        compiled = tool(str(BIN / "luau-compile"), str(out), check=False)
        assert compiled.returncode == 0, compiled.stderr
    saved = 100 * (1 - minified_size / source_size)
    pass_(f"DarkLua: {len(rules)} rules, {source_size // 1024} KB -> {minified_size // 1024} KB "
          f"({saved:.1f}% smaller), minified loader still compiles")

    # Recipe drift is a failure, not a surprise in a release.
    drift = node(
        "import('./tools/luau/minify.mjs').then((m) => {"
        "const r = m.recipeMatches(); console.log(r.ok ? 'in-sync' : 'drift:' + r.reason);"
        "});",
    )
    assert "in-sync" in drift.stdout, drift.stdout
    pass_("darklua.release.json and minify.mjs agree, rule names validated against the wasm engine")

    print(f"PASS {passed} Luau toolchain suites")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
