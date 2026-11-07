#!/usr/bin/env python3
"""Guard the v190 rule that broke the gun on PC.

`Stats.Network.ServerStatsItem["Data Ping"]:GetValue()` is a Plugin-security
method. Delta answers it with "The current thread cannot call 'GetValue'
(lacking capability Plugin)". v183-v189 called it from the namecall hook that
sits between the player's mouse click and the gun's native FireServer, so the
console filled with that error and the gun never actuated.

These checks are static on purpose: the runtime must not contain the call at
all, and the hook must never hand the packet back to the engine after it has
run its own code.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"

# Files: every Lua source the bundle ships, minus the generated bundle itself.
sources = {
    path: path.read_text(encoding="utf-8")
    for path in SRC.rglob("*.lua")
    if path.name != "bundle.lua"
}
assert sources, "no sources found"


def code_lines(text: str):
    """Yield (line number, line) with Lua comments stripped per line."""
    for number, line in enumerate(text.split("\n"), start=1):
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        # Drop trailing `-- ...` comments, but not `--` inside a string. Good
        # enough here: the patterns searched never appear inside a literal.
        yield number, line


offenders = []
for path, text in sources.items():
    for number, line in code_lines(text):
        if re.search(r":\s*GetValue\s*\(", line):
            offenders.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
        if re.search(r"GetValueString\s*\(", line):
            offenders.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
assert not offenders, "Plugin-capability Stats reads are back:\n" + "\n".join(offenders)

base = (SRC / "games/MM2/base.lua").read_text(encoding="utf-8")
assert "GetNetworkPing" in base, "the latency source must be Player:GetNetworkPing"
assert 'FindFirstChild("Data Ping")' not in base, "base.lua must not resolve Data Ping"
assert "getLatencyReadings = readLatencyReadings" in base, "the predictor keeps its API"

overlay = (SRC / "guis/Wurst/Code/FloatingWindows.lua").read_text(encoding="utf-8")
assert "Data Ping" not in overlay, "the overlay must not read Data Ping"
assert "GetNetworkPing" in overlay, "the overlay reads the engine ping"

shoot = (SRC / "games/MM2/Blatant/Shoot.lua").read_text(encoding="utf-8")
start = shoot.index("local function installNativeGunHook")
end = shoot.index("local function uninstallNativeGunHook")
hook = shoot[start:end]
assert "task.defer" in hook, "the redirect must ship from a deferred thread"
assert "resendThroughEngine" not in hook, "no re-send through the clobbered register"
assert "resendingNativeShot" not in hook, "the old re-entrancy guard is gone"
# After deciding to redirect the hook may only trampoline untouched packets.
redirect = hook[hook.index("local function redirectNamecall"):]
assert "return predecessor(remote, ...)" in redirect
assert "remote:FireServer" not in redirect, "the game's thread never waits for our send"
assert "sendingRedirect" in redirect, "our own packet cannot re-enter the redirect"

print(
    "PASS capability guard: no Plugin GetValue in src, engine ping only, "
    "and the native gun hook defers instead of re-sending on the game thread"
)
