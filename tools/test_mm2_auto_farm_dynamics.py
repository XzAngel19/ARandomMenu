#!/usr/bin/env python3
"""Run the real Auto Farm module against deterministic Roblox-shaped mocks.

This checks local movement ownership and lifecycle/idempotence only. It does
not assert server collection, damage, kills or wins.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/AutoFarm.lua").read_text()

script = PRELUDE + r'''
local cfMt = {}
cfMt.__index = cfMt
cfMt.__add = function(a,b) return CFrame.new(a.Position+b) end
cfMt.__mul = function(a,b) return CFrame.new(a.Position+b.Position) end
CFrame = {}
function CFrame.new(x,y,z)
    local p = if type(x) == "table" then x else Vector3.new(x or 0,y or 0,z or 0)
    return setmetatable({Position=p,LookVector=Vector3.new(0,0,-1)},cfMt)
end
CFrame.Angles = function() return CFrame.new() end
CFrame.lookAt = function(p) return CFrame.new(p) end
Enum.HumanoidStateType = {GettingUp="GettingUp",Running="Running"}
Enum.ActuatorRelativeTo = {World="World"}
Enum.VelocityConstraintMode = {Vector="Vector"}
Enum.OrientationAlignmentMode = {OneAttachment="OneAttachment"}
Enum.Material = {SmoothPlastic="SmoothPlastic"}
Enum.RaycastFilterType = {Exclude="Exclude"}

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
local function adopt(child,parent)
    child.Parent = parent
    return child
end
local function newInst(class,parent)
    local o = {ClassName=class,Name=class,children={},_instance=true,CanCollide=false,
        CanTouch=true,Transparency=0,Anchored=false,attributes={}}
    function o:IsA(c)
        return c == self.ClassName or (c == "BasePart" and self.ClassName == "Part")
            or (c == "Model" and self.ClassName == "Model")
    end
    function o:FindFirstChild(name,_recursive)
        for _,child in ipairs(self.children) do
            if child.Name == name then return child end
        end
        return nil
    end
    function o:FindFirstChildOfClass(className)
        for _,child in ipairs(self.children) do
            if child.ClassName == className then return child end
        end
        return nil
    end
    function o:FindFirstChildWhichIsA(className,recursive)
        for _,child in ipairs(self.children) do
            if child:IsA(className) then return child end
            if recursive then
                local found = child:FindFirstChildWhichIsA(className,true)
                if found then return found end
            end
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
    function o:GetAttribute(name) return self.attributes[name] end
    function o:SetAttribute(name,value) self.attributes[name]=value end
    function o:GetPivot()
        local root = self:FindFirstChild("HumanoidRootPart")
        return root and root.CFrame or CFrame.new()
    end
    function o:PivotTo(frame)
        self.pivotCount = (self.pivotCount or 0) + 1
        local root = self:FindFirstChild("HumanoidRootPart")
        if root then root.CFrame=frame;root.Position=frame.Position end
    end
    function o:Destroy()
        local old = rawget(self,"Parent")
        if old and old.children then
            for i,child in ipairs(old.children) do
                if child == self then table.remove(old.children,i);break end
            end
        end
        rawset(self,"Parent",nil)
        self.destroyed=true
    end
    o.DescendantAdded = signal()
    local mt = {}
    mt.__newindex = function(self,key,value)
        if key == "Parent" then
            local old = rawget(self,"Parent")
            if old and old.children then
                for i,child in ipairs(old.children) do
                    if child == self then table.remove(old.children,i);break end
                end
            end
            rawset(self,"Parent",value)
            if value and value.children then table.insert(value.children,self) end
        else
            rawset(self,key,value)
        end
    end
    setmetatable(o,mt)
    if parent then adopt(o,parent) end
    return o
end
Instance = {new=function(class,parent) return newInst(class,parent) end}

local workspace = newInst("Workspace")
workspace.FallenPartsDestroyHeight = -500
local map = newInst("Model",workspace)
map.Name = "Map"
local spawns = newInst("Folder",map)
spawns.Name = "Spawns"
local spawn = newInst("Part",spawns)
spawn.Position = Vector3.new(0,10,0)
spawn.CFrame = CFrame.new(spawn.Position)
local coin = newInst("Part",map)
coin.Name = "Coin_Server"
coin.Position = Vector3.new(0,20,0)
coin.CFrame = CFrame.new(coin.Position)
coin.Size = Vector3.new(1.2,2,2)
local coins = {coin}

local character = newInst("Model",workspace)
character.Name = "Character"
local humanoid = newInst("Humanoid",character)
humanoid.Name = "Humanoid"
humanoid.Health = 100
humanoid.WalkSpeed = 16
humanoid.PlatformStand = false
humanoid.AutoRotate = true
humanoid.Sit = false
humanoid.moveCount = 0
function humanoid:Move(direction,_relative)
    self.moveCount += 1
    self.lastMove = direction
end
function humanoid:MoveTo(_destination)
    error("MoveTo must not be a duplicate Walk writer")
end
function humanoid:ChangeState(state) self.lastState=state end
function humanoid:EquipTool(_tool) end
local root = newInst("Part",character)
root.Name = "HumanoidRootPart"
root.Position = Vector3.new(0,10,0)
root.CFrame = CFrame.new(root.Position)
root.Size = Vector3.new(2,2,1)
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero
humanoid.RootPart = root
local torso = newInst("Part",character)
torso.Name = "UpperTorso"
torso.Position = root.Position
torso.CFrame = root.CFrame
torso.Size = Vector3.new(2,2,1)
local LocalPlayer = {Name="Local",Character=character}
local Players = {GetPlayers=function() return {LocalPlayer} end}
local function getCharacterParts() return character,humanoid,root end
local function setRootPosition(position)
    root.Position = position
    root.CFrame = CFrame.new(position)
end

local roundActive = true
local phaseListener = nil
local remote = newInst("RemoteEvent")
remote.Name = "CoinCollected"
remote.OnClientEvent = signal()
local remotes = newInst("Folder")
adopt(remote,remotes)
local core = {
    getPlayerRole=function() return "Innocent" end,
    getPlayerWeapon=function() return nil end,
    isPlayerAlive=function() return humanoid.Health > 0 end,
    findMurderer=function() return nil end,
    findSheriff=function() return nil end,
    findDroppedGun=function() return nil end,
    isRoundLifecycleActive=function() return roundActive end,
    findMM2Map=function() return map end,
    getEstimatedLatency=function() return 0.05 end,
    getGunOriginCFrame=function() return nil end,
    onRoundPhase=function(listener)
        phaseListener=listener
        return function() phaseListener=nil end
    end,
    mm2GameplayRemotes=remotes,
}
local touchCount = 0
local state = {
    mm2Core=core,
    mm2CoinPickups=function() return coins end,
    fireTouchInterest=function() touchCount += 1 end,
    valueControls={},toggleControls={},
    addSectionOption=function() end,
    addStatOption=function() return {set=function() end} end,
}
local featureConnections = {}
local function disconnectFeatureConnection(key)
    local connection = featureConnections[key]
    if connection then
        connection:Disconnect()
        featureConnections[key]=nil
    end
end
local farmTick = nil
local TaskManager = {}
function TaskManager:Connect(callback)
    farmTick=callback
    return {Disconnect=function() if farmTick==callback then farmTick=nil end end}
end
local Stepped,PreSimulation = signal(),signal()
local RunService = {Stepped=Stepped,PreSimulation=PreSimulation}
local optionCallbacks = {}
local farmFeature = {status=nil}
function farmFeature:SetStatus(value) self.status=value end
local farmToggle = nil
local function createUniversalFeature(_name,_description,_order,callback,_config)
    farmToggle=callback
    return farmFeature
end
local function addCycleOption(_feature,name,_values,_default,callback)
    optionCallbacks[name]=callback
end
local function addNumberOption() end
local function addToggleOption(_feature,name,_default,callback)
    optionCallbacks[name]=callback
end
local function addInformationOption() end
local function notify() end
local MM2Scroll = nil
local mm2Features = {}
local task = {spawn=function(fn,...) return fn(...) end,wait=function(dt) now += (dt or 1/60) end,delay=function() end}

local Module = (function()
'''+SOURCE+r'''
end)()
Module.init({})
assert(farmToggle and farmTick == nil,"feature is built before enable")
optionCallbacks["Farm Mode"]("Below (Hitbox)")
optionCallbacks["Reset When Full Coin Bag"](false)
optionCallbacks["Safe Zone"](false)

local function tick(dt)
    now += (dt or 1/60)
    assert(farmTick,"farm tick connected")
    farmTick(dt or 1/60)
end
local function pre(dt)
    PreSimulation:Fire(dt or 1/60)
end
local function farmLV()
    return root:FindFirstChild("WurstAutoFarmLV")
end

-- Below selects one fixed destination and writes no CFrame in PreSimulation.
now = 1
farmToggle(true)
tick(1/60)
local afterEngage = root.Position
local pivotsAfterEngage = character.pivotCount or 0
pre(1/60)
local lv = farmLV()
assert(lv and lv.VectorVelocity.Y > 0,"below constraint drives contact destination")
assert(lv.VelocityConstraintMode == "Vector" and lv.RelativeTo == "World","world vector constraint")
assert(root.Position == afterEngage,"PreSimulation does not snap CFrame")
setRootPosition(Vector3.new(0,17,0))
tick(1/60)
pre(1/60)
lv = farmLV()
assert(lv and lv.VectorVelocity.Magnitude == 0,"fixed contact height is stationary")
local settledPivots = character.pivotCount or 0
for _=1,4 do tick(1/60);pre(1/60) end
assert((character.pivotCount or 0) == settledPivots,"no per-tick CFrame writer")
assert(farmLV().VectorVelocity.Magnitude == 0,"no vertical oscillation at contact")

-- Losing the target after farming holds the current pose, not an old anchor.
coins = {}
now += 1
tick(1/60)
pre(1/60)
local heldPosition = root.Position
for _=1,4 do tick(1/60);pre(1/60) end
assert(root.Position == heldPosition,"target loss holds stationary")
assert(farmLV().VectorVelocity.Magnitude == 0,"hold uses zero constraint velocity")
pass("Below fixed contact, no per-tick CFrame and stationary target loss")

-- Death is cleanup-only; no coin pulse, teleport or new constraint.
coins = {coin}
now += 1
tick(1/60)
pre(1/60)
local beforeDeathPivots = character.pivotCount or 0
local beforeDeathTouches = touchCount
humanoid.Health = 0
tick(1/60)
pre(1/60)
assert((character.pivotCount or 0) == beforeDeathPivots,"dead farm does not teleport")
assert(touchCount == beforeDeathTouches,"dead farm does not collect")
assert(farmLV() == nil,"dead farm destroys constraints")
pass("death blocks farm actions and restores constraints")

-- Lobby/ended round is also inert, even with a full-bag report.
humanoid.Health = 100
roundActive = false
remote.OnClientEvent:Fire(nil,50,50)
local beforeLobbyPivots = character.pivotCount or 0
local beforeLobbyTouches = touchCount
tick(1/60)
pre(1/60)
assert((character.pivotCount or 0) == beforeLobbyPivots,"lobby does not teleport")
assert(touchCount == beforeLobbyTouches,"lobby does not act on full bag")
assert(farmLV() == nil,"lobby leaves no constraints")
pass("lobby and ended-round guards ignore full-bag actions")

-- A live full bag is handled once; repeated OFF/ON does not repeat it.
roundActive = true
coins = {coin}
now += 1
tick(1/60)
pre(1/60)
remote.OnClientEvent:Fire(nil,50,50)
local beforeFullPivots = character.pivotCount or 0
tick(1/60)
local afterFullPivots = character.pivotCount or 0
assert(afterFullPivots > beforeFullPivots,"live full bag performs its one return")
local fullTouches = touchCount
for _=1,3 do
    farmToggle(false)
    farmToggle(true)
    tick(1/60)
    pre(1/60)
end
assert((character.pivotCount or 0) == afterFullPivots,"OFF/ON full bag is idempotent")
assert(touchCount == fullTouches,"OFF/ON does not resume full-bag actions")
assert(farmLV() == nil,"handled full bag leaves no movement owner")
pass("50/50 repeated toggles do not repeat terminal actions")

farmToggle(false)
Module.destroy()
assert(farmTick == nil,"cleanup disconnects tick")
print("PASS Auto Farm dynamic cleanup and round listener")
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
