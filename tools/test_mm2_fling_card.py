#!/usr/bin/env python3
"""Execute the real MM2 Fling card (v190) against mocked UI and players.

What this proves, and what it cannot:

  * the card exists again as its own MM2 card, with Target player / Power /
    Retries, and the sliders reach `state.mm2PerformFling` as options;
  * a selection stored in the profile never flings at injection;
  * with Anti Fling ON the card refuses and notifies instead of flinging;
  * the row clears so the same player can be picked again.

It does NOT prove Roblox physics or that a server accepts the fling.
"""

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/Fling.lua").read_text(encoding="utf-8")
MANIFEST = (ROOT / "src/libraries/Manifest.lua").read_text(encoding="utf-8")

assert '"src/games/MM2/Other/Fling.lua"' in MANIFEST, "the Fling card must be in the MM2 load list"
assert MANIFEST.index('"src/games/MM2/Other/FlingEngine.lua"') < MANIFEST.index(
    '"src/games/MM2/Other/Fling.lua"'
), "the engine loads before the card that drives it"
assert '["Fling"] = "Exploits"' in MANIFEST, "the Fling card lives in Exploits"

script = r'''
local notifications = {}
local function notify(message) table.insert(notifications, message) end

local function node(name)
    return { Name = name, Parent = nil }
end
local function player(name, alive)
    local humanoid = { Health = alive and 100 or 0 }
    local character = { Parent = true }
    function character:FindFirstChildOfClass(class)
        if class == "Humanoid" then return humanoid end
        return nil
    end
    return { Name = name, Character = character }
end
local alice = player("Alice", true)
local bob = player("Bob", true)
local dead = player("Casper", false)
local LocalPlayer = player("Me", true)
local roster = { LocalPlayer, alice, bob, dead }
local Players = { GetPlayers = function() return roster end }

MM2Scroll = node("MM2Scroll")
mm2Features = {}

local flingCalls = {}
local listDefinitions = {}
local numberOptions = {}
local informationRows = {}
local listControls = {}

local function makeFeature(name, description, order, onToggle, options)
    local feature = {
        name = name,
        description = description,
        order = order,
        onToggle = onToggle,
        configuration = options,
        configKey = (options and options.registry == mm2Features and "MM2." or "Universal.")
            .. name:gsub("%W", ""),
        status = nil,
    }
    function feature:SetStatus(text) self.status = text end
    table.insert(mm2Features, feature)
    return feature
end

function createUniversalFeature(name, description, order, onToggle, options)
    return makeFeature(name, description, order, onToggle, options)
end

-- Mirrors Widgets.addListOption: the builder publishes the stored selection
-- once, during construction, and exposes controls.set for later changes.
function addListOption(feature, label, definition)
    local key = feature.configKey .. "." .. label:gsub("%W", "")
    listDefinitions[label] = definition
    local selected = { [ "Alice" ] = true }
    local controls
    local function publish(names)
        if type(definition.onChanged) == "function" then
            definition.onChanged(selected, names)
        end
    end
    controls = {
        selected = selected,
        set = function(item, on)
            if definition.single and on then table.clear(selected) end
            selected[item] = on or nil
            local names = {}
            for name, value in pairs(selected) do
                if value then table.insert(names, name) end
            end
            table.sort(names)
            if controls.onSet then controls.onSet(item, on, names) end
            publish(names)
        end,
    }
    listControls[key] = controls
    publish({ "Alice" })
    return { key = key, definition = definition }
end

function addNumberOption(feature, name, default, minimum, maximum, callback, description, order)
    numberOptions[name] = {
        default = default, min = minimum, max = maximum,
        callback = callback, description = description, order = order, feature = feature,
    }
    return { Name = name }
end

function addInformationOption(feature, text)
    table.insert(informationRows, { feature = feature, text = text })
end

local clearedRows = setmetatable({}, { __mode = "k" })

state = {
    mm2Core = {},
    antiFlingActive = false,
    listControls = listControls,
    mm2PerformFling = function(target, options)
        table.insert(flingCalls, { target = target, options = options })
        return true
    end,
}

local Module = (function()
''' + SOURCE + r'''
end)()

Module.init({})
local card = state.mm2FlingFeature
assert(card, "the card must publish itself as state.mm2FlingFeature")
assert(card.name == "Fling", "card name is Fling")
assert(card.configuration.categoryName == "Exploits", "Fling belongs to Exploits")
assert(card.configuration.kind == "group", "Fling is a group card, it never runs by itself")
assert(card.configuration.registry == mm2Features, "Fling lives in the MM2 page")
assert(#mm2Features == 1, "exactly one MM2 card is created")

-- The stored selection ("Alice") is published while the list is built; that
-- must not fling anyone at injection.
assert(#flingCalls == 0, "a saved target must never fling on injection")
assert(card.status == nil, "no status is written while booting")

local list = listDefinitions["Target player"]
assert(list, "Target player list exists")
assert(list.single == true, "one target at a time")
assert(type(list.items) == "function", "targets are resolved live")
assert(list.emptyText == "No other players", "empty list copy")

local names = list.items()
table.sort(names)
eq = function(actual, expected, message)
    if actual ~= expected then
        error(message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected), 0)
    end
end
eq(#names, 2, "living players only")
eq(names[1], "Alice", "first living player")
eq(names[2], "Bob", "second living player")

-- Power and Retries defaults.
assert(numberOptions["Power"].default == 6, "Power default 6")
assert(numberOptions["Power"].min == 1 and numberOptions["Power"].max == 10, "Power range")
assert(numberOptions["Retries"].default == 2, "Retries default 2")
assert(numberOptions["Retries"].min == 0 and numberOptions["Retries"].max == 3, "Retries range")
assert(#informationRows == 1, "one information row explains the Anti Fling rule")

-- Picking a player flings exactly that player with the slider values.
listControls["MM2.Fling.Targetplayer"].set("Alice", true)
eq(#flingCalls, 1, "one fling per pick")
assert(flingCalls[1].target == alice, "the picked player is the target")
eq(flingCalls[1].options.power, 6, "Power travels to the engine")
eq(flingCalls[1].options.retries, 2, "Retries travel to the engine")
assert(card.status == "Flinging Alice", "status names the target")

-- The row clears so the same player can be picked again.
listControls["MM2.Fling.Targetplayer"].set("Alice", true)
eq(#flingCalls, 2, "the same player can be flung twice in a row")

-- Anti Fling ON: refuse with a notice, never call the engine.
state.antiFlingActive = true
local before = #flingCalls
local noticesBefore = #notifications
listControls["MM2.Fling.Targetplayer"].set("Bob", true)
eq(#flingCalls, before, "Anti Fling ON must not fling anybody")
eq(#notifications, noticesBefore + 1, "Anti Fling ON warns the player")
assert(string.find(notifications[#notifications], "Anti Fling"), "the notice names Anti Fling")
eq(card.status, "Anti Fling is ON", "status explains the refusal")
state.antiFlingActive = false

-- Slider changes reach the engine.
numberOptions["Power"].callback(9)
numberOptions["Retries"].callback(1)
local callsBeforePower = #flingCalls
listControls["MM2.Fling.Targetplayer"].set("Bob", true)
eq(#flingCalls, callsBeforePower + 1, "fling after slider changes")
eq(flingCalls[#flingCalls].options.power, 9, "new Power reaches the engine")
eq(flingCalls[#flingCalls].options.retries, 1, "new Retries reach the engine")

-- A target that left, and an engine that is not there yet.
roster = { LocalPlayer, bob }
local callsBeforeMissing = #flingCalls
listControls["MM2.Fling.Targetplayer"].set("Alice", true)
eq(#flingCalls, callsBeforeMissing, "a target that left is not flung")
eq(card.status, "Player left", "status reports the missing player")
roster = { LocalPlayer, alice, bob, dead }
state.mm2PerformFling = nil
listControls["MM2.Fling.Targetplayer"].set("Alice", true)
eq(card.status, "Fling engine unavailable", "a missing engine is disclosed")

Module.destroy()
assert(state.mm2FlingFeature == nil, "destroy retires the published feature")
print("PASS MM2 Fling card: group card, live target list, Power/Retries, no fling on inject, Anti Fling notice")
'''

with tempfile.TemporaryDirectory(prefix="mm2-fling-card-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
