--!strict
--
-- Card factory.
--
-- One card: the row a module gets on a board. Its title and description, the
-- switch or the button its kind calls for, the favourite star, the key slot,
-- the expand arrow, the panel its option rows are filed into, and the search
-- text that finds it.
--
-- Every module in the menu is built by calling this once. It was the last
-- large thing left in `ARandomMenu.luau`, and it is not shell logic: the shell
-- owns the window, the rail and the boards; this owns what sits on a board.
--
-- The shell copies the returned function into the environment every module
-- runs in, under the name they already call — so a module cannot tell that it
-- moved.

local Module = {
    Name = "Cards",
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
    local makeTextLabel: any = host.makeTextLabel
    local notify: any = host.notify
    local Theme: any = host.Theme
    local CONTROL_FONT: any = host.CONTROL_FONT
    local TweenService: any = host.TweenService
    local UI_MOTION: any = host.UI_MOTION
    local cornerRadius: any = host.cornerRadius
    local trackUiConnection: any = host.trackUiConnection
    local applyKeySlotStyle: any = host.applyKeySlotStyle
    local bindActionShortcut: any = host.bindActionShortcut
    local getFeatureCardParent: any = host.getFeatureCardParent
    -- The taxonomy: which section of a board a card is filed under, and where
    -- a name nobody classified ends up.
    local FEATURE_CATEGORIES: any = host.FEATURE_CATEGORIES
    local DEFAULT_FEATURE_CATEGORY: any = host.DEFAULT_FEATURE_CATEGORY
    -- The registries a card files itself into. The old board (UniversalScroll)
    -- is gone; cards start in CardBin and are moved into ClickGUI windows.
    local universalFeatures: any = host.universalFeatures
    local movementFeatures: any = host.movementFeatures
    local mm2Features: any = host.mm2Features
    local allFeatures: any = host.allFeatures
    -- Repainting a card belongs to the shell's skin, not to the factory.
    local applyFeaturePresentation: any = host.applyFeaturePresentation
    local refreshFeatureToggle: any = host.refreshFeatureToggle

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
            or (registry == state.mvsdFeatures and "MVSD")
            or (registry == movementFeatures and "Movement")
            or "Universal"
        local configKey: string = configuration.configKey
            or (sectionName .. "." .. name:gsub("%W", ""))
        -- A module may declare its own category; otherwise the shared taxonomy
        -- decides, and anything unknown lands in the catch-all bucket.
        local categoryName: string = type(configuration.categoryName) == "string"
            and configuration.categoryName
            or FEATURE_CATEGORIES[name]
            or DEFAULT_FEATURE_CATEGORY

        local feature: any = {
            name = name,
            description = description,
            categoryName = categoryName,
            enabled = false,
            expanded = false,
            -- Module kinds.
            --
            -- Everything about a card — what a click does, what its key slot
            -- does, whether it can be "off", whether it announces itself — is
            -- decided by one kind instead of a pile of independent booleans:
            --
            --   toggle  (default) enable/disable state; click or key flips it.
            --   action            a button: click or key runs it once, no state.
            --   hold              always-on system; the key is a dead-man switch
            --                     that only applies the effect while it is held.
            --                     It can never be turned off and never toasts.
            --   group             an always-on container of options; the card
            --                     expands, and its key slot is inert because
            --                     there is nothing to activate.
            --
            -- Legacy flags still work: `action`, `category` and `holdAction` map
            -- onto the kinds above.
            kind = configuration.kind
                or (configuration.action == true and "action")
                or (configuration.holdAction == true and "hold")
                or (configuration.category == true and "group")
                or "toggle",
            silentAction = configuration.silentAction == true,
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

        -- Kept as plain flags so existing code (and the game modules downloaded
        -- from the repository) keep reading the same fields.
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
        -- Ordering metadata read back by the card grid. `layoutOrder` above is
        -- only the pre-sort value; the category pass overwrites it on the next
        -- frame with "category block + alphabetical position".
        row:SetAttribute("FeatureCategory", categoryName)
        row:SetAttribute("FeatureSortName", string.lower(name))
        create("UICorner", {
            Parent = row,
            Name = "CardCorner",
            -- Cards are rows in a list, not floating tiles: a small radius keeps
            -- them reading as one surface instead of a tray of lozenges.
            CornerRadius = cornerRadius(math.min(state.layout.cardCorner, 8)),
        })
        local cardStroke: UIStroke = (create("UIStroke", {
            Parent = row,
            Color = state.guiStyle == "Default"
                and Theme.outline
                or Theme.outline,
            Transparency = 1,
            Thickness = 1,
        }) :: any) :: UIStroke
        feature.stroke = cardStroke
        -- Hairline under the card. A separator instead of a box: forty boxed cards
        -- read as a spreadsheet, forty separated rows read as a list.
        local cardRule: Frame = create("Frame", {
            Parent = row,
            Name = "CardRule",
            AnchorPoint = Vector2.new(0.5, 1),
            BackgroundColor3 = Theme.outline,
            BackgroundTransparency = 0.86,
            BorderSizePixel = 0,
            Position = UDim2.new(0.5, 0, 1, 0),
            Size = UDim2.new(1, 0, 0, 1),
            ZIndex = 8,
        }) :: Frame
        feature.cardRule = cardRule

        -- The card itself carries the kind (see `state.applyCardSkin`).

        local title: TextLabel =
            (makeTextLabel(row, name, state.layout.titleFontSize) :: any) :: TextLabel
        title.FontFace = CONTROL_FONT
        title.Position = UDim2.fromOffset(12, 0)
        title.Size = UDim2.new(1, -(state.layout.cardHeight + 96), 0, feature.collapsedHeight)
        title.TextTruncate = Enum.TextTruncate.AtEnd
        title.TextColor3 = state.guiStyle == "Default"
            and Theme.text
            or Theme.text
        feature.title = title

        local headerControls: Frame = create("Frame", {
            Parent = row,
            Name = "HeaderControls",
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -8, 0, feature.collapsedHeight / 2),
            Size = UDim2.fromOffset(
                state.layout.iconButton * 2 + state.layout.keySlotWidth + 12,
                state.layout.iconButton + 4
            ),
            ZIndex = 9,
        }) :: Frame
        create("UIListLayout", {
            Parent = headerControls,
            Name = "HeaderControlsLayout",
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, state.layout.compact and 4 or 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        local arrow: TextButton =
            (makeButton(headerControls, "", 10) :: any) :: TextButton
        arrow.Name = "Expand"
        arrow.LayoutOrder = 3
        arrow:SetAttribute("ThemeRole", "Icon")
        arrow:SetAttribute("NoPressEffect", true)
        arrow.BackgroundTransparency = 1
        arrow.Size =
            UDim2.fromOffset(state.layout.iconButton, state.layout.iconButton)
        arrow.TextColor3 = state.guiStyle == "Default"
            and Theme.textMuted
            or Theme.textMuted
        -- Every card shows the three lines, including modules with nothing to
        -- configure (Anti-AFK, Anti-Void, X-Ray...): a row that silently drops a
        -- control makes the list look ragged. A card with no options simply never
        -- opens — the mark is dimmed and the click is ignored, which is checked
        -- at click time because option rows can be added after the card is built.
        arrow.Active = true
        arrow.ZIndex = 9
        state.applyLinesGlyph(arrow, configuration.noOptions == true)
        arrow.ZIndex = 9
        local arrowStroke: UIStroke? = arrow:FindFirstChild("StyleStroke") :: UIStroke?
        if arrowStroke then
            arrowStroke.Enabled = false
        end
        feature.arrow = arrow

        -- A module is expandable when it actually owns at least one option row.
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
        title.ZIndex = 7

        trackUiConnection(row.MouseEnter:Connect(function(): ()
            state.applyCardSkin(feature, true)
        end))
        trackUiConnection(row.MouseLeave:Connect(function(): ()
            state.applyCardSkin(feature, false)
        end))

        -- The options panel is a plain container, not a third surface.
        --
        -- It used to draw its own fill, corners and outline *inside* the card,
        -- with every option row drawing its own fill and outline again inside
        -- that: three nested rounded rectangles for one setting. The panel is
        -- transparent now, so an expanded card shows the card and its rows, and
        -- nothing in between.
        local options: Frame = (create("Frame", {
            Parent = row,
            Name = "Options",
            Active = true,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(8, feature.collapsedHeight),
            Size = UDim2.new(1, -16, 0, 0),
            Visible = false,
            ZIndex = row.ZIndex + 10,
        }) :: any) :: Frame
        feature.options = options
        create("UIPadding", {
            Parent = options,
            PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 2),
            PaddingTop = UDim.new(0, 2),
        })
        local optionsLayout: UIListLayout = (create("UIListLayout", {
            Parent = options,
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }) :: any) :: UIListLayout

        local function updateExpandedSize(animate: boolean?): ()
            -- Rows are no longer a uniform height (hint rows are taller, section
            -- headings shorter), so the fallback used before the layout has
            -- measured anything sums the declared heights instead of assuming 38.
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
                    + math.max(0, visibleOptions - 1) * 6
            end
            -- +8 = the panel's 2px top and 6px bottom UIPadding.
            local optionsHeight: number = measuredHeight + 8
            local targetOptionsSize: UDim2 = UDim2.new(1, -16, 0, optionsHeight)
            local targetRowSize: UDim2 = UDim2.new(
                1,
                0,
                0,
                feature.expanded
                    and feature.collapsedHeight + optionsHeight + 6
                    or feature.collapsedHeight
            )
            if feature.expanded then
                options.Visible = true
            end
            if animate and state.animationsEnabled then
                TweenService:Create(
                    options,
                    TweenInfo.new(UI_MOTION.slow, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                    {Size = targetOptionsSize}
                ):Play()
                TweenService:Create(
                    row,
                    TweenInfo.new(UI_MOTION.slow, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                    {Size = targetRowSize}
                ):Play()
                state.applyLinesGlyph(arrow, false, feature.expanded)
                if not feature.expanded then
                    task.delay(UI_MOTION.slow + 0.02, function(): ()
                        if not feature.expanded and options.Parent then
                            options.Visible = false
                        end
                    end)
                end
            else
                options.Size = targetOptionsSize
                row.Size = targetRowSize
                state.applyLinesGlyph(arrow, false, feature.expanded)
                options.Visible = feature.expanded
            end
        end
        feature.updateExpandedSize = updateExpandedSize
        trackUiConnection(
            optionsLayout:GetPropertyChangedSignal("AbsoluteContentSize")
                :Connect(function(): ()
                    updateExpandedSize(false)
                end)
        )

        trackUiConnection(arrow.MouseButton1Click:Connect(function(): ()
            if not feature.hasOptions() then
                -- Nothing to show: keep the panel shut instead of opening an
                -- empty box under the card.
                state.applyLinesGlyph(arrow, true)
                return
            end
            feature.expanded = not feature.expanded
            updateExpandedSize(true)
        end))

        -- Hold modules.
        --
        -- The module itself is *always* running — it can never be switched off
        -- and never announces itself. `setHeld` only reports whether the player
        -- is currently holding the key (or the placed mobile button), and the
        -- module applies or drops its effect accordingly. The card lights up
        -- while held purely as feedback.
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
                -- Clicking the card does nothing: a hold module has no on/off
                -- state to flip, and an accidental click must never leave the
                -- effect latched. Only the key slot drives it.
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
                        -- Actions meant to be spammed from a hotkey (High Jump)
                        -- opt out of the toast: one notification per keypress is
                        -- noise, not feedback.
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
        -- Start in the right skin instead of inheriting the creation defaults.
        state.applyCardSkin(feature, false)
        if feature.isAction then
            -- The only feedback a button needs: the surface lifts under the press
            -- and settles back. No colour, no bounce.
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
        do
            local favoriteButton: TextButton =
                (makeButton(headerControls, "☆", 11) :: any) :: TextButton
            favoriteButton.Name = "Favorite"
            favoriteButton.LayoutOrder = 1
            favoriteButton:SetAttribute("ThemeRole", "Icon")
            favoriteButton:SetAttribute("NoPressEffect", true)
            favoriteButton.BackgroundTransparency = 1
            favoriteButton.Size =
                UDim2.fromOffset(state.layout.iconButton, state.layout.iconButton)
            favoriteButton.ZIndex = 9
            local favoriteStroke: UIStroke? =
                favoriteButton:FindFirstChild("StyleStroke") :: UIStroke?
            if favoriteStroke then
                favoriteStroke.Enabled = false
            end
            feature.favoriteButton = favoriteButton
            trackUiConnection(favoriteButton.MouseButton1Click:Connect(function(): ()
                state.floatingUi.toggleFavorite(feature)
            end))
        end
        -- Every card header carries the same three controls — favourite, key
        -- slot, expand — so the whole list reads as one symmetric grid no matter
        -- whether the module is a toggle, an action or a category. The key slot
        -- toggles regular modules, runs actions, and expands/collapses category
        -- headers (the same path `activateFeature` already provides).
        local shortcutButton: TextButton =
            (makeButton(headerControls, "KEY", 9) :: any) :: TextButton
        shortcutButton.Name = "Shortcut"
        shortcutButton.LayoutOrder = 2
        shortcutButton.BackgroundColor3 = state.guiStyle == "Default"
            and Theme.surface
            or Theme.surfaceRaised
        shortcutButton.Size = UDim2.fromOffset(
            state.layout.keySlotWidth,
            state.layout.iconButton
        )
        shortcutButton.ZIndex = 9
        applyKeySlotStyle(shortcutButton)
        shortcutButton.TextScaled = true
        create("UITextSizeConstraint", {
            Parent = shortcutButton,
            MaxTextSize = 11,
            MinTextSize = 7,
        })
        feature.shortcutButton = shortcutButton
        if feature.kind == "group" then
            -- A container has nothing to activate: the slot stays on the card for
            -- symmetry but never captures a key, never places a mobile button and
            -- never fires. Pressing it does nothing, by design.
            shortcutButton.Active = false
            shortcutButton.AutoButtonColor = false
            shortcutButton.Text = ""
            shortcutButton.TextTransparency = 1
            shortcutButton.BackgroundTransparency = 0.86
            shortcutButton:SetAttribute("Disabled", true)
            shortcutButton:SetAttribute("NoHover", true)
            shortcutButton:SetAttribute("CaptureIdleText", "")
        elseif feature.kind == "hold" then
            -- The key is a dead-man switch: held means active, released means
            -- inactive. It never toggles the module on or off.
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

        feature.headerControls = headerControls

        -- Point at the card, press a key, the card owns that key — the same
        -- gesture the reference interface uses instead of a capture dialog.
        -- Containers are excluded because their slot has nothing to activate.

        -- Re-applies the responsive metrics to this card. The shared listener
        -- registered next to `allFeatures` calls it for every module whenever the
        -- viewport mode changes, which is what makes phone/tablet/desktop layouts
        -- work without a single game module knowing a pixel value.
        feature.applyLayout = function(): ()
            local metrics: LayoutMetrics = state.layout
            local sideWidth: number =
                metrics.iconButton * 2 + metrics.keySlotWidth + 12
            feature.collapsedHeight = metrics.cardHeight
            local cardCorner: UICorner? = row:FindFirstChild("CardCorner") :: UICorner?
            if cardCorner then
                cardCorner.CornerRadius = cornerRadius(math.min(metrics.cardCorner, 8))
            end
            title.Size =
                UDim2.new(1, -(sideWidth + 26), 0, metrics.cardHeight)
            state.setTextMetric(title, metrics.titleFontSize)
            headerControls.Position = UDim2.new(1, -8, 0, metrics.cardHeight / 2)
            headerControls.Size =
                UDim2.fromOffset(sideWidth, metrics.iconButton + 4)
            local controlsLayout: UIListLayout? =
                headerControls:FindFirstChild("HeaderControlsLayout") :: UIListLayout?
            if controlsLayout then
                controlsLayout.Padding = UDim.new(0, metrics.compact and 4 or 6)
            end
            arrow.Size = UDim2.fromOffset(metrics.iconButton, metrics.iconButton)
            if feature.favoriteButton then
                feature.favoriteButton.Size =
                    UDim2.fromOffset(metrics.iconButton, metrics.iconButton)
            end
            shortcutButton.Size =
                UDim2.fromOffset(metrics.keySlotWidth, metrics.iconButton)
            activationTarget.Size = UDim2.new(1, 0, 0, metrics.cardHeight)
            options.Position = UDim2.fromOffset(8, metrics.cardHeight)
            updateExpandedSize(false)
        end
        -- Applied once at creation too, so a card built while the shell is in one
        -- mode never keeps sizes from another.
        feature.applyLayout()

        -- What the HUD list writes in brackets after the module's name, the
        -- way Wurst prints `AutoTotem [0 totems]`. It lives on the card rather
        -- than on the framework's wrapper because only eighteen of the
        -- thirty-eight modules have a wrapper — the other twenty build their
        -- card straight through this factory, and a status only half the menu
        -- can publish is a list that lies by omission.
        --
        -- `nil` means say nothing, which is the right answer for most modules
        -- most of the time; `[on]` is noise, since the name is in the list
        -- precisely because it is on.
        function feature:SetStatus(status: string?): ()
            feature.status = status
        end

        registry[name] = feature
        table.insert(allFeatures, feature)
        -- Favourites and the overlay menu are a downloaded layer. A card that
        -- cannot be favourited is a small loss; a card that cannot be created
        -- because the layer is missing takes the whole menu with it.
        if state.floatingUi then
            state.floatingUi.registerFeature(feature)
        end
        -- A game module builds its cards after the libraries have started, so
        -- the ClickGUI cannot have collected them at init.
        if state.clickGui then
            state.clickGui.place(feature)
        end
        applyFeaturePresentation(feature, state.guiStyle == "Default")

        -- No "Toggle key" option row any more: every card already carries a key
        -- slot in its header and that slot is the only place an activation key
        -- lives, on desktop and on touch alike.

        -- Always-on modules (hold systems, containers) start their runtime once,
        -- here, instead of waiting for a click that can never come.
        if feature.isAlwaysOn then
            task.defer(function(): ()
                local ok: boolean, failure: any = pcall(feature.onToggle, true)
                if not ok then
                    warn("[Random Testing Menu] " .. name .. ": " .. tostring(failure))
                end
            end)
        end

        -- Hold modules are momentary: they are never restored as "on" at startup.
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

    Module.Initialized = true
    return {createUniversalFeature = createUniversalFeature}
end

-- Nothing to tear down: a card is a child of the board the shell destroys, and
-- every connection it makes went through `trackUiConnection`.
function Module.destroy(): ()
    Module.Initialized = false
end

return Module
