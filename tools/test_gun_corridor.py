#!/usr/bin/env python3
"""v139.2: the shot is chosen by what is BEHIND the murderer.

MM2's gun is a long hitscan ray, so the endpoint we author is not where the
ray stops. The saved v139.1 session proves it: of 10 confirmed shots 4 hit the
murderer, 3 stopped on map geometry past the aim and 2 landed on another
player's HumanoidRootPart. This suite drives the real `fireGunAtTarget` plus the
real `describeRayBeyond` against an axis-aligned ray mock and checks that

  * a clear line behind the target is left alone,
  * a body behind the torso moves the aim to a part whose line is clear,
  * a body close enough that every line crosses it refuses the shot,
  * a body far down the ray is not a reason to move,
  * turning the option off restores the old "always shoot" behaviour.

LUAU=/path/to/luau python3 tools/test_gun_corridor.py
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

code = PRELUDE + r'''
local SELECT_TARGET = {Name = 'Murderer', role = 'Murderer'}
local SELECT_INNOCENT = {Name = 'Innocent', role = 'Innocent'}
local Players = {GetPlayerFromCharacter = function(_, model)
    if model == SELECT_TARGET.Character then return SELECT_TARGET end
    if model == SELECT_INNOCENT.Character then return SELECT_INNOCENT end
    return nil
end}
local LocalPlayer = {Character = nil}
local CollectionService = {GetTagged = function() return {} end}
local RaycastParams = {new = function() return {} end}

local function part(position, size, owner)
    local p = {Position = position, Size = size, CanQuery = true,
        Transparency = 0, CanCollide = true, Parent = owner}
    function p:IsA(class) return class == 'BasePart' end
    function p:IsDescendantOf(other) return other == owner end
    function p:GetFullName() return 'Workspace.Map.Part' end
    return p
end

local function character(position)
    local model = {parts = {}, Name = 'Character'}
    local root = part(position, Vector3.new(2, 2, 1), model)
    local torso = part(Vector3.new(position.X, position.Y + 1, position.Z),
        Vector3.new(2, 2, 1), model)
    local head = part(Vector3.new(position.X, position.Y + 2, position.Z),
        Vector3.new(1, 1, 1), model)
    model.root, model.upper, model.headPart = root, torso, head
    model.parts = {root, torso, head}
    function model:FindFirstChild(name)
        if name == 'HumanoidRootPart' then return root end
        if name == 'UpperTorso' or name == 'Torso' then return torso end
        if name == 'Head' then return head end
        return nil
    end
    function model:FindFirstChildOfClass(class)
        if class == 'Humanoid' then return {Health = 100} end
        return nil
    end
    function model:IsDescendantOf() return false end
    return model
end

SELECT_TARGET.Character = character(Vector3.new(20, 0, 0))
SELECT_INNOCENT.Character = character(Vector3.new(40, 0, 0))

-- Scene the ray mock walks. Every entry is a box part with an owner model.
local scene = {}
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
local function listed(p, params)
    for _, model in ipairs(params.FilterDescendantsInstances or {}) do
        if p:IsDescendantOf(model) then return true end
    end
    return false
end
local workspace = {Gravity = 196.2}
function workspace:Raycast(origin, delta, params)
    local nearest, hit = math.huge, nil
    for _, p in ipairs(scene) do
        if p.CanQuery and not listed(p, params) then
            local t = entry(p, origin, delta)
            if t and t < nearest then nearest, hit = t, p end
        end
    end
    return hit and {Instance = hit, Position = origin + delta * nearest} or nil
end
function workspace:GetServerTimeNow() return 0 end
function workspace:GetChildren() return {} end
''' + section(
    BASE, "local function describeRayBeyond(", "local function getWeaponFromContainer("
) + r'''
-- Shoot.lua's dispatch path, with the real corridor helper handed to it.
local mm2Settings = {silentAim = false, shootWallCheck = true,
    silentSpawn = 'Through', silentSweep = 0, avoidInnocents = true}
local remote = {IsA = function() return true end, FireServer = function() end}
local character = {FindFirstChildOfClass = function() return {} end}
local gun = {Parent = character, Enabled = true, Name = 'Gun',
    GetAttribute = function() return nil end}
function gun:FindFirstChild(name) return name == 'Shoot' and remote or nil end
local function getCharacterParts() return character, {} end
local function getPlayerWeapon() return gun end
local function getGunOriginCFrame() return CFrame.new(Vector3.zero) end
local function getPlayerRole() return 'Murderer' end
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
local function isWeaponPathClear() return true end
local function validateGunShot() return true end
local function bystanderOnSegment() return false end
local function buildSilentShot()
    return CFrame.new(Vector3.zero), CFrame.new(Vector3.zero), 2.5, 0.5, 'Front'
end
-- Defined before the extracted section in the real file; the dispatch path
-- calls it after a normal shot.
local function macroUnequip() end

local aim = {endpoint = Vector3.new(20, 1, 0)}
local function gunAim()
    return aim.endpoint, {
        endpoint = aim.endpoint, capturedPosition = aim.endpoint,
        velocity = Vector3.zero, leadSeconds = 0.1, model = 'kinematic-v51',
        sampleAge = 0, samples = 4, rtt = 0.1, motionSource = 'fit',
        rootPosition = Vector3.new(20, 0, 0),
    }, nil
end
local prediction = {gunAim = gunAim}
local authored = {}
local trajectoryCalibration = {
    noteAuthoredShot = function(_, info) table.insert(authored, info) end,
}
local state = {mm2ShotFeedback = {queue = function() end, shootActive = true}}
''' + section(
    SHOOT, "    local SILENT_ORIGIN_STUDS", "    -- The Top/fallback origin lift"
) + section(
    SHOOT, "    type FireOptions", "    local shootFeatureActive:"
) + r'''
local function shoot()
    authored = {}
    local ok = fireGunAtTarget(SELECT_TARGET, {whenReady = true, quiet = true})
    return ok, authored[1] and authored[1].aimPos or nil
end
local function targetParts()
    return {SELECT_TARGET.Character.root, SELECT_TARGET.Character.upper,
        SELECT_TARGET.Character.headPart}
end
local function withScene(extra)
    scene = targetParts()
    for _, p in ipairs(extra or {}) do table.insert(scene, p) end
end

-- 1. Nothing behind: the authored aim is the preferred torso point, untouched.
withScene({})
local sent, point = shoot()
assert(sent, 'a clear line behind the murderer must shoot')
assert(point and (point - aim.endpoint).Magnitude < 1e-6,
    'with nobody behind, the aim must not be nudged')

-- 2. An innocent 20 studs behind the torso line: the torso line crosses it,
--    the head line passes above. The aim moves instead of refusing.
withScene({part(Vector3.new(40, 0, 0), Vector3.new(2, 6, 6),
    SELECT_INNOCENT.Character)})
sent, point = shoot()
assert(sent, 'a body 20 studs behind must move the aim, not refuse the shot')
assert(point and (point - aim.endpoint).Magnitude > 0.01,
    'the aim must leave the torso line when a body sits behind it')
assert(point and math.abs(point.X - 20) < 2.5 and math.abs(point.Z) < 2.5,
    'the new aim must still be on the murderer')

-- 3. A body so close and tall that every candidate line crosses it: refuse.
--    Point blank behind means a 1-stud miss kills an innocent.
withScene({part(Vector3.new(22, 0, 0), Vector3.new(2, 10, 10),
    SELECT_INNOCENT.Character)})
sent = shoot()
assert(not sent, 'an innocent right behind the murderer must skip the shot')

-- 4. The option off: shoot anyway, exactly where the predictor asked.
mm2Settings.avoidInnocents = false
sent, point = shoot()
assert(sent, 'with Avoid innocents off the shot must still fire')
assert(point and (point - aim.endpoint).Magnitude < 1e-6,
    'with the option off the aim must not move')
mm2Settings.avoidInnocents = true

-- 5. A body far down the ray is not a reason to change the aim: the murderer's
--    own body stops the ray long before it gets there.
withScene({part(Vector3.new(170, 8.5, 0), Vector3.new(2, 2, 2),
    SELECT_INNOCENT.Character)})
sent, point = shoot()
assert(sent, 'a far body must not skip the shot')
assert(point and (point - aim.endpoint).Magnitude < 1e-6,
    'a body far down the ray must not disturb the aim')

print('PASS gun corridor: clear line, moved aim, point-blank refusal, far body, option off')
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="gun-corridor-") as directory:
        script = Path(directory) / "corridor.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
