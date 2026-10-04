local Module = {
    Name = "Cards",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local moduleCleanup: () -> () = function(): () end

function Module.init(context: any): any
    local host: any = context
    local state: any = host.state
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local create: any = host.create
    local makeButton: any = host.makeButton
    local makeTextLabel: any = host.makeTextLabel
    local notify: any = host.notify
    local Theme: any = host.Theme
    local CONTROL_FONT: any = host.CONTROL_FONT
    local trackUiConnection: any = host.trackUiConnection
    local beginKeyCapture: any = host.beginKeyCapture
    local UserInputService: any = host.UserInputService
    local applyKeySlotStyle: any = host.applyKeySlotStyle
    local bindActionShortcut: any = host.bindActionShortcut
    local getFeatureCardParent: any = host.getFeatureCardParent

    local FEATURE_CATEGORIES: any = host.FEATURE_CATEGORIES
    local DEFAULT_FEATURE_CATEGORY: any = host.DEFAULT_FEATURE_CATEGORY
    local normalizeFeatureCategory: any = host.normalizeFeatureCategory

    local universalFeatures: any = host.universalFeatures
    local movementFeatures: any = host.movementFeatures
    local mm2Features: any = host.mm2Features
    local allFeatures: any = host.allFeatures
    local registeredSearchFeatures: {any} = {}

    local applyFeaturePresentation: any = host.applyFeaturePresentation
    local refreshFeatureToggle: any = host.refreshFeatureToggle
    local addFeatureTooltip: any = host.addFeatureTooltip

    local drawPixelIcon: any = host.drawPixelIcon
        or function(parent: Instance, _kind: string, _color: Color3?): Frame
            local existing: Instance? = (parent :: any):FindFirstChild("PixelIcon")
            if existing then
                existing:Destroy()
            end
            return create("Frame", {
                Parent = parent,
                Name = "PixelIcon",
                BackgroundTransparency = 1,
            }) :: Frame
        end

    local function createUniversalFeature(
        name: string,
        description: string,
        layoutOrder: number,
        onToggle: any,
        configuration: any?
    ): any
        configuration = configuration or {}
        local registry: any = configuration.registry or universalFeatures
        local sectionName: string = configuration.section
            or (registry == mm2Features and "MM2")
            or (registry == state.trsFeatures and "TRS")
            or (registry == state.vdFeatures and "VD")
            or (registry == state.bedFightFeatures and "BedFight")
            or (registry == state.bedWarsFeatures and "BedWars")
            or (registry == state.mvsdFeatures and "MVSD")
            or (registry == movementFeatures and "Movement")
            or "Universal"
        local configKey: string = configuration.configKey
            or (sectionName .. "." .. name:gsub("%W", ""))

        local rawCategory: any = type(configuration.categoryName) == "string"
            and configuration.categoryName
            or FEATURE_CATEGORIES[name]
            or DEFAULT_FEATURE_CATEGORY
        local categoryName: string = type(normalizeFeatureCategory) == "function"
            and normalizeFeatureCategory(rawCategory)
            or tostring(rawCategory)

        local feature: any = {
            name = name,
            description = description,
            categoryName = categoryName,
            enabled = false,
            expanded = false,

            kind = configuration.kind
                or (configuration.action == true and "action")
                or (configuration.holdAction == true and "hold")
                or (configuration.category == true and "group")
                or "toggle",
            silentAction = configuration.silentAction == true,
            searchable = configuration.searchable ~= false,
            onHold = configuration.onHold,
            optionCount = 0,
            optionRows = {},
            collapsedHeight = state.layout.cardHeight,
            onToggle = onToggle,
            configKey = configKey,
            registry = registry,
            sectionName = sectionName,
            searchText = string.lower(
                name
                    .. " "
                    .. description
                    .. " "
                    .. sectionName
                    .. " "
                    .. categoryName
            ),
            tooltipText = description,
            tooltipBound = false,
        }

        feature.isAction = feature.kind == "action"
        feature.isCategory = feature.kind == "group"
        feature.isHoldAction = feature.kind == "hold"
        feature.isAlwaysOn = feature.kind == "hold" or feature.kind == "group"

        local requestedParent: Instance? =
            configuration.parent :: any
        local fallback: Instance = (host :: any).ScreenGui or (host :: any).PopupLayer or ({} :: any)
        local rowParent: Instance = getFeatureCardParent(requestedParent or fallback)
        if type(rowParent) ~= "table" or (rowParent :: any).Children == nil then
            rowParent = fallback
        end
        local row: Frame = (create("Frame", {
            Parent = rowParent,
            Name = name:gsub("%W", "") .. "Feature",
            Active = true,
            BackgroundColor3 = state.guiStyle == "Default"
                and Theme.surface
                or Theme.background,
            BackgroundTransparency = state.guiStyle == "Default" and 0.82 or 1,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            LayoutOrder = layoutOrder,
            Size = UDim2.new(1, 0, 0, feature.collapsedHeight),
        }) :: any) :: Frame
        feature.row = row

        row:SetAttribute("FeatureCategory", categoryName)
        row:SetAttribute("FeatureSortName", string.lower(name))

        local bitmapText: any = state.bitmapText
        local title: TextLabel? = nil
        if bitmapText and type(bitmapText.draw) == "function" then
            feature.drawTitle = function(color: Color3?, transparency: number?): ()
                if color ~= nil then
                    feature.titleColor = color
                end
                if transparency ~= nil then
                    feature.titleTransparency = transparency
                end
                bitmapText.draw(row, {
                    {
                        text = name,
                        color = feature.titleColor or Theme.text,
                    },
                }, {
                    Name = "Title",
                    TextSize = state.layout.titleFontSize,
                    ZIndex = 7,
                    align = "Center",
                    transparency = feature.titleTransparency or 0,

                    maxWidth = 140,
                })
            end
            feature.drawTitle(Theme.text, 0)
        else
            title = (makeTextLabel(row, name, state.layout.titleFontSize) :: any) :: TextLabel
            local label: TextLabel = title :: TextLabel
            label.FontFace = CONTROL_FONT

            label.Position = UDim2.fromOffset(28, 0)
            label.Size = UDim2.new(1, -56, 0, feature.collapsedHeight)
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextTruncate = Enum.TextTruncate.AtEnd
            label.TextColor3 = state.guiStyle == "Default"
                and Theme.text
                or Theme.text
            feature.title = label
        end

        local arrow: TextButton? = nil
        local toggleExpansion: () -> () = function(): () end

        function feature.hasOptions(): boolean
            if configuration.noOptions == true then
                return false
            end
            for _, optionRow: GuiObject in ipairs(feature.optionRows) do
                if optionRow.Visible then
                    return true
                end
            end
            return false
        end

        local function syncArrow(): ()
            local expandable: boolean = feature.hasOptions()
            feature.hasSettings = expandable
            if expandable and not arrow then
                local built: TextButton = (create("TextButton", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                    Name = "Expand",
                    Active = true,
                    AnchorPoint = Vector2.new(1, 0),
                    AutoButtonColor = false,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    FontFace = CONTROL_FONT,
                    Position = UDim2.new(1, 0, 0, 0),
                    Size = UDim2.fromOffset(22, feature.collapsedHeight),
                    Text = "",
                    TextSize = 10,
                    ZIndex = 9,
                }) :: any) :: TextButton
                trackUiConnection(built.MouseButton1Click:Connect(function(): ()
                    toggleExpansion()
                end))
                arrow = built
                feature.arrow = built
            end
            if arrow then
                (arrow :: TextButton).Visible = expandable

                drawPixelIcon(
                    arrow :: TextButton,
                    feature.expanded and "up" or "down",
                    Color3.fromRGB(0, 204, 0)
                )
            end
        end
        feature.syncArrow = syncArrow

        local activationTarget: TextButton = create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClipsDescendants = true,
            Parent = row,
            Name = "ActivationTarget",
            Active = true,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, 0, 0, feature.collapsedHeight),
            Text = "",
            ZIndex = 6,
        }) :: TextButton
        feature.activationTarget = activationTarget
        if title then
            (title :: TextLabel).ZIndex = 7
        end

        trackUiConnection(row.MouseEnter:Connect(function(): ()
            state.applyCardSkin(feature, true)
        end))
        trackUiConnection(row.MouseLeave:Connect(function(): ()
            state.applyCardSkin(feature, false)
        end))

        local options: Frame = (create("Frame", {
            Parent = row,
            Name = "Options",
            Active = true,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(4, feature.collapsedHeight),
            Size = UDim2.new(1, -8, 0, 0),
            Visible = false,
            ZIndex = row.ZIndex + 10,
        }) :: any) :: Frame
        feature.options = options
        create("UIPadding", {
            Parent = options,
            PaddingBottom = UDim.new(0, 4),
            PaddingLeft = UDim.new(0, 0),
            PaddingRight = UDim.new(0, 0),
            PaddingTop = UDim.new(0, 4),
        })
        local optionsLayout: UIListLayout = (create("UIListLayout", {
            Parent = options,
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }) :: any) :: UIListLayout

        local function updateExpandedSize(_animate: boolean?): ()

            local visibleOptions: number = 0
            local declaredHeight: number = 0
            for _, optionRow: GuiObject in ipairs(feature.optionRows) do
                if optionRow.Visible then
                    visibleOptions += 1
                    declaredHeight += optionRow.Size.Y.Offset
                end
            end
            local measuredHeight: number = optionsLayout.AbsoluteContentSize.Y
            if visibleOptions > 0 and measuredHeight <= 0 then
                measuredHeight = declaredHeight
                    + math.max(0, visibleOptions - 1) * 4
            end

            local optionsHeight: number = measuredHeight + 8
            feature.optionsHeight = optionsHeight
            options.Size = UDim2.new(1, 0, 0, optionsHeight)
            syncArrow()
            local settingsWindow: any = feature.settingsWindow
            if settingsWindow and settingsWindow.resizeToOptions then
                settingsWindow.resizeToOptions()
            end
        end
        feature.updateExpandedSize = updateExpandedSize
        trackUiConnection(
            optionsLayout:GetPropertyChangedSignal("AbsoluteContentSize")
                :Connect(function(): ()
                    updateExpandedSize(false)
                end)
        )

        toggleExpansion = function(): ()
            if not feature.hasOptions() then

                syncArrow()
                return
            end

            local windows: any = state.windows
            if windows and type(windows.OpenFeatureSettings) == "function" then
                windows.OpenFeatureSettings(feature)
            end
        end
        feature.toggleExpansion = toggleExpansion

        function feature.setHeld(held: boolean): ()
            if feature.held == held then
                return
            end
            feature.held = held
            local handler: any = feature.onHold
            if type(handler) ~= "function" then
                return
            end
            local ok: boolean, failure: any = pcall(handler, held)
            if not ok then
                warn("[Random Testing Menu] " .. name .. ": " .. tostring(failure))
                return
            end
            feature.active = held
            refreshFeatureToggle(feature)
        end

        local function activateFeature(): ()
            if feature.isHoldAction then

                return
            end
            if feature.isCategory then
                if not feature.hasOptions() then
                    return
                end
                feature.expanded = not feature.expanded
                updateExpandedSize(true)
                return
            end
            if feature.isAction then
                if feature.actionRunning then
                    return
                end
                feature.actionRunning = true
                task.spawn(function(): ()
                    local success: boolean, errorMessage: any = pcall(feature.onToggle)
                    feature.actionRunning = false
                    if success then

                        if not feature.silentAction then
                            notify(name .. " ran")
                        end
                    else
                        warn("[Random Testing Menu] " .. name .. ": " .. tostring(errorMessage))
                        notify("Could not run " .. name)
                    end
                end)
                return
            end

            local requestedState: boolean = not feature.enabled
            local success: boolean, errorMessage: any = pcall(
                feature.onToggle,
                requestedState
            )
            if success then
                feature.enabled = requestedState
                if requestedState then
                    feature.enabledAt = os.clock()
                end
                configData.states[feature.configKey] = requestedState
                queueConfigSave()
                notify(name .. (requestedState and " enabled" or " disabled"))
            else
                warn("[Random Testing Menu] " .. name .. ": " .. tostring(errorMessage))
                feature.enabled = false
                pcall(feature.onToggle, false)
                notify("Could not toggle " .. name)
            end
            refreshFeatureToggle(feature)
        end
        feature.activate = activateFeature

        state.applyCardSkin(feature, false)
        if feature.isAction then

            trackUiConnection(activationTarget.MouseButton1Down:Connect(function(): ()
                if feature.row then
                    (feature.row :: Frame).BackgroundTransparency = 0.46
                end
            end))
            trackUiConnection(activationTarget.MouseButton1Up:Connect(function(): ()
                state.applyCardSkin(feature, true)
            end))
        end

        trackUiConnection(activationTarget.MouseButton1Click:Connect(activateFeature))

        trackUiConnection(activationTarget.InputBegan:Connect(function(input: InputObject): ()
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                toggleExpansion()
            end
        end))

        local shortcutButton: TextButton? = nil
        if state.isMobile then
            local slot: TextButton =
                (makeButton(row, "KEY", 9) :: any) :: TextButton
            slot.Name = "Shortcut"

            slot.AnchorPoint = Vector2.new(0, 0.5)
            slot.Position = UDim2.new(0, 4, 0, feature.collapsedHeight / 2)
            slot.Size = UDim2.fromOffset(22, 22)
            slot.ZIndex = 9
            applyKeySlotStyle(slot)
            slot.TextScaled = true
            create("UITextSizeConstraint", {
                Parent = slot,
                MaxTextSize = 11,
                MinTextSize = 7,
            })
            shortcutButton = slot
        end
        feature.shortcutButton = shortcutButton
        if feature.kind == "group" then

            if shortcutButton then
                (shortcutButton :: TextButton).Visible = false
            end
        elseif feature.kind == "hold" then

            bindActionShortcut(
                shortcutButton,
                feature.configKey,
                name,
                function(): () end,
                {
                    hold = true,
                    onPress = function(): ()
                        feature.setHeld(true)
                    end,
                    onRelease = function(): ()
                        feature.setHeld(false)
                    end,
                }
            )
        else
            bindActionShortcut(
                shortcutButton,
                feature.configKey,
                name,
                activateFeature
            )
        end

        if (feature.kind == "toggle"
                or feature.kind == "action"
                or feature.kind == "hold")
            and not state.isMobile
            and type(beginKeyCapture) == "function"
            and type(state.shortcutBindings) == "table"
            and state.shortcutBindings[feature.configKey] ~= nil then
            local binding: any = state.shortcutBindings[feature.configKey]
            local UNBOUND_BG: Color3 = Color3.fromRGB(0, 0, 0)
            local BOUND_BG: Color3 = Color3.fromRGB(0, 80, 0)
            local CONFLICT_BG: Color3 = Color3.fromRGB(80, 0, 0)
            local BOUND_EDGE: Color3 = Color3.fromRGB(0, 204, 0)
            local CONFLICT_EDGE: Color3 = Color3.fromRGB(204, 0, 0)
            local square: TextButton = (create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
                Name = "BindSquare",
                Active = true,
                AnchorPoint = Vector2.new(0, 0.5),
                AutoButtonColor = false,
                BackgroundColor3 = UNBOUND_BG,
                BackgroundTransparency = 0.55,
                BorderSizePixel = 0,
                FontFace = CONTROL_FONT,
                Position = UDim2.new(0, 4, 0.5, 0),
                Size = UDim2.fromOffset(18, 18),
                Text = "",
                TextColor3 = Theme.text,
                TextTransparency = 0,
                TextSize = 8,
                ZIndex = 8,
            }) :: any) :: TextButton
            square:SetAttribute("CaptureIdleText", "")
            local edge: UIStroke = (create("UIStroke", {
                Parent = square,
                Name = "StyleStroke",
                Color = Theme.outline,
                Thickness = 1,
                Transparency = 0.6,
            }) :: any) :: UIStroke

            local COMPACT_KEY_NAMES: {[string]: string} = {
                LeftShift = "LS",
                RightShift = "RS",
                LeftControl = "LC",
                RightControl = "RC",
                LeftAlt = "LA",
                RightAlt = "RA",
                CapsLock = "CL",
                Backspace = "Bk",
                Return = "En",
                Escape = "Es",
                Space = "Sp",
                PageUp = "PU",
                PageDown = "PD",
                Insert = "Ins",
                Delete = "Del",
                Home = "Hm",
                End = "End",
            }
            local function keyCaption(): string
                if binding.key == nil or binding.key == Enum.KeyCode.Unknown then
                    return ""
                end
                local name: string = tostring(binding.key.Name or "")
                local compact: string? = COMPACT_KEY_NAMES[name]
                if compact then
                    return compact
                end
                local display: string = state.keyDisplayName
                        and tostring(state.keyDisplayName(name))
                    or name
                return string.sub(display, 1, 3)
            end

            local capturing: boolean = false
            local function conflictWith(): any
                if binding.key == nil or binding.key == Enum.KeyCode.Unknown then
                    return nil
                end
                for _, other: any in pairs(state.shortcutBindings) do
                    if other ~= binding and other.key == binding.key then
                        return other
                    end
                end
                return nil
            end
            local function syncSquare(): ()
                if capturing then
                    return
                end
                local caption: string = keyCaption()
                square.Text = caption
                square:SetAttribute("CaptureIdleText", caption)
                local bound: boolean = binding.key ~= nil
                    and binding.key ~= Enum.KeyCode.Unknown
                local conflict: any = bound and conflictWith() or nil
                if conflict then
                    square.BackgroundColor3 = CONFLICT_BG
                    square.BackgroundTransparency = 0.35
                    edge.Color = CONFLICT_EDGE
                    edge.Transparency = 0.15
                elseif bound then
                    square.BackgroundColor3 = BOUND_BG
                    square.BackgroundTransparency = 0.35
                    edge.Color = BOUND_EDGE
                    edge.Transparency = 0.25
                else
                    square.BackgroundColor3 = UNBOUND_BG
                    square.BackgroundTransparency = 0.55
                    edge.Color = Theme.outline
                    edge.Transparency = 0.6
                end
            end
            feature.bindSquare = square
            feature.syncBindSquare = syncSquare
            local refreshBinding: any = binding.refresh
            binding.refresh = function(): ()
                if refreshBinding then
                    refreshBinding()
                end
                syncSquare()
            end
            syncSquare()

            local function syncKeyboard(): ()
                square.Visible = UserInputService == nil
                    or UserInputService.KeyboardEnabled ~= false
            end
            syncKeyboard()
            pcall(function(): ()
                trackUiConnection(
                    UserInputService:GetPropertyChangedSignal("KeyboardEnabled")
                        :Connect(syncKeyboard)
                )
            end)

            local function tipText(): string
                local bound: boolean = binding.key ~= nil
                    and binding.key ~= Enum.KeyCode.Unknown
                if not bound then
                    return "Bind: click, then press a key"
                end
                local conflict: any = conflictWith()
                if conflict then
                    return binding.key.Name .. " — also bound to "
                        .. tostring(conflict.id)
                end
                return "Bound: " .. binding.key.Name
            end
            trackUiConnection(square.MouseEnter:Connect(function(): ()
                local tooltip: any = state.featureTooltip
                if not tooltip then
                    return
                end
                state.tooltipToken = (state.tooltipToken or 0) + 1
                local token: number = state.tooltipToken
                task.delay(0.4, function(): ()
                    if state.tooltipToken ~= token or not square.Parent then
                        return
                    end
                    local rawText: string = tipText()
                    local bitmap: any = state.bitmapText
                    local measured: number = bitmap
                            and type(bitmap.measure) == "function"
                            and tonumber(bitmap.measure({{text = rawText}}, 16))
                        or #rawText * 8
                    local width: number = math.clamp(measured + 24, 140, 360)
                    local wrapped: string = rawText
                    local lines: number = 1
                    if bitmap and type(bitmap.wrap) == "function" then
                        wrapped, lines = bitmap.wrap(rawText, width - 24, 16)
                    end
                    tooltip.Text = wrapped
                    tooltip.TextTransparency = 1
                    tooltip.Size = UDim2.fromOffset(width, math.max(30, lines * 18 + 12))
                    tooltip.Position = UDim2.fromOffset(
                        square.AbsolutePosition.X,
                        square.AbsolutePosition.Y + square.AbsoluteSize.Y + 8
                    )
                    if state.bitmapText and type(state.bitmapText.draw) == "function" then
                        state.bitmapText.draw(tooltip, {
                            {text = tooltip.Text},
                        }, {
                            Name = "Glyphs",
                            TextSize = 16,
                            maxWidth = width - 24,
                            ellipsis = true,
                            ZIndex = 251,
                        })
                    end
                    tooltip.Visible = true
                end)
            end))
            trackUiConnection(square.MouseLeave:Connect(function(): ()
                state.tooltipToken = (state.tooltipToken or 0) + 1
                if state.featureTooltip then
                    state.featureTooltip.Visible = false
                end
            end))

            local outsideConnection: RBXScriptConnection? = nil
            local function cleanupCapture(): ()
                capturing = false
                if outsideConnection then
                    pcall(function(): ()
                        (outsideConnection :: RBXScriptConnection):Disconnect()
                    end)
                    outsideConnection = nil
                end
                syncSquare()

                task.delay(0.2, function(): ()
                    if square.Parent and not capturing then
                        syncSquare()
                    end
                end)
            end
            trackUiConnection(square.MouseButton1Click:Connect(function(): ()
                if capturing then

                    if state.keyCaptureCancel then
                        state.keyCaptureCancel()
                    else
                        cleanupCapture()
                    end
                    return
                end
                capturing = true
                beginKeyCapture(square, function(keyCode: Enum.KeyCode): ()

                    local backspaceKey: any = (Enum.KeyCode :: any).Backspace
                    local deleteKey: any = (Enum.KeyCode :: any).Delete
                    if keyCode == backspaceKey or keyCode == deleteKey then
                        if binding.key ~= Enum.KeyCode.Unknown
                            and type(binding.assign) == "function" then
                            binding.assign(binding.key)
                        end
                    elseif type(binding.assign) == "function" then
                        binding.assign(keyCode)
                    end
                    cleanupCapture()
                end)

                local baseCancel: any = state.keyCaptureCancel
                state.keyCaptureCancel = function(): ()
                    if baseCancel then
                        baseCancel()
                    end
                    cleanupCapture()
                end

                pcall(function(): ()
                    outsideConnection = UserInputService.InputBegan:Connect(function(
                        input: InputObject
                    ): ()
                        if input.UserInputType ~= Enum.UserInputType.MouseButton1
                            and input.UserInputType ~= Enum.UserInputType.Touch then
                            return
                        end
                        local px: number = input.Position.X
                        local py: number = input.Position.Y
                        local ax: number = square.AbsolutePosition.X
                        local ay: number = square.AbsolutePosition.Y
                        if px < ax or px > ax + square.AbsoluteSize.X
                            or py < ay or py > ay + square.AbsoluteSize.Y then
                            if state.keyCaptureCancel then
                                state.keyCaptureCancel()
                            end
                        end
                    end)
                end)
            end))
        end

        feature.applyLayout = function(): ()
            local metrics: LayoutMetrics = state.layout
            feature.collapsedHeight = metrics.cardHeight
            if title then
                state.setTextMetric(title, metrics.titleFontSize)
            elseif feature.drawTitle then

                feature.drawTitle(nil, nil)
            end
            if arrow then
                (arrow :: TextButton).Size =
                    UDim2.fromOffset(22, metrics.cardHeight)
            end
            if shortcutButton then
                (shortcutButton :: TextButton).Size = UDim2.fromOffset(22, 22);
                (shortcutButton :: TextButton).Position =
                    UDim2.new(0, 4, 0, metrics.cardHeight / 2)
            end
            activationTarget.Size = UDim2.new(1, 0, 0, metrics.cardHeight)
            options.Position = UDim2.fromOffset(4, metrics.cardHeight)
            syncArrow()
            updateExpandedSize(false)
        end

        feature.applyLayout()

        function feature:SetStatus(status: string?): ()
            feature.status = status
        end

        registry[name] = feature
        table.insert(allFeatures, feature)

        if state.floatingUi then
            state.floatingUi.registerFeature(feature)
        end

        if state.clickGui then
            state.clickGui.place(feature)
        end
        applyFeaturePresentation(feature, state.guiStyle == "Default")

        if type(addFeatureTooltip) == "function" and description ~= "" then
            addFeatureTooltip(feature, description)
        end

        local search: any = state.moduleSearch
        if search and type(search.Register) == "function" then
            search.Register(feature)
            table.insert(registeredSearchFeatures, feature)
        end

        if feature.isAlwaysOn then
            task.defer(function(): ()
                local ok: boolean, failure: any = pcall(feature.onToggle, true)
                if not ok then
                    warn("[Random Testing Menu] " .. name .. ": " .. tostring(failure))
                end
            end)
        end

        if not feature.isAction
            and not feature.isCategory
            and not feature.isHoldAction
            and configuration.restore ~= false
            and configData.states[feature.configKey] == true then
            task.defer(function(): ()
                local success: boolean, errorMessage: any = pcall(
                    feature.onToggle,
                    true
                )
                if success then
                    feature.enabled = true
                    feature.enabledAt = os.clock()
                    refreshFeatureToggle(feature)
                else
                    configData.states[feature.configKey] = false
                    queueConfigSave()
                    warn(
                        "[Random Testing Menu] Could not restore "
                            .. name
                            .. ": "
                            .. tostring(errorMessage)
                    )
                end
            end)
        end
        return feature
    end

    moduleCleanup = function(): ()
        local search: any = state.moduleSearch
        if search and type(search.Unregister) == "function" then
            for _, feature: any in ipairs(registeredSearchFeatures) do
                search.Unregister(feature)
            end
        end
        table.clear(registeredSearchFeatures)
    end
    Module.Initialized = true
    return {createUniversalFeature = createUniversalFeature}
end

function Module.destroy(): ()
    moduleCleanup()
    moduleCleanup = function(): () end
    Module.Initialized = false
end

return Module
