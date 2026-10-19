#!/usr/bin/env python3
"""Execute the real MM2 Coin ESP module against a mocked map and card.

The place dump names a coin by its two parts (`CoinVisual` + `Coin_Server`) and
the event candies are the same coin model under names such as `Candy2024`,
`Candies2022` or `CandyCorn`. The old module only looked inside three folders
that the live game does not populate, which is why the candy on screen was
never highlighted.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Render/CoinEsp.lua').read_text()

script = r'''
-- A tiny instance mock: only what the module reads.
local function base(name, tags)
    local object = {Name = name, Parent = nil, tags = tags or {}, children = {}}
    function object:IsA(class)
        return class == "BasePart" or class == "Instance"
    end
    function object:FindFirstChildOfClass(class)
        if class == "Humanoid" then return self.humanoid end
        return nil
    end
    function object:GetChildren() return self.children end
    function object:IsDescendantOf(ancestor)
        local current = self.Parent
        while current do
            if current == ancestor then return true end
            current = current.Parent
        end
        return false
    end
    function object:FindFirstChild(childName)
        for _, child in ipairs(self.children) do
            if child.Name == childName then return child end
        end
        return nil
    end
    function object:FindFirstChildWhichIsA(class)
        local function walk(node)
            for _, child in ipairs(node:GetChildren()) do
                if child:IsA(class) then return child end
                local nested = walk(child)
                if nested then return nested end
            end
            return nil
        end
        return walk(self)
    end
    return object
end
local function model(name, children)
    local object = base(name)
    object.children = children or {}
    function object:IsA(class)
        return class == "Model" or class == "Instance"
    end
    for _, child in ipairs(object.children) do child.Parent = object end
    return object
end
local function folder(name, children)
    local object = base(name)
    object.children = children or {}
    function object:IsA(class)
        return class == "Folder" or class == "Instance"
    end
    for _, child in ipairs(object.children) do child.Parent = object end
    return object
end

-- One coin: a model holding CoinVisual + Coin_Server, exactly the pair the
-- place dump lists ~100 times.
local coinModel = model("Coin", {
    base("CoinVisual"),
    base("Coin_Server"),
})
-- A candy: the same coin model with another look, named like an event treat.
local candyModel = model("Candy2024", {
    base("InteractiveBox"),
})
-- One loose part that only carries the part name, no model around it.
local looseCoin = base("CoinVisual")
-- A legacy container with an untagged part inside.
local legacyCoin = base("OldCoin")
local container = folder("Coins", {legacyCoin})
-- Noise: a character part must never be counted.
local character = model("Dummy", {base("CoinVisual")})
character.humanoid = true
-- Noise: another InteractiveBox, this one on a door, must stay dark.
local door = model("Door", {base("InteractiveBox")})

local world = {coinModel, candyModel, looseCoin, container, character, door}
-- GetDescendants returns everything below the roots, exactly like the engine.
local function flatten(roots)
    local out = {}
    local function walk(node)
        for _, child in ipairs(node:GetChildren()) do
            out[#out + 1] = child
            walk(child)
        end
    end
    for _, root in ipairs(roots) do
        out[#out + 1] = root
        walk(root)
    end
    return out
end
local worldConnections = {}
local workspace = {
    GetDescendants = function() return flatten(world) end,
    DescendantAdded = {Connect = function(_, fn)
        worldConnections.added = fn
        return {Disconnect = function() worldConnections.added = nil end}
    end},
    DescendantRemoving = {Connect = function(_, fn)
        worldConnections.removed = fn
        return {Disconnect = function() worldConnections.removed = nil end}
    end},
}

local marks = {}
local statuses = {}
local lastStatus = "unset"
local callbacks = {}
local loops = {}
local featureConnections = {}
local coinCollected = {listeners = {}}
function coinCollected:Connect(fn)
    self.listeners[#self.listeners + 1] = fn
    return {Disconnect = function() end}
end
function coinCollected:fire()
    for _, fn in ipairs(self.listeners) do fn() end
end
local remotes = {FindFirstChild = function(_, name)
    if name == "CoinCollected" then return coinCollected end
    return nil
end}
function coinCollected:IsA(class) return class == "RemoteEvent" end
-- The module connects to OnClientEvent; the mock uses itself as the signal.
coinCollected.OnClientEvent = coinCollected

-- CollectionService: tags plus the added/removed signals the module listens to.
local tagSignals = {added = {}, removed = {}}
local function signal(bag, tag)
    bag[tag] = bag[tag] or {listeners = {}}
    local entry = bag[tag]
    entry.Connect = function(_, fn)
        entry.listeners[#entry.listeners + 1] = fn
        return {Disconnect = function() end}
    end
    entry.fire = function()
        for _, fn in ipairs(entry.listeners) do fn() end
    end
    return entry
end
local CollectionService = {
    HasTag = function(_, object, tag)
        return object.tags and object.tags[tag] == true
    end,
    GetInstanceAddedSignal = function(_, tag) return signal(tagSignals.added, tag) end,
    GetInstanceRemovedSignal = function(_, tag) return signal(tagSignals.removed, tag) end,
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
local state = {
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
local mm2Settings = state.mm2Core.mm2Settings
local MM2Scroll, mm2Features = {}, {}
local function createUniversalFeature(name, description, order, onToggle, config)
    return {name = name, description = description, order = order,
        enabled = false, configKey = "MM2." .. name, onToggle = onToggle,
        SetStatus = function(self, value)
            lastStatus = value
            if value ~= nil then statuses[#statuses + 1] = value end
        end}
end
local function addColorOption(feature, name, value, callback)
    callbacks[name] = callback
end
local function addNumberOption(feature, name, value, low, high, callback)
    callbacks[name] = callback
end
local function addInformationOption(feature, text)
    feature.information = text
end
local notices = {}
local function notify(message) notices[#notices + 1] = message end
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
assert(not next(state.mm2Core.CoinEffects), "nothing is drawn before enabling")

local function highlighted(object)
    for _, entry in ipairs(state.mm2Core.CoinEffects) do
        if entry.object == object then return true end
    end
    return false
end

-- ON: the coin model once (not once per part), the candy model via the
-- InteractiveBox inside it, the loose tagged part and the legacy container
-- child. The character and the door stay dark.
feature.enabled = true
feature.onToggle(true)
assert(#state.mm2Core.CoinEffects == 4, "four pickups: " .. #state.mm2Core.CoinEffects)
assert(highlighted(coinModel), "the coin model is the adornee, both parts light up once")
assert(highlighted(candyModel), "the candy is highlighted")
assert(highlighted(looseCoin), "a loose CoinVisual part is highlighted")
assert(highlighted(legacyCoin), "a legacy container child is highlighted")
assert(not highlighted(character), "a character is never a pickup")
assert(not highlighted(door), "a generic InteractiveBox on a door stays dark")
assert(lastStatus == "3 coins · 1 candy", tostring(lastStatus))

-- A candy appears without any tag: the model name is enough, and the world
-- signal makes the module look again.
local candy2022 = model("Candies2022", {base("Part")})
table.insert(world, candy2022)
worldConnections.added(candy2022)
assert(lastStatus == "3 coins · 1 candy", "the status waits for the next tick")
loops.coin(0.01)
assert(highlighted(candy2022), "a Candies2022 model is highlighted")
assert(lastStatus == "3 coins · 2 candies", tostring(lastStatus))

-- A part becomes a coin only after the game tags it: the tag signal is what
-- catches it, because its name (`Part`) says nothing.
local taggedPart = base("Part")
table.insert(world, taggedPart)
worldConnections.added(taggedPart)
loops.coin(0.01)
assert(not highlighted(taggedPart), "an untagged Part is not a coin yet")
taggedPart.tags.CoinVisual = true
tagSignals.added.CoinVisual.fire()
loops.coin(0.01)
assert(highlighted(taggedPart), "the tag signal promotes the part")
assert(lastStatus == "4 coins · 2 candies", tostring(lastStatus))

-- Collected: remove it, fire the game's remote, and the next frame drops the
-- highlight without waiting for the five second scan.
table.remove(world)
taggedPart.tags.CoinVisual = false
coinCollected:fire()
loops.coin(0.01)
assert(not highlighted(taggedPart), "a collected coin loses its highlight")
assert(lastStatus == "3 coins · 2 candies", tostring(lastStatus))

-- Removing through the world signal works too.
table.remove(world)
worldConnections.removed(candy2022)
loops.coin(0.01)
assert(not highlighted(candy2022), "a removed candy loses its highlight")

-- Colour changes while ON rebuild with the new colour.
callbacks["Coin colour"]("red")
for _, entry in ipairs(state.mm2Core.CoinEffects) do
    assert(entry.color == "red", "colour applies live")
end

-- OFF clears every highlight and the status.
feature.enabled = false
feature.onToggle(false)
assert(#state.mm2Core.CoinEffects == 0, "OFF clears every highlight")
assert(not loops.coin, "OFF stops the refresh loop")
assert(lastStatus == nil, "OFF clears the status")

-- An empty map says so instead of drawing nothing in silence.
world = {}
feature.enabled = true
feature.onToggle(true)
assert(#state.mm2Core.CoinEffects == 0)
assert(lastStatus == "no coins yet", tostring(lastStatus))
feature.onToggle(false)

Module.destroy()
assert(not state.mm2CoinFeature, "the card reference is released")
assert(#state.mm2Core.CoinEffects == 0 and not loops.coin, "unload leaves nothing")

-- Client-side only: no remote and no network anywhere in the module.
for _, forbidden in ipairs({"FireServer", "InvokeServer", "HttpGet", "HttpPost"}) do
    assert(not string.find(''' + repr(SOURCE) + ''', forbidden),
        "Coin ESP must not call " .. forbidden)
end
print("PASS MM2 Coins: coin parts, candy names, InteractiveBox scoping, tag signal, character skip, live counts, collection refresh, colour, OFF, empty map, unload")
'''

with tempfile.TemporaryDirectory(prefix='coin-esp-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
