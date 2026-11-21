--!strict
--[[
    VIOLENT — ESP Visuals / HUD menu (standalone, executor-ready)

    A pixel-faithful replica of the "VIOLENT" ESP menu: a hot-pink branded
    main window (VISUALS / HUD) plus a separate ESP PREVIEW window showing a
    blocky avatar, skeleton overlay and rainbow health bar.

    HOW TO RUN (script executor, live client — not Roblox Studio):
        loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/76bb1400-arandommenu/src/gui/Violent/Violent.lua"))()

    Toggle the menu with RightShift. Drag either window by its header.

    MODULE MAP (single self-contained file, cleanly separated modules):
        Util        — instance factory, safe parenting fallback, dragging
        Theme       — colors / fonts / sizes (single source of truth)
        State       — settings table + EMPTY stub callbacks (wire features here)
        Window      — main window + preview window shells (headers, borders)
        Controls    — toggle / slider / color / dropdown / section components
        Preview     — ESP preview viewport (avatar, skeleton, health bar)
        Navigation  — VISUALS / HUD header + tab stub
        Main        — assembly, control stacking, toggle key

    Every feature callback in State.Callbacks is intentionally EMPTY.
    This file builds the full UI only — no gameplay logic.
]]

-- ================= MODULE: Util =================
local Util = (function()
    local env: any = (type(getfenv) == "function" and getfenv()) or _G

    local function ref(value: any): any
        local clonerefFn = env.cloneref
        if type(clonerefFn) == "function" then
            local ok, result = pcall(clonerefFn, value)
            if ok then
                return result
            end
        end
        return value
    end

    local function create(className: string, properties: {[string]: any}): any
        local instance = Instance.new(className)
        for property, value in pairs(properties) do
            if property ~= "Parent" then
                (instance :: any)[property] = value
            end
        end
        local parent = properties.Parent
        if parent ~= nil then
            instance.Parent = parent
        end
        return instance
    end

    local function stroke(object: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
        return create("UIStroke", {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Color = color,
            Thickness = thickness,
            Transparency = transparency or 0,
            Parent = object,
        })
    end

    local function textStroke(label: TextLabel, color: Color3, thickness: number): UIStroke
        return create("UIStroke", {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
            Color = color,
            Thickness = thickness,
            Transparency = 0,
            Parent = label,
        })
    end

    -- Safe executor parenting: gethui() -> CoreGui -> PlayerGui.
    local function parentScreenGui(screenGui: ScreenGui, playerGui: PlayerGui): ()
        local synEnv = env.syn
        if type(synEnv) == "table" and type(synEnv.protect_gui) == "function" then
            pcall(synEnv.protect_gui, screenGui)
        end
        local getHiddenUi = env.gethui
        if type(getHiddenUi) == "function" then
            local ok, hiddenUi = pcall(getHiddenUi)
            if ok and typeof(hiddenUi) == "Instance" then
                local parented = pcall(function()
                    screenGui.Parent = hiddenUi
                end)
                if parented then
                    return
                end
            end
        end
        local coreOk, coreGui = pcall(function()
            return game:GetService("CoreGui")
        end)
        if coreOk and coreGui ~= nil then
            local parented = pcall(function()
                screenGui.Parent = coreGui
            end)
            if parented then
                return
            end
        end
        screenGui.Parent = playerGui
    end

    local function destroyExisting(name: string, playerGui: PlayerGui): ()
        local locations: {Instance} = {playerGui}
        local coreOk, coreGui = pcall(function()
            return game:GetService("CoreGui")
        end)
        if coreOk and coreGui ~= nil then
            table.insert(locations, coreGui)
        end
        local getHiddenUi = env.gethui
        if type(getHiddenUi) == "function" then
            local ok, hiddenUi = pcall(getHiddenUi)
            if ok and typeof(hiddenUi) == "Instance" then
                table.insert(locations, hiddenUi)
            end
        end
        for _, location in ipairs(locations) do
            local existing = location:FindFirstChild(name)
            while existing ~= nil do
                existing:Destroy()
                existing = location:FindFirstChild(name)
            end
        end
    end

    local function makeDraggable(frame: Frame, handle: GuiObject, userInputService: UserInputService): ()
        local dragging = false
        local dragStart = Vector3.zero
        local frameStart = UDim2.new()
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                frameStart = frame.Position
                input.Changed:Connect(function()
                    if input.UserState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        userInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X, frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
            end
        end)
    end

    return {
        Env = env,
        Ref = ref,
        Create = create,
        Stroke = stroke,
        TextStroke = textStroke,
        ParentScreenGui = parentScreenGui,
        DestroyExisting = destroyExisting,
        MakeDraggable = makeDraggable,
    }
end)()

-- ================= MODULE: Theme =================
local Theme = (function()
    return {
        Accent = Color3.fromRGB(247, 37, 133),
        Panel = Color3.fromRGB(30, 30, 30),
        PanelDark = Color3.fromRGB(20, 20, 20),
        RowHover = Color3.fromRGB(43, 43, 43),
        Separator = Color3.fromRGB(52, 52, 52),
        Text = Color3.fromRGB(232, 232, 232),
        TextDark = Color3.fromRGB(20, 20, 20),
        Muted = Color3.fromRGB(154, 160, 166),
        TooltipText = Color3.fromRGB(200, 200, 200),
        CheckBorder = Color3.fromRGB(185, 185, 185),
        CheckBg = Color3.fromRGB(36, 36, 36),
        PreviewBg = Color3.fromRGB(26, 11, 46),
        PreviewBg2 = Color3.fromRGB(48, 28, 82),
        Avatar = Color3.fromRGB(201, 168, 232),
        Skeleton = Color3.fromRGB(255, 255, 255),
        FontDisplay = Enum.Font.LuckiestGuy,
        FontBody = Enum.Font.Gotham,
        FontBodyMedium = Enum.Font.GothamMedium,
        FontBodyBold = Enum.Font.GothamBold,
        MainWidth = 300,
        MainHeight = 552,
        MainHeaderHeight = 64,
        RowHeight = 30,
        SectionHeight = 36,
        MetaHeight = 28,
        TooltipHeight = 22,
        PreviewWidth = 240,
        PreviewHeight = 300,
        PreviewHeaderHeight = 88,
    }
end)()

-- ================= MODULE: State (stub callbacks) =================
local State = (function()
    local Settings: {[string]: any} = {
        EnableSkeleton = true,
        SkeletonThickness = 1,
        SkeletonColor = Color3.fromRGB(255, 255, 255),
        HighlightESP = true,
        HighlightFill = true,
        HighlightOutline = true,
        HighlightFillColor = Color3.fromRGB(255, 0, 180),
        HighlightOutlineColor = Color3.fromRGB(255, 105, 180),
        ShowHealthBar = true,
        HealthBarSize = 2.5,
        Version = "Release, v1.4",
    }

    -- STUBS: intentionally empty. Wire real features here later.
    local Callbacks = {
        onToggle = function(_id: string, _value: boolean) end,
        onSlider = function(_id: string, _value: number) end,
        onColor = function(_id: string, _color: Color3) end,
        onVersion = function(_version: string) end,
        onTab = function(_tab: string) end,
    }

    return { Settings = Settings, Callbacks = Callbacks }
end)()

-- ================= MODULE: Window =================
local Window = (function()
    local function createMain(screenGui: ScreenGui, userInputService: UserInputService)
        local window: Frame = Util.Create("Frame", {
            Name = "MainWindow",
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(100, 80),
            Size = UDim2.fromOffset(Theme.MainWidth, Theme.MainHeight),
            ZIndex = 1,
            Parent = screenGui,
        })
        Util.Stroke(window, Color3.fromRGB(10, 10, 10), 1)

        local header: Frame = Util.Create("Frame", {
            Name = "Header",
            Active = true,
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, Theme.MainHeaderHeight),
            ZIndex = 2,
            Parent = window,
        })

        local title: TextLabel = Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontDisplay,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "VIOLENT",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 38,
            ZIndex = 3,
            Parent = header,
        })
        Util.TextStroke(title, Color3.fromRGB(0, 0, 0), 5)

        local body: Frame = Util.Create("Frame", {
            Name = "Body",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, Theme.MainHeaderHeight),
            Size = UDim2.new(1, 0, 1, -(Theme.MainHeaderHeight + Theme.TooltipHeight)),
            ZIndex = 1,
            Parent = window,
        })

        local tooltipBar: Frame = Util.Create("Frame", {
            Name = "TooltipBar",
            BackgroundColor3 = Theme.PanelDark,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 1, -Theme.TooltipHeight),
            Size = UDim2.new(1, 0, 0, Theme.TooltipHeight),
            ZIndex = 2,
            Parent = window,
        })

        Util.Create("Frame", {
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 2),
            ZIndex = 3,
            Parent = tooltipBar,
        })

        local tooltipLabel: TextLabel = Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontBody,
            Position = UDim2.new(0, 10, 0, 2),
            Size = UDim2.new(1, -20, 1, -2),
            Text = "Set color to: Hightlight Outline Color",
            TextColor3 = Theme.TooltipText,
            TextSize = 11,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 3,
            Parent = tooltipBar,
        })

        Util.MakeDraggable(window, header, userInputService)

        local function setTooltip(text: string)
            tooltipLabel.Text = text
        end

        return { Window = window, Body = body, SetTooltip = setTooltip }
    end

    local function createPreview(screenGui: ScreenGui, userInputService: UserInputService)
        local window: Frame = Util.Create("Frame", {
            Name = "PreviewWindow",
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(420, 80),
            Size = UDim2.fromOffset(Theme.PreviewWidth, Theme.PreviewHeight),
            ZIndex = 1,
            Parent = screenGui,
        })
        Util.Stroke(window, Color3.fromRGB(10, 10, 10), 1)

        local header: Frame = Util.Create("Frame", {
            Name = "Header",
            Active = true,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, Theme.PreviewHeaderHeight),
            ZIndex = 2,
            Parent = window,
        })

        Util.Create("Frame", {
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 3),
            ZIndex = 3,
            Parent = header,
        })

        local title: TextLabel = Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontDisplay,
            Position = UDim2.new(0, 12, 0, 8),
            Size = UDim2.new(1, -24, 0, 28),
            Text = "ESP PREVIEW",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 24,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 3,
            Parent = header,
        })
        Util.TextStroke(title, Color3.fromRGB(0, 0, 0), 3)

        Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontBody,
            Position = UDim2.new(0, 12, 0, 38),
            Size = UDim2.new(1, -24, 0, 44),
            Text = "Roblox doesnt support highlights or selection boxes in viewports so previews arent possible on those options.",
            TextColor3 = Theme.Muted,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 3,
            Parent = header,
        })

        local body: Frame = Util.Create("Frame", {
            Name = "Body",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, Theme.PreviewHeaderHeight),
            Size = UDim2.new(1, 0, 1, -Theme.PreviewHeaderHeight),
            ZIndex = 1,
            Parent = window,
        })

        Util.MakeDraggable(window, header, userInputService)
        return { Window = window, Body = body }
    end

    return { CreateMain = createMain, CreatePreview = createPreview }
