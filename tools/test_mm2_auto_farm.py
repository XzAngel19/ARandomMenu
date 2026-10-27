#!/usr/bin/env python3
"""Static architecture contract for MM2 Auto Farm v151 ("Below Map").

The user reported that v150 did not move the character and stole manual
controls. This build removes the render-step movement owner and the old route
solver, defaults to a physical Below Map pickup, and credits only server
CoinCollected events. Dynamic lifecycle checks live in the companion suite.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/AutoFarm.lua").read_text()
WURST = (ROOT / "src/Wurst.lua").read_text()

assert '"src/games/MM2/Other/AutoFarm.lua"' in WURST
assert '"Auto Farm"' in SOURCE
assert "restore = false" in SOURCE, "farming must be an explicit session action"
assert "featureConnections.MM2AutoFarmTick = TaskManager:Connect(farmTick)" in SOURCE

# Real pickup discovery and the exact server payment contract.
assert "state.mm2CoinPickups" in SOURCE
assert 'GetTagged("CoinVisual")' in SOURCE
assert 'object.Name == "Coin_Server"' in SOURCE
assert "local function serverPartOf" in SOURCE
assert 'attribute(source, "Collected")' in SOURCE
assert 'attribute(source, "Delete")' in SOURCE
assert 'attribute(server, "CoinID")' in SOURCE
for event in ("CoinsStarted", "CoinCollected", "RoundStart", "VictoryScreen",
              "RoundEndFade", "PlayerDataChanged"):
    assert f'"{event}"' in SOURCE, event
assert "ChangeInventoryItem" in SOURCE
assert "coinsConfirmed += 1" in SOURCE
assert "state.fireTouchInterest" in SOURCE, \
    "Below Map may nudge a local touch only after the physical overlap"
assert "firetouchinterest(" not in SOURCE, "use the late-bound state wrapper"
assert "runFullSequence" not in SOURCE
assert "killAll" not in SOURCE
assert "grabGunAndShoot" not in SOURCE

# No pathfinding, no render-step movement lock, no physics motor/hitbox hack.
assert "Pathfinding" not in SOURCE
assert "Path Finder" not in SOURCE
assert "PathfindingService" not in SOURCE
assert "ComputeAsync" not in SOURCE
assert "BindToRenderStep" not in SOURCE
assert "UnbindFromRenderStep" not in SOURCE
assert "humanoid:Move(" not in SOURCE
assert "humanoid:MoveTo(position)" in SOURCE
assert "RunService" not in SOURCE
assert "root.CFrame =" not in SOURCE
assert "root.Size =" not in SOURCE
assert "Instance.new(\"LinearVelocity\")" not in SOURCE
assert "AlignOrientation" not in SOURCE
assert "BodyVelocity" not in SOURCE and "BodyGyro" not in SOURCE
assert "HITBOX_SIZE" not in SOURCE
assert "safeZonePlatform" not in SOURCE
assert "task.wait" not in SOURCE

# Below Map: park under the real server part, then physically rise into its
# volume. Bounded contact refresh, never a CFrame-per-frame writer.
assert 'mode = "Below Map"' in SOURCE
assert '{"Below Map", "Direct"}' in SOURCE
assert "BELOW_OFFSET: number = 4" in SOURCE
assert "CONTACT_OFFSET: number = 0.6" in SOURCE
assert "CONTACT_REFRESH: number = 0.12" in SOURCE
assert "placeCharacter(character, root, parkPosition(position), now)" in SOURCE
assert "placeCharacter(character, root, contactPosition(position), now)" in SOURCE
assert "CFrame.lookAt(position, position + look)" in SOURCE
assert "character:PivotTo(destination)" in SOURCE
assert SOURCE.count("AssemblyLinearVelocity = Vector3.zero") == 2, \
    "only one contact placement and one Direct void rescue bound velocity"

# Manual control is preserved: no zero-move writer, WASD/jump yields farm.
assert "manualOverride = true" in SOURCE
assert '"Manual override"' in SOURCE
assert "MANUAL_PAUSE: number = 1.2" in SOURCE
assert "manualControlActive" in SOURCE
assert "releaseMovement" in SOURCE
assert 'setStatus("Paused · manual movement")' in SOURCE

# Round guards remain, but a missing local role no longer blocks the farm.
assert "core.isRoundLifecycleActive" in SOURCE
assert "core.getRoundPhase" in SOURCE
assert "core.findMM2Map" in SOURCE
assert "core.getPlayerRole" not in SOURCE
assert 'role ~= "Innocent"' not in SOURCE
assert "RoundTimerPart" in SOURCE and 'GetAttribute("Time")' in SOURCE
assert 'featureEnabled("Anti Void")' in SOURCE

# UI: Below Map by default, no retired options.
for label in ("Coins Collected", "Time", "State", "Farm mode", "Step interval",
              "Manual override", "Jump for high pickups", "Roam when empty",
              "Void rescue", "Stop at full bag"):
    assert f'"{label}"' in SOURCE, label
assert "Navigation" not in SOURCE
assert "state.mm2AutoFarmSnapshot" in SOURCE

print("PASS MM2 Auto Farm v151 static contract (Below Map, manual control, server coins)")
