#!/usr/bin/env python3
"""v196: the main chunk must stay under Luau's 200 live locals.

The report that started this build:

    Out of local registers when trying to allocate cleanupRuntime:
    exceeded limit 200

Luau allows at most 200 live locals per function, and a Luau file's main chunk
is one function. `bootstrap()` used to declare the whole menu -- services,
theme, config, teleport, layout, widgets, cards, tasks, MM2 helpers -- and then,
at the very end, the destruct runtime on top: `runtimeCleaned`,
`runtimeDestructed`, `runtimeHandoff`, `cleanupStep` and `cleanupRuntime`.
The frame reached 201 and the executor refused to compile the file at all, so
nothing ran and the loader reported the generic `:2: attempt to call a nil
value`.

This suite pins the fix two ways:

1. structural -- the destruct runtime lives in `createRuntimeDestructor`, a
   function of its own, and `bootstrap()` only calls it, stores the returned
   closures on `state` and binds the handoff;
2. measured -- if a register-tracing compiler is available, the live-local peak
   of `bootstrap()` must stay below the limit with headroom.

Point it at a tracing build with `WURST_TRACE_COMPILER=/path/to/luau-compile`.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WURST = (ROOT / "src" / "Wurst.lua").read_text(encoding="utf-8")

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


# --- structure ------------------------------------------------------------
check("local function createRuntimeDestructor(" in WURST,
      "the destruct runtime lives in its own function (createRuntimeDestructor)")

factory_start = WURST.find("local function createRuntimeDestructor(")
bootstrap_start = WURST.find("local function bootstrap(): ()")
check(0 <= factory_start < bootstrap_start,
      "the factory is declared before bootstrap(), at chunk level")

# The factory is where the runtime locals are allowed to live.
factory = WURST[factory_start:bootstrap_start] if factory_start >= 0 else ""
for name in ("runtimeCleaned", "runtimeDestructed", "runtimeHandoff",
             "cleanupStep", "cleanupRuntime", "destructRuntime", "bindHandoff"):
    check(name in factory, f"{name} is declared inside the factory")

# bootstrap() must not re-declare them: that is what pushed the frame to 201.
# Everything from `bootstrap` to the xpcall that calls it. The file does not
# indent uniformly, so a brace/`end` count would be guesswork; the region is
# enough for both the presence and the absence checks below.
bootstrap = WURST[bootstrap_start:] if bootstrap_start >= 0 else ""
region_end = bootstrap.find("local initialized: boolean, bootstrapError")
bootstrap_body = bootstrap[:region_end] if region_end > 0 else bootstrap
check("createRuntimeDestructor({" in bootstrap_body,
      "the runtime handoff block is inside bootstrap(), not after it")
for name in ("runtimeCleaned", "runtimeDestructed", "runtimeHandoff",
             "local function cleanupStep", "local function cleanupRuntime"):
    check(name not in bootstrap_body,
          f"bootstrap() no longer declares {name} (it is the factory's job)")

check("local runtime: any = createRuntimeDestructor({" in bootstrap_body,
      "bootstrap() builds the runtime through the factory")
check("state.destruct = runtime.destructRuntime" in bootstrap_body,
      "bootstrap() still publishes state.destruct")
check("state.cleanupRuntime = runtime.cleanupRuntime" in bootstrap_body,
      "bootstrap() still publishes state.cleanupRuntime")
check("runtime.bindHandoff()" in bootstrap_body,
      "bootstrap() still binds the genv handoff")

# Behaviour that must survive the move, verbatim.
for probe, label in (
    ('cleanupStep("session kill switch"', "the kill switch still goes first"),
    ('cleanupStep("runtime", cleanupRuntime)', "the runtime cleanup still runs"),
    ('cleanupStep("screen gui"', "the ScreenGui teardown survives"),
    ('genv.WURST_RUNTIME = nil', "the genv handoff is still revoked"),
    ('ScreenGui.AncestryChanged:Connect', "the ancestry handoff still connects"),
    ('Destruct = destructRuntime', "the handoff still exposes Destruct"),
):
    check(probe in factory, label)


# --- measured -------------------------------------------------------------
def find_compiler() -> str | None:
    explicit = os.environ.get("WURST_TRACE_COMPILER")
    if explicit and Path(explicit).exists():
        return explicit
    for candidate in ("luau-compile",):
        found = shutil.which(candidate)
        if found:
            return found
    return None


compiler = find_compiler()
if compiler and os.environ.get("WURST_TRACE_COMPILER"):
    env = dict(os.environ, LUAU_TRACE_LOCALS="1")
    # `luau-compile` writes bytecode to stdout on success; capture it as bytes
    # and decode leniently so the trace on stderr is all we read.
    result = subprocess.run([compiler, "-O0", "src/Wurst.lua"], cwd=str(ROOT),
                            capture_output=True, env=env)
    result = subprocess.CompletedProcess(
        result.args, result.returncode,
        result.stdout.decode("utf-8", "replace"),
        result.stderr.decode("utf-8", "replace"))
    check(result.returncode == 0, f"src/Wurst.lua compiles under -O0: {result.stderr[-300:]}")

    current = "<chunk>"
    peak = 0
    where = ""
    for line in result.stderr.splitlines():
        if line.startswith("FUNC "):
            parts = line.split(" ", 2)
            current = parts[2] if len(parts) > 2 else "<anon>"
        elif line.startswith("PUSH "):
            parts = line.split()
            live = int(parts[1]) + 1
            if live > peak:
                peak, where = live, f"{current} line {parts[2]} {parts[3]}"
    if peak:
        print(f"register peak: {peak} live locals ({where})")
        check(peak < 200, f"the live-local peak stays under 200 (measured {peak} at {where})")
else:
    print("register peak: not measured (set WURST_TRACE_COMPILER to a tracing luau-compile)")

if failures:
    print(f"FAIL v196 local registers: {len(failures)} problem(s)")
    for failure in failures:
        print(f"  - {failure}")
    raise SystemExit(1)

print("PASS v196 local registers: destruct runtime owns its frame, bootstrap keeps its headroom")
