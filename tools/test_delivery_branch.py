#!/usr/bin/env python3
"""The entry point, recovery URL and runtime fetch branch must stay together."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
wurst = (ROOT / "src/Wurst.lua").read_text()
readme = (ROOT / "README.md").read_text()

# The loader no longer hardcodes the branch inside RUNTIME_BRANCH (it accepts a
# validated override); the single ship branch is CANONICAL_BRANCH and everything
# else must follow it.
canonical_match = re.search(r'local CANONICAL_BRANCH: string = "([^"]+)"', wurst)
assert canonical_match, "CANONICAL_BRANCH is missing"
branch = canonical_match.group(1)
assert "local RUNTIME_BRANCH: string = CANONICAL_BRANCH" in wurst, (
    "RUNTIME_BRANCH must default to CANONICAL_BRANCH"
)
suffix = f"/refs/heads/{branch}/src/Wurst.lua"

safety_match = re.search(r'RUNTIME_SAFETY_SOURCE_URL: string =\s*\n\s*"([^"]+)"', wurst)
assert safety_match, "RUNTIME_SAFETY_SOURCE_URL is missing"
assert safety_match.group(1).endswith(suffix), (
    "recovery loads a different branch from the runtime bundle"
)
assert suffix in readme, "README loader does not use the runtime branch"
assert "/refs/heads/main/src/Wurst.lua" not in readme
# One canonical branch only: a second hardcoded tree is how an old build kept
# coming back. Any other refs/heads/<x>/src/Wurst.lua in the loader is a bug.
declared = set(re.findall(r"refs/heads/([^\"']+)/src/Wurst\.lua", wurst))
assert declared == {branch}, f"loader references other branches: {sorted(declared)}"
# The visible version is derived from the stamp, never a frozen label.
assert 'version = BUILD_LABEL' in wurst, "PRODUCT.version must derive from the stamp"
assert re.search(r'BUILD_LABEL: string = string\.match\(SOURCE_STAMP, "\^v%d\+"\)', wurst)
assert "0.1 Beta" not in wurst, "stale hardcoded version label"

print(f"PASS delivery entry point, recovery and runtime use {branch} only, "
      "with the version derived from the stamp")
