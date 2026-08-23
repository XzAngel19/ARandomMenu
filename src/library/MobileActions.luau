--!strict
--
-- Mobile action layer.
--
-- Placed shortcuts: the buttons a phone player drops on top of the game so a
-- feature can be fired without opening the menu. Placement mode, dragging,
-- snapping back inside the screen, hold-style bindings that behave like a held
-- key, and remembering all of it between sessions.
--
-- The launcher — the one button that opens the menu — deliberately stays in
-- `ARandomMenu.luau`. On a phone it is the only way in, so it cannot depend on
-- a download: if this file never arrives the player loses their shortcuts, not
-- their menu.

export type MobileHoldCallbacks = {
    -- Asked at press time. A binding can become (or stop being) a hold after
    -- the button was placed, so the answer cannot be baked in at creation.
    isActive: (() -> boolean)?,
    onPress: (() -> ())?,
    onRelease: (() -> ())?,
}

export type MobileActionRecord = {
    id: string,
    label: string,
    button: TextButton,
    callback: () -> (),
    -- Hold-style features (Sprint) drive press/release instead of a single
    -- tap, so a finger on the button behaves exactly like a held key.
    hold: MobileHoldCallbacks?,
    holding: boolean,
    activeInput: InputObject?,
    startPointer: Vector2,
    startPosition: Vector2,
    moved: boolean,
    holdToken: number,
    size: number,
    opacity: number,
    connections: {RBXScriptConnection},
}

export type PendingMobilePlacement = {
    id: string,
    label: string,
    callback: () -> (),
    hold: MobileHoldCallbacks?,
    restoreMenu: boolean,
}

