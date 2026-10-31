#!/usr/bin/env python3
"""Execute the real universal Fling module, ported from the YARHM SkidFling.

The user compared both: theirs teleports onto the target, does a short choreography
and launches them; ours orbited and the local character seemed to fade. The two
concrete defects were pinned down and are asserted here:

  1. The BodyVelocity must be "EpixVel" with Velocity (9e8, 9e8, 9e8) and infinite
     MaxForce - a catapult. Our old port used Velocity zero, which transfers
     nothing.
  2. The pose is written with RootPart.CFrame *and* SetPrimaryPartCFrame plus
     RootPart.Velocity/RotVelocity only. Writing AssemblyLinearVelocity and
     CustomPhysicalProperties every frame (the old port) is what made the local
     character flicker like it was disappearing.
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
function Vector3.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},mt) end
Vector3.zero = Vector3.new(0,0,0)
mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__unm=function(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
mt.__mul=function(a,b)
    if type(a)=="number" then a,b=b,a end
    if type(b)=="number" then return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
    return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
mt.__div=function(a,b) return a*(1/b) end
mt.__index=function(a,k)
    if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k=="Unit" then return a/a.Magnitude end
end

local CF = {}
CF.__index = CF
CF.__add = function(a, b)
    local out = setmetatable({}, CF)
    out.Position = a.Position + b
    out.Angle = a.Angle
    return out
end
CF.__sub = function(a, b)
    local out = setmetatable({}, CF)
    out.Position = a.Position - b
    out.Angle = a.Angle
    return out
end
CF.__mul = function(a,b)
    local out = setmetatable({}, CF)
    out.Position = a.Position + b.Position
    out.Angle = (a.Angle or 0) + (b.Angle or 0)
    return out
end
local CFrame = {}
function CFrame.new(x, y, z)
    local c = setmetatable({}, CF)
    if type(x) == "table" then
        c.Position = x
    else
        c.Position = Vector3.new(x or 0, y or 0, z or 0)
    end
    return c
end
function CFrame.Angles(x, y, z)
    local c = setmetatable({}, CF)
    c.Position = Vector3.zero
    c.Angle = math.deg(x)
    return c
end
local Enum = {HumanoidStateType={Seated="Seated",GettingUp="GettingUp",Freefall="Freefall"}}

-- Roblox exposes typeof(); the module uses it to detect a CFrame option, so the
-- harness has to provide it or every options table would take the error path.
local function typeof(value)
    if type(value) == "table" then
        local meta = getmetatable(value)
        if meta == CF then return "CFrame" end
        if meta == mt then return "Vector3" end
        return "table"
    end
    return type(value)
end

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
    delay=function(_seconds, fn) table.insert(pendingDelays, fn) end,
}
pendingDelays = {}
local function runDelays()
    local queued = pendingDelays
    pendingDelays = {}
    for _, fn in ipairs(queued) do fn() end
end
local function pump(frames, onFrame)
    for index = 1, frames or 1 do
        for _, co in ipairs(spawned) do
            if coroutine.status(co) ~= "dead" then
                now += 0.01
                if onFrame then onFrame(index) end
                local ok, err = coroutine.resume(co)
                assert(ok, err)
            end
        end
    end
end

local created = {}
local function newInstance(class)
    local object = {ClassName=class, Name=class, Parent=nil, destroyed=false}
    function object:Destroy() self.destroyed = true; self.Parent = nil end
    table.insert(created, object)
    return object
end
local Instance = {new=function(class) return newInstance(class) end}

-- Records what the module writes on the local body.
local writes = {maxVelocity=0, maxRotVelocity=0, poses=0, primaries=0,
    assemblyWrites=0, customPhysicsWrites=0, cframeWrites=0, positions={}}

local failNextPose = false
local function track(name, props, value)
    if name == "CFrame" and failNextPose then
        failNextPose = false
        error("simulated pose failure")
    end
    if name == "Velocity" and type(value) == "table" then
        if value.Magnitude > writes.maxVelocity then writes.maxVelocity = value.Magnitude end
        writes.poses += 1
    elseif name == "RotVelocity" and type(value) == "table" then
        if value.Magnitude > writes.maxRotVelocity then writes.maxRotVelocity = value.Magnitude end
    elseif name == "AssemblyLinearVelocity" or name == "AssemblyAngularVelocity" then
        writes.assemblyWrites += 1
    elseif name == "CustomPhysicalProperties" then
        writes.customPhysicsWrites += 1
    elseif name == "CFrame" then
        writes.cframeWrites += 1
        if type(value) == "table" and value.Position then
            props.Position = value.Position
            table.insert(writes.positions, value.Position)
        end
    end
end

local function makePart(name, position)
    local props = {Name=name, Parent=true, Position=position,
        Velocity=Vector3.zero, RotVelocity=Vector3.zero,
        AssemblyLinearVelocity=Vector3.zero, AssemblyAngularVelocity=Vector3.zero}
    local part = setmetatable({}, {__index=props, __newindex=function(_, key, value)
        track(key, props, value)
        props[key] = value
    end})
    props.IsA = function(_, class) return class == "BasePart" end
    return part, props
end

local root, rootProps = makePart("HumanoidRootPart", Vector3.new(0, 10, 0))
local torso = makePart("Torso", Vector3.new(0, 10, 0))
root.CFrame = CFrame.new(Vector3.new(0, 10, 0))
local localParts = {root, torso}

local humanoid = {Health=100, RootPart=root, Sit=false, AutoRotate=true,
    MoveDirection=Vector3.zero, WalkSpeed=16}
function humanoid:SetStateEnabled(state, enabled) self["seated_" .. tostring(state)] = enabled end
function humanoid:ChangeState() end

local function makeCharacter(partList, hum, name)
    local character = {Parent=true, Name=name or "Local", Humanoid=hum}
    function character:SetPrimaryPartCFrame(cframe)
        writes.primaries += 1
        for _, part in ipairs(partList) do
            if part == root then
                root.CFrame = cframe
            end
        end
        if hum and hum.RootPart == root then rootProps.Position = cframe.Position end
    end
    function character:PivotTo(cframe) self:SetPrimaryPartCFrame(cframe) end
    function character:GetChildren() return partList end
    function character:GetDescendants() return partList end
    function character:FindFirstChild(name_)
        for _, part in ipairs(partList) do if part.Name == name_ then return part end end
        return nil
    end
    function character:FindFirstChildOfClass(class)
        if class == "Humanoid" then return hum end
        if class == "Accessory" then return nil end
        return nil
    end
    function character:FindFirstChildWhichIsA() return partList[1] end
    return character
end
local character = makeCharacter(localParts, humanoid, "Local")

-- Victim ------------------------------------------------------------------
local victimSpeed = 0
local function makeVictimPart(name, position)
    local props = {Name=name, Parent=true, Position=position}
    props.IsA = function(_, class) return class == "BasePart" end
    return setmetatable({}, {__index=function(_, key)
        if key == "Velocity" or key == "AssemblyLinearVelocity" then
            return Vector3.new(victimSpeed, 0, 0)
        end
        if key == "RotVelocity" or key == "AssemblyAngularVelocity" then
            return Vector3.zero
        end
        if key == "CFrame" then return CFrame.new(props.Position) end
        return props[key]
    end, __newindex=function(_, key, value) props[key] = value end})
end
local victimRoot = makeVictimPart("HumanoidRootPart", Vector3.new(0, 12, 5))
local victimTorso = makeVictimPart("Torso", Vector3.new(0, 12, 5))
local victimHead = makeVictimPart("Head", Vector3.new(0, 13.5, 5))
local victimHumanoid = {Health=100, RootPart=victimRoot, Sit=false,
    MoveDirection=Vector3.zero, WalkSpeed=16}
local victimCharacter = makeCharacter({victimRoot, victimTorso, victimHead}, victimHumanoid, "Victim")
victimCharacter.Head = victimHead
-- The victim's parts must be children of the victim's character: the pose loop
-- stops when "basePart.Parent ~= targetCharacter" (a part that got destroyed).
victimRoot.Parent = victimCharacter
victimTorso.Parent = victimCharacter
victimHead.Parent = victimCharacter
function victimCharacter:FindFirstChild(name_)
    if name_ == "Head" then return victimHead end
    return makeCharacter
end
local function victimFind(name_)
    if name_ == "Head" then return victimHead end
    for _, part in ipairs({victimRoot, victimTorso}) do
        if part.Name == name_ then return part end
    end
    return nil
end
victimCharacter.FindFirstChild = function(_, name_) return victimFind(name_) end
victimCharacter.FindFirstChildOfClass = function(_, class)
    if class == "Humanoid" then return victimHumanoid end
    if class == "Accessory" then return nil end
    return nil
end
victimCharacter.FindFirstChildWhichIsA = function() return victimRoot end

-- cloneReference() hands the module a different service reference: the player's
-- Parent is the real service, never the reference the module holds. The old port
-- compared them, so "player left the game" was true on frame one and the
-- choreography died after six poses ("fling finished" in half a second).
local PlayersReference = {Name="Players"}
local victimPlayer = {Name="Victim", DisplayName="Victim", Parent=true, Character=victimCharacter}

local Players = {GetPlayers=function() return {victimPlayer} end}
Players.FindFirstChild = function(_, name)
    if name == victimPlayer.Name then return victimPlayer end
    return nil
end

local world = {FallenPartsDestroyHeight=-500, CurrentCamera=nil}

local networkPing = 0
local notifications = {}
local configData = {states={["MM2.Fling.AutoFlingSelectedTarget"]=true,["MM2.Fling.TouchFling"]=true}, values={}}
local feature, options = nil, {}
local host = {
    Players=Players,
    LocalPlayer={Name="Local", Character=character,
        GetNetworkPing=function() return networkPing end},
    getCharacterParts=function() return character, humanoid, root end,
    notify=function(message) table.insert(notifications, message) end,
    findPlayerByText=function() return nil end,
    RunService=RunService,
    workspace=world,
    featureConnections={},
    configData=configData,
    addActionOption=function(_feature, name, callback) options[name] = callback end,
    addTextOption=function(_feature, name, _default, callback) options[name] = callback end,
    addNumberOption=function(_feature, name, _default, _min, _max, callback)
        options[name] = callback
    end,
    addInformationOption=function() end,
}
host.disconnectFeatureConnection = function(key)
    local connection = host.featureConnections[key]
    if connection then connection:Disconnect(); host.featureConnections[key] = nil end
end
host.createUniversalFeature = function(name, description, _order, onToggle, configuration)
    feature = {name=name, description=description, toggle=onToggle,
        options={}, configuration=configuration}
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
local function resetWrites()
    writes.maxVelocity = 0; writes.maxRotVelocity = 0; writes.poses = 0
    writes.primaries = 0; writes.assemblyWrites = 0
    writes.customPhysicsWrites = 0; writes.cframeWrites = 0
    writes.positions = {}
end
local passed = 0
local function pass(name) passed += 1; print("PASS", name) end
local function near(a, b, epsilon)
    assert(math.abs(a - b) <= (epsilon or 1e-6), tostring(a) .. " != " .. tostring(b))
end
'''

SCRIPT = PRELUDE + "\nlocal Module = (function()\n" + SOURCE + "\nend)()\n" + r'''
Module.init(context)
assert(options["Auto Fling Selected Target"] == nil, "Auto Fling must be gone")
assert(options["Touch Fling"] == nil, "Touch Fling moved to its own card")
assert(options["Select Target"] == nil, "the Select Target dropdown must be gone")
assert(options["Target player"] ~= nil, "Target player is the only target input")
assert(options["Fling"] ~= nil and options["Fling Murderer"] ~= nil, "actions stay")
assert(type(state.mm2PerformFling) == "function", "mm2PerformFling export must survive for Auto Win")
pass("Fling card exposes the typed target and the actions only")

-- Empty target ------------------------------------------------------------
notifications = {}
options["Fling"]()
assert(#notifications > 0 and string.find(notifications[1], "No player matched") ~= nil,
    "an empty Target player must say so instead of flinging")
pass("an empty Target player never flings")

-- The fling itself --------------------------------------------------------
victimSpeed = 0
resetWrites()
options["Target player"]("Victim")
options["Fling"]()
pump(80, function(index) if index == 10 then victimSpeed = 900 end end)

assert(writes.poses >= 6, "the six-pose YARHM choreography must run, got " .. writes.poses)
assert(writes.maxVelocity >= 8e8,
    "each pose writes 9e7/9e8 through RootPart.Velocity, got " .. tostring(writes.maxVelocity))
assert(writes.maxRotVelocity >= 8e8, "each pose writes 9e8 rotation, got " .. tostring(writes.maxRotVelocity))
assert(writes.primaries > 0, "the pose goes through SetPrimaryPartCFrame like the original")
assert(writes.cframeWrites > 0, "RootPart.CFrame is written too")
assert(writes.assemblyWrites == 0,
    "AssemblyLinearVelocity/AssemblyAngularVelocity must not be written (that is the fading bug)")
assert(writes.customPhysicsWrites == 0,
    "CustomPhysicalProperties must not be written per pose (that is the fading bug)")

local pin = nil
for _, object in ipairs(created) do
    if object.ClassName == "BodyVelocity" then pin = object end
end
assert(pin ~= nil, "the EpixVel BodyVelocity must exist")
assert(pin.Name == "EpixVel", "the pin keeps the original name")
assert(pin.Velocity ~= nil and pin.Velocity.Magnitude >= 8e8,
    "the pin must DRIVE at 9e8, not hold at zero, got " .. tostring(pin.Velocity and pin.Velocity.Magnitude))
assert(pin.MaxForce ~= nil and pin.MaxForce.Magnitude == math.huge, "the pin uses infinite MaxForce")
assert(pin.destroyed == true, "the pin must be destroyed at the end")

assert(world.FallenPartsDestroyHeight == -500, "FallenPartsDestroyHeight must be restored")
assert(humanoid.seated_Seated == true, "the Seated state must be re-enabled")
assert(math.abs(rootProps.Position.Y - 10.5) < 26, "the character comes back near where it started")
assert(activityService.flags["fling"] == false, "fling activity must be released")
pass("SkidFling poses 9e7/9e8 with an EpixVel 9e8 catapult, then restores everything")

-- cloneref: the loop must not stop because Parent ~= the module's reference ---
victimSpeed = 0
resetWrites()
notifications = {}
options["Target player"]("Victim")
options["Fling"]()
pump(60)
assert(#notifications == 0,
    "after 0.6 s the fling must still be running, got: " .. tostring(notifications[1]))
assert(writes.poses >= 12,
    "the choreography keeps going past the first pose set, got " .. writes.poses)
assert(writes.primaries >= 12, "every pose still goes through SetPrimaryPartCFrame")

-- Duration 3 s + one half-length retry: ~4.5 s of 10 ms frames.
pump(600)
assert(#notifications == 1, "exactly one notification when it ends, got " .. #notifications)
assert(string.find(notifications[1], "did not move") ~= nil,
    "a target that never moved is reported as such, got: " .. notifications[1])
assert(state.mm2LastFling and state.mm2LastFling.poses >= 12, "diagnostics are published")
assert(activityService.flags["fling"] == false, "activity released after the full run")
for _, object in ipairs(created) do
    assert(object.Name ~= "Wurst_RescueSpin" and object.Name ~= "Wurst_RescuePush",
        "the extra, non-YARHM impulse must not be applied to the target")
    if object.ClassName == "BodyAngularVelocity" or object.ClassName == "BodyVelocity" then
        assert(object.Parent == nil or object.destroyed, "no body mover may be left alive")
    end
end
pass("cloneref-safe loop reports failure without the extra rescue impulse")

-- A target without a character fails closed --------------------------------
notifications = {}
local empty = {Name="Nobody", Parent=true, Character=nil}
local failed = state.mm2PerformFling(empty, {blocking=true, silent=false, duration=0.1})
assert(failed == false, "no character must return false")
assert(#notifications == 1, "it must say why exactly once, got " .. #notifications)
assert(string.find(notifications[1], "No valid character") ~= nil,
    "and it must be the character message, not an internal error: " .. notifications[1])
assert(world.FallenPartsDestroyHeight == -500, "a failed fling must not leave the void layer off")
pass("a target without a character fails closed")

-- Per-frame export used by Auto Win ---------------------------------------
victimSpeed = 0
resetWrites()
local stepped = state.mm2FlingStep(character, humanoid, root, victimPlayer, {}, {})
assert(stepped == true, "the per-frame pose must report success")
assert(writes.maxVelocity >= 8e8, "the per-frame pose uses the same 9e7 velocity")
assert(activityService.flags["fling"] == true, "the per-frame pose marks fling activity")
local stepPin = nil
for _, object in ipairs(created) do
    if object.ClassName == "BodyVelocity" and object.destroyed == false then stepPin = object end
end
assert(stepPin ~= nil, "the per-frame pose installs its own pin")
runDelays()
assert(stepPin.destroyed == true, "the per-frame pin is cleaned up when the caller stops")
assert(activityService.flags["fling"] == false, "the per-frame fling releases its activity")
pass("the per-frame pose (Auto Win) uses the same fling and cleans up after itself")

-- Role actions outside MM2 ------------------------------------------------
local savedCore = state.mm2Core
state.mm2Core = nil
notifications = {}
options["Fling Murderer"]()
assert(#notifications == 1 and string.find(notifications[1], "Murder Mystery 2") ~= nil,
    "role actions must explain that they need MM2")
state.mm2Core = savedCore
pass("MM2 role actions degrade cleanly outside MM2")

-- A failed YARHM pose still restores the local body, pin and void setting.
notifications = {}
victimSpeed = 0
options["Retries"](0)
options["Duration"](1)
failNextPose = true
options["Target player"]("Victim")
options["Fling"]()
pump(10)
assert(#notifications == 1 and notifications[1]:find("fling failed", 1, true),
    "pose errors must be reported")
assert(world.FallenPartsDestroyHeight == -500, "void height must be restored after pose error")
assert(humanoid.seated_Seated == true and activityService.flags["fling"] == false,
    "seated state and activity must be restored after pose error")
for _, object in ipairs(created) do
    if object.Name == "EpixVel" then
        assert(object.destroyed, "a pose error must not leave the pin active")
    end
end
pass("a pose error cleans the pin and restores local state")

-- Ping prediction: the pose is written where the victim WILL be ------------
-- 300 ms of ping means the server works on a copy of the victim that is 150 ms
-- old; with Prediction 0.15 that is 0.30 s of its own velocity added to the pose.
victimSpeed = 100
networkPing = 0.3
notifications = {}
resetWrites()
options["Power"](3)
options["Prediction"](0.15)
options["Duration"](1)
options["Retries"](0)
options["Target player"]("Victim")
options["Fling"]()
pump(120)
assert(#notifications == 1, "the fling must finish, got " .. tostring(notifications[1]))
local furthest = 0
for _, position in ipairs(writes.positions) do
    if position.X > furthest then furthest = position.X end
end
assert(furthest > 22,
    "the pose must lead the victim by ~30 studs at 300 ms ping, got " .. tostring(furthest))
networkPing = 0
-- Prediction 0 still leads by half the (now zero) ping: essentially no lead.
victimSpeed = 0
pass("the pose leads the victim by half the ping plus Prediction")

-- Power scales both the pose velocity and the EpixVel pin ------------------
networkPing = 0
victimSpeed = 0
notifications = {}
resetWrites()
options["Power"](6)
options["Duration"](1)
options["Retries"](0)
local baseMax = writes.maxVelocity
options["Target player"]("Victim")
options["Fling"]()
pump(120)
assert(writes.maxVelocity >= 1.7e9,
    "Power 6 must double the 9e8 pose velocity, got " .. tostring(writes.maxVelocity))
local pinAfter = nil
for _, object in ipairs(created) do
    if object.ClassName == "BodyVelocity" and object.Name == "EpixVel"
        and object.destroyed == false then pinAfter = object end
end
-- The pin is destroyed when the fling ends; assert the scaled value was set.
local sawScaledPin = false
for _, object in ipairs(created) do
    if object.ClassName == "BodyVelocity" and object.Name == "EpixVel"
        and object.Velocity and object.Velocity.Magnitude >= 1.7e9 then
        sawScaledPin = true
    end
end
assert(sawScaledPin, "the EpixVel pin must be scaled by Power too")
options["Power"](3)
pass("Power scales the pose velocity and the pin together")

-- Retries: a victim that never moves gets a second pass ---------------------
victimSpeed = 0
notifications = {}
resetWrites()
options["Power"](3)
options["Duration"](0.5)
options["Retries"](1)
options["Prediction"](0)
options["Target player"]("Victim")
options["Fling"]()
pump(400)
assert(#notifications == 1, "one notification, got " .. tostring(#notifications))
assert(state.mm2LastFling and (state.mm2LastFling.retries or 0) >= 1,
    "a victim that did not move must trigger the second pass")
assert(writes.poses >= 24, "the second pass writes more poses, got " .. writes.poses)
options["Retries"](1)
pass("a motionless victim gets a second pass on its other part")

print("PASS " .. passed .. " SkidFling suites")
'''

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "fling_skid.luau"
    script.write_text(SCRIPT)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
