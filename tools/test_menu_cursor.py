#!/usr/bin/env python3
"""Menu cursor vs. the game's shift lock (v162).

The menu needs a free cursor while it is open. It must not keep it afterwards:
the reported regression was that shift lock stopped working and the mouse
stayed free, because the release path always wrote a behavior back (Default)
over whatever the game had just set.

This runs the real block from src/Wurst.lua against a mocked UserInputService
and asserts the three rules: own only our write, never write LockCenter, and
stop fighting a cursor the game keeps taking back.
"""
import os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WURST = (ROOT / 'src/Wurst.lua').read_text()

START = 'local menuCursorState: any = {'
END = '-- Roblox blurs the 3D scene, not GUI text; share the existing effect rather'
assert WURST.count(START) == 1 and WURST.count(END) == 1
SECTION = WURST[WURST.index(START):WURST.index(END)]

PRELUDE = r'''
local function pass(name) print("PASS\t" .. name) end

local Enum = {
    MouseBehavior = {
        Default = "Default",
        LockCenter = "LockCenter",
        LockCurrentPosition = "LockCurrentPosition",
    },
    UserInputType = {MouseButton2 = "MouseButton2"},
}

local function signal()
    local self = {listeners = {}}
    function self:Connect(fn)
        local connection = {Connected = true}
        connection.fn = fn
        function connection:Disconnect()
            self.Connected = false
            connection.Connected = false
            for index, entry in ipairs(self.listeners) do
                if entry == connection then
                    table.remove(self.listeners, index)
                    break
                end
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
    function self:Count() return #self.listeners end
    return self
end

-- MouseBehavior / MouseIconEnabled are NOT raw keys: they only exist behind
-- the metatable, so every write goes through the change signal.
local ui = {
    rightClicking = false,
    changeSignals = {},
    InputEnded = signal(),
}
for _, property in ipairs({"MouseBehavior", "MouseIconEnabled"}) do
    ui.changeSignals[property] = signal()
end
function ui:IsMouseButtonPressed()
    return self.rightClicking
end
function ui:GetPropertyChangedSignal(property)
    return self.changeSignals[property]
end
-- Writes go through real assignments so the change signal fires like it does
-- in the engine.
local behaviorStore, iconStore
local writes = {behavior = 0, icon = 0}
setmetatable(ui, {
    __index = function(_, key)
        if key == "MouseBehavior" then return behaviorStore end
        if key == "MouseIconEnabled" then return iconStore end
        return rawget(ui, key)
    end,
    __newindex = function(_, key, value)
        if key == "MouseBehavior" then
            if behaviorStore == value then return end
            behaviorStore = value
            writes.behavior += 1
            ui.changeSignals.MouseBehavior:Fire()
            return
        end
        if key == "MouseIconEnabled" then
            if iconStore == value then return end
            iconStore = value
            writes.icon += 1
            ui.changeSignals.MouseIconEnabled:Fire()
            return
        end
        rawset(ui, key, value)
    end,
})
behaviorStore = Enum.MouseBehavior.Default
iconStore = true

local UserInputService = ui
local LocalPlayer = {CharacterAdded = signal()}
local state = {visible = false, uiConnections = {}}
local function trackUiConnection(connection)
    table.insert(state.uiConnections, connection)
    return connection
end
local task = {defer = function(fn) fn() end}
local os = {clock = function() return NOW end}
NOW = 0
'''

