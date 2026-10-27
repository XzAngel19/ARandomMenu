#!/usr/bin/env python3
"""Run MM2 Auto Farm v151 against deterministic Roblox-shaped mocks.

This checks Below Map's two physical placements, bounded contact refresh,
manual-control override, server-only coin confirmation, full-bag stop,
lobby guard, Direct MoveTo mode and complete OFF cleanup. It does NOT prove
that a live MM2 server awards a coin for the physical overlap.
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
local CFrame = {new = function(p) return {Position = p or Vector3.zero} end}
function CFrame.lookAt(p) return CFrame.new(p) end

local now = 0
os = {clock = function() return now end, time = function() return now end}
task = {spawn = function(fn) fn() end, wait = function() end, defer = function(fn) fn() end}
Enum = {
    Material = {Air = "Air", Grass = "Grass"},
    RaycastFilterType = {Exclude = "Exclude"},
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
    return {Name = name, className = "RemoteEvent", OnClientEvent = signal()}
end
local gameplay = {}
local remoteNames = {"CoinsStarted", "CoinCollected", "RoundStart",
    "VictoryScreen", "RoundEndFade", "PlayerDataChanged"}
for _, name in ipairs(remoteNames) do gameplay[name] = remoteEvent(name) end
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
    if name == "CollectionService" then
        return {GetTagged = function() return {} end}
    end
    return nil
end}

local written = {CFrame = 0, Size = 0, AssemblyLinearVelocity = 0}
local rootData = {
    Position = Vector3.new(0, 10, 0),
    CFrame = CFrame.new(Vector3.new(0, 10, 0)),
    Parent = true,
    Anchored = false,
    AssemblyLinearVelocity = Vector3.zero,
    AssemblyAngularVelocity = Vector3.zero,
}
local root = setmetatable({}, {
    __index = rootData,
    __newindex = function(_, k, v)
        if written[k] ~= nil then written[k] += 1 end
        rootData[k] = v
    end,
})

local pivotCalls, pivots = 0, {}
local character = {
    Parent = workspaceMock,
    PivotTo = function(_, frame)
        pivotCalls += 1
        table.insert(pivots, frame.Position)
        -- Bypass the write-tracking proxy: PivotTo moves the whole model, so
        -- the test harness must not count its own bookkeeping as a root write.
        rootData.Position = frame.Position
        rootData.CFrame = frame
    end,
}
local moveToCalls = {}
local humanoid = {
    Health = 100,
    WalkSpeed = 16,
    MoveDirection = Vector3.zero,
    FloorMaterial = "Grass",
    Jump = false,
    MoveTo = function(_, pos) table.insert(moveToCalls, pos) end,
}

local coinParent = {
    Name = "Coin_Server",
    Parent = map,
    Position = Vector3.new(10, 10, 0),
    CanTouch = true,
    Transparency = 0,
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
    Transparency = 0,
    GetAttribute = function(_, name)
        if name == "CoinID" then return "Coin" end
        return nil
    end,
}
local coinVisuals = {coinVisual}

local renderBindCount, renderUnbindCount = 0, 0
local RunService = {}
function RunService:BindToRenderStep() renderBindCount += 1 end
function RunService:UnbindFromRenderStep() renderUnbindCount += 1 end

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
local options, stats = {}, {}
local touchCalls, invalidations = 0, 0
state = {
    mm2CoinPickups = function() return coinVisuals end,
    mm2InvalidateCoinPickups = function() invalidations += 1 end,
    fireTouchInterest = function(_, _, _) touchCalls += 1 end,
    addStatOption = function(_, label)
        return {set = function(value) stats[label] = value end}
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
local function check(label, condition)
    if not condition then error("FAIL " .. label, 2) end
    print("PASS " .. label)
end

-- Activation: one scheduler owner, no render-step lock.
card.onToggle(true)
check("activation owns exactly one scheduler task", #tasks == 1)
check("activation never binds a render-step owner", renderBindCount == 0)
check("boot does not enable from config", card.status ~= nil)
local snap = state.mm2AutoFarmSnapshot()
check("Below Map is the default mode", snap.mode == "Below Map" and snap.belowMap)
check("manual override is on by default", snap.manualOverride)

-- Park under Coin_Server, then rise into its real volume from below.
now = 0.2
tick(0.2)
check("first placement parks below the coin", pivotCalls == 1
    and pivots[1].X == 10 and pivots[1].Y == 6)
snap = state.mm2AutoFarmSnapshot()
check("target is the real server pickup", snap.targetName == "Coin_Server")
now = 0.4
tick(0.2)
check("second placement physically overlaps the coin", pivotCalls == 2
    and pivots[2].Y == 9.4)
check("local touch nudge is optional and bounded", touchCalls == 2)
check("farm does not resize the hitbox or write root CFrame",
    written.CFrame == 0 and written.Size == 0)

now = 0.45
tick(0.05)
check("contact is not refreshed every frame", pivotCalls == 2)
now = 0.55
tick(0.1)
check("contact refresh is bounded to ~0.12 s", pivotCalls == 3
    and pivots[3].Y == 9.4)
check("contact does not credit a fake coin",
    state.mm2AutoFarmSnapshot().coinsConfirmed == 0)

-- Only the server event confirms a coin.
inventoryEvent.OnClientEvent:Fire("Materials", "Coins", 900)
gameplay.CoinCollected.OnClientEvent:Fire("Coin", 1, 50, {Value = 1})
snap = state.mm2AutoFarmSnapshot()
check("CoinCollected confirms exactly one coin", snap.coinsConfirmed == 1)
check("bag amount comes from the event", snap.bagAmount == 1 and snap.bagLimit == 50)
check("persistent balance is observed", snap.persistentCoins == 900)
now = 0.6
tick(0.05)
check("overlay reports the confirmed coin", stats["Coins Collected"] == "1")
check("overlay reports active time", stats["Time"] ~= nil)

-- Manual input pauses Below Map placements instead of stealing controls.
humanoid.MoveDirection = Vector3.new(1, 0, 0)
now = 0.7
tick(0.1)
snap = state.mm2AutoFarmSnapshot()
check("manual movement pauses the farm", snap.manualPause > 0
    and string.find(snap.status, "Paused", 1, true) ~= nil)
local beforeManual = pivotCalls
humanoid.MoveDirection = Vector3.zero
now = 1.0
tick(0.3)
check("pause leaves the character under player control",
    pivotCalls == beforeManual and renderBindCount == 0)

-- CoinsStarted announces the real limit; reaching it stops the farm.
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

-- Lobby fails closed; a missing or non-Innocent role no longer blocks farming.
gameplay.CoinsStarted.OnClientEvent:Fire({
    Coin = {CollectedAmount = 0, CollectionLimit = 50},
})
phase = "lobby"
now = 2.1
tick(0.1)
check("lobby pauses farming",
    string.find(state.mm2AutoFarmSnapshot().status, "Waiting", 1, true) ~= nil)
phase = "map"
role = "Murderer"
rootData.Position = Vector3.new(0, 10, 0)
now = 2.3
tick(0.2)
check("role no longer blocks the farm",
    string.find(state.mm2AutoFarmSnapshot().status, "Waiting", 1, true) == nil)

-- Direct mode uses native MoveTo, never the Below Map pivots.
options["Farm mode"]("Direct")
rootData.Position = Vector3.new(0, 10, 0)
local beforeDirect = pivotCalls
now = 2.5
tick(0.2)
check("Direct mode keeps native MoveTo", #moveToCalls > 0)
check("Direct mode performs no teleport", pivotCalls == beforeDirect)
check("Direct status names the mode",
    string.find(state.mm2AutoFarmSnapshot().status, "Direct", 1, true) ~= nil)

-- OFF releases the frame task, every remote listener and the native autopilot.
card.onToggle(false)
check("OFF disconnects the farm tick", featureConnections.MM2AutoFarmTick == nil)
check("OFF leaves scheduler empty", #tasks == 0)
check("OFF never needed a render-step unbind", renderUnbindCount == 0)
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
print("[MM2 AUTO FARM v151] Below Map dynamics verified")
'''

script = HARNESS.replace("__AUTOFARM_SOURCE__", SOURCE)

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "auto_farm_v151.luau"
    path.write_text(script)
    luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
    result = subprocess.run([luau, str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())
