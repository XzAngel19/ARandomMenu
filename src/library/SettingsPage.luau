--!strict
--
-- The configuration surface, replicated from Wurst.
--
-- Wurst configures itself through ClickGUI windows: a **UI Settings** window
-- that carries four feature shortcuts (WurstLogo, HackList, Keybinds, Wurst
-- Options) and the ClickGUI hack's own settings, and a closable settings
-- window per feature behind each shortcut. This file builds exactly that,
-- with Wurst's setting names, types and defaults — the parity gate reads the
-- constants below against `docs/design/prototype/spec.json` and fails a
-- drifted default, naming both sides.
--
-- The page this file used to build — one scroll of text-scale, interface
-- font, blur and mobile-launcher rows — was the old menu's Config. tab.
-- Wurst has none of those, and the tab that hosted the page is already
-- demolished; what was still functional in it (the menu key, reinject,
-- destruct, the game check) lives on in the Wurst Options window, which is
-- where Wurst keeps client management.

local Module = {
    Name = "SettingsPage",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- The prototype's UI Settings window width; category windows stay at 160.
local WINDOW_WIDTH: number = 214
local ROW_HEIGHT: number = 22
local WINDOW_GAP: number = 2
-- The prototype's title bar — Wurst's 13 logical pixels at GUI scale 2. The
-- parity gate reads this name in every scanned file, so it has to agree
-- with WindowManager's.
local TITLE_HEIGHT: number = 26

function Module.init(context: any): any
    -- Wurst's defaults, verbatim (docs/wurst-features.md). A value that is
    -- not what a fresh Wurst install shows does not belong in this block.
    -- Inside init because Color3 only exists once the shell's environment
    -- is installed; the parity gate still reads the names.
    local OPACITY: number = 0.5
    local TOOLTIP_OPACITY: number = 0.75
    local MAX_HEIGHT: number = 200
    local MAX_SETTINGS_HEIGHT: number = 200
    local CLICKGUI_BACKGROUND: Color3 = Color3.fromRGB(64, 64, 64)
    local CLICKGUI_ACCENT: Color3 = Color3.fromRGB(16, 16, 16)
    local CLICKGUI_TEXT: Color3 = Color3.fromRGB(240, 240, 240)
    local HACKLIST_MODE: string = "Auto"
    local HACKLIST_POSITION: string = "Left"
    local HACKLIST_COLOR: Color3 = Color3.fromRGB(255, 255, 255)
    local HACKLIST_SORT_BY: string = "Name"
    local HACKLIST_REVERSE: boolean = false
    local HACKLIST_ANIMATIONS: boolean = true
    local WURSTLOGO_BACKGROUND: Color3 = Color3.fromRGB(255, 255, 255)
    local WURSTLOGO_TEXT: Color3 = Color3.fromRGB(0, 0, 0)
    local WURSTLOGO_VISIBILITY: string = "Always"

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
    local GAME_CHECK: any = host.GAME_CHECK
    local ScreenGui: any = host.ScreenGui
    local allFeatures: {any} = host.allFeatures or {}
    local REPOSITORY_RAW_BASE: any = host.REPOSITORY_RAW_BASE
    local RUNTIME_SAFETY_SOURCE_URL: any = host.RUNTIME_SAFETY_SOURCE_URL
    local RUNTIME_COMPATIBILITY_MARKER: any = host.RUNTIME_COMPATIBILITY_MARKER
    local SOURCE_STAMP: any = host.SOURCE_STAMP
    -- The option builders, under the names every module calls them with.
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addCycleOption: any = host.addCycleOption
    local addColorOption: any = host.addColorOption
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

    local windows: any = state.windows
    if not windows then
        error("SettingsPage requires the window manager")
    end

    local Settings: any = {
        records = {} :: {any},
        connections = {} :: {RBXScriptConnection},
    }

    local function viewport(): Vector2
        -- The manager's logical space — window offsets under the ClickGUI's
        -- UIScale — not the camera's raw pixels, which differ at any scale
        -- other than 1 and put "top right" off the visible screen.
        if type(windows.LogicalViewport) == "function" then
            return windows.LogicalViewport()
        end
        local camera: Camera? = workspace.CurrentCamera
        return camera and (camera :: Camera).ViewportSize or Vector2.new(1280, 720)
    end

    -- The live "Max settings height" value; 0 means no limit, as Wurst's
    -- tooltip says. The UI Settings window itself obeys "Max height" through
    -- state.uiMaxHeight, like every other ClickGUI window.
    local maxSettingsHeight: number = MAX_SETTINGS_HEIGHT

    -- One window of setting lines. `settingsSized` windows follow the "Max
    -- settings height" slider; the UI Settings window follows "Max height".
    -- Wurst packs a settings window to its content — no window is 200 px
    -- because 200 was convenient. Monocraft advances ~12 px per glyph at the
    -- 16 px bitmap size, so a row's natural width is estimable without
    -- TextService, which the environment does not publish: label + gap +
    -- value + whatever the row appends (an arrow box, a checkbox).
    local function textWidth(text: any): number
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
        local width: number = tonumber(definition.width) or WINDOW_WIDTH
        local window: any = windows.Create({
            id = id,
            title = title,
            size = Vector2.new(width, 30),
            position = definition.position,
            closable = definition.closable ~= false,
        })
        -- Every management window is placed by the same manager contract the
        -- feature settings use; the anchor is the window this one opened
        -- from, so Keybinds and Wurst Options land beside UI Settings
        -- instead of on the crossed hard-coded spots the capture showed.
        window.managementWindow = true
        if definition.anchor ~= nil then
            window.placementAnchor = definition.anchor
        end
        -- Every label, value and action row this window will ever hold
        -- renders on the bitmap contract; the sweep follows rows built
        -- later and its connection dies with the window.
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
            local wanted: number = math.min(
                TITLE_HEIGHT + layout.AbsoluteContentSize.Y + WINDOW_GAP * 2,
                limit
            )
            window.fullHeight = wanted
            if not window.collapsed then
                window.root.Size = UDim2.fromOffset(width, wanted)
            end
            -- The second placement, not a bare clamp: a window that chose
            -- its spot at birth height and grew must move to a free
            -- rectangle rather than end up over a neighbour. A hand-moved
            -- window is only clamped back on screen.
            if windows.ReflowWindow then
                windows.ReflowWindow(window)
            elseif windows.ClampWindow then
                windows.ClampWindow(window)
            end
        end
        record.resize = resize
        table.insert(
            Settings.connections,
            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
        )
        resize()
        table.insert(Settings.records, record)
        return record
    end

    -- The adapter the option builders expect: they were written for a card's
    -- expansion panel, and a configuration window is the same column of
    -- lines with a window for a parent.
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

    -- A flat row that opens something: Wurst's feature buttons in UI
    -- Settings, and the manager buttons everywhere else. No tween — nothing
    -- in Wurst's ClickGUI animates a button.
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
        -- The feature shortcut's arrow is the same pixel-drawn green triangle
        -- every other Wurst arrow is, pointing right: it opens a window.
        drawPixelIcon(arrowBox, "right", Color3.fromRGB(0, 204, 0))
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
        -- First open runs the manager's placement — content is complete by
        -- now, so the window is measured at its real size, anchored to the
        -- window it opened from, and lands on a rectangle that overlaps
        -- nothing. A saved manual position wins inside PlaceWindow itself.
        if not record.placed then
            record.placed = true
            if windows.PlaceWindow then
                windows.PlaceWindow(record.window)
            end
        end
        record.window:SetVisible(true)
    end

    -- ------------------------------------------------------------ WurstLogo
    -- Forward-declared: the lazy windows anchor their placement to the UI
    -- Settings window they open from, which is built below them.
    local uiRecord: any = nil
    local logoRecord: any = nil
    local function openWurstLogo(): ()
        if logoRecord then
            raiseOpen(logoRecord)
            return
        end
        local screen: Vector2 = viewport()
        logoRecord = configWindow("WurstLogo", "WurstLogo", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 120),
            anchor = uiRecord and uiRecord.window,
            settingsSized = true,
            -- Packed to its own content, as Wurst sizes it: the combo's
            -- longest value plus its arrow decides the width.
            width = packedWidth({
                {"Background", "#FFFFFF"},
                {"Text", "#000000"},
                {"Visibility", "Only when outdated", 26},
            }),
        })
        local panel: any = panelFor(logoRecord, "WurstLogo")
        addColorOption(panel, "Background", WURSTLOGO_BACKGROUND, function(color: Color3): ()
            if state.wurstLogo then
                state.wurstLogo.SetBackground(color)
            end
        end)
        addColorOption(panel, "Text", WURSTLOGO_TEXT, function(color: Color3): ()
            if state.wurstLogo then
                state.wurstLogo.SetTextColor(color)
            end
        end)
        local visibilityValues: {string} = {"Always", "Only when outdated"}
        addCycleOption(
            panel,
            "Visibility",
            visibilityValues,
            table.find(visibilityValues, WURSTLOGO_VISIBILITY) or 1,
            function(value: string): ()
                if state.wurstLogo then
                    state.wurstLogo.SetVisibility(value)
                end
            end
        )
        raiseOpen(logoRecord)
    end

    -- ------------------------------------------------------------- HackList
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
            width = packedWidth({
                {"Mode", "Hidden", 26},
                {"Position", "Right", 26},
                {"Color", "#FFFFFF"},
                {"Sort by", "Width", 26},
                {"Reverse sorting", nil, 30},
                {"Animations", nil, 30},
            }),
        })
        local panel: any = panelFor(hackListRecord, "HackList")
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
        local positions: {string} = {"Left", "Right"}
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
        raiseOpen(hackListRecord)
    end

    -- ------------------------------------------------------------- Keybinds
    -- Wurst's Keybind Manager: every bound key in one list, rebindable, a
    -- Reset that restores the defaults (here: nothing bound, the menu key
    -- untouched), and Profiles. Ours are the key slots the cards already
    -- own — this window is one place to see and edit all of them.
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

        -- Two rows on one key is a fight the player cannot see anywhere
        -- else; the manager paints both slots in the warning colour.
        local keyUses: {[string]: number} = {}
        for _, binding: any in pairs(state.shortcutBindings) do
            if binding.key and binding.key ~= Enum.KeyCode.Unknown then
                local name: string = binding.key.Name
                keyUses[name] = (keyUses[name] or 0) + 1
            end
        end

        local order: number = 0
        -- A key is compact right-aligned text, not a capsule: Wurst's
        -- keybind list is two columns of words. The text itself is the
        -- rebind target, wide enough that RightControl never truncates,
        -- and a conflicted key is painted in the warning colour.
        local function keybindRow(labelText: string, slotText: string, conflicted: boolean, onSlot: (TextButton) -> ()): ()
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
        end

        -- The menu key first: it is the one bind that can lock a player out,
        -- which is exactly why Wurst's own description of WurstOptions
        -- mentions restoring keybinds.
        if not UserInputService.TouchEnabled then
            keybindRow("Open menu", state.toggleKey.Name, false, function(slot: TextButton): ()
                if state.keyCaptureCancel then
                    state.keyCaptureCancel()
                end
                state.keybindButton = slot
                state.waitingForKey = true
                slot.Text = "..."
                setKeySlotCapture(slot, true)
            end)
        end

        -- Only the menu key and the bindings that exist. Wurst's manager
        -- lists keybinds, not one empty capsule per module — an unbound
        -- module simply is not a keybind. New keys are still made on the
        -- card slots (touch) or by loading a profile.
        for _, binding: any in ipairs(sortedBindings()) do
            local bound: boolean = binding.key ~= nil
                and binding.key ~= Enum.KeyCode.Unknown
            if not bound then
                continue
            end
            local slotText: string = binding.key.Name
            local conflicted: boolean = (keyUses[binding.key.Name] or 0) > 1
            keybindRow(featureLabel(tostring(binding.id)), slotText, conflicted, function(slot: TextButton): ()
                beginKeyCapture(slot, function(keyCode: Enum.KeyCode): ()
                    -- Pressing the bound key again clears it, the same
                    -- gesture every card slot already understands.
                    binding.key = keyCode == binding.key
                        and Enum.KeyCode.Unknown
                        or keyCode
                    persistBindingKey(binding)
                    if binding.refresh then
                        binding.refresh()
                    end
                    rebuildKeybinds()
                end)
            end)
        end

        if keybindsRecord then
            keybindsRecord.resize()
        end
    end

    -- ------------------------------------------------------------- Profiles
    -- Wurst's keybind profiles are .json files next to keybinds.json. Ours
    -- live inside the same per-game profile store everything else already
    -- persists in — a second file format for one window would be invention.
    local function profileStore(): any
        if type(configData.values.KeybindProfiles) ~= "table" then
            configData.values.KeybindProfiles = {}
        end
        return configData.values.KeybindProfiles
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
        profilesRecord = configWindow("KeybindProfiles", "Keybind Profiles", {
            position = Vector2.new(screen.X - WINDOW_WIDTH * 2 - 32, 260),
            anchor = keybindsRecord and keybindsRecord.window,
            settingsSized = true,
        })

        -- New profile: a name and a button, like Wurst's New Profile dialog.
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
        nameBox.Size = UDim2.new(1, -54, 1, 0)
        nameBox.TextSize = 11
        nameBox.ZIndex = entryRow.ZIndex + 1
        local saveButton: TextButton = (makeButton(entryRow, "SAVE", 9) :: any) :: TextButton
        saveButton.AnchorPoint = Vector2.new(1, 0.5)
        saveButton.Position = UDim2.new(1, 0, 0.5, 0)
        saveButton.Size = UDim2.fromOffset(48, 18)
        saveButton.ZIndex = entryRow.ZIndex + 1

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
            table.sort(names)
            for index: number, name: string in ipairs(names) do
                local row: Frame = (create("Frame", {
                    Parent = container,
                    Name = "Profile_" .. name:gsub("%W", ""),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    LayoutOrder = index,
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
                    Size = UDim2.new(1, -60, 1, 0),
                    Text = name,
                    TextColor3 = Theme.text,
                    TextSize = 11.5,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = row.ZIndex + 1,
                })
                local loadButton: TextButton = (makeButton(row, "LOAD", 9) :: any) :: TextButton
                loadButton.AnchorPoint = Vector2.new(1, 0.5)
                loadButton.Position = UDim2.new(1, -6, 0.5, 0)
                loadButton.Size = UDim2.fromOffset(48, 16)
                loadButton.ZIndex = row.ZIndex + 1
                trackUiConnection(loadButton.MouseButton1Click:Connect(function(): ()
                    local snapshot: any = profileStore()[name]
                    if type(snapshot) ~= "table" then
                        return
                    end
                    for _, binding: any in pairs(state.shortcutBindings) do
                        local savedName: any = snapshot[tostring(binding.id)]
                        local savedKey: Enum.KeyCode? = nil
                        if type(savedName) == "string" and savedName ~= "" then
                            savedKey = (Enum.KeyCode :: any)[savedName]
                        end
                        binding.key = savedKey or Enum.KeyCode.Unknown
                        persistBindingKey(binding)
                        if binding.refresh then
                            binding.refresh()
                        end
                    end
                    rebuildKeybinds()
                    notify("Keybind profile loaded: " .. name)
                end))
            end
            if profilesRecord then
                profilesRecord.resize()
            end
        end

        trackUiConnection(saveButton.MouseButton1Click:Connect(function(): ()
            local name: string = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then
                notify("Keybind profile: enter a name first")
                return
            end
            local snapshot: {[string]: string} = {}
            for _, binding: any in pairs(state.shortcutBindings) do
                if binding.key ~= Enum.KeyCode.Unknown then
                    snapshot[tostring(binding.id)] = binding.key.Name
                end
            end
            profileStore()[name] = snapshot
            queueConfigSave()
            nameBox.Text = ""
            rebuildProfiles()
            notify("Keybind profile saved: " .. name)
        end))

        rebuildProfiles()
        raiseOpen(profilesRecord)
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
            {"Open menu", "RightControl", 12},
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
            width = packedWidth(keybindRows),
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
        actionRow(keybindsRecord, 100, "Reset keybinds", function(): ()
            for _, binding: any in pairs(state.shortcutBindings) do
                binding.key = Enum.KeyCode.Unknown
                persistBindingKey(binding)
                if binding.refresh then
                    binding.refresh()
                end
            end
            rebuildKeybinds()
            notify("Keybinds reset — profiles are untouched, as in Wurst")
        end)
        actionRow(keybindsRecord, 101, "Profiles…", openProfiles)
        rebuildKeybinds()
        raiseOpen(keybindsRecord)
    end

    -- -------------------------------------------------------- Wurst Options
    -- Wurst's client-management screen. What survives from the old Config.
    -- page lands here because it is management, not decoration: the reinject
    -- and destruct actions and the game check readout.
    local optionsRecord: any = nil
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
            width = packedWidth({
                {"Keybinds", nil, 26},
                {"Reinject latest", nil, 26},
                {"Destruct", nil, 26},
                {"Reset layout", nil, 26},
                {"Game check: Universal only"},
            }),
        })

        actionRow(optionsRecord, 1, "Keybinds", openKeybinds)

        local reinjectBusy: boolean = false
        local reinjectRow: TextButton = actionRow(optionsRecord, 2, "Reinject latest", function(): () end)
        local reinjectLabel: TextLabel = reinjectRow:FindFirstChild("Label") :: TextLabel
        trackUiConnection(reinjectRow.MouseButton1Click:Connect(function(): ()
            if reinjectBusy then
                return
            end
            local compiler: any = (getfenv() :: any).loadstring
            if type(compiler) ~= "function" then
                notify("Reinject unavailable: this executor has no loadstring")
                return
            end
            reinjectBusy = true
            reinjectLabel.Text = "Downloading…"
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
                reinjectLabel.Text = "Reinject latest"
                notify("Could not download the latest build")
                warn("[Wurst] Reinject download: "
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
                reinjectLabel.Text = "Reinject latest"
                notify("The downloaded build could not be compiled")
                warn("[Wurst] Reinject compile: " .. tostring(compileError))
                return
            end
            reinjectLabel.Text = "Restarting…"
            task.defer(function(): ()
                local executed: boolean, executionError: any = xpcall(
                    compiled,
                    debug.traceback
                )
                if not executed then
                    reinjectBusy = false
                    if reinjectLabel.Parent then
                        reinjectLabel.Text = "Reinject latest"
                    end
                    warn("[Wurst] Reinject runtime: " .. tostring(executionError))
                end
            end)
        end))

        local destructRow: TextButton = actionRow(optionsRecord, 3, "Destruct", function(): () end)
        local destructLabel: TextLabel = destructRow:FindFirstChild("Label") :: TextLabel
        trackUiConnection(destructRow.MouseButton1Click:Connect(function(): ()
            destructLabel.Text = "Removing…"
            task.defer(function(): ()
                local destruct: any = state.destruct
                if type(destruct) ~= "function" then
                    -- The teardown routine is defined at the very end of
                    -- bootstrap; if it is somehow missing, remove the
                    -- interface anyway instead of a label stuck mid-word.
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
        end))

        actionRow(optionsRecord, 4, "Reset layout", function(): ()
            -- Saved geometry gone, category grid re-tiled now. Every window
            -- also forgets it was ever hand-moved — that is what "reset"
            -- promises — and the settings and management windows still on
            -- screen re-run placement immediately instead of waiting for a
            -- reopen while standing on the freshly tiled grid.
            configData.ui.windows = {}
            queueConfigSave()
            for _, window: any in ipairs(windows.list or {}) do
                window.userMoved = nil
            end
            if state.clickGui and state.clickGui.Retile then
                state.clickGui.Retile()
            end
            if windows.PlaceWindow then
                for _, window: any in ipairs(windows.list or {}) do
                    if (window.featureSettings or window.managementWindow)
                        and window.root.Visible then
                        windows.PlaceWindow(window, {force = true})
                    end
                end
            end
            notify("Layout reset")
        end)

        -- The game check readout: *how* the game was recognised, which is
        -- what tells you a clone was matched by structure, not PlaceId.
        local recognised: string = GAME_CHECK.MM2Active and "MM2"
            or GAME_CHECK.TRSActive and "TRS"
            or GAME_CHECK.VDActive and "VD"
            or GAME_CHECK.BedFightActive and "BedFight"
            or GAME_CHECK.MVSDActive and "MVSD"
            or "Universal only"
        create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = optionsRecord.window.body,
            Name = "GameCheck",
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            LayoutOrder = 5,
            Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
            Text = "  Game check: " .. recognised,
            TextColor3 = Theme.textMuted,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = optionsRecord.window.body.ZIndex + 1,
        })
        optionsRecord.resize()
        raiseOpen(optionsRecord)
    end

    -- ---------------------------------------------------------- UI Settings
    -- Built eagerly: in Wurst this window sits in the ClickGUI grid like any
    -- category window, and building it is also what applies the stored (or
    -- default) opacity, tooltip opacity and heights at boot.
    local screen: Vector2 = viewport()
    uiRecord = configWindow("UISettings", "UI Settings", {
        position = Vector2.new(screen.X - WINDOW_WIDTH - 12, 64),
        closable = false,
        settingsSized = false,
        width = packedWidth({
            {"WurstLogo", nil, 26},
            {"HackList", nil, 26},
            {"Keybinds", nil, 26},
            {"WurstOptions", nil, 26},
            {"Background", "#404040"},
            {"Accent", "#101010"},
            {"Text", "#F0F0F0"},
            {"Opacity", "0.85"},
            {"Tooltip opacity", "0.75"},
            {"Max height", "1000"},
            {"Max settings height", "1000"},
        }),
    })
    uiRecord.open = true

    actionRow(uiRecord, 1, "WurstLogo", openWurstLogo)
    actionRow(uiRecord, 2, "HackList", openHackList)
    actionRow(uiRecord, 3, "Keybinds", openKeybinds)
    actionRow(uiRecord, 4, "WurstOptions", openWurstOptions)

    local uiPanel: any = panelFor(uiRecord, "ClickGUI")
    -- The four shortcuts above hold LayoutOrder 1–4; starting the option
    -- counter past them keeps Wurst's order (buttons first, then settings).
    uiPanel.optionCount = 4

    -- The window's current values, published so anything that wants to read
    -- the defaults does not have to walk rows — the parity suite does.
    local uiSettingsValues: {[string]: any} = {}
    state.uiSettings = uiSettingsValues

    for _, row: any in ipairs({
        {label = "Background", default = CLICKGUI_BACKGROUND, tokens = {"surface", "background"}},
        {label = "Accent", default = CLICKGUI_ACCENT, tokens = {"accent", "outline"}},
        {label = "Text", default = CLICKGUI_TEXT, tokens = {"text", "accentText"}},
    }) do
        local tokens: {string} = row.tokens
        local labelText: string = row.label
        addColorOption(uiPanel, labelText, row.default, function(color: Color3): ()
            uiSettingsValues[labelText] = color
            -- Wurst's Background paints window bodies, Accent paints title
            -- bars *and* borders, Text paints every label — and in the Wurst
            -- preset each pair already shares one value, so this mapping is
            -- exact at boot.
            if ThemeEngine and type(ThemeEngine.Set) == "function" then
                for _, token: string in ipairs(tokens) do
                    ThemeEngine.Set(token, color)
                end
            end
        end)
    end

    addNumberOption(uiPanel, "Opacity", OPACITY, 0.15, 0.85, function(value: number): ()
        uiSettingsValues["Opacity"] = value
        windows.SetOpacity(value)
    end)
    addNumberOption(uiPanel, "Tooltip opacity", TOOLTIP_OPACITY, 0.15, 1, function(value: number): ()
        uiSettingsValues["Tooltip opacity"] = value
        if state.featureTooltip then
            state.featureTooltip.BackgroundTransparency = 1 - value
        end
    end)
    addNumberOption(uiPanel, "Max height", MAX_HEIGHT, 0, 1000, function(value: number): ()
        uiSettingsValues["Max height"] = value
        state.uiMaxHeight = value
        if state.clickGui and state.clickGui.RefreshHeights then
            state.clickGui.RefreshHeights()
        end
        uiRecord.resize()
    end)
    addNumberOption(uiPanel, "Max settings height", MAX_SETTINGS_HEIGHT, 0, 1000, function(value: number): ()
        uiSettingsValues["Max settings height"] = value
        maxSettingsHeight = value
        -- Published: the window manager caps every popped-out feature
        -- settings window with the same slider.
        state.uiMaxSettingsHeight = value
        for _, window: any in ipairs((state.windows and state.windows.list) or {}) do
            if window.featureSettings and window.resizeToOptions then
                window.resizeToOptions()
            end
        end
        for _, record: any in ipairs(Settings.records) do
            record.resize()
        end
    end)

    -- UI Settings is eager and its rows are all in place now: one reflow at
    -- the real measured size keeps its top-right default when that spot is
    -- free and moves it to a free rectangle when the category grid already
    -- reached it. A saved manual position only gets clamped.
    uiRecord.placed = true
    if windows.ReflowWindow then
        windows.ReflowWindow(uiRecord.window)
    end

    -- The configuration windows follow the GUI the way category windows do,
    -- except the pinned ones, which is the whole point of pinning.
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
    Settings.openWurstLogo = openWurstLogo
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
