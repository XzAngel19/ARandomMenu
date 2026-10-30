#!/usr/bin/env python3
"""v139.4: the knife predictor gets the real blade speed, and the body-part
fallback stops counting the torso height twice.

Two defects in `resolveKnifeAim`:

  1. `ThrowSpeed` was read from the tool -- and then only the LOCAL fallback
     used it. `prediction.knifeAim(target, originPos)` was called without it,
     so every knife that is not the default 96 studs/s got a flight time for
     the wrong speed. The saved session has six projectiles at exactly 96, so
     this alone does not explain its results; it is still wrong.
  2. When the first trajectory is blocked, the scan tries UpperTorso / Head /
     arms with `part.Position + (predicted - root.Position)`. The predictor's
     aim is `predictedRoot + aimOffset`, so that displacement ALREADY contains
     the torso/head offset: adding it to a part that is itself above the root
     counted the height twice and aimed 2-4 studs high.

LUAU=/path/to/luau python3 tools/test_mm2_knife_aim.py
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
KNIFE = (ROOT / "src/games/MM2/Combat/KnifeThrow.lua").read_text()

# Only the solver, so the harness owns `checkLineOfSight` and the predictor.
SOLVER = section(
    KNIFE,
    "    local function resolveKnifeAim(",
    "    -- Find best target for knife throw",
)

code = PRELUDE + r'''
local clock = 0
os.clock = function() return clock end
-- Standalone Luau's own typeof() reports these mock vectors as "table"; the
-- module (like Roblox) asks for "Vector3".
do
    local vectorMeta = getmetatable(Vector3.zero)
    typeof = function(value)
        if getmetatable(value) == vectorMeta then return 'Vector3' end
        return type(value)
    end
end

-- A rig with a root, a torso 1.5 studs above it and a head 3 studs above it:
-- the geometry the fallback scan names, with the torso offset made explicit.
local function body(rootPosition)
    local model = {Name = 'Target', parts = {}}
    local function make(offset, size)
        local p = {Position = rootPosition + offset, Size = size}
        function p:IsA(c) return c == 'BasePart' end
        return p
    end
    model.root = make(Vector3.zero, Vector3.new(2, 2, 1))
    model.torso = make(Vector3.new(0, 1.5, 0), Vector3.new(2, 2, 1))
    model.head = make(Vector3.new(0, 3, 0), Vector3.new(1, 1, 1))
    model.root.AssemblyLinearVelocity = Vector3.zero
    function model:FindFirstChild(name)
        if name == 'HumanoidRootPart' then return model.root end
        if name == 'UpperTorso' or name == 'Torso' then return model.torso end
        if name == 'Head' then return model.head end
        return nil
    end
    function model:FindFirstChildOfClass(c)
        if c == 'Humanoid' then return {Health = 100} end
        return nil
    end
    function model:IsA(c) return c == 'Model' end
    return model
end

local LocalPlayer = {Character = nil}
local Player = {Name = 'Target', Character = body(Vector3.new(20, 0, 0))}
local speedWithNoAttribute = 96
local seenSpeed = nil
local predictorCalls = 0
local bodyAllowed = true
local aimOffset = Vector3.new(0, 1.5, 0)   -- what the sampler reports (torso)
local lead = Vector3.new(1.7, 0, 0)         -- 0.1 s at 17 studs/s
local prediction = {
    knifeAim = function(target, origin, speed)
        predictorCalls += 1
        seenSpeed = speed
        local root = target.Character.root.Position
        return root + aimOffset + lead, {
            endpoint = root + aimOffset + lead,
            capturedPosition = root + aimOffset,
            rootPosition = root,
            velocity = Vector3.new(17, 0, 0),
            leadSeconds = 0.1,
            flightSeconds = 0.1,
        }, nil
    end,
}

-- Only the head is visible: the primary point and every other part are
-- blocked, so the scan must reach the last candidate. `losVisible` is what
-- the last scenario switches to model a clear line.
local losVisible = function(point, head)
    return math.abs(point.Y - head.Position.Y) < 0.01
end
local function checkLineOfSight(origin, point, character)
    local head = character:FindFirstChild('Head')
    return losVisible(point, head)
end
local function getEstimatedLatency() return 0.1 end
-- v159: the shipped solver asks whether the body is visible before it aims.
-- This harness owns line of sight (checkLineOfSight below), so the body check
-- is satisfied and the solver's own picks are what the assertions read.
local function bodyVisible() return bodyAllowed end
local function getPlayerWeapon() return nil end
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
local function getPlayerRole() return 'Innocent' end

''' + SOLVER + r'''

-- 1. The speed reaches the predictor, whatever the tool says.
local knife = {GetAttribute = function(_, name)
    if name == 'ThrowSpeed' then return 140 end
    return nil
end}
local aim = resolveKnifeAim(Player, Vector3.new(0, 0, 0), knife)
assert(aim, 'the fallback scan must find the visible head')
assert(seenSpeed == 140, 'the predictor must receive ThrowSpeed, got '
    .. tostring(seenSpeed))
print('PASS\tknife speed: ThrowSpeed 140 reaches the predictor')

-- 2. A tool with no attribute keeps the default 96.
seenSpeed = nil
resolveKnifeAim(Player, Vector3.new(0, 0, 0), nil)
assert(seenSpeed == speedWithNoAttribute, 'no attribute must mean 96, got '
    .. tostring(seenSpeed))
print('PASS\tknife speed: no ThrowSpeed still solves at 96')

-- 3. The head candidate carries the TIME lead only. The predictor aimed at
-- root + 1.5 (torso) + 1.7 (lead) while the head already sits at root + 3:
-- head + 1.7 is right, head + 1.5 + 1.7 is 1.5 studs too high.
local head = Player.Character.head
aim = resolveKnifeAim(Player, Vector3.new(0, 0, 0), knife)
assert(math.abs(aim.Y - head.Position.Y) < 0.01,
    'the fallback must not add the torso offset to a part that already has it: '
        .. tostring(aim.Y) .. ' vs head ' .. tostring(head.Position.Y))
assert(math.abs(aim.X - (head.Position.X + 1.7)) < 0.01,
    'the time lead must still be applied, X was ' .. tostring(aim.X))
print('PASS\tknife fallback: torso offset counted once, lead kept')

-- 4. The primary trajectory, when visible, is returned untouched.
losVisible = function() return true end
local primary = resolveKnifeAim(Player, Vector3.new(0, 0, 0), knife)
local root = Player.Character.root.Position
assert(math.abs(primary.X - (root.X + aimOffset.X + lead.X)) < 0.01
    and math.abs(primary.Y - (root.Y + aimOffset.Y + lead.Y)) < 0.01,
    'a visible primary point must be returned as-is')
print('PASS\tknife aim: visible primary trajectory untouched')

-- Occluded candidates do not pay for prediction or the knife floor probe.
bodyAllowed = false
local beforeHidden = predictorCalls
assert(resolveKnifeAim(Player, Vector3.zero, knife, true) == nil)
assert(predictorCalls == beforeHidden, 'hidden body must be rejected before prediction')
bodyAllowed = true
print('PASS\tknife selection: hidden body rejected before prediction')

-- 5. If the shared predictor cannot solve, transport used to multiply the
-- entire vertical velocity BEFORE clamping the flight term. At -120 Y and
-- 500 ms this pointed 60+ studs under the target. The cap must cover both.
local savedPrediction = prediction
prediction = nil
getEstimatedLatency = function() return 0.5 end
local victim = Player.Character.root
victim.AssemblyLinearVelocity = Vector3.new(0, -120, 0)
local fallback = resolveKnifeAim(Player, Vector3.new(0, 20, 0), nil)
near(fallback.Y, victim.Position.Y - 2)
-- A genuinely lower body still yields a downward aim; never clamp to the
-- thrower's Y or prevent shots from a balcony to the ground.
victim.Position = Vector3.new(20, -30, 0)
victim.AssemblyLinearVelocity = Vector3.zero
fallback = resolveKnifeAim(Player, Vector3.new(0, 20, 0), nil)
near(fallback.Y, -30)
assert(fallback.Y < 20, 'a lower target must remain aimable downward')
-- Malformed replicated velocity cannot manufacture a NaN endpoint.
victim.AssemblyLinearVelocity = Vector3.new(0, 0/0, 0)
fallback = resolveKnifeAim(Player, Vector3.new(0, 20, 0), nil)
near(fallback.Y, -30)
prediction = savedPrediction
print('PASS\tknife fallback: whole vertical lead bounded, genuinely lower targets preserved')

print('PASS knife aim: real speed, single torso offset, bounded fallback')
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="knife-aim-") as directory:
        script = Path(directory) / "aim.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
