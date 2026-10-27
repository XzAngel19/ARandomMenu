#!/usr/bin/env python3
"""Static architecture contract for the rebuilt MM2 Auto Farm (v150).

Evidence: TestingStuff / "place, source.rbxlx" (placeId 142823291) and the
remote-spy logs. Coins are server-owned `Coin_Server` parts with a
TouchTransmitter; only `CoinsStarted` / `CoinCollected` confirm a payment.
Dynamic lifecycle/physics checks live in test_mm2_auto_farm_dynamics.py.
No assertion here is evidence of live coins, damage or wins.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/AutoFarm.lua").read_text()
WURST = (ROOT / "src/Wurst.lua").read_text()

assert '"src/games/MM2/Other/AutoFarm.lua"' in WURST
assert '"Auto Farm"' in SOURCE
assert 'restore = false' in SOURCE, "farming must be an explicit session action"
assert 'featureConnections.MM2AutoFarmTick = TaskManager:Connect(farmTick)' in SOURCE

# Real pickup discovery: Coin ESP's provider first, then the game's own tag and
# the exact spawn part name. No generic "coin" name harvesting.
assert 'state.mm2CoinPickups' in SOURCE
assert 'GetTagged("CoinVisual")' in SOURCE
assert 'object.Name == "Coin_Server"' in SOURCE
assert 'local function serverPartOf' in SOURCE
assert 'attribute(part, "Collected")' in SOURCE
assert 'attribute(part, "Delete")' in SOURCE
assert 'attribute(part, "CoinID")' in SOURCE

# Only the server's own remotes confirm a coin. A local fake touch cannot.
for event in ("CoinsStarted", "CoinCollected", "RoundStart", "VictoryScreen",
              "RoundEndFade", "PlayerDataChanged"):
    assert f'"{event}"' in SOURCE, event
assert 'ChangeInventoryItem' in SOURCE
assert 'coinsConfirmed += 1' in SOURCE
assert 'firetouchinterest(' not in SOURCE, "only documentation may mention it"
assert 'state.fireTouchInterest' not in SOURCE
assert 'runFullSequence' not in SOURCE
assert 'killAll' not in SOURCE
assert 'grabGunAndShoot' not in SOURCE

# Movement is native locomotion: no CFrame per tick, no hitbox resize, no
# velocity/constraint writers, no "below the map" hack.
assert 'humanoid:Move(desiredDirection, false)' in SOURCE
assert 'BindToRenderStep' in SOURCE and 'UnbindFromRenderStep' in SOURCE
assert 'humanoid:MoveTo(position)' in SOURCE
assert 'PathfindingService' in SOURCE and 'ComputeAsync' in SOURCE
assert 'root.CFrame =' not in SOURCE
assert 'root.Size =' not in SOURCE
# The only velocity write is the single bounded void rescue; there is no
# per-frame velocity/constraint writer driving the farm.
assert SOURCE.count('AssemblyLinearVelocity = Vector3.zero') == 1
assert 'Instance.new("LinearVelocity")' not in SOURCE
assert 'AlignOrientation' not in SOURCE
assert 'BodyVelocity' not in SOURCE and 'BodyGyro' not in SOURCE
assert 'BELOW_OFFSET' not in SOURCE and 'HITBOX_SIZE' not in SOURCE
assert 'holdHiddenUnderMap' not in SOURCE and 'safeZonePlatform' not in SOURCE
assert 'Stay Under When Round starts' not in SOURCE
assert 'task.wait' not in SOURCE

# Round/role guards and single bounded void rescue.
assert 'core.isRoundLifecycleActive' in SOURCE
assert 'core.getRoundPhase' in SOURCE
assert 'core.findMM2Map' in SOURCE
assert 'core.getPlayerRole' in SOURCE
assert 'role ~= "Innocent"' in SOURCE
assert 'RoundTimerPart' in SOURCE and 'GetAttribute("Time")' in SOURCE
assert 'character:PivotTo(destination)' in SOURCE
assert 'featureEnabled("Anti Void")' in SOURCE

# UI: the rebuilt options, not the retired ones.
for label in ("Coins Collected", "Time", "State", "Navigation", "Step interval",
              "Jump for high pickups", "Roam when empty", "Void rescue",
              "Stop at full bag"):
    assert f'"{label}"' in SOURCE, label
assert 'state.mm2AutoFarmSnapshot' in SOURCE

print("PASS MM2 Auto Farm v150 static contract (server-confirmed coins, native walk)")
