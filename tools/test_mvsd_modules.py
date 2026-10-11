#!/usr/bin/env python3
"""Initialize every MVSD feature module in Luau against mocked Roblox APIs.

This is the regression the user reported: the modules called a widget helper
(`addButtonOption`) that does not exist, so `Module.init` raised, the loader
rolled the whole section back and not one MVSD card reached the menu. Running
the real sources here proves each card is built and each option is registered.

Usage:
    python3 tools/test_mvsd_modules.py
    LUAU=/tmp/luau-0.742/luau python3 tools/test_mvsd_modules.py
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [
    "src/games/MVSD/base.lua",
    "src/games/MVSD/Blatant/SilentAim.lua",
    "src/games/MVSD/Other/Shoot.lua",
    "src/games/MVSD/Blatant/Knife.lua",
    "src/games/MVSD/Blatant/AutoWin.lua",
]

PRELUDE = r"""
-- ---------------------------------------------------------------- mocks ----
local function signal()
    return {
        Connect = function(_self, _callback)
            return {Disconnect = function() end}
        end,
    }
end

local Vector3 = {}
local function newVector3(x, y, z)
    return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, Vector3)
end
function Vector3.__index(self, key)
    if key == "Magnitude" then
        return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
    end
    return Vector3[key]
end
function Vector3.__sub(a, b)
    return newVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function Vector3.__add(a, b)
    return newVector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function Vector3.__mul(a, b)
    if type(b) == "number" then
        return newVector3(a.X * b, a.Y * b, a.Z * b)
    end
    return newVector3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
function Vector3.Dot(self, other)
    return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end
local vector3Metatable = getmetatable(newVector3(0, 0, 0))
vector3Metatable.new = newVector3
vector3Metatable.zero = newVector3(0, 0, 0)
vector3Metatable.one = newVector3(1, 1, 1)

local function autoEnum()
    local proxy = {}
    setmetatable(proxy, {__index = function(self, key)
        local child = autoEnum()
        rawset(self, key, child)
        return child
    end})
    return proxy
end

local Instance = {}
Instance.__index = Instance

local function makeInstance(className, name)
    local self = setmetatable({}, Instance)
    self.ClassName = className
    self.Name = name or className
    self.children = {}
    self.attributes = {}
    self.isInstance = true
    return self
end

function Instance:GetAttribute(attributeName)
    return self.attributes[attributeName]
end

function Instance:SetAttribute(attributeName, value)
    self.attributes[attributeName] = value
end

function Instance:FindFirstChild(childName)
    return self.children[childName]
end

function Instance:FindFirstChildOfClass(className)
    for _, child in pairs(self.children) do
        if child.ClassName == className then
            return child
        end
    end
    return nil
end

function Instance:FindFirstChildWhichIsA(className)
    return self:FindFirstChildOfClass(className)
end

function Instance:GetChildren()
    local list = {}
    for _, child in pairs(self.children) do
        table.insert(list, child)
    end
    return list
end

function Instance:GetDescendants()
    local list = {}
    local function walk(node)
        for _, child in pairs(node.children) do
            table.insert(list, child)
            walk(child)
        end
    end
    walk(self)
    return list
end

function Instance:IsA(className)
    return self.ClassName == className
end

function Instance:WaitForChild(childName)
    return self.children[childName]
end

function Instance:Destroy()
    self.destroyed = true
end

local function makeCharacter(name, position)
    local character = makeInstance("Model", name)
    local humanoid = makeInstance("Humanoid", "Humanoid")
    humanoid.Health = 100
    humanoid.MaxHealth = 100
    local root = makeInstance("Part", "HumanoidRootPart")
    root.Position = position or newVector3(0, 0, 0)
    root.CFrame = {Position = root.Position, LookVector = newVector3(0, 0, -1)}
    local head = makeInstance("Part", "Head")
    head.Position = position or newVector3(0, 0, 0)
    character.children.Humanoid = humanoid
    character.children.HumanoidRootPart = root
    character.children.Head = head
    character.PrimaryPart = root
    character.Parent = workspace
    return character
end

local function makePlayer(playerName, position)
    local player = makeInstance("Player", playerName)
    player.Neutral = true
    player.Team = nil
    player.CharacterAdded = signal()
    player.Character = makeCharacter(playerName, position)
    return player
end

workspace = makeInstance("Workspace", "Workspace")
workspace.DescendantAdded = signal()
workspace.DescendantRemoving = signal()
workspace.CurrentCamera = makeInstance("Camera", "Camera")
workspace.CurrentCamera.CFrame = {
    Position = newVector3(0, 5, 0),
    LookVector = newVector3(0, 0, -1),
}
function workspace.CurrentCamera:WorldToViewportPoint(position)
    return newVector3(100, 100, 10), true
end
function workspace:Raycast(_origin, _direction, _params)
    return nil
end

local localPlayer = makePlayer("Local", newVector3(0, 0, 0))
local ally = makePlayer("Ally", newVector3(4, 0, 0))
local enemy = makePlayer("Enemy", newVector3(12, 0, 0))
ally.attributes.Role = "Sheriff"
localPlayer.attributes.Role = "Sheriff"
enemy.attributes.Role = "Murderer"

