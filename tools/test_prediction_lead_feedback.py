#!/usr/bin/env python3
"""Lead feedback from confirmed shots and the knife's measured transport.

v161 re-enables the closed loop that v120 had reduced to a recorder: the
measured lead error is filed per aim mode, bounded, slew-limited and actually
added to the horizon. These tests pin that behaviour down, including what must
NOT move (two samples, absurd values, the other mode's bucket).
"""
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

# `leadTarget` is local to the module; the harness exposes it so the reporting
# value (what the median asks for, before the slew limit) can be asserted.
horizons = horizons.replace(
    'local function leadUncertainty(mode: any): number',
    'local function leadTargetForTest(mode: any): number\n'
    '        return leadTarget(mode)\n    end\n\n'
    '    local function leadUncertainty(mode: any): number',
)
assert 'leadTargetForTest' in horizons

PREAMBLE = r'''
local settings = {autoLead = true, extraLead = 0, interpolation = 1 / 40}
local function finiteNumber(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local echoes = {}
local echo = nil
local rtt = 0.2
local function robustRtt() return rtt end
local function echoMedian() return echo end
'''

BODY = r'''
local function near(a, b) assert(math.abs(a - b) < 1e-6, tostring(a) .. " != " .. tostring(b)) end

-- 1) No measurements yet: the horizon is the transport plus interpolation.
local horizon = gunHorizon("Bullet")
near(horizon, 0.2 + 1 / 40)
near(leadCorrection("Bullet"), 0)
near(leadUncertainty("Bullet"), 0)
near(leadSamples("Bullet"), 0)
pass("gun horizon: full transport only until three confirmations are measured")

-- 2) Two samples are not a median; the count is still reported.
noteLeadError(0.05, "Bullet")
noteLeadError(0.05, "Bullet")
near(leadSamples("Bullet"), 2)
near(leadCorrection("Bullet"), 0)
near(gunHorizon("Bullet"), 0.2 + 1 / 40)
pass("lead feedback: two samples do not move the aim")

-- 3) The third sample makes the median real. It is 0.05 here (the earlier two
--    samples weigh more than the new outlier), and the correction is APPLIED
--    now, but one small step per confirmation.
noteLeadError(0.12, "Bullet")
near(leadCorrection("Bullet"), 0.02)
near(leadTargetForTest("Bullet"), 0.05)
near(gunHorizon("Bullet"), 0.2 + 1 / 40 + 0.02)
pass("lead feedback: third confirmation starts moving the horizon")

-- 4) It converges to the measured median and then stops (no runaway).
for _ = 1, 4 do noteLeadError(0.12, "Bullet") end
near(leadCorrection("Bullet"), 0.06)
near(gunHorizon("Bullet"), 0.2 + 1 / 40 + 0.06)
pass("lead feedback: bounded by MAX_LEAD_CORRECTION")

-- 5) The knob is per aim mode: a Bullet bias cannot steer CFrame.
near(leadCorrection("CFrame"), 0)
near(gunHorizon("CFrame"), 0.2 + 1 / 40)
near(leadSamples("CFrame"), 0)
pass("lead feedback: Bullet and CFrame keep separate corrections")

-- 6) CFrame learns its own, independently (Silent is the CFrame bucket).
for _ = 1, 3 do noteLeadError(-0.03, "Silent") end
near(leadCorrection("CFrame"), -0.02)
near(leadCorrection("Bullet"), 0.06)
pass("lead feedback: Silent is the CFrame bucket and stays independent")

-- 7) Over-lead subtracts, and the same cap applies in the other direction.
--    Ten samples, so the eight-deep window has fully rolled over to over-lead.
for _ = 1, 10 do noteLeadError(-0.09, "Bullet") end
near(leadCorrection("Bullet"), -0.06)
pass("lead feedback: over-lead walks the correction the other way")

-- 8) A single absurd measurement (teleport, target swap) is dropped, not
--    stored, so it can never dominate the median.
local before = leadCorrection("Bullet")
local samplesBefore = leadSamples("Bullet")
noteLeadError(1.5, "Bullet")
noteLeadError(-0.4, "Bullet")
noteLeadError(0 / 0, "Bullet")
assert(leadCorrection("Bullet") == before, "out-of-range samples must be ignored")
assert(leadSamples("Bullet") == samplesBefore, "out-of-range samples must not be stored")
pass("lead feedback: teleports, swaps and NaN are rejected")

-- 9) The knife shares the neutral bucket (the captures only score the gun) and
--    never inherits a gun mode's bias.
near(leadCorrection("knife"), 0)
near(knifeHorizon(), 0.2 + 1 / 40)
pass("knife horizon: no gun-mode bias leaks into the blade")

-- 10) The echo still blends 60/40 with the engine RTT, and the measured
--     correction rides on top of the whole pipeline. The Bullet correction is
--     -0.06 here (over-lead, from step 7), so it is part of the sum.
echoes = {1, 2, 3}; echo = 0.31
near(gunHorizon("Bullet"), 0.2 * 0.6 + 0.31 * 0.4 + 1 / 40 - 0.06)
echoes = {1, 2, 3, 4, 5}
near(gunHorizon("Bullet"), 0.2 * 0.6 + 0.31 * 0.4 + 1 / 40 - 0.06)
pass("echo blend: unchanged 60/40, the correction is added on top")

-- 11) The knife uses the same blended pipeline.
local knifePipeline, knifeRtt, knifeEcho = knifeHorizon()
near(knifePipeline, 0.2 * 0.6 + 0.31 * 0.4 + 1 / 40)
near(knifeRtt, 0.2)
near(knifeEcho, 0.31)
echoes = {}; echo = nil
local fallbackPipeline, _, fallbackEcho = knifeHorizon()
near(fallbackPipeline, 0.2 + 1 / 40)
assert(fallbackEcho == nil, "no echo means the engine RTT is used")
pass("knife horizon: measured echo first, engine RTT as fallback")

-- 12) A manual offset still works when auto lead is off, on top of whatever the
--     loop already learned.
settings.autoLead = false
settings.extraLead = 0.12
near(gunHorizon("Bullet"), 0.2 + 1 / 40 - 0.06 + 0.12)
pass("manual lead: unchanged when automatic lead is off")
settings.autoLead = true
settings.extraLead = 0

-- 13) The same measurements, without their sign, size the silent segment. It
--     is zero until the median exists, so a fresh session keeps the configured
--     sweep and a measured one grows by exactly the error it has to cover.
near(leadUncertainty("Bullet"), 0.09)
assert(leadUncertainty("Bullet") > 0 and leadUncertainty("Bullet") <= 0.15,
    "the segment never grows past the sample limit")
near(leadUncertainty("CFrame"), 0.03)
pass("lead uncertainty: measured, unsigned, and zero without samples")
'''

script = PRELUDE + constants + PREAMBLE + horizons + BODY

with tempfile.TemporaryDirectory(prefix='prediction-feedback-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
