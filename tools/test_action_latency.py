#!/usr/bin/env python3
"""Action-latency contract: user-triggered actions leave on the first
frame the client can produce, with no hidden polling throttle.

Heartbeat is the fastest cadence a Roblox client script gets, so
"instant" means: event handlers fire synchronously, TaskManager loops
run every Heartbeat, and waits only exist where they are either
user-configured (a slider the user owns) or load-bearing (a server /
animation / safety constraint measured in live sessions). This test
pins both halves so nobody reintroduces a silent 0.5 s poll, and
nobody "optimizes" away a deliberate gate either.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text()


# The framework clock itself: every non-render TaskManager task runs per
# Heartbeat. The signal is opened lazily through syncTaskConnection rather than
# kept alive for an empty bucket, so check the phase selection and connection.
WURST = read("src/Wurst.lua")
assert "else RunService.Heartbeat" in WURST
assert "owner[field] = signal:Connect" in WURST

teleport = read("src/games/MM2/Movement/Teleport.lua")
# Auto Get Gun used to poll twice a second (up to 500 ms late) and the
# dropped-gun lookup cached a miss for 0.4 s (another ~400 ms). Both
# are gone: per-frame checks, an immediate tick on enable, and a
# ~3-frame negative cache.
assert "elapsed < 0.5" not in teleport
assert "TaskManager:Connect(autoGetGunTick)" in teleport
assert "autoGetGunTick()" in teleport, "enable must react the same frame"
assert "Gun pickup delay" not in teleport
assert "autoGetGunDelay" not in teleport
assert "task.wait" not in teleport, "manual and automatic gun pickup are immediate"
base = read("src/games/MM2/base.lua")
assert "autoGetGunDelay" not in base
assert "droppedGunCache.at < 0.05" in base
assert "droppedGunCache.at < 0.4" not in base

# Auto Farm (v151): the farm reacts on the shared Heartbeat tick. It must NOT
# bind a render-step movement owner (that stole player controls in v150).
# Below Map uses bounded whole-model placements; Direct refreshes native
# MoveTo. There is no full-bag coroutine, no gun-touch routine and no sleep.
farm = read("src/games/MM2/Other/AutoFarm.lua")
assert "TaskManager:Connect(farmTick)" in farm
assert "BindToRenderStep" not in farm, "never overwrite default player controls"
assert "humanoid:Move(" not in farm, "no zero-move writer that freezes input"
assert "humanoid:MoveTo(position)" in farm, "Direct uses native locomotion"
assert "CONTACT_REFRESH: number = 0.12" in farm, "contact refresh stays bounded"
assert "MANUAL_PAUSE: number = 1.2" in farm, "manual input always wins briefly"
assert "task.wait" not in farm, "farm must not add hidden polling sleeps"
assert "firetouchinterest(" not in farm, "a local fake touch is not a server coin"

# Deliberate delays stay. Removing these would not make anything
# faster in reality -- it would desync the knife animation, re-open
# the v105 lost-echo failure, spam the server past its swing rate,
# or bring back the Auto Unbox grey screen the user asked to avoid.
shoot = read("src/games/MM2/Blatant/Shoot.lua")
assert "SHOT_CONFIRM_WINDOW: number = 1.5" in shoot
knife_throw = read("src/games/MM2/Combat/KnifeThrow.lua")
assert '"Delay"' in knife_throw  # Independent module with user-controlled delay
knife_aura = read("src/games/MM2/Blatant/KnifeAura.lua")
assert "lastAuraSwing < 0.86" in knife_aura  # measured swing cycle
unbox = read("src/games/MM2/Other/AutoUnbox.lua")
assert '"Delay between boxes"' in unbox  # user-owned pacing

# User-configured rates are not hidden delays: the user sets them.
trigger = read("src/games/universal/Combat/TriggerBot.lua")
assert 'options["Delay"].Value' in trigger
kill_aura = read("src/games/universal/Combat/KillAura.lua")
assert '"Swings per second"' in kill_aura

print("PASS action latency: per-frame reactions, immediate Auto Get Gun, "
      "frame-checked Auto Farm waits; deliberate server/animation/user "
      "gates documented and intact")
