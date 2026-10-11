#!/usr/bin/env python3
"""Build and run a Luau harness that executes the real MVSD base module.

The shipped source is embedded verbatim, loaded with loadstring and initialized
against mocked Roblox services, so what runs here is the same code the executor
runs in game - not a re-implementation of it.

Usage:
    python3 tools/test_mvsd_teams.py            # needs luau on PATH
    LUAU=/tmp/luau-0.742/luau python3 tools/test_mvsd_teams.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "src" / "games" / "MVSD" / "base.lua"

PRELUDE = r"""
-- ---------------------------------------------------------------- mocks ----
local instances = {}

local Instance = {}
Instance.__index = Instance

local function makeInstance(className, name)
    local self = setmetatable({}, Instance)
    self.ClassName = className
    self.Name = name or className
    self.children = {}
    self.attributes = {}
    self.isInstance = true
    instances[self] = true
    return self
end

function Instance:GetAttribute(attributeName)
    return self.attributes[attributeName]
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

local function makePlayer(playerName)
    local player = makeInstance("Player", playerName)
    player.Team = nil
    player.Neutral = true

    -- Modules only treat a player as a live target with a character and a
    -- humanoid above zero health, so the mock has to look like one.
    local character = makeInstance("Model", playerName)
    local humanoid = makeInstance("Humanoid", "Humanoid")
    humanoid.Health = 100
    humanoid.MaxHealth = 100
    character.children.Humanoid = humanoid
    player.Character = character
    return player
end

local players = {LocalPlayer = nil, list = {}}

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

local heartbeatConnections = 0
local heartbeat = {}

function heartbeat:Connect(_callback)
    heartbeatConnections += 1
    return {
        Disconnect = function()
            heartbeatConnections -= 1
        end,
    }
end

local runService = {Heartbeat = heartbeat}
local services = {Players = players, RunService = runService}

game = {}

function game:GetService(serviceName)
    return services[serviceName]
end

-- The module reads typeof(value) == "Instance"; the CLI's typeof only knows
-- the built-in types, so instances are recognised by the marker field.
typeof = function(value)
    if type(value) == "table" and value.isInstance then
        return "Instance"
    end
    return type(value)
end

-- ------------------------------------------------------- menu host mocks ---
local createdFeatures = {}
local createdOptions = {}
local registeredProvider = nil

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
    }
    table.insert(createdFeatures, feature)
    return feature
end

addToggleOption = function(feature, label, defaultValue, callback, hint)
    table.insert(createdOptions, {
        kind = "toggle", feature = feature, label = label,
        defaultValue = defaultValue, callback = callback, hint = hint,
    })
end

addCycleOption = function(feature, label, values, index, callback, hint)
    table.insert(createdOptions, {
        kind = "cycle", feature = feature, label = label, values = values,
        index = index, callback = callback, hint = hint,
    })
end

addActionOption = function(feature, label, callback, hint)
    table.insert(createdOptions, {
        kind = "action", feature = feature, label = label,
        callback = callback, hint = hint,
    })
end

registerTeamProvider = function(provider)
    registeredProvider = provider
    -- mirrors state.registerTeamProvider in src/Wurst.lua
    state.gameBridge.teamProvider = provider
    state.teamProvider = provider
end

-- --------------------------------------------------------------- runner ----
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

local function countOptions(kind)
    local total = 0
    for _, option in ipairs(createdOptions) do
        if option.kind == kind then
            total += 1
        end
    end
    return total
end

local source = [=====[
"""

EPILOGUE = r"""
]=====]

local chunk, compileError = loadstring(source, "@src/games/MVSD/base.lua")
assert(type(chunk) == "function", "module did not compile: " .. tostring(compileError))

local Module = chunk()
check("module name", Module.Name, "MVSD")
check("module exports init", type(Module.init), "function")
check("module exports destroy", type(Module.destroy), "function")

local me = makePlayer("Local")
me.attributes.Role = "Sheriff"
players.LocalPlayer = me
players.list = {me}

Module.init({Menu = {}, TaskManager = {}})
check("module initialized", Module.Initialized, true)
check("provider registered", type(registeredProvider), "table")
check("provider.Get", type(registeredProvider.Get), "function")
check("provider.IsFriendly", type(registeredProvider.IsFriendly), "function")
check("state.mvsdCore published", type(state.mvsdCore), "table")

-- Scenario A: the game spells the role out in a player attribute.
local ally = makePlayer("Ally")
ally.attributes.Role = "Sheriff"
local foe = makePlayer("Foe")
foe.attributes.Role = "Murderer"
players.list = {me, ally, foe}

