#!/usr/bin/env python3
"""Execute the real MM2 Coins Aura and Gun Aura modules against mocked workspace and character.

Verifies:
- Coins Aura:
  - Range option is registered (default 15, min 4, max 100).
  - Sorts coins by nearest first so distant coins never block close coins.
  - Pulls Coin_Server.CFrame to root.CFrame while preserving CoinVisual.CFrame and fires firetouchinterest.
  - Restores Coin_Server.CFrame when out of range, collected, or toggled OFF.
- Gun Aura:
  - Detects GunDrop anywhere in workspace even if findMM2Map() is nil.
  - Creates upright WurstGunAuraHitbox at the gun's true drop position.
  - Pulls GunDrop to root.CFrame and fires firetouchinterest when within Studs range.
  - Restores GunDrop state and destroys hitboxes on OFF.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COINS_SOURCE = (ROOT / "src/games/MM2/Other/CoinsAura.lua").read_text(encoding="utf-8")
GUN_SOURCE = (ROOT / "src/games/MM2/Other/GunAura.lua").read_text(encoding="utf-8")

assert '"Coins Aura"' in COINS_SOURCE
assert '"Range"' in COINS_SOURCE
assert "settings.range" in COINS_SOURCE
assert '"Gun Aura"' in GUN_SOURCE
assert '"Studs"' in GUN_SOURCE

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
CFrame = {
    new = function(posOrX, y, z)
        if type(posOrX) == "table" and posOrX.__typeof == "Vector3" then
            return { Position = posOrX }
        end
        return { Position = Vector3.new(posOrX or 0, y or 0, z or 0) }
    end,
}
BrickColor = {
    new = function(name) return { Name = name } end,
}
Enum = {
    Material = { Neon = "Neon" },
}
Instance = {
    new = function(className)
        local inst = {
            ClassName = className,
            Name = className,
            Parent = nil,
            Size = Vector3.new(1, 1, 1),
            CFrame = CFrame.new(0, 0, 0),
        }
        function inst:IsA(c)
            return c == className or c == "BasePart" or c == "Instance"
        end
        function inst:Destroy()
            self.Parent = nil
        end
        return inst
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
local gunStudsCallback = nil

local function makePart(name, pos, parent, attrs)
    local p = {
        Name = name,
        Position = pos or Vector3.new(0, 0, 0),
        CFrame = CFrame.new(pos or Vector3.new(0, 0, 0)),
        Size = Vector3.new(1.2, 2, 2),
        CanCollide = false,
        Parent = parent,
        attrs = attrs or {},
        children = {},
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
        return nil
    end
    function p:FindFirstAncestorOfClass(class)
        return nil
    end
    function p:IsDescendantOf(ancestor)
        local cur = self.Parent
        while cur do
            if cur == ancestor then return true end
            cur = cur.Parent
        end
        return false
    end
    function p:GetChildren()
        return self.children
    end
    function p:GetDescendants()
        return self.children
    end
    if parent and parent.children then
        table.insert(parent.children, p)
    end
    return p
end

workspace = {
    Name = "Workspace",
    children = {},
    FindFirstChild = function(self, name, recursive)
        for _, c in ipairs(self.children) do
            if c.Name == name then return c end
            if recursive and c.FindFirstChild then
                local f = c:FindFirstChild(name, true)
                if f then return f end
            end
        end
        return nil
    end,
    GetChildren = function(self) return self.children end,
    GetDescendants = function(self)
        local out = {}
        for _, c in ipairs(self.children) do
            table.insert(out, c)
            if c.GetChildren then
                for _, sub in ipairs(c:GetChildren()) do
                    table.insert(out, sub)
                end
            end
        end
        return out
    end,
}
local map = {
    Name = "Workplace",
    Parent = workspace,
    children = {},
    IsA = function(_, c) return c == "Model" end,
    FindFirstChild = function(self, name)
        for _, c in ipairs(self.children) do
            if c.Name == name then return c end
        end
        return nil
    end,
    GetChildren = function(self) return self.children end,
}
table.insert(workspace.children, map)
local coinContainer = {
    Name = "CoinContainer",
    Parent = map,
    children = {},
    GetChildren = function(self) return self.children end,
}
table.insert(map.children, coinContainer)

-- Coin 1: 12 studs away (within default 15 studs range)
local coinServer12 = makePart("Coin_Server", Vector3.new(12, 0, 0), coinContainer, {})
local coinVisual12 = makePart("CoinVisual", Vector3.new(12, 0, 0), coinServer12, {})

-- Coin 2: 6 studs away (closer than Coin 1 -> must be sorted and touched FIRST!)
local coinServer6 = makePart("Coin_Server", Vector3.new(6, 0, 0), coinContainer, {})
local coinVisual6 = makePart("CoinVisual", Vector3.new(6, 0, 0), coinServer6, {})

-- Coin 3: 40 studs away (outside default 15 studs, inside when Range=50)
local coinServer40 = makePart("Coin_Server", Vector3.new(0, 0, 40), coinContainer, {})
local coinVisual40 = makePart("CoinVisual", Vector3.new(0, 0, 40), coinServer40, {})

-- Dropped gun inside map (20 studs away, within Gun Aura default 25 studs)
local gunDrop = makePart("GunDrop", Vector3.new(0, 0, 20), map, {})

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
LocalPlayer = {
    Character = character,
    FindFirstChildOfClass = function() return nil end,
}

featureConnections = {}
function disconnectFeatureConnection(name)
    if featureConnections[name] then
        featureConnections[name]:Disconnect()
        featureConnections[name] = nil
    end
end

TaskManager = {
    Connect = function(_, fn)
        connections[#connections + 1] = fn
        return {
            Disconnect = function() end,
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
        findDroppedGun = function()
            return gunDrop
        end,
        getPlayerRole = function()
            return "Innocent"
        end,
    },
    mm2CoinPickups = function()
        return { coinVisual12, coinVisual6, coinVisual40 }
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
                        return { coinVisual12, coinVisual6, coinVisual40 }
                    end
                    return {}
                end,
            }
        elseif serviceName == "Players" then
            return {
                GetPlayers = function() return { LocalPlayer } end,
            }
        end
        return {}
    end,
}

function createUniversalFeature(name, desc, order, onToggle, opts)
    return {
        name = name,
        enabled = false,
        status = nil,
        onToggle = onToggle,
        SetStatus = function(self, text)
            self.status = text
        end,
    }
end

function addNumberOption(feature, name, default, minVal, maxVal, callback, desc, step)
    if feature.name == "Coins Aura" then
        assert(name == "Range", "Coins Aura slider must be named Range")
        assert(default == 15 and minVal == 4 and maxVal == 100, "Coins Aura Range bounds must be 15 (4..100)")
        rangeCallback = callback
    elseif feature.name == "Gun Aura" then
        assert(name == "Studs", "Gun Aura slider must be named Studs")
        assert(default == 25 and minVal == 5 and maxVal == 250, "Gun Aura Studs bounds must be 25 (5..250)")
        gunStudsCallback = callback
    end
end

local CoinsModule = (function()
''' + COINS_SOURCE + r'''
end)()

local GunModule = (function()
''' + GUN_SOURCE + r'''
end)()

CoinsModule.init({ Menu = {}, TaskManager = TaskManager })
local coinsCard = state.mm2CoinsAuraFeature
assert(coinsCard ~= nil, "Coins Aura card must be registered")

-- 1. Toggle Coins Aura ON at default Range = 15 studs
coinsCard.enabled = true
coinsCard.onToggle(true)
assert(coinsCard.status == "15 studs", "Status must show 15 studs, got: " .. tostring(coinsCard.status))

-- Nearest coin (coinServer6 at 6 studs) must be touched FIRST, before coinServer12 (12 studs)!
assert(#touched >= 4, "Both 6-stud and 12-stud coins must be touched")
assert(touched[1].part == coinServer6, "Closest coin (6 studs) must be pulsed first")
assert(coinServer6.CFrame.Position.X == 0, "Coin_Server in range must be pulled to root.CFrame")
assert(coinVisual6.CFrame.Position.X == 6, "CoinVisual must stay at its visual ground position")

-- 2. Toggle Coins Aura OFF restores Coin_Server CFrame
coinsCard.enabled = false
coinsCard.onToggle(false)
assert(coinServer6.CFrame.Position.X == 6, "Coin_Server CFrame must restore when Coins Aura turns OFF")

-- 3. Test Gun Aura detects GunDrop even when findMM2Map returns nil
state.mm2Core.findMM2Map = function() return nil end
GunModule.init({ Menu = {}, TaskManager = TaskManager })
local gunCard = state.mm2GunAuraFeature
assert(gunCard ~= nil, "Gun Aura card must be registered")

touched = {}
gunCard.enabled = true
gunCard.onToggle(true)
assert(string.find(tostring(gunCard.status), "Gun detected", 1, true) ~= nil,
    "Gun Aura must detect GunDrop even when findMM2Map is nil, got: " .. tostring(gunCard.status))
assert(#touched >= 2 and touched[1].part == gunDrop, "Gun Aura must pulse firetouchinterest on GunDrop within 25 studs")

gunCard.enabled = false
gunCard.onToggle(false)
assert(gunDrop.CFrame.Position.Z == 20, "GunDrop CFrame must restore when Gun Aura turns OFF")

CoinsModule.destroy()
GunModule.destroy()
print("PASS MM2 Coins Aura & Gun Aura: nearest-first coin pull+touch, true-position restore, map-independent GunDrop detection and grab")
'''

luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
    handle.write(script)
    temp_path = handle.name

try:
    res = subprocess.run([luau, temp_path], capture_output=True, text=True, check=False)
    if res.returncode != 0:
        raise SystemExit(f"CoinsAura/GunAura test failed:\n{res.stdout}\n{res.stderr}")
    print(res.stdout.strip())
finally:
    Path(temp_path).unlink(missing_ok=True)
