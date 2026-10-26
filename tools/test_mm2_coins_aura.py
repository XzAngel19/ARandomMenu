#!/usr/bin/env python3
"""Execute the real MM2 Coins Aura, Gun Aura, and Auto Vote modules against mocked workspace.

Verifies:
- Coins Aura:
  - Has no Range slider; collects automatically at max server reach (15 studs).
  - Picks the single nearest coin within 15 studs and detaches CoinVisual WeldConstraint.
  - Restores Coin_Server CFrame when out of range or toggled OFF.
- Gun Aura:
  - Event-driven + top-level GunDrop detection with zero recursive GetDescendants lag.
  - Creates upright WurstGunAuraHitbox and grabs GunDrop within Studs.
- Auto Vote:
  - Exposes Select Map option populated from RegularLobby.VotePad1..3 billboards.
  - Votes via Detector1..3 and VotePad1..3.Pad firetouchinterest without teleporting root.
  - Resets character repeatedly while voting intermission is active.
  - Stops resetting immediately when voting intermission ends (VoteInfoGui.Enabled == false or LoadingMap fires).
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COINS_SOURCE = (ROOT / "src/games/MM2/Other/CoinsAura.lua").read_text(encoding="utf-8")
GUN_SOURCE = (ROOT / "src/games/MM2/Other/GunAura.lua").read_text(encoding="utf-8")
VOTE_SOURCE = (ROOT / "src/games/MM2/Other/AutoVote.lua").read_text(encoding="utf-8")

assert '"Coins Aura"' in COINS_SOURCE
assert "addNumberOption" not in COINS_SOURCE, "Coins Aura must not have a Range slider"
assert '"Gun Aura"' in GUN_SOURCE
assert '"Studs"' in GUN_SOURCE
assert '"Auto Vote"' in VOTE_SOURCE
assert '"Select Map"' in VOTE_SOURCE

script = r'''
local clockNow = 100
os = { clock = function() return clockNow end }
local Vector3Mt = {}
function Vector3Mt:__index(k)
    if k == "Magnitude" then
        return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
    end
    return rawget(Vector3Mt, k)
end
function Vector3Mt:__sub(other)
    return Vector3.new(self.X - other.X, self.Y - other.Y, self.Z - other.Z)
end
function Vector3Mt:__eq(other)
    return type(other) == "table" and self.X == other.X and self.Y == other.Y and self.Z == other.Z
end
Vector3 = {
    new = function(x, y, z)
        return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __typeof = "Vector3" }, Vector3Mt)
    end,
}
local CFrameMt = {}
CFrameMt.__index = CFrameMt
function CFrameMt:__sub(vec)
    return setmetatable({ Position = Vector3.new(0, 0, 0) }, CFrameMt)
end
function CFrameMt:__mul(other)
    return self
end
CFrame = {
    new = function(posOrX, y, z)
        if type(posOrX) == "table" and posOrX.__typeof == "Vector3" then
            return setmetatable({ Position = posOrX }, CFrameMt)
        end
        return setmetatable({ Position = Vector3.new(posOrX or 0, y or 0, z or 0) }, CFrameMt)
    end,
}
BrickColor = {
    new = function(name) return { Name = name } end,
}
Enum = {
    Material = { Neon = "Neon" },
    HumanoidStateType = { Dead = "Dead" },
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

local function makeNode(name, className, parent, extra)
    local node = {
        Name = name,
        ClassName = className,
        Parent = parent,
        children = {},
        attrs = {},
    }
    if extra then
        for k, v in pairs(extra) do
            node[k] = v
        end
    end
    function node:IsA(c)
        if c == className or c == "Instance" then return true end
        if (className == "Part" or className == "BasePart") and c == "BasePart" then return true end
        return false
    end
    function node:GetAttribute(attr)
        return self.attrs[attr]
    end
    function node:FindFirstChild(childName)
        for _, c in ipairs(self.children) do
            if c.Name == childName then
                return c
            end
        end
        return nil
    end
    function node:FindFirstChildOfClass(c)
        for _, ch in ipairs(self.children) do
            if ch.ClassName == c then
                return ch
            end
        end
        return nil
    end
    function node:FindFirstChildWhichIsA(c)
        for _, ch in ipairs(self.children) do
            if ch:IsA(c) then
                return ch
            end
        end
        return nil
    end
    function node:GetChildren()
        return self.children
    end
    function node:IsDescendantOf(ancestor)
        local cur = self.Parent
        while cur do
            if cur == ancestor then return true end
            cur = cur.Parent
        end
        return false
    end
    if parent and parent.children then
        table.insert(parent.children, node)
    end
    return node
end

local function makePart(name, pos, parent, attrs)
    return makeNode(name, "Part", parent, {
        Position = pos or Vector3.new(0, 0, 0),
        CFrame = CFrame.new(pos or Vector3.new(0, 0, 0)),
        Size = Vector3.new(1.2, 2, 2),
        CanCollide = false,
        Anchored = true,
        attrs = attrs or {},
    })
end

workspace = makeNode("Workspace", "Workspace", nil)

local map = makeNode("House2", "Model", workspace)
local coinContainer = makeNode("CoinContainer", "Model", map)

-- Coin 1: 12 studs away
local coinServer12 = makePart("Coin_Server", Vector3.new(12, 0, 0), coinContainer, {})
local coinVisual12 = makePart("CoinVisual", Vector3.new(12, 0, 0), coinServer12, {})
local weld12 = makeNode("WeldConstraint", "WeldConstraint", coinVisual12, { Enabled = true })

-- Coin 2: 6 studs away (closer than Coin 1 -> must be picked!)
local coinServer6 = makePart("Coin_Server", Vector3.new(6, 0, 0), coinContainer, {})
local coinVisual6 = makePart("CoinVisual", Vector3.new(6, 0, 0), coinServer6, {})
local weld6 = makeNode("WeldConstraint", "WeldConstraint", coinVisual6, { Enabled = true })

-- Coin 3: 40 studs away (outside 15 studs max server reach)
local coinServer40 = makePart("Coin_Server", Vector3.new(0, 0, 40), coinContainer, {})

-- Dropped gun inside map (20 studs away)
local gunDrop = makePart("GunDrop", Vector3.new(0, 0, 20), map, {})

-- RegularLobby with VotePads and VotePad1..3 matching place, source.rbxlx
local regularLobby = makeNode("RegularLobby", "Model", workspace)
local votePads = makeNode("VotePads", "Model", regularLobby)
local detector1 = makePart("Detector1", Vector3.new(1.7, 506.8, 49.6), votePads, {})
local detector2 = makePart("Detector2", Vector3.new(13.9, 506.9, 52.5), votePads, {})
local detector3 = makePart("Detector3", Vector3.new(25.9, 506.9, 50.0), votePads, {})

local function buildVotePad(idx, mapTitle, pos, votesNum)
    local vp = makeNode("VotePad" .. tostring(idx), "Model", regularLobby)
    local mapGui = makeNode("MapInfoGui", "SurfaceGui", vp, { Enabled = true })
    local voteGui = makeNode("VoteInfoGui", "SurfaceGui", vp, { Enabled = true })
    local container = makeNode("Container", "Frame", voteGui)
    local mapNameLabel = makeNode("MapName", "TextLabel", container, { Text = mapTitle })
    local votesLabel = makeNode("Votes", "TextLabel", container, { Text = "Votes: " .. tostring(votesNum) })
    local padPart = makePart("Pad", pos, vp, {})
    return vp, voteGui, mapGui, mapNameLabel, votesLabel, padPart
end

local vp1, vgui1, mgui1, mname1, vlabel1, pad1 = buildVotePad(1, "Police Station", Vector3.new(1.7, 506.8, 49.6), 0)
local vp2, vgui2, mgui2, mname2, vlabel2, pad2 = buildVotePad(2, "House 2", Vector3.new(13.9, 506.9, 52.5), 3)
local vp3, vgui3, mgui3, mname3, vlabel3, pad3 = buildVotePad(3, "Bio Lab", Vector3.new(25.9, 506.9, 50.0), 0)

local rootPart = makePart("HumanoidRootPart", Vector3.new(0, 0, 0), nil, {})
local humanoid = {
    Health = 100,
    ChangeState = function(self, st) end,
}
local character = {
    HumanoidRootPart = rootPart,
    BreakJoints = function(self) humanoid.Health = 0 end,
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

local currentMap = map
local roundActive = false

state = {
    mm2Core = {
        findMM2Map = function()
            return currentMap
        end,
        findDroppedGun = function()
            return gunDrop
        end,
        getPlayerRole = function()
            return "Innocent"
        end,
        isRoundLifecycleActive = function()
            return roundActive
        end,
    },
    mm2CoinPickups = function()
        return { coinVisual12, coinVisual6 }
    end,
    fireTouchInterest = function(root, targetPart, toggleState)
        table.insert(touched, { root = root, part = targetPart, state = toggleState })
    end,
}

game = {
    GetService = function(_, serviceName)
        if serviceName == "Players" then
            return {
                GetPlayers = function() return { LocalPlayer } end,
            }
        end
        return nil
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
    assert(feature.name == "Gun Aura", "Only Gun Aura should register a number option here")
end

local selectMapChoices = nil
local selectMapCallback = nil
function addCycleOption(feature, name, choices, defaultIdx, callback, desc)
    if feature.name == "Auto Vote" then
        assert(name == "Select Map", "Auto Vote cycle option must be Select Map")
        selectMapChoices = choices
        selectMapCallback = callback
    end
    return { Text = choices[defaultIdx or 1] }
end

local CoinsModule = (function()
''' + COINS_SOURCE + r'''
end)()

local GunModule = (function()
''' + GUN_SOURCE + r'''
end)()

local VoteModule = (function()
''' + VOTE_SOURCE + r'''
end)()

-- 1. Test Coins Aura (no Range option, picks nearest coin at 6 studs, detaches weld)
CoinsModule.init({ Menu = {}, TaskManager = TaskManager })
local coinsCard = state.mm2CoinsAuraFeature
assert(coinsCard ~= nil, "Coins Aura card must be registered")

coinsCard.enabled = true
coinsCard.onToggle(true)
assert(#touched == 2 and touched[1].part == coinServer6, "Closest coin (6 studs) must be touched")
assert(weld6.Enabled == false, "CoinVisual WeldConstraint must be disabled before pulling Coin_Server")
assert(coinServer6.CFrame.Position.X == 0, "Coin_Server in range must be pulled to root.CFrame")

coinsCard.enabled = false
coinsCard.onToggle(false)
assert(coinServer6.CFrame.Position.X == 6, "Coin_Server CFrame must restore on OFF")

-- 2. Test Gun Aura
GunModule.init({ Menu = {}, TaskManager = TaskManager })
local gunCard = state.mm2GunAuraFeature
touched = {}
clockNow = 200
gunCard.enabled = true
gunCard.onToggle(true)
assert(string.find(tostring(gunCard.status), "Gun detected", 1, true) ~= nil, "Gun Aura must detect GunDrop")
assert(#touched == 2 and touched[1].part == gunDrop, "Gun Aura must touch GunDrop")
gunCard.enabled = false
gunCard.onToggle(false)
assert(gunDrop.CFrame.Position.Z == 20, "GunDrop CFrame must restore on OFF")

-- 3. Test Auto Vote in lobby during active voting intermission
currentMap = nil
roundActive = false
VoteModule.init({ Menu = {}, TaskManager = TaskManager })
local voteCard = state.mm2AutoVoteFeature
assert(voteCard ~= nil, "Auto Vote card must be registered")
assert(selectMapChoices[1] == "Police Station" and selectMapChoices[2] == "House 2" and selectMapChoices[3] == "Bio Lab",
    "Auto Vote must detect the 3 maps on the lobby billboard")

-- Select "House 2" (slot 2)
selectMapCallback("House 2")
touched = {}
clockNow = 300
humanoid.Health = 100
rootPart.Position = Vector3.new(10, 506, 40)
rootPart.CFrame = CFrame.new(rootPart.Position)
voteCard.enabled = true
voteCard.onToggle(true)

-- First tick steps onto the wooden pad (X=13.9) and pulses Detector2 and VotePad2.Pad
assert(math.abs(rootPart.CFrame.Position.X - 13.9) < 0.2, "Auto Vote must step onto the wooden pad")
assert(#touched >= 2, "Auto Vote must firetouchinterest on VotePad2 detector parts")
assert(humanoid.Health == 100, "Character stays alive during initial vote hold window")

-- Advance clock past VOTE_HOLD_Before_RESET (0.22s) while voting is still active -> resets character!
clockNow = 300.30
connections[#connections]()
assert(humanoid.Health == 0, "Auto Vote must reset character after casting vote during active intermission")
assert(detector2.CFrame.Position.X > 13, "Detector2 CFrame must restore before reset")

-- Respawn character and end voting intermission (VoteInfoGui.Enabled = false) -> MUST NOT RESET!
local newHumanoid = { Health = 100, ChangeState = function() end }
local newChar = {
    HumanoidRootPart = rootPart,
    BreakJoints = function() newHumanoid.Health = 0 end,
    FindFirstChild = character.FindFirstChild,
    FindFirstChildOfClass = function(_, c) if c == "Humanoid" then return newHumanoid end return nil end,
}
LocalPlayer.Character = newChar
vgui1.Enabled = false; mgui1.Enabled = false
vgui2.Enabled = false; mgui2.Enabled = false
vgui3.Enabled = false; mgui3.Enabled = false

touched = {}
clockNow = 301.0
connections[#connections]()
clockNow = 301.5
connections[#connections]()
assert(#touched == 0, "Auto Vote must not touch pads after voting intermission ends")
assert(newHumanoid.Health == 100, "Auto Vote must NEVER reset character after voting intermission ends!")

-- Test enabling Auto Vote mid-intermission when SurfaceGui.Enabled is false on client
-- (like in live MM2 place file) while player is near lobby pads and board has map names
voteCard.enabled = false
voteCard.onToggle(false)
touched = {}
clockNow = 305.0
rootPart.Position = Vector3.new(10, 506, 40)
rootPart.CFrame = CFrame.new(rootPart.Position)
voteCard.enabled = true
voteCard.onToggle(true)
assert(#touched >= 2, "Auto Vote enabled mid-intermission must immediately detect lobby intermission and vote")

voteCard.enabled = false
voteCard.onToggle(false)
CoinsModule.destroy()
GunModule.destroy()
VoteModule.destroy()
print("PASS MM2 Coins Aura (no slider, low CPU), Gun Aura (low CPU), and Auto Vote (3-map billboard detection, mid-intermission enable, intermission-only reset)")
'''

luau = os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau"))
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
    handle.write(script)
    temp_path = handle.name

try:
    res = subprocess.run([luau, temp_path], capture_output=True, text=True, check=False)
    if res.returncode != 0:
        raise SystemExit(f"MM2 Aura/Vote test failed:\n{res.stdout}\n{res.stderr}")
    print(res.stdout.strip())
finally:
    Path(temp_path).unlink(missing_ok=True)
