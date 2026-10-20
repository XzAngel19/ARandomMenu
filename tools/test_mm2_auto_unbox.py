#!/usr/bin/env python3
"""Execute the real MM2 Auto Unbox module against the mocked shop remotes.

The place dump shows the game opens boxes through
`Remotes.Shop.OpenCrate:InvokeServer(boxId, "MysteryBox", currency)` (the
shop's own `RequestUnbox`/`PurchaseBox` do exactly that) and then plays the
reveal through `BoxController`/`EggController`, while `CrateComplete` reports
the finished crate. The catalogue comes from `Sync.MysteryBox`, `Sync.Eggs`
and the `EventInfoService1` box modules; the currency Auto pays with follows
the coin family the server announces on `CoinsStarted`. Robux prompts are
never part of the flow, and a box that does not open is a failure, not a loop.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Other/AutoUnbox.lua').read_text()

script = r'''
local clock = 100
local realOs = os
os = {clock = function() return clock end, time = realOs.time}

-- ============================ shop remotes ============================
local openCalls = {}
local openCrate = {Name = "OpenCrate", failCount = 0}
function openCrate:IsA(class) return class == "RemoteFunction" end
function openCrate:InvokeServer(boxId, category, currency)
    openCalls[#openCalls + 1] = {boxId = boxId, category = category, currency = currency}
    if self.failCount > 0 then
        self.failCount -= 1
        return nil
    end
    return "Reward_" .. tostring(boxId)
end
local boxController = {Name = "BoxController", fires = {}}
function boxController:Fire(payload) self.fires[#self.fires + 1] = payload end
local eggController = {Name = "EggController", fires = {}}
function eggController:Fire(boxId, reward)
    self.fires[#self.fires + 1] = {boxId = boxId, reward = reward}
end
local crateComplete = {Name = "CrateComplete", fires = {}}
function crateComplete:FireServer(reward) self.fires[#self.fires + 1] = reward end
local shopFolder = {children = {openCrate, boxController, eggController, crateComplete}}
function shopFolder:FindFirstChild(name)
    for _, child in ipairs(self.children) do
        if child.Name == name then return child end
    end
    return nil
end

-- ============================ database ============================
local syncData = {
    MysteryBox = {
        MysteryBox1 = {Name = "Mystery Box #1"},
        KnifeBox1 = {Name = "Knife Box #1"},
    },
    Eggs = {
        Egg = {Name = "Common Egg"},
    },
    NewShop = {
        MysteryBox1 = {Type = "MysteryBox", Price = {Coins = 1000, Gems = 100, Key = 1}},
        KnifeBox1 = {Type = "MysteryBox", Price = {Coins = 1000, Gems = 100, Key = 1}},
        Egg = {Type = "Eggs", Price = {Coins = 1000, Gems = 100}},
    },
}
local moduleScripts = {}
local function moduleScript(name)
    local object = {Name = name}
    function object:IsA(class) return class == "ModuleScript" or class == "Instance" end
    moduleScripts[name] = object
    return object
end
local syncInstance = moduleScript("Sync")
local christmasBox = moduleScript("Christmas2024Box")
local halloweenBox = moduleScript("Halloween2025Box")
local requireData = {
    Sync = syncData,
    Christmas2024Box = {ItemData = {Name = "Christmas Box '24"}},
    Halloween2025Box = {Name = "Halloween2025Box", ItemData = {Name = "Halloween Box '25"}},
}
local mysteryBoxesFolder = {Name = "MysteryBoxes", children = {christmasBox}}
function mysteryBoxesFolder:GetChildren() return self.children end
local halloweenEvent = {Name = "Halloween2025"}
function halloweenEvent:FindFirstChild(name)
    if name == "MysteryBox" then return halloweenBox end
    return nil
end
local eventListFolder = {Name = "EventList", children = {halloweenEvent}}
function eventListFolder:GetChildren() return self.children end
local eventInfoService = {Name = "EventInfoService1"}
function eventInfoService:FindFirstChild(name)
    if name == "MysteryBoxes" then return mysteryBoxesFolder end
    if name == "EventList" then return eventListFolder end
    return nil
end
local sharedServices = {Name = "SharedServices"}
function sharedServices:FindFirstChild(name)
    if name == "EventInfoService1" then return eventInfoService end
    return nil
end
local databaseFolder = {Name = "Database"}
function databaseFolder:FindFirstChild(name)
    if name == "Sync" then return syncInstance end
    return nil
end
local remotesFolder = {Name = "Remotes"}
function remotesFolder:FindFirstChild(name)
    if name == "Shop" then return shopFolder end
    return nil
end
local replicated = {}
function replicated:FindFirstChild(name)
    if name == "Remotes" then return remotesFolder end
    if name == "Database" then return databaseFolder end
    if name == "SharedServices" then return sharedServices end
    return nil
end

-- The workspace event attributes drive the fallback family detection.
local workspaceAttrs = {}
local workspace = {}
function workspace:GetAttribute(key) return workspaceAttrs[key] end

-- CoinsStarted names the bag the round pays out.
local startedListeners = {}
local coinsStarted = {}
function coinsStarted:IsA(class) return class == "RemoteEvent" end
coinsStarted.OnClientEvent = {Connect = function(_, fn)
    startedListeners[#startedListeners + 1] = fn
    return {Disconnect = function() end}
end}
function coinsStarted:fire(bagTable)
    for _, fn in ipairs(startedListeners) do fn(bagTable) end
end
local gameplayFolder = {}
function gameplayFolder:FindFirstChild(name)
    if name == "CoinsStarted" then return coinsStarted end
    return nil
end

local game = {GetService = function(_, name)
    if name == "ReplicatedStorage" then return replicated end
    error("unexpected service " .. tostring(name))
end}

-- ============================ menu framework ============================
local statuses, notices = {}, {}
local featureConnections = {}
local function disconnectFeatureConnection(key)
    if featureConnections[key] then
        featureConnections[key]:Disconnect()
        featureConnections[key] = nil
    end
end
local loop = nil
local TaskManager = {Connect = function(_, fn)
    loop = fn
    return {Disconnect = function() loop = nil end}
end}
local options, cycleValues = {}, {}
local state = {
    mm2Core = {mm2GameplayRemotes = gameplayFolder},
    requireModule = function(instance)
        local data = requireData[instance and instance.Name]
        if data == nil then error("cannot require " .. tostring(instance and instance.Name)) end
        return data
    end,
}
local MM2Scroll, mm2Features = {}, {}
local function createUniversalFeature(name, description, order, onToggle, config)
    local feature = {name = name, description = description, enabled = false,
        onToggle = onToggle,
        SetStatus = function(self, value) statuses[#statuses + 1] = value end}
    return feature
end
local function addCycleOption(feature, name, values, initialIndex, callback)
    options[name] = callback
    cycleValues[name] = values
end
local function addNumberOption(feature, name, value, low, high, callback)
    options[name] = callback
end
local function addActionOption(feature, name, callback)
    options[name] = callback
end
local function addInformationOption(feature, text)
    feature.information = text
end
local function notify(message) notices[#notices + 1] = message end
local refreshCalls = 0
function refreshFeatureToggle(feature) refreshCalls += 1 end

local Module = (function()
''' + SOURCE + '''
end)()

Module.init({})
local card = state.mm2AutoUnboxFeature
assert(card and card.name == "Auto Unbox", "the card is created")
assert(card.information and string.find(card.information, "OpenCrate"),
    "the card explains the remote it uses")
assert(options["Delay between boxes"] and options["Max boxes per run"])
assert(options["Box to open"] and options["Pay with"] and options["Reveal animation"],
    "box, currency and reveal are selectable")

-- The catalogue sees every box of the game: the Sync banks, the event box
-- modules and the fallback the place dump lists.
assert(cycleValues["Box to open"] and #cycleValues["Box to open"] == 15,
    "catalogue has every box: " .. tostring(cycleValues["Box to open"] and #cycleValues["Box to open"]))
local labels = cycleValues["Box to open"]
local function hasLabel(wanted)
    for _, label in ipairs(labels) do
        if label == wanted then return true end
    end
    return false
end
assert(hasLabel("Mystery Box #1") and hasLabel("Knife Box #1") and hasLabel("Common Egg"),
    "Sync boxes appear in the selector")
assert(hasLabel("Christmas Box '24") and hasLabel("Halloween Box '25"),
    "event boxes appear in the selector")
assert(hasLabel("Summer Box '25") and hasLabel("Gun Box #3"),
    "the dump's boxes appear even when the live Sync banks are smaller")

options["Report boxes and coin"]()
assert(string.find(notices[#notices], "Boxes found: 15"), tostring(notices[#notices]))
assert(string.find(notices[#notices], "Mystery Box #1"), "the default box is named")

-- OFF: no loop until the card is ON.
assert(loop == nil, "nothing runs until the card is ON")

-- Auto pays with the currency the server's coin fills: the Halloween box
-- takes Candies2025 while the server hands out candy.
options["Box to open"]("Halloween Box '25")
coinsStarted:fire({Candy = true})
options["Delay between boxes"](0.8)
card.enabled = true
card.onToggle(true)
loop(0.1)
assert(#openCalls == 1, "one open per due tick")
assert(openCalls[1].boxId == "Halloween2025Box" and openCalls[1].category == "MysteryBox",
    "the event box id and category are the game's own")
assert(openCalls[1].currency == "Candies2025",
    "Auto pays with the family the server announced: " .. tostring(openCalls[1].currency))
assert(#boxController.fires == 1, "the reveal plays through BoxController")
assert(boxController.fires[1][1].MysteryBoxId == "Halloween2025Box"
    and boxController.fires[1][1].RewardedItemId == "Reward_Halloween2025Box",
    "the reveal carries the box id and the rewarded item")
assert(string.find(statuses[#statuses], "1 opened"), tostring(statuses[#statuses]))
assert(string.find(statuses[#statuses], "server coin: Candy"), tostring(statuses[#statuses]))

-- Without a server family the box's own currency wins over its key.
card.enabled = false
card.onToggle(false)
options["Box to open"]("Christmas Box '24")
options["Delay between boxes"](0.8)
card.enabled = true
card.onToggle(true)
clock += 5
loop(0.1)
assert(openCalls[#openCalls].boxId == "Christmas2024Box")
assert(openCalls[#openCalls].currency == "SnowTokens2024",
    "the event currency is preferred over the key: " .. tostring(openCalls[#openCalls].currency))

-- A classic box pays Coins by default, and the manual choice is honoured.
card.enabled = false
card.onToggle(false)
options["Box to open"]("Mystery Box #1")
options["Pay with"]("Gems")
card.enabled = true
card.onToggle(true)
clock += 5
loop(0.1)
assert(openCalls[#openCalls].boxId == "MysteryBox1")
assert(openCalls[#openCalls].currency == "Gems", "the manual currency is used")

-- A currency the box does not take falls back to Auto instead of firing a
-- request the server must reject.
options["Pay with"]("SnowTokens2024")
clock += 5
loop(0.1)
assert(openCalls[#openCalls].boxId == "MysteryBox1")
assert(openCalls[#openCalls].currency ~= "SnowTokens2024",
    "an impossible currency is replaced")
assert(string.find(statuses[#statuses], "SnowTokens2024 rejected"),
    "the fallback is reported: " .. tostring(statuses[#statuses]))

-- Reveal Off still reports the crate, just without the animation.
options["Pay with"]("Auto")
options["Reveal animation"]("Off")
local crateBefore = #crateComplete.fires
local boxBefore = #boxController.fires
clock += 5
loop(0.1)
assert(#boxController.fires == boxBefore, "Reveal Off plays no animation")
assert(#crateComplete.fires == crateBefore + 1, "Reveal Off still reports CrateComplete")
options["Reveal animation"]("On")

-- Eggs open through the Egss category and hatch through EggController.
options["Box to open"]("Common Egg")
options["Pay with"]("Coins")
clock += 5
loop(0.1)
assert(openCalls[#openCalls].boxId == "Egg" and openCalls[#openCalls].category == "Eggs",
    "pets open through the Eggs category")
assert(eggController.fires[#eggController.fires].boxId == "Egg",
    "the hatch plays through EggController")

-- The delay is honoured: nothing opens twice in the same instant.
local before = #openCalls
loop(0.1)
assert(#openCalls == before, "the delay is respected")

-- Max boxes stops the run and turns the card off.
options["Delay between boxes"](0.8)
options["Max boxes per run"](2)
card.enabled = false
card.onToggle(false)
card.enabled = true
card.onToggle(true)
clock += 5
loop(0.1) -- open 1
clock += 5
loop(0.1) -- open 2
clock += 5
loop(0.1) -- done
assert(string.find(statuses[#statuses], "2 opened") and string.find(statuses[#statuses], "done"),
    tostring(statuses[#statuses]))
assert(loop == nil, "the run stops at Max boxes")
assert(card.enabled == false, "the card turns itself OFF when done")
assert(refreshCalls > 0, "the card repaints when it turns itself OFF")

-- A box that never opens is a failure, not an infinite loop: three nil
-- rewards stop the run with the reason in a notification.
openCrate.failCount = 10
card.enabled = true
card.onToggle(true)
clock += 5
loop(0.1)
clock += 5
loop(0.1)
assert(string.find(statuses[#statuses], "2 failed"), tostring(statuses[#statuses]))
clock += 5
loop(0.1)
assert(loop == nil, "three failures stop the run")
assert(card.enabled == false, "the card turns OFF after repeated failures")
assert(string.find(notices[#notices], "did not open"),
    "the reason is reported: " .. tostring(notices[#notices]))

-- The workspace attributes are the fallback family when no CoinsStarted has
-- fired: a fresh module reads them instead of remembering an old bag.
Module.destroy()
Module.init({})
card = state.mm2AutoUnboxFeature
workspaceAttrs.CurrentEvent = "Christmas"
options["Box to open"]("Christmas Box '24")
options["Pay with"]("Auto")
options["Delay between boxes"](0.8)
card.enabled = true
card.onToggle(true)
assert(string.find(statuses[#statuses], "server coin: SnowToken"),
    "the workspace event names the family: " .. tostring(statuses[#statuses]))
loop(0.1)
assert(openCalls[#openCalls].currency == "SnowTokens2024",
    "the workspace family pays the matching currency")
card.enabled = false
card.onToggle(false)

Module.destroy()
assert(not state.mm2AutoUnboxFeature and loop == nil, "unload leaves nothing")

-- The remote flow never presses GUI prompts and never touches purchases.
for _, forbidden in ipairs({"firesignal", "MouseButton1Click", "PurchaseProduct",
    "PurchaseWeaponPack"}) do
    assert(not string.find(''' + repr(SOURCE) + ''', forbidden),
        "Auto Unbox must not use " .. forbidden)
end
print("PASS MM2 Auto Unbox: catalogue, event boxes, server currency, manual currency, impossible currency fallback, reveal on/off, eggs, delay, max boxes, failure stop, workspace fallback, unload")
'''

with tempfile.TemporaryDirectory(prefix='auto-unbox-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
