#!/usr/bin/env python3
"""Run the real MM2 Fling module: Auto Fling is gone and walkfling only exists
while the Touch Fling option is ON.

Covers the two things the user asked for on v138:
  1. "Auto Fling Selected Target" is deleted, and its stale config key can never
     start a fling on injection.
  2. The Infinite Yield walkfling pulse (the one that also clears CanCollide,
     which the user reads as noclip) runs only while Touch Fling is ON, and the
     collision flags are put back when it stops.

The module is executed with deterministic mocks; no Roblox, no executor.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Blatant/Fling.lua").read_text()

PRELUDE = r'''
local Vector3 = {}
local mt = {}
function Vector3.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},mt) end
Vector3.zero = Vector3.new(0,0,0)
mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul=function(a,b)
    if type(a)=="number" then a,b=b,a end
    return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
mt.__index=function(a,k)
    if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k=="Unit" then return a/a.Magnitude end
end
local CFrame = {new=function(p) return {Position=p} end,
    lookAt=function(p,q) return {Position=p,Endpoint=q} end}
local Enum = {HumanoidStateType={Jumping="Jumping",Freefall="Freefall"},
    RaycastFilterType={Exclude="Exclude",Include="Include"},
    Material={Air="Air"}}

-- Frame pump: the module spawns the loop with task.spawn and waits on RunService.
local jobs = {}
local function pump(frames)
    for _ = 1, frames or 1 do
        for _, thread in ipairs(jobs) do
            if coroutine.status(thread) ~= "dead" then
                local ok, err = coroutine.resume(thread)
                assert(ok, err)
            end
        end
    end
end
local RunService = {
    Heartbeat={Wait=function() coroutine.yield() end},
    RenderStepped={Wait=function() coroutine.yield() end},
    Stepped={Wait=function() coroutine.yield() end},
}
local task = {
    spawn=function(fn)
        local thread = coroutine.create(fn)
        table.insert(jobs, thread)
        local ok, err = coroutine.resume(thread)
        assert(ok, err)
    end,
    wait=function() coroutine.yield() end,
    defer=function(fn) fn() end,
}
local function signal()
    local s = {}
    function s:Connect(fn)
        local h = {Connected=true, fn=fn}
        function h:Disconnect() self.Connected=false end
        return h
    end
    function s:Wait() coroutine.yield() end
    return s
end

-- Physics writes are recorded, never applied to a real character.
local writes = 0
local maxSpeed = 0
local sawCollisionOff = false
local sawCollisionRestored = false
local function makePart(name, canCollide)
    local props = {Name=name, CanCollide=canCollide, Parent=true, Position=Vector3.new(0,10,0)}
    props.IsA = function(_self, class) return class == "BasePart" end
    local part = setmetatable({}, {__index=props, __newindex=function(_, key, value)
        if key == "CanCollide" then
            if value == false then
                sawCollisionOff = true
            elseif sawCollisionOff and value == true then
                sawCollisionRestored = true
            end
        end
        props[key] = value
    end})
    return part
end
local rootProps = {CanCollide=true, Parent=true, Position=Vector3.new(0,10,0),
    AssemblyLinearVelocity=Vector3.zero, Velocity=Vector3.zero,
    AssemblyAngularVelocity=Vector3.zero}
rootProps.IsA = function(_self, class) return class == "BasePart" end
local root = setmetatable({}, {__index=rootProps, __newindex=function(_, key, value)
    if (key == "AssemblyLinearVelocity" or key == "Velocity") and type(value) == "table" then
        local magnitude = math.sqrt(value.X*value.X + value.Y*value.Y + value.Z*value.Z)
        if magnitude > maxSpeed then maxSpeed = magnitude end
    end
    if key == "AssemblyLinearVelocity" or key == "Velocity" then writes += 1 end
    rootProps[key] = value
end})
local arm = makePart("LeftArm", true)
local leg = makePart("RightLeg", true)
local children = {root, arm, leg}
local humanoid = {Health=100, RootPart=root, Sit=false}
local character = {Parent=true, Humanoid=humanoid}
function character:GetChildren() return children end
function character:FindFirstChild(name) for _, part in ipairs(children) do if part.Name == name then return part end end return nil end
function character:FindFirstChildOfClass(class) if class == "Humanoid" then return humanoid end return nil end
function character:PivotTo() error("the fling must never teleport the local character") end

local activity = {}
local configData = {states={
    ["MM2.Fling"]=false,
    ["MM2.Fling.AutoFlingSelectedTarget"]=true,   -- stale v138 key
    ["MM2.Fling.TouchFling"]=true,                -- stale v140 key
}}
local feature, options, notifications = nil, {}, {}
local host = {
    LocalPlayer={Name="LocalPlayer", Character=character},
    Players={GetPlayers=function() return {} end, PlayerAdded=signal(), PlayerRemoving=signal()},
    getCharacterParts=function() return character, humanoid, root end,
    notify=function(message) table.insert(notifications, message) end,
    findPlayerByText=function() return nil end,
    RunService=RunService,
    workspace={FallenPartsDestroyHeight=-500},
    featureConnections={},
    configData=configData,
}
function host.disconnectFeatureConnection(key)
    local connection = host.featureConnections[key]
    if connection then connection:Disconnect(); host.featureConnections[key] = nil end
end
host.createUniversalFeature = function(name, _description, _order, onToggle, _config)
    feature = {name=name, toggle=onToggle, options={}}
    return feature
end
host.addActionOption = function(_feature, name, callback) options[name] = callback end
host.addCycleOption = function(_feature, name, _values, _index, callback)
    options[name] = callback
    return {}
end
host.addToggleOption = function(_feature, name, _default, callback) options[name] = callback end
host.addTextOption = function(_feature, name, _default, callback) options[name] = callback end
host.addInformationOption = function() end

local services = {
    activity={set=function(name, value) activity[name] = value end},
    protectedTargets={isProtected=function() return false end},
    gameBridge={},
}
state = {
    frameworkEnvironment=host,
    mm2Core={
        findMurderer=function() return nil end,
        findSheriff=function() return nil end,
        getPlayerRole=function() return nil end,
        getPlayerWeapon=function() return nil end,
        isPlayerAlive=function() return true end,
    },
}
local function resetWrites() writes = 0; maxSpeed = 0 end
local function near(a, b) assert(math.abs(a - b) < 1e-6, tostring(a) .. " != " .. tostring(b)) end
local passed = 0
local function pass(name) passed += 1; print("PASS", name) end
'''

SCRIPT = PRELUDE + "\nlocal Module = (function()\n" + SOURCE + "\nend)()\n" + r'''
-- 1. Injection: Auto Fling is gone and the stale keys cannot start anything.
Module.init({})
assert(options["Auto Fling Selected Target"] == nil, "Auto Fling must not be registered")
assert(options["Touch Fling"] ~= nil, "Touch Fling must be registered")
assert(options["Touch Fling"] ~= options["Auto Fling Selected Target"], "Touch Fling is its own option")
assert(configData.states["MM2.Fling.AutoFlingSelectedTarget"] == nil,
    "the stale Auto Fling key must be dropped at boot")
assert(configData.states["MM2.Fling.TouchFling"] == false,
    "Touch Fling must never be restored from the saved config")
assert(writes == 0, "injecting must not write character velocity")
assert(sawCollisionOff == false, "injecting must not clear CanCollide")
assert(activity["fling"] == nil, "injecting must not flag fling activity")

resetWrites()
pump(12)
assert(writes == 0 and maxSpeed == 0, "no frame work while Touch Fling is OFF")
assert(sawCollisionOff == false, "the walkfling/noclip pulse never runs by itself")
pass("injecting v138 writes no physics and drops the Auto Fling key")

-- 2. Turning the module container off never starts walkfling.
feature.toggle(true)
pump(6)
assert(writes == 0 and maxSpeed == 0, "the module container must not walk-fling")
assert(sawCollisionOff == false, "the module container must not clear collisions")
feature.toggle(false)
pump(6)
assert(maxSpeed == 0, "turning the module off must not spike velocity")
assert(sawCollisionOff == false, "turning the module off must not clear collisions")
pass("the Fling container toggle never starts walkfling on its own")

-- 3. Touch Fling ON: the unchanged IY walkfling pulse (spike + CanCollide clear).
options["Touch Fling"](true)
pump(10)
assert(activity["fling"] == true, "Touch Fling marks fling activity")
assert(maxSpeed > 9000, "walkfling must spike the root velocity while ON")
assert(sawCollisionOff == true, "walkfling must clear CanCollide while ON")
pass("Touch Fling ON runs the real walkfling pulse")

-- 4. Touch Fling OFF: loop stops, collision flags come back, velocity is parked.
options["Touch Fling"](false)
pump(12)
assert(sawCollisionRestored == true, "stopping Touch Fling must restore CanCollide")
near(rootProps.AssemblyLinearVelocity.Magnitude, 0)
near(rootProps.AssemblyAngularVelocity.Magnitude, 0)
local before, beforeSpeed = writes, maxSpeed
pump(12)
assert(writes == before and maxSpeed == beforeSpeed, "no frame work after Touch Fling is OFF")
pass("Touch Fling OFF stops the loop and restores collisions")

-- 5. Destroy while ON also restores: no "noclip forever" left behind.
resetWrites()
sawCollisionOff = false
sawCollisionRestored = false
options["Touch Fling"](true)
pump(8)
assert(sawCollisionOff == true, "the loop restarts after being re-enabled")
Module.destroy()
pump(12)
assert(sawCollisionRestored == true, "destroy must restore CanCollide")
assert(writes > 0, "destroy still owns the velocity reset")
pass("destroy while Touch Fling is ON restores the character")

print("PASS " .. passed .. " Touch Fling suites")
'''

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "fling_touch.luau"
    script.write_text(SCRIPT)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