end)()

-- ================= MODULE: Controls =================
local Controls = (function()
    local userInputService: UserInputService = Util.Ref(game:GetService("UserInputService"))

    local screenGuiRef: ScreenGui? = nil
    local bodyRef: Frame? = nil
    local tooltipFn: ((string) -> ())? = nil
    local rowsById: {[string]: {Row: Frame, Label: TextLabel}} = {}
    local selectedId: string? = nil
    local openPopup: Frame? = nil
    local openCatcher: TextButton? = nil

    local function setTooltip(text: string)
        if tooltipFn ~= nil then
            tooltipFn(text)
        end
    end

    local function closePopup()
        if openPopup ~= nil then
            openPopup:Destroy()
            openPopup = nil
        end
        if openCatcher ~= nil then
            openCatcher:Destroy()
            openCatcher = nil
        end
    end

    local function makeCatcher(onClose: () -> ()): TextButton?
        if screenGuiRef == nil then
            return nil
        end
        local catcher: TextButton = Util.Create("TextButton", {
            Name = "PopupCatcher",
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            ZIndex = 49,
            Parent = screenGuiRef,
        })
        catcher.MouseButton1Click:Connect(onClose)
        return catcher
    end

    local function applySelection()
        for id, entry in pairs(rowsById) do
            if id == selectedId then
                entry.Row.BackgroundColor3 = Theme.Accent
                entry.Row.BackgroundTransparency = 0
                entry.Label.TextColor3 = Theme.TextDark
            else
                entry.Row.BackgroundColor3 = Theme.Panel
                entry.Row.BackgroundTransparency = 1
                entry.Label.TextColor3 = Theme.Text
            end
        end
    end

    local function selectRow(id: string)
        selectedId = id
        applySelection()
    end

    local function addSeparator(parent: Frame, y: number, height: number)
        Util.Create("Frame", {
            BackgroundColor3 = Theme.Separator,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, y + height - 1),
            Size = UDim2.new(1, 0, 0, 1),
            ZIndex = 2,
            Parent = parent,
        })
    end

    local function baseRow(parent: Frame, y: number, id: string, labelText: string, tooltipText: string, height: number): (Frame, TextLabel)
        local row: Frame = Util.Create("Frame", {
            Name = id,
            Active = true,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, y),
            Size = UDim2.new(1, 0, 0, height),
            ZIndex = 1,
            Parent = parent,
        })
        local label: TextLabel = Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontBody,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -80, 1, 0),
            Text = labelText,
            TextColor3 = Theme.Text,
            TextSize = 14,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 2,
            Parent = row,
        })
        rowsById[id] = { Row = row, Label = label }
        row.MouseEnter:Connect(function()
            setTooltip(tooltipText)
            if selectedId ~= id then
                row.BackgroundColor3 = Theme.RowHover
                row.BackgroundTransparency = 0
            end
        end)
        row.MouseLeave:Connect(function()
            if selectedId ~= id then
                row.BackgroundTransparency = 1
            end
        end)
        row.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                selectRow(id)
            end
        end)
        addSeparator(parent, y, height)
        return row, label
    end

    local function toggle(parent: Frame, y: number, id: string, labelText: string, defaultValue: boolean): number
        local row: Frame = baseRow(parent, y, id, labelText, "Toggle: " .. labelText, Theme.RowHeight)
        local value = defaultValue
        local box: Frame = Util.Create("Frame", {
            Name = "Checkbox",
            BackgroundColor3 = Theme.CheckBg,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -28, 0.5, -9),
            Size = UDim2.fromOffset(18, 18),
            ZIndex = 3,
            Parent = row,
        })
        Util.Stroke(box, Theme.CheckBorder, 1)
        local check: TextLabel = Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontBodyBold,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "✓",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            Visible = value,
            ZIndex = 4,
            Parent = box,
        })
        local function setValue(newValue: boolean)
            value = newValue
            check.Visible = value
            State.Settings[id] = value
            State.Callbacks.onToggle(id, value)
        end
        row.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                setValue(not value)
            end
        end)
        State.Settings[id] = value
        return Theme.RowHeight
    end

    local function slider(parent: Frame, y: number, id: string, labelText: string, minimum: number, maximum: number, step: number, defaultValue: number, formatFn: (number) -> string): number
        local row: Frame = baseRow(parent, y, id, labelText, "Set slider: " .. labelText, Theme.RowHeight)
        local value = defaultValue
        local valueLabel: TextLabel = Util.Create("TextLabel", {
            Name = "Value",
            Active = true,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontBodyMedium,
            Position = UDim2.new(1, -70, 0, 0),
            Size = UDim2.fromOffset(60, Theme.RowHeight),
            Text = formatFn(value),
            TextColor3 = Theme.Text,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 3,
            Parent = row,
        })
        local function setValue(newValue: number)
            local snapped = math.floor(newValue / step + 0.5) * step
            snapped = math.clamp(snapped, minimum, maximum)
            value = snapped
            valueLabel.Text = formatFn(value)
            State.Settings[id] = value
            State.Callbacks.onSlider(id, value)
        end
        local dragging = false
        local dragStartX = 0
        local dragStartValue = value
        valueLabel.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStartX = input.Position.X
                dragStartValue = value
                input.Changed:Connect(function()
                    if input.UserState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        userInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local deltaX = input.Position.X - dragStartX
                local range = maximum - minimum
                setValue(dragStartValue + (deltaX / 60) * range)
            end
        end)
        State.Settings[id] = value
        return Theme.RowHeight
    end

    local PALETTE: {Color3} = {
        Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 0, 0),
        Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 165, 0),
        Color3.fromRGB(255, 235, 80), Color3.fromRGB(80, 255, 80),
        Color3.fromRGB(0, 200, 255), Color3.fromRGB(60, 120, 255),
        Color3.fromRGB(170, 80, 255), Color3.fromRGB(255, 0, 180),
        Color3.fromRGB(255, 105, 180), Color3.fromRGB(150, 150, 150),
    }

    local function openPalette(anchorX: number, anchorY: number, current: Color3, onPick: (Color3) -> ())
        closePopup()
        if bodyRef == nil then
            return
        end
        local catcher = makeCatcher(function()
            closePopup()
        end)
        local paletteWidth = 6 * 24 + 8
        local paletteHeight = 2 * 24 + 8
        local paletteX = math.clamp(anchorX - paletteWidth + 30, 4, Theme.MainWidth - paletteWidth - 4)
        local palette: Frame = Util.Create("Frame", {
            Name = "ColorPalette",
            BackgroundColor3 = Theme.PanelDark,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(paletteX, anchorY),
            Size = UDim2.fromOffset(paletteWidth, paletteHeight),
            ZIndex = 50,
            Parent = bodyRef,
        })
        Util.Stroke(palette, Theme.Separator, 1)
        for index, color in ipairs(PALETTE) do
            local col = (index - 1) % 6
            local rowIndex = math.floor((index - 1) / 6)
            local swatch: TextButton = Util.Create("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = color,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(4 + col * 24, 4 + rowIndex * 24),
                Size = UDim2.fromOffset(22, 22),
                Text = "",
                ZIndex = 51,
                Parent = palette,
            })
            Util.Stroke(swatch, Color3.fromRGB(10, 10, 10), 1)
            if color == current then
                Util.Stroke(swatch, Color3.fromRGB(255, 255, 255), 2)
            end
            swatch.MouseButton1Click:Connect(function()
                onPick(color)
                closePopup()
            end)
        end
        openPopup = palette
        openCatcher = catcher
    end

    local function color(parent: Frame, y: number, id: string, labelText: string, defaultValue: Color3): number
        local row: Frame = baseRow(parent, y, id, labelText, "Set color to: " .. labelText, Theme.RowHeight)
        local value = defaultValue
        local swatch: Frame = Util.Create("Frame", {
            Name = "Swatch",
            Active = true,
            BackgroundColor3 = value,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -40, 0.5, -8),
            Size = UDim2.fromOffset(30, 16),
            ZIndex = 3,
            Parent = row,
        })
        Util.Stroke(swatch, Color3.fromRGB(10, 10, 10), 1)
        local function setValue(newValue: Color3)
            value = newValue
            swatch.BackgroundColor3 = value
            State.Settings[id] = value
            State.Callbacks.onColor(id, value)
        end
        swatch.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                selectRow(id)
                openPalette(Theme.MainWidth - 40, y + Theme.RowHeight + 4, value, setValue)
            end
        end)
        State.Settings[id] = value
        return Theme.RowHeight
    end

    local function dropdown(parent: Frame, y: number, id: string, options: {string}, defaultValue: string, tooltipText: string): number
        local row: Frame, label: TextLabel = baseRow(parent, y, id, defaultValue, tooltipText, Theme.RowHeight)
        local current = defaultValue
        local chevron: Frame = Util.Create("Frame", {
            Name = "Chevron",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -26, 0.5, -7),
            Size = UDim2.fromOffset(16, 14),
            ZIndex = 3,
            Parent = row,
        })
        local bar1: Frame = Util.Create("Frame", {
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 1, 0.5, -1),
            Rotation = 45,
            Size = UDim2.fromOffset(9, 2),
            ZIndex = 4,
            Parent = chevron,
        })
        local bar2: Frame = Util.Create("Frame", {
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 7, 0.5, -1),
            Rotation = -45,
            Size = UDim2.fromOffset(9, 2),
            ZIndex = 4,
            Parent = chevron,
        })
        local function setChevron(open: boolean)
            bar1.Rotation = open and -45 or 45
            bar2.Rotation = open and 45 or -45
        end
        local list: Frame? = nil
        local function closeList()
            if list ~= nil then
                list:Destroy()
                list = nil
            end
            setChevron(false)
        end
        local function openList()
            closePopup()
            if bodyRef == nil then
                return
            end
            local catcher = makeCatcher(function()
                closePopup()
                closeList()
            end)
            local listFrame: Frame = Util.Create("Frame", {
                Name = "DropdownList",
                BackgroundColor3 = Theme.PanelDark,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(10, y + Theme.RowHeight),
                Size = UDim2.new(1, -20, 0, #options * 26),
                ZIndex = 50,
                Parent = bodyRef,
            })
            Util.Stroke(listFrame, Theme.Separator, 1)
            for index, option in ipairs(options) do
                local optionButton: TextButton = Util.Create("TextButton", {
                    AutoButtonColor = false,
                    BackgroundColor3 = Theme.PanelDark,
                    BorderSizePixel = 0,
                    Font = Theme.FontBody,
                    Position = UDim2.new(0, 0, 0, (index - 1) * 26),
                    Size = UDim2.new(1, 0, 0, 26),
                    Text = option,
                    TextColor3 = option == current and Theme.Accent or Theme.Text,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 51,
                    Parent = listFrame,
                })
                Util.Create("UIPadding", {
                    PaddingLeft = UDim.new(0, 10),
                    Parent = optionButton,
                })
                optionButton.MouseEnter:Connect(function()
                    optionButton.BackgroundColor3 = Theme.RowHover
                end)
                optionButton.MouseLeave:Connect(function()
                    optionButton.BackgroundColor3 = Theme.PanelDark
                end)
                optionButton.MouseButton1Click:Connect(function()
                    current = option
                    label.Text = option
                    State.Settings[id] = option
                    State.Callbacks.onVersion(option)
                    closePopup()
                    closeList()
                end)
            end
            list = listFrame
            openPopup = listFrame
            openCatcher = catcher
            setChevron(true)
        end
        row.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if list ~= nil then
                    closePopup()
                    closeList()
                else
                    openList()
                end
            end
        end)
        State.Settings[id] = current
        return Theme.RowHeight
    end

    local function sectionHeader(parent: Frame, y: number, text: string): number
        local container: Frame = Util.Create("Frame", {
            Name = "Section_" .. text,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, y),
            Size = UDim2.new(1, 0, 0, Theme.SectionHeight),
            ZIndex = 1,
            Parent = parent,
        })
        local label: TextLabel = Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontDisplay,
            Size = UDim2.new(1, 0, 0, 26),
            Text = text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 20,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 2,
            Parent = container,
        })
        Util.TextStroke(label, Color3.fromRGB(0, 0, 0), 3)
        Util.Create("Frame", {
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Position = UDim2.new(0.5, -45, 0, 28),
            Size = UDim2.fromOffset(90, 3),
            ZIndex = 2,
            Parent = container,
        })
        return Theme.SectionHeight
    end

    local function metaRow(parent: Frame, y: number, leftText: string, rightText: string): number
        local container: Frame = Util.Create("Frame", {
            Name = "MetaRow",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, y),
            Size = UDim2.new(1, 0, 0, Theme.MetaHeight),
            ZIndex = 1,
            Parent = parent,
        })
        Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontBody,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(0.6, 0, 1, 0),
            Text = leftText,
            TextColor3 = Theme.Muted,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 2,
            Parent = container,
        })
        Util.Create("TextLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Theme.FontBody,
            Position = UDim2.new(0.6, 0, 0, 0),
            Size = UDim2.new(0.4, -10, 1, 0),
            Text = rightText,
            TextColor3 = Theme.Muted,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = 2,
            Parent = container,
        })
        addSeparator(parent, y, Theme.MetaHeight)
        return Theme.MetaHeight
    end

    local function bind(screenGui: ScreenGui, body: Frame, tooltip: (string) -> ())
        screenGuiRef = screenGui
        bodyRef = body
        tooltipFn = tooltip
    end

    local function selectById(id: string)
        if rowsById[id] ~= nil then
            selectRow(id)
        end
    end

    return {
        Bind = bind,
        SelectById = selectById,
        MetaRow = metaRow,
        Toggle = toggle,
        Slider = slider,
        Color = color,
        Dropdown = dropdown,
        SectionHeader = sectionHeader,
    }
