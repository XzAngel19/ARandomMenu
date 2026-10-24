#!/usr/bin/env python3
"""Run src/libraries/Entity.lua against a mocked Roblox API in Luau.

Guards the regression the user hit in Murderers VS Sheriffs Duels: the library
used to answer "nobody is a teammate" for every game that keeps its players
Neutral, so the ESP painted teammates the same red it paints enemies.

Usage:
    python3 tools/test_entity_team_provider.py
    LUAU=/tmp/luau-0.742/luau python3 tools/test_entity_team_provider.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "src" / "libraries" / "Entity.lua"

PRELUDE = r"""
-- ---------------------------------------------------------------- mocks ----
Vector3 = {}
Vector3.zero = nil

local function newVector3(x, y, z)
    return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, Vector3)
end

Vector3.new = newVector3
Vector3.zero = newVector3(0, 0, 0)

function Vector3.__index(self, key)
    if key == "Magnitude" then
        return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
    end
    return Vector3[key]
end

function Vector3.__sub(a, b)
    return newVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
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

function Vector3.GetUnit(self)
    local magnitude = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
    if magnitude < 0.000001 then
        return newVector3(0, 0, 0)
    end
    return newVector3(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
end

-- keep "Magnitude" and "Unit" resolving through the __index function
local vectorIndex = Vector3.__index
Vector3.__index = function(self, key)
    if key == "Unit" then
        return Vector3.GetUnit(self)
    end
    return vectorIndex(self, key)
end

local function signal()
    return {
        Connect = function(_self, _callback)
            return {Disconnect = function() end}
        end,
    }
end

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

function Instance:FindFirstChildWhichIsA(className)
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

function Instance:IsDescendantOf(_ancestor)
    return false
end

function Instance:WaitForChild(childName)
    return self.children[childName]
end

local function makeCharacter(name)
    local character = makeInstance("Model", name)
    local humanoid = makeInstance("Humanoid", "Humanoid")
    humanoid.Health = 100
    humanoid.MaxHealth = 100
    local root = makeInstance("Part", "HumanoidRootPart")
    root.Position = newVector3(0, 0, 0)
    root.CFrame = {Position = root.Position, LookVector = newVector3(0, 0, -1)}
    character.children.Humanoid = humanoid
    character.children.HumanoidRootPart = root
    character.CharacterAdded = signal()
    character.Parent = workspace
    return character
end

local function makePlayer(playerName, position)
    local player = makeInstance("Player", playerName)
    player.Neutral = true
    player.Team = nil
    player.CharacterAdded = signal()
    local character = makeCharacter(playerName)
    character.children.HumanoidRootPart.Position = position or newVector3(0, 0, 0)
    player.Character = character
    return player
end

workspace = makeInstance("Workspace", "Workspace")
workspace.DescendantAdded = signal()
workspace.DescendantRemoving = signal()
workspace.CurrentCamera = makeInstance("Camera", "Camera")

local localPlayer = makePlayer("Local", newVector3(0, 0, 0))
local teammate = makePlayer("Teammate", newVector3(5, 0, 0))
local enemy = makePlayer("Enemy", newVector3(10, 0, 0))

local players = {
    LocalPlayer = localPlayer,
    list = {localPlayer, teammate, enemy},
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

local game = {}
local services = {Players = players, RunService = {Heartbeat = signal()}}

function game:GetService(serviceName)
    return services[serviceName]
end

typeof = function(value)
    if type(value) == "table" and value.isInstance then
        return "Instance"
    end
    return type(value)
end

-- ------------------------------------------------------------- harness -----
state = {gameBridge = {}}

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

local ENTITY_SOURCE

local function loadEntityLibrary()
    local chunk, compileError = loadstring(ENTITY_SOURCE, "@src/libraries/Entity.lua")
    assert(type(chunk) == "function", "Entity.lua did not compile: " .. tostring(compileError))
    local module = chunk()
    local library = module.init({
        Players = players,
        LocalPlayer = localPlayer,
        workspace = workspace,
        state = state,
        services = {},
    })
    return module, library
end

ENTITY_SOURCE = [=====[
"""

EPILOGUE = r"""
]=====]

-- Case 1: a game that keeps everyone Neutral and publishes a team provider
-- (what Murderers VS Sheriffs Duels now does).
state.gameBridge.teamProvider = {
    Name = "MVSD",
    Get = function(instance)
        if instance == localPlayer or instance == teammate or instance == teammate.Character then
            return "sheriff"
        end
        if instance == enemy or instance == enemy.Character then
            return "murderer"
        end
        return nil
    end,
}

local module, library = loadEntityLibrary()

check("library initialized", module.Initialized, true)
check("provider: teammate friendly", library:IsFriendly(teammate), true)
check("provider: enemy not friendly", library:IsFriendly(enemy), false)
check("provider: local player never friendly", library:IsFriendly(localPlayer), false)

library:Refresh(true)
local teammateEntity = library:Get(teammate)
local enemyEntity = library:Get(enemy)
check("refresh indexed teammate", teammateEntity ~= nil, true)
check("refresh indexed enemy", enemyEntity ~= nil, true)
check("ESP sees teammate as friendly", teammateEntity.IsFriendly, true)
check("ESP sees enemy as hostile", enemyEntity.IsFriendly, false)
local surviving = library:InRange({Range = 100, IgnoreTeam = false, IgnoreWalls = true, IgnoreFriends = true})
local foundEnemy = false
local foundTeammate = false
for _, entity in ipairs(surviving) do
    if entity.Player == enemy then foundEnemy = true end
    if entity.Player == teammate then foundTeammate = true end
end
check("targeting keeps the enemy", foundEnemy, true)
check("targeting drops the teammate", foundTeammate, false)

module.destroy()

-- Case 2: no provider at all. The Neutral guard has to stay, otherwise every
-- Neutral server would suddenly report all players as teammates.
state.gameBridge.teamProvider = nil
local plainModule, plainLibrary = loadEntityLibrary()

check("no provider: neutral teammate not friendly", plainLibrary:IsFriendly(teammate), false)
check("no provider: neutral enemy not friendly", plainLibrary:IsFriendly(enemy), false)

plainModule.destroy()

-- Case 3: no provider, but the game does use the Teams service.
local blueTeam = makeInstance("Team", "Blue")
local redTeam = makeInstance("Team", "Red")
localPlayer.Team = blueTeam
localPlayer.Neutral = false
teammate.Team = blueTeam
teammate.Neutral = false
enemy.Team = redTeam
enemy.Neutral = false

local teamsModule, teamsLibrary = loadEntityLibrary()
check("teams service: teammate friendly", teamsLibrary:IsFriendly(teammate), true)
check("teams service: enemy not friendly", teamsLibrary:IsFriendly(enemy), false)
teamsModule.destroy()

-- Case 4: a relation-aware provider must not fall back to the shared Roblox
-- lobby Team when its MVS side is Unknown. That fallback made everyone green.
local unknown = makePlayer("Unknown", newVector3(15, 0, 0))
unknown.Team = blueTeam
unknown.Neutral = false
table.insert(players.list, unknown)
state.gameBridge.teamProvider = {
    Name = "MVSD-relation",
    GetRelation = function(instance)
        if instance == teammate or instance == teammate.Character then
            return "Teammate"
        end
        if instance == enemy or instance == enemy.Character then
            return "Enemy"
        end
        return "Unknown"
    end,
}
local relationModule, relationLibrary = loadEntityLibrary()
check("relation provider: teammate friendly", relationLibrary:IsFriendly(teammate), true)
check("relation provider: enemy not friendly", relationLibrary:IsFriendly(enemy), false)
check("relation provider: unknown never uses lobby team", relationLibrary:IsFriendly(unknown), false)
relationLibrary:Refresh(true)
local relationTargets = relationLibrary:InRange({
    Range = 100,
    IgnoreTeam = false,
    IgnoreWalls = true,
    IgnoreFriends = true,
})
local relationEnemyFound = false
local relationUnknownFound = false
local relationTeammateFound = false
for _, entity in ipairs(relationTargets) do
    if entity.Player == enemy then relationEnemyFound = true end
    if entity.Player == unknown then relationUnknownFound = true end
    if entity.Player == teammate then relationTeammateFound = true end
end
check("relation targeting keeps confirmed enemy", relationEnemyFound, true)
check("relation targeting rejects unknown", relationUnknownFound, false)
check("relation targeting rejects teammate", relationTeammateFound, false)
relationModule.destroy()

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
