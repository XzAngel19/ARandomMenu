-- Speed Hub X | Version: 3.7.0 — standalone, client-side UI replica.
-- Paste this whole file into a Roblox script executor. No require, HttpGet, assets,
-- remotes, game-specific objects, or Roblox Studio services are needed.
-- Only the menu itself is interactive; every feature callback below is a no-op.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer

-- FEATURE MODULE -------------------------------------------------------------
-- Deliberately empty: UI changes must not perform any gameplay action.
local Features = {}
function Features.OnTabSelected(_tab) end
function Features.AutoUltimate(_enabled) end
function Features.AutoDash(_enabled) end
function Features.AimPart(_part) end
function Features.Aimlock(_enabled) end
function Features.AntiKnockback(_enabled) end
function Features.AntiStun(_enabled) end
function Features.AntiBusy(_enabled) end

-- CORE / DRAWING MODULE ------------------------------------------------------
local Core = {}
local C = {
    window = Color3.fromRGB(12, 12, 12),
    row = Color3.fromRGB(31, 31, 31),
    inset = Color3.fromRGB(39, 39, 39),
    red = Color3.fromRGB(193, 0, 12),
    selected = Color3.fromRGB(172, 6, 9),
    white = Color3.fromRGB(244, 244, 244),
    muted = Color3.fromRGB(169, 169, 169),
    hint = Color3.fromRGB(117, 117, 117),
}

function Core.make(className, parent, properties)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

function Core.round(object, radius)
    Core.make("UICorner", object, { CornerRadius = UDim.new(0, radius) })
    return object
end

function Core.label(parent, text, x, y, w, h, size, color, bold)
    return Core.make("TextLabel", parent, {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        Text = text,
        TextColor3 = color or C.white,
        TextSize = size,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BorderSizePixel = 0,
    })
end

function Core.strokeLine(parent, x1, y1, x2, y2, color, thickness)
    local dx, dy = x2 - x1, y2 - y1
    return Core.make("Frame", parent, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
        Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thickness or 2),
        Rotation = math.deg(math.atan2(dy, dx)),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    })
end

-- Vector icons: no external images or font-dependent emoji.
function Core.icon(parent, name, color)
    local holder = Core.make("Frame", parent, {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(24, 24),
        BorderSizePixel = 0,
    })
    local function line(x1, y1, x2, y2)
        Core.strokeLine(holder, x1, y1, x2, y2, color, 2)
    end
    if name == "Home" then
        -- Broken-corner focus mark in the reference's first sidebar row.
        line(3, 8, 3, 5); line(3, 5, 7, 5)
        line(17, 5, 21, 5); line(21, 5, 21, 9)
        line(3, 15, 3, 19); line(3, 19, 7, 19)
        line(17, 19, 21, 19); line(21, 19, 21, 15)
        line(10, 12, 14, 12)
    elseif name == "Main" then
        line(3, 11, 12, 4); line(12, 4, 21, 11)
        line(5, 10, 5, 21); line(19, 10, 19, 21); line(5, 21, 19, 21)
        line(10, 21, 10, 14); line(10, 14, 14, 14); line(14, 14, 14, 21)
    elseif name == "Farming" then
        line(7, 6, 20, 20); line(4, 11, 13, 2)
        line(4, 11, 4, 6); line(13, 2, 18, 2)
    elseif name == "Killer" then
        line(4, 12, 3, 8); line(3, 8, 6, 6); line(6, 6, 8, 8)
        line(8, 8, 9, 4); line(9, 4, 12, 4); line(12, 4, 13, 8)
        line(13, 8, 15, 5); line(15, 5, 18, 6); line(18, 6, 18, 12)
        line(18, 12, 21, 10); line(21, 10, 21, 17)
        line(21, 17, 17, 21); line(17, 21, 7, 21); line(7, 21, 4, 17)
    elseif name == "Misc" then
        line(2, 19, 8, 5); line(8, 5, 13, 13)
        line(13, 13, 16, 9); line(16, 9, 22, 19)
        line(2, 19, 22, 19); line(6, 14, 12, 16); line(12, 16, 18, 13)
    end
    return holder
