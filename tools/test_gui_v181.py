#!/usr/bin/env python3
"""GUI regressions fixed in v181, on the real booted menu.

1. Motion Lock: switching Mode (Position Lock <-> Motion) must never empty
   the card. The old code hid the whole options container instead of the rows
   because addToggleOption returns the button and addNumberOption the row.
2. HackList: the overlay only shows when Settings -> UI -> HackList -> Show is
   on. Opening the menu must not bring it back.
3. setOptionVisible: the options container is never a valid target.
4. Opacity / Menu scale sliders: moving them keeps every window and its rows
   intact, and the applied value is the one requested.
"""
import os
import subprocess
import tempfile
from pathlib import Path

import audit_menu

source = audit_menu.build(debug=True).read_text()

PROBE = r'''
local function byName(name)
    for _, feature in ipairs(ex.allFeatures) do
        if feature.name == name then return feature end
    end
end

-- 1. Motion Lock mode switching.
local freeze = byName('Freeze Animations')
assert(freeze, 'Freeze Animations card is missing')
assert(freeze.options, 'Freeze Animations has no options container')
local ctl = ex.state.valueControls['Movement.FreezeMovements.Freezemode']
assert(ctl and ctl.apply, 'the Freeze mode control is missing')

local function visibleRows()
    local n = 0
    for _, row in ipairs(freeze.optionRows or {}) do
        if row.Visible then n += 1 end
    end
    return n
end

local startRows = visibleRows()
assert(startRows > 0, 'Freeze Animations starts with visible rows: ' .. startRows)
-- The card starts collapsed, so only the rows themselves (not the container)
-- are asserted here; opening the card is what the reported bug did.
local containerWasVisible = freeze.options.Visible

-- Going back to a mode must reproduce exactly the same visible set. The two
-- modes show different blocks on purpose, so the reference is per mode.
local expectedRows = {}
for _, mode in ipairs({'Motion', 'Position Lock', 'Motion', 'Position Lock'}) do
    ctl.apply(mode)
    assert(freeze.options ~= nil, 'the options container still exists after ' .. mode)
    local rows = visibleRows()
    assert(rows > 0, 'switching to ' .. mode .. ' left the card empty')
    expectedRows[mode] = expectedRows[mode] or rows
    assert(rows == expectedRows[mode], 'switching back to ' .. mode .. ' lost rows: '
        .. rows .. ' vs ' .. expectedRows[mode])
    local height = freeze.optionsHeight or (freeze.options and freeze.options.AbsoluteSize.Y)
    assert(type(height) == 'number' and height > 0,
        'the card keeps a measured height after ' .. mode .. ': ' .. tostring(height))
end

-- Motion shows the emote/animation block, Position Lock the lock block.
local function rowNamed(name)
    for _, row in ipairs(freeze.optionRows or {}) do
        if row.Name == name then return row end
    end
end
ctl.apply('Position Lock')
local lockRows = { 'Option_Lockrotation', 'Option_Keepgravity', 'Option_Returnifpushed' }
local motionRows = { 'Option_FreezeEmotes', 'Option_Anyanimation' }
for _, name in ipairs(lockRows) do
    local row = rowNamed(name)
    assert(row and row.Visible, name .. ' must be visible in Position Lock')
end
ctl.apply('Motion')
for _, name in ipairs(lockRows) do
    local row = rowNamed(name)
    assert(row and row.Visible == false, name .. ' must be hidden in Motion')
end
for _, name in ipairs(motionRows) do
    local row = rowNamed(name)
    assert(row and row.Visible, name .. ' must be visible in Motion')
end
ctl.apply('Position Lock')

-- 3. The options container is never a valid setOptionVisible target.
ex.state.frameworkEnvironment.setOptionVisible(freeze, freeze.options, false)
assert(freeze.options.Visible == containerWasVisible,
    'setOptionVisible must refuse to hide the options container')
-- Passing the control inside a row hides that row, never the container.
local lockRow = rowNamed('Option_Lockrotation')
local innerControl = lockRow:FindFirstChildOfClass('TextButton') or lockRow:GetChildren()[1]
ex.state.frameworkEnvironment.setOptionVisible(freeze, innerControl, false)
assert(lockRow.Visible == false, 'setOptionVisible must resolve the owning row')
assert(freeze.options.Visible == containerWasVisible,
    'hiding an inner control must not touch the options container')
ex.state.frameworkEnvironment.setOptionVisible(freeze, innerControl, true)
assert(lockRow.Visible == true, 'the row comes back')

-- 2. HackList overlay.
local hud = ex.state.hudList
assert(hud and hud.frame, 'the HackList overlay is missing')
assert(hud.frame.Visible == false, 'the HackList must start hidden')
local menuWasOpen = ex.state.visible
ex.state.setMenuVisible(true)
assert(hud.frame.Visible == false, 'opening the menu must not show the HackList')
hud.SetAlways(true)
assert(hud.frame.Visible == true, 'Show must show the HackList even with the menu open')
hud.SetAlways(false)
assert(hud.frame.Visible == false, 'turning Show off hides the HackList again')
if menuWasOpen ~= true then
    ex.state.setMenuVisible(menuWasOpen)
end

-- 4. Opacity and Menu scale.
local opacity = ex.state.valueControls['ClickGUI.Opacity']
local menuScale = ex.state.valueControls['ClickGUI.Menuscale']
assert(opacity and menuScale, 'both UI sliders must exist')
local windowCount = #ex.state.windows.list
local function windowsIntact(tag)
    assert(#ex.state.windows.list == windowCount, tag .. ' changed the window count')
    for _, window in ipairs(ex.state.windows.list) do
        local size = window.root.AbsoluteSize
        assert(size.X > 5 and size.Y > 5, tag .. ' broke a window geometry')
    end
end
for _, value in ipairs({0.15, 0.35, 0.5, 0.85}) do
    opacity.apply(value)
    assert(math.abs(ex.state.windows.bodyTransparency - (1 - value)) < 0.001,
        'opacity ' .. value .. ' did not reach the window manager')
    windowsIntact('opacity ' .. value)
end
for _, value in ipairs({0.7, 0.85, 1, 1.15, 1.3}) do
    menuScale.apply(value)
    assert(math.abs(ex.configData.values['UI.MenuScale'] - value) < 0.001,
        'menu scale ' .. value .. ' was not stored')
    windowsIntact('menu scale ' .. value)
end
assert(ex.state.clickGui and ex.state.clickGui.ApplyScale,
    'the menu scale must be applicable without a full relayout')
ex.state.clickGui.ApplyScale()
windowsIntact('ApplyScale')

-- Every card that has rows still has them after both sliders moved.
local withRows = 0
for _, feature in ipairs(ex.allFeatures) do
    if feature.optionRows and #feature.optionRows > 0 then withRows += 1 end
end
assert(withRows >= 40, 'cards still carry their rows: ' .. withRows)

print('PASS GUI v181: Motion Lock mode switching keeps every row, HackList needs Show, '
    .. 'options container protected, opacity and menu scale keep the windows intact')
'''

with tempfile.TemporaryDirectory(prefix="gui-v181-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(source + PROBE)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
