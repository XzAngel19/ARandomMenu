#!/usr/bin/env python3
"""v151 shared Fling engine: exact Infinite Yield walkfling sequence.

The tests below prove the local mechanism -- three velocity frames, local
noclip, one engine owner, bounded sessions and cleanup. Only a live Roblox
session can prove another player's knockback.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/libraries/Fling.lua").read_text()
MM2_SOURCE = (ROOT / "src/games/MM2/Blatant/Fling.lua").read_text()
TOUCH_SOURCE = (ROOT / "src/games/universal/Blatant/TouchFling.lua").read_text()

# --- Static contract -------------------------------------------------------
for required in (
    "VELOCITY_SCALE: number = 10000",
    "VELOCITY_LIFT: number = 10000",
    "local DRIFT: number = 0.1",
    "RunService.Heartbeat",
    "RunService.RenderStepped",
    "RunService.Stepped",
    "part.CanCollide = false",
    "restoreCollisions",
    "writeVelocity",
    "CFrame.lookAt",
    'pcall(activity.set, "fling"',
):
    assert required in SOURCE, f"missing walkfling mechanism: {required}"

for banned in (
    'Instance.new("BodyAngularVelocity")',
    'Instance.new("BodyVelocity")',
    'Instance.new("BodyGyro")',
    "ApplyImpulse(",
    "GetNetworkOwner(",
    "SetNetworkOwner(",
    "root.CFrame =",
    "BindToRenderStep",
    ":Wait()",
    "99999",
    "1000000",
    "CustomPhysicalProperties",
    "MaxTorque",
):
    assert banned not in SOURCE, f"retired fling mechanism: {banned}"

for required in (
    '"Fling target"', "state.mm2FlingRoster", "state.mm2FlingSelection",
    '"Auto Fling Selected Target"', "MM2AutoFlingTarget", "MM2FlingRoster",
    "physics.start",
):
    assert required in MM2_SOURCE, required
assert "task.wait" not in MM2_SOURCE, "no blocking coroutine in the MM2 card"
assert "physics.setTouchEnabled" in TOUCH_SOURCE
assert "restore = false" in TOUCH_SOURCE
assert "WALKFLING ON" in TOUCH_SOURCE
assert "physics.isRunning() or physics.isTouchEnabled()" not in MM2_SOURCE, \
    "continuous Touch Fling must not block a directed session"

HARNESS = r'''
local Vector3 = {}
local vmt = {}
function Vector3.new(x, y, z)
    return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vmt)
end
Vector3.zero = Vector3.new(0, 0, 0)
vmt.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vmt.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vmt.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    if type(b) == "table" then return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
    return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
vmt.__div = function(a, b) return a * (1 / b) end
vmt.__index = function(a, k)
    if k == "Magnitude" then
        return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    end
end
local CFrame = {}
function CFrame.new(p) return {Position = p or Vector3.zero} end
function CFrame.lookAt(p) return CFrame.new(p) end

local now = 0
os = {clock = function() return now end, time = function() return now end}
task = {spawn = function(fn) fn() end, wait = function() end, defer = function(fn) fn() end}
Enum = {Material = {Air = "Air"}}

local function signal()
    local s = {listeners = {}}
    function s:Connect(fn)
        self.listeners[fn] = true
        local alive = true
        return {Disconnect = function()
            if alive then alive = false; self.listeners[fn] = nil end
        end}
    end
    function s:Fire(...)
        for fn in pairs(self.listeners) do fn(...) end
    end
    function s:count()
        local n = 0
        for _ in pairs(self.listeners) do n += 1 end
        return n
    end
    return s
end

local activityValue = false
local activity = {set = function(name, value)
    if name == "fling" then activityValue = value end
end}

local tasks = {}
local TaskManager = {}
function TaskManager:Connect(fn)
    local handle = {fn = fn, Disconnect = function(self)
        for i, entry in ipairs(tasks) do
            if entry == self then table.remove(tasks, i); break end
        end
    end}
    table.insert(tasks, handle)
    return handle
end
local function drive(dt)
    for _, handle in ipairs(table.clone(tasks)) do handle.fn(dt) end
end

local Heartbeat, RenderStepped, Stepped = signal(), signal(), signal()
local RunService = {Heartbeat = Heartbeat, RenderStepped = RenderStepped, Stepped = Stepped}
local LocalPlayer = {Name = "Me", CharacterAdded = signal()}

local velocityWrites, collisionWrites, pivotCalls = 0, 0, 0
local function makeRoot(label, position)
    local data = {
        Name = label,
        Position = position,
        CFrame = CFrame.new(position),
        Parent = true,
        Anchored = false,
        CanCollide = true,
        Velocity = Vector3.new(1, 0, 0),
        AssemblyLinearVelocity = Vector3.new(1, 0, 0),
    }
    local methods = {
        IsA = function(_, className) return className == "BasePart" end,
    }
    return setmetatable({}, {
        __index = function(_, k)
            if methods[k] then return methods[k] end
            return data[k]
        end,
        __newindex = function(_, k, v)
            if k == "Velocity" or k == "AssemblyLinearVelocity" then
                velocityWrites += 1
            elseif k == "CanCollide" then
                collisionWrites += 1
            end
            data[k] = v
        end,
    })
end

local localRoot = makeRoot("LocalRoot", Vector3.new(0, 0, 0))
local targetRoot = makeRoot("TargetRoot", Vector3.new(3, 0, 0))
local secondRoot = makeRoot("SecondRoot", Vector3.new(-3, 0, 0))

local function makeCharacter(root, hum)
    return {
        Parent = true,
        GetDescendants = function() return {root} end,
        GetChildren = function() return {root, hum} end,
        FindFirstChildOfClass = function(_, name)
            if name == "Humanoid" then return hum end
            return nil
        end,
        PivotTo = function(_, frame)
            pivotCalls += 1
            root.Position = frame.Position
            root.CFrame = frame
        end,
    }
end
local localHum = {Health = 100, RootPart = localRoot, Died = signal()}
local targetHum = {Health = 100, RootPart = targetRoot, Died = signal()}
local secondHum = {Health = 100, RootPart = secondRoot, Died = signal()}
LocalPlayer.Character = makeCharacter(localRoot, localHum)
local target = {Name = "Target", Character = makeCharacter(targetRoot, targetHum)}
local second = {Name = "Second", Character = makeCharacter(secondRoot, secondHum)}
localRoot.Parent = LocalPlayer.Character
targetRoot.Parent = target.Character
secondRoot.Parent = second.Character

local Players = {
    LocalPlayer = LocalPlayer,
    GetPlayerFromCharacter = function(_, character)
        if character == target.Character then return target end
        if character == second.Character then return second end
        return nil
    end,
}
local host = {
    Players = Players,
    LocalPlayer = LocalPlayer,
    RunService = RunService,
    TaskManager = TaskManager,
    clock = function() return now end,
}
local Module = (function()
__FLING_SOURCE__
end)()
local physics = Module.init({host = host, services = {activity = activity}})

local function check(label, condition)
    if not condition then error("FAIL " .. label, 2) end
    print("PASS " .. label)
end
local function frame()
    Heartbeat:Fire(1/60)
    RenderStepped:Fire(1/60)
    Stepped:Fire(now, 1/60)
end

check("boot is idle", not physics.isRunning() and not physics.isTouchEnabled()
    and not physics.isPulsing() and not activityValue)
check("no spin or pin APIs", not physics.isSpinning() and not physics.isHeld()
    and not physics.hasOwnership())
check("literal IY constants", physics.constants().velocityScale == 10000
    and physics.constants().velocityLift == 10000
    and physics.constants().drift == 0.1)

-- One directed session: high velocity on Heartbeat, restore on RenderStepped,
-- alternating drift + noclip on Stepped.
check("directed start succeeds", physics.start(target,
    {duration = 0.5, restorePosition = false}))
check("one engine owns the session", physics.isRunning()
    and physics.isPulsing() and activityValue)
check("a second directed session is rejected", not physics.start(second,
    {duration = 0.4, restorePosition = false}))
Heartbeat:Fire(1/60)
check("Heartbeat publishes IY's one-step spike",
    localRoot.Velocity.X == 10000 and localRoot.Velocity.Y == 10000
    and localRoot.AssemblyLinearVelocity.X == 10000
    and physics.lastStrategy() == "walkfling")
RenderStepped:Fire(1/60)
check("RenderStepped restores the real velocity",
    localRoot.Velocity.X == 1 and localRoot.Velocity.Y == 0)
Stepped:Fire(now, 1/60)
check("Stepped writes the alternating drift",
    localRoot.Velocity.X == 1 and localRoot.Velocity.Y == 0.1)
check("noclip is applied only to local parts", localRoot.CanCollide == false
    and targetRoot.CanCollide == true)
check("one bounded placement", pivotCalls == 1)

now = 1
drive(1/60)
check("bounded session ends", not physics.isRunning()
    and not physics.isPulsing() and not activityValue)
check("idle scheduler is empty after the session", #tasks == 0)
check("velocity and collisions are restored", localRoot.CanCollide == true
    and localRoot.Velocity.X == 1)

-- Continuous Touch Fling uses the same engine, not a Touched-listener pulse.
physics.setTouchEnabled(true)
check("Touch Fling starts one continuous engine", physics.isTouchEnabled()
    and physics.isPulsing() and activityValue)
frame()
check("continuous engine keeps cycling", localRoot.Velocity.X == 1
    and localRoot.Velocity.Y == 0.1 and localRoot.CanCollide == false)
check("directed action can run during Touch Fling", physics.start(second,
    {duration = 0.2, restorePosition = false, place = false}))
now = 2
drive(1/60)
check("session ends without disabling Touch Fling", not physics.isRunning()
    and physics.isTouchEnabled() and physics.isPulsing())
physics.setTouchEnabled(false)
check("OFF stops the engine and restores collisions",
    not physics.isTouchEnabled() and not physics.isPulsing()
    and not activityValue and localRoot.CanCollide == true and #tasks == 0)

-- Death / cancel / destroy.
physics.setTouchEnabled(true)
check("cancel does not turn off continuous Touch Fling", (function()
    physics.cancel()
    return physics.isTouchEnabled() and physics.isPulsing()
end)())
physics.destroy()
check("destroy stops everything", not physics.isPulsing()
    and not physics.isRunning() and not physics.isTouchEnabled()
    and not activityValue and localRoot.CanCollide == true)
check("destroyed library cannot restart", not physics.start(target,
    {duration = 0.3, restorePosition = false}))
check("destroy is idempotent", (function() physics.destroy(); return true end)())
print("[FLING v151] exact IY walkfling sequence verified")
'''

script = HARNESS.replace("__FLING_SOURCE__", SOURCE)

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "fling_v151.luau"
    path.write_text(script)
    luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
    result = subprocess.run([luau, str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())
