--!nocheck
--[[
    Speed Hub X — Components
    =========================
    Reusable UI building blocks: window chrome, sidebar navigation,
    section headers, toggle rows, dropdown rows, slider rows, button
    rows, info rows, empty-state panels and page shells.

    Components are pure UI.  Event wiring accepts callbacks and invokes
    them; all feature logic lives (empty) in Features/*.luau.
]]

local Theme = require("Theme")
local Util = require("Util")
local Icons = require("Icons")

local M = Theme.Metrics
local C = Theme.Colors
local F = Theme.Fonts

local Components = {}

-- Tracks the currently open dropdown so only one is expanded at a time.
Components._openDropdown = nil

---------------------------------------------------------------------------
-- Window chrome
---------------------------------------------------------------------------
-- config = {
--   onClose: () -> ()   -- fired when the × button is clicked (UI only)
--   rootConnections: {} -- table the caller passes to collect connections
-- }
-- Returns a table with the root frame, the pages host, the sidebar host,
-- plus helpers to show/hide and destroy the window.
function Components.makeWindow(config)
    config = config or {}
    local connections = config.rootConnections or {}

    -- Root: transparent, holds the shadow + the visible panel.
    local root = Util.create("Frame", {
        Name = Theme.WindowName,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = M.WindowAnchor,
        Position = M.WindowPosition,
        Size = UDim2.fromOffset(M.WindowWidth, M.WindowHeight),
    })

    local uiScale = Util.create("UIScale", {
        Scale = Util.computeScale(M.WindowWidth, M.WindowHeight),
    })
    uiScale.Parent = root

    -- Soft drop shadow behind the panel.
    Util.create("Frame", {
        Name = "Shadow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 6),
        Size = UDim2.new(1, 26, 1, 26),
        BackgroundColor3 = C.WindowShadow,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Corner = M.WindowCorner + 8,
        ZIndex = 0,
    }).Parent = root

    -- Visible panel (the actual window).
    local panel = Util.create("Frame", {
        Name = "Panel",
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = C.WindowBackground,
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        Corner = M.WindowCorner,
        ZIndex = 1,
    })
    panel.Parent = root

    ------------------------------------------------------------------
    -- Title bar
    ------------------------------------------------------------------
    local titleBar = Util.create("Frame", {
        Name = "TitleBar",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, M.TitleBarHeight),
        ZIndex = 5,
    })
    titleBar.Parent = panel

    -- Invisible drag handle covering the title bar strip.
    local dragHandle = Util.create("TextButton", {
        Name = "DragHandle",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -M.CloseButtonSize - 30, 1, 0),
        ZIndex = 6,
    })
    dragHandle.Parent = titleBar

    local titleLabel = Util.create("TextLabel", {
        Name = "Title",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.TitlePaddingLeft, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(1, -120, 0, 30),
        Font = F.Title,
        TextColor3 = C.TextTitle,
        TextSize = M.TitleTextSize,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = Theme.Title,
        ZIndex = 6,
    })
    titleLabel.Parent = titleBar

    -- Close (×) button — primitive-drawn glyph so no font/asset is needed.
    local closeButton = Util.create("TextButton", {
        Name = "Close",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -M.CloseButtonSize / 2 - 14, 0.5, 0),
        Size = UDim2.fromOffset(M.CloseButtonSize, M.CloseButtonSize),
        ZIndex = 7,
        Corner = 8,
    })
    closeButton.Parent = titleBar

    local closeGlyph = Icons.close(Color3.fromRGB(245, 245, 245), 0, M.CloseGlyphSize)
    closeGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
    closeGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
    closeGlyph.ZIndex = 7
    closeGlyph.Parent = closeButton

    closeButton.MouseEnter:Connect(function()
        Util.tween(closeButton, 0.15, { BackgroundTransparency = 0.88, BackgroundColor3 = C.AccentBright })
    end)
    closeButton.MouseLeave:Connect(function()
        Util.tween(closeButton, 0.15, { BackgroundTransparency = 1 })
    end)
    closeButton.MouseButton1Click:Connect(function()
        if config.onClose then
            config.onClose()
        end
    end)

    ------------------------------------------------------------------
    -- Right-edge accent strip (thin red bar running down the edge)
    ------------------------------------------------------------------
    local strip = Util.create("Frame", {
        Name = "AccentStrip",
        BackgroundColor3 = C.StripMid,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(1, -2, 0, 78),
        Size = UDim2.new(0, M.AccentStripWidth, 1, -118),
        Corner = 2,
        Gradient = {
            Color = { C.StripTop, C.StripMid, C.StripBottom },
            Rotation = 90,
        },
        ZIndex = 5,
    })
    strip.Parent = panel

    ------------------------------------------------------------------
    -- Sidebar + pages hosts
    ------------------------------------------------------------------
    local sidebar = Util.create("Frame", {
        Name = "Sidebar",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.SidebarX, 0, M.SidebarY),
        Size = UDim2.new(0, M.SidebarWidth, 1, -M.SidebarY - 20),
        ZIndex = 4,
    })
    sidebar.Parent = panel

    local pagesHost = Util.create("Frame", {
        Name = "Pages",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.ContentX, 0, M.ContentY),
        Size = UDim2.new(1, -M.ContentX - M.ContentRightPad, 1, -M.ContentY - M.ContentBottomPad),
        ClipsDescendants = false,
        ZIndex = 4,
    })
    pagesHost.Parent = panel

    -- Drag wiring (title bar handle moves the whole window root).
    Util.makeDraggable(dragHandle, root, connections, function()
        return uiScale.Scale
    end)

    -- Keep the window fully on screen when the viewport changes.
    local scaleUpdate = Util.bindScale(uiScale, M.WindowWidth, M.WindowHeight, connections)

    local window = {}
    window.Root = root
    window.Panel = panel
    window.UiScale = uiScale
    window.Sidebar = sidebar
    window.Pages = pagesHost
    window.Connections = connections
    window.RefreshScale = scaleUpdate

    function window.SetVisible(visible)
        root.Visible = visible
    end

    function window.Destroy()
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        root:Destroy()
    end

    return window
end

---------------------------------------------------------------------------
-- Sidebar navigation button
---------------------------------------------------------------------------
-- config = {
--   id, label, iconBuilder (function(color, transparency) -> Frame),
--   order (0-based), onSelected(id)
-- }
function Components.navButton(parent, config)
    local button = Util.create("TextButton", {
        Name = "Nav_" .. config.id,
        Text = "",
        AutoButtonColor = false,
        BackgroundColor3 = C.RowBackground,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, config.order * M.NavPitch),
        Size = UDim2.new(0, M.SidebarWidth, 0, M.NavHeight),
        Corner = M.NavCorner,
        ZIndex = 4,
    })
    button.Parent = parent

    local idleColor = Color3.fromRGB(218, 218, 218)
    local activeColor = Color3.fromRGB(255, 255, 255)

    local icon = config.iconBuilder(idleColor, 0)
    icon.Position = UDim2.new(0, M.NavIconX, 0.5, 0)
    icon.AnchorPoint = Vector2.new(0, 0.5)
    icon.ZIndex = 5
    icon.Parent = button

    local separator = Util.create("TextLabel", {
        Name = "Separator",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.NavSeparatorX, 0, 0),
        Size = UDim2.new(0, 10, 1, 0),
        Font = F.Body,
        Text = "|",
        TextSize = 20,
        TextColor3 = C.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 5,
    })
    separator.Parent = button

    local label = Util.create("TextLabel", {
        Name = "Label",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.NavLabelX, 0, 0),
        Size = UDim2.new(1, -M.NavLabelX - 12, 1, 0),
        Font = F.NavLabel,
        Text = config.label,
        TextSize = M.NavTextSize,
        TextColor3 = C.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })
    label.Parent = button

    -- Gradient used only while active.
    local activeGradient = Instance.new("UIGradient")
    activeGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.AccentTop),
        ColorSequenceKeypoint.new(0.5, C.AccentMid),
        ColorSequenceKeypoint.new(1, C.AccentBottom),
    })
    activeGradient.Rotation = 90

    local api = {}
    local active = false

    local function setIconColor(color, transparency)
        for _, descendant in ipairs(icon:GetDescendants()) do
            if descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
                descendant.BackgroundColor3 = color
                descendant.BackgroundTransparency = transparency or 0
            elseif descendant:IsA("UIStroke") then
                descendant.Color = color
                descendant.Transparency = transparency or 0
            end
        end
    end

    function api.SetActive(isActive)
        active = isActive
        if active then
            button.BackgroundColor3 = C.AccentMid
            activeGradient.Parent = button
            separator.TextColor3 = Color3.fromRGB(255, 205, 205)
            label.TextColor3 = Color3.fromRGB(255, 235, 235)
            setIconColor(activeColor, 0.05)
        else
            activeGradient.Parent = nil
            button.BackgroundColor3 = C.RowBackground
            separator.TextColor3 = C.TextDim
            label.TextColor3 = C.TextPrimary
            setIconColor(idleColor, 0)
        end
    end

    button.MouseEnter:Connect(function()
        if not active then
            Util.tween(button, 0.15, { BackgroundColor3 = C.RowHover })
        end
    end)
    button.MouseLeave:Connect(function()
        if not active then
            Util.tween(button, 0.15, { BackgroundColor3 = C.RowBackground })
        end
    end)
    button.MouseButton1Click:Connect(function()
        if config.onSelected then
            config.onSelected(config.id)
        end
    end)

    api.Button = button
    api.SetActive(false)
    return api
end

---------------------------------------------------------------------------
-- Section header ("Skill" / "Aim" / "Body")
---------------------------------------------------------------------------
function Components.sectionHeader(parent, text, position)
    local header = Util.create("TextLabel", {
        Name = "Section_" .. text,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = position,
        Size = UDim2.new(1, 0, 0, M.HeaderHeight),
        Font = F.Header,
        Text = text,
        TextSize = M.HeaderTextSize,
        TextColor3 = Color3.fromRGB(250, 250, 250),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
    })
    header.Parent = parent
    return header
end

---------------------------------------------------------------------------
-- Shared row scaffold
---------------------------------------------------------------------------
local function makeRow(parent, name, position, size)
    local row = Util.create("Frame", {
        Name = name,
        BackgroundColor3 = C.RowBackground,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = position,
        Size = size or UDim2.new(1, 0, 0, M.RowHeight),
        Corner = M.RowCorner,
        ZIndex = 4,
    })
    row.Parent = parent
    return row
end

local function rowTitle(row, text, y)
    local label = Util.create("TextLabel", {
        Name = "Title",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.RowTextX, 0, y or M.RowTitleY),
        Size = UDim2.new(1, -M.RowTextX - 120, 0, 24),
        Font = F.RowTitle,
        Text = text,
        TextSize = M.RowTitleSize,
        TextColor3 = C.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })
    label.Parent = row
    return label
end

local function rowSubtitle(row, text, y)
    local label = Util.create("TextLabel", {
        Name = "Subtitle",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.RowTextX, 0, y or M.RowSubtitleY),
        Size = UDim2.new(1, -M.RowTextX - 120, 0, 18),
        Font = F.Body,
        Text = text,
        TextSize = M.RowSubtitleSize,
        TextColor3 = C.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })
    label.Parent = row
    return label
end

local function bindRowHover(row)
    row.MouseEnter:Connect(function()
        Util.tween(row, 0.15, { BackgroundColor3 = C.RowHover })
    end)
    row.MouseLeave:Connect(function()
        Util.tween(row, 0.15, { BackgroundColor3 = C.RowBackground })
    end)
end

---------------------------------------------------------------------------
-- Toggle row (Skill / Body controls)
---------------------------------------------------------------------------
-- config = { title, subtitle, defaultOn = true|false, onChanged(enabled) }
function Components.toggleRow(parent, config, position)
    local row = makeRow(parent, "Toggle_" .. config.title:gsub("%s+", ""), position)
    rowTitle(row, config.title, M.RowTitleY)
    if config.subtitle then
        rowSubtitle(row, config.subtitle, M.RowSubtitleY)
    end

    -- Track (rounded square)
    local track = Util.create("Frame", {
        Name = "Track",
        BackgroundColor3 = C.ToggleTrackOff,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -M.ToggleRightPad, 0.5, 0),
        Size = UDim2.fromOffset(M.ToggleTrackSize, M.ToggleTrackSize),
        Corner = M.ToggleTrackCorner,
        ZIndex = 6,
    })
    track.Parent = row

    -- Knob: circle + red gradient when ON, rounded square when OFF.
    local glow = Util.create("Frame", {
        Name = "Glow",
        BackgroundColor3 = C.AccentBright,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(M.ToggleKnobOnSize + 8, M.ToggleKnobOnSize + 8),
        Corner = 999,
        ZIndex = 6,
    })
    glow.Parent = track

    local knob = Util.create("Frame", {
        Name = "Knob",
        BackgroundColor3 = C.ToggleKnobOff,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(M.ToggleKnobOffSize, M.ToggleKnobOffSize),
        Corner = M.ToggleKnobOffCorner,
        ZIndex = 7,
    })
    knob.Parent = track

    local knobGradient = Util.create("UIGradient", {
        Color = { C.AccentGlowTop, C.AccentGlowBottom },
        Rotation = 90,
    })

    local state = { enabled = config.defaultOn and true or false }

    local function applyVisual(animated)
        local on = state.enabled
        local targetSize = on and M.ToggleKnobOnSize or M.ToggleKnobOffSize
        local targetCorner = on and math.floor(targetSize / 2) or M.ToggleKnobOffCorner
        -- Gradient only exists on top of the red (ON) knob.
        knobGradient.Parent = on and knob or nil
        if animated then
            Util.tween(track, 0.18, { BackgroundColor3 = on and C.ToggleTrackOn or C.ToggleTrackOff })
            Util.tween(knob, 0.18, {
                Size = UDim2.fromOffset(targetSize, targetSize),
                BackgroundColor3 = on and C.AccentBright or C.ToggleKnobOff,
            })
            Util.tween(knob.UICorner, 0.18, { CornerRadius = UDim.new(0, targetCorner) })
            Util.tween(glow, 0.18, { BackgroundTransparency = on and 0.72 or 1 })
        else
            track.BackgroundColor3 = on and C.ToggleTrackOn or C.ToggleTrackOff
            knob.Size = UDim2.fromOffset(targetSize, targetSize)
            knob.BackgroundColor3 = on and C.AccentBright or C.ToggleKnobOff
            knob.UICorner.CornerRadius = UDim.new(0, targetCorner)
            glow.BackgroundTransparency = on and 0.72 or 1
        end
    end

    local clickTarget = Util.create("TextButton", {
        Name = "ClickTarget",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 8,
    })
    clickTarget.Parent = row

    local function setEnabled(value, fireCallback)
        state.enabled = value and true or false
        applyVisual(true)
        if fireCallback ~= false and config.onChanged then
            config.onChanged(state.enabled)
        end
    end

    clickTarget.MouseButton1Click:Connect(function()
        setEnabled(not state.enabled, true)
    end)

    bindRowHover(row)
    applyVisual(false)

    return {
        Frame = row,
        Set = function(self, value)
            setEnabled(value, false)
        end,
        Get = function(self)
            return state.enabled
        end,
    }
end

---------------------------------------------------------------------------
-- Dropdown row ("Choose Aim Part")
---------------------------------------------------------------------------
-- config = {
--   label, value, options = {...}, onChanged(value),
--   panelHost (frame that absolutely-positioned dropdown panels float over)
-- }
function Components.dropdownRow(parent, config, position)
    local row = makeRow(parent, "Dropdown_" .. config.label:gsub("%s+", ""), position)
    rowTitle(row, config.label, 0)
    row.Title.TextSize = M.RowTitleSize
    row.Title.Size = UDim2.new(1, -M.PillWidth - M.ChevronGap - 70, 0, M.RowHeight)
    row.Title.Position = UDim2.new(0, M.RowTextX, 0, 0)
    row.Title.TextYAlignment = Enum.TextYAlignment.Center

    -- Chevron (^) — rotated 180° while expanded.
    local chevron = Icons.chevron(Color3.fromRGB(238, 238, 238), 0)
    chevron.AnchorPoint = Vector2.new(0.5, 0.5)
    chevron.Position = UDim2.new(1, -M.PillRightPad - M.PillWidth - M.ChevronGap, 0.5, 0)
    chevron.ZIndex = 6
    chevron.Parent = row

    -- Value pill (right side, centered bold text)
    local pill = Util.create("TextButton", {
        Name = "Value",
        Text = config.value,
        AutoButtonColor = false,
        BackgroundColor3 = C.RowBackgroundAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -M.PillRightPad, 0.5, 0),
        Size = UDim2.new(0, M.PillWidth, 0, M.PillHeight),
        Font = F.Pill,
        TextSize = M.PillTextSize,
        TextColor3 = Color3.fromRGB(245, 245, 245),
        Corner = M.PillCorner,
        ZIndex = 6,
    })
    pill.Parent = row

    local expanded = false
    local panel = nil

    local function closePanel()
        expanded = false
        Util.tween(chevron, 0.18, { Rotation = 0 })
        if panel then
            panel:Destroy()
            panel = nil
        end
        Components._openDropdown = nil
    end

    local function openPanel()
        if Components._openDropdown and Components._openDropdown ~= closePanel then
            Components._openDropdown()
        end
        expanded = true
        Util.tween(chevron, 0.18, { Rotation = 180 })

        local host = config.panelHost or parent
        local rowBottom = position.Y.Offset + M.RowHeight + 6
        local panelHeight = #config.options * M.OptionsRowHeight + 14

        panel = Util.create("Frame", {
            Name = "OptionsPanel",
            BackgroundColor3 = C.RowBackground,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, rowBottom),
            Size = UDim2.new(1, 0, 0, panelHeight),
            Corner = M.RowCorner,
            Stroke = { Color = Color3.fromRGB(44, 44, 44), Thickness = 1, Transparency = 0 },
            ZIndex = 40,
        })
        panel.Parent = host

        local selected = config.value
        for index, option in ipairs(config.options) do
            local optionRow = Util.create("TextButton", {
                Name = "Option_" .. option:gsub("%s+", ""),
                Text = "",
                AutoButtonColor = false,
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 7, 0, 7 + (index - 1) * M.OptionsRowHeight),
                Size = UDim2.new(1, -14, 0, M.OptionsRowHeight),
                Corner = 8,
                ZIndex = 41,
            })
            optionRow.Parent = panel

            local optionLabel = Util.create("TextLabel", {
                Name = "OptionLabel",
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 15, 0, 0),
                Size = UDim2.new(1, -70, 1, 0),
                Font = F.Body,
                Text = option,
                TextSize = 16,
                TextColor3 = option == selected and C.White or Color3.fromRGB(205, 205, 205),
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 42,
            })
            optionLabel.Parent = optionRow

            if option == selected then
                Util.create("Frame", {
                    Name = "SelectedDot",
                    BackgroundColor3 = C.AccentBright,
                    BorderSizePixel = 0,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(1, -18, 0.5, 0),
                    Size = UDim2.fromOffset(9, 9),
                    Corner = 999,
                    ZIndex = 42,
                }).Parent = optionRow
            end

            optionRow.MouseEnter:Connect(function()
                Util.tween(optionRow, 0.12, { BackgroundTransparency = 0.72 })
            end)
            optionRow.MouseLeave:Connect(function()
                Util.tween(optionRow, 0.12, { BackgroundTransparency = 1 })
            end)
            optionRow.MouseButton1Click:Connect(function()
                config.value = option
                pill.Text = option
                closePanel()
                if config.onChanged then
                    config.onChanged(option)
                end
            end)
        end

        Components._openDropdown = closePanel
    end

    local function toggle()
        if expanded then
            closePanel()
        else
            openPanel()
        end
    end

    local clickTarget = Util.create("TextButton", {
        Name = "ClickTarget",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 8,
    })
    clickTarget.Parent = row
    clickTarget.MouseButton1Click:Connect(toggle)
    pill.MouseButton1Click:Connect(toggle)

    bindRowHover(row)

    return {
        Frame = row,
        SetValue = function(self, value)
            config.value = value
            pill.Text = value
        end,
        GetValue = function(self)
            return config.value
        end,
        ClosePanel = closePanel,
    }
end

---------------------------------------------------------------------------
-- Slider row (component library — not mounted on any page by default)
---------------------------------------------------------------------------
-- config = { title, subtitle, min, max, default, onChanged(value) }
function Components.sliderRow(parent, config, position)
    local row = makeRow(parent, "Slider_" .. config.title:gsub("%s+", ""), position)
    rowTitle(row, config.title, M.RowTitleY)
    if config.subtitle then
        rowSubtitle(row, config.subtitle, M.RowSubtitleY)
    end

    local trackWidth = 210
    local track = Util.create("Frame", {
        Name = "Track",
        BackgroundColor3 = C.ToggleTrackOff,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -M.ToggleRightPad - 54, 0.5, 0),
        Size = UDim2.new(0, trackWidth, 0, 6),
        Corner = 3,
        ZIndex = 6,
    })
    track.Parent = row

    local fill = Util.create("Frame", {
        Name = "Fill",
        BackgroundColor3 = C.AccentBright,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
        Corner = 3,
        Gradient = { Color = { C.AccentGlowTop, C.AccentGlowBottom }, Rotation = 0 },
        ZIndex = 6,
    })
    fill.Parent = track

    local knob = Util.create("Frame", {
        Name = "Knob",
        BackgroundColor3 = Color3.fromRGB(240, 240, 240),
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        Corner = 999,
        ZIndex = 7,
        Stroke = { Color = Color3.fromRGB(0, 0, 0), Thickness = 1, Transparency = 0.6 },
    })
    knob.Parent = track

    local valueLabel = Util.create("TextLabel", {
        Name = "Value",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -M.ToggleRightPad + 50, 0.5, 0),
        Size = UDim2.new(0, 52, 0, 22),
        Font = F.Pill,
        Text = tostring(config.default or config.min),
        TextSize = 15,
        TextColor3 = C.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 6,
    })
    valueLabel.Parent = row

    local minValue = config.min or 0
    local maxValue = config.max or 100
    local value = config.default or minValue

    local function apply(newValue, fire)
        value = math.clamp(newValue, minValue, maxValue)
        local alpha = (value - minValue) / math.max(maxValue - minValue, 1e-6)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = tostring(math.floor(value + 0.5))
        if fire ~= false and config.onChanged then
            config.onChanged(value)
        end
    end

    local dragging = false
    local function updateFromInput(input)
        if track.Parent == nil then
            dragging = false
            return
        end
        local trackX = track.AbsolutePosition.X
        local trackWidthPixels = track.AbsoluteSize.X
        local alpha = math.clamp((input.Position.X - trackX) / math.max(trackWidthPixels, 1), 0, 1)
        apply(minValue + alpha * (maxValue - minValue), true)
    end

    local sliderHit = Util.create("TextButton", {
        Name = "SliderHit",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -M.ToggleRightPad - 54, 0.5, 0),
        Size = UDim2.new(0, trackWidth + 24, 0, 30),
        ZIndex = 8,
    })
    sliderHit.Parent = row

    sliderHit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input)
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)
    game:GetService("UserInputService").InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    bindRowHover(row)
    apply(value, false)

    return {
        Frame = row,
        Set = function(self, newValue)
            apply(newValue, false)
        end,
        Get = function(self)
            return value
        end,
    }
end

---------------------------------------------------------------------------
-- Button row (label + accent action button on the right)
---------------------------------------------------------------------------
-- config = { title, subtitle, buttonText, onClick() }
function Components.buttonRow(parent, config, position)
    local row = makeRow(parent, "Button_" .. config.title:gsub("%s+", ""), position)
    rowTitle(row, config.title, M.RowTitleY)
    if config.subtitle then
        rowSubtitle(row, config.subtitle, M.RowSubtitleY)
    end

    local button = Util.create("TextButton", {
        Name = "Action",
        Text = config.buttonText or "Run",
        AutoButtonColor = false,
        BackgroundColor3 = C.AccentMid,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -M.ToggleRightPad, 0.5, 0),
        Size = UDim2.new(0, 118, 0, 36),
        Font = F.Pill,
        TextSize = 15,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Corner = 9,
        Gradient = { Color = { C.AccentTop, C.AccentBottom }, Rotation = 90 },
        ZIndex = 6,
    })
    button.Parent = row

    button.MouseEnter:Connect(function()
        Util.tween(button, 0.15, { BackgroundColor3 = C.AccentBright })
    end)
    button.MouseLeave:Connect(function()
        Util.tween(button, 0.15, { BackgroundColor3 = C.AccentMid })
    end)
    button.MouseButton1Click:Connect(function()
        if config.onClick then
            config.onClick()
        end
    end)

    bindRowHover(row)
    return { Frame = row }
end

---------------------------------------------------------------------------
-- Info row (label — value, display only)
---------------------------------------------------------------------------
-- config = { label, value }
function Components.infoRow(parent, config, position)
    local row = makeRow(parent, "Info_" .. config.label:gsub("%s+", ""), position, UDim2.new(1, 0, 0, 46))

    Util.create("TextLabel", {
        Name = "Label",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, M.RowTextX, 0, 0),
        Size = UDim2.new(0.5, -M.RowTextX, 1, 0),
        Font = F.Body,
        Text = config.label,
        TextSize = 15,
        TextColor3 = C.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    }).Parent = row

    Util.create("TextLabel", {
        Name = "Value",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -M.RowTextX, 0.5, 0),
        Size = UDim2.new(0.5, -M.RowTextX, 1, 0),
        Font = F.Pill,
        Text = config.value,
        TextSize = 15,
        TextColor3 = C.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 5,
    }).Parent = row

    return { Frame = row }
end

---------------------------------------------------------------------------
-- Empty-state panel (Farming / Killer / Misc placeholders)
---------------------------------------------------------------------------
-- config = { iconBuilder, title, subtitle }
function Components.emptyState(parent, config)
    local holder = Util.create("Frame", {
        Name = "EmptyState_" .. config.title,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 4,
    })
    holder.Parent = parent

    local panel = Util.create("Frame", {
        Name = "Panel",
        BackgroundColor3 = Color3.fromRGB(24, 24, 24),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.42, 0),
        Size = UDim2.new(0, 420, 0, 240),
        Corner = 16,
        Stroke = { Color = Color3.fromRGB(46, 46, 46), Thickness = 1.2, Transparency = 0.15 },
        ZIndex = 4,
    })
    panel.Parent = holder

    local ghost = config.iconBuilder(Color3.fromRGB(120, 120, 120), 0.35)
    ghost.AnchorPoint = Vector2.new(0.5, 0)
    ghost.Position = UDim2.new(0.5, 0, 0, 34)
    ghost.ZIndex = 5
    local ghostScale = Instance.new("UIScale")
    ghostScale.Scale = 2.1
    ghostScale.Parent = ghost
    ghost.Parent = panel
    for _, descendant in ipairs(ghost:GetDescendants()) do
        if descendant:IsA("Frame") then
            -- keep the scaled-up ghost subtle
            descendant.BackgroundTransparency = math.min(descendant.BackgroundTransparency + 0.35, 1)
        elseif descendant:IsA("UIStroke") then
            descendant.Transparency = math.min(descendant.Transparency + 0.35, 1)
        end
    end

    Util.create("TextLabel", {
        Name = "Title",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 24, 0, 102),
        Size = UDim2.new(1, -48, 0, 30),
        Font = F.Header,
        Text = config.title,
        TextSize = 20,
        TextColor3 = Color3.fromRGB(214, 214, 214),
        ZIndex = 5,
    }).Parent = panel

    Util.create("TextLabel", {
        Name = "Subtitle",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 26, 0, 134),
        Size = UDim2.new(1, -52, 0, 66),
        Font = F.Body,
        Text = config.subtitle,
        TextSize = 13,
        TextColor3 = C.TextSecondary,
        TextWrapped = true,
        ZIndex = 5,
    }).Parent = panel

    return { Frame = holder }
end

---------------------------------------------------------------------------
-- Page shell — one per sidebar tab
---------------------------------------------------------------------------
function Components.makePage(pagesHost, name)
    local page = Util.create("Frame", {
        Name = "Page_" .. name,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
        ZIndex = 4,
    })
    page.Parent = pagesHost
    return page
end

return Components
