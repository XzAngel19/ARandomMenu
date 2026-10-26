#!/usr/bin/env python3
"""The entry point, recovery URL and runtime fetch branch must stay together."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
wurst = (ROOT / "src/Wurst.lua").read_text()
readme = (ROOT / "README.md").read_text()

branch_match = re.search(r'local RUNTIME_BRANCH: string = "([^"]+)"', wurst)
assert branch_match, "RUNTIME_BRANCH is missing"
branch = branch_match.group(1)
suffix = f"/refs/heads/{branch}/src/Wurst.lua"

safety_match = re.search(r'RUNTIME_SAFETY_SOURCE_URL: string =\s*\n\s*"([^"]+)"', wurst)
assert safety_match, "RUNTIME_SAFETY_SOURCE_URL is missing"
assert safety_match.group(1).endswith(suffix), (
    "recovery loads a different branch from the runtime bundle"
)
assert suffix in readme, "README loader does not use the runtime branch"
assert "/refs/heads/main/src/Wurst.lua" not in readme

print(f"PASS delivery entry point, recovery and runtime use {branch}")
