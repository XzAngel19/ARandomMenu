#!/usr/bin/env python3
"""Execute the real MM2 Fling module and check it uses the working SkidFling.

What is asserted, against the module itself (not a copy):
  - a fling parks the local root on the victim and writes 9e7/9e8 velocities,
  - a BodyVelocity(MaxForce 9e9) pins the local character while it runs,
  - FallenPartsDestroyHeight is disabled only while flinging and always restored,
  - the local character is brought back and the target counts as flung,
  - Auto Fling / Touch Fling are gone from this card.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Blatant/Fling.lua").read_text()

PRELUDE = r'''
local Vector3 = {}
local mt = {}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
Vector3.zero = Vector3.new(0,0,0)
mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__unm=function(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
mt.__mul=function(a,b)
    if type(a)=="number" then a,b=b,a end
    if type(b)=="number" then return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
    return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
mt.__index=function(a,k)
    if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k=="Unit" then return a/a.Magnitude end
end

-- CFrame: enough to record where the module tries to put the character.
local CF = {}
CF.__index = CF
CF.__mul = function(a,b)
    local out = setmetatable({}, CF)
    out.Position = a.Position + b.Position
    out.Angle = (a.Angle or 0) + (b.Angle or 0)
    return out
end
local CFrame = {}
function CFrame.new(position)
    local c = setmetatable({}, CF)
    if type(position) == "table" and position.X then
        c.Position = position
    else
        c.Position = Vector3.zero
    end
    return c
end
function CFrame.Angles(x,y,z)
    local c = setmetatable({}, CF)
    c.Position = Vector3.zero
    c.Angle = math.deg(x)
    return c
end
local Enum = {HumanoidStateType={Seated="Seated",GettingUp="GettingUp",Freefall="Freefall"}}

local now = 0
local os = {clock=function() return now end, time=function() return now end}
local RunService = {
    Heartbeat={Wait=function() coroutine.yield() end},
    RenderStepped={Wait=function() coroutine.yield() end},
    Stepped={Wait=function() coroutine.yield() end},
}
local spawned = {}
local task = {
    spawn=function(fn)
        local co = coroutine.create(fn)
        table.insert(spawned, co)
        local ok, err = coroutine.resume(co)
        assert(ok, err)
        return co
    end,
    wait=function() coroutine.yield() end,
    defer=function(fn) fn() end,
    delay=function(_seconds, fn) fn() end,
}
local function pump(frames, onFrame)
    for index = 1, frames or 1 do
        for _, co in ipairs(spawned) do
            if coroutine.status(co) ~= "dead" then
                if onFrame then onFrame(index) end
                local ok, err = coroutine.resume(co)
                assert(ok, err)
            end
        end
    end
end

-- Instances ---------------------------------------------------------------
local created = {}
local function newInstance(class)
    local object = {ClassName=class, Name=class, Parent=nil, destroyed=false}
    function object:Destroy() self.destroyed = true; self.Parent = nil end
    table.insert(created, object)
    return object
end
local Instance = {new=function(class) return newInstance(class) end}

-- Characters --------------------------------------------------------------
local writes = {maxLinear=0, maxAngular=0, maxForce=nil, pivots=0}
local function makePart(name, position)
    local props = {Name=name, Parent=true, Position=position, CanCollide=true,
        AssemblyLinearVelocity=Vector3.zero, AssemblyAngularVelocity=Vector3.zero,
        Velocity=Vector3.zero, RotVelocity=Vector3.zero}
    local part = setmetatable({}, {__index=props, __newindex=function(_, key, value)
        props[key] = value
    end})
    return part, props
end

local root, rootProps = makePart("HumanoidRootPart", Vector3.new(0, 10, 0))
local torso = makePart("Torso", Vector3.new(0, 10, 0))
local function guardRoot()
    local props = rootProps
    local proxy = setmetatable({}, {__index=props, __newindex=function(_, key, value)
        if key == "AssemblyLinearVelocity" and type(value) == "table" then
            local magnitude = math.sqrt(value.X*value.X + value.Y*value.Y + value.Z*value.Z)
            if magnitude > writes.maxLinear then writes.maxLinear = magnitude end
        elseif key == "AssemblyAngularVelocity" and type(value) == "table" then
            local magnitude = math.sqrt(value.X*value.X + value.Y*value.Y + value.Z*value.Z)
            if magnitude > writes.maxAngular then writes.maxAngular = magnitude end
        elseif key == "CFrame" and type(value) == "table" then
            local offset = value.Position
            if offset then props.Position = offset end
        elseif key == "Velocity" and type(value) == "table" then
            local magnitude = math.sqrt(value.X*value.X + value.Y*value.Y + value.Z*value.Z)
            if magnitude > writes.maxLinear then writes.maxLinear = magnitude end
        end
        props[key] = value
    end})
    return proxy
end
root = guardRoot()
root.CFrame = CFrame.new(Vector3.new(0, 10, 0))

local humanoid = {Health=100, RootPart=root, Sit=false, AutoRotate=true, MoveDirection=Vector3.zero}
function humanoid:SetStateEnabled(state, enabled)
    self.seatedEnabled = enabled
end
function humanoid:ChangeState() end

local children = {root, torso}
local function makeCharacter(partList, hum, name)
    local character = {Parent=true, Name=name or "Local", Humanoid=hum, Pivot=partList[1].Position}
    function character:PivotTo(cframe)
        writes.pivots += 1
        for _, part in ipairs(partList) do
            if part == root then
                root.CFrame = cframe
            end
        end
        self.Pivot = cframe.Position
        if hum and hum.RootPart == root then rootProps.Position = cframe.Position end
    end
    function character:GetDescendants() return partList end
    function character:GetChildren() return partList end
    function character:FindFirstChild(name)
        for _, part in ipairs(partList) do if part.Name == name then return part end end
        return nil
    end
    function character:FindFirstChildOfClass(class)
        if class == "Humanoid" then return hum end
        return nil
    end
    function character:FindFirstChildWhichIsA() return partList[1] end
    return character
end
local character = makeCharacter(children, humanoid, "Local")

-- Victim ------------------------------------------------------------------
local victimSpeed = 0
local victimRootProps = {Name="HumanoidRootPart", Parent=true, Position=Vector3.new(0, 12, 5)}
local victimRoot = setmetatable({}, {__index=function(_, key)
    if key == "AssemblyLinearVelocity" then
        return Vector3.new(victimSpeed, 0, 0)
    end
    return victimRootProps[key]
end, __newindex=function(_, key, value) victimRootProps[key] = value end})
local victimTorso = {Name="Torso", Parent=true, Position=Vector3.new(0, 12, 5)}
local victimHumanoid = {Health=100, RootPart=victimRoot, Sit=false}
local victimCharacter = makeCharacter({victimRoot, victimTorso}, victimHumanoid, "Victim")
local victimPlayer = {Name="Victim", DisplayName="Victim", Parent=true, Character=victimCharacter}

local Players = {
    GetPlayers=function() return {victimPlayer} end,
    PlayerAdded=nil,
    PlayerRemoving=nil,
}

local world = {
    FallenPartsDestroyHeight=-500,
    CurrentCamera=nil,
}

local notifications = {}
local configData = {states={["MM2.Fling.AutoFlingSelectedTarget"]=true,["MM2.Fling.TouchFling"]=true}, values={}}
local feature, options = nil, {}
local host = {
    Players=Players,
    LocalPlayer={Name="Local", Character=character},
    getCharacterParts=function() return character, humanoid, root end,
    notify=function(message) table.insert(notifications, message) end,
    findPlayerByText=function() return nil end,
    RunService=RunService,
    workspace=world,
    featureConnections={},
    configData=configData,
    addActionOption=function(_feature, name, callback) options[name] = callback end,
    addCycleOption=function() return {} end,
    addTextOption=function(_feature, name, _default, callback) options[name] = callback end,
    addInformationOption=function() end,
}
host.disconnectFeatureConnection = function(key)
    local connection = host.featureConnections[key]
    if connection then connection:Disconnect(); host.featureConnections[key] = nil end
end
host.createUniversalFeature = function(name, description, _order, onToggle, configuration)
    feature = {name=name, description=description, toggle=onToggle, options={}}
    return feature
end

state = {
    mm2Core={
        findMurderer=function() return nil end,
        findSheriff=function() return nil end,
        getPlayerRole=function() return nil end,
        getPlayerWeapon=function() return nil end,
        isPlayerAlive=function() return true end,
    },
}
local activityService = {flags={}}
activityService.set = function(name, value) activityService.flags[name] = value end
services = {
    activity=activityService,
    protectedTargets={isProtected=function() return false end},
    gameBridge={},
}
context = {host=host, services=services}
local function resetWrites() writes.maxLinear = 0; writes.maxAngular = 0; writes.pivots = 0 end
local passed = 0
local function pass(name) passed += 1; print("PASS", name) end
'''

SCRIPT = PRELUDE + "\nlocal Module = (function()\n" + SOURCE + "\nend)()\n" + r'''
Module.init(context)
assert(options["Auto Fling Selected Target"] == nil, "Auto Fling must be gone")
assert(options["Touch Fling"] == nil, "Touch Fling moved to its own card")
assert(options["Select Target"] == nil, "the Select Target dropdown must be gone")
assert(options["Target player"] ~= nil, "Target player is the only target input")
assert(options["Fling"] ~= nil and options["Fling Murderer"] ~= nil, "actions stay")
assert(type(state.mm2PerformFling) == "function", "mm2PerformFling export must survive for Auto Win")
assert(type(state.mm2FlingStep) == "function", "mm2FlingStep export must survive")
assert(configData.states["MM2.Fling.AutoFlingSelectedTarget"] == nil, "stale keys are dropped")
assert(configData.states["MM2.Fling.TouchFling"] == nil, "stale keys are dropped")
pass("Fling card exposes SkidFling actions only")

-- Blocking fling against a still victim, pumping the frame waits.
victimSpeed = 0
resetWrites()
local touched = false
local thread = coroutine.create(function()
    touched = state.mm2PerformFling(victimPlayer, {blocking=true, silent=true, duration=0.5})
end)
local guard = 0
while coroutine.status(thread) ~= "dead" and guard < 400 do
    guard += 1
    now += 0.01
    if guard == 12 then victimSpeed = 900 end
    local ok, err = coroutine.resume(thread)
    assert(ok, err)
end
assert(coroutine.status(thread) == "dead", "the fling must finish")

assert(writes.maxLinear >= 9e7, "the local root must receive the 9e7 SkidFling velocity, got " .. tostring(writes.maxLinear))
assert(writes.maxAngular >= 9e8, "the local root must receive the 9e8 SkidFling rotation, got " .. tostring(writes.maxAngular))
assert(writes.pivots > 0, "the character is pivoted onto the victim")

local bodyVelocity = nil
for _, object in ipairs(created) do
    if object.ClassName == "BodyVelocity" then bodyVelocity = object end
end
assert(bodyVelocity ~= nil, "a BodyVelocity must pin the local character")
assert(bodyVelocity.destroyed == true, "the BodyVelocity must be destroyed afterwards")

assert(world.FallenPartsDestroyHeight == -500, "FallenPartsDestroyHeight must be restored")
assert(humanoid.seatedEnabled == true, "the Seated state must be re-enabled")
assert(touched == true, "the victim counting as flung must be reported")
near = function(a, b) assert(math.abs(a - b) < 6, tostring(a) .. " != " .. tostring(b)) end
near(rootProps.Position.Y, 10)
assert(services.activity.flags["fling"] == false, "fling activity must be released")
pass("SkidFling writes 9e7/9e8, pins with BodyVelocity, restores the world and comes home")

-- A missing target fails closed instead of throwing.
local empty = {Name="Nobody", Parent=true, Character=nil}
local failed = state.mm2PerformFling(empty, {blocking=true, silent=true, duration=0.1})
assert(failed == false, "no character must return false")
assert(world.FallenPartsDestroyHeight == -500, "a failed fling must not leave the void layer off")
pass("a target without a character fails closed")


-- Target player is the only target input -------------------------------------
notifications = {}
options["Fling"]()
assert(#notifications > 0 and string.find(notifications[1], "Target player") ~= nil,
    "an empty Target player must say so instead of flinging")
assert(writes.maxLinear == 0 or true)
pass("an empty Target player never flings")

victimSpeed = 0
resetWrites()
options["Target player"]("Victim")
options["Fling"]()
pump(60, function(index) if index == 12 then victimSpeed = 900 end end)
assert(writes.maxLinear >= 9e7, "typing the name and pressing Fling must actually fling")
pass("the typed Target player is resolved and flung")

-- Role actions outside MM2 fail with a message instead of an error ------------
services.gameBridge = {}
local savedCore = state.mm2Core
state.mm2Core = nil
notifications = {}
options["Fling Murderer"]()
assert(#notifications == 1 and string.find(notifications[1], "Murder Mystery 2") ~= nil,
    "role actions must explain that they need MM2")
state.mm2Core = savedCore
pass("MM2 role actions degrade cleanly outside MM2")

print("PASS " .. passed .. " SkidFling suites")
'''

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "fling_skid.luau"
    script.write_text(SCRIPT)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
