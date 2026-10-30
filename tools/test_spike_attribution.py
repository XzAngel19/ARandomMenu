#!/usr/bin/env python3
"""Exercise the real scheduler/report, without inferring a spike's cause.

Heartbeat delta describes an earlier frame interval; the task run after it is
not necessarily responsible. The user's v162 notification mixed the worst
interval with a label from the latest spike. This test keeps frame intervals,
callback elapsed times and resets separate, including render tasks.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
wurst = (ROOT / "src/Wurst.lua").read_text()
settings = (ROOT / "src/guis/Wurst/Code/SettingsPage.lua").read_text()
block = wurst[wurst.index("type TaskHandle = {"):
              wurst.index("state.taskManager = TaskManager") + len("state.taskManager = TaskManager")]
start = settings.index('    host.addActionOption(uiPanel, "Perf report"')
end = settings.index('\n    host.addActionOption(uiPanel, "Move dock"', start)
action = settings[start:end]

PRELUDE = r'''
local now = 0
local os = {clock = function() return now end}
local warnings = {}
local function warn(message) table.insert(warnings, tostring(message)) end
local PRODUCT = {name = "Wurst", logPrefix = "Wurst"}
local debug = {info = function() return "task" end}
local state = {}
local heartbeat, render
local RunService = {
    Heartbeat = {Connect = function(_, cb) heartbeat = cb; return {Disconnect = function() end} end},
    RenderStepped = {Connect = function(_, cb) render = cb; return {Disconnect = function() end} end},
}
local function frame(dt) now += dt; heartbeat(dt) end
local function pass(text) print("PASS\tperformance: " .. text) end
'''

BODY = r'''
local knifeCost = 0.00037
state.taskManager:Connect(function() now += knifeCost end, nil, "MM2 Knife Throw")

-- The screenshot: current callback time is small, but we cannot conclude
-- whether the prior 988 ms interval was due to game, executor, GPU, async
-- work, or an earlier callback. The report must not make that claim.
frame(0.988)
assert(state.performance.spikeCount == 1)
assert(math.abs(state.performance.worstSpikeMs - 988) < 0.001)
assert(state.performance.peakTask == "MM2 Knife Throw")
assert(math.abs(state.performance.peakTaskMs - 0.37) < 0.001)
local report = state.perfReport()
local intervalLine = report:match("observation[^\n]+")
assert(intervalLine and intervalLine:find("worst 988 ms", 1, true), report)
assert(not intervalLine:find("Knife", 1, true), "worst interval has no module attribution")
assert(report:find("longest callback MM2 Knife Throw", 1, true), report)
assert(report:find("not linked to worst frame", 1, true), report)
assert(warnings[#warnings]:find("cause not determined", 1, true), warnings[#warnings])
pass("988 ms interval and 0.37 ms callback remain independent")

-- A long callback in a later non-spike frame remains a separate measured peak.
knifeCost = 0.240
frame(0.016)
assert(math.abs(state.performance.peakTaskMs - 240) < 0.001)
assert(state.performance.spikeCount == 1 and state.performance.worstSpikeMs == 988)
assert(state.perfReport():find("not linked to worst frame", 1, true))
pass("a long callback in a different frame is never attached to the worst interval")

-- Render phase is measured too, including callbacks that are later removed.
local renderHandle = state.taskManager:Connect(function() now += 0.3 end, "render", "Render test")
render(0.016)
renderHandle:Disconnect()
assert(state.performance.peakTask == "Render test")
assert(state.performance.peakTaskPhase == "render")
assert(math.abs(state.performance.peakTaskMs - 300) < 0.001)
assert(state.perfReport():find("Render test", 1, true))
pass("render callback peaks remain recorded even after disconnect")

local actionCallback
local notification
local uiPanel = {}
local host = {addActionOption = function(_, name, callback)
    assert(name == "Perf report")
    actionCallback = callback
end}
local function notify(text) notification = text end
'''

CHECKS = r'''
assert(type(actionCallback) == "function", "real settings action was registered")
actionCallback()
assert(notification:find("worst 988 ms", 1, true), notification)
assert(notification:find("callback peak Render test", 1, true), notification)
assert(state.performance.spikeCount == 0 and state.performance.worstSpikeMs == 0)
assert(state.performance.peakTask == nil and state.performance.peakTaskMs == 0)
assert(state.performance.peakTaskPhase == nil and state.performance.spikeAt == nil)
assert(state.performance.spikeAgo == -1)
pass("real Perf report action summarizes then resets both measurements")

knifeCost = 0.005
frame(0.060)
assert(state.performance.spikeCount == 1 and state.performance.worstSpikeMs == 60)
assert(state.performance.peakTask == "MM2 Knife Throw")
assert(math.abs(state.performance.peakTaskMs - 5) < 0.001)
assert(state.performance.peakTaskPhase == "heartbeat")
assert(not state.perfReport():find("Render test", 1, true), "old peak cleared")
pass("new observation has a fresh maximum and correct heartbeat phase")
'''

with tempfile.TemporaryDirectory(prefix="spike-") as tmp:
    file = Path(tmp) / "test.luau"
    file.write_text(PRELUDE + "\n" + block + "\n" + BODY + "\n" + action + "\n" + CHECKS)
    subprocess.run([os.environ.get("LUAU", "luau"), str(file)], check=True)
