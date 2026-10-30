#!/usr/bin/env python3
"""Exercise the actual Knife Throw loop, visual smoothing and throw separately.

Mocked objects and geometry test the lifecycle and operation counts, not FPS,
Roblox rendering, server acceptance or hits. No per-frame raycast is needed for
interpolation; line-of-sight is checked at the existing throttled solve.
"""
from __future__ import annotations
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Combat/KnifeThrow.lua').read_text()

code = PRELUDE + r'''
local clock = 0
os.clock = function() return clock end
local vectorMeta = getmetatable(Vector3.zero)
local typeof = function(value)
    if getmetatable(value) == vectorMeta then return 'Vector3' end
    return type(value)
end
Enum.Material.Neon = 'Neon'
Enum.PartType = {Ball = 'Ball'}
local Color3 = {fromRGB = function(...) return {...} end}
local created, destroyed, writes = 0, 0, 0
local parts = {}
local instanceMeta = {
    __index = function(object, key)
        if key == 'Destroy' then return function(self)
            if not self.dead then self.dead = true; destroyed += 1 end
            self.props.Parent = nil
        end end
        return object.props[key]
    end,
    __newindex = function(object, key, value)
        if key == 'CFrame' or key == 'Size' then writes += 1 end
        object.props[key] = value
    end,
}
local Instance = {new = function(kind)
    assert(kind == 'Part')
    created += 1
    local object = setmetatable({props = {}, dead = false}, instanceMeta)
    table.insert(parts, object)
    return object
end}
local workspace = {}
local localCharacter = {}
local LocalPlayer = {Character = localCharacter}
local handle = {CFrame = CFrame.new(Vector3.new(0, 3, 0))}
function handle:IsA(class) return class == 'BasePart' end
local fired = {}
local remote = {IsA = function(_, class) return class == 'RemoteEvent' end}
function remote:FireServer(origin, endpoint) table.insert(fired, {origin, endpoint}) end
local events = {FindFirstChild = function(_, name) return name == 'KnifeThrown' and remote or nil end}
local knife = {Parent = localCharacter}
handle.Parent = knife
local handleLookups = 0
function knife:FindFirstChild(name)
    if name == 'Handle' then handleLookups += 1; return handle end
    if name == 'Events' then return events end
end
function knife:GetAttribute() return nil end
function knife:IsA(class) return class == 'Tool' end
local localHumanoid = {Health = 100, EquipTool = function() end}
function localCharacter:FindFirstChild(name)
    if name == 'HumanoidRootPart' then return handle end
    return nil
end
function localCharacter:FindFirstChildOfClass(name)
    if name == 'Humanoid' then return localHumanoid end
    return nil
end
function localCharacter:GetChildren() return {} end
function LocalPlayer:FindFirstChildOfClass() return nil end
local function newTarget(name, position)
    local character = {Name = name}
    local root = {Position = position, AssemblyLinearVelocity = Vector3.zero, Parent = character}
    function root:IsA(class) return class == 'BasePart' end
    local humanoid = {Health = 100}
    function character:FindFirstChild(name)
        if name == 'HumanoidRootPart' then return root end
        return nil
    end
    function character:FindFirstChildOfClass(class)
        if class == 'Humanoid' then return humanoid end
        return nil
    end
    function character:IsA(class) return class == 'Model' end
    return {Name = name, Character = character}, root
end
local target, root = newTarget('Target', Vector3.new(20, 3, 0))
local lobby = {LocalPlayer, target}
local selections, rays, predicts = 0, 0, 0
local Players = {GetPlayers = function() selections += 1; return lobby end}
local blocked = false
local function isWeaponPathClear()
    rays += 1
    return not blocked
end
local weaponLookups = 0
local availableKnife = knife
local function getPlayerWeapon() weaponLookups += 1; return availableKnife end
local function getPlayerRole(player) return player == LocalPlayer and 'Murderer' or 'Innocent' end
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
local function getEstimatedLatency() return 0.1 end
local offset = Vector3.zero
local prediction = {knifeAim = function(player, origin, speed)
    predicts += 1
    local p = player.Character:FindFirstChild('HumanoidRootPart').Position + offset
    return p, {capturedPosition = p - offset, flightSeconds = (p - origin).Magnitude / speed}
end}
local state = {mm2Core = {}}
local featureConnections = {}
local function disconnectFeatureConnection(key) featureConnections[key] = nil end
local settings = {enabled = true, autoThrow = false, wallCheck = true, knifeTracer = true, delay = 0.6}
local lastThrowAttempt = 0
local tracerPart, targetDotPart = nil, nil
local hookedWeaponService, origGetMouseTargetCFrame, origGetTargetPosition = nil, nil, nil
local function destroyTracerVisuals()
    if tracerPart then tracerPart:Destroy(); tracerPart = nil end
    if targetDotPart then targetDotPart:Destroy(); targetDotPart = nil end
end
local function setKnifeStatus() end
local function load()
''' + section(SOURCE, '    -- Check if player is valid target', '    -- Toggle function') + r'''
    return knifeThrowLoop, updateTracerVisual, hideTracerVisuals, throwKnife, invalidateAim
end
local loop, update, hide, throw, invalidate = load()

-- Same elapsed time gives the same smoothing at 30, 60 and 120 Hz.
local final = {}
for _, fps in ipairs({30, 60, 120}) do
    hide()
    local from, a, b = Vector3.new(0, 3, 0), Vector3.new(20, 3, 0), Vector3.new(28, 3, 0)
    update(from, a, target, 1/fps)
    for _ = 1, fps/5 do update(from, b, target, 1/fps) end
    local x = targetDotPart.CFrame.Position.X
    near(x, 28 - 8*math.exp(-26*.2), 1e-6)
    final[fps] = x
end
near(final[30], final[60]); near(final[60], final[120])
assert(created == 2, 'only two reused parts')
print('PASS tracer smoothing: continuous and time-based at 30/60/120 Hz; two parts')

-- Full loop: refreshes stay at 10 Hz while the visuals move each frame.
hide(); invalidate()
clock = 10
loop(1/120)
local solves0, rays0, predicts0 = selections, rays, predicts
local start = targetDotPart.CFrame.Position.X
root.Position = root.Position + Vector3.new(1, 0, 0)
clock += 1/120
loop(1/120)
assert(selections == solves0 and rays == rays0 and predicts == predicts0,
    'visual interpolation must not select, predict or raycast')
assert(targetDotPart.CFrame.Position.X > start, 'follows observed root between solves')
local endX = root.Position.X + 8
offset = Vector3.new(8, 0, 0)
clock += 0.11
loop(1/120)
local smoothed = targetDotPart.CFrame.Position.X
assert(smoothed > start and smoothed < endX, 'new solve is blended, not snapped')
local raysAfterSolve, callsAfterSolve = rays, selections
clock += 1/120
loop(1/120)
assert(rays == raysAfterSolve and selections == callsAfterSolve)
assert(targetDotPart.CFrame.Position.X > smoothed and targetDotPart.CFrame.Position.X < endX)

-- The unsmoothed real throw re-solves; it must not fire at the display point.
assert(throw(target, knife))
near(fired[#fired][2].Position.X, endX)
assert(math.abs(fired[#fired][2].Position.X - targetDotPart.CFrame.Position.X) > .1,
    'preview must not replace the live shot')

-- The next visibility refresh hides immediately rather than fading/sticking;
-- repeated blocked/visible transitions reuse the existing parts.
local beam, dot = tracerPart, targetDotPart
blocked = true
clock += .11
loop(1/120)
assert(beam.Transparency == 1 and dot.Transparency == 1, 'blocked preview hidden')
for _=1,5 do clock += .11; loop(1/120) end
assert(created == 2 and tracerPart == beam and targetDotPart == dot)
blocked = false
clock += .11
loop(1/120)
assert(beam.Transparency < 1 and dot.Transparency < 1 and created == 2)
assert(beam.Transparency > .25 and dot.Transparency > .15, 'new target fades in')
near(dot.CFrame.Position.X, endX)

-- New players and large teleports snap/reset instead of drawing a sweep.
local second, secondRoot = newTarget('Second', Vector3.new(27, 3, 0))
lobby = {LocalPlayer, second}
offset = Vector3.zero
clock += .11
loop(1/120)
near(dot.CFrame.Position.X, secondRoot.Position.X)
assert(dot.Transparency > .15 and dot.Transparency < 1, 'switch fades at the new target')
secondRoot.Position += Vector3.new(30, 0, 0)
clock += 1/120
loop(1/120)
assert(dot.Transparency == 1 and beam.Transparency == 1, 'teleport hides stale preview')
clock += 1/120
loop(1/120)
near(dot.CFrame.Position.X, secondRoot.Position.X)

-- Static visuals stop writing; not creating/destroying parts per tick.
for _=1,60 do clock += 1/120; loop(1/120) end
local staticWrites = writes
for _=1,60 do clock += 1/120; loop(1/120) end
assert(writes == staticWrites, 'stationary line should not rewrite every frame')
assert(created == 2 and destroyed == 0)

selections, rays, predicts, weaponLookups, handleLookups = 0, 0, 0, 0, 0
invalidate()
for i=1,120 do clock += 1/120; loop(1/120) end
assert(selections <= 11 and selections >= 8, 'selection rate must be capped, got '..selections)
assert(predicts <= selections * 2, 'one cheap candidate plus one full solve')
assert(rays <= selections * 7, 'no extra per-frame line-of-sight raycast')
assert(weaponLookups <= selections + 2, 'equipped knife must not be searched per frame')
assert(handleLookups <= 1, 'equipped handle must not be searched per frame')
print(string.format('PASS tracer loop: %d selections, %d LOS calls, %d predictions, %d weapon searches in 120 mocked frames', selections, rays, predicts, weaponLookups))

-- A removed knife hides immediately; searching a missing tool is capped and
-- obtaining it again is noticed by the next preview refresh.
availableKnife = nil
knife.Parent = nil
clock += 1/120; loop(1/120)
assert(dot.Transparency == 1 and beam.Transparency == 1, 'removed knife hides the line')
weaponLookups = 0
for i=1,120 do clock += 1/120; loop(1/120) end
assert(weaponLookups <= 22, 'missing knife search is throttled, got '..weaponLookups)
availableKnife = knife
knife.Parent = localCharacter
clock += .11; loop(1/120)
assert(dot.Transparency < 1 and beam.Transparency < 1, 'new knife is picked up')

settings.knifeTracer = false
loop(1/120)
assert(tracerPart == nil and targetDotPart == nil and destroyed == 2, 'OFF destroys both')
assert(#fired == 1, 'visuals and hiding never fire')
print('PASS tracer lifecycle: blocked, reuse, target switch, teleport, stationary, OFF; shot uses live aim')
'''

with tempfile.TemporaryDirectory(prefix='knife-tracer-') as tmp:
    path = Path(tmp) / 'tracer.luau'
    path.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
