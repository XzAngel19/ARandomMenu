#!/usr/bin/env python3
"""v195: one branch everywhere, and a download failure that names it.

The report that started this build:

    :2: attempt to call a nil value
    Stack Begin
    Script '', Line 2
    Stack End

That is not a syntax problem inside the menu. `src/Wurst.lua` was fine (the
branch tip serves 254,853 bytes, matching the local file byte for byte). The
docs told the player to load branch `arena/7446e4e3-arandommenu`, which had been
superseded, while `RUNTIME_BRANCH` inside the file pointed at
`arena/05c45e27-arandommenu`; the session branch itself, `arena/e21ba23f-…`,
had never been pushed. GitHub answers a missing branch with `404: Not Found`
(plain text, 14 bytes), `loadstring` returns nil on it, and calling nil is
exactly `:2: attempt to call a nil value`.

So this suite pins the three things that failure taught:

  * the loader in docs/LOADER.md, `RUNTIME_BRANCH` in src/Wurst.lua and the loader
    example in docs/LOADER.md name the SAME branch;
  * every documented URL is built from that one branch name (no second copy);
  * a failed download reports a short reason plus the branch, so a 404 can no
    longer be mistaken for a broken download or a syntax error.
"""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# v196: `src/Wurst.lua` is the loader, so the instructions a player copies live in
# docs/LOADER.md. There is no README to read any more.
LOADER_DOC = (ROOT / "docs/LOADER.md").read_text(encoding="utf-8")
WURST = (ROOT / "src/Wurst.lua").read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL v195: {message}")


def loader_block() -> str:
    start = LOADER_DOC.index("## El cargador")
    end = LOADER_DOC.index("## Cuando carga el fichero", start)
    return LOADER_DOC[start:end]


# --- one branch, everywhere -------------------------------------------------
runtime = re.search(r'local RUNTIME_BRANCH: string = "([^"]+)"', WURST)
check(runtime is not None, "src/Wurst.lua declares RUNTIME_BRANCH")
branch = runtime.group(1)

check(branch.startswith("arena/"), f"RUNTIME_BRANCH is an arena branch (got {branch})")
# The branch this file ships on. Arena tracks the session by this name and the
# loader URL is built from it, so a rename here is a loader regression, not a
# cosmetic edit. Update it in one place only: this check and src/Wurst.lua.
EXPECTED_BRANCH = "arena/0ce50d99-arandommenu"
check(branch == EXPECTED_BRANCH,
      f"RUNTIME_BRANCH is this session's branch (got {branch})")

# The changelog is allowed to name the old branches: that is the explanation of
# the bug. What must never name another branch is an instruction a player copies
# -- the loader lines themselves.
def instruction_branches(text: str) -> set:
    found = set()
    for line in text.splitlines():
        if ("raw.githubusercontent" in line
                or "getgenv().WURST_BRANCH" in line
                or "/src/Wurst.lua" in line):
            found |= set(re.findall(r"arena/[0-9a-f]{8}-arandommenu", line))
    return found


documented = instruction_branches(LOADER_DOC)
check(documented == {branch},
      "every loader instruction names the runtime branch "
      f"(found {sorted(documented)})")
check(instruction_branches(LOADER_DOC) == {branch},
      "the LOADER.md loader instructions match RUNTIME_BRANCH")

# v196: the Reinject button used to download from a hardcoded older session
# branch. The only source address in the runtime must be the branch above.
safety = re.search(r'local RUNTIME_SAFETY_SOURCE_URL: string = ([^\n]+)', WURST)
check(safety is not None, "src/Wurst.lua declares RUNTIME_SAFETY_SOURCE_URL")
check(safety.group(1).strip() == 'RUNTIME_RAW_BASE .. "src/Wurst.lua"',
      "RUNTIME_SAFETY_SOURCE_URL is derived from RUNTIME_BRANCH, not hardcoded")
hardcoded = [
    line for line in WURST.splitlines()
    if "raw.githubusercontent.com" in line and "arena/" in line
]
check(hardcoded == [], f"no hardcoded branch URL survives in src/Wurst.lua: {hardcoded}")

block = loader_block()
check(f'getgenv().WURST_BRANCH = "{branch}"' in block,
      "the documented loader sets WURST_BRANCH to that same branch")
# v196: the loader builds the URL from the WURST_BRANCH it just set instead of
# repeating the branch in a second literal, so there is one place to change.
check(f'getgenv().WURST_BRANCH = "{branch}"' in block
      and '.. branch' in block
      and '"/src/Wurst.lua"' in block,
      "the documented loader URL is built from that same branch")
check(block.count("arena/") == 2,
      "the loader block has exactly two branch mentions (env var and URL)")

# A stale session branch in the docs is what broke the load; the runtime must
# not fall back to a branch this repository does not publish.
for stale in ("arena/05c45e27-arandommenu", "arena/7446e4e3-arandommenu"):
    check(stale not in block, f"the loader block no longer points at {stale}")

# --- the failure message names the cause and the branch ---------------------
check('state.describeHttpFailure = function(body: any): string' in WURST,
      "a failed download is described, not dumped raw")
describe = WURST[WURST.index("state.describeHttpFailure"):]
describe = describe[: describe.index("state.httpGetPath")]
check('"HTTP 404"' in describe, "a 404 is named as a 404")
check('"HTML answer, not Lua"' in describe, "an HTML error page is named")
check('"empty answer (' in describe, "a short answer reports its size")
check('" · branch " .. RUNTIME_BRANCH' in describe,
      "the failure message names the branch it tried")
check('"HttpGet threw: "' in WURST,
      "a throwing executor is reported instead of swallowed")

# --- the stamp ------------------------------------------------------------
# The stamp moves with every release; this suite only pins that the shipped
# source still carries a v195-or-later stamp (the branch alignment this file
# guards) and that no label is hardcoded next to it.
stamp = re.search(r'local SOURCE_STAMP: string = "(v(\d+))-', WURST)
check(stamp is not None and int(stamp.group(2)) >= 195,
      f"the shipped stamp is v195 or later (found {stamp.group(0) if stamp else 'none'})")
check("0." + (stamp.group(2) if stamp else "") not in WURST,
      "no hardcoded 0.<build> label (it derives from the stamp)")

# --- it compiles ----------------------------------------------------------
result = subprocess.run(
    ["node", "tools/luau/compile.mjs", "src/Wurst.lua"],
    cwd=str(ROOT), capture_output=True, text=True,
)
check(result.returncode == 0, f"src/Wurst.lua compiles: {result.stderr[-400:]}")

print("PASS v195 loader: one branch in loader/RUNTIME_BRANCH/docs, "
      "and a failed download names the cause (HTTP 404, HTML, empty) plus the branch")