check("A teammate is friendly", registeredProvider.IsFriendly(ally), true)
check("A enemy is not friendly", registeredProvider.IsFriendly(foe), false)
check("A tokens match", registeredProvider.Get(ally), registeredProvider.Get(me))
check("A tokens differ", registeredProvider.Get(foe) ~= registeredProvider.Get(me), true)
check("A core.isEnemy(foe)", state.mvsdCore.isEnemy(foe), true)
check("A core.isTeammate(ally)", state.mvsdCore.isTeammate(ally), true)
check("A core.roleOf(me)", state.mvsdCore.roleOf(me), "Sheriff")
check("A enemy list size", #state.mvsdCore.enemies(), 1)

state.mvsdCore.clearCache()

-- Scenario B: only a numeric side id exists.
local numericAlly = makePlayer("NumericAlly")
numericAlly.attributes.Team = 1
local numericFoe = makePlayer("NumericFoe")
numericFoe.attributes.Team = 2
local numericMe = me
numericMe.attributes.Role = nil
numericMe.attributes.Team = 1
players.list = {numericMe, numericAlly, numericFoe}

check("B numeric teammate friendly", registeredProvider.IsFriendly(numericAlly), true)
check("B numeric enemy not friendly", registeredProvider.IsFriendly(numericFoe), false)
check("B numeric token", registeredProvider.Get(numericAlly), "attr:1")

state.mvsdCore.clearCache()

-- Scenario C: the Teams service carries the side.
me.attributes.Team = nil
local teamSheriffs = makeInstance("Team", "Sheriffs")
local teamMurderers = makeInstance("Team", "Murderers")
me.Team = teamSheriffs
local teamAlly = makePlayer("TeamAlly")
teamAlly.Team = teamSheriffs
local teamFoe = makePlayer("TeamFoe")
teamFoe.Team = teamMurderers
players.list = {me, teamAlly, teamFoe}

check("C teams teammate friendly", registeredProvider.IsFriendly(teamAlly), true)
check("C teams enemy not friendly", registeredProvider.IsFriendly(teamFoe), false)
check("C teams token", registeredProvider.Get(teamAlly), "sheriff")

state.mvsdCore.clearCache()

-- Scenario D: nothing to read. Unknown must read as an enemy, never a friend.
me.Team = nil
local blank = makePlayer("Blank")
players.list = {me, blank}

check("D unknown token", registeredProvider.Get(blank), nil)
check("D unknown not friendly", registeredProvider.IsFriendly(blank), false)
check("D unknown is enemy", state.mvsdCore.isEnemy(blank), true)
check("D model lookup works", registeredProvider.Get(blank.Character or blank), nil)

state.mvsdCore.clearCache()

-- Scenario E: a player from another lobby is never a teammate.
me.attributes.Role = "Sheriff"
me.attributes.Game = "lobby-1"
local otherLobby = makePlayer("OtherLobby")
otherLobby.attributes.Role = "Sheriff"
otherLobby.attributes.Game = "lobby-2"
local sameLobby = makePlayer("SameLobby")
sameLobby.attributes.Role = "Sheriff"
sameLobby.attributes.Game = "lobby-1"
players.list = {me, otherLobby, sameLobby}

check("E other lobby not friendly", registeredProvider.IsFriendly(otherLobby), false)
check("E same lobby friendly", registeredProvider.IsFriendly(sameLobby), true)

-- Scenario F: the menu card and its options.
check("F one card created", #createdFeatures, 1)
check("F card name", createdFeatures[1].name, "Team Detection")
check("F card category", createdFeatures[1].configuration.categoryName, "Render")
check("F card registry is mvsdFeatures", createdFeatures[1].configuration.registry == state.mvsdFeatures, true)
check("F toggle options", countOptions("toggle"), 2)
check("F cycle options", countOptions("cycle"), 1)
check("F action options", countOptions("action"), 1)

createdFeatures[1].onToggle(true)
check("F enabling starts diagnostics", heartbeatConnections, 1)
createdFeatures[1].onToggle(false)
check("F disabling stops diagnostics", heartbeatConnections, 0)

Module.destroy()
check("destroy clears core", state.mvsdCore, nil)
check("destroy clears provider", state.gameBridge.teamProvider, nil)
check("destroy clears state.teamProvider", state.teamProvider, nil)

print(string.format("%d check(s), %d failure(s)", checks, failures))
if failures > 0 then
    error(failures .. " check(s) failed")
end
"""


def main() -> int:
    luau = os.environ.get("LUAU", "luau")
    module_source = MODULE.read_text(encoding="utf-8")
    script = PRELUDE + module_source + EPILOGUE

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
