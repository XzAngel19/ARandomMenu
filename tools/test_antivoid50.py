#!/usr/bin/env python3
"""Execute the real Anti Void (invisible platform) and Anti Fling modules.

Anti Void: one local anchored part, `Distance` studs under the character, kept in
place while falling so the fall lands on it, ignoring every raycast and touch.
Anti Fling: every frame removes fling-sized planar speed, rise, fall and spin
while keeping the player's own input, and never fights our own flings.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANTIVOID = (ROOT / "src/games/universal/Movement/AntiVoid.lua").read_text()
ANTIFLING = (ROOT / "src/games/universal/Movement/AntiFling.lua").read_text()

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
    if k=="Unit" then return a/a.Magnitude end
end
mt.__div=function(a,b) return a*(1/b) end
local CFrame = {new=function(x, y, z)
    if type(x) == "table" then return {Position=x} end
    return {Position=Vector3.new(x or 0, y or 0, z or 0)}
end}
local Enum = {SurfaceType={Smooth="Smooth"},Material={Air="Air"},HumanoidStateType={Seated="Seated"}}

local objects = {}
local Instance = {new=function(class)
    local object = {ClassName=class, Name=class, Parent=nil, destroyed=false}
    function object:Destroy() self.destroyed = true; self.Parent = nil end
    table.insert(objects, object)
    return object
end}

local tick, feature, options
local humanoid = {Health=100, WalkSpeed=16, JumpPower=50, MoveDirection=Vector3.zero, FloorMaterial="Ground"}
local rootProps = {Position=Vector3.new(0, 100, 0), Parent=true,
    AssemblyLinearVelocity=Vector3.zero, AssemblyAngularVelocity=Vector3.zero, Anchored=false}
local root = setmetatable({}, {__index=rootProps, __newindex=function(_, key, value) rootProps[key] = value end})
local character = {Parent=true}
local world = {FallenPartsDestroyHeight=-500}
local host = {
    workspace=world,
    getCharacterParts=function() return character, humanoid, root end,
    featureConnections={},
    TaskManager={Connect=function(_, fn)
        tick = fn
        return {Disconnect=function() tick = nil end}
    end},
    createUniversalFeature=function(name, description, order, onToggle, configuration)
        feature = {name=name, description=description, order=order, toggle=onToggle,
            configuration=configuration, options={}}
        return feature
    end,
    addToggleOption=function(_feature, name, default, callback) options[name] = callback end,
    addNumberOption=function(_feature, name, default, minimum, maximum, callback)
        options[name] = callback
        options["__default_" .. name] = default
    end,
    addFeatureTooltip=function(_feature, text) feature.tooltip = text end,
}
host.disconnectFeatureConnection = function(key)
    local connection = host.featureConnections[key]
    if connection then connection:Disconnect(); host.featureConnections[key] = nil end
end
local activityFlags = {}
local context = {
    host=host,
    framework={GetModule=function() return nil end},
    services={activity={
        isActive=function(name) return activityFlags[name] == true end,
        set=function(name, value) activityFlags[name] = value end,
    }},
}
local passed = 0
local function pass(name) passed += 1; print("PASS", name) end
local function near(a, b, epsilon)
    assert(math.abs(a - b) <= (epsilon or 1e-6), tostring(a) .. " != " .. tostring(b))
end
'''

SCRIPT = PRELUDE + "\nlocal AntiVoid = (function()\n" + ANTIVOID + "\nend)()\n" + r'''
-- Anti Void: the invisible platform -----------------------------------------
options = {}
AntiVoid.init(context)
assert(feature.name == "Anti Void", "the card is Anti Void")
assert(feature.configuration.categoryName == "Utilities", "Anti Void lives in Utilities")
assert(feature.options["Anti fling"] == nil, "Anti Fling is not a sub-option any more")
assert(options["Distance"] ~= nil, "Distance is configurable")

tick = nil
feature.toggle(true)
assert(type(tick) == "function", "Anti Void owns its frame step")

local platform = nil
for _, object in ipairs(objects) do
    if object.ClassName == "Part" and object.Name == "Wurst_AntiVoidPlatform" then platform = object end
end
assert(platform ~= nil, "the platform must exist after enabling")
assert(platform.Anchored == true, "the platform is anchored")
assert(platform.CanCollide == true, "the platform stops the fall")
assert(platform.CanQuery == false and platform.CanTouch == false, "it never enters raycasts or touches")
assert(platform.Transparency == 1, "it is invisible by default")
near(platform.CFrame.Position.X, 0)
near(platform.CFrame.Position.Y, 96)     -- 100 - 4
pass("Anti Void builds one invisible local platform under the character")

-- Walking keeps it under the feet.
rootProps.Position = Vector3.new(30, 120, -12)
tick(0.016)
near(platform.CFrame.Position.X, 30)
near(platform.CFrame.Position.Y, 116)
near(platform.CFrame.Position.Z, -12)
pass("the platform follows the character")

-- Falling: the platform holds its height so the fall actually lands.
local landingY = platform.CFrame.Position.Y
rootProps.Position = Vector3.new(30, 100, -12)
rootProps.AssemblyLinearVelocity = Vector3.new(0, -250, 0)
tick(0.016)
near(platform.CFrame.Position.Y, landingY)
pass("the platform does not descend with a falling character")

-- Standing on it, then jumping: it goes back under the feet.
rootProps.Position = Vector3.new(30, landingY + 4, -12)
rootProps.AssemblyLinearVelocity = Vector3.zero
tick(0.016)
rootProps.Position = Vector3.new(30, landingY + 30, -12)
tick(0.016)
near(platform.CFrame.Position.Y, landingY + 26)
pass("the platform rises again after a jump")

-- It never sinks under the destroy layer.
world.FallenPartsDestroyHeight = -100
rootProps.Position = Vector3.new(0, -40, 0)
tick(0.016)
assert(platform.CFrame.Position.Y >= -92, "the platform stops above the void layer")
world.FallenPartsDestroyHeight = -500
pass("the platform is clamped above the destroy layer")

-- Show platform only changes transparency.
options["Show platform"](true)
tick(0.016)
near(platform.Transparency, 0.4)
options["Show platform"](false)
tick(0.016)
near(platform.Transparency, 1)
pass("Show platform is cosmetic only")

feature.toggle(false)
assert(platform.destroyed == true, "disabling destroys the platform")
assert(tick == nil, "disabling releases the frame step")
AntiVoid.destroy()
pass("Anti Void tears down cleanly")
'''

SCRIPT_ANTIFLING = PRELUDE + "\nlocal AntiFling = (function()\n" + ANTIFLING + "\nend)()\n" + r'''
-- Anti Fling: the clamp -----------------------------------------------------
options = {}
AntiFling.init(context)
assert(feature.name == "Anti Fling", "the card is Anti Fling")
-- v138.8: Anti Fling has NO options; the thresholds scale with the character.
assert(next(options) == nil,
    "Anti Fling must be a plain ON/OFF card, got option(s): " .. tostring(next(options)))
assert(feature.configuration and feature.configuration.noOptions == true,
    "the card must declare noOptions")

feature.toggle(true)
assert(type(tick) == "function", "Anti Fling owns its own frame step")

-- A fling-sized impulse is removed and the input direction survives.
humanoid.MoveDirection = Vector3.new(1, 0, 0)
rootProps.AssemblyLinearVelocity = Vector3.new(9000, 40, 0)
rootProps.AssemblyAngularVelocity = Vector3.new(0, 500, 0)
tick(0.016)
assert(rootProps.AssemblyLinearVelocity.Magnitude < 100, "the planar impulse must be cancelled")
assert(rootProps.AssemblyLinearVelocity.X > 0, "the player's input direction is kept")
near(rootProps.AssemblyLinearVelocity.Y, 40)
near(rootProps.AssemblyAngularVelocity.Magnitude, 0)
pass("Anti Fling cancels planar impulses and spins, keeping the input")

-- A normal walk and a normal jump are untouched.
rootProps.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
rootProps.AssemblyAngularVelocity = Vector3.zero
tick(0.016)
near(rootProps.AssemblyLinearVelocity.X, 16)
rootProps.AssemblyLinearVelocity = Vector3.new(0, 45, 0)
tick(0.016)
near(rootProps.AssemblyLinearVelocity.Y, 45)
pass("walking and jumping are never touched")

-- An upward launch beyond three jump powers is clipped.
rootProps.AssemblyLinearVelocity = Vector3.new(0, 9000, 0)
tick(0.016)
assert(rootProps.AssemblyLinearVelocity.Y <= 150, "a launch must be clipped to the jump limit")
pass("vertical launches are clipped instead of killing the character")

-- Its own flings are never cancelled.
activityFlags["fling"] = true
rootProps.AssemblyLinearVelocity = Vector3.new(9000, 0, 0)
tick(0.016)
near(rootProps.AssemblyLinearVelocity.X, 9000)
activityFlags["fling"] = nil
activityFlags["walkfling"] = true
tick(0.016)
near(rootProps.AssemblyLinearVelocity.X, 9000)
activityFlags["walkfling"] = nil
pass("Anti Fling never fights our own Fling or Walk Fling")

-- The limit scales with the character, with nothing to tune: 2.5x WalkSpeed
-- clamps 150 studs/s at WalkSpeed 16 but allows it at WalkSpeed 80.
humanoid.MoveDirection = Vector3.zero
local savedWalkSpeed = humanoid.WalkSpeed
humanoid.WalkSpeed = 16
rootProps.AssemblyLinearVelocity = Vector3.new(150, 0, 0)
tick(0.016)
assert(rootProps.AssemblyLinearVelocity.X < 100, "16 WalkSpeed must clamp 150 studs/s")
humanoid.WalkSpeed = 80
rootProps.AssemblyLinearVelocity = Vector3.new(150, 0, 0)
tick(0.016)
near(rootProps.AssemblyLinearVelocity.X, 150)
humanoid.WalkSpeed = savedWalkSpeed
pass("Anti Fling thresholds scale with WalkSpeed, no options to tune")

-- The common Framework supplies a Speed module and numeric slider value.
-- Its higher configured speed must not be mistaken for an external fling.
context.framework.GetModule = function(_, name)
    if name == "Speed" then return {Enabled=true, Options={Speed={Value=120}}} end
end
rootProps.AssemblyLinearVelocity = Vector3.new(200, 0, 0)
tick(0.016)
near(rootProps.AssemblyLinearVelocity.X, 200)
context.framework.GetModule = function() return nil end
rootProps.AssemblyLinearVelocity = Vector3.new(200, 0, 0)
tick(0.016)
assert(rootProps.AssemblyLinearVelocity.X < 100)
pass("Anti Fling honours the enabled Speed setting")

feature.toggle(false)
assert(tick == nil, "disabling releases the frame step")
AntiFling.destroy()
pass("Anti Fling tears down cleanly")
print("PASS " .. passed .. " Anti Void / Anti Fling suites")
'''

with tempfile.TemporaryDirectory() as tmp:
    first = Path(tmp) / "antivoid.luau"
    first.write_text(SCRIPT)
    subprocess.run([os.environ.get("LUAU", "luau"), str(first)], check=True)
    second = Path(tmp) / "antifling.luau"
    second.write_text(SCRIPT_ANTIFLING)
    subprocess.run([os.environ.get("LUAU", "luau"), str(second)], check=True)
