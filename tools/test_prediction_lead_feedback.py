#!/usr/bin/env python3
"""Lead feedback from confirmed shots and the knife's measured transport."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
PREDICTION = (ROOT / 'src/games/MM2/Prediction.lua').read_text()

constants = section(PREDICTION, 'local MAX_SAMPLE_AGE: number = 0.35', 'local settings = {')
horizons = section(
    PREDICTION,
    '    local function manualLead(): number',
    '    local function gunAim(',
)

script = PRELUDE + constants + r'''
local settings = {autoLead = true, extraLead = 0, interpolation = 1 / 40}
local function finiteNumber(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local echo = nil
local rtt = 0.2
local function robustRtt() return rtt end
local function echoMedian() return echo end
''' + horizons + r'''
local function near(a, b) assert(math.abs(a - b) < 1e-6, tostring(a) .. " != " .. tostring(b)) end

-- 1) No measurements yet: the horizon is the transport plus interpolation.
local horizon = gunHorizon()
near(horizon, 0.2 + 1 / 40)
near(leadCorrection(), 0)
pass("gun horizon: transport only until three confirmations are measured")

-- 2) Two samples are not a median.
noteLeadError(0.05)
noteLeadError(0.05)
near(leadCorrection(), 0)
pass("lead feedback: two samples do not move the aim")

-- 3) Three samples of +120 ms mean the target was ahead: the horizon grows,
--    bounded by the 60 ms cap.
noteLeadError(0.12)
noteLeadError(0.12)
noteLeadError(0.12)
near(leadCorrection(), 0.06)
near(gunHorizon(), 0.2 + 1 / 40 + 0.06)
pass("lead feedback: a consistent under-lead is added, capped at 60 ms")

-- 4) Over-leading subtracts, and the same cap applies in the other direction.
for _ = 1, 5 do noteLeadError(-0.09) end
near(leadCorrection(), -0.06)
near(gunHorizon(), 0.2 + 1 / 40 - 0.06)
pass("lead feedback: over-lead is subtracted, capped symmetrically")

-- 5) A single absurd measurement (teleport, target swap) is dropped, not
--    stored, so it can never dominate the median.
local before = leadCorrection()
noteLeadError(1.5)
noteLeadError(-0.4)
noteLeadError(0 / 0)
assert(leadCorrection() == before, "out-of-range samples must be ignored")
pass("lead feedback: teleports, swaps and NaN are rejected")

-- 6) The knife uses the measured FireServer -> GunFired round trip when one
--    exists, exactly like the gun, and reports it for the calibration file.
echo = 0.31
local knifePipeline, knifeRtt, knifeEcho = knifeHorizon()
near(knifePipeline, 0.31 + 1 / 40)
near(knifeRtt, 0.2)
near(knifeEcho, 0.31)
echo = nil
local fallbackPipeline, _, fallbackEcho = knifeHorizon()
near(fallbackPipeline, 0.2 + 1 / 40)
assert(fallbackEcho == nil, "no echo means the engine RTT is used")
pass("knife horizon: measured echo first, engine RTT as fallback")

-- 7) A manual offset still works when auto lead is off, and the correction is
--    not added on top of it.
settings.autoLead = false
settings.extraLead = 0.12
near(gunHorizon(), 0.2 + 1 / 40 + 0.12)
pass("manual lead: unchanged when automatic lead is off")
'''
with tempfile.TemporaryDirectory(prefix='prediction-feedback-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
