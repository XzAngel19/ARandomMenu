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
    -- The window itself, hidden while a button is being placed so the player
    -- can see where it is going, and the viewport the shell measured at start.
    local Main: any = host.Main
    local initialViewport: any = host.initialViewport

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
        BackgroundColor3 = Theme.DefaultBackground,
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

    local function setMobileActionVisibility(menuVisible: boolean): ()
        for _, record: MobileActionRecord in pairs(mobileActions) do
            record.button.Visible = state.isMobile and not menuVisible
        end
    end
    state.setMobileActionVisibility = setMobileActionVisibility

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

        local size: number = state.mobileButtonSize
        local stored: any = ensureMobileConfig()[id]
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
            BackgroundColor3 = Theme.SurfaceRaised,
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(selectedPosition.X, selectedPosition.Y),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(size, size),
            Text = label,
            TextColor3 = Theme.Text,
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
            Color = Theme.DefaultOutline,
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
                button.BackgroundTransparency = 0.02
                task.spawn((hold :: MobileHoldCallbacks).onPress :: () -> ())
            end
            record.holdToken += 1
            local token: number = record.holdToken
            -- Hold-to-remove would fight a hold *feature*: keeping a finger on the
            -- Sprint button is how you sprint, not how you delete it. Those are
            -- removed from the menu instead, by tapping their key slot again.
            if not holdActive then
                task.delay(0.85, function(): ()
                    if mobileActions[id] == record
                        and record.activeInput == input
                        and not record.moved
                        and record.holdToken == token then
                        record.activeInput = nil
                        removeMobileAction(id)
                        notify(record.label .. " button removed.")
                    end
                end)
            end
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
                button.BackgroundTransparency = 0.18
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
                    {BackgroundTransparency = 0.03}
                ):Play()
                task.delay(0.09, function(): ()
                    if button.Parent then
                        TweenService:Create(
                            button,
                            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad),
                            {BackgroundTransparency = 0.18}
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
                        record.button.BackgroundTransparency = 0.18
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
            removeMobileAction(id)
            notify(label .. " button removed.")
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
                or "\nHOLD THE CIRCLE LATER TO REMOVE IT")
        MobilePlacementOverlay.Visible = true
        Main.Visible = false
        -- The menu is hidden for placement, so drop the blur rather than leaving
        -- the screen dimmed behind the overlay.
        state.suspendBlur()

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
    -- A single tap opens placement mode (a second tap on an already-placed button
    -- removes it). It used to need a 0.6s hold, which nothing on screen hinted at
    -- and which is impossible to guess now that an unbound slot is blank.
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
    state.resetMobileActions = resetMobileActions
    state.mobileUi = {
        actions = mobileActions,
        setActionVisibility = setMobileActionVisibility,
        resetActions = resetMobileActions,
        clampButtonPosition = clampMobileButtonPosition,
        saveActionPosition = saveMobileActionPosition,
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
