#!/usr/bin/env python3
"""Isolated Luau smoke tests; no Roblox/world simulation or existing menu boot."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

from build_violent import ROOT, SOURCE, OUTPUT, bundle

HARNESS = r'''
local realTypeof = typeof
local function signal()
    local self = { connections = {} }
    function self:Connect(fn)
        local c = { Connected = true, fn = fn }
        function c:Disconnect() self.Connected = false end
        table.insert(self.connections, c)
        return c
    end
    function self:Fire(...)
        for _, c in ipairs(table.clone(self.connections)) do
            if c.Connected then c.fn(...) end
        end
    end
    return self
end
local function enumGroup()
    return setmetatable({}, { __index = function(_, key) return key end })
end
Enum = setmetatable({}, { __index = function(self, key)
    local group = enumGroup(); rawset(self, key, group); return group
end })
-- Font names are pinned to actual Roblox enum members, not auto-created.
Enum.Font = { SourceSans = 'SourceSans', SourceSansItalic = 'SourceSansItalic',
    RobotoCondensed = 'RobotoCondensed' }
setmetatable(Enum.Font, { __index = function(_, key) error('Invalid font enum: ' .. key) end })
Font = { new = function(...) return {...} end }
local vectorMeta = {}
local function vector(x, y) return setmetatable({ X = x, Y = y }, vectorMeta) end
vectorMeta.__sub = function(a, b) return vector(a.X - b.X, a.Y - b.Y) end
vectorMeta.__div = function(a, b) return vector(a.X / b, a.Y / b) end
Vector2 = { new = vector }
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = { fromOffset = function(x, y) return { X = UDim.new(0, x), Y = UDim.new(0, y) } end }
Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
ColorSequence = { new = function(...) return {...} end }
ColorSequenceKeypoint = { new = function(...) return {...} end }
NumberSequence = { new = function(...) return {...} end }
NumberSequenceKeypoint = { new = function(...) return {...} end }
local methods = {}
local events = { Destroying = true, InputBegan = true, InputChanged = true,
    InputEnded = true, Activated = true, MouseEnter = true, MouseLeave = true,
    Focused = true, FocusLost = true }
local created = {}
local function instance(class)
    local object = { props = { ClassName = class, Name = class, Enabled = true,
        Visible = true, AbsoluteSize = vector(614, 550), AbsolutePosition = vector(0, 0),
        CanvasPosition = vector(0, 0) }, children = {}, attributes = {}, signals = {}, instance = true }
    setmetatable(object, {
        __index = function(self, key)
            if methods[key] then return methods[key] end
            if events[key] then
                if not self.signals[key] then self.signals[key] = signal() end
                return self.signals[key]
            end
            return self.props[key]
        end,
        __newindex = function(self, key, value)
            if key == 'Parent' then
                if value and value.reject then error('Parent permission denied') end
                local previous = self.props.Parent
                if previous then
                    local index = table.find(previous.children, self)
                    if index then table.remove(previous.children, index) end
                end
                if value then table.insert(value.children, self) end
            end
            self.props[key] = value
        end,
    })
    table.insert(created, object)
    return object
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
    local result = {}
    local function visit(node)
        for _, child in ipairs(node.children) do table.insert(result, child); visit(child) end
    end
    visit(self)
    return result
end
function methods:SetAttribute(key, value) self.attributes[key] = value end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:Destroy()
    if self.props.destroyed then return end
    self.props.destroyed = true
    self.Destroying:Fire()
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
    for _, event in pairs(self.signals) do
        for _, c in ipairs(event.connections) do c:Disconnect() end
    end
    self.Parent = nil
end
function methods:GetPropertyChangedSignal(key)
    local name = 'Property_' .. key
    if not self.signals[name] then self.signals[name] = signal() end
    return self.signals[name]
end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(self.children) do if child.ClassName == class then return child end end
end
function methods:WaitForChild(name)
    for _, child in ipairs(self.children) do if child.Name == name then return child end end
end
function methods:CaptureFocus() self.Focused:Fire() end
Instance = { new = instance }
typeof = function(value)
    if type(value) == 'table' and value.instance then return 'Instance' end
    return realTypeof(value)
end
local input = { InputBegan = signal(), InputChanged = signal(), InputEnded = signal() }
function input:GetFocusedTextBox() return self.focus end
local core, hidden, playerGui = instance('CoreGui'), instance('Folder'), instance('PlayerGui')
local player = instance('Player'); playerGui.Parent = player
local services = { UserInputService = input, CoreGui = core, Players = { LocalPlayer = player } }
game = { GetService = function(_, name) return assert(services[name], 'Forbidden service: ' .. name) end }
gethui = function() return hidden end
local function find(root, name, class)
    for _, child in ipairs(root:GetDescendants()) do
        if child.Name == name and (not class or child.ClassName == class) then return child end
    end
    error('Missing UI object: ' .. name)
end
local function press(key, processed)
    input.InputBegan:Fire({ KeyCode = key, UserInputType = 'Keyboard' }, processed or false)
end
local function activeInputConnections()
    local n = 0
    for _, event in ipairs({input.InputBegan, input.InputChanged, input.InputEnded}) do
        for _, c in ipairs(event.connections) do if c.Connected then n += 1 end end
    end
    return n
end
'''

CHECKS = r'''
local app = run()
assert(app.Gui.Parent == hidden, 'gethui takes priority')
assert(#app.Gui:GetDescendants() > 100, 'Full UI tree created')
assert(find(app.Gui, 'Violent').Position.X.Offset == 20)
assert(find(app.Gui, 'ESP Preview').Position.X.Offset == 342)
assert(find(app.Gui, 'VIOLENT').Text == 'VIOLENT')
assert(find(app.Gui, '29/51').Text == '29/51')
assert(find(app.Gui, 'Highlight Outline Color', 'TextButton').BackgroundTransparency == 0)
assert(find(app.Gui, 'Set color to: Highlight Outline Color').Text == 'Set color to: Highlight Outline Color')
assert(app.State.EnableSkeleton and app.State.HighlightESP and app.State.ShowHealthBar)
assert(app.State.SkeletonThickness == 1 and app.State.HealthBarSize == 2.5)
assert(find(app.Gui, 'Controls').Size.Y.Offset == 351)
find(app.Gui, 'Enable Skeleton', 'TextButton').Activated:Fire()
assert(not app.State.EnableSkeleton)
assert(not find(find(app.Gui, 'Enable Skeleton', 'TextButton'), 'Check').Visible)
local numeric = find(find(app.Gui, 'Skeleton Thickness', 'TextButton'), 'Value')
numeric.Focused:Fire()
numeric.Text = '999'; numeric.FocusLost:Fire(); assert(app.State.SkeletonThickness == 5)
numeric.Text = 'bad'; numeric.FocusLost:Fire(); assert(numeric.Text == '5')
numeric.Text = '1.5'; numeric.FocusLost:Fire(); assert(app.State.SkeletonThickness == 1.5)
press('Right'); assert(app.State.SkeletonThickness == 2)
-- UI drag-style numeric input and release.
local drag = find(find(app.Gui, 'Skeleton Thickness', 'TextButton'), 'ValueDrag')
drag.InputBegan:Fire({UserInputType = 'MouseButton1', Position = vector(200, 0)})
input.InputChanged:Fire({UserInputType = 'MouseMovement', Position = vector(224, 0)})
input.InputEnded:Fire({UserInputType = 'MouseButton1'})
assert(app.State.SkeletonThickness == 3)
find(app.Gui, 'Highlight Fill Color', 'TextButton').Activated:Fire()
local popup = find(app.Gui, 'ColorPicker')
find(popup, 'R', 'TextBox').Text = '12'
find(popup, 'G', 'TextBox').Text = '34'
find(popup, 'B', 'TextBox').Text = '56'
find(popup, 'Apply', 'TextButton').Activated:Fire()
assert(popup.destroyed and app.State.HighlightFillColor.R == 12 / 255)
assert(find(find(app.Gui, 'Highlight Fill Color', 'TextButton'), 'Swatch').BackgroundColor3.B == 56 / 255)
find(app.Gui, 'Highlight Fill Color', 'TextButton').Activated:Fire()
popup = find(app.Gui, 'ColorPicker')
press('RightShift'); assert(not app.Gui.Enabled and popup.destroyed)
press('RightShift'); assert(app.Gui.Enabled)
press('RightShift', true); assert(app.Gui.Enabled, 'Processed input must be ignored')
input.focus = numeric; press('RightShift'); assert(app.Gui.Enabled); input.focus = nil
find(app.Gui, 'ScrollDown').Activated:Fire(); assert(find(app.Gui, 'Controls').CanvasPosition.Y == 7)
find(app.Gui, 'ScrollUp').Activated:Fire(); assert(find(app.Gui, 'Controls').CanvasPosition.Y == 0)
local selected = find(app.Gui, 'Highlight Fill Color', 'TextButton')
selected.Activated:Fire(); find(find(app.Gui, 'ColorPicker'), 'Close').Activated:Fire()
press('Down'); press('Return'); assert(find(app.Gui, 'ColorPicker'))
find(find(app.Gui, 'ColorPicker'), 'Close').Activated:Fire()
app.Gui.AbsoluteSize = vector(307, 275)
app.Gui:GetPropertyChangedSignal('AbsoluteSize'):Fire()
assert(find(app.Gui, 'UIScale').Scale == 0.5)
app.Gui.AbsoluteSize = vector(614, 550); app.Gui:GetPropertyChangedSignal('AbsoluteSize'):Fire()
local handle = find(app.Gui, 'DragMenu')
handle.InputBegan:Fire({UserInputType = 'MouseButton1', Position = vector(20, 30)})
input.InputChanged:Fire({UserInputType = 'MouseMovement', Position = vector(50, 60)})
input.InputEnded:Fire({UserInputType = 'MouseButton1'})
assert(find(app.Gui, 'Violent').Position.X.Offset == 50)
local previousConnections = activeInputConnections()
local replacement = run()
assert(app.Gui.destroyed and activeInputConnections() == previousConnections, 'Re-execution cleans old UI listeners')
replacement.Destroy(); assert(activeInputConnections() == 0, 'No service listeners after destroy')
-- Missing/broken gethui and denied CoreGui are independent fallback cases.
gethui = nil
local coreApp = run(); assert(coreApp.Gui.Parent == core); coreApp.Destroy()
gethui = function() error('Unavailable executor API') end
core.reject = true
local fallback = run(); assert(fallback.Gui.Parent == playerGui); fallback.Destroy()
gethui = function() return 'not an Instance' end
fallback = run(); assert(fallback.Gui.Parent == playerGui); fallback.Destroy()
playerGui.reject = true
local ok, message = pcall(run)
assert(not ok and string.find(message, 'unable to parent ScreenGui'))
assert(activeInputConnections() == 0)
-- Only UI Instances are ever constructed, including the preview and picker.
local allowed = { ScreenGui=true, Frame=true, TextLabel=true, TextButton=true,
    TextBox=true, ScrollingFrame=true, UIStroke=true, UIScale=true, UIGradient=true,
    UICorner=true, CoreGui=true, Folder=true, PlayerGui=true, Player=true }
for _, object in ipairs(created) do assert(allowed[object.ClassName], object.ClassName) end
print('PASS standalone UI: defaults, controls, keyboard, picker, scaling, dragging, parenting, re-execution, cleanup')
'''


def main():
    assert OUTPUT.read_text(encoding='utf-8') == bundle(), 'Run tools/build_violent.py'
    features = (SOURCE / 'modules/Features.luau').read_text(encoding='utf-8')
    assert len(re.findall(r'= function\([^)]*\) end', features)) == 10, 'Feature hooks must stay empty'
    text = OUTPUT.read_text(encoding='utf-8')
    for forbidden in ('HttpGet', 'loadstring(', 'require(', 'FireServer', 'RenderStepped', 'workspace', 'Humanoid'):
        assert forbidden not in text, f'Unexpected gameplay/dependency API: {forbidden}'
    default = ROOT / 'tools/luau/bin/luau'
    runtime = os.environ.get('LUAU', str(default) if default.exists() else 'luau')
    with tempfile.TemporaryDirectory(prefix='violent-ui-') as directory:
        path = Path(directory) / 'test.luau'
        path.write_text(HARNESS + '\nlocal function run()\n' + text + '\nend\n' + CHECKS, encoding='utf-8')
        result = subprocess.run([runtime, str(path)], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        print(result.stdout.strip())


if __name__ == '__main__':
    main()
