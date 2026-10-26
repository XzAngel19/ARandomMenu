#!/usr/bin/env python3
"""Exercise the real shared Fling controller with deterministic physics mocks.

These tests cover ownership, contact gating, pulse timing and cleanup only.
They do not prove server-side knockback, damage, kills, coins or wins.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/libraries/Fling.lua").read_text()
MM2_SOURCE = (ROOT / "src/games/MM2/Blatant/Fling.lua").read_text()
TOUCH_SOURCE = (ROOT / "src/games/universal/Blatant/TouchFling.lua").read_text()

# No global/deprecated legacy mechanism is hidden in the replacement.
for forbidden in (
    "SetNetworkOwner", "FallenPartsDestroyHeight", "CameraSubject",
    "BodyVelocity", "BodyGyro", "9e7", "9e8", "12000",
):
    assert forbidden not in SOURCE, forbidden

script = PRELUDE + r'''
local cfMt = {}
cfMt.__index = cfMt
cfMt.__mul = function(a,b) return CFrame.new(a.Position + b.Position) end
CFrame = {}
function CFrame.new(x,y,z)
    local p = if type(x) == "table" then x else Vector3.new(x or 0,y or 0,z or 0)
    return setmetatable({Position=p,LookVector=Vector3.new(0,0,-1)},cfMt)
end
function CFrame.lookAt(p,q)
    local result = CFrame.new(p)
    result.LookVector = (q-p).Unit
    return result
end
CFrame.Angles = function() return CFrame.new() end
Enum.HumanoidStateType = {Seated="Seated",Physics="Physics",GettingUp="GettingUp"}

local oldTypeof = typeof
function typeof(value)
    if type(value) == "table" and value._instance then return "Instance" end
    return oldTypeof(value)
end

local function signal()
    local s = {callbacks={}}
    function s:Connect(fn)
        local c = {Connected=true,fn=fn}
        function c:Disconnect() self.Connected=false end
        table.insert(self.callbacks,c)
        return c
    end
    function s:Fire(...)
        for _,c in ipairs(self.callbacks) do
            if c.Connected then c.fn(...) end
        end
    end
    return s
end
local function liveConnections(s)
    local count = 0
    for _,c in ipairs(s.callbacks) do
        if c.Connected then count += 1 end
    end
    return count
end

local function adopt(child,parent)
    child.Parent = parent
    if parent then table.insert(parent.children,child) end
    return child
end
local function instance(class,parent)
    local o = {ClassName=class,children={},_instance=true}
    function o:IsA(c)
        return c == self.ClassName or (c == "BasePart" and self.ClassName == "Part")
            or (c == "Model" and self.ClassName == "Model")
    end
    function o:FindFirstChildOfClass(c)
        for _,child in ipairs(self.children) do
            if child.ClassName == c then return child end
        end
        return nil
    end
    function o:FindFirstChild(name)
        for _,child in ipairs(self.children) do
            if child.Name == name then return child end
        end
        return nil
    end
    function o:GetChildren() return self.children end
    function o:GetDescendants()
        local result = {}
        local function walk(node)
            for _,child in ipairs(node.children) do
                table.insert(result,child)
                walk(child)
            end
        end
        walk(self)
        return result
    end
    function o:PivotTo(frame)
        self.pivotCalls = (self.pivotCalls or 0) + 1
        local root = self:FindFirstChild("HumanoidRootPart")
        root.CFrame = frame
        root.Position = frame.Position
    end
    function o:Destroy()
        self.Parent = nil
        self.destroyed = true
    end
    o.Touched = signal()
    o.Died = signal()
    o.DescendantAdded = signal()
    if parent then adopt(o,parent) end
    return o
end

local function makeRig(name,position)
    local character = instance("Model")
    character.Name = name
    local humanoid = instance("Humanoid",character)
    humanoid.Name = "Humanoid"
    humanoid.Health = 100
    humanoid.AutoRotate = true
    humanoid.Sit = false
    humanoid.seated = true
    function humanoid:GetStateEnabled(state) return self.seated end
    function humanoid:SetStateEnabled(state,value) self.seated = value end
    function humanoid:ChangeState(state) self.lastState = state end
    local root = instance("Part",character)
    root.Name = "HumanoidRootPart"
    root.Size = Vector3.new(2,2,1)
    root.CanCollide = false
    root.CanTouch = false
    root.Anchored = false
    root.Position = position
    root.CFrame = CFrame.new(position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    humanoid.RootPart = root
    local body = instance("Part",character)
    body.Name = "UpperTorso"
    body.CanCollide = true
    body.CanTouch = false
    body.Position = position
    body.CFrame = CFrame.new(position)
    body.AssemblyLinearVelocity = Vector3.zero
    body.AssemblyAngularVelocity = Vector3.zero
    return character,humanoid,root,body
end

local localCharacter,humanoid,root,body = makeRig("Local",Vector3.new(0,10,0))
local targetCharacter,targetHumanoid,targetRoot = makeRig("Target",Vector3.new(0,10,-4))
localCharacter.Parent = true
targetCharacter.Parent = true
local LocalPlayer = {Character=localCharacter,CharacterAdded=signal()}
local target = {Character=targetCharacter,Parent=true}
local Players = {}
target.Parent = Players
function Players:GetPlayerFromCharacter(character)
    if character == localCharacter then return LocalPlayer end
    if character == targetCharacter then return target end
    return nil
end
local PreSimulation,PostSimulation,Heartbeat = signal(),signal(),signal()
local activityValue = false
local activity = {set=function(name,value)
    assert(name == "fling")
    activityValue = value
end}
local RunService = {PreSimulation=PreSimulation,PostSimulation=PostSimulation,Heartbeat=Heartbeat}
local host = {RunService=RunService,Players=Players,LocalPlayer=LocalPlayer}
local Module = (function()
'''+SOURCE+r'''
end)()
local physics = Module.init({host=host,services={activity=activity}})
assert(liveConnections(PreSimulation) == 0 and liveConnections(Heartbeat) == 0,
    "Fling must not connect physics signals while OFF")
local function sameVector(a,b)
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
local function closeVector(a,b,epsilon)
    return (a-b).Magnitude <= (epsilon or 0.001)
end

-- Directed contact is placed once, then pulsed without a per-frame CFrame writer.
local home = root.CFrame
local originalLinear = Vector3.new(4,0,0)
local originalAngular = Vector3.new(1,0,0)
root.AssemblyLinearVelocity = originalLinear
root.AssemblyAngularVelocity = originalAngular
assert(physics.start(target,{duration=1.4}))
assert(localCharacter.pivotCalls == 1,"one directed contact placement")
assert(not physics.start(target,{duration=1.4}),"one directed owner")
PreSimulation:Fire()
assert(localCharacter.pivotCalls == 1,"no directed contact teleport per tick")
assert(root.AssemblyLinearVelocity.Magnitude <= 20000,"finite directed pulse cap")
assert(root.AssemblyAngularVelocity.Magnitude <= 10000,"finite directed angular cap")
PostSimulation:Fire()
assert(not sameVector(root.AssemblyLinearVelocity,originalLinear),
    "pulse survives PostSimulation for physics/replication")
Heartbeat:Fire()
assert(sameVector(root.AssemblyLinearVelocity,originalLinear),"Heartbeat restores linear")
assert(sameVector(root.AssemblyAngularVelocity,originalAngular),"Heartbeat restores angular")
physics.cancel()
assert(not physics.isRunning() and not activityValue)
assert(liveConnections(PreSimulation) == 0 and liveConnections(Heartbeat) == 0,
    "directed cleanup disconnects signals")
assert(closeVector(root.Position,home.Position),"cancel returns home")
assert(sameVector(root.AssemblyLinearVelocity,Vector3.zero),"cancel stops local motion")
assert(body.CanCollide == true and body.CanTouch == false and humanoid.AutoRotate == true,
    "directed snapshots restored")
pass("directed contact pulse, one placement, Heartbeat restore and cleanup")

-- Death and target loss cancel without a delayed action.
humanoid.Health = 100
assert(physics.start(target,{duration=1.4}))
humanoid.Health = 0
PreSimulation:Fire()
Heartbeat:Fire()
assert(not physics.isRunning() and not activityValue,"death cancels")
humanoid.Health = 100
assert(physics.start(target,{duration=1.4}))
targetHumanoid.Health = 0
PreSimulation:Fire()
Heartbeat:Fire()
assert(not physics.isRunning(),"target death cancels")
targetHumanoid.Health = 100
pass("local death and target death cancel sessions")

-- Touch mode only pulses on recent contact and never pivots the character.
root.CFrame = CFrame.new(Vector3.new(0,10,0))
root.Position = Vector3.new(0,10,0)
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero
physics.setTouchEnabled(true)
assert(physics.isTouchEnabled() and activityValue)
assert(liveConnections(PreSimulation) == 1 and liveConnections(Heartbeat) == 1,
    "Touch owns signals only while enabled")
PreSimulation:Fire()
assert(sameVector(root.AssemblyLinearVelocity,Vector3.zero),"no contact no pulse")
local beforeTouch = root.Position
root.Touched:Fire(targetRoot)
PreSimulation:Fire()
assert(root.AssemblyLinearVelocity.Magnitude <= 20000,"finite touch pulse cap")
assert(root.AssemblyLinearVelocity.Magnitude > 0,"contact produces a pulse")
assert(closeVector(root.Position,beforeTouch),"touch does not teleport")
PostSimulation:Fire()
assert(root.AssemblyLinearVelocity.Magnitude > 0,"touch pulse crosses PostSimulation")
Heartbeat:Fire()
assert(sameVector(root.AssemblyLinearVelocity,Vector3.zero),"touch restores after Heartbeat")
physics.setTouchEnabled(false)
assert(not physics.isTouchEnabled() and not activityValue)
assert(body.CanCollide == true and body.CanTouch == false and root.CanTouch == false,
    "Touch collision and CanTouch snapshots restored")
assert(liveConnections(PreSimulation) == 0 and liveConnections(Heartbeat) == 0,
    "Touch OFF disconnects signals")
PreSimulation:Fire()
assert(sameVector(root.AssemblyLinearVelocity,Vector3.zero),"OFF is inert")
pass("touch requires contact, is bounded, non-teleporting and OFF-safe")

-- Exercise the actual universal card wiring, not only the library API.
local universalState = {flingPhysics=physics,toggleControls={}}
host.state = universalState
host.configData = {states={}}
host.addFeatureTooltip = function() end
local touchCard = nil
host.createUniversalFeature = function(_name,_description,_order,callback,_config)
    touchCard = {onToggle=callback}
    function touchCard:SetStatus(value) self.status=value end
    return touchCard
end
local TouchModule = (function()
'''+TOUCH_SOURCE+r'''
end)()
TouchModule.init({host=host})
assert(type(universalState.setTouchFlingEnabled) == "function")
touchCard.onToggle(true)
assert(physics.isTouchEnabled() and touchCard.status == "ON",
    "universal Touch card enables the shared controller")
touchCard.onToggle(false)
assert(not physics.isTouchEnabled(),"universal Touch card disables the controller")
TouchModule.destroy()
pass("universal Touch card wires ON/OFF and cleanup")

-- Destroy disconnects signals and restores any active Touch pulse.
physics.setTouchEnabled(true)
root.Touched:Fire(targetRoot)
PreSimulation:Fire()
physics.destroy()
Heartbeat:Fire()
assert(not physics.isTouchEnabled() and not activityValue)
assert(sameVector(root.AssemblyLinearVelocity,Vector3.zero),"destroy restores pulse")
local saved = root.AssemblyLinearVelocity
PreSimulation:Fire()
assert(sameVector(root.AssemblyLinearVelocity,saved),"destroy disconnects PreSimulation")
pass("destroy cleans touch resources and signal ownership")
'''

script += r'''
-- MM2 wrapper guards and blocking contract, using the real module next.
local roundActive = false
state = {
    flingPhysics=nil,
    mm2Core=nil,
    frameworkEnvironment=nil,
    clearRoleMemo=function() end,
    setTouchFlingEnabled=function(on) physics.setTouchEnabled(on) end,
}
services = {
    protectedTargets={isProtected=function() return false end},
    gameBridge={playerRole=function() return "Innocent" end},
    activity=activity,
}
mm2Features = {}
local core = {
    isRoundLifecycleActive=function() return roundActive end,
    findMM2Map=function() return true end,
    isPlayerAlive=function(player)
        if player == LocalPlayer then return humanoid.Health > 0 end
        return targetHumanoid.Health > 0
    end,
    getPlayerWeapon=function() return nil end,
    getPlayerRole=function() return "Innocent" end,
    findMurderer=function() return target end,
    findSheriff=function() return target end,
    requestRoleRefresh=function() end,
}
host.getCharacterParts=function() return localCharacter,humanoid,root end
host.notify=function() end
host.findPlayerByText=function() return target end
host.configData={states={}}
host.featureConnections={}
host.disconnectFeatureConnection=function(key)
    local connection=host.featureConnections[key]
    if connection then connection:Disconnect();host.featureConnections[key]=nil end
end
host.TaskManager={Connect=function(_,callback)
    return {Disconnect=function() end}
end}
host.createUniversalFeature=function(_name,_description,_order,callback,_config)
    return {SetStatus=function() end,onToggle=callback}
end
host.addActionOption=function() end
host.addTextOption=function() end
host.addInformationOption=function() end
host.addToggleOption=function() end
Players.GetPlayers=function() return {LocalPlayer,target} end
LocalPlayer.Name="Local"
target.Name="Target"
state.mm2Core=core
state.frameworkEnvironment=host
physics = Module.init({host=host,services={activity=activity}})
state.flingPhysics=physics
local MM2Module = (function()
'''+MM2_SOURCE+r'''
end)()
MM2Module.init({})
assert(type(state.mm2PerformFling)=="function")
assert(not state.mm2PerformFling(target,{silent=true}),"lobby rejected")
assert(not physics.isRunning())
roundActive=true
humanoid.Health=0
assert(not state.mm2PerformFling(target,{silent=true}),"dead local rejected")
assert(not physics.isRunning())
humanoid.Health=100
assert(not state.mm2PerformFling(LocalPlayer,{silent=true}),"self target rejected")
assert(state.mm2PerformFling(target,{silent=true}),"valid round target starts")
assert(not state.mm2PerformFling(target,{silent=true}),"second session rejected")
physics.cancel()
assert(not physics.isRunning())
pass("MM2 wrapper rejects lobby, death and self target and deduplicates sessions")

-- task.wait advances the fake clock and pumps Pre/Post/Heartbeat.
task = {wait=function(dt)
    now += (dt or 1/60)
    PreSimulation:Fire()
    PostSimulation:Fire()
    Heartbeat:Fire()
end,spawn=function(fn,...) return fn(...) end}
localCharacter.pivotCalls = 0
assert(state.mm2PerformFling(target,{
    silent=true,blocking=true,duration=0.1,restorePosition=false,
}))
assert(not physics.isRunning(),"blocking waits for bounded session")
assert(localCharacter.pivotCalls == 1,
    "Auto Farm path has one live contact placement and no cancellation return")
assert(sameVector(root.AssemblyLinearVelocity,Vector3.zero),"blocking return stops velocity")
MM2Module.destroy()
assert(state.mm2PerformFling==nil,"MM2 cleanup removes export")
physics.destroy()
pass("MM2 blocking cancellation and destroy cleanup")
'''

with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as handle:
    handle.write(script)
    path = handle.name
try:
    result = subprocess.run(
        [os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau")), path],
        text=True, capture_output=True,
    )
    print(result.stdout, end="")
    if result.returncode:
        print(result.stderr, end="")
        raise SystemExit(result.returncode)
finally:
    os.unlink(path)
