#!/usr/bin/env python3
"""v159: the knife aims at a visible target or not at all.

The previous build used a "speculative lane": with nobody visible it sampled
openings around the map, and before that it centred points on the nearest
hidden opponent. Both spent the knife on a guess, and the second one aimed
through geometry. v159 removes the fallback completely and makes WallCheck the
only guarantee, so this suite runs the real `findTarget`, `resolveKnifeAim`,
`throwKnife` and redirects against:

  * a visible target (aim near the predicted body, one packet),
  * an opaque wall and an invisible SOLID barrier (the real `isWeaponPathClear`
    with `strict`), both refused,
  * invisible non-colliding decoration, still allowed,
  * a thin post on the corridor but not on the centre ray, refused,
  * a predicted point that peeks past cover while the body is hidden, refused,
  * corpse states (Health 0, Dead, Physics, Dead attribute), never a target,
  * target choice by blade FLIGHT TIME, not raw distance,
  * WallCheck OFF (the documented meaning of the toggle), allowed through.

Analytic axis-aligned box map with mocked hits: client-side geometry and
contract only. It does not prove server damage, hit rate or anti-cheat
behaviour.

LUAU=/path/to/luau python3 tools/test_mm2_knife_targeting.py
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "src/games/MM2/base.lua").read_text()
KNIFE = (ROOT / "src/games/MM2/Combat/KnifeThrow.lua").read_text()

ALIVE = section(BASE, "local function isPlayerAlive", "local function playerFromRoundKey")
WALLCHECK = section(BASE, "local function isWeaponPathClear", "local function describeRayHit")
LANES = section(KNIFE, "    -- Check if player is valid target", "    -- Toggle function")

code = PRELUDE + ALIVE + r'''
-- Analytic map ---------------------------------------------------------------
-- Static boxes plus the characters themselves. A ray is a segment and the
-- nearest entry wins.
local statics = {}
local bodies = {}
local function addBox(x0, y0, z0, x1, y1, z1, options)
    local spec = options or {}
    table.insert(statics, {
        min = {x0, y0, z0},
        max = {x1, y1, z1},
        transparency = spec.transparency or 0,
        canCollide = spec.canCollide ~= false,
        name = spec.name or 'Map.Brick',
        owner = spec.owner,
    })
end
local function resetMap()
    table.clear(statics)
    addBox(-120, -2, -120, 120, 0, 120, {name = 'Map.Floor'})
end
local function bodyBox(owner, root, half, height)
    table.insert(bodies, {owner = owner, root = root, half = half or 1.6,
        height = height or 3})
end

local function boxBounds(box)
    if box.root then
        local p = box.root.Position
        return {p.X - box.half, p.Y - box.height / 2, p.Z - box.half},
            {p.X + box.half, p.Y + box.height / 2, p.Z + box.half}
    end
    return box.min, box.max
end
local function rayBox(origin, direction, box)
    local low, high = 0, math.huge
    local axis = nil
    for i = 1, 3 do
        local o = ({origin.X, origin.Y, origin.Z})[i]
        local d = ({direction.X, direction.Y, direction.Z})[i]
        local bmin, bmax = boxBounds(box)
        if math.abs(d) < 1e-9 then
            if o < bmin[i] or o > bmax[i] then return nil end
        else
            local t1 = (bmin[i] - o) / d
            local t2 = (bmax[i] - o) / d
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > low then low, axis = t1, i end
            if t2 < high then high = t2 end
            if low > high then return nil end
        end
    end
    if low > 1 or high < 0 then return nil end
    return low, axis
end
-- One stable instance per box: the shared helper excludes the part it just
-- skipped and asks the next ray to look past it, so identity has to survive.
local function partFor(box)
    if box.part then return box.part end
    local part = {
        Transparency = box.transparency,
        CanCollide = box.canCollide,
        ClassName = 'Part',
        Name = box.name,
    }
    function part:IsA(class) return class == 'BasePart' end
    function part:GetFullName() return 'Workspace.' .. box.name end
    function part:IsDescendantOf(model) return box.owner ~= nil and box.owner == model end
    box.part = part
    return part
end
local function excluded(box, filter)
    for _, entry in ipairs(filter or {}) do
        if box.owner ~= nil and entry == box.owner then return true end
        if entry == partFor(box) then return true end
    end
    return false
end
local function worldRaycast(origin, direction, params)
    local filter = params and params.FilterDescendantsInstances
    local best, bestT, bestAxis = nil, math.huge, nil
    local function consider(box)
        if excluded(box, filter) then return end
        local t, axis = rayBox(origin, direction, box)
        if t and t < bestT then best, bestT, bestAxis = box, t, axis end
    end
    for _, box in ipairs(statics) do consider(box) end
    for _, box in ipairs(bodies) do consider(box) end
    if not best then return nil end
    local normal
    if bestAxis == 1 then
        normal = Vector3.new(direction.X > 0 and -1 or 1, 0, 0)
    elseif bestAxis == 2 then
        normal = Vector3.new(0, direction.Y > 0 and -1 or 1, 0)
    else
        normal = Vector3.new(0, 0, direction.Z > 0 and -1 or 1)
    end
    return {Instance = partFor(best), Position = origin + direction * bestT, Normal = normal}
end
local RaycastParams = {new = function() return {} end}
local CollectionService = {GetTagged = function() return {} end}
local workspace = {
    Raycast = function(_, origin, direction, params) return worldRaycast(origin, direction, params) end,
    CurrentCamera = nil,
    Gravity = 196.2,
}

local enumVector = getmetatable(Vector3.zero)
local function typeof(value)
    if getmetatable(value) == enumVector then return 'Vector3' end
    return type(value)
end
local function cframeAt(position)
    return {Position = position}
end

local clock = 0
os.clock = function() return clock end

-- Characters -----------------------------------------------------------------
local deadFlag = {}
local function makeBody(position, stateName, health)
    local root = {Position = position, AssemblyLinearVelocity = Vector3.zero}
    function root:IsA(class) return class == 'BasePart' end
    local humanoid = {Health = health or 100, MoveDirection = Vector3.zero,
        EquipTool = function() end}
    function humanoid:GetState() return stateName end
    humanoid.Parent = nil
    local character = {Name = 'Body'}
    function character:FindFirstChild(name)
        if name == 'HumanoidRootPart' or name == 'UpperTorso' then return root end
        return nil
    end
    function character:FindFirstChildOfClass(class)
        if class == 'Humanoid' then return humanoid end
        return nil
    end
    function character:GetAttribute(name)
        if name == 'Dead' then return deadFlag[character] == true end
        return nil
    end
    function character:IsA(class) return class == 'Model' end
    humanoid.Parent = character
    return character, root, humanoid
end

local LocalPlayer = {Name = 'Local'}
local playerCharacter, playerRoot, playerHumanoid =
    makeBody(Vector3.new(0, 3, 0), 'Running')
playerRoot.CFrame = cframeAt(Vector3.new(0, 3, 0))
LocalPlayer.Character = playerCharacter

local knifeRemote = {IsA = function(_, class) return class == 'RemoteEvent' end}
local fired = {}
function knifeRemote:FireServer(origin, target)
    table.insert(fired, {origin = origin, target = target})
end
local handle = {CFrame = cframeAt(Vector3.new(0, 3, 0))}
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

local protectedPlayer = nil
local state = {mm2Prediction = nil, mm2Core = {}}
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

local function getPlayerWeapon() return knife end
local function getPlayerRole(who)
    if who == LocalPlayer then return 'Murderer' end
    return 'Innocent'
end
local isPlayerAlive = isPlayerAlive
local function isProtectedTarget(player) return player == protectedPlayer end
local function getEstimatedLatency() return 0.1 end

local function load()
''' + WALLCHECK + r'''
''' + LANES + r'''
    return throwKnife, findTarget, resolveKnifeAim, knifeThrowLoop,
        installWeaponServiceRedirect, uninstallWeaponServiceRedirect
end

local throwKnife, findTarget, resolveKnifeAim, knifeThrowLoop,
    installRedirect, uninstallRedirect = load()

local function addTarget(name, position, stateName, health)
    local character, root, humanoid = makeBody(position, stateName or 'Running', health)
    bodyBox(character, root)
    local player = {Name = name, Character = character}
    table.insert(lobby, player)
    return player, character, root, humanoid
end
local function clearTargets()
    lobby = {LocalPlayer}
    table.clear(bodies)
end
local function throwOnce()
    fired = {}
    clock = clock + 1
    knifeThrowLoop()
    return #fired
end
local function assertAimNear(position, radius, label)
    assert(#fired == 1, label .. ': expected one throw, saw ' .. tostring(#fired))
    local aim = fired[1].target.Position
    assert((aim - position).Magnitude <= radius,
        label .. ': aim ' .. tostring(aim.X) .. ',' .. tostring(aim.Z)
            .. ' is not near the target')
end

-- 1. Visible target: one packet, aimed at the predicted body.
resetMap()
clearTargets()
local visible, visibleCharacter = addTarget('Visible', Vector3.new(30, 3, 0))
assert(findTarget() == visible, 'a visible target must be selected')
assert(throwOnce() == 1, 'a visible target must be thrown at')
assertAimNear(Vector3.new(30, 3, 0), 3, 'visible target')
pass('visible target: selected, one packet, aim on the body')

-- 2. Opaque wall between the hand and the target: nothing is thrown and the
-- redirect keeps the game's own aim.
addBox(12, 0, -6, 14, 9, 6, {name = 'Map.Wall'})
assert(findTarget() == nil, 'a target behind a wall must not be selected')
assert(throwOnce() == 0, 'a wall must stop the knife')
local originalMouse = cframeAt(Vector3.new(1, 2, 3))
local originalTarget = cframeAt(Vector3.new(4, 5, 6))
local forwarded = 0
local weaponService = {}
function weaponService:GetMouseTargetCFrame() return originalMouse end
function weaponService:GetTargetPosition()
    forwarded += 1
    return originalTarget
end
local module = {}
local clientServices = {FindFirstChild = function(_, name)
    if name == 'WeaponService' then return module end
    return nil
end}
local replicated = {FindFirstChild = function(_, name)
    if name == 'ClientServices' then return clientServices end
    return nil
end}
game = {GetService = function(_, name)
    if name == 'ReplicatedStorage' then return replicated end
    return nil
end}
getfenv().require = function()
    return weaponService
end
settings.enabled, settings.autoThrow = true, false
installRedirect()
assert(weaponService:GetMouseTargetCFrame() == originalMouse,
    'a wall must leave the native mouse aim alone')
assert(weaponService:GetTargetPosition() == originalTarget,
    'a wall must leave the native touch aim alone')
uninstallRedirect()
settings.enabled, settings.autoThrow = true, true
pass('opaque wall: no throw, native aim preserved')

-- 3. Invisible but SOLID barrier: the shared helper's strict pass stops it,
-- which the gun's first pass would have skipped.
table.remove(statics)
addBox(12, 0, -6, 14, 9, 6, {name = 'Map.InvisibleWall', transparency = 1})
assert(findTarget() == nil, 'an invisible solid barrier must stop the knife')
assert(throwOnce() == 0, 'an invisible solid barrier must not be thrown through')
pass('invisible solid barrier: strict WallCheck refuses it')

-- 4. Invisible decoration that cannot collide: still passable.
table.remove(statics)
addBox(12, 0, -6, 14, 9, 6,
    {name = 'Map.Decor', transparency = 1, canCollide = false})
assert(findTarget() == visible, 'non-colliding decoration must not block the knife')
assert(throwOnce() == 1, 'non-colliding decoration must not stop the throw')
pass('invisible decoration: non-colliding stays passable')

-- 5. A thin post on the corridor, not on the centre ray: the five-ray corridor
-- refuses it where a single ray would have said clear.
table.remove(statics)
addBox(20, 1.8, 0.28, 22, 3.4, 0.62, {name = 'Map.Post'})
-- Selection only needs the body to be visible, so the post is found at throw
-- time, with the live origin, by the corridor: one ray says clear, five say no.
assert(findTarget() == visible, 'the body is still visible past the post')
assert(resolveKnifeAim(visible, Vector3.new(0, 3, 0), knife) == nil,
    'the corridor must refuse the post')
assert(throwOnce() == 0, 'a post on the corridor must not be thrown past')
pass('corridor: a post beside the centre ray still blocks')

-- 6. The documented meaning of the toggle: with WallCheck OFF the throw is
-- allowed through geometry, because that is what turning it off asks for.
settings.wallCheck = false
table.remove(statics)
addBox(12, 0, -6, 14, 9, 6, {name = 'Map.Wall'})
assert(throwOnce() == 1, 'WallCheck OFF must allow the throw')
assertAimNear(Vector3.new(30, 3, 0), 3, 'WallCheck off')
settings.wallCheck = true
assert(throwOnce() == 0, 'WallCheck back on must refuse again')
pass('WallCheck toggle: off allows, on refuses, nothing else changes')

-- 7. A predicted point that peeks past cover while the body is hidden: the
-- body has to be visible NOW, so the throw is refused.
resetMap()
clearTargets()
local corner, cornerCharacter, cornerRoot = addTarget('Corner', Vector3.new(30, 3, 10))
cornerRoot.AssemblyLinearVelocity = Vector3.new(0, 0, -16)
addBox(28, 1.5, 9.4, 29.5, 4.5, 11.5, {name = 'Map.Pillar'})
assert(resolveKnifeAim(corner, Vector3.new(0, 3, 0), knife) == nil,
    'a hidden body must not be aimed at through a predicting shortcut')
assert(throwOnce() == 0, 'the corner case must not spend a knife')
cornerRoot.AssemblyLinearVelocity = Vector3.zero
table.remove(statics)
assert(findTarget() == corner, 'with the pillar gone the target comes back')
pass('corner: predicted point does not outrank a hidden body')

-- 8. Corpses: never a target, never thrown at.
local corpse, corpseCharacter, corpseRoot, corpseHumanoid =
    addTarget('Corpse', Vector3.new(25, 3, -6), 'Running')
corpseHumanoid.Health = 0
assert(findTarget() == corner, 'a zero-health body must not be selected')
corpseHumanoid.Health = 100
corpseHumanoid.GetState = function() return Enum.HumanoidStateType.Dead end
assert(findTarget() == corner, 'a Dead humanoid must not be selected')
corpseHumanoid.GetState = function() return Enum.HumanoidStateType.Physics end
assert(findTarget() == corner, 'a Physics ragdoll must not be selected')
corpseHumanoid.GetState = function() return 'Running' end
deadFlag[corpseCharacter] = true
assert(findTarget() == corner, 'the Dead attribute must not be selected')
assert(throwOnce() == 1, 'a live target must still be thrown at next to a corpse')
deadFlag[corpseCharacter] = nil
pass('corpses: health, Dead, Physics and the Dead attribute are never targets')

-- 9. Target choice by blade flight time: the farther body that runs INTO the
-- blade is hit sooner than the nearer one standing still, and sooner is less
-- prediction error.
resetMap()
clearTargets()
local still, _, stillRoot = addTarget('Still', Vector3.new(50, 3, 0))
-- A different bearing, so the two bodies do not block each other's line.
local running, _, runningRoot = addTarget('Running', Vector3.new(55, 3, 10))
runningRoot.AssemblyLinearVelocity = Vector3.new(-16, 0, 0)
local chosen = findTarget()
assert(chosen == running, 'the soonest intercept must win, not the nearest body')
local _, stillFlight = resolveKnifeAim(still, Vector3.new(0, 3, 0), knife)
local _, runningFlight = resolveKnifeAim(running, Vector3.new(0, 3, 0), knife)
assert(stillFlight and runningFlight and runningFlight < stillFlight,
    'flight times must show the farther body is the sooner hit')
assert(throwOnce() == 1, 'the chosen target must be thrown at')
assertAimNear(runningRoot.Position + Vector3.new(-16 * runningFlight, 0, 0), 4,
    'flight-time selection')
pass('target choice: blade flight time, not raw distance')

uninstallRedirect()
print('PASS knife targeting: visible, wall, invisible barrier, post, corner, corpse, flight time, toggle')
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="knife-targeting-") as directory:
        script = Path(directory) / "targeting.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