end

function Core.parentGui(gui)
    -- Executors differ: gethui is preferred, but CoreGui and PlayerGui work
    -- as fallbacks. Assignment is guarded because some executors deny CoreGui.
    local candidates = {}
    if type(gethui) == "function" then
        local ok, hidden = pcall(gethui)
        if ok and typeof(hidden) == "Instance" then
            table.insert(candidates, hidden)
        end
    end
    table.insert(candidates, CoreGui)
    for _, parent in ipairs(candidates) do
        local ok = pcall(function() gui.Parent = parent end)
        if ok and gui.Parent == parent then
            return
        end
    end
    if player then
        local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
        if playerGui then
            local ok = pcall(function() gui.Parent = playerGui end)
            if ok and gui.Parent == playerGui then return end
        end
    end
    gui:Destroy()
    error("Speed Hub X: could not parent the client GUI")
end

function Core.window(gui, connect)
    local root = Core.make("Frame", gui, {
        Name = "MenuRoot",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.58, 0.495),
        Size = UDim2.fromOffset(1016, 646),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    })
    local scale = Core.make("UIScale", root, { Scale = 1 })
    local function updateScale()
        local camera = workspace.CurrentCamera
        if camera then
            local viewport = camera.ViewportSize
            scale.Scale = math.min(1, viewport.X / 1350, viewport.Y / 760)
        end
    end
    local cameraConnection
    local function watchCamera()
        if cameraConnection then cameraConnection:Disconnect() end
        local camera = workspace.CurrentCamera
        if camera then
            cameraConnection = connect(camera:GetPropertyChangedSignal("ViewportSize"), updateScale)
        end
        updateScale()
    end
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
    watchCamera()

    local shadow = Core.round(Core.make("Frame", root, {
        Position = UDim2.fromOffset(1, 5),
        Size = UDim2.fromOffset(1016, 646),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.52,
        BorderSizePixel = 0,
    }), 14)
    local window = Core.round(Core.make("Frame", root, {
        Name = "Window",
        Size = UDim2.fromOffset(1016, 646),
        BackgroundColor3 = C.window,
        BackgroundTransparency = 0.035,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }), 14)
    Core.make("UIStroke", window, {
        Color = Color3.fromRGB(36, 30, 30), Thickness = 1, Transparency = 0.38,
    })
    -- The screenshot has a very fine crimson edge on the far right.
    Core.make("Frame", window, {
        Position = UDim2.fromOffset(1013, 64),
        Size = UDim2.new(0, 2, 1, -66),
        BackgroundColor3 = C.red,
        BackgroundTransparency = 0.58,
        BorderSizePixel = 0,
    })
    Core.label(window, "Speed Hub X | Version: 3.7.0", 28, 9, 530, 35, 20, C.white, false)

    local close = Core.make("TextButton", window, {
        Name = "Close", Position = UDim2.fromOffset(960, 5),
        Size = UDim2.fromOffset(48, 42), BackgroundTransparency = 1,
        Text = "×", TextSize = 32, Font = Enum.Font.Gotham,
        TextColor3 = C.white, BorderSizePixel = 0,
    })

    -- Small detached black/red S tile at the left of the window, kept visible
    -- when the menu is closed so it can be reopened.
    local launcher = Core.round(Core.make("TextButton", root, {
        Name = "Launcher", Position = UDim2.fromOffset(-168, 76),
        Size = UDim2.fromOffset(65, 65), BackgroundColor3 = Color3.fromRGB(3, 3, 3),
        Text = "", BorderSizePixel = 0, AutoButtonColor = false,
    }), 10)
    Core.label(launcher, "S", 13, 2, 47, 58, 45, Color3.fromRGB(85, 0, 7), true)
    Core.label(launcher, "S", 11, 0, 47, 58, 45, C.red, true)
    Core.make("UIStroke", launcher, {
        Color = Color3.fromRGB(17, 17, 17), Thickness = 1,
    })
    connect(close.MouseButton1Click, function()
        window.Visible = false
        shadow.Visible = false
    end)
    connect(launcher.MouseButton1Click, function()
        window.Visible = not window.Visible
        shadow.Visible = window.Visible
    end)

    -- Drag only from the title strip, not from controls or the scroll area.
    local dragHandle = Core.make("TextButton", window, {
        Name = "DragHandle", Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(950, 57), Text = "", BackgroundTransparency = 1,
        BorderSizePixel = 0, AutoButtonColor = false,
    })
    local dragging, dragInput, dragStart, positionStart = false, nil, nil, nil
    connect(dragHandle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragInput = true, input
            dragStart, positionStart = input.Position, root.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if not dragging then return end
        if (dragInput.UserInputType == Enum.UserInputType.Touch and input ~= dragInput)
            or (dragInput.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseMovement) then
            return
        end
        local delta = input.Position - dragStart
        -- UIScale scales the window's children, not root's screen position.
        root.Position = UDim2.new(positionStart.X.Scale, positionStart.X.Offset + delta.X,
            positionStart.Y.Scale, positionStart.Y.Offset + delta.Y)
    end)
    connect(UserInputService.InputEnded, function(input)
        if dragging and (input == dragInput
            or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseButton1)) then
            dragging = false
        end
    end)
    return window
