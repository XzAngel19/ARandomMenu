#!/usr/bin/env python3
"""Run the real Shaders module AND Framework against a model of PostEffect parenting.

Roblox renders PostEffects only when directly parented to Lighting or the
current camera. This deliberately models that rule, unlike the old mock that
accepted inert Folder/Lighting descendants. It does not simulate the real GPU,
graphics quality, MM2 or an executor; an in-game visual test remains necessary.
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
                from.G + (to.G - from.G) * alpha,
                from.B + (to.B - from.B) * alpha)
        end
    end
end

local lighting = {Name = "Lighting", ClassName = "Lighting", children = {}}
local camera = {Name = "Camera", ClassName = "Camera", children = {}}
function lighting:GetChildren() return table.clone(self.children) end
function camera:GetChildren() return table.clone(self.children) end
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
    local obj = {ClassName = className, Name = className, children = {}, destroyed = false}
    local store = {Enabled = true, Brightness = 0, Contrast = 0, Saturation = 0,
        TintColor = Color3.new(1, 1, 1)}
    function obj:IsA(name) return self.ClassName == name end
    function obj:Destroy()
        self.Parent = nil
        self.destroyed = true
        for _, child in ipairs(table.clone(self.children)) do child:Destroy() end
    end
    setmetatable(obj, {
        __index = function(_, key)
            if key == "Parent" then return store.Parent end
            return store[key]
        end,
        __newindex = function(_, key, value)
            if key == "Parent" then
                local old = store.Parent
                if old then
                    for i, child in ipairs(old.children) do
                        if child == obj then table.remove(old.children, i); break end
                    end
                end
                store.Parent = value
                if value then table.insert(value.children, obj) end
            else
                store[key] = value
            end
        end,
    })
    return obj
end

game = {GetService = function(_, name) if name == "Lighting" then return lighting end end}
function settings() return {Rendering = {QualityLevel = "Manual10"}} end

local notifications = {}
local features = {}
local host = {Lighting = lighting, workspace = {CurrentCamera = camera}, state = {}, notify = function(text)
    table.insert(notifications, text)
end}
function host.createUniversalFeature(name, _, _, toggle, options)
    local feature = {name = name, configKey = options.configKey, toggle = toggle}
    function feature:SetStatus(status) self.status = status end
    features[name] = feature
    return feature
end
function host.addCycleOption(_, _, _, _, callback) return {callback = callback} end
function host.addNumberOption(_, _, _, _, _, callback, _, step)
    return {callback = callback, step = step}
end
function host.addColorOption(_, _, _, callback) return {callback = callback} end
function host.addActionOption(_, _, callback) return {callback = callback} end
function host.addInformationOption() end

-- This is intentionally narrow: an effect inside Folder/Lighting is inert.
local function renderable(effect)
    return effect and not effect.destroyed and effect.Enabled
        and (effect.Parent == lighting or effect.Parent == camera)
end
local function byName(name)
    for _, obj in ipairs(lighting.children) do
        if obj.Name == name and not obj.destroyed then return obj end
    end
end
local function pass(name) print("PASS\tshaders: " .. name) end
'''

BODY = r'''
local Framework = assert(loadstring(FRAMEWORK_SOURCE))()
local framework = Framework.init(host)
local Shaders = assert(loadstring(SHADERS_SOURCE))()
local card = Shaders.init({framework = framework, host = host})
assert(card == framework.Modules.Shaders, "actual Framework must register the card")

-- Demonstrate the engine invariant that the old mock missed.
local inertFolder = Instance.new("Folder")
inertFolder.Parent = lighting
local inertColor = Instance.new("ColorCorrectionEffect")
inertColor.Parent = inertFolder
assert(not renderable(inertColor), "a post effect nested in Folder must not render")
inertFolder:Destroy()
pass("model rejects the old inert Folder/Lighting hierarchy")

local gameEffect = Instance.new("ColorCorrectionEffect")
gameEffect.Name = "GameOwned"
gameEffect.Brightness = -0.2
gameEffect.Parent = lighting
local cameraEffect = Instance.new("ColorCorrectionEffect")
cameraEffect.Name = "CameraOwned"
cameraEffect.Parent = camera
assert(#children(lighting) == 1, "no effects before enabling")

-- Invoke the real UI onToggle path rather than a hand-written mock toggle.
features.Shaders.toggle(true)
assert(card.Enabled == true, "Framework sets Enabled before the callback")
local color = byName("ARMShaderColor")
local bloom = byName("ARMShaderBloom")
local rays = byName("ARMShaderRays")
assert(color and bloom and rays, "all three effects are created")
assert(color.Parent == lighting and bloom.Parent == lighting and rays.Parent == lighting,
    "post effects must be DIRECT children of Lighting")
assert(renderable(color) and renderable(bloom) and renderable(rays), "default passes are enabled")
assert(card.Options.Look.Value == "Cinematic", "default Look")
assert(card.Options.Saturation.Metadata.step == 0.01 and card.Options.Saturation.Object.step == 0.01,
    "Saturation must support decimal slider steps in the real Framework")
assert(color.Saturation ~= 0 or color.Contrast ~= 0, "default color pass is non-neutral")
assert(bloom.Intensity > 0.3, "default bloom is non-neutral")
pass("real Framework toggles three non-neutral direct Lighting effects")

-- Previously, typed or restored slider values bypassed the visible slider
-- range: Brightness -5 became -1 (documented by Roblox as entirely black), and
-- a black Tint multiplied all three pixel channels by zero. Verify the actual
-- effects of every preset, including old saved/extreme option values. This is
-- a parameter test, not a GPU render or a promise about the game's own effects.
local looks = {"None", "Cinematic", "Vivid", "Neon", "Noir", "Warm", "Frost", "Dream"}
card.Options.Brightness.Metadata.callback(-20)
assert(color.Brightness > -1, "a restored or typed value must not apply documented blackout brightness")
card.Options.Brightness.Metadata.callback(0)
local function assertVisibleParameters(name)
    assert(color.Brightness >= -0.05 and color.Brightness <= 0.3,
        name .. " must not use blackout/whiteout brightness")
    assert(color.Contrast >= -0.35 and color.Contrast <= 0.25,
        name .. " must keep contrast moderate")
    assert(color.TintColor.R >= 0.6 and color.TintColor.G >= 0.6 and color.TintColor.B >= 0.6,
        name .. " tint must not zero pixel channels")
end
for _, look in ipairs(looks) do
    card.Options.Look.Metadata.callback(look)
    assertVisibleParameters(look .. " with defaults")
end
card.Options.Brightness.Metadata.callback(-20)
card.Options.Contrast.Metadata.callback(20)
card.Options.Tint.Metadata.callback(Color3.new(0, 0, 0))
for _, look in ipairs(looks) do
    card.Options.Look.Metadata.callback(look)
    assertVisibleParameters(look .. " with old extreme settings")
end
assert(card.Options.Brightness.Value == -20 and card.Options.Tint.Value == Color3.new(0, 0, 0),
    "safe applied values must not overwrite saved option values")
card.Options.Brightness.Metadata.callback(20)
card.Options.Contrast.Metadata.callback(-20)
for _, look in ipairs(looks) do
    card.Options.Look.Metadata.callback(look)
    assertVisibleParameters(look .. " with opposite extremes")
end
card.Options.Brightness.Metadata.callback(0)
card.Options.Contrast.Metadata.callback(0)
card.Options.Tint.Metadata.callback(Color3.new(1, 1, 1))
card.Options.Look.Metadata.callback("Cinematic")
pass("all eight presets bound brightness, contrast and tint even with old extreme settings")

-- Use real Framework's option callbacks to prove changes reach the instances.
card.Options.Look.Metadata.callback("Noir")
assert(renderable(color) and color.Saturation == -1 and color.Contrast > 0.2,
    "Noir must set a renderable desaturated pass")
card.Options.Saturation.Metadata.callback(0.5)
assert(color.Saturation == -0.5, "manual slider adds to Noir")
card.Options.Saturation.Metadata.callback(5)
assert(color.Saturation == 1, "saturation is clamped")
card.Options.Look.Metadata.callback("None")
card.Options.Bloom.Metadata.callback(0)
card.Options["Sun rays"].Metadata.callback(0)
assert(not bloom.Enabled and not rays.Enabled, "zero-intensity effects are disabled")
card.Options.Bloom.Metadata.callback(1.5)
card.Options["Sun rays"].Metadata.callback(0.6)
assert(bloom.Enabled and bloom.Intensity == 1.5 and rays.Enabled and rays.Intensity == 0.6)
card.Options.Tint.Metadata.callback(Color3.new(1, 0, 0))
card.Options.Look.Metadata.callback("Frost")
assert(color.TintColor.R < 1 and color.TintColor.B > 0.5, "tint blends with preset")
pass("options update actual color, clamp, bloom, rays and tint")

-- A game script or optimization may disable the effect after it was applied.
color.Enabled = false
local lines = {}
local oldPrint = print
print = function(text) table.insert(lines, text) end
card.Options.Diagnose.Metadata.callback()
print = oldPrint
assert(#notifications > 0 and notifications[#notifications]:find("enabled=false", 1, true),
    "diagnostic reports actual enabled flag")
assert(#lines == 3 and lines[1]:find("brightness=", 1, true)
    and lines[2]:find("name=GameOwned", 1, true) and lines[3]:find("name=CameraOwned", 1, true),
    "diagnostic lists our values and existing enabled color effects on Lighting and Camera")
assert(not renderable(color), "a disabled effect is not rendered")
assert(gameEffect.Brightness == -0.2 and cameraEffect.Parent == camera, "diagnosis never modifies game effects")
card.Options.Contrast.Metadata.callback(0.1)
assert(color.Enabled == true, "an option change re-applies this module's color effect")
pass("diagnostic reports our values and other effects without claiming pixels rendered")

-- No automatic repair/check loop: if a game moves an effect, OFF still cleans
-- the owned instance and ON creates it again as a direct Lighting child.
color.Parent = inertFolder
card.Options.Contrast.Metadata.callback(0.2)
assert(not renderable(color) and not byName("ARMShaderColor"),
    "an option change does not secretly replace a moved instance")
assert(byName("ARMShaderBloom") == bloom and byName("ARMShaderRays") == rays)
pass("no replacement machinery or polling when the game moves an effect")

features.Shaders.toggle(false)
assert(not card.Enabled and color.destroyed and bloom.destroyed and rays.destroyed,
    "all owned effects are destroyed on disable")
assert(not gameEffect.destroyed and gameEffect.Parent == lighting,
    "a game-owned post effect must not be changed")
assert(#children(lighting) == 1, "only the game-owned effect remains")
pass("disable destroys only this module's effects")

-- During deferred config restoration the caller may catch an enable failure
-- without sending OFF. The card must already be OFF and all partial effects
-- removed, while the original error still reaches that caller.
Instance.fail.BloomEffect = true
local createdOK = pcall(features.Shaders.toggle, true)
assert(not createdOK, "construction failure must reach the caller")
assert(not card.Enabled and not byName("ARMShaderColor") and #children(lighting) == 1,
    "failed enable cleans partial effects and resets state without a later OFF")
Instance.fail.BloomEffect = nil
pass("interrupted creation immediately cleans partial effects and resets state")

features.Shaders.toggle(true)
assert(renderable(byName("ARMShaderColor")), "can re-enable after a failure")
Shaders.destroy()
assert(#children(lighting) == 1 and not card.Enabled, "module destroy performs full cleanup")
assert(gameEffect.Parent == lighting and not gameEffect.destroyed)
pass("re-enable and module destroy are reusable and preserve game effects")

-- The real host supplies Lighting. Restore saved options while the widgets
-- construct themselves, before their entries have been registered.
local fallbackHost = table.clone(host)
fallbackHost.state = {}
-- Widgets restore stored values during construction, before option registration.
function fallbackHost.addCycleOption(_, name, list, index, callback)
    callback(name == "Look" and "Frost" or list[index])
    return {callback = callback}
end
function fallbackHost.addNumberOption(_, name, default, _, _, callback, _, step)
    local saved = if name == "Saturation" then -0.30
        elseif name == "Brightness" then -20
        elseif name == "Contrast" then 20
        else default
    callback(saved)
    return {callback = callback, step = step}
end
function fallbackHost.addColorOption(_, _, _, callback)
    callback(Color3.new(0, 0, 0))
    return {callback = callback}
end
local fallbackFramework = Framework.init(fallbackHost)
local savedCard = Shaders.init({framework = fallbackFramework, host = fallbackHost})
assert(savedCard.Options.Look.Value == "Frost" and savedCard.Options.Saturation.Value == -0.30,
    "saved options must survive widget callbacks before registration")
features.Shaders.toggle(true)
local savedColor = byName("ARMShaderColor")
assert(renderable(savedColor), "restored settings still use direct Lighting parenting")
assert(math.abs(savedColor.Saturation - (-0.35)) < 1e-6,
    "saved Saturation and Frost offset must be applied on enable")
assert(savedCard.Options.Brightness.Value == -20 and savedCard.Options.Contrast.Value == 20,
    "existing saved settings remain intact")
assert(savedColor.Brightness == -0.05 and savedColor.Contrast == 0.25
    and savedColor.TintColor.R >= 0.6 and savedColor.TintColor.G >= 0.6 and savedColor.TintColor.B >= 0.6,
    "extreme saved values are made safe when the card is enabled")
Shaders.destroy()
assert(#children(lighting) == 1, "restored configuration is cleaned up")
pass("saved extreme options are bounded through initial widget callbacks")
'''


def quote_lua(text: str) -> str:
    assert "]==]" not in text
    return "[==[\n" + text + "\n]==]"


script = (PRELUDE + "\nlocal FRAMEWORK_SOURCE = " + quote_lua(FRAMEWORK)
          + "\nlocal SHADERS_SOURCE = " + quote_lua(SHADERS) + "\n" + BODY)
with tempfile.TemporaryDirectory(prefix="shaders-") as tmp:
    file = Path(tmp) / "test.luau"
    file.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(file)], check=True)
