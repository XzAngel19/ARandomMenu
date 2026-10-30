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

local lighting = {Name = "Lighting", ClassName = "Lighting", children = {}}
local camera = {Name = "Camera", ClassName = "Camera", children = {}}
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
    local store = {Enabled = true}
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
local host = {Lighting = lighting, state = {}, notify = function(text)
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
gameEffect.Parent = lighting
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
card.Options.Diagnose.Metadata.callback()
assert(#notifications > 0 and notifications[#notifications]:find("enabled=false", 1, true),
    "diagnostic reports actual enabled flag")
assert(not renderable(color), "a disabled effect is not rendered")
card.Options.Contrast.Metadata.callback(0.1)
assert(color.Enabled == true, "an option change re-applies this module's color effect")
pass("diagnostic reports an externally disabled effect without claiming pixels rendered")

-- If the game reparents or removes one effect, the next apply repairs just it.
color.Parent = inertFolder -- a detached folder: not a valid rendering parent
card.Options.Contrast.Metadata.callback(0.2)
local replacement = byName("ARMShaderColor")
assert(replacement and replacement ~= color and color.destroyed and renderable(replacement),
    "reparented owned effect is replaced on next apply")
assert(byName("ARMShaderBloom") == bloom and byName("ARMShaderRays") == rays,
    "other effects are not duplicated")
pass("removed or reparented effects are rebuilt on next option change")

features.Shaders.toggle(false)
assert(not card.Enabled and replacement.destroyed and bloom.destroyed and rays.destroyed,
    "all owned effects are destroyed on disable")
assert(not gameEffect.destroyed and gameEffect.Parent == lighting,
    "a game-owned post effect must not be changed")
assert(#children(lighting) == 1, "only the game-owned effect remains")
pass("disable destroys only this module's effects")

-- A partial creation failure must not leak Bloom/Rays because color is nil.
Instance.fail.ColorCorrectionEffect = true
features.Shaders.toggle(true)
assert(card.Status:find("color", 1, true), "partial failure must be visible")
local partialBloom, partialRays = byName("ARMShaderBloom"), byName("ARMShaderRays")
assert(partialBloom and partialRays and not byName("ARMShaderColor"), "partial creation")
card.Options.Diagnose.Metadata.callback()
assert(notifications[#notifications]:find("missing", 1, true), "missing color is reported")
features.Shaders.toggle(false)
assert(partialBloom.destroyed and partialRays.destroyed and #children(lighting) == 1,
    "partial creation must be cleaned up without ipairs holes")
Instance.fail.ColorCorrectionEffect = nil
pass("partial creation reports failure and cleans up every surviving effect")

features.Shaders.toggle(true)
assert(renderable(byName("ARMShaderColor")), "can re-enable after a failure")
Shaders.destroy()
assert(#children(lighting) == 1 and not card.Enabled, "module destroy performs full cleanup")
assert(gameEffect.Parent == lighting and not gameEffect.destroyed)
pass("re-enable and module destroy are reusable and preserve game effects")

-- Fallback to game:GetService when the host did not supply Lighting.
local fallbackHost = table.clone(host)
fallbackHost.Lighting = nil
fallbackHost.state = {}
-- Widgets restore stored values during construction, before option registration.
function fallbackHost.addCycleOption(_, name, list, index, callback)
    callback(name == "Look" and "Frost" or list[index])
    return {callback = callback}
end
function fallbackHost.addNumberOption(_, name, default, _, _, callback, _, step)
    callback(name == "Saturation" and -0.30 or default)
    return {callback = callback, step = step}
end
function fallbackHost.addColorOption(_, _, default, callback)
    callback(default)
    return {callback = callback}
end
local fallbackFramework = Framework.init(fallbackHost)
local savedCard = Shaders.init({framework = fallbackFramework, host = fallbackHost})
assert(savedCard.Options.Look.Value == "Frost" and savedCard.Options.Saturation.Value == -0.30,
    "saved options must survive widget callbacks before registration")
features.Shaders.toggle(true)
local savedColor = byName("ARMShaderColor")
assert(renderable(savedColor), "Lighting fallback must be direct")
assert(math.abs(savedColor.Saturation - (-0.35)) < 1e-6,
    "saved Saturation and Frost offset must be applied on enable")
Shaders.destroy()
assert(#children(lighting) == 1, "fallback is also cleaned up")
pass("saved options and Lighting service fallback work through initial widget callbacks")
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
