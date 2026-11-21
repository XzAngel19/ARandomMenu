#!/usr/bin/env python3
"""Guard the executor-only screenshot replica against feature code and UI drift."""
from pathlib import Path
import re

source = (Path(__file__).resolve().parents[1] / "SpeedHubX.client.luau").read_text()

# Single file: no calls out to Wurst, games, remote sources, or gameplay APIs.
for forbidden in ("require(", "loadstring(", "HttpGet(", "FireServer(",
                  "InvokeServer(", "VirtualInputManager", "Humanoid:"):
    assert forbidden not in source, forbidden

hooks = ("OnTabSelected", "AutoUltimate", "AutoDash", "AimPart", "Aimlock",
         "AntiKnockback", "AntiStun", "AntiBusy")
for hook in hooks:
    assert re.search(rf"function Features\.{hook}\([^)]*\) end", source), hook

for module in ("Core", "Controls", "Navigation", "Features"):
    assert f"local {module} = {{}}" in source
for text in ("Speed Hub X | Version: 3.7.0", "Home", "Main", "Farming",
             "Killer", "Misc", "Skill", "Aim", "Body", "Auto Ultimate",
             "This is Meaning Auto Use Ultimate", "Auto Dash",
             "This is Meaning Auto Use Dash", "Choose Aim Part", "Head",
             "Aimlock = Lock Camera Player", "Anti-Knockback", "Anti-Stun",
             "Anti-Busy", "BETA"):
    assert text in source, text

assert 'Size = UDim2.fromOffset(1016, 646)' in source
assert 'Position = UDim2.fromOffset(-168, 76)' in source
assert source.count("Controls.toggle(main, {") == 6
assert source.count("Controls.dropdown(main, {") == 1
assert "Controls.slider(main," not in source
assert "Controls.button(main," not in source
assert 'initial = true, onChange = Features.AutoUltimate' in source
assert 'initial = true, onChange = Features.AutoDash' in source
assert "if type(gethui)" in source and "CoreGui" in source and "PlayerGui" in source
assert "ResetOnSpawn = false" in source
print("PASS standalone Speed Hub X UI: labels/layout, empty hooks, no gameplay/remote code")
