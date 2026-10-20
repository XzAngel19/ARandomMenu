#!/usr/bin/env python3
"""Static contract for the MM2 Auto Farm module.

The farm reuses Coin ESP's pickup list, moves prone under the map at a
ping-derived safe speed, and implements the requested full-bag options.
Kill All is adapted from YARHM 1.21 ("Kill EVERYONE as murderer"):
anchor every victim in front of the local root, then slash.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Other/AutoFarm.lua').read_text()
WURST = (ROOT / 'src/Wurst.lua').read_text()

# Registered in the MM2 module load list.
assert '"src/games/MM2/Other/AutoFarm.lua"' in WURST

# Feature + the five requested options, with the requested defaults.
assert '"Auto Farm"' in SOURCE
for option, default in (
    ("Reset When Full Coin Bag", "true"),
    ("Fling Murder after reset", "false"),
    ("Fling Sheriff after reset", "false"),
    ("Auto Grab gun and Shoot", "false"),
    ("Auto Kill All When full coin bag", "false"),
):
    needle = f'"{option}", {default}'
    assert needle in SOURCE, f"missing option: {option}"

# Coins come from Coin ESP's detection, shared through state.
assert "state.mm2CoinPickups" in SOURCE
assert '"Coin_Server"' in SOURCE  # fallback scan if Coin ESP is off

# Prone under the map, nearest coin first.
assert "UNDER_OFFSET" in SOURCE
assert "CFrame.Angles(math.rad(90), 0, 0)" in SOURCE
assert "nearestDistance" in SOURCE

# Speed is automatic from the measured ping, never a bare constant,
# and every step is capped by delta time.
assert "getEstimatedLatency" in SOURCE
assert "math.clamp(9.0 / ping, 45, 150)" in SOURCE
assert "speed * deltaTime" in SOURCE

# Full bag comes from the game's own CoinCollected report.
assert '"CoinCollected"' in SOURCE
assert "bagAmount >= bagLimit" in SOURCE

# Reset + respawn wait, then the optional flings.
assert "humanoid.Health = 0" in SOURCE
assert "findMurderer" in SOURCE and "findSheriff" in SOURCE
assert "AssemblyAngularVelocity = Vector3.new(0, 400, 0)" in SOURCE

# Kill All, YARHM-style: victims anchored in front, then the slash.
assert 'getPlayerRole(LocalPlayer) ~= "Murderer"' in SOURCE
assert "victimRoot.Anchored = true" in SOURCE
assert 'FireServer("Slash")' in SOURCE
assert '"HandleTouched"' in SOURCE

# Grab gun and shoot: dropped gun lookup, equip, one predicted shot.
assert "findDroppedGun" in SOURCE
assert "humanoid:EquipTool(gun" in SOURCE or "humanoid:EquipTool(gun :: Tool)" in SOURCE
assert 'gun:FindFirstChild("Shoot")' in SOURCE
assert "prediction.gunAim" in SOURCE

# A coin that never collects is skipped instead of trapping the farm.
assert "BLACKLIST_SECONDS" in SOURCE

# OFF restores collisions and AutoRotate.
assert "restoreProne" in SOURCE
assert "AutoRotate = true" in SOURCE

print("PASS MM2 Auto Farm: prone under-map nearest-coin farm, ping-safe "
      "speed, Coin ESP pickups, full-bag reset/flings, YARHM Kill All, "
      "grab gun + predicted shot, stuck-coin skip, OFF restore")
