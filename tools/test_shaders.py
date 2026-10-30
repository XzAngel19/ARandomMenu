#!/usr/bin/env python3
"""Shaders: real module, mocked engine. Toggling it must change the picture.

The module only uses post-processing instances, so a mock that records the
property writes is enough to prove the wiring: enable -> effects created and
written, option change -> written again, disable -> folder destroyed and the
effects gone. It also pins the defaults: a card that turns on and changes
nothing is a card that "does nothing".
"""
import os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Render/Shaders.lua').read_text()

PRELUDE = r'''
local function pass(name) print("PASS\t" .. name) end
Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b)
    return setmetatable({R = r or 0, G = g or 0, B = b or 0}, Color3)
end
function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
Color3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end

-- Every Instance.new is recorded so the test can inspect what the module built.
local instances = {}
local function destroyNode(node)
    for _, child in ipairs(table.clone(node.children)) do
        destroyNode(child)
    end
    for index, child in ipairs(node.parentNode and node.parentNode.children or {}) do
        if child == node then table.remove(node.parentNode.children, index) end
    end
    node.parentNode = nil
    node.destroyed = true
end
local lighting = {children = {}, Name = "Lighting"}
Instance = {}
function Instance.new(className)
    local node = {ClassName = className, Name = className, children = {},
        writes = 0}
    function node:Destroy() destroyNode(self) end
    local store = {Enabled = true}
    setmetatable(node, {
        __index = function(_, key)
            if key == "children" then return rawget(node, "children") end
            if key == "ClassName" or key == "Name" or key == "Parent"
                or key == "writes" then
                return rawget(node, key)
            end
            local value = store[key]
            if value ~= nil then return value end
            return nil
        end,
        __newindex = function(_, key, value)
            if key == "Parent" then
                if node.parentNode then
                    for index, child in ipairs(node.parentNode.children) do
                        if child == node then
                            table.remove(node.parentNode.children, index)
                            break
                        end
                    end
                end
                node.parentNode = value
                if value and value.children then table.insert(value.children, node) end
                return
            end
            if key == "Name" then rawset(node, "Name", value) return end
            store[key] = value
            rawset(node, "writes", (rawget(node, "writes") or 0) + 1)
        end,
    })
    table.insert(instances, node)
    return node
end

-- A card shaped like the real one: Options[name].Value plus the real methods.
local function newCard(definition)
    local card = {Name = definition.Name, Enabled = false, Options = {},
        Status = nil, Cleanup = {}}
    function card:SetStatus(status) self.Status = status end
    function card:Clean(item) table.insert(self.Cleanup, item) return item end
    function card:CleanAll()
        for index = #self.Cleanup, 1, -1 do
            local ok = pcall(self.Cleanup[index])
            self.Cleanup[index] = nil
        end
    end
    function card:RunCleanup() self:CleanAll() end
    function card:CreateDropdown(o)
        self.Options[o.Name] = {Value = o.List[o.Index or 1], Function = o.Function}
    end
    function card:CreateSlider(o)
        self.Options[o.Name] = {Value = o.Default or 0, Function = o.Function}
    end
    function card:CreateToggle(o)
        self.Options[o.Name] = {Value = o.Default == true, Function = o.Function}
    end
    function card:CreateColor(o)
        self.Options[o.Name] = {Value = o.Default or Color3.new(1, 1, 1), Function = o.Function}
    end
    function card:CreateNote() end
    -- Mirrors the real toggle: the module's Function runs with the new state.
    function card:SetEnabled(value)
        if value == self.Enabled then return end
        if value then
            self.Enabled = true
            definition.Function(true)
        else
            definition.Function(false)
            self.Enabled = false
            self:CleanAll()
        end
    end
    function card:Set(name, value)
        local option = self.Options[name]
        assert(option, "missing option " .. tostring(name))
        option.Value = value
        if type(option.Function) == "function" then option.Function(value) end
    end
    return card
end

local card
local context = {
    host = {Lighting = lighting},
    framework = {
        Categories = {
            Render = {
                CreateModule = function(_, definition)
                    card = newCard(definition)
                    return card
                end,
            },
        },
    },
}
'''

