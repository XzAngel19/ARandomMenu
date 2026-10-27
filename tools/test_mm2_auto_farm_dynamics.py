#!/usr/bin/env python3
"""Run the rebuilt MM2 Auto Farm against deterministic Roblox-shaped mocks.

This checks that the farm walks with native Humanoid locomotion, only credits
server CoinCollected events, stops at the announced bag limit, respects
lobby/round/role guards and releases every connection on OFF. It does NOT
prove that a live server awards a coin for a physical overlap.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/AutoFarm.lua").read_text()

HARNESS = r'''
local Vector3 = {}
local vmt = {}
function Vector3.new(x, y, z)
    return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vmt)
end
Vector3.zero = Vector3.new(0, 0, 0)
vmt.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vmt.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vmt.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    if type(b) == "table" then return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
    return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
vmt.__div = function(a, b) return a * (1 / b) end
vmt.__index = function(a, k)
    if k == "Magnitude" then
        return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    end
end
local CFrame = {new = function(p) return {Position = p} end}

local now = 0
os = {clock = function() return now end, time = function() return now end}
task = {spawn = function(fn) fn() end, wait = function() end, defer = function(fn) fn() end}
Enum = {
    Material = {Air = "Air"},
    RenderPriority = {Character = {Value = 200}},
    RaycastFilterType = {Exclude = "Exclude"},
    PathStatus = {Success = "Success"},
}
RaycastParams = nil

local function signal()
    local s = {listeners = {}}
    function s:Connect(fn)
        self.listeners[fn] = true
        local alive = true
        return {Disconnect = function()
            if alive then
                alive = false
                self.listeners[fn] = nil
            end
        end}
    end
    function s:Fire(...)
        for fn in pairs(self.listeners) do fn(...) end
    end
    function s:count()
        local n = 0
        for _ in pairs(self.listeners) do n += 1 end
        return n
    end
    return s
end

local function remoteEvent(name)
    local event = {Name = name, className = "RemoteEvent", OnClientEvent = signal()}
    return event
end

local gameplay = {}
local remoteNames = {"CoinsStarted", "CoinCollected", "RoundStart",
    "VictoryScreen", "RoundEndFade", "PlayerDataChanged"}
for _, name in ipairs(remoteNames) do
    gameplay[name] = remoteEvent(name)
end
function gameplay:FindFirstChild(name) return self[name] end

local inventoryEvent = remoteEvent("ChangeInventoryItem")
local inventoryFolder = {ChangeInventoryItem = inventoryEvent}
function inventoryFolder:FindFirstChild(name)
    if name == "ChangeInventoryItem" then return inventoryEvent end
    return nil
end
local remotesFolder = {Inventory = inventoryFolder}
function remotesFolder:FindFirstChild(name) return self[name] end
local replicated = {Remotes = remotesFolder}
function replicated:FindFirstChild(name) return self[name] end

local timer = {GetAttribute = function(_, name)
    if name == "Time" then return 120 end
    return nil
end}
local spawnFolder = {}
function spawnFolder:GetChildren()
    return {{Position = Vector3.new(50, 10, 50)}}
end
local map = {}
function map:FindFirstChild(name)
    if name == "Spawns" then return spawnFolder end
    return nil
end

local workspaceMock = {
    FindFirstChild = function(_, name)
        if name == "RoundTimerPart" then return timer end
        return nil
    end,
    GetDescendants = function() return {} end,
}

game = {GetService = function(_, name)
    if name == "ReplicatedStorage" then return replicated end
    if name == "CollectionService" then return {GetTagged = function() return {} end} end
    return nil -- PathfindingService is unavailable: Direct fallback
end}

local written = {CFrame = 0, Size = 0, AssemblyLinearVelocity = 0}
local rootData = {
    Position = Vector3.new(0, 10, 0),
    CFrame = CFrame.new(Vector3.new(0, 10, 0)),
    Parent = true,
    AssemblyLinearVelocity = Vector3.zero,
    AssemblyAngularVelocity = Vector3.zero,
    AssemblyMass = 10,
}
local root = setmetatable({}, {
    __index = rootData,
    __newindex = function(_, k, v)
        if written[k] ~= nil then written[k] += 1 end
        rootData[k] = v
    end,
})

local pivotCalls = 0
local character = {
    Parent = workspaceMock,
    PivotTo = function() pivotCalls += 1 end,
}
local moveCalls, moveToCalls = {}, {}
local humanoid = {
    Health = 100,
    WalkSpeed = 16,
    MoveDirection = Vector3.zero,
    FloorMaterial = "Ground",
    Move = function(_, dir) table.insert(moveCalls, dir) end,
    MoveTo = function(_, pos) table.insert(moveToCalls, pos) end,
}

local coinParent = {
    Name = "Coin_Server",
    Parent = map,
    Position = Vector3.new(10, 10, 0),
    CanTouch = true,
    GetAttribute = function(_, name)
        if name == "CoinID" then return "Coin" end
        return nil
    end,
}
local coinVisual = {
    Name = "CoinVisual",
    Parent = coinParent,
    Position = Vector3.new(10, 10, 0),
    CanTouch = true,
    GetAttribute = function(_, name)
        if name == "CoinID" then return "Coin" end
        return nil
    end,
}
local coinVisuals = {coinVisual}

local renderBindings = {}
local RunService = {}
function RunService:BindToRenderStep(name, _, fn) renderBindings[name] = fn end
function RunService:UnbindFromRenderStep(name) renderBindings[name] = nil end

local tasks = {}
local TaskManager = {}
function TaskManager:Connect(fn)
    local handle = {fn = fn, Disconnect = function(self)
        for i, entry in ipairs(tasks) do
            if entry == self then table.remove(tasks, i); break end
        end
    end}
    table.insert(tasks, handle)
    return handle
end
local featureConnections = {}
local function disconnectFeatureConnection(name)
    local handle = featureConnections[name]
    if handle then handle:Disconnect(); featureConnections[name] = nil end
end

local card
local options = {}
local stats = {}
state = {
    mm2CoinPickups = function() return coinVisuals end,
    mm2InvalidateCoinPickups = function() end,
    addStatOption = function(_, label)
        local stat = {set = function(value) stats[label] = value end}
        return stat
    end,
    addSectionOption = function() end,
    framework = {GetModule = function() return nil end},
    flingPhysics = nil,
}
state.frameworkEnvironment = {
    workspace = workspaceMock,
    LocalPlayer = {Name = "Me"},
    RunService = RunService,
    TaskManager = TaskManager,
    featureConnections = featureConnections,
    disconnectFeatureConnection = disconnectFeatureConnection,
    getCharacterParts = function() return character, humanoid, root end,
    createUniversalFeature = function(_, _, _, onToggle)
        card = {onToggle = onToggle, status = nil,
            SetStatus = function(self, text) self.status = text end}
        return card
    end,
    addCycleOption = function(_, label, _, _, callback) options[label] = callback end,
    addNumberOption = function(_, label, _, _, _, callback) options[label] = callback end,
    addToggleOption = function(_, label, _, callback) options[label] = callback end,
    addInformationOption = function() end,
}
services = {activity = {isActive = function() return false end}}
MM2Scroll = {}
mm2Features = {}
local phase, roundActive, role = "map", true, "Innocent"
state.mm2Core = {
    mm2GameplayRemotes = gameplay,
    getRoundPhase = function() return phase end,
    isRoundLifecycleActive = function() return roundActive end,
    findMM2Map = function() return map end,
    getPlayerRole = function() return role end,
}

local Module = (function()
__AUTOFARM_SOURCE__
end)()
Module.init({})

local function tick(dt)
    local handle = featureConnections.MM2AutoFarmTick
    assert(handle, "farm tick is not connected")
    handle.fn(dt)
end
local function render()
    local fn = renderBindings["WurstMM2AutoFarm"]
    assert(fn, "movement binding missing")
    fn()
end
local function check(label, condition)
    if not condition then error("FAIL " .. label, 2) end
    print("PASS " .. label)
end

-- Activation: one tick owner and one native movement binding.
card.onToggle(true)
check("activation owns exactly one scheduler task", #tasks == 1)
check("activation binds after default controls", renderBindings["WurstMM2AutoFarm"] ~= nil)
check("boot does not enable from config", card.status ~= nil)

-- First real step walks toward the actual Coin_Server part.
now = 0.5
tick(0.5)
local snap = state.mm2AutoFarmSnapshot()
check("target is the real server pickup", snap.targetName == "Coin_Server")
check("navigation defaults to Pathfinding", snap.navigation == "Pathfinding")
render()
check("native Move drives toward the coin", #moveCalls > 0
    and moveCalls[#moveCalls].X > 0.9 and moveCalls[#moveCalls].Y == 0)
check("no CFrame/Size/velocity writer while farming",
    written.CFrame == 0 and written.Size == 0
    and written.AssemblyLinearVelocity == 0)

-- Overlap the pickup: the farm waits for the server's own Touched handler.
rootData.Position = Vector3.new(9, 10, 0)
now = 1.0
tick(0.5)
snap = state.mm2AutoFarmSnapshot()
check("contact counts no coin before CoinCollected", snap.coinsConfirmed == 0)
check("contact status is Collecting", string.find(snap.status, "Collecting", 1, true) ~= nil)
check("no pivot used for collection", pivotCalls == 0)

-- Only the server event confirms a coin (and the persistent balance event is
-- observed but never counted as a second coin).
inventoryEvent.OnClientEvent:Fire("Materials", "Coins", 900)
gameplay.CoinCollected.OnClientEvent:Fire("Coin", 1, 50, {Value = 1})
snap = state.mm2AutoFarmSnapshot()
check("CoinCollected confirms exactly one coin", snap.coinsConfirmed == 1)
check("bag amount comes from the event", snap.bagAmount == 1 and snap.bagLimit == 50)
check("persistent balance is observed", snap.persistentCoins == 900)
now = 1.5
tick(0.5)
check("overlay reports the confirmed coin", stats["Coins Collected"] == "1")
check("overlay reports active time", stats["Time"] ~= nil)

-- CoinsStarted announces this round's real limit; reaching it stops walking.
gameplay.CoinsStarted.OnClientEvent:Fire({
    Coin = {CollectedAmount = 0, CollectionLimit = 2},
})
gameplay.CoinCollected.OnClientEvent:Fire("Coin", 1, 2, {Value = 1})
gameplay.CoinCollected.OnClientEvent:Fire("Coin", 2, 2, {Value = 1})
now = 2.0
tick(1.0)
snap = state.mm2AutoFarmSnapshot()
check("bag full is read from the server limit",
    snap.bagAmount == 2 and snap.bagLimit == 2)
check("full bag stops the farm", string.find(snap.status, "Bag full", 1, true) ~= nil)

-- Lobby / role guards fail closed.
phase = "lobby"
gameplay.CoinsStarted.OnClientEvent:Fire({
    Coin = {CollectedAmount = 0, CollectionLimit = 50},
})
now = 2.5
tick(0.5)
check("lobby pauses farming",
    string.find(state.mm2AutoFarmSnapshot().status, "Waiting", 1, true) ~= nil)
phase = "map"
role = "Murderer"
now = 3.0
tick(0.5)
check("non-Innocent role pauses farming",
    string.find(state.mm2AutoFarmSnapshot().status, "Waiting", 1, true) ~= nil)
role = "Innocent"

-- Direct navigation is still native locomotion, never a teleport.
options["Navigation"]("Direct")
now = 3.5
tick(0.5)
render()
check("Direct mode keeps native Move", #moveCalls > 1)
check("no teleport in any mode", written.CFrame == 0 and pivotCalls == 0)

-- OFF releases the frame task, the render binding and every remote listener.
card.onToggle(false)
check("OFF disconnects the farm tick", featureConnections.MM2AutoFarmTick == nil)
check("OFF unbinds movement", renderBindings["WurstMM2AutoFarm"] == nil)
check("OFF leaves scheduler empty", #tasks == 0)
check("OFF clears status", card.status == nil)
local listeners = 0
for _, name in ipairs(remoteNames) do
    listeners += gameplay[name].OnClientEvent:count()
end
listeners += inventoryEvent.OnClientEvent:count()
check("OFF disconnects every remote listener", listeners == 0)
check("feature exposes a read-only snapshot",
    type(state.mm2AutoFarmSnapshot) == "function")
Module.destroy()
check("destroy clears the published snapshot", state.mm2AutoFarmSnapshot == nil)
print("[MM2 AUTO FARM v150] dynamics verified")
'''

script = HARNESS.replace("__AUTOFARM_SOURCE__", SOURCE)

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "auto_farm_v150.luau"
    path.write_text(script)
    luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
    result = subprocess.run([luau, str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())