local players = {
    LocalPlayer = localPlayer,
    list = {localPlayer, ally, enemy},
    PlayerAdded = signal(),
    PlayerRemoving = signal(),
}

function players:GetPlayers()
    return self.list
end

function players:GetPlayerFromCharacter(character)
    for _, player in ipairs(self.list) do
        if player.Character == character then
            return player
        end
    end
    return nil
end

local replicatedStorage = makeInstance("ReplicatedStorage", "ReplicatedStorage")
local userInput = {
    InputBegan = signal(),
    InputEnded = signal(),
    GetMouseLocation = function(_self)
        return newVector3(200, 200, 0)
    end,
    IsKeyDown = function(_self, _key)
        return false
    end,
}
local runService = {Heartbeat = signal(), RenderStepped = signal()}
local tweenService = {
    Create = function(_self, _instance, _info, _goals)
        return {Play = function() end, Completed = signal()}
    end,
}

local services = {
    Players = players,
    RunService = runService,
    ReplicatedStorage = replicatedStorage,
    UserInputService = userInput,
    TweenService = tweenService,
    Lighting = makeInstance("Lighting", "Lighting"),
    HttpService = {JSONEncode = function(_self, value) return tostring(value) end},
}

game = makeInstance("DataModel", "game")

function game:GetService(serviceName)
    return services[serviceName]
end

function game:HttpGet(_url)
    return ""
end

typeof = function(value)
    if type(value) == "table" and value.isInstance then
        return "Instance"
    end
    return type(value)
end

-- Executor/Roblox globals the modules touch while wiring themselves up.
Enum = autoEnum()
Vector3 = vector3Metatable
CFrame = {
    new = function(x, y, z)
        return {
            Position = newVector3(x or 0, y or 0, z or 0),
            LookVector = newVector3(0, 0, -1),
        }
    end,
    lookAt = function(from, to)
        return {Position = from, LookVector = newVector3(0, 0, -1), target = to}
    end,
}
RaycastParams = {
    new = function()
        return {FilterDescendantsInstances = {}, IgnoreWater = true}
    end,
}
Color3 = {
    fromRGB = function(r, g, b)
        return {R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255}
    end,
    new = function(r, g, b)
        return {R = r or 0, G = g or 0, B = b or 0}
    end,
}
UDim2 = {
    fromScale = function(x, y) return {X = x, Y = y} end,
    fromOffset = function(x, y) return {X = x, Y = y} end,
    new = function(a, b, c, d) return {a, b, c, d} end,
}
TweenInfo = {new = function() return {} end}
task = {
    spawn = function(callback) return callback() end,
    defer = function(callback) return callback() end,
    wait = function() return 0 end,
    delay = function(_seconds, callback) return callback() end,
}
tick = function() return os.clock() end
Instance.new = makeInstance

-- ------------------------------------------------------- menu host mocks ---
local createdFeatures = {}
local createdOptions = {}

state = {
    mvsdScroll = {},
    mvsdFeatures = {},
    gameBridge = {},
}

createUniversalFeature = function(name, description, layoutOrder, onToggle, configuration)
    local feature = {
        name = name,
        description = description,
        layoutOrder = layoutOrder,
        onToggle = onToggle,
        configuration = configuration,
        optionCount = 0,
    }
    table.insert(createdFeatures, feature)
    return feature
end

local function recordOption(kind, feature, label, extra)
    local option = {kind = kind, feature = feature, label = label}
    for key, value in pairs(extra or {}) do
        option[key] = value
    end
    table.insert(createdOptions, option)
    feature.optionCount += 1
    return option
end

addToggleOption = function(feature, label, defaultValue, callback, hint)
    return recordOption("toggle", feature, label, {
        defaultValue = defaultValue, callback = callback, hint = hint,
    })
end

addNumberOption = function(feature, label, defaultValue, minimum, maximum, callback, hint, step)
    return recordOption("number", feature, label, {
        defaultValue = defaultValue, minimum = minimum, maximum = maximum,
        callback = callback, hint = hint, step = step,
    })
end

addCycleOption = function(feature, label, values, index, callback, hint)
    return recordOption("cycle", feature, label, {
        values = values, index = index, callback = callback, hint = hint,
    })
end

addActionOption = function(feature, label, callback, hint)
    return recordOption("action", feature, label, {callback = callback, hint = hint})
end

addKeyOption = function(feature, label, defaultValue, callback, hint)
    return recordOption("key", feature, label, {callback = callback, hint = hint})
end

addColorOption = function(feature, label, defaultValue, callback, hint)
    return recordOption("color", feature, label, {callback = callback, hint = hint})
end

addInformationOption = function(feature, text)
    return recordOption("info", feature, text, {})
end

registerTeamProvider = function(provider)
    state.gameBridge.teamProvider = provider
    state.teamProvider = provider
end

registerRoleProvider = function(provider)
    state.gameBridge.roleProvider = provider
end

registerEspExtra = function(extra)
    state.gameBridge.extras = state.gameBridge.extras or {}
    table.insert(state.gameBridge.extras, extra)
