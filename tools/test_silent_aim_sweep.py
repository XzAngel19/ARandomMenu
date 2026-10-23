#!/usr/bin/env python3
"""Silent aim: the bypass segment is sized by the measured lead uncertainty.

The extra length used to be whatever the slider said. The confirmed shots now
tell how far the aim lands from the body, so the segment grows by that error
instead of by a guess, and it never grows past the maximum.
"""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()

geometry = section(
    SOURCE,
    '    local SILENT_ORIGIN_STUDS: number = 2.5',
    '    type FireOptions = {',
)

script = PRELUDE + r'''
local mm2Settings = {silentSweep = 0.5}
local prediction = {}
local function bystanderOnSegment() return false end
''' + geometry + r'''
-- The predicted point is 20 studs in front of the muzzle, and the target runs
-- along +X at 16 studs/s, so the extra segment is a straight extension of X.
local info = {
    endpoint = Vector3.new(10, 0, 0),
    capturedPosition = Vector3.new(0, 0, 0),
    velocity = Vector3.new(16, 0, 0),
}
local muzzle = CFrame.new(Vector3.new(-10, 0, 0))

local function segment(distance)
    local startCFrame, endCFrame = buildSilentShot({}, info, muzzle, "Through")
    assert(startCFrame and endCFrame, "the shot must be built")
    -- "Through" starts one stud before the captured point and ends one stud
    -- past the predicted point, plus the sweep on each side.
    near(startCFrame.Position.X, 0 - 1 - distance)
    near(endCFrame.Position.X, 10 + 1 + distance)
end

-- 1) No confirmation measured yet: the slider is used untouched.
segment(0.5)
near(getSilentSweepDistance(16), 0.5)
pass("silent sweep: the configured value until a shot is confirmed")

-- 2) Three confirmations 60 ms off at 16 studs/s are 0.96 studs of body the
--    segment has to cover; it grows by exactly that much.
prediction = {getLeadUncertainty = function() return 0.06 end}
near(getSilentSweepDistance(16), 0.5 + 0.96)
segment(0.5 + 0.96)
pass("silent sweep: grows by the measured error times the target speed")

-- 3) A standing target has no along-track error to cover.
near(getSilentSweepDistance(0), 0.5)
pass("silent sweep: a still target keeps the configured length")

-- 4) The segment never exceeds the hard maximum, whatever the measurement.
prediction = {getLeadUncertainty = function() return 0.15 end}
near(getSilentSweepDistance(40), 1.5)
pass("silent sweep: capped at the same maximum as the slider")

-- 5) A prediction module without the measurement, or one that throws, is not
--    allowed to break the shot: the configured value is used.
prediction = {}
near(getSilentSweepDistance(16), 0.5)
prediction = {getLeadUncertainty = function() error("boom") end}
near(getSilentSweepDistance(16), 0.5)
pass("silent sweep: a missing or failing measurement falls back cleanly")
'''

with tempfile.TemporaryDirectory(prefix='silent-sweep-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
