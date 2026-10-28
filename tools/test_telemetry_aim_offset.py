#!/usr/bin/env python3
"""v139.4: the scored error has to describe the point we aimed at.

`endpointErrorStuds` and `leadErrorSeconds` both compare the aim against the
target's position at the scoring instant. Two things stopped that number from
meaning what it says:

  1. `Prediction.getHistory` never returned `aimOffset`, while base.lua read it
     and added it. So the comparison was ROOT vs AIM: every sample carried the
     torso offset as a fake error, and the median was an approximation with a
     vertical bias, not the server's miss distance.
  2. `captureTargetHistory` capped the window at 36 points by breaking while
     walking oldest -> newest, so at any sample rate above 60 Hz the NEWEST
     samples were the ones dropped -- the ones the scoring interpolates from.

That number is not cosmetic: the lead error it produces is fed back through
`noteLeadError` into `leadUncertainty()`, which widens the adaptive Silent
sweep. A biased error moves a real shot.

LUAU=/path/to/luau python3 tools/test_telemetry_aim_offset.py
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "src/games/MM2/base.lua").read_text()
PREDICTION = (ROOT / "src/games/MM2/Prediction.lua").read_text()

# The measurement half of base.lua: capture + both scorers.
SCORERS = section(
    BASE,
    "    -- Pre-shot movement window, straight from the predictor's ring buffer.",
    "    finalizeGunCapture = function",
)

code = PRELUDE + r'''
local state = {}
-- Standalone Luau's typeof() calls these mock vectors "table".
do
    local vectorMeta = getmetatable(Vector3.zero)
    typeof = function(value)
        if getmetatable(value) == vectorMeta then return 'Vector3' end
        return type(value)
    end
end
local predictionMath = {finite = function(n)
    return type(n) == 'number' and n == n and math.abs(n) < math.huge
end}
local function vectorArray(v) return {v.X, v.Y, v.Z} end

''' + SCORERS + r'''

-- getHistory now carries the offset, and the window keeps its newest point.
do
    local points = {}
    for index = 1, 100 do
        -- 100 samples over 0.6 s: 166 Hz, well over the 36-point cap.
        table.insert(points, {
            at = (index - 100) / 6,
            position = Vector3.new(index, 0, 0),
            velocity = Vector3.new(17, 0, 0),
            state = 'Running',
            grounded = true,
            moveDirection = Vector3.new(1, 0, 0),
            aimOffset = Vector3.new(0, 1.5, 0),
        })
    end
    state.mm2Prediction = {getHistory = function(player, seconds)
        return points, 0
    end}
    local history = captureTargetHistory('target', 0)
    assert(#history <= 36, 'the window stays bounded, got ' .. tostring(#history))
    assert(history[#history].dt == 0,
        'the newest sample must survive the cap, newest dt is '
            .. tostring(history[#history].dt))
    assert(history[#history].position[1] == 100,
        'the newest position must be the last one, got '
            .. tostring(history[#history].position[1]))
    assert(history[1].dt < -0.5, 'the window must still span 0.6 s')
    assert(history[1].aimOffset and history[1].aimOffset[2] == 1.5,
        'every point must carry the torso offset')
    assert(history[#history].aimOffset and history[#history].aimOffset[2] == 1.5,
        'including the newest one')
    print('PASS\thistory: newest kept, span preserved, torso offset on every point')
end

-- With the offset recorded, the scored error is the aim error and nothing else.
do
    local now = 10
    local pending = {
        activatedAt = now,
        requestedAim = Vector3.new(26.5, 1.5, 0),
        latencyMs = 100,
        confirmedAt = now + 0.1,
        rootAtConfirmation = {position = {26.5, 0, 0}},
        targetHistory = {
            {dt = -0.1, position = {25, 0, 0}, velocity = {17, 0, 0},
                aimOffset = {0, 1.5, 0}},
            {dt = 0, position = {26.5, 0, 0}, velocity = {17, 0, 0},
                aimOffset = {0, 1.5, 0}},
        },
    }
    local errorStuds = measureEndpointErrorStuds(pending)
    assert(errorStuds and math.abs(errorStuds) < 1e-6,
        'a perfect torso aim must score 0, got ' .. tostring(errorStuds))
    local leadError = measureLeadErrorSeconds(pending)
    assert(leadError and math.abs(leadError) < 1e-6,
        'a perfect lead must score 0 s, got ' .. tostring(leadError))
    print('PASS\tscoring: torso aim scores zero error')

    -- Without the offset in the history the same shot scores 1.5 studs of
    -- phantom error: the bug, reproduced.
    pending.targetHistory[1].aimOffset = nil
    pending.targetHistory[2].aimOffset = nil
    local phantom = measureEndpointErrorStuds(pending)
    assert(phantom and math.abs(phantom - 1.5) < 1e-6,
        'the offset-less history must show the 1.5-stud bias, got '
            .. tostring(phantom))
    print('PASS\tscoring: missing offset would have invented 1.5 studs of error')
end

-- A real miss still scores as a miss.
do
    local now = 20
    local pending = {
        activatedAt = now,
        requestedAim = Vector3.new(26.5, 1.5, 0),
        latencyMs = 100,
        confirmedAt = now + 0.1,
        rootAtConfirmation = {position = {24, 0, 0}},
        targetHistory = {
            {dt = 0, position = {24, 0, 0}, velocity = {17, 0, 0},
                aimOffset = {0, 1.5, 0}},
        },
    }
    local errorStuds = measureEndpointErrorStuds(pending)
    assert(errorStuds and math.abs(errorStuds - 2.5) < 1e-6,
        '2.5 studs short must score 2.5, got ' .. tostring(errorStuds))
    print('PASS\tscoring: a real miss keeps its real distance')
end
'''

# Prediction.getHistory must expose the offset it already samples.
def check_history_export(source: str) -> None:
    assert "aimOffset = sample.aimOffset" in source, (
        "getHistory must return the sampled torso offset"
    )
    assert "aimPart = sample.aimPart" in source, (
        "getHistory must return which part the offset belongs to"
    )
    print("PASS\tPrediction.getHistory: torso offset and aim part are exported")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="telemetry-offset-") as directory:
        script = Path(directory) / "offset.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
    check_history_export(PREDICTION)


if __name__ == "__main__":
    main()
