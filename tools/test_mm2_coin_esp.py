#!/usr/bin/env python3
"""Execute the real MM2 Coin ESP module against a mocked map and card."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Render/CoinEsp.lua').read_text()

script = r'''
-- A tiny instance mock: only what the module reads.
local function part(name)
    return {Name = name, children = {},
        IsA = function(_, class) return class == "BasePart" end,
        GetChildren = function(self) return self.children end}
end
local function model(name, hasPart)
    return {Name = name, children = {},
        IsA = function(_, class) return class == "Model" end,
        GetChildren = function(self) return self.children end,
        FindFirstChildWhichIsA = function(_, class)
            return hasPart and class == "BasePart" and {} or nil
        end}
end
local function folder(name, children)
    return {Name = name, children = children or {},
        IsA = function(_, class) return class == "Folder" end,
        GetChildren = function(self) return self.children end}
end
local function container(name, children)
    return {Name = name, children = children or {},
        IsA = function(_, class) return class == "Model" end,
        GetChildren = function(self) return self.children end,
        FindFirstChildWhichIsA = function() return nil end}
end

local coinA, coinB = part("Coin"), model("Coin", true)
local coinContainer = container("CoinContainer", {coinA, coinB})
local map = {Name = "Map", IsA = function(_, c) return c == "Model" end,
    GetChildren = function() return {coinContainer} end,
    FindFirstChild = function(_, name)
        if name == "CoinContainer" then return coinContainer end
        return nil
    end}

local marks = {}
local statuses = {}
local lastStatus = "unset"
local callbacks = {}
local loops = {}
local featureConnections = {}
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
    debug = false,
    mm2Core = {
        CoinEffects = {},
        clearEffects = function(folder) table.clear(folder) end,
        createMM2Cham = function(folder, object, color, transparency)
            table.insert(folder, {object = object, color = color,
                transparency = transparency})
        end,
        findMM2Map = function() return map end,
        mm2Settings = {coinColor = "gold", coinTransparency = 0.8},
    },
}
local mm2Settings = state.mm2Core.mm2Settings
local MM2Scroll, mm2Features = {}, {}
local function createUniversalFeature(name, description, order, onToggle, config)
    local feature = {name = name, description = description, order = order,
        enabled = false, configKey = "MM2." .. name, onToggle = onToggle,
        SetStatus = function(self, value)
            lastStatus = value
            if value ~= nil then statuses[#statuses + 1] = value end
        end}
    return feature
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
local create = function() return {} end

local Module = (function()
''' + SOURCE + '''
end)()

Module.init({})
local feature = state.mm2CoinFeature
assert(feature and feature.name == "Coin ESP", "the card is created")
assert(feature.information and string.find(feature.information, "live number"),
    "the card explains where the count is")
assert(callbacks["Coin colour"] and callbacks["Coin transparency"],
    "colour and transparency are exposed")
assert(not next(state.mm2Core.CoinEffects), "nothing is drawn before enabling")

-- ON: one cham per coin, one status with the count.
feature.enabled = true
feature.onToggle(true)
assert(#state.mm2Core.CoinEffects == 2, "two coins, two highlights")
assert(state.mm2Core.CoinEffects[1].color == "gold"
    and state.mm2Core.CoinEffects[1].transparency == 0.8,
    "the shared coin settings are used")
assert(statuses[#statuses] == "2 coins", "the status reports the count")
assert(loops.coin, "a refresh loop exists while enabled")

-- A coin appears: the loop picks it up.
table.insert(coinContainer.children, part("Coin"))
loops.coin(0.8)
assert(#state.mm2Core.CoinEffects == 3, "a new coin is chammed")
assert(statuses[#statuses] == "3 coins")

-- A coin is collected: its highlight is removed, the others stay.
table.remove(coinContainer.children, 1)
loops.coin(0.8)
assert(#state.mm2Core.CoinEffects == 2, "a collected coin loses its cham")

-- Colour changes while ON rebuild with the new colour; while OFF they store.
callbacks["Coin colour"]("red")
assert(state.mm2Core.CoinEffects[1].color == "red", "colour applies live")
feature.enabled = false
feature.onToggle(false)
assert(#state.mm2Core.CoinEffects == 0, "OFF clears every highlight")
assert(not loops.coin, "OFF stops the refresh loop")
assert(lastStatus == nil, "OFF clears the status")

-- No map (lobby) is not an error: zero coins, no status until one exists.
map.FindFirstChild = function() return nil end
feature.enabled = true
feature.onToggle(true)
assert(#state.mm2Core.CoinEffects == 0, "no map means no coin")
assert(statuses[#statuses] == "no coins", "the empty map says so")
feature.onToggle(false)

Module.destroy()
assert(not state.mm2CoinFeature, "the card reference is released")
assert(#state.mm2Core.CoinEffects == 0 and not loops.coin, "unload leaves nothing")
print("PASS MM2 Coins: card, highlight per coin, live count, add/remove, colour, OFF clears, no map, no remotes, unload")
'''

# Client-side only: no remote and no network anywhere in the module.
for forbidden in ('FireServer', 'InvokeServer', 'HttpGet', 'HttpPost'):
    assert forbidden not in SOURCE, f'Coin ESP must not call {forbidden}'

with tempfile.TemporaryDirectory(prefix='coin-esp-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
