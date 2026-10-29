#!/usr/bin/env python3
"""v139.3: point-blank shots belong to us, and "behind" must respect walls.

Two real refusals came out of the v139.2 session and both were ours, not the
game's:

  * "Invalid shot geometry" -- with the murderer charging at the measured
    17 studs/s, the silent "Through" construction pierced ALONG HIS MOTION.
    Running at us, that direction points at us: the authored segment finished
    on our own muzzle (start 0.5, end 0.5) and the shot was refused. Inside
    POINT_BLANK_STUDS the body covers the whole sight, so the shot is authored
    from the real muzzle straight at him.

  * "Another player blocks the silent shot" -- the bystander overshoot probe
    shared a constant with the new corridor check and had been raised from 12
    to 200 studs, and it asks a PLAYER-ONLY raycast: walls are transparent to
    it. An innocent 108 studs behind the murderer, in another room, refused
    every silent shot.

This suite runs the real `fireGunAtTarget`, `buildSilentShot`, `validateGunShot`
and `describeRayBeyond` against an axis-aligned ray mock.

LUAU=/path/to/luau python3 tools/test_gun_pointblank.py
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
    function p:IsA(c) return c=='BasePart' end
    function p:IsDescendantOf(o) return owner ~= nil and o==owner end
    function p:GetFullName() return 'Workspace.Map.Part' end
    return p
end
-- One part per character: the point-blank logic must not depend on the rig
-- having a dozen limbs, and a single box is the worst case for it.
local function character(pos, label)
    local m = {Name=label or 'Character', parts={}}
    local root = part(pos, Vector3.new(2, 2, 1), m)
    m.root = root
    m.parts = {root}
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
local mm2Settings = {silentAim = false, shootWallCheck = true,
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

-- Returns fired, status of the attempt.
local function trial(distance, opts)
    opts = opts or {}
    MURDERER.Character = character(Vector3.new(distance, 0, 0), 'Murderer')
    scene = {own.root, MURDERER.Character.root, INNOCENT.Character.root}
    for _, p in ipairs(opts.extra or {}) do table.insert(scene, p) end
    mm2Settings.silentAim = opts.silent == true
    mm2Settings.experimentalAim = opts.experimental == true
    blockedNotes = {}
    -- The predictor hands us its aim point; a charging murderer moves at the
    -- measured 17 studs/s and the lead is the measured 0.1 s.
    local velocity = opts.velocity or Vector3.zero
    MURDERER.Character.root.AssemblyLinearVelocity = velocity
    local endpoint = MURDERER.Character.root.Position + velocity * 0.1
    aimInfo = {endpoint = endpoint, targetPosition = endpoint,
        capturedPosition = MURDERER.Character.root.Position,
        rootPosition = MURDERER.Character.root.Position,
        velocity = velocity, leadSeconds = 0.1, model = 'kinematic-v51',
        sampleAge = 0, samples = 8, rtt = 0.1, motionSource = 'fit',
        turnRate = 0, brakeSeconds = 0, leadCorrection = 0}
    statusMessage = nil
    remote.sends = 0
    local fired = fireGunAtTarget(MURDERER, {quiet = false, wallCheck = true})
    return fired, statusMessage
end

local function expect(label, fired, status, wantFired, wantStatus)
    assert(fired == wantFired, label .. ': fired ' .. tostring(fired)
        .. ', status ' .. tostring(status))
    if wantStatus then
        assert(status == wantStatus, label .. ': status ' .. tostring(status))
    end
    print('PASS\t' .. label .. (status and (' (' .. status .. ')') or ''))
end

-- Experimental chooses exactly one authored path; a send is not a hit.
do
    local fired, status = trial(12, {experimental = true})
    expect('experimental near target uses Bullet', fired, status, true,
        'Experimental · Bullet · request sent')
    fired, status = trial(40, {experimental = true, velocity = Vector3.new(0, 0, 12)})
    expect('experimental moving distant target uses CFrame', fired, status, true,
        'Experimental · CFrame · request sent')
    local wall = part(Vector3.new(6, 0, 0), Vector3.new(0.5, 8, 8), nil)
    fired, status = trial(12, {experimental = true, extra = {wall}})
    expect('experimental preserves WallCheck', fired, status, false,
        'A wall or another body blocks the shot.')
end

-- 1. Point blank, nothing behind: the murderer's own body is never a wall.
for _, silent in ipairs({false, true}) do
    local mode = silent and 'silent' or 'normal'
    for _, distance in ipairs({0.8, 1.2, 3, 6}) do
        local fired, status = trial(distance, {silent = silent})
        expect(mode .. ' point blank ' .. tostring(distance), fired, status, true)
    end
end

-- 2. The charging murderer: his lead points at us, the shot used to invert.
for _, silent in ipairs({false, true}) do
    local mode = silent and 'silent' or 'normal'
    for _, distance in ipairs({1.5, 3, 5}) do
        local fired, status = trial(distance,
            {silent = silent, velocity = Vector3.new(-17, 0, 0)})
        expect(mode .. ' charging at 17 from ' .. tostring(distance),
            fired, status, true)
    end
end

-- 3. A wall right behind the murderer: the ray dies in the wall, not in a body.
for _, silent in ipairs({false, true}) do
    local mode = silent and 'silent' or 'normal'
    local wall = part(Vector3.new(2.6, 0, 0), Vector3.new(0.4, 8, 8), nil)
    local fired, status = trial(1.2, {silent = silent, extra = {wall}})
    expect(mode .. ' murderer against a wall', fired, status, true)
end

-- 4. An innocent far behind, with and without a wall: not a reason to hold.
for _, silent in ipairs({false, true}) do
    local mode = silent and 'silent' or 'normal'
    INNOCENT.Character = character(Vector3.new(120, 0, 0), 'Innocent')
    local fired, status = trial(12, {silent = silent,
        extra = {INNOCENT.Character.root}})
    expect(mode .. ' innocent 108 behind', fired, status, true)
    local wall = part(Vector3.new(60, 0, 0), Vector3.new(0.4, 8, 8), nil)
    fired, status = trial(12, {silent = silent,
        extra = {wall, INNOCENT.Character.root}})
    expect(mode .. ' innocent 108 behind a wall', fired, status, true)
    INNOCENT.Character = character(Vector3.new(4000, 0, 0), 'Innocent')
end

-- 5. An innocent right behind with nothing between: still refused, and the
-- refusal is recorded with its own reason so a session can count the cost.
INNOCENT.Character = character(Vector3.new(25, 0, 0), 'Innocent')
for _, silent in ipairs({false, true}) do
    local mode = silent and 'silent' or 'normal'
    local fired, status = trial(12, {silent = silent,
        extra = {INNOCENT.Character.root}})
    expect(mode .. ' innocent 13 behind is refused', fired, status, false,
        'An innocent is right behind the murderer.')
    assert(#blockedNotes == 1, 'the refusal must be recorded once')
    assert(blockedNotes[1].reason == 'corridor',
        'the refusal must carry reason=corridor, got '
            .. tostring(blockedNotes[1].reason))
end
INNOCENT.Character = character(Vector3.new(4000, 0, 0), 'Innocent')

-- 5b. A corpse behind is not an innocent: an unowned rig with no health must
-- not hold the shot (MM2 leaves bodies where they died).
do
    local corpse = {Name = 'Corpse', parts = {}}
    local body = part(Vector3.new(25, 0, 0), Vector3.new(2, 2, 1), corpse)
    corpse.root = body
    corpse.parts = {body}
    function corpse:FindFirstChild(n)
        if n == 'HumanoidRootPart' then return body end
        return nil
    end
    function corpse:FindFirstChildOfClass(c)
        if c == 'Humanoid' then return {Health = 0} end
        return nil
    end
    function corpse:IsA(c) return c == 'Model' end
    function corpse:IsDescendantOf() return false end
    for _, silent in ipairs({false, true}) do
        local mode = silent and 'silent' or 'normal'
        local fired, status = trial(12, {silent = silent, extra = {body}})
        expect(mode .. ' corpse behind is not an innocent', fired, status, true)
    end
end

-- 6. A real wall between us and the murderer still refuses: the check that
-- matters was not weakened to make the cases above pass.
for _, silent in ipairs({false, true}) do
    local mode = silent and 'silent' or 'normal'
    local wall = part(Vector3.new(6, 0, 0), Vector3.new(0.5, 8, 8), nil)
    local fired, status = trial(12, {silent = silent, extra = {wall}})
    expect(mode .. ' wall between us and him', fired, status, false,
        'A wall or another body blocks the shot.')
end
'''

# One range: the constants, the silent construction, the corridor helper and
# the dispatch. Two overlapping ranges would declare `ShootFeature` twice and
# the module's own nil declaration would shadow the harness one.
shoot_section = section(
    SHOOT, "    local function bystanderOnSegment(", "    local shootFeatureActive:"
)
shoot_section = shoot_section.replace("local ShootFeature: any = nil", "-- injected")

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
    + "\nprint('PASS gun point blank: the murderer is not a wall, and a wall still is')\n"
)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="gun-pointblank-") as directory:
        script = Path(directory) / "pointblank.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
