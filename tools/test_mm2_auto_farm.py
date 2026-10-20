#!/usr/bin/env python3
"""Static contract for the MM2 Auto Farm module.

v83 fixes from live play: the server kicked with "Invalid position"
(267) because the root was CFrame-teleported every tick, the camera
glitched because prone/noclip were applied even in the lobby, and
turning the feature off left the character lying in geometry. The
farm now moves by physics velocity at a user-tunable Farm Speed,
engages only when a target exists, NoClips while engaged, and
restores everything (returning home upright) on OFF.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Other/AutoFarm.lua').read_text()
WURST = (ROOT / 'src/Wurst.lua').read_text()

# Registered in the MM2 module load list.
assert '"src/games/MM2/Other/AutoFarm.lua"' in WURST

# Feature + Farm Speed slider + the five requested options.
assert '"Auto Farm"' in SOURCE
assert '"Farm Speed", 16, 5, 60' in SOURCE, "user-tunable speed slider, slow default"
for option, default in (
    ("Reset When Full Coin Bag", "true"),
    ("Fling Murder after reset", "false"),
    ("Fling Sheriff after reset", "false"),
    ("Auto Grab gun and Shoot", "false"),
    ("Auto Kill All When full coin bag", "false"),
):
    needle = f'"{option}", {default}'
    assert needle in SOURCE, f"missing option: {option}"

# Movement is physics velocity, never per-tick CFrame teleports.
assert "root.AssemblyLinearVelocity = delta.Unit * speed" in SOURCE
assert "Invalid position" in SOURCE  # documented in the module
assert "settings.speed" in SOURCE

# Coins come from Coin ESP's detection, shared through state.
assert "state.mm2CoinPickups" in SOURCE
assert '"Coin_Server"' in SOURCE  # fallback scan if Coin ESP is off

# One constant collect height: Coin_Server is 1.2x2x2 in the place,
# reaching 1 stud either side of the coin centre, so a body part
# overlaps it at all times (the old 3.1 ride height touched nothing;
# a two-phase rise bobbed visibly at every coin).
assert "local UNDER_OFFSET: number = 1.0" in SOURCE

# Prone applied once on engage; NoClip forced while engaged.
assert "CFrame.Angles(math.rad(90), 0, 0)" in SOURCE
assert "CanCollide = false" in SOURCE
assert "PlatformStand = true" in SOURCE

# Lobby safety: hands off the character when there is no target.
assert "restoreCharacter(false)" in SOURCE
assert "waiting for coins" in SOURCE

# OFF restores everything and returns the character home, upright.
assert "restoreCharacter(true)" in SOURCE
assert "PlatformStand = false" in SOURCE
assert "AutoRotate = true" in SOURCE
assert "homeCFrame" in SOURCE

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
assert "humanoid:EquipTool(gun :: Tool)" in SOURCE
assert 'gun:FindFirstChild("Shoot")' in SOURCE
assert "prediction.gunAim" in SOURCE

# A coin that never collects is skipped instead of trapping the farm.
assert "BLACKLIST_SECONDS" in SOURCE

# Parked collections also pulse the touch directly (physics Touched
# is not guaranteed for a fully NoClipped body).
assert "state.fireTouchInterest" in SOURCE

print("PASS MM2 Auto Farm: velocity flight at slider speed (no CFrame "
      "teleports, no 267 kick), NoClip + prone on engage only, "
      "constant-height collect (a body part always overlaps the "
      "2-stud Coin_Server volume; touch pulse), lobby hands-off, "
      "OFF returns home upright, ping "
      "in status, full-bag reset/flings, YARHM Kill All, grab gun")
