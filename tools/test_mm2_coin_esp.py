#!/usr/bin/env python3
"""Execute the real MM2 Coin ESP module against a mocked map and card.

The game's own CoinVisualizer is the contract: a real pickup is a BasePart
tagged "CoinVisual" by CollectionService (structure in the place dump:
CoinContainer -> Coin_Server -> CoinVisual with MainCoin/DecalPart/2Part
mesh children), skipped when its "Collected" attribute is true. The old
name-based detection (Coin_Server parts, InteractiveBox, models named like
coins) lit whole containers and flooded the screen with one giant
highlight, so the module now uses GetTagged("CoinVisual") ONLY and puts
each highlight on the tagged part itself -- never on a parent model.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Render/CoinEsp.lua').read_text()

# Lightweight contract (user report: labels lagged with ~100 coins):
# no billboard labels at all, exactly one box adornment per pickup, and
# the box takes the visible MainCoin mesh size -- never Coin_Server's.
assert "BillboardGui" not in SOURCE, "coin markers must not create labels"
assert 'Instance.new("BoxHandleAdornment")' in SOURCE
assert 'FindFirstChild("MainCoin", true)' in SOURCE
assert "state.mm2CoinPickups" in SOURCE, "Auto Farm shares this pickup list"
# Visibility guard (v82-v85 live bug): the marker used the raw
# coinTransparency setting whose core default was 0.8 -- a candy-sized
# adornment at 80% transparency is invisible, so the ESP "detected
# nothing" while detection ran fine. The opacity is capped and the
# core default is the 0.35 the last visible build used.
assert "markerTransparency" in SOURCE and "0, 0.6" in SOURCE
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()
assert "coinTransparency = 0.35," in BASE
# Performance contract (live report: the ESP still lagged): the Auto
# Farm pickup list is cached instead of rescanning per poll, the
# static filter half is cached per part, and families are cached.
# (A cheap-rescan variant shipped in v84 reported nothing in game;
# the single full scan is the proven behaviour and stays.)
assert "local function collectAll()" in SOURCE
assert "filterCache" in SOURCE
assert "pickupCache" in SOURCE
assert "refreshPickupCache(found)" in SOURCE

script = r'''
local clock = 100
local os = {clock = function() return clock end}
local workspace = {}
local workspaceAttrs = {}
function workspace:GetAttribute(name) return workspaceAttrs[name] end
local worldScan = {}
function workspace:GetDescendants() return worldScan end
local descendantAdded = nil
workspace.DescendantAdded = {Connect = function(_, fn)
    descendantAdded = fn
    return {Disconnect = function() descendantAdded = nil end}
end}

local sizeMeta = {}
sizeMeta.__mul = function(size, factor)
    return setmetatable({X = size.X * factor, Y = size.Y * factor, Z = size.Z * factor}, sizeMeta)
end
local function size(x, y, z) return setmetatable({X = x, Y = y, Z = z}, sizeMeta) end
local function base(name, tags, attrs, children)
    local object = {Name = name, Parent = workspace, tags = tags or {},
        attrs = attrs or {}, children = children or {}, Transparency = 0,
        Size = size(1, 2, 0.25), Position = {}}
    function object:IsA(class)
        return class == "BasePart" or class == "Instance"
    end
    function object:FindFirstChildOfClass(class)
        if class == "Humanoid" then return self.humanoid end
        return nil
    end
    function object:GetAttribute(name) return self.attrs[name] end
    function object:Clone()
        local copy = base(self.Name)
        copy.Transparency = self.Transparency
        copy.Color = self.Color
        return copy
    end
    function object:Destroy() self.Parent = nil; self.destroyed = true end
    function object:FindFirstChild(childName, recursive)
        for _, child in ipairs(self.children) do
            if child.Name == childName then return child end
        end
        if recursive then
            for _, child in ipairs(self.children) do
                local found = child:FindFirstChild(childName, true)
                if found then return found end
            end
        end
        return nil
    end
    function object:GetDescendants()
        local out = {}
        local function walk(node)
            for _, child in ipairs(node.children) do
                out[#out + 1] = child
                walk(child)
            end
        end
        walk(self)
        return out
    end
    function object:IsDescendantOf(ancestor)
        local current = self.Parent
        while current do
            if current == ancestor then return true end
            current = current.Parent
        end
        return false
    end
    for _, child in ipairs(object.children) do child.Parent = object end
    return object
end
local function model(name, children)
    local object = base(name, nil, nil, children)
    function object:IsA(class)
        return class == "Model" or class == "Instance"
    end
    return object
end

-- REAL pickups: tagged CoinVisual parts, exactly as the game spawns them.
local coinMesh = base("MainCoin")
function coinMesh:IsA(class)
    return class == "MeshPart" or class == "BasePart" or class == "Instance"
end
local coinPart = base("CoinVisual", {CoinVisual = true}, nil,
    {coinMesh, base("DecalPart"), base("2Part")})
coinPart.Transparency = 1 -- the holder is invisible; its meshes are the coin
local candyMesh = base("CandyMesh")
function candyMesh:IsA(class)
    return class == "MeshPart" or class == "BasePart" or class == "Instance"
end
local candyPart = base("CoinVisual", {CoinVisual = true}, nil, {candyMesh})
candyPart.Transparency = 1
local snowMesh = base("SnowTokenMesh")
function snowMesh:IsA(class)
    return class == "MeshPart" or class == "BasePart" or class == "Instance"
end
local snowPart = base("CoinVisual", {CoinVisual = true}, nil, {snowMesh})
-- A collected pickup: the game keeps it tagged, the ESP must skip it.
local collectedPart = base("CoinVisual", {CoinVisual = true},
    {Collected = true}, {base("MainCoin")})

-- FAKES the old code lit up -- none of these may ever be highlighted.
local serverPart = base("Coin_Server")                    -- untagged
local looseMainCoin = base("MainCoin")                    -- untagged
local untaggedVisual = base("CoinVisual")                 -- name only, no tag
local container = model("CoinContainer", {serverPart, untaggedVisual})
local doorBox = base("InteractiveBox")                    -- untagged
local coinModel = model("Coin", {base("Coin_Server")})    -- untagged model

-- A pickup known only by its CoinID attribute (the CoinCollected key).
local coinIdPart = base("Hitbox", {}, {CoinID = "candy-7"}, {base("CandyMesh")})
-- A tagged part inside a character is not a pickup.
local character = model("Dummy", {})
local charPart = base("CoinVisual", {CoinVisual = true})
charPart.Parent = character
character.humanoid = true
character.children = {charPart}

local tagged = {coinPart, candyPart, snowPart, collectedPart, charPart}
worldScan = {coinPart, candyPart, snowPart, collectedPart, charPart,
    serverPart, looseMainCoin, untaggedVisual, container, doorBox, coinModel,
    coinIdPart}

local statuses = {}
local lastStatus = "unset"
local callbacks = {}
local cycleValues = {}
local loops = {}
local featureConnections = {}
local function signal()
    local entry = {listeners = {}}
    function entry:Connect(fn)
        entry.listeners[#entry.listeners + 1] = fn
        return {Disconnect = function() end}
    end
    function entry:fire(...)
        for _, fn in ipairs(self.listeners) do fn(...) end
    end
    return entry
end
local coinCollected, coinStarted = signal(), signal()
function coinStarted:IsA(class) return class == "RemoteEvent" end
coinStarted.OnClientEvent = coinStarted
function coinCollected:IsA(class) return class == "RemoteEvent" end
coinCollected.OnClientEvent = coinCollected
local remotes = {FindFirstChild = function(_, name)
    if name == "CoinCollected" then return coinCollected end
    if name == "CoinsStarted" then return coinStarted end
    return nil
end}

local tagAdded, tagRemoved = signal(), signal()
local CollectionService = {
    HasTag = function(_, object, tag)
        return object.tags and object.tags[tag] == true
    end,
    GetTagged = function(_, tag)
        local out = {}
        for _, object in ipairs(tagged) do
            if object.tags[tag] then out[#out + 1] = object end
        end
        return out
    end,
    GetInstanceAddedSignal = function(_, _) return tagAdded end,
    GetInstanceRemovedSignal = function(_, _) return tagRemoved end,
}

local function disconnectFeatureConnection(key)
    if featureConnections[key] then
        featureConnections[key]:Disconnect()
        featureConnections[key] = nil
    end
end
local TaskManager = {Connect = function(_, fn)
    loops.coin = fn
    return {Disconnect = function() loops.coin = nil end}
end}
-- The menu render library Item ESP draws with: record every label/box.
local overlayLabels = {}
local overlayBoxes = 0
local overlayLayer = {Visible = false}
local renderLibrary = {
    Layer = function(_, _) return overlayLayer end,
    Set = function(_, _, part)
        return {
            Show = function() end,
            Label = function(_, slot, text) overlayLabels[text] = true end,
            Box = function() overlayBoxes += 1 end,
        }
    end,
    Release = function() end,
    ReleaseAll = function() end,
    Project = function(_, _, _) return {X = 100, Y = 50} end,
}
workspace.CurrentCamera = {CFrame = {}}
local state = {
    renderLibrary = renderLibrary,
    mm2Core = {
        CoinEffects = {},
        clearEffects = function(folder) table.clear(folder) end,
        createMM2Cham = function(folder, object, color, transparency)
            table.insert(folder, {object = object, color = color,
                transparency = transparency})
        end,
        mm2GameplayRemotes = remotes,
        mm2Settings = {coinColor = "gold", coinTransparency = 0.8},
    },
}
local MM2Scroll, mm2Features = {}, {}
local function createUniversalFeature(name, description, order, onToggle, config)
    return {name = name, description = description, order = order,
        enabled = false, configKey = "MM2." .. name, onToggle = onToggle,
        SetStatus = function(self, value)
            lastStatus = value
            if value ~= nil then statuses[#statuses + 1] = value end
        end}
end
local function addCycleOption(feature, name, values, initialIndex, callback)
    callbacks[name] = callback
    cycleValues[name] = values
end
local function addColorOption(feature, name, value, callback)
    callbacks[name] = callback
end
local function addNumberOption(feature, name, value, low, high, callback)
    callbacks[name] = callback
end
local function addActionOption(feature, name, callback)
    callbacks[name] = callback
end
local function addInformationOption(feature, text)
    feature.information = text
end
local notices = {}
local function notify(message) notices[#notices + 1] = message end
local boxes = {}
local Instance = {new = function(class)
    local object = base("WurstCoinChams")
    object.ClassName = class
    if class == "BoxHandleAdornment" then table.insert(boxes, object) end
    return object
end}
local UDim2 = {fromOffset = function(x, y) return {x, y} end,
    fromScale = function(x, y) return {x, y} end}
local Vector3 = {new = function(x, y, z) return {X = x, Y = y, Z = z} end}
local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
local game = {GetService = function(_, name)
    if name == "CollectionService" then return CollectionService end
    error("unexpected service " .. tostring(name))
end}

local Module = (function()
''' + SOURCE + '''
end)()

Module.init({})
local feature = state.mm2CoinFeature
assert(feature and feature.name == "Coin ESP", "the card is created")
assert(feature.information and string.find(feature.information, "CoinVisual"),
    "the card explains how coins are found")
assert(callbacks["Coin colour"] and callbacks["Coin transparency"])
assert(callbacks["Coin in use"] and cycleValues["Coin in use"],
    "the family selector is registered")
assert(not next(state.mm2CoinChamSources or {}), "nothing is drawn before enabling")

local function highlighted(object)
    return state.mm2CoinTagParts ~= nil
        and state.mm2CoinTagParts[object] ~= nil
end

-- ON: only the three uncollected tagged parts, each highlighted ITSELF.
feature.enabled = true
feature.onToggle(true)
local drawnCount = 0
for _ in pairs(state.mm2CoinTagParts or {}) do drawnCount += 1 end
assert(drawnCount >= 5, "pickups tagged: " .. drawnCount)
assert(highlighted(coinPart), "the coin part carries a tag")
assert(highlighted(candyPart), "the candy part carries a tag")
assert(highlighted(snowPart), "the snow part carries a tag")
assert(not highlighted(collectedPart), "a collected pickup stays dark")
assert(not highlighted(serverPart), "Coin_Server alone is never a pickup")
assert(not highlighted(looseMainCoin), "an untagged MainCoin is never a pickup")
assert(highlighted(untaggedVisual), "the exact CoinVisual name is a signature even without the tag")
assert(highlighted(coinIdPart), "a CoinID attribute is a signature even without the tag")
assert(not highlighted(container), "a container model is never highlighted")
assert(not highlighted(coinModel), "a model named Coin is never highlighted")
assert(not highlighted(doorBox), "an InteractiveBox is never a pickup")
assert(not highlighted(charPart), "a tagged part inside a character is skipped")
assert(lastStatus:find("2 coins · 2 candies · 1 snowtoken", 1, true) == 1, tostring(lastStatus))
local tagCount = 0
for _ in pairs(state.mm2CoinTagParts or {}) do tagCount += 1 end
assert(tagCount >= 5, "every pickup carries a billboard tag: " .. tagCount)
assert(state.mm2CoinTagParts[coinPart] and state.mm2CoinTagParts[candyPart],
    "the tags sit on the pickup parts themselves")
local coinBox
for _, box in ipairs(boxes) do if box.Parent == coinPart then coinBox = box end end
assert(coinBox and coinBox.Adornee == coinMesh, "the box targets the visible MainCoin mesh")
assert(math.abs(coinBox.Size.X - coinMesh.Size.X * 1.3) < 1e-6
    and math.abs(coinBox.Size.Y - coinMesh.Size.Y * 1.3) < 1e-6,
    "the box is sized from the visible mesh, not the server holder")
coinPart.Parent = nil
clock += 1
loops.coin(0.01)
assert(coinBox.destroyed and not highlighted(coinPart),
    "an unparented pickup cannot keep an orphaned marker between scans")
coinPart.Parent = workspace
tagAdded:fire(coinPart)
loops.coin(0.01)
assert(highlighted(coinPart), "a returning pickup can receive a new marker")

-- Selector: Candy only.
callbacks["Coin in use"]("Candy")
assert(highlighted(candyPart) and not highlighted(coinPart)
    and not highlighted(snowPart), "the selector keeps only the chosen family")
assert(lastStatus:find("2 coins · 2 candies · 1 snowtoken", 1, true) == 1,
    "counts still report every family: " .. tostring(lastStatus))

-- Auto + the server announces Candy: only candy.
callbacks["Coin in use"]("Auto (server)")
coinStarted:fire({Candy = true})
loops.coin(0.01)
assert(highlighted(candyPart) and highlighted(coinPart),
    "Auto follows the CoinsStarted bag: coin-template pickups are candies this round")

-- A generic tagged part takes the server family (one kind per round).
local genericMesh = base("Mesh")
local genericPart = base("CoinVisual", {CoinVisual = true}, nil, {genericMesh})
table.insert(tagged, genericPart)
tagAdded:fire(genericPart)
loops.coin(0.01)
assert(highlighted(genericPart), "a newly tagged part gets a tag on the tag signal")
assert(lastStatus:find("5 candies · 1 snowtoken", 1, true) == 1, tostring(lastStatus))

-- Collection: the attribute flips, the remote fires, highlight drops.
genericPart.attrs.Collected = true
coinCollected:fire()
loops.coin(0.01)
assert(not highlighted(genericPart), "a collected pickup loses its tag")

-- Destroyed: gone from the tag list and the workspace scan.
snowPart.tags.CoinVisual = nil
for i, object in ipairs(tagged) do if object == snowPart then table.remove(tagged, i) end end
for i, object in ipairs(worldScan) do if object == snowPart then table.remove(worldScan, i) end end
tagRemoved:fire(snowPart)
loops.coin(0.01)
assert(not highlighted(snowPart), "a destroyed part loses its tag")
assert(lastStatus:find("4 candies", 1, true) == 1, tostring(lastStatus))

-- Colour applies live, OFF clears, empty map reports honestly.
callbacks["Coin colour"]("red")
assert(state.mm2CoinTagParts[coinPart], "tags still applied after colour change")
feature.enabled = false
feature.onToggle(false)
assert(not next(state.mm2CoinTagParts or {}), "OFF clears every tag")
assert(lastStatus == nil, "OFF clears the status")
tagged = {}
worldScan = {}
feature.enabled = true
feature.onToggle(true)
assert(lastStatus:find("no coins yet", 1, true) == 1, tostring(lastStatus))
feature.onToggle(false)

-- The reported live bug: an event round announced ONLY through the
-- Workspace attributes (CurrentEvent = Halloween), with pickups built
-- on the classic coin template (MainCoin meshes). They must classify
-- as candies and be drawn on Auto -- not counted as coins and hidden.
workspaceAttrs.CurrentEvent = "Halloween"
local eventCandy = base("CoinVisual", {CoinVisual = true}, nil,
    {base("MainCoin"), base("DecalPart")})
tagged = {eventCandy}
worldScan = {eventCandy}
feature.enabled = true
feature.onToggle(true)
assert(lastStatus:find("1 candy", 1, true) == 1, tostring(lastStatus))
assert(state.mm2CoinTagParts[eventCandy], "the event candy carries a tag on Auto")
feature.enabled = false
feature.onToggle(false)
workspaceAttrs.CurrentEvent = nil

Module.destroy()
assert(not state.mm2CoinFeature, "the card reference is released")
assert(not next(state.mm2CoinTagParts or {}) and not loops.coin, "unload leaves nothing")

-- Client-side only, and no name heuristics left in the source.
for _, forbidden in ipairs({"FireServer", "InvokeServer", "HttpGet", "HttpPost",
    "InteractiveBox"}) do
    assert(not string.find(''' + repr(SOURCE) + ''', forbidden),
        "Coin ESP must not use " .. forbidden)
end
print("PASS MM2 Coins: three exact signatures (CoinVisual tag, CoinID attribute, server/visual pair), one box per pickup, collected skip, families, selector, server bag, signals, OFF, unload")
'''

with tempfile.TemporaryDirectory(prefix='coin-esp-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
