--!strict
--
-- Settings page.
--
-- The Config. tab: interface scale and typeface, blur, animations, the toggle
-- key, re-inject and destruct, the detected game, and the mobile action size.
--
-- It lived in `ARandomMenu.luau` as one eight-hundred-line function, which is
-- how a shell stops being a shell. Nothing in it is shell logic — it is a page
-- of controls, exactly like a module's panel, and the only reason it was in
-- the main file is that it was written before there was anywhere else to put
-- it.
--
-- The page is built on demand: `SectionManager` calls `build` the first time
-- the Config. tab is opened, and everything below runs then, not at startup.

export type SettingsPage = {
    build: () -> (),
}

local Module = {
    Name = "SettingsPage",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

function Module.init(context: any): SettingsPage
    local host: any = context
    local state: any = host.state
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local create: any = host.create
    local makeButton: any = host.makeButton
    local makeTextBox: any = host.makeTextBox
    local makeTextLabel: any = host.makeTextLabel
    local notify: any = host.notify
    local Theme: any = host.Theme
    local CONTROL_FONT: any = host.CONTROL_FONT
    local ScreenGui: any = host.ScreenGui
    local TweenService: any = host.TweenService
    local UserInputService: any = host.UserInputService
    local UI_RADIUS: any = host.UI_RADIUS
    local UI_MOTION: any = host.UI_MOTION
    local cornerRadius: any = host.cornerRadius
    local trackUiConnection: any = host.trackUiConnection
    local applyKeySlotStyle: any = host.applyKeySlotStyle
    local setKeySlotCapture: any = host.setKeySlotCapture
    local GAME_CHECK: any = host.GAME_CHECK
    -- The page frame the shell already created for this tab, and the helper
    -- that files a row into the right column of a card grid. Both belong to
    -- the shell's layout engine; the page only fills what it is given.
    local SettingsPage: any = host.SettingsPage
    local getFeatureCardParent: any = host.getFeatureCardParent
    -- Where the runtime came from, so the page can show it and re-inject it.
    local REPOSITORY_RAW_BASE: any = host.REPOSITORY_RAW_BASE
    local RUNTIME_SAFETY_SOURCE_URL: any = host.RUNTIME_SAFETY_SOURCE_URL
    local RUNTIME_COMPATIBILITY_MARKER: any = host.RUNTIME_COMPATIBILITY_MARKER
    local SOURCE_STAMP: any = host.SOURCE_STAMP
    -- Text scale bounds, shared with the shell so the slider cannot offer a
    -- size the rest of the interface refuses to render.
    local TEXT_BASE_MULTIPLIER: any = host.TEXT_BASE_MULTIPLIER
    local TEXT_SCALE_MINIMUM: any = host.TEXT_SCALE_MINIMUM
    local TEXT_SCALE_MAXIMUM: any = host.TEXT_SCALE_MAXIMUM
    -- Every label the shell has registered for scaling. The page owns the
    -- slider, so it is the thing that walks the list when the scale changes.
    local registeredText: any = host.registeredText

    local function build(): ()
        state.settingRows = {} :: {Frame}
        local SettingsScroll = create("ScrollingFrame", {
            Parent = SettingsPage,
            Name = "SettingsScroll",
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, 0),
            ScrollBarImageColor3 = Theme.DefaultOutline,
            ScrollBarThickness = 6,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Size = UDim2.fromScale(1, 1),
        })
        -- Setting rows are label + control across their full width, so this page is
        -- never split into two narrow columns no matter how wide the shell gets.
        SettingsScroll:SetAttribute("CardGridSingleColumn", true)

        create("UIPadding", {
            Parent = SettingsScroll,
            PaddingBottom = UDim.new(0, 18),
            PaddingLeft = UDim.new(0, 18),
            PaddingRight = UDim.new(0, 18),
            PaddingTop = UDim.new(0, 18),
        })

        local _SettingsLayout = create("UIListLayout", {
            Parent = SettingsScroll,
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 10),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        -- Settings rows.
        --
        -- A row is one line: its name, vertically centred on the left, and its
        -- control on the right. The explanatory second line every row used to carry
        -- was removed — the names say what they do and the descriptions only made the
        -- page twice as tall. `descriptionText` is still accepted so every existing
        -- call site (and any game module) keeps working; it is simply not rendered.
        local function createSettingRow(
            titleText: string,
            _descriptionText: string,
            height: number?
        ): (Frame, Frame)
            local rowHeight: number = height or math.max(38, state.layout.cardHeight)
            local row = create("Frame", {
                Parent = getFeatureCardParent(SettingsScroll),
                Name = "Setting_" .. titleText:gsub("%W", ""),
                BackgroundColor3 = state.guiStyle == "Default"
                    and Theme.DefaultSurface
                    or Theme.Surface,
                BackgroundTransparency = state.guiStyle == "Default" and 0.58 or 0,
                BorderSizePixel = 0,
                Size = UDim2.new(1, -2, 0, rowHeight),
            })

            local title = makeTextLabel(row, titleText, 12)
            title.Name = "SettingTitle"
            title.FontFace = CONTROL_FONT
            title.AnchorPoint = Vector2.new(0, 0.5)
            title.Position = UDim2.new(0, 14, 0.5, 0)
            title.Size = UDim2.new(0.46, -14, 1, 0)
            title.TextTruncate = Enum.TextTruncate.AtEnd
            title.TextYAlignment = Enum.TextYAlignment.Center

            local control = create("Frame", {
                Parent = row,
                Name = "SettingControl",
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0.5, 6, 0.5, 0),
                Size = UDim2.new(0.5, -18, 1, -12),
            })

            create("UICorner", {
                Parent = row,
                CornerRadius = cornerRadius(UI_RADIUS.card),
            })
            create("UIStroke", {
                Parent = row,
                Name = "SettingStroke",
                Color = state.guiStyle == "Default"
                    and Theme.DefaultOutline
                    or Theme.Outline,
                Transparency = state.guiStyle == "Default" and 0.82 or 0.28,
                Thickness = 1,
            })
            table.insert(state.settingRows, row)
            return (row :: any) :: Frame, (control :: any) :: Frame
        end

        -- Switch-free toggle rows.
        --
        -- Blur mode and Interface motion used to carry a switch control. They now
        -- behave exactly like a module card: the whole row is the button, a click
        -- flips it, and the state is read from the row itself (accent stripe, brighter
        -- surface and an ON/OFF caption) instead of from a separate widget.
        state.settingRowRepaint = setmetatable({}, {__mode = "k"}) :: any

        local function makeToggleSettingRow(
            row: Frame,
            _control: Frame,
            enabled: boolean,
            onToggle: (boolean) -> ()
        ): ()
            row:SetAttribute("ToggleRow", true)
            local title: TextLabel = row:FindFirstChild("SettingTitle") :: TextLabel
            local stripe: Frame = create("Frame", {
                Parent = row,
                Name = "ActiveStripe",
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = Theme.DefaultAccent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.new(0, 2, 1, -14),
                ZIndex = 3,
            }) :: Frame
            create("UICorner", {Parent = stripe, CornerRadius = UDim.new(1, 0)})

            local activation: TextButton = create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                ClipsDescendants = true,
                Parent = row,
                Name = "ActivationTarget",
                Active = true,
                AutoButtonColor = false,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1),
                Text = "",
                ZIndex = 4,
            }) :: TextButton

            local current: boolean = enabled
            local function paint(): ()
                -- Kept in sync from one place: clicks, restyles and external state
                -- changes all end up here.
                row.BackgroundColor3 = current
                    and Theme.DefaultSurfaceHover
                    or Theme.DefaultSurface
                row.BackgroundTransparency = current and 0.42 or 0.58
                stripe.BackgroundTransparency = current and 0 or 1
                -- No ON/OFF caption: the accent stripe and the lit surface are the
                -- state, exactly like a module card.
                title.TextColor3 = current and Theme.DefaultText or Theme.DefaultTextMuted
            end
            paint()
            state.settingRowRepaint[row] = paint

            trackUiConnection(activation.MouseButton1Click:Connect(function(): ()
                current = not current
                paint()
                onToggle(current)
            end))
            trackUiConnection(row.MouseEnter:Connect(function(): ()
                TweenService:Create(
                    row,
                    TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    {BackgroundTransparency = current and 0.34 or 0.46}
                ):Play()
            end))
            trackUiConnection(row.MouseLeave:Connect(function(): ()
                TweenService:Create(
                    row,
                    TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    {BackgroundTransparency = current and 0.42 or 0.58}
                ):Play()
            end))

            -- No setter is returned. It used to hand one back "so an external
            -- change could push the row back in sync", and for both rows that
            -- used this the only consumer was a `state.` publication nothing
            -- ever read: blur and motion are changed from these rows and
            -- nowhere else. When something does change them elsewhere, this is
            -- where the setter comes back.
        end

        state.restyleSettings = function(isDefault: boolean): ()
            SettingsScroll.ScrollBarImageColor3 = isDefault
                and Theme.DefaultOutline
                or Color3.fromRGB(100, 100, 100)
            for _, row: Frame in ipairs(state.settingRows) do
                -- Click-to-toggle rows paint their own surface from their state; a
                -- restyle must not reset an enabled row back to the idle colour.
                local repaint: any = row:GetAttribute("ToggleRow") == true
                    and state.settingRowRepaint
                    and state.settingRowRepaint[row]
                if repaint then
                    repaint()
                else
                    row.BackgroundColor3 = isDefault and Theme.DefaultSurface or Theme.Surface
                    row.BackgroundTransparency = isDefault and 0.58 or 0
                end
                local rowStroke: UIStroke? = row:FindFirstChild("SettingStroke") :: UIStroke?
                if rowStroke then
                    rowStroke.Color = isDefault and Theme.DefaultOutline or Theme.Outline
                    rowStroke.Transparency = isDefault and 0.82 or 0.28
                end
            end
        end

        local textRow, textControl = createSettingRow(
            "Text size",
            "Drag the linear control to scale every label"
        )
        textRow.LayoutOrder = 1
        local textScaleRatio: number = (state.textScale - TEXT_SCALE_MINIMUM)
            / (TEXT_SCALE_MAXIMUM - TEXT_SCALE_MINIMUM)
        local TextSizeTrack: TextButton = create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClipsDescendants = true,
            Parent = textControl,
            Name = "TextSizeTrack",
            Active = true,
            AutoButtonColor = false,
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = state.guiStyle == "Default"
                and Theme.DefaultButtonPressed
                or Color3.fromRGB(45, 45, 49),
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(1, -58, 0, 4),
            Text = "",
        }) :: TextButton
        create("UICorner", {
            Parent = TextSizeTrack,
            CornerRadius = UDim.new(1, 0),
        })
        local TextSizeFill: Frame = create("Frame", {
            Parent = TextSizeTrack,
            Name = "Fill",
            BackgroundColor3 = state.guiStyle == "Default"
                and Theme.DefaultButtonHover
                or Color3.fromRGB(238, 238, 242),
            BorderSizePixel = 0,
            Size = UDim2.fromScale(textScaleRatio, 1),
        }) :: Frame
        create("UICorner", {
            Parent = TextSizeFill,
            CornerRadius = UDim.new(1, 0),
        })
        local TextSizeKnob: Frame = create("Frame", {
            Parent = TextSizeTrack,
            Name = "Knob",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = state.guiStyle == "Default"
                and Theme.DefaultText
                or Color3.fromRGB(250, 250, 252),
            BorderSizePixel = 0,
            Position = UDim2.fromScale(textScaleRatio, 0.5),
            Size = UDim2.fromOffset(14, 14),
            ZIndex = TextSizeTrack.ZIndex + 2,
        }) :: Frame
        create("UICorner", {
            Parent = TextSizeKnob,
            CornerRadius = UDim.new(1, 0),
        })
        create("UIStroke", {
            Parent = TextSizeKnob,
            Color = Theme.DefaultOutline,
            Transparency = 0.55,
            Thickness = 1,
        })
        local baseRestyleSettings: (boolean) -> () = state.restyleSettings
        state.restyleSettings = function(isDefault: boolean): ()
            baseRestyleSettings(isDefault)
            TextSizeTrack.BackgroundColor3 = isDefault
                and Theme.DefaultButtonPressed
                or Color3.fromRGB(45, 45, 49)
            TextSizeFill.BackgroundColor3 = isDefault
                and Theme.DefaultButtonHover
                or Color3.fromRGB(238, 238, 242)
            TextSizeKnob.BackgroundColor3 = isDefault
                and Theme.DefaultText
                or Color3.fromRGB(250, 250, 252)
        end
        local TextSizeValue: TextLabel = makeTextLabel(
            textControl,
            tostring(math.round(state.textScale * 100)) .. "%",
            11
        ) :: TextLabel
        TextSizeValue.AnchorPoint = Vector2.new(1, 0.5)
        TextSizeValue.Position = UDim2.new(1, 0, 0.5, 0)
        TextSizeValue.Size = UDim2.fromOffset(48, 22)
        TextSizeValue.TextXAlignment = Enum.TextXAlignment.Right

        -- Typeface picker.
        --
        -- Every face the client ships plus the three the repository carries, including
        -- a Minecraft-shaped one. Picking here rebuilds the menu's three weights from
        -- the chosen family and repaints every label already on screen.
        local fontRow, fontControl = createSettingRow(
            "Interface font",
            "Choose the typeface the whole menu is drawn in"
        )
        fontRow.LayoutOrder = 2
        local fontNames: {string} = state.listInterfaceFonts()
        local currentFontName: string = tostring(
            configData.values.interfaceFont or "Menu default"
        )
        local currentFontIndex: number = table.find(fontNames, currentFontName) or 1
        local FontButton: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClipsDescendants = true,
            Parent = fontControl,
            Name = "FontChoice",
            Active = true,
            AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor3 = Theme.DefaultButton,
            BackgroundTransparency = 0.25,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(1, -6, 0, 26),
            Text = fontNames[currentFontIndex],
            TextColor3 = Theme.DefaultText,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }) :: any) :: TextButton
        create("UICorner", {
            Parent = FontButton,
            CornerRadius = cornerRadius(UI_RADIUS.chip),
        })
        create("UIPadding", {
            Parent = FontButton,
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        })
        trackUiConnection(FontButton.MouseButton1Click:Connect(function(): ()
            state.openChoiceList(FontButton, fontNames, currentFontIndex, function(picked: number): ()
                currentFontIndex = picked
                FontButton.Text = fontNames[picked]
                -- A repository font has to be downloaded before it can be applied, so
                -- the switch happens off the input thread.
                task.spawn(function(): ()
                    state.applyInterfaceFont(fontNames[picked])
                end)
            end)
        end))

        local blurRow, blurControl = createSettingRow(
            "Blur mode",
            "Blur the game while the menu is visible"
        )
        blurRow.LayoutOrder = 3

        -- No switch: the row is the button, exactly like a module card.
        makeToggleSettingRow(
            blurRow,
            blurControl,
            state.blurEnabled,
            function(enabled: boolean): ()
                state.blurEnabled = enabled
                state.setBlurVisible(true)
                configData.ui.blurEnabled = enabled
                queueConfigSave()
                notify(enabled and "Blur mode enabled" or "Blur mode disabled")
            end
        )

        local motionRow, motionControl = createSettingRow(
            "Interface motion",
            "Smooth transitions for cards, tabs, and menu controls"
        )
        motionRow.LayoutOrder = 4
        makeToggleSettingRow(
            motionRow,
            motionControl,
            state.animationsEnabled,
            function(enabled: boolean): ()
                state.animationsEnabled = enabled
                configData.ui.animationsEnabled = enabled
                -- The hail is motion too, so it must follow this row immediately.
                if state.refreshBlurDecoration then
                    pcall(state.refreshBlurDecoration)
                end
                queueConfigSave()
                notify(enabled and "Interface motion enabled" or "Interface motion disabled")
            end
        )

        -- Menu key: keyboard-only. A touch client has no key to bind and reaches the
        -- menu through its floating button, so the row is not built there at all.
        local keyRow, keyControl = createSettingRow(
            "Menu key",
            "Choose the key used to show or hide"
        )
        keyRow.LayoutOrder = 5
        keyRow.Visible = not UserInputService.TouchEnabled

        local KeybindButton = makeButton(keyControl, state.toggleKey.Name, 13)
        KeybindButton.Size = UDim2.fromScale(1, 1)
        applyKeySlotStyle(KeybindButton)
        state.keybindButton = KeybindButton

        local reinjectRow, reinjectControl = createSettingRow(
            "Reinject latest",
            "Download and restart the newest main build"
        )
        reinjectRow.LayoutOrder = 5
        local ReinjectButton: TextButton = makeButton(
            reinjectControl,
            "REINJECT LATEST",
            12
        )
        ReinjectButton.Size = UDim2.fromScale(1, 1)

        local destructRow, destructControl = createSettingRow(
            "Destruct",
            "Disable every function and completely remove the menu from this client"
        )
        destructRow.LayoutOrder = 6
        local DestructButton: TextButton = makeButton(
            destructControl,
            "DESTRUCT",
            12
        )
        DestructButton.Size = UDim2.fromScale(1, 1)

        local gameRow, gameControl = createSettingRow(
            "Game check",
            "Only the matching game-specific module is loaded"
        )
        gameRow.LayoutOrder = 7
        -- Shows *how* the game was recognised, which is what tells you a clone was
        -- matched by its structure rather than by its PlaceId.
        local gameStatus = makeTextLabel(
            gameControl,
            (GAME_CHECK.MM2Active and "MM2"
                or GAME_CHECK.TRSActive and "TRS"
                or GAME_CHECK.VDActive and "VD"
                or GAME_CHECK.MVSDActive and "MVSD"
                or GAME_CHECK.BedFightActive and "BedFight"
                or "Universal only")
                .. " · "
                .. (GAME_CHECK.source == "PlaceId"
                    and tostring(game.PlaceId)
                    or GAME_CHECK.source),
            12
        )
        gameStatus.TextXAlignment = Enum.TextXAlignment.Center
        gameStatus.Size = UDim2.fromScale(1, 1)

        -- Mobile action size.
        --
        -- The only mobile row left. "Mobile menu icon" always said ON - REQUIRED and
        -- could not be changed, and "Mobile action buttons" only offered a reset that
        -- holding a button already does, so both were noise. The size is a real value
        -- now instead of a four-step preset cycle: type it, or drag the slider.
        local mobileSizeRow, mobileSizeControl = createSettingRow(
            "Mobile action size",
            "Exact pixel size for placed mobile shortcuts"
        )
        mobileSizeRow.LayoutOrder = 8
        mobileSizeRow.Visible = UserInputService.TouchEnabled

        local MobileSizeTrack: TextButton = create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClipsDescendants = true,
            Parent = mobileSizeControl,
            Name = "MobileSizeTrack",
            Active = true,
            AutoButtonColor = false,
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = Theme.DefaultButtonPressed,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(1, -62, 0, 4),
            Text = "",
        }) :: TextButton
        create("UICorner", {Parent = MobileSizeTrack, CornerRadius = UDim.new(1, 0)})
        local MobileSizeFill: Frame = create("Frame", {
            Parent = MobileSizeTrack,
            Name = "Fill",
            BackgroundColor3 = Theme.DefaultButtonHover,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(0, 1),
        }) :: Frame
        create("UICorner", {Parent = MobileSizeFill, CornerRadius = UDim.new(1, 0)})
        local MobileSizeKnob: Frame = create("Frame", {
            Parent = MobileSizeTrack,
            Name = "Knob",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.DefaultText,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.fromOffset(14, 14),
            ZIndex = 3,
        }) :: Frame
        create("UICorner", {Parent = MobileSizeKnob, CornerRadius = UDim.new(1, 0)})
        local MobileSizeInput: TextBox = makeTextBox(
            mobileSizeControl,
            tostring(state.mobileButtonSize)
        )
        MobileSizeInput.Name = "MobileSizeValue"
        MobileSizeInput.AnchorPoint = Vector2.new(1, 0.5)
        MobileSizeInput.Position = UDim2.new(1, 0, 0.5, 0)
        MobileSizeInput.Size = UDim2.fromOffset(54, 24)
        MobileSizeInput.PlaceholderText = "px"

        -- Contribute the Settings/overlay-specific side effects to the shared
        -- visibility controller instead of replacing it. `state.setMenuVisible` stays
        -- the single entry point and always updates the blur, even if this builder
        -- never runs.
        state.addMenuVisibilityListener(function(visible: boolean): ()
            -- `FloatingUi` is a local of the floating-UI block, so referring to it by
            -- name from this builder resolved to a nil global and the whole listener
            -- threw (silently: visibility listeners are pcall'd). The published
            -- registry is the one that is actually in scope here.
            local floating: any = state.floatingUi
            if type(floating) ~= "table" then
                return
            end
            local textOverlay: any = floating.overlays and floating.overlays.TextGUI
            if textOverlay and textOverlay.window and textOverlay.window.root then
                textOverlay.window.root.Active = visible
            end
            if visible then
                return
            end
            -- The per-overlay settings windows are closed with the menu. They used to
            -- be listed here by name, but those names are locals of the floating-UI
            -- block: from here they resolved to nil globals, so the list was empty and
            -- the windows stayed on screen. The live registry is authoritative.
            local settingsWindows: any = floating.settingsWindows
            if type(settingsWindows) ~= "table" then
                return
            end
            for _, settingsWindow: any in pairs(settingsWindows) do
                if settingsWindow and settingsWindow.root then
                    settingsWindow.root.Visible = false
                end
            end
        end)

        local function updateTextSizes(): ()
            for _, item in ipairs(registeredText) do
                if item.object and item.object.Parent then
                    item.object.TextSize = state.fitTextSize(
                        item.object,
                        math.round(
                            item.normalSize * TEXT_BASE_MULTIPLIER * state.textScale
                        )
                    )
                end
            end
        end
        -- One pass once the shell has been laid out: every label sized in scale has a
        -- real AbsoluteSize by then, so this is where those get their cap applied. A
        -- viewport change resizes boxes, so the cap is re-applied then too.
        state.onLayout(function(): ()
            updateTextSizes()
        end)
        task.defer(updateTextSizes)

        local textSizeDragInput: InputObject? = nil
        local function setTextScaleFromX(pointerX: number): ()
            local width: number = math.max(1, TextSizeTrack.AbsoluteSize.X)
            local ratio: number = math.clamp(
                (pointerX - TextSizeTrack.AbsolutePosition.X) / width,
                0,
                1
            )
            state.textScale = math.round((
                TEXT_SCALE_MINIMUM
                    + ratio * (TEXT_SCALE_MAXIMUM - TEXT_SCALE_MINIMUM)
            ) * 100) / 100
            TextSizeFill.Size = UDim2.fromScale(ratio, 1)
            TextSizeKnob.Position = UDim2.fromScale(ratio, 0.5)
            TextSizeValue.Text = tostring(math.round(state.textScale * 100)) .. "%"
            updateTextSizes()
            configData.ui.largeText = nil
            configData.ui.textScale = state.textScale
            configData.ui.textScaleCalibrationVersion = 2
            queueConfigSave()
        end
        trackUiConnection(TextSizeTrack.InputBegan:Connect(function(input: InputObject): ()
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                textSizeDragInput = input
                setTextScaleFromX(input.Position.X)
            end
        end))
        trackUiConnection(UserInputService.InputChanged:Connect(function(input: InputObject): ()
            if textSizeDragInput == nil then
                return
            end
            if input == textSizeDragInput
                or input.UserInputType == Enum.UserInputType.MouseMovement then
                setTextScaleFromX(input.Position.X)
            end
        end))
        trackUiConnection(UserInputService.InputEnded:Connect(function(input: InputObject): ()
            if input == textSizeDragInput
                or input.UserInputType == Enum.UserInputType.MouseButton1 then
                textSizeDragInput = nil
            end
        end))

        local reinjectBusy: boolean = false
        trackUiConnection(ReinjectButton.MouseButton1Click:Connect(function(): ()
            if reinjectBusy then
                return
            end
            local compiler: any = (getfenv() :: any).loadstring
            if type(compiler) ~= "function" then
                notify("Reinject unavailable: this executor has no loadstring")
                return
            end
            reinjectBusy = true
            ReinjectButton:SetAttribute("Disabled", true)
            ReinjectButton.Text = "DOWNLOADING…"
            local sourceUrls: {string} = {
                REPOSITORY_RAW_BASE .. "ARandomMenu.luau",
                RUNTIME_SAFETY_SOURCE_URL,
            }
            local sourceOrError: any = nil
            local downloaded: boolean = false
            local downloadFailures: {string} = {}
            for _, candidateUrl: string in ipairs(sourceUrls) do
                local requestUrl: string = candidateUrl
                    .. "?reinject=v3&v="
                    .. SOURCE_STAMP
                local requestOk: boolean, bodyOrError: any = pcall(function(): string
                    return (game :: any):HttpGet(requestUrl, true)
                end)
                local current: boolean = requestOk
                    and type(bodyOrError) == "string"
                    and #bodyOrError >= 1024
                    and bodyOrError:find(RUNTIME_COMPATIBILITY_MARKER, 1, true) ~= nil
                if current then
                    downloaded = true
                    sourceOrError = bodyOrError
                    break
                end
                table.insert(downloadFailures, tostring(bodyOrError))
            end
            if not downloaded then
                reinjectBusy = false
                ReinjectButton:SetAttribute("Disabled", false)
                ReinjectButton.Text = "REINJECT LATEST"
                notify("Could not download the latest build")
                warn("[Random Testing Menu] Reinject download: "
                    .. table.concat(downloadFailures, " | "))
                return
            end
            local compiled: any = nil
            local compileError: any = nil
            local compiledOk: boolean, compileResult: any, returnedError: any = pcall(
                compiler,
                sourceOrError,
                "@ARandomMenu.luau"
            )
            if compiledOk then
                compiled = compileResult
                compileError = returnedError
            else
                compileError = compileResult
            end
            if type(compiled) ~= "function" then
                reinjectBusy = false
                ReinjectButton:SetAttribute("Disabled", false)
                ReinjectButton.Text = "REINJECT LATEST"
                notify("The downloaded build could not be compiled")
                warn("[Random Testing Menu] Reinject compile: " .. tostring(compileError))
                return
            end
            ReinjectButton.Text = "RESTARTING…"
            task.defer(function(): ()
                local executed: boolean, executionError: any = xpcall(
                    compiled,
                    debug.traceback
                )
                if not executed then
                    reinjectBusy = false
                    if ReinjectButton.Parent then
                        ReinjectButton:SetAttribute("Disabled", false)
                        ReinjectButton.Text = "REINJECT LATEST"
                    end
                    warn("[Random Testing Menu] Reinject runtime: " .. tostring(executionError))
                end
            end)
        end))

        trackUiConnection(DestructButton.MouseButton1Click:Connect(function(): ()
            DestructButton:SetAttribute("Disabled", true)
            DestructButton.Text = "REMOVING…"
            task.defer(function(): ()
                local destruct: any = state.destruct
                if type(destruct) ~= "function" then
                    -- The teardown routine is defined at the very end of bootstrap;
                    -- if it is somehow missing, remove the interface anyway instead
                    -- of leaving the button stuck on "REMOVING…".
                    pcall(function(): ()
                        ScreenGui:Destroy()
                    end)
                    return
                end
                local ok: boolean, failure: any = pcall(destruct)
                if not ok then
                    warn("[Random Testing Menu] Destruct: " .. tostring(failure))
                    pcall(function(): ()
                        ScreenGui:Destroy()
                    end)
                end
            end)
        end))

        -- Mobile action size: exact value, from the field or the slider.
        do
        local MOBILE_SIZE_MINIMUM: number = 28
        local MOBILE_SIZE_MAXIMUM: number = 120

        local function applyMobileButtonSize(requested: number, persist: boolean): ()
            local size: number = math.clamp(
                math.round(requested),
                MOBILE_SIZE_MINIMUM,
                MOBILE_SIZE_MAXIMUM
            )
            state.mobileButtonSize = size
            configData.ui.mobileButtonSize = size

            local ratio: number = (size - MOBILE_SIZE_MINIMUM)
                / (MOBILE_SIZE_MAXIMUM - MOBILE_SIZE_MINIMUM)
            MobileSizeFill.Size = UDim2.fromScale(ratio, 1)
            MobileSizeKnob.Position = UDim2.fromScale(ratio, 0.5)
            if not MobileSizeInput:IsFocused() then
                MobileSizeInput.Text = tostring(size)
            end

            -- Every placed button follows immediately, and is pulled back on screen
            -- if the new size pushed it past an edge.
            -- `any` rather than the record type: that type belongs to
            -- src/library/MobileActions.luau, and a downloaded file cannot
            -- require another one. Naming it here annotated nothing.
            for _, record: any in pairs(state.mobileUi.actions) do
                record.button.Size = UDim2.fromOffset(size, size)
                local clamped: Vector2 = state.mobileUi.clampButtonPosition(
                    Vector2.new(
                        record.button.Position.X.Offset,
                        record.button.Position.Y.Offset
                    ),
                    size
                )
                record.button.Position = UDim2.fromOffset(clamped.X, clamped.Y)
                state.mobileUi.saveActionPosition(record)
            end
            if persist then
                queueConfigSave()
            end
        end

        local function sizeFromPointer(pointerX: number): number
            local width: number = math.max(1, MobileSizeTrack.AbsoluteSize.X)
            local alpha: number = math.clamp(
                (pointerX - MobileSizeTrack.AbsolutePosition.X) / width,
                0,
                1
            )
            return MOBILE_SIZE_MINIMUM
                + alpha * (MOBILE_SIZE_MAXIMUM - MOBILE_SIZE_MINIMUM)
        end

        local mobileSizeDrag: InputObject? = nil
        trackUiConnection(MobileSizeTrack.InputBegan:Connect(function(
            input: InputObject
        ): ()
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            mobileSizeDrag = input
            applyMobileButtonSize(sizeFromPointer(input.Position.X), false)
        end))
        trackUiConnection(UserInputService.InputChanged:Connect(function(
            input: InputObject
        ): ()
            if mobileSizeDrag
                and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                applyMobileButtonSize(sizeFromPointer(input.Position.X), false)
            end
        end))
        trackUiConnection(UserInputService.InputEnded:Connect(function(
            input: InputObject
        ): ()
            if mobileSizeDrag
                and (input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch) then
                mobileSizeDrag = nil
                applyMobileButtonSize(state.mobileButtonSize, true)
            end
        end))

        trackUiConnection(MobileSizeInput.FocusLost:Connect(function(): ()
            local parsed: number? = tonumber(MobileSizeInput.Text)
            if parsed == nil then
                MobileSizeInput.Text = tostring(state.mobileButtonSize)
                notify("Mobile action size: enter a number of pixels.")
                return
            end
            applyMobileButtonSize(parsed, true)
            notify("Mobile action size: " .. tostring(state.mobileButtonSize) .. " px")
        end))

        applyMobileButtonSize(state.mobileButtonSize, false)
        end

        trackUiConnection(KeybindButton.MouseButton1Click:Connect(function(): ()
            if state.keyCaptureCancel then
                state.keyCaptureCancel()
            end
            state.waitingForKey = true
            KeybindButton.Text = "PRESS A KEY…"
            setKeySlotCapture(KeybindButton, true)
        end))

    end

    state.buildSettingsPage = build
    Module.Initialized = true
    return {build = build}
end

-- Nothing to tear down: every connection the page makes goes through the
-- shell's own `trackUiConnection`, which the shell releases with the window.
function Module.destroy(): ()
    Module.Initialized = false
end

return Module
