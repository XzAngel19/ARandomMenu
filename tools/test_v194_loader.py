#!/usr/bin/env python3
"""v194: the loader (and the file it loads) must be loadable, and must say why
when it is not.

The report that started this build was:

    17:36:01   :2: attempt to call a nil value
    Script '', Line 2

That is the two-line loader calling `loadstring(...)()` with a chunk that did not
compile. The one-line form throws the reason away.

v196 note: `src/Wurst.lua` is the loader. The player pastes its raw URL, so the
guard rules live in this repository's own docs (`docs/LOADER.md`) and in the
source, not in a README that no longer ships. This file checks that the
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

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER_DOC = ROOT / "docs/LOADER.md"
WURST = (ROOT / "src/Wurst.lua").read_bytes()


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL v194: {message}")


# --- the documented loader -------------------------------------------------
check(LOADER_DOC.exists(), "docs/LOADER.md exists")
LOADER_TEXT = LOADER_DOC.read_text(encoding="utf-8")
_block_start = LOADER_TEXT.index("## El cargador")
_block_end = LOADER_TEXT.index("## Cuando carga el fichero", _block_start)
loader_block = LOADER_TEXT[_block_start:_block_end]
check("?t=" in loader_block, "the loader breaks the CDN cache")
check("&a=" in loader_block, "the loader breaks the executor cache")
check(re.search(r"size\s*>=?\s*100000", loader_block) is not None,
      "the loader rejects a short download")
check(re.search(r'size\s*<\s*100000', loader_block) is not None,
      "a short download is reported with its size")
check("local RUNTIME_COMPATIBILITY_MARKER" in loader_block,
      "the loader checks the answer is the menu")
check('warn("[Wurst] loader: "' in loader_block, "the loader says WHY it failed")
check('loadstring(source, "@Wurst")' in loader_block,
      "the chunk is named so menu errors are not blamed on the loader")
check("for attempt = 1, 4 do" in loader_block, "the loader retries")
check("getgenv().WURST_BRANCH" in loader_block, "the branch is still set by the loader")
check('loadstring(source, \"@Wurst\")' in loader_block,
      "the loader compiles the download with @Wurst as the chunk name")

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
# v195 moved the stamp past v194 (the loader itself is unchanged). Pinning the
# exact number here made every later build fail on a rule that has nothing to do
# with this suite; what v194 has to keep is a parseable stamp, so the build
# labels keep deriving from it (test_v193_build.py owns that rule).
build_stamp = re.search(r'local SOURCE_STAMP: string = "(v(\d+)-[^"]+)"', text)
check(build_stamp is not None, "the source declares a vNNN-… stamp")
check(int(build_stamp.group(2)) >= 194, "the published build is v194 or newer")
check("wartung" not in LOADER_TEXT, "no leftover placeholder name in the loader")

# --- the documented loader itself compiles --------------------------------
# v196: the loader is what the player pastes, so a typo in the doc is a bug the
# player cannot diagnose. Compile the fenced block exactly as written.
_fence = loader_block.index("```lua") + len("```lua\n")
_loader_source = loader_block[_fence:loader_block.index("```", _fence)]
_loader_file = ROOT / "build" / "documented_loader.luau"
_loader_file.parent.mkdir(parents=True, exist_ok=True)
_loader_file.write_text(_loader_source, encoding="utf-8")
_loader_compile = subprocess.run(
    ["node", "tools/luau/compile.mjs", str(_loader_file)],
    cwd=str(ROOT), capture_output=True, text=True,
)
check(_loader_compile.returncode == 0,
      f"the documented loader compiles: {_loader_compile.stderr[-400:]}")

# --- it really compiles ----------------------------------------------------
result = subprocess.run(
    ["node", "tools/luau/compile.mjs", "src/Wurst.lua"],
    cwd=str(ROOT), capture_output=True, text=True,
)
check(result.returncode == 0, f"src/Wurst.lua compiles: {result.stderr[-400:]}")

print("PASS v194 loader: cache-busting retry with a reason, chunk named @Wurst, "
      "and a published file that is clean UTF-8, marked, complete and compiles")
