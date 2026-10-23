#!/usr/bin/env python3
"""Regression: motion fits use their actual sample timestamps, not call time."""
import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
PREDICTION = (ROOT / "src/games/MM2/Prediction.lua").read_text()

types = section(PREDICTION, "type Sample = {", "type Motion = {")
constants = section(
    PREDICTION,
    "local MAX_SAMPLE_AGE: number = 0.35",
    "local settings = {",
)
functions = section(
    PREDICTION,
    "    local function fitVelocity",
    "    local function estimateMotion",
)

script = PRELUDE + types + constants + functions + r'''
-- A fit made after the newest sample must still be anchored to that sample.
-- `reference` is the time of the asking call; it is not a position sample.
local linear = {samples = {}}
for _, t in ipairs({0.0, 0.04, 0.08, 0.10}) do
    table.insert(linear.samples, {
        at = t,
        position = Vector3.new(16 * t, 0, 0),
        velocity = Vector3.zero,
    })
end
local reference = 0.123
local fit = fitVelocity(linear, reference)
assert(fit)
local anchor = linear.samples[#linear.samples].at
local sw, st = 0, 0
for _, sample in ipairs(linear.samples) do
    local weight = math.exp(-(reference - sample.at) / FIT_TAU)
    sw += weight
    st += weight * (sample.at - anchor)
end
local expectedCenter = anchor + st / sw
near(fit.center, expectedCenter, 1e-9)
near(fit.velocity.X, 16, 1e-8)
assert(math.abs(fit.center - (reference + st / sw)) > 0.01,
    "this regression must distinguish the sample anchor from call time")
local _, _, _, fitLag = measureTurn(linear, reference, fit)
near(fitLag, linear.samples[#linear.samples].at - fit.center, 1e-9)
pass("fit clock: weighted center and extrapolation lag use the newest sample")

-- Uneven replication frames make reference-anchored centers disagree by
-- different amounts. That used to shrink the measured dt and inflate a true
-- 24 studs/s^2 acceleration to 27.33. Actual sample anchors keep it near 24.
local accelerating = {samples = {}}
local acceleration = 24
for _, t in ipairs({
    0.10, 0.14, 0.17, 0.20, 0.22, 0.25, 0.27,
    0.29, 0.30, 0.33, 0.35, 0.37, 0.39, 0.41,
}) do
    table.insert(accelerating.samples, {
        at = t,
        position = Vector3.new(8 * t + 0.5 * acceleration * t * t, 0, 0),
        velocity = Vector3.zero,
    })
end
local now = 0.415
local current = fitVelocity(accelerating, now)
assert(current)
local turnRate, along, _, _, accelX, accelZ =
    measureTurn(accelerating, now, current)
near(turnRate, 0, 1e-9)
assert(math.abs(along - acceleration) < 1.0,
    string.format("uneven-frame acceleration %.3f is not near %d", along, acceleration))
near(accelX, along, 1e-9)
near(accelZ, 0, 1e-9)
pass("fit clock: uneven frames do not inflate measured acceleration")
'''

with tempfile.TemporaryDirectory(prefix="prediction-fit-clock-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
