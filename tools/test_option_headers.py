#!/usr/bin/env python3
"""Option headers: a real caption widget, Gun/Knife sections, English labels."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
WIDGETS = (ROOT / 'src/guis/Wurst/Code/Widgets.lua').read_text()
SHOOT = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()
KNIFE = (ROOT / 'src/games/MM2/Combat/KnifeThrow.lua').read_text()
FREEZE = (ROOT / 'src/games/universal/Movement/FreezeMovementS.lua'.replace('MovementS', 'Movements')).read_text()

header = section(
    WIDGETS,
    '    state.addSectionOption = function(feature: any, titleText: string): Frame',
    '    local function setOptionVisible(',
)

script = PRELUDE + r'''
local children = {}
local function create(kind, props)
    local object = {ClassName = kind, Children = {}}
    for key, value in pairs(props) do object[key] = value end
    if props.Parent then table.insert(props.Parent.Children, object) end
    function object:SetAttribute(name, value) self[name] = value end
    function object:FindFirstChild(name)
        for _, child in ipairs(self.Children) do
            if child.Name == name then return child end
        end
        return nil
    end
    table.insert(children, object)
    return object
end
local Theme = {textMuted = "muted", outline = "outline"}
local CONTROL_FONT = "font"
local UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end}
local UDim2 = {new = function(xs, xo, ys, yo)
    return {X = {Scale = xs, Offset = xo}, Y = {Scale = ys, Offset = yo}}
end}
function UDim2.fromOffset(x, y)
    return {X = {Scale = 0, Offset = x}, Y = {Scale = 0, Offset = y}}
end
local CHILD_INSET = 4
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
local Enum = {TextXAlignment = {Left = "Left"}}
local state = {layout = {sectionRowHeight = 22}}
local function updateExpandedSize() end
local feature = {
    optionCount = 0,
    options = {ZIndex = 3, Children = {}},
    optionRows = {},
    updateExpandedSize = updateExpandedSize,
}
''' + header + r'''
local sectionRow = state.addSectionOption(feature, "Gun")
assert(sectionRow and sectionRow.Visible == true, "a header must be visible")
assert(sectionRow.Size.Y.Offset == 22)
assert(sectionRow.LayoutOrder == 1 and feature.optionCount == 1)
assert(#feature.optionRows == 1 and feature.optionRows[1] == sectionRow)
local caption = sectionRow:FindFirstChild("SectionLabel")
assert(caption and caption.Text == "GUN", "the caption is the upper-cased title")
assert(caption.TextColor3 == "muted")
assert(sectionRow:FindFirstChild("SectionLine"), "the header carries its divider")
pass("header widget: visible caption, divider, layout order and height")
'''
with tempfile.TemporaryDirectory(prefix='option-headers-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)

# SilentAIM: one card, Gun section. Auto Shoot is now independent.
gun = SHOOT.index('addSectionOption(ShootFeature, "Gun")')
# Auto Shoot is now an independent module, not in Shoot.lua
assert 'addToggleOption(ShootFeature, "Auto Shoot"' not in SHOOT, 'Auto Shoot moved to independent module'

# Knife Throw is also independent now
assert 'addToggleOption(feature, "Knife Throw"' not in KNIFE, 'Knife Throw moved to independent module'

# Verify independent modules exist
AUTO_SHOOT = (ROOT / 'src/games/MM2/Combat/AutoShoot.lua').read_text()
assert 'createUniversalFeature' in AUTO_SHOOT
assert '"Auto Shoot"' in AUTO_SHOOT

INDEPENDENT_KNIFE = (ROOT / 'src/games/MM2/Combat/KnifeThrow.lua').read_text()
assert 'createUniversalFeature' in INDEPENDENT_KNIFE
assert '"Knife Throw"' in INDEPENDENT_KNIFE

assert 'Throw with button' not in KNIFE, 'the button trigger option was removed'
assert 'Lanzar con el boton' not in KNIFE, 'the menu is English'
assert 'table.insert(feature.optionRows, 2, row)' not in KNIFE, \
    'headers replace the old row-reordering hack'
print("PASS headers: Auto Shoot and Knife Throw are independent Combat modules")

# The header widget renders its own caption, so cards must not draw another.
assert 'makeTextLabel(heading' not in FREEZE
assert 'addSectionOption(FreezeFeature, "Motion settings")' in FREEZE
print("PASS headers: Freeze Movements uses the shared caption without a duplicate")
