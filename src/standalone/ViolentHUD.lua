--[[
    VIOLENT / VISUALS HUD
    Standalone client-side GUI. Paste this entire file into a script executor.
    All feature hooks below are intentionally empty; only the interface changes.
    The module tables are local so no ModuleScripts, HTTP requests, or assets are needed.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then
    warn("VIOLENT HUD requires a live Roblox client with a LocalPlayer")
    return
end

-- Feature module: connect your own behavior here if desired. These are deliberately stubs.
local Features = {}
function Features.EnableSkeleton(_value) end
function Features.SkeletonThickness(_value) end
function Features.SkeletonColor(_value) end
function Features.HighlightESP(_value) end
function Features.HighlightFill(_value) end
function Features.HighlightOutline(_value) end
function Features.HighlightFillColor(_value) end
function Features.HighlightOutlineColor(_value) end
function Features.ShowHealthBar(_value) end
function Features.HealthBarSize(_value) end

-- Theme / primitive UI module.
local Theme = {
    pink = Color3.fromRGB(255, 0, 151),
    selected = Color3.fromRGB(247, 79, 167),
    dark = Color3.fromRGB(17, 22, 24),
    white = Color3.fromRGB(245, 245, 245),
    muted = Color3.fromRGB(207, 207, 207),
}
local function font(name, fallback)
    local ok, result = pcall(function() return Enum.Font[name] end)
    return ok and result or fallback
end
local displayFont = font("Anton", Enum.Font.GothamBlack)
local textFont = Enum.Font.Gotham
local Ui = {}
function Ui.make(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props or {}) do object[key] = value end
    object.Parent = parent
    return object
end
function Ui.frame(parent, x, y, w, h, color, transparency, z)
    return Ui.make("Frame", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = color, BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0, ZIndex = z or 1,
    }, parent)
end
function Ui.label(parent, text, x, y, w, h, size, color, alignment, z, chosenFont)
    return Ui.make("TextLabel", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, BorderSizePixel = 0, Text = text,
        TextColor3 = color or Theme.white, TextSize = size, Font = chosenFont or textFont,
        TextXAlignment = alignment or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, ZIndex = z or 2,
    }, parent)
end
function Ui.stroke(object, color, thickness, transparency)
    return Ui.make("UIStroke", {Color = color, Thickness = thickness or 1, Transparency = transparency or 0}, object)
end
function Ui.corner(object, radius)
    Ui.make("UICorner", {CornerRadius = UDim.new(0, radius)}, object)
end
function Ui.button(parent, x, y, w, h, z)
    return Ui.make("TextButton", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
        BorderSizePixel = 0, ZIndex = z or 5,
    }, parent)
end

