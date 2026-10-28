#!/usr/bin/env python3
"""The frame scheduler, executed for real against a fake RunService.

v139 rewrote TaskManager: the buckets are dense arrays (swap-remove), every task
keeps a cost average, the slowest one is published in state.performance and a
task that goes over budget is warned about by name. That is the code that decides
how many callbacks run per frame for the whole menu, so it gets its own suite:

  1. connect/run/disconnect semantics (no ghosts, no double calls);
  2. swap-remove keeps every other task alive and in place;
  3. a self-disconnecting task survives the frame without skipping its neighbour;
  4. errors disable a task after three failures instead of breaking the frame;
  5. Stats() reports counts, costs and the slowest task, sorted;
  6. perfReport() is a readable string;
  7. the render bucket is separate from the heartbeat bucket.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WURST = (ROOT / 'src/Wurst.lua').read_text()
START = WURST.index('type TaskHandle = {')
END = WURST.index('state.taskManager = TaskManager') + len('state.taskManager = TaskManager')
BLOCK = WURST[START:END]

PRELUDE = r'''
local now = 0
local os = {clock = function() return now end, time = function() return 0 end}
local warnings = {}
local function warn(message) table.insert(warnings, tostring(message)) end
local PRODUCT = {name = "Wurst", logPrefix = "Wurst"}
local debug = {info = function() return "generated chunk" end}
local state = {}
local heartbeats = {}
local renders = {}
local RunService = {
    Heartbeat = {Connect = function(_, callback) table.insert(heartbeats, callback) return {Disconnect = function() end} end},
    RenderStepped = {Connect = function(_, callback) table.insert(renders, callback) return {Disconnect = function() end} end},
}
local function frame(delta)
    now += delta or 1 / 60
    for _, callback in ipairs(heartbeats) do callback(delta or 1 / 60) end
end
local function render(delta)
    for _, callback in ipairs(renders) do callback(delta or 1 / 60) end
end
'''

SCRIPT = PRELUDE + "\n" + BLOCK + r'''
local passed = 0
local function pass(name) passed += 1; print("PASS", name) end
local function near(a, b, epsilon)
    assert(math.abs(a - b) <= (epsilon or 1e-6), tostring(a) .. " != " .. tostring(b))
end

-- 1) connect / run / disconnect ------------------------------------------
local calls = {}
local function makeTask(name, cost)
    return function(deltaTime)
        calls[name] = (calls[name] or 0) + 1
        if cost then now += cost end
    end
end
local a = state.taskManager:Connect(makeTask("a"))
local b = state.taskManager:Connect(makeTask("b"))
local c = state.taskManager:Connect(makeTask("c"))
assert(#state.taskManager.tasks == 3, "three tasks registered")
frame()
frame()
assert(calls.a == 2 and calls.b == 2 and calls.c == 2, "every task runs once per frame")
b:Disconnect()
assert(#state.taskManager.tasks == 2, "disconnect removes the task")
frame()
assert(calls.b == 2, "a disconnected task never runs again")
assert(calls.a == 3 and calls.c == 3, "the neighbours keep running")
assert(b.Connected == false, "the handle reports the state")
pass("connect, run and disconnect are exact")

-- 2) swap-remove keeps the survivors intact ------------------------------
calls = {}
local ids = {}
for index = 1, 6 do
    ids[index] = state.taskManager:Connect(makeTask("t" .. index))
end
assert(#state.taskManager.tasks == 8, "eight tasks now, got " .. #state.taskManager.tasks)
ids[3]:Disconnect()
ids[5]:Disconnect()
frame()
for index = 1, 6 do
    if index ~= 3 and index ~= 5 then
        assert(calls["t" .. index] == 1, "t" .. index .. " survived the swap-remove")
    else
        assert(calls["t" .. index] == nil, "t" .. index .. " was disconnected")
    end
end
assert(calls.a == 1 and calls.c == 1, "the original tasks still run")
pass("swap-remove keeps every other task alive exactly once")

-- 3) a task that disconnects itself mid-frame ----------------------------
calls = {}
local selfHandle
selfHandle = state.taskManager:Connect(function()
    calls.self = (calls.self or 0) + 1
    selfHandle:Disconnect()
end)
local after = state.taskManager:Connect(makeTask("after"))
frame()
frame()
assert(calls.self == 1, "a self-disconnecting task runs once, got " .. tostring(calls.self))
assert(calls.after == 2, "the task after it still runs every frame")
selfHandle:Disconnect() -- idempotent, must not corrupt the bucket
pass("self-disconnect inside a frame is safe")

-- 4) failures disable a task after three frames --------------------------
local failing = state.taskManager:Connect(function() error("boom") end)
warnings = {}
frame()
frame()
assert(warnings[1] ~= nil and string.find(warnings[1], "failed") ~= nil,
    "a failing task is reported")
frame()
frame()
assert(failing.Connected == false, "three failures disable the task")
local before = #state.taskManager.tasks
frame()
assert(#state.taskManager.tasks == before, "the disabled task is swept out of the bucket")
pass("an erroring task is disabled instead of breaking the frame")

-- 5) Stats() --------------------------------------------------------------
calls = {}
local slow = state.taskManager:Connect(makeTask("slow", 0.004), nil, "slow module")
local quick = state.taskManager:Connect(makeTask("quick", 0))
for _ = 1, 20 do frame() end
local stats = state.taskManager:Stats()
assert(stats.taskCount == #state.taskManager.tasks, "Stats counts the heartbeat bucket")
assert(stats.renderCount == 0, "the render bucket is separate")
assert(stats.tasksMs > 0, "the bucket cost is measured")
assert(stats.slowest and stats.slowest.label == "slow module",
    "an explicit label wins, got " .. tostring(stats.slowest and stats.slowest.label))
assert(type(stats.top[1].label) == "string" and #stats.top[1].label > 0,
    "every task has a label")
assert(#stats.top >= 2, "Stats lists the tasks")
assert(stats.top[1].ms >= stats.top[2].ms, "Stats is sorted by cost")
assert(state.performance.tasksMs >= 0, "state.performance mirrors the bucket")
assert(state.performance.taskCount == #state.taskManager.tasks, "performance counts the tasks")
pass("Stats reports counts, costs and the slowest task")

-- 6) perfReport() ---------------------------------------------------------
local report = state.perfReport()
assert(type(report) == "string" and #report > 0, "perfReport returns text")
assert(string.find(report, "FPS") ~= nil, "the report starts with FPS")
assert(string.find(report, "tasks") ~= nil, "the report lists the task bucket")
pass("perfReport is a readable snapshot")

-- 7) the render bucket is independent -------------------------------------
local rendered = 0
local renderTask = state.taskManager:Connect(function() rendered += 1 end, "render")
assert(#state.taskManager.renderTasks == 1, "render task registered in its own bucket")
render()
assert(rendered == 1, "render tasks run on the render signal")
frame()
assert(rendered == 1, "heartbeat does not run render tasks")
renderTask:Disconnect()
render()
assert(rendered == 1, "a disconnected render task stops")
pass("the render bucket runs on RenderStepped only")

-- 8) Destroy() empties everything -----------------------------------------
state.taskManager:Destroy()
assert(#state.taskManager.tasks == 0 and #state.taskManager.renderTasks == 0, "Destroy empties the buckets")
pass("Destroy empties the scheduler")

print("PASS " .. passed .. " scheduler suites")
'''

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "scheduler.luau"
    script.write_text(SCRIPT)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
