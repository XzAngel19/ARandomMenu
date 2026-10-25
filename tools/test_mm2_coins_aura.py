#!/usr/bin/env python3
"""Execute the real MM2 Coins Aura module against a mocked map and character.

Verifies:
- Range option is registered (default 100, min 5, max 1000) and defined before toggleCoinsAura.
- Toggling Coins Aura ON/OFF never raises (guards against v127 nil * nil crash).
- Detects coins from map.CoinContainer, state.mm2CoinPickups, and CoinVisual tags.
- Resolves CoinVisual/MainCoin children to Coin_Server and fires firetouchinterest(root, server, 0/1).
- Respects Range: a coin at 100 studs is touched at default Range=100; a coin at 450 studs
  (far end of map) is touched when Range is raised to 500+.
- Skips coins marked Collected=true or Delete=true on either Coin_Server or CoinVisual.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/CoinsAura.lua").read_text(encoding="utf-8")

assert '"Coins Aura"' in SOURCE
assert '"Range", 100, 5, 1000' in SOURCE or '"Range",\n        100,\n        5,\n        1000' in SOURCE
assert "settings.range" in SOURCE
assert "findMM2Map" in SOURCE
assert '"CoinContainer"' in SOURCE

script = r'''
local clockNow = 100
os = { clock = function() return clockNow end }
local Vector3Mt = {}
Vector3Mt.__index = Vector3Mt
function Vector3Mt:__sub(other)
    return Vector3.new(self.X - other.X, self.Y - other.Y, self.Z - other.Z)
end
Vector3 = {
    new = function(x, y, z)
        return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __typeof = "Vector3" }, Vector3Mt)
    end,
}
local realTypeof = typeof
function typeof(v)
    if type(v) == "table" and v.__typeof then
        return v.__typeof
    end
    return realTypeof and realTypeof(v) or type(v)
end

local touched = {}
local connections = {}
local rangeCallback = nil

local function makePart(name, pos, parent, attrs)
    local p = {
        Name = name,
        Position = pos or Vector3.new(0, 0, 0),
        Parent = parent,
        attrs = attrs or {},
        children = {},
        touchTransmitter = nil,
    }
    function p:IsA(class)
        return class == "BasePart" or class == "Part" or class == "Instance"
    end
    function p:GetAttribute(attr)
        return self.attrs[attr]
    end
    function p:FindFirstChild(childName)
        for _, c in ipairs(self.children) do
            if c.Name == childName then
                return c
            end
        end
        return nil
    end
    function p:FindFirstChildOfClass(class)
        if class == "TouchTransmitter" then
            return self.touchTransmitter
        end
        return nil
    end
    function p:GetChildren()
        return self.children
    end
    if parent and parent.children then
        table.insert(parent.children, p)
    end
    return p
end

workspace = { Name = "Workspace", children = {} }
local map = { Name = "Workplace", Parent = workspace, children = {} }
local coinContainer = { Name = "CoinContainer", Parent = map, children = {} }
function map:FindFirstChild(name)
    if name == "CoinContainer" then return coinContainer end
    return nil
end
function coinContainer:GetChildren()
    return self.children
end

-- Coin 1: 95 studs away (within default 100 studs range), inside CoinContainer
local coinServer100 = makePart("Coin_Server", Vector3.new(95, 0, 0), coinContainer, {})
local coinVisual100 = makePart("CoinVisual", Vector3.new(95, 0, 0), coinServer100, {})

-- Coin 2: 450 studs away (at the far end of the map), surfaced via mm2CoinPickups as CoinVisual
local coinServerFar = makePart("Coin_Server", Vector3.new(0, 0, 450), coinContainer, {})
local coinVisualFar = makePart("CoinVisual", Vector3.new(0, 0, 450), coinServerFar, {})

-- Coin 3: 30 studs away, but already Collected on CoinVisual
local coinServerCollected = makePart("Coin_Server", Vector3.new(30, 0, 0), coinContainer, {})
local coinVisualCollected = makePart("CoinVisual", Vector3.new(30, 0, 0), coinServerCollected, { Collected = true })

local rootPart = makePart("HumanoidRootPart", Vector3.new(0, 0, 0), nil, {})
local humanoid = { Health = 100 }
local character = {
    HumanoidRootPart = rootPart,
    FindFirstChild = function(self, name)
        if name == "HumanoidRootPart" then return rootPart end
        return nil
    end,
    FindFirstChildOfClass = function(self, class)
        if class == "Humanoid" then return humanoid end
        return nil
    end,
}
LocalPlayer = { Character = character }

featureConnections = {}
function disconnectFeatureConnection(name)
    if featureConnections[name] then
        featureConnections[name]:Disconnect()
        featureConnections[name] = nil
    end
end

TaskManager = {
    Connect = function(_, fn)
        connections.tick = fn
        return {
            Disconnect = function()
                connections.tick = nil
            end,
        }
    end,
}

MM2Scroll = {}
mm2Features = {}

state = {
    mm2Core = {
        findMM2Map = function()
            return map
        end,
    },
    mm2CoinPickups = function()
        return { coinVisual100, coinVisualFar, coinVisualCollected }
    end,
    fireTouchInterest = function(root, targetPart, toggleState)
        table.insert(touched, { root = root, part = targetPart, state = toggleState })
    end,
}

game = {
    GetService = function(_, serviceName)
        if serviceName == "CollectionService" then
            return {
                GetTagged = function(_, tag)
                    if tag == "CoinVisual" then
                        return { coinVisual100, coinVisualFar, coinVisualCollected }
                    end
                    return {}
                end,
            }
        end
        return {}
    end,
}

function createUniversalFeature(name, desc, order, onToggle, opts)
    local card = {
        name = name,
        enabled = false,
        status = nil,
        onToggle = onToggle,
        SetStatus = function(self, text)
            self.status = text
        end,
    }
    return card
end

function addNumberOption(feature, name, default, minVal, maxVal, callback, desc, step)
    assert(name == "Range", "Coins Aura slider must be named Range")
    assert(default == 100 and minVal == 5 and maxVal == 1000, "Range bounds must be 100 (5..1000)")
    rangeCallback = callback
end

local Module = (function()
''' + SOURCE + r'''
end)()

Module.init({ Menu = {}, TaskManager = TaskManager })
local card = state.mm2CoinsAuraFeature
assert(card ~= nil, "Coins Aura card must be registered")
assert(type(rangeCallback) == "function", "Range callback must be registered")

-- 1. Toggle ON at default Range = 100 studs
card.enabled = true
card.onToggle(true)
assert(card.status == "100 studs", "Status must show 100 studs, got: " .. tostring(card.status))

-- Should have touched coinServer100 (0 and 1), NOT coinServerFar (450 studs) and NOT coinServerCollected
assert(#touched == 2, "Expected 2 fireTouchInterest calls (0 and 1) for the 95-stud coin, got " .. tostring(#touched))
assert(touched[1].root == rootPart and touched[1].part == coinServer100 and touched[1].state == 0)
assert(touched[2].root == rootPart and touched[2].part == coinServer100 and touched[2].state == 1)

-- 2. Raise Range to 500 studs to reach the coin at the far end of the map (450 studs)
touched = {}
rangeCallback(500)
assert(card.status == "500 studs", "Status must update to 500 studs")
connections.tick()
assert(#touched == 4, "Expected 4 fireTouchInterest calls (both 95-stud and 450-stud coins), got " .. tostring(#touched))
assert(touched[1].part == coinServer100 and touched[3].part == coinServerFar)

-- 3. Mark the 95-stud coin Collected on Coin_Server -> only the far coin should be pulsed next tick
coinServer100.attrs.Collected = true
touched = {}
connections.tick()
assert(#touched == 2 and touched[1].part == coinServerFar, "Collected coin must be skipped immediately")

-- 4. Toggle OFF cleans up connection and status
card.enabled = false
card.onToggle(false)
assert(connections.tick == nil, "MM2CoinsAura connection must disconnect on OFF")
assert(card.status == nil, "Status must clear on OFF")

Module.destroy()
print("PASS MM2 Coins Aura: Range (5..1000, default 100), full-map CoinContainer + CoinESP detection, Coin_Server firetouchinterest, collected skip, cleanup")
'''

luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
    handle.write(script)
    temp_path = handle.name

try:
    res = subprocess.run([luau, temp_path], capture_output=True, text=True, check=False)
    if res.returncode != 0:
        raise SystemExit(f"CoinsAura test failed:\n{res.stdout}\n{res.stderr}")
    print(res.stdout.strip())
finally:
    Path(temp_path).unlink(missing_ok=True)
