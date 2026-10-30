local Module = {
    Name = "SettingsPage",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local WINDOW_WIDTH: number = 214
local ROW_HEIGHT: number = 22
local WINDOW_GAP: number = 2

local TITLE_HEIGHT: number = 26

function Module.init(context: any): any

    local OPACITY: number = 0.5
    local TOOLTIP_OPACITY: number = 0.75
    local MAX_HEIGHT: number = 200
    local MAX_SETTINGS_HEIGHT: number = 200
    local HACKLIST_MODE: string = "Auto"
    local HACKLIST_POSITION: string = "Left"
    local HACKLIST_COLOR: Color3 = Color3.fromRGB(255, 255, 255)
    local HACKLIST_SORT_BY: string = "Name"
    local HACKLIST_REVERSE: boolean = false
    local HACKLIST_ANIMATIONS: boolean = true
    local HACKLIST_SIZE: string = "Normal"
    local HACKLIST_RAINBOW: boolean = false

    local host: any = context
    local state: any = host.state
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local create: any = host.create
    local makeButton: any = host.makeButton
    local makeTextBox: any = host.makeTextBox
    local notify: any = host.notify
    local Theme: any = host.Theme
    local ThemeEngine: any = host.ThemeEngine
    local CONTROL_FONT: any = host.CONTROL_FONT
    local UserInputService: any = host.UserInputService
    local trackUiConnection: any = host.trackUiConnection
    local beginKeyCapture: any = host.beginKeyCapture
    local setKeySlotCapture: any = host.setKeySlotCapture
    local bindActionShortcut: any = host.bindActionShortcut
    local GAME_CHECK: any = host.GAME_CHECK
    local ScreenGui: any = host.ScreenGui
    local allFeatures: {any} = host.allFeatures or {}
    local REPOSITORY_RAW_BASE: any = host.REPOSITORY_RAW_BASE
    local RUNTIME_SAFETY_SOURCE_URL: any = host.RUNTIME_SAFETY_SOURCE_URL
    local RUNTIME_COMPATIBILITY_MARKER: any = host.RUNTIME_COMPATIBILITY_MARKER
    local SOURCE_STAMP: any = host.SOURCE_STAMP

    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addCycleOption: any = host.addCycleOption
    local addColorOption: any = host.addColorOption

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

    local windows: any = state.windows
    if not windows then
        error("SettingsPage requires the window manager")
    end

    local Settings: any = {
        records = {} :: {any},
        connections = {} :: {RBXScriptConnection},
    }

    local function viewport(): Vector2

        if type(windows.LogicalViewport) == "function" then
            return windows.LogicalViewport()
        end
        local camera: Camera? = workspace.CurrentCamera
        return camera and (camera :: Camera).ViewportSize or Vector2.new(1280, 720)
    end

    local maxSettingsHeight: number = MAX_SETTINGS_HEIGHT
    state.uiMaxHeight = MAX_HEIGHT

    local function textWidth(text: any): number
        local bitmapText: any = state.bitmapText
        if bitmapText and type(bitmapText.measure) == "function" then
            local measured: number = tonumber(bitmapText.measure(
                {{text = tostring(text)}}, 16
            )) or 0
            if measured > 0 then
                return measured
            end
        end
        return #tostring(text) * 12
    end
    local function packedWidth(rows: {{any}}): number
        local widest: number = 150
        for _, row: {any} in ipairs(rows) do
            local labelWidth: number = textWidth(row[1])
            local valueWidth: number = row[2] ~= nil and textWidth(row[2]) or 0
            local extra: number = tonumber(row[3]) or 0
            widest = math.max(widest, 8 + labelWidth + 24 + valueWidth + extra)
        end
        return widest
    end

    local function configWindow(
        id: string,
        title: string,
        definition: any
    ): any

        local packRows: {{any}}? = definition.packRows
        local width: number = packRows and packedWidth(packRows)
            or tonumber(definition.width)
            or WINDOW_WIDTH
        local window: any = windows.Create({
            id = id,
            title = title,
            size = Vector2.new(width, 30),
            position = definition.position,
            closable = definition.closable ~= false,
        })

        window.managementWindow = true
        if definition.anchor ~= nil then
            window.placementAnchor = definition.anchor
        end

        do
            local bitmapText: any = state.bitmapText
            if bitmapText and type(bitmapText.adoptTree) == "function" then
                table.insert(
                    window.connections,
                    bitmapText.adoptTree(window.body)
                )
            end
        end
        local layout: UIListLayout = (create("UIListLayout", {
            Parent = window.body,
            Padding = UDim.new(0, WINDOW_GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }) :: any) :: UIListLayout
        create("UIPadding", {
            Parent = window.body,
            PaddingTop = UDim.new(0, WINDOW_GAP),
            PaddingBottom = UDim.new(0, WINDOW_GAP),
            PaddingLeft = UDim.new(0, WINDOW_GAP),
            PaddingRight = UDim.new(0, WINDOW_GAP),
        })

        local record: any = {
            window = window,
            layout = layout,
            open = false,
            width = width,
            packRows = packRows,
        }
        local function resize(): ()
            local limit: number
            if definition.settingsSized then
                limit = maxSettingsHeight
            else
                limit = tonumber(state.uiMaxHeight) or MAX_HEIGHT
            end
            if limit <= 0 then
                limit = math.huge
            end

            if type(windows.LogicalViewport) == "function" then
                limit = math.min(limit, windows.LogicalViewport().Y - 12)
            end
            local wanted: number = math.min(
                TITLE_HEIGHT + layout.AbsoluteContentSize.Y + WINDOW_GAP * 2,
                limit
            )
            window.fullHeight = wanted
            if not window.collapsed then
                window.root.Size = UDim2.fromOffset(record.width, wanted)
            end

            if windows.ReflowWindow then
                windows.ReflowWindow(window)
            elseif windows.ClampWindow then
                windows.ClampWindow(window)
            end
        end
        record.resize = resize

        record.repack = function(rowsOverride: {{any}}?): ()
            if rowsOverride ~= nil then
                record.packRows = rowsOverride
            end
            if record.packRows == nil then
                return
            end
            local packed: number = packedWidth(record.packRows)
            if packed ~= record.width then
                record.width = packed
                resize()
            end
        end
        table.insert(
            Settings.connections,
            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
        )
        resize()
        table.insert(Settings.records, record)
        return record
    end

    local function panelFor(record: any, configKey: string): any
        local panel: any = {
            options = record.window.body,
            optionCount = 0,
            optionRows = {},
            configKey = configKey,
            searchText = "",
        }
        panel.updateExpandedSize = function(): ()
            record.resize()
        end
        return panel
    end

    local function actionRow(
        record: any,
        order: number,
        labelText: string,
        onClick: () -> ()
    ): TextButton
        local row: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = record.window.body,
            Name = "Row_" .. labelText:gsub("%W", ""),
            Active = true,
            AutoButtonColor = false,
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
            Text = "",
            ZIndex = record.window.body.ZIndex + 1,
        }) :: any) :: TextButton
        create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
            Name = "Label",
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(6, 0),
            Size = UDim2.new(1, -28, 1, 0),
            Text = labelText,
            TextColor3 = Theme.text,
            TextSize = 16,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = row.ZIndex + 1,
        })
        local arrowBox: Frame = (create("Frame", {
            Parent = row,
            Name = "Arrow",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -4, 0, 0),
            Size = UDim2.fromOffset(22, ROW_HEIGHT),
            ZIndex = row.ZIndex + 1,
        }) :: any) :: Frame

        drawPixelIcon(arrowBox, "right", nil, "arrows")
        trackUiConnection(row.MouseEnter:Connect(function(): ()
            row.BackgroundTransparency = 0.3
        end))
        trackUiConnection(row.MouseLeave:Connect(function(): ()
            row.BackgroundTransparency = 0.5
        end))
        trackUiConnection(row.MouseButton1Click:Connect(onClick))
        record.resize()
        return row
    end

    local function raiseOpen(record: any): ()
        record.open = true

        if not record.placed or record.window.stalePlacement then
            record.placed = true
            record.window.stalePlacement = nil
            if windows.PlaceWindow then
                windows.PlaceWindow(record.window)
            end
        end
        record.window:SetVisible(true)
    end

    local uiRecord: any = nil

    local hackListRecord: any = nil
    local function openHackList(): ()
        if hackListRecord then
            raiseOpen(hackListRecord)
            return
        end
        local screen: Vector2 = viewport()
        hackListRecord = configWindow("HackList", "HackList", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 180),
            anchor = uiRecord and uiRecord.window,
            settingsSized = true,
            packRows = {
                {"Show", nil, 30},
                {"Mode", "Hidden", 26},
                {"Position", "Right", 26},
                {"Color", "#FFFFFF"},
                {"Sort by", "Width", 26},
                {"Reverse sorting", nil, 30},
                {"Animations", nil, 30},
                {"Size", "Normal", 26},
                {"Rainbow", nil, 30},
            },
        })
        local panel: any = panelFor(hackListRecord, "HackList")
        addToggleOption(
            panel,
            "Show",
            false,
            function(value: boolean): ()
                state.hudListAlways = value
                if state.hudList and type(state.hudList.SetAlways) == "function" then
                    state.hudList.SetAlways(value)
                end
            end,
            "Keep the hack list on screen even while the menu is closed"
        )
        local modes: {string} = {"Auto", "Count", "Hidden"}
        addCycleOption(
            panel,
            "Mode",
            modes,
            table.find(modes, HACKLIST_MODE) or 1,
            function(value: string): ()
                if state.hudList then
                    state.hudList.SetMode(value)
                end
            end
        )
        local positions: {string} = {"Left", "Right", "Custom"}
        addCycleOption(
            panel,
            "Position",
            positions,
            table.find(positions, HACKLIST_POSITION) or 1,
            function(value: string): ()
                if state.hudList then
                    state.hudList.SetPosition(value)
                end
            end
        )
        addColorOption(panel, "Color", HACKLIST_COLOR, function(color: Color3): ()
            if state.hudList then
                state.hudList.SetColor(color)
            end
        end)
        local sorts: {string} = {"Name", "Width"}
        addCycleOption(
            panel,
            "Sort by",
            sorts,
            table.find(sorts, HACKLIST_SORT_BY) or 1,
            function(value: string): ()
                if state.hudList then
                    state.hudList.SetSortBy(value)
                end
            end
        )
        addToggleOption(panel, "Reverse sorting", HACKLIST_REVERSE, function(value: boolean): ()
            if state.hudList then
                state.hudList.SetReverse(value)
            end
        end)
        addToggleOption(panel, "Animations", HACKLIST_ANIMATIONS, function(value: boolean): ()
            if state.hudList then
                state.hudList.SetAnimations(value)
            end
        end)
        local sizes: {string} = {"Small", "Normal", "Large"}
        addCycleOption(
            panel,
            "Size",
            sizes,
            table.find(sizes, HACKLIST_SIZE) or 2,
            function(value: string): ()
                if state.hudList and type(state.hudList.SetSize) == "function" then
                    state.hudList.SetSize(value)
                end
            end
        )
        addToggleOption(panel, "Rainbow", HACKLIST_RAINBOW, function(value: boolean): ()
            if state.hudList and type(state.hudList.SetRainbow) == "function" then
                state.hudList.SetRainbow(value)
            end
        end)
        raiseOpen(hackListRecord)
    end

    local keybindsRecord: any = nil
    local profilesRecord: any = nil
    local keybindsList: Frame? = nil

    local function featureLabel(bindingId: string): string
        for _, feature: any in ipairs(allFeatures) do
            if feature.configKey == bindingId then
                return tostring(feature.name)
            end
        end
        return bindingId
    end

    local function keyLabel(name: any): string
        if type(state.keyDisplayName) == "function" then
            return state.keyDisplayName(name)
        end
        return tostring(name or "")
    end

    local function persistBindingKey(binding: any): ()
        local optionKey: string = "Shortcut." .. tostring(binding.id):gsub("%W", "")
        if binding.key == Enum.KeyCode.Unknown then
            configData.values[optionKey] = nil
        else
            configData.values[optionKey] = binding.key.Name
        end
        queueConfigSave()
    end

    local rebuildKeybinds: () -> () = function(): () end

    local function sortedBindings(): {any}
        local list: {any} = {}
        for _, binding: any in pairs(state.shortcutBindings) do
            table.insert(list, binding)
        end
        table.sort(list, function(left: any, right: any): boolean
            return featureLabel(tostring(left.id)) < featureLabel(tostring(right.id))
        end)
        return list
    end

    rebuildKeybinds = function(): ()
        local container: Frame? = keybindsList
        if not container then
            return
        end
        for _, child: Instance in ipairs((container :: Frame):GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end

        local keyUses: {[string]: number} = {}
        for _, binding: any in pairs(state.shortcutBindings) do
            if binding.key and binding.key ~= Enum.KeyCode.Unknown then
                local name: string = binding.key.Name
                keyUses[name] = (keyUses[name] or 0) + 1
            end
        end

        local order: number = 0

        local function keybindRow(
            labelText: string,
            slotText: string,
            conflicted: boolean,
            onSlot: (TextButton) -> (),
            onRemove: (() -> ())?
        ): ()
            order += 1
            local row: Frame = (create("Frame", {
                Parent = container,
                Name = "Bind_" .. labelText:gsub("%W", ""),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
                ZIndex = (container :: Frame).ZIndex + 1,
            }) :: any) :: Frame
            create("TextLabel", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
                Name = "Label",
                BackgroundTransparency = 1,
                FontFace = CONTROL_FONT,
                Position = UDim2.fromOffset(6, 0),
                Size = UDim2.new(1, -160, 1, 0),
                Text = labelText,
                TextColor3 = Theme.text,
                TextSize = 16,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = row.ZIndex + 1,
            })
            local slot: TextButton = (create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
                Name = "Key",
                Active = true,
                AnchorPoint = Vector2.new(1, 0),
                AutoButtonColor = false,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                FontFace = CONTROL_FONT,
                Position = UDim2.new(1, -6, 0, 0),
                Size = UDim2.fromOffset(150, ROW_HEIGHT),
                Text = slotText,
                TextColor3 = conflicted and Theme.negative or Theme.textMuted,
                TextSize = 16,
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = row.ZIndex + 1,
            }) :: any) :: TextButton
            slot:SetAttribute("CaptureIdleText", slotText)
            trackUiConnection(slot.MouseButton1Click:Connect(function(): ()
                onSlot(slot)
            end))

            if onRemove then
                trackUiConnection(slot.InputBegan:Connect(function(
                    input: InputObject
                ): ()
                    if input.UserInputType == Enum.UserInputType.MouseButton2 then
                        (onRemove :: () -> ())()
                    end
                end))
            end
        end

        if not UserInputService.TouchEnabled then
            keybindRow("Open menu", keyLabel(state.toggleKey.Name), false, function(slot: TextButton): ()
                if state.keyCaptureCancel then
                    state.keyCaptureCancel()
                end
                state.keybindButton = slot
                state.waitingForKey = true
                slot.Text = "..."
                setKeySlotCapture(slot, true)
            end)
        end

        for _, binding: any in ipairs(sortedBindings()) do
            local bound: boolean = binding.key ~= nil
                and binding.key ~= Enum.KeyCode.Unknown
            if not bound then
                continue
            end
            local slotText: string = keyLabel(binding.key.Name)
            local conflicted: boolean = (keyUses[binding.key.Name] or 0) > 1
            keybindRow(featureLabel(tostring(binding.id)), slotText, conflicted, function(slot: TextButton): ()
                beginKeyCapture(slot, function(keyCode: Enum.KeyCode): ()

                    binding.key = keyCode == binding.key
                        and Enum.KeyCode.Unknown
                        or keyCode
                    persistBindingKey(binding)
                    if binding.refresh then
                        binding.refresh()
                    end
                    rebuildKeybinds()
                end)
            end, function(): ()

                binding.key = Enum.KeyCode.Unknown
                persistBindingKey(binding)
                if binding.refresh then
                    binding.refresh()
                end
                rebuildKeybinds()
                notify(featureLabel(tostring(binding.id)) .. " unbound")
            end)
        end

        if keybindsRecord then

            local rows: {{any}} = {
                {"Open menu", "RShift", 12},
                {"Reset keybinds", nil, 26},
                {"Add", nil, 26},
                {"Profiles…", nil, 26},
            }
            for _, binding: any in ipairs(sortedBindings()) do
                if binding.key and binding.key ~= Enum.KeyCode.Unknown then
                    table.insert(
                        rows,
                        {featureLabel(tostring(binding.id)), keyLabel(binding.key.Name), 12}
                    )
                end
            end
            if keybindsRecord.repack then
                keybindsRecord.repack(rows)
            end
            keybindsRecord.resize()
        end
    end

    local function profileStore(): any
        if type(configData.values.Profiles) ~= "table" then
            configData.values.Profiles = {}
        end
        return configData.values.Profiles
    end

    -- Profile stores must never be captured inside a profile.
    local PROFILE_STORE_KEYS: {[string]: boolean} = {
        Profiles = true,
        KeybindProfiles = true,
    }

    local function captureProfile(): any
        local states: {[string]: any} = {}
        for key: string, value: any in pairs(configData.states) do
            states[key] = value
        end
        local values: {[string]: any} = {}
        for key: string, value: any in pairs(configData.values) do
            if not PROFILE_STORE_KEYS[key] then
                values[key] = value
            end
        end
        local shortcuts: {[string]: string} = {}
        for id: string, binding: any in pairs(state.shortcutBindings) do
            if binding.key and binding.key ~= Enum.KeyCode.Unknown then
                shortcuts[id] = binding.key.Name
            end
        end
        local enabledModules: number = 0
        for _, feature: any in ipairs(allFeatures) do
            if configData.states[feature.configKey] == true then
                enabledModules += 1
            end
        end
        local optionCount: number = 0
        for _ in pairs(values) do
            optionCount += 1
        end
        return {
            savedAt = os.time(),
            states = states,
            values = values,
            shortcuts = shortcuts,
            enabledModules = enabledModules,
            optionCount = optionCount,
        }
    end

    local function applyProfile(name: string): boolean
        local snapshot: any = profileStore()[name]
        if type(snapshot) ~= "table" then
            return false
        end
        -- 1) Saved config first: states are replaced wholesale, values merge
        --    (the profile stores themselves are never captured).
        for key: string in pairs(configData.states) do
            configData.states[key] = nil
        end
        for key: string, value: any in pairs(snapshot.states) do
            configData.states[key] = value
        end
        for key: string, value: any in pairs(snapshot.values) do
            if not PROFILE_STORE_KEYS[key] then
                configData.values[key] = value
            end
        end
        -- 2) Keybinds.
        for _, binding: any in pairs(state.shortcutBindings) do
            local savedName: any = snapshot.shortcuts
                and snapshot.shortcuts[tostring(binding.id)]
            local savedKey: any = Enum.KeyCode.Unknown
            if type(savedName) == "string" and savedName ~= "" then
                local resolved: boolean, candidate: any = pcall(function(): any
                    return (Enum.KeyCode :: any)[savedName]
                end)
                if resolved then
                    savedKey = candidate
                end
            end
            if savedKey == Enum.KeyCode.Unknown then
                if binding.key ~= Enum.KeyCode.Unknown
                    and type(binding.assign) == "function" then
                    binding.assign(binding.key)
                end
            elseif binding.key ~= savedKey
                and type(binding.assign) == "function" then
                binding.assign(savedKey)
            elseif type(binding.refresh) == "function" then
                binding.refresh()
            end
        end
        -- 3) Module masters: the cards flip with full UI sync.
        for _, feature: any in ipairs(allFeatures) do
            local wanted: boolean = snapshot.states[feature.configKey] == true
            if feature.enabled ~= wanted
                and type(feature.activate) == "function" then
                pcall(feature.activate)
            end
        end
        -- 4) Option toggles.
        for key: string, control: any in pairs(state.toggleControls or {}) do
            local saved: any = snapshot.states[key]
            if saved ~= nil and type(control.setChecked) == "function" then
                pcall(control.setChecked, saved == true)
            end
        end
        -- 5) Option values (sliders, colours, cycles, text).
        for key: string, control: any in pairs(state.valueControls or {}) do
            local saved: any = snapshot.values[key]
            if saved ~= nil and type(control.apply) == "function" then
                pcall(control.apply, saved)
            end
        end
        queueConfigSave()
        return true
    end

    local function panicReset(): ()
        -- Every module off (cards flip with full UI sync).
        for _, feature: any in ipairs(allFeatures) do
            if feature.enabled and type(feature.activate) == "function" then
                pcall(feature.activate)
            end
        end
        -- Every option toggle off.
        for _, control: any in pairs(state.toggleControls or {}) do
            if type(control.setChecked) == "function" then
                pcall(control.setChecked, false)
            end
        end
        -- Every option value back to its default, live on screen.
        for _, control: any in pairs(state.valueControls or {}) do
            if control.default ~= nil and type(control.apply) == "function" then
                pcall(control.apply, control.default)
            end
        end
        -- Wipe the saved config. Profile stores and keybinds survive so a
        -- saved profile can bring everything back.
        for key: string in pairs(configData.states) do
            configData.states[key] = nil
        end
        for key: string in pairs(configData.values) do
            if not PROFILE_STORE_KEYS[key]
                and not string.match(key, "^Shortcut%.") then
                configData.values[key] = nil
            end
        end
        queueConfigSave()
        notify("panic: every module and option is back to defaults")
    end

    local rebuildProfiles: () -> () = function(): () end
    local profilesList: Frame? = nil

    local function openProfiles(): ()
        if profilesRecord then
            raiseOpen(profilesRecord)
            rebuildProfiles()
            return
        end
        local screen: Vector2 = viewport()
        profilesRecord = configWindow("Profiles", "Profiles", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 260),
            anchor = keybindsRecord and keybindsRecord.window,
            settingsSized = true,
        })

        local entryRow: Frame = (create("Frame", {
            Parent = profilesRecord.window.body,
            Name = "NewProfile",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
            ZIndex = profilesRecord.window.body.ZIndex + 1,
        }) :: any) :: Frame
        local nameBox: TextBox = (makeTextBox(entryRow, "") :: any) :: TextBox
        nameBox.PlaceholderText = "New profile name"
        nameBox.Position = UDim2.fromOffset(0, 0)
        nameBox.Size = UDim2.new(1, -170, 1, 0)
        nameBox.TextSize = 14
        nameBox.ZIndex = entryRow.ZIndex + 1
        local saveButton: TextButton = (makeButton(entryRow, "SAVE", 10) :: any) :: TextButton
        saveButton.AnchorPoint = Vector2.new(1, 0.5)
        saveButton.Position = UDim2.new(1, -66, 0.5, 0)
        saveButton.Size = UDim2.fromOffset(56, 20)
        saveButton.ZIndex = entryRow.ZIndex + 1
        local panicButton: TextButton = (makeButton(entryRow, "PANIC", 10) :: any) :: TextButton
        panicButton.AnchorPoint = Vector2.new(1, 0.5)
        panicButton.Position = UDim2.new(1, 0, 0.5, 0)
        panicButton.Size = UDim2.fromOffset(56, 20)
        panicButton.ZIndex = entryRow.ZIndex + 1
        trackUiConnection(panicButton.MouseButton1Click:Connect(function(): ()
            panicReset()
            rebuildProfiles()
        end))

        profilesList = (create("Frame", {
            Parent = profilesRecord.window.body,
            Name = "ProfileList",
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 0),
            ZIndex = profilesRecord.window.body.ZIndex + 1,
        }) :: any) :: Frame
        create("UIListLayout", {
            Parent = profilesList,
            Padding = UDim.new(0, WINDOW_GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        rebuildProfiles = function(): ()
            local container: Frame? = profilesList
            if not container then
                return
            end
            for _, child: Instance in ipairs((container :: Frame):GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
            local names: {string} = {}
            for name: string in pairs(profileStore()) do
                table.insert(names, name)
            end
            table.sort(names, function(a: string, b: string): boolean
                local left: any = profileStore()[a]
                local right: any = profileStore()[b]
                local leftAt: number = type(left) == "table"
                    and tonumber(left.savedAt) or 0
                local rightAt: number = type(right) == "table"
                    and tonumber(right.savedAt) or 0
                if leftAt ~= rightAt then
                    return leftAt > rightAt
                end
                return a < b
            end)
            for index: number, name: string in ipairs(names) do
                local snapshot: any = profileStore()[name]
                local row: Frame = (create("Frame", {
                    Parent = container,
                    Name = "Profile_" .. name:gsub("%W", ""),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    LayoutOrder = index,
                    Size = UDim2.new(1, 0, 0, 44),
                    ZIndex = (container :: Frame).ZIndex + 1,
                }) :: any) :: Frame
                create("TextLabel", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                    Name = "Label",
                    BackgroundTransparency = 1,
                    FontFace = CONTROL_FONT,
                    Position = UDim2.fromOffset(6, 2),
                    Size = UDim2.new(1, -180, 0, 18),
                    Text = name,
                    TextColor3 = Theme.text,
                    TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = row.ZIndex + 1,
                })
                local detail: string = "profile"
                if type(snapshot) == "table" then
                    local savedAt: number = tonumber(snapshot.savedAt) or 0
                    local when: string = savedAt > 0
                        and os.date("%Y-%m-%d %H:%M", savedAt)
                        or "unknown date"
                    detail = when
                        .. " · "
                        .. tostring(snapshot.enabledModules or 0)
                        .. " modules on · "
                        .. tostring(snapshot.optionCount or 0)
                        .. " options"
                end
                create("TextLabel", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                    Name = "Detail",
                    BackgroundTransparency = 1,
                    FontFace = CONTROL_FONT,
                    Position = UDim2.fromOffset(6, 22),
                    Size = UDim2.new(1, -180, 0, 16),
                    Text = detail,
                    TextColor3 = Theme.textMuted,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = row.ZIndex + 1,
                })
                local loadButton: TextButton =
                    (makeButton(row, "LOAD", 10) :: any) :: TextButton
                loadButton.AnchorPoint = Vector2.new(1, 0.5)
                loadButton.Position = UDim2.new(1, -56, 0.5, 0)
                loadButton.Size = UDim2.fromOffset(48, 18)
                loadButton.ZIndex = row.ZIndex + 1
                trackUiConnection(loadButton.MouseButton1Click:Connect(function(): ()
                    if applyProfile(name) then
                        notify("loaded profile " .. name)
                        rebuildProfiles()
                    else
                        notify("profile " .. name .. " is corrupted")
                    end
                end))
                local updateButton: TextButton =
                    (makeButton(row, "UPD", 10) :: any) :: TextButton
                updateButton.AnchorPoint = Vector2.new(1, 0.5)
                updateButton.Position = UDim2.new(1, -108, 0.5, 0)
                updateButton.Size = UDim2.fromOffset(44, 18)
                updateButton.ZIndex = row.ZIndex + 1
                trackUiConnection(updateButton.MouseButton1Click:Connect(function(): ()
                    profileStore()[name] = captureProfile()
                    queueConfigSave()
                    notify("updated profile " .. name)
                    rebuildProfiles()
                end))
                local deleteButton: TextButton = (create("TextButton", {
                    Parent = row,
                    Name = "Delete",
                    AutoButtonColor = false,
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                    BackgroundTransparency = 0.5,
                    BorderSizePixel = 0,
                    FontFace = CONTROL_FONT,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -6, 0.5, 0),
                    Size = UDim2.fromOffset(18, 18),
                    Text = "x",
                    TextColor3 = Theme.negative,
                    TextSize = 12,
                    ZIndex = row.ZIndex + 1,
                }) :: any) :: TextButton
                trackUiConnection(deleteButton.MouseButton1Click:Connect(function(): ()
                    profileStore()[name] = nil
                    queueConfigSave()
                    notify("deleted profile " .. name)
                    rebuildProfiles()
                end))
            end
            if profilesRecord then

                if profilesRecord.repack then
                    local rows: {{any}} = {{"New profile name", nil, 60}}
                    for _, name: string in ipairs(names) do
                        table.insert(rows, {name, nil, 64})
                    end
                    profilesRecord.repack(rows)
                end
                profilesRecord.resize()
            end
        end

        trackUiConnection(saveButton.MouseButton1Click:Connect(function(): ()
            local name: string = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then
                notify("enter a profile name")
                return
            end
            profileStore()[name] = captureProfile()
            queueConfigSave()
            nameBox.Text = ""
            rebuildProfiles()
            notify("saved profile " .. name)
        end))

        rebuildProfiles()
        raiseOpen(profilesRecord)
    end

    local addRecord: any = nil
    local addList: Frame? = nil
    local pendingConflict: any = nil
    local rebuildAddList: () -> () = function(): () end

    local function applyBinding(
        binding: any,
        keyCode: Enum.KeyCode,
        clearOther: any
    ): ()
        binding.key = keyCode
        persistBindingKey(binding)
        if binding.refresh then
            binding.refresh()
        end
        if clearOther then
            clearOther.key = Enum.KeyCode.Unknown
            persistBindingKey(clearOther)
            if clearOther.refresh then
                clearOther.refresh()
            end
        end
        pendingConflict = nil
        rebuildKeybinds()
        rebuildAddList()
        notify(featureLabel(tostring(binding.id)) .. " bound to " .. keyCode.Name)
    end

    rebuildAddList = function(): ()
        local container: Frame? = addList
        if not container then
            return
        end
        for _, child: Instance in ipairs((container :: Frame):GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        local order: number = 0
        local function addRow(
            labelText: string,
            valueText: string,
            warning: boolean,
            onClick: ((TextButton) -> ())?
        ): ()
            order += 1
            local row: TextButton = (create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = container,
                Name = "Add_" .. labelText:gsub("%W", ""),
                Active = onClick ~= nil,
                AutoButtonColor = false,
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BackgroundTransparency = onClick ~= nil and 0.5 or 1,
                BorderSizePixel = 0,
                FontFace = CONTROL_FONT,
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
                Text = "",
                ZIndex = (container :: Frame).ZIndex + 1,
            }) :: any) :: TextButton
            create("TextLabel", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
                Name = "Label",
                BackgroundTransparency = 1,
                FontFace = CONTROL_FONT,
                Position = UDim2.fromOffset(6, 0),
                Size = UDim2.new(1, -120, 1, 0),
                Text = labelText,
                TextColor3 = warning and Theme.negative or Theme.text,
                TextSize = 16,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = row.ZIndex + 1,
            })
            local slot: TextButton = (create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
                Name = "Key",
                Active = onClick ~= nil,
                AnchorPoint = Vector2.new(1, 0),
                AutoButtonColor = false,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                FontFace = CONTROL_FONT,
                Position = UDim2.new(1, -6, 0, 0),
                Size = UDim2.fromOffset(110, ROW_HEIGHT),
                Text = valueText,
                TextColor3 = Theme.textMuted,
                TextSize = 16,
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = row.ZIndex + 1,
            }) :: any) :: TextButton
            slot:SetAttribute("CaptureIdleText", valueText)
            if onClick then
                trackUiConnection(row.MouseButton1Click:Connect(function(): ()
                    (onClick :: (TextButton) -> ())(slot)
                end))
                trackUiConnection(slot.MouseButton1Click:Connect(function(): ()
                    (onClick :: (TextButton) -> ())(slot)
                end))
                trackUiConnection(row.MouseEnter:Connect(function(): ()
                    row.BackgroundTransparency = 0.3
                end))
                trackUiConnection(row.MouseLeave:Connect(function(): ()
                    row.BackgroundTransparency = 0.5
                end))
            end
        end

        if pendingConflict then

            local conflict: any = pendingConflict
            addRow(
                conflict.key.Name .. " already binds "
                    .. featureLabel(tostring(conflict.other.id)),
                "",
                true,
                nil
            )
            addRow("Replace it", "", false, function(_slot: TextButton): ()
                applyBinding(conflict.binding, conflict.key, conflict.other)
            end)
            addRow("Keep both", "", false, function(_slot: TextButton): ()
                applyBinding(conflict.binding, conflict.key, nil)
            end)
            addRow("Cancel", "", false, function(_slot: TextButton): ()
                pendingConflict = nil
                rebuildAddList()
            end)
        else
            addRow("Click an action, then press a key", "", false, nil)
            for _, binding: any in ipairs(sortedBindings()) do
                local bound: boolean = binding.key ~= nil
                    and binding.key ~= Enum.KeyCode.Unknown
                addRow(
                    featureLabel(tostring(binding.id)),
                    bound and keyLabel(binding.key.Name) or "—",
                    false,
                    function(slot: TextButton): ()
                        beginKeyCapture(slot, function(keyCode: Enum.KeyCode): ()
                            local other: any = nil
                            for _, candidate: any in pairs(state.shortcutBindings) do
                                if candidate ~= binding
                                    and candidate.key == keyCode then
                                    other = candidate
                                    break
                                end
                            end
                            if other then
                                pendingConflict = {
                                    binding = binding,
                                    key = keyCode,
                                    other = other,
                                }
                                rebuildAddList()
                            else
                                applyBinding(binding, keyCode, nil)
                            end
                        end)
                    end
                )
            end
        end

        if addRecord then
            if addRecord.repack then
                local rows: {{any}} = {
                    {"Click an action, then press a key", nil, 12},
                }
                for _, binding: any in ipairs(sortedBindings()) do
                    table.insert(rows, {
                        featureLabel(tostring(binding.id)),
                        binding.key and binding.key ~= Enum.KeyCode.Unknown
                            and binding.key.Name
                            or "—",
                        12,
                    })
                end
                addRecord.repack(rows)
            end
            addRecord.resize()
        end
    end

    local function openAddKeybind(): ()
        pendingConflict = nil
        if addRecord then
            rebuildAddList()
            raiseOpen(addRecord)
            return
        end
        local screen: Vector2 = viewport()
        addRecord = configWindow("KeybindAdd", "Add Keybind", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 200),
            anchor = keybindsRecord and keybindsRecord.window,
            settingsSized = true,
            packRows = {{"Click an action, then press a key", nil, 12}},
        })
        addList = (create("Frame", {
            Parent = addRecord.window.body,
            Name = "AddList",
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 0),
            ZIndex = addRecord.window.body.ZIndex + 1,
        }) :: any) :: Frame
        create("UIListLayout", {
            Parent = addList,
            Padding = UDim.new(0, WINDOW_GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        rebuildAddList()
        raiseOpen(addRecord)
    end

    local function openKeybinds(): ()
        if keybindsRecord then
            raiseOpen(keybindsRecord)
            rebuildKeybinds()
            return
        end
        local screen: Vector2 = viewport()
        local keybindRows: {{any}} = {
            {"Reset keybinds", nil, 26},
            {"Open menu", keyLabel(state.toggleKey.Name), 12},
        }
        for _, binding: any in pairs(state.shortcutBindings) do
            if binding.key and binding.key ~= Enum.KeyCode.Unknown then
                table.insert(
                    keybindRows,
                    {featureLabel(tostring(binding.id)), binding.key.Name, 12}
                )
            end
        end
        keybindsRecord = configWindow("Keybinds", "Keybinds", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 140),
            anchor = uiRecord and uiRecord.window,
            settingsSized = true,
            packRows = keybindRows,
        })
        keybindsList = (create("Frame", {
            Parent = keybindsRecord.window.body,
            Name = "KeybindList",
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 0),
            ZIndex = keybindsRecord.window.body.ZIndex + 1,
        }) :: any) :: Frame
        create("UIListLayout", {
            Parent = keybindsList,
            Padding = UDim.new(0, WINDOW_GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        actionRow(keybindsRecord, 99, "Add", openAddKeybind)
        actionRow(keybindsRecord, 100, "Reset keybinds", function(): ()
            for _, binding: any in pairs(state.shortcutBindings) do
                binding.key = Enum.KeyCode.Unknown
                persistBindingKey(binding)
                if binding.refresh then
                    binding.refresh()
                end
            end
            rebuildKeybinds()
            notify("keybinds reset")
        end)
        actionRow(keybindsRecord, 101, "Profiles…", openProfiles)
        rebuildKeybinds()
        raiseOpen(keybindsRecord)
    end

    ------------------------------------------------------------------
    -- Mobile controls. Keybinds need a keyboard, so on a touch device the
    -- same slot opens the buttons page instead: every shortcut the menu
    -- exposes can be placed as an on-screen button and restyled (shape,
    -- colour, size, opacity) without editing the config by hand.
    ------------------------------------------------------------------
    local buttonsRecord: any = nil
    local buttonsList: Frame? = nil
    local buttonsAddRecord: any = nil
    local buttonsAddList: Frame? = nil

    local function mobileCallbacks(binding: any): (() -> (), any)
        local hold: boolean = binding.hold == true
        local function press(): ()
            if type(binding.onPress) == "function" then
                binding.onPress()
            end
        end
        local function release(): ()
            if type(binding.onRelease) == "function" then
                binding.onRelease()
            end
        end
        local callback: () -> () = function(): ()
            if not hold then press() end
        end
        if not hold then
            return callback, nil
        end
        return callback, {
            isActive = function(): boolean return true end,
            onPress = press,
            onRelease = release,
        }
    end

    local function mobileUiOrNil(): any
        return state.mobileUi
    end

    local function buttonRow(
        parent: Frame,
        order: number,
        labelText: string,
        valueText: string,
        onClick: () -> ()
    ): TextButton
        local row: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = parent,
            Name = "ButtonRow_" .. labelText:gsub("%W", ""),
            Active = true,
            AutoButtonColor = false,
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 22),
            Text = "",
            ZIndex = parent.ZIndex + 1,
        }) :: any) :: TextButton
        create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
            Name = "Label",
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(6, 0),
            Size = UDim2.new(0.6, -6, 1, 0),
            Text = labelText,
            TextColor3 = Theme.text,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = row.ZIndex + 1,
        })
        create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
            Name = "Value",
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.new(0.6, 0, 0, 0),
            Size = UDim2.new(0.4, -8, 1, 0),
            Text = valueText,
            TextColor3 = Theme.textMuted,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = row.ZIndex + 1,
        })
        trackUiConnection(row.MouseButton1Click:Connect(onClick))
        return row
    end

    local rebuildButtons: () -> () = function(): () end
    local openAddMobileButton: () -> () = function(): () end

    rebuildButtons = function(): ()
        local container: Frame? = buttonsList
        local ui: any = mobileUiOrNil()
        if not container or not ui then
            return
        end
        container:ClearAllChildren()
        local order: number = 1
        local placed: number = 0
        local ids: {string} = {}
        for id: string in pairs(ui.actions) do
            table.insert(ids, id)
        end
        table.sort(ids)
        for _, id: string in ipairs(ids) do
            local record: any = ui.actions[id]
            if record then
                placed += 1
                local shape: string = tostring(record.shape or "Square")
                buttonRow(
                    container,
                    order,
                    tostring(record.label),
                    tostring(record.shape),
                    function(): ()
                        ui.openEditor(record)
                    end
                )
                order += 1
            end
        end
        if placed == 0 then
            buttonRow(container, order, "No buttons yet", "tap Add button", function(): () end)
            order += 1
        end
        local defaults: any = ui.defaults and ui.defaults()
        if defaults then
            buttonRow(
                container,
                order,
                "Default shape",
                tostring(defaults.shape),
                function(): ()
                    local shapes: {string} = ui.shapes
                    local index: number = table.find(shapes, defaults.shape) or 1
                    defaults.shape = shapes[index % #shapes + 1]
                    queueConfigSave()
                    rebuildButtons()
                    notify("new buttons: " .. defaults.shape)
                end
            )
            order += 1
            buttonRow(
                container,
                order,
                "Default colour",
                tostring(defaults.color),
                function(): ()
                    local palette: {string} = ui.palette
                    local index: number = table.find(palette, string.upper(defaults.color)) or 1
                    defaults.color = palette[index % #palette + 1]
                    queueConfigSave()
                    rebuildButtons()
                    notify("new buttons: " .. defaults.color)
                end
            )
            order += 1
        end
        if buttonsRecord then
            buttonsRecord.resize()
        end
    end

    local function openButtons(): ()
        local ui: any = mobileUiOrNil()
        if not ui then
            notify("touch controls are not ready yet")
            return
        end
        if buttonsRecord then
            raiseOpen(buttonsRecord)
            rebuildButtons()
            return
        end
        local screen: Vector2 = viewport()
        buttonsRecord = configWindow("Buttons", "Buttons", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 140),
            anchor = uiRecord and uiRecord.window,
            settingsSized = true,
            packRows = {{"Add button", nil, 26}, {"Reset buttons", nil, 26}},
        })
        buttonsList = (create("Frame", {
            Parent = buttonsRecord.window.body,
            Name = "ButtonList",
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 0),
            ZIndex = buttonsRecord.window.body.ZIndex + 1,
        }) :: any) :: Frame
        create("UIListLayout", {
            Parent = buttonsList,
            Padding = UDim.new(0, WINDOW_GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        actionRow(buttonsRecord, 90, "Add button", openAddMobileButton)
        actionRow(buttonsRecord, 91, "Reset buttons", function(): ()
            ui.resetActions()
            rebuildButtons()
            notify("mobile buttons reset")
        end)
        rebuildButtons()
        raiseOpen(buttonsRecord)
    end

    openAddMobileButton = function(): ()
        local ui: any = mobileUiOrNil()
        if not ui then
            return
        end
        if buttonsAddRecord then
            raiseOpen(buttonsAddRecord)
            return
        end
        local screen: Vector2 = viewport()
        buttonsAddRecord = configWindow("ButtonAdd", "Add button", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 200),
            anchor = buttonsRecord and buttonsRecord.window,
            settingsSized = true,
            packRows = {{"Tap an action to place its button", nil, 12}},
        })
        buttonsAddList = (create("Frame", {
            Parent = buttonsAddRecord.window.body,
            Name = "ButtonAddList",
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 0),
            ZIndex = buttonsAddRecord.window.body.ZIndex + 1,
        }) :: any) :: Frame
        create("UIListLayout", {
            Parent = buttonsAddList,
            Padding = UDim.new(0, WINDOW_GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        local order: number = 1
        for id: string, binding: any in pairs(state.shortcutBindings) do
            local actionId: string = ui.actionId(id)
            if not ui.actions[actionId] then
                local label: string = featureLabel(tostring(id))
                buttonRow(buttonsAddList :: Frame, order, label, "place", function(): ()
                    local callback: () -> (), hold: any = mobileCallbacks(binding)
                    ui.place(actionId, label, callback, hold)
                end)
                order += 1
            end
        end
        if order == 1 then
            buttonRow(buttonsAddList :: Frame, order, "Every action already has a button", "", function(): () end)
        end
        buttonsAddRecord.resize()
        raiseOpen(buttonsAddRecord)
    end

    local windowsRecord: any = nil
    local windowsPanel: any = nil
    local windowOptions: {[string]: boolean} = {}

    local function openWindows(): ()
        local clickGui: any = state.clickGui
        if not windowsRecord then
            local screen: Vector2 = viewport()
            windowsRecord = configWindow("Windows", "Windows", {
                position = Vector2.new(screen.X - WINDOW_WIDTH * 3 - 44, 140),
                anchor = uiRecord and uiRecord.window,
                settingsSized = true,
                packRows = {{"Combat", "ON", 20}},
            })
            windowsPanel = panelFor(windowsRecord, "ClickGUI.Windows")
        end
        if clickGui and windowsPanel then
            for _, name: string in ipairs(clickGui.order or {}) do
                if not windowOptions[name] then
                    windowOptions[name] = true
                    local category: any = clickGui.categories[name]
                    addToggleOption(windowsPanel, name, category.window.userVisible ~= false, function(value: boolean): ()
                        category.window.userVisible = value
                        category.window:SetVisible(value and state.visible == true)
                    end)
                end
            end
        end
        raiseOpen(windowsRecord)
    end

    local function applySavedWindowVisibility(): boolean
        local clickGui: any = state.clickGui
        if not clickGui or type(clickGui.order) ~= "table" then
            return false
        end
        for _, name: string in ipairs(clickGui.order) do
            local category: any = clickGui.categories
                and clickGui.categories[name]
            if category and category.window then
                local optionKey: string = "ClickGUI.Windows."
                    .. tostring(name):gsub("%W", "")
                if configData.states[optionKey] == false then
                    category.window.userVisible = false
                    pcall(function(): ()
                        category.window:SetVisible(false)
                    end)
                end
            end
        end
        return true
    end

    task.spawn(function(): ()

        for _ = 1, 15 do
            applySavedWindowVisibility()
            task.wait(1)
        end
    end)

    local optionsRecord: any = nil

    local actionEntries: {any} = {}
    local actionIndex: {[string]: any} = {}
    local actionSequence: number = 0
    local refreshActionRows: () -> () = function(): () end

    state.wurstOptions = {
        RegisterAction = function(id: any, label: any, callback: any, options: any?): any
            local key: string = tostring(id)
            local configuration: any = options or {}
            local entry: any = actionIndex[key]
            if entry == nil then
                actionSequence += 1
                entry = {id = key, order = actionSequence}
                actionIndex[key] = entry
                table.insert(actionEntries, entry)
            end
            entry.label = tostring(label)
            entry.callback = callback
            entry.enabled = configuration.enabled ~= false
            entry.visible = configuration.visible ~= false
            entry.static = configuration.static == true
            if entry.handle == nil then
                local handle: any = {}
                function handle.SetLabel(text: any): ()
                    entry.label = tostring(text)
                    if entry.rowLabel and entry.rowLabel.Parent then
                        entry.rowLabel.Text = entry.label
                    end
                end
                function handle.SetEnabled(value: boolean): ()
                    entry.enabled = value == true
                    refreshActionRows()
                end
                function handle.SetVisible(value: boolean): ()
                    entry.visible = value == true
                    refreshActionRows()
                end
                function handle.Unregister(): ()
                    state.wurstOptions.UnregisterAction(entry.id)
                end
                entry.handle = handle
            end
            if configuration.shortcut == true
                and entry.shortcutBound ~= true
                and type(bindActionShortcut) == "function" then
                entry.shortcutBound = true
                bindActionShortcut(nil, "Action " .. key, entry.label, function(): ()
                    state.wurstOptions.InvokeAction(key)
                end)
            end
            refreshActionRows()
            return entry.handle
        end,
        UnregisterAction = function(id: any): boolean
            local key: string = tostring(id)
            local entry: any = actionIndex[key]
            if entry == nil then
                return false
            end
            actionIndex[key] = nil
            local at: number? = table.find(actionEntries, entry)
            if at then
                table.remove(actionEntries, at)
            end
            refreshActionRows()
            return true
        end,
        InvokeAction = function(id: any): boolean
            local entry: any = actionIndex[tostring(id)]
            if entry == nil
                or entry.enabled ~= true
                or entry.visible ~= true
                or type(entry.callback) ~= "function" then
                return false
            end
            local ok: boolean, failure: any = pcall(entry.callback)
            if not ok then
                warn("[Wurst] Action " .. tostring(id) .. ": " .. tostring(failure))
            end
            return ok
        end,
        List = function(): {string}
            local ids: {string} = {}
            for _, entry: any in ipairs(actionEntries) do
                table.insert(ids, entry.id)
            end
            return ids
        end,
    }

    refreshActionRows = function(): ()
        if not optionsRecord then
            return
        end
        local body: any = optionsRecord.window.body
        for _, child: Instance in ipairs(body:GetChildren()) do
            if child:IsA("GuiObject")
                and child:GetAttribute("RegisteredAction") == true then
                child:Destroy()
            end
        end
        local packRows: {{any}} = {}
        for _, entry: any in ipairs(actionEntries) do
            if entry.visible then
                table.insert(packRows, {entry.label, nil, 26})
                if entry.static then

                    local label: TextLabel = (create("TextLabel", {
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = body,
                        Name = "Static_" .. entry.id:gsub("%W", ""),
                        BackgroundTransparency = 1,
                        FontFace = CONTROL_FONT,
                        LayoutOrder = entry.order,
                        Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
                        Text = "  " .. entry.label,
                        TextColor3 = Theme.textMuted,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        ZIndex = body.ZIndex + 1,
                    }) :: any) :: TextLabel
                    label:SetAttribute("RegisteredAction", true)
                    entry.rowLabel = label
                else
                    local row: TextButton = actionRow(
                        optionsRecord,
                        entry.order,
                        entry.label,
                        function(): ()
                            state.wurstOptions.InvokeAction(entry.id)
                        end
                    )
                    row:SetAttribute("RegisteredAction", true)
                    local rowLabel: any = row:FindFirstChild("Label")
                    entry.rowLabel = rowLabel
                    if not entry.enabled then
                        row.Active = false
                        if rowLabel then
                            rowLabel.TextColor3 = Theme.textMuted
                        end
                    end
                end
            end
        end
        if optionsRecord.repack then
            optionsRecord.repack(packRows)
        end
        optionsRecord.resize()
    end

    local reinjectBusy: boolean = false
    local reinjectHandle: any = nil
    local function runReinject(): ()
        local function setReinjectLabel(text: string): ()
            if reinjectHandle then
                reinjectHandle.SetLabel(text)
            end
        end
        if reinjectBusy then
            return
        end
        local compiler: any = (getfenv() :: any).loadstring
        if type(compiler) ~= "function" then
            notify("reinject unavailable")
            return
        end
        reinjectBusy = true
        setReinjectLabel("Downloading…")
        local sourceUrls: {string} = {
            REPOSITORY_RAW_BASE .. "src/Wurst.lua",
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
            setReinjectLabel("Reinject latest")
            notify("download failed")
            warn("[Wurst] Reinject download: "
                .. table.concat(downloadFailures, " | "))
            return
        end
        local compiled: any = nil
        local compileError: any = nil
        local compiledOk: boolean, compileResult: any, returnedError: any = pcall(
            compiler,
            sourceOrError,
            "@src/Wurst.lua"
        )
        if compiledOk then
            compiled = compileResult
            compileError = returnedError
        else
            compileError = compileResult
        end
        if type(compiled) ~= "function" then
            reinjectBusy = false
            setReinjectLabel("Reinject latest")
            notify("compile failed")
            warn("[Wurst] Reinject compile: " .. tostring(compileError))
            return
        end
        setReinjectLabel("Restarting…")
        task.defer(function(): ()
            local executed: boolean, executionError: any = xpcall(
                compiled,
                debug.traceback
            )
            if not executed then
                reinjectBusy = false
                setReinjectLabel("Reinject latest")
                warn("[Wurst] Reinject runtime: " .. tostring(executionError))
            end
        end)
    end

    local destructHandle: any = nil
    local function runDestruct(): ()
        if destructHandle then
            destructHandle.SetLabel("Removing…")
        end
        task.defer(function(): ()
            local destruct: any = state.destruct
            if type(destruct) ~= "function" then

                pcall(function(): ()
                    ScreenGui:Destroy()
                end)
                return
            end
            local ok: boolean, failure: any = pcall(destruct)
            if not ok then
                warn("[Wurst] Destruct: " .. tostring(failure))
                pcall(function(): ()
                    ScreenGui:Destroy()
                end)
            end
        end)
    end

    local function runResetLayout(): ()

        configData.ui.windows = {}
        queueConfigSave()
        for _, window: any in ipairs(windows.list or {}) do
            window.userMoved = nil
        end
        if state.clickGui and state.clickGui.Retile then
            state.clickGui.Retile()
        end
        for _, window: any in ipairs(windows.list or {}) do
            if window.featureSettings or window.managementWindow then
                if window.root.Visible and windows.PlaceWindow then
                    windows.PlaceWindow(window, {force = true})
                else
                    window.stalePlacement = true
                end
            end
        end
        for _, record: any in ipairs(Settings.records) do
            if not record.window.root.Visible then
                record.placed = false
            end
        end
        notify("layout reset")
    end

    local recognised: string = GAME_CHECK.MM2Active and "MM2"
        or GAME_CHECK.TRSActive and "TRS"
        or GAME_CHECK.VDActive and "VD"
        or GAME_CHECK.BedFightActive and "BedFight"
        or "Universal only"

    reinjectHandle = state.wurstOptions.RegisterAction(
        "Reinject", "Reinject latest", runReinject
    )
    destructHandle = state.wurstOptions.RegisterAction(
        "Destruct", "Destruct", runDestruct
    )
    state.wurstOptions.RegisterAction("ResetLayout", "Reset layout", runResetLayout)

    local _ = recognised

    local function openWurstOptions(): ()
        if optionsRecord then
            raiseOpen(optionsRecord)
            return
        end
        local screen: Vector2 = viewport()
        optionsRecord = configWindow("WurstOptions", "Wurst Options", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 220),
            anchor = uiRecord and uiRecord.window,
            settingsSized = true,
            packRows = {{"Reinject latest", nil, 26}},
        })
        refreshActionRows()
        raiseOpen(optionsRecord)
    end

    local screen: Vector2 = viewport()
    -- Small build watermark on the window the user opens first: the
    -- short stamp ("v95") so a screenshot alone says which build it
    -- is, without opening anything.
    local versionTag: string = string.match(
        tostring(SOURCE_STAMP or ""),
        "^v%d+"
    ) or tostring(SOURCE_STAMP or "")
    uiRecord = configWindow("UISettings", "UI Settings · " .. versionTag, {
        position = Vector2.new(screen.X - WINDOW_WIDTH - 12, 64),
        closable = false,
        settingsSized = false,
        packRows = {
            {"HackList", nil, 26},
            {state.isMobile and "Buttons" or "Keybinds", nil, 26},
            {"Windows", nil, 26},
            {"WurstOptions", nil, 26},
            {"Background", "#404040"},
            {"Accent", "#101010"},
            {"Text", "#F0F0F0"},
            {"Opacity", "0.85"},
        },
    })
    uiRecord.open = true

    actionRow(uiRecord, 1, "HackList", openHackList)
    -- A phone has no keyboard: the row that would open keybinds opens the
    -- touch-button page instead. Desktop keeps the keybinds window untouched.
    if state.isMobile then
        actionRow(uiRecord, 2, "Buttons", openButtons)
    else
        actionRow(uiRecord, 2, "Keybinds", openKeybinds)
    end
    actionRow(uiRecord, 3, "Windows", openWindows)
    actionRow(uiRecord, 4, "WurstOptions", openWurstOptions)

    local uiPanel: any = panelFor(uiRecord, "ClickGUI")

    uiPanel.optionCount = 4

    local uiSettingsValues: {[string]: any} = {}
    state.uiSettings = uiSettingsValues

    -- Palette defaults come from the LIVE theme so the swatches always show
    -- what the UI is actually drawing (the old constants drifted from the
    -- real preset and misled the colour pickers).
    local CLICKGUI_ENABLED: Color3 = Theme.enabled
    -- Theme.arrows is a v26 token: older saved themes (and the default
    -- "Wurst" preset before v26.1) never wrote it. Missing token must
    -- never abort this page — fall back to the enabled colour.
    local CLICKGUI_ARROWS: Color3 = Theme.arrows or Theme.enabled
        or Color3.fromRGB(0, 204, 0)
    local uiPaletteRows: {[string]: Frame} = {}
    local function paintPalette(labelText: string, color: Color3): ()
        local option: Frame? = uiPaletteRows[labelText]
        if not option then
            return
        end
        local bar: Frame? = option:FindFirstChild("ColorBar") :: Frame?
        local hex: TextLabel? = option:FindFirstChild("HexValue") :: TextLabel?
        if bar then
            bar.BackgroundColor3 = color
        end
        if hex then
            hex.Text = string.format(
                "#%02X%02X%02X",
                math.floor(color.R * 255 + 0.5),
                math.floor(color.G * 255 + 0.5),
                math.floor(color.B * 255 + 0.5)
            )
        end
    end
    -- A single bad palette row (missing theme token, malformed saved
    -- colour) must never kill the whole Settings window — v26 regressed
    -- exactly here when Theme.arrows was nil and hexOf(nil) aborted
    -- SettingsPage.init before the "Show dock" toggle could restore the
    -- saved dock state. Isolate the rows and keep building the page.
    local PALETTE_ROWS: {any} = {
        {label = "Background", default = Theme.background, tokens = {"surface", "background"}},
        {label = "Accent", default = Theme.accent, tokens = {"accent", "outline"}},
        {label = "Text", default = Theme.text, tokens = {"text", "accentText"}},
        {label = "Enabled", default = Theme.enabled, tokens = {"enabled"}},
        {label = "Arrows", default = Theme.arrows, tokens = {"arrows"}},
    }
    -- Re-apply the saved palette when the page builds: the theme starts
    -- from the preset on every execution, so without this the chosen
    -- colours were forgotten on rejoin and the UI came back with preset
    -- colours while the swatches still showed the saved ones.
    if ThemeEngine and type(ThemeEngine.SetMany) == "function" then
        for _, row: any in ipairs(PALETTE_ROWS) do
            local saved: Color3? = colorFromConfig(
                configData.values[
                    uiPanel.configKey .. "." .. row.label:gsub("%W", "")
                ],
                nil
            )
            if saved then
                local updates: {[string]: Color3} = {}
                for _, token: string in ipairs(row.tokens) do
                    updates[token] = saved
                end
                ThemeEngine.SetMany(updates)
            end
        end
    end
    local paletteOk: boolean, paletteError: string? = pcall(function(): ()
        for _, row: any in ipairs(PALETTE_ROWS) do
            local tokens: {string} = row.tokens
            local labelText: string = row.label
            local swatch: TextButton? = addColorOption(
                uiPanel,
                labelText,
                row.default or Theme.text,
                function(color: Color3): ()
                    uiSettingsValues[labelText] = color

                    if ThemeEngine and type(ThemeEngine.SetMany) == "function" then
                        local updates: {[string]: Color3} = {}
                        for _, token: string in ipairs(tokens) do
                            updates[token] = color
                        end
                        ThemeEngine.SetMany(updates)
                    elseif ThemeEngine and type(ThemeEngine.Set) == "function" then
                        for _, token: string in ipairs(tokens) do
                            ThemeEngine.Set(token, color)
                        end
                    end
                end
            )
            if swatch and swatch.Parent and swatch.Parent:IsA("Frame") then
                uiPaletteRows[labelText] = swatch.Parent :: Frame
            end
        end
    end)
    if not paletteOk then
        warn("[Wurst:Settings] palette rows skipped: " .. tostring(paletteError))
    end

    addNumberOption(uiPanel, "Opacity", OPACITY, 0.15, 0.85, function(value: number): ()
        uiSettingsValues["Opacity"] = value
        windows.SetOpacity(value)
    end)

    uiSettingsValues["Tooltip opacity"] = TOOLTIP_OPACITY
    if state.featureTooltip then
        state.featureTooltip.BackgroundTransparency = 1 - TOOLTIP_OPACITY
    end

    uiSettingsValues["Max height"] = MAX_HEIGHT
    state.uiMaxHeight = MAX_HEIGHT
    uiSettingsValues["Max settings height"] = MAX_SETTINGS_HEIGHT
    maxSettingsHeight = MAX_SETTINGS_HEIGHT
    state.uiMaxSettingsHeight = MAX_SETTINGS_HEIGHT

    uiSettingsValues["Menu style"] = "Wurst"

    -- v162: the menu's own scale, so "make it like the older build" is a
    -- number and not a code change. It only touches the ClickGui UIScale; the
    -- HUD, the dock and the tooltips keep their own sizes.
    local themeShape: any = ThemeEngine and ThemeEngine.shape
    local initialScale: number = themeShape and tonumber(themeShape.scale) or 1
    uiSettingsValues["Menu scale"] = initialScale
    addNumberOption(uiPanel, "Menu scale", initialScale, 0.7, 1.3,
        function(value: number): ()
            local shape: any = ThemeEngine and ThemeEngine.shape
            if not shape then
                return
            end
            shape.scale = value
            uiSettingsValues["Menu scale"] = value
            configData.values["UI.MenuScale"] = value
            queueConfigSave()
            if type(state.refreshLayout) == "function" then
                state.refreshLayout(true)
            end
        end)

    addToggleOption(uiPanel, "Keep after teleport", true, function(value: boolean): ()
        uiSettingsValues["Keep after teleport"] = value
        local persist: any = state.teleportPersist
        if persist and type(persist.SetEnabled) == "function" then
            persist.SetEnabled(value)
            if value and persist.supported ~= true then
                notify("queue on teleport unavailable — "
                    .. "the menu cannot follow teleports here")
            end
        end
    end)

    local touchPrimary: boolean = state.isMobile == true
    if not touchPrimary then
        addToggleOption(uiPanel, "Show dock", false, function(value: boolean): ()
            uiSettingsValues["Show dock"] = value
            state.uiShowDock = value
            if state.dock and type(state.dock.SetVisible) == "function" then
                state.dock.SetVisible(value)
            end
        end)
    end

    -- v162: what the menu itself costs, on demand. The overlay shows it live,
    -- but the useful question after a hitch is "what was running", and that is
    -- one press away here. It also restarts the counter, so the next press
    -- describes the last minute and not the session.
    host.addActionOption(uiPanel, "Perf report", function(): ()
        local performance: any = state.performance or {}
        local report: string = "no report"
        if type(state.perfReport) == "function" then
            local ok: boolean, text: any = pcall(state.perfReport)
            if ok and type(text) == "string" then
                report = text
            end
        end
        print(report)
        local worst: string = performance.spikeTask
            and (" · " .. tostring(performance.spikeTask))
            or ""
        notify(string.format(
            "FPS %.0f · menu %.2f+%.2f ms · spikes %d (worst %.0f ms%s)",
            tonumber(performance.fps) or 0,
            tonumber(performance.tasksMs) or 0,
            tonumber(performance.renderMs) or 0,
            tonumber(performance.spikeCount) or 0,
            tonumber(performance.worstSpikeMs) or 0,
            worst
        ))
        print("[" .. "perf" .. "] counter reset")
        performance.spikeCount = 0
        performance.worstSpikeMs = 0
        performance.spikeTask = nil
        performance.spikeAt = nil
        performance.spikeMs = 0
    end, "Prints FPS, the menu's own cost and the heaviest modules to the console, "
        .. "then restarts the spike counter. Press it, play a minute, press it "
        .. "again: the second line describes what just happened.")

    host.addActionOption(uiPanel, "Move dock", function(): ()
        if state.dock and state.dock.BeginMove then state.dock.BeginMove() end
    end, "Temporarily show the dock. Drag and release to save its position; Escape cancels. Show dock still controls visibility.")

    uiRecord.placed = true
    if windows.ReflowWindow then
        windows.ReflowWindow(uiRecord.window)
    end

    if state.bitmapText and type(state.bitmapText.onReady) == "table" then
        table.insert(state.bitmapText.onReady, function(): ()
            for _, record: any in ipairs(Settings.records) do
                if record.repack then
                    record.repack()
                end
            end
        end)
    end

    state.addMenuVisibilityListener(function(visible: boolean): ()
        for _, record: any in ipairs(Settings.records) do
            if not visible and record.window.pinned then
                continue
            end
            if visible then
                record.window:SetVisible(record.open)
            else
                record.open = record.window.root.Visible
                record.window:SetVisible(false)
            end
        end
    end)
    for _, record: any in ipairs(Settings.records) do
        record.window:SetVisible(state.visible == true and record.open)
    end

    Settings.ui = uiRecord
    Settings.openKeybinds = openKeybinds
    Settings.openProfiles = openProfiles
    Settings.openHackList = openHackList
    Settings.openWurstOptions = openWurstOptions

    activeCleanup = function(): ()
        for _, record: any in ipairs(Settings.records) do
            pcall(function(): ()
                record.window:Destroy()
            end)
        end
        Settings.records = {}
        for _, connection: RBXScriptConnection in ipairs(Settings.connections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        Settings.connections = {}
        state.uiSettings = nil
        state.wurstOptions = nil
    end
    Module.Initialized = true
    return Settings
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
