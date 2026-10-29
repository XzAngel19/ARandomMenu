#!/usr/bin/env python3
"""v158: the speculative knife aims down map openings, not at opponents.

The v157 build centred its pre-fire points on the nearest hidden opponent and
walked radii around that body. With WallCheck on, the native throw redirect
therefore pointed through geometry at a player nobody could see, and a corpse
lying on the floor received the same treatment. This suite runs the real
`findTarget` / `resolveSpeculativeAim` / `throwKnife` against a small analytic
map (axis-aligned walls, a doorway, a floor and a void beyond it) and asserts:

  * a hidden opponent does not move the lane; the lane goes through the door,
  * a dead body is never a target and never the aim point,
  * a sealed room produces no throw at all,
  * with the wall in front and an opening to the side, the side is chosen,
  * `isPlayerAlive` and the predictor's body check reject ragdoll states.

These are client-side geometry assertions. They do not prove server damage,
hit rate or anti-cheat behaviour.

LUAU=/path/to/luau python3 tools/test_mm2_knife_openings.py
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "src/games/MM2/base.lua").read_text()
PREDICTION = (ROOT / "src/games/MM2/Prediction.lua").read_text()
KNIFE = (ROOT / "src/games/MM2/Combat/KnifeThrow.lua").read_text()

ALIVE = section(BASE, "local function isPlayerAlive", "local function playerFromRoundKey")
CORPSE_HELPER = section(PREDICTION, "local function bodyIsAlive", "local AIM_PARTS")
LANES = section(KNIFE, "    -- Check if player is valid target", "    -- Toggle function")

code = PRELUDE + ALIVE + r'''
-- Analytic map: axis-aligned boxes only, plus a floor. Every ray is a segment
-- and the nearest entry point wins, which is enough to tell a doorway from a
-- wall and a floor from the void.
local boxes = {}
local function addBox(x0, y0, z0, x1, y1, z1)
    table.insert(boxes, {
        min = {x0, y0, z0},
        max = {x1, y1, z1},
    })
end
local function resetMap()
    table.clear(boxes)
end
local function rayBox(origin, direction, box)
    local o = {origin.X, origin.Y, origin.Z}
    local d = {direction.X, direction.Y, direction.Z}
    local low, high = 0, math.huge
    local axis = nil
    for i = 1, 3 do
        if math.abs(d[i]) < 1e-9 then
            if o[i] < box.min[i] or o[i] > box.max[i] then
                return nil
            end
        else
            local t1 = (box.min[i] - o[i]) / d[i]
            local t2 = (box.max[i] - o[i]) / d[i]
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > low then
                low, axis = t1, i
            end
            if t2 < high then
                high = t2
            end
            if low > high then
                return nil
            end
        end
    end
    if low > 1 or high < 0 then
        return nil
    end
    return low, axis
end
local function worldRaycast(origin, direction)
    local best, bestT, bestAxis = nil, math.huge, nil
    for _, box in ipairs(boxes) do
        local t, axis = rayBox(origin, direction, box)
        if t and t < bestT then
            best, bestT, bestAxis = box, t, axis
        end
    end
    if not best then
        return nil
    end
    local normal
    if bestAxis == 1 then
        normal = Vector3.new(direction.X > 0 and -1 or 1, 0, 0)
    elseif bestAxis == 2 then
        normal = Vector3.new(0, direction.Y > 0 and -1 or 1, 0)
    else
        normal = Vector3.new(0, 0, direction.Z > 0 and -1 or 1)
    end
    return {Position = origin + direction * bestT, Normal = normal}
end
local RaycastParams = {new = function() return {} end}
local workspace = {
    Raycast = function(_, origin, direction) return worldRaycast(origin, direction) end,
    CurrentCamera = nil,
}
local vectorMeta = getmetatable(Vector3.zero)
local function isVector(value)
    return getmetatable(value) == vectorMeta
end
local typeof = function(value)
    if isVector(value) then return 'Vector3' end
    return type(value)
end
local function cframeAt(position, look)
    return {Position = position, LookVector = look, RightVector = Vector3.new(0, 0, 1)}
end

local clock = 0
os.clock = function() return clock end

-- Characters -----------------------------------------------------------------
local dead = {}
local function makeBody(position, humanoidState, health)
    local root = {Position = position, AssemblyLinearVelocity = Vector3.zero}
    function root:IsA(class) return class == 'BasePart' end
    local humanoid = {
        Health = health or 100,
        MoveDirection = Vector3.zero,
        EquipTool = function() end,
    }
    function humanoid:GetState() return humanoidState end
    local character = {Name = 'Body'}
    function character:FindFirstChild(name)
        if name == 'HumanoidRootPart' then return root end
        if name == 'UpperTorso' then return root end
        if name == 'Head' then return root end
        return nil
    end
    function character:FindFirstChildOfClass(class)
        if class == 'Humanoid' then return humanoid end
        return nil
    end
    function character:GetAttribute(name)
        if name == 'Dead' then return dead[character] == true end
        return nil
    end
    character.IsA = function(_, class) return class == 'Model' end
    return character, root, humanoid
end

-- Local player: the Murderer holding the knife.
local LocalPlayer = {Name = 'Local'}
local playerCharacter, playerRoot, playerHumanoid = makeBody(Vector3.new(0, 3, 0), 'Running')
playerRoot.CFrame = cframeAt(Vector3.new(0, 3, 0), Vector3.new(1, 0, 0))
LocalPlayer.Character = playerCharacter

local knifeRemote = {IsA = function(_, class) return class == 'RemoteEvent' end}
local fired = {}
function knifeRemote:FireServer(origin, target)
    table.insert(fired, {origin = origin, target = target})
end
local handle = {CFrame = cframeAt(Vector3.new(0, 3, 0), Vector3.new(1, 0, 0))}
function handle:IsA(class) return class == 'BasePart' end
local knifeEvents = {FindFirstChild = function(_, name)
    if name == 'KnifeThrown' then return knifeRemote end
    return nil
end}
local knife = {Name = 'Knife', Parent = playerCharacter}
function knife:FindFirstChild(name)
    if name == 'Handle' then return handle end
    if name == 'Events' then return knifeEvents end
    return nil
end
function knife:IsA() return true end
LocalPlayer.FindFirstChildOfClass = function(_, class)
    if class == 'Backpack' then return {GetChildren = function() return {} end} end
    return nil
end

local lobby = {LocalPlayer}
local Players = {GetPlayers = function() return lobby end}

-- The real base.lua `isPlayerAlive` (loaded above) is the contract the knife
-- module consumes; no simplified stand-in, so a corpse has to be rejected by
-- the shipped rule.
local protectedPlayer = nil
local roundActive = true
local state = {mm2Prediction = nil, mm2Core = {}}
state.mm2Core.isRoundLifecycleActive = function() return roundActive end
local featureConnections = {}
local function disconnectFeatureConnection(name) featureConnections[name] = nil end
local function createUniversalFeature() return {SetStatus = function() end} end
local function addToggleOption() end
local function addNumberOption() end
local function addInformationOption() end

local settings = {enabled = true, autoThrow = true, wallCheck = true,
    knifeTracer = false, delay = 0.6}
local lastThrowAttempt = 0
local tracerPart, targetDotPart = nil, nil
local hookedWeaponService, origGetMouseTargetCFrame, origGetTargetPosition =
    nil, nil, nil
local function destroyTracerVisuals() end
local function setKnifeStatus() end
local prediction = nil

-- Module.init locals the section closes over.
local function getPlayerWeapon() return knife end
local function getPlayerRole(who)
    if who == LocalPlayer then return 'Murderer' end
    return 'Innocent'
end
local function isProtectedTarget(player) return player == protectedPlayer end
local function getEstimatedLatency() return 0.1 end
local function isWeaponPathClear(origin, target)
    local direction = target - origin
    if direction.Magnitude < 0.05 then return true end
    return worldRaycast(origin, direction) == nil
end
local findMurderer = function() return nil end

local function load()
''' + LANES + r'''
    return throwKnife, findTarget, resolveSpeculativeAim, knifeThrowLoop,
        getKnife, getThrowOriginCFrame
end

local throwKnife, findTarget, resolveSpeculativeAim, knifeThrowLoop, getKnife,
    getThrowOriginCFrame = load()

''' + CORPSE_HELPER + r'''
local function runThrow()
    fired = {}
    clock = clock + 1
    knifeThrowLoop()
    assert(#fired == 1, 'expected one throw, saw ' .. tostring(#fired))
    return fired[1]
end
local function lastAim()
    return fired[#fired].target.Position
end

-- 1. Doorway in front, hidden opponent behind it, walls elsewhere. The lane is
-- the doorway: past the wall plane, inside the door width, and nowhere near
-- the opponent standing behind the wall.
resetMap()
addBox(-80, -2, -80, 80, 0, 80)          -- floor
addBox(9, 0, -30, 11, 8, -2)             -- wall, left of the door
addBox(9, 0, 2, 11, 8, 30)               -- wall, right of the door
addBox(9, 7, -2, 11, 8, 2)               -- lintel above the door
addBox(-30, 0, -12, 30, 8, -10)          -- solid wall on the -Z side
local hiddenCharacter, hiddenRoot = makeBody(Vector3.new(20, 3, 12), 'Running')
local hidden = {Name = 'Hidden', Character = hiddenCharacter}
table.insert(lobby, hidden)
-- The doorway is in front, but the opponent stands behind the wall beside it.
assert(findTarget() == nil, 'an opponent behind the wall must not be a target')
local throw = runThrow()
local aim = lastAim()
assert(aim.X > 12, 'the lane must pass through the doorway, got X=' .. tostring(aim.X))
assert(math.abs(aim.Z) < 2.5, 'the lane left the doorway, got Z=' .. tostring(aim.Z))
assert((aim - hiddenRoot.Position).Magnitude > 10,
    'the lane must not be built around the hidden opponent')
pass('opening lane: doorway chosen, hidden opponent does not move the aim')

-- A live opponent standing in that doorway IS a target; the lane is only the
-- fallback. Same map, same bearings: the difference is line of sight.
hiddenRoot.Position = Vector3.new(20, 3, 0)
assert(findTarget() == hidden, 'a visible opponent through the door must be a target')
fired = {}
clock = clock + 1
knifeThrowLoop()
assert(#fired == 1, 'a visible target must still throw')
assert((lastAim() - Vector3.new(20, 3, 0)).Magnitude < 3,
    'a visible target must be aimed at, not replaced by a lane')
pass('visible target: line of sight still wins over an opening lane')

-- 2. Same map, the doorway walled shut: no straight lane at the opponent, and
-- the side opening is preferred instead of the blocked direction.
addBox(9, 0, -2, 11, 8, 2)
fired = {}
clock = clock + 1
knifeThrowLoop()
aim = lastAim()
assert(aim.Z > 20, 'with the front walled, the open +Z lane must win, got Z=' .. tostring(aim.Z))
assert((aim - Vector3.new(20, 3, 0)).Magnitude > 10,
    'the walled opponent must not attract the lane')
pass('opening lane: solid wall in front is skipped, side opening is used')

-- 3. A dead body lying in the open is never a target and never the aim point.
resetMap()
addBox(-80, -2, -80, 80, 0, 80)
lobby = {LocalPlayer}
local corpseCharacter, corpseRoot = makeBody(Vector3.new(0, 0.5, 6), 'Physics', 0)
local corpse = {Name = 'Corpse', Character = corpseCharacter}
dead[corpseCharacter] = true
lobby = {LocalPlayer, corpse}
assert(findTarget() == nil, 'a corpse must never be selected as a knife target')
local laneAim = resolveSpeculativeAim(Vector3.new(0, 3, 0))
assert(laneAim, 'an open floor must still provide an opening lane')
assert((laneAim - corpseRoot.Position).Magnitude > 3,
    'the lane must not be aimed at the body on the floor')
fired = {}
clock = clock + 1
knifeThrowLoop()
assert(#fired == 1, 'a corpse in the lobby must not stop a speculative throw')
assert((lastAim() - corpseRoot.Position).Magnitude > 3,
    'the sent aim followed the corpse')
pass('corpse: never a target, never the aim, throw still leaves')

-- 4. A body the client still reads as healthy but that is already Dead or
-- Physics is a corpse too: MM2 leaves the ragdoll around after the kill.
local stateCharacter, stateRoot, stateHumanoid =
    makeBody(Vector3.new(0, 0.5, 8), 'Freefall', 100)
local stateCorpse = {Name = 'Ragdoll', Character = stateCharacter}
lobby = {LocalPlayer, stateCorpse}
assert(findTarget() == stateCorpse, 'a healthy body is a valid target')
stateHumanoid.Health = 0
assert(findTarget() == nil, 'Health 0 must fail closed')
stateHumanoid.Health = 100
stateHumanoid.GetState = function() return Enum.HumanoidStateType.Dead end
assert(findTarget() == nil, 'a Dead humanoid must fail closed')
stateHumanoid.GetState = function() return Enum.HumanoidStateType.Physics end
assert(findTarget() == nil, 'a Physics ragdoll must fail closed')
stateHumanoid.GetState = function() return 'Running' end
dead[stateCharacter] = true
assert(findTarget() == nil, 'the Dead attribute must fail closed')
dead[stateCharacter] = nil
assert(findTarget() == stateCorpse, 'a live body must come back')
pass('corpse states: Health 0, Dead, Physics and the Dead attribute are rejected')

-- 5. Sealed room: no opening at all, and the opponent outside it is hidden by
-- the wall, so neither path may send a blade.
resetMap()
addBox(-80, -2, -80, 80, 0, 80)
addBox(-8, 0, -8, 8, 10, -6)
addBox(-8, 0, 6, 8, 10, 8)
addBox(-8, 0, -6, -6, 10, 6)
addBox(6, 0, -6, 8, 10, 6)
addBox(-6, 9, -6, 6, 10, 6)
local sealedCharacter = makeBody(Vector3.new(20, 3, 0), 'Running')
local sealed = {Name = 'Sealed', Character = sealedCharacter}
lobby = {LocalPlayer, sealed}
assert(resolveSpeculativeAim(Vector3.new(0, 3, 0)) == nil,
    'a sealed room must not produce an opening lane')
fired = {}
clock = clock + 1
knifeThrowLoop()
assert(#fired == 0, 'a sealed room must not send a throw at a hidden player')
pass('sealed room: no opening means no throw')

-- 6. Floor edge: the lane cannot land in the void beyond the map.
resetMap()
addBox(-20, -2, -20, 20, 0, 20)
lobby = {LocalPlayer}
clock = clock + 1
knifeThrowLoop()
assert(#fired == 1, 'the floor itself must provide a lane')
aim = lastAim()
assert(math.abs(aim.X) <= 20 and math.abs(aim.Z) <= 20,
    'the lane landed outside the floor: ' .. tostring(aim.X) .. ',' .. tostring(aim.Z))
assert(aim.Y > 0, 'the lane must land on the floor, not inside it')
pass('floor edge: the landing point stays on solid ground')

-- 7. The shared alive test (base.lua) rejects ragdolls as well.
local function body(health, stateName, deadAttribute)
    local character = {}
    local humanoid = {Health = health}
    function humanoid:GetState() return stateName end
    function character:GetAttribute(name)
        if name == 'Dead' then return deadAttribute end
        return nil
    end
    local function findClass(_, class)
        if class == 'Humanoid' then return humanoid end
        return nil
    end
    humanoid.Parent = character
    return {Character = character}, character, humanoid, findClass
end
for _, case in ipairs({
        {health = 100, state = 'Running', dead = nil, alive = true},
        {health = 0, state = 'Running', dead = nil, alive = false},
        {health = 100, state = Enum.HumanoidStateType.Dead, dead = nil, alive = false},
        {health = 100, state = Enum.HumanoidStateType.Physics, dead = nil, alive = false},
        {health = 100, state = 'Running', dead = true, alive = false},
}) do
    local player, character, humanoid, findClass = body(case.health, case.state, case.dead)
    character.FindFirstChildOfClass = findClass
    local alive = isPlayerAlive(player)
    assert(alive == case.alive, 'isPlayerAlive disagreed for ' ..
        tostring(case.state) .. ' health ' .. tostring(case.health))
    local helper = bodyIsAlive(humanoid)
    assert(helper == case.alive, 'bodyIsAlive disagreed for ' .. tostring(case.state))
end
pass('alive contract: base.lua and the predictor share the corpse rule')
print('PASS knife openings: doorway, wall, corpse, sealed room and floor edge')
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="knife-openings-") as directory:
        script = Path(directory) / "openings.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
