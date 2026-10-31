#!/usr/bin/env python3
"""Actual knife predictor with synthetic client-side support geometry.

The falling pose below uses de-identified Y/velocity samples from calibration
v162 shot :15. Floor height, horizontal location, timing and shooter location
are synthetic; the original capture did NOT record the knife aim or map floor.
These are physics/contract regression tests, not observed knife hits or proof
of live Roblox rendering, server behaviour, or latency.
"""
from __future__ import annotations
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()
PREDICTION = (ROOT / 'src/games/MM2/Prediction.lua').read_text()

code = PRELUDE + '\n' + section(BASE, 'local predictionMath = {}', 'local lastLatencyReadAt') + r'''
Enum.HumanoidRigType = {R6='R6', R15='R15'}
local vectorMeta = getmetatable(Vector3.zero)
local typeof = function(value)
    if getmetatable(value) == vectorMeta then return 'Vector3' end
    return type(value)
end
local LocalPlayer = {Character = {Name = 'Local'}}
local currentState = 'Freefall'
local humanoid = {Health = 100, HipHeight = 2, RigType = Enum.HumanoidRigType.R15,
    MoveDirection = Vector3.zero, GetState = function() return currentState end,
    GetAttribute = function() return nil end}
local root = {Position = Vector3.zero, AssemblyLinearVelocity = Vector3.zero, Size = Vector3.new(2, 2, 1)}
local torso = {Position = Vector3.zero, IsA = function(_, class) return class == 'BasePart' end}
local leg = {Size = Vector3.new(1, 2, 1), IsA = function(_, class) return class == 'BasePart' end}
local character = {Name = 'TargetCharacter'}
function character:GetAttribute() return nil end
function character:FindFirstChild(name)
    if name == 'HumanoidRootPart' then return root end
    if name == 'UpperTorso' then return torso end
    if name == 'Left Leg' then return leg end
    return nil
end
function character:FindFirstChildOfClass(name) if name == 'Humanoid' then return humanoid end end
root.Parent, humanoid.Parent = character, character
local target = {Character = character}
local Players = {GetPlayers = function() return {LocalPlayer, target} end}
local paramsCreated = 0
local RaycastParams = {new = function() paramsCreated += 1; return {} end}
local mode = 'support'
local floorY = 269.8123779296875 -- synthetic floor, not recorded in the capture
local edgeX = 0
local casts = 0
local probePositions = {}
local supportPart = {Parent = {}, CanCollide = true, CFrame = {version = 1}}
function supportPart:IsA(class) return class == 'BasePart' end
function supportPart:FindFirstAncestorOfClass(class)
    if mode == 'actor' and class == 'Model' then
        return {FindFirstChildOfClass = function(_, name) return name == 'Humanoid' and humanoid or nil end}
    end
    return nil
end
local workspace = {Gravity = 196.2}
function workspace:Raycast(origin, direction, params)
    casts += 1
    table.insert(probePositions, origin)
    assert(direction.Y == -80 and direction.X == 0 and direction.Z == 0)
    assert(params.RespectCanCollide == true and params.IgnoreWater == true)
    assert(params.FilterType == Enum.RaycastFilterType.Exclude)
    assert(table.find(params.FilterDescendantsInstances, LocalPlayer.Character))
    assert(table.find(params.FilterDescendantsInstances, character))
    if mode == 'error' then error('unavailable geometry') end
    if mode == 'clear' or (mode == 'ledge' and origin.X > edgeX)
        or (mode == 'only-first' and #probePositions > 1) then return nil end
    if floorY > origin.Y or floorY < origin.Y - 80 then return nil end
    supportPart.CanCollide = mode ~= 'noncollide'
    return {Instance = supportPart, Position = Vector3.new(origin.X, floorY, origin.Z),
        Normal = mode == 'steep' and Vector3.new(1, .1, 0) or Vector3.new(0, 1, 0)}
end
local state = {mm2Core = {predictionMath = predictionMath, getEstimatedLatency = function() return .12 end}}
local featureConnections = {}
local function disconnectFeatureConnection(key)
    if featureConnections[key] then featureConnections[key]:Disconnect(); featureConnections[key]=nil end
end
local sampleTick
local TaskManager = {Connect = function(_, callback)
    sampleTick = callback
    return {Disconnect = function() sampleTick = nil end}
end}
local function load()
''' + PREDICTION + r'''
end
local Module = load()
Module.init({})
local prediction = state.mm2Prediction
local function begin()
    prediction.reset()
    casts = 0
    table.clear(probePositions)
    supportPart.Parent = {}
    supportPart.CFrame = {version = 1}
    supportPart.CanCollide = true
    humanoid.HipHeight, humanoid.RigType = 2, Enum.HumanoidRigType.R15
    now = 50
end
local function sample(x, y, vx, vy, stateName)
    currentState = stateName
    root.Position = Vector3.new(x, y, 0)
    root.AssemblyLinearVelocity = Vector3.new(vx, vy, 0)
    torso.Position = root.Position
    sampleTick(1/60)
end
local function capturedFall(vx)
    -- Only these vertical samples are copied from :15; X is constructed.
    local samples = {
        {-.134, 275.217, -.97, 'Landed'}, {-.118, 275.140, -5.24, 'Landed'},
        {-.099, 275.011, -10.00, 'Running'}, {-.087, 274.858, -13.38, 'Running'},
        {-.070, 274.638, -15.15, 'Running'}, {-.053, 274.336, -17.22, 'Freefall'},
        {-.037, 274.048, -20.99, 'Freefall'}, {-.018, 273.609, -26.08, 'Freefall'},
        {-.001, 273.2060852050781, -28.147619247436523, 'Freefall'},
    }
    for _, p in ipairs(samples) do
        now = 50 + p[1]
        sample(20 + vx*p[1], p[2], vx, p[3], p[4])
    end
    now = 50
end

begin(); mode = 'support'; capturedFall(0)
local origin = Vector3.new(0, 273.2060852050781, 0)
local gunBefore, gunInfo = prediction.gunAim(target, origin)
assert(gunBefore and casts == 0, 'Gun must not use the knife floor probe')
local aim, info, reason = prediction.knifeAim(target, origin, 96)
assert(aim, tostring(reason))
assert(info.model == 'kinematic-v164-knife')
near(aim.Y, floorY + 3, 1e-6)
assert(casts >= 1 and casts <= 2)
near((aim-origin).Magnitude, 96*info.flightSeconds, 1e-5)
near(info.rootPosition.Y, aim.Y, 1e-6)
local firstCasts = casts
for _=1,20 do
    local repeated = prediction.knifeAim(target, origin, 96)
    near(repeated.Y, aim.Y)
end
assert(casts == firstCasts, 'same pose must reuse the support probe')
assert(paramsCreated == 1, 'RaycastParams should be reused')
supportPart.CFrame = {version=2}
prediction.knifeAim(target, origin, 96)
assert(casts > firstCasts, 'moving platform invalidates cached support')
local movedCasts = casts
mode = 'noncollide'
supportPart.CanCollide = false
local changed = prediction.knifeAim(target, origin, 96)
assert(casts > movedCasts and (changed == nil or changed.Y < aim.Y - 6),
    'a floor becoming non-collidable invalidates its cached support')
mode = 'support'
local gunAfter = prediction.gunAim(target, origin)
near(gunAfter.Y, gunBefore.Y)
print('PASS knife landing: capture-derived fall on hypothetical support; cache, moving floor, unchanged gun')

-- The recorded fall also had horizontal motion. A support probe should start
-- near the plausible horizontal intercept, not at a diverged vertical solve.
begin(); mode = 'support'; capturedFall(7.79)
local moving, movingInfo, movingWhy = prediction.knifeAim(target, origin, 96)
assert(moving, tostring(movingWhy))
near(moving.Y, floorY + 3, 1e-6)
assert(casts <= 2)
near(moving.X - 20, 7.79 * (movingInfo.leadSeconds + movingInfo.flightSeconds), .1)
print(string.format('PASS moving landing: %d support ray(s) near the horizontal intercept', casts))

-- With no floor the body is allowed to fall: no fake plane at the shooter's Y
-- and no old ledge height. This uses exactly the same measured Y/vy history.
begin(); mode = 'clear'; capturedFall(0)
local freeAim, _, freeWhy = prediction.knifeAim(target, origin, 96)
assert(freeAim == nil and freeWhy == 'unreachable',
    'a diverging fall must not become an aim hundreds of studs below the body')
assert(casts <= 2)
-- A shorter, physically interceptable free fall still produces a downward
-- lead when there is no observed floor. No floor is manufactured.
begin(); mode = 'clear'; now += 1
sample(10, 100, 0, -10, 'Freefall')
local fallOrigin = Vector3.new(0,100,0)
local realFall, fallInfo, fallWhy = prediction.knifeAim(target, fallOrigin, 96)
assert(realFall, tostring(fallWhy))
assert(realFall.Y < 98, 'reachable free fall must still be led down')
local span = fallInfo.leadSeconds + fallInfo.flightSeconds
near(realFall.Y, 100 - 10*span - .5*workspace.Gravity*span*span, .25)
near((realFall-fallOrigin).Magnitude, 96*fallInfo.flightSeconds, 1e-5)
print('PASS no floor: unreachable divergence rejected; reachable fall still leads downward')

-- Compare the real knife solver against an independent dense scan of the
-- assumed ballistic model, not against a server hit. The earliest physical
-- intercept must be consistent or the solver must refuse an impossible one.
local function referenceFall(distance, velocity, speed, horizon)
    for i=0,2000 do
        local t = i/2000
        local span = horizon + t
        local dy = velocity*span - .5*workspace.Gravity*span*span
        if math.sqrt(distance*distance + dy*dy) <= speed*t then return t end
    end
    return nil
end
local checked = 0
for _, speed in ipairs({72, 96, 140}) do
    for _, distance in ipairs({5, 10, 15, 20}) do
        for _, vy in ipairs({-10, -20, -28}) do
            begin(); mode = 'clear'; now += 1
            sample(distance, 100, 0, vy, 'Freefall')
            local reference = referenceFall(distance, vy, speed, .145)
            local point, result = prediction.knifeAim(target, fallOrigin, speed)
            if reference then
                assert(point and result, string.format('reachable fall missed: d=%s v=%s s=%s',distance,vy,speed))
                near(result.flightSeconds, reference, .003)
                local total = result.leadSeconds + result.flightSeconds
                near(point.Y, 100 + vy*total - .5*workspace.Gravity*total*total, .25)
            else
                assert(point == nil, string.format('impossible fall accepted: d=%s v=%s s=%s',distance,vy,speed))
            end
            assert(casts <= 2)
            checked += 1
        end
    end
end
print('PASS '..checked..' airborne intercepts against independent synthetic ballistic scan')

-- The ray is local evidence, not permission to invent a walkable surface.
-- An error, steep geometry, a character or a non-collidable object all fall
-- back to the existing model instead of raising the point.
for _, invalid in ipairs({'error', 'steep', 'noncollide', 'actor'}) do
    begin(); mode = invalid; capturedFall(0)
    local rejected = prediction.knifeAim(target, origin, 96)
    assert(rejected == nil or rejected.Y < aim.Y - 6, invalid .. ' was mistaken for support')
end
print('PASS support rejects unavailable, steep, non-collidable and character surfaces')

-- Two cached columns can overlap after a small movement. Prefer the newest
-- observation, not an older empty column that now overlaps a real floor.
begin(); floorY = 96; mode = 'clear'; now += 1
sample(20, 100, 0, -28, 'Freefall')
prediction.knifeAim(target, Vector3.new(0,100,0), 96)
mode = 'support'; now += .016
sample(20.4, 100, 0, -28, 'Freefall')
local recentFloor = prediction.knifeAim(target, Vector3.new(0,100,0), 96)
assert(recentFloor and math.abs(recentFloor.Y-99) < .01)
local afterSecondProbe = casts
now += .016; sample(20.25, 100, 0, -28, 'Freefall')
local overlap = prediction.knifeAim(target, Vector3.new(0,100,0), 96)
assert(overlap and math.abs(overlap.Y-99) < .01, 'older empty column overrode newer support')
assert(casts == afterSecondProbe, 'overlap should reuse the newest valid probe')
print('PASS support cache: overlapping columns choose the newest observation')

-- R6's hip height does not include the leg: include its size just once.
begin(); mode = 'support'; floorY = 269.8123779296875; capturedFall(0)
humanoid.RigType, humanoid.HipHeight = Enum.HumanoidRigType.R6, 0
local r6 = prediction.knifeAim(target, origin, 96)
near(r6.Y, floorY + 3, 1e-6)
print('PASS R6 support height: root half-height plus leg and HipHeight')

-- A lower, standing target is a legitimate downward shot. No probe should
-- run when there is no vertical prediction to correct.
begin(); mode = 'support'; now += 1
sample(20, 15, 0, 0, 'Running')
local low, lowInfo = prediction.knifeAim(target, Vector3.new(0, 50, 0), 96)
assert(low and low.Y == 15 and low.Y < 50 and casts == 0)
near((low-Vector3.new(0,50,0)).Magnitude, 96*lowInfo.flightSeconds, 1e-5)
print('PASS lower standing target remains aimable downward without a ground ray')

-- The projected XZ is beyond a synthetic ledge. Do not reuse the floor that
-- happens to exist near the target's previous/current position.
begin(); mode = 'ledge'; floorY = 269.8123779296875; edgeX = 21; capturedFall(16)
local offLedge = prediction.knifeAim(target, origin, 96)
assert(casts >= 1 and probePositions[1].X > edgeX)
assert(offLedge == nil or offLedge.Y < floorY,
    'past a ledge, an unobserved support cannot stop the fall')
print('PASS ledge: no fabricated floor at a different XZ')

-- The initial full-velocity intercept has no root when the target is falling
-- faster than the blade. A horizontal seed is accepted only if this projected
-- landing is actually supported; otherwise the solver remains unreachable.
begin(); mode = 'support'; floorY = 96; now += 1
sample(20, 100, 0, -120, 'Freefall')
local fast, fastInfo, fastWhy = prediction.knifeAim(target, Vector3.new(0,100,0), 96)
assert(fast, tostring(fastWhy)); near(fast.Y, 99, 1e-6)
near((fast-Vector3.new(0,100,0)).Magnitude, 96*fastInfo.flightSeconds, 1e-5)
begin(); mode = 'clear'; now += 1
sample(20, 100, 0, -120, 'Freefall')
local noFast, _, why = prediction.knifeAim(target, Vector3.new(0,100,0), 96)
assert(noFast == nil and why == 'unreachable')
print('PASS fast fall: horizontal seed requires observed landing support')

-- Re-solving the flight after finding a floor can move its predicted XZ across
-- an edge. Only the first ray gets support; the second does not. The old floor
-- must not be borrowed across that edge. Maximum two rays for this solve.
begin(); mode = 'only-first'; floorY = 60; now += 1
for i=1,12 do
    now += 1/60
    sample(20 + 20*i/60, 100, 20, -28, 'Freefall')
end
local edgeAim = prediction.knifeAim(target, Vector3.new(0,100,0), 96)
assert(casts == 2, 'corrected landing must be re-probed once across an edge: '..casts)
assert(edgeAim == nil or edgeAim.Y < 63, 'first floor must not be reused at the other position')
print('PASS support recheck: changed landing XZ, bounded to two raycasts')

-- Respawn can replace the model between sampler ticks. The next knife solve
-- must immediately discard the old body's track and sample the new one.
local replacement = {Name = 'Respawned'}
function replacement:GetAttribute() return nil end
function replacement:FindFirstChild(name)
    if name == 'HumanoidRootPart' then return root end
    if name == 'UpperTorso' then return torso end
    if name == 'Left Leg' then return leg end
end
function replacement:FindFirstChildOfClass(name) if name == 'Humanoid' then return humanoid end end
character = replacement
root.Parent, humanoid.Parent, target.Character = replacement, replacement, replacement
root.Position, torso.Position = Vector3.new(15, 12, 0), Vector3.new(15, 12, 0)
root.AssemblyLinearVelocity, currentState = Vector3.zero, 'Running'
now += .01
local respawnAim = prediction.knifeAim(target, Vector3.new(0,12,0), 96)
assert(respawnAim and respawnAim.Y == 12 and math.abs(respawnAim.X - 15) < .01,
    'old body track survived respawn')
print('PASS respawn: fresh character replaces the prior knife track before the next sample')

Module.destroy()
assert(sampleTick == nil and state.mm2Prediction == nil)
print('PASS knife support model: synthetic client geometry only; no hit-rate inference')
'''
with tempfile.TemporaryDirectory(prefix='knife-ground-') as tmp:
    path = Path(tmp) / 'ground.luau'
    path.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
