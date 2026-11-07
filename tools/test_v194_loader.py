#!/usr/bin/env python3
"""v194/v195: the loader (and the file it loads) must be loadable, and must say
why when it is not.

The report that started this build was:

    17:36:01   :2: attempt to call a nil value
    Script '', Line 2

That is the two-line loader calling `loadstring(...)()` with a chunk that did not
compile. The one-line form throws the reason away, so this file checks that the
documented loader:

  * breaks the executor and CDN caches (`?t=` and `&a=`),
  * refuses a short answer or an answer that is not the menu (size + head mark),
  * prints the reason with `warn("[Wurst] loader: …")` and retries,
  * names the chunk "@Wurst" so an error INSIDE the menu is not mistaken for a
    loader failure.

It also checks the published file itself: UTF-8 without BOM or NUL bytes, the
expected first line, a trailing newline, and a size in the range the loader
accepts. It cannot check the player's network or the executor's Luau version --
for those, the `warn` line exists.
"""

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
README = (ROOT / "README.md").read_text(encoding="utf-8")
LOADER_DOC = ROOT / "docs/LOADER.md"
WURST = (ROOT / "src/Wurst.lua").read_bytes()
READY = ROOT / "loader.lua"


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL v194: {message}")


# --- the documented loader -------------------------------------------------
check(LOADER_DOC.exists(), "docs/LOADER.md exists")
loader_block = README[README.index("## Loader"):README.index("## Cambios de v195")
                      if "## Cambios de v195" in README else len(README)]
check("loader.lua" in loader_block, "the two-line loader points at loader.lua")
check("getgenv().WURST_BRANCH" in loader_block, "the branch is still set by the loader")
check(READY.exists(), "loader.lua ships at the repository root")
load = READY.read_text(encoding="utf-8")
check("?t=" in load and "&a=" in load, "loader.lua breaks both caches")
check("#body < MIN_BYTES" in load, "loader.lua rejects a short download")
check("local RUNTIME_COMPATIBILITY_MARKER" in load, "loader.lua checks the answer is the menu")
check('warn("[Wurst] loader: "' in load, "loader.lua says WHY it failed")
check('compile(body, "@Wurst")' in load, "the chunk is named so menu errors are not blamed on the loader")
check("for attempt: number = 1, ATTEMPTS do" in load, "loader.lua retries")
check("cdn.jsdelivr.net" in load, "loader.lua has a second mirror")
check("http_request" in load and "env.request" in load,
      "loader.lua copes without game:HttpGet")

# --- the published file ----------------------------------------------------
check(WURST[:3] != b"\xef\xbb\xbf", "src/Wurst.lua has no UTF-8 BOM")
check(b"\x00" not in WURST, "src/Wurst.lua has no NUL bytes")
check(WURST.endswith(b"\n"), "src/Wurst.lua ends with a newline")
try:
    text = WURST.decode("utf-8")
except UnicodeDecodeError as error:  # pragma: no cover - defensive
    raise SystemExit(f"FAIL v194: src/Wurst.lua is not valid UTF-8: {error}")
check(text.startswith("local RUNTIME_COMPATIBILITY_MARKER"),
      "the first line is the marker the loader checks")
check(len(WURST) > 100000, "the file is bigger than the loader's minimum")
check(len(WURST) < 1000000, "the file stayed inside one HttpGet")

# --- the build ------------------------------------------------------------
check('local SOURCE_STAMP: string = "v19' in text, "a v19x stamp ships this build")
check("wartung" not in README, "no leftover placeholder name in the loader")

# --- it really compiles ----------------------------------------------------
result = subprocess.run(
    ["node", "tools/luau/compile.mjs", "src/Wurst.lua", "loader.lua"],
    cwd=str(ROOT), capture_output=True, text=True,
)
check(result.returncode == 0, f"src/Wurst.lua and loader.lua compile: {result.stderr[-400:]}")

print("PASS v194/v195 loader: two lines to loader.lua (mirrors, validated downloads, "
      "reasons) and a published menu file that is clean UTF-8, marked, complete and compiles")
