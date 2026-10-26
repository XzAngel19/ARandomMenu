#!/usr/bin/env python3
"""Static architecture contract for the current MM2 Auto Farm source.

Dynamic lifecycle/physics checks live in test_mm2_auto_farm_dynamics.py.
No assertion here is evidence of live coins, damage or wins.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/AutoFarm.lua").read_text()
WURST = (ROOT / "src/Wurst.lua").read_text()

assert '"src/games/MM2/Other/AutoFarm.lua"' in WURST
assert '"Auto Farm"' in SOURCE
assert '"Farm Speed", 16, 5, 60' in SOURCE
for option, default in (
    ("Reset When Full Coin Bag", "true"),
    ("Fling Murder after reset", "false"),
    ("Fling Sheriff after reset", "false"),
    ("Auto Grab gun and Shoot", "false"),
    ("Auto Kill All When full coin bag", "false"),
):
    assert f'"{option}", {default}' in SOURCE

# Below has one fixed contact pose and one PreSimulation constraint writer.
assert "local BELOW_OFFSET: number = 3.0" in SOURCE
assert "Vector3.new(4, 8, 4)" in SOURCE
assert "root.Size = HITBOX_SIZE" in SOURCE
assert "LinearVelocity" in SOURCE and "AlignOrientation" in SOURCE
assert "BodyVelocity" not in SOURCE and "BodyGyro" not in SOURCE
assert "local function preFarmPhysics" in SOURCE
assert "moveTowards(root, belowDestination" in SOURCE
assert "nearestPosition :: Vector3) - Vector3.new(0, BELOW_OFFSET, 0)" in SOURCE
assert "BELOW_OFFSET + 3.5" not in SOURCE
assert "initialPlacement" in SOURCE
assert "hideAnchorPosition = root.Position" in SOURCE
assert "nextCF" not in SOURCE and "root.CFrame = destCF" not in SOURCE

# Walk uses Humanoid locomotion, not a parallel CFrame/velocity writer.
assert "humanoid:Move(unitDir, false)" in SOURCE
assert "humanoid.WalkSpeed = speed" in SOURCE
assert "humanoid.Jump = true" in SOURCE
walk_body = SOURCE.split("local function walkTowards", 1)[1].split(
    "-- The Coin_Server part", 1
)[0]
assert "root.CFrame" not in walk_body
assert "AssemblyLinearVelocity" not in walk_body
assert "MoveTo" not in walk_body

# Active-round and living-character gates cover ordinary and terminal work.
assert "isRoundLifecycleActive() ~= true" in SOURCE
assert "local function livingRoundParts" in SOURCE
assert "canReposition" in SOURCE
assert "humanoid.Health <= 0" in SOURCE
assert "enableGeneration" in SOURCE and "roundGeneration" in SOURCE
assert "rememberedFullHandled" in SOURCE
assert "thisEnable == enableGeneration" in SOURCE
assert "thisRound == roundGeneration" in SOURCE
assert "task.spawn(runFullSequence, thisEnable, roundGeneration)" in SOURCE
assert "elseif settings.grabGunShoot and canGrabGun()" not in SOURCE
assert "local function runFullSequence(thisEnable: number, thisRound: number)" in SOURCE
assert "killAll(alive)" in SOURCE
assert "grabGunAndShoot(alive)" in SOURCE
assert "flingPlayer(findMurderer(), alive)" in SOURCE
assert "flingPlayer(findSheriff(), alive)" in SOURCE

# Fling is only a shared API call; there is no local fallback.
assert "state.mm2PerformFling" in SOURCE
assert "AssemblyAngularVelocity = Vector3.new(0, 400, 0)" not in SOURCE
assert "mm2FlingStep" not in SOURCE
assert "10000" not in SOURCE and "12000" not in SOURCE

# Coin detection, touch pickup, blacklist and cleanup remain intact.
assert "state.mm2CoinPickups" in SOURCE
assert '"Coin_Server"' in SOURCE
assert '"CoinCollected"' in SOURCE
assert "BLACKLIST_SECONDS" in SOURCE
assert "stillCollectable" in SOURCE
assert "state.fireTouchInterest" in SOURCE
assert "savedRootSize" in SOURCE and "savedCollide" in SOURCE
assert "destroyFarmConstraints" in SOURCE
assert "restoreCharacter(false)" in SOURCE
assert "restoreCharacter(true)" in SOURCE
assert '"Auto Farm: waiting in lobby"' in SOURCE

# Full-bag ordering remains Kill All -> return -> gun -> reset -> flings.
sequence = SOURCE.split("local function runFullSequence", 1)[1]
assert sequence.index("killAll(alive)") < sequence.index("restoreCharacter(true)")
assert sequence.index("restoreCharacter(true)") < sequence.index("grabGunAndShoot(alive)")
assert sequence.index("grabGunAndShoot(alive)") < sequence.index("humanoid.Health = 0")
assert sequence.index("humanoid.Health = 0") < sequence.index("flingPlayer(findMurderer(), alive)")

print("PASS MM2 Auto Farm static: fixed Below contact, constraint-owned movement, "
      "Humanoid Walk, strict alive/round guards, one terminal sequence, "
      "remembered full-bag idempotence and shared Fling only")