BODY = r'''
local function childrenOf(node, className)
    local found = {}
    for _, child in ipairs(node.children) do
        if child.ClassName == className and not child.destroyed then
            table.insert(found, child)
        end
    end
    return found
end

local Module = assert(loadstring(MODULE_SOURCE))()
local result = Module.init(context)
assert(result == card, "init must return the card")
assert(childrenOf(lighting, "Folder")[1] == nil, "nothing is created before enabling")

-- 1) Enabling builds the three effects under one folder.
card:SetEnabled(true)
local folders = childrenOf(lighting, "Folder")
assert(#folders == 1, "one folder, got " .. tostring(#folders))
assert(folders[1].Name == "ARandomMenuShaders")
local color = childrenOf(folders[1], "ColorCorrectionEffect")[1]
local bloom = childrenOf(folders[1], "BloomEffect")[1]
local rays = childrenOf(folders[1], "SunRaysEffect")[1]
assert(color and bloom and rays, "all three effects must exist")
pass("shaders: enabling creates the effects inside its own folder")

-- 2) The defaults are VISIBLE. A module that turns on and changes nothing is
--    exactly the bug this test exists for: every channel neutral is not a
--    default, it is a no-op.
assert(card.Options.Look.Value ~= "None", "no neutral look by default")
assert(bloom.Enabled == true and bloom.Intensity > 0.3,
    "bloom must be visible by default, got " .. tostring(bloom.Intensity))
assert(color.Enabled == true)
assert(color.Saturation ~= 0 or color.Contrast ~= 0,
    "the colour pass must differ from neutral on enable")

-- 3) A look is applied on top of the sliders.
card:Set("Look", "Noir")
assert(card.Status == "Noir", "the status names the look")
assert(color.Saturation == -1, "Noir drains the colour, got " .. tostring(color.Saturation))
assert(color.Contrast > 0.2, "Noir adds contrast")
pass("shaders: the Look preset is written to the effect")

-- 4) Sliders still work on top of the preset, and are clamped.
card:Set("Saturation", 0.5)
assert(color.Saturation == -0.5, "slider plus look, got " .. tostring(color.Saturation))
card:Set("Saturation", 5)
assert(color.Saturation == 1, "the sum is clamped to 1, got " .. tostring(color.Saturation))
card:Set("Contrast", 0.5)
assert(color.Contrast <= 1, "contrast is clamped")
card:Set("Look", "None")
assert(color.Saturation == 1, "back to the slider alone")
pass("shaders: sliders are added to the look and clamped to the effect range")

-- 5) Bloom and sun rays follow their own switches.
card:Set("Bloom", 0)
assert(bloom.Enabled == false, "zero bloom disables the effect")
card:Set("Bloom", 1.5)
assert(bloom.Enabled == true and bloom.Intensity >= 1.5)
card:Set("Sun rays", 0.6)
assert(rays.Enabled == true and math.abs(rays.Intensity - 0.6) < 1e-6)
card:Set("Sun rays", 0)
assert(rays.Enabled == false, "zero rays disable the effect")
pass("shaders: bloom and sun rays switch themselves off at zero")

-- 6) The tint blends with the look's own tint.
card:Set("Tint", Color3.new(1, 0, 0))
card:Set("Look", "Frost")
assert(color.TintColor.R < 1 and color.TintColor.B > 0.5,
    "Frost blends toward blue, got " .. tostring(color.TintColor.B))
card:Set("Look", "None")
assert(color.TintColor.R == 1 and color.TintColor.G == 0 and color.TintColor.B == 0,
    "None leaves the hand-picked tint alone")
pass("shaders: the tint blends with the look and survives it")

-- 7) Turning it off removes everything it built.
card:SetEnabled(false)
assert(#childrenOf(lighting, "Folder") == 0, "the folder is destroyed")
assert(#lighting.children == 0, "Lighting is left exactly as it was")
pass("shaders: disabling destroys the folder and leaves Lighting clean")

-- 8) Turning it on again rebuilds it (the module must be reusable).
card:SetEnabled(true)
local again = childrenOf(lighting, "Folder")
assert(#again == 1 and #childrenOf(again[1], "ColorCorrectionEffect") == 1,
    "enabling again rebuilds the effects")
card:SetEnabled(false)
assert(#lighting.children == 0)
pass("shaders: enabling again rebuilds exactly one set of effects")
'''

assert ']==]' not in SOURCE
script = (
    PRELUDE
    + "local MODULE_SOURCE = [==[\n" + SOURCE + "\n]==]\n"
    + BODY
)

with tempfile.TemporaryDirectory(prefix='shaders-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
