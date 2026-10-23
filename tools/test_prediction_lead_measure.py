#!/usr/bin/env python3
"""The confirmation-side measurement that feeds the lead feedback loop."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()

helper = section(
    BASE,
    '    local function measureLeadErrorSeconds(pending: PendingGun): number?',
    '    finalizeGunCapture = function(pending: PendingGun): ()',
)

script = PRELUDE + r'''
predictionMath = {finite = function(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end}
''' + helper + r'''
local function pending(overrides)
    local p = {
        activatedAt = 0,
        confirmedAt = 0.3,
        latencyMs = 300,
        -- The target walked 3 studs in the 0.3 s round trip: 10 studs/s +X.
        targetHistory = {{dt = 0, position = {0, 3, 0}, velocity = {10, 0, 0},
            aimOffset = {0, 0, 0}}},
        rootAtConfirmation = {position = {3, 3, 0}},
        requestedAim = Vector3.new(1, 3, 0),
        targetTrajectory = {},
        targetName = "target",
        tool = {},
        pingMs = 30,
        lastTrajectorySampleAt = 0,
    }
    -- `false` removes the field: pairs() cannot carry a nil.
    for key, value in pairs(overrides or {}) do
        p[key] = value == false and nil or value
    end
    return p
end

local function near(a, b)
    assert(a ~= nil and math.abs(a - b) < 1e-6, tostring(a) .. " != " .. tostring(b))
end

-- The server scores at the CONFIRMATION instant (the saved sessions
-- separate hits from misses there, a full round trip after firing):
-- at 300 ms the target is at x = 3. Aiming at x = 1 under-led by 0.2 s.
near(measureLeadErrorSeconds(pending()), 0.2)
pass("lead error: aiming short of the confirmation position is positive")

-- Aimed exactly where the body was when the shot resolved: no error.
near(measureLeadErrorSeconds(pending({requestedAim = Vector3.new(3, 3, 0)})), 0)
pass("lead error: aiming at the scored position measures zero")

-- Aimed one stud past the body: over-led.
near(measureLeadErrorSeconds(pending({requestedAim = Vector3.new(4, 3, 0)})), -0.1)
pass("lead error: an aim past the body is negative")

-- Standing still: no lead to correct, so no sample.
local still = pending({targetHistory = {{dt = 0, position = {0, 3, 0},
    velocity = {1.5, 0, 0}, aimOffset = {0, 0, 0}}}})
assert(measureLeadErrorSeconds(still) == nil)
pass("lead error: a target that is not walking produces no sample")

-- A respawn, a teleport or a target swap is not a lead error.
local far = pending({requestedAim = Vector3.new(20, 3, 0)})
assert(measureLeadErrorSeconds(far) == nil)
pass("lead error: a 20-stud difference is rejected, not learned")

-- Missing evidence fails closed instead of guessing.
assert(measureLeadErrorSeconds(pending({rootAtConfirmation = false})) == nil, "root")
assert(measureLeadErrorSeconds(pending({latencyMs = 0})) == nil, "zero latency")
assert(measureLeadErrorSeconds(pending({latencyMs = 5000})) == nil, "huge latency")
assert(measureLeadErrorSeconds(pending({requestedAim = false})) == nil, "no aim")
assert(measureLeadErrorSeconds(pending({targetHistory = {}})) == nil, "no history")
pass("lead error: missing confirmation data produces nil")
'''
with tempfile.TemporaryDirectory(prefix='prediction-lead-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