-- Window module: prefer executor-provided GUI roots, then fall back to PlayerGui.
local Window = {}
function Window.create()
    local gui = Ui.make("ScreenGui", {
        Name = "ViolentHUDReplica", ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local parents = {}
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then table.insert(parents, result) end
    end
    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then table.insert(parents, core) end
    local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
    if playerGui then table.insert(parents, playerGui) end
    for _, parent in ipairs(parents) do
        local ok = pcall(function()
            local previous = parent:FindFirstChild(gui.Name)
            if previous then previous:Destroy() end
            gui.Parent = parent
        end)
        if ok and gui.Parent == parent then break end
    end
    if not gui.Parent then
        gui:Destroy()
        warn("VIOLENT HUD could not find a writable GUI parent")
        return nil
    end
    local canvas = Ui.frame(gui, 20, 27, 622, 508, Color3.new(), 1)
    local scale = Ui.make("UIScale", {Scale = 1}, canvas)
    -- Keep the complete layout on small viewports, but retain the reference's pixel sizes otherwise.
    local function resize()
        local camera = workspace.CurrentCamera
        if not camera then return end
        local size = camera.ViewportSize
        scale.Scale = math.min(1, math.max(0.1, (size.X - 20) / 622), math.max(0.1, (size.Y - 27) / 508))
    end
    resize()
    local cameraConnection
    local function watchCamera()
        if cameraConnection then cameraConnection:Disconnect() end
        local camera = workspace.CurrentCamera
        if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
        resize()
    end
    local cameraChanged = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
    watchCamera()
    gui.Destroying:Connect(function()
        cameraChanged:Disconnect()
        if cameraConnection then cameraConnection:Disconnect() end
    end)
    return gui, canvas
end

-- Static preview module. This is drawn entirely from GUI elements, not a live ESP.
local Preview = {}
function Preview.create(canvas)
    local panel = Ui.frame(canvas, 322, 0, 300, 312, Theme.dark, 0.12, 1)
    Ui.frame(panel, 0, 0, 300, 4, Color3.fromRGB(152, 28, 100), 0, 2)
    local title = Ui.label(panel, "ESP PREVIEW", 14, 10, 270, 25, 22, Theme.white, nil, 3, displayFont)
    title.TextStrokeColor3 = Color3.new(0, 0, 0)
    title.TextStrokeTransparency = 0.35
    local info = Ui.label(panel, "Roblox doesnt support highlights or selection boxes\nin viewportframes so previews arent possible on\nthose options.", 14, 39, 276, 37, 10, Theme.white, nil, 3, Enum.Font.GothamMedium)
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.TextWrapped = true

    -- Layered translucent rectangles suggest the purple preview glow.
    Ui.frame(panel, 59, 87, 151, 218, Color3.fromRGB(116, 0, 160), 0.91, 2)
    Ui.frame(panel, 64, 92, 142, 210, Color3.fromRGB(126, 0, 173), 0.86, 2)
    Ui.frame(panel, 70, 98, 130, 198, Color3.fromRGB(95, 0, 125), 0.52, 3)
    local box = Ui.frame(panel, 75, 99, 123, 195, Color3.fromRGB(89, 26, 113), 0.47, 4)
    Ui.stroke(box, Color3.fromRGB(5, 4, 7), 2)
    local inside = Ui.frame(box, 3, 3, 117, 189, Color3.fromRGB(74, 34, 93), 0.45, 4)
    Ui.stroke(inside, Color3.fromRGB(33, 5, 37), 1)
    Ui.make("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(71, 57, 86), Color3.fromRGB(86, 0, 120)), Rotation = 90}, inside)

    -- Example health bar at the left of the preview box.
    Ui.frame(panel, 69, 99, 5, 195, Color3.fromRGB(6, 5, 8), 0, 5)
    local health = Ui.frame(panel, 71, 139, 2, 154, Color3.new(1, 1, 1), 0, 6)
    Ui.make("UIGradient", {Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 255, 0)),
        ColorSequenceKeypoint.new(0.52, Color3.fromRGB(233, 220, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 37, 0)),
    }), Rotation = 90}, health)

    -- Stylized, deliberately inert mannequin, with a fine skeleton overlay.
    local figureColor = Color3.fromRGB(205, 186, 216)
    local head = Ui.frame(panel, 119, 122, 36, 43, figureColor, 0.48, 5)
    Ui.corner(head, 9)
    local torso = Ui.frame(panel, 115, 156, 40, 73, figureColor, 0.52, 5)
    Ui.corner(torso, 7)
    local arm = Ui.frame(panel, 113, 164, 11, 65, figureColor, 0.57, 5)
    Ui.corner(arm, 5)
    local leg1 = Ui.frame(panel, 119, 221, 17, 61, figureColor, 0.55, 5)
    local leg2 = Ui.frame(panel, 136, 221, 15, 61, figureColor, 0.55, 5)
    Ui.corner(leg1, 3); Ui.corner(leg2, 3)
    local bone = Color3.fromRGB(235, 229, 239)
    Ui.frame(panel, 135, 139, 1, 132, bone, 0.23, 6)
    Ui.frame(panel, 132, 181, 1, 37, bone, 0.25, 6)
    Ui.frame(panel, 138, 168, 1, 32, bone, 0.25, 6)
    Ui.frame(panel, 133, 180, 5, 1, bone, 0.25, 6)
    Ui.frame(panel, 132, 218, 3, 1, bone, 0.25, 6)
