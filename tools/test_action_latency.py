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


# The framework clock itself: every TaskManager task runs per Heartbeat.
WURST = read("src/Wurst.lua")
assert "RunService.Heartbeat:Connect" in WURST

teleport = read("src/games/MM2/Movement/Teleport.lua")
# Auto Get Gun used to poll twice a second (up to 500 ms late) and the
# dropped-gun lookup cached a miss for 0.4 s (another ~400 ms). Both
# are gone: per-frame checks, an immediate tick on enable, and a
# ~3-frame negative cache.
assert "elapsed < 0.5" not in teleport
assert "TaskManager:Connect(autoGetGunTick)" in teleport
assert "autoGetGunTick()" in teleport, "enable must react the same frame"
base = read("src/games/MM2/base.lua")
assert "droppedGunCache.at < 0.05" in base
assert "droppedGunCache.at < 0.4" not in base

# Auto Farm: the full-bag sequence waits for conditions (equip landed,
# respawn arrived) per frame instead of sleeping fixed amounts.
farm = read("src/games/MM2/Other/AutoFarm.lua")
assert "equipDeadline" in farm
assert "task.wait(0.25)" not in farm.split("runFullSequence")[1]

# Deliberate delays stay. Removing these would not make anything
# faster in reality -- it would desync the knife animation, re-open
# the v105 lost-echo failure, spam the server past its swing rate,
# or bring back the Auto Unbox grey screen the user asked to avoid.
shoot = read("src/games/MM2/Blatant/Shoot.lua")
assert "SHOT_CONFIRM_WINDOW: number = 1.5" in shoot
knife_throw = read("src/games/MM2/Blatant/KnifeThrow.lua")
assert "MIN_PACKET_INTERVAL: number = 0.25" in knife_throw
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
