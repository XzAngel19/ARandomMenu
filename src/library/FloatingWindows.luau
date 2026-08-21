--!strict
--
-- Floating windows and overlays.
--
-- Everything the menu draws *outside* its own window: the favourites list, the
-- overlay menu, and the four overlays themselves — the text readout, the
-- session panel, the target panel and the radar — each with its own compact
-- settings window.
--
-- Eighteen hundred lines of it lived in `ARandomMenu.luau`, which is most of
-- the reason the shell was still five figures long. None of it is shell logic:
-- a floating window is a draggable frame with a title bar and a close button,
-- and an overlay is a thing drawn on a timer from values the game already
-- publishes.
--
-- The whole subsystem reaches the rest of the menu through one table,
-- `state.floatingUi`. That was already true before it moved, which is why the
-- move is a relocation rather than a rewrite.

export type FloatingWindowRecord = {
    id: string,
    root: Frame,
    body: Frame,
    closeButton: TextButton,
}

local activeCleanup: (() -> ())? = nil

local Module = {
    Name = "FloatingWindows",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

function Module.init(context: any): any
    local host: any = context
    local state: any = host.state
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local create: any = host.create
    local makeButton: any = host.makeButton
    local makeTextBox: any = host.makeTextBox
    local makeTextLabel: any = host.makeTextLabel
    local Theme: any = host.Theme
    local CONTROL_FONT: any = host.CONTROL_FONT
    local THIN_FONT: any = host.THIN_FONT
    local VALVE_FONT: any = host.VALVE_FONT
    local PopupLayer: any = host.PopupLayer
    local UI_RADIUS: any = host.UI_RADIUS
    local cornerRadius: any = host.cornerRadius
    local trackUiConnection: any = host.trackUiConnection
    local createToggleSwitch: any = host.createToggleSwitch
    local setToggleSwitch: any = host.setToggleSwitch
    local TweenService: any = host.TweenService
    local UserInputService: any = host.UserInputService
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local Stats: any = host.Stats
    local TaskManager: any = host.TaskManager
    local allFeatures: any = host.allFeatures
    local PROFILE_CARD_HEIGHT: any = host.PROFILE_CARD_HEIGHT
    -- A favourite jumps to the page its card lives on, so the layer needs the
    -- shell's tab switcher.
    local setTab: any = host.setTab

    -- Per-frame work this layer owns. In the shell these two loops simply ran
    -- for the life of the menu and were swept up when the task manager was
    -- destroyed; a library is started and stopped on its own, so it has to
    -- hand them back itself.
    local ownedTasks: {any} = {}

    local FloatingUi: any = {
        favorites = {},
        favoriteRows = {},
        overlays = {},
        featureRows = {},
        windows = {},
    }
    state.floatingUi = FloatingUi

    if type(configData.ui.favorites) ~= "table" then
        configData.ui.favorites = {}
    end
    if type(configData.ui.overlays) ~= "table" then
        configData.ui.overlays = {}
    end
    if type(configData.ui.floatingPositions) ~= "table" then
        configData.ui.floatingPositions = {}
    end
    if type(configData.ui.overlaySettings) ~= "table" then
        configData.ui.overlaySettings = {}
    end
    local overlaySettings: any = configData.ui.overlaySettings
    overlaySettings.TextGUI = type(overlaySettings.TextGUI) == "table"
        and overlaySettings.TextGUI
        or {}
    overlaySettings.SessionInfo = type(overlaySettings.SessionInfo) == "table"
        and overlaySettings.SessionInfo
        or {}
    overlaySettings.TargetInfo = type(overlaySettings.TargetInfo) == "table"
        and overlaySettings.TargetInfo
        or {}
    overlaySettings.Radar = type(overlaySettings.Radar) == "table"
        and overlaySettings.Radar
        or {}
    local textGuiSettings: any = overlaySettings.TextGUI
    textGuiSettings.sort = textGuiSettings.sort or "Alphabetical"
    textGuiSettings.font = textGuiSettings.font or "Builder Sans"
    textGuiSettings.colorMode = textGuiSettings.colorMode or "Match GUI"
    textGuiSettings.scale = math.clamp(tonumber(textGuiSettings.scale) or 1, 0.75, 2)
    textGuiSettings.shadow = textGuiSettings.shadow ~= false
    textGuiSettings.gradient = textGuiSettings.gradient == true
    textGuiSettings.v4Gradient = textGuiSettings.v4Gradient == true
    textGuiSettings.animations = textGuiSettings.animations ~= false
    textGuiSettings.watermark = textGuiSettings.watermark == true
    textGuiSettings.background = textGuiSettings.background == true
    textGuiSettings.hideModules = textGuiSettings.hideModules == true
    textGuiSettings.hideRender = textGuiSettings.hideRender == true
    textGuiSettings.customText = tostring(textGuiSettings.customText or "")
    local sessionSettings: any = overlaySettings.SessionInfo
    sessionSettings.showPerformance = sessionSettings.showPerformance ~= false
    sessionSettings.showServer = sessionSettings.showServer ~= false
    sessionSettings.showRole = sessionSettings.showRole ~= false
    sessionSettings.showDeaths = sessionSettings.showDeaths ~= false
    sessionSettings.showWins = sessionSettings.showWins ~= false
    local targetSettings: any = overlaySettings.TargetInfo
    targetSettings.mode = targetSettings.mode or "Smart Priority"
    targetSettings.showAvatar = targetSettings.showAvatar ~= false
    targetSettings.showHealth = targetSettings.showHealth ~= false
    targetSettings.showDistance = targetSettings.showDistance ~= false
    local radarSettings: any = overlaySettings.Radar
    radarSettings.range = math.clamp(tonumber(radarSettings.range) or 250, 25, 2000)
    radarSettings.size = math.clamp(tonumber(radarSettings.size) or 190, 140, 280)
    radarSettings.rotation = radarSettings.rotation or "Camera"
    radarSettings.colorMode = radarSettings.colorMode or "Smart"
    radarSettings.outOfRange = radarSettings.outOfRange or "Clamp"
    radarSettings.showNames = radarSettings.showNames == true
    radarSettings.showDistance = radarSettings.showDistance == true
    radarSettings.showTeam = radarSettings.showTeam ~= false
    radarSettings.aliveOnly = radarSettings.aliveOnly ~= false
    radarSettings.grid = radarSettings.grid ~= false
    radarSettings.rings = radarSettings.rings ~= false

    local function getFloatingViewport(): Vector2
        local camera: Camera? = workspace.CurrentCamera
        return camera and camera.ViewportSize or Vector2.new(1280, 720)
    end

    local function clampFloatingPosition(
        position: Vector2,
        size: Vector2
    ): Vector2
        local viewport: Vector2 = getFloatingViewport()
        return Vector2.new(
            math.clamp(position.X, 6, math.max(6, viewport.X - size.X - 6)),
            math.clamp(position.Y, 6, math.max(6, viewport.Y - size.Y - 6))
        )
    end

    local function bringFloatingToFront(record: FloatingWindowRecord): ()
        for index: number = #FloatingUi.windows, 1, -1 do
            if FloatingUi.windows[index] == record then
                table.remove(FloatingUi.windows, index)
                break
            end
        end
        table.insert(FloatingUi.windows, record)
        for index: number, window: FloatingWindowRecord in ipairs(FloatingUi.windows) do
            local baseZ: number = 108 + index * 4
            window.root.ZIndex = baseZ
            for _, descendant: Instance in ipairs(window.root:GetDescendants()) do
                if descendant:IsA("GuiObject") then
                    local relative: number =
                        tonumber(descendant:GetAttribute("FloatingDepth")) or 1
                    descendant.ZIndex = baseZ + relative
                end
            end
        end
    end

    -- Floating windows.
    --
    -- Two flavours share this factory:
    --   * framed  — favourites, the overlay manager and the per-overlay settings.
    --               These are tool windows: header, title, close button, panel
    --               background. They are movable on purpose (the fixed shell is
    --               the main menu, not these).
    --   * chrome-less — the HUD overlays (radar, target info, session info, text
    --               GUI). They render their content and nothing else: no panel,
    --               no header, no close button, so a circular radar is just a
    --               circle on screen instead of a circle inside a box. They stay
    --               movable: the content itself is the drag handle.
    local function createFloatingWindow(
        id: string,
        titleText: string,
        size: Vector2,
        defaultPosition: Vector2,
        onClose: (() -> ())?,
        chromeless: boolean?
    ): FloatingWindowRecord
        local bare: boolean = chromeless == true
        local headerHeight: number = bare and 0 or 30
        local saved: any = configData.ui.floatingPositions[id]
        local position: Vector2 = type(saved) == "table"
            and Vector2.new(
                tonumber(saved[1]) or defaultPosition.X,
                tonumber(saved[2]) or defaultPosition.Y
            )
            or defaultPosition
        position = clampFloatingPosition(position, size)

        local root: Frame = create("Frame", {
            Parent = PopupLayer,
            Name = "Floating_" .. id,
            Active = true,
            BackgroundColor3 = Theme.DefaultBackground,
            BackgroundTransparency = bare and 1 or 0.08,
            BorderSizePixel = 0,
            ClipsDescendants = not bare,
            Position = UDim2.fromOffset(position.X, position.Y),
            Size = UDim2.fromOffset(size.X, size.Y),
            Visible = false,
            ZIndex = 150,
        }) :: Frame
        if not bare then
            create("UICorner", {
                Parent = root,
                CornerRadius = cornerRadius(UI_RADIUS.panel),
            })
            -- Hairline only: the floating windows share the borderless look of
            -- the main shell, so no grey frame draws attention at their corners.
            create("UIStroke", {
                Parent = root,
                Color = Theme.DefaultOutline,
                Transparency = 0.78,
                Thickness = 1,
            })

            local shade: Frame = create("Frame", {
                Parent = root,
                Name = "Readability",
                BackgroundColor3 = Theme.DefaultBackground,
                BackgroundTransparency = 0.28,
                BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1),
            }) :: Frame
            shade:SetAttribute("FloatingDepth", 2)
        end

        local header: Frame = create("Frame", {
            Parent = root,
            Name = "Header",
            Active = not bare,
            BackgroundColor3 = Theme.DefaultSurface,
            BackgroundTransparency = 0.24,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, headerHeight),
            Visible = not bare,
        }) :: Frame
        header:SetAttribute("FloatingDepth", 3)

        local closeButton: TextButton
        if bare then
            -- Kept so every record has the same shape; never shown.
            closeButton = create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                ClipsDescendants = true,
                Parent = header,
                Name = "Close",
                BackgroundTransparency = 1,
                Text = "",
                Visible = false,
            }) :: TextButton
        else
            local accent: Frame = create("Frame", {
                Parent = header,
                BackgroundColor3 = Theme.DefaultOutline,
                BackgroundTransparency = 0.62,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, headerHeight - 1),
                Size = UDim2.new(1, 0, 0, 1),
            }) :: Frame
            accent:SetAttribute("FloatingDepth", 1)
            local title: TextLabel = makeTextLabel(header, titleText, 10)
            title.FontFace = CONTROL_FONT
            title.Position = UDim2.fromOffset(10, 0)
            title.Size = UDim2.new(1, -40, 1, 0)
            title.TextColor3 = Theme.DefaultText
            title:SetAttribute("FloatingDepth", 2)

            closeButton = makeButton(header, "x", 9)
            closeButton.Name = "Close"
            closeButton.AnchorPoint = Vector2.new(1, 0.5)
            closeButton.BackgroundTransparency = 1
            closeButton.Position = UDim2.new(1, -6, 0.5, 0)
            closeButton.Size = UDim2.fromOffset(22, 22)
            closeButton.TextColor3 = Theme.DefaultTextMuted
            closeButton:SetAttribute("ThemeRole", "Icon")
            closeButton:SetAttribute("FloatingDepth", 3)
            local closeStroke: UIStroke? =
                closeButton:FindFirstChild("StyleStroke") :: UIStroke?
            if closeStroke then
                closeStroke.Enabled = false
            end
        end

        local body: Frame = create("Frame", {
            Parent = root,
            Name = "Body",
            Active = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, headerHeight),
            Size = UDim2.new(1, 0, 1, -headerHeight),
        }) :: Frame
        body:SetAttribute("FloatingDepth", 4)

        -- A chrome-less overlay is mostly transparent, so while the menu is
        -- closed it must not swallow clicks meant for the game underneath: it
        -- only becomes an input surface (and therefore only becomes movable)
        -- while the menu is on screen.
        if bare then
            root.Active = state.visible == true
            -- Faint outline shown only while the menu is open, so it is obvious
            -- which HUD elements can be grabbed and repositioned. It disappears
            -- with the menu, leaving the bare read-out on screen.
            create("UICorner", {
                Parent = root,
                CornerRadius = cornerRadius(UI_RADIUS.control),
            })
            local hint: UIStroke = create("UIStroke", {
                Parent = root,
                Name = "MoveHint",
                Color = Theme.DefaultOutline,
                Thickness = 1,
                Transparency = state.visible and 0.72 or 1,
            }) :: UIStroke
            state.addMenuVisibilityListener(function(visible: boolean): ()
                if not root.Parent then
                    return
                end
                root.Active = visible
                hint.Transparency = visible and 0.72 or 1
            end)
        end

        local record: FloatingWindowRecord = {
            id = id,
            root = root,
            body = body,
            closeButton = closeButton,
        }
        -- A chrome-less overlay has no title bar to grab, so the whole surface
        -- drags it; a framed window only drags from its header, which keeps its
        -- content clickable.
        local dragHandle: GuiObject = bare and root or header
        local dragging: boolean = false
        local dragInput: InputObject? = nil
        local dragStart: Vector2 = Vector2.zero
        local startPosition: Vector2 = position

        trackUiConnection(root.InputBegan:Connect(function(): ()
            bringFloatingToFront(record)
        end))
        trackUiConnection(dragHandle.InputBegan:Connect(function(input: InputObject): ()
            if bare and not state.visible then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                dragStart = Vector2.new(input.Position.X, input.Position.Y)
                startPosition = Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
                bringFloatingToFront(record)
            end
        end))
        trackUiConnection(UserInputService.InputChanged:Connect(function(input: InputObject): ()
            if not dragging then
                return
            end
            if input == dragInput
                or (dragInput
                    and dragInput.UserInputType == Enum.UserInputType.MouseButton1
                    and input.UserInputType == Enum.UserInputType.MouseMovement) then
                local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
                local nextPosition: Vector2 = clampFloatingPosition(
                    startPosition + pointer - dragStart,
                    root.AbsoluteSize
                )
                root.Position = UDim2.fromOffset(nextPosition.X, nextPosition.Y)
            end
        end))
        trackUiConnection(UserInputService.InputEnded:Connect(function(input: InputObject): ()
            if dragging
                and (input == dragInput
                    or input.UserInputType == Enum.UserInputType.MouseButton1) then
                dragging = false
                dragInput = nil
                configData.ui.floatingPositions[id] = {
                    root.Position.X.Offset,
                    root.Position.Y.Offset,
                }
                queueConfigSave()
            end
        end))
        trackUiConnection(closeButton.MouseButton1Click:Connect(function(): ()
            root.Visible = false
            if onClose then
                onClose()
            end
        end))
        bringFloatingToFront(record)
        return record
    end

    function FloatingUi.reclamp(): ()
        for _, record: FloatingWindowRecord in ipairs(FloatingUi.windows) do
            local position: Vector2 = clampFloatingPosition(
                Vector2.new(record.root.Position.X.Offset, record.root.Position.Y.Offset),
                record.root.AbsoluteSize
            )
            record.root.Position = UDim2.fromOffset(position.X, position.Y)
        end
    end

    -- Movable windows keep their saved position, but a smaller screen must never
    -- leave one of them stranded outside the viewport.
    state.onLayout(function(): ()
        FloatingUi.reclamp()
    end)

    local FavoritesWindow: FloatingWindowRecord = createFloatingWindow(
        "Favorites",
        "Favorites",
        Vector2.new(state.layout.compact and 240 or 270, 236),
        Vector2.new(40, 90),
        function(): ()
            configData.ui.favoritesWindowOpen = false
            queueConfigSave()
        end
    )
    local FavoritesList: ScrollingFrame = create("ScrollingFrame", {
        Parent = FavoritesWindow.body,
        Name = "FavoriteModules",
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(8, 8),
        ScrollBarImageColor3 = Theme.DefaultOutline,
        ScrollBarThickness = 3,
        Size = UDim2.new(1, -16, 1, -16),
    }) :: ScrollingFrame
    FavoritesList:SetAttribute("FloatingDepth", 2)
    create("UIListLayout", {
        Parent = FavoritesList,
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local function syncFavoriteButton(feature: any): ()
        if not feature.favoriteButton then
            return
        end
        local selected: boolean = configData.ui.favorites[feature.configKey] == true
        feature.favoriteButton.Text = selected and "★" or "☆"
        feature.favoriteButton.TextColor3 = selected
            and Theme.DefaultAccent
            or Theme.DefaultTextMuted
        feature.favoriteButton.TextTransparency = selected and 0 or 0.34
    end

    local function refreshFavorites(): ()
        for _, row: GuiObject in ipairs(FloatingUi.favoriteRows) do
            row:Destroy()
        end
        table.clear(FloatingUi.favoriteRows)
        local order: number = 0
        for _, feature: any in ipairs(allFeatures) do
            if configData.ui.favorites[feature.configKey] == true then
                order += 1
                local row: TextButton = create("TextButton", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ClipsDescendants = true,
                    Parent = FavoritesList,
                    Name = feature.configKey:gsub("%W", ""),
                    AutoButtonColor = false,
                    BackgroundColor3 = Theme.DefaultSurface,
                    BackgroundTransparency = 0.38,
                    BorderSizePixel = 0,
                    FontFace = THIN_FONT,
                    LayoutOrder = order,
                    Size = UDim2.new(1, -4, 0, 36),
                    Text = feature.name,
                    TextColor3 = feature.enabled
                        and Theme.DefaultAccent
                        or Theme.DefaultText,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }) :: TextButton
                create("UICorner", {
                    Parent = row,
                    CornerRadius = cornerRadius(8),
                })
                row:SetAttribute("FloatingDepth", 3)
                create("UIPadding", {
                    Parent = row,
                    PaddingLeft = UDim.new(0, 12),
                    PaddingRight = UDim.new(0, 38),
                })
                local status: Frame = create("Frame", {
                    Parent = row,
                    Name = "Status",
                    AnchorPoint = Vector2.new(1, 0.5),
                    BackgroundColor3 = feature.enabled
                        and Theme.AccentCyan
                        or Theme.DefaultTextMuted,
                    BackgroundTransparency = feature.enabled and 0 or 0.58,
                    BorderSizePixel = 0,
                    Position = UDim2.new(1, -14, 0.5, 0),
                    Size = UDim2.fromOffset(feature.enabled and 9 or 7, feature.enabled and 9 or 7),
                }) :: Frame
                create("UICorner", {Parent = status, CornerRadius = UDim.new(1, 0)})
                status:SetAttribute("FloatingDepth", 2)
                row.MouseButton1Click:Connect(function(): ()
                    if feature.isCategory then
                        state.setMenuVisible(true)
                        setTab("Universal")
                    end
                    feature.activate()
                end)
                table.insert(FloatingUi.favoriteRows, row)
            end
        end
        if order == 0 then
            local empty: TextLabel = create("TextLabel", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                ClipsDescendants = true,
                Parent = FavoritesList,
                BackgroundTransparency = 1,
                FontFace = THIN_FONT,
                LayoutOrder = 1,
                Size = UDim2.new(1, -4, 0, 52),
                Text = "Star a module to keep it here",
                TextColor3 = Theme.DefaultTextMuted,
                TextSize = 13,
                TextTransparency = 0.28,
                TextXAlignment = Enum.TextXAlignment.Center,
            }) :: TextLabel
            empty:SetAttribute("FloatingDepth", 3)
            table.insert(FloatingUi.favoriteRows, empty)
        end
    end

    function FloatingUi.toggleFavorite(feature: any): ()
        local nextValue: boolean = configData.ui.favorites[feature.configKey] ~= true
        configData.ui.favorites[feature.configKey] = nextValue and true or nil
        syncFavoriteButton(feature)
        refreshFavorites()
        queueConfigSave()
    end

    function FloatingUi.registerFeature(feature: any): ()
        FloatingUi.favorites[feature.configKey] = feature
        syncFavoriteButton(feature)
        if configData.ui.favorites[feature.configKey] == true then
            refreshFavorites()
        end
    end

    function FloatingUi.unregisterFeature(feature: any): ()
        FloatingUi.favorites[feature.configKey] = nil
        if configData.ui.favorites[feature.configKey] == true then
            refreshFavorites()
        end
    end

    function FloatingUi.refreshFeature(feature: any): ()
        if configData.ui.favorites[feature.configKey] == true then
            refreshFavorites()
        end
    end

    local OverlayMenu: FloatingWindowRecord = createFloatingWindow(
        "OverlayMenu",
        "Overlays",
        Vector2.new(state.layout.compact and 232 or 252, 220),
        Vector2.new(340, 90),
        function(): ()
            configData.ui.overlayMenuOpen = false
            queueConfigSave()
        end
    )
    local OverlayList: Frame = create("Frame", {
        Parent = OverlayMenu.body,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -16, 1, -16),
    }) :: Frame
    OverlayList:SetAttribute("FloatingDepth", 2)
    create("UIListLayout", {
        Parent = OverlayList,
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    -- HUD overlays are chrome-less: their window is exactly the content and
    -- nothing else, so the radar is a bare circle, the target read-out is a bare
    -- read-out and the session counters are bare text. They keep their own drag
    -- handling, and the overlay manager below is what turns them on and off.
    local overlayDefinitions: {any} = {
        {id = "SessionInfo", title = "Session Info", size = Vector2.new(210, 118), position = Vector2.new(24, 300)},
        {id = "TextGUI", title = "Text GUI", size = Vector2.new(240, 220), position = Vector2.new(250, 300)},
        {id = "TargetInfo", title = "Target Info", size = Vector2.new(260, 86), position = Vector2.new(510, 300)},
        {id = "Radar", title = "Radar", size = Vector2.new(radarSettings.size, radarSettings.size), position = Vector2.new(820, 280)},
    }

    local function setOverlayEnabled(id: string, enabled: boolean): ()
        local overlay: any = FloatingUi.overlays[id]
        if not overlay then
            return
        end
        overlay.enabled = enabled
        overlay.window.root.Visible = enabled
        setToggleSwitch(overlay.toggle, enabled, true)
        configData.ui.overlays[id] = enabled
        queueConfigSave()
        if enabled then
            bringFloatingToFront(overlay.window)
        end
    end

    FloatingUi.settingsWindows = {}
    FloatingUi.openSettings = function(id: string): ()
        local window: FloatingWindowRecord? = FloatingUi.settingsWindows[id]
        if window then
            window.root.Visible = not window.root.Visible
            if window.root.Visible then
                bringFloatingToFront(window)
            end
        end
    end

    for index: number, definition: any in ipairs(overlayDefinitions) do
        local overlayId: string = definition.id
        local overlayWindow: FloatingWindowRecord
        overlayWindow = createFloatingWindow(
            overlayId,
            definition.title,
            definition.size,
            definition.position,
            function(): ()
                setOverlayEnabled(overlayId, false)
            end,
            true
        )
        local managerRow: Frame = create("Frame", {
            Parent = OverlayList,
            BackgroundColor3 = Theme.DefaultSurface,
            BackgroundTransparency = 0.48,
            BorderSizePixel = 0,
            LayoutOrder = index,
            Size = UDim2.new(1, 0, 0, 40),
        }) :: Frame
        managerRow:SetAttribute("FloatingDepth", 3)
        create("UICorner", {
            Parent = managerRow,
            CornerRadius = cornerRadius(8),
        })
        local managerLabel: TextLabel = makeTextLabel(managerRow, definition.title, 10)
        managerLabel.Position = UDim2.fromOffset(10, 0)
        managerLabel.Size = UDim2.new(1, -112, 1, 0)
        managerLabel.TextColor3 = Theme.DefaultTextMuted
        managerLabel:SetAttribute("FloatingDepth", 1)
        local settingsButton: TextButton = makeButton(managerRow, "", 9)
        settingsButton.Name = "Settings"
        -- Same three-line mark the cards use: one glyph means "open the settings
        -- of the thing on this row" everywhere in the interface.
        state.applyLinesGlyph(settingsButton, false)
        settingsButton.AnchorPoint = Vector2.new(1, 0.5)
        settingsButton.BackgroundTransparency = 1
        settingsButton.Position = UDim2.new(1, -58, 0.5, 0)
        settingsButton.Size = UDim2.fromOffset(28, 28)
        settingsButton:SetAttribute("FloatingDepth", 2)
        local settingsStroke: UIStroke? =
            settingsButton:FindFirstChild("StyleStroke") :: UIStroke?
        if settingsStroke then
            settingsStroke.Enabled = false
        end
        local toggle: TextButton = createToggleSwitch(managerRow, false, 42)
        toggle.AnchorPoint = Vector2.new(1, 0.5)
        toggle.Position = UDim2.new(1, -7, 0.5, 0)
        toggle:SetAttribute("FloatingDepth", 2)
        FloatingUi.overlays[overlayId] = {
            window = overlayWindow,
            toggle = toggle,
            enabled = false,
        }
        trackUiConnection(toggle.MouseButton1Click:Connect(function(): ()
            setOverlayEnabled(overlayId, not FloatingUi.overlays[overlayId].enabled)
        end))
        trackUiConnection(settingsButton.MouseButton1Click:Connect(function(): ()
            FloatingUi.openSettings(overlayId)
        end))
    end

    local function createOverlaySettingsWindow(
        id: string,
        title: string,
        height: number,
        position: Vector2
    ): (FloatingWindowRecord, ScrollingFrame)
        -- Settings windows scroll, so their height is capped to the screen: a
        -- 500px panel would run off a phone in landscape.
        local window: FloatingWindowRecord = createFloatingWindow(
            id .. "Settings",
            title,
            Vector2.new(
                state.layout.compact and 268 or 292,
                math.min(height, math.max(180, getFloatingViewport().Y - 24))
            ),
            position,
            nil
        )
        local scroll: ScrollingFrame = create("ScrollingFrame", {
            Parent = window.body,
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, 0),
            Position = UDim2.fromOffset(8, 8),
            ScrollBarImageColor3 = Theme.AccentViolet,
            ScrollBarThickness = 3,
            Size = UDim2.new(1, -16, 1, -16),
        }) :: ScrollingFrame
        scroll:SetAttribute("FloatingDepth", 2)
        create("UIListLayout", {
            Parent = scroll,
            Padding = UDim.new(0, 5),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        FloatingUi.settingsWindows[id] = window
        return window, scroll
    end

    local function createCompactSettingRow(parent: Instance, labelText: string): Frame
        local row: Frame = create("Frame", {
            Parent = parent,
            BackgroundColor3 = Theme.DefaultSurface,
            BackgroundTransparency = 0.44,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -4, 0, 38),
        }) :: Frame
        create("UICorner", {Parent = row, CornerRadius = cornerRadius(8)})
        local label: TextLabel = makeTextLabel(row, labelText, 9)
        label.Position = UDim2.fromOffset(10, 0)
        label.Size = UDim2.new(0.48, -10, 1, 0)
        label.TextColor3 = Theme.DefaultTextMuted
        return row
    end

    local function addCompactCycle(
        parent: Instance,
        labelText: string,
        values: {string},
        currentValue: string,
        callback: (string) -> ()
    ): ()
        local row: Frame = createCompactSettingRow(parent, labelText)
        local index: number = table.find(values, currentValue) or 1
        local button: TextButton = makeButton(row, values[index], 8)
        button.Position = UDim2.new(0.48, 4, 0, 4)
        button.Size = UDim2.new(0.52, -8, 1, -8)
        trackUiConnection(button.MouseButton1Click:Connect(function(): ()
            index = index % #values + 1
            button.Text = values[index]
            callback(values[index])
            queueConfigSave()
        end))
    end

    local function addCompactToggle(
        parent: Instance,
        labelText: string,
        initial: boolean,
        callback: (boolean) -> ()
    ): ()
        local row: Frame = createCompactSettingRow(parent, labelText)
        local enabled: boolean = initial
        local toggle: TextButton = createToggleSwitch(row, enabled, 42)
        toggle.AnchorPoint = Vector2.new(1, 0.5)
        toggle.Position = UDim2.new(1, -8, 0.5, 0)
        trackUiConnection(toggle.MouseButton1Click:Connect(function(): ()
            enabled = not enabled
            setToggleSwitch(toggle, enabled, true)
            callback(enabled)
            queueConfigSave()
        end))
    end

    local function addCompactText(
        parent: Instance,
        labelText: string,
        initial: string,
        callback: (string) -> ()
    ): ()
        local row: Frame = createCompactSettingRow(parent, labelText)
        local box: TextBox = makeTextBox(row, initial)
        box.Position = UDim2.new(0.48, 4, 0, 4)
        box.Size = UDim2.new(0.52, -8, 1, -8)
        box.PlaceholderText = "Custom text"
        box.TextXAlignment = Enum.TextXAlignment.Left
        trackUiConnection(box.FocusLost:Connect(function(): ()
            callback(string.sub(box.Text, 1, 80))
            queueConfigSave()
        end))
    end

    -- The four settings windows are reachable through `FloatingUi.settingsWindows`
    -- (createOverlaySettingsWindow registers each one), so they no longer need
    -- block locals that other scopes cannot see.
    do
        local textSettingsScroll: ScrollingFrame
        local _textSettingsWindow: FloatingWindowRecord
        _textSettingsWindow, textSettingsScroll = createOverlaySettingsWindow(
            "TextGUI",
            "Text GUI Studio",
            state.layout.compact and 500 or 540,
            Vector2.new(300, 70)
        )
        addCompactCycle(textSettingsScroll, "Sort", {"Alphabetical", "Length", "Enabled order", "Section"}, textGuiSettings.sort, function(value: string): () textGuiSettings.sort = value end)
        addCompactCycle(textSettingsScroll, "Font", {"Builder Sans", "Source Sans", "Gotham", "Code", "Valve"}, textGuiSettings.font, function(value: string): () textGuiSettings.font = value end)
        addCompactCycle(textSettingsScroll, "Color mode", {"Match GUI", "Solid white", "Greyscale", "Rainbow", "By section"}, textGuiSettings.colorMode, function(value: string): () textGuiSettings.colorMode = value end)
        addCompactCycle(textSettingsScroll, "Scale", {"0.75", "1", "1.25", "1.5", "2"}, tostring(textGuiSettings.scale), function(value: string): () textGuiSettings.scale = tonumber(value) or 1 end)
        addCompactToggle(textSettingsScroll, "Shadow", textGuiSettings.shadow, function(value: boolean): () textGuiSettings.shadow = value end)
        addCompactToggle(textSettingsScroll, "Gradient", textGuiSettings.gradient, function(value: boolean): () textGuiSettings.gradient = value end)
        addCompactToggle(textSettingsScroll, "V4 gradient", textGuiSettings.v4Gradient, function(value: boolean): () textGuiSettings.v4Gradient = value end)
        addCompactToggle(textSettingsScroll, "Animations", textGuiSettings.animations, function(value: boolean): () textGuiSettings.animations = value end)
        addCompactToggle(textSettingsScroll, "Watermark", textGuiSettings.watermark, function(value: boolean): () textGuiSettings.watermark = value end)
        addCompactToggle(textSettingsScroll, "Render background", textGuiSettings.background, function(value: boolean): () textGuiSettings.background = value end)
        addCompactToggle(textSettingsScroll, "Hide modules", textGuiSettings.hideModules, function(value: boolean): () textGuiSettings.hideModules = value end)
        addCompactToggle(textSettingsScroll, "Hide render", textGuiSettings.hideRender, function(value: boolean): () textGuiSettings.hideRender = value end)
        addCompactText(textSettingsScroll, "Custom text", textGuiSettings.customText, function(value: string): () textGuiSettings.customText = value end)
    end

    do
        local radarSettingsScroll: ScrollingFrame
        local _radarSettingsWindow: FloatingWindowRecord
        _radarSettingsWindow, radarSettingsScroll = createOverlaySettingsWindow(
            "Radar",
            "Radar Studio",
            500,
            Vector2.new(630, 70)
        )
        addCompactCycle(radarSettingsScroll, "Range", {"75", "150", "250", "500", "1000", "2000"}, tostring(radarSettings.range), function(value: string): () radarSettings.range = tonumber(value) or 250 end)
        addCompactCycle(radarSettingsScroll, "Radar size", {"160", "190", "220", "250", "280"}, tostring(radarSettings.size), function(value: string): () radarSettings.size = tonumber(value) or 190 end)
        addCompactCycle(radarSettingsScroll, "Rotation", {"Camera", "Player", "North"}, radarSettings.rotation, function(value: string): () radarSettings.rotation = value end)
        addCompactCycle(radarSettingsScroll, "Color mode", {"Smart", "Team", "Health", "MM2 role", "Spectrum"}, radarSettings.colorMode, function(value: string): () radarSettings.colorMode = value end)
        addCompactCycle(radarSettingsScroll, "Out of range", {"Clamp", "Hide"}, radarSettings.outOfRange, function(value: string): () radarSettings.outOfRange = value end)
        addCompactToggle(radarSettingsScroll, "Alive only", radarSettings.aliveOnly, function(value: boolean): () radarSettings.aliveOnly = value end)
        addCompactToggle(radarSettingsScroll, "Show team", radarSettings.showTeam, function(value: boolean): () radarSettings.showTeam = value end)
        addCompactToggle(radarSettingsScroll, "Show names", radarSettings.showNames, function(value: boolean): () radarSettings.showNames = value end)
        addCompactToggle(radarSettingsScroll, "Show distance", radarSettings.showDistance, function(value: boolean): () radarSettings.showDistance = value end)
        addCompactToggle(radarSettingsScroll, "Grid", radarSettings.grid, function(value: boolean): () radarSettings.grid = value end)
        addCompactToggle(radarSettingsScroll, "Range rings", radarSettings.rings, function(value: boolean): () radarSettings.rings = value end)
    end

    do
        local sessionSettingsScroll: ScrollingFrame
        local _sessionSettingsWindow: FloatingWindowRecord
        _sessionSettingsWindow, sessionSettingsScroll = createOverlaySettingsWindow(
            "SessionInfo",
            "Session Metrics",
            310,
            Vector2.new(960, 70)
        )
        addCompactToggle(sessionSettingsScroll, "Performance", sessionSettings.showPerformance, function(value: boolean): () sessionSettings.showPerformance = value end)
        addCompactToggle(sessionSettingsScroll, "Server data", sessionSettings.showServer, function(value: boolean): () sessionSettings.showServer = value end)
        addCompactToggle(sessionSettingsScroll, "Role and team", sessionSettings.showRole, function(value: boolean): () sessionSettings.showRole = value end)
        addCompactToggle(sessionSettingsScroll, "Deaths", sessionSettings.showDeaths, function(value: boolean): () sessionSettings.showDeaths = value end)
        addCompactToggle(sessionSettingsScroll, "Wins / rounds", sessionSettings.showWins, function(value: boolean): () sessionSettings.showWins = value end)
    end

    do
        local targetSettingsScroll: ScrollingFrame
        local _targetSettingsWindow: FloatingWindowRecord
        _targetSettingsWindow, targetSettingsScroll = createOverlaySettingsWindow(
            "TargetInfo",
            "Target Priority",
            280,
            Vector2.new(960, 395)
        )
        addCompactCycle(targetSettingsScroll, "Selection", {"Smart Priority", "Nearest cursor", "Nearest distance"}, targetSettings.mode, function(value: string): () targetSettings.mode = value end)
        addCompactToggle(targetSettingsScroll, "Avatar portrait", targetSettings.showAvatar, function(value: boolean): () targetSettings.showAvatar = value end)
        addCompactToggle(targetSettingsScroll, "Health bar", targetSettings.showHealth, function(value: boolean): () targetSettings.showHealth = value end)
        addCompactToggle(targetSettingsScroll, "Distance", targetSettings.showDistance, function(value: boolean): () targetSettings.showDistance = value end)
    end

    -- Session read-out. With the panel gone the text sits directly on the game,
    -- so it carries its own one-pixel shadow instead of relying on a background.
    local SessionShadow: TextLabel = makeTextLabel(
        FloatingUi.overlays.SessionInfo.window.body,
        "Session initializing...",
        9
    )
    SessionShadow.Name = "SessionShadow"
    SessionShadow.Position = UDim2.fromOffset(1, 1)
    SessionShadow.Size = UDim2.fromScale(1, 1)
    SessionShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    SessionShadow.TextTransparency = 0.25
    SessionShadow.TextYAlignment = Enum.TextYAlignment.Top
    SessionShadow:SetAttribute("FloatingDepth", 1)

    local SessionText: TextLabel = makeTextLabel(
        FloatingUi.overlays.SessionInfo.window.body,
        "Session initializing...",
        9
    )
    SessionText.Position = UDim2.fromOffset(0, 0)
    SessionText.Size = UDim2.fromScale(1, 1)
    SessionText.TextColor3 = Theme.DefaultText
    SessionText.TextYAlignment = Enum.TextYAlignment.Top
    SessionText:SetAttribute("FloatingDepth", 2)

    local TextGuiBody: Frame = FloatingUi.overlays.TextGUI.window.body
    local TextGuiShadow: TextLabel = makeTextLabel(
        TextGuiBody,
        "No active modules",
        10
    )
    TextGuiShadow.Position = UDim2.fromOffset(1, 1)
    TextGuiShadow.Size = UDim2.fromScale(1, 1)
    TextGuiShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    TextGuiShadow.TextTransparency = 0.16
    TextGuiShadow.TextWrapped = true
    TextGuiShadow.TextYAlignment = Enum.TextYAlignment.Top
    TextGuiShadow:SetAttribute("FloatingDepth", 1)
    local TextGuiLabel: TextLabel = makeTextLabel(
        FloatingUi.overlays.TextGUI.window.body,
        "No active modules",
        10
    )
    TextGuiLabel.Position = UDim2.fromOffset(0, 0)
    TextGuiLabel.Size = UDim2.fromScale(1, 1)
    TextGuiLabel.TextColor3 = Theme.AccentCyan
    TextGuiLabel.TextWrapped = true
    TextGuiLabel.TextYAlignment = Enum.TextYAlignment.Top
    TextGuiLabel:SetAttribute("FloatingDepth", 2)
    local TextGuiGradient: UIGradient = create("UIGradient", {
        Parent = TextGuiLabel,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.DefaultAccent),
            ColorSequenceKeypoint.new(0.5, Theme.AccentViolet),
            ColorSequenceKeypoint.new(1, Theme.AccentPink),
        }),
        Rotation = 90,
        Enabled = false,
    }) :: UIGradient

    local TargetBody: Frame = FloatingUi.overlays.TargetInfo.window.body
    -- The portrait is content, not chrome, so it keeps its own rounded plate;
    -- everything that used to box the whole read-out is gone.
    local TargetPortraitFrame: Frame = create("Frame", {
        Parent = TargetBody,
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(56, 56),
    }) :: Frame
    TargetPortraitFrame:SetAttribute("FloatingDepth", 2)
    create("UICorner", {Parent = TargetPortraitFrame, CornerRadius = cornerRadius(UI_RADIUS.panel)})
    create("UIStroke", {
        Parent = TargetPortraitFrame,
        Color = Theme.DefaultOutline,
        Transparency = 0.55,
        Thickness = 1,
    })
    local TargetPortrait: ImageLabel = create("ImageLabel", {
        Parent = TargetPortraitFrame,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        Position = UDim2.fromOffset(4, 4),
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.new(1, -8, 1, -8),
        ZIndex = 3,
    }) :: ImageLabel
    TargetPortrait:SetAttribute("FloatingDepth", 3)
    create("UICorner", {Parent = TargetPortrait, CornerRadius = cornerRadius(10)})
    local TargetName: TextLabel = makeTextLabel(
        TargetBody,
        "No target",
        11
    )
    TargetName.FontFace = CONTROL_FONT
    TargetName.Position = UDim2.fromOffset(64, 0)
    TargetName.Size = UDim2.new(1, -64, 0, 22)
    TargetName:SetAttribute("FloatingDepth", 2)
    local TargetRole: TextLabel = makeTextLabel(TargetBody, "No priority target", 8)
    TargetRole.Position = UDim2.fromOffset(64, 21)
    TargetRole.Size = UDim2.new(1, -64, 0, 18)
    TargetRole.TextColor3 = Theme.AccentViolet
    TargetRole:SetAttribute("FloatingDepth", 2)
    local TargetHealthTrack: Frame = create("Frame", {
        Parent = TargetBody,
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(64, 42),
        Size = UDim2.new(1, -64, 0, 6),
    }) :: Frame
    TargetHealthTrack:SetAttribute("FloatingDepth", 2)
    create("UICorner", {Parent = TargetHealthTrack, CornerRadius = UDim.new(1, 0)})
    local TargetHealthFill: Frame = create("Frame", {
        Parent = TargetHealthTrack,
        BackgroundColor3 = Theme.AccentCyan,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1),
    }) :: Frame
    TargetHealthFill:SetAttribute("FloatingDepth", 1)
    create("UICorner", {Parent = TargetHealthFill, CornerRadius = UDim.new(1, 0)})
    local TargetDetails: TextLabel = makeTextLabel(
        TargetBody,
        "Waiting for a nearby player",
        9
    )
    TargetDetails.Position = UDim2.fromOffset(0, 58)
    TargetDetails.Size = UDim2.new(1, 0, 0, 28)
    TargetDetails.TextColor3 = Theme.DefaultTextMuted
    TargetDetails:SetAttribute("FloatingDepth", 2)

    local RadarSurface: Frame = create("Frame", {
        Parent = FloatingUi.overlays.Radar.window.body,
        Name = "Surface",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.34,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(radarSettings.size, radarSettings.size),
    }) :: Frame
    RadarSurface:SetAttribute("FloatingDepth", 2)
    create("UICorner", {Parent = RadarSurface, CornerRadius = UDim.new(1, 0)})
    create("UIStroke", {
        Parent = RadarSurface,
        Color = Theme.DefaultOutline,
        Transparency = 0.55,
    })
    local radarAxes: {Frame} = {}
    for _, rotation: number in ipairs({0, 90}) do
        local axis: Frame = create("Frame", {
            Parent = RadarSurface,
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.DefaultOutline,
            BackgroundTransparency = 0.72,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(0.5, 0.5),
            Rotation = rotation,
            Size = UDim2.new(1, -16, 0, 1),
        }) :: Frame
        axis:SetAttribute("FloatingDepth", 1)
        table.insert(radarAxes, axis)
    end
    local radarRings: {Frame} = {}
    for _, scale: number in ipairs({0.34, 0.67}) do
        local ring: Frame = create("Frame", {
            Parent = RadarSurface,
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(scale, scale),
        }) :: Frame
        ring:SetAttribute("FloatingDepth", 1)
        create("UICorner", {Parent = ring, CornerRadius = UDim.new(1, 0)})
        create("UIStroke", {
            Parent = ring,
            Color = Theme.DefaultOutline,
            Transparency = 0.7,
            Thickness = 1,
        })
        table.insert(radarRings, ring)
    end
    local RadarNorth: TextLabel = makeTextLabel(RadarSurface, "N", 8)
    RadarNorth.AnchorPoint = Vector2.new(0.5, 0)
    RadarNorth.Position = UDim2.new(0.5, 0, 0, 5)
    RadarNorth.Size = UDim2.fromOffset(20, 18)
    RadarNorth.TextColor3 = Theme.AccentCyan
    RadarNorth.TextXAlignment = Enum.TextXAlignment.Center
    RadarNorth:SetAttribute("FloatingDepth", 3)
    local RadarCenter: Frame = create("Frame", {
        Parent = RadarSurface,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.AccentCyan,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(7, 7),
    }) :: Frame
    RadarCenter:SetAttribute("FloatingDepth", 3)
    create("UICorner", {Parent = RadarCenter, CornerRadius = UDim.new(1, 0)})
    local radarBlips: {[Player]: any} = {}
    local sessionStartedAt: number = os.clock()
    local overlayElapsed: number = 1
    local sessionFps: number = 60
    local sessionStats: any = {
        deaths = 0,
        wins = 0,
        rounds = 0,
        winsAvailable = false,
        roundsAvailable = false,
        role = nil,
    }
    state.sessionInfo = {
        setRole = function(role: string?): () sessionStats.role = role end,
        addWin = function(): ()
            sessionStats.winsAvailable = true
            sessionStats.wins += 1
        end,
        addRound = function(): ()
            sessionStats.roundsAvailable = true
            sessionStats.rounds += 1
        end,
    }
    local deathConnection: RBXScriptConnection? = nil
    local sessionBindGeneration: number = 0
    local sessionTrackingActive: boolean = true
    local function bindSessionCharacter(character: Model): ()
        sessionBindGeneration += 1
        local generation: number = sessionBindGeneration
        if deathConnection then
            deathConnection:Disconnect()
            deathConnection = nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 8) :: Humanoid?
        if humanoid
            and sessionTrackingActive
            and generation == sessionBindGeneration
            and character == LocalPlayer.Character then
            deathConnection = humanoid.Died:Connect(function(): ()
                sessionStats.deaths += 1
            end)
        end
    end
    if LocalPlayer.Character then
        task.defer(bindSessionCharacter, LocalPlayer.Character)
    end
    trackUiConnection(LocalPlayer.CharacterAdded:Connect(bindSessionCharacter))

    -- Teardown hook for the session counters.
    --
    -- These three values are locals of this block, so the destruct routine at the
    -- bottom of the file could not reach them: assigning them there created three
    -- globals instead and left the `Died` connection alive. Exposing the teardown
    -- through `state` is what actually stops the tracking.
    state.destroySessionTracking = function(): ()
        sessionTrackingActive = false
        sessionBindGeneration += 1
        if deathConnection then
            deathConnection:Disconnect()
            deathConnection = nil
        end
    end
    local thumbnailCache: {[number]: string} = {}
    local thumbnailGeneration: number = 0
    local displayedTargetUserId: number = 0
    local currentOverlayTarget: Player? = nil

    local function requestTargetThumbnail(player: Player?): ()
        local userId: number = player and player.UserId or 0
        if userId == displayedTargetUserId then
            return
        end
        displayedTargetUserId = userId
        thumbnailGeneration += 1
        local generation: number = thumbnailGeneration
        TargetPortrait.Image = userId > 0 and (thumbnailCache[userId] or "") or ""
        if userId <= 0 or thumbnailCache[userId] then
            return
        end
        task.spawn(function(): ()
            local success: boolean, image: any, ready: any = pcall(
                Players.GetUserThumbnailAsync,
                Players,
                userId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size180x180
            )
            if success and ready == true and type(image) == "string" and image ~= "" then
                thumbnailCache[userId] = image
                if generation == thumbnailGeneration and TargetPortrait.Parent then
                    TargetPortrait.Image = image
                end
            elseif generation == thumbnailGeneration then
                task.delay(1, function(): ()
                    if generation == thumbnailGeneration then
                        displayedTargetUserId = 0
                    end
                end)
            end
        end)
    end

    local function getTextGuiFont(): Font
        if textGuiSettings.font == "Source Sans" then
            return Font.fromEnum(Enum.Font.SourceSans)
        elseif textGuiSettings.font == "Gotham" then
            return Font.fromEnum(Enum.Font.Gotham)
        elseif textGuiSettings.font == "Code" then
            return Font.fromEnum(Enum.Font.Code)
        elseif textGuiSettings.font == "Valve" then
            return VALVE_FONT
        end
        return CONTROL_FONT
    end

    local function getSessionPing(): number?
        local success: boolean, value: any = pcall(function(): number
            local network: any = Stats:FindFirstChild("Network")
            local serverStats: any = network and network:FindFirstChild("ServerStatsItem")
            local ping: any = serverStats and serverStats:FindFirstChild("Data Ping")
            return ping and ping:GetValue() or 0
        end)
        return success and tonumber(value) or nil
    end

    local lastTextGuiText: string = ""
    table.insert(ownedTasks, TaskManager:Connect(function(deltaTime: number): ()
        sessionFps += ((1 / math.max(deltaTime, 1 / 240)) - sessionFps) * 0.12
        overlayElapsed += deltaTime
        if overlayElapsed < 0.12 then
            return
        end
        overlayElapsed = 0
        local now: number = os.clock()
        local elapsed: number = math.max(0, math.floor(now - sessionStartedAt))

        if FloatingUi.overlays.SessionInfo.enabled then
            local role: string? = sessionStats.role
            if state.gameRoleProvider then
                local success: boolean, resolved: any = pcall(
                    state.gameRoleProvider,
                    LocalPlayer
                )
                if success and type(resolved) == "string" then
                    role = resolved
                end
            end
            local lines: {string} = {
                string.format(
                    "Injected  %02d:%02d:%02d",
                    math.floor(elapsed / 3600),
                    math.floor(elapsed / 60) % 60,
                    elapsed % 60
                ),
            }
            if sessionSettings.showDeaths then
                table.insert(lines, "Deaths    " .. tostring(sessionStats.deaths))
            end
            if sessionSettings.showWins then
                table.insert(lines, "Wins      " .. (sessionStats.winsAvailable and tostring(sessionStats.wins) or "N/A"))
                table.insert(lines, "Rounds    " .. (sessionStats.roundsAvailable and tostring(sessionStats.rounds) or "N/A"))
            end
            if sessionSettings.showRole then
                table.insert(lines, "Role      " .. tostring(role or "N/A"))
                table.insert(lines, "Team      " .. tostring(LocalPlayer.Team and LocalPlayer.Team.Name or "None"))
            end
            if sessionSettings.showPerformance then
                local ping: number? = getSessionPing()
                table.insert(lines, string.format("FPS       %.0f", math.clamp(sessionFps, 0, 999)))
                table.insert(lines, "Ping      " .. (ping and string.format("%.0f ms", ping) or "N/A"))
            end
            if sessionSettings.showServer then
                table.insert(lines, string.format("Players   %d/%d", #Players:GetPlayers(), Players.MaxPlayers))
                table.insert(lines, "Game      " .. tostring(state.activeGameName or "Universal"))
            end
            SessionText.Text = table.concat(lines, "\n")
        end

        if FloatingUi.overlays.TextGUI.enabled then
            local enabledFeatures: {any} = {}
            if not textGuiSettings.hideModules then
                for _, feature: any in ipairs(allFeatures) do
                    local lowerName: string = string.lower(feature.name)
                    local renderLike: boolean = string.find(lowerName, "esp", 1, true) ~= nil
                        or string.find(lowerName, "visual", 1, true) ~= nil
                        or string.find(lowerName, "x-ray", 1, true) ~= nil
                        or string.find(lowerName, "fov", 1, true) ~= nil
                        or string.find(lowerName, "fullbright", 1, true) ~= nil
                    if feature.enabled
                        and not feature.isCategory
                        and not feature.isAction
                        and (not textGuiSettings.hideRender or not renderLike) then
                        table.insert(enabledFeatures, feature)
                    end
                end
            end
            table.sort(enabledFeatures, function(left: any, right: any): boolean
                if textGuiSettings.sort == "Length" then
                    return #left.name > #right.name
                elseif textGuiSettings.sort == "Enabled order" then
                    return (left.enabledAt or 0) < (right.enabledAt or 0)
                elseif textGuiSettings.sort == "Section" then
                    local leftKey: string = left.sectionName .. left.name
                    local rightKey: string = right.sectionName .. right.name
                    return leftKey < rightKey
                end
                return string.lower(left.name) < string.lower(right.name)
            end)
            local textLines: {string} = {}
            if textGuiSettings.watermark then
                table.insert(textLines, "A Random Menu")
            end
            if textGuiSettings.customText ~= "" then
                table.insert(textLines, textGuiSettings.customText)
            end
            for _, feature: any in ipairs(enabledFeatures) do
                table.insert(textLines, feature.name)
            end
            if #textLines == 0 then
                table.insert(textLines, "No active modules")
            end
            local nextText: string = table.concat(textLines, "\n")
            if nextText ~= lastTextGuiText then
                lastTextGuiText = nextText
                TextGuiLabel.Text = nextText
                TextGuiShadow.Text = nextText
                if textGuiSettings.animations then
                    TextGuiLabel.TextTransparency = 0.5
                    TweenService:Create(TextGuiLabel, TweenInfo.new(0.2), {
                        TextTransparency = 0,
                    }):Play()
                end
            end
            TextGuiLabel.FontFace = getTextGuiFont()
            TextGuiShadow.FontFace = TextGuiLabel.FontFace
            TextGuiLabel.TextSize = math.round(14 * textGuiSettings.scale)
            TextGuiShadow.TextSize = TextGuiLabel.TextSize
            TextGuiShadow.Visible = textGuiSettings.shadow
            TextGuiBody.BackgroundColor3 = Theme.DefaultBackground
            TextGuiBody.BackgroundTransparency = textGuiSettings.background and 0.42 or 1
            local textWindowRoot: Frame = FloatingUi.overlays.TextGUI.window.root
            local textHeader: Frame? = textWindowRoot:FindFirstChild("Header") :: Frame?
            local textShade: Frame? = textWindowRoot:FindFirstChild("Readability") :: Frame?
            local textStroke: UIStroke? = textWindowRoot:FindFirstChildOfClass("UIStroke")
            if textHeader then textHeader.Visible = state.visible end
            if textShade then textShade.Visible = state.visible or textGuiSettings.background end
            if textStroke then textStroke.Transparency = state.visible and 0.38 or 1 end
            textWindowRoot.Active = state.visible
            textWindowRoot.BackgroundTransparency = state.visible and 0.08 or 1
            TextGuiBody.Position = state.visible and UDim2.fromOffset(0, 36)
                or UDim2.fromOffset(0, 0)
            TextGuiBody.Size = state.visible and UDim2.new(1, 0, 1, -36)
                or UDim2.fromScale(1, 1)
            local gradientEnabled: boolean = textGuiSettings.gradient
                or textGuiSettings.v4Gradient
                or textGuiSettings.colorMode == "Greyscale"
                or textGuiSettings.colorMode == "Rainbow"
            TextGuiGradient.Enabled = gradientEnabled
            if textGuiSettings.v4Gradient then
                TextGuiGradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Theme.DefaultAccent),
                    ColorSequenceKeypoint.new(0.34, Theme.AccentViolet),
                    ColorSequenceKeypoint.new(0.68, Theme.AccentPink),
                    ColorSequenceKeypoint.new(1, Theme.DefaultAccent),
                })
                TextGuiGradient.Rotation = (now * 45) % 360
            elseif textGuiSettings.colorMode == "Rainbow" then
                local hue: number = (now * 0.12) % 1
                TextGuiLabel.TextColor3 = Color3.fromHSV(hue, 0.72, 1)
                TextGuiGradient.Enabled = false
            elseif textGuiSettings.colorMode == "Greyscale" then
                local pulse: number = 0.72 + 0.28 * math.sin(now * 1.6)
                TextGuiLabel.TextColor3 = Color3.fromHSV(0, 0, pulse)
                TextGuiGradient.Enabled = false
            elseif textGuiSettings.colorMode == "Solid white" then
                TextGuiLabel.TextColor3 = Theme.AccentCyan
            elseif textGuiSettings.colorMode == "By section" then
                TextGuiLabel.TextColor3 = Theme.AccentViolet
            else
                TextGuiLabel.TextColor3 = Theme.DefaultAccent
                TextGuiGradient.Rotation = 90
            end
        end

        local targetInfoEnabled: boolean = FloatingUi.overlays.TargetInfo.enabled
        local localCharacter: Model? = LocalPlayer.Character
        local localRoot: BasePart? = localCharacter
            and localCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
        local camera: Camera? = workspace.CurrentCamera
        local selectedTarget: Player? = nil
        local targetRole: string? = nil
        local targetSource: string = "Nearest player"
        local targetAccent: Color3 = Theme.AccentViolet
        if targetInfoEnabled
            and targetSettings.mode == "Smart Priority"
            and state.gameTargetProvider then
            local success: boolean, snapshot: any = pcall(state.gameTargetProvider)
            if success then
                if typeof(snapshot) == "Instance" and snapshot:IsA("Player") then
                    selectedTarget = snapshot
                elseif type(snapshot) == "table"
                    and typeof(snapshot.player) == "Instance"
                    and snapshot.player:IsA("Player") then
                    selectedTarget = snapshot.player
                    targetRole = snapshot.role
                    targetSource = tostring(snapshot.source or "Game priority")
                    if typeof(snapshot.accent) == "Color3" then
                        targetAccent = snapshot.accent
                    end
                end
            end
        end
        if targetInfoEnabled and not selectedTarget and localRoot then
            local bestScore: number = math.huge
            local pointer: Vector2 = state.isMobile and getFloatingViewport() / 2
                or UserInputService:GetMouseLocation()
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local character: Model? = player.Character
                    local humanoid: Humanoid? = character
                        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                    local root: BasePart? = character
                        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if humanoid and humanoid.Health > 0 and root then
                        local distance: number = (root.Position - localRoot.Position).Magnitude
                        local score: number = distance
                        if targetSettings.mode ~= "Nearest distance" and camera then
                            local screenPoint: Vector3, visible: boolean =
                                camera:WorldToViewportPoint(root.Position)
                            score = visible and (Vector2.new(screenPoint.X, screenPoint.Y) - pointer).Magnitude
                                or math.huge
                        end
                        if score < bestScore then
                            bestScore = score
                            selectedTarget = player
                        end
                    end
                end
            end
            targetSource = targetSettings.mode
        end
        currentOverlayTarget = targetInfoEnabled and selectedTarget or nil
        if selectedTarget and state.gameRoleProvider and not targetRole then
            local success: boolean, role: any = pcall(state.gameRoleProvider, selectedTarget)
            targetRole = success and type(role) == "string" and role or nil
        end
        if targetRole then
            targetAccent = targetRole == "Murderer" and Theme.Danger
                or ((targetRole == "Sheriff" or targetRole == "Hero")
                    and Theme.AccentCyan
                    or Theme.Success)
        end
        if targetInfoEnabled then
            local targetCharacter: Model? = selectedTarget and selectedTarget.Character
            local targetHumanoid: Humanoid? = targetCharacter
                and targetCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
            local targetRoot: BasePart? = targetCharacter
                and targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
            if selectedTarget and targetHumanoid then
                local ratio: number = math.clamp(
                    targetHumanoid.Health / math.max(1, targetHumanoid.MaxHealth),
                    0,
                    1
                )
                local distance: number? = localRoot and targetRoot
                    and (targetRoot.Position - localRoot.Position).Magnitude
                    or nil
                TargetName.Text = selectedTarget.DisplayName .. "  @" .. selectedTarget.Name
                TargetRole.Text = tostring(targetRole or "Player") .. "  ·  " .. targetSource
                TargetRole.TextColor3 = targetAccent
                TargetDetails.Text = string.format(
                    "Health %.0f / %.0f%s",
                    targetHumanoid.Health,
                    targetHumanoid.MaxHealth,
                    targetSettings.showDistance and distance
                        and string.format("  ·  %.0f studs", distance)
                        or ""
                )
                TargetHealthTrack.Visible = targetSettings.showHealth
                TargetHealthFill.Size = UDim2.fromScale(ratio, 1)
                TargetHealthFill.BackgroundColor3 = ratio > 0.5
                    and Theme.AccentCyan
                    or (ratio > 0.25 and Theme.AccentViolet or Theme.AccentPink)
                TargetPortraitFrame.Visible = targetSettings.showAvatar
                requestTargetThumbnail(selectedTarget)
            else
                TargetName.Text = "No target"
                TargetRole.Text = "No priority target"
                TargetDetails.Text = "Waiting for a valid player"
                TargetHealthFill.Size = UDim2.fromScale(0, 1)
                TargetHealthTrack.Visible = targetSettings.showHealth
                TargetPortraitFrame.Visible = targetSettings.showAvatar
                requestTargetThumbnail(nil)
            end
        end

        if FloatingUi.overlays.Radar.enabled then
            local radarSize: number = radarSettings.size
            RadarSurface.Size = UDim2.fromOffset(radarSize, radarSize)
            -- The window is the circle: no padding for a header that no longer
            -- exists, no square plate around it.
            local radarWindow: FloatingWindowRecord = FloatingUi.overlays.Radar.window
            local nextRadarSize: UDim2 = UDim2.fromOffset(radarSize, radarSize)
            if radarWindow.root.Size ~= nextRadarSize then
                radarWindow.root.Size = nextRadarSize
                FloatingUi.reclamp()
            end
            for _, axis: Frame in ipairs(radarAxes) do axis.Visible = radarSettings.grid end
            for _, ring: Frame in ipairs(radarRings) do ring.Visible = radarSettings.rings end
            RadarNorth.Visible = radarSettings.rotation == "North"
            local activePlayers: {[Player]: boolean} = {}
            local basis: CFrame? = localRoot and localRoot.CFrame or nil
            if localRoot and radarSettings.rotation == "Camera" and camera then
                local look: Vector3 = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
                if look.Magnitude > 0.01 then
                    basis = CFrame.lookAt(localRoot.Position, localRoot.Position + look.Unit)
                end
            elseif localRoot and radarSettings.rotation == "North" then
                basis = CFrame.new(localRoot.Position)
            end
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and localRoot and basis then
                    local character: Model? = player.Character
                    local humanoid: Humanoid? = character
                        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                    local targetRoot: BasePart? = character
                        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    local sameTeam: boolean = LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
                    local allowed: boolean = targetRoot ~= nil
                        and (not radarSettings.aliveOnly or (humanoid ~= nil and humanoid.Health > 0))
                        and (radarSettings.showTeam or not sameTeam)
                    if allowed and targetRoot then
                        local relative: Vector3 = (basis :: CFrame):PointToObjectSpace(targetRoot.Position)
                        local distance: number = Vector2.new(relative.X, relative.Z).Magnitude
                        if distance <= radarSettings.range or radarSettings.outOfRange == "Clamp" then
                            activePlayers[player] = true
                            local record: any = radarBlips[player]
                            if not record then
                                local blip: Frame = create("Frame", {
                                    Parent = RadarSurface,
                                    AnchorPoint = Vector2.new(0.5, 0.5),
                                    BackgroundColor3 = Theme.AccentPink,
                                    BorderSizePixel = 0,
                                    Size = UDim2.fromOffset(7, 7),
                                }) :: Frame
                                blip:SetAttribute("FloatingDepth", 4)
                                create("UICorner", {Parent = blip, CornerRadius = UDim.new(1, 0)})
                                local targetRing: UIStroke = create("UIStroke", {
                                    Parent = blip,
                                    Color = Theme.AccentCyan,
                                    Transparency = 1,
                                    Thickness = 2,
                                }) :: UIStroke
                                local label: TextLabel = makeTextLabel(blip, "", 7)
                                label.AnchorPoint = Vector2.new(0.5, 0)
                                label.Position = UDim2.new(0.5, 0, 1, 3)
                                label.Size = UDim2.fromOffset(100, 18)
                                label.TextColor3 = Theme.DefaultText
                                label.TextXAlignment = Enum.TextXAlignment.Center
                                record = {blip = blip, label = label, ring = targetRing}
                                radarBlips[player] = record
                            end
                            local radius: number = radarSize / 2 - 12
                            local offset: Vector2 = Vector2.new(relative.X, relative.Z)
                                * (radius / radarSettings.range)
                            if offset.Magnitude > radius then offset = offset.Unit * radius end
                            record.blip.Position = UDim2.fromOffset(
                                radarSize / 2 + offset.X,
                                radarSize / 2 + offset.Y
                            )
                            local role: string? = nil
                            if state.gameRoleProvider then
                                local roleOk: boolean, roleValue: any = pcall(state.gameRoleProvider, player)
                                role = roleOk and type(roleValue) == "string" and roleValue or nil
                            end
                            local color: Color3 = Theme.AccentPink
                            if radarSettings.colorMode == "Health" and humanoid then
                                local healthRatio: number = humanoid.Health / math.max(1, humanoid.MaxHealth)
                                color = Color3.fromHSV(healthRatio * 0.34, 0.8, 1)
                            elseif radarSettings.colorMode == "Team" or radarSettings.colorMode == "Smart" then
                                color = sameTeam and Theme.Success or Theme.Danger
                            end
                            if (radarSettings.colorMode == "MM2 role" or radarSettings.colorMode == "Smart") and role then
                                color = role == "Murderer" and Theme.Danger
                                    or ((role == "Sheriff" or role == "Hero") and Theme.AccentCyan
                                        or Theme.Success)
                            elseif radarSettings.colorMode == "Spectrum" then
                                color = Color3.fromHSV((now * 0.1 + player.UserId % 10 / 10) % 1, 0.7, 1)
                            end
                            record.blip.BackgroundColor3 = color
                            record.ring.Transparency = player == currentOverlayTarget and 0 or 1
                            record.blip.Size = UDim2.fromOffset(
                                player == currentOverlayTarget and 10 or 7,
                                player == currentOverlayTarget and 10 or 7
                            )
                            record.label.Visible = radarSettings.showNames or radarSettings.showDistance
                            record.label.Text = (radarSettings.showNames and player.DisplayName or "")
                                .. (radarSettings.showDistance and string.format(" %.0f", distance) or "")
                        end
                    end
                end
            end
            for player: Player, record: any in pairs(radarBlips) do
                if not activePlayers[player] then
                    record.blip:Destroy()
                    radarBlips[player] = nil
                end
            end
        end
    end))


    -- ---------------------------------------------------------------------------
    -- Player card
    -- ---------------------------------------------------------------------------
    --
    -- Who is running the menu, docked at the foot of the rail: the account's own
    -- avatar, its display name and handle, and how long this account has been
    -- using the menu. The "since" date and the session count are stored in the
    -- config file, so they survive rejoins; the session clock restarts with the
    -- injection.
    --
    -- The avatar comes from `rbxthumb://`, which the engine resolves itself — no
    -- download, no executor file API, and it works on the first frame.
    do
    (function(): ()
    local profileKey: string = "profile." .. tostring(LocalPlayer.UserId)
    local storedFirstSeen: number? = tonumber(configData.values[profileKey .. ".firstSeen"])
    local firstSeen: number = storedFirstSeen or os.time()
    local sessions: number =
        (tonumber(configData.values[profileKey .. ".sessions"]) or 0) + 1
    configData.values[profileKey .. ".firstSeen"] = firstSeen
    configData.values[profileKey .. ".sessions"] = sessions
    queueConfigSave()
    local sessionStart: number = os.clock()

    local ProfileCard: Frame = create("Frame", {
        Parent = state.shells.defaultSidebar,
        Name = "PlayerCard",
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 1, -(state.layout.launcherHeight + 14)),
        Size = UDim2.new(1, -(state.layout.sidebarPadding * 2), 0, PROFILE_CARD_HEIGHT - 8),
        ZIndex = 24,
    }) :: Frame
    create("UICorner", {
        Parent = ProfileCard,
        CornerRadius = cornerRadius(UI_RADIUS.control),
    })
    create("UIStroke", {
        Parent = ProfileCard,
        Color = Theme.DefaultOutline,
        Transparency = 0.68,
        Thickness = 1,
    })

    local ProfileBanner: ImageLabel = create("ImageLabel", {
        Parent = ProfileCard,
        Name = "Banner",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        ImageTransparency = 0.35,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 24,
    }) :: ImageLabel
    create("UICorner", {
        Parent = ProfileBanner,
        CornerRadius = cornerRadius(UI_RADIUS.control),
    })
    if state.applyAssetImage then
        state.applyAssetImage("profileBanner", ProfileBanner)
    end

    local Avatar: ImageLabel = create("ImageLabel", {
        Parent = ProfileCard,
        Name = "Avatar",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id="
            .. tostring(LocalPlayer.UserId)
            .. "&w=150&h=150",
        Position = UDim2.new(0, 6, 0.5, 0),
        Size = UDim2.fromOffset(34, 34),
        ZIndex = 25,
    }) :: ImageLabel
    -- No plate and no ring: the head shot already arrives inside a circle, and a
    -- frame behind it only showed up as a grey square in the corners.

    local ProfileName: TextLabel =
        (makeTextLabel(ProfileCard, LocalPlayer.DisplayName, 11) :: any) :: TextLabel
    ProfileName.Name = "DisplayName"
    ProfileName.FontFace = CONTROL_FONT
    ProfileName.Position = UDim2.fromOffset(46, 3)
    ProfileName.Size = UDim2.new(1, -52, 0, 21)
    ProfileName.TextColor3 = Theme.DefaultText
    ProfileName.TextTruncate = Enum.TextTruncate.AtEnd
    ProfileName.ZIndex = 25

    local ProfileHandle: TextLabel =
        (makeTextLabel(ProfileCard, "@" .. LocalPlayer.Name, 9) :: any) :: TextLabel
    ProfileHandle.Name = "Handle"
    ProfileHandle.Position = UDim2.fromOffset(46, 25)
    ProfileHandle.Size = UDim2.new(1, -52, 0, 18)
    ProfileHandle.TextColor3 = Theme.DefaultTextMuted
    ProfileHandle.TextTruncate = Enum.TextTruncate.AtEnd
    ProfileHandle.ZIndex = 25

    local ProfileMeta: TextLabel = (makeTextLabel(ProfileCard, "", 9) :: any) :: TextLabel
    ProfileMeta.Name = "Meta"
    ProfileMeta.Position = UDim2.fromOffset(46, 43)
    ProfileMeta.Size = UDim2.new(1, -52, 0, 18)
    ProfileMeta.TextColor3 = Theme.DefaultTextMuted
    ProfileMeta.TextTruncate = Enum.TextTruncate.AtEnd
    ProfileMeta.ZIndex = 25

    local function describeSession(): string
        local minutes: number = math.floor((os.clock() - sessionStart) / 60)
        if minutes < 60 then
            return tostring(minutes) .. "m"
        end
        return tostring(math.floor(minutes / 60)) .. "h " .. tostring(minutes % 60) .. "m"
    end

    local function refreshMeta(): ()
        ProfileMeta.Text = os.date("!%d/%m/%Y", firstSeen)
            .. "  ·  "
            .. tostring(sessions)
            .. (sessions == 1 and " sesión" or " sesiones")
            .. "  ·  "
            .. describeSession()
    end
    refreshMeta()

    -- Once a minute is enough for a clock measured in minutes, and it keeps the
    -- card off the per-frame budget.
    local metaClock: number = 0
    table.insert(ownedTasks, TaskManager:Connect(function(deltaTime: number): ()
        metaClock += deltaTime
        if metaClock < 30 then
            return
        end
        metaClock = 0
        refreshMeta()
    end))

    local function applyProfileLayout(metrics: LayoutMetrics): ()
        ProfileCard.Position = UDim2.new(0.5, 0, 1, -(metrics.launcherHeight + 14))
        ProfileCard.Size = metrics.sidebarCollapsed
            and UDim2.fromOffset(40, 40)
            or UDim2.new(1, -(metrics.sidebarPadding * 2), 0, PROFILE_CARD_HEIGHT - 8)
        -- Collapsed rail: the avatar is the card.
        Avatar.AnchorPoint = metrics.sidebarCollapsed
            and Vector2.new(0.5, 0.5)
            or Vector2.new(0, 0.5)
        Avatar.Position = metrics.sidebarCollapsed
            and UDim2.fromScale(0.5, 0.5)
            or UDim2.new(0, 6, 0.5, 0)
        ProfileName.Visible = not metrics.sidebarCollapsed
        ProfileHandle.Visible = not metrics.sidebarCollapsed
        ProfileMeta.Visible = not metrics.sidebarCollapsed
        ProfileBanner.Visible = not metrics.sidebarCollapsed
    end
    applyProfileLayout(state.layout)
    state.onLayout(applyProfileLayout)
    end)()
    end
    -- Launchers for the movable tool windows, docked at the foot of the rail.
    -- They stack vertically when the rail collapses, which is the only way two
    -- 32px buttons fit inside a 58px icon rail.
    local FloatingButtons: Frame = create("Frame", {
        Parent = state.shells.defaultSidebar,
        Name = "FloatingWindowButtons",
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 1, -8),
        Size = UDim2.fromOffset(
            state.layout.sidebarCollapsed and 34 or 72,
            state.layout.launcherHeight
        ),
        ZIndex = 24,
    }) :: Frame
    create("UICorner", {
        Parent = FloatingButtons,
        CornerRadius = cornerRadius(UI_RADIUS.control),
    })
    create("UIStroke", {
        Parent = FloatingButtons,
        Color = Theme.DefaultOutline,
        Transparency = 0.62,
    })
    local FloatingButtonsLayout: UIListLayout = create("UIListLayout", {
        Parent = FloatingButtons,
        FillDirection = state.layout.sidebarCollapsed
            and Enum.FillDirection.Vertical
            or Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 2),
    }) :: UIListLayout

    local function createFloatingLauncher(
        name: string,
        fallbackText: string,
        callback: () -> (),
        iconAsset: string?
    ): TextButton
        local button: TextButton = makeButton(FloatingButtons, fallbackText, 8)
        button.Name = name
        button.BackgroundTransparency = 1
        button.Size = UDim2.fromOffset(30, 24)
        button.ZIndex = 25
        button:SetAttribute("ThemeRole", "Icon")
        local stroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
        if stroke then
            stroke.Enabled = false
        end
        -- The three-letter labels were placeholders. The icon replaces the text
        -- once it resolves, and the text stays put if it never does.
        if iconAsset and state.applyAssetImage then
            local icon: ImageLabel = create("ImageLabel", {
                Parent = button,
                Name = "Icon",
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Image = "",
                ImageTransparency = 0.12,
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(18, 18),
                ZIndex = 26,
            }) :: ImageLabel
            create("UICorner", {Parent = icon, CornerRadius = cornerRadius(UI_RADIUS.chip)})
            state.applyAssetImage(iconAsset, icon, function(): ()
                button.Text = ""
            end)
        end
        trackUiConnection(button.MouseButton1Click:Connect(callback))
        return button
    end

    state.onLayout(function(metrics: LayoutMetrics): ()
        FloatingButtons.Size = UDim2.fromOffset(
            metrics.sidebarCollapsed and 34 or 72,
            metrics.launcherHeight
        )
        FloatingButtonsLayout.FillDirection = metrics.sidebarCollapsed
            and Enum.FillDirection.Vertical
            or Enum.FillDirection.Horizontal
    end)

    createFloatingLauncher("Favorites", "FAV", function(): ()
        FavoritesWindow.root.Visible = not FavoritesWindow.root.Visible
        configData.ui.favoritesWindowOpen = FavoritesWindow.root.Visible
        if FavoritesWindow.root.Visible then
            refreshFavorites()
            bringFloatingToFront(FavoritesWindow)
        end
        queueConfigSave()
    end, "windowFavorites")
    createFloatingLauncher("Overlays", "OVR", function(): ()
        OverlayMenu.root.Visible = not OverlayMenu.root.Visible
        configData.ui.overlayMenuOpen = OverlayMenu.root.Visible
        if OverlayMenu.root.Visible then
            bringFloatingToFront(OverlayMenu)
        end
        queueConfigSave()
    end, "windowOverlays")

    FavoritesWindow.root.Visible = configData.ui.favoritesWindowOpen == true
    OverlayMenu.root.Visible = configData.ui.overlayMenuOpen == true
    for overlayId: string, overlay: any in pairs(FloatingUi.overlays) do
        setOverlayEnabled(overlayId, configData.ui.overlays[overlayId] == true)
    end
    refreshFavorites()

    activeCleanup = function(): ()
        for _, handle: any in ipairs(ownedTasks) do
            if handle and handle.Disconnect then
                handle:Disconnect()
            end
        end
        table.clear(ownedTasks)
        if type(state.destroySessionTracking) == "function" then
            state.destroySessionTracking()
        end
    end
    Module.Initialized = true
    return state.floatingUi
end

-- The windows themselves need no teardown: each is a child of the ScreenGui
-- the shell destroys. The two per-frame loops do.
function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
