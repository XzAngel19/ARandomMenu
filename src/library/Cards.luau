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
    local applyKeySlotStyle: any = host.applyKeySlotStyle
    local bindActionShortcut: any = host.bindActionShortcut
    local getFeatureCardParent: any = host.getFeatureCardParent
    -- The taxonomy: which section of a board a card is filed under, and where
    -- a name nobody classified ends up.
    local FEATURE_CATEGORIES: any = host.FEATURE_CATEGORIES
    local DEFAULT_FEATURE_CATEGORY: any = host.DEFAULT_FEATURE_CATEGORY
    local normalizeFeatureCategory: any = host.normalizeFeatureCategory
    -- The registries a card files itself into. The old board (UniversalScroll)
    -- is gone; cards start in CardBin and are moved into ClickGUI windows.
    local universalFeatures: any = host.universalFeatures
    local movementFeatures: any = host.movementFeatures
    local mm2Features: any = host.mm2Features
    local allFeatures: any = host.allFeatures
    local registeredSearchFeatures: {any} = {}
    -- Repainting a card belongs to the shell's skin, not to the factory.
    local applyFeaturePresentation: any = host.applyFeaturePresentation
    local refreshFeatureToggle: any = host.refreshFeatureToggle
    local addFeatureTooltip: any = host.addFeatureTooltip
    -- The pixel-sprite pen the widget library publishes; a stand-in for the
    -- harness host, which does not carry it.
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
            or (registry == state.mvsdFeatures and "MVSD")
            or (registry == movementFeatures and "Movement")
            or "Universal"
        local configKey: string = configuration.configKey
            or (sectionName .. "." .. name:gsub("%W", ""))
        -- A module may declare its own category; otherwise the shared taxonomy
        -- decides. Every answer is resolved through the category contract, so
        -- whatever a module says — an official window, an old port name, or
        -- nothing — it lands in one of Wurst's eight windows, never in limbo.
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
        -- A Wurst row is a rectangle. No corner radius, no stroke, no hairline
        -- separator — the previous card dressing made forty rows read as a
        -- tray of lozenges, and none of it is in ref-wurst-719.

        -- The hack's name on the bitmap contract, centred on the whole row —
        -- ref-wurst-719 — with the settings arrow floating over the right
        -- end without moving that centre. The TextLabel branch is the
        -- harness stand-in: the shell always publishes state.bitmapText, so
        -- at runtime only the glyph path draws, and no second label exists.
        -- applyCardSkin repaints through drawTitle, which the pool makes an
        -- in-place recolour rather than a rebuild.
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
                })
            end
            feature.drawTitle(Theme.text, 0)
        else
            title = (makeTextLabel(row, name, state.layout.titleFontSize) :: any) :: TextLabel
            local label: TextLabel = title :: TextLabel
            label.FontFace = CONTROL_FONT
            -- Wurst centres the hack's name on the whole row — ref-wurst-719 —
            -- and the settings arrow floats over the right end without moving
            -- that centre, so the label always spans the full row.
            label.Position = UDim2.fromOffset(0, 0)
            label.Size = UDim2.new(1, 0, 0, feature.collapsedHeight)
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextTruncate = Enum.TextTruncate.AtEnd
            label.TextColor3 = state.guiStyle == "Default"
                and Theme.text
                or Theme.text
            feature.title = label
        end

        -- Wurst's settings arrow: an 11-logical-px box on the right end of
        -- the row (22 here, everything is drawn at GUI scale 2), holding a
        -- triangle that points down while the settings are closed and up
        -- while they are open. It is not created — no instance, no reserved
        -- width — until the module actually owns an option row;
        -- `feature.hasSettings` below is the one shared answer to "does this
        -- module have settings", derived from real option rows and nothing
        -- else.
        local arrow: TextButton? = nil
        local toggleExpansion: () -> () = function(): () end

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

        -- Options arrive after the card is built (the module adds its rows to
        -- a card that already exists), so both the metadata and the arrow are
        -- re-decided every time the panel is remeasured — from the real
        -- option rows, never from a heuristic over transient children.
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
                -- Wurst's own green pixel triangle, whatever the palette —
                -- the reference screenshots keep it green on magenta and on
                -- pink alike. Down while closed, up while open. The title
                -- keeps its full-row centre either way.
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

        -- The options panel is a plain container, not a third surface.
        --
        -- It used to draw its own fill, corners and outline *inside* the card,
        -- with every option row drawing its own fill and outline again inside
        -- that: three nested rounded rectangles for one setting. The panel is
        -- transparent now, so an expanded card shows the card and its rows, and
        -- nothing in between.
        -- Wurst's child metrics: settings are inset 2 logical (4 px) from
        -- the row and separated by the same 2-logical gap.
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
            -- Options never expand inside the category window any more —
            -- Wurst pops them into a settings window of their own. This
            -- remeasure keeps the panel's height current for that window
            -- and re-decides the arrow; the row's own height never moves.
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
            -- +8 = the panel's 4px top and 4px bottom UIPadding.
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
                -- Nothing to show: no window for an empty panel.
                syncArrow()
                return
            end
            -- The triangle, the right-click and the Navigator all open the
            -- same window through the one contract. A second call raises
            -- the existing window rather than duplicating it.
            local windows: any = state.windows
            if windows and type(windows.OpenFeatureSettings) == "function" then
                windows.OpenFeatureSettings(feature)
            end
        end
        feature.toggleExpansion = toggleExpansion

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
        -- Wurst's right-click: the settings open under the row. The star and
        -- the permanent key slot that used to sit in every header are gone —
        -- Wurst rows carry a name and, at most, the arrow.
        trackUiConnection(activationTarget.InputBegan:Connect(function(input: InputObject): ()
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                toggleExpansion()
            end
        end))

        -- On touch there is no keyboard and no right-click: the slot that
        -- places an on-screen button for the module is the only way a phone
        -- reaches a shortcut, so the slot survives there and only there.
        local shortcutButton: TextButton? = nil
        if state.isMobile then
            local slot: TextButton =
                (makeButton(row, "KEY", 9) :: any) :: TextButton
            slot.Name = "Shortcut"
            slot.AnchorPoint = Vector2.new(1, 0.5)
            slot.Position = UDim2.new(1, -30, 0, feature.collapsedHeight / 2)
            slot.Size = UDim2.fromOffset(
                state.layout.keySlotWidth,
                state.layout.iconButton
            )
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
            -- A container has nothing to activate: no key is ever bound to
            -- it, so no binding is registered at all.
            if shortcutButton then
                (shortcutButton :: TextButton).Visible = false
            end
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



        -- Point at the card, press a key, the card owns that key — the same
        -- gesture the reference interface uses instead of a capture dialog.
        -- Containers are excluded because their slot has nothing to activate.

        -- Re-applies the responsive metrics to this card. The shared listener
        -- registered next to `allFeatures` calls it for every module whenever the
        -- viewport mode changes, which is what makes phone/tablet/desktop layouts
        -- work without a single game module knowing a pixel value.
        feature.applyLayout = function(): ()
            local metrics: LayoutMetrics = state.layout
            feature.collapsedHeight = metrics.cardHeight
            if title then
                state.setTextMetric(title, metrics.titleFontSize)
            elseif feature.drawTitle then
                -- The bitmap title re-reads the layout size on every draw.
                feature.drawTitle(nil, nil)
            end
            if arrow then
                (arrow :: TextButton).Size =
                    UDim2.fromOffset(22, metrics.cardHeight)
            end
            if shortcutButton then
                (shortcutButton :: TextButton).Size =
                    UDim2.fromOffset(metrics.keySlotWidth, metrics.iconButton);
                (shortcutButton :: TextButton).Position =
                    UDim2.new(1, -30, 0, metrics.cardHeight / 2)
            end
            activationTarget.Size = UDim2.new(1, 0, 0, metrics.cardHeight)
            options.Position = UDim2.fromOffset(4, metrics.cardHeight)
            syncArrow()
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

        -- Every card describes itself, so every card gets the hover tooltip —
        -- the prototype binds `card.t` on each row. Modules that call
        -- `addFeatureTooltip` themselves only replace this text with a longer
        -- one; the binding is made once either way.
        if type(addFeatureTooltip) == "function" and description ~= "" then
            addFeatureTooltip(feature, description)
        end

        -- The searchable registry is independent of ClickGUI and Navigator.
        -- Cards are its source of truth because all 38 modules, framework and
        -- legacy alike, pass through this factory exactly once.
        local search: any = state.moduleSearch
        if search and type(search.Register) == "function" then
            search.Register(feature)
            table.insert(registeredSearchFeatures, feature)
        end

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
