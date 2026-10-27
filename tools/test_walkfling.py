#!/usr/bin/env python3
"""Execute the real Walk Fling module (the Infinite Yield walkfling card).

The pulse was approved by the user; what is asserted here is the contract:
  - it never runs on injection (the persisted state is dropped),
  - OFF does nothing at all,
  - ON produces the 10000x velocity spike and the noclip the card promises,
  - OFF/destroy restore the original CanCollide and park the velocity,
  - Fling no longer owns a Touch Fling option (it moved here).
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Blatant/WalkFling.lua").read_text()
FLING = (ROOT / "src/games/MM2/Blatant/Fling.lua").read_text()
MANIFEST = (ROOT / "src/libraries/Manifest.lua").read_text()
LOADER = (ROOT / "src/Wurst.lua").read_text()

PRELUDE = r'''
local Vector3 = {}
local mt = {}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
Vector3.zero = Vector3.new(0,0,0)
mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul=function(a,b)
    if type(a)=="number" then a,b=b,a end
    return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
mt.__index=function(a,k)
    if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
end
local Enum = {Material={Air="Air"},HumanoidStateType={Seated="Seated"}}

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
}

local writes = {maxSpeed=0, spins=0}
local collisionFalse, collisionTrue = 0, 0
local function makePart(name, canCollide)
    local props = {Name=name, Parent=true, CanCollide=canCollide, Position=Vector3.new(0, 10, 0)}
    props.IsA = function(_, class) return class == "BasePart" end
    return setmetatable({}, {__index=props, __newindex=function(_, key, value)
        if key == "CanCollide" then
            if value == false then collisionFalse += 1 elseif value == true then collisionTrue += 1 end
        end
        props[key] = value
    end})
end
local rootProps = {Name="HumanoidRootPart", Parent=true, CanCollide=true, Position=Vector3.new(0, 10, 0),
    AssemblyLinearVelocity=Vector3.zero, Velocity=Vector3.zero, AssemblyAngularVelocity=Vector3.zero}
rootProps.IsA = function(_, class) return class == "BasePart" end
local root = setmetatable({}, {__index=rootProps, __newindex=function(_, key, value)
    if (key == "AssemblyLinearVelocity" or key == "Velocity") and type(value) == "table" then
        local magnitude = math.sqrt(value.X*value.X + value.Y*value.Y + value.Z*value.Z)
        if magnitude > writes.maxSpeed then writes.maxSpeed = magnitude end
    end
    if key == "AssemblyAngularVelocity" and type(value) == "table" then
        writes.spins += 1
    end
    rootProps[key] = value
end})
local arm = makePart("LeftArm", true)
local leg = makePart("RightLeg", true)
local parts = {root, arm, leg}
local humanoid = {Health=100, RootPart=root, WalkSpeed=16}
local character = {Parent=true}
function character:GetChildren() return parts end
function character:FindFirstChild(name)
    for _, part in ipairs(parts) do if part.Name == name then return part end end
    return nil
end
function character:FindFirstChildOfClass(class)
    if class == "Humanoid" then return humanoid end
    return nil
end

local configData = {states={["Universal.WalkFling"]=true}, values={}}
local activity = {}
local feature = nil
local options = {}
local host = {
    LocalPlayer={Name="Local", Character=character},
    RunService=RunService,
    workspace={},
    configData=configData,
    createUniversalFeature=function(name, description, _order, onToggle, configuration)
        feature = {name=name, description=description, toggle=onToggle, options={},
            SetStatus=function(self, status) self.status = status end}
        return feature
    end,
    addNumberOption=function(_feature, name, default, minimum, maximum, callback)
        options[name] = callback
        options["__default_" .. name] = default
    end,
    addFeatureTooltip=function() end,
}
local context = {
    host=host,
    services={activity={set=function(name, value) activity[name] = value end}},
}
local function resetWrites() writes.maxSpeed = 0; writes.spins = 0; collisionFalse = 0; collisionTrue = 0 end
local passed = 0
local function pass(name) passed += 1; print("PASS", name) end
'''

SCRIPT = PRELUDE + "\nlocal Module = (function()\n" + SOURCE + "\nend)()\n" + r'''
Module.init(context)

assert(configData.states["Universal.WalkFling"] == false,
    "a saved ON state must never start a fling on injection")
assert(feature.name == "Walk Fling", "the card is Walk Fling")
assert(options["Power"] ~= nil, "the card exposes Power")

resetWrites()
pump(15)
assert(writes.maxSpeed == 0, "nothing runs while the card is OFF")
assert(collisionFalse == 0, "nothing is noclipped while the card is OFF")
assert(activity["walkfling"] == nil, "no activity flag while OFF")
pass("Walk Fling is inert on injection and while OFF")

feature.toggle(true)
pump(12)
assert(writes.maxSpeed >= 9999, "the IY walkfling spike must run, got " .. tostring(writes.maxSpeed))
assert(collisionFalse > 0, "the walkfling noclip must run while ON")
assert(activity["walkfling"] == true, "the card marks its activity")
pass("Walk Fling ON runs the 10000x pulse and the noclip")

options["Power"](50000)
resetWrites()
pump(10)
assert(writes.maxSpeed >= 49999, "Power must scale the spike, got " .. tostring(writes.maxSpeed))
options["Power"](10000)
pass("Power scales the spike")

feature.toggle(false)
pump(12)
assert(collisionFalse > 0 and collisionTrue > 0, "stopping must restore the original CanCollide")
assert(activity["walkfling"] == false, "the activity flag is released")
local parked = writes.maxSpeed
resetWrites()
pump(12)
assert(writes.maxSpeed == 0, "no frame work after OFF")
pass("Walk Fling OFF restores collisions and stops the loop")

feature.toggle(true)
pump(8)
resetWrites()
Module.destroy()
pump(12)
assert(collisionTrue > 0, "destroy while ON must restore collisions")
assert(writes.maxSpeed < 9999, "destroy must not re-apply the spike, got " .. tostring(writes.maxSpeed))
assert(rootProps.AssemblyLinearVelocity.Magnitude < 1, "the body must be parked after destroy")
pass("destroy while ON restores the character")

print("PASS " .. passed .. " Walk Fling suites")
'''

assert '"Touch Fling"' not in FLING, "Fling must not own Touch Fling any more"
assert "startTouchFlingLoop" not in FLING, "the walkfling loop moved out of Fling"
assert "universal/Blatant/WalkFling.lua" in MANIFEST, "Walk Fling must be in the manifest"
assert "universal/Movement/AntiFling.lua" in MANIFEST, "Anti Fling must be its own module"
assert 'name = "Walk Fling"' in LOADER, "Walk Fling must be in the loader fallback manifest"
assert 'name = "Anti Fling"' in LOADER, "Anti Fling must be in the loader fallback manifest"

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "walkfling.luau"
    script.write_text(SCRIPT)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