local Module = {
    Name = "MobileActions",
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
    local makeTextLabel: any = host.makeTextLabel
    local notify: any = host.notify
    local Theme: any = host.Theme
    local CONTROL_FONT: any = host.CONTROL_FONT
    local ScreenGui: any = host.ScreenGui
    local PopupLayer: any = host.PopupLayer
    local TweenService: any = host.TweenService
    local UserInputService: any = host.UserInputService
    local UI_MOTION: any = host.UI_MOTION
    local cornerRadius: any = host.cornerRadius
    local trackUiConnection: any = host.trackUiConnection
    -- The viewport the shell measured at start, and the hidden bin that holds
    -- cards before they are placed. Main (the old central window) is gone.
    local initialViewport: any = host.initialViewport or Vector2.new(1280, 720)

    type MobileActionRecord = {
        id: string,
        label: string,
        button: TextButton,
        callback: () -> (),
        -- Hold-style features (Sprint) drive press/release instead of a single
        -- tap, so a finger on the button behaves exactly like a held key.
        hold: MobileHoldCallbacks?,
        holding: boolean,
        activeInput: InputObject?,
        startPointer: Vector2,
        startPosition: Vector2,
        moved: boolean,
        holdToken: number,
        size: number,
        opacity: number,
        connections: {RBXScriptConnection},
    }

    type PendingMobilePlacement = {
        id: string,
        label: string,
        callback: () -> (),
        hold: MobileHoldCallbacks?,
        restoreMenu: boolean,
    }

    local mobileActions: {[string]: MobileActionRecord} = {}
    local pendingMobilePlacement: PendingMobilePlacement? = nil

    local MobilePlacementOverlay: Frame = (create("Frame", {
        Parent = PopupLayer,
        Name = "MobilePlacementOverlay",
        Active = true,
        BackgroundColor3 = Theme.background,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 200,
    }) :: any) :: Frame
    local MobilePlacementLabel = makeTextLabel(
        MobilePlacementOverlay,
        "TOUCH WHERE THE ACTION BUTTON SHOULD GO",
        16
    )
    MobilePlacementLabel.FontFace = CONTROL_FONT
    MobilePlacementLabel.TextXAlignment = Enum.TextXAlignment.Center
    MobilePlacementLabel.Position = UDim2.new(0.08, 0, 0.08, 0)
    MobilePlacementLabel.Size = UDim2.new(0.84, 0, 0, 54)
    MobilePlacementLabel.ZIndex = 201

    local function ensureMobileConfig(): {[string]: any}
        if type(configData.ui.mobileActions) ~= "table" then
            configData.ui.mobileActions = {}
        end
        return configData.ui.mobileActions
    end

    local function clampMobileButtonPosition(
        position: Vector2,
        size: number
    ): Vector2
        local camera: Camera? = workspace.CurrentCamera
        local viewport: Vector2 = camera
            and camera.ViewportSize
            or Vector2.new(1280, 720)
        local radius: number = size / 2
        return Vector2.new(
            math.clamp(position.X, radius + 6, math.max(radius + 6, viewport.X - radius - 6)),
            math.clamp(position.Y, radius + 6, math.max(radius + 6, viewport.Y - radius - 6))
        )
    end

    local function saveMobileActionPosition(record: MobileActionRecord): ()
        local mobileConfig: {[string]: any} = ensureMobileConfig()
        mobileConfig[record.id] = {
            record.button.Position.X.Offset,
            record.button.Position.Y.Offset,
            record.size,
            record.opacity,
        }
        queueConfigSave()
    end

    local function removeMobileAction(id: string): ()
        local record: MobileActionRecord? = mobileActions[id]
        if not record then
            return
        end
        mobileActions[id] = nil
        ensureMobileConfig()[id] = nil
        for _, connection: RBXScriptConnection in ipairs(record.connections) do
            connection:Disconnect()
        end
        table.clear(record.connections)
        if record.button.Parent then
            record.button:Destroy()
        end
        queueConfigSave()
        notify(record.label .. " mobile button removed.")
    end

    -- One editor is shared by every placed shortcut. Long-pressing a button
    -- opens it instead of silently deleting the button, which was impossible
    -- to discover and offered no way to tune a large touch target.
    local editingRecord: MobileActionRecord? = nil
    local editorOverlay: Frame = (create("Frame", {
        Parent = ScreenGui,
        Name = "MobileActionEditor",
        Active = true,
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 270,
    }) :: any) :: Frame
    local editorPanel: Frame = (create("Frame", {
        Parent = editorOverlay,
        Name = "Panel",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.surfaceRaised,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(280, 190),
        ZIndex = 271,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = editorPanel,
        CornerRadius = UDim.new(0, 12),
    })
    create("UIStroke", {
        Parent = editorPanel,
        Color = Theme.outline,
        Thickness = 1,
        Transparency = 0.25,
    })
    local editorTitle: TextLabel = (makeTextLabel(
        editorPanel,
        "Mobile button",
        16
    ) :: any) :: TextLabel
    editorTitle.Position = UDim2.fromOffset(14, 8)
    editorTitle.Size = UDim2.new(1, -28, 0, 28)
    editorTitle.TextXAlignment = Enum.TextXAlignment.Left
    editorTitle.ZIndex = 272

    local function editorLabel(text: string, y: number): TextLabel
        local label: TextLabel = (makeTextLabel(editorPanel, text, 14) :: any) :: TextLabel
        label.Position = UDim2.fromOffset(14, y)
        label.Size = UDim2.fromOffset(76, 36)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 272
        return label
    end
    editorLabel("Size", 46)
    editorLabel("Opacity", 88)

    local function editorButton(
        name: string,
        text: string,
        x: number,
        y: number,
        width: number
    ): TextButton
        local button: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = editorPanel,
            Name = name,
            Active = true,
            AutoButtonColor = false,
            BackgroundColor3 = Theme.surface,
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(width, 34),
            Text = text,
            TextColor3 = Theme.text,
            TextSize = 14,
            ZIndex = 272,
        }) :: any) :: TextButton
        create("UICorner", {
            Parent = button,
            CornerRadius = UDim.new(0, 7),
        })
        return button
    end

    local sizeDown: TextButton = editorButton("SizeDown", "-", 92, 47, 40)
    local sizeValue: TextButton = editorButton("SizeValue", "52 px", 138, 47, 72)
    local sizeUp: TextButton = editorButton("SizeUp", "+", 216, 47, 40)
    sizeValue.Active = false
    local opacityDown: TextButton = editorButton("OpacityDown", "-", 92, 89, 40)
    local opacityValue: TextButton = editorButton("OpacityValue", "92%", 138, 89, 72)
    local opacityUp: TextButton = editorButton("OpacityUp", "+", 216, 89, 40)
    opacityValue.Active = false
    local removeButton: TextButton = editorButton("Remove", "Remove", 14, 140, 120)
    removeButton.BackgroundColor3 = Color3.fromRGB(120, 28, 28)
    local doneButton: TextButton = editorButton("Done", "Done", 146, 140, 120)
    doneButton.BackgroundColor3 = Theme.enabled
    doneButton.TextColor3 = Theme.enabledText

    local function closeEditor(): ()
        editingRecord = nil
        editorOverlay.Visible = false
    end

    local function refreshEditor(): ()
        local record: MobileActionRecord? = editingRecord
        if not record then
            return
        end
        editorTitle.Text = record.label
        sizeValue.Text = tostring(math.round(record.size)) .. " px"
        opacityValue.Text = tostring(math.round(record.opacity * 100)) .. "%"
        record.button.Size = UDim2.fromOffset(record.size, record.size)
        record.button.BackgroundTransparency = 1 - record.opacity
        local clamped: Vector2 = clampMobileButtonPosition(
            Vector2.new(record.button.Position.X.Offset, record.button.Position.Y.Offset),
            record.size
        )
        record.button.Position = UDim2.fromOffset(clamped.X, clamped.Y)
        saveMobileActionPosition(record)
    end

    local function openEditor(record: MobileActionRecord): ()
        editingRecord = record
        editorOverlay.Visible = true
        refreshEditor()
    end

    trackUiConnection(sizeDown.MouseButton1Click:Connect(function(): ()
        if editingRecord then
            editingRecord.size = math.clamp(editingRecord.size - 8, 36, 120)
            refreshEditor()
        end
    end))
    trackUiConnection(sizeUp.MouseButton1Click:Connect(function(): ()
        if editingRecord then
            editingRecord.size = math.clamp(editingRecord.size + 8, 36, 120)
            refreshEditor()
        end
    end))
    trackUiConnection(opacityDown.MouseButton1Click:Connect(function(): ()
        if editingRecord then
            editingRecord.opacity = math.clamp(editingRecord.opacity - 0.1, 0.2, 1)
            refreshEditor()
        end
    end))
    trackUiConnection(opacityUp.MouseButton1Click:Connect(function(): ()
        if editingRecord then
            editingRecord.opacity = math.clamp(editingRecord.opacity + 0.1, 0.2, 1)
            refreshEditor()
        end
    end))
    trackUiConnection(removeButton.MouseButton1Click:Connect(function(): ()
        local record: MobileActionRecord? = editingRecord
        closeEditor()
        if record then
            removeMobileAction(record.id)
        end
    end))
    trackUiConnection(doneButton.MouseButton1Click:Connect(closeEditor))

    local function setMobileActionVisibility(menuVisible: boolean): ()
        if menuVisible then
            closeEditor()
        end
        for _, record: MobileActionRecord in pairs(mobileActions) do
            record.button.Visible = state.isMobile and not menuVisible
        end
    end

    local function createMobileAction(
        id: string,
        label: string,
        callback: () -> (),
        requestedPosition: Vector2?,
        hold: MobileHoldCallbacks?
    ): MobileActionRecord?
        if not state.isMobile then
            return nil
        end

        local existing: MobileActionRecord? = mobileActions[id]
        if existing then
            existing.callback = callback
            existing.label = label
            existing.hold = hold
            return existing
        end

        local stored: any = ensureMobileConfig()[id]
        local size: number = math.clamp(
            type(stored) == "table" and tonumber(stored[3])
                or tonumber(state.mobileButtonSize)
                or 52,
            36,
            120
        )
        local opacity: number = math.clamp(
            type(stored) == "table" and tonumber(stored[4]) or 0.92,
            0.2,
            1
        )
        local actionCount: number = 0
        for _ in pairs(mobileActions) do
            actionCount += 1
        end
        local defaultPosition: Vector2 = Vector2.new(
            74 + (actionCount * (size + 10)),
            math.max(size, initialViewport.Y - size - 70)
        )
        local selectedPosition: Vector2 = requestedPosition or (
            type(stored) == "table"
                and Vector2.new(
                    tonumber(stored[1]) or defaultPosition.X,
                    tonumber(stored[2]) or defaultPosition.Y
                )
                or defaultPosition
        )
        selectedPosition = clampMobileButtonPosition(selectedPosition, size)

        local button = create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClipsDescendants = true,
            Parent = ScreenGui,
            Name = "MobileAction_" .. id:gsub("%W", ""),
            Active = true,
            AutoButtonColor = false,
            BackgroundColor3 = Theme.surfaceRaised,
            BackgroundTransparency = 1 - opacity,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(selectedPosition.X, selectedPosition.Y),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(size, size),
            Text = label,
            TextColor3 = Theme.text,
            -- Wrapped and auto-scaled: a long module name is shown in full at a
            -- smaller size instead of being clipped to its first few letters.
            TextScaled = true,
            TextWrapped = true,
            Visible = not state.visible,
            ZIndex = 180,
        }) :: TextButton
        create("UIPadding", {
            Parent = button,
            PaddingBottom = UDim.new(0, 4),
            PaddingLeft = UDim.new(0, 4),
            PaddingRight = UDim.new(0, 4),
            PaddingTop = UDim.new(0, 4),
        })
        create("UICorner", {
            Parent = button,
            CornerRadius = cornerRadius(12),
        })
        create("UIStroke", {
            Parent = button,
            Color = Theme.outline,
            Transparency = 0.55,
            Thickness = 1,
        })
        create("UITextSizeConstraint", {
            Parent = button,
            MaxTextSize = 12,
            MinTextSize = 6,
        })

        local record: MobileActionRecord = {
            id = id,
            label = label,
            button = button,
            callback = callback,
            hold = hold,
            holding = false,
            activeInput = nil,
            startPointer = Vector2.zero,
            startPosition = selectedPosition,
            moved = false,
            holdToken = 0,
            size = size,
            opacity = opacity,
            connections = {},
        }
        mobileActions[id] = record
        saveMobileActionPosition(record)

        table.insert(record.connections, trackUiConnection(
            button.InputBegan:Connect(function(input: InputObject): ()
            if input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            record.activeInput = input
            record.startPointer = Vector2.new(input.Position.X, input.Position.Y)
            record.startPosition = Vector2.new(
                button.Position.X.Offset,
                button.Position.Y.Offset
            )
            record.moved = false
            -- Hold features engage on touch-down and stay engaged until the
            -- finger lifts, so Sprint behaves like a real hold button. Everything
            -- else stays a tap and fires on release.
            local hold: MobileHoldCallbacks? = record.hold
            local holdActive: boolean = hold ~= nil
                and hold.onPress ~= nil
                and (hold.isActive == nil or (hold.isActive :: () -> boolean)())
            if holdActive and not record.holding then
                record.holding = true
                button.BackgroundTransparency = math.max(0, 1 - record.opacity - 0.1)
                task.spawn((hold :: MobileHoldCallbacks).onPress :: () -> ())
            end
            record.holdToken += 1
            local token: number = record.holdToken
            task.delay(0.75, function(): ()
                if mobileActions[id] ~= record
                    or record.activeInput ~= input
                    or record.moved
                    or record.holdToken ~= token then
                    return
                end
                record.activeInput = nil
                record.holdToken += 1
                if record.holding then
                    record.holding = false
                    if record.hold and record.hold.onRelease then
                        task.spawn(record.hold.onRelease)
                    end
                end
                button.BackgroundTransparency = 1 - record.opacity
                openEditor(record)
            end)
        end)))

        table.insert(record.connections, trackUiConnection(
            UserInputService.InputEnded:Connect(function(
            input: InputObject
        ): ()
            if input.UserInputType ~= Enum.UserInputType.Touch
                or record.activeInput ~= input then
                return
            end
            record.activeInput = nil
            record.holdToken += 1
            if record.holding then
                record.holding = false
                button.BackgroundTransparency = 1 - record.opacity
                if record.hold and record.hold.onRelease then
                    task.spawn(record.hold.onRelease)
                end
                if record.moved then
                    saveMobileActionPosition(record)
                end
            elseif record.moved then
                saveMobileActionPosition(record)
            else
                TweenService:Create(
                    button,
                    TweenInfo.new(0.08, Enum.EasingStyle.Quad),
                    {BackgroundTransparency = math.max(0, 1 - record.opacity - 0.1)}
                ):Play()
                task.delay(0.09, function(): ()
                    if button.Parent then
                        TweenService:Create(
                            button,
                            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad),
                            {BackgroundTransparency = 1 - record.opacity}
                        ):Play()
                    end
                end)
                task.spawn(record.callback)
            end
        end)))

        return record
    end

    trackUiConnection(UserInputService.InputChanged:Connect(function(
        input: InputObject
    ): ()
        if input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        for _, record: MobileActionRecord in pairs(mobileActions) do
            if record.activeInput == input then
                local pointer: Vector2 = Vector2.new(
                    input.Position.X,
                    input.Position.Y
                )
                local delta: Vector2 = pointer - record.startPointer
                if delta.Magnitude >= 7 then
                    record.moved = true
                    if record.holding then
                        -- The finger is repositioning the button, not using it.
                        record.holding = false
                        record.button.BackgroundTransparency = 1 - record.opacity
                        if record.hold and record.hold.onRelease then
                            task.spawn(record.hold.onRelease)
                        end
                    end
                end
                if record.moved then
                    local position: Vector2 = clampMobileButtonPosition(
                        record.startPosition + delta,
                        record.button.AbsoluteSize.X
                    )
                    record.button.Position = UDim2.fromOffset(
                        position.X,
                        position.Y
                    )
                end
            end
        end
    end))

    local function beginMobileActionPlacement(
        id: string,
        label: string,
        callback: () -> (),
        hold: MobileHoldCallbacks?
    ): ()
        if not state.isMobile then
            return
        end
        if mobileActions[id] then
            openEditor(mobileActions[id])
            return
        end

        pendingMobilePlacement = {
            id = id,
            label = label,
            callback = callback,
            hold = hold,
            restoreMenu = state.visible,
        }
        MobilePlacementLabel.Text = "TOUCH TO PLACE " .. string.upper(label)
            .. (hold
                and "\nHOLD THE BUTTON TO KEEP IT ACTIVE"
                or "\nHOLD THE BUTTON LATER TO CUSTOMIZE IT")
        MobilePlacementOverlay.Visible = true
        -- Hide the menu so the player can see where the button is going. The old
        -- central Main frame is gone; visibility now drives ClickGUI windows.
        state.setMenuVisible(false)

        local placement: PendingMobilePlacement =
            pendingMobilePlacement :: PendingMobilePlacement
        task.delay(8, function(): ()
            if pendingMobilePlacement == placement then
                pendingMobilePlacement = nil
                MobilePlacementOverlay.Visible = false
                if placement.restoreMenu then
                    state.setMenuVisible(true)
                end
                notify("Mobile button placement cancelled.")
            end
        end)
    end

    trackUiConnection(MobilePlacementOverlay.InputBegan:Connect(function(
        input: InputObject
    ): ()
        local placement: PendingMobilePlacement? = pendingMobilePlacement
        if not placement
            or input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        pendingMobilePlacement = nil
        MobilePlacementOverlay.Visible = false
        createMobileAction(
            placement.id,
            placement.label,
            placement.callback,
            Vector2.new(input.Position.X, input.Position.Y),
            placement.hold
        )
        if placement.restoreMenu then
            state.setMenuVisible(true)
        end
        notify(placement.label .. " mobile button placed.")
    end))

    -- Touch key slots are the mobile-button factory.
    --
    -- A single tap opens placement mode. Tapping the slot again for an existing
    -- action opens the same size/opacity/remove editor as a long press on the
    -- placed button.
    local function bindMobileActionPlacement(
        source: TextButton,
        id: string,
        label: string,
        callback: () -> (),
        hold: MobileHoldCallbacks?
    ): ()
        if not state.isMobile then
            return
        end

        trackUiConnection(source.MouseButton1Click:Connect(function(): ()
            beginMobileActionPlacement(id, label, callback, hold)
        end))

        if ensureMobileConfig()[id] ~= nil then
            createMobileAction(id, label, callback, nil, hold)
        end
    end
    state.bindMobileActionPlacement = bindMobileActionPlacement

    local function resetMobileActions(): ()
        local ids: {string} = {}
        for id: string in pairs(mobileActions) do
            table.insert(ids, id)
        end
        for _, id: string in ipairs(ids) do
            removeMobileAction(id)
        end
        configData.ui.mobileActions = {}
        queueConfigSave()
    end
    state.mobileUi = {
        actions = mobileActions,
        setActionVisibility = setMobileActionVisibility,
        resetActions = resetMobileActions,
        clampButtonPosition = clampMobileButtonPosition,
        saveActionPosition = saveMobileActionPosition,
        editor = editorOverlay,
        openEditor = openEditor,
        closeEditor = closeEditor,
    }
    -- Placed mobile shortcuts are the inverse of the menu, and this is wired up as
    -- soon as the mobile layer exists rather than waiting for the Settings tab.
    state.addMenuVisibilityListener(setMobileActionVisibility)

    Module.Initialized = true
    return state.mobileUi
end

-- Nothing to tear down: every connection goes through the shell's own
-- `trackUiConnection`, and the buttons are children of the ScreenGui the shell
-- destroys.
function Module.destroy(): ()
    Module.Initialized = false
end

return Module
