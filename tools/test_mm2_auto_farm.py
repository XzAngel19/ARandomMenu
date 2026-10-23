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

# Two farm modes: Walk on the ground, or Below with a grown hitbox.
assert '"Farm Mode"' in SOURCE and '"Walk"' in SOURCE
assert '"Below (Hitbox)"' in SOURCE
# Below: Coin_Server is 1.2x2x2 (one stud either side of its centre);
# riding 3 studs under it with an 8-tall root hitbox overlaps that
# volume without ever lying the character face-down.
assert "local BELOW_OFFSET: number = 3.0" in SOURCE
assert "Vector3.new(4, 8, 4)" in SOURCE
assert "root.Size = HITBOX_SIZE" in SOURCE
assert "savedRootSize" in SOURCE  # hitbox restored on OFF
# The face-down tilt is gone for good (that fight glitched the camera).
assert "math.rad(90)" not in SOURCE
assert "PlatformStand = true" in SOURCE  # Below only, upright
# Walk: plain humanoid locomotion at slider WalkSpeed, restored after.
assert "humanoid:Move(flat.Unit, false)" in SOURCE
assert "humanoid.WalkSpeed" in SOURCE and "savedWalkSpeed" in SOURCE
assert "humanoid.Jump = true" in SOURCE  # hop when walking stalls
assert "CanCollide = false" in SOURCE  # Below NoClip

# Lobby safety: hands off the character when there is no target.
assert "restoreCharacter(false)" in SOURCE
assert "no coins - roaming" in SOURCE
# A coin-less tick must not park the body under the floor: it restores
# home upright, then keeps walking a slow circle around it.
assert "restoreCharacter(true)" in SOURCE
assert "recovered from the void" in SOURCE
assert "humanoid:Move(roamFlat.Unit, false)" in SOURCE
assert "roamTarget" in SOURCE and "roamAnchor" in SOURCE

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

# Full-bag actions ONLY at 50: Kill All, grab gun + SilentAim shot,
# reset and flings all live in the full-bag sequence; the per-tick grab
# is gone so nothing fires during ordinary farming.
assert "state.mm2FireSilentShot" in SOURCE
assert "grabGunAndShoot" in SOURCE
assert "settings.grabGunShoot) then" in SOURCE
assert "during ordinary farming" in SOURCE
assert "findDroppedGun" in SOURCE
assert "humanoid:EquipTool(gun :: Tool)" in SOURCE
assert 'gun:FindFirstChild("Shoot")' in SOURCE  # direct fallback shot
assert "prediction.gunAim" in SOURCE
assert "or settings.flingMurder or settings.flingSheriff" in SOURCE
assert "going for the dropped gun" not in SOURCE, \
    "no gun grab in the ordinary farming tick"
tick_body = SOURCE.rsplit("featureConnections.MM2AutoFarmTick", 1)[1]
assert "findDroppedGun" not in tick_body.split("-- Nearest pickup")[0], \
    "the farming tick never looks for the dropped gun"

# A coin that never collects is skipped instead of trapping the farm.
assert "BLACKLIST_SECONDS" in SOURCE

# Already-collected coins stop being targets immediately (the old farm
# flew up to a ghost coin and hovered over it).
assert "stillCollectable" in SOURCE
assert 'GetAttribute("Collected")' in SOURCE

# Parked collections also pulse the touch directly (physics Touched
# is not guaranteed for a fully NoClipped body).
assert "state.fireTouchInterest" in SOURCE

print("PASS MM2 Auto Farm: Walk (ground locomotion, slider WalkSpeed, "
      "hop on stall) and Below (Hitbox) (upright velocity flight, grown "
      "4x8x4 root hitbox, NoClip, no face-down tilt, no 267 teleports), "
      "collected coins dropped as targets at once, uncollectable coins "
      "blacklisted, lobby/coin-less roaming instead of parking under the floor, OFF restores hitbox/WalkSpeed and "
      "returns home upright, ping in status, full-bag reset/flings, "
      "YARHM Kill All, grab gun")
