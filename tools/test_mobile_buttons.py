#!/usr/bin/env python3
"""Mobile: configurable touch buttons replace the impossible keybinds page."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
MOBILE = (ROOT / 'src/guis/Wurst/Code/MobileActions.lua').read_text()
SETTINGS = (ROOT / 'src/guis/Wurst/Code/SettingsPage.lua').read_text()
CARDS = (ROOT / 'src/guis/Wurst/Code/Cards.lua').read_text()
WIDGETS = (ROOT / 'src/guis/Wurst/Code/Widgets.lua').read_text()

style = section(
    MOBILE,
    '    local MOBILE_SHAPES: {string} =',
    '    local function ensureMobileConfig(',
)
apply = section(
    MOBILE,
    '    local function applyMobileStyle(',
    '    local function notifyMobileChanged(',
)

script = PRELUDE + r'''
local Theme = {surfaceRaised = "theme", text = "text", outline = "outline"}
local UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end}
local function color(r, g, b)
    return setmetatable({R = r, G = g, B = b},
        {__typename = "Color3"})
end
local Color3 = {}
function Color3.fromRGB(r, g, b) return color(r / 255, g / 255, b / 255) end
function Color3.fromHex(hex)
    local r = tonumber(string.sub(hex, 2, 3), 16)
    local g = tonumber(string.sub(hex, 4, 5), 16)
    local b = tonumber(string.sub(hex, 6, 7), 16)
    return color(r / 255, g / 255, b / 255)
end
function Color3.toHex(value)
    return string.format("#%02X%02X%02X",
        math.floor(value.R * 255 + 0.5),
        math.floor(value.G * 255 + 0.5),
        math.floor(value.B * 255 + 0.5))
end
local function typeof(value)
    local mt = getmetatable(value)
    return mt and mt.__typename or type(value)
end
''' + style + apply + r'''
-- Shapes are real choices, not a single hardcoded square.
assert(table.concat(MOBILE_SHAPES, ",") == "Square,Rounded,Circle")
assert(#MOBILE_PALETTE == 8)
assert(SHAPE_CORNERS.Circle.Scale == 1, "Circle must be fully round")
assert(SHAPE_CORNERS.Square.Offset == 2, "Square stays nearly square")

-- Colour round-trips through the saved hex string.
local hex = colorToHex(Color3.fromRGB(10, 132, 255))
assert(hex == "#0A84FF", hex)
local parsed = colorFromHex(hex)
assert(parsed and math.abs(parsed.R - 10 / 255) < 0.001)

-- Readable label on any button colour.
assert(readableTextColor(Color3.fromRGB(10, 10, 10)).R > 0.9)
assert(readableTextColor(Color3.fromRGB(240, 240, 240)).R < 0.2)

-- The style applies shape and colour to a real record shape.
local corner = {CornerRadius = nil}
local button = {FindFirstChildOfClass = function(_, class)
    assert(class == "UICorner")
    return corner
end}
local record = {button = button, shape = "Circle", color = "#0A84FF"}
applyMobileStyle(record)
assert(corner.CornerRadius.Scale == 1)
assert(math.abs(button.BackgroundColor3.B - 1) < 0.001)
record.shape = "Square"
applyMobileStyle(record)
assert(corner.CornerRadius.Offset == 2)
record.shape = "Nope"
applyMobileStyle(record)
assert(corner.CornerRadius.Scale == 0 and corner.CornerRadius.Offset == 12,
    "an unknown shape falls back to Rounded")
pass("mobile buttons: shapes, palette, readable text and applied corner")
'''
with tempfile.TemporaryDirectory(prefix='mobile-buttons-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)

# Touch devices get the Buttons page where desktop keeps Keybinds.
assert '{"HackList", nil, 26},\n            {state.isMobile and "Buttons" or "Keybinds", nil, 26},' in SETTINGS
assert 'actionRow(uiRecord, 2, "Buttons", openButtons)' in SETTINGS
assert 'actionRow(uiRecord, 2, "Keybinds", openKeybinds)' in SETTINGS
assert 'configWindow("Buttons", "Buttons"' in SETTINGS
assert 'Default shape' in SETTINGS and 'Default colour' in SETTINGS
assert 'ui.place(actionId, label, callback, hold)' in SETTINGS

# The per-button editor owns shape and colour, and they are persisted.
assert 'editorLabel("Shape", 130)' in MOBILE
assert 'editorLabel("Colour", 172)' in MOBILE
assert 'record.shape' in MOBILE and 'record.color' in MOBILE
assert 'record.shape,\n            record.color,' in MOBILE, "shape/colour must be saved"
assert 'Apply to all buttons' in MOBILE
print("PASS mobile buttons: Buttons page replaces Keybinds on touch only")

# The card slot is a touch-button preview, not a key slot.
assert 'mobileUi.actionId(feature.configKey)' in CARDS
assert 'slot.Text = "+"' in CARDS
assert 'mobileUi.onChanged(syncMobileSlot)' in CARDS

# A phone cannot press keys: key-option rows are removed, not left inert.
assert 'if state.isMobile then\n            option.Visible = false' in WIDGETS
print("PASS mobile buttons: card slot previews/opens the touch button")
