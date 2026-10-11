local Module = {
    Name = "Furniture",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local WURSTLOGO_BACKGROUND: Color3 = Color3.fromRGB(255, 255, 255)
local WURSTLOGO_TEXT: Color3 = Color3.fromRGB(0, 0, 0)

local FURNITURE_MARGIN_X: number = 14
local FURNITURE_MARGIN_Y: number = 10

local LOGO_HEIGHT: number = 36
local LOGO_WIDTH: number = 142

local HACKLIST_MODE: string = "Auto"
local HACKLIST_POSITION: string = "Left"
local HACKLIST_COLOR: Color3 = Color3.fromRGB(255, 255, 255)
local HACKLIST_SORT_BY: string = "Name"
local HACKLIST_REVERSE: boolean = false
local HACKLIST_ANIMATIONS: boolean = true

local HACKLIST_FONT_SIZE: number = 16
local HACKLIST_LINE_HEIGHT: number = 18
local HACKLIST_TOP: number = 56

local HACKLIST_SLIDE: number = 24

local WURSTLOGO_VISIBILITY: string = "Always"

local PILL_BUTTON: number = 32
local PILL_PADDING_X: number = 7
local PILL_PADDING_Y: number = 5
local PILL_GAP: number = 2
local TOOLTIP_DELAY_MS: number = 400

function Module.init(context: any): any
    local host: any = context
    local state: any = host.state
    local create: any = host.create
    local PRODUCT: any = host.PRODUCT
    local Theme: any = host.Theme
    local ThemeEngine: any = host.ThemeEngine
    local TaskManager: any = host.TaskManager
    local PopupLayer: any = host.PopupLayer
    local TITLE_FONT: any = host.TITLE_FONT
    local CONTROL_FONT: any = host.CONTROL_FONT
    local TweenService: any = host.TweenService
    local allFeatures: {any} = host.allFeatures
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local UserInputService: any = host.UserInputService
    local colorFromConfig: any = host.colorFromConfig
    local ScreenGui: any = host.ScreenGui
    local makeTextBox: any = host.makeTextBox
    local notify: any = host.notify or function(_message: any): () end

    local Furniture: any = {
        handles = {} :: {any},
        connections = {} :: {RBXScriptConnection},
    }

    for _, ghostName: string in ipairs({
        "WurstLogo",
        "HackList",
        "Navigator",
        "Pill",
    }) do
        local ghost: Instance? = PopupLayer:FindFirstChild(ghostName)
        while ghost do
            ghost:Destroy()
            ghost = PopupLayer:FindFirstChild(ghostName)
        end

        if ScreenGui then
            local screenGhost: Instance? = ScreenGui:FindFirstChild(ghostName)
            while screenGhost do
                screenGhost:Destroy()
                screenGhost = ScreenGui:FindFirstChild(ghostName)
            end
        end
    end

    local versionText: string = tostring(PRODUCT.version)
    local versionWidth: number = 8 + #versionText * 15
    local chipWidth: number = LOGO_WIDTH + 10 + versionWidth + 4
    local chip: Frame = (create("Frame", {
        Parent = PopupLayer,
        Name = "WurstLogo",
        Active = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(FURNITURE_MARGIN_X, FURNITURE_MARGIN_Y),
        Size = UDim2.fromOffset(chipWidth, LOGO_HEIGHT + 8),
        ZIndex = 20,
    }) :: any) :: Frame

    local logoStripe: Frame = (create("Frame", {
        Parent = chip,
        Name = "BackgroundStripe",
        BackgroundColor3 = WURSTLOGO_BACKGROUND,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 12),
        Size = UDim2.fromOffset(chipWidth, 22),
        ZIndex = 20,
    }) :: any) :: Frame

    local logoImage: ImageLabel = (create("ImageLabel", {
        Parent = chip,
        Name = "Logo",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        Position = UDim2.fromOffset(4, 4),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.fromOffset(LOGO_WIDTH, LOGO_HEIGHT),
        Visible = false,
        ZIndex = 21,
    }) :: any) :: ImageLabel

    local logoFallback: TextLabel = (create("TextLabel", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = chip,
        Name = "LogoFallback",
        BackgroundTransparency = 1,
        FontFace = TITLE_FONT,
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(LOGO_WIDTH, LOGO_HEIGHT),
        Text = string.upper(tostring(PRODUCT.name)),
        TextColor3 = WURSTLOGO_TEXT,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 21,
    }) :: any) :: TextLabel

    local versionChip: Frame = (create("Frame", {
        Parent = chip,
        Name = "VersionChip",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(LOGO_WIDTH + 10, 12),
        Size = UDim2.fromOffset(versionWidth, 22),
        ZIndex = 20,
    }) :: any) :: Frame

    local bitmapText: any = state.bitmapText
    local drawsVersion: boolean = bitmapText ~= nil
        and type(bitmapText.draw) == "function"
    local versionColor: Color3 = WURSTLOGO_TEXT
    local versionLabel: TextLabel? = nil
    local function drawVersion(): ()
        if drawsVersion then
            bitmapText.draw(versionChip, {
                {text = versionText, color = versionColor},
            }, {
                Name = "Version",
                TextSize = 20,
                ZIndex = 21,
                align = "Left",
            })
        end
    end
    if drawsVersion then
        drawVersion()
    else
        versionLabel = (create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = versionChip,
            Name = "Version",
            BackgroundTransparency = 1,
            FontFace = TITLE_FONT,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(1, 1),
            Text = versionText,
            TextColor3 = WURSTLOGO_TEXT,
            TextSize = 20,
            TextXAlignment = Enum.TextXAlignment.Left,
        }) :: any) :: TextLabel
    end

    local function fitLogoBand(): ()
        local measured: number = 0
        if drawsVersion and type(bitmapText.measure) == "function" then

            measured = tonumber(bitmapText.measure(
                {{text = versionText}}, 20
            )) or 0
        elseif versionLabel then
            local bounds: any = (versionLabel :: any).TextBounds
            measured = bounds and tonumber(bounds.X) or 0
        end
        if measured <= 0 then
            return
        end
        local fittedVersion: number = 8 + measured
        local fittedChip: number = LOGO_WIDTH + 10 + fittedVersion + 4
        versionChip.Size = UDim2.fromOffset(fittedVersion, 22)
        chip.Size = UDim2.fromOffset(fittedChip, LOGO_HEIGHT + 8)
        logoStripe.Size = UDim2.fromOffset(fittedChip, 22)
    end
    if versionLabel then
        table.insert(
            Furniture.connections,
            (versionLabel :: TextLabel):GetPropertyChangedSignal("TextBounds")
                :Connect(fitLogoBand)
        )
    end
    if drawsVersion and type(bitmapText.onReady) == "table" then

        table.insert(bitmapText.onReady, fitLogoBand)
    end
    task.defer(fitLogoBand)

    if type(state.applyAssetImage) == "function" then
        state.applyAssetImage("wurstLogo", logoImage, function(): ()
            logoImage.Visible = true
            logoFallback.Visible = false
        end)
    end

    local logoAlways: boolean = true
    local function refreshLogoVisibility(): ()

        chip.Visible = logoAlways and state.visible == true
    end
    local function setLogoBackground(color: Color3): ()
        logoStripe.BackgroundColor3 = color
    end
    local function setLogoTextColor(color: Color3): ()
        versionColor = color
        if drawsVersion then
            drawVersion()
        elseif versionLabel then
            (versionLabel :: TextLabel).TextColor3 = color
        end
        logoFallback.TextColor3 = color
    end
    local function setLogoVisibility(value: string): ()
        logoAlways = value == "Always"
        refreshLogoVisibility()
    end
    setLogoBackground(colorFromConfig(
        configData.values["WurstLogo.Background"],
        WURSTLOGO_BACKGROUND
    ))
    setLogoTextColor(colorFromConfig(
        configData.values["WurstLogo.Text"],
        WURSTLOGO_TEXT
    ))
    local storedLogoVisibility: any = configData.values["WurstLogo.Visibility"]
    setLogoVisibility(type(storedLogoVisibility) == "string"
        and storedLogoVisibility
        or WURSTLOGO_VISIBILITY)

    state.wurstLogo = {
        root = chip,
        SetBackground = setLogoBackground,
        SetTextColor = setLogoTextColor,
        SetVisibility = setLogoVisibility,
    }

    local hudFrame: Frame = (create("Frame", {
        Parent = PopupLayer,
        Name = "HackList",
        Active = false,
        AnchorPoint = Vector2.new(1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -12, 0, HACKLIST_TOP),
        Size = UDim2.new(0, 260, 1, -(HACKLIST_TOP + 12)),
        ZIndex = 20,
    }) :: any) :: Frame

    local hudLayout: UIListLayout = (create("UIListLayout", {
        Parent = hudFrame,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 1),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }) :: any) :: UIListLayout

    local hudMode: string = type(configData.values["HackList.Mode"]) == "string"
        and configData.values["HackList.Mode"]
        or HACKLIST_MODE
    local hudPosition: string = type(configData.values["HackList.Position"]) == "string"
        and configData.values["HackList.Position"]
        or HACKLIST_POSITION
    local hudColor: Color3 = colorFromConfig(
        configData.values["HackList.Color"],
        HACKLIST_COLOR
    )
    local hudSortBy: string = type(configData.values["HackList.Sortby"]) == "string"
        and configData.values["HackList.Sortby"]
        or HACKLIST_SORT_BY
    local hudReverse: boolean = HACKLIST_REVERSE
    if configData.states["HackList.Reversesorting"] ~= nil then
        hudReverse = configData.states["HackList.Reversesorting"] == true
    end
    local hudAnimations: boolean = HACKLIST_ANIMATIONS
    if configData.states["HackList.Animations"] ~= nil then
        hudAnimations = configData.states["HackList.Animations"] == true
    end
    local hudSize: string = type(configData.values["HackList.Size"]) == "string"
        and configData.values["HackList.Size"]
        or "Normal"
    local hudRainbow: boolean = configData.states["HackList.Rainbow"] == true
    local HUD_SIZES: {[string]: {font: number, line: number}} = {
        Small = {font = 12, line = 14},
        Normal = {font = HACKLIST_FONT_SIZE, line = HACKLIST_LINE_HEIGHT},
        Large = {font = 20, line = 23},
    }
    local function hudMetrics(): {font: number, line: number}
        return HUD_SIZES[hudSize] or HUD_SIZES.Normal
    end

    local function hudOnLeft(): boolean

        return hudPosition == "Left" or hudPosition == "Custom"
    end

    local navigatorBottom: () -> number = function(): number
        return FURNITURE_MARGIN_Y + LOGO_HEIGHT + 8
    end
    local hudCustomX: number? = tonumber(configData.values["HackList.CustomX"])
    local hudCustomY: number? = tonumber(configData.values["HackList.CustomY"])

    local function logicalViewport(): Vector2
        local windows: any = state.windows
        if windows and type(windows.LogicalViewport) == "function" then
            local ok: boolean, viewport: any = pcall(windows.LogicalViewport)
            if ok and viewport then
                return viewport
            end
        end
        local raw: Vector2 = ScreenGui and ScreenGui.AbsoluteSize
            or Vector2.new(1280, 720)
        return raw
    end

    local function clampHudCustom(x: number, y: number): (number, number)
        local viewport: Vector2 = logicalViewport()
        return math.clamp(x, 0, math.max(viewport.X - 260, 0)),
            math.clamp(y, 0, math.max(viewport.Y - 32, 0))
    end

    local function placeHudList(): ()
        if hudPosition == "Custom" then
            local x: number = hudCustomX or FURNITURE_MARGIN_X
            local y: number = hudCustomY or navigatorBottom()
            x, y = clampHudCustom(x, y)
            hudCustomX, hudCustomY = x, y
            hudFrame.AnchorPoint = Vector2.new(0, 0)
            hudFrame.Position = UDim2.fromOffset(x, y)
            hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        elseif hudOnLeft() then
            hudFrame.AnchorPoint = Vector2.new(0, 0)
            hudFrame.Position = UDim2.new(
                0,
                FURNITURE_MARGIN_X,
                0,
                navigatorBottom()
            )
            hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        else

            local windows: any = state.windows
            local logicalWidth: number? = nil
            if windows and type(windows.LogicalViewport) == "function" then
                local ok: boolean, logical: any = pcall(windows.LogicalViewport)
                if ok and logical then
                    logicalWidth = logical.X
                end
            end
            hudFrame.AnchorPoint = Vector2.new(1, 0)
            if logicalWidth then
                hudFrame.Position = UDim2.new(0, logicalWidth - 12, 0, HACKLIST_TOP)
            else
                hudFrame.Position = UDim2.new(1, -12, 0, HACKLIST_TOP)
            end
            hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        end
    end
    placeHudList()
    state.onLayout(placeHudList)

    local hudRows: {[string]: any} = {}

    local hudDragInput: InputObject? = nil
    local hudDragStart: Vector2 = Vector2.zero
    local hudDragOrigin: Vector2 = Vector2.zero
    local function hudHitTest(point: Vector2): boolean
        if hudPosition ~= "Custom" or state.visible ~= true then
            return false
        end
        for _, row: any in pairs(hudRows) do
            local target: GuiObject? = row.holder or row.container
            if target and target.Parent and target.Visible then
                local at: Vector2 = target.AbsolutePosition
                local size: Vector2 = target.AbsoluteSize
                if size.X > 0 and size.Y > 0
                    and point.X >= at.X and point.X <= at.X + size.X
                    and point.Y >= at.Y and point.Y <= at.Y + size.Y then
                    return true
                end
            end
        end
        return false
    end
    state.surfaceDragHitTest = hudHitTest
    hudFrame.Active = false
    hudFrame.ZIndex = 20

    table.insert(Furniture.connections, UserInputService.InputBegan:Connect(function(
        input: InputObject
    ): ()
        if state.surfaceDragOwner ~= nil
            or (input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch)
            or not hudHitTest(Vector2.new(input.Position.X, input.Position.Y)) then
            return
        end
        hudDragInput = input
        state.surfaceDragOwner = hudFrame
        hudDragStart = Vector2.new(input.Position.X, input.Position.Y)
        hudDragOrigin = Vector2.new(
            hudFrame.Position.X.Offset,
            hudFrame.Position.Y.Offset
        )
    end))
    table.insert(Furniture.connections, UserInputService.InputChanged:Connect(function(
        input: InputObject
    ): ()
        if not hudDragInput
            or (input ~= hudDragInput
                and not (hudDragInput.UserInputType == Enum.UserInputType.MouseButton1
                    and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            return
        end
        local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
        local delta: Vector2 = pointer - hudDragStart
        local windows: any = state.windows
        if windows and type(windows.ScreenToLogical) == "function" then
            delta = windows.ScreenToLogical(delta)
        end
        local x: number, y: number = clampHudCustom(
            hudDragOrigin.X + delta.X,
            hudDragOrigin.Y + delta.Y
        )
        hudCustomX, hudCustomY = x, y
        hudFrame.Position = UDim2.fromOffset(x, y)
    end))
    table.insert(Furniture.connections, UserInputService.InputEnded:Connect(function(
        input: InputObject
    ): ()
        if not hudDragInput
            or (input ~= hudDragInput
                and input.UserInputType ~= Enum.UserInputType.MouseButton1) then
            return
        end
        hudDragInput = nil
        if state.surfaceDragOwner == hudFrame then
            state.surfaceDragOwner = nil
        end
        if hudCustomX and hudCustomY then
            configData.values["HackList.CustomX"] = hudCustomX
            configData.values["HackList.CustomY"] = hudCustomY
            queueConfigSave()
        end
    end))

    local function animationsOn(): boolean
        return hudAnimations and state.animationsEnabled ~= false
    end

    local hudRainbowClock: number = 0
    local function hudEntryColor(order: number?): Color3

        if hudRainbow then
            local hue: number = (hudRainbowClock * 0.35 + (order or 0) * 0.05) % 1
            return Color3.fromHSV(hue, 0.85, 1)
        end
        if animationsOn() then
            local wave: number = 0.5 + 0.5 * math.sin(
                hudRainbowClock * 2.4 - (order or 0) * 0.65
            )
            local brightness: number = 0.45 + 0.55 * wave
            return Color3.new(
                hudColor.R * brightness,
                hudColor.G * brightness,
                hudColor.B * brightness
            )
        end
        return hudColor
    end
    local function drawHudEntry(row: any, name: string, status: string?): ()
        row.name = name
        row.status = status
        local segments: {any} = {{text = name, color = hudEntryColor(row.order)}}
        if status and status ~= "" then
            table.insert(segments, {
                text = " [" .. tostring(status) .. "]",
                color = Theme.textMuted,
            })
        end
        local bitmapText: any = state.bitmapText
        if bitmapText and type(bitmapText.draw) == "function" then
            row.holder = bitmapText.draw(row.container, segments, {
                Name = "Entry",
                TextSize = hudMetrics().font,
                ZIndex = 20,
                align = hudOnLeft() and "Left" or "Right",
            })
        end
    end

    local function newHudRow(name: string): any
        local container: Frame = (create("Frame", {
            Parent = hudFrame,
            Name = name,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, hudMetrics().line),
            ZIndex = 20,
        }) :: any) :: Frame
        return {container = container}
    end

    local function slideHudRow(row: any): ()
        if not animationsOn() or not row.holder then
            return
        end
        local holder: Frame = row.holder :: Frame
        local resting: UDim2 = holder.Position

        holder.Position = UDim2.new(
            resting.X.Scale,
            resting.X.Offset + HACKLIST_SLIDE,
            resting.Y.Scale,
            resting.Y.Offset
        )
        TweenService:Create(
            holder,
            TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Position = resting}
        ):Play()
    end

    local function dropHudRow(row: any): ()
        if animationsOn() and row.holder then
            local holder: Frame = row.holder :: Frame
            local slid: UDim2 = UDim2.new(
                holder.Position.X.Scale,
                holder.Position.X.Offset + HACKLIST_SLIDE,
                holder.Position.Y.Scale,
                holder.Position.Y.Offset
            )
            local tween: Tween = TweenService:Create(
                holder,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {Position = slid}
            )
            tween.Completed:Connect(function(): ()
                row.container:Destroy()
            end)
            tween:Play()
        else
            row.container:Destroy()
        end
    end

    local hudSignature: string = ""
    local hudElapsed: number = 0

    -- By default the hack list is only visible while the menu is open; the
    -- "Show" toggle in the HackList window keeps it on screen permanently.
    local hudAlways: boolean = configData.states["HackList.Show"] == true
        or configData.states["ClickGUI.ShowHackList"] == true
    local hudVisible: boolean = hudAlways or state.visible == true

    local function refreshHudList(): ()
        if not hudVisible then
            return
        end
        local entries: {any} = {}
        for _, feature: any in ipairs(allFeatures) do
            if feature.enabled == true and not feature.isCategory then
                table.insert(entries, {
                    name = tostring(feature.name),
                    status = feature.status,
                })
            end
        end

        local function before(left: any, right: any): boolean
            if hudSortBy == "Width" then
                local leftWidth: number = #left.name
                    + (left.status and #tostring(left.status) + 3 or 0)
                local rightWidth: number = #right.name
                    + (right.status and #tostring(right.status) + 3 or 0)
                if leftWidth ~= rightWidth then
                    return leftWidth > rightWidth
                end
            end
            return left.name < right.name
        end
        table.sort(entries, function(left: any, right: any): boolean
            if hudReverse then
                return before(right, left)
            end
            return before(left, right)
        end)

        if hudMode == "Hidden" then
            entries = {}
        elseif #entries > 0 then

            local screenHeight: number
            local manager: any = state.windows
            if manager and type(manager.LogicalViewport) == "function" then
                screenHeight = manager.LogicalViewport().Y
            else
                local camera: Camera? = workspace.CurrentCamera
                screenHeight = camera
                    and (camera :: Camera).ViewportSize.Y
                    or 720
            end
            local available: number = screenHeight - HACKLIST_TOP - 12
            local overflows: boolean =
                #entries * (hudMetrics().line + 1) > available
            if hudMode == "Count" or (hudMode == "Auto" and overflows) then
                entries = {{
                    name = tostring(#entries) .. " hacks active",
                    status = nil,
                }}
            end
        end

        local signature: {string} = {}
        for _, entry: any in ipairs(entries) do
            table.insert(
                signature,
                entry.name .. "\1" .. tostring(entry.status or "")
            )
        end
        local composed: string = table.concat(signature, "\2")
            .. (hudOnLeft() and "\3left" or "\3right")
        if composed == hudSignature then
            return
        end
        hudSignature = composed

        local wanted: {[string]: boolean} = {}
        for order: number, entry: any in ipairs(entries) do
            wanted[entry.name] = true
            local row: any = hudRows[entry.name]
            local isNew: boolean = row == nil
            if not row then
                row = newHudRow(entry.name)
                hudRows[entry.name] = row
            end
            row.container.LayoutOrder = order
            row.order = order
            drawHudEntry(row, entry.name, entry.status)
            if isNew then
                slideHudRow(row)
            end
        end
        for name: string, row: any in pairs(hudRows) do
            if not wanted[name] then
                hudRows[name] = nil
                dropHudRow(row)
            end
        end
    end

    local hudRainbowSince: number = 0
    table.insert(Furniture.handles, TaskManager:Connect(function(
        deltaTime: number
    ): ()

        if hudVisible and (hudRainbow or animationsOn()) then
            hudRainbowClock += deltaTime
            hudRainbowSince += deltaTime
            if hudRainbowSince >= 0.033 then
                hudRainbowSince = 0
                for _, row: any in pairs(hudRows) do
                    if row.name then
                        drawHudEntry(row, row.name, row.status)
                    end
                end
            end
        end
        hudElapsed += deltaTime
        if hudElapsed < 0.25 then
            return
        end
        hudElapsed = 0
        refreshHudList()
    end))
    refreshHudList()

    local function forceHudRefresh(): ()
        hudSignature = "\0stale"
        refreshHudList()
    end

    if state.bitmapText and type(state.bitmapText.onReady) == "table" then
        table.insert(state.bitmapText.onReady, forceHudRefresh)
    end

    hudFrame.Visible = hudVisible
    local function setHackListVisible(value: boolean): ()
        hudVisible = value ~= false
        hudFrame.Visible = hudVisible
        if hudVisible then
            forceHudRefresh()

            for _, row: any in pairs(hudRows) do
                slideHudRow(row)
            end
        end
    end
    Furniture.SetHackListVisible = setHackListVisible

    local function applyHudVisibility(): ()
        setHackListVisible(hudAlways or state.visible == true)
    end
    if type(state.addMenuVisibilityListener) == "function" then
        state.addMenuVisibilityListener(function(visible: boolean): ()
            if not hudAlways then
                setHackListVisible(visible == true)
            end
        end)
    end

    state.hudList = {
        frame = hudFrame,
        refresh = refreshHudList,
        SetVisible = setHackListVisible,
        SetAlways = function(value: boolean): ()
            hudAlways = value == true
            applyHudVisibility()
        end,

        SetMode = function(value: string): ()
            hudMode = value
            forceHudRefresh()
        end,
        SetPosition = function(value: string): ()
            hudPosition = value
            placeHudList()
            if value == "Custom" then
                notify("Drag the HackList while the menu is open")
            end
            forceHudRefresh()
        end,
        SetColor = function(color: Color3): ()

            hudColor = color
            forceHudRefresh()
        end,
        SetSortBy = function(value: string): ()
            hudSortBy = value
            forceHudRefresh()
        end,
        SetReverse = function(value: boolean): ()
            hudReverse = value
            forceHudRefresh()
        end,
        SetAnimations = function(value: boolean): ()
            hudAnimations = value
            forceHudRefresh()
        end,
        SetSize = function(value: string): ()
            hudSize = value
            for _, row: any in pairs(hudRows) do
                row.container.Size = UDim2.new(1, 0, 0, hudMetrics().line)
            end
            forceHudRefresh()
        end,
        SetRainbow = function(value: boolean): ()
            hudRainbow = value == true
            if not hudRainbow then
                forceHudRefresh()
            end
        end,
    }

    local NAV_COLUMNS: number = 3
    local NAV_CELL_WIDTH: number = 150
    local NAV_CELL_HEIGHT: number = 22
    local NAV_CELL_GAP: number = 3
    local NAV_WIDTH: number = NAV_COLUMNS * NAV_CELL_WIDTH
        + (NAV_COLUMNS - 1) * NAV_CELL_GAP

    local navScreen: Frame = (create("Frame", {

        Parent = ScreenGui or PopupLayer,
        Name = "Navigator",

        Active = false,
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),

        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 246,
    }) :: any) :: Frame

    do
        local bitmap: any = state.bitmapText
        if bitmap and type(bitmap.adoptTree) == "function" then
            table.insert(Furniture.connections, bitmap.adoptTree(navScreen))
        end
    end

    local navColumn: Frame = (create("Frame", {
        Parent = navScreen,
        Name = "Column",
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0, 48),
        Size = UDim2.fromOffset(NAV_WIDTH, 32),
        ZIndex = 247,
    }) :: any) :: Frame
    local navStroke: UIStroke = (create("UIStroke", {
        Parent = navColumn,
        Name = "NavigatorStroke",
        Color = Theme.outline,
        Thickness = 1,
        Transparency = 0.35,
    }) :: any) :: UIStroke

    local navSearch: TextBox = (create("TextBox", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = navColumn,
        Name = "Search",
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        FontFace = CONTROL_FONT,
        PlaceholderText = "Search…",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 32),
        Text = "",
        TextColor3 = Theme.text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 248,
    }) :: any) :: TextBox
    create("UIPadding", {
        Parent = navSearch,
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
    })

    local navResults: ScrollingFrame = (create("ScrollingFrame", {
        Parent = navColumn,
        Name = "Results",
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Position = UDim2.fromOffset(0, 38),
        ScrollBarThickness = 3,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Size = UDim2.new(1, 0, 1, -38),
        ZIndex = 247,
    }) :: any) :: ScrollingFrame
    create("UIGridLayout", {
        Parent = navResults,
        CellPadding = UDim2.fromOffset(NAV_CELL_GAP, NAV_CELL_GAP),
        CellSize = UDim2.fromOffset(NAV_CELL_WIDTH, NAV_CELL_HEIGHT),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local function navPrefs(): any
        if type(configData.values.NavigatorPrefs) ~= "table" then
            configData.values.NavigatorPrefs = {}
        end
        return configData.values.NavigatorPrefs
    end

    local navOrdered: {any} = {}
    local navEntries: {TextButton} = {}
    local navSelected: number = 1

    local navCellConnections: {RBXScriptConnection} = {}
    local rebuildNavigator: () -> () = function(): () end

    local function paintNavEntry(index: number): ()
        local entry: TextButton? = navEntries[index]
        local feature: any = navOrdered[index]
        if not entry or not feature then
            return
        end
        local on: boolean = feature.enabled == true
        (entry :: TextButton).BackgroundColor3 =
            on and Theme.enabled or Color3.fromRGB(0, 0, 0);
        (entry :: TextButton).BackgroundTransparency = on and 0 or 0.35;
        (entry :: TextButton).TextColor3 = on and Theme.enabledText or Theme.text
        local ring: UIStroke? =
            (entry :: TextButton):FindFirstChild("SelectionRing") :: UIStroke?
        if ring then
            (ring :: UIStroke).Transparency =
                index == navSelected and 0 or 1
        end
    end

    local function paintNavSelection(): ()
        for index: number in ipairs(navEntries) do
            paintNavEntry(index)
        end
    end

    local function navActivate(index: number): ()
        local feature: any = navOrdered[index]
        if not feature then
            return
        end
        if type(feature.activate) == "function" then
            feature.activate()
        end
        navPrefs()[tostring(feature.name)] =
            (tonumber(navPrefs()[tostring(feature.name)]) or 0) + 1
        queueConfigSave()
        paintNavEntry(index)
        refreshHudList()
    end

    local closeNavigator: () -> () = function(): () end

    local function navOpenSettings(index: number): ()
        local feature: any = navOrdered[index]
        if not feature or type(feature.hasOptions) ~= "function"
            or not feature.hasOptions() then
            return
        end
        closeNavigator()
        if state.visible ~= true then
            state.setMenuVisible(true)
        end
        if not feature.expanded and type(feature.toggleExpansion) == "function" then
            feature.toggleExpansion()
        end
    end

    rebuildNavigator = function(): ()
        for _, connection: RBXScriptConnection in ipairs(navCellConnections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        table.clear(navCellConnections)
        for _, child: Instance in ipairs(navResults:GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        local query: string = string.lower(navSearch.Text or "")
        local matches: {any} = {}
        for _, feature: any in ipairs(allFeatures) do
            if query == ""
                or string.find(tostring(feature.searchText), query, 1, true) then
                table.insert(matches, feature)
            end
        end
        local prefs: any = navPrefs()
        table.sort(matches, function(left: any, right: any): boolean
            local leftUses: number = tonumber(prefs[left.name]) or 0
            local rightUses: number = tonumber(prefs[right.name]) or 0
            if leftUses ~= rightUses then
                return leftUses > rightUses
            end
            return tostring(left.name) < tostring(right.name)
        end)
        navOrdered = {}
        navEntries = {}
        for index: number, feature: any in ipairs(matches) do
            table.insert(navOrdered, feature)
            local entry: TextButton = (create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = navResults,
                Name = "Nav_" .. tostring(feature.name):gsub("%W", ""),
                Active = true,
                AutoButtonColor = false,
                BorderSizePixel = 0,
                FontFace = CONTROL_FONT,
                LayoutOrder = index,
                Text = tostring(feature.name),
                TextSize = 14,
                ZIndex = 248,
            }) :: any) :: TextButton
            create("UIStroke", {
                Parent = entry,
                Name = "SelectionRing",
                Color = Theme.enabled,
                Thickness = 1,
                Transparency = 1,
            })
            navEntries[index] = entry
            table.insert(navCellConnections, entry.MouseButton1Click:Connect(function(): ()
                navSelected = index
                navActivate(index)
                paintNavSelection()
            end))
        end
        navSelected = math.clamp(navSelected, 1, math.max(#navOrdered, 1))
        local rows: number = math.ceil(#navOrdered / NAV_COLUMNS)
        local resultHeight: number = rows * NAV_CELL_HEIGHT
            + math.max(rows - 1, 0) * NAV_CELL_GAP
        local screenHeight: number = ScreenGui
                and tonumber(ScreenGui.AbsoluteSize.Y)
            or 0
        if screenHeight <= 0 then
            screenHeight = 480
        end
        local columnHeight: number = math.min(
            38 + resultHeight,
            math.max(160, screenHeight - 96)
        )
        navColumn.Size = UDim2.fromOffset(NAV_WIDTH, columnHeight)
        navResults.Size = UDim2.fromOffset(NAV_WIDTH, columnHeight - 38)
        navResults.CanvasSize = UDim2.fromOffset(0, resultHeight)
        paintNavSelection()
    end

    local navigatorHidMenu: boolean = false
    local function openNavigator(): ()
        if state.visible == true and type(state.setMenuVisible) == "function" then
            navigatorHidMenu = true
            state.setMenuVisible(false)
        else
            navigatorHidMenu = false
        end
        navScreen.Visible = true
        navSelected = 1
        rebuildNavigator()

    end

    closeNavigator = function(): ()
        navScreen.Visible = false
        navSearch:ReleaseFocus()
        navSearch.Text = ""
        if navigatorHidMenu then
            navigatorHidMenu = false
            if type(state.setMenuVisible) == "function" then
                state.setMenuVisible(true)
            end
        end
    end

    table.insert(
        Furniture.connections,
        navSearch:GetPropertyChangedSignal("Text"):Connect(function(): ()
            if navScreen.Visible then
                rebuildNavigator()
            end
        end)
    )
    table.insert(Furniture.connections, navSearch.FocusLost:Connect(function(
        enterPressed: boolean
    ): ()
        if enterPressed and navScreen.Visible then
            navActivate(navSelected)

        end
    end))

    table.insert(Furniture.connections, UserInputService.InputBegan:Connect(function(
        input: InputObject,
        _gameProcessed: boolean
    ): ()
        if not navScreen.Visible then
            return
        end
        local key: Enum.KeyCode = input.KeyCode
        local step: number = 0
        if key == Enum.KeyCode.Escape then
            closeNavigator()
            return
        elseif key == Enum.KeyCode.Backspace then
            if navSearch.Text == "" then
                closeNavigator()
            end
            return
        elseif key == Enum.KeyCode.Down then
            step = NAV_COLUMNS
        elseif key == Enum.KeyCode.Up then
            step = -NAV_COLUMNS
        elseif key == Enum.KeyCode.Right
            or key == Enum.KeyCode.Tab then
            step = 1
        elseif key == Enum.KeyCode.Left then
            step = -1
        elseif key == Enum.KeyCode.Space then
            if navSearch:IsFocused() then
                return
            end
            navOpenSettings(navSelected)
            return
        else
            return
        end
        if #navOrdered > 0 then
            navSelected = ((navSelected - 1 + step) % #navOrdered) + 1
            paintNavSelection()
        end
    end))

    state.navigator = {
        root = navScreen,
        refresh = rebuildNavigator,
        Open = openNavigator,
        Close = closeNavigator,
    }

    local touchPrimary: boolean = state.isMobile == true
    local DOCK_SEARCH_WIDTH: number = 190
    local DOCK_BOTTOM_MARGIN: number = 70
    local dockSearchWidth: number = touchPrimary and 0 or DOCK_SEARCH_WIDTH
    local dockSearchGap: number = touchPrimary and 0 or PILL_GAP
    local menuButtonX: number = PILL_PADDING_X
        + dockSearchWidth
        + dockSearchGap
    local navButtonX: number = menuButtonX + PILL_BUTTON + PILL_GAP
    local pillWidth: number = PILL_PADDING_X * 2
        + dockSearchWidth
        + dockSearchGap
        + PILL_BUTTON
        + PILL_GAP
        + PILL_BUTTON

    local pillFrame: Frame = (create("Frame", {
        Parent = ScreenGui or PopupLayer,
        Name = "Pill",
        Active = true,
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor3 = Color3.fromRGB(16, 18, 28),
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 1, -DOCK_BOTTOM_MARGIN),
        Size = UDim2.fromOffset(pillWidth, PILL_BUTTON + PILL_PADDING_Y * 2),

        ZIndex = 249,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = pillFrame,
        CornerRadius = UDim.new(1, 0),
    })
    create("UIStroke", {
        Parent = pillFrame,
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 1,
        Transparency = 0.91,
    })

    local PILL_IDLE_TEXT: Color3 = Color3.fromRGB(232, 232, 238)

    local function showPillTip(anchor: GuiObject, text: string): ()
        local tooltip: TextLabel? = state.featureTooltip
        if not tooltip then
            return
        end
        state.tooltipToken = state.tooltipToken + 1
        local bitmap: any = state.bitmapText
        local measured: number = bitmap
                and type(bitmap.measure) == "function"
                and tonumber(bitmap.measure({{text = text}}, 16))
            or #text * 8
        local width: number = math.clamp(measured + 24, 120, 320)
        local wrapped: string = text
        local lines: number = 1
        if bitmap and type(bitmap.wrap) == "function" then
            wrapped, lines = bitmap.wrap(text, width - 24, 16)
        end
        local resolvedTooltip: TextLabel = tooltip :: TextLabel
        resolvedTooltip.Text = wrapped
        resolvedTooltip.TextTransparency = 1
        resolvedTooltip.Size = UDim2.fromOffset(
            width,
            math.max(30, lines * 18 + 12)
        )
        resolvedTooltip.Position = UDim2.fromOffset(
            anchor.AbsolutePosition.X,

            anchor.AbsolutePosition.Y - (math.max(30, lines * 18 + 12) + 8)
        )
        if bitmap and type(bitmap.draw) == "function" then
            bitmap.draw(tooltip, {{text = wrapped}}, {
                Name = "Glyphs",
                TextSize = 16,
                maxWidth = width - 24,
                ellipsis = true,
                ZIndex = 251,
            })
        else
            (tooltip :: TextLabel).TextTransparency = 0
        end
        (tooltip :: TextLabel).Visible = true
    end

    local function hidePillTip(): ()
        local tooltip: TextLabel? = state.featureTooltip
        if not tooltip then
            return
        end
        state.tooltipToken = state.tooltipToken + 1;
        (tooltip :: TextLabel).Visible = false
    end

    local function pillButton(
        order: number,
        offsetX: number,
        glyph: string,
        textSize: number,
        tip: string,
        onClick: () -> ()
    ): TextButton
        local button: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = pillFrame,
            Name = "PillButton" .. tostring(order),
            AutoButtonColor = false,
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(offsetX, PILL_PADDING_Y),
            Size = UDim2.fromOffset(PILL_BUTTON, PILL_BUTTON),
            Text = glyph,
            TextColor3 = PILL_IDLE_TEXT,
            TextSize = textSize,
            ZIndex = 241,
        }) :: any) :: TextButton
        create("UICorner", {
            Parent = button,
            CornerRadius = UDim.new(1, 0),
        })
        table.insert(Furniture.connections, button.MouseEnter:Connect(function(): ()
            if not UserInputService.MouseEnabled then
                return
            end
            state.tooltipToken = state.tooltipToken + 1
            local token: number = state.tooltipToken
            task.delay(TOOLTIP_DELAY_MS / 1000, function(): ()
                if state.tooltipToken == token and button.Parent then
                    showPillTip(button, tip)
                end
            end)
        end))
        table.insert(Furniture.connections, button.MouseLeave:Connect(function(): ()
            hidePillTip()
        end))
        table.insert(Furniture.connections, button.MouseButton1Click:Connect(function(): ()
            hidePillTip()
            onClick()
        end))
        return button
    end

    local menuButton: TextButton = pillButton(
        1,
        menuButtonX,
        "≡",
        16,
        "Show or hide the menu",
        function(): ()

            if navScreen.Visible and type(state.SetMenuStyle) == "function" then
                state.SetMenuStyle("Wurst", true)
                return
            end
            if type(state.openMenuSurface) == "function" then
                state.openMenuSurface()
            else
                state.setMenuVisible(not state.visible)
            end
        end
    )

    local navButton: TextButton = pillButton(
        2,
        navButtonX,
        "",
        16,
        "Navigator",
        function(): ()
            local navigator: any = state.navigator
            if not navigator then
                return
            end
            if navigator.root and navigator.root.Visible then
                if type(navigator.Close) == "function" then
                    navigator.Close()
                end
            elseif type(navigator.Open) == "function" then
                navigator.Open()
            end
        end
    )
    do
        local ring: Frame = (create("Frame", {
            Parent = navButton,
            Name = "LupaRing",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0.5, -2, 0.5, -2),
            Size = UDim2.fromOffset(11, 11),
            ZIndex = navButton.ZIndex + 1,
        }) :: any) :: Frame
        create("UICorner", {
            Parent = ring,
            CornerRadius = UDim.new(1, 0),
        })
        create("UIStroke", {
            Parent = ring,
            Color = PILL_IDLE_TEXT,
            Thickness = 1.6,
            Transparency = 0.1,
        })
        local handle: Frame = (create("Frame", {
            Parent = navButton,
            Name = "LupaHandle",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = PILL_IDLE_TEXT,
            BorderSizePixel = 0,
            Position = UDim2.new(0.5, 5, 0.5, 5),
            Rotation = 45,
            Size = UDim2.fromOffset(2, 7),
            ZIndex = navButton.ZIndex + 1,
        }) :: any) :: Frame
        local _ = handle
    end

    local searchShell: Frame = (create("Frame", {
        Parent = pillFrame,
        Name = "DockSearch",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.94,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(PILL_PADDING_X, PILL_PADDING_Y),
        Size = UDim2.fromOffset(dockSearchWidth, PILL_BUTTON),
        Visible = not touchPrimary,
        ZIndex = 241,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = searchShell,
        CornerRadius = UDim.new(1, 0),
    })
    if not touchPrimary and type(makeTextBox) == "function" then
        local searchBox: TextBox = (makeTextBox(searchShell, "") :: any) :: TextBox
        searchBox.Name = "DockSearchBox"
        searchBox.BackgroundTransparency = 1
        searchBox.ClearTextOnFocus = false
        searchBox.PlaceholderText = "Search module..."
        searchBox.Position = UDim2.fromOffset(12, 0)
        searchBox.Size = UDim2.new(1, -18, 1, 0)
        searchBox.TextColor3 = PILL_IDLE_TEXT
        searchBox.TextSize = 14
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.ZIndex = 242
        local boxCorner: UICorner? = searchBox:FindFirstChild("StyleCorner") :: UICorner?
        if boxCorner then
            boxCorner:Destroy()
        end
        local boxStroke: UIStroke? = searchBox:FindFirstChild("StyleStroke") :: UIStroke?
        if boxStroke then
            boxStroke:Destroy()
        end

        local function submitSearch(): ()
            local query: string = tostring(searchBox.Text or "")
            if query:gsub("%s", "") == "" then
                return
            end
            searchBox.Text = ""
            local search: any = state.moduleSearch
            if type(search) ~= "table" or type(search.Execute) ~= "function" then
                notify("module search unavailable")
                return
            end
            local result: any = search.Execute(query)
            local status: string = tostring(result and result.status)
            if status == "success" then
                searchBox.Text = ""
                local entryName: string = tostring(
                    result.entry and result.entry.displayName or query
                )
                notify(entryName .. ": "
                    .. (result.enabled and "enabled" or "disabled"))
            elseif status == "ambiguous" then
                local names: {string} = {}
                for index: number, match: any in ipairs(result.matches or {}) do
                    if index > 4 then
                        table.insert(names, "…")
                        break
                    end
                    table.insert(names, tostring(match.displayName))
                end
                notify("ambiguous: " .. table.concat(names, ", "))
            elseif status == "not_toggleable" then
                notify(tostring(
                    result.entry and result.entry.displayName or query
                ) .. " has nothing to toggle")
            else
                notify("no module matches \"" .. query .. "\"")
            end
        end
        table.insert(
            Furniture.connections,
            searchBox.FocusLost:Connect(function(enterPressed: boolean): ()
                if enterPressed == true then
                    submitSearch()
                end
            end)
        )

        pcall(function(): ()
            table.insert(
                Furniture.connections,
                (searchBox :: any).ReturnPressedFromOnScreenKeyboard:Connect(
                    submitSearch
                )
            )
        end)
    end

    local function setDockVisible(value: boolean): ()
        if touchPrimary then
            pillFrame.Visible = true
            return
        end
        pillFrame.Visible = value ~= false
    end
    setDockVisible(state.uiShowDock ~= false)
    Furniture.SetDockVisible = setDockVisible
    state.dock = {
        root = pillFrame,
        SetVisible = setDockVisible,
    }

    local function restyleMenuButton(): ()
        if not pillFrame.Parent then
            return
        end
        local open: boolean = state.visible == true
        menuButton.BackgroundColor3 = Theme.accent
        menuButton.BackgroundTransparency = open and 0 or 1
        menuButton.TextColor3 = open and Theme.accentText or PILL_IDLE_TEXT
    end
    restyleMenuButton()
    state.addMenuVisibilityListener(function(visible: boolean): ()
        restyleMenuButton()

        refreshLogoVisibility()
        placeHudList()

        if visible then
            task.defer(function(): ()
                local manager: any = state.windows
                if not manager or type(manager.ReflowWindow) ~= "function" then
                    return
                end
                for _, window: any in ipairs(manager.list or {}) do
                    if (window.featureSettings or window.managementWindow)
                        and window.root.Visible
                        and not window.userMoved then
                        manager.ReflowWindow(window)
                    end
                end
            end)
        end
    end)
    refreshLogoVisibility()
    ThemeEngine.OnChange(function(): ()
        restyleMenuButton()

        navSearch.TextColor3 = Theme.text
        navStroke.Color = Theme.outline
        for _, entry: TextButton in ipairs(navEntries) do
            local ring: UIStroke? = entry:FindFirstChild("SelectionRing") :: UIStroke?
            if ring then
                ring.Color = Theme.enabled
            end
        end
        paintNavSelection()
    end)

    state.pill = {
        root = pillFrame,
        restyle = restyleMenuButton,
    }

    if type(state.refreshLauncher) == "function" then
        state.refreshLauncher()
    end

    activeCleanup = function(): ()
        for _, handle: any in ipairs(Furniture.handles) do
            pcall(function(): ()
                handle:Disconnect()
            end)
        end
        Furniture.handles = {}
        for _, connection: RBXScriptConnection in ipairs(Furniture.connections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        Furniture.connections = {}
        for _, connection: RBXScriptConnection in ipairs(navCellConnections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        table.clear(navCellConnections)
        if state.surfaceDragOwner == hudFrame then
            state.surfaceDragOwner = nil
        end
        if state.surfaceDragHitTest == hudHitTest then
            state.surfaceDragHitTest = nil
        end
        chip:Destroy()
        hudFrame:Destroy()
        navScreen:Destroy()
        pillFrame:Destroy()
        state.hudList = nil
        state.wurstLogo = nil
        state.navigator = nil
        state.pill = nil

        if type(state.refreshLauncher) == "function" then
            pcall(state.refreshLauncher)
        end
    end
    Module.Initialized = true
    return Furniture
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