end

-- CONTROL / SECTION MODULE ---------------------------------------------------
local Controls = {}
function Controls.section(page, title, y)
    Core.label(page, title, 9, y, 620, 30, 23, C.white, true)
end

local function rowBase(page, y, height)
    return Core.round(Core.make("Frame", page, {
        Position = UDim2.fromOffset(0, y),
        Size = UDim2.fromOffset(682, height),
        BackgroundColor3 = C.row, BorderSizePixel = 0,
    }), 11)
end

function Controls.toggle(page, spec, connect)
    local row = rowBase(page, spec.y, 56)
    Core.label(row, spec.title, 17, 6, 560, 24, 16, C.white, false)
    Core.label(row, spec.description, 17, 28, 560, 20, 13, C.hint, false)
    local switch = Core.round(Core.make("TextButton", row, {
        Name = spec.title, Position = UDim2.fromOffset(626, 9),
        Size = UDim2.fromOffset(39, 38), BackgroundColor3 = C.inset,
        Text = "", BorderSizePixel = 0, AutoButtonColor = false,
    }), 10)
    local dot = Core.round(Core.make("Frame", switch, {
        Size = UDim2.fromOffset(23, 23), BorderSizePixel = 0,
    }), 12)
    local enabled = spec.initial == true
    local function paint()
        dot.Position = UDim2.fromOffset(enabled and 8 or 3, 7)
        dot.BackgroundColor3 = enabled and C.red or Color3.fromRGB(35, 35, 35)
    end
    paint()
    connect(switch.MouseButton1Click, function()
        enabled = not enabled
        paint()
        if spec.onChange then spec.onChange(enabled) end
    end)
    return row
end