end)()

-- ================= MODULE: Preview =================
local Preview = (function()
    local function part(parent: Frame, x: number, y: number, w: number, h: number, color: Color3, transparency: number): Frame
        return Util.Create("Frame", {
            BackgroundColor3 = color,
            BackgroundTransparency = transparency,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(w, h),
            ZIndex = 3,
            Parent = parent,
        })
    end

    local function build(parent: Frame)
        local viewportW, viewportH = 150, 190
        local bodyW = Theme.PreviewWidth
        local bodyH = Theme.PreviewHeight - Theme.PreviewHeaderHeight
        local vx = math.floor((bodyW - viewportW) / 2)
        local vy = math.floor((bodyH - viewportH) / 2)

        Util.Create("Frame", {
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.78,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(vx - 4, vy - 4),
            Size = UDim2.fromOffset(viewportW + 8, viewportH + 8),
            ZIndex = 1,
            Parent = parent,
        })

        local viewport: Frame = Util.Create("Frame", {
            Name = "Viewport",
            BackgroundColor3 = Theme.PreviewBg,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(vx, vy),
            Size = UDim2.fromOffset(viewportW, viewportH),
            ZIndex = 2,
            Parent = parent,
        })
        Util.Stroke(viewport, Theme.Accent, 2)
        Util.Create("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.PreviewBg),
                ColorSequenceKeypoint.new(1, Theme.PreviewBg2),
            }),
            Rotation = 90,
            Parent = viewport,
        })

        local cx = 75
        part(viewport, cx - 15, 16, 30, 30, Theme.Avatar, 0.05)
        part(viewport, cx - 23, 50, 46, 54, Theme.Avatar, 0.05)
        part(viewport, cx - 39, 52, 12, 50, Theme.Avatar, 0.05)
        part(viewport, cx + 27, 52, 12, 50, Theme.Avatar, 0.05)
        part(viewport, cx - 21, 108, 18, 54, Theme.Avatar, 0.05)
        part(viewport, cx + 3, 108, 18, 54, Theme.Avatar, 0.05)

        part(viewport, cx - 1, 28, 2, 134, Theme.Skeleton, 0.1)
        part(viewport, cx - 7, 50, 14, 2, Theme.Skeleton, 0.1)
        part(viewport, cx - 7, 104, 14, 2, Theme.Skeleton, 0.1)
        part(viewport, cx - 7, 132, 14, 2, Theme.Skeleton, 0.1)

        local barOuter: Frame = Util.Create("Frame", {
            Name = "HealthBar",
            BackgroundColor3 = Color3.fromRGB(15, 15, 15),
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(cx - 52, 50),
            Size = UDim2.fromOffset(8, 112),
            ZIndex = 4,
            Parent = viewport,
        })
        Util.Stroke(barOuter, Color3.fromRGB(220, 220, 220), 1)
        local barFill: Frame = Util.Create("Frame", {
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(1, 1),
            Size = UDim2.new(1, -2, 1, -2),
            ZIndex = 5,
            Parent = barOuter,
        })
        Util.Create("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 255, 80)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 235, 80)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 60)),
            }),
            Rotation = 90,
            Parent = barFill,
        })

        -- STUB: preview sync hook (intentionally empty — no feature logic).
        local function sync()
        end

        return { Viewport = viewport, Sync = sync }
    end

    return { Build = build }