end

-- Controls module. State is local to the GUI and does not affect the game.
local Controls = {}
local palette = {
    Color3.fromRGB(255, 0, 230), Color3.fromRGB(255, 255, 255),
    Color3.fromRGB(255, 59, 89), Color3.fromRGB(255, 213, 0),
    Color3.fromRGB(54, 226, 111), Color3.fromRGB(50, 174, 255),
    Color3.fromRGB(164, 91, 255),
}
function Controls.create(canvas, gui)
    local panel = Ui.frame(canvas, 0, 0, 305, 483, Theme.dark, 0.12, 1)
    Ui.frame(panel, 0, 0, 305, 76, Theme.pink, 0, 2)
    local title = Ui.label(panel, "VIOLENT", 0, 9, 305, 63, 43, Color3.new(1, 1, 1), Enum.TextXAlignment.Center, 3, displayFont)
    title.TextStrokeColor3 = Color3.new(0, 0, 0)
    title.TextStrokeTransparency = 0
    Ui.frame(panel, 0, 76, 305, 29, Color3.new(0, 0, 0), 0, 2)
    Ui.label(panel, "VISUALS / HUD", 8, 77, 220, 27, 14, Theme.white, nil, 3)
    Ui.label(panel, "29/51", 240, 77, 57, 27, 14, Theme.muted, Enum.TextXAlignment.Right, 3)

    local status = Ui.frame(canvas, 0, 488, 305, 20, Color3.fromRGB(10, 10, 10), 0.05, 2)
    Ui.frame(canvas, 0, 485, 305, 2, Color3.fromRGB(147, 51, 104), 0.15, 2)
    local statusLabel = Ui.label(status, "Set color to: Highlight Outline Color", 7, 0, 291, 20, 11, Theme.white, nil, 3)

    local rows = {}
    local selected = 0
    local function section(text, y)
        local shadow = Ui.label(panel, text, 1, y + 3, 305, 23, 18, Theme.pink, Enum.TextXAlignment.Center, 3, displayFont)
        shadow.TextStrokeColor3 = Color3.new(0, 0, 0); shadow.TextStrokeTransparency = 0
        local label = Ui.label(panel, text, 0, y, 305, 23, 18, Theme.white, Enum.TextXAlignment.Center, 4, displayFont)
        label.TextStrokeColor3 = Color3.new(0, 0, 0); label.TextStrokeTransparency = 0
    end
    local function selectRow(index)
        selected = index
        for i, row in ipairs(rows) do
            row.highlight.Visible = i == index
            row.label.TextColor3 = i == index and Color3.new(0, 0, 0) or Theme.white
        end
        local row = rows[index]
        if row.kind == "color" then
            statusLabel.Text = "Set color to: " .. row.name
        elseif row.kind == "toggle" then
            statusLabel.Text = "Toggle: " .. row.name
        else
            statusLabel.Text = "Set value: " .. row.name
        end
    end
    local function render(row)
        if row.kind == "toggle" then
            row.check.Visible = row.value
        elseif row.kind == "number" then
            row.valueLabel.Text = tostring(row.value)
        else
            row.swatch.BackgroundColor3 = row.value
        end
    end
    local function change(row, direction)
        if row.kind == "toggle" then
            row.value = not row.value
        elseif row.kind == "number" then
            row.value = math.floor((math.clamp(row.value + row.step * direction, row.min, row.max) * 10) + 0.5) / 10
        else
            row.colorIndex = ((row.colorIndex - 1 + direction) % #palette) + 1
            row.value = palette[row.colorIndex]
        end
        render(row)
        row.callback(row.value)
    end
    local function add(name, kind, y, value, callback, extra)
        local row = {name = name, kind = kind, value = value, callback = callback}
        if extra then for k, v in pairs(extra) do row[k] = v end end
        row.highlight = Ui.frame(panel, 0, y, 305, 25, Theme.selected, 0, 2)
        row.highlight.Visible = false
        row.label = Ui.label(panel, name, 8, y, 250, 25, 13, Theme.white, nil, 3)
        if kind == "toggle" then
            local box = Ui.frame(panel, 278, y + 3, 19, 19, Color3.fromRGB(25, 32, 33), 0.45, 3)
            Ui.stroke(box, Color3.fromRGB(235, 235, 235), 2)
            row.check = Ui.label(box, "✓", 0, -2, 19, 20, 19, Theme.white, Enum.TextXAlignment.Center, 4, Enum.Font.GothamBold)
        elseif kind == "number" then
            row.valueLabel = Ui.label(panel, "", 258, y, 41, 25, 13, Theme.white, Enum.TextXAlignment.Right, 3)
        else
            row.swatch = Ui.frame(panel, 275, y + 3, 26, 19, value, 0, 3)
            Ui.stroke(row.swatch, Color3.fromRGB(45, 34, 42), 1)
        end
        render(row)
        table.insert(rows, row)
        local index = #rows
        Ui.button(panel, 0, y, 305, 25, 5).MouseButton1Click:Connect(function()
            selectRow(index)
            change(row, UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and -1 or 1)
        end)
    end

    add("Enable Skeleton", "toggle", 105, true, Features.EnableSkeleton)
    add("Skeleton Thickness", "number", 132, 1, Features.SkeletonThickness, {step = 0.5, min = 0.5, max = 10})
    add("Skeleton Color", "color", 159, Color3.new(1, 1, 1), Features.SkeletonColor, {colorIndex = 2})
    section("Highlights", 185)
    add("Highlight ESP", "toggle", 210, true, Features.HighlightESP)
    add("Highlight Fill", "toggle", 237, true, Features.HighlightFill)
    add("Highlight Outline", "toggle", 264, true, Features.HighlightOutline)
    add("Highlight Fill Color", "color", 291, palette[1], Features.HighlightFillColor, {colorIndex = 1})
    add("Highlight Outline Color", "color", 317, palette[1], Features.HighlightOutlineColor, {colorIndex = 1})
    section("Health Bar", 344)
    add("Show Health Bar", "toggle", 370, true, Features.ShowHealthBar)
    add("Health Bar Size", "number", 397, 2.5, Features.HealthBarSize, {step = 0.5, min = 0.5, max = 10})
    section("text", 425)

    -- Footer and navigation chevrons visible in the reference.
    Ui.frame(panel, 0, 454, 305, 29, Color3.fromRGB(13, 13, 13), 0.12, 2)
    Ui.label(panel, "Release, v1.4", 9, 454, 125, 28, 14, Theme.white, nil, 3, Enum.Font.Garamond).TextStrokeTransparency = 0.5
    Ui.frame(panel, 278, 453, 20, 2, Color3.fromRGB(140, 140, 140), 0, 3)
    local up = Ui.label(panel, "⌃", 139, 453, 23, 16, 21, Theme.white, Enum.TextXAlignment.Center, 3, Enum.Font.GothamBold)
    local down = Ui.label(panel, "⌄", 139, 463, 23, 16, 21, Theme.white, Enum.TextXAlignment.Center, 3, Enum.Font.GothamBold)
    Ui.button(panel, 139, 454, 23, 14, 5).MouseButton1Click:Connect(function() selectRow(((selected - 2) % #rows) + 1) end)
    Ui.button(panel, 139, 468, 23, 14, 5).MouseButton1Click:Connect(function() selectRow((selected % #rows) + 1) end)
    selectRow(8)

    local inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.Up then
            selectRow(((selected - 2) % #rows) + 1)
        elseif input.KeyCode == Enum.KeyCode.Down then
            selectRow((selected % #rows) + 1)
        elseif input.KeyCode == Enum.KeyCode.Left then
            change(rows[selected], -1)
        elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
            change(rows[selected], 1)
        end
    end)
    gui.Destroying:Connect(function() inputConnection:Disconnect() end)
end

local gui, canvas = Window.create()
if gui then
    Preview.create(canvas)
    Controls.create(canvas, gui)
end
