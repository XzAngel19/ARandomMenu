#!/usr/bin/env python3
"""v139.2: knife throw discipline -- the blade must be in hand, and the aim
solver must not run every frame.

The saved v139.1 session has 13 knife activations and 9 observed blades. Four
crossed the remote without ever becoming a projectile, and the ones that did
fire from the RightHand fallback origin instead of the knife handle, because
`EquipTool` is a round trip and `FireServer` is not. This suite runs the real
`throwKnife` from the module against a tool that only reaches the character
after one frame and asserts:

  * the first call equips and does NOT fire,
  * the remote is not re-spammed while the equip is travelling,
  * once the handle is in the character the throw fires with the handle origin,
  * the equipped path still works for a tool that was already in hand,
  * the per-frame loop solves the aim at most 15x/s, not 60x/s, and still
    throws on time once a target is in range.

LUAU=/path/to/luau python3 tools/test_mm2_knife_equip.py
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
KNIFE = (ROOT / "src/games/MM2/Combat/KnifeThrow.lua").read_text()

code = PRELUDE + r'''
local clock = 0
-- The module reads os.clock() for its cooldown and its aim cache.
os.clock = function() return clock end
local Player = {Name = 'Local'}
local LocalPlayer = Player
local fired = {}
local equips = 0

local remote = {IsA = function(_, class) return class == 'RemoteEvent' end}
function remote:FireServer(origin, target)
    table.insert(fired, {origin = origin, target = target})
end

local function makeKnife()
    local handle = {CFrame = CFrame.new(Vector3.new(0, 2, 0))}
    function handle:IsA(class) return class == 'BasePart' end
    local events = {KnifeThrown = remote}
    function events:FindFirstChild(name)
        if name == 'KnifeThrown' then return remote end
        return nil
    end
    local tool = {Name = 'Knife', Parent = nil}
    function tool:FindFirstChild(name)
        if name == 'Handle' then return handle end
        if name == 'Events' then return events end
        return nil
    end
    function tool:IsA() return true end
    return tool, handle
end

local knife, handle = makeKnife()
local backpack = {}
local character = {Name = 'Character'}
function character:FindFirstChild(name)
    if name == 'RightHand' then return nil end
    if name == 'Right Arm' then return nil end
    if name == 'HumanoidRootPart' then return handle end
    return nil
end
function character:FindFirstChildOfClass(class)
    if class == 'Humanoid' then
        return {EquipTool = function(_, tool)
            equips += 1
            -- The equip is a round trip: the tool reaches the character only
            -- when the next frame is simulated.
        end}
    end
    return nil
end
Player.Character = character
Player.FindFirstChildOfClass = function(_, class)
    if class == 'Backpack' then return {GetChildren = function() return {} end} end
    return nil
end
knife.Parent = backpack

local function getPlayerWeapon() return knife end
local function getPlayerRole(who)
    if who == Player then return 'Murderer' end
    return 'Innocent'
end
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
local function getEstimatedLatency() return 0.1 end
local function isWeaponPathClear() return true end
local lobby = {Player}
local getPlayersCalls = 0
local Players = {GetPlayers = function()
    getPlayersCalls += 1
    return lobby
end}
local state = {mm2Prediction = nil}
local featureConnections = {}
local function disconnectFeatureConnection(name) featureConnections[name] = nil end
local function createUniversalFeature() return {} end
local function addToggleOption() end
local function addNumberOption() end
local function addInformationOption() end

-- Module.init state that lives above the extracted section.
local settings = {enabled = true, autoThrow = true, wallCheck = true,
    knifeTracer = false, delay = 0.6}
local lastThrowAttempt = 0
local tracerPart, targetDotPart = nil, nil
local hookedWeaponService, origGetMouseTargetCFrame, origGetTargetPosition =
    nil, nil, nil
local function destroyTracerVisuals() end
local prediction = nil

local function load()
''' + section(
    KNIFE, "    -- Check if player is valid target", "    -- Toggle function"
) + r'''
    return throwKnife, getKnife, getThrowOriginCFrame, knifeThrowLoop
end

local throwKnife, getKnife, _getOrigin, knifeThrowLoop = load()
local target = {Name = 'MurdererTarget', Character = {
    FindFirstChild = function() return nil end,
}}
local victimRoot = {Position = Vector3.new(6, 0, 0), AssemblyLinearVelocity = Vector3.zero}
function target.Character:FindFirstChild(name)
    if name == 'HumanoidRootPart' then return victimRoot end
    return nil
end
function target.Character:FindFirstChildOfClass(class)
    if class == 'Humanoid' then return {Health = 100} end
    return nil
end
target.Character.IsA = function(_, c) return c == 'Model' end
table.insert(lobby, target)

-- 1. First call: the knife is in the backpack. It equips, it must NOT fire.
local ok = throwKnife(target, knife)
assert(ok == false, 'a throw from a backpack tool must not fire')
assert(#fired == 0, 'no packet may leave before the blade is in hand')
assert(equips == 1, 'the equip must be requested exactly once')

-- 2. The equip is still travelling (same frame): no second EquipTool, no fire.
clock = 0.05
assert(throwKnife(target, knife) == false, 'still waiting for the equip')
assert(equips == 1, 'the equip must not be re-spammed every frame')
assert(#fired == 0, 'no packet while the equip is in flight')

-- 3. The server accepted the equip: the blade is in the character now.
knife.Parent = character
ok = throwKnife(target, knife)
assert(ok == true, 'an equipped blade must throw')
assert(#fired == 1, 'exactly one packet per throw')
assert(equips == 1, 'no extra equip once the blade is in hand')

-- 4. Already equipped from the start: fire immediately.
fired = {}
assert(throwKnife(target, knife) == true, 'an already equipped blade throws at once')
assert(#fired == 1 and equips == 1, 'one packet, no equip churn')

-- 5. Frame cost: one simulated second of the loop at 60 fps must not solve
-- the aim 60 times. resolveKnifeAim casts a line-of-sight ray per player, so
-- the 15 Hz cache is what keeps an idle menu from burning frames.
settings.autoThrow = false
settings.knifeTracer = false
settings.delay = 0.6
getPlayersCalls = 0
clock = 100
knifeThrowLoop()
for frame = 1, 60 do
    clock = 100 + frame / 60
    knifeThrowLoop()
end
assert(getPlayersCalls <= 20,
    'the aim solver ran ' .. tostring(getPlayersCalls) .. ' times in 61 frames')
assert(getPlayersCalls >= 2, 'the cache must still refresh (saw ' .. tostring(getPlayersCalls) .. ')')
local solvesPerSecond = getPlayersCalls

-- 6. And the thinning must not cost a throw: the blade still leaves on time.
settings.autoThrow = true
fired = {}
getPlayersCalls = 0
local throws = 0
for frame = 1, 120 do
    clock = 200 + frame / 60
    local before = #fired
    knifeThrowLoop()
    if #fired > before then throws += 1 end
end
assert(throws >= 3 and throws <= 5,
    'a 0.6 s delay over 2 s must throw 3-4 times, saw ' .. tostring(throws))
assert(getPlayersCalls <= 2 * 20,
    'throwing must not restore a per-frame solve (saw ' .. tostring(getPlayersCalls) .. ')')

print('PASS knife equip: no packet before the blade is in hand, then one per throw')
print('PASS knife loop: aim solved ' .. tostring(solvesPerSecond)
    .. 'x per second at 60 fps, ' .. tostring(throws) .. ' throws on schedule')
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="knife-equip-") as directory:
        script = Path(directory) / "equip.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
