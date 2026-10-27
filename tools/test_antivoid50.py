#!/usr/bin/env python3
"""v150 Anti Void / Anti fling: bounded rescue, local damping and cheap strips.

Off-line only. Proves that the module does not create a platform, does not
write CFrames, damps only its own root, strips a nearby flinger once per window
and restores every collision, and performs one PivotTo when a real void fall is
detected. It does not prove anything about a live Roblox server.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Movement/AntiVoid.lua").read_text()

for banned in ("Wurst_AntiVoidPlatform", "Instance.new(\"Part\")",
               "root.CFrame =", "BodyAngularVelocity"):
    assert banned not in SOURCE, banned
for required in ("character:PivotTo(target)", "safeCFrame", "AntiVoidStepped",
                 "partCache", "releaseStrip", "forgetSafe", "RaycastParams"):
    assert required in SOURCE, required

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
vmt.__index = function(a, k)
    if k == "Magnitude" then
        return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    end
end
local CFrame = {new = function(p) return {Position = p} end}
local now = 0
os = {clock = function() return now end}
Enum = {Material = {Air = "Air"}, RaycastFilterType = {Exclude = "Exclude"}}
RaycastParams = {new = function()
    return {FilterDescendantsInstances = {}, RespectCanCollide = false}
end}

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
    return s
end

local casts = 0
local world = {
    FallenPartsDestroyHeight = -500,
    Raycast = function(_, origin, direction, params)
        casts += 1
        assert(params.RespectCanCollide, "raycast must respect collisions")
        assert(type(params.FilterDescendantsInstances) == "table")
        return nil -- no floor below the character: a real void
    end,
}

local rootWrites = {CFrame = 0, Position = 0}
local rootData = {
    Position = Vector3.new(0, 250, 0),
    CFrame = CFrame.new(Vector3.new(0, 250, 0)),
    Parent = true,
    Anchored = false,
    AssemblyLinearVelocity = Vector3.zero,
    AssemblyAngularVelocity = Vector3.zero,
}
local root = setmetatable({}, {
    __index = rootData,
    __newindex = function(_, k, v)
        if rootWrites[k] ~= nil then rootWrites[k] += 1 end
        rootData[k] = v
    end,
})
local pivotCalls, pivotTargets = 0, {}
local character = {
    Parent = world,
    PivotTo = function(_, target)
        pivotCalls += 1
        table.insert(pivotTargets, target)
    end,
}
local humanoid = {
    Health = 100,
    WalkSpeed = 16,
    JumpPower = 50,
    MoveDirection = Vector3.zero,
    FloorMaterial = "Ground",
    Died = signal(),
}

local otherParts = {}
local function makePart(name)
    local p = {
        Name = name,
        Parent = character,
        CanCollide = true,
        AssemblyLinearVelocity = Vector3.zero,
        AssemblyAngularVelocity = Vector3.zero,
        IsA = function(_, c) return c == "BasePart" end,
    }
    table.insert(otherParts, p)
    return p
end
local otherRoot = makePart("OtherRoot")
otherRoot.PrimaryPart = nil
otherRoot.Position = Vector3.new(5, 250, 0)
local otherCharacter = {
    PrimaryPart = otherRoot,
    GetDescendants = function() return otherParts end,
    DescendantAdded = signal(),
    FindFirstChildOfClass = function(_, name)
        if name == "Humanoid" then
            return {WalkSpeed = 16}
        end
        return nil
    end,
}
for _, p in ipairs(otherParts) do p.Parent = otherCharacter end

local flingActive = false
local LocalPlayer = {Name = "Me", Character = character}
local otherPlayer = {Name = "Flinger", Character = otherCharacter}
local Players = {GetPlayers = function() return {LocalPlayer, otherPlayer} end}

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
local featureConnections = {}
local function disconnectFeatureConnection(name)
    local handle = featureConnections[name]
    if handle then handle:Disconnect(); featureConnections[name] = nil end
end
local RunService = {Stepped = signal()}

local card
local options = {}
local host = {
    workspace = world,
    Players = Players,
    LocalPlayer = LocalPlayer,
    RunService = RunService,
    TaskManager = TaskManager,
    featureConnections = featureConnections,
    disconnectFeatureConnection = disconnectFeatureConnection,
    getCharacterParts = function() return character, humanoid, root end,
    clock = function() return now end,
    createUniversalFeature = function(_, _, _, fn)
        card = {fn = fn, options = options}
        return card
    end,
    addToggleOption = function(_, label, _, callback) options[label] = callback end,
    addFeatureTooltip = function() end,
}
local context = {
    host = host,
    framework = {GetModule = function() return nil end},
    services = {activity = {isActive = function(name)
        return name == "fling" and flingActive
    end}},
}
state = {}

local Module = (function()
__ANTIVOID_SOURCE__
end)()
Module.init(context)

local function tick(dt)
    local handle = featureConnections.AntiVoid
    assert(handle, "Anti Void/Anti fling tick is not connected")
    handle.fn(dt)
end
local function check(label, condition)
    if not condition then error("FAIL " .. label, 2) end
    print("PASS " .. label)
end

-- Anti Void alone records a safe ground pose; it does not teleport.
card.fn(true)
tick(0.02)
check("grounded pose is remembered", pivotCalls == 0 and rootWrites.CFrame == 0)
check("no platform instance is created", #otherParts == 1)

-- Anti fling keeps its own tick and its Stepped strip owner.
options["Anti fling"](true)
check("anti fling owns a tick independently", featureConnections.AntiVoid ~= nil)
check("anti fling owns the Stepped strip scanner",
    featureConnections.AntiVoidStepped ~= nil)

rootData.AssemblyLinearVelocity = Vector3.new(999, 0, 0)
tick(0.02)
check("launch impulse is damped on the local root",
    rootData.AssemblyLinearVelocity.Magnitude == 0)
check("damping never teleports", rootWrites.CFrame == 0 and pivotCalls == 0)

flingActive = true
rootData.AssemblyLinearVelocity = Vector3.new(999, 0, 0)
tick(0.02)
check("explicit MM2 Fling is never fought",
    rootData.AssemblyLinearVelocity.X == 999)
flingActive = false
rootData.AssemblyLinearVelocity = Vector3.zero
tick(0.02)

-- A nearby driven spin is stripped once, then restored after the window.
otherRoot.AssemblyAngularVelocity = Vector3.new(0, 40, 0)
otherRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
RunService.Stepped:Fire()
check("flinger collisions are stripped once", otherRoot.CanCollide == false)
otherRoot.CanCollide = false
now = 0.5
RunService.Stepped:Fire()
check("stripped collisions are restored", otherRoot.CanCollide == true)

-- A real void fall: one bounded PivotTo to the last safe ground.
now = 3
rootData.Position = Vector3.new(0, 220, 0)
rootData.AssemblyLinearVelocity = Vector3.new(0, -60, 0)
humanoid.FloorMaterial = "Air"
tick(0.02)
check("void fall triggers exactly one rescue", pivotCalls == 1)
check("rescue uses the remembered safe CFrame",
    pivotTargets[1] ~= nil and pivotTargets[1].Position.Y == 250)
check("rescue zeroes velocities without writing CFrames",
    rootData.AssemblyLinearVelocity.Y == 0 and rootWrites.CFrame == 0)
check("rescue is rate limited", (function()
    now = 3.1
    rootData.Position = Vector3.new(0, 220, 0)
    rootData.AssemblyLinearVelocity = Vector3.new(0, -60, 0)
    tick(0.02)
    return pivotCalls == 1
end)())

-- Respawn invalidates the remembered pose.
character = {
    Parent = world,
    PivotTo = function() pivotCalls += 1 end,
}
rootData.Position = Vector3.new(0, 250, 0)
humanoid.FloorMaterial = "Ground"
rootData.AssemblyLinearVelocity = Vector3.zero
LocalPlayer.Character = character
host.getCharacterParts = function() return character, humanoid, root end
tick(0.02)
check("respawn drops the stale rescue pose", pivotCalls == 1)

-- OFF and destroy release everything.
card.fn(false)
check("Anti Void OFF keeps Anti fling tick", featureConnections.AntiVoid ~= nil)
options["Anti fling"](false)
check("both OFF disconnect the tick", featureConnections.AntiVoid == nil
    and featureConnections.AntiVoidStepped == nil and #tasks == 0)
Module.destroy()
check("destroy is safe", true)
print("[ANTI VOID v150] bounded rescue and collision ownership verified")
'''

script = HARNESS.replace("__ANTIVOID_SOURCE__", SOURCE)

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "antivoid_v150.luau"
    path.write_text(script)
    luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
    result = subprocess.run([luau, str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())
