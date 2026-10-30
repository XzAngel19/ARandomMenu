#!/usr/bin/env python3
"""Vertical prediction: the floor clamp has a ceiling (v161).

The clamp exists so a landing target is not aimed at below the ground. It used
to apply without limit; the archived sessions show it lifting an aim by 20.9
studs on a target that was falling off something, not landing on it. These
tests pin both halves: a small dip below the floor a body left is still
clamped, a real fall is led.
"""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
PREDICTION = (ROOT / 'src/games/MM2/Prediction.lua').read_text()

constants = section(PREDICTION, 'local MAX_SAMPLE_AGE: number = 0.35', 'local settings = {')
# Straight slices: `section` anchors on a prefix and one of these two
# boundaries is not unique enough for it.
def cut(start_marker, end_marker):
    start = PREDICTION.index(start_marker)
    end = PREDICTION.index(end_marker, start)
    return PREDICTION[start:end]

vertical = (
    cut('    local function leadHorizontal(motion: Motion, horizon: number)',
        '    local function predictedRoot(')
    + cut('    local function predictedRoot(',
          '    local function currentRtt(')
)

PREAMBLE = r'''
local workspace = {Gravity = 196.2}
local function sample(y, grounded)
    return {position = Vector3.new(0, y, 0), grounded = grounded,
        velocity = Vector3.zero, at = 0}
end
local function track(...)
    return {samples = {...}}
end
local function motion(verticalSpeed)
    return {
        horizontal = Vector3.zero,
        reportedHorizontal = Vector3.zero,
        hasInputHistory = false,
        moveDirection = Vector3.zero,
        airborne = true,
        verticalLead = true,
        vertical = verticalSpeed,
        turnRate = 0,
    }
end
'''

BODY = r'''
local function near(a, b, tolerance)
    assert(math.abs(a - b) <= (tolerance or 1e-6),
        tostring(a) .. " != " .. tostring(b))
end
local horizon = 0.2
local drop = 0.5 * workspace.Gravity * horizon * horizon

-- 1) A body whose prediction lands less than one jump height below the floor
--    it left is landing: the aim stays at the floor instead of under it.
local landing = track(sample(10, true), sample(11, false))
local y = predictedRoot(landing, motion(-4), horizon).Y
near(y, 10)
pass("floor clamp: a small dip is still snapped to the floor")

-- 2) A body falling from a ledge keeps its lead. 40 studs below the floor it
--    left is a fall, not a landing, and the v161 cap stops the clamp from
--    cancelling it (the archived session lifted one aim by 20.9 studs here).
local g = workspace.Gravity
local fallSpeed = -40
local falling = track(sample(50, true), sample(20, false))
local ballistic = 20 + fallSpeed * horizon - 0.5 * g * horizon * horizon
local fell = predictedRoot(falling, motion(fallSpeed), horizon).Y
assert(fell < 20 - 5, "a fall must be led downward, got " .. tostring(fell))
near(fell, ballistic)

-- 3) The clamp never raises an aim that is already above the floor: a rising
--    body keeps its own prediction untouched.
local level = track(sample(10, true), sample(10.4, false))
near(predictedRoot(level, motion(40), horizon).Y,
    10.4 + 40 * horizon - 0.5 * g * horizon * horizon)

-- 4) Without a vertical lead nothing is invented.
local flat = track(sample(10, true), sample(10, false))
local stillMotion = motion(0)
stillMotion.verticalLead = false
near(predictedRoot(flat, stillMotion, horizon).Y, 10)
pass("floor clamp: bounded by one jump height, inert otherwise")
'''

script = PRELUDE + constants + PREAMBLE + vertical + BODY

with tempfile.TemporaryDirectory(prefix='prediction-floor-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
