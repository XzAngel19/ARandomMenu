#!/usr/bin/env python3
"""v139.4: the silent constructor obeys the caller, and raw means "no guard", not "no walls".

Four defects, all reachable from the menu:

  1. `state.mm2FireSilentShot(target)` took no options, so Auto Shoot and
     Auto Win (its only callers) could not pass their own WallCheck. The
     wrapper hardcoded `continuous = true`, which is exactly the mode that
     returned early from the geometry check: a silent Auto Shoot fired with no
     wall check at all.
  2. "Raw" skipped `safeToSend` entirely, so the near-target origin was the
     only line anything ever looked at. A wall between the GUN and the
     murderer was never tested.
  3. Callers that got `false` back fired their own hand-rolled CFrame, also
     unchecked -- a bypass dressed as a fallback.
  4. The construction was hardcoded to "Through"; `mm2Settings.silentSpawn`
     only ever reached the telemetry.

This suite drives the real `fireGunAtTarget` and `buildSilentShot`.

LUAU=/path/to/luau python3 tools/test_gun_silent_constructor.py
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "src/games/MM2/base.lua").read_text()
SHOOT = (ROOT / "src/games/MM2/Blatant/Shoot.lua").read_text()

MOCKS = r'''
local scene = {}
local function part(pos, size, owner)
    local p = {Position=pos, Size=size, CanQuery=true, Transparency=0,
        CanCollide=true, Parent=owner, ClassName='Part'}
    function p:IsA(c) return c == 'BasePart' end
    function p:IsDescendantOf(o) return owner ~= nil and o == owner end
    function p:GetFullName() return 'Workspace.Map.Part' end
    return p
end
local function character(pos, label)
    local m = {Name = label or 'Character', parts = {}}
    local root = part(pos, Vector3.new(2, 2, 1), m)
    m.root, m.parts = root, {root}
    function m:FindFirstChild(n)
        if n == 'HumanoidRootPart' or n == 'Torso' or n == 'UpperTorso'
            or n == 'Head' then
            return root
        end
        return nil
    end
    function m:FindFirstChildOfClass(c)
        if c == 'Humanoid' then return {Health = 100} end
        return nil
    end
    function m:IsA(c) return c == 'Model' end
    function m:IsDescendantOf() return false end
    return m
end
local function entry(p, origin, delta)
    local lo, hi = 0, 1
    for _, axis in ipairs({'X', 'Y', 'Z'}) do
        local low = p.Position[axis] - p.Size[axis] / 2
        local high = p.Position[axis] + p.Size[axis] / 2
        if math.abs(delta[axis]) < 1e-8 then
            if origin[axis] < low or origin[axis] > high then return nil end
        else
            local a, b = (low - origin[axis]) / delta[axis],
                (high - origin[axis]) / delta[axis]
            lo = math.max(lo, math.min(a, b))
            hi = math.min(hi, math.max(a, b))
            if lo > hi then return nil end
        end
    end
    return lo
end
local function filtered(p, params)
    local listed = false
    for _, model in ipairs(params.FilterDescendantsInstances or {}) do
        if p:IsDescendantOf(model) then listed = true break end
    end
    if params.FilterType == 'Include' then return not listed end
    return listed
end
local workspace = {Gravity = 196.2}
function workspace:Raycast(origin, delta, params)
    local nearest, hit = math.huge, nil
    for _, p in ipairs(scene) do
        if p.CanQuery and not filtered(p, params) then
            local t = entry(p, origin, delta)
            if t and t < nearest then nearest, hit = t, p end
        end
    end
    return hit and {Instance = hit, Position = origin + delta * nearest} or nil
end
function workspace:GetChildren() return {} end
function workspace:GetServerTimeNow() return 0 end

local LocalPlayer = {Character = nil}
local CollectionService = {GetTagged = function() return {} end}
local RaycastParams = {new = function() return {} end}
local MURDERER = {Name = 'Murderer', role = 'Murderer'}
local INNOCENT = {Name = 'Innocent', role = 'Innocent'}
local Players = {
    GetPlayerFromCharacter = function(_, model)
        if model == MURDERER.Character then return MURDERER end
        if model == INNOCENT.Character then return INNOCENT end
        return nil
    end,
    GetPlayers = function() return {MURDERER, INNOCENT} end,
}
local predictionMath = {finite = function(n)
    return type(n) == 'number' and n == n and math.abs(n) < math.huge
end}
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
local function getPlayerRole(p) return p.role end
local function getRoundRole(p) return p.role end
local function getPlayerWeapon() return {} end
local function hasMurdererCollisionGroup() return true end
local roundLifecycleActive = true
local statusMessage = nil
local ShootFeature = {SetStatus = function(_, m) statusMessage = m end}
'''

SHOOT_MOCKS = r'''
local muzzlePosition = Vector3.new(0.5, 0, 0)
local mm2Settings = {silentAim = true, shootWallCheck = true,
    silentSpawn = 'Through', silentSweep = 0, avoidInnocents = true,
    shootRaw = false}
local remote = {IsA = function() return true end, sends = 0,
    FireServer = function(self) self.sends += 1 end}
local gun = {Parent = nil, Enabled = true, Name = 'Gun',
    GetAttribute = function() return nil end}
function gun:FindFirstChild(n) if n == 'Shoot' then return remote end return nil end
local humanoid = {Health = 100, EquipTool = function() end}
local function getCharacterParts() return LocalPlayer.Character, humanoid end
local function getGunOriginCFrame() return CFrame.new(muzzlePosition) end
local function macroUnequip() end
local aimInfo = nil
local function gunAim() return aimInfo and aimInfo.endpoint or nil, aimInfo, nil end
local prediction = {gunAim = gunAim}
local state = {mm2ShotFeedback = {queue = function() end, shootActive = true}}
local blockedNotes = {}
local trajectoryCalibration = {
    noteAuthoredShot = function() end,
    noteBlockedShot = function(_, blocker) table.insert(blockedNotes, blocker) end,
}
local function getPlayerWeapon(_, name) if name == 'Gun' then return gun end return nil end
local function getSelectedShootTarget() return MURDERER end
local RunService = {Heartbeat = {Wait = function() end}}
'''

TAIL = r'''
local own = character(Vector3.zero, 'Local')
LocalPlayer.Character = own
gun.Parent = own
INNOCENT.Character = character(Vector3.new(4000, 0, 0), 'Innocent')

local function aimFor(distance, velocity)
    MURDERER.Character = character(Vector3.new(distance, 0, 0), 'Murderer')
    scene = {own.root, MURDERER.Character.root, INNOCENT.Character.root}
    local velocityVector = velocity or Vector3.zero
    local endpoint = MURDERER.Character.root.Position + velocityVector * 0.1
    aimInfo = {endpoint = endpoint, targetPosition = endpoint,
        capturedPosition = MURDERER.Character.root.Position,
        rootPosition = MURDERER.Character.root.Position,
        velocity = velocityVector, leadSeconds = 0.1, model = 'kinematic-v51',
        sampleAge = 0, samples = 8, rtt = 0.1, motionSource = 'fit',
        turnRate = 0, brakeSeconds = 0, leadCorrection = 0}
    blockedNotes = {}
    statusMessage = nil
    remote.sends = 0
end

local function expect(label, fired, status, wantFired, wantStatus)
    assert(fired == wantFired, label .. ': fired ' .. tostring(fired)
        .. ' (status ' .. tostring(status) .. ')')
    if wantStatus then
        assert(status == wantStatus, label .. ': status ' .. tostring(status))
    end
    print('PASS\t' .. label .. (status and (' [' .. status .. ']') or ''))
end

-- 1. A wall between the GUN and the murderer, continuous (the Auto Shoot mode).
do
    aimFor(12)
    local wall = part(Vector3.new(6, 0, 0), Vector3.new(0.5, 8, 8), nil)
    table.insert(scene, wall)
    local fired = state.mm2FireSilentShot(MURDERER,
        {continuous = true, quiet = false, wallCheck = true})
    expect('continuous silent, wall between gun and murderer', fired, statusMessage,
        false, 'A wall or another body blocks the shot.')
    assert(remote.sends == 0, 'nothing may leave the client past a wall')
    assert(#blockedNotes == 1 and blockedNotes[1].name ~= nil,
        'the blocked ray must be recorded for the calibration')
end

-- 2. Same shot without the wall: the data path is not broken by the new check.
do
    aimFor(12)
    local fired = state.mm2FireSilentShot(MURDERER,
        {continuous = true, quiet = false, wallCheck = true})
    expect('continuous silent, clear line', fired, statusMessage, true)
    assert(remote.sends == 1, 'exactly one packet')
end

-- 3. The caller's WallCheck=off is honoured, not silently dropped.
do
    aimFor(12)
    local wall = part(Vector3.new(6, 0, 0), Vector3.new(0.5, 8, 8), nil)
    table.insert(scene, wall)
    local fired = state.mm2FireSilentShot(MURDERER,
        {continuous = true, quiet = false, wallCheck = false})
    expect('continuous silent, WallCheck OFF still fires', fired, statusMessage, true)
    assert(remote.sends == 1, 'WallCheck off means fire')
end

-- 4. A near-target fallback must not become a bypass: the authored segment
-- from the muzzle is refused when the gun cannot see the murderer, and the
-- fallback that replaces it is also checked.
do
    aimFor(12)
    local wall = part(Vector3.new(6, 0, 0), Vector3.new(0.5, 8, 8), nil)
    table.insert(scene, wall)
    local fired = fireGunAtTarget(MURDERER,
        {silent = true, continuous = false, quiet = false, wallCheck = true})
    expect('one-shot silent, wall between gun and murderer', fired,
        statusMessage, false)
    assert(remote.sends == 0, 'the one-shot path may not bypass either')
end

-- 5. The configured construction is used, and reported as such.
do
    aimFor(12)
    mm2Settings.silentSpawn = 'Front'
    local fired = fireGunAtTarget(MURDERER,
        {silent = true, continuous = false, quiet = true, wallCheck = true})
    assert(fired, 'a Front construction must still fire')
    assert(state.lastSilentShotInfo and state.lastSilentShotInfo.variant == 'Front',
        'the shot must use the configured spawn, got '
            .. tostring(state.lastSilentShotInfo and state.lastSilentShotInfo.variant))
    print('PASS\tconfigured construction wins over the hardcoded Through')
    mm2Settings.silentSpawn = 'Through'
end

-- 6. Point blank is still ours in every mode (v139.3 regression guard).
do
    aimFor(1.5, Vector3.new(-17, 0, 0))
    local fired = state.mm2FireSilentShot(MURDERER,
        {continuous = true, quiet = false, wallCheck = true})
    expect('continuous silent, charging murderer at 1.5 studs', fired, statusMessage, true)
end

print('PASS gun silent constructor: options honoured, walls checked from the gun, no unchecked fallback')
'''

shoot_section = section(
    SHOOT, "    local function bystanderOnSegment(", "    local shootFeatureActive:"
)
shoot_section = shoot_section.replace("local ShootFeature: any = nil", "-- injected")
# The real published wrapper, so the suite cannot drift from the module.
shoot_section += "\n" + section(
    SHOOT,
    "    state.mm2FireSilentShot = function",
    "    state.mm2FireGunShot = function",
)

code = (
    PRELUDE
    + MOCKS
    + section(BASE, "local function describeRayHit(", "local function describeRayBeyond(")
    + section(BASE, "local function describeRayBeyond(", "local function getWeaponFromContainer(")
    + section(BASE, "local function isWeaponPathClear(", "local function getWeaponFromContainer(")
    + section(BASE, "local function validateGunShot(", "local function disconnectGunFiredObserver")
    + SHOOT_MOCKS
    + shoot_section
    + TAIL
)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="gun-silent-") as directory:
        script = Path(directory) / "silent.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