end

notify = function(text)
    print("notify: " .. tostring(text))
end

-- ------------------------------------------------------------- harness -----
local failures = 0
local checks = 0

local function check(label, actual, expected)
    checks += 1
    if actual ~= expected then
        failures += 1
        print("FAIL " .. label .. ": got " .. tostring(actual)
            .. " expected " .. tostring(expected))
    else
        print("ok   " .. label .. " = " .. tostring(actual))
    end
end

local function findFeature(name)
    for _, feature in ipairs(createdFeatures) do
        if feature.name == name then
            return feature
        end
    end
    return nil
end

local function countOptions(feature)
    local total = 0
    for _, option in ipairs(createdOptions) do
        if option.feature == feature then
            total += 1
        end
    end
    return total
end

local function loadModule(source, path)
    local chunk, compileError = loadstring(source, "@" .. path)
    assert(type(chunk) == "function", path .. " did not compile: " .. tostring(compileError))
    return chunk()
end

local runtime = {
    Menu = {Root = {}, ScreenGui = {}, Pages = {}, Components = {}, Notify = notify},
    State = state,
    TaskManager = {
        Connect = function(_self, signalObject, callback)
            return signalObject:Connect(callback)
        end,
    },
    Diagnostics = {uiBindings = 0, taskBindings = 0},
}

local SOURCES = {
"""

EPILOGUE = r"""
}

-- The real load order: base.lua first, because the feature modules delegate
-- their team check to state.mvsdCore.
for _, entry in ipairs(SOURCES) do
    local module = loadModule(entry.source, entry.path)
    check(entry.path .. " exposes init", type(module.init), "function")
    check(entry.path .. " exposes destroy", type(module.destroy), "function")

    local ok, result = pcall(module.init, runtime)
    check(entry.path .. " initialized", ok and module.Initialized == true, true)
    if not ok then
        print("    error: " .. tostring(result))
    end

    local expected = entry.featureName
    local feature = findFeature(expected)
    check(entry.path .. " created card '" .. expected .. "'", feature ~= nil, true)
    if feature then
        check(entry.path .. " card options", countOptions(feature), entry.minimumOptions)
        check(entry.path .. " card registry", feature.configuration.registry == state.mvsdFeatures, true)
        check(entry.path .. " card category", feature.configuration.categoryName, entry.category)
    end

    if entry.destroy then
        module.destroy()
        check(entry.path .. " destroyed", module.Initialized, false)
    end
end

-- The MVSD Shoot card carries the action button that used to raise.
local shootFeature = findFeature("Shoot")
if shootFeature then
    local sawAction = false
    for _, option in ipairs(createdOptions) do
        if option.feature == shootFeature and option.kind == "action" then
            sawAction = true
        end
    end
    check("Shoot card has an action button", sawAction, true)
end

print(string.format("%d check(s), %d failure(s)", checks, failures))
if failures > 0 then
    error(failures .. " check(s) failed")
end
"""

FEATURES = {
    "src/games/MVSD/base.lua": ("Team Detection", "Render", True),
    "src/games/MVSD/Blatant/SilentAim.lua": ("Silent Aim", "Blatant", True),
    "src/games/MVSD/Other/Shoot.lua": ("Shoot", "Other", True),
    "src/games/MVSD/Blatant/Knife.lua": ("Knife", "Blatant", True),
    "src/games/MVSD/Blatant/AutoWin.lua": ("AutoWin", "Blatant", True),
}

OPTION_HELPERS = (
    "addToggleOption",
    "addNumberOption",
    "addCycleOption",
    "addActionOption",
    "addKeyOption",
    "addColorOption",
    "addInformationOption",
)


def count_option_calls(source: str) -> int:
    """Count option-helper call sites, skipping the `local x = env.x` lines."""
    total = 0
    for helper in OPTION_HELPERS:
        for match in re.finditer(rf"\b{helper}\s*\(", source):
            line_start = source.rfind("\n", 0, match.start()) + 1
            line = source[line_start : source.find("\n", match.start())]
            if "env." + helper in line:
                continue
            total += 1
    return total


def main() -> int:
    luau = os.environ.get("LUAU", "luau")

    entries = []
    for relative in SOURCES:
        source = (ROOT / relative).read_text(encoding="utf-8")
        name, category, destroy = FEATURES[relative]
        minimum = count_option_calls(source)
        entries.append(
            "    {path = \"%s\", featureName = \"%s\", minimumOptions = %d, "
            "category = \"%s\", destroy = %s, source = [=====[\n%s\n]=====]},"
            % (
                relative,
                name,
                minimum,
                category,
                "true" if destroy else "false",
                source,
            )
        )

    script = PRELUDE + "\n".join(entries) + "\n" + EPILOGUE

    with tempfile.NamedTemporaryFile(
        "w", suffix=".lua", delete=False, encoding="utf-8"
    ) as handle:
        handle.write(script)
        path = handle.name

    try:
        result = subprocess.run([luau, path], capture_output=True, text=True)
    finally:
        os.unlink(path)

    sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
