#!/usr/bin/env python3
"""Auto Unbox presses the game's OPEN BOX button and counts real results."""
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

local function guiButton(name, text, visible, ok)
    local button = {Name = name, Text = text, Visible = visible, Active = true}
    button.MouseButton1Click = {signal = true, owner = button, ok = ok ~= false}
    button.Activated = {Fire = function() error("signals cannot be fired") end}
    function button:IsA(class) return class == "GuiButton" or class == "TextButton" end
    function button:GetFullName() return "PlayerGui.Shop." .. self.Name end
    button.Parent = nil
    return button
end
local frame = {Name = "Shop", Visible = true}
function frame:IsA(class) return class == "Frame" end
local playerGui = {Name = "PlayerGui", Visible = true}
function playerGui:IsA(class) return class == "PlayerGui" end
function playerGui:GetDescendants()
    local list = {frame}
    local function walk(node)
        for _, child in ipairs(node.children or {}) do
            list[#list + 1] = child
            walk(child)
        end
    end
    walk(frame)
    return list
end
local buttons = {}
frame.children = buttons

local pressed = {}
function firesignal(signal)
    if not signal.ok then error("pressed a disabled button") end
    pressed[#pressed + 1] = signal.owner.Text
end

local LocalPlayer = {Name = "Tester"}
function LocalPlayer:FindFirstChild(name)
    if name == "PlayerGui" then return playerGui end
    return nil
end

-- Remotes: inventory changes are the confirmation source.
local listeners = {}
local changeInventory = {Name = "ChangeInventoryItem"}
function changeInventory:IsA(class) return class == "RemoteEvent" end
changeInventory.OnClientEvent = {Connect = function(_, fn)
    listeners[#listeners + 1] = fn
    return {Disconnect = function() end}
end}
local remotes = {children = {changeInventory}}
function remotes:FindFirstChild(name, recursive)
    for _, child in ipairs(self.children) do
        if child.Name == name then return child end
    end
    return nil
end
local replicated = {FindFirstChild = function(_, name)
    if name == "Remotes" then return remotes end
    return nil
end}
local game = {GetService = function(_, name)
    if name == "ReplicatedStorage" then return replicated end
    error("unexpected service " .. tostring(name))
end}

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
local options = {}
local state = {mm2Core = {}}
local MM2Scroll, mm2Features = {}, {}
local function createUniversalFeature(name, description, order, onToggle, config)
    local feature = {name = name, enabled = false, onToggle = onToggle,
        SetStatus = function(self, value) statuses[#statuses + 1] = value end,
        Toggle = function(self, value)
            self.enabled = value
            if self.onToggle then self.onToggle(value) end
        end}
    return feature
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
local function confirm() for _, fn in ipairs(listeners) do fn() end end

local Module = (function()
''' + SOURCE + '''
end)()

Module.init({})
local card = state.mm2AutoUnboxFeature
assert(card and card.name == "Auto Unbox", "the card is created")
assert(card.information and string.find(card.information, "OPEN BOX"))
assert(options["Delay between boxes"] and options["Max boxes per run"])

-- OFF: no loop, no status side effects.
assert(loop == nil, "nothing runs until the card is ON")

-- ON with no box window: it waits, it does not press anything.
card.enabled = true
card.onToggle(true)
loop(0.1)
assert(#pressed == 0, "no button, no press")
assert(statuses[#statuses] == "waiting for a box window", tostring(statuses[#statuses]))

-- A purchase prompt must never be pressed, even if it is on screen.
buttons[1] = guiButton("Purchase", "PURCHASE 100 ROBUX", true)
clock += 1.1
loop(0.1)
assert(#pressed == 0, "purchase prompts are never pressed")

-- A hidden OPEN BOX is not pressable either.
buttons[#buttons + 1] = guiButton("Open", "OPEN BOX", false)
clock += 1.1
loop(0.1)
assert(#pressed == 0, "a hidden button is not pressed")

-- The real button: one press, then the inventory change confirms it.
buttons[#buttons + 1] = guiButton("OpenBox", "OPEN BOX", true)
buttons[#buttons].Parent = frame
clock += 1.1
loop(0.1)
assert(#pressed == 1 and pressed[1] == "OPEN BOX", "the real button is pressed once")
assert(statuses[#statuses] == "waiting for a box window",
    "a press is not a box until the game answers: " .. tostring(statuses[#statuses]))
confirm()
clock += 0.2
loop(0.2)
assert(statuses[#statuses] == "1 opened", tostring(statuses[#statuses]))

-- The delay is honoured: nothing is pressed twice in the same instant.
local before = #pressed
loop(0.1)
assert(#pressed == before, "the delay is respected")

-- After the delay the next box opens, and Max boxes stops the run.
options["Delay between boxes"](0.8)
options["Max boxes per run"](2)
clock += 1.6
loop(0.1)
assert(#pressed == before + 1, "the next box is pressed after the delay")
confirm()
clock += 0.2
loop(0.2)
assert(statuses[#statuses] == "2 opened", tostring(statuses[#statuses]))
loop(0.1)
assert(statuses[#statuses] == "2 opened · done", tostring(statuses[#statuses]))
assert(loop == nil, "the run stops at Max boxes")
assert(card.enabled == false, "the card turns itself OFF when done")
assert(refreshCalls > 0, "the card repaints when it turns itself OFF")

-- A bare OPEN belongs to the menu, not to a box: only a window makes it a
-- box button. And inside the window, a purchase prompt still stays untouched.
card.enabled = true
card.onToggle(true)
pressed = {}
-- Drop the earlier OPEN BOX so only the generic OPEN is on screen.
for index, button in ipairs(buttons) do
    if button.Name == "OpenBox" then
        table.remove(buttons, index)
        break
    end
end
local generic = guiButton("OpenMenu", "OPEN", true)
generic.Parent = frame
buttons[#buttons + 1] = generic
clock += 10
loop(0.1)
assert(#pressed == 0, "a generic OPEN outside a box window is ignored")
-- The game keeps hidden unboxing windows around: they must not shadow the
-- visible one, and their buttons must not be pressed.
local hiddenHatch = {Name = "Hatching", Visible = false, children = {}}
function hiddenHatch:IsA(class) return class == "Frame" end
function hiddenHatch:GetDescendants()
    local list = {}
    local function walk(node)
        for _, child in ipairs(node.children or {}) do
            list[#list + 1] = child
            walk(child)
        end
    end
    walk(self)
    return list
end
hiddenHatch.Parent = frame
buttons[#buttons + 1] = hiddenHatch
local hiddenOpen = guiButton("OpenHidden", "OPEN BOX", true)
hiddenOpen.Parent = hiddenHatch
hiddenHatch.children[1] = hiddenOpen
clock += 1.1
loop(0.1)
assert(#pressed == 0, "a button inside a hidden window is not pressed")
local unboxing = {Name = "Unboxing", Visible = true, children = {}}
function unboxing:IsA(class) return class == "Frame" end
function unboxing:GetFullName() return "PlayerGui.Shop.Unboxing" end
function unboxing:GetDescendants()
    local list = {}
    local function walk(node)
        for _, child in ipairs(node.children or {}) do
            list[#list + 1] = child
            walk(child)
        end
    end
    walk(self)
    return list
end
unboxing.Parent = frame
buttons[#buttons + 1] = unboxing
local purchaseInWindow = guiButton("Purchase", "BUY FOR 1000 COINS", true)
purchaseInWindow.Parent = unboxing
unboxing.children[1] = purchaseInWindow
clock += 1.1
loop(0.1)
assert(#pressed == 0, "a BUY button inside the window is never pressed")
local openInWindow = guiButton("OpenBtn", "OPEN", true)
openInWindow.Parent = unboxing
unboxing.children[2] = openInWindow
clock += 1.1
loop(0.1)
assert(#pressed == 1 and pressed[1] == "OPEN", "the window OPEN button is pressed")
assert(statuses[#statuses] == "window: Unboxing", tostring(statuses[#statuses]))
confirm()
clock += 0.2
loop(0.2)
assert(statuses[#statuses] == "1 opened", tostring(statuses[#statuses]))

-- A button that never answers is a failure, not an infinite loop.
card.enabled = true
card.onToggle(true)
pressed = {}
clock += 10
loop(0.1)               -- press
clock += 9              -- no confirmation within 8 s
loop(0.1)
assert(statuses[#statuses] == "0 opened · 1 failed", tostring(statuses[#statuses]))

-- Without firesignal the module says so and stops instead of doing nothing.
card.enabled = true
card.onToggle(true)
local saved = firesignal
firesignal = nil
clock += 10
loop(0.1)
assert(loop == nil, "no firer, no loop")
assert(card.enabled == false, "no firer, the card turns OFF")
assert(string.find(notices[#notices], "firesignal"),
    "the reason is reported: " .. tostring(notices[#notices]))
firesignal = saved

-- The finder action reports what it sees.
buttons[#buttons + 1] = guiButton("Open2", "Open - Box 1", true)
buttons[#buttons].Parent = frame
options["Find box button"]()
assert(string.find(notices[#notices], "Open box button found"),
    tostring(notices[#notices]))

Module.destroy()
assert(not state.mm2AutoUnboxFeature and loop == nil, "unload leaves nothing")
print("PASS MM2 Auto Unbox: no button, purchase never pressed, hidden ignored, generic OPEN outside window ignored, window OPEN pressed, press once, confirmation, delay, max, timeout, no firesignal, unload")
'''

with tempfile.TemporaryDirectory(prefix='auto-unbox-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