BODY = r'''
local function open()
    state.visible = true
    setMenuCursorUnlocked(true)
end
local function close()
    state.visible = false
    setMenuCursorUnlocked(false)
end

-- 1) Opening takes the cursor; closing gives it back exactly as it was.
ui.MouseBehavior = Enum.MouseBehavior.Default
ui.MouseIconEnabled = true
open()
assert(ui.MouseBehavior == Enum.MouseBehavior.Default)
assert(ui.MouseIconEnabled == true)
close()
assert(ui.MouseBehavior == Enum.MouseBehavior.Default, "restored to Default")
pass("cursor: open/close in normal play leaves the cursor where it was")

-- 2) THE REGRESSION: pressing Shift to close the menu also turns shift lock
--    on. The release must not overwrite the LockCenter that follows it.
ui.MouseBehavior = Enum.MouseBehavior.Default
open()
state.visible = false
setMenuCursorUnlocked(false)
ui.MouseBehavior = Enum.MouseBehavior.LockCenter   -- the game's shift lock
assert(ui.MouseBehavior == Enum.MouseBehavior.LockCenter,
    "shift lock after closing the menu, got " .. tostring(ui.MouseBehavior))
local held = writes.behavior
for _ = 1, 60 do
    ui.MouseBehavior = Enum.MouseBehavior.LockCenter
end
assert(writes.behavior == held, "a closed menu never takes the cursor back")
pass("cursor: closing the menu leaves the shift lock the game enables next")

-- 2b) Shift lock enabled while the menu is still open: the menu yields after a
--     bounded fight and the lock is still there when it closes.
ui.MouseBehavior = Enum.MouseBehavior.Default
open()
for _ = 1, 40 do
    ui.MouseBehavior = Enum.MouseBehavior.LockCenter
end
assert(menuCursorState.yielded == true, "the menu yields instead of fighting")
assert(ui.MouseBehavior == Enum.MouseBehavior.LockCenter,
    "the game keeps the cursor once the menu yields")
NOW += 2
state.visible = false
setMenuCursorUnlocked(false)
assert(ui.MouseBehavior == Enum.MouseBehavior.LockCenter,
    "closing after yielding leaves the lock alone")
pass("cursor: an active shift lock survives the menu")

-- 3) And it never writes LockCenter itself, even if that is what it captured.
ui.MouseBehavior = Enum.MouseBehavior.LockCenter
open()
assert(ui.MouseBehavior == Enum.MouseBehavior.Default, "the menu still gets a free cursor")
close()
assert(ui.MouseBehavior ~= Enum.MouseBehavior.LockCenter,
    "a captured LockCenter is released to Default, never re-applied")
pass("cursor: a captured LockCenter is not written back")

-- 4) A game that keeps re-locking the cursor is not fought forever: the menu
--    yields after a bounded number of re-assertions.
ui.MouseBehavior = Enum.MouseBehavior.Default
open()
local before = writes.behavior
for _ = 1, 60 do
    ui.MouseBehavior = Enum.MouseBehavior.LockCenter
end
-- 60 external changes; each costs the game's own write plus at most one of
-- ours, and ours stop after the limit.
local fought = writes.behavior - before
assert(fought <= 20, "at most a few re-assertions, got " .. tostring(fought))
assert(menuCursorState.yielded == true, "the menu yields the cursor")
local settled = writes.behavior
for _ = 1, 30 do
    ui.MouseBehavior = Enum.MouseBehavior.LockCenter
end
assert(writes.behavior == settled, "after yielding it stops writing")
pass("cursor: stops fighting a cursor the game keeps re-locking")

-- 5) ...and the next menu session starts fighting again.
state.visible = false
setMenuCursorUnlocked(false)
assert(menuCursorState.yielded == false, "the yield is per menu session")
open()
local after = writes.behavior
ui.MouseBehavior = Enum.MouseBehavior.LockCenter
assert(writes.behavior == after + 2,
    "the new session takes the cursor back (game write + ours)")
pass("cursor: yielding only lasts for the session that yielded")

-- 6) Nothing is written while the menu is closed, however often the game moves
--    the cursor. This is what made shift lock look broken.
close()
local behaves = writes.behavior
local icons = writes.icon
for _ = 1, 120 do
    ui.MouseBehavior = Enum.MouseBehavior.LockCenter
    ui.MouseBehavior = Enum.MouseBehavior.Default
    ui.MouseIconEnabled = false
    ui.MouseIconEnabled = true
end
assert(writes.behavior == behaves + 240,
    "only the game's own writes, got extra "
        .. tostring(writes.behavior - behaves - 240))
assert(writes.icon == icons + 240, "the menu never touches the icon while closed")
pass("cursor: a closed menu is completely inert")

-- 7) Respawn while the menu is closed drops any stale ownership.
ui.MouseBehavior = Enum.MouseBehavior.Default
open()
state.visible = false
LocalPlayer.CharacterAdded:Fire()
assert(menuCursorState.owned == false, "respawn releases the cursor")
local respawn = writes.behavior
for _ = 1, 30 do
    ui.MouseBehavior = Enum.MouseBehavior.LockCenter
    ui.MouseBehavior = Enum.MouseBehavior.Default
end
assert(writes.behavior == respawn + 60,
    "only the game's writes after a respawn, got extra "
        .. tostring(writes.behavior - respawn - 60))
pass("cursor: a respawn releases a stale ownership")
'''

script = PRELUDE + SECTION + BODY

with tempfile.TemporaryDirectory(prefix='cursor-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
