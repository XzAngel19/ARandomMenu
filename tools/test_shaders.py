#!/usr/bin/env python3
"""Run the real Shaders + Framework with mock lighting, weather and UI.

Models direct PostEffect parenting, atmosphere ownership, deferred asset loads,
roof checks, four weather cells, configuration restoration and teardown. It
cannot render pixels or measure Roblox/Delta GPU performance.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHADERS = (ROOT / "src/games/universal/Render/Shaders.lua").read_text()
FRAMEWORK = (ROOT / "src/libraries/Framework.lua").read_text()

PRELUDE = r'''
Color3 = {}
local colorMeta = {__eq = function(a, b)
    return a.R == b.R and a.G == b.G and a.B == b.B
end}
function Color3.new(r, g, b)
    return setmetatable({R = r or 0, G = g or 0, B = b or 0}, colorMeta)
end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
function colorMeta.__index(color, key)
    if key == "Lerp" then
        return function(from, to, alpha)
            return Color3.new(from.R + (to.R - from.R) * alpha,
                from.G + (to.G - from.G) * alpha, from.B + (to.B - from.B) * alpha)
        end
    end
end
local vectorMeta = {}
function vectorMeta.__index(v, key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
end
function vectorMeta.__add(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
function vectorMeta.__sub(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
Vector3 = {new = function(x, y, z) return setmetatable({X=x, Y=y, Z=z}, vectorMeta) end}
Vector2 = {new = function(x, y) return {X=x, Y=y} end}
NumberSequence = {new = function(value) return {Value=value} end}
NumberRange = {new = function(a, b) return {Min=a, Max=b or a} end}
ColorSequence = {new = function(value) return {Value=value} end}
RaycastParams = {new = function() return {} end}
Enum = {
    ParticleEmitterShape = {Box = "Box"}, ParticleEmitterShapeStyle = {Volume = "Volume"},
    NormalId = {Bottom = "Bottom"},
    ParticleOrientation = {VelocityParallel = "VelocityParallel", FacingCamera = "FacingCamera"},
    RaycastFilterType = {Exclude = "Exclude"},
}

local deferred, spawned = {}, {}
task = {
    defer = function(fn) table.insert(deferred, fn) end,
    spawn = function(fn) table.insert(spawned, fn) end,
}
local function flushDeferred()
    local count = 0
    while #deferred > 0 do
        count += 1
        assert(count < 100, "deferred atmosphere events must settle")
        local fn = table.remove(deferred, 1)
        fn()
    end
end
local function runSpawned()
    assert(#spawned > 0, "asset job expected")
    local fn = table.remove(spawned, 1)
    fn()
end
local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn)
            table.insert(callbacks, fn)
            return {Disconnect = function()
                for i, cb in ipairs(callbacks) do
                    if cb == fn then table.remove(callbacks, i); break end
                end
            end}
        end,
        Fire = function(_, ...)
            for _, fn in ipairs(table.clone(callbacks)) do fn(...) end
        end,
        Count = function() return #callbacks end,
    }
end
local function container(name, class)
    local object = {Name=name, ClassName=class, children={}, ChildAdded=signal(), ChildRemoved=signal()}
    function object:GetChildren() return table.clone(self.children) end
    return object
end
local lighting = container("Lighting", "Lighting")
local camera = container("Camera", "Camera")
camera.CFrame = {Position=Vector3.new(0, 12, 0)}
local world = container("Workspace", "Workspace")
world.CurrentCamera = camera
local roof = {Transparency=0, IsA=function(_, name) return name == "BasePart" end}
local rayCount, isCovered, roofHeight = 0, false, nil
function world:Raycast(origin, direction, params)
    rayCount += 1
    assert(params.FilterType == "Exclude" and #params.FilterDescendantsInstances >= 1,
        "weather rays must exclude their own cells")
    if isCovered or (roofHeight and origin.Y <= roofHeight and origin.Y + direction.Y >= roofHeight) then
        return {Instance=roof}
    end
    return nil
end
local function children(parent, className)
    local result = {}
    for _, obj in ipairs(parent.children) do
        if not obj.destroyed and (not className or obj.ClassName == className) then
            table.insert(result, obj)
        end
    end
    return result
end

Instance = {fail = {}}
function Instance.new(className)
    if Instance.fail[className] then error("creation denied for " .. className) end
    local obj = container(className, className)
    obj.destroyed = false
    local store = {Enabled=true, Brightness=0, Contrast=0, Saturation=0,
        TintColor=Color3.new(1,1,1), Density=0.2, Offset=0, Haze=0.5,
        Glare=0, Color=Color3.new(1,1,1), Decay=Color3.new(0.5,0.5,0.5)}
    function obj:IsA(name)
        return self.ClassName == name or (name == "BasePart" and self.ClassName == "Part")
    end
    function obj:Destroy()
        self.Parent = nil
        self.destroyed = true
        for _, child in ipairs(table.clone(self.children)) do child:Destroy() end
    end
    setmetatable(obj, {
        __index = function(_, key) return store[key] end,
        __newindex = function(_, key, value)
            if key == "Parent" then
                local old = store.Parent
                if old then
                    for i, child in ipairs(old.children) do
                        if child == obj then table.remove(old.children, i); break end
                    end
                end
                store.Parent = value
                if old and old.ChildRemoved then old.ChildRemoved:Fire(obj) end
                if value then
                    table.insert(value.children, obj)
                    if value.ChildAdded then value.ChildAdded:Fire(obj) end
                end
            else
                store[key] = value
            end
        end,
    })
    return obj
end

game = {GetService = function(_, name) if name == "Lighting" then return lighting end end}
local warnings = {}
warn = function(text) table.insert(warnings, tostring(text)) end
local notifications, features = {}, {}
local handles = {}
local manager = {}
function manager:Connect(callback, _phase, label)
    local handle = {Connected=true, callback=callback, label=label}
    function handle:Disconnect() self.Connected = false end
    table.insert(handles, handle)
    return handle
end
local function activeHandles()
    local count = 0
    for _, handle in ipairs(handles) do if handle.Connected then count += 1 end end
    return count
end
local function frames(count, dt)
    for _ = 1, count do
        for _, handle in ipairs(table.clone(handles)) do
            if handle.Connected then handle.callback(dt or 0.05) end
        end
        flushDeferred()
    end
end
local localCharacter = {Name="LocalCharacter"}
local host = {Lighting=lighting, workspace=world, TaskManager=manager,
    LocalPlayer={Character=localCharacter}, state={}, notify=function(text)
        table.insert(notifications, text)
    end}
function host.createUniversalFeature(name, _, _, toggle, options)
    local feature = {name=name, configKey=options.configKey, toggle=toggle}
    function feature:SetStatus(status) self.status = status end
    features[name] = feature
    return feature
end
function host.addCycleOption(_, _, _, _, callback) return {callback=callback} end
function host.addToggleOption(_, _, _, callback) return {callback=callback} end
function host.addNumberOption(_, _, _, _, _, callback, _, step) return {callback=callback, step=step} end
function host.addColorOption(_, _, _, callback) return {callback=callback} end
function host.addActionOption(_, _, callback) return {callback=callback} end
function host.addInformationOption() end
function host.setOptionVisible(_, row, visible) row.visible = visible end
host.state.resolveAsset = function(name) return "custom://" .. name end
local function renderable(effect)
    return effect and not effect.destroyed and effect.Enabled
        and (effect.Parent == lighting or effect.Parent == camera)
end
local function byName(parent, name)
    for _, obj in ipairs(parent.children) do
        if obj.Name == name and not obj.destroyed then return obj end
    end
end
local function pass(name) print("PASS\tshaders: " .. name) end
'''

BODY = r'''
local Framework = assert(loadstring(FRAMEWORK_SOURCE))()
local framework = Framework.init(host)
local Shaders = assert(loadstring(SHADERS_SOURCE))()
local card = Shaders.init({framework=framework, host=host})
assert(card == framework.Modules.Shaders, "actual Framework registers the card")
local inertFolder = Instance.new("Folder")
inertFolder.Parent = lighting
local inertColor = Instance.new("ColorCorrectionEffect")
inertColor.Parent = inertFolder
assert(not renderable(inertColor), "an effect nested in a Folder is inert")
inertFolder:Destroy()
local gameEffect = Instance.new("ColorCorrectionEffect")
gameEffect.Name = "GameOwned"
gameEffect.Brightness = -0.2
gameEffect.Parent = lighting
local cameraEffect = Instance.new("ColorCorrectionEffect")
cameraEffect.Name = "CameraOwned"
cameraEffect.Parent = camera

features.Shaders.toggle(true)
local color = byName(lighting, "ARMShaderColor")
local bloom = byName(lighting, "ARMShaderBloom")
local rays = byName(lighting, "ARMShaderRays")
assert(card.Enabled and renderable(color) and renderable(bloom) and renderable(rays),
    "three native effects must be direct Lighting children")
assert(card.Options.Look.Value == "Photoreal" and card.Options.Weather.Value == "Clear")
assert(math.abs(bloom.Intensity - 0.32) < 0.001 and bloom.Size == 22,
    "default post-processing derives from the imported HighNoon preset")
assert(math.abs(bloom.Threshold - 2) < 0.001 and math.abs(rays.Intensity - 0.05) < 0.001)
assert(not byName(world, "ARMShaderWeather") and activeHandles() == 0,
    "clear weather creates no frame task or particles")
pass("direct native effects, imported defaults and zero weather work in Clear")

local advancedNames = {"Saturation", "Contrast", "Brightness", "Tint", "Bloom",
    "Bloom threshold", "Bloom size", "Sun rays", "Ray spread", "Diagnose"}
for _, name in ipairs(advancedNames) do
    assert(card.Options[name].Metadata.visible == false, name .. " starts hidden")
end
card.Options.Advanced.Metadata.callback(true)
for _, name in ipairs(advancedNames) do
    assert(card.Options[name].Metadata.visible == true, name .. " remains accessible")
end
assert(card.Options.Saturation.Metadata.step == 0.01)
pass("simple default panel retains all original controls behind Advanced")

local looks = {"None", "Photoreal", "Golden Hour", "Blue Hour", "Overcast",
    "Cinematic", "Vivid", "Neon", "Noir", "Warm", "Frost", "Dream"}
card.Options.Brightness.Metadata.callback(-20)
card.Options.Contrast.Metadata.callback(20)
card.Options.Tint.Metadata.callback(Color3.new(0, 0, 0))
for _, look in ipairs(looks) do
    card.Options.Look.Metadata.callback(look)
    assert(color.Brightness >= -0.05 and color.Brightness <= 0.3, look .. " safe brightness")
    assert(color.Contrast >= -0.35 and color.Contrast <= 0.25, look .. " safe contrast")
    assert(color.TintColor.R >= 0.6 and color.TintColor.G >= 0.6 and color.TintColor.B >= 0.6,
        look .. " must not zero the colour channels")
end
card.Options.Brightness.Metadata.callback(0)
card.Options.Contrast.Metadata.callback(0)
card.Options.Tint.Metadata.callback(Color3.new(1,1,1))
card.Options.Look.Metadata.callback("Noir")
assert(color.Saturation == -1 and color.Contrast > 0.2)
card.Options.Saturation.Metadata.callback(0.5)
assert(color.Saturation == -0.5, "old manual slider adds to its preset")
card.Options.Saturation.Metadata.callback(0)
card.Options.Look.Metadata.callback("Cinematic")
pass("all imported and original looks bound blackout values and keep legacy sliders")

-- Preserve the original zero-intensity/reenable and no-reparent-polling
-- contracts as well as the new weather behaviour.
card.Options.Look.Metadata.callback("None")
card.Options.Bloom.Metadata.callback(0)
card.Options["Sun rays"].Metadata.callback(0)
assert(not bloom.Enabled and not rays.Enabled, "zero intensity disables native passes")
card.Options.Bloom.Metadata.callback(1.5)
card.Options["Sun rays"].Metadata.callback(0.6)
assert(bloom.Enabled and bloom.Intensity == 1.5 and rays.Enabled and rays.Intensity == 0.6)
local movedFolder = Instance.new("Folder")
movedFolder.Parent = lighting
color.Parent = movedFolder
frames(5)
assert(not renderable(color) and not byName(lighting, "ARMShaderColor"),
    "the module must not poll or recreate an externally moved effect")
assert(byName(lighting, "ARMShaderBloom") == bloom and byName(lighting, "ARMShaderRays") == rays)
color.Parent = lighting
movedFolder:Destroy()
card.Options.Bloom.Metadata.callback(0.6)
card.Options["Sun rays"].Metadata.callback(0.2)
card.Options.Look.Metadata.callback("Cinematic")
pass("legacy intensity controls and externally moved effects remain unchanged")

color.Enabled = false
local lines = {}
local oldPrint = print
print = function(text) table.insert(lines, text) end
card.Options.Diagnose.Metadata.callback()
print = oldPrint
assert(#notifications > 0 and notifications[#notifications]:find("enabled=false", 1, true))
assert(#lines == 3 and lines[1]:find("brightness=", 1, true)
    and lines[2]:find("name=GameOwned", 1, true) and lines[3]:find("name=CameraOwned", 1, true))
assert(gameEffect.Brightness == -0.2 and cameraEffect.Parent == camera)
card.Options.Contrast.Metadata.callback(0)
assert(color.Enabled, "an option change re-applies our colour effect")
pass("legacy Diagnose still reports owned and external effects without mutating them")

-- Fog with no game atmosphere: create exactly one, then remove only ours.
card.Options.Fog.Metadata.callback(true)
local ownFog = byName(lighting, "Atmosphere")
assert(ownFog and ownFog.Density == 0.38 and #children(lighting, "Atmosphere") == 1)
card.Options.Fog.Metadata.callback(false)
flushDeferred()
assert(ownFog.destroyed and #children(lighting, "Atmosphere") == 0)
assert(gameEffect.Brightness == -0.2 and cameraEffect.Parent == camera)
pass("Fog creates and removes only its own atmosphere")

-- If the game has an atmosphere, use it instead of adding an ignored duplicate.
local existing = Instance.new("Atmosphere")
existing.Name = "GameAtmosphere"
existing.Density = 0.12
existing.Haze = 0.2
existing.Parent = lighting
card.Options.Fog.Metadata.callback(true)
assert(existing.Density == 0.38 and #children(lighting, "Atmosphere") == 1)
existing.Density = 0.77 -- a game update wins on release
card.Options.Fog.Metadata.callback(false)
flushDeferred()
assert(existing.Density == 0.77 and existing.Haze == 0.2,
    "release restores untouched properties but not changes made by the game")
assert(existing.Parent == lighting and not existing.destroyed)
pass("Fog borrows existing atmosphere and preserves later game changes")

-- A game atmosphere can arrive or be replaced after Fog was enabled.
existing:Destroy()
flushDeferred()
card.Options.Fog.Metadata.callback(true)
local replacedOwn = byName(lighting, "Atmosphere")
local incoming = Instance.new("Atmosphere")
incoming.Name = "IncomingGameAtmosphere"
incoming.Density = 0.16
incoming.Parent = lighting
flushDeferred()
assert(replacedOwn.destroyed and incoming.Density == 0.38
    and #children(lighting, "Atmosphere") == 1, "new game atmosphere supersedes our temporary one")
incoming:Destroy()
local replacement = Instance.new("Atmosphere")
replacement.Name = "Replacement"
replacement.Density = 0.23
replacement.Parent = lighting
flushDeferred()
assert(replacement.Density == 0.38 and replacement.Parent == lighting)
card.Options.Fog.Metadata.callback(false)
flushDeferred()
assert(replacement.Density == 0.23 and not replacement.destroyed)
pass("game atmosphere arrival and replacement are handled and restored")

-- Weather jobs stay lazy, bounded, roof-aware and reversible.
card.Options.Weather.Metadata.callback("Rain")
local rainFolder = byName(world, "ARMShaderWeather")
assert(rainFolder and #children(rainFolder, "Part") == 4 and activeHandles() == 1)
local rainEmitters = {}
for _, part in ipairs(children(rainFolder, "Part")) do
    assert(part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch)
    local emitter = children(part, "ParticleEmitter")[1]
    assert(emitter.Rate == 15 and emitter.Texture == "rbxasset://textures/particles/SquareParticle.png")
    table.insert(rainEmitters, emitter)
end
assert(#spawned == 1, "only the selected weather texture is requested")
rayCount = 0
frames(20)
assert(rayCount <= 8, "one staggered roof ray at most every 0.15 s: " .. rayCount)
for _, emitter in ipairs(rainEmitters) do assert(emitter.Enabled, "open sky emits rain") end
isCovered = true
frames(20)
for _, emitter in ipairs(rainEmitters) do assert(not emitter.Enabled, "roof disables its cell") end
roof.Transparency = 1
frames(20)
for _, emitter in ipairs(rainEmitters) do assert(emitter.Enabled, "invisible parts do not block rain") end
isCovered = false
roof.Transparency = 0
isCovered = false
-- The ceiling lies above the camera but below the raised emitters. A ray
-- starting at the emitters would miss it and incorrectly rain indoors.
roofHeight = camera.CFrame.Position.Y + 5
frames(60)
for _, emitter in ipairs(rainEmitters) do assert(not emitter.Enabled, "low ceiling disables its cell") end
roofHeight = nil
frames(60)
for _, emitter in ipairs(rainEmitters) do assert(emitter.Enabled, "weather resumes outdoors") end
local beforeJumps = rayCount
for i = 1, 120 do
    camera.CFrame = {Position=Vector3.new(if i % 6 < 3 then 100 else 0, 12, 0)}
    frames(1, 1/60)
end
assert(rayCount - beforeJumps <= 15, "rapid camera jumps must not bypass the roof ray limit")
camera.CFrame = {Position=Vector3.new(0, 12, 0)}
frames(60)
pass("four capped rain emitters, staggered roof tests and collision-safe parts")

card.Options.Weather.Metadata.callback("Snow")
local snowFolder = byName(world, "ARMShaderWeather")
assert(rainFolder.destroyed and snowFolder and activeHandles() == 1)
local snowEmitter = children(children(snowFolder, "Part")[1], "ParticleEmitter")[1]
assert(snowEmitter.Rate == 7 and snowEmitter.Texture == "rbxasset://textures/particles/smoke_main.dds")
runSpawned() -- delayed Rain download must not touch current Snow cells
assert(snowEmitter.Texture == "rbxasset://textures/particles/smoke_main.dds")
runSpawned()
assert(snowEmitter.Texture == "custom://shaderSnowTexture")
local camera2 = container("Camera2", "Camera")
camera2.CFrame = {Position=Vector3.new(100, 30, 100)}
world.CurrentCamera = camera2
frames(20)
assert(children(snowFolder, "Part")[1].Position.X > 80, "cells follow replacement camera")
world.CurrentCamera = nil
frames(2)
for _, part in ipairs(children(snowFolder, "Part")) do
    assert(not children(part, "ParticleEmitter")[1].Enabled, "no camera stops emissions")
end
world.CurrentCamera = camera2
frames(20)
assert(snowEmitter.Enabled, "weather resumes after the camera returns")
pass("Snow, async texture race and camera loss/replacement")

card.Options.Weather.Metadata.callback("Autumn")
local autumnFolder = byName(world, "ARMShaderWeather")
local autumnEmitter = children(children(autumnFolder, "Part")[1], "ParticleEmitter")[1]
assert(autumnEmitter.Rate == 3 and autumnEmitter.Texture == "rbxassetid://80805595237760")
runSpawned()
assert(autumnEmitter.Texture == "custom://shaderAutumnTexture")
card.Options.Weather.Metadata.callback("Clear")
assert(autumnFolder.destroyed and activeHandles() == 0 and not byName(world, "ARMShaderWeather"))
pass("downloaded Autumn texture and Clear cleanup")

-- An unavailable texture keeps the built-in fallback, and a failed Part or
-- emitter construction must not turn off the working colour effects.
host.state.resolveAsset = function() return nil, "not available" end
card.Options.Weather.Metadata.callback("Rain")
local fallback = byName(world, "ARMShaderWeather")
local fallbackEmitter = children(children(fallback, "Part")[1], "ParticleEmitter")[1]
runSpawned()
assert(fallbackEmitter.Texture == "rbxasset://textures/particles/SquareParticle.png")
Instance.fail.ParticleEmitter = true
card.Options.Weather.Metadata.callback("Snow")
assert(card.Enabled and renderable(color) and not byName(world, "ARMShaderWeather") and activeHandles() == 0)
assert(notifications[#notifications]:find("Weather unavailable", 1, true))
Instance.fail.ParticleEmitter = nil
card.Options.Weather.Metadata.callback("Rain")
local pending = byName(world, "ARMShaderWeather")
features.Shaders.toggle(false)
runSpawned() -- completion after OFF must not revive instances
flushDeferred()
assert(pending.destroyed and not card.Enabled and activeHandles() == 0)
assert(not gameEffect.destroyed and replacement.Parent == lighting and not replacement.destroyed)
assert(color.destroyed and bloom.destroyed and rays.destroyed)
pass("fallback, partial weather failure, OFF and delayed job cleanup")

Instance.fail.BloomEffect = true
local createdOK = pcall(features.Shaders.toggle, true)
assert(not createdOK and not card.Enabled and not byName(lighting, "ARMShaderColor"),
    "failed shader construction cleans partial effects")
Instance.fail.BloomEffect = nil
features.Shaders.toggle(true)
assert(renderable(byName(lighting, "ARMShaderColor")), "can re-enable after failure")
Shaders.destroy()
assert(not card.Enabled and not byName(lighting, "ARMShaderColor") and activeHandles() == 0)
assert(gameEffect.Parent == lighting and replacement.Parent == lighting)
pass("interrupted enable, re-enable and module destroy")

-- Real Framework callbacks can restore legacy settings during widget creation.
local fallbackHost = table.clone(host)
fallbackHost.state = {}
function fallbackHost.addCycleOption(_, name, list, index, callback)
    callback(name == "Look" and "Frost" or list[index])
    return {callback=callback}
end
function fallbackHost.addToggleOption(_, name, default, callback)
    callback(name == "Advanced" or default)
    return {callback=callback}
end
function fallbackHost.addNumberOption(_, name, default, _, _, callback, _, step)
    local saved = if name == "Saturation" then -0.30
        elseif name == "Brightness" then -20 elseif name == "Contrast" then 20 else default
    callback(saved)
    return {callback=callback, step=step}
end
function fallbackHost.addColorOption(_, _, _, callback)
    callback(Color3.new(0,0,0))
    return {callback=callback}
end
local fallbackFramework = Framework.init(fallbackHost)
local savedCard = Shaders.init({framework=fallbackFramework, host=fallbackHost})
assert(savedCard.Options.Look.Value == "Frost" and savedCard.Options.Advanced.Value == true)
features.Shaders.toggle(true)
local restored = byName(lighting, "ARMShaderColor")
assert(restored.Brightness >= -0.05 and restored.Contrast <= 0.25 and restored.TintColor.R >= 0.6)
assert(savedCard.Options.Saturation.Metadata.visible == true)
Shaders.destroy()
pass("legacy saved profile restoration remains safe")
'''


def lua_quote(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


script_text = (PRELUDE + "\nlocal FRAMEWORK_SOURCE = " + lua_quote(FRAMEWORK)
               + "\nlocal SHADERS_SOURCE = " + lua_quote(SHADERS) + "\n" + BODY)
with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "shaders.luau"
    script.write_text(script_text, encoding="utf-8")
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