function Controls.dropdown(page, spec, connect)
    local row = rowBase(page, spec.y, 46)
    Core.label(row, spec.title, 17, 4, 340, 38, 16, C.white, false)
    -- Upward chevron exactly as seen to the left of the selected value.
    local chevron = Core.make("Frame", row, {
        Position = UDim2.fromOffset(352, 14), Size = UDim2.fromOffset(23, 18),
        BackgroundTransparency = 1, BorderSizePixel = 0,
    })
    Core.strokeLine(chevron, 5, 11, 12, 4, C.white, 2)
    Core.strokeLine(chevron, 12, 4, 19, 11, C.white, 2)
    local value = Core.round(Core.make("TextButton", row, {
        Name = spec.title, Position = UDim2.fromOffset(387, 6),
        Size = UDim2.fromOffset(277, 34), BackgroundColor3 = C.inset,
        Text = spec.value, TextColor3 = C.white, TextSize = 22,
        Font = Enum.Font.GothamBold, BorderSizePixel = 0, AutoButtonColor = false,
    }), 9)
    -- Options are hidden until clicked; the initial frame matches the image.
    local popup = Core.round(Core.make("Frame", page, {
        Name = "AimPartOptions", Position = UDim2.fromOffset(387, spec.y + 48),
        Size = UDim2.fromOffset(277, 0), BackgroundColor3 = C.inset,
        BorderSizePixel = 0, Visible = false, ZIndex = 15,
    }), 9)
    local options = spec.options or { spec.value }
    popup.Size = UDim2.fromOffset(277, #options * 34 + 4)
    for index, option in ipairs(options) do
        local item = Core.make("TextButton", popup, {
            Position = UDim2.fromOffset(2, 2 + (index - 1) * 34),
            Size = UDim2.fromOffset(273, 34), BackgroundTransparency = 1,
            Text = option, TextSize = 16, Font = Enum.Font.Gotham,
            TextColor3 = C.white, BorderSizePixel = 0, ZIndex = 16,
        })
        connect(item.MouseButton1Click, function()
            value.Text = option
            popup.Visible = false
            if spec.onChange then spec.onChange(option) end
        end)
    end
    local labelHitbox = Core.make("TextButton", row, {
        Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(387, 46),
        BackgroundTransparency = 1, Text = "", BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    local function toggleOptions() popup.Visible = not popup.Visible end
    connect(value.MouseButton1Click, toggleOptions)
    connect(labelHitbox.MouseButton1Click, toggleOptions)
    return row
end

-- Reusable controls for future pages; neither is mounted in the pictured Main
-- page, which contains no visible slider or action button.
function Controls.button(page, spec, connect)
    local row = rowBase(page, spec.y, 46)
    local button = Core.make("TextButton", row, {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Text = spec.title, TextColor3 = C.white, Font = Enum.Font.Gotham,
        TextSize = 16, BorderSizePixel = 0,
    })
    connect(button.MouseButton1Click, function()
        if spec.onClick then spec.onClick() end
    end)
    return row
end

function Controls.slider(page, spec, connect)
    local row = rowBase(page, spec.y, 56)
    Core.label(row, spec.title, 17, 3, 450, 25, 16, C.white)
    local track = Core.round(Core.make("Frame", row, {
        Position = UDim2.fromOffset(17, 40), Size = UDim2.fromOffset(646, 5),
        BackgroundColor3 = C.inset, BorderSizePixel = 0,
    }), 3)
    local fill = Core.round(Core.make("Frame", track, {
        Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.red,
        BorderSizePixel = 0,
    }), 3)
    local knob = Core.round(Core.make("TextButton", track, {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(15, 15), BackgroundColor3 = C.red,
        Text = "", BorderSizePixel = 0, AutoButtonColor = false,
    }), 8)
    local dragInput
    local function setValue(input)
        local fraction = math.clamp((input.Position.X - track.AbsolutePosition.X)
            / math.max(1, track.AbsoluteSize.X), 0, 1)
        fill.Size = UDim2.fromScale(fraction, 1)
        knob.Position = UDim2.fromScale(fraction, 0.5)
        if spec.onChange then
            spec.onChange(spec.min + (spec.max - spec.min) * fraction)
        end
    end
    local range = math.max(0.0001, spec.max - spec.min)
    local initial = math.clamp((spec.value - spec.min) / range, 0, 1)
    fill.Size = UDim2.fromScale(initial, 1)
    knob.Position = UDim2.fromScale(initial, 0.5)
    local hitbox = Core.make("TextButton", row, {
        Position = UDim2.fromOffset(17, 28), Size = UDim2.fromOffset(646, 25),
        BackgroundTransparency = 1, Text = "", BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    local function begin(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
            setValue(input)
        end
    end
    connect(hitbox.InputBegan, begin)
    connect(UserInputService.InputChanged, function(input)
        if dragInput and (input == dragInput
            or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            setValue(input)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input == dragInput then dragInput = nil end
    end)
    return row
end

-- NAVIGATION MODULE ----------------------------------------------------------
local Navigation = {}
function Navigation.build(window, pages, connect)
    local names = { "Home", "Main", "Farming", "Killer", "Misc" }
    local buttons = {}
    local function selectTab(selected)
        for name, page in pairs(pages) do page.Visible = (name == selected) end
        for name, item in pairs(buttons) do
            local active = name == selected
            item.row.BackgroundColor3 = active and C.selected or C.row
            item.caption.TextColor3 = active and Color3.fromRGB(214, 128, 128) or C.muted
            -- Vector icon strokes are recolored along with the label.
            for _, shape in ipairs(item.icon:GetChildren()) do
                if shape:IsA("Frame") then
                    shape.BackgroundColor3 = active and Color3.fromRGB(219, 88, 88) or C.muted
                end
            end
        end
        Features.OnTabSelected(selected)
    end
    for index, name in ipairs(names) do
        local row = Core.round(Core.make("TextButton", window, {
            Name = name .. "Tab", Position = UDim2.fromOffset(19, 69 + (index - 1) * 54),
            Size = UDim2.fromOffset(259, 45), BackgroundColor3 = C.row,
            Text = "", BorderSizePixel = 0, AutoButtonColor = false,
        }), 11)
        local icon = Core.icon(row, name, C.muted)
        icon.Position = UDim2.fromOffset(14, 10)
        local caption = Core.label(row, "|  " .. name, 46, 4, 198, 37, 16, C.muted)
        buttons[name] = { row = row, icon = icon, caption = caption }
        connect(row.MouseButton1Click, function() selectTab(name) end)
    end
    selectTab("Main")
end

-- ASSEMBLY -------------------------------------------------------------------
local gui = Core.make("ScreenGui", nil, {
    Name = "SpeedHubX_Standalone_370", ResetOnSpawn = false,
    IgnoreGuiInset = true, DisplayOrder = 1000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local connections = {}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function dispose()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
end
connect(gui.Destroying, dispose)

-- Remove only this script's earlier GUI when re-executed, not other GUIs.
local environment = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then environment = result end
end
if typeof(environment.__SpeedHubXStandalone370) == "Instance" then
    pcall(function() environment.__SpeedHubXStandalone370:Destroy() end)
end
Core.parentGui(gui)
environment.__SpeedHubXStandalone370 = gui

local window = Core.window(gui, connect)
local pages = {}
for _, name in ipairs({ "Home", "Main", "Farming", "Killer", "Misc" }) do
    local page = Core.make("ScrollingFrame", window, {
        Name = name .. "Page", Position = UDim2.fromOffset(315, 58),
        Size = UDim2.fromOffset(682, 577), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.hint,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.fromOffset(0, 577), Visible = false,
    })
    pages[name] = page
    if name ~= "Main" then
        -- The reference does not show the contents of other pages.
        Controls.section(page, name, 8)
    end
end

local main = pages.Main
Controls.section(main, "Skill", 8)
Controls.toggle(main, {
    y = 46, title = "Auto Ultimate", description = "This is Meaning Auto Use Ultimate",
    initial = true, onChange = Features.AutoUltimate,
}, connect)
Controls.toggle(main, {
    y = 110, title = "Auto Dash", description = "This is Meaning Auto Use Dash",
    initial = true, onChange = Features.AutoDash,
}, connect)

Controls.section(main, "Aim", 181)
Controls.dropdown(main, {
    y = 221, title = "Choose Aim Part", value = "Head",
    options = { "Head", "Torso", "HumanoidRootPart" },
    onChange = Features.AimPart,
}, connect)
Controls.toggle(main, {
    y = 276, title = "Aimlock", description = "Aimlock = Lock Camera Player",
    onChange = Features.Aimlock,
}, connect)

Controls.section(main, "Body", 349)
Controls.toggle(main, {
    y = 387, title = "Anti-Knockback", description = "BETA",
    onChange = Features.AntiKnockback,
}, connect)
Controls.toggle(main, {
    y = 451, title = "Anti-Stun", description = "BETA",
    onChange = Features.AntiStun,
}, connect)
Controls.toggle(main, {
    y = 515, title = "Anti-Busy", description = "BETA",
    onChange = Features.AntiBusy,
}, connect)
Navigation.build(window, pages, connect)