end)()

-- ================= MODULE: Navigation =================
local Navigation = (function()
    local Tabs = { "VISUALS / HUD" }
    local current = Tabs[1]

    local function setTab(tab: string)
        current = tab
        State.Callbacks.onTab(tab)
    end

    local function getCurrent(): string
        return current
    end

    return { Tabs = Tabs, SetTab = setTab, GetCurrent = getCurrent }
end)()

-- ================= MODULE: Main =================
local Main = (function()
    local function init()
        local players = Util.Ref(game:GetService("Players"))
        local userInputService = Util.Ref(game:GetService("UserInputService"))
        local localPlayer = players.LocalPlayer
        local playerGui = localPlayer:WaitForChild("PlayerGui")

        Util.DestroyExisting("ViolentGui", playerGui)

        local screenGui: ScreenGui = Util.Create("ScreenGui", {
            Name = "ViolentGui",
            DisplayOrder = 999999,
            Enabled = true,
            IgnoreGuiInset = true,
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Global,
        })
        Util.ParentScreenGui(screenGui, playerGui)

        local main = Window.CreateMain(screenGui, userInputService)
        local previewWindow = Window.CreatePreview(screenGui, userInputService)

        Controls.Bind(screenGui, main.Body, main.SetTooltip)

        local y = 0
        y = y + Controls.MetaRow(main.Body, y, Navigation.GetCurrent(), "29/51")
        y = y + Controls.Toggle(main.Body, y, "EnableSkeleton", "Enable Skeleton", true)
        y = y + Controls.Slider(main.Body, y, "SkeletonThickness", "Skeleton Thickness", 1, 10, 1, 1, function(v: number)
            return string.format("%d", v)
        end)
        y = y + Controls.Color(main.Body, y, "SkeletonColor", "Skeleton Color", Color3.fromRGB(255, 255, 255))
        y = y + Controls.SectionHeader(main.Body, y, "Highlights")
        y = y + Controls.Toggle(main.Body, y, "HighlightESP", "Hightlight ESP", true)
        y = y + Controls.Toggle(main.Body, y, "HighlightFill", "Hightlight Fill", true)
        y = y + Controls.Toggle(main.Body, y, "HighlightOutline", "Hightlight Outline", true)
        y = y + Controls.Color(main.Body, y, "HighlightFillColor", "Hightlight Fill Color", Color3.fromRGB(255, 0, 180))
        y = y + Controls.Color(main.Body, y, "HighlightOutlineColor", "Hightlight Outline Color", Color3.fromRGB(255, 105, 180))
        y = y + Controls.SectionHeader(main.Body, y, "Health Bar")
        y = y + Controls.Toggle(main.Body, y, "ShowHealthBar", "Show Health Bar", true)
        y = y + Controls.Slider(main.Body, y, "HealthBarSize", "Healt Bar Size", 1, 5, 0.5, 2.5, function(v: number)
            return string.format("%.1f", v)
        end)
        y = y + Controls.SectionHeader(main.Body, y, "Text")
        y = y + Controls.Dropdown(main.Body, y, "Version", { "Release, v1.4", "Beta, v1.3", "Legacy, v1.2" }, "Release, v1.4", "Select version")

        Controls.SelectById("HighlightOutlineColor")

        local preview = Preview.Build(previewWindow.Body)
        preview.Sync()

        userInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
            if processed then
                return
            end
            if input.KeyCode == Enum.KeyCode.RightShift then
                screenGui.Enabled = not screenGui.Enabled
            end
        end)

        local globalEnv: any = nil
        local getgenvFn = Util.Env.getgenv
        if type(getgenvFn) == "function" then
            local ok, result = pcall(getgenvFn)
            if ok then
                globalEnv = result
            end
        end
        if globalEnv == nil then
            globalEnv = _G
        end
        globalEnv.Violent = {
            Settings = State.Settings,
            Callbacks = State.Callbacks,
            ScreenGui = screenGui,
        }
    end

    return { Init = init }
end)()

Main.Init()
