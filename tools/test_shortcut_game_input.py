#!/usr/bin/env python3
"""Shortcut dispatch must survive a game that already used the key (v176).

The report was specific: a card toggled fine when clicked, but its keybind did
nothing in game, especially in MM2. `gameProcessed` only means "the place or the
core GUI already used this input"; the old gate treated it as "do not run the
menu shortcut", so every key the game binds (MM2 binds several) killed the bind.

This runs the real blocks from src/Wurst.lua against a mocked client:
`bindActionShortcut`, `setShortcutPressed`, `shortcutInputAllowed` and the two
global shortcut connections. It asserts the new contract and the parts that must
still be guarded (typing, key capture) plus the toast that proves the bind ran.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WURST = (ROOT / "src/Wurst.lua").read_text()

START = "local function bindActionShortcut("
END = "state.bindFeatureActivationKey = function("
assert WURST.count(START) == 1 and WURST.count(END) == 1
BIND = WURST[WURST.index(START):WURST.index(END)]

START = "local function setShortcutPressed(binding: any, pressed: boolean): ()"
END = "state.itemEspProviders = {}"
assert WURST.count(START) == 1 and WURST.count(END) == 1
DISPATCH = WURST[WURST.index(START):WURST.index(END)]

PRELUDE = r'''
local function pass(name) print("PASS\t" .. name) end

local function item(name) return setmetatable({Name = name}, {__tostring = function() return name end}) end
local Enum = {KeyCode = {}}
for _, name in ipairs({"Unknown", "F", "G", "J", "Escape", "RightShift"}) do Enum.KeyCode[name] = item(name) end
Enum.UserInputType = {Keyboard = item("Keyboard"), MouseButton1 = item("MouseButton1")}

local function signal()
    local self = {listeners = {}}
    function self:Connect(fn)
        local connection = {Connected = true, fn = fn}
        function connection:Disconnect()
            connection.Connected = false
            for index, entry in ipairs(self.listeners) do
                if entry == connection then table.remove(self.listeners, index) break end
            end
        end
        table.insert(self.listeners, connection)
        return connection
    end
    function self:Fire(...)
        for _, connection in ipairs(table.clone(self.listeners)) do
            if connection.Connected then connection.fn(...) end
        end
    end
    return self
end

local deferred, spawned = {}, {}
task = {
    defer = function(fn) table.insert(deferred, fn) end,
    spawn = function(fn) table.insert(spawned, fn) end,
}
local function flush()
    local guard = 0
    while #deferred > 0 or #spawned > 0 do
        guard += 1
        assert(guard < 100, "tasks must settle")
        if #deferred > 0 then table.remove(deferred, 1)() else table.remove(spawned, 1)() end
    end
end

local focusedTextBox = nil
local UserInputService = {
    InputBegan = signal(),
    InputEnded = signal(),
    WindowFocusReleased = signal(),
}
function UserInputService:GetFocusedTextBox() return focusedTextBox end

local notifications = {}
local function notify(text) table.insert(notifications, tostring(text)) end
local function trackUiConnection(connection) return connection end
local function beginKeyCapture() end

local configData = {values = {}, ui = {}}
local function queueConfigSave() end
local state = {shortcutBindings = {}, isMobile = false}
'''

BODY = r'''
-- The binding keeps the label and the feedback so a keypress with the menu
-- closed can answer with a toast instead of changing state silently.
local pressed = 0
bindActionShortcut(nil, "Universal.Fullbright", "Fullbright", function() pressed += 1 end, {
    feedback = function() return "Fullbright on" end,
})
local fullbright = state.shortcutBindings["Universal.Fullbright"]
assert(fullbright and fullbright.label == "Fullbright", "the binding must remember its label")
assert(type(fullbright.feedback) == "function", "the binding must keep the feedback callback")
assert(fullbright.key == Enum.KeyCode.Unknown, "registration must not invent a key")

-- A saved key is restored, and an explicit assignment survives a second call.
configData.values["Shortcut.UniversalFullbright"] = "F"
bindActionShortcut(nil, "Universal.Fullbright", "Fullbright", function() pressed += 1 end, {
    feedback = function() return "Fullbright on" end,
})
assert(state.shortcutBindings["Universal.UniversalFullbright"] == nil, "the option key is sanitized, not duplicated")
assert(state.shortcutBindings["Universal.Fullbright"].key == Enum.KeyCode.F,
    "the persisted key must be restored on boot")
pass("shortcut bindings keep label, feedback and the saved key")

local function keyPress(code, gameProcessed)
    UserInputService.InputBegan:Fire({UserInputType = Enum.UserInputType.Keyboard, KeyCode = code}, gameProcessed)
    flush()
end

-- The v176 fix: the game already used the key (MM2, core controls) and the menu
-- still runs its own shortcut.
keyPress(Enum.KeyCode.F, false)
assert(pressed == 1 and notifications[#notifications] == "Fullbright on",
    "a shortcut with the menu closed must fire and report the new state")
keyPress(Enum.KeyCode.F, true)
assert(pressed == 2 and notifications[#notifications] == "Fullbright on",
    "gameProcessed must not swallow the shortcut: that was the MM2 bug")
assert(#notifications == 2, "one toast per activation, not per poll")
pass("shortcuts fire whether or not the game consumed the key")

-- Typing and key capture still own the keyboard.
focusedTextBox = {ClassName = "TextBox"}
keyPress(Enum.KeyCode.F, true)
assert(pressed == 2, "a focused TextBox keeps the key for typing")
focusedTextBox = nil
state.keyCaptureCallback = function() end
keyPress(Enum.KeyCode.F, false)
assert(pressed == 2, "an active key capture must not also toggle a feature")
state.keyCaptureCallback = nil
state.waitingForKey = true
keyPress(Enum.KeyCode.F, false)
assert(pressed == 2, "waiting for a new menu key must not toggle features")
state.waitingForKey = false
pass("typing, capture and menu-key waits still block shortcuts")

-- Hold bindings report press and release; a window blur releases them.
local hold = {key = Enum.KeyCode.G, hold = true, pressed = false}
local events = {}
hold.onPress = function() table.insert(events, "press") end
hold.onRelease = function() table.insert(events, "release") end
state.shortcutBindings.hold = hold
UserInputService.InputBegan:Fire({UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.G}, true)
flush()
assert(hold.pressed and events[1] == "press", "a hold binding must press even when the game used the key")
UserInputService.InputEnded:Fire({UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.G})
flush()
assert(not hold.pressed and events[2] == "release")
UserInputService.InputBegan:Fire({UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.G}, false)
UserInputService.WindowFocusReleased:Fire()
flush()
assert(not hold.pressed, "losing focus must release a held shortcut")
pass("hold shortcuts press, release and clear on window blur")
'''

script = PRELUDE + "\n" + BIND + "\n" + DISPATCH + "\n" + BODY
with tempfile.TemporaryDirectory(prefix="shortcut-game-input-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script, encoding="utf-8")
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
