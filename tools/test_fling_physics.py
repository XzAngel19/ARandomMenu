#!/usr/bin/env python3
"""v150 contact-physics controller: static bans and deterministic lifecycle.

The rebuilt library uses a finite impulse on an assembly this client can
steer (confirmed network ownership of the target, or its own root through a
character-to-character contact). It does not spin, does not write CFrames per
frame, does not leave constraints or ownership behind. These tests prove the
local mechanism and cleanup; only a live session can prove server knockback.
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
for banned in (
    "BodyAngularVelocity", "BodyVelocity", "BodyGyro",
    "99999", "1000000", "AlignPosition", "Massless",
    "CustomPhysicalProperties", "RenderStepped:Wait", "Stepped:Wait",
    "root.CFrame =", "Character:PivotTo(", "Density", "MaxTorque",
):
    assert banned not in SOURCE, f"retired fling mechanism: {banned}"
# math.huge may only appear in finite-value guards / an empty cooldown sentinel.
assert SOURCE.count("math.huge") <= 6
for required in (
    "ApplyImpulse", "GetNetworkOwner", "SetNetworkOwner",
    "SetNetworkOwnershipAuto", "releaseOwnership", "applyImpulseOnce",
    "PULSE_SPEED: number = 190", "TaskManager:Connect",
    "activity.set", "lastStrategy", "PLACE_DISTANCE: number = 2.4",
    "character:PivotTo",  # one bounded placement / return, never per frame
):
    assert required in SOURCE, f"missing contact mechanism: {required}"
# Two calls (placement and return) plus one reference in the evidence comment.
assert SOURCE.count("character:PivotTo") == 3, "exactly two bounded placements"

for required in (
    '"Fling target"', "state.mm2FlingRoster", "state.mm2FlingSelection",
    '"Auto Fling Selected Target"', "MM2AutoFlingTarget", "MM2FlingRoster",
    "physics.start",
):
    assert required in MM2_SOURCE, required
assert "task.wait" not in MM2_SOURCE, "no blocking coroutine in the MM2 card"
assert "physics.setTouchEnabled" in TOUCH_SOURCE
assert "restore = false" in TOUCH_SOURCE
assert "BodyAngularVelocity" not in TOUCH_SOURCE

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
local CFrame = {new = function(p) return {Position = p} end}
local now = 0
os = {clock = function() return now end}
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

local ownerMode = "none"
local autoCalls = 0
local LocalPlayer = {Name = "Me"}
local function makeRoot(label, position)
    local r = {
        Name = label,
        Position = position,
        Parent = true,
        Anchored = false,
        AssemblyLinearVelocity = Vector3.zero,
        AssemblyAngularVelocity = Vector3.zero,
        AssemblyMass = 10,
        impulses = 0,
        Touched = signal(),
        LookVector = Vector3.new(0, 0, -1),
    }
    r.CFrame = CFrame.new(position)
    function r:ApplyImpulse(delta)
        self.impulses += 1
        self.AssemblyLinearVelocity = self.AssemblyLinearVelocity + delta
    end
    function r:GetNetworkOwner()
        if ownerMode == "local" then return LocalPlayer end
        return nil
    end
    function r:SetNetworkOwner(player) self.lastOwnerRequest = player end
    function r:SetNetworkOwnershipAuto() autoCalls += 1 end
    function r:IsA(className) return className == "BasePart" end
    return r
end

local localRoot = makeRoot("LocalRoot", Vector3.new(0, 0, 0))
local targetRoot = makeRoot("TargetRoot", Vector3.new(3, 0, 0))
local secondTargetRoot = makeRoot("SecondRoot", Vector3.new(-3, 0, 0))

local function makeCharacter(root, hum)
    local c = {
        Parent = true,
        DescendantAdded = signal(),
        GetChildren = function() return {root} end,
        FindFirstChildOfClass = function(_, name)
            if name == "Humanoid" then return hum end
            return nil
        end,
        PivotTo = function() pivotCalls += 1 end,
    }
    return c
end
pivotCalls = 0
local localHum = {Health = 100, RootPart = localRoot, Died = signal()}
local targetHum = {Health = 100, RootPart = targetRoot, Died = signal()}
local secondHum = {Health = 100, RootPart = secondTargetRoot, Died = signal()}
LocalPlayer.Character = makeCharacter(localRoot, localHum)
local target = {Name = "Target", Character = makeCharacter(targetRoot, targetHum)}
local second = {Name = "Second", Character = makeCharacter(secondTargetRoot, secondHum)}
localRoot.Parent = LocalPlayer.Character
targetRoot.Parent = target.Character
secondTargetRoot.Parent = second.Character

local Players = {
    LocalPlayer = LocalPlayer,
    GetPlayerFromCharacter = function(_, character)
        if character == target.Character then return target end
        if character == second.Character then return second end
        if character == LocalPlayer.Character then return LocalPlayer end
        return nil
    end,
}

local host = {
    Players = Players,
    LocalPlayer = LocalPlayer,
    RunService = nil,
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
local function constants() return physics.constants() end

check("boot is idle", not physics.isRunning() and not physics.isTouchEnabled()
    and not physics.isPulsing() and not activityValue)
check("no spin or pin APIs", not physics.isSpinning() and not physics.isHeld())
check("impulse is finite and bounded", constants().pulseSpeed == 190
    and constants().pulseSpeed < 1000)

-- Directed session, contact path (ownership unavailable).
ownerMode = "none"
check("directed start succeeds", physics.start(target,
    {duration = 0.5, restorePosition = false}))
check("session owns the pulse", physics.isRunning() and physics.isPulsing()
    and activityValue)
check("one directed owner", not physics.start(second,
    {duration = 0.4, restorePosition = false}))
local before = localRoot.impulses
drive(0.1)
drive(0.1)
check("finite impulses go through the contact path",
    localRoot.impulses > before and physics.lastStrategy() == "contact")
check("ownership was not assumed", not physics.hasOwnership())
drive(0.1); drive(0.1); drive(0.1); drive(0.1)
check("bounded session ends by itself", not physics.isRunning()
    and not physics.isPulsing() and not activityValue)
check("single placement, no per-frame teleport", pivotCalls <= 1)

-- Directed session, confirmed ownership path.
ownerMode = "local"
check("second directed start succeeds", physics.start(second,
    {duration = 0.4, restorePosition = false}))
local targetBefore = secondTargetRoot.impulses
drive(0.1)
drive(0.1)
check("impulses use confirmed ownership",
    secondTargetRoot.impulses > targetBefore
    and physics.lastStrategy() == "ownership" and physics.hasOwnership())
drive(0.1); drive(0.1); drive(0.1)
check("ownership is released with the session", not physics.hasOwnership()
    and autoCalls > 0 and not physics.isRunning())

-- Touch fling: listeners, cooldown, OFF and respawn cleanup.
ownerMode = "none"
local touchParts = LocalPlayer.Character:GetChildren()
physics.setTouchEnabled(true)
check("Touch binds local parts", physics.isTouchEnabled() and activityValue
    and touchParts[1].Touched:count() == 1)
check("idle Touch never pulses", not physics.isPulsing())
check("scenery is ignored", (function()
    local scenery = {Parent = {Parent = nil}}
    touchParts[1].Touched:Fire(scenery)
    return not physics.isPulsing()
end)())
now = 10
touchParts[1].Touched:Fire(targetRoot)
check("contact starts a pulse", physics.isPulsing())
check("cooldown prevents a crowd chain", (function()
    local beforeCount = localRoot.impulses
    physics.cancel()
    now = 10.1
    touchParts[1].Touched:Fire(targetRoot)
    return not physics.isPulsing() and localRoot.impulses == beforeCount
end)())
now = 11
touchParts[1].Touched:Fire(targetRoot)
check("contact after cooldown pulses again", physics.isPulsing())
physics.setTouchEnabled(false)
check("OFF releases listeners and pulse", not physics.isTouchEnabled()
    and not physics.isPulsing() and touchParts[1].Touched:count() == 0
    and not activityValue)

-- Death / cancel / destroy.
check("cancel is idempotent", (function()
    physics.cancel(); physics.cancel()
    return not physics.isRunning()
end)())
physics.setTouchEnabled(true)
now = 20
touchParts[1].Touched:Fire(targetRoot)
check("pulse runs before destroy", physics.isPulsing())
physics.destroy()
check("destroy stops everything", not physics.isPulsing()
    and not physics.isRunning() and not physics.isTouchEnabled()
    and not activityValue and not physics.hasOwnership())
check("destroyed library cannot restart", not physics.start(target,
    {duration = 0.3, restorePosition = false}))
check("destroy is idempotent", (function() physics.destroy(); return true end)())
print("[FLING v150] contact physics verified")
'''

script = HARNESS.replace("__FLING_SOURCE__", SOURCE)

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "fling_v150.luau"
    path.write_text(script)
    luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
    result = subprocess.run([luau, str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())
