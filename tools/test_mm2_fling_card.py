#!/usr/bin/env python3
"""Execute the real MM2 Fling card (v191) against mocked UI and players.

What this proves, and what it cannot:

  * the card is the FULL historical one again: "Fling Murderer", "Fling
    Sheriff", "Fling All Innocents", the live role-labelled roster and "Fling";
  * the roster is ordered by role and never lists the local player, the dead or
    protected players;
  * Power/Retries default to the maximum the engine accepts (12 / 3) and travel
    to `state.mm2PerformFling` as options;
  * a selection stored in the profile never flings at injection;
  * with Anti Fling ON every path refuses and notifies instead of flinging.

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
local now = 0
os = { clock = function() return now end }
local jobs = {}
task = {
    spawn = function(fn) local co = coroutine.create(fn); coroutine.resume(co) end,
    wait = function(seconds) now += seconds or 0 end,
    delay = function(seconds, fn) table.insert(jobs, { due = now + (seconds or 0), fn = fn }) end,
}
TableClone = nil

local notifications = {}
local function notify(message) table.insert(notifications, message) end

local function node(name) return { Name = name } end

local Players = { GetPlayers = function() return {} end }
local function newPlayer(name, state)
    local humanoid = { Health = state.alive and 100 or 0 }
    local root = { Parent = true, Name = "HumanoidRootPart" }
    local character = { Parent = true }
    function character:FindFirstChildOfClass(class)
        if class == "Humanoid" then return humanoid end
        return nil
    end
    function character:FindFirstChild(name2)
        if name2 == "HumanoidRootPart" then return root end
        return nil
    end
    local tools = state.tools or {}
    return {
        Name = name,
        Parent = Players,
        Character = character,
        humanoid = humanoid,
        tools = tools,
    }
end

Players.GetPlayers = function() return roster end
roster = {}

local LocalPlayer = newPlayer("Me", { alive = true })
local murderer = newPlayer("Murd", { alive = true, tools = { Knife = true } })
local sheriff = newPlayer("Sheriff", { alive = true, tools = { Gun = true } })
local innocent = newPlayer("Innocent", { alive = true })
local dead = newPlayer("Casper", { alive = false })
local protected = newPlayer("Protected", { alive = true })
roster = { LocalPlayer, innocent, sheriff, murderer, dead, protected }

MM2Scroll = node("MM2Scroll")
mm2Features = {}

local actions = {}
local toggles = {}
local numberOptions = {}
local informationRows = {}
local listDefinitions = {}
local listControls = {}
local featureConnections = {}
local disconnected = {}

local function disconnectFeatureConnection(key)
    featureConnections[key] = nil
    disconnected[key] = true
end

local TaskManager = {
    Connect = function(_, fn)
        local connection = { fn = fn }
        function connection:Disconnect() self.gone = true end
        return connection
    end,
}

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

function addActionOption(feature, label, callback)
    actions[label] = { feature = feature, callback = callback }
end

function addToggleOption(feature, label, default, callback, hint)
    toggles[label] = { feature = feature, default = default, callback = callback, hint = hint }
end

-- Mirrors Widgets.addListOption: the builder publishes the stored selection
-- once, during construction, and exposes controls.set for later changes.
function addListOption(feature, label, definition)
    local key = feature.configKey .. "." .. label:gsub("%W", "")
    listDefinitions[label] = definition
    local selected = { ["Innocent [Innocent]"] = true }
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
            publish(names)
        end,
    }
    listControls[key] = controls
    publish({ "Innocent [Innocent]" })
    return { key = key, definition = definition }
end

function addInformationOption(feature, text)
    table.insert(informationRows, { feature = feature, text = text })
end

local function isAlivePlayer(player)
    local humanoid = player.humanoid
    return humanoid ~= nil and humanoid.Health > 0
end

state = {
    mm2Core = {
        getPlayerWeapon = function(player, toolName)
            return player.tools and player.tools[toolName] or nil
        end,
        getPlayerRole = function(player)
            -- The real core infers the role from the round data and the held
            -- tool; the mock states it explicitly.
            if player == murderer then return "Murderer" end
            if player == sheriff then return "Sheriff" end
            if player == innocent then return "Innocent" end
            return nil
        end,
        isPlayerAlive = isAlivePlayer,
        hasActiveRoundRoles = function() return true end,
        requestRoleRefresh = function() end,
        findMurderer = function() return murderer end,
        findSheriff = function() return sheriff end,
    },
    antiFlingActive = false,
    listControls = listControls,
    mm2PerformFling = nil,
}

services = {
    protectedTargets = {
        isProtected = function(player) return player == protected end,
    },
    gameBridge = nil,
}

local function addNumberOptionImpl(feature, name, default, minimum, maximum, callback, description, order)
    numberOptions[name] = {
        default = default, min = minimum, max = maximum,
        callback = callback, description = description, order = order, feature = feature,
    }
    return { Name = name }
end
addNumberOption = function(feature, name, default, minimum, maximum, callback, description, order, step, persist)
    return addNumberOptionImpl(feature, name, default, minimum, maximum, callback, description, order)
end

local flingCalls = {}
state.mm2PerformFling = function(target, options)
    table.insert(flingCalls, { target = target, options = options })
    return true
end

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

-- Every button the historical card had is back.
assert(actions["Fling Murderer"], "Fling Murderer button")
assert(actions["Fling Sheriff"], "Fling Sheriff button")
assert(actions["Fling All Innocents"], "Fling All Innocents button")
assert(actions["Fling"], "Fling button")
assert(toggles["Auto Fling Selected Target"], "Auto Fling toggle")

-- The stored selection is published while the list is built; that must not
-- fling anyone at injection.
assert(#flingCalls == 0, "a saved target must never fling on injection")
assert(card.status == nil, "no status is written while booting")

local list = listDefinitions["Fling target"]
assert(list, "Fling target list exists")
assert(list.single == true, "one target at a time")
assert(type(list.items) == "function", "targets are resolved live")
assert(list.emptyText == "No other players", "empty list copy")

local labels = list.items()
eq = function(actual, expected, message)
    if actual ~= expected then
        error(message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected), 0)
    end
end

eq(#labels, 3, "living, unprotected players only")
assert(string.find(labels[1], "Murd", 1, true), "murderer first: " .. tostring(labels[1]))
assert(string.find(labels[1], "Murderer", 1, true), "murderer is labelled by role")
assert(string.find(labels[2], "Sheriff", 1, true), "sheriff second: " .. tostring(labels[2]))
assert(string.find(labels[3], "Innocent", 1, true), "innocent last: " .. tostring(labels[3]))
for _, label in ipairs(labels) do
    assert(not string.find(label, "Casper", 1, true), "the dead are never listed")
    assert(not string.find(label, "Protected", 1, true), "protected players are never listed")
    assert(not string.find(label, "Me ", 1, true), "the local player is never listed")
end

-- Power and Retries default to the engine maximum.
eq(numberOptions["Power"].default, 12, "Power default is the engine maximum")
eq(numberOptions["Power"].min, 1, "Power min")
eq(numberOptions["Power"].max, 12, "Power max")
eq(numberOptions["Retries"].default, 3, "Retries default is the maximum")
eq(numberOptions["Retries"].min, 0, "Retries min")
eq(numberOptions["Retries"].max, 3, "Retries max")
eq(#informationRows, 1, "one information row explains the Anti Fling rule")

-- Fling Murderer targets the knife carrier.
actions["Fling Murderer"].callback()
eq(#flingCalls, 1, "Fling Murderer flings once")
assert(flingCalls[1].target == murderer, "the murderer is the target")
eq(flingCalls[1].options.power, 12, "Power travels to the engine")
eq(flingCalls[1].options.retries, 3, "Retries travel to the engine")
assert(card.status == "Flinging Murd", "status names the target")

-- Fling Sheriff targets the gun carrier.
actions["Fling Sheriff"].callback()
eq(#flingCalls, 2, "Fling Sheriff flings once")
assert(flingCalls[2].target == sheriff, "the sheriff is the target")

-- Picking a row flings that player and clears the row.
listControls["MM2.Fling.Flingtarget"].set("Innocent [Innocent]", true)
eq(#flingCalls, 3, "one fling per pick")
assert(flingCalls[3].target == innocent, "the picked player is the target")
eq(#listControls["MM2.Fling.Flingtarget"].selected, 0, "the row clears so the same player can be picked again")
listControls["MM2.Fling.Flingtarget"].set("Innocent [Innocent]", true)
eq(#flingCalls, 4, "the same player can be flung twice in a row")

-- The explicit "Fling" button uses the remembered selection.
actions["Fling"].callback()
eq(#flingCalls, 5, "Fling uses the selected target")
assert(flingCalls[5].target == innocent, "the selected innocent is flung")

-- Auto Fling arms a ticker for the remembered target and disarms with it.
toggles["Auto Fling Selected Target"].callback(true)
eq(state.mm2FlingSettings.autoFling, true, "auto fling arms with a living target")
assert(featureConnections.MM2FlingAuto ~= nil, "auto fling owns its ticker")
toggles["Auto Fling Selected Target"].callback(false)
eq(state.mm2FlingSettings.autoFling, false, "auto fling disarms")
assert(featureConnections.MM2FlingAuto == nil, "the ticker is disconnected when auto fling is off")

-- Anti Fling ON: every path refuses with a notice, never calling the engine.
state.antiFlingActive = true
local before = #flingCalls
local noticesBefore = #notifications
actions["Fling Murderer"].callback()
actions["Fling Sheriff"].callback()
actions["Fling"].callback()
eq(#flingCalls, before, "Anti Fling ON must not fling anybody")
eq(#notifications, noticesBefore + 3, "every refused button warns the player")
assert(string.find(notifications[#notifications], "Anti Fling"), "the notice names Anti Fling")
eq(card.status, "Anti Fling is ON", "status explains the refusal")
state.antiFlingActive = false

-- Slider changes reach the engine.
numberOptions["Power"].callback(9)
numberOptions["Retries"].callback(1)
local callsBeforePower = #flingCalls
actions["Fling Murderer"].callback()
eq(#flingCalls, callsBeforePower + 1, "fling after slider changes")
eq(flingCalls[#flingCalls].options.power, 9, "new Power reaches the engine")
eq(flingCalls[#flingCalls].options.retries, 1, "new Retries reach the engine")

-- Fling All Innocents walks the innocents with blocking calls.
local callsBeforeAll = #flingCalls
actions["Fling All Innocents"].callback()
eq(#flingCalls, callsBeforeAll + 1, "one innocent is flung")
assert(flingCalls[#flingCalls].options.blocking == true, "the sweep waits for each fling")
assert(flingCalls[#flingCalls].target == innocent, "only innocents are swept")

-- A target that left, and an engine that is not there yet.
innocent.Parent = nil
roster = { LocalPlayer, murderer }
local callsBeforeMissing = #flingCalls
actions["Fling"].callback()
eq(#flingCalls, callsBeforeMissing, "a target that left is not flung")
state.mm2PerformFling = nil
innocent.Parent = Players
roster = { LocalPlayer, innocent, sheriff, murderer, dead, protected }
actions["Fling Murderer"].callback()
eq(card.status, "Fling engine unavailable", "a missing engine is disclosed")

Module.destroy()
assert(state.mm2FlingFeature == nil, "destroy retires the published feature")
print("PASS MM2 Fling card: Murderer/Sheriff/All Innocents/roster/Fling, max Power+Retries, no fling on inject, Anti Fling notice")
'''

with tempfile.TemporaryDirectory(prefix="mm2-fling-card-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
