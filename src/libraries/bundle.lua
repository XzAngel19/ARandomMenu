return {
    stamp = "c3b79b32e60bd74c",
    files = {
        ["src/libraries/Manifest.lua"] = [[export type ModuleEntry = {
    path: string,
    name: string,
    category: string,
}

export type Manifest = {
    version: number,
    widgets: string,
    core: {string},
    libraries: {string},
    modules: {ModuleEntry},
}

local Manifest: Manifest = {
    version = 1,

    widgets = "src/guis/Wurst/Code/Widgets.lua",
    core = {
        "src/libraries/Framework.lua",
    },
    libraries = {
        "src/libraries/Entity.lua",
        "src/libraries/Targeting.lua",
        "src/libraries/Weapons.lua",
        "src/libraries/Render.lua",

        "src/guis/Wurst/Code/Cards.lua",

        "src/guis/Wurst/Code/WindowManager.lua",

        "src/guis/Wurst/Code/ClickGui.lua",

        "src/guis/Wurst/Code/FloatingWindows.lua",

        "src/guis/Wurst/Code/SettingsPage.lua",

        "src/guis/Wurst/Code/MobileActions.lua",

        "src/guis/Wurst/Code/Furniture.lua",
    },
    modules = {

        {
            path = "src/games/universal/Utility/FriendList.lua",
            name = "Friend List",
            category = "Other",
        },
        {
            path = "src/games/universal/Render/ItemRender.lua",
            name = "ItemESP",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/PlayerESP.lua",
            name = "PlayerESP",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/Chams.lua",
            name = "Chams",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/Arrows.lua",
            name = "Arrows",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/NPCESP.lua",
            name = "NPCESP",
            category = "Render",
        },
        {
            path = "src/games/universal/Combat/KillAura.lua",
            name = "Killaura",
            category = "Combat",
        },
        {
            path = "src/games/universal/Utility/RemoteLogger.lua",
            name = "Remote Logger",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/Learning.lua",
            name = "Learning",
            category = "Other",
        },
        {
            path = "src/games/universal/Blatant/ClickTeleport.lua",
            name = "Click Teleport",
            category = "Movement",
        },
        {
            path = "src/games/universal/Combat/AutoClicker.lua",
            name = "Auto Clicker",
            category = "Combat",
        },
        {
            path = "src/games/universal/Combat/TriggerBot.lua",
            name = "TriggerBot",
            category = "Combat",
        },
        {
            path = "src/games/universal/Combat/AimAssist.lua",
            name = "Aim Assist",
            category = "Combat",
        },

        {
            path = "src/games/universal/Render/XRay.lua",
            name = "X-Ray",
            category = "Render",
        },
        {
            path = "src/games/universal/Blatant/HighJump.lua",
            name = "HighJump",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/Spider.lua",
            name = "Spider",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/WallHop.lua",
            name = "WallHop",
            category = "Movement",
        },
        {
            path = "src/games/universal/World/SafeWalk.lua",
            name = "SafeWalk",
            category = "Movement",
        },
        {
            path = "src/games/universal/World/RejoinServer.lua",
            name = "Rejoin Server",
            category = "Other",
        },
        {
            path = "src/games/universal/Render/ZoomUnlocker.lua",
            name = "Zoom",
            category = "Render",
        },
        {
            path = "src/games/universal/World/InteractExtender.lua",
            name = "Interact Extender",
            category = "Other",
        },
        {
            path = "src/games/universal/Blatant/PhaseDash.lua",
            name = "Phase Dash",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/NoFall.lua",
            name = "NoFall",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/Fly.lua",
            name = "Flight",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/VehicleSpeed.lua",
            name = "Vehicle Speed",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/AntiVoid.lua",
            name = "Anti-Void",
            category = "Movement",
        },
        {
            path = "src/games/universal/World/Gravity.lua",
            name = "Gravity",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/JumpPower.lua",
            name = "Jump Power",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/InfiniteJump.lua",
            name = "Infinite Jump",
            category = "Movement",
        },
        {
            path = "src/games/universal/Render/FieldOfView.lua",
            name = "FOV",
            category = "Render",
        },
        {
            path = "src/games/universal/Blatant/Noclip.lua",
            name = "Noclip",
            category = "Movement",
        },
        {
            path = "src/games/universal/World/AntiAfk.lua",
            name = "AntiAFK",
            category = "Other",
        },
        {
            path = "src/games/universal/Blatant/AntiFling.lua",
            name = "Anti-Fling",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/LagSwitch.lua",
            name = "Lag Switch",
            category = "Other",
        },
        {
            path = "src/games/universal/Blatant/Fling.lua",
            name = "Fling",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/ImproveFps.lua",
            name = "Improve FPS",
            category = "Other",
        },
        {
            path = "src/games/universal/Render/Fullbright.lua",
            name = "Fullbright",
            category = "Render",
        },
        {
            path = "src/games/universal/Blatant/FreezeMovements.lua",
            name = "Freeze Movements",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/Speed.lua",
            name = "SpeedHack",
            category = "Movement",
        },
        {
            path = "src/games/universal/Combat/Hitboxes.lua",
            name = "Hitboxes",
            category = "Combat",
        },
        {
            path = "src/games/universal/Render/ProjectileCalibration.lua",
            name = "Projectile Calibration",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/SpinBot.lua",
            name = "SpinBot",
            category = "Fun",
        },
        {
            path = "src/games/universal/Utility/Disguise.lua",
            name = "Disguise",
            category = "Fun",
        },
        {
            path = "src/games/universal/Utility/AnimationChanger.lua",
            name = "Animation Changer",
            category = "Fun",
        },
        {
            path = "src/games/universal/Utility/EmotePlayer.lua",
            name = "Emote Player",
            category = "Fun",
        },
    },
}

return Manifest
]],
        ["src/guis/Wurst/Code/Widgets.lua"] = [[export type OptionDefinition = {
    kind: string,
    label: string,
    default: any?,
    minimum: number?,
    maximum: number?,
    values: {string}?,
    callback: any,
    persist: boolean?,
}

export type FeatureDefinition = {
    name: string,
    description: string,
    order: number,
    onToggle: any,
    configuration: any?,
    options: {OptionDefinition}?,
}

export type WidgetLibrary = {
    addToggleOption: any,
    addActionOption: any,
    addNumberOption: any,
    addRangeOption: any,
    addCycleOption: any,
    addKeyOption: any,
    addTextOption: any,
    addColorOption: any,
    addListOption: any,
    addSectionOption: any,
    addInformationOption: any,
    setOptionVisible: any,
}

local Module = {
    Name = "Widgets",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local LABEL_FONT_SIZE: number = 16
local SLIDER_BAR_HEIGHT: number = 6
local SLIDER_KNOB_WIDTH: number = 16
local SLIDER_KNOB_HEIGHT: number = 16

local CHILD_INSET: number = 4
local CHILD_GAP: number = 4

function Module.init(context: any): WidgetLibrary

    local WURST_GREEN: Color3 = Color3.fromRGB(0, 204, 0)
    local host: any = context

    local UserInputService: any = host.UserInputService
    local state: any = host.state
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local create: any = host.create
    local makeButton: any = host.makeButton
    local makeTextBox: any = host.makeTextBox

    local function flatTextBox(parent: Instance, initial: any): TextBox
        local box: TextBox = (makeTextBox(parent, initial) :: any) :: TextBox
        local corner: UICorner? = box:FindFirstChild("StyleCorner") :: UICorner?
        if corner then
            corner:Destroy()
        end
        return box
    end
    local makeTextLabel: any = host.makeTextLabel
    local notify: any = host.notify
    local Theme: any = host.Theme
    local CONTROL_FONT: any = host.CONTROL_FONT
    local ScreenGui: any = host.ScreenGui

    local PopupLayer: any = host.PopupLayer
    local trackUiConnection: any = host.trackUiConnection
    local applyKeySlotStyle: any = host.applyKeySlotStyle
    local beginKeyCapture: any = host.beginKeyCapture
    local bindActionShortcut: any = host.bindActionShortcut
    local runActionButton: any = host.runActionButton
    local colorFromConfig: any = host.colorFromConfig
    local colorToConfig: any = host.colorToConfig

    local function drawPixelIcon(
        parent: Instance,
        kind: string,
        color: Color3?
    ): Frame
        local paint: Color3 = color or WURST_GREEN
        local existing: Instance? = (parent :: any):FindFirstChild("PixelIcon")
        if existing then
            existing:Destroy()
        end
        local sizes: {[string]: {number}} = {
            down = {14, 8},
            up = {14, 8},
            right = {8, 14},
            cross = {10, 10},
            pin = {10, 10},
            check = {12, 10},
        }
        local size: {number} = sizes[kind] or {10, 10}
        local container: Frame = (create("Frame", {
            Parent = parent,
            Name = "PixelIcon",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(size[1], size[2]),
            ZIndex = (tonumber((parent :: any).ZIndex) or 1) + 1,
        }) :: any) :: Frame
        local function px(x: number, y: number, w: number, h: number): ()
            create("Frame", {
                Parent = container,
                BackgroundColor3 = paint,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(x * 2, y * 2),
                Size = UDim2.fromOffset(w * 2, h * 2),
                ZIndex = container.ZIndex + 1,
            })
        end
        if kind == "down" then
            px(0, 0, 7, 1); px(1, 1, 5, 1); px(2, 2, 3, 1); px(3, 3, 1, 1)
        elseif kind == "up" then
            px(3, 0, 1, 1); px(2, 1, 3, 1); px(1, 2, 5, 1); px(0, 3, 7, 1)
        elseif kind == "right" then
            px(0, 0, 1, 7); px(1, 1, 1, 5); px(2, 2, 1, 3); px(3, 3, 1, 1)
        elseif kind == "cross" then
            px(0, 0, 1, 1); px(4, 0, 1, 1)
            px(1, 1, 1, 1); px(3, 1, 1, 1)
            px(2, 2, 1, 1)
            px(1, 3, 1, 1); px(3, 3, 1, 1)
            px(0, 4, 1, 1); px(4, 4, 1, 1)
        elseif kind == "pin" then
            px(1, 0, 3, 3); px(2, 3, 1, 2)
        elseif kind == "check" then
            px(0, 2, 1, 1); px(1, 3, 1, 1); px(2, 4, 1, 1)
            px(3, 3, 1, 1); px(4, 2, 1, 1); px(5, 1, 1, 1)
        end
        return container
    end

    state.layoutOptionControl = function(
        option: Frame,
        control: GuiObject,
        widthScale: number?
    ): ()
        local top: number = tonumber(option:GetAttribute("ControlTop")) or 0
        local height: number = tonumber(option:GetAttribute("ControlHeight"))
            or option.Size.Y.Offset

        local scale: number = widthScale or 0.5
        control.AnchorPoint = Vector2.new(1, 0)
        control.Position = UDim2.new(1, -10, 0, top)
        control.Size = UDim2.new(scale, -10, 0, height)
        control.ZIndex = math.max(control.ZIndex, option.ZIndex + 2)
    end

    local function createOptionRow(
        feature: any,
        labelText: string,
        _hintText: string?
    ): Frame
        feature.optionCount += 1
        feature.searchText ..= " " .. string.lower(labelText)
        local rowHeight: number = state.layout.optionRowHeight

        local option: Frame = (create("Frame", {
            Parent = feature.options,
            Name = "Option_" .. labelText:gsub("%W", ""),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = feature.optionCount,
            Size = UDim2.new(1, 0, 0, rowHeight),
            ZIndex = feature.options.ZIndex + 1,
        }) :: any) :: Frame
        table.insert(feature.optionRows, option)

        local label: TextLabel = (create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "OptionLabel",
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(CHILD_INSET, 0),
            Size = UDim2.new(0.55, -CHILD_INSET, 0, rowHeight),
            Text = labelText,
            TextColor3 = Theme.text,
            TextSize = LABEL_FONT_SIZE,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = option.ZIndex + 1,
        }) :: any) :: TextLabel
        label.Visible = true

        option:SetAttribute("ControlTop", 3)
        option:SetAttribute("ControlHeight", rowHeight - 6)

        feature.updateExpandedSize()
        return option
    end

    state.addSectionOption = function(feature: any, titleText: string): Frame
        feature.optionCount += 1
        local section: Frame = (create("Frame", {
            Parent = feature.options,
            Name = "Section_" .. titleText:gsub("%W", ""),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = feature.optionCount,
            Size = UDim2.new(1, 0, 0, 0),
            Visible = false,
            ZIndex = feature.options.ZIndex + 1,
        }) :: any) :: Frame
        table.insert(feature.optionRows, section)
        feature.updateExpandedSize()
        return section
    end

    local function setOptionVisible(
        feature: any,
        option: GuiObject,
        visible: boolean
    ): ()
        option.Visible = visible
        feature.updateExpandedSize()
    end

    local function addToggleOption(
        feature: any,
        labelText: string,
        defaultValue: boolean,
        callback: (boolean) -> (),
        hintText: string?
    ): TextButton
        local optionKey: string =
            feature.configKey .. "." .. labelText:gsub("%W", "")
        local enabled: boolean? = configData.states[optionKey]
        if enabled == nil then
            enabled = defaultValue == true
        end

        local option: Frame = createOptionRow(feature, labelText, hintText)
        local button: TextButton = create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClipsDescendants = true,
            Parent = option,
            Name = "OptionClickTarget",
            Active = true,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            ZIndex = option.ZIndex + 2,
        }) :: TextButton

        local box: Frame = (create("Frame", {
            Parent = option,
            Name = "OptionCheckbox",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            Position = UDim2.new(0, CHILD_INSET, 0.5, 0),
            Size = UDim2.fromOffset(22, 22),
            ZIndex = option.ZIndex + 3,
        }) :: any) :: Frame

        local boxStroke: UIStroke = (create("UIStroke", {
            Parent = box,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Color = Theme.outline,
            Thickness = 1,
            Transparency = 0.35,
        }) :: any) :: UIStroke

        local mark: Frame = drawPixelIcon(box, "check", WURST_GREEN)
        mark.Visible = false
        local optionLabel: TextLabel? =
            option:FindFirstChild("OptionLabel") :: TextLabel?
        if optionLabel then
            (optionLabel :: TextLabel).Position =
                UDim2.fromOffset(CHILD_INSET + 22 + CHILD_GAP, 0);
            (optionLabel :: TextLabel).Size =
                UDim2.new(1, -(CHILD_INSET + 22 + CHILD_GAP), 1, 0)
        end

        local function refreshOptionState(): ()
            local on: boolean = enabled :: boolean
            box.BackgroundColor3 = on and Theme.enabled or Color3.fromRGB(0, 0, 0)
            box.BackgroundTransparency = on and 0 or 0.5
            boxStroke.Color = on and Theme.enabled or Theme.outline
            mark.Visible = on
        end

        local function toggleOption(): ()
            enabled = not enabled
            refreshOptionState()
            configData.states[optionKey] = enabled
            callback(enabled :: boolean)
            queueConfigSave()
            notify(labelText .. ((enabled :: boolean) and " enabled" or " disabled"))
        end
        trackUiConnection(button.MouseButton1Click:Connect(toggleOption))

        refreshOptionState()
        callback(enabled :: boolean)
        return button
    end
    local function addActionOption(
        feature: any,
        labelText: string,
        callback: () -> (),
        hintText: string?
    ): TextButton
        local option = createOptionRow(feature, labelText, hintText)
        local button = makeButton(option, "RUN", 11)
        button.BackgroundColor3 = state.guiStyle == "Default"
            and Theme.buttonHover
            or Theme.accentSoft

        state.layoutOptionControl(option, button, 0.26)
        local function executeAction(): ()
            runActionButton(
                button,
                "RUN",
                callback,
                labelText .. " completado",
                "[Random Testing Menu] " .. labelText
            )
        end
        trackUiConnection(button.MouseButton1Click:Connect(executeAction))
        local shortcutButton: TextButton =
            (makeButton(option, "KEY", 9) :: any) :: TextButton
        shortcutButton.BackgroundColor3 = state.guiStyle == "Default"
            and Theme.button
            or Theme.surfaceRaised

        state.layoutOptionControl(option, shortcutButton, 0.24)
        shortcutButton.Position = UDim2.new(
            0.74,
            -16,
            shortcutButton.Position.Y.Scale,
            shortcutButton.Position.Y.Offset
        )
        applyKeySlotStyle(shortcutButton)
        shortcutButton.TextScaled = true
        create("UITextSizeConstraint", {
            Parent = shortcutButton,
            MaxTextSize = 14,
            MinTextSize = 8,
        })
        bindActionShortcut(
            shortcutButton,
            feature.configKey .. labelText,
            labelText,
            executeAction
        )
        return button :: TextButton
    end

    type ActiveSlider = {
        update: (number) -> (),
        finish: () -> (),
    }

    local activeSlider: ActiveSlider? = nil

    trackUiConnection(UserInputService.InputChanged:Connect(function(
        input: InputObject
    ): ()
        if activeSlider
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            activeSlider.update(input.Position.X)
        end
    end))

    trackUiConnection(UserInputService.InputEnded:Connect(function(
        input: InputObject
    ): ()
        if activeSlider
            and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
            local slider: ActiveSlider = activeSlider
            activeSlider = nil
            slider.finish()
        end
    end))

    local function isFiniteNumber(value: any): boolean
        return type(value) == "number"
            and value == value
            and value ~= math.huge
            and value ~= -math.huge
    end

    local function formatCompactNumber(value: number): string
        local magnitude: number = math.abs(value)
        if magnitude >= 1e9 or (magnitude > 0 and magnitude < 1e-4) then
            return string.format("%.3e", value)
        end
        return string.format("%.12g", value)
    end

    local function addNumberOption(
        feature: any,
        labelText: string,
        defaultValue: number,
        minimum: number,
        maximum: number,
        callback: (number) -> (),
        hintText: string?,
        stepValue: number?
    ): Frame
        local optionKey: string =
            feature.configKey .. "." .. labelText:gsub("%W", "")
        local storedValue: number? = tonumber(configData.values[optionKey])

        local value: number = isFiniteNumber(storedValue)
            and (storedValue :: number)
            or defaultValue
        local integerOnly: boolean = defaultValue % 1 == 0
            and minimum % 1 == 0
            and maximum % 1 == 0

        local option: Frame = createOptionRow(feature, labelText, hintText)

        option.Size = UDim2.new(1, 0, 0, 44)
        local headerLabel: TextLabel? =
            option:FindFirstChild("OptionLabel") :: TextLabel?
        if headerLabel then
            (headerLabel :: TextLabel).Size =
                UDim2.new(0.55, -CHILD_INSET, 0, 22)
        end

        local requestedStep: number? = tonumber(stepValue)
        if requestedStep ~= nil and requestedStep <= 0 then
            requestedStep = nil
        end

        local step: number = requestedStep or (integerOnly and 1 or 0.01)
        local precisionFactor: number = 1
        for _ = 1, 6 do
            if math.abs(step * precisionFactor - math.round(step * precisionFactor)) < 1e-7 then
                break
            end
            precisionFactor *= 10
        end

        option:SetAttribute("Min", minimum)
        option:SetAttribute("Max", maximum)
        option:SetAttribute("Step", step)
        option:SetAttribute("FreeNumeric", true)

        local slider: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "Slider",
            Active = true,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 22),
            Size = UDim2.new(1, 0, 0, 22),
            Text = "",
            ZIndex = option.ZIndex + 1,
        }) :: any) :: TextButton

        local minText: string = formatCompactNumber(minimum)
        local maxText: string = formatCompactNumber(maximum)

        local bitmapContract: any = state.bitmapText
        local function endLabelWidth(endText: string): number
            if bitmapContract and type(bitmapContract.measure) == "function" then
                return bitmapContract.measure({{text = endText}}, 14) + 4
            end
            return #endText * 11 + 4
        end
        local minWidth: number = endLabelWidth(minText)
        local maxWidth: number = endLabelWidth(maxText)
        create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = slider,
            Name = "MinLabel",
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.new(0, CHILD_INSET, 0, 0),
            Size = UDim2.new(0, minWidth, 1, 0),
            Text = minText,
            TextColor3 = Theme.textMuted,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = option.ZIndex + 1,
        })
        create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = slider,
            Name = "MaxLabel",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.new(1, -CHILD_INSET, 0, 0),
            Size = UDim2.new(0, maxWidth, 1, 0),
            Text = maxText,
            TextColor3 = Theme.textMuted,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = option.ZIndex + 1,
        })

        local track: Frame = (create("Frame", {
            Parent = slider,
            Name = "Track",
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 0.9,
            BorderSizePixel = 0,
            Position = UDim2.new(
                0,
                CHILD_INSET + minWidth + CHILD_GAP,
                0,
                (22 - SLIDER_BAR_HEIGHT) // 2
            ),
            Size = UDim2.new(
                1,
                -(CHILD_INSET * 2 + minWidth + maxWidth + CHILD_GAP * 2),
                0,
                SLIDER_BAR_HEIGHT
            ),
            ZIndex = option.ZIndex + 1,
        }) :: any) :: Frame

        local fill: Frame = (create("Frame", {
            Parent = track,
            Name = "Fill",
            BackgroundColor3 = Theme.accent,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(0, 1),
            ZIndex = track.ZIndex + 1,
        }) :: any) :: Frame

        local knob: Frame = (create("Frame", {
            Parent = track,
            Name = "Knob",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.text,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.fromOffset(SLIDER_KNOB_WIDTH, SLIDER_KNOB_HEIGHT),
            ZIndex = track.ZIndex + 2,
        }) :: any) :: Frame

        local valueInput: TextBox = (flatTextBox(slider, "") :: any) :: TextBox
        valueInput.Name = "NumericValue"
        valueInput.AnchorPoint = Vector2.new(1, 0)
        valueInput.Position = UDim2.new(1, -CHILD_INSET, 0, -22)
        valueInput.Size = UDim2.new(0.42, 0, 0, 22)
        valueInput.BackgroundTransparency = 1
        valueInput.TextColor3 = Theme.textMuted
        valueInput.TextSize = LABEL_FONT_SIZE
        valueInput.TextXAlignment = Enum.TextXAlignment.Right
        valueInput.TextTruncate = Enum.TextTruncate.AtEnd
        valueInput.ZIndex = option.ZIndex + 2
        local valueStroke: UIStroke? =
            valueInput:FindFirstChild("StyleStroke") :: UIStroke?
        if valueStroke then
            (valueStroke :: UIStroke).Transparency = 1
        end

        valueInput.PlaceholderText = formatCompactNumber(minimum)
            .. " – "
            .. formatCompactNumber(maximum)

        local editing: boolean = false

        local function quantize(raw: number, fromSlider: boolean): number
            if not fromSlider then
                return raw
            end
            local stepped: number = minimum
                + math.round((raw - minimum) / step) * step
            stepped = math.round(stepped * precisionFactor) / precisionFactor
            return math.clamp(stepped, minimum, maximum)
        end
        local function setValue(
            nextValue: number,
            persist: boolean,
            _fromSlider: boolean
        ): ()
            if not isFiniteNumber(nextValue) then
                return
            end
            value = quantize(nextValue, _fromSlider)
            local alpha: number = maximum == minimum
                and 0
                or math.clamp((value - minimum) / (maximum - minimum), 0, 1)
            fill.Size = UDim2.fromScale(alpha, 1)
            knob.Position = UDim2.fromScale(alpha, 0.5)
            if not editing then
                valueInput.Text = formatCompactNumber(value)
            end
            callback(value)
            if persist then
                configData.values[optionKey] = value
                queueConfigSave()
            end
        end

        local function updateFromScreenX(screenX: number): ()
            local width: number = math.max(track.AbsoluteSize.X, 1)
            local alpha: number = math.clamp(
                (screenX - track.AbsolutePosition.X) / width,
                0,
                1
            )
            setValue(minimum + (maximum - minimum) * alpha, true, true)
        end

        trackUiConnection(slider.InputBegan:Connect(function(
            input: InputObject
        ): ()
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if input.Position.X > track.AbsolutePosition.X + track.AbsoluteSize.X then
                return
            end
            updateFromScreenX(input.Position.X)
            activeSlider = {
                update = updateFromScreenX,
                finish = function(): ()
                    notify(
                        labelText
                            .. ": "
                            .. formatCompactNumber(value)
                    )
                end,
            }
        end))

        trackUiConnection(valueInput.Focused:Connect(function(): ()
            editing = true
            valueInput.Text = tostring(value)
            valueInput.CursorPosition = #valueInput.Text + 1
        end))

        trackUiConnection(valueInput.FocusLost:Connect(function(): ()
            local parsed: number? = tonumber(valueInput.Text)
            editing = false
            if not isFiniteNumber(parsed) then
                valueInput.Text = formatCompactNumber(value)
                notify(labelText .. ": invalid numeric value")
                return
            end
            setValue(parsed :: number, true, false)
            notify(labelText .. ": " .. formatCompactNumber(value))
        end))

        task.defer(function(): ()
            if option.Parent then
                setValue(value, false, false)
            end
        end)
        return option
    end

    state.addRangeOption = function(
        feature: any,
        labelText: string,
        definition: any
    ): Frame
        local minimum: number = tonumber(definition.min) or 0
        local maximum: number = tonumber(definition.max) or 100
        local baseKey: string =
            feature.configKey .. "." .. labelText:gsub("%W", "")
        local storedLow: number? = tonumber(configData.values[baseKey .. ".Low"])
        local storedHigh: number? = tonumber(configData.values[baseKey .. ".High"])

        local low: number = isFiniteNumber(storedLow)
            and (storedLow :: number)
            or tonumber(definition.defaultLow)
            or minimum
        local high: number = isFiniteNumber(storedHigh)
            and (storedHigh :: number)
            or tonumber(definition.defaultHigh)
            or maximum
        if low > high then
            low, high = high, low
        end
        local integerOnly: boolean = definition.integer ~= false

        local option: Frame = createOptionRow(feature, labelText, definition.hint)

        option.Size = UDim2.new(1, 0, 0, 44)
        local rangeLabel: TextLabel? =
            option:FindFirstChild("OptionLabel") :: TextLabel?
        if rangeLabel then
            (rangeLabel :: TextLabel).Size =
                UDim2.new(0.55, -CHILD_INSET, 0, 22)
        end
        local slider: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "RangeSlider",
            Active = true,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 22),
            Size = UDim2.new(1, 0, 0, 22),
            Text = "",
            ZIndex = option.ZIndex + 1,
        }) :: any) :: TextButton

        local track: Frame = (create("Frame", {
            Parent = option,
            Name = "Track",
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 0.9,
            BorderSizePixel = 0,
            Position = UDim2.new(0, CHILD_INSET, 0, 22 + (22 - SLIDER_BAR_HEIGHT) // 2),
            Size = UDim2.new(1, -CHILD_INSET * 2, 0, SLIDER_BAR_HEIGHT),
            ZIndex = option.ZIndex + 1,
        }) :: any) :: Frame

        local span: Frame = (create("Frame", {
            Parent = track,
            Name = "Span",
            BackgroundColor3 = Theme.accent,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(0, 0),
            Size = UDim2.fromScale(1, 1),
            ZIndex = track.ZIndex + 1,
        }) :: any) :: Frame

        local function makeKnob(name: string): Frame
            local knob: Frame = (create("Frame", {
                Parent = track,
                Name = name,
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Theme.text,
                BorderSizePixel = 0,
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.fromOffset(SLIDER_KNOB_WIDTH, SLIDER_KNOB_HEIGHT),
                ZIndex = track.ZIndex + 2,
            }) :: any) :: Frame
            return knob
        end
        local lowKnob: Frame = makeKnob("Low")
        local highKnob: Frame = makeKnob("High")

        local step: number? = tonumber(definition.step)
        if step ~= nil and step <= 0 then
            step = nil
        end
        option:SetAttribute("Min", minimum)
        option:SetAttribute("Max", maximum)
        option:SetAttribute("Step", step or (integerOnly and 1 or 0))
        option:SetAttribute("FreeNumeric", true)
        local highBox: TextBox = (flatTextBox(option, "") :: any) :: TextBox
        highBox.Name = "HighValue"
        highBox.AnchorPoint = Vector2.new(1, 0)
        highBox.Position = UDim2.new(1, -CHILD_INSET, 0, 0)
        highBox.Size = UDim2.fromOffset(52, 22)
        highBox.BackgroundTransparency = 1
        highBox.TextColor3 = Theme.textMuted
        highBox.TextSize = LABEL_FONT_SIZE
        highBox.TextXAlignment = Enum.TextXAlignment.Right
        highBox.TextTruncate = Enum.TextTruncate.AtEnd
        highBox.ZIndex = option.ZIndex + 2
        local _dash: TextLabel = (create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "RangeDash",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.new(1, -CHILD_INSET - 52, 0, 0),
            Size = UDim2.fromOffset(14, 22),
            Text = " – ",
            TextColor3 = Theme.textMuted,
            TextSize = LABEL_FONT_SIZE,
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = option.ZIndex + 2,
        }) :: any) :: TextLabel
        local lowBox: TextBox = (flatTextBox(option, "") :: any) :: TextBox
        lowBox.Name = "LowValue"
        lowBox.AnchorPoint = Vector2.new(1, 0)
        lowBox.Position = UDim2.new(1, -CHILD_INSET - 52 - 14, 0, 0)
        lowBox.Size = UDim2.fromOffset(52, 22)
        lowBox.BackgroundTransparency = 1
        lowBox.TextColor3 = Theme.textMuted
        lowBox.TextSize = LABEL_FONT_SIZE
        lowBox.TextXAlignment = Enum.TextXAlignment.Right
        lowBox.TextTruncate = Enum.TextTruncate.AtEnd
        lowBox.ZIndex = option.ZIndex + 2
        for _, box: TextBox in ipairs({lowBox, highBox}) do
            local stroke: UIStroke? = box:FindFirstChild("StyleStroke") :: UIStroke?
            if stroke then
                (stroke :: UIStroke).Transparency = 1
            end
        end
        local editingLow: boolean = false
        local editingHigh: boolean = false

        local function alphaOf(value: number): number
            if maximum == minimum then
                return 0
            end
            return math.clamp((value - minimum) / (maximum - minimum), 0, 1)
        end

        local function refreshRange(persist: boolean): ()
            local lowAlpha: number = alphaOf(low)
            local highAlpha: number = alphaOf(high)
            span.Position = UDim2.fromScale(lowAlpha, 0)
            span.Size = UDim2.fromScale(math.max(highAlpha - lowAlpha, 0), 1)
            lowKnob.Position = UDim2.fromScale(lowAlpha, 0.5)
            highKnob.Position = UDim2.fromScale(highAlpha, 0.5)
            if not editingLow then
                lowBox.Text = formatCompactNumber(low)
            end
            if not editingHigh then
                highBox.Text = formatCompactNumber(high)
            end
            if type(definition.onChanged) == "function" then
                definition.onChanged(low, high)
            end
            if persist then
                configData.values[baseKey .. ".Low"] = low
                configData.values[baseKey .. ".High"] = high
                queueConfigSave()
            end
        end

        local dragging: string = "High"
        local function valueAtScreenX(screenX: number): number
            local width: number = math.max(track.AbsoluteSize.X, 1)
            local alpha: number = math.clamp(
                (screenX - track.AbsolutePosition.X) / width,
                0,
                1
            )
            local value: number = minimum + (maximum - minimum) * alpha
            if step ~= nil then
                value = minimum
                    + math.round((value - minimum) / (step :: number))
                        * (step :: number)
            elseif integerOnly then
                value = math.round(value)
            end
            return math.clamp(value, minimum, maximum)
        end

        local function quantizeTyped(raw: number): number
            return raw
        end

        local function updateFromScreenX(screenX: number): ()
            local value: number = valueAtScreenX(screenX)
            if dragging == "Low" then
                low = math.min(value, high)
            else
                high = math.max(value, low)
            end
            refreshRange(true)
        end

        trackUiConnection(slider.InputBegan:Connect(function(
            input: InputObject
        ): ()
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if input.Position.X > track.AbsolutePosition.X + track.AbsoluteSize.X then
                return
            end
            local value: number = valueAtScreenX(input.Position.X)
            dragging = math.abs(value - low) <= math.abs(value - high)
                and "Low"
                or "High"
            updateFromScreenX(input.Position.X)
            activeSlider = {
                update = updateFromScreenX,
                finish = function(): ()
                    notify(
                        labelText
                            .. ": "
                            .. formatCompactNumber(low)
                            .. " – "
                            .. formatCompactNumber(high)
                    )
                end,
            }
        end))

        trackUiConnection(lowBox.Focused:Connect(function(): ()
            editingLow = true
            lowBox.Text = tostring(low)
            lowBox.CursorPosition = #lowBox.Text + 1
        end))
        trackUiConnection(lowBox.FocusLost:Connect(function(): ()
            local parsed: number? = tonumber(lowBox.Text)
            editingLow = false
            if not isFiniteNumber(parsed) then
                lowBox.Text = formatCompactNumber(low)
                notify(labelText .. ": invalid numeric value")
                return
            end
            low = math.min(quantizeTyped(parsed :: number), high)
            refreshRange(true)
            notify(labelText .. ": "
                .. formatCompactNumber(low) .. " – " .. formatCompactNumber(high))
        end))
        trackUiConnection(highBox.Focused:Connect(function(): ()
            editingHigh = true
            highBox.Text = tostring(high)
            highBox.CursorPosition = #highBox.Text + 1
        end))
        trackUiConnection(highBox.FocusLost:Connect(function(): ()
            local parsed: number? = tonumber(highBox.Text)
            editingHigh = false
            if not isFiniteNumber(parsed) then
                highBox.Text = formatCompactNumber(high)
                notify(labelText .. ": invalid numeric value")
                return
            end
            high = math.max(quantizeTyped(parsed :: number), low)
            refreshRange(true)
            notify(labelText .. ": "
                .. formatCompactNumber(low) .. " – " .. formatCompactNumber(high))
        end))

        task.defer(function(): ()
            if option.Parent then
                refreshRange(false)
            end
        end)
        refreshRange(false)
        return option
    end

    state.closeChoiceList = function(): () end
    state.choiceListAnchor = nil :: TextButton?

    local function watchPopupOwner(
        owner: any,
        onInvalid: () -> ()
    ): {RBXScriptConnection}
        local connections: {RBXScriptConnection} = {}
        if owner == nil then
            return connections
        end
        local scroller: any = nil
        local windowRoot: any = nil
        local node: any = owner
        while node ~= nil do
            if scroller == nil and type(node.IsA) == "function"
                and node:IsA("ScrollingFrame") then
                scroller = node
                windowRoot = node.Parent
                break
            end
            node = node.Parent
        end
        local function watch(instance: any, property: string, test: () -> boolean): ()
            pcall(function(): ()
                table.insert(
                    connections,
                    instance:GetPropertyChangedSignal(property):Connect(function(): ()
                        if test() then
                            onInvalid()
                        end
                    end)
                )
            end)
        end
        if windowRoot then
            watch(windowRoot, "Visible", function(): boolean
                return windowRoot.Visible ~= true
            end)
            pcall(function(): ()
                table.insert(
                    connections,
                    windowRoot.AncestryChanged:Connect(function(): ()
                        if windowRoot.Parent == nil then
                            onInvalid()
                        end
                    end)
                )
            end)
        end
        if scroller then

            watch(scroller, "Visible", function(): boolean
                return scroller.Visible ~= true
            end)
            watch(scroller, "CanvasPosition", function(): boolean
                local ok: boolean, clippedOut: any = pcall(function(): boolean
                    local top: number = scroller.AbsolutePosition.Y
                    local bottom: number = top + scroller.AbsoluteSize.Y
                    local rowTop: number = owner.AbsolutePosition.Y
                    local rowBottom: number = rowTop + owner.AbsoluteSize.Y
                    return rowBottom < top or rowTop > bottom
                end)
                return ok and clippedOut == true
            end)
        end
        return connections
    end

    local function openChoiceList(
        anchor: TextButton,
        values: {string},
        currentIndex: number,
        onPick: (number) -> ()
    ): ()
        if state.choiceListAnchor == anchor then
            state.closeChoiceList()
            return
        end
        state.closeChoiceList()

        local rowHeight: number = 24

        local searchable: boolean = #values > 8
        local searchHeight: number = searchable and 24 or 0
        local visibleRows: number = math.min(#values, 6)
        local listHeight: number = visibleRows * rowHeight + 8 + searchHeight
        local anchorPosition: Vector2 = anchor.AbsolutePosition
        local anchorSize: Vector2 = anchor.AbsoluteSize

        local viewport: Vector2 = ScreenGui.AbsoluteSize
        local below: boolean = anchorPosition.Y + anchorSize.Y + listHeight
            < viewport.Y - 8

        local list: Frame = create("Frame", {
            Parent = ScreenGui,
            Name = "ChoiceList",
            BackgroundColor3 = Theme.surfaceRaised,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(
                math.round(anchorPosition.X),
                math.round(below
                    and (anchorPosition.Y + anchorSize.Y + 4)
                    or (anchorPosition.Y - listHeight - 4))
            ),
            Size = UDim2.fromOffset(math.round(anchorSize.X), listHeight),
            ZIndex = 400,
        }) :: Frame
        create("UIStroke", {
            Parent = list,
            Color = Theme.outline,
            Transparency = 0.15,
            Thickness = 1,
        })

        do
            local bitmap: any = state.bitmapText
            if bitmap and type(bitmap.adoptTree) == "function" then
                bitmap.adoptTree(list)
            end
        end

        local filterBox: TextBox? = nil
        if searchable then
            local filterFrame: Frame = create("Frame", {
                Parent = list,
                Name = "Filter",
                BackgroundColor3 = Theme.background,
                BackgroundTransparency = 0.25,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Position = UDim2.fromOffset(4, 4),
                Size = UDim2.new(1, -8, 0, searchHeight - 4),
                ZIndex = 402,
            }) :: Frame
            local box: TextBox = flatTextBox(filterFrame, "")
            box.Name = "FilterBox"
            box.BackgroundTransparency = 1
            box.PlaceholderText = "Search"
            box.Position = UDim2.fromOffset(8, 0)
            box.Size = UDim2.new(1, -12, 1, 0)
            box.TextXAlignment = Enum.TextXAlignment.Left
            box.TextSize = 14
            box.ZIndex = 403
            local boxCorner: UICorner? =
                box:FindFirstChild("StyleCorner") :: UICorner?
            if boxCorner then
                boxCorner:Destroy()
            end
            local boxStroke: UIStroke? =
                box:FindFirstChild("StyleStroke") :: UIStroke?
            if boxStroke then
                boxStroke:Destroy()
            end
            filterBox = box
        end

        local scroller: ScrollingFrame = create("ScrollingFrame", {
            Parent = list,
            Name = "Items",
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            Position = UDim2.fromOffset(4, 4 + searchHeight),
            ScrollBarThickness = 2,
            ScrollBarImageTransparency = 0.6,
            Size = UDim2.new(1, -8, 1, -(8 + searchHeight)),
            ZIndex = 401,
        }) :: ScrollingFrame
        create("UIListLayout", {
            Parent = scroller,
            Padding = UDim.new(0, 1),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        local closed: boolean = false
        local outsideConnection: RBXScriptConnection? = nil
        local ownerConnections: {RBXScriptConnection} = {}
        local function close(): ()
            if closed then
                return
            end
            closed = true
            if outsideConnection then
                outsideConnection:Disconnect()
                outsideConnection = nil
            end
            for _, connection: RBXScriptConnection in ipairs(ownerConnections) do
                pcall(function(): ()
                    connection:Disconnect()
                end)
            end
            ownerConnections = {}
            list:Destroy()
            if state.choiceListAnchor == anchor then
                state.choiceListAnchor = nil
            end
            state.closeChoiceList = function(): () end
        end
        state.closeChoiceList = close
        state.choiceListAnchor = anchor

        ownerConnections = watchPopupOwner(anchor, close)

        local rowsByValue: {[string]: TextButton} = {}
        for itemIndex: number, value: string in ipairs(values) do
            local item: TextButton = (create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                ClipsDescendants = true,
                Parent = scroller,
                Name = "Choice" .. tostring(itemIndex),
                AutoButtonColor = false,
                BackgroundColor3 = Theme.surfaceHover,
                BackgroundTransparency = itemIndex == currentIndex and 0.25 or 1,
                BorderSizePixel = 0,
                FontFace = CONTROL_FONT,
                LayoutOrder = itemIndex,
                Size = UDim2.new(1, 0, 0, rowHeight - 1),
                Text = value,
                TextColor3 = itemIndex == currentIndex
                    and Theme.text
                    or Theme.textMuted,
                TextSize = 14,
                ZIndex = 402,
            }) :: any) :: TextButton
            create("UIPadding", {
                Parent = item,
                PaddingLeft = UDim.new(0, 10),
                PaddingRight = UDim.new(0, 8),
            })

            if itemIndex == currentIndex then
                create("Frame", {
                    Parent = item,
                    Name = "PickedBar",
                    BackgroundColor3 = Theme.enabled,
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(-10, 0),
                    Size = UDim2.new(0, 3, 1, 0),
                    ZIndex = 403,
                })
            end

            local itemStroke: UIStroke = (create("UIStroke", {
                Parent = item,
                Name = "EntryStroke",
                Color = Theme.outline,
                Thickness = 1,
                Transparency = itemIndex == currentIndex and 0.35 or 0.82,
            }) :: any) :: UIStroke
            item.TextXAlignment = Enum.TextXAlignment.Left
            item.MouseEnter:Connect(function(): ()
                if itemIndex ~= currentIndex then
                    item.BackgroundTransparency = 0.6
                    item.TextColor3 = Theme.text
                end
                itemStroke.Transparency = 0.35
            end)
            item.MouseLeave:Connect(function(): ()
                item.BackgroundTransparency = itemIndex == currentIndex and 0.25 or 1
                item.TextColor3 = itemIndex == currentIndex
                    and Theme.text
                    or Theme.textMuted
                itemStroke.Transparency = itemIndex == currentIndex and 0.35 or 0.82
            end)
            item.MouseButton1Click:Connect(function(): ()
                close()
                onPick(itemIndex)
            end)
            rowsByValue[value] = item
        end

        if filterBox then
            local box: TextBox = filterBox :: TextBox
            trackUiConnection(box:GetPropertyChangedSignal("Text"):Connect(function(): ()
                local query: string = string.lower(box.Text)
                for value: string, row: TextButton in pairs(rowsByValue) do
                    row.Visible = query == ""
                        or string.find(string.lower(value), query, 1, true) ~= nil
                end
            end))
            task.defer(function(): ()
                if not closed then
                    box:CaptureFocus()
                end
            end)
        end

        outsideConnection = UserInputService.InputBegan:Connect(function(
            input: InputObject
        ): ()
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            task.defer(function(): ()
                if closed then
                    return
                end
                local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
                local origin: Vector2 = list.AbsolutePosition
                local size: Vector2 = list.AbsoluteSize
                local inside: boolean = pointer.X >= origin.X
                    and pointer.X <= origin.X + size.X
                    and pointer.Y >= origin.Y
                    and pointer.Y <= origin.Y + size.Y
                if not inside then
                    close()
                end
            end)
        end)
        trackUiConnection(outsideConnection :: RBXScriptConnection)
    end

    state.openChoiceList = openChoiceList

    state.addMenuVisibilityListener(function(visible: boolean): ()
        if not visible then
            state.closeChoiceList()
        end
    end)

    state.openMultiList = function(
        anchor: TextButton,
        items: {string},
        selected: {[string]: boolean},
        onToggle: (string, boolean) -> (),
        onBulk: ((boolean) -> ())?
    ): ()
        if state.choiceListAnchor == anchor then
            state.closeChoiceList()
            return
        end
        state.closeChoiceList()

        local rowHeight: number = 24
        local rows: number = math.min(#items + (onBulk and 1 or 0), 7)
        local listHeight: number = math.max(rows, 1) * rowHeight + 8
        local anchorPosition: Vector2 = anchor.AbsolutePosition
        local anchorSize: Vector2 = anchor.AbsoluteSize
        local viewport: Vector2 = ScreenGui.AbsoluteSize
        local below: boolean = anchorPosition.Y + anchorSize.Y + listHeight
            < viewport.Y - 8

        local list: Frame = create("Frame", {
            Parent = ScreenGui,
            Name = "MultiList",
            BackgroundColor3 = Theme.surface,
            BackgroundTransparency = 0.04,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(
                math.round(anchorPosition.X),
                math.round(below
                    and (anchorPosition.Y + anchorSize.Y + 4)
                    or (anchorPosition.Y - listHeight - 4))
            ),
            Size = UDim2.fromOffset(math.round(anchorSize.X), listHeight),
            ZIndex = 400,
        }) :: Frame
        create("UIStroke", {
            Parent = list,
            Color = Theme.outline,
            Transparency = 0.4,
            Thickness = 1,
        })

        local scroller: ScrollingFrame = create("ScrollingFrame", {
            Parent = list,
            Name = "Items",
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            Position = UDim2.fromOffset(4, 4),
            ScrollBarThickness = 2,
            ScrollBarImageTransparency = 0.6,
            Size = UDim2.new(1, -8, 1, -8),
            ZIndex = 401,
        }) :: ScrollingFrame
        create("UIListLayout", {
            Parent = scroller,
            Padding = UDim.new(0, 1),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        local closed: boolean = false
        local outsideConnection: RBXScriptConnection? = nil
        local ownerConnections: {RBXScriptConnection} = {}
        local function close(): ()
            if closed then
                return
            end
            closed = true
            if outsideConnection then
                outsideConnection:Disconnect()
                outsideConnection = nil
            end
            for _, connection: RBXScriptConnection in ipairs(ownerConnections) do
                pcall(function(): ()
                    connection:Disconnect()
                end)
            end
            ownerConnections = {}
            list:Destroy()
            if state.choiceListAnchor == anchor then
                state.choiceListAnchor = nil
            end
            state.closeChoiceList = function(): () end
        end
        state.closeChoiceList = close
        state.choiceListAnchor = anchor

        ownerConnections = watchPopupOwner(anchor, close)

        local function makeRow(text: string, order: number): TextButton
            local row: TextButton = (create("TextButton", {
                TextTruncate = Enum.TextTruncate.AtEnd,
                ClipsDescendants = true,
                Parent = scroller,
                Name = "Row" .. tostring(order),
                AutoButtonColor = false,
                BackgroundColor3 = Theme.surfaceHover,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                FontFace = CONTROL_FONT,
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, rowHeight - 1),
                Text = text,
                TextColor3 = Theme.textMuted,
                TextSize = 14,
                ZIndex = 402,
            }) :: any) :: TextButton
            create("UIPadding", {
                Parent = row,
                PaddingLeft = UDim.new(0, 26),
                PaddingRight = UDim.new(0, 8),
            })
            row.TextXAlignment = Enum.TextXAlignment.Left
            return row
        end

        if onBulk then
            local bulk: TextButton = makeRow("All / none", 0)
            bulk.TextColor3 = Theme.text
            local anyOn: boolean = false
            for _, item: string in ipairs(items) do
                if selected[item] then
                    anyOn = true
                    break
                end
            end
            bulk.MouseButton1Click:Connect(function(): ()
                close();
                (onBulk :: (boolean) -> ())(not anyOn)
            end)
        end

        for index: number, item: string in ipairs(items) do
            local row: TextButton = makeRow(item, index)

            local mark: Frame = create("Frame", {
                Parent = row,
                Name = "Mark",
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, -18, 0.5, 0),
                Size = UDim2.fromOffset(11, 11),
                ZIndex = 403,
            }) :: Frame
            local markStroke: UIStroke = (create("UIStroke", {
                Parent = mark,
                Color = Theme.textMuted,
                Transparency = 0.35,
                Thickness = 1,
            }) :: any) :: UIStroke
            local fill: Frame = create("Frame", {
                Parent = mark,
                Name = "Fill",
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Theme.text,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromScale(0, 0),
                ZIndex = 404,
            }) :: Frame

            local function paint(): ()
                local on: boolean = selected[item] == true
                fill.Size = on and UDim2.fromScale(0.6, 0.6) or UDim2.fromScale(0, 0)
                fill.BackgroundTransparency = on and 0.05 or 1
                markStroke.Transparency = on and 0.1 or 0.35
                row.TextColor3 = on and Theme.text or Theme.textMuted
            end
            paint()

            row.MouseEnter:Connect(function(): ()
                row.BackgroundTransparency = 0.72
            end)
            row.MouseLeave:Connect(function(): ()
                row.BackgroundTransparency = 1
            end)
            row.MouseButton1Click:Connect(function(): ()

                selected[item] = not selected[item]
                paint()
                onToggle(item, selected[item] == true)
            end)
        end

        outsideConnection = UserInputService.InputBegan:Connect(function(
            input: InputObject
        ): ()
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            task.defer(function(): ()
                if closed then
                    return
                end
                local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
                local origin: Vector2 = list.AbsolutePosition
                local size: Vector2 = list.AbsoluteSize
                if pointer.X < origin.X
                    or pointer.X > origin.X + size.X
                    or pointer.Y < origin.Y
                    or pointer.Y > origin.Y + size.Y then
                    close()
                end
            end)
        end)
        trackUiConnection(outsideConnection :: RBXScriptConnection)
    end

    state.addListOption = function(feature: any, labelText: string, definition: any): TextButton
        local optionKey: string = feature.configKey .. "." .. labelText:gsub("%W", "")
        local selected: {[string]: boolean} = {}
        local stored: any = configData.values[optionKey]
        if type(stored) == "string" and stored ~= "" then
            for entry: string in string.gmatch(stored, "[^,]+") do
                local trimmed: string = string.match(entry, "^%s*(.-)%s*$") or entry
                if trimmed ~= "" then
                    selected[trimmed] = true
                end
            end
        elseif type(definition.default) == "table" then
            for _, entry: string in ipairs(definition.default) do
                selected[entry] = true
            end
        end

        local option: Frame = createOptionRow(feature, labelText, definition.hint)
        local button: TextButton = makeButton(option, "", 11)
        state.layoutOptionControl(option, button, 0.5)
        button.TextXAlignment = Enum.TextXAlignment.Left
        create("UIPadding", {
            Parent = button,
            Name = "ListPadding",
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 10),
        })

        local function currentItems(): {string}
            local provider: any = definition.items
            if type(provider) == "function" then
                local ok: boolean, result: any = pcall(provider)
                if ok and type(result) == "table" then
                    return result
                end
                return {}
            end
            return provider or {}
        end

        local function describe(): ()
            local items: {string} = currentItems()
            local total: number = #items
            local count: number = 0
            local last: string = ""
            for _, item: string in ipairs(items) do
                if selected[item] then
                    count += 1
                    last = item
                end
            end
            if total == 0 then

                button.Text = definition.emptyText or ""
            elseif count == 0 then
                button.Text = ""
            elseif count == 1 then
                button.Text = last
            elseif count == total then
                button.Text = "all " .. tostring(total)
            else
                button.Text = tostring(count) .. " of " .. tostring(total)
            end
        end

        local function publish(): ()
            local names: {string} = {}
            for name: string, on: boolean in pairs(selected) do
                if on then
                    table.insert(names, name)
                end
            end
            table.sort(names)
            configData.values[optionKey] = table.concat(names, ",")
            queueConfigSave()
            describe()
            if type(definition.onChanged) == "function" then
                definition.onChanged(selected, names)
            end
        end

        button.MouseButton1Click:Connect(function(): ()
            local items: {string} = currentItems()
            state.openMultiList(
                button,
                items,
                selected,
                function(): ()
                    publish()
                end,
                function(enableAll: boolean): ()
                    for _, item: string in ipairs(items) do
                        selected[item] = enableAll or nil
                    end
                    publish()
                end
            )
        end)

        describe()
        if type(definition.onChanged) == "function" then
            definition.onChanged(selected, {})
        end

        button:SetAttribute("ListOption", optionKey)
        state.listSelections = state.listSelections or {}
        state.listSelections[optionKey] = selected
        state.listControls = state.listControls or {}
        state.listControls[optionKey] = {
            set = function(item: string, on: boolean): ()
                selected[item] = on or nil
                publish()
            end,
            refresh = publish,
            selected = selected,
        }
        button:SetAttribute("ListKey", optionKey)
        return button
    end

    local function addCycleOption(
        feature: any,
        labelText: string,
        values: {string},
        initialIndex: number?,
        callback: (string) -> (),
        hintText: string?
    ): TextButton
        local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
        local storedValue = configData.values[optionKey]
        local option = createOptionRow(feature, labelText, hintText)
        local index = initialIndex or 1
        if storedValue ~= nil then
            for valueIndex, value in ipairs(values) do
                if value == storedValue then
                    index = valueIndex
                    break
                end
            end
        end

        local button: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "ComboValue",
            Active = true,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, -(22 + CHILD_INSET), 1, 0),
            Text = values[index],
            TextColor3 = Theme.text,
            TextSize = LABEL_FONT_SIZE,
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = option.ZIndex + 2,
        }) :: any) :: TextButton

        local arrowBox: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "ComboArrow",
            Active = true,
            AnchorPoint = Vector2.new(1, 0),
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -CHILD_INSET, 0, 0),
            Size = UDim2.fromOffset(22, 22),
            Text = "",
            ZIndex = option.ZIndex + 2,
        }) :: any) :: TextButton
        drawPixelIcon(arrowBox, "down", WURST_GREEN)

        local function refreshChoiceVisual(): ()
            button.Text = values[index]
        end
        refreshChoiceVisual()

        local function openList(): ()
            openChoiceList(button, values, index, function(picked: number): ()
                index = picked
                refreshChoiceVisual()
                callback(values[index])
                configData.values[optionKey] = values[index]
                queueConfigSave()
            end)
        end
        button.MouseButton1Click:Connect(openList)
        arrowBox.MouseButton1Click:Connect(openList)

        callback(values[index])
        return button :: TextButton
    end

    local function addKeyOption(
        feature: any,
        labelText: string,
        defaultKey: Enum.KeyCode,
        callback: (Enum.KeyCode) -> (),
        hintText: string?
    ): TextButton

        feature.hasKeyOption = true
        local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
        local savedKey = nil
        local savedName = configData.values[optionKey]
        if type(savedName) == "string" and savedName ~= "" then
            pcall(function()
                savedKey = Enum.KeyCode[savedName]
            end)
        end
        local initialKey = savedKey or defaultKey
        local currentKey: Enum.KeyCode = initialKey
        local function keyLabel(name: any): string
            if type(state.keyDisplayName) == "function" then
                return state.keyDisplayName(name)
            end
            return tostring(name or "")
        end
        local option = createOptionRow(feature, labelText, hintText)
        local button = makeButton(
            option,
            currentKey == Enum.KeyCode.Unknown and "" or keyLabel(currentKey.Name),
            11
        )
        state.layoutOptionControl(option, button, 0.5)
        applyKeySlotStyle(button)
        button:SetAttribute("CaptureIdleText", button.Text)

        local function assignKey(keyCode: Enum.KeyCode): boolean
            local cleared: boolean = keyCode == currentKey
            currentKey = cleared and Enum.KeyCode.Unknown or keyCode
            button.Text = currentKey == Enum.KeyCode.Unknown
                and ""
                or keyLabel(currentKey.Name)
            button:SetAttribute("CaptureIdleText", button.Text)
            callback(currentKey)
            configData.values[optionKey] = currentKey.Name
            queueConfigSave()
            return not cleared
        end

        button.MouseButton1Click:Connect(function()
            if state.isMobile then
                return
            end
            beginKeyCapture(button, function(keyCode: Enum.KeyCode): ()
                assignKey(keyCode)
            end)
        end)

        callback(currentKey)
        return button :: TextButton
    end

    local function addTextOption(
        feature: any,
        labelText: string,
        defaultText: string,
        callback: (string) -> (),
        persist: boolean?,
        hintText: string?
    ): TextBox
        local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
        local shouldPersist = persist ~= false
        local initialText = shouldPersist and configData.values[optionKey] or nil
        if initialText == nil then
            initialText = defaultText or ""
        end
        local option = createOptionRow(feature, labelText, hintText)
        local box = flatTextBox(option, initialText)
        box.PlaceholderText = "Enter"

        box.TextXAlignment = Enum.TextXAlignment.Center
        state.layoutOptionControl(option, box, 0.5)

        box.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                callback(box.Text)
            end
        end)

        box:GetPropertyChangedSignal("Text"):Connect(function()
            callback(box.Text)
            if shouldPersist then
                configData.values[optionKey] = box.Text
                queueConfigSave()
            end
        end)

        if not shouldPersist and configData.values[optionKey] ~= nil then
            configData.values[optionKey] = nil
            queueConfigSave()
        end
        callback(initialText)
        return box :: TextBox
    end

    local colorPicker = {}

    colorPicker.open = function(initialColor, onApply, ownerRow)
        if not colorPicker.panel then
            local panel = create("Frame", {
                Parent = PopupLayer,
                Name = "ColorPicker",
                Active = true,
                BackgroundColor3 = Theme.surface,
                BorderColor3 = Theme.outline,
                BorderSizePixel = 1,
                Position = UDim2.new(0.5, -170, 0.5, -150),
                Size = UDim2.fromOffset(340, 300),
                Visible = false,
                ZIndex = 460,
            })

            do
                local bitmap: any = state.bitmapText
                if bitmap and type(bitmap.adoptTree) == "function" then
                    bitmap.adoptTree(panel)
                end
            end

            local title = makeTextLabel(panel, "COLOR", 14)
            title.FontFace = CONTROL_FONT
            title.Position = UDim2.fromOffset(15, 8)
            title.Size = UDim2.new(1, -60, 0, 28)
            title.ZIndex = 81

            local close = makeButton(panel, "X", 12)
            close.AutoButtonColor = false
            close.Position = UDim2.new(1, -42, 0, 8)
            close.Size = UDim2.fromOffset(28, 28)
            close.ZIndex = 82

            local sv = makeButton(panel, "", 10)
            sv.AutoButtonColor = false
            sv:SetAttribute("NoHover", true)
            sv.Position = UDim2.fromOffset(15, 44)
            sv.Size = UDim2.fromOffset(205, 165)
            sv.ZIndex = 81
            local saturationGradient = create("UIGradient", {
                Parent = sv,
                Color = ColorSequence.new(
                    Color3.fromRGB(255, 255, 255),
                    Color3.fromRGB(255, 0, 0)
                ),
            })
            local shade = create("Frame", {
                Parent = sv,
                BackgroundColor3 = Theme.background,
                BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1),
                ZIndex = 462,
            })
            create("UIGradient", {
                Parent = shade,
                Rotation = 90,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(1, 0),
                }),
            })
            local svCursor = create("Frame", {
                Parent = sv,
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BorderColor3 = Theme.surface,
                BorderSizePixel = 2,
                Size = UDim2.fromOffset(12, 12),
                ZIndex = 463,
            })
            create("UICorner", {
                Parent = svCursor,
                CornerRadius = UDim.new(1, 0),
            })

            local hue = makeButton(panel, "", 10)
            hue.AutoButtonColor = false
            hue:SetAttribute("NoHover", true)
            hue.Position = UDim2.fromOffset(232, 44)
            hue.Size = UDim2.fromOffset(22, 165)
            hue.ZIndex = 81
            create("UIGradient", {
                Parent = hue,
                Rotation = 90,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
                    ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
                    ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
                    ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
                    ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
                    ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
                }),
            })
            local hueCursor = create("Frame", {
                Parent = hue,
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Color3.fromRGB(245, 245, 245),
                BorderColor3 = Theme.surface,
                BorderSizePixel = 1,
                Position = UDim2.new(0.5, 0, 0, 0),
                Size = UDim2.new(1, 6, 0, 5),
                ZIndex = 463,
            })

            local preview = create("Frame", {
                Parent = panel,
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BorderColor3 = Color3.fromRGB(85, 85, 85),
                BorderSizePixel = 1,
                Position = UDim2.fromOffset(273, 45),
                Size = UDim2.fromOffset(48, 48),
                ZIndex = 461,
            })

            local apply = makeButton(panel, "APPLY", 11)
            apply.AutoButtonColor = false
            apply.Position = UDim2.fromOffset(268, 105)
            apply.Size = UDim2.fromOffset(58, 34)
            apply.ZIndex = 81

            local hex = flatTextBox(panel, "#ffffff")
            hex.Name = "HexField"
            hex.Position = UDim2.fromOffset(15, 218)
            hex.Size = UDim2.fromOffset(150, 30)
            hex.PlaceholderText = "#rrggbb"
            hex.TextXAlignment = Enum.TextXAlignment.Center
            hex.ZIndex = 81

            local rgb = flatTextBox(panel, "255, 255, 255")
            rgb.Name = "RgbField"
            rgb.Position = UDim2.fromOffset(174, 218)
            rgb.Size = UDim2.fromOffset(151, 30)
            rgb.PlaceholderText = "r, g, b"
            rgb.TextXAlignment = Enum.TextXAlignment.Center
            rgb.ZIndex = 81

            local hint = makeTextLabel(
                panel,
                "Drag the square for saturation and brightness, the strip for hue",
                10
            )
            hint.TextColor3 = Color3.fromRGB(145, 145, 145)
            hint.Position = UDim2.fromOffset(15, 256)
            hint.Size = UDim2.new(1, -30, 0, 24)
            hint.ZIndex = 81

            colorPicker.panel = panel
            colorPicker.sv = sv
            colorPicker.saturationGradient = saturationGradient
            colorPicker.svCursor = svCursor
            colorPicker.hue = hue
            colorPicker.hueCursor = hueCursor
            colorPicker.preview = preview
            colorPicker.hex = hex
            colorPicker.rgb = rgb
            colorPicker.apply = apply
            colorPicker.drag = nil

            local function updateColor()
                local color = Color3.fromHSV(
                    colorPicker.h,
                    colorPicker.s,
                    colorPicker.v
                )
                colorPicker.current = color
                colorPicker.preview.BackgroundColor3 = color
                colorPicker.saturationGradient.Color = ColorSequence.new(
                    Color3.fromRGB(255, 255, 255),
                    Color3.fromHSV(colorPicker.h, 1, 1)
                )
                colorPicker.svCursor.Position = UDim2.fromScale(
                    colorPicker.s,
                    1 - colorPicker.v
                )
                colorPicker.hueCursor.Position = UDim2.new(
                    0.5,
                    0,
                    colorPicker.h,
                    0
                )
                local channels = colorToConfig(color)
                colorPicker.hex.Text = string.format(
                    "#%02x%02x%02x",
                    channels[1],
                    channels[2],
                    channels[3]
                )
                colorPicker.rgb.Text = string.format(
                    "%d, %d, %d",
                    channels[1],
                    channels[2],
                    channels[3]
                )
            end
            colorPicker.update = updateColor

            local function updateFromPointer(kind, position)
                local object = kind == "hue" and hue or sv
                local relative = Vector2.new(position.X, position.Y)
                    - object.AbsolutePosition
                if kind == "hue" then
                    colorPicker.h = math.clamp(
                        relative.Y / object.AbsoluteSize.Y,
                        0,
                        1
                    )
                else
                    colorPicker.s = math.clamp(
                        relative.X / object.AbsoluteSize.X,
                        0,
                        1
                    )
                    colorPicker.v = 1 - math.clamp(
                        relative.Y / object.AbsoluteSize.Y,
                        0,
                        1
                    )
                end
                updateColor()
            end

            sv.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    colorPicker.drag = "sv"
                    updateFromPointer("sv", input.Position)
                end
            end)
            hue.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    colorPicker.drag = "hue"
                    updateFromPointer("hue", input.Position)
                end
            end)
            colorPicker.inputChanged = UserInputService.InputChanged:Connect(function(input)
                if colorPicker.panel.Visible
                    and colorPicker.drag
                    and (input.UserInputType == Enum.UserInputType.MouseMovement
                        or input.UserInputType == Enum.UserInputType.Touch) then
                    updateFromPointer(colorPicker.drag, input.Position)
                end
            end)
            colorPicker.inputEnded = UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    colorPicker.drag = nil
                end
            end)

            hex.FocusLost:Connect(function()
                local value = string.match(hex.Text, "^#?(%x%x%x%x%x%x)$")
                if value then
                    local r = tonumber(string.sub(value, 1, 2), 16)
                    local g = tonumber(string.sub(value, 3, 4), 16)
                    local b = tonumber(string.sub(value, 5, 6), 16)
                    colorPicker.h, colorPicker.s, colorPicker.v =
                        Color3.fromRGB(r, g, b):ToHSV()
                end

                updateColor()
            end)
            rgb.FocusLost:Connect(function()
                local r, g, b = string.match(
                    rgb.Text,
                    "^%s*(%d+)%s*[, ]%s*(%d+)%s*[, ]%s*(%d+)%s*$"
                )
                if r and g and b then
                    colorPicker.h, colorPicker.s, colorPicker.v = Color3.fromRGB(
                        math.clamp(tonumber(r) or 0, 0, 255),
                        math.clamp(tonumber(g) or 0, 0, 255),
                        math.clamp(tonumber(b) or 0, 0, 255)
                    ):ToHSV()
                end
                updateColor()
            end)
            close.MouseButton1Click:Connect(function()
                panel.Visible = false
            end)
            apply.MouseButton1Click:Connect(function()
                if colorPicker.callback then
                    colorPicker.callback(colorPicker.current)
                end
                panel.Visible = false
            end)
        end

        colorPicker.h, colorPicker.s, colorPicker.v = initialColor:ToHSV()
        colorPicker.callback = onApply
        colorPicker.panel.Visible = true
        colorPicker.update()

        for _, connection in ipairs(colorPicker.ownerConnections or {}) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        colorPicker.ownerConnections = watchPopupOwner(ownerRow, function()
            colorPicker.panel.Visible = false
            for _, connection in ipairs(colorPicker.ownerConnections or {}) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            colorPicker.ownerConnections = {}
        end)
    end

    state.colorPicker = colorPicker

    local function addColorOption(feature, labelText, defaultColor, callback, hintText)
        local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
        local color = colorFromConfig(configData.values[optionKey], defaultColor)
        local option = createOptionRow(feature, labelText, hintText)

        option.Size = UDim2.new(1, 0, 0, 44)
        local colorLabel: TextLabel? =
            option:FindFirstChild("OptionLabel") :: TextLabel?
        if colorLabel then
            (colorLabel :: TextLabel).Size =
                UDim2.new(0.55, -CHILD_INSET, 0, 22)
        end

        local hexValue: TextLabel = (create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "HexValue",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.new(1, -CHILD_INSET, 0, 0),
            Size = UDim2.new(0.42, 0, 0, 22),
            Text = "",
            TextColor3 = Theme.textMuted,
            TextSize = LABEL_FONT_SIZE,
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = option.ZIndex + 2,
        }) :: any) :: TextLabel

        local bar: Frame = (create("Frame", {
            Parent = option,
            Name = "ColorBar",
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            Position = UDim2.new(0, CHILD_INSET, 0, 22),
            Size = UDim2.new(1, -CHILD_INSET * 2, 0, 22),
            ZIndex = option.ZIndex + 1,
        }) :: any) :: Frame

        local swatch = create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = option,
            Name = "ColorClickTarget",
            Active = true,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            ZIndex = option.ZIndex + 3,
        })

        local function hexOf(value: Color3): string
            return string.format(
                "#%02X%02X%02X",
                math.floor(value.R * 255 + 0.5),
                math.floor(value.G * 255 + 0.5),
                math.floor(value.B * 255 + 0.5)
            )
        end
        hexValue.Text = hexOf(color)

        swatch.MouseButton1Click:Connect(function()
            colorPicker.open(color, function(newColor)
                color = newColor
                bar.BackgroundColor3 = color
                hexValue.Text = hexOf(color)
                configData.values[optionKey] = colorToConfig(color)
                callback(color)
                queueConfigSave()
            end, swatch)
        end)

        callback(color)
        return swatch
    end

    local function addInformationOption(feature: any, text: string): ()
        local current: string = feature.tooltipText or feature.description or ""
        local combined: string = current ~= "" and (current .. "\n" .. text) or text
        feature.tooltipText = combined
        feature.description = combined
    end

    type OptionDefinition = {
        kind: string,
        label: string,
        default: any?,
        minimum: number?,
        maximum: number?,
        values: {string}?,
        callback: any,
        persist: boolean?,
    }

    type FeatureDefinition = {
        name: string,
        description: string,
        order: number,
        onToggle: any,
        configuration: any?,
        options: {OptionDefinition}?,
    }

    local function addConfiguredOptions(
        feature: any,
        definitions: {OptionDefinition}
    ): ()
        for _, definition: OptionDefinition in ipairs(definitions) do
            if definition.kind == "toggle" then
                addToggleOption(
                    feature,
                    definition.label,
                    definition.default == true,
                    definition.callback
                )
            elseif definition.kind == "slider" then
                addNumberOption(
                    feature,
                    definition.label,
                    tonumber(definition.default) or 0,
                    definition.minimum or 0,
                    definition.maximum or 100,
                    definition.callback
                )
            elseif definition.kind == "color" then
                addColorOption(
                    feature,
                    definition.label,
                    definition.default :: Color3,
                    definition.callback
                )
            elseif definition.kind == "cycle" then
                addCycleOption(
                    feature,
                    definition.label,
                    definition.values or {},
                    tonumber(definition.default) or 1,
                    definition.callback
                )
            elseif definition.kind == "keybind" then
                addKeyOption(
                    feature,
                    definition.label,
                    definition.default :: Enum.KeyCode,
                    definition.callback
                )
            elseif definition.kind == "text" then
                addTextOption(
                    feature,
                    definition.label,
                    tostring(definition.default or ""),
                    definition.callback,
                    definition.persist
                )
            elseif definition.kind == "action" then
                addActionOption(feature, definition.label, definition.callback)
            elseif definition.kind == "info" then
                addInformationOption(feature, definition.label)
            end
        end
    end

    local function createFeatureFromDefinition(
        definition: FeatureDefinition
    ): any

        local feature: any = host.createUniversalFeature(
            definition.name,
            definition.description,
            definition.order,
            definition.onToggle,
            definition.configuration
        )
        if definition.options then
            addConfiguredOptions(feature, definition.options)
        end
        return feature
    end

    local function createFeaturesFromDefinitions(
        definitions: {FeatureDefinition}
    ): {any}
        local createdFeatures: {any} = {}
        for _, definition: FeatureDefinition in ipairs(definitions) do
            table.insert(
                createdFeatures,
                createFeatureFromDefinition(definition)
            )
        end
        return createdFeatures
    end

    state.components = {
        createFeature = createFeatureFromDefinition,
        createFeatures = createFeaturesFromDefinitions,
        addOptions = addConfiguredOptions,
    }

    Module.Initialized = true
    return {
        addToggleOption = addToggleOption,
        addActionOption = addActionOption,
        addNumberOption = addNumberOption,
        addRangeOption = state.addRangeOption,
        addCycleOption = addCycleOption,
        addKeyOption = addKeyOption,
        addTextOption = addTextOption,
        addColorOption = addColorOption,
        addListOption = state.addListOption,
        addSectionOption = state.addSectionOption,
        addInformationOption = addInformationOption,
        setOptionVisible = setOptionVisible,
        drawPixelIcon = drawPixelIcon,
    }
end

function Module.destroy(): ()
    Module.Initialized = false
end

return Module
]],
        ["src/libraries/Framework.lua"] = [[export type CleanupItem = any

export type MovementInputService = {
    getVector: () -> (number, number),
    isJumpHeld: () -> boolean,
    onJumpRequest: ((() -> ())) -> RBXScriptConnection,
}

export type OwnershipService<T> = {
    set: (ownerId: string, value: T?) -> (),
    apply: (instance: Instance?) -> (),
}

export type ModuleServices = {
    movementInput: MovementInputService,
    aim: {getRay: () -> Ray?},
    screenCapture: {
        isAvailable: () -> boolean,
        capture: (string) -> (boolean, string?),
        writeText: (string, string) -> boolean,
    },
    menu: {
        isVisible: () -> boolean,
        isCapturingInput: () -> boolean,
        setVisible: (boolean) -> (),
    },
    mobileActions: {bindPlacement: (...any) -> any},
    protectedTargets: {
        isProtected: (Player?) -> boolean,
        setProvider: (((Player?) -> boolean)?) -> (),
    },
    fovOwnership: OwnershipService<number>,
    platformStandOwnership: OwnershipService<boolean>,
    activity: {
        set: (string, boolean) -> (),
        isActive: (string) -> boolean,
    },
    spoofAvatar: any,
    projectileCalibration: any,
    gameBridge: any,
    shortcuts: any,
    registries: any,
}

export type ModuleContext = {
    framework: Framework,
    entity: any,
    weapons: any,
    render: any,
    libraries: {[string]: any},
    host: any,
    services: ModuleServices,
}

export type Option = {
    Name: string,

    Value: any,
    Object: any,
    SetVisible: (self: Option, visible: boolean) -> (),
}

export type Module = {
    Name: string,
    Category: string,
    Enabled: boolean,
    Feature: any,
    Options: {[string]: Option},
    OptionMetadata: {any},

    CreateToggle: (self: Module, definition: any) -> Option,
    CreateSlider: (self: Module, definition: any) -> Option,
    CreateTwoSlider: (self: Module, definition: any) -> Option,
    CreateDropdown: (self: Module, definition: any) -> Option,
    CreateBind: (self: Module, definition: any) -> Option,
    CreateTextBox: (self: Module, definition: any) -> Option,
    CreateColor: (self: Module, definition: any) -> Option,
    CreateList: (self: Module, definition: any) -> Option,
    CreateButton: (self: Module, definition: any) -> Option,
    CreateSection: (self: Module, name: string) -> Option,
    CreateNote: (self: Module, text: string) -> (),

    Clean: (self: Module, item: CleanupItem) -> CleanupItem,
    Loop: (self: Module, callback: (number) -> ()) -> any,
    Render: (self: Module, callback: (number) -> ()) -> any,
    Event: (self: Module, signal: any, callback: (...any) -> ()) -> any,
    CleanAll: (self: Module) -> (),
    Toggle: (self: Module, value: boolean?) -> (),
    Notify: (self: Module, message: string) -> (),
    SetStatus: (self: Module, status: string?) -> (),
}

export type Category = {
    Name: string,
    Modules: {Module},
    CreateModule: (self: Category, definition: any) -> Module,
}

export type Framework = {
    Categories: {[string]: Category},
    Modules: {[string]: Module},
    Order: {string},
    Host: any,
    GetCategory: (self: Framework, name: string) -> Category,
    GetModule: (self: Framework, name: string) -> Module?,
    DisableAll: (self: Framework) -> (),
    Destroy: (self: Framework) -> (),
}

local Module = {
    Name = "Framework",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local KNOWN_CATEGORIES: {string} = {
    "Combat",
    "Blatant",
    "Render",
    "Blocks",
    "Movement",
    "Fun",
    "Items",
    "Other",
}

local activeFramework: Framework? = nil

local function isKnownCategory(name: string): boolean
    return table.find(KNOWN_CATEGORIES, name) ~= nil
end

local CATEGORY_ALIASES: {[string]: string} = {
    ["Visuals"] = "Render",
    ["Protection"] = "Movement",
    ["Utility"] = "Other",
    ["Spoof"] = "Fun",
    ["General"] = "Other",
    ["Player"] = "Movement",
}

local function canonicalCategory(name: string): string
    if isKnownCategory(name) then
        return name
    end
    return CATEGORY_ALIASES[name] or "Other"
end

local function disposeItem(item: CleanupItem): ()
    if item == nil then
        return
    end
    local itemType: string = typeof(item)
    if itemType == "function" then
        pcall(item :: any)
        return
    end
    if itemType == "RBXScriptConnection" then
        pcall(function(): ()
            (item :: any):Disconnect()
        end)
        return
    end
    if itemType == "Instance" then
        pcall(function(): ()
            (item :: any):Destroy()
        end)
        return
    end
    if itemType == "table" then
        local candidate: any = item
        if type(candidate.Disconnect) == "function" then
            pcall(candidate.Disconnect, candidate)
            return
        end
        if type(candidate.Destroy) == "function" then
            pcall(candidate.Destroy, candidate)
            return
        end
        if type(candidate.disconnect) == "function" then
            pcall(candidate.disconnect, candidate)
            return
        end
    end
end

function Module.init(context: any): Framework
    local host: any = context
    local framework: any = {
        Categories = {},
        Modules = {},
        Order = {},
        Host = host,
    }

    local function normalizeSearchName(value: any): string
        return string.lower(tostring(value or "")):gsub("[%s%-%_]", "")
    end
    local moduleSearch: any = {
        entries = {},
        aliases = {
            esp = "playeresp",
            playeresp = "playeresp",
            itemesp = "itemesp",
            autoclicker = "autoclicker",
            killaura = "killaura",
            fly = "flight",
            speed = "speedhack",
            nofall = "nofall",
        },
    }
    function moduleSearch.Register(feature: any): ()
        if type(feature) ~= "table" then
            return
        end
        local normalized: string = normalizeSearchName(feature.name)
        local binding: any = host.state.shortcutBindings
            and host.state.shortcutBindings[feature.configKey]
        local entry: any = {
            normalized = normalized,
            displayName = feature.name,
            configKey = feature.configKey,
            actionId = feature.configKey,
            aliases = {},
            kind = feature.kind,
            searchable = feature.searchable ~= false,
            feature = feature,
            activate = feature.activate,
            invoke = feature.activate,
        }
        function entry.currentKey(): any
            return binding and binding.key or Enum.KeyCode.Unknown
        end
        function entry.conflict(): boolean
            local key: any = entry.currentKey()
            if key == nil or key == Enum.KeyCode.Unknown then
                return false
            end
            local uses: number = 0
            for _, candidate: any in pairs(host.state.shortcutBindings or {}) do
                if candidate.key == key then
                    uses += 1
                end
            end
            return uses > 1
        end
        function entry.capture(key: Enum.KeyCode): boolean
            return binding ~= nil and binding.assign(key) == true
        end
        function entry.remove(): ()
            if binding and binding.key ~= Enum.KeyCode.Unknown then
                binding.assign(binding.key)
            end
        end
        for alias: string, target: string in pairs(moduleSearch.aliases) do
            if target == normalized then
                table.insert(entry.aliases, alias)
            end
        end
        table.sort(entry.aliases)
        function entry.enabled(): boolean
            return feature.enabled == true
        end
        table.insert(moduleSearch.entries, entry)
    end
    function moduleSearch.Unregister(feature: any): ()
        for index: number = #moduleSearch.entries, 1, -1 do
            if moduleSearch.entries[index].feature == feature then
                table.remove(moduleSearch.entries, index)
            end
        end
    end
    function moduleSearch.Resolve(query: any): any
        local normalized: string = normalizeSearchName(query)
        if normalized == "" then
            return {status = "not_found"}
        end
        normalized = moduleSearch.aliases[normalized] or normalized
        local matches: {any} = {}
        for _, entry: any in ipairs(moduleSearch.entries) do
            if entry.searchable and entry.normalized == normalized then
                table.insert(matches, entry)
            end
        end
        if #matches == 0 then
            return {status = "not_found"}
        end
        if #matches > 1 then
            return {status = "ambiguous", matches = matches}
        end
        return {status = "success", entry = matches[1]}
    end
    function moduleSearch.Execute(query: any): any
        local result: any = moduleSearch.Resolve(query)
        if result.status ~= "success" then
            return result
        end
        local entry: any = result.entry
        if entry.kind ~= "toggle" and entry.kind ~= "action" then
            return {status = "not_toggleable", entry = entry}
        end
        if type(entry.activate) ~= "function" then
            return {status = "not_toggleable", entry = entry}
        end
        entry.activate()
        return {
            status = "success",
            entry = entry,
            enabled = entry.enabled(),
        }
    end
    host.state.moduleSearch = moduleSearch

    local function newOption(
        name: string,
        initialValue: any,
        optionType: string,
        definition: any?
    ): any
        local source: any = definition or {}
        local defaultValue: any = initialValue
        if type(initialValue) == "table" then
            defaultValue = table.clone(initialValue)
        end
        local step: number? = source.Step
        if step == nil and (optionType == "slider" or optionType == "range") then
            local integerOnly: boolean = type(source.Min) == "number"
                and type(source.Max) == "number"
                and source.Min % 1 == 0
                and source.Max % 1 == 0
                and ((type(initialValue) == "number" and initialValue % 1 == 0)
                    or (type(initialValue) == "table"
                        and initialValue.Min % 1 == 0
                        and initialValue.Max % 1 == 0))
            step = integerOnly and 1 or 0
        end
        local option: any = {
            Name = name,
            Value = initialValue,
            Object = nil,
            Metadata = {
                id = "",
                configKey = "",
                label = name,
                type = optionType,
                default = defaultValue,
                current = initialValue,
                min = source.Min,
                max = source.Max,
                step = step,
                values = source.List and table.clone(source.List) or nil,
                callback = source.Function,
                show = source.Show,
                visible = source.Show == nil,
                action = optionType == "action",
                bind = optionType == "bind",
                color = optionType == "color",
                rangeLow = source.DefaultMin,
                rangeHigh = source.DefaultMax,
            },
        }
        function option:SetValue(value: any): ()
            self.Value = value
            self.Metadata.current = value
            if type(value) == "table" and value.Min ~= nil and value.Max ~= nil then
                self.Metadata.rangeLow = value.Min
                self.Metadata.rangeHigh = value.Max
            end
        end
        function option:SetVisible(visible: boolean): ()
            self.Metadata.visible = visible
            local row: any = self.Object
            if typeof(row) == "Instance" and row.ClassName ~= "Frame" then
                row = row.Parent
            end
            if host.setOptionVisible and row then
                host.setOptionVisible(self.Feature, row, visible)
            end
        end
        return option
    end

    local function createModule(category: any, definition: any): Module
        local moduleName: string = definition.Name
        local categoryName: string = definition.Category or category.Name
        local created: any = {
            Name = moduleName,
            Category = categoryName,
            Enabled = false,
            Options = {},
            OptionMetadata = {},
            Cleanup = {},
        }

        local function onToggle(enabled: boolean?): ()
            local nextState: boolean = enabled == true
            created.Enabled = nextState
            if not nextState then
                created:CleanAll()
            end
            local handler: any = definition.Function
            if type(handler) == "function" then
                handler(nextState)
            end
            if not nextState then

                created:CleanAll()
            end
        end

        local kind: string = definition.Kind
            or (definition.Action == true and "action")
            or "toggle"
        local feature: any = host.createUniversalFeature(
            moduleName,
            definition.Tooltip or definition.Description or "",
            definition.Order or (#category.Modules + 1),
            kind == "action" and function(): ()
                if type(definition.Function) == "function" then
                    definition.Function(true)
                end
            end or onToggle,
            {
                categoryName = categoryName,
                kind = kind,
                silentAction = definition.Silent == true,
                searchable = definition.Searchable ~= false,
                registry = definition.Registry,
                parent = definition.Parent,
                configKey = definition.ConfigKey,
            }
        )
        created.Feature = feature
        feature.frameworkModule = true

        local function register(option: any, definition2: any?): Option
            option.Feature = feature
            local optionId: string = option.Name:gsub("%W", "")
            option.Metadata.id = optionId
            option.Metadata.configKey = feature.configKey .. "." .. optionId
            local gated: boolean = false
            if definition2 and type(definition2.Show) == "table" then
                option.Show = definition2.Show
                gated = true
            end
            created.Options[option.Name] = option
            table.insert(created.OptionMetadata, option.Metadata)
            feature.optionMetadata = created.OptionMetadata

            if gated then
                created:RefreshVisibility()
            end
            return option
        end

        local function ruleHolds(rule: any): boolean
            local source: any = created.Options[rule.Option]
            local holds: boolean = false
            if source ~= nil then
                if type(rule.Values) == "table" then
                    for _, wanted: any in ipairs(rule.Values) do
                        if source.Value == wanted then
                            holds = true
                            break
                        end
                    end
                else
                    holds = source.Value == true
                end
            end
            if rule.Invert == true then
                return not holds
            end
            return holds
        end

        function created:RefreshVisibility(): ()
            for _, option: any in pairs(created.Options) do
                local rule: any = option.Show
                if type(rule) ~= "table" then
                    continue
                end
                local visible: boolean = true
                if rule.Option ~= nil then
                    visible = ruleHolds(rule)
                else
                    for _, nested: any in ipairs(rule) do
                        if not ruleHolds(nested) then
                            visible = false
                            break
                        end
                    end
                end
                if option.Visible ~= visible then
                    option.Visible = visible
                    option:SetVisible(visible)
                end
            end
        end

        local function valueCallback(option: any, definition2: any): (any) -> ()
            local function changed(value: any): ()
                option:SetValue(value)
                if type(definition2.Function) == "function" then
                    definition2.Function(value)
                end
                created:RefreshVisibility()
            end
            option.Metadata.callback = changed
            return changed
        end

        function created:CreateToggle(definition2: any): Option
            local option: any = newOption(definition2.Name, definition2.Default == true, "toggle", definition2)
            option.Object = host.addToggleOption(
                feature,
                definition2.Name,
                definition2.Default == true,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateSlider(definition2: any): Option
            local default: number = definition2.Default or definition2.Min or 0
            local option: any = newOption(definition2.Name, default, "slider", definition2)
            option.Object = host.addNumberOption(
                feature,
                definition2.Name,
                default,
                definition2.Min or 0,
                definition2.Max or 100,
                valueCallback(option, definition2),
                definition2.Tooltip,
                definition2.Step
            )
            return register(option, definition2)
        end

        function created:CreateTwoSlider(definition2: any): Option
            local minimum: number = definition2.Min or 0
            local maximum: number = definition2.Max or 100
            local low: number = definition2.DefaultMin or minimum
            local high: number = definition2.DefaultMax or maximum
            local option: any = newOption(definition2.Name, {Min = low, Max = high}, "range", definition2)
            local builder: any = host.addRangeOption
                or (host.state and host.state.addRangeOption)
            option.GetRandomValue = function(_self: any): number
                local band: any = option.Value
                local lowValue: number = band.Min
                local highValue: number = math.max(band.Max, lowValue)
                return lowValue + math.random() * (highValue - lowValue)
            end
            if type(builder) ~= "function" then
                return register(option)
            end
            local function rangeChanged(newLow: number, newHigh: number): ()
                option:SetValue({Min = newLow, Max = newHigh})
                if type(definition2.Function) == "function" then
                    definition2.Function(newLow, newHigh)
                end
                created:RefreshVisibility()
            end
            option.Metadata.callback = rangeChanged
            option.Object = builder(feature, definition2.Name, {
                min = minimum,
                max = maximum,
                step = definition2.Step,
                defaultLow = low,
                defaultHigh = high,
                integer = definition2.Decimal == nil,
                hint = definition2.Tooltip,
                onChanged = rangeChanged,
            })
            return register(option, definition2)
        end

        function created:CreateDropdown(definition2: any): Option
            local list: {string} = definition2.List or {}
            local index: number = definition2.Index or 1
            local option: any = newOption(definition2.Name, list[index], "dropdown", definition2)
            option.Object = host.addCycleOption(
                feature,
                definition2.Name,
                list,
                index,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateBind(definition2: any): Option
            local default: Enum.KeyCode = definition2.Default or Enum.KeyCode.Unknown
            local option: any = newOption(definition2.Name, default, "bind", definition2)
            option.Object = host.addKeyOption(
                feature,
                definition2.Name,
                default,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateTextBox(definition2: any): Option
            local default: string = definition2.Default or ""
            local option: any = newOption(definition2.Name, default, "text", definition2)
            option.Object = host.addTextOption(
                feature,
                definition2.Name,
                default,
                valueCallback(option, definition2),
                definition2.Persist ~= false,
                definition2.Tooltip
            )
            option.Set = function(self: any, value: string): ()
                self.Metadata.callback(value)
                if self.Object then
                    self.Object.Text = value
                end
            end
            return register(option, definition2)
        end

        function created:CreateColor(definition2: any): Option
            local default: Color3 = definition2.Default or Color3.new(1, 1, 1)
            local option: any = newOption(definition2.Name, default, "color", definition2)
            option.Object = host.addColorOption(
                feature,
                definition2.Name,
                default,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateList(definition2: any): Option
            local option: any = newOption(definition2.Name, {}, "list", definition2)
            option.Selected = {}

            local builder: any = host.addListOption
                or (host.state and host.state.addListOption)
            if type(builder) ~= "function" then

                return register(option)
            end
            local optionKey: string = feature.configKey
                .. "."
                .. definition2.Name:gsub("%W", "")
            local function listChanged(selected: any, names: {string}): ()
                option:SetValue(selected)
                option.Selected = names
                if type(definition2.Function) == "function" then
                    definition2.Function(selected, names)
                end
                created:RefreshVisibility()
            end
            option.Metadata.callback = listChanged
            option.Object = builder(feature, definition2.Name, {
                items = definition2.Items,
                default = definition2.Default,
                hint = definition2.Tooltip,
                emptyText = definition2.EmptyText,
                onChanged = listChanged,
            })

            local controls: any = host.state
                and host.state.listControls
                and host.state.listControls[optionKey]
            option.Set = function(_self: any, item: string, on: boolean): ()
                if controls then
                    controls.set(item, on)
                end
            end
            option.Refresh = function(_self: any): ()
                if controls then
                    controls.refresh()
                end
            end
            option.IsSelected = function(_self: any, item: string): boolean
                if controls then
                    return controls.selected[item] == true
                end
                return false
            end
            return register(option, definition2)
        end

        function created:CreateButton(definition2: any): Option
            local option: any = newOption(definition2.Name, nil, "action", definition2)
            local function run(): ()
                if type(definition2.Function) == "function" then
                    definition2.Function()
                end
            end
            option.Metadata.callback = run
            option.Object = host.addActionOption(
                feature,
                definition2.Name,
                run,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateSection(name: string): Option
            local option: any = newOption(name, nil, "section", nil)
            option.Object = host.addSectionOption
                and host.addSectionOption(feature, name)
                or nil

            return register(option)
        end

        function created:CreateNote(text: string): ()
            if host.addInformationOption then
                host.addInformationOption(feature, text)
            end
        end

        function created:Clean(item: CleanupItem): CleanupItem
            table.insert(created.Cleanup, item)
            return item
        end

        function created:Loop(callback: (number) -> ()): any
            return created:Clean(host.TaskManager:Connect(callback))
        end

        function created:Render(callback: (number) -> ()): any
            return created:Clean(host.TaskManager:Connect(callback, "render"))
        end

        function created:Event(signal: any, callback: (...any) -> ()): any
            return created:Clean(signal:Connect(callback))
        end

        function created:CleanAll(): ()
            local items: {CleanupItem} = created.Cleanup
            created.Cleanup = {}

            for index: number = #items, 1, -1 do
                disposeItem(items[index])
            end
        end

        function created:Toggle(value: boolean?): ()
            if value ~= nil and value == created.Enabled then
                return
            end
            if feature and type(feature.activate) == "function" then
                feature.activate()
                return
            end
            onToggle(not created.Enabled)
        end

        function created:SetStatus(status: string?): ()
            created.Status = status
            if feature and type(feature.SetStatus) == "function" then
                feature:SetStatus(status)
            end
        end

        function created:Notify(message: string): ()
            if host.notify then
                host.notify(moduleName .. ": " .. message)
            end
        end

        table.insert(category.Modules, created)
        framework.Modules[moduleName] = created
        table.insert(framework.Order, moduleName)
        return (created :: any) :: Module
    end

    function framework:GetCategory(name: string): Category
        local existing: any = framework.Categories[name]
        if existing then
            return existing
        end

        local canonical: string = canonicalCategory(name)
        local category: any = framework.Categories[canonical]
        if not category then
            category = {
                Name = canonical,
                Modules = {},
            }
            function category:CreateModule(definition: any): Module
                return createModule(category, definition)
            end
            framework.Categories[canonical] = category
        end
        if name ~= canonical then
            framework.Categories[name] = category
        end
        return (category :: any) :: Category
    end

    function framework:GetModule(name: string): Module?
        return framework.Modules[name]
    end

    function framework:DisableAll(): ()
        for _, moduleName: string in ipairs(framework.Order) do
            local entry: any = framework.Modules[moduleName]
            if entry and entry.Enabled then
                pcall(function(): ()
                    entry:Toggle(false)
                end)
            end
            if entry then
                pcall(function(): ()
                    entry:CleanAll()
                end)
            end
        end
    end

    function framework:Destroy(): ()
        framework:DisableAll()
        framework.Categories = {}
        framework.Modules = {}
        framework.Order = {}
        if host.state.moduleSearch == moduleSearch then
            host.state.moduleSearch = nil
        end
        table.clear(moduleSearch.entries)
        if activeFramework == framework then
            activeFramework = nil
        end
    end

    for _, name: string in ipairs(KNOWN_CATEGORIES) do
        framework:GetCategory(name)
    end
    for oldName: string in pairs(CATEGORY_ALIASES) do
        framework:GetCategory(oldName)
    end

    activeFramework = (framework :: any) :: Framework
    Module.Initialized = true
    return (framework :: any) :: Framework
end

function Module.destroy(): ()
    local framework: Framework? = activeFramework
    if framework then
        framework:Destroy()
    end
    activeFramework = nil
    Module.Initialized = false
end

return Module
]],
        ["src/libraries/Entity.lua"] = [[export type Entity = {
    Player: Player?,
    Character: Model,
    Humanoid: Humanoid,
    RootPart: BasePart,
    Head: BasePart?,
    Health: number,
    MaxHealth: number,
    Distance: number,
    Team: Team?,
    IsFriendly: boolean,
    IsNPC: boolean,
    Name: string,
}

export type RangeQuery = {
    Range: number,
    Limit: number?,
    IgnoreTeam: boolean?,
    IgnoreWalls: boolean?,
    IgnoreFriends: boolean?,
    Angle: number?,
    Sort: string?,
    IncludeNPCs: boolean?,
}

export type EntityQuery = {

    Radius: number?,
    MaxDistance: number?,
    IgnoreTeam: boolean?,
    IgnoreWalls: boolean?,
    IgnoreFriends: boolean?,
    Part: string?,
    IncludeNPCs: boolean?,
}

export type EntityLibrary = {
    List: {Entity},
    ByPlayer: {[Player]: Entity},
    NPCList: {Entity},
    ByModel: {[Model]: Entity},
    LocalEntity: Entity?,
    IsAlive: (self: EntityLibrary) -> boolean,
    Refresh: (self: EntityLibrary) -> {Entity},
    Get: (self: EntityLibrary, player: Player) -> Entity?,
    GetNpc: (self: EntityLibrary, model: Model) -> Entity?,
    ForEach: (self: EntityLibrary, callback: (Entity) -> ()) -> (),
    IsFriendly: (self: EntityLibrary, player: Player?) -> boolean,
    IsFriendlyModel: (self: EntityLibrary, model: Model) -> boolean,
    IsProtected: (self: EntityLibrary, player: Player?) -> boolean,
    InRange: (self: EntityLibrary, query: RangeQuery) -> {Entity},
    ClosestToRay: (
        self: EntityLibrary,
        origin: Vector3,
        direction: Vector3,
        query: EntityQuery?
    ) -> Entity?,
    ClosestToCursor: (self: EntityLibrary, query: EntityQuery?) -> Entity?,
    VisibleFrom: (self: EntityLibrary, entity: Entity) -> boolean,
    Rig: (self: EntityLibrary, entity: Entity) -> {{BasePart}},
    Destroy: (self: EntityLibrary) -> (),
}

local Module = {
    Name = "Entity",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local R15_BONES: {{string}} = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
}

local R6_BONES: {{string}} = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"},
}

local activeLibrary: EntityLibrary? = nil

function Module.init(context: any): EntityLibrary
    local host: any = context
    local players: Players = host.Players
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace

    local library: any = {
        List = {},
        ByPlayer = {},
        NPCList = {},
        ByModel = {},
        LocalEntity = nil,
        Connections = {},

        lastRefresh = -1,
        pool = setmetatable({}, {__mode = "k"}),
        npcPool = setmetatable({}, {__mode = "k"}),
        npcModels = setmetatable({}, {__mode = "k"}),
        rigs = setmetatable({}, {__mode = "k"}),
    }

    local function characterParts(player: Player): (Model?, Humanoid?, BasePart?)
        local character: Model? = player.Character
        if not character or not character.Parent then
            for _, containerName: string in ipairs({"PlayersContainer", "Characters", "Live", "Players"}) do
                local container: Instance? = currentWorkspace:FindFirstChild(containerName)
                local candidate: Instance? = container and container:FindFirstChild(player.Name)
                if candidate and candidate:IsA("Model") then
                    character = candidate :: Model
                    break
                end
            end
        end
        if not character or not character.Parent then
            return nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            or character.PrimaryPart
            or character:FindFirstChildWhichIsA("BasePart") :: BasePart?
        return character, humanoid, root
    end

    local function localRoot(): BasePart?
        local _, _, root = characterParts(localPlayer)
        return root
    end

    local TEAM_ATTRIBUTE_NAMES: {string} = {
        "Team",
        "TeamId",
        "TeamID",
        "Faction",
        "FactionId",
        "FactionID",
    }

    local function normalizeTeamValue(value: any): string?
        if value == nil then
            return nil
        end
        if typeof(value) == "Instance" then
            return "name:" .. string.lower((value :: Instance).Name)
        end
        if type(value) == "table" and type(value.Name) == "string" then
            return "name:" .. string.lower(value.Name)
        end
        if type(value) == "table"
            and type(value.R) == "number"
            and type(value.G) == "number"
            and type(value.B) == "number" then
            return string.format(
                "colour:%d:%d:%d",
                math.round(value.R * 255),
                math.round(value.G * 255),
                math.round(value.B * 255)
            )
        end
        if type(value) == "table" and value.Color ~= nil then
            local nested: string? = normalizeTeamValue(value.Color)
            if nested then
                return nested
            end
        end
        if type(value) == "string" then
            return "name:" .. string.lower(value)
        end
        local text: string = tostring(value)
        if text == "" or text == "nil" then
            return nil
        end
        return "value:" .. string.lower(text)
    end

    local function teamToken(instance: Instance): string?
        for _, attributeName: string in ipairs(TEAM_ATTRIBUTE_NAMES) do
            local ok: boolean, value: any = pcall(
                instance.GetAttribute,
                instance,
                attributeName
            )
            if ok then
                local normalized: string? = normalizeTeamValue(value)
                if normalized then
                    return normalized
                end
            end
        end

        local directOk: boolean, direct: any = pcall(function(): any
            return (instance :: any).Team
        end)
        if directOk then
            local normalizedDirect: string? = normalizeTeamValue(direct)
            if normalizedDirect then
                return normalizedDirect
            end
        end
        local colourOk: boolean, colour: any = pcall(function(): any
            return (instance :: any).TeamColor
        end)
        if colourOk then
            local normalizedColour: string? = normalizeTeamValue(colour)
            if normalizedColour then
                return normalizedColour
            end
        end
        local child: Instance? = instance:FindFirstChild("Team")
        if child then
            local valueOk: boolean, childValue: any = pcall(function(): any
                return (child :: any).Value
            end)
            return normalizeTeamValue(valueOk and childValue or child.Name)
        end
        return nil
    end

    local function localTeamToken(): string?
        return teamToken(localPlayer)
    end

    function library:IsFriendly(player: Player?): boolean
        if not player or player == localPlayer then
            return false
        end

        if player.Neutral == true or localPlayer.Neutral == true then
            return false
        end
        local localToken: string? = localTeamToken()
        local targetToken: string? = teamToken(player)
        return localToken ~= nil and targetToken ~= nil and localToken == targetToken
    end

    function library:IsFriendlyModel(model: Model): boolean
        if model == localPlayer.Character then
            return false
        end
        local localToken: string? = localTeamToken()
        local targetToken: string? = teamToken(model)
        return localToken ~= nil and targetToken ~= nil and localToken == targetToken
    end

    local function npcParts(model: Model): (Humanoid?, BasePart?)
        local humanoid: Humanoid? =
            model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? =
            model:FindFirstChild("HumanoidRootPart") :: BasePart?
                or model.PrimaryPart
                or model:FindFirstChildWhichIsA("BasePart") :: BasePart?
        return humanoid, root
    end

    local function isNpcModel(model: Model): boolean
        if not model.Parent or model == localPlayer.Character then
            return false
        end
        if players:GetPlayerFromCharacter(model) ~= nil then
            return false
        end
        -- The local Disguise body double is the local player's own stand-in,
        -- never an NPC to target.
        if model:GetAttribute("WurstDisguise") == true then
            return false
        end
        local humanoid: Humanoid?, root: BasePart? = npcParts(model)
        return humanoid ~= nil and root ~= nil
    end

    local function modelFor(instance: Instance): Model?
        if instance:IsA("Model") then
            return instance :: Model
        end
        return instance:FindFirstAncestorOfClass("Model") :: Model?
    end

    local function indexNpc(instance: Instance): ()
        local model: Model? = modelFor(instance)
        if model and isNpcModel(model) then
            library.npcModels[model] = true
        end
    end

    local function unindexNpc(instance: Instance): ()
        local model: Model? = modelFor(instance)
        if model and (instance == model or not model.Parent) then
            library.npcModels[model] = nil
            library.ByModel[model] = nil
        end
    end

    local function refreshNpcs(originPosition: Vector3): ()
        local list: {Entity} = library.NPCList
        local byModel: {[Model]: Entity} = library.ByModel
        table.clear(list)
        table.clear(byModel)
        for model: Model in pairs(library.npcModels) do
            if not isNpcModel(model) then
                library.npcModels[model] = nil
                continue
            end
            local humanoid: Humanoid?, root: BasePart? = npcParts(model)
            if not humanoid or not root or humanoid.Health <= 0 then
                continue
            end
            local entity: any = library.npcPool[model]
            if not entity then
                entity = {}
                library.npcPool[model] = entity
            end
            entity.Player = nil
            entity.Character = model
            entity.Humanoid = humanoid
            entity.RootPart = root
            entity.Head = model:FindFirstChild("Head") :: BasePart?
            entity.Health = humanoid.Health
            entity.MaxHealth = math.max(humanoid.MaxHealth, 1)
            entity.Distance = (originPosition - root.Position).Magnitude
            entity.Team = nil
            entity.IsFriendly = library:IsFriendlyModel(model)
            entity.IsNPC = true
            entity.Name = model.Name
            byModel[model] = entity
            table.insert(list, entity)
        end
    end

    function library:Refresh(force: boolean?): {Entity}

        local now: number = os.clock()
        if not force and now - library.lastRefresh < 1 / 30 then
            return library.List
        end
        library.lastRefresh = now

        local origin: BasePart? = localRoot()
        local originPosition: Vector3 = origin and origin.Position or Vector3.zero
        local list: {Entity} = library.List
        table.clear(list)
        local byPlayer: {[Player]: Entity} = library.ByPlayer
        table.clear(byPlayer)

        for _, player: Player in ipairs(players:GetPlayers()) do
            local character, humanoid, root = characterParts(player)
            if not character or not humanoid or not root then
                continue
            end
            if humanoid.Health <= 0 then
                continue
            end

            local entity: any = library.pool[player]
            if not entity then
                entity = {}
                library.pool[player] = entity
            end
            entity.Player = player
            entity.Character = character
            entity.Humanoid = humanoid
            entity.RootPart = root
            entity.Head = character:FindFirstChild("Head") :: BasePart?
            entity.Health = humanoid.Health
            entity.MaxHealth = math.max(humanoid.MaxHealth, 1)
            entity.Distance = (originPosition - root.Position).Magnitude
            entity.Team = player.Team
            entity.IsFriendly = library:IsFriendly(player)
            entity.IsNPC = false
            entity.Name = player.Name

            byPlayer[player] = entity
            if player == localPlayer then
                library.LocalEntity = entity
            else
                table.insert(list, entity)
            end
        end

        if not byPlayer[localPlayer] then
            library.LocalEntity = nil
        end
        refreshNpcs(originPosition)
        return list
    end

    function library:IsAlive(): boolean
        local _, humanoid, root = characterParts(localPlayer)
        return humanoid ~= nil and root ~= nil and humanoid.Health > 0
    end

    function library:Get(player: Player): Entity?
        return library.ByPlayer[player]
    end

    function library:GetNpc(model: Model): Entity?
        return library.ByModel[model]
    end

    function library:ForEach(callback: (Entity) -> ()): ()
        for _, entity: Entity in ipairs(library.List) do
            callback(entity)
        end
    end

    function library:VisibleFrom(entity: Entity): boolean
        local camera: Camera? = currentWorkspace.CurrentCamera
        if not camera then
            return false
        end
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        parameters.FilterDescendantsInstances = {
            entity.Character,
            localPlayer.Character :: any,
            camera,
        }
        local origin: Vector3 = camera.CFrame.Position
        local target: Vector3 = entity.RootPart.Position
        local result: RaycastResult? = currentWorkspace:Raycast(
            origin,
            target - origin,
            parameters
        )
        return result == nil
    end

    function library:Rig(entity: Entity): {{BasePart}}
        local character: Model = entity.Character
        local cached: any = library.rigs[character]
        if cached then
            return cached
        end
        local bones: {{BasePart}} = {}
        local definitions: {{string}} =
            character:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
        for _, pair: {string} in ipairs(definitions) do
            local first: BasePart? = character:FindFirstChild(pair[1]) :: BasePart?
            local second: BasePart? = character:FindFirstChild(pair[2]) :: BasePart?
            if first and second then
                table.insert(bones, {first, second})
            end
        end
        library.rigs[character] = bones
        return bones
    end

    function library:IsProtected(player: Player?): boolean
        if not player then
            return false
        end
        local targets: any = host.services and host.services.protectedTargets
        if targets and type(targets.isProtected) == "function" then
            return targets.isProtected(player) == true
        end
        return false
    end

    function library:InRange(query: RangeQuery): {Entity}
        local origin: BasePart? = localRoot()
        if not origin then
            return {}
        end
        local resolvedOrigin: BasePart = origin :: BasePart
        local facing: Vector3 = resolvedOrigin.CFrame.LookVector
            * Vector3.new(1, 0, 1)
        local halfAngle: number? = query.Angle and math.rad(query.Angle) / 2 or nil
        local candidates: {Entity} = {}

        local function consider(entity: Entity): ()
            if entity.Distance > query.Range then
                return
            end
            if not query.IgnoreTeam and entity.IsFriendly then
                return
            end
            if not query.IgnoreFriends and library:IsProtected(entity.Player) then
                return
            end
            if halfAngle then
                local delta: Vector3 = (entity.RootPart.Position - resolvedOrigin.Position)
                    * Vector3.new(1, 0, 1)
                if delta.Magnitude > 0.001 and facing.Magnitude > 0.001 then
                    local dot: number = facing.Unit:Dot(delta.Unit)
                    if math.acos(math.clamp(dot, -1, 1)) > halfAngle then
                        return
                    end
                end
            end
            if not query.IgnoreWalls and not library:VisibleFrom(entity) then
                return
            end
            table.insert(candidates, entity)
        end

        for _, entity: Entity in ipairs(library.List) do
            consider(entity)
        end
        if query.IncludeNPCs then
            for _, entity: Entity in ipairs(library.NPCList) do
                consider(entity)
            end
        end

        local sortMode: string = query.Sort or "Distance"
        table.sort(candidates, function(first: Entity, second: Entity): boolean
            if sortMode == "Health" then
                return first.Health < second.Health
            end
            if sortMode == "Threat" then

                return first.Distance / math.max(first.Health, 1)
                    > second.Distance / math.max(second.Health, 1)
            end
            return first.Distance < second.Distance
        end)

        local limit: number = query.Limit or #candidates
        while #candidates > limit do
            table.remove(candidates)
        end
        return candidates
    end

    function library:ClosestToRay(
        origin: Vector3,
        direction: Vector3,
        query: EntityQuery?
    ): Entity?
        local options: EntityQuery = query or {}
        local unit: Vector3 = direction.Magnitude > 0
            and direction.Unit
            or Vector3.new(0, 0, -1)
        local maxDistance: number = options.MaxDistance or math.huge
        local best: Entity? = nil
        local bestScore: number = math.huge

        local function consider(entity: Entity): ()
            if not options.IgnoreTeam and entity.IsFriendly then
                return
            end
            if entity.Distance > maxDistance then
                return
            end
            if not options.IgnoreFriends and library:IsProtected(entity.Player) then
                return
            end
            local part: BasePart = entity.RootPart
            if options.Part == "Head" and entity.Head then
                part = entity.Head :: BasePart
            end
            local offset: Vector3 = part.Position - origin
            local along: number = offset:Dot(unit)
            if along <= 0 then
                return
            end

            local perpendicular: number = (offset - unit * along).Magnitude
            if perpendicular < bestScore
                and (options.IgnoreWalls or library:VisibleFrom(entity)) then
                best = entity
                bestScore = perpendicular
            end
        end
        for _, entity: Entity in ipairs(library.List) do
            consider(entity)
        end
        if options.IncludeNPCs then
            for _, entity: Entity in ipairs(library.NPCList) do
                consider(entity)
            end
        end

        local radius: number? = options.Radius
        if radius and bestScore > radius then
            return nil
        end
        return best
    end

    function library:ClosestToCursor(query: EntityQuery?): Entity?
        local camera: Camera? = currentWorkspace.CurrentCamera
        if not camera then
            return nil
        end
        local ray: Ray? = host.services and host.services.aim.getRay()
        local origin: Vector3 = ray and ray.Origin or camera.CFrame.Position
        local direction: Vector3 = ray and ray.Direction or camera.CFrame.LookVector
        return library:ClosestToRay(origin, direction, query)
    end

    function library:Destroy(): ()
        for _, connection: RBXScriptConnection in ipairs(library.Connections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        library.Connections = {}
        library.List = {}
        library.ByPlayer = {}
        library.NPCList = {}
        library.ByModel = {}
        library.npcModels = setmetatable({}, {__mode = "k"})
        library.LocalEntity = nil
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
        indexNpc(descendant)
    end
    table.insert(
        library.Connections,
        currentWorkspace.DescendantAdded:Connect(indexNpc)
    )
    table.insert(
        library.Connections,
        currentWorkspace.DescendantRemoving:Connect(unindexNpc)
    )

    table.insert(
        library.Connections,
        players.PlayerAdded:Connect(function(player: Player): ()
            table.insert(
                library.Connections,
                player.CharacterAdded:Connect(function(): ()
                    library:Refresh(true)
                end)
            )
            library:Refresh(true)
        end)
    )
    table.insert(
        library.Connections,
        players.PlayerRemoving:Connect(function(player: Player): ()
            library.ByPlayer[player] = nil
            library:Refresh(true)
        end)
    )
    for _, player: Player in ipairs(players:GetPlayers()) do
        table.insert(
            library.Connections,
            player.CharacterAdded:Connect(function(): ()
                library:Refresh(true)
            end)
        )
    end
    library:Refresh(true)

    activeLibrary = (library :: any) :: EntityLibrary
    Module.Initialized = true
    return (library :: any) :: EntityLibrary
end

function Module.destroy(): ()
    local library: EntityLibrary? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
]],
        ["src/libraries/Targeting.lua"] = [[export type Query = {
    FOV: number?,
    MaxDistance: number?,
    TargetPart: string?,
    Prediction: number?,
    TeamCheck: boolean?,
    VisibilityCheck: boolean?,
    Priority: string?,
    IncludeNPCs: boolean?,
    AllowOffscreen: boolean?,
}

export type Target = {
    player: Player?,
    entity: any,
    character: Model,
    part: BasePart,
    position: Vector3,
    screenPosition: Vector2,
    distance: number,
    cursorDistance: number,
}

export type Library = {
    List: (self: Library, entities: any, query: Query?) -> {Target},
    Select: (self: Library, entities: any, query: Query?) -> Target?,
    Destroy: (self: Library) -> (),
}

local Module = {
    Name = "Targeting",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: Library? = nil

local function asBasePart(instance: Instance?): BasePart?
    if instance and instance:IsA("BasePart") then
        return instance :: BasePart
    end
    return nil
end

function Module.init(context: any): Library
    local host: any = context.host or context
    local userInput: UserInputService? = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local localPlayer: Player? = host.LocalPlayer
    local services: any = context.services or host.services

    local library: any = {}

    local function camera(): Camera?
        return currentWorkspace.CurrentCamera
    end

    local function cursor(cameraObject: Camera): Vector2
        if userInput and userInput.MouseEnabled then
            local ok: boolean, location: any = pcall(
                (userInput :: UserInputService).GetMouseLocation,
                userInput
            )
            if ok and typeof(location) == "Vector2" then
                return location :: Vector2
            end
        end
        local viewport: Vector2 = cameraObject.ViewportSize
        return Vector2.new(viewport.X / 2, viewport.Y / 2)
    end

    local function targetParts(entity: any, requested: string?): {BasePart}
        local character: Model = entity.Character
        local wanted: string = requested or "Closest"
        if wanted == "Head" then
            return {
                asBasePart(character:FindFirstChild("Head")) or entity.RootPart,
            }
        end
        if wanted == "Torso" then
            return {
                asBasePart(character:FindFirstChild("UpperTorso"))
                    or asBasePart(character:FindFirstChild("Torso"))
                    or entity.RootPart,
            }
        end
        if wanted ~= "Closest" then
            return {entity.RootPart}
        end
        local head: BasePart? = asBasePart(character:FindFirstChild("Head"))
        if head then
            return {head, entity.RootPart}
        end
        return {entity.RootPart}
    end

    local function protected(player: Player?): boolean
        if not player then
            return false
        end
        local policy: any = services and services.protectedTargets
        if policy and type(policy.isProtected) == "function" then
            return policy.isProtected(player) == true
        end
        return false
    end

    local function visibleFrom(
        cameraObject: Camera,
        entity: any,
        position: Vector3
    ): boolean
        local origin: Vector3 = cameraObject.CFrame.Position
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        local ignored: {Instance} = {entity.Character, cameraObject}
        if localPlayer and localPlayer.Character then
            table.insert(ignored, localPlayer.Character)
        end
        parameters.FilterDescendantsInstances = ignored
        parameters.IgnoreWater = true
        local ok: boolean, result: any = pcall(
            currentWorkspace.Raycast,
            currentWorkspace,
            origin,
            position - origin,
            parameters
        )
        return ok and result == nil
    end

    local function candidateForPart(
        cameraObject: Camera,
        pointer: Vector2,
        entity: any,
        part: BasePart,
        prediction: number,
        query: Query
    ): Target?
        local velocity: Vector3 = part.AssemblyLinearVelocity or Vector3.zero
        local predicted: Vector3 = part.Position + velocity * prediction
        local projected: Vector3, onScreen: boolean =
            cameraObject:WorldToViewportPoint(predicted)
        if (not onScreen or projected.Z <= 0) and not query.AllowOffscreen then
            return nil
        end
        local screenPosition: Vector2 = Vector2.new(projected.X, projected.Y)
        local cursorDistance: number = onScreen
                and (screenPosition - pointer).Magnitude
            or math.huge
        if query.FOV ~= nil and cursorDistance > (query.FOV :: number) then
            return nil
        end
        if query.VisibilityCheck == true
            and not visibleFrom(cameraObject, entity, predicted) then
            return nil
        end
        return {
            player = entity.Player,
            entity = entity,
            character = entity.Character,
            part = part,
            position = predicted,
            screenPosition = screenPosition,
            distance = entity.Distance,
            cursorDistance = cursorDistance,
        }
    end

    function library:List(entities: any, query: Query?): {Target}
        local options: Query = query or {}
        local cameraObject: Camera? = camera()
        if not cameraObject or not entities then
            return {}
        end
        if type(entities.Refresh) == "function" then
            entities:Refresh()
        end
        local pointer: Vector2 = cursor(cameraObject :: Camera)
        local found: {Target} = {}
        local maxDistance: number = options.MaxDistance or math.huge
        local prediction: number = math.max(options.Prediction or 0, 0)

        local function consider(entity: any): ()
            if entity.Distance > maxDistance then
                return
            end
            if options.TeamCheck ~= false and entity.IsFriendly then
                return
            end
            if protected(entity.Player) then
                return
            end

            local bestForEntity: Target? = nil
            for _, part: BasePart in ipairs(targetParts(entity, options.TargetPart)) do
                local candidate: Target? = candidateForPart(
                    cameraObject :: Camera,
                    pointer,
                    entity,
                    part,
                    prediction,
                    options
                )
                if candidate
                    and (not bestForEntity
                        or candidate.cursorDistance < (bestForEntity :: Target).cursorDistance) then
                    bestForEntity = candidate
                end
            end
            if bestForEntity then
                table.insert(found, bestForEntity :: Target)
            end
        end
        for _, entity: any in ipairs(entities.List or {}) do
            consider(entity)
        end
        if options.IncludeNPCs then
            for _, entity: any in ipairs(entities.NPCList or {}) do
                consider(entity)
            end
        end

        local priority: string = options.Priority or "Cursor"
        table.sort(found, function(first: Target, second: Target): boolean
            if priority == "Distance" then
                if first.distance == second.distance then
                    return first.cursorDistance < second.cursorDistance
                end
                return first.distance < second.distance
            end
            if first.cursorDistance == second.cursorDistance then
                return first.distance < second.distance
            end
            return first.cursorDistance < second.cursorDistance
        end)
        return found
    end

    function library:Select(entities: any, query: Query?): Target?
        return self:List(entities, query)[1]
    end

    function library:Destroy(): ()
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = (library :: any) :: Library
    Module.Initialized = true
    return (library :: any) :: Library
end

function Module.destroy(): ()
    local library: Library? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
]],
        ["src/libraries/Weapons.lua"] = [[export type Candidate = {
    id: string,
    label: string,
    kind: string,
    melee: boolean,
    instance: Instance,
}

export type GameSource = {

    scan: () -> {{string}},

    press: (label: string, target: any?) -> boolean,
}

export type WeaponLibrary = {
    Scan: (self: WeaponLibrary, query: any?) -> {Candidate},
    Labels: (self: WeaponLibrary, query: any?) -> {string},
    Find: (self: WeaponLibrary, label: string) -> Candidate?,
    IsMelee: (self: WeaponLibrary, name: string) -> boolean,
    Activate: (self: WeaponLibrary, candidate: Candidate, target: any?) -> boolean,
    Best: (self: WeaponLibrary, query: any?) -> Candidate?,
    Invalidate: (self: WeaponLibrary) -> (),
    SetAllowEquip: (self: WeaponLibrary, allowed: boolean) -> (),
    Swing: (self: WeaponLibrary) -> boolean,
    RegisterGameSource: (self: WeaponLibrary, source: GameSource?) -> (),
    PressButton: (self: WeaponLibrary, button: GuiButton) -> boolean,
    Destroy: (self: WeaponLibrary) -> (),
}

local Module = {
    Name = "Weapons",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local WEAPON_WORDS: {string} = {
    "sword",
    "katana",
    "dagger",
    "blade",
    "knife",
    "axe",
    "mace",
    "spear",
    "scythe",
    "sabre",
    "saber",
    "machete",
    "hammer",
    "club",
    "bat",
    "staff",
    "pickaxe",
    "fist",
    "punch",
    "attack",
    "swing",
    "hit",
    "melee",
    "weapon",
    "combat",
}

local MELEE_WORDS: {string} = {
    "sword",
    "katana",
    "dagger",
    "blade",
    "knife",
    "axe",
    "mace",
    "spear",
    "scythe",
    "sickle",
    "sabre",
    "saber",
    "rapier",
    "cutlass",
    "machete",
    "glaive",
    "halberd",
    "hammer",
    "club",
    "baton",
    "bat",
    "pickaxe",
    "fist",
    "knuckle",
}

local RANGED_WORDS: {string} = {
    "bow",
    "crossbow",
    "arrow",
    "gun",
    "rifle",
    "pistol",
    "revolver",
    "shotgun",
    "sniper",
    "launcher",
    "rocket",
    "grenade",
    "snowball",
    "projectile",
    "throw",
    "wand",
    "staff",
    "gauntlet",
    "fireball",
}

local RIG_WORDS: {string} = {
    "hand",
    "arm",
    "leg",
    "foot",
    "torso",
    "head",
    "upper",
    "lower",
    "root",
    "limb",
    "joint",
    "motor",
    "weld",
    "attachment",
    "rig",
    "bone",
    "hitbox",
    "collider",
    "humanoid",
    "camera",
    "viewmodel",
    "idle",
    "walk",
    "run",
    "sprint",
    "sneak",
    "crouch",
    "jump",
    "fall",
    "land",
    "swim",
    "pose",
    "track",
    "sequence",
}

local NOT_WEAPON_WORDS: {string} = {
    "emote",
    "animation",
    "anim",
    "dance",
    "cosmetic",
    "cape",
    "skin",
    "kit",
    "shop",
    "setting",
    "gift",
    "trade",
    "coin",
    "gem",
    "wool",
    "block",
    "plank",
    "brick",
    "glass",
    "ladder",
    "wood ",
    "sand",
    "dirt",
    "obsidian",
    "potion",
    "food",
    "apple",
    "bed",
    "chest",
    "music",
    "sound",
    "menu",
    "close",
    "back",
    "shopkeeper",
}

local INVENTORY_WORDS: {string} = {
    "hotbar",
    "backpack",
    "inventory",
    "toolbar",
    "slots",
    "items",
}

local TOUCH_WORDS: {string} = {
    "mobile",
    "touch",
    "buttons",
    "controls",
}

local activeLibrary: WeaponLibrary? = nil

local function containsWord(text: string, words: {string}): boolean
    local lowered: string = string.lower(text)
    for _, word: string in ipairs(words) do
        if string.find(lowered, word, 1, true) then
            return true
        end
    end
    return false
end

local function isMeleeName(name: string): boolean
    if containsWord(name, NOT_WEAPON_WORDS)
        or containsWord(name, RANGED_WORDS)
        or containsWord(name, RIG_WORDS) then
        return false
    end
    return containsWord(name, MELEE_WORDS)
end

local function ancestryMatches(instance: Instance, words: {string}, depth: number): boolean
    local current: Instance? = instance
    local steps: number = 0
    while current and steps < depth do
        if containsWord(current.Name, words) then
            return true
        end
        current = current.Parent
        steps += 1
    end
    return false
end

function Module.init(context: any): WeaponLibrary
    local host: any = context
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    local menuGui: Instance? = host.ScreenGui

    local library: any = {

        cache = {},
        cachedAt = -1,
        cachedAll = false,
        cachedMelee = false,

        allowEquip = false,
    }

    function library:PressButton(button: GuiButton): boolean
        local environment: any = getfenv()
        local connectionsOf: any = environment.getconnections
        local fireSignal: any = environment.firesignal
        local pressed: boolean = false

        if type(connectionsOf) == "function" then
            for _, signal: any in
                ipairs({
                    button.MouseButton1Down,
                    button.MouseButton1Click,
                    (button :: any).Activated,
                    button.MouseButton1Up,
                })
            do
                local ok: boolean, connections: any = pcall(connectionsOf, signal)
                if not ok or type(connections) ~= "table" then
                    continue
                end
                for _, connection: any in ipairs(connections) do
                    local fired: boolean = pcall(function(): ()
                        connection:Fire()
                    end)
                    pressed = pressed or fired
                end
            end
        end
        if not pressed and type(fireSignal) == "function" then
            pressed = pcall(fireSignal, (button :: any).Activated) == true
        end
        return pressed
    end

    local function isMenuOwned(instance: Instance): boolean
        return menuGui ~= nil and instance:IsDescendantOf(menuGui :: Instance)
    end

    function library:Invalidate(): ()
        library.cachedAt = -1
    end

    function library:RegisterGameSource(source: any): ()
        library.gameSource = source
        library.cachedAt = -1
    end

    function library:SetAllowEquip(allowed: boolean): ()
        library.allowEquip = allowed == true
    end

    function library:Scan(query: any?): {Candidate}
        local options: any = query or {}
        local everything: boolean = options.All == true
        local now: number = os.clock()
        if now - library.cachedAt < 1
            and library.cachedAll == everything
            and library.cachedMelee == (options.Melee == true) then
            return library.cache
        end
        local found: {Candidate} = {}
        local seen: {[string]: boolean} = {}

        local meleeOnly: boolean = options.Melee == true
        local function add(kind: string, label: string, instance: Instance): ()
            local id: string = kind .. ":" .. label
            if seen[id] then
                return
            end
            local melee: boolean = isMeleeName(label)
            if meleeOnly and not melee then
                return
            end
            seen[id] = true
            table.insert(found, {
                id = id,
                label = label,
                kind = kind,
                melee = melee,
                instance = instance,
            })
        end

        if library.gameSource and type(library.gameSource.scan) == "function" then
            local ok: boolean, listed: any = pcall(library.gameSource.scan)
            if ok and type(listed) == "table" then
                for _, entry: any in ipairs(listed) do
                    if type(entry) == "table" and entry[1] and entry[2] then
                        add("Game", tostring(entry[1]), entry[2])
                    end
                end
            end
        end

        local character: Model? = localPlayer.Character
        if character then
            for _, child: Instance in ipairs(character:GetChildren()) do
                if child:IsA("Tool") then
                    add("Tool", child.Name, child)
                end
            end
        end
        local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
        if backpack then
            for _, child: Instance in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then
                    add("Tool", child.Name, child)
                end
            end
        end

        local viewRoots: {Instance} = {}
        local camera: Camera? = currentWorkspace.CurrentCamera
        if camera then
            table.insert(viewRoots, camera)
        end
        if character then
            table.insert(viewRoots, character)
        end
        for _, root: Instance in ipairs(viewRoots) do
            for _, child: Instance in ipairs(root:GetChildren()) do
                if not child:IsA("Model") then
                    continue
                end
                if containsWord(child.Name, WEAPON_WORDS)
                    and not containsWord(child.Name, NOT_WEAPON_WORDS) then
                    add("ViewModel", child.Name, child)
                end
                if string.find(string.lower(child.Name), "viewmodel", 1, true) then

                    for _, held: Instance in ipairs(child:GetChildren()) do
                        if not held:IsA("Model") and not held:IsA("BasePart") then
                            continue
                        end
                        if not isMeleeName(held.Name) then
                            continue
                        end
                        add("ViewModel", held.Name, held)
                    end
                end
            end
        end

        local playerGui: Instance? = localPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            for _, descendant: Instance in ipairs(playerGui:GetDescendants()) do
                if not descendant:IsA("GuiButton") then
                    continue
                end
                if isMenuOwned(descendant) then

                    continue
                end
                if containsWord(descendant.Name, NOT_WEAPON_WORDS) then
                    continue
                end
                local named: boolean = containsWord(descendant.Name, WEAPON_WORDS)
                if not named then

                    if not everything then
                        continue
                    end
                    if not ancestryMatches(descendant, TOUCH_WORDS, 4) then
                        continue
                    end
                    add("Button", descendant.Name, descendant)
                    continue
                end
                local inInventory: boolean =
                    ancestryMatches(descendant, INVENTORY_WORDS, 4)
                add(inInventory and "Slot" or "Button", descendant.Name, descendant)
            end
        end

        library.cache = found
        library.cachedAt = now
        library.cachedAll = everything
        library.cachedMelee = meleeOnly
        return found
    end

    function library:Labels(query: any?): {string}
        local labels: {string} = {}
        for _, candidate: Candidate in ipairs(library:Scan(query)) do
            table.insert(labels, candidate.label .. "  ·  " .. candidate.kind)
        end
        table.sort(labels)
        return labels
    end

    function library:IsMelee(name: string): boolean
        return isMeleeName(name)
    end

    function library:Find(label: string): Candidate?
        local wanted: string = string.lower(label)
        for _, candidate: Candidate in ipairs(library:Scan({All = true})) do
            if string.lower(candidate.label) == wanted then
                return candidate
            end
            if string.lower(candidate.label .. "  ·  " .. candidate.kind) == wanted then
                return candidate
            end
        end
        return nil
    end

    function library:Best(query: any?): Candidate?
        local found: {Candidate} = library:Scan(query or {All = false})

        local order: {string} = {"Game", "Tool", "Button", "Slot", "ViewModel"}
        local character: Model? = localPlayer.Character
        for _, kind: string in ipairs(order) do
            for _, candidate: Candidate in ipairs(found) do
                if candidate.kind ~= kind then
                    continue
                end
                if kind == "Tool"
                    and character
                    and candidate.instance.Parent ~= character
                    and not library.allowEquip then

                    continue
                end
                return candidate
            end
        end
        return found[1]
    end

    function library:Swing(): boolean

        local candidate: Candidate? = library:Best({Melee = true})
            or library:Best()
        if not candidate then
            return false
        end
        return library:Activate(candidate :: Candidate)
    end

    function library:Activate(candidate: Candidate, target: any?): boolean
        local instance: Instance = candidate.instance
        if candidate.kind == "Game" then

            if not library.gameSource or type(library.gameSource.press) ~= "function" then
                return false
            end
            local ok: boolean, pressed: any =
                pcall(library.gameSource.press, candidate.label, target)
            return ok and pressed == true
        end
        if not instance.Parent then
            return false
        end
        if candidate.kind == "Tool" then
            local tool: Tool = instance :: Tool

            if library.allowEquip and tool.Parent ~= localPlayer.Character then
                local humanoid: Humanoid? = localPlayer.Character
                    and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if humanoid then
                    pcall(function(): ()
                        (humanoid :: Humanoid):EquipTool(tool)
                    end)
                end
            end
            return pcall(function(): ()
                tool:Activate()
            end)
        end
        if candidate.kind == "Button" or candidate.kind == "Slot" then
            return library:PressButton(instance :: GuiButton)
        end
        if candidate.kind == "ViewModel" then

            for _, other: Candidate in ipairs(library:Scan({All = true})) do
                if other.kind == "Button" then
                    return library:PressButton(other.instance :: GuiButton)
                end
            end
            return false
        end
        return false
    end

    function library:Destroy(): ()
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = (library :: any) :: WeaponLibrary
    Module.Initialized = true
    return (library :: any) :: WeaponLibrary
end

function Module.destroy(): ()
    local library: WeaponLibrary? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
]],
        ["src/libraries/Render.lua"] = [[export type Rect = {
    left: number,
    right: number,
    top: number,
    bottom: number,
    width: number,
    height: number,
    centreX: number,
    centreY: number,
}

export type DrawingSet = {
    root: Frame,
    Line: (self: DrawingSet, group: string, index: number, from: Vector2, to: Vector2, thickness: number, colour: Color3) -> (),
    Box: (self: DrawingSet, rect: Rect, mode: string, thickness: number, colour: Color3) -> (),
    Fill: (self: DrawingSet, rect: Rect?, colour: Color3, transparency: number) -> (),
    Label: (self: DrawingSet, slot: string, text: string, at: Vector2, anchorY: number, size: number, colour: Color3, plate: boolean) -> (),
    HideLabel: (self: DrawingSet, slot: string) -> (),
    HideLines: (self: DrawingSet, group: string, first: number, last: number) -> (),
    Bar: (self: DrawingSet, at: Vector2, height: number, fraction: number) -> (),
    HideBar: (self: DrawingSet) -> (),
    Show: (self: DrawingSet, visible: boolean) -> (),
    Highlight: (self: DrawingSet, adornee: Instance?, colour: Color3, fill: number, mode: string) -> (),
    Destroy: (self: DrawingSet) -> (),
}

export type RenderLibrary = {
    Layer: (self: RenderLibrary, name: string) -> Frame,
    Set: (self: RenderLibrary, layer: Frame, key: any) -> DrawingSet,
    Release: (self: RenderLibrary, layer: Frame, key: any) -> (),
    ReleaseAll: (self: RenderLibrary, layer: Frame) -> (),
    Project: (self: RenderLibrary, camera: Camera, position: Vector3) -> Vector2?,
    ModelRect: (self: RenderLibrary, camera: Camera, model: Model) -> Rect?,
    Destroy: (self: RenderLibrary) -> (),
}

local Module = {
    Name = "Render",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: RenderLibrary? = nil

function Module.init(context: any): RenderLibrary
    local host: any = context
    local create: any = host.create
    local screenGui: Instance = host.ScreenGui

    local library: any = {}

    local pools: any = setmetatable({}, {__mode = "k"})

    function library:Layer(name: string): Frame
        local existing: Instance? = screenGui:FindFirstChild(name)
        if existing and existing:IsA("Frame") then
            return existing :: Frame
        end
        local layer: Frame = create("Frame", {
            Parent = screenGui,
            Name = name,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Visible = false,

            ZIndex = 0,
        }) :: Frame
        pools[layer] = {}
        return layer
    end

    local function newSet(layer: Frame, key: any): DrawingSet
        local root: Frame = create("Frame", {
            Parent = layer,
            Name = typeof(key) == "Instance" and (key :: Instance).Name or tostring(key),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 0,
        }) :: Frame

        local set: any = {
            root = root,
            lines = {} :: {[string]: {Frame}},
            labels = {} :: {[string]: TextLabel},
            fill = nil :: Frame?,
            highlight = nil :: Highlight?,
        }

        local function line(group: string, index: number): Frame
            local bucket: {Frame} = set.lines[group]
            if not bucket then
                bucket = {}
                set.lines[group] = bucket
            end
            local existing: Frame? = bucket[index]
            if existing then
                return existing :: Frame
            end
            local frame: Frame = create("Frame", {
                Parent = root,

                Name = group .. tostring(index),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BorderSizePixel = 0,
                Size = UDim2.fromOffset(0, 1),
                Visible = false,
                ZIndex = 1,
            }) :: Frame
            bucket[index] = frame
            return frame
        end

        function set:Line(
            group: string,
            index: number,
            from: Vector2,
            to: Vector2,
            thickness: number,
            colour: Color3
        ): ()
            local frame: Frame = line(group, index)
            local delta: Vector2 = to - from
            local length: number = delta.Magnitude
            if length < 0.5 then
                frame.Visible = false
                return
            end
            frame.Visible = true
            frame.BackgroundColor3 = colour
            frame.Position = UDim2.fromOffset(
                math.round((from.X + to.X) * 0.5),
                math.round((from.Y + to.Y) * 0.5)
            )
            frame.Size = UDim2.fromOffset(math.round(length), thickness)
            frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        end

        function set:HideLines(group: string, first: number, last: number): ()
            local bucket: {Frame}? = set.lines[group]
            if not bucket then
                return
            end
            for index: number = first, last do
                local frame: Frame? = (bucket :: {Frame})[index]
                if frame then
                    (frame :: Frame).Visible = false
                end
            end
        end

        function set:Box(
            rect: Rect,
            mode: string,
            thickness: number,
            colour: Color3
        ): ()
            if mode == "Off" then
                set:HideLines("Box", 1, 8)
                return
            end
            local corners: {Vector2} = {
                Vector2.new(rect.left, rect.top),
                Vector2.new(rect.right, rect.top),
                Vector2.new(rect.right, rect.bottom),
                Vector2.new(rect.left, rect.bottom),
            }
            if mode == "Full" then
                for index: number = 1, 4 do
                    set:Line(
                        "Box",
                        index,
                        corners[index],
                        corners[index % 4 + 1],
                        thickness,
                        colour
                    )
                end
                set:HideLines("Box", 5, 8)
                return
            end
            local segment: number =
                math.max(math.min(rect.width, rect.height) * 0.28, 3)
            local index: number = 1
            for corner: number = 1, 4 do
                local from: Vector2 = corners[corner]
                local nextCorner: Vector2 = corners[corner % 4 + 1]
                local previousCorner: Vector2 = corners[(corner + 2) % 4 + 1]
                set:Line(
                    "Box",
                    index,
                    from,
                    from + (nextCorner - from).Unit * segment,
                    thickness,
                    colour
                )
                set:Line(
                    "Box",
                    index + 1,
                    from,
                    from + (previousCorner - from).Unit * segment,
                    thickness,
                    colour
                )
                index += 2
            end
        end

        function set:Fill(rect: Rect?, colour: Color3, transparency: number): ()
            if not set.fill then
                set.fill = create("Frame", {
                    Parent = root,
                    Name = "BoxFill",
                    BackgroundColor3 = colour,
                    BackgroundTransparency = transparency,
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 0,
                }) :: Frame
            end
            local frame: Frame = set.fill :: Frame
            if not rect then
                frame.Visible = false
                return
            end
            local resolved: Rect = rect :: Rect
            frame.Visible = true
            frame.BackgroundColor3 = colour
            frame.BackgroundTransparency = transparency
            frame.Position =
                UDim2.fromOffset(math.round(resolved.left), math.round(resolved.top))
            frame.Size =
                UDim2.fromOffset(math.round(resolved.width), math.round(resolved.height))
        end

        function set:Label(
            slot: string,
            text: string,
            at: Vector2,
            anchorY: number,
            size: number,
            colour: Color3,
            plate: boolean
        ): ()
            local label: TextLabel? = set.labels[slot]
            if not label then
                label = create("TextLabel", {
                    Parent = root,
                    Name = slot,
                    AnchorPoint = Vector2.new(0.5, anchorY),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Color3.fromRGB(10, 10, 12),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Text = "",
                    TextColor3 = Color3.fromRGB(236, 236, 240),
                    TextSize = size,

                    TextTruncate = Enum.TextTruncate.None,
                    TextXAlignment = Enum.TextXAlignment.Center,
                    TextYAlignment = Enum.TextYAlignment.Center,
                    Visible = false,
                    ZIndex = 2,
                }) :: TextLabel
                create("UIPadding", {
                    Parent = label,
                    PaddingLeft = UDim.new(0, 5),
                    PaddingRight = UDim.new(0, 5),
                })
                create("UICorner", {Parent = label, CornerRadius = UDim.new(0, 3)})
                set.labels[slot] = label
            end
            local resolved: TextLabel = label :: TextLabel
            resolved.Visible = true
            resolved.Text = text
            resolved.TextColor3 = colour
            resolved.TextSize = size
            resolved.BackgroundTransparency = plate and 0.35 or 1
            resolved.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
            resolved.Size = UDim2.fromOffset(0, size + 6)
        end

        function set:HideLabel(slot: string): ()
            local label: TextLabel? = set.labels[slot]
            if label then
                (label :: TextLabel).Visible = false
            end
        end

        function set:Bar(at: Vector2, height: number, fraction: number): ()
            if not set.barTrack then
                set.barTrack = create("Frame", {
                    Parent = root,
                    Name = "HealthTrack",
                    AnchorPoint = Vector2.new(1, 0),
                    BackgroundColor3 = Color3.fromRGB(12, 12, 14),
                    BackgroundTransparency = 0.35,
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 1,
                }) :: Frame
                set.barFill = create("Frame", {
                    Parent = set.barTrack,
                    Name = "HealthFill",
                    AnchorPoint = Vector2.new(0, 1),
                    BackgroundColor3 = Color3.fromRGB(120, 220, 140),
                    BorderSizePixel = 0,
                    Position = UDim2.fromScale(0, 1),
                    Size = UDim2.fromScale(1, 1),
                    ZIndex = 2,
                }) :: Frame
            end
            local track: Frame = set.barTrack :: Frame
            local fill: Frame = set.barFill :: Frame
            local clamped: number = math.clamp(fraction, 0, 1)
            track.Visible = true
            track.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
            track.Size = UDim2.fromOffset(2, math.round(height))
            fill.Size = UDim2.fromScale(1, clamped)
            fill.BackgroundColor3 = Color3.fromRGB(
                math.round(255 * (1 - clamped)),
                math.round(200 * clamped + 40),
                math.round(120 * clamped)
            )
        end

        function set:HideBar(): ()
            if set.barTrack then
                (set.barTrack :: Frame).Visible = false
            end
        end

        function set:Show(visible: boolean): ()
            root.Visible = visible
            if set.highlight then
                (set.highlight :: Highlight).Enabled = visible
            end
        end

        function set:Highlight(
            adornee: Instance?,
            colour: Color3,
            fill: number,
            mode: string
        ): ()
            if not adornee or mode == "Off" then
                if set.highlight then
                    (set.highlight :: Highlight):Destroy()
                    set.highlight = nil
                end
                return
            end
            local highlight: Highlight? = set.highlight
            if not highlight or not (highlight :: Highlight).Parent then
                highlight = create("Highlight", {
                    Parent = adornee,
                    Name = "Wurst_Chams",
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                }) :: Highlight
                set.highlight = highlight
            end
            local resolved: Highlight = highlight :: Highlight
            resolved.Adornee = adornee
            resolved.Parent = adornee
            resolved.Enabled = root.Visible
            resolved.DepthMode = mode == "Occluded"
                    and Enum.HighlightDepthMode.Occluded
                or Enum.HighlightDepthMode.AlwaysOnTop
            resolved.FillColor = colour
            resolved.OutlineColor = colour
            resolved.FillTransparency = mode == "Outline" and 1 or fill
            resolved.OutlineTransparency = 0
        end

        function set:Destroy(): ()
            if set.highlight then
                pcall(function(): ()
                    (set.highlight :: Highlight):Destroy()
                end)
            end
            pcall(function(): ()
                root:Destroy()
            end)
        end

        return (set :: any) :: DrawingSet
    end

    function library:Set(layer: Frame, key: any): DrawingSet
        local pool: any = pools[layer]
        if not pool then
            pool = {}
            pools[layer] = pool
        end
        local existing: any = pool[key]
        if existing then
            return existing
        end
        local set: DrawingSet = newSet(layer, key)
        pool[key] = set
        return set
    end

    function library:Release(layer: Frame, key: any): ()
        local pool: any = pools[layer]
        local set: any = pool and pool[key]
        if not set then
            return
        end
        pool[key] = nil
        set:Destroy()
    end

    function library:ReleaseAll(layer: Frame): ()
        local pool: any = pools[layer]
        if not pool then
            return
        end
        for key: any, set: any in pairs(pool) do
            pool[key] = nil
            set:Destroy()
        end
    end

    function library:Project(camera: Camera, position: Vector3): Vector2?
        -- The host ScreenGui ignores the GUI inset, so drawings live in raw
        -- screen space and WorldToScreenPoint is the matching projection.
        -- Points merely outside the viewport still project so skeleton lines
        -- keep their bearings at the screen edge; only points behind the
        -- camera are rejected.
        local point: Vector3 = camera:WorldToScreenPoint(position)
        if point.Z <= 0 then
            return nil
        end
        return Vector2.new(point.X, point.Y)
    end

    -- Builds a screen rectangle from world sample points. Points behind the
    -- camera are dropped, the rest contribute to the bounds, and the final
    -- rectangle is clamped to the viewport so a target that is merely close
    -- can never produce a box larger than the screen. Models that are fully
    -- off-screen return nil so callers can hide their drawings cleanly.
    local function rectFromPoints(
        camera: Camera,
        viewport: Vector2,
        points: {Vector3},
        minimumAspect: number?
    ): Rect?
        local minimumX: number, minimumY: number = math.huge, math.huge
        local maximumX: number, maximumY: number = -math.huge, -math.huge
        local inFront: number = 0
        for _, position: Vector3 in ipairs(points) do
            local point: Vector3 = camera:WorldToScreenPoint(position)
            if point.Z > 0 then
                inFront += 1
                if point.X < minimumX then minimumX = point.X end
                if point.Y < minimumY then minimumY = point.Y end
                if point.X > maximumX then maximumX = point.X end
                if point.Y > maximumY then maximumY = point.Y end
            end
        end
        if inFront < 2 then
            return nil
        end
        minimumX -= 2
        maximumX += 2
        minimumY -= 2
        maximumY += 2
        local width: number = maximumX - minimumX
        local height: number = maximumY - minimumY
        if minimumAspect and height > 0 and height * minimumAspect > width then
            width = height * minimumAspect
            local centreX: number = (minimumX + maximumX) * 0.5
            minimumX = centreX - width * 0.5
            maximumX = centreX + width * 0.5
        end
        if maximumX < 0 or minimumX > viewport.X
            or maximumY < 0 or minimumY > viewport.Y then
            return nil
        end
        local left: number = math.max(minimumX, 0)
        local right: number = math.min(maximumX, viewport.X)
        local top: number = math.max(minimumY, 0)
        local bottom: number = math.min(maximumY, viewport.Y)
        if right - left < 1 or bottom - top < 1 then
            return nil
        end
        return {
            left = left,
            right = right,
            top = top,
            bottom = bottom,
            width = right - left,
            height = bottom - top,
            centreX = (left + right) * 0.5,
            centreY = (top + bottom) * 0.5,
        }
    end

    function library:ModelRect(camera: Camera, model: Model): Rect?
        if not model.Parent then
            return nil
        end
        local viewport: Vector2 = camera.ViewportSize
        local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? = model:FindFirstChild("HumanoidRootPart") :: BasePart?
            or model.PrimaryPart
        if humanoid and root then
            -- Character rig: measure a handful of body landmarks instead of
            -- walking every part. The head and feet anchor the height, the
            -- four torso landmarks anchor the width at any rotation, and any
            -- landmark that falls behind the camera is simply dropped so the
            -- box degrades gracefully instead of flipping or vanishing.
            local head: BasePart? = model:FindFirstChild("Head") :: BasePart?
            local rootPosition: Vector3 = root.Position
            local topPosition: Vector3 = head
                and (head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.35, 0))
                or (rootPosition + Vector3.new(0, 3, 0))
            local bottomPosition: Vector3 = rootPosition
                - Vector3.new(0, math.max(humanoid.HipHeight + root.Size.Y * 0.5, 2.5), 0)
            local rootCFrame: CFrame = root.CFrame
            return rectFromPoints(camera, viewport, {
                topPosition,
                bottomPosition,
                rootPosition,
                rootCFrame * Vector3.new(1.35, 0, 0),
                rootCFrame * Vector3.new(-1.35, 0, 0),
                rootCFrame * Vector3.new(0, 0, 0.75),
                rootCFrame * Vector3.new(0, 0, -0.75),
            }, 0.38)
        end

        -- Anything without a live humanoid rig: take the engine-side bounding
        -- box and project its eight corners. One engine call and eight
        -- projections, instead of walking and projecting every descendant
        -- part each frame.
        local boundsOk: boolean, boundsCFrame: any, boundsSize: any =
            pcall(model.GetBoundingBox, model)
        if not boundsOk or typeof(boundsSize) ~= "Vector3" or boundsSize.Magnitude <= 0 then
            return nil
        end
        local half: Vector3 = boundsSize * 0.5
        return rectFromPoints(camera, viewport, {
            boundsCFrame * Vector3.new(half.X, half.Y, half.Z),
            boundsCFrame * Vector3.new(-half.X, half.Y, half.Z),
            boundsCFrame * Vector3.new(half.X, -half.Y, half.Z),
            boundsCFrame * Vector3.new(-half.X, -half.Y, half.Z),
            boundsCFrame * Vector3.new(half.X, half.Y, -half.Z),
            boundsCFrame * Vector3.new(-half.X, half.Y, -half.Z),
            boundsCFrame * Vector3.new(half.X, -half.Y, -half.Z),
            boundsCFrame * Vector3.new(-half.X, -half.Y, -half.Z),
        })
    end

    function library:Destroy(): ()
        for layer: any, pool: any in pairs(pools) do
            for key: any, set: any in pairs(pool) do
                pool[key] = nil
                pcall(function(): ()
                    set:Destroy()
                end)
            end
            pcall(function(): ()
                (layer :: Frame):Destroy()
            end)
        end
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = (library :: any) :: RenderLibrary
    Module.Initialized = true
    return (library :: any) :: RenderLibrary
end

function Module.destroy(): ()
    local library: RenderLibrary? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
]],
        ["src/guis/Wurst/Code/Cards.lua"] = [[local Module = {
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
    local flushConfigSave: any = host.flushConfigSave or queueConfigSave
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
                flushConfigSave()
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
]],
        ["src/guis/Wurst/Code/WindowManager.lua"] = [[export type WindowDefinition = {
    id: string,
    title: string?,
    size: Vector2,
    position: Vector2,

    chromeless: boolean?,
    closable: boolean?,
    collapsible: boolean?,
    pinnable: boolean?,
    maxHeight: number?,
    onClose: (() -> ())?,
}

export type Window = {
    id: string,
    root: Frame,
    body: Frame,
    header: Frame?,
    closeButton: TextButton?,
    collapsed: boolean,
    pinned: boolean,
    SetVisible: (self: Window, visible: boolean) -> (),
    SetCollapsed: (self: Window, collapsed: boolean) -> (),
    SetPinned: (self: Window, pinned: boolean) -> (),
    Raise: (self: Window) -> (),
    Destroy: (self: Window) -> (),
}

local Module = {
    Name = "WindowManager",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local SNAP_DISTANCE: number = 8

local BASE_Z: number = 150
local MARGIN: number = 6

local PLACEMENT_GAP: number = 10

local TITLE_HEIGHT: number = 26

local TITLE_FONT_SIZE: number = 16

function Module.init(context: any): any
    local host: any = context
    local state: any = host.state
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local create: any = host.create
    local Theme: any = host.Theme
    local ThemeEngine: any = host.ThemeEngine
    local CONTROL_FONT: any = host.CONTROL_FONT
    local PopupLayer: any = host.PopupLayer
    local trackUiConnection: any = host.trackUiConnection
    local UserInputService: any = host.UserInputService

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

    configData.ui = configData.ui or {}
    configData.ui.windows = configData.ui.windows or {}

    local manager: any = {
        list = {} :: {any},
        byId = {} :: {[string]: any},
    }

    local function screenViewport(): Vector2
        local camera: Camera? = workspace.CurrentCamera
        if camera then
            return (camera :: Camera).ViewportSize
        end
        return Vector2.new(1280, 720)
    end

    local function layerScale(): number
        local instance: any = PopupLayer
            and (PopupLayer :: Instance):FindFirstChild("ClickGuiScale")
        local value: number = instance and tonumber(instance.Scale) or 1
        if value ~= value or value <= 0 then
            value = 1
        end
        return value
    end

    local function logicalViewport(): Vector2
        local screen: Vector2 = screenViewport()
        local factor: number = layerScale()
        return Vector2.new(screen.X / factor, screen.Y / factor)
    end

    local function screenToLogical(point: Vector2): Vector2
        local factor: number = layerScale()
        return Vector2.new(point.X / factor, point.Y / factor)
    end

    local function logicalToScreen(point: Vector2): Vector2
        local factor: number = layerScale()
        return Vector2.new(point.X * factor, point.Y * factor)
    end

    local function windowRect(window: any): (number, number, number, number)
        local root: any = window.root
        return root.Position.X.Offset, root.Position.Y.Offset,
            root.Size.X.Offset, root.Size.Y.Offset
    end

    local function snapPixel(value: number): number
        local factor: number = layerScale()
        return math.round(value * factor) / factor
    end

    local function clamp(position: Vector2, size: Vector2): Vector2
        local screen: Vector2 = logicalViewport()
        return Vector2.new(
            snapPixel(math.clamp(position.X, MARGIN, math.max(MARGIN, screen.X - size.X - MARGIN))),
            snapPixel(math.clamp(position.Y, MARGIN, math.max(MARGIN, screen.Y - size.Y - MARGIN)))
        )
    end

    function manager.ClampWindow(window: any): ()
        local root: any = window and window.root
        if not root then
            return
        end
        local landed: Vector2 = clamp(
            Vector2.new(root.Position.X.Offset, root.Position.Y.Offset),
            Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
        )
        root.Position = UDim2.fromOffset(landed.X, landed.Y)
    end

    function manager.MeasureWindow(window: any): Vector2
        local root: any = window and window.root
        if not root then
            return Vector2.zero
        end
        local width: number = root.Size.X.Offset
        local height: number
        if window.collapsed then
            height = window.headerHeight or root.Size.Y.Offset
        else
            height = math.max(root.Size.Y.Offset, tonumber(window.fullHeight) or 0)
        end
        return Vector2.new(width, height)
    end

    function manager.AbsoluteRect(window: any): (number, number, number, number)
        local x: number, y: number, w: number, h: number = windowRect(window)
        local origin: Vector2 = logicalToScreen(Vector2.new(x, y))
        local extent: Vector2 = logicalToScreen(Vector2.new(w, h))
        return origin.X, origin.Y, extent.X, extent.Y
    end

    manager.LogicalViewport = logicalViewport
    manager.ScreenToLogical = screenToLogical
    manager.LogicalToScreen = logicalToScreen

    local function bind(instance: Instance, property: string, token: string): ()
        if ThemeEngine and type(ThemeEngine.Bind) == "function" then
            ThemeEngine.Bind(instance, property, token)
        else
            (instance :: any)[property] = Theme[token]
        end
    end

    local function persist(window: any): ()
        configData.ui.windows[window.id] = {
            x = window.root.Position.X.Offset,
            y = window.root.Position.Y.Offset,
            collapsed = window.collapsed,
            pinned = window.pinned,
        }
        queueConfigSave()
    end

    local function snap(window: any, position: Vector2, size: Vector2): Vector2
        local screen: Vector2 = logicalViewport()
        local xLines: {number} = {MARGIN, screen.X - size.X - MARGIN}
        local yLines: {number} = {MARGIN, screen.Y - size.Y - MARGIN}
        for _, other: any in ipairs(manager.list) do
            if other ~= window and other.root.Visible then
                local otherX: number, otherY: number, otherW: number, otherH: number =
                    windowRect(other)
                table.insert(xLines, otherX)
                table.insert(xLines, otherX + otherW)
                table.insert(xLines, otherX - size.X)
                table.insert(yLines, otherY)
                table.insert(yLines, otherY + otherH)
                table.insert(yLines, otherY - size.Y)
            end
        end
        local x: number, y: number = position.X, position.Y
        for _, line: number in ipairs(xLines) do
            if math.abs(x - line) <= SNAP_DISTANCE then
                x = line
                break
            end
        end
        for _, line: number in ipairs(yLines) do
            if math.abs(y - line) <= SNAP_DISTANCE then
                y = line
                break
            end
        end
        return Vector2.new(snapPixel(x), snapPixel(y))
    end

    local function raise(window: any): ()
        local index: number? = table.find(manager.list, window)
        if index then
            table.remove(manager.list, index)
        end
        table.insert(manager.list, window)
        for order: number, entry: any in ipairs(manager.list) do

            local base: number = math.min(BASE_Z + order, 239)
            entry.root.ZIndex = base

            if entry.layered then
                for _, descendant: Instance in ipairs(entry.root:GetDescendants()) do
                    if descendant:IsA("GuiObject") then
                        local relative: number =
                            tonumber(descendant:GetAttribute("FloatingDepth")) or 1
                        descendant.ZIndex = base + relative
                    end
                end
            end
        end
    end

    function manager.Raise(id: string): ()
        local window: any = manager.byId[id]
        if window then
            raise(window)
        end
    end

    function manager.Adopt(root: Frame, definition: any): any
        local id: string = definition.id
        local saved: any = configData.ui.windows[id]
        if type(saved) ~= "table" then

            local legacy: any = (configData.ui.floatingPositions or {})[id]
            if type(legacy) == "table" then
                saved = {x = tonumber(legacy[1]), y = tonumber(legacy[2])}
            end
        end

        local window: any = {
            id = id,
            root = root,
            body = definition.body,
            header = definition.header,
            closeButton = definition.closeButton,
            collapsed = type(saved) == "table" and saved.collapsed == true,
            pinned = type(saved) == "table" and saved.pinned == true,
            fullHeight = root.Size.Y.Offset,
            headerHeight = definition.headerHeight or 0,
            layered = definition.layered == true,

            connections = {} :: {RBXScriptConnection},
        }

        local function own(connection: RBXScriptConnection): RBXScriptConnection
            table.insert(window.connections, connection)
            trackUiConnection(connection)
            return connection
        end

        if type(saved) == "table" and saved.x and saved.y then

            local savedX: number? = tonumber(saved.x)
            local savedY: number? = tonumber(saved.y)
            if savedX and savedY then
                local landed: Vector2 = clamp(
                    Vector2.new(savedX, savedY),
                    Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
                )
                root.Position = UDim2.fromOffset(landed.X, landed.Y)

                window.userMoved = true
            end
        end

        function window:SetVisible(visible: boolean): ()
            root.Visible = visible
            if visible then
                raise(window)
            end
        end

        function window:SetCollapsed(collapsed: boolean): ()
            window.collapsed = collapsed
            if window.body then
                (window.body :: any).Visible = not collapsed
            end

            root.Size = collapsed
                and UDim2.fromOffset(root.Size.X.Offset, window.headerHeight)
                or UDim2.fromOffset(root.Size.X.Offset, window.fullHeight)
            persist(window)
        end

        function window:SetPinned(pinned: boolean): ()
            window.pinned = pinned

            if not pinned and state.visible ~= true then
                root.Visible = false
            end
            persist(window)
        end

        function window:Raise(): ()
            raise(window)
        end

        function window:Destroy(): ()
            if state.surfaceDragOwner == root then
                state.surfaceDragOwner = nil
            end
            local index: number? = table.find(manager.list, window)
            if index then
                table.remove(manager.list, index)
            end
            manager.byId[id] = nil
            for _, connection: RBXScriptConnection in ipairs(window.connections) do
                pcall(function(): ()
                    connection:Disconnect()
                end)
            end
            window.connections = {}
            root:Destroy()
        end

        local dragHandle: GuiObject = definition.dragHandle or root
        local requiresMenuOpen: boolean = definition.requiresMenuOpen == true
        local dragging: boolean = false
        local dragInput: InputObject? = nil
        local dragStart: Vector2 = Vector2.zero
        local startPosition: Vector2 = Vector2.new(
            root.Position.X.Offset,
            root.Position.Y.Offset
        )

        own(root.InputBegan:Connect(function(): ()
            raise(window)
        end))
        own(dragHandle.InputBegan:Connect(function(
            input: InputObject
        ): ()
            if requiresMenuOpen and not state.visible then
                return
            end
            local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
            if state.surfaceDragHitTest
                and state.surfaceDragHitTest(pointer) then
                return
            end
            if state.surfaceDragOwner ~= nil
                and state.surfaceDragOwner ~= root then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            local absoluteSize: Vector2 = dragHandle.AbsoluteSize
            if absoluteSize.X > 0 and absoluteSize.Y > 0 then
                local absolutePosition: Vector2 = dragHandle.AbsolutePosition
                if input.Position.X < absolutePosition.X
                    or input.Position.X > absolutePosition.X + absoluteSize.X
                    or input.Position.Y < absolutePosition.Y
                    or input.Position.Y > absolutePosition.Y + absoluteSize.Y then
                    return
                end
            end
            dragging = true
            dragInput = input
            state.surfaceDragOwner = root
            dragStart = Vector2.new(input.Position.X, input.Position.Y)
            startPosition = Vector2.new(
                root.Position.X.Offset,
                root.Position.Y.Offset
            )
            raise(window)
        end))
        own(UserInputService.InputChanged:Connect(function(
            input: InputObject
        ): ()
            if not dragging then
                return
            end
            if input == dragInput
                or (dragInput
                    and dragInput.UserInputType == Enum.UserInputType.MouseButton1
                    and input.UserInputType == Enum.UserInputType.MouseMovement) then

                local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
                local delta: Vector2 = screenToLogical(pointer - dragStart)
                local size: Vector2 = Vector2.new(
                    root.Size.X.Offset,
                    root.Size.Y.Offset
                )
                local wanted: Vector2 = startPosition + delta
                local landed: Vector2 = snap(window, clamp(wanted, size), size)
                root.Position = UDim2.fromOffset(landed.X, landed.Y)
            end
        end))
        own(UserInputService.InputEnded:Connect(function(
            input: InputObject
        ): ()
            if dragging
                and (input == dragInput
                    or input.UserInputType == Enum.UserInputType.MouseButton1) then
                dragging = false
                dragInput = nil
                if state.surfaceDragOwner == root then
                    state.surfaceDragOwner = nil
                end

                window.userMoved = true
                persist(window)
            end
        end))
        if window.closeButton then
            own(
                (window.closeButton :: TextButton).MouseButton1Click:Connect(function(): ()
                    root.Visible = false
                    if definition.onClose then
                        definition.onClose()
                    end
                end)
            )
        end

        manager.byId[id] = window
        raise(window)
        return window
    end

    function manager.Create(definition: WindowDefinition): any
        local id: string = definition.id
        local bare: boolean = definition.chromeless == true
        local headerHeight: number = bare and 0 or TITLE_HEIGHT
        local saved: any = configData.ui.windows[id]

        local position: Vector2 = definition.position
        if type(saved) == "table" then
            position = Vector2.new(
                tonumber(saved.x) or position.X,
                tonumber(saved.y) or position.Y
            )
        end
        position = clamp(position, definition.size)

        local root: Frame = create("Frame", {
            Parent = PopupLayer,
            Name = "Window_" .. id,
            Active = true,
            BackgroundTransparency = bare and 1 or manager.bodyTransparency,
            BorderSizePixel = 0,
            ClipsDescendants = not bare,
            Position = UDim2.fromOffset(position.X, position.Y),
            Size = UDim2.fromOffset(definition.size.X, definition.size.Y),
            Visible = false,
            ZIndex = BASE_Z,
        }) :: Frame
        bind(root, "BackgroundColor3", "background")

        local window: any = nil
        local paintChrome: {() -> ()} = {}

        local chromeConnections: {RBXScriptConnection} = {}
        local header: Frame? = nil
        local closeButton: TextButton? = nil

        if not bare then

            local edge: UIStroke = (create("UIStroke", {
                Parent = root,
                Name = "WindowOutline",
                Color = Theme.outline,
                Transparency = 0.08,
                Thickness = 1,
            }) :: any) :: UIStroke
            bind(edge, "Color", "outline")

            local bar: Frame = create("Frame", {
                Parent = root,
                Name = "Header",
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, headerHeight),
                ZIndex = 2,
            }) :: Frame
            bind(bar, "BackgroundColor3", "accent")

            local bitmapText: any = state.bitmapText
            if bitmapText and type(bitmapText.draw) == "function" then
                local function paintTitle(): ()
                    if root.Parent == nil then
                        return
                    end

                    bitmapText.draw(bar, {
                        {text = definition.title or id, color = Theme.accentText},
                    }, {
                        Name = "Title",
                        TextSize = TITLE_FONT_SIZE,
                        ZIndex = 3,
                        AnchorPoint = Vector2.new(0, 0.5),
                        Position = UDim2.new(0, 8, 0.5, 0),
                        maxWidth = math.max(40, root.Size.X.Offset - 68),
                    })
                end
                paintTitle()
                if ThemeEngine and type(ThemeEngine.OnChange) == "function" then
                    ThemeEngine.OnChange(paintTitle)
                end

                pcall(function(): ()
                    table.insert(
                        chromeConnections,
                        root:GetPropertyChangedSignal("Size"):Connect(paintTitle)
                    )
                end)
            else
                local title: TextLabel = (create("TextLabel", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = bar,
                    Name = "Title",
                    BackgroundTransparency = 1,
                    FontFace = CONTROL_FONT,
                    Text = definition.title or id,
                    TextSize = TITLE_FONT_SIZE,
                }) :: any) :: TextLabel
                title.AnchorPoint = Vector2.new(0, 0.5)
                title.Position = UDim2.new(0, 8, 0.5, 0)
                title.Size = UDim2.new(1, -60, 1, 0)
                title.TextXAlignment = Enum.TextXAlignment.Left
                title.ZIndex = 3
                bind(title, "TextColor3", "accentText")
            end

            local buttonX: number = -5

            local function chromeButton(kind: string, paint: Color3): TextButton
                local button: TextButton = (create("TextButton", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = bar,
                    Active = true,
                    AutoButtonColor = false,
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                    BackgroundTransparency = 0.72,
                    BorderSizePixel = 0,
                    FontFace = CONTROL_FONT,
                    Text = "",
                    TextSize = 11,
                }) :: any) :: TextButton
                create("UIStroke", {
                    Parent = button,
                    Color = Color3.fromRGB(0, 0, 0),
                    Thickness = 1,
                    Transparency = 0.55,
                })
                button.AnchorPoint = Vector2.new(1, 0.5)
                button.Position = UDim2.new(1, buttonX, 0.5, 0)
                button.Size = UDim2.fromOffset(22, 22)
                button.ZIndex = 3
                drawPixelIcon(button, kind, paint)

                table.insert(chromeConnections, button.MouseEnter:Connect(function(): ()
                    button.BackgroundTransparency = 0.45
                end))
                table.insert(chromeConnections, button.MouseLeave:Connect(function(): ()
                    button.BackgroundTransparency = 0.72
                end))
                buttonX -= 25
                return button
            end

            if definition.closable ~= false then
                closeButton = chromeButton("cross", Color3.fromRGB(204, 0, 0))
            end
            if definition.pinnable ~= false then

                local pin: TextButton = chromeButton("pin", Color3.fromRGB(0, 204, 0))
                local function paintPin(): ()
                    pin.BackgroundTransparency = window.pinned and 0.2 or 0.72
                    pin.BackgroundColor3 = window.pinned
                        and Color3.fromRGB(0, 80, 0)
                        or Color3.fromRGB(0, 0, 0)
                end
                table.insert(paintChrome, paintPin)
                table.insert(chromeConnections, pin.MouseButton1Click:Connect(function(): ()
                    window:SetPinned(not window.pinned)
                    paintPin()
                end))
            end
            if definition.collapsible ~= false then

                local chevron: TextButton = chromeButton("up", Color3.fromRGB(170, 32, 32))
                local function paintChevron(): ()
                    drawPixelIcon(
                        chevron,
                        window.collapsed and "down" or "up",
                        Color3.fromRGB(170, 32, 32)
                    )
                end
                table.insert(chromeConnections, chevron.MouseButton1Click:Connect(function(): ()
                    window:SetCollapsed(not window.collapsed)
                    paintChevron()
                end))
                table.insert(paintChrome, paintChevron)
            end
            header = bar
        end

        local body: ScrollingFrame = create("ScrollingFrame", {
            Parent = root,
            Name = "Body",
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            Position = UDim2.fromOffset(0, headerHeight),
            ScrollBarThickness = 3,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Size = UDim2.new(1, 0, 1, -headerHeight),
            ZIndex = 2,
        }) :: ScrollingFrame
        bind(body, "ScrollBarImageColor3", "accentDim")

        local adopted: any = manager.Adopt(root, {
            id = id,
            body = body,
            header = header,
            closeButton = closeButton,
            headerHeight = headerHeight,
            dragHandle = bare and root or header,
            requiresMenuOpen = bare,
            onClose = definition.onClose,
        })
        adopted.fullHeight = definition.size.Y
        for _, connection: RBXScriptConnection in ipairs(chromeConnections) do
            table.insert(adopted.connections, connection)
            trackUiConnection(connection)
        end
        window = adopted
        for _, paint: () -> () in ipairs(paintChrome) do
            paint()
        end

        if window.collapsed then
            window:SetCollapsed(true)
        end

        manager.byId[id] = window
        raise(window)
        return window
    end

    function manager.Get(id: string): any
        return manager.byId[id]
    end

    function manager.SetMenuVisible(visible: boolean): ()
        for _, window: any in ipairs(manager.list) do
            if not visible and window.pinned then
                continue
            end
            window.root.Visible = visible and window.wasVisible == true
            if visible == false then
                window.wasVisible = window.root.Visible
            end
        end
    end

    local function intersects(
        ax: number, ay: number, aw: number, ah: number,
        bx: number, by: number, bw: number, bh: number
    ): boolean
        return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
    end

    local function obstacleRects(excludeWindow: any): {{number}}
        local rects: {{number}} = {}
        for _, other: any in ipairs(manager.list) do
            local root: any = other.root
            if other ~= excludeWindow and root and root.Visible ~= false then
                local size: Vector2 = manager.MeasureWindow(other)
                table.insert(rects, {
                    root.Position.X.Offset,
                    root.Position.Y.Offset,
                    size.X,
                    size.Y,
                })
            end
        end
        return rects
    end

    local function rectIsFree(
        x: number, y: number, width: number, height: number,
        obstacles: {{number}}
    ): boolean
        local screen: Vector2 = logicalViewport()
        if x < MARGIN or y < MARGIN
            or x + width > screen.X - MARGIN
            or y + height > screen.Y - MARGIN then
            return false
        end
        for _, rect: {number} in ipairs(obstacles) do
            if intersects(
                x, y, width, height,
                rect[1] - PLACEMENT_GAP, rect[2] - PLACEMENT_GAP,
                rect[3] + PLACEMENT_GAP * 2, rect[4] + PLACEMENT_GAP * 2
            ) then
                return false
            end
        end
        return true
    end

    local function anchorRect(preferredAnchor: any): {number}?
        if type(preferredAnchor) ~= "table" then
            return nil
        end
        local root: any = preferredAnchor.root
        if root then
            if root.Parent == nil then
                return nil
            end
            local size: Vector2 = manager.MeasureWindow(preferredAnchor)
            return {root.Position.X.Offset, root.Position.Y.Offset, size.X, size.Y}
        end
        local x: number? = tonumber(preferredAnchor.x)
        local y: number? = tonumber(preferredAnchor.y)
        if x and y then
            return {
                x, y,
                tonumber(preferredAnchor.width) or 0,
                tonumber(preferredAnchor.height) or 0,
            }
        end
        return nil
    end

    function manager.FindFreeRect(
        desiredSize: Vector2,
        preferredAnchor: any?,
        excludeWindow: any?
    ): Vector2
        local width: number = desiredSize.X
        local height: number = desiredSize.Y
        local obstacles: {{number}} = obstacleRects(excludeWindow)
        local screen: Vector2 = logicalViewport()

        local function fitY(y: number): number
            return math.max(MARGIN, math.min(y, screen.Y - height - MARGIN))
        end

        local anchor: {number}? = anchorRect(preferredAnchor)
        if anchor then
            local candidates: {{number}} = {
                {anchor[1] + anchor[3] + PLACEMENT_GAP, fitY(anchor[2])},
                {anchor[1] - width - PLACEMENT_GAP, fitY(anchor[2])},
                {anchor[1], anchor[2] + anchor[4] + PLACEMENT_GAP},
            }
            for _, candidate: {number} in ipairs(candidates) do
                if rectIsFree(candidate[1], candidate[2], width, height, obstacles) then
                    return Vector2.new(candidate[1], candidate[2])
                end
            end
        end

        local step: number = 40
        local yLimit: number = math.max(64, screen.Y - height - MARGIN)
        local xLimit: number = math.max(MARGIN, screen.X - width - MARGIN)
        local y: number = 64
        while y <= yLimit do
            local x: number = MARGIN
            while x <= xLimit do
                if rectIsFree(x, y, width, height, obstacles) then
                    return Vector2.new(x, y)
                end
                x += step
            end
            y += step
        end
        return clamp(Vector2.new(MARGIN, 64), desiredSize)
    end

    function manager.PlaceWindow(window: any, options: any?): ()
        if not window or not window.root then
            return
        end
        local opts: any = options or {}
        if opts.anchor ~= nil then
            window.placementAnchor = opts.anchor
        end
        if window.userMoved and opts.force ~= true then
            manager.ClampWindow(window)
            return
        end
        local size: Vector2 = manager.MeasureWindow(window)
        local landed: Vector2 = manager.FindFreeRect(
            size,
            window.placementAnchor,
            window
        )
        window.root.Position = UDim2.fromOffset(landed.X, landed.Y)
        manager.ClampWindow(window)
    end

    function manager.ReflowWindow(window: any): ()
        if not window or not window.root then
            return
        end
        if window.userMoved then
            manager.ClampWindow(window)
            return
        end
        local size: Vector2 = manager.MeasureWindow(window)
        local x: number = window.root.Position.X.Offset
        local y: number = window.root.Position.Y.Offset
        if rectIsFree(x, y, size.X, size.Y, obstacleRects(window)) then
            return
        end
        local landed: Vector2 = manager.FindFreeRect(
            size,
            window.placementAnchor,
            window
        )
        window.root.Position = UDim2.fromOffset(landed.X, landed.Y)
        manager.ClampWindow(window)
    end

    local function categoryAnchor(feature: any): any
        local row: any = feature and feature.row
        local rowRoot: any = row and row.Parent and (row.Parent :: any).Parent
        if rowRoot then
            for _, entry: any in ipairs(manager.list) do
                if entry.root == rowRoot then
                    return entry
                end
            end
        end
        local gui: any = state.clickGui
        if row and gui and type(gui.categories) == "table"
            and type(row.GetAttribute) == "function" then
            local raw: any = row:GetAttribute("FeatureCategory")
            local name: any = raw
            if type(host.normalizeFeatureCategory) == "function" then
                name = host.normalizeFeatureCategory(raw)
            end
            local record: any = name and gui.categories[name]
            if record and record.window then
                return record.window
            end
        end
        return nil
    end

    function manager.OpenFeatureSettings(feature: any): any
        if type(feature) ~= "table" or feature.row == nil then
            return nil
        end
        local id: string = "FeatureSettings_"
            .. tostring(feature.configKey or feature.name):gsub("%W", "")
        local existing: any = manager.byId[id]
        if existing then
            existing.root.Visible = true

            if existing.stalePlacement then
                existing.stalePlacement = nil
                manager.PlaceWindow(existing, {force = true})
            end
            feature.expanded = true
            if feature.syncArrow then
                feature.syncArrow()
            end
            raise(existing)
            return existing
        end

        local bitmapText: any = state.bitmapText
        local width: number = 200
        for _, optionRow: any in ipairs(feature.optionRows or {}) do
            local label: any = optionRow:FindFirstChild("OptionLabel")
            local text: string = label and tostring(label.Text) or ""
            local labelWidth: number
            if bitmapText and type(bitmapText.measure) == "function" then
                labelWidth = bitmapText.measure({{text = text}}, 16)
            else
                labelWidth = #text * 12
            end
            width = math.max(width, 8 + labelWidth + 24 + 72)
        end
        width = math.min(width, 420)

        local expectedLimit: number = tonumber(state.uiMaxSettingsHeight) or 200
        if expectedLimit <= 0 then
            expectedLimit = 600
        end
        local expectedHeight: number = math.min(
            TITLE_HEIGHT + (feature.optionsHeight or 40),
            expectedLimit
        )
        local anchor: any = categoryAnchor(feature)
        local slot: Vector2 = manager.FindFreeRect(
            Vector2.new(width, expectedHeight),
            anchor
        )

        local window: any = manager.Create({
            id = id,
            title = tostring(feature.name) .. " Settings",
            size = Vector2.new(width, TITLE_HEIGHT + 40),
            position = slot,
            closable = true,

            collapsible = false,
            onClose = function(): ()
                feature.expanded = false
                if feature.syncArrow then
                    feature.syncArrow()
                end
            end,
        })
        window.featureSettings = true
        window.placementAnchor = anchor
        feature.settingsWindow = window

        local options: any = feature.options
        if options then
            options.Visible = true
            options.Position = UDim2.fromOffset(0, 0)
            options.Size = UDim2.new(1, 0, 0, feature.optionsHeight or 40)
            options.Parent = window.body
            if bitmapText and type(bitmapText.adoptTree) == "function" then
                table.insert(
                    window.connections,
                    bitmapText.adoptTree(options)
                )
            end
        end

        local function resizeToOptions(): ()
            local wanted: number = TITLE_HEIGHT + (feature.optionsHeight or 40)
            local limit: number = tonumber(state.uiMaxSettingsHeight) or 200
            if limit <= 0 then
                limit = math.huge
            end
            wanted = math.min(wanted, limit)

            wanted = math.min(wanted, logicalViewport().Y - MARGIN * 2)
            window.fullHeight = wanted
            if not window.collapsed then
                window.root.Size = UDim2.fromOffset(width, wanted)
            end

            manager.ReflowWindow(window)
        end
        window.resizeToOptions = resizeToOptions
        resizeToOptions()

        local function repackWidth(): ()
            if not window.root.Parent then
                return
            end
            local bitmapText: any = state.bitmapText
            local widest: number = 0
            for _, optionRow: any in ipairs(feature.optionRows or {}) do
                local label: any = optionRow:FindFirstChild("OptionLabel")
                if label then
                    local measured: number = 0
                    if bitmapText and type(bitmapText.measure) == "function" then
                        measured = tonumber(bitmapText.measure(
                            {{text = label.Text}},
                            tonumber(label.TextSize) or 16
                        )) or 0
                    end
                    if measured <= 0 then
                        local bounds: any = label.TextBounds
                        measured = bounds and tonumber(bounds.X) or 0
                    end
                    if measured > 0 then
                        widest = math.max(widest, 8 + measured + 24 + 72)
                    end
                end
            end
            if widest > 0 then
                local packed: number = math.clamp(widest, 160, 420)
                if packed ~= width then
                    width = packed
                    resizeToOptions()
                end
            end
        end
        window.repackWidth = repackWidth
        task.defer(repackWidth)

        feature.expanded = true
        if feature.syncArrow then
            feature.syncArrow()
        end
        window.root.Visible = true
        raise(window)
        return window
    end

    function manager.BringToFront(window: any): ()
        if window then
            raise(window)
        end
    end

    function manager.DebugRects(): any
        local rects: {any} = {}
        for _, window: any in ipairs(manager.list) do
            local x: number, y: number, w: number, h: number = windowRect(window)
            table.insert(rects, {
                id = window.id,
                x = x, y = y, width = w, height = h,
                visible = window.root.Visible == true,
                userMoved = window.userMoved == true,
                collapsed = window.collapsed == true,
            })
        end
        return {
            scale = layerScale(),
            viewport = logicalViewport(),
            windows = rects,
        }
    end

    do
        local bitmapText: any = state.bitmapText
        if bitmapText and type(bitmapText.onReady) == "table" then
            table.insert(bitmapText.onReady, function(): ()
                for _, window: any in ipairs(manager.list) do
                    if window.featureSettings and window.repackWidth then
                        window.repackWidth()
                    end
                end
            end)
        end
    end

    state.addMenuVisibilityListener(function(visible: boolean): ()
        for _, window: any in ipairs(manager.list) do
            if window.featureSettings then
                if not visible and window.pinned then
                    continue
                end
                if visible then
                    window.root.Visible = window.wasOpenWithMenu == true
                else
                    window.wasOpenWithMenu = window.root.Visible
                    window.root.Visible = false
                end
            end
        end
    end)

    manager.bodyTransparency = 0.5
    function manager.SetOpacity(alpha: number): ()
        manager.bodyTransparency = math.clamp(1 - alpha, 0, 1)
        for _, window: any in ipairs(manager.list) do
            if window.headerHeight and window.headerHeight > 0 then
                window.root.BackgroundTransparency = manager.bodyTransparency
            end
        end
    end

    function manager.Reclamp(): ()
        for _, window: any in ipairs(manager.list) do
            local x: number, y: number, w: number, h: number = windowRect(window)
            local landed: Vector2 = clamp(Vector2.new(x, y), Vector2.new(w, h))
            window.root.Position = UDim2.fromOffset(landed.X, landed.Y)
        end
    end

    state.onLayout(function(): ()
        manager.Reclamp()
    end)

    state.windows = manager

    activeCleanup = function(): ()
        for index: number = #manager.list, 1, -1 do
            local window: any = manager.list[index]
            pcall(function(): ()
                window.root:Destroy()
            end)
        end
        manager.list = {}
        manager.byId = {}
        state.windows = nil
    end
    Module.Initialized = true
    return manager
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/guis/Wurst/Code/ClickGui.lua"] = [[export type CategoryWindow = {
    name: string,
    window: any,
    layout: UIListLayout,
    count: number,
}

local Module = {
    Name = "ClickGui",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local WINDOW_WIDTH: number = 200
local WINDOW_MAX_HEIGHT: number = 300

local SCALE_MINIMUM: number = 0.7
local SCALE_MAXIMUM: number = 1.6

local CALIBRATION_WIDTH: number = 1600
local CALIBRATION_HEIGHT: number = 900
local GRID_MARGIN: number = 10
local WINDOW_GAP: number = 2

local GRID_GAP: number = 10
local TITLE_HEIGHT: number = 26

local CATEGORY_ORDER: {string} = {
    "Combat",
    "Render",
    "Blocks",
    "Movement",
    "Fun",
    "Items",
    "Other",
}

local CATEGORY_ALIASES: {[string]: string} = {
    ["Visuals"] = "Render",
    ["Protection"] = "Movement",
    ["Utility"] = "Other",
    ["Spoof"] = "Fun",
    ["General"] = "Other",
    ["Player"] = "Movement",
}

local function fallbackNormalize(raw: any): string
    local name: string = tostring(raw or "Other")
    if table.find(CATEGORY_ORDER, name) ~= nil then
        return name
    end
    return CATEGORY_ALIASES[name] or "Other"
end

function Module.init(context: any): any
    local host: any = context
    local state: any = host.state
    local create: any = host.create
    local allFeatures: {any} = host.allFeatures
    local normalizeFeatureCategory: any = host.normalizeFeatureCategory

    local function viewportScale(): number
        local shape: any = host.ThemeEngine and host.ThemeEngine.shape
        local wanted: number = shape and tonumber(shape.scale) or 1
        local camera: Camera? = workspace.CurrentCamera
        local viewport: Vector2 = camera
            and (camera :: Camera).ViewportSize
            or Vector2.new(CALIBRATION_WIDTH, CALIBRATION_HEIGHT)
        local fit: number = math.min(
            viewport.X / CALIBRATION_WIDTH,
            viewport.Y / CALIBRATION_HEIGHT
        )
        return math.clamp(wanted * fit, SCALE_MINIMUM, SCALE_MAXIMUM)
    end

    local function logicalViewport(): Vector2
        local camera: Camera? = workspace.CurrentCamera
        local viewport: Vector2 = camera
            and (camera :: Camera).ViewportSize
            or Vector2.new(CALIBRATION_WIDTH, CALIBRATION_HEIGHT)
        local factor: number = viewportScale()
        return Vector2.new(viewport.X / factor, viewport.Y / factor)
    end

    local windows: any = state.windows
    if not windows then

        error("ClickGui requires the window manager")
    end

    local ClickGui: any = {
        categories = {} :: {[string]: CategoryWindow},
        order = {} :: {string},

        connections = {} :: {RBXScriptConnection},
    }

    local productVersion: string = tostring(
        (host.PRODUCT and host.PRODUCT.version) or "0.1 Beta"
    )
    local LOGO_CHIP_WIDTH: number = 142 + 10 + (8 + #productVersion * 15) + 4
    local LOGO_CHIP_HEIGHT: number = 44
    local TOP_ROW_X: number = 14 + LOGO_CHIP_WIDTH + GRID_GAP
    local TOP_ROW_Y: number = 10
    local nextX: number = TOP_ROW_X
    local nextY: number = TOP_ROW_Y
    local rowHeight: number = LOGO_CHIP_HEIGHT

    local function nextSlot(height: number): Vector2
        local viewport: Vector2 = logicalViewport()
        if nextX + WINDOW_WIDTH > viewport.X - GRID_MARGIN then
            nextX = GRID_MARGIN
            nextY += rowHeight + GRID_GAP
            rowHeight = 0
        end
        local slot: Vector2 = Vector2.new(nextX, nextY)
        nextX += WINDOW_WIDTH + GRID_GAP
        rowHeight = math.max(rowHeight, height)
        return slot
    end

    local function categoryWindow(name: string): CategoryWindow
        local existing: CategoryWindow? = ClickGui.categories[name]
        if existing then
            return existing :: CategoryWindow
        end

        local height: number = TITLE_HEIGHT + 8
        local window: any = windows.Create({
            id = "ClickGui_" .. name,
            title = name,
            size = Vector2.new(WINDOW_WIDTH, height),
            position = nextSlot(WINDOW_MAX_HEIGHT * 0.5),
            maxHeight = WINDOW_MAX_HEIGHT,

            closable = false,
        })

        local layout: UIListLayout = create("UIListLayout", {
            Parent = window.body,
            Padding = UDim.new(0, WINDOW_GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }) :: UIListLayout
        create("UIPadding", {
            Parent = window.body,
            PaddingTop = UDim.new(0, WINDOW_GAP),
            PaddingBottom = UDim.new(0, WINDOW_GAP),
            PaddingLeft = UDim.new(0, WINDOW_GAP),
            PaddingRight = UDim.new(0, WINDOW_GAP),
        })

        local record: CategoryWindow = {
            name = name,
            window = window,
            layout = layout,
            count = 0,
        }
        ClickGui.categories[name] = record
        table.insert(ClickGui.order, name)
        table.sort(ClickGui.order, function(left: string, right: string): boolean
            local leftRank: number = table.find(CATEGORY_ORDER, left) or math.huge
            local rightRank: number = table.find(CATEGORY_ORDER, right) or math.huge
            if leftRank == rightRank then
                return left < right
            end
            return leftRank < rightRank
        end)

        local function resize(): ()

            local limit: number = tonumber(state.uiMaxHeight) or WINDOW_MAX_HEIGHT
            if limit <= 0 then
                limit = math.huge
            end

            limit = math.min(limit, logicalViewport().Y - 12)

            local declaredHeight: number = 0
            local visibleRows: number = 0
            for _, child: Instance in ipairs(window.body:GetChildren()) do
                if child:IsA("GuiObject") and (child :: GuiObject).Visible then
                    visibleRows += 1
                    declaredHeight += (child :: GuiObject).Size.Y.Offset
                end
            end
            declaredHeight += math.max(visibleRows - 1, 0) * WINDOW_GAP
            local contentHeight: number = math.max(
                layout.AbsoluteContentSize.Y,
                declaredHeight
            )
            local wanted: number = math.min(
                TITLE_HEIGHT + contentHeight + 4,
                limit
            )
            window.fullHeight = wanted
            if not window.collapsed then
                window.root.Size = UDim2.fromOffset(WINDOW_WIDTH, wanted)
            end

            if windows.ClampWindow then
                windows.ClampWindow(window)
            end
        end
        table.insert(
            ClickGui.connections,
            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
        )
        resize()
        record.resize = resize :: any
        return record
    end

    local function sortCategoryRows(record: CategoryWindow): ()
        local rows: {GuiObject} = {}
        for _, child: Instance in ipairs(record.window.body:GetChildren()) do
            if not child:IsA("GuiObject") then
                continue
            end
            local key: any = child:GetAttribute("FeatureSortName")
            if type(key) == "string" then
                table.insert(rows, child :: GuiObject)
            end
        end
        table.sort(rows, function(left: GuiObject, right: GuiObject): boolean
            local leftKey: string = tostring(left:GetAttribute("FeatureSortName") or "")
            local rightKey: string = tostring(right:GetAttribute("FeatureSortName") or "")
            if leftKey == rightKey then
                return left.Name < right.Name
            end
            return leftKey < rightKey
        end)
        for index: number, row: GuiObject in ipairs(rows) do
            row.LayoutOrder = index
        end
    end

    function ClickGui.place(feature: any): ()
        local row: Frame? = feature and feature.row
        if not row then
            return
        end

        local raw: any = (row :: Frame):GetAttribute("FeatureCategory")
        local name: string = type(normalizeFeatureCategory) == "function"
            and normalizeFeatureCategory(raw)
            or fallbackNormalize(raw)
        local record: CategoryWindow = categoryWindow(name)
        record.count += 1;
        (row :: Frame).Parent = record.window.body;
        (row :: Frame).Size = UDim2.new(1, 0, 0, feature.collapsedHeight or 22)
        sortCategoryRows(record)
        if record.resize then
            (record.resize :: () -> ())()
        end
        local userMoved: boolean = false
        for _, category: string in ipairs(ClickGui.order) do
            local candidate: CategoryWindow? = ClickGui.categories[category]
            if candidate and candidate.window.userMoved == true then
                userMoved = true
                break
            end
        end
        if not userMoved and type(ClickGui.Retile) == "function" then
            ClickGui.Retile()
        end
    end

    function ClickGui.Retile(): ()

        nextX = TOP_ROW_X
        nextY = TOP_ROW_Y
        rowHeight = LOGO_CHIP_HEIGHT
        for _, name: string in ipairs(ClickGui.order) do
            local record: CategoryWindow = ClickGui.categories[name]
            if record then
                local slot: Vector2 = nextSlot(
                    record.window.fullHeight or WINDOW_MAX_HEIGHT * 0.5
                )
                record.window.root.Position = UDim2.fromOffset(slot.X, slot.Y)
                if type(windows.ClampWindow) == "function" then
                    windows.ClampWindow(record.window)
                end
            end
        end
    end

    function ClickGui.RefreshHeights(): ()
        for _, name: string in ipairs(ClickGui.order) do
            local record: CategoryWindow = ClickGui.categories[name]
            if record and record.resize then
                (record.resize :: () -> ())()
            end
        end
    end

    function ClickGui.SetVisible(visible: boolean): ()
        for _, name: string in ipairs(ClickGui.order) do
            local record: CategoryWindow = ClickGui.categories[name]

            if not visible and record.window.pinned then
                continue
            end
            record.window:SetVisible(visible and record.window.userVisible ~= false)
        end
    end

    local function resolvedCategory(feature: any): string
        local row: any = feature and feature.row
        local raw: any = row and row:GetAttribute("FeatureCategory")
        if type(normalizeFeatureCategory) == "function" then
            return normalizeFeatureCategory(raw)
        end
        return fallbackNormalize(raw)
    end
    for _, name: string in ipairs(CATEGORY_ORDER) do
        for _, feature: any in ipairs(allFeatures) do
            if resolvedCategory(feature) == name then
                categoryWindow(name)
                break
            end
        end
    end

    for _, feature: any in ipairs(allFeatures) do
        ClickGui.place(feature)
    end

    local scale: UIScale = create("UIScale", {
        Parent = host.PopupLayer,
        Name = "ClickGuiScale",
        Scale = viewportScale(),
    }) :: UIScale

    state.onLayout(function(): ()
        scale.Scale = viewportScale()
        ClickGui.RefreshHeights()
    end)
    ClickGui.scale = scale

    state.clickGui = ClickGui
    state.addMenuVisibilityListener(function(visible: boolean): ()
        ClickGui.SetVisible(visible)
    end)
    ClickGui.SetVisible(state.visible == true)

    activeCleanup = function(): ()
        for _, name: string in ipairs(ClickGui.order) do
            local record: CategoryWindow? = ClickGui.categories[name]
            if record then
                pcall(function(): ()
                    (record :: CategoryWindow).window:Destroy()
                end)
            end
        end
        for _, connection: RBXScriptConnection in ipairs(ClickGui.connections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        ClickGui.connections = {}
        ClickGui.categories = {}
        ClickGui.order = {}
        state.clickGui = nil
    end
    Module.Initialized = true
    return ClickGui
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/guis/Wurst/Code/FloatingWindows.lua"] = [[export type FloatingWindowRecord = {
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
    local ThemeEngine: any = host.ThemeEngine
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

    local function bind(instance: Instance, property: string, token: string): ()
        if ThemeEngine and type(ThemeEngine.Bind) == "function" then
            ThemeEngine.Bind(instance, property, token)
        else
            (instance :: any)[property] = Theme[token]
        end
    end

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
        state.windows.Raise(record.id)
    end

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
            BackgroundColor3 = Theme.background,
            BackgroundTransparency = bare and 1 or 0.08,
            BorderSizePixel = 0,
            ClipsDescendants = not bare,
            Position = UDim2.fromOffset(position.X, position.Y),
            Size = UDim2.fromOffset(size.X, size.Y),
            Visible = false,
            ZIndex = 150,
        }) :: Frame
        bind(root, "BackgroundColor3", "background")
        if not bare then
            create("UICorner", {
                Parent = root,
                CornerRadius = cornerRadius(UI_RADIUS.panel),
            })
            local edge: UIStroke = create("UIStroke", {
                Parent = root,
                Name = "WindowOutline",
                Color = Theme.outline,
                Transparency = 0.08,
                Thickness = 1,
            }) :: UIStroke
            bind(edge, "Color", "outline")

            local shade: Frame = create("Frame", {
                Parent = root,
                Name = "Readability",
                BackgroundColor3 = Theme.background,
                BackgroundTransparency = 0.28,
                BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1),
            }) :: Frame
            bind(shade, "BackgroundColor3", "background")
            shade:SetAttribute("FloatingDepth", 2)
        end

        local header: Frame = create("Frame", {
            Parent = root,
            Name = "Header",
            Active = not bare,
            BackgroundColor3 = Theme.surface,
            BackgroundTransparency = 0.24,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, headerHeight),
            Visible = not bare,
        }) :: Frame
        bind(header, "BackgroundColor3", "surface")
        header:SetAttribute("FloatingDepth", 3)

        local closeButton: TextButton
        if bare then

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
                BackgroundColor3 = Theme.outline,
                BackgroundTransparency = 0.62,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, headerHeight - 1),
                Size = UDim2.new(1, 0, 0, 1),
            }) :: Frame
            bind(accent, "BackgroundColor3", "outline")
            accent:SetAttribute("FloatingDepth", 1)
            local title: TextLabel = makeTextLabel(header, titleText, 10)
            title.FontFace = CONTROL_FONT
            title.Position = UDim2.fromOffset(10, 0)
            title.Size = UDim2.new(1, -40, 1, 0)
            title.TextColor3 = Theme.text
            bind(title, "TextColor3", "text")
            title:SetAttribute("FloatingDepth", 2)

            closeButton = makeButton(header, "x", 9)
            closeButton.Name = "Close"
            closeButton.AnchorPoint = Vector2.new(1, 0.5)
            closeButton.BackgroundTransparency = 1
            closeButton.Position = UDim2.new(1, -6, 0.5, 0)
            closeButton.Size = UDim2.fromOffset(22, 22)
            closeButton.TextColor3 = Theme.textMuted
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

        if bare then
            root.Active = state.visible == true

            create("UICorner", {
                Parent = root,
                CornerRadius = cornerRadius(UI_RADIUS.control),
            })
            local hint: UIStroke = create("UIStroke", {
                Parent = root,
                Name = "MoveHint",
                Color = Theme.outline,
                Thickness = 1,
                Transparency = state.visible and 0.72 or 1,
            }) :: UIStroke
            bind(hint, "Color", "outline")
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

        state.windows.Adopt(root, {
            id = id,
            body = body,
            header = header,
            closeButton = closeButton,
            headerHeight = headerHeight,
            dragHandle = bare and root or header,
            requiresMenuOpen = bare,
            layered = true,
            onClose = onClose,
        })
        return record
    end

    function FloatingUi.reclamp(): ()
        state.windows.Reclamp()
    end

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
        ScrollBarImageColor3 = Theme.outline,
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
            and Theme.accent
            or Theme.textMuted
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
                    BackgroundColor3 = Theme.surface,
                    BackgroundTransparency = 0.38,
                    BorderSizePixel = 0,
                    FontFace = THIN_FONT,
                    LayoutOrder = order,
                    Size = UDim2.new(1, -4, 0, 36),
                    Text = feature.name,
                    TextColor3 = feature.enabled
                        and Theme.accent
                        or Theme.text,
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
                        and Theme.accent
                        or Theme.textMuted,
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
                TextColor3 = Theme.textMuted,
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
            BackgroundColor3 = Theme.surface,
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
        managerLabel.TextColor3 = Theme.textMuted
        managerLabel:SetAttribute("FloatingDepth", 1)
        local settingsButton: TextButton = makeButton(managerRow, "", 9)
        settingsButton.Name = "Settings"

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
            ScrollBarImageColor3 = Theme.accentDim,
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
            BackgroundColor3 = Theme.surface,
            BackgroundTransparency = 0.44,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -4, 0, 38),
        }) :: Frame
        create("UICorner", {Parent = row, CornerRadius = cornerRadius(8)})
        local label: TextLabel = makeTextLabel(row, labelText, 9)
        label.Position = UDim2.fromOffset(10, 0)
        label.Size = UDim2.new(0.48, -10, 1, 0)
        label.TextColor3 = Theme.textMuted
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
    SessionText.TextColor3 = Theme.text
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
    TextGuiLabel.TextColor3 = Theme.accent
    TextGuiLabel.TextWrapped = true
    TextGuiLabel.TextYAlignment = Enum.TextYAlignment.Top
    TextGuiLabel:SetAttribute("FloatingDepth", 2)
    local TextGuiGradient: UIGradient = create("UIGradient", {
        Parent = TextGuiLabel,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.accent),
            ColorSequenceKeypoint.new(0.5, Theme.accentDim),
            ColorSequenceKeypoint.new(1, Theme.accentFaint),
        }),
        Rotation = 90,
        Enabled = false,
    }) :: UIGradient

    local TargetBody: Frame = FloatingUi.overlays.TargetInfo.window.body

    local TargetPortraitFrame: Frame = create("Frame", {
        Parent = TargetBody,
        BackgroundColor3 = Theme.surface,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(56, 56),
    }) :: Frame
    TargetPortraitFrame:SetAttribute("FloatingDepth", 2)
    create("UICorner", {Parent = TargetPortraitFrame, CornerRadius = cornerRadius(UI_RADIUS.panel)})
    create("UIStroke", {
        Parent = TargetPortraitFrame,
        Color = Theme.outline,
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
    TargetRole.TextColor3 = Theme.accentDim
    TargetRole:SetAttribute("FloatingDepth", 2)
    local TargetHealthTrack: Frame = create("Frame", {
        Parent = TargetBody,
        BackgroundColor3 = Theme.background,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(64, 42),
        Size = UDim2.new(1, -64, 0, 6),
    }) :: Frame
    TargetHealthTrack:SetAttribute("FloatingDepth", 2)
    create("UICorner", {Parent = TargetHealthTrack, CornerRadius = UDim.new(1, 0)})
    local TargetHealthFill: Frame = create("Frame", {
        Parent = TargetHealthTrack,
        BackgroundColor3 = Theme.accent,
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
    TargetDetails.TextColor3 = Theme.textMuted
    TargetDetails:SetAttribute("FloatingDepth", 2)

    local RadarSurface: Frame = create("Frame", {
        Parent = FloatingUi.overlays.Radar.window.body,
        Name = "Surface",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.surface,
        BackgroundTransparency = 0.34,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(radarSettings.size, radarSettings.size),
    }) :: Frame
    RadarSurface:SetAttribute("FloatingDepth", 2)
    create("UICorner", {Parent = RadarSurface, CornerRadius = UDim.new(1, 0)})
    create("UIStroke", {
        Parent = RadarSurface,
        Color = Theme.outline,
        Transparency = 0.55,
    })
    local radarAxes: {Frame} = {}
    for _, rotation: number in ipairs({0, 90}) do
        local axis: Frame = create("Frame", {
            Parent = RadarSurface,
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.outline,
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
            Color = Theme.outline,
            Transparency = 0.7,
            Thickness = 1,
        })
        table.insert(radarRings, ring)
    end
    local RadarNorth: TextLabel = makeTextLabel(RadarSurface, "N", 8)
    RadarNorth.AnchorPoint = Vector2.new(0.5, 0)
    RadarNorth.Position = UDim2.new(0.5, 0, 0, 5)
    RadarNorth.Size = UDim2.fromOffset(20, 18)
    RadarNorth.TextColor3 = Theme.accent
    RadarNorth.TextXAlignment = Enum.TextXAlignment.Center
    RadarNorth:SetAttribute("FloatingDepth", 3)
    local RadarCenter: Frame = create("Frame", {
        Parent = RadarSurface,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.accent,
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
                table.insert(textLines, "Wurst")
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
            TextGuiBody.BackgroundColor3 = Theme.background
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
                    ColorSequenceKeypoint.new(0, Theme.accent),
                    ColorSequenceKeypoint.new(0.34, Theme.accentDim),
                    ColorSequenceKeypoint.new(0.68, Theme.accentFaint),
                    ColorSequenceKeypoint.new(1, Theme.accent),
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
                TextGuiLabel.TextColor3 = Theme.accent
            elseif textGuiSettings.colorMode == "By section" then
                TextGuiLabel.TextColor3 = Theme.accentDim
            else
                TextGuiLabel.TextColor3 = Theme.accent
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
        local targetAccent: Color3 = Theme.accentDim
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
            targetAccent = targetRole == "Murderer" and Theme.negative
                or ((targetRole == "Sheriff" or targetRole == "Hero")
                    and Theme.accent
                    or Theme.positive)
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
                    and Theme.accent
                    or (ratio > 0.25 and Theme.accentDim or Theme.accentFaint)
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
                                    BackgroundColor3 = Theme.accentFaint,
                                    BorderSizePixel = 0,
                                    Size = UDim2.fromOffset(7, 7),
                                }) :: Frame
                                blip:SetAttribute("FloatingDepth", 4)
                                create("UICorner", {Parent = blip, CornerRadius = UDim.new(1, 0)})
                                local targetRing: UIStroke = create("UIStroke", {
                                    Parent = blip,
                                    Color = Theme.accent,
                                    Transparency = 1,
                                    Thickness = 2,
                                }) :: UIStroke
                                local label: TextLabel = makeTextLabel(blip, "", 7)
                                label.AnchorPoint = Vector2.new(0.5, 0)
                                label.Position = UDim2.new(0.5, 0, 1, 3)
                                label.Size = UDim2.fromOffset(100, 18)
                                label.TextColor3 = Theme.text
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
                            local color: Color3 = Theme.accentFaint
                            if radarSettings.colorMode == "Health" and humanoid then
                                local healthRatio: number = humanoid.Health / math.max(1, humanoid.MaxHealth)
                                color = Color3.fromHSV(healthRatio * 0.34, 0.8, 1)
                            elseif radarSettings.colorMode == "Team" or radarSettings.colorMode == "Smart" then
                                color = sameTeam and Theme.positive or Theme.negative
                            end
                            if (radarSettings.colorMode == "MM2 role" or radarSettings.colorMode == "Smart") and role then
                                color = role == "Murderer" and Theme.negative
                                    or ((role == "Sheriff" or role == "Hero") and Theme.accent
                                        or Theme.positive)
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

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/guis/Wurst/Code/SettingsPage.lua"] = [[local Module = {
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
    local CLICKGUI_BACKGROUND: Color3 = Color3.fromRGB(64, 64, 64)
    local CLICKGUI_ACCENT: Color3 = Color3.fromRGB(16, 16, 16)
    local CLICKGUI_TEXT: Color3 = Color3.fromRGB(240, 240, 240)
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
        nameBox.TextSize = 14
        nameBox.ZIndex = entryRow.ZIndex + 1
        local saveButton: TextButton = (makeButton(entryRow, "SAVE", 10) :: any) :: TextButton
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
                    TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = row.ZIndex + 1,
                })
                local loadButton: TextButton = (makeButton(row, "LOAD", 10) :: any) :: TextButton
                loadButton.AnchorPoint = Vector2.new(1, 0.5)
                loadButton.Position = UDim2.new(1, -6, 0.5, 0)
                loadButton.Size = UDim2.fromOffset(48, 18)
                loadButton.ZIndex = row.ZIndex + 1
                trackUiConnection(loadButton.MouseButton1Click:Connect(function(): ()
                    local snapshot: any = profileStore()[name]
                    if type(snapshot) ~= "table" then
                        return
                    end
                    for _, binding: any in pairs(state.shortcutBindings) do
                        local savedName: any = snapshot[tostring(binding.id)]
                        local savedKey: any = nil
                        if type(savedName) == "string" and savedName ~= "" then

                            local resolved: boolean, candidate: any = pcall(function(): any
                                return (Enum.KeyCode :: any)[savedName]
                            end)
                            if resolved then
                                savedKey = candidate
                            end
                        end
                        binding.key = savedKey or Enum.KeyCode.Unknown
                        persistBindingKey(binding)
                        if binding.refresh then
                            binding.refresh()
                        end
                    end
                    rebuildKeybinds()
                    notify("loaded profile " .. name)
                end))
            end
            if profilesRecord then

                if profilesRecord.repack then
                    local rows: {{any}} = {{"New profile name", nil, 60}}
                    for _, name: string in ipairs(names) do
                        table.insert(rows, {name, nil, 66})
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

    -- Hidden windows must stay hidden on the next join too: the saved
    -- "ClickGUI.Windows.<name>" states have to be re-applied at boot,
    -- without opening the Windows panel first.
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
        -- Category windows appear as modules register, so keep re-applying
        -- the saved visibility for a while; it is idempotent and cheap.
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
        or GAME_CHECK.MVSDActive and "MVSD"
        or "Universal only"

    -- Keybinds and Windows live as rows inside UI Settings only; registering
    -- them here as well duplicated the whole UI Settings window inside
    -- Wurst Options.
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
    uiRecord = configWindow("UISettings", "UI Settings", {
        position = Vector2.new(screen.X - WINDOW_WIDTH - 12, 64),
        closable = false,
        settingsSized = false,
        packRows = {
            {"HackList", nil, 26},
            {"Keybinds", nil, 26},
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
    actionRow(uiRecord, 2, "Keybinds", openKeybinds)
    actionRow(uiRecord, 3, "Windows", openWindows)
    actionRow(uiRecord, 4, "WurstOptions", openWurstOptions)

    local uiPanel: any = panelFor(uiRecord, "ClickGUI")

    uiPanel.optionCount = 4

    local uiSettingsValues: {[string]: any} = {}
    state.uiSettings = uiSettingsValues

    local CLICKGUI_ENABLED: Color3 = Color3.fromRGB(32, 175, 32)
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
    for _, row: any in ipairs({
        {label = "Background", default = CLICKGUI_BACKGROUND, tokens = {"surface", "background"}},
        {label = "Accent", default = CLICKGUI_ACCENT, tokens = {"accent", "outline"}},
        {label = "Text", default = CLICKGUI_TEXT, tokens = {"text", "accentText"}},
        {label = "Enabled", default = CLICKGUI_ENABLED, tokens = {"enabled"}},
    }) do
        local tokens: {string} = row.tokens
        local labelText: string = row.label
        local swatch: TextButton? = addColorOption(
            uiPanel,
            labelText,
            row.default,
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

    local rainbowConnection: any = nil
    local rainbowElapsed: number = 0
    local rainbowSince: number = 0
    addToggleOption(uiPanel, "Rainbow", false, function(value: boolean): ()
        uiSettingsValues["Rainbow"] = value
        if rainbowConnection then
            rainbowConnection:Disconnect()
            rainbowConnection = nil
        end
        if not ThemeEngine or type(ThemeEngine.Set) ~= "function" then
            return
        end
        if not value then
            local accent: any = uiSettingsValues["Accent"] or CLICKGUI_ACCENT
            local enabledColor: any = uiSettingsValues["Enabled"] or CLICKGUI_ENABLED
            paintPalette("Accent", accent)
            paintPalette("Enabled", enabledColor)
            if type(ThemeEngine.SetMany) == "function" then
                ThemeEngine.SetMany({
                    accent = accent,
                    outline = accent,
                    enabled = enabledColor,
                })
            else
                ThemeEngine.Set("accent", accent)
                ThemeEngine.Set("outline", accent)
                ThemeEngine.Set("enabled", enabledColor)
            end
            return
        end
        rainbowConnection = trackUiConnection(RunService.Heartbeat:Connect(function(step: number): ()
            rainbowElapsed += step
            rainbowSince += step
            if rainbowSince < 0.05 then
                return
            end
            rainbowSince = 0
            local color: Color3 = Color3.fromHSV(rainbowElapsed * 0.25 % 1, 0.85, 1)
            paintPalette("Accent", color)
            paintPalette("Enabled", color)
            if type(ThemeEngine.SetMany) == "function" then
                ThemeEngine.SetMany({
                    accent = color,
                    outline = color,
                    enabled = color,
                })
            else
                ThemeEngine.Set("accent", color)
                ThemeEngine.Set("outline", color)
                ThemeEngine.Set("enabled", color)
            end
        end))
    end)

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
        addToggleOption(uiPanel, "Show dock", true, function(value: boolean): ()
            uiSettingsValues["Show dock"] = value
            state.uiShowDock = value
            if state.dock and type(state.dock.SetVisible) == "function" then
                state.dock.SetVisible(value)
            end
        end)
    end

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
]],
        ["src/guis/Wurst/Code/MobileActions.lua"] = [[export type MobileHoldCallbacks = {

    isActive: (() -> boolean)?,
    onPress: (() -> ())?,
    onRelease: (() -> ())?,
}

export type MobileActionRecord = {
    id: string,
    label: string,
    button: TextButton,
    callback: () -> (),

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
    local ThemeEngine: any = host.ThemeEngine
    local CONTROL_FONT: any = host.CONTROL_FONT
    local ScreenGui: any = host.ScreenGui
    local PopupLayer: any = host.PopupLayer
    local TweenService: any = host.TweenService
    local UserInputService: any = host.UserInputService
    local UI_MOTION: any = host.UI_MOTION
    local cornerRadius: any = host.cornerRadius
    local trackUiConnection: any = host.trackUiConnection

    local initialViewport: any = host.initialViewport or Vector2.new(1280, 720)

    type MobileActionRecord = {
        id: string,
        label: string,
        button: TextButton,
        callback: () -> (),

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
    local editorStroke: UIStroke = (create("UIStroke", {
        Parent = editorPanel,
        Name = "WindowOutline",
        Color = Theme.outline,
        Thickness = 1,
        Transparency = 0.08,
    }) :: any) :: UIStroke
    if ThemeEngine and type(ThemeEngine.Bind) == "function" then
        ThemeEngine.Bind(editorStroke, "Color", "outline")
    end
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
    local removeButton: TextButton = editorButton("Remove", "Remove", 14, 140, 78)
    removeButton.BackgroundColor3 = Color3.fromRGB(120, 28, 28)
    local resetButton: TextButton = editorButton("Reset", "Reset", 101, 140, 78)
    local doneButton: TextButton = editorButton("Done", "Done", 188, 140, 78)
    doneButton.BackgroundColor3 = Theme.enabled
    doneButton.TextColor3 = Theme.enabledText
    if ThemeEngine and type(ThemeEngine.Bind) == "function" then
        ThemeEngine.Bind(doneButton, "BackgroundColor3", "enabled")
        ThemeEngine.Bind(doneButton, "TextColor3", "enabledText")
    end

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
    trackUiConnection(resetButton.MouseButton1Click:Connect(function(): ()
        if editingRecord then
            editingRecord.size = 52
            editingRecord.opacity = 0.92
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
        local buttonOutline: UIStroke = (create("UIStroke", {
            Parent = button,
            Name = "MobileActionOutline",
            Color = Theme.outline,
            Transparency = 0.35,
            Thickness = 1,
        }) :: any) :: UIStroke
        if ThemeEngine and type(ThemeEngine.Bind) == "function" then
            ThemeEngine.Bind(buttonOutline, "Color", "outline")
        end
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

    state.addMenuVisibilityListener(setMobileActionVisibility)

    Module.Initialized = true
    return state.mobileUi
end

function Module.destroy(): ()
    Module.Initialized = false
end

return Module
]],
        ["src/guis/Wurst/Code/Furniture.lua"] = [[local Module = {
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
]],
        ["src/games/universal/Utility/FriendList.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "FriendList",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function splitNames(text: string): {[string]: boolean}
    local names: {[string]: boolean} = {}
    for name: string in string.gmatch(string.lower(text), "[^,%s]+") do
        names[name] = true
    end
    return names
end

local function countKeys(map: {[string]: boolean}): number
    local total: number = 0
    for _ in pairs(map) do
        total += 1
    end
    return total
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local players: Players = host.Players
    local localPlayer: Player = host.LocalPlayer
    local protectedTargets: any = context.services.protectedTargets

    local list: any = {
        names = {} :: {[string]: boolean},
        userIds = {} :: {[number]: boolean},
        protectRobloxFriends = true,
        protectTeam = false,
    }

    function list.isProtected(player: Player?): boolean
        if not player then
            return true
        end
        if player == localPlayer then
            return true
        end
        if list.userIds[player.UserId] then
            return true
        end
        if list.protectTeam
            and player.Team ~= nil
            and player.Team == localPlayer.Team
            and not player.Neutral then
            return true
        end
        return list.names[string.lower(player.Name)] == true
            or list.names[string.lower(player.DisplayName)] == true
    end

    function list.count(): number
        return countKeys(list.names) + countKeys(list.userIds :: any)
    end

    function list.refreshRobloxFriends(): ()
        list.userIds = {}
        if not list.protectRobloxFriends then
            return
        end
        for _, player: Player in ipairs(players:GetPlayers()) do
            if player == localPlayer then
                continue
            end
            local ok: boolean, isFriend: any = pcall(
                localPlayer.IsFriendsWithAsync,
                localPlayer,
                player.UserId
            )
            if ok and isFriend then
                list.userIds[player.UserId] = true
            end
        end
    end

    protectedTargets.setProvider(list.isProtected)

    local friends: any
    friends = framework.Categories.Utility:CreateModule({
        Name = "Friend List",
        Category = "Other",
        Order = 1,
        Kind = "group",
        Tooltip = "Players listed here are never targeted by Kill Aura, "
            .. "TriggerBot, Fling or any game module.",
        Function = function(): () end,
    })

    local namesBox: any
    local statusNote: any

    local function publish(): ()
        if statusNote then
            statusNote.Value = list.count()
        end
        if host.notify and list.count() > 0 then

        end
    end

    namesBox = friends:CreateTextBox({
        Name = "Protected names",
        Default = "",
        Tooltip = "Comma-separated. Matches display names too.",
        Function = function(value: string): ()
            list.names = splitNames(value)
            publish()
        end,
    })

    friends:CreateToggle({
        Name = "Protect Roblox friends",
        Default = false,
        Tooltip = "Everyone in the server you are actually friends with.",
        Function = function(value: boolean): ()
            list.protectRobloxFriends = value
            task.spawn(list.refreshRobloxFriends)
        end,
    })

    friends:CreateToggle({
        Name = "Protect team-mates",
        Default = false,
        Tooltip = "Adds everyone sharing your team, on top of the list.",
        Function = function(value: boolean): ()
            list.protectTeam = value
        end,
    })

    friends:CreateButton({
        Name = "Add nearest player",
        Tooltip = "Puts whoever is closest to you on the list.",
        Function = function(): ()
            local entityLibrary: any = context.entity
            if not entityLibrary then
                return
            end
            entityLibrary:Refresh()
            local closest: any = nil
            local closestDistance: number = math.huge
            for _, entity: any in ipairs(entityLibrary.List) do
                if entity.Distance < closestDistance then
                    closest = entity
                    closestDistance = entity.Distance
                end
            end
            if not closest then
                friends:Notify("nobody nearby")
                return
            end
            list.names[string.lower(closest.Player.Name)] = true
            if namesBox and namesBox.Object then
                local current: string = tostring(namesBox.Value or "")
                namesBox.Value = current == ""
                    and closest.Player.Name
                    or (current .. ", " .. closest.Player.Name)
                namesBox:Set(namesBox.Value)
            end
            friends:Notify(closest.Player.Name .. " protected")
            publish()
        end,
    })

    friends:CreateButton({
        Name = "Clear list",
        Function = function(): ()
            list.names = {}
            if namesBox and namesBox.Object then
                namesBox.Value = ""
                namesBox:Set("")
            end
            friends:Notify("list cleared")
            publish()
        end,
    })

    friends:CreateNote(
        "Protection is checked by every targeting module, in every game."
    )

    local connection: RBXScriptConnection = players.PlayerAdded:Connect(function(): ()
        task.defer(list.refreshRobloxFriends)
    end)
    task.spawn(list.refreshRobloxFriends)

    activeCleanup = function(): ()
        pcall(function(): ()
            connection:Disconnect()
        end)
        protectedTargets.setProvider(nil)
    end
    Module.Initialized = true
    return friends
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/ItemRender.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    render: any,
}

local Module = {
    Name = "ItemRender",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
    layer = nil :: Frame?,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local menu: any = context.services.menu

    local tracked: {[Instance]: boolean} = {}

    local index: {Instance} = {}
    local indexConnections: {RBXScriptConnection} = {}
    local indexDirty: boolean = true

    local known: {string} = {}
    local wanted: {string} = {}
    local picking: boolean = false

    local function release(instance: Instance): ()
        if not tracked[instance] then
            return
        end
        tracked[instance] = nil
        local renderLib: any = context.render
        if renderLib and Module.layer then
            renderLib:Release(Module.layer, instance)
        end
    end

    local function releaseAll(): ()
        for instance: Instance in pairs(tracked) do
            release(instance)
        end
    end

    local function nameMatches(name: string): boolean
        local lowered: string = string.lower(name)
        for _, entry: string in ipairs(wanted) do
            if string.find(lowered, string.lower(entry), 1, true) then
                return true
            end
        end
        return false
    end

    local function rebuildIndex(): ()
        table.clear(index)
        indexDirty = false
        if #wanted == 0 then
            return
        end
        for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if descendant:IsA("BasePart") or descendant:IsA("Model") then
                if nameMatches(descendant.Name) then
                    table.insert(index, descendant)
                end
            end
        end
    end

    local function watchWorkspace(): ()
        table.insert(
            indexConnections,
            currentWorkspace.DescendantAdded:Connect(function(descendant: Instance): ()
                if #wanted == 0 then
                    return
                end
                if not descendant:IsA("BasePart") and not descendant:IsA("Model") then
                    return
                end
                if nameMatches(descendant.Name) then
                    table.insert(index, descendant)
                end
            end)
        )
        table.insert(
            indexConnections,
            currentWorkspace.DescendantRemoving:Connect(function(descendant: Instance): ()
                local position: number? = table.find(index, descendant)
                if position then
                    table.remove(index, position)
                end
            end)
        )
    end

    local renderLib: any = context.render
    local layer: Frame? = renderLib and renderLib:Layer("ItemRenderLayer") or nil
    Module.layer = layer

    local render: any
    render = framework.Categories.Visuals:CreateModule({
        Name = "ItemESP",
        Category = "Render",
        ConfigKey = "Universal.ItemRender",
        Order = 2,
        Tooltip = "Names and outlines every object on the list, wherever it is.",
        Function = function(enabled: boolean): ()
            if layer then
                layer.Visible = enabled
            end
            if not enabled then
                render:SetStatus(nil)
                releaseAll()
                picking = false
                return
            end
            render:SetStatus("0")
            render:Clean(function(): ()
                releaseAll()
                picking = false
                if layer then
                    layer.Visible = false
                end
            end)
            indexDirty = true
            watchWorkspace()
            render:Clean(function(): ()
                for _, connection: RBXScriptConnection in ipairs(indexConnections) do
                    pcall(function(): ()
                        connection:Disconnect()
                    end)
                end
                indexConnections = {}
                table.clear(index)
            end)
            render:Render(function(): ()
                if indexDirty then
                    rebuildIndex()
                end
                Module.render(context, render, tracked, wanted, release, index)
            end)
        end,
    })

    local objectList: any
    objectList = render:CreateList({
        Name = "Objects",
        Items = function(): {string}
            return known
        end,
        Tooltip = "Every object the module knows about. Tick the ones to draw.",
        Function = function(_selected: any, names: {string}): ()
            wanted = names
            indexDirty = true
            releaseAll()
        end,
    })

    local function learn(name: string): ()
        if name == "" then
            return
        end
        if not table.find(known, name) then
            table.insert(known, name)
            table.sort(known)
        end
        objectList:Set(name, true)
    end

    local addBox: any
    addBox = render:CreateTextBox({
        Name = "Add by name",
        Default = "",
        Tooltip = "Type a name and it joins the list, ticked. Partial names "
            .. "match, so chest catches GoldChest.",
        Function = function(value: string): ()
            local trimmed: string = string.match(value, "^%s*(.-)%s*$") or value
            if trimmed == "" then
                return
            end
            learn(trimmed)

            addBox:Set("")
        end,
    })

    render:CreateButton({
        Name = "Touch part",
        Tooltip = "Hides the menu, then adds whatever you tap next.",
        Function = function(): ()
            if picking then
                picking = false
                render:Notify("cancelled")
                return
            end
            picking = true

            menu.setVisible(false)
            render:Notify("tap the object you want rendered")
        end,
    })

    render:CreateButton({
        Name = "Clear list",
        Function = function(): ()
            for _, name: string in ipairs(known) do
                objectList:Set(name, false)
            end
            table.clear(known)
            wanted = {}
            objectList:Refresh()
            releaseAll()
            render:Notify("list cleared")
        end,
    })

    render:CreateToggle({
        Name = "Show distance",
        Default = true,
    })
    render:CreateToggle({
        Name = "Outline",
        Default = true,
        Tooltip = "Draw the object's silhouette through walls.",
    })
    render:CreateSlider({
        Name = "Max distance",
        Min = 50,
        Max = 5000,
        Default = 1200,
    })
    render:CreateSlider({
        Name = "Text size",
        Min = 8,
        Max = 22,
        Default = 12,
    })
    render:CreateColor({
        Name = "Colour",
        Default = Color3.fromRGB(232, 232, 236),
    })

    local pickConnection: RBXScriptConnection = userInput.InputBegan:Connect(
        function(input: InputObject, processed: boolean): ()
            if not picking or processed then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local camera: Camera? = currentWorkspace.CurrentCamera
            if not camera then
                return
            end

            local ray: Ray = (camera :: Camera):ScreenPointToRay(
                input.Position.X,
                input.Position.Y
            )
            local parameters: RaycastParams = RaycastParams.new()
            parameters.FilterType = Enum.RaycastFilterType.Exclude
            parameters.IgnoreWater = true
            parameters.FilterDescendantsInstances = {
                localPlayer.Character :: any,
                camera,
            }
            local result: RaycastResult? = currentWorkspace:Raycast(
                ray.Origin,
                ray.Direction.Unit * 4096,
                parameters
            )
            if not result then
                render:Notify("nothing under that tap")
                return
            end
            picking = false

            local hit: Instance = (result :: RaycastResult).Instance
            local model: Instance? = hit:FindFirstAncestorOfClass("Model")
            local name: string = model and model.Name or hit.Name
            learn(name)
            menu.setVisible(true)
            render:Notify(name .. " added")
        end
    )

    render:CreateNote(
        "Every object sharing the name is rendered, not just the one you tapped."
    )

    activeCleanup = function(): ()
        picking = false
        pcall(function(): ()
            pickConnection:Disconnect()
        end)
        releaseAll()
    end
    Module.Initialized = true
    return render
end

function Module.render(
    context: Runtime,
    render: any,
    tracked: {[Instance]: any},
    wanted: {string},
    release: (Instance) -> (),
    index: {Instance}
): ()
    local host: any = context.host
    local renderLib: any = context.render
    local layer: Frame? = Module.layer
    local localPlayer: Player = host.LocalPlayer
    local options: any = render.Options
    local currentWorkspace: Workspace = host.workspace or workspace
    local camera: Camera? = currentWorkspace.CurrentCamera

    if #wanted == 0 or not renderLib or not layer or not camera then
        for instance: Instance in pairs(tracked) do
            release(instance)
        end
        return
    end

    local resolvedCamera: Camera = camera :: Camera
    local resolvedLayer: Frame = layer :: Frame
    local character: Model? = localPlayer.Character
    local root: BasePart? = character
        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local origin: Vector3 = root and (root :: BasePart).Position or Vector3.zero
    local maxDistance: number = options["Max distance"].Value
    local colour: Color3 = options["Colour"].Value
    local textSize: number = math.round(options["Text size"].Value)
    local seen: {[Instance]: boolean} = {}

    local function lowerMatch(name: string): boolean
        local lowered: string = string.lower(name)
        for _, entry: string in ipairs(wanted) do
            if string.find(lowered, string.lower(entry), 1, true) then
                return true
            end
        end
        return false
    end

    for _, descendant: Instance in ipairs(index) do
        if not descendant.Parent then
            continue
        end
        local isPart: boolean = descendant:IsA("BasePart")
        local isModel: boolean = descendant:IsA("Model")
        if not isPart and not isModel then
            continue
        end
        if character and descendant:IsDescendantOf(character) then
            continue
        end
        if not lowerMatch(descendant.Name) then
            continue
        end
        if isPart and descendant:FindFirstAncestorOfClass("Model") then
            local ancestor: Instance? = descendant:FindFirstAncestorOfClass("Model")
            if ancestor and lowerMatch(ancestor.Name) then
                continue
            end
        end

        local anchor: BasePart? = nil
        if isPart then
            anchor = descendant :: BasePart
        else
            anchor = (descendant :: Model).PrimaryPart
                or (descendant :: Model):FindFirstChildWhichIsA("BasePart")
        end
        if not anchor then
            continue
        end
        local resolvedAnchor: BasePart = anchor :: BasePart
        local distance: number = (resolvedAnchor.Position - origin).Magnitude
        if distance > maxDistance then
            continue
        end
        local projected: Vector2? = renderLib:Project(resolvedCamera, resolvedAnchor.Position)
        if not projected then
            continue
        end

        seen[descendant] = true
        tracked[descendant] = true
        local drawings: any = renderLib:Set(resolvedLayer, descendant)
        drawings:Show(true)
        drawings:Label(
            "NameTag",
            options["Show distance"].Value
                    and (descendant.Name .. "  " .. tostring(math.round(distance)) .. "m")
                or descendant.Name,
            projected :: Vector2,
            0.5,
            textSize,
            colour,
            true
        )
        drawings:Highlight(
            descendant,
            colour,
            1,
            options["Outline"].Value and "Outline" or "Off"
        )
    end

    local count: number = 0
    for instance: Instance in pairs(tracked) do
        if not seen[instance] or not instance.Parent then
            release(instance)
        else
            count += 1
        end
    end
    local status: string = tostring(count)
    if render.Status ~= status then
        render:SetStatus(status)
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.layer = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/PlayerESP.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "PlayerESP",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local players: Players = host.Players

    local render: any = context.render

    local container: Frame = render:Layer("PlayerEspLayer")
    local pool: {[Player]: boolean} = {}
    local lastStatusAt: number = -math.huge
    local visibilityCache: any = setmetatable({}, {__mode = "k"})

    local esp: any
    esp = framework.Categories.Visuals:CreateModule({
        Name = "PlayerESP",
        Category = "Render",
        ConfigKey = "Universal.PlayerESP",
        Order = 1,
        Tooltip = "Boxes, skeletons, name tags, health, tracers and chams, "
            .. "each independently switchable.",
        Function = function(enabled: boolean): ()
            container.Visible = enabled
            if not enabled then
                esp:SetStatus(nil)
                render:ReleaseAll(container)
                table.clear(pool)
                return
            end
            lastStatusAt = -math.huge
            esp:SetStatus("0")
            esp:Render(function(): ()
                Module.render(context, container, pool, esp, visibilityCache)
                local now: number = os.clock()
                if now - lastStatusAt >= 0.25 then
                    lastStatusAt = now
                    local count: number = 0
                    for _player: Player in pairs(pool) do
                        count += 1
                    end
                    esp:SetStatus(tostring(count))
                end
            end)
            esp:Event(players.PlayerRemoving, function(player: Player): ()
                render:Release(container, player)
                pool[player] = nil
            end)
            esp:Clean(function(): ()
                render:ReleaseAll(container)
                table.clear(pool)
                container.Visible = false
            end)
        end,
    })

    esp:CreateDropdown({
        Name = "Boxes",
        List = {"Corner", "Full", "Off"},
        Index = 1,
        Tooltip = "Corner draws four brackets, Full draws the whole rectangle.",
    })
    esp:CreateSlider({
        Name = "Box thickness",
        Show = {Option = "Boxes", Values = {"Corner", "Full"}},
        Min = 1,
        Max = 5,
        Default = 1,
    })
    esp:CreateToggle({
        Name = "Filled box",
        Show = {Option = "Boxes", Values = {"Corner", "Full"}},
        Default = false,
        Tooltip = "Wash the inside of the box in the target's colour. Reads "
            .. "at a glance across a map; noisy in a crowd.",
    })
    esp:CreateToggle({
        Name = "Skeleton",
        Default = false,
        Tooltip = "Draw the rig's bones. Works on both R6 and R15.",
    })
    esp:CreateToggle({
        Name = "Name tags",
        Default = true,
        Tooltip = "The player's name above the box.",
    })
    esp:CreateToggle({
        Name = "Display name",
        Show = {Option = "Name tags"},
        Default = true,
        Tooltip = "Show the display name rather than the account name.",
    })
    esp:CreateToggle({
        Name = "Health bar",
        Default = true,
        Tooltip = "Vertical bar on the left edge of the box.",
    })
    esp:CreateToggle({
        Name = "Health text",
        Default = false,
        Tooltip = "Print the exact hit points next to the name.",
    })
    esp:CreateToggle({
        Name = "Distance",
        Default = true,
        Tooltip = "Studs between you and the target.",
    })
    esp:CreateToggle({
        Name = "Held tool",
        Default = false,
        Tooltip = "Name of whatever the target currently has equipped.",
    })
    esp:CreateDropdown({
        Name = "Tracers",
        List = {"Off", "Bottom", "Centre", "Cursor"},
        Index = 1,
        Tooltip = "Where the line to each target starts.",
    })
    esp:CreateToggle({
        Name = "Team check",
        Default = false,
        Tooltip = "Skip players on your own team.",
    })
    esp:CreateToggle({
        Name = "Visibility check",
        Default = false,
        Tooltip = "Recolour targets that are behind geometry.",
    })
    esp:CreateSlider({
        Name = "Max distance",
        Min = 50,
        Max = 5000,
        Default = 2000,
    })

    esp:CreateColor({
        Name = "Colour",
        Default = Color3.fromRGB(255, 255, 255),
        Tooltip = "Used for every target the game gives no colour of its own.",
    })
    esp:CreateToggle({
        Name = "Team colours",
        Default = true,
        Tooltip = "Draw each player in their own team's colour where the game "
            .. "has teams.",
    })
    esp:CreateToggle({
        Name = "Name plate",
        Default = true,
        Tooltip = "Put the name on a dark plate so it stays readable against "
            .. "a bright map.",
    })
    esp:CreateSlider({
        Name = "Text size",
        Min = 8,
        Max = 24,
        Default = 13,
    })

    local extraRuntime: any = {
        roles = nil :: any,
        extras = {} :: {any},
    }
    Module.bridge = extraRuntime

    local function addRoleRows(provider: any): ()
        if extraRuntime.roles then
            return
        end
        extraRuntime.roles = provider

        for _, redundant: string in
            ipairs({"Team check", "Visibility check", "Team colours", "Colour"})
        do
            local row: any = esp.Options[redundant]
            if row then

                row.Show = {Option = "__roles", Values = {true}}
                pcall(function(): ()
                    row:SetVisible(false)
                    row.Visible = false
                end)
            end
        end
        esp:CreateToggle({
            Name = "Role colours",
            Default = true,
            Tooltip = "Colour every drawing by what the player is in this "
                .. "game instead of by team.",
        })
        esp:CreateToggle({
            Name = "Show role",
            Show = {Option = "Name tags"},
            Default = true,
            Tooltip = "Print the role next to the name.",
        })
        for _, roleName: string in ipairs(provider.Roles or {}) do
            esp:CreateColor({
                Name = roleName .. " colour",
                Default = (provider.Colors or {})[roleName]
                    or Color3.fromRGB(236, 236, 240),
                Function = function(value: Color3): ()

                    if type(provider.SetColor) == "function" then
                        pcall(provider.SetColor, roleName, value)
                    end
                end,
            })
        end
    end

    local function addExtraRows(extra: any): ()
        table.insert(extraRuntime.extras, extra)
        esp:CreateToggle({
            Name = extra.Name,
            Default = extra.Default == true,
            Tooltip = extra.Tooltip,
            Function = function(value: boolean): ()
                if type(extra.Toggle) == "function" then
                    pcall(extra.Toggle, value)
                end
            end,
        })
        if extra.Color then
            esp:CreateColor({
                Name = extra.Name .. " colour",
                Show = {Option = extra.Name},
                Default = extra.Color,
                Function = function(value: Color3): ()
                    if type(extra.SetColor) == "function" then
                        pcall(extra.SetColor, value)
                    end
                end,
            })
        end

        for _, definition: any in ipairs(extra.Options or {}) do
            local rowName: string = extra.Name .. " " .. definition.Name
            if definition.Kind == "toggle" then
                esp:CreateToggle({
                    Name = rowName,
                    Show = {Option = extra.Name},
                    Default = definition.Default == true,
                    Tooltip = definition.Tooltip,
                    Function = function(value: boolean): ()
                        if type(definition.Set) == "function" then
                            pcall(definition.Set, value)
                        end
                    end,
                })
            else
                esp:CreateSlider({
                    Name = rowName,
                    Show = {Option = extra.Name},
                    Min = definition.Min or 0,
                    Max = definition.Max or 100,
                    Default = definition.Default or definition.Min or 0,
                    Tooltip = definition.Tooltip,
                    Function = function(value: number): ()
                        if type(definition.Set) == "function" then
                            pcall(definition.Set, value)
                        end
                    end,
                })
            end
        end
    end

    local gameBridge: any = context.services.gameBridge
    if type(gameBridge.onEvent) == "function" then
        gameBridge.onEvent(function(kind: string, payload: any): ()
            if kind == "roles" then
                addRoleRows(payload)
            elseif kind == "extra" then
                addExtraRows(payload)
            end
        end)
    end

    activeCleanup = function(): ()
        render:ReleaseAll(container)
        table.clear(pool)
        container.Visible = false
    end
    Module.Initialized = true
    return esp
end

function Module.render(
    context: Runtime,
    container: Frame,
    pool: {[Player]: any},
    esp: any,
    visibilityCache: any
): ()
    local host: any = context.host
    local entityLibrary: any = context.entity
    local render: any = context.render
    local gameBridge: any = context.services.gameBridge
    local currentWorkspace: Workspace = host.workspace or workspace
    local camera: Camera? = currentWorkspace.CurrentCamera
    if not camera then
        return
    end
    local resolvedCamera: Camera = camera :: Camera
    local options: any = esp.Options
    local viewport: Vector2 = resolvedCamera.ViewportSize

    entityLibrary:Refresh()
    local seen: {[Player]: boolean} = {}

    for _, entity: any in ipairs(entityLibrary.List) do
        local player: Player = entity.Player
        if options["Team check"].Value and entity.IsFriendly then
            continue
        end
        if entity.Distance > options["Max distance"].Value then

            continue
        end

        local rect: any = render:ModelRect(resolvedCamera, entity.Character)

        -- Mark the player as seen before the rect check: a target that is
        -- momentarily behind the camera or off-screen must keep its pooled
        -- drawing (hidden) instead of being released and rebuilt every frame.
        seen[player] = true
        pool[player] = true
        local drawings: any = render:Set(container, player)

        if not rect then
            -- Behind the camera or fully outside the viewport: hide instead
            -- of leaving the previous frame's box frozen on screen.
            drawings:Show(false)
            continue
        end

        local visible: boolean = true
        if options["Visibility check"].Value then
            local cache: any = visibilityCache[player]
            local now: number = os.clock()
            if not cache or now - cache.at > 0.12 then
                cache = {at = now, value = entityLibrary:VisibleFrom(entity)}
                visibilityCache[player] = cache
            end
            visible = cache.value
        end
        local colour: Color3 = options["Colour"].Value

        local role: string? = nil
        if type(gameBridge.playerRole) == "function" then
            role = gameBridge.playerRole(player)
        end
        local roleOption: any = role and options[role .. " colour"] or nil
        local useRoleColour: boolean = roleOption ~= nil
            and options["Role colours"] ~= nil
            and options["Role colours"].Value == true
        if useRoleColour then
            colour = roleOption.Value
        end

        if not useRoleColour and options["Team colours"].Value and entity.Team then

            local teamOk: boolean, teamColour: any = pcall(function(): Color3
                return (entity.Team :: any).TeamColor.Color
            end)
            if teamOk and typeof(teamColour) == "Color3" then
                colour = teamColour
            end
        end

        if not visible then
            colour = colour:Lerp(Color3.new(0, 0, 0), 0.45)
        end

        local left: number = rect.left
        local top: number = rect.top
        local bottom: number = rect.bottom
        local height: number = rect.height
        local centreX: number = rect.centreX

        drawings:Show(true)

        local thickness: number = math.round(options["Box thickness"].Value)
        local boxMode: string = options["Boxes"].Value
        drawings:Fill(
            options["Filled box"].Value and boxMode ~= "Off" and rect or nil,
            colour,
            0.82
        )
        drawings:Box(rect, boxMode, thickness, colour)

        if options["Skeleton"].Value then
            local bones: {{BasePart}} = entityLibrary:Rig(entity)
            for index: number = 1, 14 do
                local pair: {BasePart}? = bones[index]
                local first: Vector2? = pair
                    and render:Project(resolvedCamera, pair[1].Position)
                local second: Vector2? = pair
                    and render:Project(resolvedCamera, pair[2].Position)
                if first and second then
                    drawings:Line(
                        "Bone",
                        index,
                        first :: Vector2,
                        second :: Vector2,
                        1,
                        colour
                    )
                else
                    drawings:HideLines("Bone", index, index)
                end
            end
        else
            drawings:HideLines("Bone", 1, 14)
        end

        if options["Health bar"].Value then
            drawings:Bar(
                Vector2.new(left - 4, top),
                height,
                entity.Health / math.max(entity.MaxHealth, 1)
            )
        else
            drawings:HideBar()
        end

        local textSize: number = math.round(options["Text size"].Value)
        if options["Name tags"].Value then
            local shown: string = options["Display name"].Value
                and player.DisplayName
                or player.Name
            drawings:Label(
                "NameTag",
                (role
                        and options["Show role"] ~= nil
                        and options["Show role"].Value)
                    and (shown .. "  [" .. (role :: string) .. "]")
                    or shown,
                Vector2.new(centreX, top - 3),
                1,
                textSize,
                colour,
                options["Name plate"].Value
            )
        else
            drawings:HideLabel("NameTag")
        end

        local details: {string} = {}
        if options["Distance"].Value then
            table.insert(details, tostring(math.round(entity.Distance)) .. "m")
        end
        if options["Health text"].Value then
            table.insert(
                details,
                tostring(math.round(entity.Health))
                    .. "/"
                    .. tostring(math.round(entity.MaxHealth))
            )
        end
        if options["Held tool"].Value then
            local tool: Instance? = entity.Character:FindFirstChildOfClass("Tool")
            if tool then
                table.insert(details, tool.Name)
            end
        end
        if #details > 0 then
            drawings:Label(
                "Details",
                table.concat(details, "  "),
                Vector2.new(centreX, bottom + 2),
                0,
                math.max(textSize - 2, 8),
                colour,
                options["Name plate"].Value
            )
        else
            drawings:HideLabel("Details")
        end

        local tracerMode: string = options["Tracers"].Value
        if tracerMode == "Off" then
            drawings:HideLines("Tracer", 1, 1)
        else
            local origin: Vector2
            if tracerMode == "Bottom" then
                origin = Vector2.new(viewport.X * 0.5, viewport.Y)
            elseif tracerMode == "Centre" then
                origin = viewport * 0.5
            else
                origin = host.UserInputService:GetMouseLocation()
            end
            drawings:Line(
                "Tracer",
                1,
                origin,
                Vector2.new(centreX, bottom),
                1,
                colour
            )
        end

    end

    for player: Player in pairs(pool) do
        if not seen[player] then
            render:Release(container, player)
            pool[player] = nil
        end
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/Chams.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Chams",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil
local activeBridgeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local entity: any = context.entity
    local host: any = context.host
    local protectedTargets: any = context.services.protectedTargets
    local currentWorkspace: Workspace = host.workspace or workspace
    local highlights: {[Player]: Highlight} = {}
    local lastUpdate: number = -math.huge
    local gameBridge: any = context.services.gameBridge
    if activeBridgeCleanup then
        pcall(activeBridgeCleanup)
        activeBridgeCleanup = nil
    end
    if type(gameBridge.onEvent) == "function" then
        activeBridgeCleanup = gameBridge.onEvent(function(kind: string): ()
            if kind == "roleUpdate" then
                -- Role assignment bypasses the regular 0.2 s work throttle;
                -- the next rendered frame recolours every existing highlight.
                lastUpdate = -math.huge
            end
        end)
    end

    local store: any = host.configData
    if store and store.values and store.states then
        local oldMode: any = store.values["Universal.PlayerESP.Chams"]
        if store.states["Universal.Chams"] == nil
            and (oldMode == "Overlay" or oldMode == "Outline") then
            store.states["Universal.Chams"] = true
            local fillKey: string = "Universal.Chams.Filltransparency"
            if store.values[fillKey] == nil then
                store.values[fillKey] = oldMode == "Outline" and 1 or 0.55
            end
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
        end
    end

    local card: any
    local function clear(): ()
        for player: Player, highlight: Highlight in pairs(highlights) do
            highlights[player] = nil
            highlight:Destroy()
        end
    end

    card = framework.Categories.Visuals:CreateModule({
        Name = "Chams",
        Category = "Render",
        ConfigKey = "Universal.Chams",
        Order = 2,
        Tooltip = "Highlights live players, optionally through walls.",
        Function = function(enabled: boolean): ()
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            card:SetStatus("0")
            card:Render(function(): ()
                local now: number = os.clock()
                if now - lastUpdate < 0.2 then return end
                lastUpdate = now
                local seen: {[Player]: boolean} = {}
                local count: number = 0
                for _, target: any in ipairs(entity:Refresh()) do
                    local player: Player = target.Player
                    local allowedTeam: boolean = card.Options["Teammates"].Value
                        or not target.IsFriendly
                    local protected: boolean = protectedTargets.isProtected(player)
                    if allowedTeam and not protected
                        and target.Character
                        and target.Humanoid
                        and target.Humanoid.Health > 0 then
                        seen[player] = true
                        count += 1
                        local highlight: Highlight? = highlights[player]
                        if not highlight or not highlight.Parent then
                            highlight = Instance.new("Highlight")
                            highlight.Name = "Wurst_Chams"
                            highlight.Parent = currentWorkspace
                            highlights[player] = highlight
                        end
                        local resolved: Highlight = highlight :: Highlight
                        local roleColour: Color3? = nil
                        if type(gameBridge.playerRoleColor) == "function" then
                            roleColour = gameBridge.playerRoleColor(player)
                        end
                        -- Without a role the chams used to fall straight back
                        -- to white, which is exactly what made an undetected
                        -- MM2 innocent look like "no cham at all". Team colour
                        -- is a far better guess than white.
                        local teamColour: Color3? = nil
                        local teamOption: any = card.Options["Team colours"]
                        if not roleColour
                            and teamOption ~= nil
                            and teamOption.Value == true
                            and target.Team then
                            local ok: boolean, resolved: any = pcall(function(): any
                                return target.Team.TeamColor.Color
                            end)
                            if ok and typeof(resolved) == "Color3" then
                                teamColour = resolved
                            end
                        end
                        local fillColour: Color3 = roleColour
                            or teamColour
                            or card.Options["Fill colour"].Value
                        local outlineColour: Color3 = roleColour
                            or teamColour
                            or card.Options["Outline colour"].Value
                        local fillTransparency: number = card.Options["Fill transparency"].Value
                        local outlineTransparency: number = card.Options["Outline transparency"].Value
                        local depthMode: Enum.HighlightDepthMode = card.Options["Through walls"].Value
                                and Enum.HighlightDepthMode.AlwaysOnTop
                            or Enum.HighlightDepthMode.Occluded
                        if resolved.Adornee ~= target.Character then resolved.Adornee = target.Character end
                        if resolved.FillColor ~= fillColour then resolved.FillColor = fillColour end
                        if resolved.OutlineColor ~= outlineColour then resolved.OutlineColor = outlineColour end
                        if resolved.FillTransparency ~= fillTransparency then resolved.FillTransparency = fillTransparency end
                        if resolved.OutlineTransparency ~= outlineTransparency then resolved.OutlineTransparency = outlineTransparency end
                        if resolved.DepthMode ~= depthMode then resolved.DepthMode = depthMode end
                    end
                end
                for player: Player, highlight: Highlight in pairs(highlights) do
                    if not seen[player] then
                        highlights[player] = nil
                        highlight:Destroy()
                    end
                end
                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateColor({Name = "Fill colour", Default = Color3.fromRGB(150, 230, 255)})
    card:CreateColor({Name = "Outline colour", Default = Color3.fromRGB(235, 250, 255)})
    card:CreateSlider({Name = "Fill transparency", Min = 0, Max = 1, Step = 0.05, Default = 0.55})
    card:CreateSlider({Name = "Outline transparency", Min = 0, Max = 1, Step = 0.05, Default = 0})
    card:CreateToggle({Name = "Through walls", Default = true})
    card:CreateToggle({Name = "Teammates", Default = false})
    card:CreateToggle({Name = "Team colours", Default = true})

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    if activeBridgeCleanup then
        pcall(activeBridgeCleanup)
        activeBridgeCleanup = nil
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/Arrows.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    render: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Arrows",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local entity: any = context.entity
    local render: any = context.render
    local protectedTargets: any = context.services.protectedTargets
    local currentWorkspace: Workspace = context.host.workspace or workspace
    local layer: Frame = render:Layer("ArrowsLayer")
    local shown: {[Player]: boolean} = {}

    local card: any
    local function clear(): ()
        render:ReleaseAll(layer)
        table.clear(shown)
        layer.Visible = false
    end

    card = framework.Categories.Visuals:CreateModule({
        Name = "Arrows",
        Category = "Render",
        ConfigKey = "Universal.Arrows",
        Order = 3,
        Tooltip = "Points toward players outside the camera view.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            card:Render(function(): ()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not camera then
                    render:ReleaseAll(layer)
                    table.clear(shown)
                    return
                end
                local viewport: Vector2 = camera.ViewportSize
                local centre: Vector2 = Vector2.new(viewport.X / 2, viewport.Y / 2)
                local radius: number = math.max(40, math.min(viewport.X, viewport.Y) * 0.4)
                local seen: {[Player]: boolean} = {}
                local count: number = 0
                for _, target: any in ipairs(entity:Refresh()) do
                    local player: Player = target.Player
                    if (not card.Options["Teammates"].Value and target.IsFriendly)
                        or protectedTargets.isProtected(player)
                        or not target.Humanoid
                        or target.Humanoid.Health <= 0
                        or not target.RootPart
                        or target.Distance > card.Options["Max distance"].Value then
                        render:Release(layer, player)
                        continue
                    end
                    local projected: Vector3, onScreen: boolean =
                        camera:WorldToViewportPoint(target.RootPart.Position)
                    if onScreen then
                        render:Release(layer, player)
                        continue
                    end
                    local drawing: any = render:Set(layer, player)
                    local delta: Vector2 = Vector2.new(projected.X, projected.Y) - centre
                    if projected.Z < 0 then
                        delta = Vector2.new(-delta.X, -delta.Y)
                    end
                    if delta.Magnitude < 0.001 then
                        delta = Vector2.new(0, -1)
                    end
                    local direction: Vector2 = delta.Unit
                    local perpendicular: Vector2 = Vector2.new(-direction.Y, direction.X)
                    local tip: Vector2 = centre + direction * radius
                    local back: Vector2 = tip - direction * 16
                    local colour: Color3 = card.Options["Colour"].Value
                    drawing:Line("Arrow", 1, tip, back + perpendicular * 8, 2, colour)
                    drawing:Line("Arrow", 2, tip, back - perpendicular * 8, 2, colour)
                    drawing:HideLines("Arrow", 3, 8)
                    if card.Options["Distance"].Value then
                        drawing:Label(
                            "Distance",
                            tostring(math.round(target.Distance)) .. "m",
                            tip - direction * 26,
                            0.5,
                            12,
                            colour,
                            true
                        )
                    else
                        drawing:HideLabel("Distance")
                    end
                    drawing:Show(true)
                    seen[player] = true
                    count += 1
                end
                for player: Player in pairs(shown) do
                    if not seen[player] then
                        render:Release(layer, player)
                    end
                end
                shown = seen
                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateColor({Name = "Colour", Default = Color3.fromRGB(0, 204, 255)})
    card:CreateToggle({Name = "Distance", Default = true})
    card:CreateSlider({Name = "Max distance", Min = 25, Max = 2000, Step = 25, Default = 500})
    card:CreateToggle({Name = "Teammates", Default = false})

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/NPCESP.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    render: any,
    host: any,
    services: any,
}

local Module = {
    Name = "NPCESP",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

-- Normalized names of the parts every R6/R15 character rig is built from.
-- Character-shaped models (including display statues of players) are built
-- from these; random props and creature rigs are not.
local STANDARD_PART_NAMES: {[string]: boolean} = {
    head = true,
    torso = true,
    uppertorso = true,
    lowertorso = true,
    humanoidrootpart = true,
    leftarm = true,
    rightarm = true,
    leftleg = true,
    rightleg = true,
    leftupperarm = true,
    leftlowerarm = true,
    lefthand = true,
    rightupperarm = true,
    rightlowerarm = true,
    righthand = true,
    leftupperleg = true,
    leftlowerleg = true,
    leftfoot = true,
    rightupperleg = true,
    rightlowerleg = true,
    rightfoot = true,
}

-- A model re-classified more often than this keeps its previous verdict until
-- the burst of changes settles, so a streaming model never turns
-- reclassification into a per-frame cost.
local VERDICT_COOLDOWN: number = 0.5

local function normalizeName(value: string): string
    local normalized: string = string.lower(value):gsub("[%s_%-]", "")
    return normalized
end

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local render: any = context.render
    local host: any = context.host
    local players: Players = host.Players
    local currentWorkspace: Workspace = host.workspace or workspace
    local layer: Frame = render:Layer("NpcEspLayer")
    local lastStatusAt: number = -math.huge
    local lastSweepAt: number = -math.huge

    -- Tracked models, their resolved root/humanoid, and the structural
    -- verdict per model: "rig" is a character-shaped model (with or without
    -- a living Humanoid — display statues count), "creature" merely carries a
    -- Humanoid, "reject" is neither. Verdicts and rig info are weak so
    -- destroyed models never leak, and both are only recomputed when the
    -- model's direct children actually change.
    local bots: {[Model]: boolean} = {}
    local rigInfo: any = setmetatable({}, {__mode = "k"})
    local verdicts: any = setmetatable({}, {__mode = "k"})
    local forcedNames: {string} = {}

    local function modelFor(instance: Instance): Model?
        if instance:IsA("Model") then
            return instance :: Model
        end
        return instance:FindFirstAncestorOfClass("Model") :: Model?
    end

    local function isPlayerCharacterModel(model: Model): boolean
        if players:GetPlayerFromCharacter(model) ~= nil then
            return true
        end
        for _, player: Player in ipairs(players:GetPlayers()) do
            local character: Model? = player.Character
            if character and model:IsDescendantOf(character) then
                return true
            end
        end
        return false
    end

    local function matchesForcedName(model: Model): boolean
        local name: string = string.lower(model.Name)
        for _, needle: string in ipairs(forcedNames) do
            if needle ~= "" and string.find(name, needle, 1, true) then
                return true
            end
        end
        return false
    end

    -- Classification only inspects direct children, which is what a character
    -- rig is made of, so even huge models cost one GetChildren call.
    local function classify(model: Model): string
        -- The local Disguise body double is scenery, not an NPC.
        if model:GetAttribute("WurstDisguise") == true then
            return "reject"
        end
        if matchesForcedName(model) then
            return "rig"
        end
        local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local standardParts: number = 0
        local motors: number = 0
        for _, child: Instance in ipairs(model:GetChildren()) do
            if child:IsA("BasePart") then
                if STANDARD_PART_NAMES[normalizeName(child.Name)] then
                    standardParts += 1
                end
            elseif child:IsA("Motor6D") then
                motors += 1
            end
        end
        if humanoid ~= nil then
            -- A character model is still a character model when its Humanoid
            -- is dead or purely decorative; health never gates detection.
            if standardParts >= 3 then
                return "rig"
            end
            return "creature"
        end
        -- Humanoid-less character structures: display rigs and statues keep
        -- the standard limbs (and usually their Motor6D joints).
        if standardParts >= 4 or (standardParts >= 3 and motors >= 2) then
            return "rig"
        end
        if model:FindFirstChildWhichIsA("Humanoid", true) ~= nil then
            return "creature"
        end
        return "reject"
    end

    local function verdictFor(model: Model): string
        local entry: any = verdicts[model]
        if entry == nil then
            entry = {
                verdict = isPlayerCharacterModel(model) and "reject" or classify(model),
                at = os.clock(),
                dirty = false,
            }
            verdicts[model] = entry
            return entry.verdict
        end
        if entry.dirty then
            local now: number = os.clock()
            if now - entry.at >= VERDICT_COOLDOWN then
                entry.verdict =
                    isPlayerCharacterModel(model) and "reject" or classify(model)
                entry.at = now
                entry.dirty = false
            end
        end
        return entry.verdict
    end

    local function markDirty(model: Model): ()
        local entry: any = verdicts[model]
        if entry and not entry.dirty then
            entry.dirty = true
        end
        rigInfo[model] = nil
    end

    -- Only the model whose direct children changed needs a fresh look.
    local function invalidate(instance: Instance): ()
        local parent: Instance? = instance.Parent
        if parent and parent:IsA("Model") then
            markDirty(parent :: Model)
        end
        if instance:IsA("Model") then
            markDirty(instance :: Model)
        end
    end

    local function add(model: Model, verdict: string): ()
        if verdict ~= "rig" then
            bots[model] = true
            return
        end
        -- Prefer the innermost rig so a rig nested inside a wrapper never
        -- draws two boxes.
        for existing: Model in pairs(bots) do
            if existing:IsDescendantOf(model) then
                return
            end
            if model:IsDescendantOf(existing) then
                bots[existing] = nil
                render:Release(layer, existing)
            end
        end
        bots[model] = true
    end

    local function inspect(instance: Instance): ()
        if not (instance:IsA("Model") or instance:IsA("Humanoid")
            or instance:IsA("BasePart") or instance:IsA("Motor6D")) then
            return
        end
        invalidate(instance)
        local model: Model? = modelFor(instance)
        local creature: Model? = nil
        while model and model ~= currentWorkspace do
            local verdict: string = verdictFor(model)
            if verdict == "rig" then
                add(model, "rig")
                return
            end
            if verdict == "creature" and creature == nil then
                creature = model
            end
            local parent: Instance? = model.Parent
            if not parent then
                break
            end
            model = parent:IsA("Model") and parent :: Model
                or parent:FindFirstAncestorOfClass("Model") :: Model?
        end
        if creature then
            add(creature, "creature")
        end
    end

    -- Models stream in over time; a dirty verdict that no further event
    -- refreshes is settled here so nothing stays undetected.
    local function sweep(now: number): ()
        for model: any, entry: any in pairs(verdicts) do
            if entry.dirty and now - entry.at >= VERDICT_COOLDOWN then
                local resolved: Model = model :: Model
                local verdict: string =
                    isPlayerCharacterModel(resolved) and "reject" or classify(resolved)
                entry.verdict = verdict
                entry.at = now
                entry.dirty = false
                if verdict == "rig" then
                    add(resolved, "rig")
                end
            end
        end
    end

    local function scan(): ()
        table.clear(bots)
        for _, object: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if object:IsA("Model") then
                inspect(object)
            end
        end
    end

    local function clear(): ()
        render:ReleaseAll(layer)
        table.clear(bots)
        layer.Visible = false
    end

    local card: any
    card = framework.Categories.Visuals:CreateModule({
        Name = "NPCESP",
        Category = "Render",
        ConfigKey = "Universal.NPCESP",
        Order = 4,
        Tooltip = "Displays character-shaped NPC models - bots, shopkeepers "
            .. "and display statues like the creator's rig - whether or not "
            .. "their Humanoid is alive.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            scan()
            card:Event(currentWorkspace.DescendantAdded, inspect)
            card:Event(currentWorkspace.DescendantRemoving, invalidate)
            card:Render(function(): ()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not camera then
                    return
                end
                local resolvedCamera: Camera = camera :: Camera
                local now: number = os.clock()
                if now - lastSweepAt >= 1 then
                    lastSweepAt = now
                    sweep(now)
                end

                local maxDistance: number = card.Options["Max distance"].Value
                local includeCreatures: boolean = card.Options["All humanoids"].Value
                local localCharacter: Model? = host.LocalPlayer.Character
                local localRoot: BasePart? = localCharacter and (
                    localCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
                    or localCharacter.PrimaryPart
                    or localCharacter:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
                ) or nil
                local origin: Vector3 = localRoot and localRoot.Position
                    or resolvedCamera.CFrame.Position
                local count: number = 0
                for model: Model in pairs(bots) do
                    if not model:IsDescendantOf(currentWorkspace)
                        or players:GetPlayerFromCharacter(model) ~= nil then
                        bots[model] = nil
                        render:Release(layer, model)
                        -- The model turned out to be a player character; pin
                        -- the verdict so streaming parts do not re-add it.
                        verdicts[model] = {verdict = "reject", at = now, dirty = false}
                        continue
                    end
                    local verdict: string = verdictFor(model)
                    if verdict == "reject" then
                        bots[model] = nil
                        render:Release(layer, model)
                        continue
                    end

                    if verdict == "creature" and not includeCreatures then
                        -- Not tracked right now; make sure nothing is left
                        -- over from a previous frame and move on.
                        render:Release(layer, model)
                        continue
                    end

                    local drawing: any = render:Set(layer, model)

                    local info: any = rigInfo[model]
                    if not (info and info.root and info.root.Parent) then
                        info = {
                            root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
                                or model.PrimaryPart
                                or model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?,
                            humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
                                or model:FindFirstChildWhichIsA("Humanoid", true) :: Humanoid?,
                        }
                        rigInfo[model] = info
                    end
                    local root: BasePart? = info.root
                    if not root or (root.Position - origin).Magnitude > maxDistance then
                        drawing:Show(false)
                        continue
                    end
                    -- Creatures are living things, so a dead one stops
                    -- counting; character rigs stay visible whatever their
                    -- Humanoid says.
                    if verdict == "creature"
                        and info.humanoid
                        and info.humanoid.Health <= 0 then
                        drawing:Show(false)
                        continue
                    end

                    local rect: any = render:ModelRect(resolvedCamera, model)
                    if not rect then
                        drawing:Show(false)
                        continue
                    end

                    local colour: Color3 = card.Options["Colour"].Value
                    drawing:Box(rect, card.Options["Box"].Value and "Full" or "Off", 1, colour)
                    if card.Options["Name"].Value then
                        local text: string = card.Options["Model name"].Value
                            and model.Name ~= "" and model.Name
                            or "BOT"
                        local humanoid: Humanoid? = info.humanoid
                        if humanoid and card.Options["Health"].Value then
                            text ..= " [" .. tostring(math.round(humanoid.Health)) .. "]"
                        end
                        drawing:Label(
                            "NameTag",
                            text,
                            Vector2.new(rect.centreX, rect.top - 4),
                            1,
                            13,
                            colour,
                            true
                        )
                    else
                        drawing:HideLabel("NameTag")
                    end
                    drawing:Highlight(
                        model,
                        colour,
                        0.55,
                        not card.Options["Highlight"].Value and "Off"
                            or (card.Options["Through walls"].Value and "AlwaysOnTop" or "Occluded")
                    )
                    drawing:Show(true)
                    count += 1
                end

                if now - lastStatusAt >= 0.25 then
                    lastStatusAt = now
                    card:SetStatus(tostring(count))
                end
            end)
            card:Clean(clear)
        end,
    })

    card:CreateToggle({Name = "Box", Default = true})
    card:CreateToggle({Name = "Highlight", Default = true})
    card:CreateToggle({Name = "Through walls", Default = true, Show = {Option = "Highlight"}})
    card:CreateToggle({Name = "Name", Default = true})
    card:CreateToggle({
        Name = "Model name",
        Show = {Option = "Name"},
        Default = false,
        Tooltip = "Label each model with its own name instead of BOT.",
    })
    card:CreateToggle({
        Name = "Health",
        Show = {Option = "Name"},
        Default = true,
        Tooltip = "Append the Humanoid's hit points to the label when the "
            .. "model has one.",
    })
    card:CreateToggle({
        Name = "All humanoids",
        Default = false,
        Tooltip = "Also flag non-character models that merely carry a living "
            .. "Humanoid (creatures, monsters). Off by default: NPCESP tracks "
            .. "character-shaped rigs.",
    })
    card:CreateColor({Name = "Colour", Default = Color3.new(1, 1, 1)})
    card:CreateSlider({Name = "Max distance", Min = 25, Max = 2000, Step = 25, Default = 500})

    local addBox: any
    addBox = card:CreateTextBox({
        Name = "Force by name",
        Default = "",
        Tooltip = "Type a model name and it is always treated as an NPC rig, "
            .. "whatever it is built from. Partial names match, so statue "
            .. "catches CreatorStatue.",
        Function = function(value: string): ()
            local trimmed: string = string.match(value, "^%s*(.-)%s*$") or value
            if trimmed == "" then
                return
            end
            local needle: string = string.lower(trimmed)
            if not table.find(forcedNames, needle) then
                table.insert(forcedNames, needle)
            end
            table.clear(verdicts)
            table.clear(rigInfo)
            if card.Enabled then
                scan()
            end
            addBox:Set("")
        end,
    })

    card:CreateButton({
        Name = "Clear forced names",
        Function = function(): ()
            table.clear(forcedNames)
            table.clear(verdicts)
            table.clear(rigInfo)
            if card.Enabled then
                scan()
            end
        end,
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Combat/KillAura.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "KillAura",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function collectTools(localPlayer: Player): {Tool}
    local tools: {Tool} = {}
    local character: Model? = localPlayer.Character
    if character then
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(tools, child :: Tool)
            end
        end
    end
    local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, child: Instance in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(tools, child :: Tool)
            end
        end
    end
    return tools
end

local function toolHandle(tool: Tool?): BasePart?
    if not tool then
        return nil
    end
    local resolved: Tool = tool :: Tool
    local handle: Instance? = resolved:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        return handle :: BasePart
    end

    for _, descendant: Instance in ipairs(resolved:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant :: BasePart
        end
    end
    return nil
end

local function activateTool(tool: Tool?): ()
    if not tool then
        return
    end
    pcall(function(): ()
        tool:Activate()
    end)
end

local function fireContact(handle: BasePart?, target: BasePart): ()
    if not handle then
        return
    end
    local environment: any = getfenv()
    local fire: any = environment.firetouchinterest
    if type(fire) ~= "function" then
        return
    end

    pcall(fire, handle, target, 1)
    pcall(fire, handle, target, 0)
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local entityLibrary: any = context.entity
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace

    local nextSwingAt: number = 0
    local nextStatusAt: number = 0
    local highlights: {[any]: Highlight} = {}

    local function clearHighlights(keep: {[any]: boolean}?): ()
        for key: any, highlight: Highlight in pairs(highlights) do
            if not keep or not keep[key] then
                pcall(function(): ()
                    highlight:Destroy()
                end)
                highlights[key] = nil
            end
        end
    end

    local function markTarget(entity: any, options: any): ()
        if not options["Highlight targets"].Value then
            return
        end
        local key: any = entity.Player or entity.Character
        local existing: Highlight? = highlights[key]
        if not existing or not existing.Parent then
            local created: Highlight = Instance.new("Highlight")
            created.Name = "Wurst_KillAuraTarget"
            created.FillTransparency = 0.75
            created.Parent = entity.Character
            highlights[key] = created
            existing = created
        end
        local highlight: Highlight = existing :: Highlight
        highlight.Adornee = entity.Character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        local colour: Color3 = options["Highlight colour"].Value
        highlight.FillColor = colour
        highlight.OutlineColor = colour
    end

    local aura: any = nil
    local weapons: any = context.weapons

    local function updateTargetStatus(count: number): ()
        local now: number = os.clock()
        if now < nextStatusAt then
            return
        end
        nextStatusAt = now + 0.25
        aura:SetStatus(tostring(count) .. " in range")
    end

    local learnedWeapon: string? = nil
    local learnConnections: {RBXScriptConnection} = {}

    local function watchTool(tool: Tool): ()
        table.insert(
            learnConnections,
            tool.Activated:Connect(function(): ()
                learnedWeapon = tool.Name
            end)
        )
    end

    local function watchAllTools(): ()
        for _, connection: RBXScriptConnection in ipairs(learnConnections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        learnConnections = {}
        for _, tool: Tool in ipairs(collectTools(localPlayer)) do
            watchTool(tool)
        end
    end

    local function matchesWanted(tool: Tool, wanted: string): boolean
        return string.find(string.lower(tool.Name), string.lower(wanted), 1, true) ~= nil
    end

    local function equippedTool(): (Tool?, BasePart?)
        local character: Model? = localPlayer.Character
        if not character then
            return nil, nil
        end
        local wanted: string = tostring(aura.Options["Weapon name"].Value or "")
        local held: {Tool} = {}
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(held, child :: Tool)
            end
        end

        if wanted ~= "" then
            for _, tool: Tool in ipairs(held) do
                if matchesWanted(tool, wanted) then
                    return tool, toolHandle(tool)
                end
            end
        end
        if learnedWeapon then
            for _, tool: Tool in ipairs(held) do
                if tool.Name == learnedWeapon then
                    return tool, toolHandle(tool)
                end
            end
        end
        local first: Tool? = held[1]
        return first, toolHandle(first)
    end

    local function equipFromBackpack(): ()
        local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
        local humanoid: Humanoid? = localPlayer.Character
            and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not backpack or not humanoid then
            return
        end
        local wanted: string = tostring(aura.Options["Weapon name"].Value or "")
        local chosen: Tool? = nil
        for _, child: Instance in ipairs(backpack:GetChildren()) do
            if not child:IsA("Tool") then
                continue
            end
            local tool: Tool = child :: Tool
            if wanted ~= "" and matchesWanted(tool, wanted) then
                chosen = tool
                break
            end
            if learnedWeapon and tool.Name == learnedWeapon then
                chosen = tool
                break
            end
            if not chosen then
                chosen = tool
            end
        end
        if chosen then
            pcall(function(): ()
                humanoid:EquipTool(chosen :: Tool)
            end)
        end
    end

    local store: any = host.configData
    if store and store.values then
        local reachKey: string = "Universal.KillAura.Reach"
        local stored: any = store.values["Universal.KillAura.Swingrange"]
        if store.values[reachKey] == nil and type(stored) == "number" then
            store.values[reachKey] = stored
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
        end
    end

    aura = framework.Categories.Combat:CreateModule({
        Name = "Killaura",
        Category = "Combat",
        ConfigKey = "Universal.KillAura",
        Order = 1,
        Tooltip = "Swings your weapon at everyone in reach, with its own "
            .. "range, rate, field of view and rotation.",
        Function = function(enabled: boolean): ()
            nextSwingAt = 0
            nextStatusAt = 0
            if not enabled then
                aura:SetStatus(nil)
                clearHighlights()
                return
            end
            aura:SetStatus("0 in range")

            aura:Clean(function(): ()
                clearHighlights()
            end)

            watchAllTools()
            aura:Event(localPlayer.CharacterAdded, function(): ()
                task.defer(watchAllTools)
            end)
            local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
            if backpack then
                aura:Event(backpack.ChildAdded, function(child: Instance): ()
                    if child:IsA("Tool") then
                        watchTool(child :: Tool)
                    end
                end)
            end
            aura:Clean(function(): ()
                for _, connection: RBXScriptConnection in ipairs(learnConnections) do
                    pcall(function(): ()
                        connection:Disconnect()
                    end)
                end
                learnConnections = {}
            end)

            aura:Loop(function(): ()
                local options: any = aura.Options
                if options["Activation"].Value == "Hold key"
                    and not userInput:IsKeyDown(options["Hold key"].Value) then
                    updateTargetStatus(0)
                    clearHighlights()
                    return
                end
                if not entityLibrary:IsAlive() then
                    updateTargetStatus(0)
                    clearHighlights()
                    return
                end

                local tool: Tool?, handle: BasePart? = equippedTool()
                if not tool then
                    if options["Auto equip"].Value then
                        equipFromBackpack()
                    end
                    if options["Require tool"].Value then

                        updateTargetStatus(0)
                        clearHighlights()
                        return
                    end
                end

                entityLibrary:Refresh()
                local targets: {any} = entityLibrary:InRange({
                    Range = options["Reach"].Value,
                    Limit = math.round(options["Max targets"].Value),
                    IgnoreTeam = not options["Team check"].Value,
                    IgnoreWalls = not options["Wall check"].Value,
                    Angle = options["Field of view"].Value,
                    IncludeNPCs = options["Target NPCs"].Value,
                    Sort = options["Priority"].Value,
                })
                updateTargetStatus(#targets)
                if #targets == 0 then
                    clearHighlights()
                    return
                end
                local now: number = os.clock()
                local rate: number = math.max(options["Swings per second"].Value, 0.5)

                local jitter: number = 1 / rate * 0.25
                local canSwing: boolean = now >= nextSwingAt
                local keep: {[any]: boolean} = {}

                local root: BasePart? = entityLibrary.LocalEntity
                    and entityLibrary.LocalEntity.RootPart
                local rotation: string = options["Rotation"].Value
                local originalCFrame: CFrame? = root and root.CFrame or nil

                if canSwing then

                    nextSwingAt = now
                        + (1 / rate)
                        + (math.random() - 0.5) * 2 * jitter
                end

                if rotation ~= "Off" and root then
                    local first: any = targets[1]
                    local flat: Vector3 = first.RootPart.Position
                        * Vector3.new(1, 0, 1)
                    root.CFrame = CFrame.lookAt(
                        root.Position,
                        Vector3.new(flat.X, root.Position.Y + 0.01, flat.Z)
                    )
                end

                for _, entity: any in ipairs(targets) do
                    keep[entity.Player or entity.Character] = true
                    markTarget(entity, options)

                    if not canSwing then
                        continue
                    end

                    local swung: boolean = false
                    if weapons then
                        for _, label: string in ipairs(aura.Options["Weapons"].Selected or {}) do
                            local candidate: any = weapons:Find(label)

                        if candidate and weapons:Activate(candidate, entity) then
                                swung = true
                            end
                        end
                    end
                    if not swung and tool then
                        activateTool(tool)
                        swung = true
                    end
                    if not swung and weapons then

                        local fallback: any = weapons:Best({Melee = true})
                        swung = fallback ~= nil and weapons:Activate(fallback, entity)
                    end

                    local extraHits: number =
                        math.max(math.round(options["Hits per swing"].Value) - 1, 0)
                    for _ = 1, extraHits do
                        if tool then
                            activateTool(tool)
                        elseif weapons then
                            weapons:Swing()
                        end
                    end
                    if not options["Contact damage"].Value then

                        continue
                    end

                    if not options["Hit through walls"].Value
                        and not entityLibrary:VisibleFrom(entity) then
                        continue
                    end

                    local overlap: OverlapParams = OverlapParams.new()
                    overlap.FilterType = Enum.RaycastFilterType.Include
                    overlap.FilterDescendantsInstances = {entity.Character}
                    local parts: {BasePart} = currentWorkspace:GetPartBoundsInBox(
                        entity.RootPart.CFrame,
                        Vector3.new(5, 6, 5),
                        overlap
                    )
                    for _, part: BasePart in ipairs(parts) do
                        fireContact(handle, part)
                    end
                end

                if rotation == "Silent" and root and originalCFrame then
                    root.CFrame = originalCFrame :: CFrame
                end

                clearHighlights(keep)
            end)
        end,
    })

    aura:CreateList({
        Name = "Weapons",
        Items = function(): {string}
            if not weapons then
                return {}
            end
            return weapons:Labels({All = true, Melee = true})
        end,

        EmptyText = "",
        Tooltip = "Melee weapons this module may swing: tools, view models, "
            .. "inventory slots and the game's own attack button. Empty means "
            .. "whatever you are holding.",
    })
    aura:CreateTextBox({
        Name = "Weapon name",
        Default = "",
        Tooltip = "Part of the tool's name. Leave empty and the module uses "
            .. "whatever you last swung by hand.",
    })
    aura:CreateButton({
        Name = "Bind held tool",
        Tooltip = "Remembers whatever is in your hands right now.",
        Function = function(): ()
            local tool: Tool? = equippedTool()
            if not tool then
                aura:Notify("nothing equipped")
                return
            end
            learnedWeapon = (tool :: Tool).Name
            aura:Notify((tool :: Tool).Name .. " bound")
        end,
    })
    aura:CreateSlider({
        Name = "Reach",
        Min = 5,
        Max = 60,
        Default = 18,
        Tooltip = "Distance at which the weapon swings and its touch events "
            .. "fire. This is the only Kill Aura distance.",
    })
    aura:CreateSlider({
        Name = "Max targets",
        Min = 1,
        Max = 10,
        Default = 3,
        Tooltip = "How many valid players or NPCs one swing may hit. One "
            .. "sticks to the best target.",
    })
    aura:CreateDropdown({
        Name = "Priority",
        List = {"Distance", "Health", "Threat"},
        Index = 1,
        Tooltip = "Which target comes first: nearest, weakest, or the one "
            .. "most dangerous to you.",
    })
    aura:CreateSlider({
        Name = "Swings per second",
        Min = 1,
        Max = 20,
        Default = 8,
        Tooltip = "A fast human clicks about 8-12 times a second. Twenty is "
            .. "not a person, and a server that logs click rates knows it.",
    })

    aura:CreateDropdown({
        Name = "Activation",
        List = {"Always", "Hold key"},
        Index = 1,
    })
    aura:CreateBind({
        Name = "Hold key",
        Show = {Option = "Activation", Values = {"Hold key"}},
        Default = Enum.KeyCode.Unknown,
    })
    aura:CreateSlider({
        Name = "Field of view",
        Min = 30,
        Max = 360,
        Default = 360,
        Tooltip = "Degrees around your character. 360 scans every direction; "
            .. "this is not cursor aim.",
    })
    aura:CreateDropdown({
        Name = "Rotation",
        List = {"Off", "Silent", "Face"},
        Index = 2,
        Tooltip = "Silent turns you for the swing only and puts you back; "
            .. "Face keeps you pointed at the target.",
    })
    aura:CreateSlider({
        Name = "Hits per swing",
        Min = 1,
        Max = 8,
        Default = 1,
        Tooltip = "How many times the weapon is pressed for each swing the "
            .. "rate allows. Some games count every press.",
    })
    aura:CreateToggle({
        Name = "Hit through walls",
        Default = true,
        Tooltip = "Fire contact damage even when the target is behind "
            .. "geometry. Independent of the wall check, which decides "
            .. "whether the target is picked at all.",
    })
    aura:CreateToggle({
        Name = "Contact damage",
        Default = true,
        Tooltip = "Also fire the weapon's touch events. Needed by most melee "
            .. "weapons; requires firetouchinterest.",
    })
    aura:CreateToggle({
        Name = "Wall check",
        Default = false,
        Tooltip = "Off by default: the aura hits through walls and floors "
            .. "until you ask it not to.",
    })
    aura:CreateToggle({
        Name = "Team check",
        Default = true,
        Tooltip = "Skip teammates and Friend List entries.",
    })
    aura:CreateToggle({
        Name = "Target NPCs",
        Default = false,
        Tooltip = "Include non-player humanoid models in the reach scan.",
    })
    aura:CreateToggle({
        Name = "Require tool",
        Default = false,
        Tooltip = "Do nothing while your hands are empty.",
    })
    aura:CreateToggle({
        Name = "Auto equip",
        Default = false,
        Tooltip = "Pull the weapon out of the backpack when empty-handed. Off "
            .. "by default: most games this module helps in do not need "
            .. "anything in your hands at all.",
        Function = function(value: boolean): ()
            if weapons then
                weapons:SetAllowEquip(value)
            end
        end,
    })
    aura:CreateToggle({
        Name = "Highlight targets",
        Default = false,
    })
    aura:CreateColor({
        Name = "Highlight colour",
        Show = {Option = "Highlight targets"},
        Default = Color3.fromRGB(235, 110, 110),
    })

    aura:CreateNote(
        "Safe band: 8-12 swings a second and a reach close to the weapon's "
            .. "own. Reach is the only distance this card reads; there is no "
            .. "second, longer one. Friend List protects players from this "
            .. "module in every game."
    )

    activeCleanup = function(): ()
        clearHighlights()
    end
    Module.Initialized = true
    return aura
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/RemoteLogger.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "RemoteLogger",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function fullName(instance: Instance): string
    local ok: boolean, name: any = pcall(function(): string
        return instance:GetFullName()
    end)
    return ok and tostring(name) or instance.Name
end

local function describe(value: any, depth: number): string
    local kind: string = typeof(value)
    if kind == "string" then
        return string.format("%q", (value :: string):sub(1, 200))
    end
    if kind == "number" or kind == "boolean" or kind == "nil" then
        return tostring(value)
    end
    if kind == "Instance" then
        return "«" .. (value :: Instance).ClassName .. " " .. fullName(value :: Instance) .. "»"
    end
    if kind == "Vector3" or kind == "Vector2" or kind == "CFrame"
        or kind == "Color3" or kind == "UDim2" or kind == "EnumItem" then
        return kind .. "(" .. tostring(value) .. ")"
    end
    if kind == "table" then
        if depth <= 0 then
            return "{...}"
        end
        local parts: {string} = {}
        local count: number = 0
        for key: any, entry: any in pairs(value :: any) do
            count += 1
            if count > 12 then
                table.insert(parts, "...")
                break
            end
            table.insert(
                parts,
                "[" .. describe(key, depth - 1) .. "] = " .. describe(entry, depth - 1)
            )
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return kind
end

local function snippetFor(entry: any): string
    local parts: {string} = {}
    for _, argument: string in ipairs(entry.arguments) do
        table.insert(parts, argument)
    end
    return "game:GetService(\"ReplicatedStorage\")"
        .. " -- "
        .. entry.path
        .. "\n-- :"
        .. entry.method
        .. "("
        .. table.concat(parts, ", ")
        .. ")"
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local httpService: HttpService = host.HttpService
    local product: any = host.PRODUCT
    local remoteLogFolder: string = product.storageFolder .. "/RemoteLogs"

    local log: {[string]: any} = {}
    local order: {string} = {}
    local pathCache: any = setmetatable({}, {__mode = "k"})
    local hooked: boolean = false
    local restore: (() -> ())? = nil
    local capturing: boolean = false

    local logger: any

    local function record(remote: Instance, method: string, ...: any): ()
        if not capturing then
            return
        end
        local options: any = logger.Options

        local path: string = pathCache[remote]
        if not path then
            path = fullName(remote)
            pathCache[remote] = path
        end
        local filter: string = tostring(options["Only containing"].Value or "")
        if filter ~= ""
            and not string.find(string.lower(path), string.lower(filter), 1, true) then
            return
        end

        local key: string = path .. "::" .. method
        local entry: any = log[key]
        if not entry then
            if #order >= math.round(options["Max remotes"].Value) then
                return
            end
            entry = {
                path = path,
                class = remote.ClassName,
                method = method,
                calls = 0,
                samples = 0,
                firstSeen = os.clock(),
                arguments = {},
            }
            log[key] = entry
            table.insert(order, key)
            if options["Announce new"].Value then
                logger:Notify(remote.Name .. " · " .. method)
            end
        end
        entry.calls += 1
        entry.lastSeen = os.clock()

        if entry.samples >= 3 and not options["Resample always"].Value then
            return
        end
        entry.samples += 1
        local described: {string} = {}
        local packed: {any} = table.pack(...)
        for index: number = 1, math.min(packed.n, 10) do
            table.insert(described, describe(packed[index], 3))
        end
        if packed.n > 10 then
            table.insert(described, "...")
        end
        entry.arguments = described
    end

    local queue: {any} = {}
    local queued: number = 0
    local inHook: boolean = false

    local function installHook(): boolean
        if hooked then
            return true
        end
        local environment: any = getfenv()
        local hookMetamethod: any = environment.hookmetamethod
        local getNamecall: any = environment.getnamecallmethod
        local checkCaller: any = environment.checkcaller
        if type(hookMetamethod) ~= "function" or type(getNamecall) ~= "function" then
            logger:Notify("executor lacks hookmetamethod")
            return false
        end

        local previous: any
        local ok: boolean = pcall(function(): ()
            previous = hookMetamethod(game, "__namecall", function(self: any, ...: any): any

                if not capturing or inHook then
                    return previous(self, ...)
                end
                local method: string = getNamecall()
                if method ~= "FireServer" and method ~= "InvokeServer" then
                    return previous(self, ...)
                end
                if type(checkCaller) == "function" and checkCaller() then
                    return previous(self, ...)
                end
                if queued < 256 then
                    inHook = true
                    queued += 1
                    queue[queued] = {
                        remote = self,
                        method = method,
                        count = select("#", ...),
                        arguments = table.pack(...),
                        at = os.clock(),
                    }
                    inHook = false
                end
                return previous(self, ...)
            end)
        end)
        if not ok then
            logger:Notify("could not install the hook")
            return false
        end
        hooked = true
        restore = function(): ()

            local removed: boolean = pcall(hookMetamethod, game, "__namecall", previous)
            if removed then
                hooked = false
                return
            end

            logger:Notify("hook stays until rejoin")
        end
        return true
    end

    local function drainQueue(): ()
        if queued == 0 then
            return
        end
        local pending: {any} = queue
        queue = {}
        local count: number = queued
        queued = 0
        for index: number = 1, count do
            local item: any = pending[index]
            if item then
                pcall(function(): ()
                    record(
                        item.remote,
                        item.method,
                        table.unpack(item.arguments, 1, item.count)
                    )
                end)
            end
        end
        logger:SetStatus(tostring(#order))
    end

    local function buildReport(): string
        local lines: {string} = {
            "-- " .. tostring(product.name) .. " remote log",
            "-- place " .. tostring(game.PlaceId),
            "-- " .. tostring(#order) .. " remotes",
            "",
        }
        for _, key: string in ipairs(order) do
            local entry: any = log[key]
            table.insert(lines, string.rep("-", 70))
            table.insert(lines, entry.path)
            table.insert(
                lines,
                "  class "
                    .. entry.class
                    .. "  ·  "
                    .. entry.method
                    .. "  ·  "
                    .. tostring(entry.calls)
                    .. " calls"
            )
            table.insert(lines, "  args  " .. table.concat(entry.arguments, ", "))
            table.insert(lines, snippetFor(entry))
        end
        return table.concat(lines, "\n")
    end

    local function saveReport(): ()
        local environment: any = getfenv()
        local writeFile: any = environment.writefile
        local makeFolder: any = environment.makefolder
        local isFolder: any = environment.isfolder
        if type(writeFile) ~= "function" then
            logger:Notify("executor has no writefile")
            return
        end
        if type(makeFolder) == "function" and type(isFolder) == "function" then
            if not isFolder(product.storageFolder) then
                pcall(makeFolder, product.storageFolder)
            end
            if not isFolder(remoteLogFolder) then
                pcall(makeFolder, remoteLogFolder)
            end
        end

        local stamp: string = tostring(math.round(os.time()))
        local base: string = remoteLogFolder
            .. "/"
            .. tostring(game.PlaceId)
            .. "-"
            .. stamp

        local wrote: boolean = pcall(writeFile, base .. ".txt", buildReport())

        local payload: {any} = {}
        for _, key: string in ipairs(order) do
            local entry: any = log[key]
            table.insert(payload, {
                path = entry.path,
                class = entry.class,
                method = entry.method,
                calls = entry.calls,
                arguments = entry.arguments,
            })
        end
        local encoded: boolean, json: any = pcall(function(): string
            return httpService:JSONEncode(payload)
        end)
        if encoded then
            pcall(writeFile, base .. ".json", json)
        end
        if wrote then
            logger:Notify("saved " .. tostring(#order) .. " remotes")
        else
            logger:Notify("could not write the log")
        end
    end

    logger = framework.Categories.Utility:CreateModule({
        Name = "Remote Logger",
        Category = "Other",
        Order = 2,
        Tooltip = "Records the arguments the game sends to its own remotes and "
            .. "writes them to disk.",
        Function = function(enabled: boolean): ()
            capturing = enabled
            if not enabled then
                logger:SetStatus(nil)
                return
            end
            logger:SetStatus(tostring(#order))
            if not installHook() then
                capturing = false
                return
            end
            logger:Loop(drainQueue)
            logger:Clean(function(): ()
                capturing = false
                queue = {}
                queued = 0
                if restore then
                    (restore :: () -> ())()
                    restore = nil
                end
            end)
        end,
    })

    logger:CreateTextBox({
        Name = "Only containing",
        Default = "",
        Tooltip = "Record only remotes whose path contains this. Leave empty "
            .. "for everything.",
    })
    logger:CreateSlider({
        Name = "Max remotes",
        Min = 10,
        Max = 400,
        Default = 120,
        Tooltip = "Stops the log growing without bound in a chatty game.",
    })
    logger:CreateToggle({
        Name = "Announce new",
        Default = false,
        Tooltip = "Toast the first time each remote is seen.",
    })
    logger:CreateToggle({
        Name = "Resample always",
        Default = false,
        Tooltip = "Describe the arguments of every call instead of the first "
            .. "few. Useful for a remote whose shape changes; heavier.",
    })

    logger:CreateButton({
        Name = "Save to file",
        Tooltip = "Writes " .. remoteLogFolder .. "/<place>-<time>.txt and .json",
        Function = saveReport,
    })
    logger:CreateButton({
        Name = "Copy to clipboard",
        Function = function(): ()
            local environment: any = getfenv()
            local copy: any = environment.setclipboard or environment.toclipboard
            if type(copy) ~= "function" then
                logger:Notify("executor has no clipboard")
                return
            end
            pcall(copy, buildReport())
            logger:Notify("copied")
        end,
    })
    logger:CreateButton({
        Name = "Clear log",
        Function = function(): ()
            log = {}
            order = {}
            if logger.Enabled then
                logger:SetStatus("0")
            end
            logger:Notify("cleared")
        end,
    })
    logger:CreateNote(
        "Turn it on, do the thing you want a module to do — buy, mine, place, "
            .. "hit — then save. The log records what only a live game can "
            .. "tell you: the arguments, in order, as the game really sent "
            .. "them. It watches; it never blocks, delays or alters a call."
    )

    Module.entries = function(): {any}
        local list: {any} = {}
        for _, key: string in ipairs(order) do
            table.insert(list, log[key])
        end
        return list
    end
    Module.report = buildReport

    activeCleanup = function(): ()
        capturing = false
        if restore then
            (restore :: () -> ())()
            restore = nil
        end
        Module.entries = nil
        Module.report = nil
    end
    Module.Initialized = true
    return logger
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/Learning.lua"] = [[export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Learning",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local services: any = context.services
    local captureService: any = services and services.screenCapture
    local product: any = host.PRODUCT or {}
    local httpService: any = host.HttpService
    local currentWorkspace: Workspace = host.workspace or workspace
    local sampleNumber: number = 0
    local card: any

    local function writeMetadata(path: string, payload: any): boolean
        if not captureService or type(captureService.writeText) ~= "function" then
            return false
        end
        local ok: boolean, encoded: any = pcall(function(): string
            return httpService:JSONEncode(payload)
        end)
        if not ok or type(encoded) ~= "string" then
            return false
        end
        return captureService.writeText(path, encoded) == true
    end

    local function captureSample(): ()
        if not captureService or type(captureService.isAvailable) ~= "function"
            or not captureService.isAvailable() then
            card:Notify("screenshot API unavailable")
            card:SetStatus("unavailable")
            return
        end
        if type(captureService.capture) ~= "function"
            or type(captureService.writeText) ~= "function" then
            card:Notify("screen capture service incomplete")
            card:SetStatus("unavailable")
            return
        end

        sampleNumber += 1
        local folder: string = tostring(product.storageFolder or "Wurst")
            .. "/Learning"
        local stamp: string = tostring(os.time())
        local base: string = folder
            .. "/"
            .. tostring(game.PlaceId)
            .. "-"
            .. stamp
            .. "-"
            .. tostring(sampleNumber)
        local imagePath: string = base .. ".png"
        local metadataPath: string = base .. ".json"
        local captured: boolean, reason: any = captureService.capture(imagePath)
        if not captured then
            card:Notify(tostring(reason or "screen capture failed"))
            card:SetStatus("failed")
            return
        end

        local camera: Camera? = currentWorkspace.CurrentCamera
        local viewport: Vector2 = camera
            and camera.ViewportSize
            or Vector2.new(0, 0)
        local payload: {[string]: any} = {
            schema = 1,
            kind = "learning-screen-sample",
            image = imagePath,
            capturedAt = os.time(),
            placeId = game.PlaceId,
            viewport = {width = viewport.X, height = viewport.Y},
            source = "manual Capture now action",
            menuVisible = services.menu.isVisible(),
        }
        local wrote: boolean = writeMetadata(metadataPath, payload)
        if not wrote then
            card:Notify("image saved; metadata could not be written")
            card:SetStatus("image saved")
            return
        end
        card:SetStatus("saved " .. tostring(sampleNumber))
        card:Notify("saved learning sample " .. tostring(sampleNumber))
    end

    card = framework.Categories.Other:CreateModule({
        Name = "Learning",
        Category = "Other",
        ConfigKey = "Universal.Learning",
        Kind = "group",
        Order = 26,
        Tooltip = "Save a manual local screenshot and a small metadata sidecar.",
        Function = function(_enabled: boolean): ()

        end,
    })
    card:CreateButton({
        Name = "Capture now",
        Tooltip = "Save one screenshot locally; no upload or background capture.",
        Function = captureSample,
    })
    card:CreateNote(
        "Manual and local only. Standard Roblox Luau has no screenshot API."
    )

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/ClickTeleport.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "ClickTeleport",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function characterRoot(localPlayer: Player): (BasePart?, Humanoid?)
    local character: Model? = localPlayer.Character
    if not character then
        return nil, nil
    end
    return character:FindFirstChild("HumanoidRootPart") :: BasePart?,
        character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local menu: any = context.services.menu

    local runtime: any = {
        armedUntil = 0,
        waypoint = nil :: Vector3?,
        lastOrigin = nil :: Vector3?,
    }

    local teleport: any
    teleport = framework.Categories.Blatant:CreateModule({
        Name = "Click Teleport",
        Category = "Blatant",
        Order = 1,

        Kind = "action",
        Silent = true,
        Tooltip = "Press to travel to the destination selected below.",
        Function = function(): ()
            Module.run(context, teleport, runtime)
        end,
    })

    teleport:CreateDropdown({
        Name = "Destination",
        List = {
            "Tap point",
            "Nearest player",
            "Named player",
            "Item",
            "Waypoint",
            "Last position",
        },
        Index = 1,
        Tooltip = "What the button travels to.",
    })
    teleport:CreateTextBox({
        Name = "Player",
        Show = {Option = "Destination", Values = {"Named player"}},
        Default = "",
        Tooltip = "Part of a name or display name, for Named player.",
    })
    teleport:CreateTextBox({
        Name = "Item",
        Show = {Option = "Destination", Values = {"Item"}},
        Default = "",
        Tooltip = "Part or model name to look for, for Item. Partial names "
            .. "match, so \"chest\" finds \"GoldChest\".",
    })
    teleport:CreateButton({
        Name = "Save waypoint",
        Show = {Option = "Destination", Values = {"Waypoint"}},
        Tooltip = "Stores where you are standing right now.",
        Function = function(): ()
            local root: BasePart? = characterRoot(localPlayer)
            if not root then
                return
            end
            runtime.waypoint = (root :: BasePart).Position
            teleport:Notify("waypoint saved")
        end,
    })
    teleport:CreateButton({
        Name = "Go back",
        Show = {Option = "Destination", Values = {"Last position"}},
        Tooltip = "Returns to where the last teleport started.",
        Function = function(): ()
            if not runtime.lastOrigin then
                teleport:Notify("nowhere to go back to")
                return
            end
            Module.travel(context, teleport, runtime, runtime.lastOrigin, false)
        end,
    })

    teleport:CreateSlider({
        Name = "Arm window",
        Show = {Option = "Destination", Values = {"Tap point"}},
        Min = 1,
        Max = 15,
        Default = 6,
        Tooltip = "Seconds Tap point stays armed after the button is pressed.",
    })
    teleport:CreateSlider({
        Name = "Search range",
        Show = {Option = "Destination", Values = {"Nearest player", "Named player", "Item"}},
        Min = 50,
        Max = 5000,
        Default = 1500,
        Tooltip = "How far to look for items and players.",
    })
    teleport:CreateSlider({
        Name = "Player offset",
        Show = {Option = "Destination", Values = {"Nearest player", "Named player"}},
        Min = 0,
        Max = 20,
        Default = 4,
        Tooltip = "Studs to stop short of a player, so you do not land inside "
            .. "them.",
    })
    teleport:CreateToggle({
        Name = "Skip friends",
        Show = {Option = "Destination", Values = {"Nearest player"}},
        Default = false,
        Tooltip = "Nearest player ignores anyone on the Friend List.",
    })
    teleport:CreateDropdown({
        Name = "Movement",
        List = {"Instant", "Glide"},
        Index = 1,
        Tooltip = "Glide steps the character across, which some games accept "
            .. "when a single jump is rejected.",
    })
    teleport:CreateSlider({
        Name = "Glide step",
        Show = {Option = "Movement", Values = {"Glide"}},
        Min = 4,
        Max = 60,
        Default = 18,
    })
    teleport:CreateSlider({
        Name = "Height offset",
        Min = 0,
        Max = 12,
        Default = 3,
        Tooltip = "Studs above whatever you land on.",
    })
    teleport:CreateToggle({
        Name = "Keep momentum",
        Default = false,
        Tooltip = "Leave your velocity alone on arrival instead of zeroing it.",
    })

    local tapConnection: RBXScriptConnection = userInput.InputBegan:Connect(
        function(input: InputObject, processed: boolean): ()
            if processed or os.clock() >= runtime.armedUntil then
                return
            end
            if menu.isCapturingInput() then
                return
            end
            local touched: boolean = input.UserInputType == Enum.UserInputType.Touch
            local clicked: boolean =
                input.UserInputType == Enum.UserInputType.MouseButton1
            if not touched and not clicked then
                return
            end
            runtime.armedUntil = 0
            Module.travel(
                context,
                teleport,
                runtime,
                Module.pointUnder(context, input.Position),
                true
            )
        end
    )

    activeCleanup = function(): ()
        pcall(function(): ()
            tapConnection:Disconnect()
        end)
        runtime.armedUntil = 0
    end
    Module.Initialized = true
    return teleport
end

function Module.pointUnder(context: Runtime, screenPosition: Vector3): Vector3?
    local host: any = context.host
    local currentWorkspace: Workspace = host.workspace or workspace
    local camera: Camera? = currentWorkspace.CurrentCamera
    if not camera then
        return nil
    end
    local resolvedCamera: Camera = camera :: Camera
    local ray: Ray = resolvedCamera:ScreenPointToRay(
        screenPosition.X,
        screenPosition.Y
    )
    local parameters: RaycastParams = RaycastParams.new()
    parameters.FilterType = Enum.RaycastFilterType.Exclude
    parameters.IgnoreWater = true
    parameters.FilterDescendantsInstances = {
        host.LocalPlayer.Character :: any,
        resolvedCamera,
    }
    local result: RaycastResult? = currentWorkspace:Raycast(
        ray.Origin,
        ray.Direction.Unit * 4096,
        parameters
    )
    return result and result.Position or nil
end

local function matchesName(candidate: string, query: string): boolean
    return string.find(string.lower(candidate), string.lower(query), 1, true) ~= nil
end

function Module.findItem(
    context: Runtime,
    query: string,
    origin: Vector3,
    range: number
): Vector3?
    local host: any = context.host
    local currentWorkspace: Workspace = host.workspace or workspace
    local best: Vector3? = nil
    local bestDistance: number = range
    local character: Model? = host.LocalPlayer.Character

    for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
        if character and descendant:IsDescendantOf(character) then
            continue
        end
        if not matchesName(descendant.Name, query) then
            continue
        end
        local position: Vector3? = nil
        if descendant:IsA("BasePart") then
            position = (descendant :: BasePart).Position
        elseif descendant:IsA("Model") then
            local pivotOk: boolean, pivot: any = pcall(function(): CFrame
                return (descendant :: Model):GetPivot()
            end)
            if pivotOk then
                position = (pivot :: CFrame).Position
            end
        end
        if not position then
            continue
        end
        local distance: number = ((position :: Vector3) - origin).Magnitude
        if distance < bestDistance then
            best = position
            bestDistance = distance
        end
    end
    return best
end

function Module.run(context: Runtime, teleport: any, runtime: any): ()
    local host: any = context.host
    local entityLibrary: any = context.entity
    local localPlayer: Player = host.LocalPlayer
    local options: any = teleport.Options
    local destination: string = options["Destination"].Value

    local root: BasePart? = characterRoot(localPlayer)
    if not root then
        teleport:Notify("no character")
        return
    end
    local origin: Vector3 = (root :: BasePart).Position
    local range: number = options["Search range"].Value

    if destination == "Tap point" then
        runtime.armedUntil = os.clock() + options["Arm window"].Value
        teleport:Notify("tap where you want to go")
        return
    end

    if destination == "Waypoint" then
        if not runtime.waypoint then
            teleport:Notify("no waypoint saved")
            return
        end
        Module.travel(context, teleport, runtime, runtime.waypoint, false)
        return
    end

    if destination == "Last position" then
        if not runtime.lastOrigin then
            teleport:Notify("nowhere to go back to")
            return
        end
        Module.travel(context, teleport, runtime, runtime.lastOrigin, false)
        return
    end

    if destination == "Item" then
        local query: string = tostring(options["Item"].Value or "")
        if query == "" then
            teleport:Notify("type an item name first")
            return
        end
        local found: Vector3? = Module.findItem(context, query, origin, range)
        if not found then
            teleport:Notify("no \"" .. query .. "\" within range")
            return
        end
        Module.travel(context, teleport, runtime, found, true)
        return
    end

    entityLibrary:Refresh()
    local target: any = nil
    if destination == "Nearest player" then
        local bestDistance: number = range
        for _, entity: any in ipairs(entityLibrary.List) do
            if options["Skip friends"].Value
                and entityLibrary:IsProtected(entity.Player) then
                continue
            end
            if entity.Distance < bestDistance then
                target = entity
                bestDistance = entity.Distance
            end
        end
    else
        local query: string = tostring(options["Player"].Value or "")
        if query == "" then
            teleport:Notify("type a player name first")
            return
        end
        for _, entity: any in ipairs(entityLibrary.List) do
            if matchesName(entity.Player.Name, query)
                or matchesName(entity.Player.DisplayName, query) then
                target = entity
                break
            end
        end
    end

    if not target then
        teleport:Notify("no matching player")
        return
    end

    local targetPosition: Vector3 = target.RootPart.Position
    local offset: number = options["Player offset"].Value
    local approach: Vector3 = targetPosition - origin
    if offset > 0 and approach.Magnitude > offset then
        targetPosition = targetPosition - approach.Unit * offset
    end
    Module.travel(context, teleport, runtime, targetPosition, false)
end

function Module.travel(
    context: Runtime,
    teleport: any,
    runtime: any,
    destination: Vector3?,
    liftToSurface: boolean
): ()
    local host: any = context.host
    local localPlayer: Player = host.LocalPlayer
    if not destination then
        teleport:Notify("nothing there")
        return
    end

    local root: BasePart?, humanoid: Humanoid? = characterRoot(localPlayer)
    if not root then
        return
    end
    local resolvedRoot: BasePart = root :: BasePart
    local options: any = teleport.Options

    runtime.lastOrigin = resolvedRoot.Position

    local target: Vector3 = destination :: Vector3
    if liftToSurface then

        local hipHeight: number = humanoid and (humanoid :: Humanoid).HipHeight or 2
        target = target
            + Vector3.new(0, hipHeight + options["Height offset"].Value, 0)
    end

    local keepMomentum: boolean = options["Keep momentum"].Value
    if options["Movement"].Value == "Instant" then
        resolvedRoot.CFrame = CFrame.new(target)
        if not keepMomentum then
            resolvedRoot.AssemblyLinearVelocity = Vector3.zero
        end
        return
    end

    local step: number = options["Glide step"].Value
    task.spawn(function(): ()
        for _ = 1, 360 do
            if not resolvedRoot.Parent then
                return
            end
            local offset: Vector3 = target - resolvedRoot.Position
            if offset.Magnitude < 3 then
                resolvedRoot.CFrame = CFrame.new(target)
                if not keepMomentum then
                    resolvedRoot.AssemblyLinearVelocity = Vector3.zero
                end
                return
            end
            resolvedRoot.CFrame = resolvedRoot.CFrame
                + offset.Unit * math.min(offset.Magnitude, step)
            if not keepMomentum then
                resolvedRoot.AssemblyLinearVelocity = Vector3.zero
            end
            task.wait()
        end
    end)
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Combat/AutoClicker.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    weapons: any?,
}

local Module = {
    Name = "AutoClicker",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function pressGuiButton(button: GuiButton): boolean
    local environment: any = getfenv()
    local connectionsOf: any = environment.getconnections
    local fireSignal: any = environment.firesignal
    local pressed: boolean = false

    if type(connectionsOf) == "function" then
        for _, signal: any in
            ipairs({
                button.MouseButton1Down,
                button.MouseButton1Click,
                (button :: any).Activated,
                button.MouseButton1Up,
            })
        do
            local ok: boolean, connections: any = pcall(connectionsOf, signal)
            if not ok or type(connections) ~= "table" then
                continue
            end
            for _, connection: any in ipairs(connections) do
                local fired: boolean = pcall(function(): ()
                    connection:Fire()
                end)
                pressed = pressed or fired
            end
        end
    end

    if not pressed and type(fireSignal) == "function" then
        pressed = pcall(fireSignal, (button :: any).Activated) == true
    end
    return pressed
end

local function isGameButton(
    instance: Instance,
    isMenuOwned: (Instance) -> boolean
): boolean
    if not instance:IsA("GuiButton") then
        return false
    end

    if isMenuOwned(instance) then
        return false
    end
    return true
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local isMenuOwned: (Instance) -> boolean = host.isMenuOwned
    local weapons: any = context.weapons

    local runtime: any = {
        nextClickAt = 0,
        learning = false,
        target = nil :: GuiButton?,
        touches = 0,
    }

    local function equippedTool(): Tool?
        local character: Model? = localPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChildOfClass("Tool") :: Tool?
    end

    local function findButtonByName(name: string): GuiButton?
        if name == "" then
            return nil
        end
        local playerGui: Instance? = localPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil
        end
        local wanted: string = string.lower(name)
        for _, descendant: Instance in ipairs(playerGui:GetDescendants()) do
            if not isGameButton(descendant, isMenuOwned) then
                continue
            end
            if string.find(string.lower(descendant.Name), wanted, 1, true) then
                return descendant :: GuiButton
            end
        end
        return nil
    end

    local function resolveTarget(): GuiButton?
        local current: GuiButton? = runtime.target
        if current and (current :: GuiButton).Parent then
            return current
        end
        runtime.target = nil
        return nil
    end

    local clicker: any
    clicker = framework.Categories.Combat:CreateModule({
        Name = "Auto Clicker",
        Category = "Combat",
        Order = 2,
        Tooltip = "Clicks for you while you hold the attack down.",
        Function = function(enabled: boolean): ()
            runtime.nextClickAt = 0
            runtime.touches = 0
            if not enabled then
                clicker:SetStatus(nil)
                return
            end
            local cps: any = clicker.Options["CPS"].Value
            clicker:SetStatus(
                tostring(math.round(cps.Min))
                    .. "-"
                    .. tostring(math.round(cps.Max))
                    .. " CPS"
            )

            clicker:Event(userInput.InputBegan, function(input: InputObject): ()
                if input.UserInputType == Enum.UserInputType.Touch then
                    runtime.touches += 1
                end
            end)
            clicker:Event(userInput.InputEnded, function(input: InputObject): ()
                if input.UserInputType == Enum.UserInputType.Touch then
                    runtime.touches = math.max(0, runtime.touches - 1)
                end
            end)

            clicker:Loop(function(): ()
                local options: any = clicker.Options
                local holdingAttack: boolean = false
                if options["Activation"].Value == "Hold key" then
                    local key: Enum.KeyCode = options["Hold key"].Value
                    holdingAttack = key ~= Enum.KeyCode.Unknown
                        and userInput:IsKeyDown(key)
                else
                    holdingAttack = userInput:IsMouseButtonPressed(
                        Enum.UserInputType.MouseButton1
                    ) or runtime.touches > 0
                end
                if not holdingAttack then

                    runtime.nextClickAt = 0
                    return
                end

                local mode: string = options["Click"].Value

                if context.services.menu.isVisible()
                    and (mode == "Left click" or mode == "Right click") then
                    return
                end

                local now: number = os.clock()
                if now < runtime.nextClickAt then
                    return
                end
                local rate: number = options["CPS"]:GetRandomValue()
                runtime.nextClickAt = now + 1 / math.max(rate, 0.5)

                if mode == "Tool" then
                    local tool: Tool? = equippedTool()
                    if tool then
                        pcall(function(): ()
                            (tool :: Tool):Activate()
                        end)
                        return
                    end

                    if weapons then
                        local candidate: any = weapons:Best({All = true})
                        if candidate then
                            weapons:Activate(candidate)
                        end
                    end
                    return
                end

                if mode == "Screen button" then
                    local button: GuiButton? = resolveTarget()
                        or findButtonByName(tostring(options["Button name"].Value or ""))
                    if button then
                        runtime.target = button
                        pressGuiButton(button :: GuiButton)
                    end
                    return
                end

                local environment: any = getfenv()
                local click: any = mode == "Right click"
                    and environment.mouse2click
                    or environment.mouse1click
                if type(click) == "function" then
                    pcall(click)
                end
            end)
        end,
    })

    clicker:CreateTwoSlider({
        Name = "CPS",
        Min = 1,
        Max = 28,
        DefaultMin = 8,
        DefaultMax = 12,
        Function = function(value: any): ()
            if clicker.Enabled then
                clicker:SetStatus(
                    tostring(math.round(value.Min))
                        .. "-"
                        .. tostring(math.round(value.Max))
                        .. " CPS"
                )
            end
        end,
        Tooltip = "Clicks per second. Every gap is drawn between the two ends, "
            .. "so no two clicks are the same distance apart. A fast hand peaks "
            .. "around 12; past 20 nothing human explains the rate and servers "
            .. "that log click intervals will say so.",
    })

    clicker:CreateDropdown({
        Name = "Activation",
        List = {"Hold click", "Hold key"},
        Index = 1,
        Tooltip = "Hold click follows the real attack button; Hold key runs "
            .. "while your own key is down.",
    })
    clicker:CreateBind({
        Name = "Hold key",
        Show = {Option = "Activation", Values = {"Hold key"}},
        Default = Enum.KeyCode.Unknown,
        Tooltip = "Click the slot, then press the key. On touch, tap it to "
            .. "place a button and hold that instead.",
    })

    clicker:CreateDropdown({
        Name = "Click",
        List = {"Tool", "Left click", "Right click", "Screen button"},
        Index = 1,
        Tooltip = "What one click means: activate the equipped tool, a real "
            .. "left or right click through the executor, or the game's own "
            .. "on-screen attack button.",
    })
    clicker:CreateTextBox({
        Name = "Button name",
        Show = {Option = "Click", Values = {"Screen button"}},
        Default = "",
        Tooltip = "Part of the name of the game's attack button. Filled in "
            .. "for you by Learn button.",
    })
    clicker:CreateButton({
        Name = "Learn button",
        Show = {Option = "Click", Values = {"Screen button"}},
        Tooltip = "Press this, then tap the game's own attack button once.",
        Function = function(): ()
            if runtime.learning then
                runtime.learning = false
                clicker:Notify("cancelled")
                return
            end
            runtime.learning = true
            clicker:Notify("tap the game's button now")
        end,
    })

    local learnConnection: RBXScriptConnection = userInput.InputBegan:Connect(
        function(input: InputObject): ()
            if not runtime.learning then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local playerGui: Instance? = localPlayer:FindFirstChild("PlayerGui")
            if not playerGui then
                return
            end
            local located: {Instance} = (playerGui :: any):GetGuiObjectsAtPosition(
                input.Position.X,
                input.Position.Y
            )
            for _, candidate: Instance in ipairs(located) do
                if isGameButton(candidate, isMenuOwned) then
                    runtime.learning = false
                    runtime.target = candidate :: GuiButton
                    clicker.Options["Button name"]:Set(candidate.Name)
                    clicker:Notify("bound to " .. candidate.Name)
                    return
                end
            end
        end
    )

    activeCleanup = function(): ()
        runtime.learning = false
        runtime.target = nil
        runtime.touches = 0
        pcall(function(): ()
            learnConnection:Disconnect()
        end)
    end
    Module.Initialized = true
    return clicker
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Combat/TriggerBot.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "TriggerBot",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function findTool(character: Model?): Tool?
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Tool")
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService

    local armedTarget: any = nil
    local armedAt: number = 0
    local nextShotAt: number = 0

    local trigger: any
    trigger = framework.Categories.Combat:CreateModule({
        Name = "TriggerBot",
        Category = "Combat",
        Order = 1,
        Tooltip = "Fires the equipped tool when a valid target is under the "
            .. "crosshair.",
        Function = function(enabled: boolean): ()
            armedTarget = nil
            armedAt = 0
            nextShotAt = 0
            if not enabled then
                return
            end

            trigger:Loop(function(): ()
                local options: any = trigger.Options
                if options["Activation"].Value == "Hold key"
                    and not userInput:IsKeyDown(options["Hold key"].Value) then
                    armedTarget = nil
                    return
                end

                local character: Model? = localPlayer.Character
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if not character or not humanoid or humanoid.Health <= 0 then
                    armedTarget = nil
                    return
                end

                local tool: Tool? = findTool(character)

                local target: any, distance: number =
                    Module.resolveTarget(context, trigger)
                if not target then
                    armedTarget = nil
                    return
                end
                if distance > options["Max distance"].Value then
                    armedTarget = nil
                    return
                end

                local now: number = os.clock()
                if armedTarget ~= target then
                    armedTarget = target

                    local reaction: number = options["Reaction"].Value
                    armedAt = now + reaction + math.random() * reaction * 0.34
                    return
                end
                if now < armedAt or now < nextShotAt then
                    return
                end

                Module.fire(tool)
                if options["Fire mode"].Value == "Single" then

                    armedTarget = nil
                    nextShotAt = now + math.max(options["Shot delay"].Value, 0.05)
                else
                    nextShotAt = now + math.max(options["Shot delay"].Value, 0.05)
                end
            end)
        end,
    })

    trigger:CreateDropdown({
        Name = "Activation",
        List = {"Always", "Hold key"},
        Index = 1,
        Tooltip = "Always runs while the module is on; Hold key only while "
            .. "the bind is down.",
    })
    trigger:CreateBind({
        Name = "Hold key",
        Show = {Option = "Activation", Values = {"Hold key"}},
        Default = Enum.KeyCode.Unknown,
        Tooltip = "Click the slot, then press the key.",
    })
    trigger:CreateDropdown({
        Name = "Fire mode",
        List = {"Single", "Automatic"},
        Index = 1,
        Tooltip = "Single fires once per acquisition, Automatic keeps firing.",
    })
    trigger:CreateSlider({
        Name = "Reaction",
        Min = 0,
        Max = 1,
        Default = 0.08,
        Tooltip = "Seconds between a target entering the crosshair and the "
            .. "shot. A random third of this is added on every acquisition, so "
            .. "two shots never share the same reaction time.",
    })
    trigger:CreateSlider({
        Name = "Shot delay",
        Min = 0.05,
        Max = 2,
        Default = 0.15,
        Tooltip = "Minimum seconds between two shots.",
    })

    trigger:CreateDropdown({
        Name = "Target part",
        List = {"Any", "Head", "Torso"},
        Index = 1,
        Tooltip = "Which part has to be under the crosshair.",
    })
    trigger:CreateSlider({
        Name = "Aim tolerance",
        Min = 0,
        Max = 120,
        Default = 0,
        Tooltip = "Pixels of slack around the crosshair. 0 requires an exact "
            .. "hit on the target, which is what a raycast alone gives you.",
    })
    trigger:CreateSlider({
        Name = "Max distance",
        Min = 10,
        Max = 2000,
        Default = 600,
    })
    trigger:CreateToggle({
        Name = "Team check",
        Default = true,
        Tooltip = "Never fire at players on your own team.",
    })
    trigger:CreateToggle({
        Name = "Wall check",
        Default = true,
        Tooltip = "Never fire at a target with geometry in the way.",
    })
    trigger:CreateToggle({
        Name = "Target NPCs",
        Default = false,
        Tooltip = "Also recognize non-player humanoid models under the crosshair.",
    })

    activeCleanup = function(): ()
        armedTarget = nil
    end
    Module.Initialized = true
    return trigger
end

function Module.resolveTarget(context: Runtime, trigger: any): (any, number)
    local host: any = context.host
    local entityLibrary: any = context.entity
    local players: Players = host.Players
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    local options: any = trigger.Options

    local ray: Ray? = context.services.aim.getRay()
    if not ray then
        return nil, 0
    end
    local resolvedRay: Ray = ray :: Ray
    entityLibrary:Refresh()

    local partFilter: string = options["Target part"].Value
    local radius: number = options["Aim tolerance"].Value

    if radius <= 0 then
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        parameters.FilterDescendantsInstances = {
            localPlayer.Character :: any,
            currentWorkspace.CurrentCamera :: any,
        }
        local result: RaycastResult? = currentWorkspace:Raycast(
            resolvedRay.Origin,
            resolvedRay.Direction.Unit * options["Max distance"].Value,
            parameters
        )
        if not result then
            return nil, 0
        end
        local hit: BasePart = result.Instance
        local character: Model? = hit:FindFirstAncestorOfClass("Model")
        if not character then
            return nil, 0
        end
        local player: Player? = players:GetPlayerFromCharacter(character)
        local entity: any = player
            and entityLibrary:Get(player)
            or (options["Target NPCs"].Value
                and entityLibrary.GetNpc
                and entityLibrary:GetNpc(character))
        if not entity then
            return nil, 0
        end
        if options["Team check"].Value and entity.IsFriendly then
            return nil, 0
        end
        if partFilter == "Head" and hit.Name ~= "Head" then
            return nil, 0
        end
        if partFilter == "Torso"
            and hit.Name ~= "UpperTorso"
            and hit.Name ~= "LowerTorso"
            and hit.Name ~= "Torso"
            and hit.Name ~= "HumanoidRootPart" then
            return nil, 0
        end
        return player or character, entity.Distance
    end

    entityLibrary:Refresh()
    local entity: any = entityLibrary:ClosestToRay(
        resolvedRay.Origin,
        resolvedRay.Direction,
        {

            Radius = radius * 0.05,
            MaxDistance = options["Max distance"].Value,
            IgnoreTeam = not options["Team check"].Value,
            IgnoreWalls = not options["Wall check"].Value,
            IncludeNPCs = options["Target NPCs"].Value,
            Part = partFilter == "Head" and "Head" or nil,
        }
    )
    if not entity then
        return nil, 0
    end
    return entity.Player or entity.Character, entity.Distance
end

function Module.fire(tool: Tool?): ()
    if tool then
        pcall(function(): ()
            tool:Activate()
        end)
    end
    local environment: any = getfenv()
    local press: any = environment.mouse1press
    local release: any = environment.mouse1release
    if type(press) == "function" and type(release) == "function" then
        pcall(press)
        task.delay(0.02, function(): ()
            pcall(release)
        end)
        return
    end
    local click: any = environment.mouse1click
    if type(click) == "function" then
        pcall(click)
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Combat/AimAssist.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    libraries: {[string]: any},
    services: any,
}

local Module = {
    Name = "AimAssist",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local services: any = context.services
    local targeting: any = context.libraries and context.libraries.targeting
    local entity: any = context.entity
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local runtime: any = {
        target = nil,
        lockedTarget = nil,
    }
    local card: any

    local function camera(): Camera?
        return currentWorkspace.CurrentCamera
    end

    local function moveCamera(target: any, deltaTime: number): boolean
        local cameraObject: Camera? = camera()
        if not cameraObject or not target then
            return false
        end
        local current: CFrame = cameraObject.CFrame
        local offset: Vector3 = target.position - current.Position
        if offset.Magnitude <= 0.001 then
            return false
        end

        local mode: string = card.Options["Mode"].Value
        local alpha: number = 1
        if mode ~= "Aimbot" then
            local smoothing: number = card.Options["Smoothing"].Value
            if smoothing > 0 then
                local timeConstant: number = 0.02 + smoothing * 0.01
                alpha = 1 - math.exp(-math.max(deltaTime, 1 / 240) / timeConstant)
                alpha = math.clamp(alpha, 0, 1)
            end
        end
        local currentLook: Vector3 = current.LookVector
        local blended: Vector3 = currentLook:Lerp(offset.Unit, alpha)
        if blended.Magnitude <= 0.001 then
            return false
        end
        cameraObject.CFrame = CFrame.lookAt(
            current.Position,
            current.Position + blended.Unit
        )
        return true
    end

    local function anotherAimAdapterIsActive(): boolean
        local activity: any = services and services.activity
        return activity ~= nil
            and type(activity.isActive) == "function"
            and activity.isActive("mvsdSilentAim") == true
    end

    local function selectTarget(): any
        if anotherAimAdapterIsActive()
            or not targeting
            or type(targeting.List) ~= "function" then
            return nil
        end
        local options: any = card.Options
        local mode: string = options["Mode"].Value
        local candidates: {any} = targeting:List(entity, {

            FOV = mode == "Aim Assist" and options["FOV"].Value or nil,
            MaxDistance = options["Max distance"].Value,
            TargetPart = options["Target part"].Value,
            Prediction = options["Prediction"].Value,
            TeamCheck = options["Team check"].Value,
            VisibilityCheck = options["Visibility check"].Value,
            Priority = options["Priority"].Value,
            IncludeNPCs = options["Target NPCs"].Value,
            AllowOffscreen = mode == "Aimbot",
        })
        if mode ~= "Aimbot" then
            runtime.lockedTarget = nil
            return candidates[1]
        end
        if options["Sticky target"].Value and runtime.lockedTarget then
            for _, candidate: any in ipairs(candidates) do
                if candidate.entity == runtime.lockedTarget.entity then
                    runtime.lockedTarget = candidate
                    return candidate
                end
            end
        end
        runtime.lockedTarget = candidates[1]
        return runtime.lockedTarget
    end

    card = framework.Categories.Combat:CreateModule({
        Name = "Aim Assist",
        Category = "Combat",
        ConfigKey = "Universal.AimAssist",
        Order = 4,
        Tooltip = "Eases the local camera toward a valid target; no raycast or "
            .. "remote hooks.",
        Function = function(enabled: boolean): ()
            runtime.target = nil
            runtime.lockedTarget = nil
            if not enabled then
                card:SetStatus(nil)
                return
            end
            card:SetStatus("searching")
            card:Render(function(deltaTime: number): ()

                if anotherAimAdapterIsActive()
                    or services.menu.isVisible()
                    or services.menu.isCapturingInput() then
                    runtime.target = nil
                    runtime.lockedTarget = nil
                    card:SetStatus("paused")
                    return
                end
                if userInput:GetFocusedTextBox() then
                    runtime.target = nil
                    runtime.lockedTarget = nil
                    card:SetStatus("paused")
                    return
                end

                local selected: any = selectTarget()
                runtime.target = selected
                if not selected then
                    card:SetStatus("searching")
                    return
                end
                local moved: boolean = moveCamera(selected, deltaTime)
                local targetPlayer: Player? = selected.player
                local displayName: string = targetPlayer
                    and tostring(targetPlayer.DisplayName or targetPlayer.Name)
                    or tostring(selected.entity.Name or selected.character.Name)
                local distance: number = math.round(selected.distance)
                card:SetStatus(
                    displayName .. " · " .. tostring(distance) .. " studs"
                        .. (moved and " · locked" or " · ready")
                )
            end)
            card:Clean(function(): ()
                runtime.target = nil
                card:SetStatus(nil)
            end)
        end,
    })

    card:CreateDropdown({
        Name = "Mode",
        List = {"Aim Assist", "Aimbot"},
        Index = 1,
        Function = function(): ()
            runtime.lockedTarget = nil
        end,
        Tooltip = "Aim Assist respects FOV; Aimbot keeps a smooth lock on the "
            .. "best valid character on screen.",
    })
    card:CreateSlider({
        Name = "FOV",
        Show = {Option = "Mode", Values = {"Aim Assist"}},
        Min = 15,
        Max = 500,
        Step = 5,
        Default = 180,
        Tooltip = "Pixels around the cursor in which a target may be selected.",
    })
    card:CreateSlider({
        Name = "Smoothing",
        Show = {Option = "Mode", Values = {"Aim Assist"}},
        Min = 0,
        Max = 100,
        Step = 5,
        Default = 35,
        Tooltip = "0 snaps to the target; higher values make the camera settle "
            .. "more slowly. Aimbot always uses zero smoothing.",
    })
    card:CreateDropdown({
        Name = "Target part",
        List = {"Closest", "Head", "Torso"},
        Index = 1,
        Tooltip = "Body part used as the camera target.",
    })
    card:CreateDropdown({
        Name = "Priority",
        List = {"Cursor", "Distance"},
        Index = 1,
        Tooltip = "Choose the target nearest the cursor or nearest in the world.",
    })
    card:CreateSlider({
        Name = "Prediction",
        Min = 0,
        Max = 0.5,
        Step = 0.01,
        Default = 0.06,
        Tooltip = "Seconds of target velocity to lead. Set to 0 for no lead.",
    })
    card:CreateSlider({
        Name = "Max distance",
        Min = 25,
        Max = 2000,
        Step = 5,
        Default = 600,
        Tooltip = "Ignore targets farther than this many studs.",
    })
    card:CreateToggle({
        Name = "Visibility check",
        Default = true,
        Tooltip = "Skip targets hidden by map geometry.",
    })
    card:CreateToggle({
        Name = "Team check",
        Default = true,
        Tooltip = "Skip teammates and Friend List entries.",
    })
    card:CreateToggle({
        Name = "Target NPCs",
        Default = false,
        Tooltip = "Include non-player humanoid models in both modes.",
    })
    card:CreateToggle({
        Name = "Sticky target",
        Show = {Option = "Mode", Values = {"Aimbot"}},
        Default = true,
        Function = function(value: boolean): ()
            if not value then
                runtime.lockedTarget = nil
            end
        end,
        Tooltip = "Hold the current Aimbot target. Turn off to release it and "
            .. "select a new target every frame.",
    })
    card:CreateNote(
        "Camera-only assist. It never edits remotes, raycasts or hitboxes."
    )

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/XRay.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "XRay",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local originalXrayTransparency: {[BasePart]: number} =
        setmetatable({}, {__mode = "k"}) :: any
    local xrayEnabled: boolean = false
    local feature: any = nil

    local function restoreXray(): ()
        for part: BasePart, transparency: number in pairs(originalXrayTransparency) do
            if part.Parent then
                part.LocalTransparencyModifier = transparency
            end
        end
        originalXrayTransparency = setmetatable({}, {__mode = "k"}) :: any
    end

    local function toggleXray(enabled: boolean): ()
        disconnectFeatureConnection("Xray")
        xrayEnabled = false
        restoreXray()
        if not enabled then
            if feature then feature:SetStatus(nil) end
            return
        end

        feature:SetStatus("72%")
        xrayEnabled = true
        local function applyToInstance(descendant: Instance): ()
            if not xrayEnabled or not descendant:IsA("BasePart") then
                return
            end
            local localCharacter: Model? = LocalPlayer.Character
            local ancestorModel: Model? = descendant:FindFirstAncestorOfClass("Model")
            if (localCharacter and descendant:IsDescendantOf(localCharacter))
                or descendant:FindFirstAncestorOfClass("Tool")
                or (ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid")) then
                return
            end
            if originalXrayTransparency[descendant] == nil then
                originalXrayTransparency[descendant] = descendant.LocalTransparencyModifier
            end
            descendant.LocalTransparencyModifier = math.max(
                descendant.LocalTransparencyModifier,
                0.72
            )
        end

        featureConnections.Xray = workspace.DescendantAdded:Connect(applyToInstance)
        task.spawn(function(): ()
            for index: number, descendant: Instance in ipairs(workspace:GetDescendants()) do
                if not xrayEnabled then
                    return
                end
                applyToInstance(descendant)
                if index % 240 == 0 then
                    task.wait()
                end
            end
        end)
    end

    feature = createUniversalFeature(
        "X-Ray",
        "Fade map geometry locally while keeping your character clear",
        18,
        toggleXray,
        {noOptions = true, categoryName = "Render"}
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("Xray")
        restoreXray()
    end
    Module.Initialized = true
    return feature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/HighJump.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "HighJump",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local highJumpSettings: {velocity: number} = {velocity = 72}

    local function performHighJump(): ()
        local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end
        local current: Vector3 = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(
            current.X,
            highJumpSettings.velocity,
            current.Z
        )

        if humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        end
    end

    local HighJumpFeature = createUniversalFeature(
        "HighJump",
        "Press the key slot to launch a single high jump",
        19,
        performHighJump,
        {
            action = true,
            silentAction = true,
            configKey = "Universal.HighJump",
            categoryName = "Blatant",
        }
    )
    addNumberOption(
        HighJumpFeature,
        "Jump velocity",
        highJumpSettings.velocity,
        25,
        220,
        function(value: number): ()
            highJumpSettings.velocity = value
        end
    )

    activeCleanup = function(): ()

    end
    Module.Initialized = true
    return HighJumpFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/Spider.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Spider",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addCycleOption: any = host.addCycleOption
    local addFeatureTooltip: any = host.addFeatureTooltip

    type SpiderSettings = {
        mode: string,
        speed: number,
        climbState: boolean,
    }
    local spiderSettings: SpiderSettings = {
        mode = "Velocity",
        speed = 30,
        climbState = true,
    }
    local SpiderFeature: any = nil
    local function toggleSpider(enabled: boolean): ()
        disconnectFeatureConnection("Spider")
        if not enabled then
            if SpiderFeature then
                SpiderFeature:SetStatus(nil)
            end
            return
        end
        SpiderFeature:SetStatus(spiderSettings.mode)
        local climbing: boolean = false
        featureConnections.Spider = TaskManager:Connect(function(deltaTime: number): ()
            local character: Model?, humanoidOrNil: Humanoid?, rootOrNil: BasePart? =
                getCharacterParts()
            if not character or not humanoidOrNil or not rootOrNil then
                climbing = false
                return
            end
            local humanoid: Humanoid = humanoidOrNil :: Humanoid
            local root: BasePart = rootOrNil :: BasePart
            local direction: Vector3 = humanoid.MoveDirection
            if direction.Magnitude < 0.05 then
                climbing = false
                return
            end

            local raycastParams: RaycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.RespectCanCollide = true
            local ignored: {Instance} = {character :: Instance}
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    table.insert(ignored, player.Character :: Instance)
                end
            end
            raycastParams.FilterDescendantsInstances = ignored

            local origin: Vector3 = root.Position
                - Vector3.new(0, math.max(humanoid.HipHeight - 0.5, 0), 0)
            local wall: RaycastResult? = workspace:Raycast(
                origin,
                direction.Unit * 2.5,
                raycastParams
            )
            local velocity: Vector3 = root.AssemblyLinearVelocity
            if not wall or math.abs((wall :: RaycastResult).Normal.Y) >= 0.35 then
                if climbing then

                    root.AssemblyLinearVelocity =
                        Vector3.new(velocity.X, 0, velocity.Z)
                    climbing = false
                end
                return
            end

            climbing = true
            if spiderSettings.climbState then
                humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
            end
            if spiderSettings.mode == "CFrame" then
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
                root.CFrame = root.CFrame
                    + Vector3.new(0, spiderSettings.speed * deltaTime, 0)
            elseif spiderSettings.mode == "Impulse" then
                root:ApplyImpulse(
                    Vector3.new(0, spiderSettings.speed, 0) * root.AssemblyMass
                )
            else
                root.AssemblyLinearVelocity =
                    Vector3.new(velocity.X, spiderSettings.speed, velocity.Z)
            end
        end)
    end

    SpiderFeature = createUniversalFeature(
        "Spider",
        "Climb a wall automatically while moving into it",
        20,
        toggleSpider,
        {categoryName = "Blatant"}
    )
    addCycleOption(
        SpiderFeature,
        "Mode",
        {"Velocity", "Impulse", "CFrame"},
        1,
        function(value: string): ()
            spiderSettings.mode = value
            if SpiderFeature.enabled then
                SpiderFeature:SetStatus(value)
            end
        end,
        "Velocity is smooth and works nearly everywhere; Impulse survives games "
            .. "that rewrite your velocity every frame; CFrame works when both are "
            .. "clamped and is the most obvious of the three."
    )
    addNumberOption(
        SpiderFeature,
        "Climb speed",
        spiderSettings.speed,
        5,
        100,
        function(value: number): ()
            spiderSettings.speed = value
        end
    )
    addToggleOption(
        SpiderFeature,
        "Climb state",
        spiderSettings.climbState,
        function(value: boolean): ()
            spiderSettings.climbState = value
        end,
        "Puts the humanoid in its climbing state, so the animation matches and "
            .. "games that read the state see a climb instead of a jump."
    )
    addFeatureTooltip(
        SpiderFeature,
        "Walk into a wall to climb it. The climb stops with the wall, so reaching "
            .. "the top steps onto it instead of launching you off."
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("Spider")
    end
    Module.Initialized = true
    return SpiderFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/WallHop.lua"] = [[export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

type WallSighting = {
    part: BasePart,
    normal: Vector3,
    direction: Vector3,
    distance: number,
}

local Module = {
    Name = "WallHop",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

local SCAN_DIRECTIONS: number = 8
local SCAN_HEIGHTS: {number} = {-2.35, 0.2, 1.2}
local ARROWS: {string} = {"↑", "↗", "→", "↘", "↓", "↙", "←", "↖"}

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local movementInput: any = context.services.movementInput
    local getCharacterParts: any = host.getCharacterParts
    local currentWorkspace: Workspace = host.workspace or workspace
    local lastHopAt: number = -math.huge
    local lastScanAt: number = -math.huge
    local nearestWall: WallSighting? = nil
    local highlight: Highlight? = nil

    local function destroyHighlight(): ()
        if highlight then
            highlight:Destroy()
            highlight = nil
        end
    end

    local function findWall(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        range: number
    ): WallSighting?
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = {character}
        parameters.IgnoreWater = true
        parameters.RespectCanCollide = true

        local best: WallSighting? = nil
        for directionIndex: number = 0, SCAN_DIRECTIONS - 1 do
            local angle: number = (directionIndex / SCAN_DIRECTIONS) * math.pi * 2
            local direction: Vector3 = Vector3.new(
                math.sin(angle),
                0,
                math.cos(angle)
            )
            for _, height: number in ipairs(SCAN_HEIGHTS) do
                local origin: Vector3 = root.Position + Vector3.new(0, height, 0)
                local hit: RaycastResult? = currentWorkspace:Raycast(
                    origin,
                    direction * range,
                    parameters
                )
                if hit
                    and hit.Instance
                    and hit.Instance:IsA("BasePart")
                    and math.abs(hit.Normal.Y) <= 0.35 then
                    if best == nil or hit.Distance < best.distance then
                        best = {
                            part = hit.Instance,
                            normal = Vector3.new(
                                hit.Normal.X,
                                0,
                                hit.Normal.Z
                            ),
                            direction = direction,
                            distance = hit.Distance,
                        }
                    end
                    break
                end
            end
        end
        if best and best.normal.Magnitude > 0.01 then
            best.normal = best.normal.Unit
        else
            best = nil
        end
        return best
    end

    local function wallArrow(root: BasePart, sighting: WallSighting): string
        local flatLook: Vector3 = Vector3.new(
            root.CFrame.LookVector.X,
            0,
            root.CFrame.LookVector.Z
        )
        if flatLook.Magnitude < 0.01 then
            return "↑"
        end
        flatLook = flatLook.Unit
        local flatDirection: Vector3 = sighting.direction
        local angle: number = math.atan2(
            flatLook:Cross(flatDirection).Y,
            flatLook:Dot(flatDirection)
        )
        local index: number = math.floor(
            (angle / (math.pi * 2)) * SCAN_DIRECTIONS + 0.5
        ) % SCAN_DIRECTIONS
        -- Arrows are listed clockwise starting at forward; atan2 grows
        -- counter-clockwise, so mirror the index.
        index = (SCAN_DIRECTIONS - index) % SCAN_DIRECTIONS + 1
        return ARROWS[index]
    end

    local card: any
    local function clearVisuals(): ()
        nearestWall = nil
        destroyHighlight()
    end

    card = framework.Categories.Blatant:CreateModule({
        Name = "WallHop",
        Category = "Blatant",
        ConfigKey = "Universal.WallHop",
        Order = 31,
        Tooltip = "Detect walls and thin ledges around you and wall hop off "
            .. "them with one realistic jump.",
        Function = function(enabled: boolean): ()
            clearVisuals()
            lastHopAt = -math.huge
            if not enabled then
                card:SetStatus(nil)
                return
            end
            card:SetStatus("ready")

            card:Clean(movementInput.onJumpRequest(function(): ()
                local now: number = os.clock()
                if now - lastHopAt < 0.3 then
                    return
                end
                local character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not character or not humanoid or not root
                    or humanoid.Health <= 0
                    or humanoid.FloorMaterial == Enum.Material.Air then
                    return
                end

                local range: number = tonumber(card.Options["Wall range"].Value) or 2.6
                local kick: number = tonumber(card.Options["Kick strength"].Value) or 14
                local sighting: WallSighting? = findWall(character, humanoid, root, range)
                if not sighting then
                    return
                end

                lastHopAt = now
                local jumpVelocity: number = 50
                if humanoid.UseJumpPower then
                    jumpVelocity = math.max(humanoid.JumpPower, 16)
                elseif humanoid.JumpHeight > 0 then
                    jumpVelocity = math.sqrt(
                        2 * currentWorkspace.Gravity * humanoid.JumpHeight
                    )
                end
                local velocity: Vector3 = root.AssemblyLinearVelocity
                -- One clean impulse: kick away from the wall plus a natural
                -- jump arc. No teleports, no chained boosts.
                root.AssemblyLinearVelocity = Vector3.new(
                    velocity.X * 0.35 + sighting.normal.X * kick,
                    math.max(velocity.Y, jumpVelocity + 3),
                    velocity.Z * 0.35 + sighting.normal.Z * kick
                )
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                card:SetStatus("hop")
            end))

            card:Loop(function(): ()
                local now: number = os.clock()
                if now - lastScanAt < 0.07 then
                    return
                end
                lastScanAt = now

                local character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not character or not humanoid or not root
                    or humanoid.Health <= 0 then
                    clearVisuals()
                    return
                end

                local range: number = tonumber(card.Options["Wall range"].Value) or 2.6
                local sighting: WallSighting? = findWall(character, humanoid, root, range)
                nearestWall = sighting

                local grounded: boolean = humanoid.FloorMaterial ~= Enum.Material.Air
                if not sighting or not grounded then
                    destroyHighlight()
                    card:SetStatus(grounded and "ready" or nil)
                    return
                end

                card:SetStatus(wallArrow(root, sighting))
                if card.Options["Highlight walls"].Value ~= true then
                    destroyHighlight()
                    return
                end
                if not highlight or not highlight.Parent then
                    highlight = Instance.new("Highlight")
                    highlight.Name = "Wurst_WallHop"
                    highlight.FillColor = Color3.fromRGB(64, 255, 140)
                    highlight.FillTransparency = 0.82
                    highlight.OutlineColor = Color3.fromRGB(64, 255, 140)
                    highlight.OutlineTransparency = 0.1
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Parent = currentWorkspace
                end
                if (highlight :: Highlight).Adornee ~= sighting.part then
                    (highlight :: Highlight).Adornee = sighting.part
                end
            end)
        end,
    })

    card:CreateSlider({
        Name = "Wall range",
        Min = 1.5,
        Max = 5,
        Default = 2.6,
        Step = 0.1,
        Tooltip = "How far from a wall you can be to wall hop.",
    })
    card:CreateSlider({
        Name = "Kick strength",
        Min = 8,
        Max = 26,
        Default = 14,
        Step = 1,
        Tooltip = "Horizontal push away from the wall on each hop.",
    })
    card:CreateToggle({
        Name = "Highlight walls",
        Default = true,
        Tooltip = "Outline the wall you can currently wall hop off.",
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        pcall(activeCard.Toggle, false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/World/SafeWalk.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "SafeWalk",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local currentWorkspace: Workspace = host.workspace or workspace

    local safeWalkSettings: {
        lookAhead: number,
        barrierHeight: number,
    } = {
        lookAhead = 2.8,
        barrierHeight = 4.5,
    }

    local barrierFolder: Folder? = nil
    local barrier: BasePart? = nil
    local SafeWalkFeature: any = nil

    local function ensureBarrier(): BasePart
        local existing: BasePart? = barrier
        if existing and existing.Parent then
            return existing
        end
        if not barrierFolder or not barrierFolder.Parent then
            barrierFolder = Instance.new("Folder")
            barrierFolder.Name = "WurstSafeWalk"
            barrierFolder.Parent = currentWorkspace
        end
        local part: BasePart = Instance.new("Part")
        part.Name = "SafeWalkBarrier"
        part.Anchored = true
        part.CanCollide = true
        part.CanQuery = false
        part.CanTouch = false
        part.Massless = true
        part.CastShadow = false
        part.Transparency = 1
        part.Material = Enum.Material.SmoothPlastic
        part.Size = Vector3.new(7, safeWalkSettings.barrierHeight, 0.35)
        part:SetAttribute("WurstSafeWalk", true)
        part.Parent = barrierFolder
        barrier = part
        return part
    end

    local function hideBarrier(): ()
        if barrierFolder then
            barrierFolder:Destroy()
        end
        barrierFolder = nil
        barrier = nil
    end

    local function toggleSafeWalk(enabled: boolean): ()
        disconnectFeatureConnection("SafeWalk")
        hideBarrier()
        if not enabled then
            if SafeWalkFeature then
                SafeWalkFeature:SetStatus(nil)
            end
            return
        end

        featureConnections.SafeWalk = TaskManager:Connect(function(): ()
            local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not character or not humanoid or not root
                or humanoid.Health <= 0 then
                hideBarrier()
                return
            end
            -- While airborne or standing still the last barrier stays in place
            -- so momentum cannot carry you over an edge mid-jump.
            if humanoid.MoveDirection.Magnitude < 0.05 then
                return
            end
            if humanoid.FloorMaterial == Enum.Material.Air then
                return
            end

            local moveDirection: Vector3 = humanoid.MoveDirection.Unit
            local parameters: RaycastParams = RaycastParams.new()
            parameters.FilterType = Enum.RaycastFilterType.Exclude
            parameters.FilterDescendantsInstances = {character}
            parameters.IgnoreWater = true

            -- Sample the ground along the movement direction to find where the
            -- floor ends. The barrier is placed just before that edge.
            local stepCount: number = 7
            local reach: number = 1.0 + safeWalkSettings.lookAhead + 0.8
            local step: number = (reach - 1.0) / (stepCount - 1)
            local lastGrounded: number? = nil
            local firstGap: number? = nil
            for index: number = 1, stepCount do
                local distance: number = 1.0 + step * (index - 1)
                local probeOrigin: Vector3 = root.Position + moveDirection * distance
                local ground: RaycastResult? = currentWorkspace:Raycast(
                    probeOrigin,
                    Vector3.new(0, -6, 0),
                    parameters
                )
                if ground then
                    lastGrounded = distance
                elseif lastGrounded ~= nil then
                    firstGap = distance
                    break
                end
            end

            if lastGrounded == nil then
                -- The edge is already under the feet: block right ahead.
                lastGrounded = 0.4
                firstGap = 1.0
            end
            if firstGap == nil then
                -- Solid floor ahead: nothing to block.
                hideBarrier()
                if SafeWalkFeature then
                    SafeWalkFeature:SetStatus(nil)
                end
                return
            end

            local edgeDistance: number = (lastGrounded + firstGap) * 0.5
            local feetHeight: number = root.Size.Y * 0.5 + humanoid.HipHeight
            local barrierHeight: number = math.max(safeWalkSettings.barrierHeight, 3)
            local part: BasePart = ensureBarrier()
            part.Size = Vector3.new(7, barrierHeight, 0.35)
            local feetY: number = root.Position.Y - feetHeight
            local position: Vector3 = root.Position + moveDirection * edgeDistance
            -- Thin axis (Z) points along the movement direction, so the wide
            -- face of the part faces the player like a wall.
            part.CFrame = CFrame.lookAt(
                Vector3.new(position.X, feetY + barrierHeight * 0.5, position.Z),
                Vector3.new(position.X, feetY + barrierHeight * 0.5, position.Z)
                    + moveDirection
            )
            if SafeWalkFeature then
                SafeWalkFeature:SetStatus("edge")
            end
        end)
    end

    SafeWalkFeature = createUniversalFeature(
        "SafeWalk",
        "Place an invisible barrier at edges so you cannot walk off ledges",
        21,
        toggleSafeWalk,
        {
            configKey = "Universal.SafeWalk",
            categoryName = "Movement",
        }
    )
    addNumberOption(
        SafeWalkFeature,
        "Edge look-ahead",
        safeWalkSettings.lookAhead,
        1.5,
        6,
        function(value: number): ()
            safeWalkSettings.lookAhead = value
        end
    )
    addNumberOption(
        SafeWalkFeature,
        "Barrier height",
        safeWalkSettings.barrierHeight,
        3,
        10,
        function(value: number): ()
            safeWalkSettings.barrierHeight = value
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("SafeWalk")
        hideBarrier()
    end
    Module.Initialized = true
    return SafeWalkFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/World/RejoinServer.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "RejoinServer",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local createUniversalFeature: any = host.createUniversalFeature
    local cloneReference: any = host.cloneReference
    local notify: (string) -> () = host.notify
    local function rejoinCurrentServer(): ()
        local teleportService: TeleportService = cloneReference(
            game:GetService("TeleportService")
        )
        local placeId: number = game.PlaceId
        local jobId: string = tostring(game.JobId or "")

        local rejoined: boolean = false
        if jobId ~= "" then
            rejoined = pcall(function(): ()
                teleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
            end)
        end
        if not rejoined then
            local ok: boolean, teleportError: any = pcall(function(): ()
                teleportService:Teleport(placeId, LocalPlayer)
            end)
            if not ok then
                notify("Rejoin failed: " .. tostring(teleportError))
            end
        end
    end
    local actionId: string = "RejoinServer"
    local registries: any = context.services.registries
    local wurstOptions: any = registries.wurstOptions()
    if wurstOptions and type(wurstOptions.RegisterAction) == "function" then
        local registered: boolean, registration: any = pcall(
            wurstOptions.RegisterAction,
            actionId,
            "Rejoin Server",
            rejoinCurrentServer,
            {
                description = "Reconnect to the current server instance",
                configKey = "Universal.RejoinServer",
            }
        )
        if not registered then
            error("Wurst Options refused Rejoin Server: " .. tostring(registration))
        end
        local search: any = registries.moduleSearch()
        local searchFeature: any = {
            name = "Rejoin Server",
            configKey = "Universal.RejoinServer",
            kind = "action",
            searchable = false,
            enabled = false,
            activate = rejoinCurrentServer,
        }
        if search and type(search.Register) == "function" then
            search.Register(searchFeature)
        end
        activeCleanup = function(): ()
            if search and type(search.Unregister) == "function" then
                search.Unregister(searchFeature)
            end
            if type(registration) == "table"
                and type(registration.Unregister) == "function" then
                registration.Unregister()
            elseif type(wurstOptions.UnregisterAction) == "function" then
                pcall(wurstOptions.UnregisterAction, actionId)
            end
        end
        Module.Initialized = true
        return registration
    end

    local feature: any = createUniversalFeature(
        "Rejoin Server",
        "Reconnect to the current server instance",
        22,
        rejoinCurrentServer,
        {
            action = true,
            noOptions = true,
            categoryName = "Other",
            searchable = false,
        }
    )

    activeCleanup = function(): () end
    Module.Initialized = true
    return feature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/ZoomUnlocker.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ZoomUnlocker",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    type ZoomSettings = {
        minDistance: number,
        maxDistance: number,
        unlockFirstPerson: boolean,
    }
    type ZoomState = {
        minDistance: number,
        maxDistance: number,
        cameraMode: Enum.CameraMode,
    }
    local zoomSettings: ZoomSettings = {
        minDistance = 0.5,
        maxDistance = 400,
        unlockFirstPerson = true,
    }
    local originalZoomState: ZoomState? = nil
    local ZoomFeature: any = nil

    local function toggleZoomUnlocker(enabled: boolean): ()
        disconnectFeatureConnection("ZoomUnlocker")
        if originalZoomState then
            LocalPlayer.CameraMinZoomDistance = originalZoomState.minDistance
            LocalPlayer.CameraMaxZoomDistance = originalZoomState.maxDistance
            LocalPlayer.CameraMode = originalZoomState.cameraMode
            originalZoomState = nil
        end
        if not enabled then
            if ZoomFeature then ZoomFeature:SetStatus(nil) end
            return
        end
        ZoomFeature:SetStatus(tostring(math.round(zoomSettings.maxDistance)) .. " studs")
        originalZoomState = {
            minDistance = LocalPlayer.CameraMinZoomDistance,
            maxDistance = LocalPlayer.CameraMaxZoomDistance,
            cameraMode = LocalPlayer.CameraMode,
        }
        featureConnections.ZoomUnlocker = TaskManager:Connect(function(): ()
            LocalPlayer.CameraMinZoomDistance = math.min(
                zoomSettings.minDistance,
                zoomSettings.maxDistance
            )
            LocalPlayer.CameraMaxZoomDistance = math.max(
                zoomSettings.minDistance,
                zoomSettings.maxDistance
            )
            if zoomSettings.unlockFirstPerson then
                LocalPlayer.CameraMode = Enum.CameraMode.Classic
            elseif originalZoomState then
                LocalPlayer.CameraMode = originalZoomState.cameraMode
            end
        end)
    end

    ZoomFeature = createUniversalFeature(
        "Zoom",
        "Extend camera zoom and optionally leave forced first person",
        23,
        toggleZoomUnlocker,
        {
            configKey = "Universal.ZoomUnlocker",
            categoryName = "Render",
        }
    )
    addNumberOption(
        ZoomFeature,
        "Maximum distance",
        zoomSettings.maxDistance,
        25,
        2000,
        function(value: number): ()
            zoomSettings.maxDistance = value
            if ZoomFeature.enabled then
                ZoomFeature:SetStatus(tostring(math.round(value)) .. " studs")
            end
        end
    )
    addNumberOption(
        ZoomFeature,
        "Minimum distance",
        zoomSettings.minDistance,
        0.5,
        50,
        function(value: number): ()
            zoomSettings.minDistance = value
        end
    )
    addToggleOption(
        ZoomFeature,
        "Unlock forced first person",
        zoomSettings.unlockFirstPerson,
        function(value: boolean): ()
            zoomSettings.unlockFirstPerson = value
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("ZoomUnlocker")
        if originalZoomState then
            pcall(function(): ()
                LocalPlayer.CameraMinZoomDistance = originalZoomState.minDistance
                LocalPlayer.CameraMaxZoomDistance = originalZoomState.maxDistance
                LocalPlayer.CameraMode = originalZoomState.cameraMode
            end)
            originalZoomState = nil
        end
    end
    Module.Initialized = true
    return ZoomFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/World/InteractExtender.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "InteractExtender",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    type InteractionSettings = {
        distance: number,
        instantPrompts: boolean,
        proximityPrompts: boolean,
        clickDetectors: boolean,
    }
    type PromptState = {distance: number, holdDuration: number}
    local interactionSettings: InteractionSettings = {
        distance = 32,
        instantPrompts = false,
        proximityPrompts = true,
        clickDetectors = true,
    }
    local originalPrompts: {[ProximityPrompt]: PromptState} =
        setmetatable({}, {__mode = "k"}) :: any
    local originalClickDetectors: {[ClickDetector]: number} =
        setmetatable({}, {__mode = "k"}) :: any
    local interactionExtenderEnabled: boolean = false
    local InteractFeature: any = nil
    local interactionRefreshClock: number = 0

    local function refreshInteractionExtender(): ()
        for prompt: ProximityPrompt, original: PromptState in pairs(originalPrompts) do
            if not prompt.Parent then
                continue
            end
            local wantedDistance: number = interactionExtenderEnabled
                    and interactionSettings.proximityPrompts
                    and interactionSettings.distance
                or original.distance
            local wantedHold: number = interactionExtenderEnabled
                    and interactionSettings.proximityPrompts
                    and interactionSettings.instantPrompts
                    and 0
                or original.holdDuration

            if prompt.MaxActivationDistance ~= wantedDistance then
                prompt.MaxActivationDistance = wantedDistance
            end
            if prompt.HoldDuration ~= wantedHold then
                prompt.HoldDuration = wantedHold
            end
        end
        for detector: ClickDetector, originalDistance: number in pairs(originalClickDetectors) do
            if not detector.Parent then
                continue
            end
            local wantedDistance: number = interactionExtenderEnabled
                    and interactionSettings.clickDetectors
                    and interactionSettings.distance
                or originalDistance
            if detector.MaxActivationDistance ~= wantedDistance then
                detector.MaxActivationDistance = wantedDistance
            end
        end
    end

    local function applyInteractionExtension(instance: Instance): ()
        if not interactionExtenderEnabled then
            return
        end
        if instance:IsA("ProximityPrompt") then
            if originalPrompts[instance] == nil then
                originalPrompts[instance] = {
                    distance = instance.MaxActivationDistance,
                    holdDuration = instance.HoldDuration,
                }
            end
            local original: PromptState = originalPrompts[instance]
            instance.MaxActivationDistance = interactionSettings.proximityPrompts
                    and interactionSettings.distance
                or original.distance
            instance.HoldDuration = interactionSettings.proximityPrompts
                    and interactionSettings.instantPrompts
                    and 0
                or original.holdDuration
        elseif instance:IsA("ClickDetector") then
            if originalClickDetectors[instance] == nil then
                originalClickDetectors[instance] = instance.MaxActivationDistance
            end
            instance.MaxActivationDistance = interactionSettings.clickDetectors
                    and interactionSettings.distance
                or originalClickDetectors[instance]
        end
    end

    local function restoreInteractionExtender(): ()
        interactionExtenderEnabled = false
        refreshInteractionExtender()
        originalPrompts = setmetatable({}, {__mode = "k"}) :: any
        originalClickDetectors = setmetatable({}, {__mode = "k"}) :: any
    end

    local function toggleInteractionExtender(enabled: boolean): ()
        disconnectFeatureConnection("InteractExtender")
        disconnectFeatureConnection("InteractExtenderRefresh")
        restoreInteractionExtender()
        interactionRefreshClock = 0
        if not enabled then
            if InteractFeature then InteractFeature:SetStatus(nil) end
            return
        end
        InteractFeature:SetStatus(tostring(math.round(interactionSettings.distance)) .. " studs")
        interactionExtenderEnabled = true
        featureConnections.InteractExtender = workspace.DescendantAdded:Connect(
            applyInteractionExtension
        )
        featureConnections.InteractExtenderRefresh = TaskManager:Connect(
            function(deltaTime: number): ()
                interactionRefreshClock += deltaTime
                if interactionRefreshClock >= 0.5 then
                    interactionRefreshClock = 0
                    refreshInteractionExtender()
                end
            end
        )
        task.spawn(function(): ()
            for index: number, instance: Instance in ipairs(workspace:GetDescendants()) do
                if not interactionExtenderEnabled then
                    return
                end
                applyInteractionExtension(instance)
                if index % 240 == 0 then
                    task.wait()
                end
            end
        end)
    end

    InteractFeature = createUniversalFeature(
        "Interact Extender",
        "Extend prompt and click interaction range without auto-firing",
        24,
        toggleInteractionExtender,
        {categoryName = "Other"}
    )
    addNumberOption(
        InteractFeature,
        "Interaction distance",
        interactionSettings.distance,
        8,
        250,
        function(value: number): ()
            interactionSettings.distance = value
            if InteractFeature.enabled then
                InteractFeature:SetStatus(tostring(math.round(value)) .. " studs")
            end
            refreshInteractionExtender()
        end
    )
    addToggleOption(
        InteractFeature,
        "Instant prompts",
        interactionSettings.instantPrompts,
        function(value: boolean): ()
            interactionSettings.instantPrompts = value
            refreshInteractionExtender()
        end
    )
    addToggleOption(
        InteractFeature,
        "Proximity prompts",
        interactionSettings.proximityPrompts,
        function(value: boolean): ()
            interactionSettings.proximityPrompts = value
            refreshInteractionExtender()
        end
    )
    addToggleOption(
        InteractFeature,
        "Click detectors",
        interactionSettings.clickDetectors,
        function(value: boolean): ()
            interactionSettings.clickDetectors = value
            refreshInteractionExtender()
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("InteractExtender")
        disconnectFeatureConnection("InteractExtenderRefresh")
        restoreInteractionExtender()
        interactionRefreshClock = 0
        if InteractFeature then
            InteractFeature:SetStatus(nil)
        end
    end
    Module.Initialized = true
    return InteractFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/PhaseDash.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "PhaseDash",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local getCharacterParts: any = host.getCharacterParts
    local shortcuts: any = context.services.shortcuts
    type PhaseDashSettings = {
        mode: string,
        distance: number,
        cooldown: number,
        exitSpeed: number,
        slideSpeed: number,
        collisionPadding: number,
        flashDuration: number,
        preserveVelocity: boolean,
    }
    local phaseDashSettings: PhaseDashSettings = {
        mode = "Blink",
        distance = 20,
        cooldown = 0.8,
        exitSpeed = 42,
        slideSpeed = 60,
        collisionPadding = 2.25,
        flashDuration = 0.28,
        preserveVelocity = true,
    }
    local lastPhaseDash: number = -math.huge
    local phaseDashEnabled: boolean = false

    local function createPhaseFlash(character: Model): ()
        local oldFlash: Instance? = character:FindFirstChild("Wurst_PhaseDashFlash")
        if oldFlash then
            oldFlash:Destroy()
        end
        local flash: Highlight = Instance.new("Highlight")
        flash.Name = "Wurst_PhaseDashFlash"
        flash.Adornee = character
        flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        flash.FillColor = Theme.accentDim
        flash.FillTransparency = 0.42
        flash.OutlineColor = Theme.accent
        flash.OutlineTransparency = 0.05
        flash.Parent = character
        local fade: Tween = TweenService:Create(
            flash,
            TweenInfo.new(
                math.clamp(phaseDashSettings.flashDuration, 0.05, 1.2),
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ),
            {FillTransparency = 1, OutlineTransparency = 1}
        )
        fade:Play()
        fade.Completed:Once(function(): ()
            if flash.Parent then
                flash:Destroy()
            end
        end)
    end

    local function performPhaseDash(): ()
        if not phaseDashEnabled then
            return
        end
        local now: number = os.clock()
        if now - lastPhaseDash < phaseDashSettings.cooldown then
            return
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        local camera: Camera? = workspace.CurrentCamera
        if not character or not humanoid or not root or not camera then
            return
        end
        local direction: Vector3 = humanoid.MoveDirection
        if direction.Magnitude < 0.05 then
            direction = Vector3.new(
                camera.CFrame.LookVector.X,
                0,
                camera.CFrame.LookVector.Z
            )
        end
        if direction.Magnitude < 0.05 then
            return
        end
        direction = direction.Unit
        lastPhaseDash = now
        local previousVelocity: Vector3 = root.AssemblyLinearVelocity
        local padding: number = math.clamp(
            phaseDashSettings.collisionPadding,
            0,
            8
        )
        if phaseDashSettings.mode == "Slide" then

            root.AssemblyLinearVelocity = direction * phaseDashSettings.slideSpeed
                + Vector3.new(0, previousVelocity.Y, 0)
            createPhaseFlash(character)
            return
        end

        local params: RaycastParams = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {character}
        local collision: RaycastResult? = workspace:Raycast(
            root.Position,
            direction * phaseDashSettings.distance,
            params
        )
        local safeDistance: number = collision
                and math.max(0, collision.Distance - padding)
            or phaseDashSettings.distance
        if safeDistance <= 0.1 then
            return
        end
        root.CFrame = root.CFrame + direction * safeDistance
        if not phaseDashSettings.preserveVelocity then
            root.AssemblyLinearVelocity = direction * phaseDashSettings.exitSpeed
                + Vector3.new(0, previousVelocity.Y, 0)
        end
        createPhaseFlash(character)
    end

    local phaseDash: any
    phaseDash = framework.Categories.Blatant:CreateModule({
        Name = "Phase Dash",
        Category = "Blatant",
        Tooltip = "Directional dash: collision-aware blink or a velocity slide. "
            .. "The card's key slot is the dash key.",
        Function = function(enabled: boolean): ()
            phaseDashEnabled = enabled
            phaseDash:SetStatus(enabled and phaseDashSettings.mode or nil)

        end,
    })
    phaseDash:CreateDropdown({
        Name = "Mode",
        List = {"Blink", "Slide"},
        Index = 1,
        Function = function(value: string): ()
            phaseDashSettings.mode = value
            if phaseDash.Enabled then
                phaseDash:SetStatus(value)
            end
        end,
    })
    phaseDash:CreateSlider({
        Name = "Dash distance",
        Show = {Option = "Mode", Values = {"Blink"}},
        Min = 4,
        Max = 80,
        Default = phaseDashSettings.distance,
        Function = function(value: number): ()
            phaseDashSettings.distance = value
        end,
        Tooltip = "How far a blink tries to move before the wall check "
            .. "shortens it.",
    })
    phaseDash:CreateSlider({
        Name = "Exit speed",
        Show = {Option = "Mode", Values = {"Blink"}},
        Min = 0,
        Max = 180,
        Default = phaseDashSettings.exitSpeed,
        Function = function(value: number): ()
            phaseDashSettings.exitSpeed = value
        end,
        Tooltip = "The velocity a blink leaves you with when Preserve "
            .. "velocity is off.",
    })
    phaseDash:CreateSlider({
        Name = "Slide speed",
        Show = {Option = "Mode", Values = {"Slide"}},
        Min = 20,
        Max = 250,
        Default = phaseDashSettings.slideSpeed,
        Function = function(value: number): ()
            phaseDashSettings.slideSpeed = value
        end,
    })
    phaseDash:CreateSlider({
        Name = "Collision padding",
        Show = {Option = "Mode", Values = {"Blink"}},
        Min = 0,
        Max = 8,
        Default = phaseDashSettings.collisionPadding,
        Function = function(value: number): ()
            phaseDashSettings.collisionPadding = value
        end,
        Tooltip = "Studs of clearance kept between you and whatever the blink "
            .. "stopped at.",
    })
    phaseDash:CreateSlider({
        Name = "Flash duration (s)",
        Min = 0.05,
        Max = 1.2,
        Default = phaseDashSettings.flashDuration,
        Function = function(value: number): ()
            phaseDashSettings.flashDuration = value
        end,
    })
    phaseDash:CreateToggle({
        Name = "Preserve velocity",
        Show = {Option = "Mode", Values = {"Blink"}},
        Default = phaseDashSettings.preserveVelocity,
        Function = function(value: boolean): ()
            phaseDashSettings.preserveVelocity = value
        end,
        Tooltip = "Keep the velocity you had before the blink instead of "
            .. "replacing it with Exit speed.",
    })

    phaseDash:CreateSlider({
        Name = "Cooldown",
        Min = 0.1,
        Max = 5,
        Default = phaseDashSettings.cooldown,
        Function = function(value: number): ()
            phaseDashSettings.cooldown = value
        end,
    })

    shortcuts.bindActivation(phaseDash.Feature, nil, performPhaseDash)

    activeCleanup = function(): ()
        phaseDashEnabled = false
    end
    Module.Initialized = true
    return phaseDash
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/NoFall.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "NoFall",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local getCharacterParts: any = host.getCharacterParts

    type NoFallSettings = {
        mode: string,
        safeSpeed: number,
        scanDistance: number,
        resetRecord: boolean,
    }
    local noFallSettings: NoFallSettings = {
        mode = "Both",
        safeSpeed = 30,
        scanDistance = 14,
        resetRecord = true,
    }

    local noFall: any
    noFall = framework.Categories.Protection:CreateModule({
        Name = "NoFall",
        Category = "Blatant",
        ConfigKey = "Universal.NoFall",
        Tooltip = "Fall damage is written by the game, on this client: this "
            .. "hands its formula a landing it considers safe instead of "
            .. "blocking anything.",
        Function = function(enabled: boolean): ()
            if not enabled then
                noFall:SetStatus(nil)
                return
            end
            noFall:SetStatus(noFallSettings.mode)
            local nextRecordResetAt: number = 0
            local landedThisFall: boolean = false
            noFall:Loop(function(): ()
                local character: Model?, humanoidOrNil: Humanoid?, rootOrNil: BasePart? =
                    getCharacterParts()
                if not character or not humanoidOrNil or not rootOrNil then
                    return
                end
                local humanoid: Humanoid = humanoidOrNil :: Humanoid
                local root: BasePart = rootOrNil :: BasePart
                if humanoid.SeatPart or humanoid.Health <= 0 then
                    return
                end

                local velocity: Vector3 = root.AssemblyLinearVelocity
                local airborne: boolean = humanoid.FloorMaterial == Enum.Material.Air
                if not airborne or velocity.Y >= -1 then
                    landedThisFall = false
                    nextRecordResetAt = 0
                    return
                end

                local now: number = os.clock()
                if noFallSettings.resetRecord
                    and noFallSettings.mode ~= "Impact"
                    and now >= nextRecordResetAt then
                    nextRecordResetAt = now + 0.35
                    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
                end

                local probe: number = math.max(
                    noFallSettings.scanDistance,
                    math.abs(velocity.Y) * 0.16
                )
                local params: RaycastParams = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = {character :: Instance}
                local ground: RaycastResult? = workspace:Raycast(
                    root.Position,
                    Vector3.new(0, -probe, 0),
                    params
                )
                if not ground then
                    return
                end

                if noFallSettings.mode ~= "State"
                    and velocity.Y < -noFallSettings.safeSpeed then
                    root.AssemblyLinearVelocity = Vector3.new(
                        velocity.X,
                        -noFallSettings.safeSpeed,
                        velocity.Z
                    )
                end
                if noFallSettings.mode ~= "Impact" and not landedThisFall then

                    landedThisFall = true
                    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
                end
            end)
        end,
    })
    noFall:CreateDropdown({
        Name = "Mode",
        List = {"Both", "Impact", "State"},
        Index = 1,
        Function = function(value: string): ()
            noFallSettings.mode = value
            if noFall.Enabled then
                noFall:SetStatus(value)
            end
        end,
        Tooltip = "Impact brakes the fall just above the ground, for games "
            .. "that read your landing speed. State closes the humanoid's "
            .. "fall measurement early, for games that count the drop "
            .. "between Freefall and Landed. Both covers either, and is "
            .. "what you want unless one of them fights the game.",
    })
    noFall:CreateSlider({
        Name = "Safe landing speed",
        Show = {Option = "Mode", Values = {"Both", "Impact"}},
        Min = 5,
        Max = 80,
        Default = noFallSettings.safeSpeed,
        Function = function(value: number): ()
            noFallSettings.safeSpeed = value
        end,
        Tooltip = "The vertical speed the landing is allowed to have. Most "
            .. "games start hurting somewhere above 50.",
    })
    noFall:CreateToggle({
        Name = "Reset fall record",
        Show = {Option = "Mode", Values = {"Both", "State"}},
        Default = noFallSettings.resetRecord,
        Function = function(value: boolean): ()
            noFallSettings.resetRecord = value
        end,
        Tooltip = "Closes the humanoid's fall measurement every third of a "
            .. "second while you are in the air, so a game that measures the "
            .. "drop never sees more than a short one. Costs a little "
            .. "animation flicker on long falls.",
    })
    noFall:CreateSlider({
        Name = "Ground scan",
        Min = 4,
        Max = 40,
        Default = noFallSettings.scanDistance,
        Function = function(value: number): ()
            noFallSettings.scanDistance = value
        end,
        Tooltip = "How many studs above the floor the brake starts. Higher is "
            .. "safer and more visible; the module already scales this with "
            .. "your fall speed.",
    })

    Module.Initialized = true
    return noFall
end

function Module.destroy(): ()

    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/Fly.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Fly",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local movementInput: any = context.services.movementInput
    local platformStand: any = context.services.platformStandOwnership
    local mobileActions: any = context.services.mobileActions
    local getCharacterParts: any = host.getCharacterParts
    local UserInputService: any = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace

    type FlySettings = {
        method: string,
        floatMethod: string,
        speed: number,
        verticalSpeed: number,
        response: number,
        burstInterval: number,
        wallCheck: boolean,
        platformStand: boolean,
        faceCamera: boolean,
        upKey: Enum.KeyCode,
        downKey: Enum.KeyCode,
    }

    local flySettings: FlySettings = {
        method = "Velocity",
        floatMethod = "Velocity",
        speed = 70,
        verticalSpeed = 56,
        response = 1,
        burstInterval = 0.2,
        wallCheck = true,
        platformStand = true,
        faceCamera = true,
        upKey = Enum.KeyCode.Space,
        downKey = Enum.KeyCode.LeftControl,
    }

    local flyRuntime: any = {
        yLevel = nil :: number?,
        burstAt = 0,
        platform = nil :: BasePart?,
        walkSpeed = nil :: number?,
    }
    local flySmoothedVelocity: Vector3 = Vector3.zero

    local flyObjects: {[Instance]: boolean} =
        setmetatable({}, {__mode = "k"}) :: any
    local flyTouchVertical: number = 0

    local function removeFlyObjects(): ()
        platformStand.set("Fly", nil)

        for object: Instance in pairs(flyObjects) do
            if object.Parent then
                object:Destroy()
            end
        end
        flyObjects = setmetatable({}, {__mode = "k"}) :: any
    end

    local function restoreWalkSpeed(): ()
        local _, humanoid: Humanoid? = getCharacterParts()
        if humanoid and flyRuntime.walkSpeed then
            (humanoid :: Humanoid).WalkSpeed = flyRuntime.walkSpeed :: number
        end
        flyRuntime.walkSpeed = nil
    end

    local function ensureFlyConstraints(root: BasePart): (LinearVelocity, AlignOrientation)
        local attachment: Attachment? = root:FindFirstChild("Wurst_FlyAttachment") :: Attachment?
        if not attachment then
            local newAttachment: Attachment = Instance.new("Attachment")
            newAttachment.Name = "Wurst_FlyAttachment"
            newAttachment.Parent = root
            attachment = newAttachment
        end
        local resolvedAttachment: Attachment = attachment :: Attachment
        flyObjects[resolvedAttachment] = true

        local velocity: LinearVelocity? = root:FindFirstChild("Wurst_FlyVelocity") :: LinearVelocity?
        if not velocity then
            local newVelocity: LinearVelocity = Instance.new("LinearVelocity")
            newVelocity.Name = "Wurst_FlyVelocity"
            newVelocity.Attachment0 = resolvedAttachment
            newVelocity.MaxForce = math.huge
            newVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
            newVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            newVelocity.Parent = root
            velocity = newVelocity
        end
        flyObjects[velocity :: LinearVelocity] = true

        local orientation: AlignOrientation? =
            root:FindFirstChild("Wurst_FlyOrientation") :: AlignOrientation?
        if not orientation then
            local newOrientation: AlignOrientation = Instance.new("AlignOrientation")
            newOrientation.Name = "Wurst_FlyOrientation"
            newOrientation.Attachment0 = resolvedAttachment
            newOrientation.MaxTorque = math.huge
            newOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
            newOrientation.Responsiveness = 28
            newOrientation.RigidityEnabled = false
            newOrientation.Parent = root
            orientation = newOrientation
        end
        flyObjects[orientation :: AlignOrientation] = true

        return velocity :: LinearVelocity, orientation :: AlignOrientation
    end

    local function getFlyDirection(camera: Camera): (Vector3, number, Vector3)
        local cameraForward: Vector3 = Vector3.new(
            camera.CFrame.LookVector.X,
            0,
            camera.CFrame.LookVector.Z
        )
        local cameraRight: Vector3 = Vector3.new(
            camera.CFrame.RightVector.X,
            0,
            camera.CFrame.RightVector.Z
        )
        cameraForward = cameraForward.Magnitude > 0.001
            and cameraForward.Unit
            or Vector3.new(0, 0, -1)
        cameraRight = cameraRight.Magnitude > 0.001
            and cameraRight.Unit
            or Vector3.new(1, 0, 0)

        local forwardScalar: number, rightScalar: number = movementInput.getVector()
        local horizontal: Vector3 = cameraForward * forwardScalar
            + cameraRight * rightScalar
        if horizontal.Magnitude > 1 then
            horizontal = horizontal.Unit
        end

        local vertical: number = 0
        if flyTouchVertical > 0
            or (UserInputService.KeyboardEnabled
                and UserInputService:IsKeyDown(flySettings.upKey)) then
            vertical = vertical + 1
        end
        if flyTouchVertical < 0
            or (UserInputService.KeyboardEnabled
                and UserInputService:IsKeyDown(flySettings.downKey)) then
            vertical = vertical - 1
        end

        if vertical == 0 and not UserInputService.KeyboardEnabled and movementInput.isJumpHeld() then
            vertical = 1
        end

        return horizontal, vertical, cameraForward
    end

    local applyFlyHorizontal: (BasePart, Humanoid, Vector3, number) -> ()
    local applyFlyVertical: (BasePart, Humanoid, number, number) -> ()
    do
    applyFlyHorizontal = function(
        root: BasePart,
        humanoid: Humanoid,
        moveDirection: Vector3,
        deltaTime: number
    ): ()
        local method: string = flySettings.method
        local currentVelocity: Vector3 = root.AssemblyLinearVelocity
        local target: Vector3 = moveDirection * flySettings.speed

        if method == "WalkSpeed" then
            if not flyRuntime.walkSpeed then
                flyRuntime.walkSpeed = humanoid.WalkSpeed
            end
            humanoid.WalkSpeed = flySettings.speed
            return
        end

        if method == "Pulse" then

            local period: number = math.max(flySettings.burstInterval, 0.05) * 2
            local burst: boolean = (os.clock() % period) < (period * 0.5)
            target = target * (burst and 1.8 or 0.2)
        end

        if method == "CFrame" or method == "Blink" then
            local step: Vector3 = moveDirection * flySettings.speed * deltaTime
            if method == "Blink" then
                local interval: number = math.max(flySettings.burstInterval, 0.05)
                if os.clock() < flyRuntime.burstAt then
                    step = Vector3.zero
                else
                    flyRuntime.burstAt = os.clock() + interval
                    step = moveDirection * flySettings.speed * interval
                end
            end
            if step.Magnitude > 0.001 and flySettings.wallCheck then
                local raycastParams: RaycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                local wallHit: RaycastResult? = currentWorkspace:Raycast(
                    root.Position,
                    step + step.Unit * 2,
                    raycastParams
                )
                if wallHit then
                    step = Vector3.zero
                end
            end
            if step.Magnitude > 0.001 then
                root.CFrame = root.CFrame + step
            end

            root.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
            return
        end

        if method == "Impulse" then
            local difference: Vector3 = (target - currentVelocity)
                * Vector3.new(1, 0, 1)

            local threshold: number = moveDirection.Magnitude < 0.01 and 10 or 2
            if difference.Magnitude > threshold then
                root:ApplyImpulse(difference * root.AssemblyMass)
            end
            return
        end

        local alpha: number = 1 - math.exp(-12 * flySettings.response * deltaTime)
        flySmoothedVelocity = flySmoothedVelocity:Lerp(target, alpha)
        if method == "Constraint" then
            return
        end
        root.AssemblyLinearVelocity = Vector3.new(
            flySmoothedVelocity.X,
            currentVelocity.Y,
            flySmoothedVelocity.Z
        )
    end

    applyFlyVertical = function(
        root: BasePart,
        humanoid: Humanoid,
        vertical: number,
        deltaTime: number
    ): ()
        local method: string = flySettings.floatMethod
        local currentVelocity: Vector3 = root.AssemblyLinearVelocity
        local targetY: number = vertical * flySettings.verticalSpeed

        if method == "Floor" then
            local platform: BasePart? = flyRuntime.platform
            if not platform or not platform.Parent then
                local newPlatform: BasePart = Instance.new("Part")
                newPlatform.Name = "Wurst_FlyPlatform"
                newPlatform.Anchored = true
                newPlatform.CanQuery = false
                newPlatform.CanTouch = false
                newPlatform.Size = Vector3.new(8, 1, 8)
                newPlatform.Transparency = 1

                newPlatform.Parent = currentWorkspace.CurrentCamera
                flyRuntime.platform = newPlatform
                platform = newPlatform
            end
            local resolved: BasePart = platform :: BasePart

            resolved.CFrame = vertical < 0
                and CFrame.new(0, -4096, 0)
                or CFrame.new(root.Position - Vector3.new(0, humanoid.HipHeight + 1.5, 0))
            if vertical > 0 then
                root.AssemblyLinearVelocity = Vector3.new(
                    currentVelocity.X,
                    targetY,
                    currentVelocity.Z
                )
            end
            return
        end

        if method == "Bypass" then

            local period: number = math.max(flySettings.burstInterval, 0.05) * 5
            if (os.clock() % period) > (period * 0.8) then

                flyRuntime.yLevel = nil
                return
            end
            local held: number = flyRuntime.yLevel or root.Position.Y
            held = held + targetY * deltaTime
            flyRuntime.yLevel = held
            root.AssemblyLinearVelocity = Vector3.new(
                currentVelocity.X,
                0,
                currentVelocity.Z
            )
            root.CFrame = root.CFrame + Vector3.new(0, held - root.Position.Y, 0)
            return
        end

        if method == "Hover" or method == "Jump" then
            local level: number = flyRuntime.yLevel or root.Position.Y
            level = level + targetY * deltaTime
            if flySettings.wallCheck then
                local offset: number = level - root.Position.Y
                if math.abs(offset) > 0.001 then
                    local raycastParams: RaycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                    raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                    local ceilingHit: RaycastResult? = currentWorkspace:Raycast(
                        root.Position,
                        Vector3.new(0, offset, 0),
                        raycastParams
                    )
                    if ceilingHit then
                        level = ceilingHit.Position.Y
                            - math.sign(offset) * (humanoid.HipHeight + 0.5)
                    end
                end
            end
            flyRuntime.yLevel = level
            if method == "Hover" then
                root.AssemblyLinearVelocity = Vector3.new(
                    currentVelocity.X,
                    0,
                    currentVelocity.Z
                )
                root.CFrame = root.CFrame + Vector3.new(0, level - root.Position.Y, 0)
            elseif root.Position.Y < level - 0.5 then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
            return
        end

        if method == "Bounce" then
            local period: number = math.max(flySettings.burstInterval, 0.05) * 4
            local rising: boolean = (os.clock() % period) < (period * 0.5)
            targetY = targetY
                + (rising and 1 or -1) * flySettings.verticalSpeed * 0.45
        end

        if method == "Impulse" then
            local difference: number = targetY - currentVelocity.Y
            if math.abs(difference) > 2 then
                root:ApplyImpulse(Vector3.new(0, difference, 0) * root.AssemblyMass)
            end
            return
        end

        root.AssemblyLinearVelocity = Vector3.new(
            currentVelocity.X,
            targetY,
            currentVelocity.Z
        )
    end
    end

    local fly: any
    fly = framework.Categories.Blatant:CreateModule({
        Name = "Flight",
        Category = "Blatant",
        ConfigKey = "Universal.Fly",
        Tooltip = "Use WASD to move, Space to rise and LeftControl to descend. "
            .. "Method picks how you travel sideways and Float picks what "
            .. "holds you up; if a game blocks one combination, another "
            .. "usually works.",
        Function = function(enabled: boolean): ()

            removeFlyObjects()
            flySmoothedVelocity = Vector3.zero
            flyTouchVertical = 0
            flyRuntime.yLevel = nil
            flyRuntime.burstAt = 0
            if flyRuntime.platform then
                (flyRuntime.platform :: BasePart):Destroy()
                flyRuntime.platform = nil
            end
            restoreWalkSpeed()

            if not enabled then
                fly:SetStatus(nil)
                local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
                if root then
                    (root :: BasePart).AssemblyLinearVelocity = Vector3.zero
                end
                if humanoid then
                    platformStand.set("Fly", false)
                    platformStand.apply(humanoid :: Humanoid)
                end
                return
            end

            fly:SetStatus(flySettings.method)
            fly:Loop(function(deltaTime: number): ()
                local _, humanoid, root = getCharacterParts()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not humanoid or not root or not camera then

                    flyRuntime.yLevel = nil
                    return
                end

                local method: string = flySettings.method
                local floatMethod: string = flySettings.floatMethod

                local canRagdoll: boolean = method ~= "WalkSpeed"
                    and floatMethod ~= "Floor"
                    and floatMethod ~= "Jump"
                platformStand.set(
                    "Fly",
                    canRagdoll and (flySettings.platformStand or method == "CFrame")
                )
                platformStand.apply(humanoid)

                local moveDirection, vertical, cameraForward = getFlyDirection(camera)
                if flySettings.wallCheck and moveDirection.Magnitude > 0.001 then
                    local raycastParams: RaycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                    raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                    local wallHit: RaycastResult? = currentWorkspace:Raycast(
                        root.Position,
                        moveDirection.Unit * 2.75,
                        raycastParams
                    )
                    if wallHit then
                        moveDirection = Vector3.zero
                    end
                end

                if method == "Constraint" then
                    local velocity, orientation = ensureFlyConstraints(root)
                    applyFlyHorizontal(root, humanoid, moveDirection, deltaTime)
                    velocity.Enabled = true
                    velocity.VectorVelocity = Vector3.new(
                        flySmoothedVelocity.X,
                        vertical * flySettings.verticalSpeed,
                        flySmoothedVelocity.Z
                    )
                    orientation.Enabled = flySettings.faceCamera
                    orientation.CFrame = CFrame.lookAt(Vector3.zero, cameraForward)
                    return
                end

                removeFlyObjects()
                applyFlyHorizontal(root, humanoid, moveDirection, deltaTime)
                applyFlyVertical(root, humanoid, vertical, deltaTime)

                if floatMethod ~= "Floor" and flyRuntime.platform then
                    (flyRuntime.platform :: BasePart):Destroy()
                    flyRuntime.platform = nil
                end
                if floatMethod ~= "Hover" and floatMethod ~= "Jump" then
                    flyRuntime.yLevel = nil
                end

                if flySettings.faceCamera and cameraForward.Magnitude > 0.001 then
                    root.CFrame = CFrame.lookAt(root.Position, root.Position + cameraForward)
                end
            end)
        end,
    })

    fly:CreateDropdown({
        Name = "Method",
        List = {"Velocity", "Constraint", "Impulse", "CFrame", "Blink", "Pulse", "WalkSpeed"},
        Index = 1,
        Function = function(value: string): ()
            flySettings.method = value
            if fly.Enabled then
                fly:SetStatus(value)
            end
        end,
        Tooltip = "Sideways engine. Velocity is smooth, CFrame ignores physics, "
            .. "WalkSpeed just runs faster.",
    })
    fly:CreateDropdown({
        Name = "Float",
        List = {"Velocity", "Impulse", "Hover", "Jump", "Bounce", "Floor", "Bypass"},
        Index = 1,
        Function = function(value: string): ()
            flySettings.floatMethod = value
        end,
        Tooltip = "What keeps you airborne. Hover locks an altitude, Floor "
            .. "stands you on an invisible part, and Bypass drops you to the "
            .. "ground for an instant every few seconds so the server sees "
            .. "you land.",
    })
    fly:CreateSlider({
        Name = "Horizontal speed",
        Min = 10,
        Max = 500,
        Default = flySettings.speed,
        Function = function(value: number): ()
            flySettings.speed = value
        end,
        Tooltip = "Studs per second while holding WASD.",
    })
    fly:CreateSlider({
        Name = "Vertical speed",
        Min = 10,
        Max = 350,
        Default = flySettings.verticalSpeed,
        Function = function(value: number): ()
            flySettings.verticalSpeed = value
        end,
        Tooltip = "Studs per second while rising or descending.",
    })
    fly:CreateSlider({
        Name = "Response multiplier",
        Show = {Option = "Method", Values = {"Velocity", "Constraint", "Pulse"}},
        Min = 0.5,
        Max = 2,
        Default = flySettings.response,
        Function = function(value: number): ()
            flySettings.response = value
        end,
        Tooltip = "How sharply the flight reacts to input. Higher is twitchier.",
    })
    fly:CreateSlider({
        Name = "Burst interval (s)",
        Min = 0.05,
        Max = 1,
        Default = flySettings.burstInterval,
        Function = function(value: number): ()
            flySettings.burstInterval = value
        end,
        Tooltip = "Cycle length for Blink, Pulse, Bounce and Bypass. Shorter "
            .. "is smoother.",
    })
    fly:CreateToggle({
        Name = "Wall check",
        Default = flySettings.wallCheck,
        Function = function(value: boolean): ()
            flySettings.wallCheck = value
        end,
        Tooltip = "Stop against solid geometry instead of flying through it.",
    })
    fly:CreateToggle({
        Name = "PlatformStand",
        Default = flySettings.platformStand,
        Function = function(value: boolean): ()
            flySettings.platformStand = value
        end,
        Tooltip = "Ragdoll the character while flying. Smoother, but no animations.",
    })
    fly:CreateToggle({
        Name = "Face camera",
        Default = flySettings.faceCamera,
        Function = function(value: boolean): ()
            flySettings.faceCamera = value
        end,
        Tooltip = "Rotate the character to follow wherever the camera looks.",
    })
    local upKey: any = fly:CreateBind({
        Name = "Up key",
        Default = flySettings.upKey,
        Function = function(value: Enum.KeyCode): ()
            flySettings.upKey = value
        end,
        Tooltip = "Hold to gain altitude.",
    })
    local downKey: any = fly:CreateBind({
        Name = "Down key",
        Default = flySettings.downKey,
        Function = function(value: Enum.KeyCode): ()
            flySettings.downKey = value
        end,
        Tooltip = "Hold to lose altitude.",
    })

    if mobileActions.bindPlacement then
        mobileActions.bindPlacement(
            upKey.Object,
            "UniversalFlyUp",
            "UP",
            function(): () end,
            {
                onPress = function(): ()
                    flyTouchVertical = 1
                end,
                onRelease = function(): ()
                    if flyTouchVertical == 1 then
                        flyTouchVertical = 0
                    end
                end,
            }
        )
        mobileActions.bindPlacement(
            downKey.Object,
            "UniversalFlyDown",
            "DOWN",
            function(): () end,
            {
                onPress = function(): ()
                    flyTouchVertical = -1
                end,
                onRelease = function(): ()
                    if flyTouchVertical == -1 then
                        flyTouchVertical = 0
                    end
                end,
            }
        )
    end

    activeCleanup = function(): ()
        removeFlyObjects()
        restoreWalkSpeed()
    end
    Module.Initialized = true
    return fly
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/VehicleSpeed.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "VehicleSpeed",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local getCharacterParts: any = context.host.getCharacterParts

    type VehicleSeatState = {
        maxSpeed: number,
        torque: number,
        turnSpeed: number,
    }
    type HingeState = {
        angularVelocity: number,
        motorMaxTorque: number,
    }

    local settings = {
        mode = "Multiplier",
        multiplier = 2,
        motorTorque = 50000,
    }
    local originalVehicleSeats: {[VehicleSeat]: VehicleSeatState} =
        setmetatable({}, {__mode = "k"}) :: any
    local originalMotorHinges: {[HingeConstraint]: HingeState} =
        setmetatable({}, {__mode = "k"}) :: any

    local velocityExcess: {[BasePart]: number} =
        setmetatable({}, {__mode = "k"}) :: any
    local motorExcess: {[HingeConstraint]: number} =
        setmetatable({}, {__mode = "k"}) :: any

    local function clearBoostHistory(): ()
        velocityExcess = setmetatable({}, {__mode = "k"}) :: any
        motorExcess = setmetatable({}, {__mode = "k"}) :: any
    end

    local function restoreVehicle(): ()
        for seat: VehicleSeat, original: VehicleSeatState in pairs(originalVehicleSeats) do
            if seat.Parent then
                seat.MaxSpeed = original.maxSpeed
                seat.Torque = original.torque
                seat.TurnSpeed = original.turnSpeed
            end
        end
        originalVehicleSeats = setmetatable({}, {__mode = "k"}) :: any
        for hinge: HingeConstraint, original: HingeState in pairs(originalMotorHinges) do
            if hinge.Parent then
                hinge.AngularVelocity = original.angularVelocity
                hinge.MotorMaxTorque = original.motorMaxTorque
            end
        end
        originalMotorHinges = setmetatable({}, {__mode = "k"}) :: any
        clearBoostHistory()
    end

    local function resolveVehicle(): (BasePart?, Model?, VehicleSeat?)
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            getCharacterParts()
        if not character or not humanoid or not root then
            return nil, nil, nil
        end
        local seatPart: BasePart? = humanoid.SeatPart
        local assembly: BasePart? = nil
        if seatPart then
            assembly = seatPart.AssemblyRootPart or seatPart
        else

            assembly = root.AssemblyRootPart
            if not assembly or assembly:IsDescendantOf(character) then
                return nil, nil, nil
            end
        end
        local resolvedAssembly: BasePart = assembly :: BasePart
        local model: Model? = (seatPart or resolvedAssembly):FindFirstAncestorOfClass("Model")
        local vehicleSeat: VehicleSeat? = seatPart
                and seatPart:IsA("VehicleSeat")
                and seatPart :: VehicleSeat
            or nil
        return resolvedAssembly, model, vehicleSeat
    end

    local function rememberParts(model: Model?): ()
        if not model then
            return
        end
        for _, descendant: Instance in ipairs(model:GetDescendants()) do
            if descendant:IsA("VehicleSeat")
                and originalVehicleSeats[descendant] == nil then
                originalVehicleSeats[descendant] = {
                    maxSpeed = descendant.MaxSpeed,
                    torque = descendant.Torque,
                    turnSpeed = descendant.TurnSpeed,
                }
            elseif descendant:IsA("HingeConstraint")
                and descendant.ActuatorType == Enum.ActuatorType.Motor
                and originalMotorHinges[descendant] == nil then
                originalMotorHinges[descendant] = {
                    angularVelocity = descendant.AngularVelocity,
                    motorMaxTorque = descendant.MotorMaxTorque,
                }
            end
        end
    end

    local function boostedBase(current: number, previousExcess: number): number
        local base: number = math.max(current - previousExcess, 0)
        if base < 0.01 and current > 0.01 then
            base = current / math.max(settings.multiplier, 1)
        end
        return base
    end

    local function boostVelocity(assembly: BasePart, forcedDirection: Vector3?): ()
        local current: Vector3 = assembly.AssemblyLinearVelocity
        local horizontal: Vector3 = Vector3.new(current.X, 0, current.Z)
        local speed: number = horizontal.Magnitude
        if speed < 0.01 then
            velocityExcess[assembly] = 0
            return
        end
        local base: number = boostedBase(speed, velocityExcess[assembly] or 0)
        local target: number = base * settings.multiplier
        local direction: Vector3 = forcedDirection or horizontal.Unit
        direction = Vector3.new(direction.X, 0, direction.Z)
        if direction.Magnitude < 0.01 then
            return
        end
        direction = direction.Unit
        assembly.AssemblyLinearVelocity = direction * target
            + Vector3.new(0, current.Y, 0)
        velocityExcess[assembly] = math.max(target - base, 0)
    end

    local function boostMotors(model: Model?): ()
        rememberParts(model)
        for hinge: HingeConstraint, original: HingeState in pairs(originalMotorHinges) do
            if not hinge.Parent or (model and not hinge:IsDescendantOf(model)) then
                continue
            end
            local current: number = hinge.AngularVelocity
            local sign: number = current < 0 and -1 or 1
            local magnitude: number = math.abs(current)
            local base: number = boostedBase(magnitude, motorExcess[hinge] or 0)
            local target: number = base * settings.multiplier
            hinge.AngularVelocity = sign * target
            hinge.MotorMaxTorque = math.max(
                original.motorMaxTorque * settings.multiplier,
                settings.motorTorque
            )
            motorExcess[hinge] = math.max(target - base, 0)
        end
    end

    local function boostSeatProperties(model: Model?, seat: VehicleSeat?): ()
        rememberParts(model)
        if seat and originalVehicleSeats[seat] == nil then
            originalVehicleSeats[seat] = {
                maxSpeed = seat.MaxSpeed,
                torque = seat.Torque,
                turnSpeed = seat.TurnSpeed,
            }
        end
        for candidate: VehicleSeat, original: VehicleSeatState in pairs(originalVehicleSeats) do
            if not candidate.Parent
                or (model and not candidate:IsDescendantOf(model)) then
                continue
            end
            candidate.MaxSpeed = original.maxSpeed * settings.multiplier
            candidate.Torque = original.torque * settings.multiplier
            candidate.TurnSpeed = original.turnSpeed * settings.multiplier
        end
    end

    local vehicleSpeed: any
    vehicleSpeed = framework.Categories.Blatant:CreateModule({
        Name = "Vehicle Speed",
        Category = "Blatant",
        Tooltip = "Multiplies the speed of the vehicle you are driving. Try "
            .. "Multiplier first, then Motors, Velocity and Seat.",
        Function = function(enabled: boolean): ()
            restoreVehicle()
            if not enabled then
                vehicleSpeed:SetStatus(nil)
                return
            end
            vehicleSpeed:SetStatus(string.lower(settings.mode))
            vehicleSpeed:Loop(function(): ()
                local assembly: BasePart?, model: Model?, seat: VehicleSeat? =
                    resolveVehicle()
                if not assembly then
                    return
                end
                if settings.mode == "Multiplier" then
                    boostVelocity(assembly :: BasePart, nil)
                elseif settings.mode == "Motors" then
                    boostMotors(model)
                elseif settings.mode == "Velocity" then
                    local direction: Vector3? = seat
                        and (seat :: VehicleSeat).CFrame.LookVector
                            * (seat :: VehicleSeat).ThrottleFloat
                        or nil
                    boostVelocity(assembly :: BasePart, direction)
                else
                    boostSeatProperties(model, seat)
                end
            end)
            vehicleSpeed:Clean(restoreVehicle)
        end,
    })

    vehicleSpeed:CreateDropdown({
        Name = "Mode",
        List = {"Multiplier", "Motors", "Velocity", "Seat"},
        Index = 1,
        Function = function(value: string): ()
            restoreVehicle()
            settings.mode = value
            if vehicleSpeed.Enabled then
                vehicleSpeed:SetStatus(string.lower(value))
            end
        end,
        Tooltip = "Multiplier preserves the vehicle's current steering; Motors "
            .. "drives wheel constraints; Velocity rewrites the chassis; Seat "
            .. "changes classic VehicleSeat properties.",
    })
    vehicleSpeed:CreateSlider({
        Name = "Multiplier",
        Min = 1,
        Max = 10,
        Default = settings.multiplier,
        Function = function(value: number): ()
            clearBoostHistory()
            settings.multiplier = value
        end,
        Tooltip = "A driver asks for 2x, not an absolute walking speed. The "
            .. "vehicle still supplies its own direction and base speed.",
    })
    vehicleSpeed:CreateSlider({
        Name = "Motor torque",
        Show = {Option = "Mode", Values = {"Motors"}},
        Min = 1000,
        Max = 250000,
        Default = settings.motorTorque,
        Function = function(value: number): ()
            settings.motorTorque = value
        end,
    })
    vehicleSpeed:CreateNote(
        "If one route is clamped, try the next. Every seat and motor property "
            .. "returns to the value this vehicle had before the module touched it."
    )

    activeCleanup = restoreVehicle
    Module.Initialized = true
    return vehicleSpeed
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/AntiVoid.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AntiVoid",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local workspace: any = host.workspace
    local antiVoidPlatform: Part? = nil
    local antiVoidLastGroundY: number? = nil
    local antiVoidFreefallSeconds: number = 0
    local antiVoidPlatformToken: number = 0

    local function removeAntiVoidPlatform(): ()
        antiVoidPlatformToken = antiVoidPlatformToken + 1
        if antiVoidPlatform then
            antiVoidPlatform:Destroy()
            antiVoidPlatform = nil
        end
    end

    local function createAntiVoidPlatform(root: BasePart, humanoid: Humanoid): ()
        removeAntiVoidPlatform()

        local platform: Part = Instance.new("Part")
        platform.Name = "Wurst_AntiVoidPlatform"
        platform.Anchored = true
        platform.CanCollide = true
        platform.CanQuery = false
        platform.CanTouch = false
        platform.CastShadow = false
        platform.Size = Vector3.new(42, 1, 42)
        platform.Transparency = 1
        platform.CFrame = CFrame.new(root.Position - Vector3.new(0, 4.25, 0))
        platform.Parent = workspace
        antiVoidPlatform = platform

        local velocity: Vector3 = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.25, 0, velocity.Z * 0.25)
        root.AssemblyAngularVelocity = Vector3.zero
        humanoid:ChangeState(Enum.HumanoidStateType.Landed)

        local token: number = antiVoidPlatformToken
        task.delay(3, function(): ()
            if antiVoidPlatformToken == token then
                removeAntiVoidPlatform()
            end
        end)
    end

    local function toggleAntiVoid(enabled: boolean): ()
        disconnectFeatureConnection("AntiVoid")
        removeAntiVoidPlatform()
        antiVoidLastGroundY = nil
        antiVoidFreefallSeconds = 0

        if not enabled then
            return
        end

        featureConnections.AntiVoid = TaskManager:Connect(function(deltaTime: number): ()
            local _, humanoid, root = getCharacterParts()
            if not humanoid or not root then
                return
            end

            if humanoid.FloorMaterial ~= Enum.Material.Air then
                antiVoidLastGroundY = root.Position.Y
                antiVoidFreefallSeconds = 0
                return
            end

            antiVoidFreefallSeconds = antiVoidFreefallSeconds + deltaTime
            local destroyHeight: number = workspace.FallenPartsDestroyHeight
            if destroyHeight ~= destroyHeight then
                destroyHeight = -500
            end

            local nearDestroyLayer: boolean = root.Position.Y <= destroyHeight + 45
            local fellFarFromGround: boolean = antiVoidLastGroundY ~= nil
                and root.Position.Y <= (antiVoidLastGroundY :: number) - 120
                and antiVoidFreefallSeconds >= 1.1
                and root.AssemblyLinearVelocity.Y < -45

            if nearDestroyLayer or fellFarFromGround then
                createAntiVoidPlatform(root, humanoid)
                antiVoidFreefallSeconds = 0
            end
        end)
    end

    local AntiVoidFeature = createUniversalFeature(
        "Anti-Void",
        "Create an invisible rescue platform only when death is imminent",
        4,
        toggleAntiVoid,
        {noOptions = true, categoryName = "Blatant"}
    )
    addFeatureTooltip(
        AntiVoidFeature,
        "Detects a deep lethal fall and creates a temporary invisible platform beneath you."
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("AntiVoid")
        removeAntiVoidPlatform()
    end
    Module.Initialized = true
    return AntiVoidFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/World/Gravity.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Gravity",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local workspace: any = host.workspace
    local gravitySettings = {value = 196.2}
    local GravityFeature: any = nil
    local originalGravity = workspace.Gravity

    local function toggleGravity(enabled)
        disconnectFeatureConnection("Gravity")

        if not enabled then
            if GravityFeature then
                GravityFeature:SetStatus(nil)
            end
            workspace.Gravity = originalGravity
            return
        end

        GravityFeature:SetStatus(tostring(math.round(gravitySettings.value)))
        originalGravity = workspace.Gravity
        featureConnections.Gravity = TaskManager:Connect(function()
            workspace.Gravity = gravitySettings.value
        end)
    end

    GravityFeature = createUniversalFeature(
        "Gravity",
        "Keep workspace gravity at a custom value",
        5,
        toggleGravity,
        {categoryName = "Movement"}
    )
    addNumberOption(GravityFeature, "Gravity value", gravitySettings.value, 0, 500, function(value)
        gravitySettings.value = value
        if GravityFeature.enabled then
            GravityFeature:SetStatus(tostring(math.round(value)))
        end
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("Gravity")

        workspace.Gravity = originalGravity
    end
    Module.Initialized = true
    return GravityFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/JumpPower.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "JumpPower",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local jumpPowerSettings = {value = 80}
    local JumpPowerFeature: any = nil
    local originalJumpPower = setmetatable({}, {__mode = "k"})

    local function restoreJumpPower()
        for humanoid, original in pairs(originalJumpPower) do
            if humanoid and humanoid.Parent then
                humanoid.JumpPower = original.jumpPower
                humanoid.UseJumpPower = original.useJumpPower
            end
        end
        originalJumpPower = setmetatable({}, {__mode = "k"})
    end

    local function toggleJumpPower(enabled)
        disconnectFeatureConnection("JumpPower")
        restoreJumpPower()

        if not enabled then
            if JumpPowerFeature then
                JumpPowerFeature:SetStatus(nil)
            end
            return
        end

        JumpPowerFeature:SetStatus(tostring(math.round(jumpPowerSettings.value)))
        featureConnections.JumpPower = TaskManager:Connect(function()
            local _, humanoid = getCharacterParts()
            if not humanoid then
                return
            end

            if not originalJumpPower[humanoid] then
                originalJumpPower[humanoid] = {
                    jumpPower = humanoid.JumpPower,
                    useJumpPower = humanoid.UseJumpPower,
                }
            end

            humanoid.UseJumpPower = true
            humanoid.JumpPower = jumpPowerSettings.value
        end)
    end

    JumpPowerFeature = createUniversalFeature(
        "Jump Power",
        "Keep character jump power at a custom value",
        6,
        toggleJumpPower,
        {categoryName = "Blatant"}
    )
    addNumberOption(JumpPowerFeature, "Power", jumpPowerSettings.value, 0, 500, function(value)
        jumpPowerSettings.value = value
        if JumpPowerFeature.enabled then
            JumpPowerFeature:SetStatus(tostring(math.round(value)))
        end
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("JumpPower")
        restoreJumpPower()
    end
    Module.Initialized = true
    return JumpPowerFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/InfiniteJump.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "InfiniteJump",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local getCharacterParts: any = host.getCharacterParts
    local movementInput: any = context.services.movementInput
    local UserInputService: any = host.UserInputService
    local infiniteJumpSettings = {
        mode = "Normal",
        strength = 50,
        riseSpeed = 75,

        interval = 0.18,
        stackCeiling = 160,
    }

    local enabledNow: boolean = false
    local lastJumpAt: number = -math.huge

    local function performInfiniteJump(): ()

        if not enabledNow then
            return
        end

        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        local spacing: number = infiniteJumpSettings.interval
        if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
            spacing = math.max(spacing, 0.25)
        end

        local now: number = os.clock()
        if now - lastJumpAt < spacing then
            return
        end
        lastJumpAt = now

        local velocity: Vector3 = root.AssemblyLinearVelocity
        local vertical: number
        if infiniteJumpSettings.mode == "Stack" then
            vertical = math.min(
                velocity.Y + infiniteJumpSettings.strength,
                infiniteJumpSettings.stackCeiling
            )
        elseif infiniteJumpSettings.mode == "Impulse" then

            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            root:ApplyImpulse(
                Vector3.new(0, infiniteJumpSettings.strength - velocity.Y, 0)
                    * root.AssemblyMass
            )
            return
        elseif infiniteJumpSettings.mode == "Fall" then

            if velocity.Y >= 0 then
                return
            end
            vertical = 0
        else
            vertical = infiniteJumpSettings.strength
        end

        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, vertical, velocity.Z)
    end

    local jump: any
    jump = framework.Categories.Blatant:CreateModule({
        Name = "Infinite Jump",
        Category = "Blatant",
        Tooltip = "Jump again in mid-air, as a fixed height, a force, a "
            .. "climbing stack, a hold that rises, or a fall cancel.",
        Function = function(enabled: boolean): ()
            enabledNow = false
            lastJumpAt = -math.huge
            if not enabled then
                jump:SetStatus(nil)
                return
            end
            enabledNow = true
            jump:SetStatus(infiniteJumpSettings.mode)

            jump:Clean(movementInput.onJumpRequest(function(): ()
                if infiniteJumpSettings.mode == "Rise" then
                    return
                end
                performInfiniteJump()
            end))

            jump:Loop(function(): ()
                if not enabledNow
                    or infiniteJumpSettings.mode ~= "Rise"
                    or not movementInput.isJumpHeld() then
                    return
                end

                local _, humanoid, root = getCharacterParts()
                if not humanoid or not root or humanoid.Health <= 0 then
                    return
                end

                humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                local velocity = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(
                    velocity.X,
                    infiniteJumpSettings.riseSpeed,
                    velocity.Z
                )
            end)
        end,
    })
    jump:CreateDropdown({
        Name = "Mode",
        List = {"Normal", "Impulse", "Stack", "Rise", "Fall"},
        Index = 1,
        Function = function(value: string): ()
            infiniteJumpSettings.mode = value
            if jump.Enabled then
                jump:SetStatus(value)
            end
        end,
    })
    jump:CreateSlider({
        Name = "Jump power",
        Show = {Option = "Mode", Values = {"Normal", "Impulse", "Stack"}},
        Min = 10,
        Max = 250,
        Default = infiniteJumpSettings.strength,
        Function = function(value: number): ()
            infiniteJumpSettings.strength = value
        end,
        Tooltip = "Vertical velocity of one jump. Rise and Fall do not launch "
            .. "you, so they have no power to set.",
    })
    jump:CreateSlider({
        Name = "Rise speed",
        Show = {Option = "Mode", Values = {"Rise"}},
        Min = 10,
        Max = 350,
        Default = infiniteJumpSettings.riseSpeed,
        Function = function(value: number): ()
            infiniteJumpSettings.riseSpeed = value
        end,
    })
    jump:CreateSlider({
        Name = "Jump interval (s)",
        Show = {Option = "Mode", Values = {"Normal", "Impulse", "Stack", "Fall"}},
        Min = 0.05,
        Max = 0.6,
        Default = infiniteJumpSettings.interval,
        Function = function(value: number): ()
            infiniteJumpSettings.interval = value
        end,
        Tooltip = "Minimum spacing between jumps. Rise ignores it: it is a "
            .. "hold, not a repeat.",
    })

    jump:RefreshVisibility()

    activeCleanup = function(): ()
        enabledNow = false
        lastJumpAt = -math.huge
    end
    Module.Initialized = true
    return jump
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/FieldOfView.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "FieldOfView",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local fovOwnership: any = context.services.fovOwnership
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local workspace: any = host.workspace
    local fovSettings = {value = 90}
    local FovFeature: any = nil

    local function toggleFov(enabled)
        disconnectFeatureConnection("FOV")
        fovOwnership.set("Universal", enabled and fovSettings.value or nil)
        if not enabled then
            if FovFeature then FovFeature:SetStatus(nil) end
            return
        end

        FovFeature:SetStatus(tostring(math.round(fovSettings.value)))
        featureConnections.FOV = TaskManager:Connect(function()
            fovOwnership.set("Universal", fovSettings.value)
            fovOwnership.apply(workspace.CurrentCamera)
        end)
    end

    FovFeature = createUniversalFeature(
        "FOV",
        "Keep the camera field of view fixed",
        10,
        toggleFov,
        {categoryName = "Render"}
    )
    addNumberOption(FovFeature, "Field of view", fovSettings.value, 20, 120, function(value)
        fovSettings.value = value
        if FovFeature.enabled then
            FovFeature:SetStatus(tostring(math.round(value)))
        end
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("FOV")
        fovOwnership.set("Universal", nil)
    end
    Module.Initialized = true
    return FovFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/Noclip.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Noclip",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local toggleNoclip: (boolean) -> ()
    do
    local originalCollision = setmetatable({}, {__mode = "k"})

    local function restoreCollision()
        for part, canCollide in pairs(originalCollision) do
            if part and part.Parent then
                part.CanCollide = canCollide
            end
        end
        originalCollision = setmetatable({}, {__mode = "k"})
    end

    function toggleNoclip(enabled: boolean): ()
        disconnectFeatureConnection("Noclip")
        restoreCollision()

        if not enabled then
            return
        end

        featureConnections.Noclip = TaskManager:Connect(function()
            local character = LocalPlayer.Character
            if not character then
                return
            end

            for _, descendant in ipairs(character:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    if originalCollision[descendant] == nil then
                        originalCollision[descendant] = descendant.CanCollide
                    end
                    descendant.CanCollide = false
                end
            end
        end)
    end
    end

    local NoclipFeature = createUniversalFeature(
        "Noclip",
        "Disable character collisions",
        11,
        toggleNoclip,
        {noOptions = true, categoryName = "Blatant"}
    )
    addFeatureTooltip(NoclipFeature, "Disables collisions for every local character part. "
        .. "Original collision states are restored when turned off.")

    activeCleanup = function(): ()

        toggleNoclip(false)
    end
    Module.Initialized = true
    return NoclipFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/World/AntiAfk.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AntiAfk",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local function toggleAntiAfk(enabled)
        disconnectFeatureConnection("AntiAFK")

        if not enabled then
            return
        end

        featureConnections.AntiAFK = LocalPlayer.Idled:Connect(function()
            local virtualUserOk, virtualUser = pcall(function()
                return game:GetService("VirtualUser")
            end)
            if virtualUserOk and virtualUser then
                virtualUser:CaptureController()
                virtualUser:ClickButton2(Vector2.new(0, 0))
            end
        end)
    end

    local AntiAfkFeature = createUniversalFeature(
        "AntiAFK",
        "Prevent the local idle event from disconnecting",
        13,
        toggleAntiAfk,
        {
            noOptions = true,
            configKey = "Universal.AntiAFK",
            categoryName = "Other",
        }
    )
    addFeatureTooltip(AntiAfkFeature, "Responds only to Roblox's local idle event and "
        .. "disconnects immediately when disabled.")

    activeCleanup = function(): ()

        disconnectFeatureConnection("AntiAFK")
    end
    Module.Initialized = true
    return AntiAfkFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/AntiFling.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "AntiFling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local activity: any = context.services.activity
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local antiFlingSettings = {velocityLimit = 120}
    local antiFlingSafeCFrame = nil
    local AntiFlingFeature: any = nil
    local antiFlingStatus: string? = nil

    local function setAntiFlingStatus(status: string?): ()
        if antiFlingStatus == status then
            return
        end
        antiFlingStatus = status
        if AntiFlingFeature then
            AntiFlingFeature:SetStatus(status)
        end
    end

    local function toggleAntiFling(enabled)
        disconnectFeatureConnection("AntiFling")
        antiFlingSafeCFrame = nil

        if not enabled then
            setAntiFlingStatus(nil)
            return
        end

        setAntiFlingStatus("standing by")
        featureConnections.AntiFling = TaskManager:Connect(function()

            if activity.isActive("fling") then
                return
            end

            local _, humanoid, root = getCharacterParts()
            if not humanoid or not root then
                return
            end

            local linearSpeed = root.AssemblyLinearVelocity.Magnitude
            local angularSpeed = root.AssemblyAngularVelocity.Magnitude

            if linearSpeed > antiFlingSettings.velocityLimit
                or angularSpeed > antiFlingSettings.velocityLimit then
                setAntiFlingStatus("blocking")
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if antiFlingSafeCFrame then
                    root.CFrame = antiFlingSafeCFrame
                end
            elseif humanoid.FloorMaterial ~= Enum.Material.Air
                and linearSpeed < antiFlingSettings.velocityLimit * 0.45 then
                setAntiFlingStatus("standing by")
                antiFlingSafeCFrame = root.CFrame
            end
        end)
    end

    AntiFlingFeature = createUniversalFeature(
        "Anti-Fling",
        "Stop extreme local velocity and return to safety",
        14,
        toggleAntiFling,
        {categoryName = "Blatant"}
    )
    addNumberOption(
        AntiFlingFeature,
        "Velocity limit",
        antiFlingSettings.velocityLimit,
        40,
        1000,
        function(value)
            antiFlingSettings.velocityLimit = value
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("AntiFling")
    end
    Module.Initialized = true
    return AntiFlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/LagSwitch.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "LagSwitch",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local lagSwitchSettings = {incomingLag = 999}
    local originalIncomingLag = 0
    local LagSwitchFeature: any = nil

    local function setIncomingReplicationLag(value)
        local success = pcall(function()
            settings():GetService("NetworkSettings").IncomingReplicationLag = value
        end)
        return success
    end

    local function toggleLagSwitch(enabled)
        disconnectFeatureConnection("LagSwitch")

        if not enabled then
            if LagSwitchFeature then LagSwitchFeature:SetStatus(nil) end
            setIncomingReplicationLag(originalIncomingLag)
            return
        end

        LagSwitchFeature:SetStatus(tostring(math.round(lagSwitchSettings.incomingLag)) .. " ms")
        pcall(function()
            originalIncomingLag = settings():GetService(
                "NetworkSettings"
            ).IncomingReplicationLag
        end)

        if not setIncomingReplicationLag(lagSwitchSettings.incomingLag) then
            error("NetworkSettings is not available in this client.")
        end

        featureConnections.LagSwitch = TaskManager:Connect(function()
            setIncomingReplicationLag(lagSwitchSettings.incomingLag)
        end)
    end

    LagSwitchFeature = createUniversalFeature(
        "Lag Switch",
        "Simulate extreme incoming replication delay",
        16,
        toggleLagSwitch,
        {categoryName = "Other"}
    )
    addNumberOption(
        LagSwitchFeature,
        "Incoming lag",
        lagSwitchSettings.incomingLag,
        1,
        999,
        function(value)
            lagSwitchSettings.incomingLag = value
            if LagSwitchFeature.enabled then
                LagSwitchFeature:SetStatus(tostring(math.round(value)) .. " ms")
            end
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("LagSwitch")
        setIncomingReplicationLag(originalIncomingLag)
    end
    Module.Initialized = true
    return LagSwitchFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/Fling.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Fling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local activity: any = context.services.activity
    local protectedTargets: any = context.services.protectedTargets
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addFeatureTooltip: any = host.addFeatureTooltip

    local addTextOption: any = host.addTextOption
    local workspace: any = host.workspace
    local RunService: any = host.RunService

    local flingRunning: boolean = false

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running)
    end
    local findPlayerByText: (string) -> Player?
    local performFling: (Player) -> ()

    type UniversalFlingSettings = {
        target: string,
        duration: number,
        power: number,
        returnToStart: boolean,
    }

    local universalFlingSettings: UniversalFlingSettings = {
        target = "",
        duration = 6,
        power = 1,
        returnToStart = true,
    }

    findPlayerByText = function(text: string): Player?
        local query: string = string.lower(text)
        if query == "" then
            local _, _, localRoot = getCharacterParts()
            local nearest: Player? = nil
            local nearestDistance: number = math.huge

            if localRoot then
                for _, player: Player in ipairs(Players:GetPlayers()) do
                    local root: BasePart? = player.Character
                        and player.Character:FindFirstChild("HumanoidRootPart")
                        :: BasePart?
                    if player ~= LocalPlayer and root then
                        local distance: number = (root.Position - localRoot.Position).Magnitude
                        if distance < nearestDistance then
                            nearest = player
                            nearestDistance = distance
                        end
                    end
                end
            end
            return nearest
        end

        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local username: string = string.lower(player.Name)
                local displayName: string = string.lower(player.DisplayName)
                if string.sub(username, 1, #query) == query
                    or string.sub(displayName, 1, #query) == query then
                    return player
                end
            end
        end

        return nil
    end

    performFling = function(targetPlayer: Player): ()
        if protectedTargets.isProtected(targetPlayer) then
            notify("player protected")
            return
        end
        if flingRunning then
            notify("fling already running")
            return
        end

        setFlingRunning(true)
        task.spawn(function(): ()
            local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not humanoid or not root then
                setFlingRunning(false)
                notify("character not ready")
                return
            end

            local savedCFrame: CFrame = root.CFrame
            local savedAutoRotate: boolean = humanoid.AutoRotate
            local savedCameraSubject: (Humanoid | BasePart)? = workspace.CurrentCamera
                and workspace.CurrentCamera.CameraSubject
                :: (Humanoid | BasePart)?
            local touchedTarget: boolean = false
            local reason: string = "timeout"

            local power: number = 9e4 * math.clamp(universalFlingSettings.power, 0.25, 4)
            local duration: number = math.clamp(universalFlingSettings.duration, 1, 20)

            local success: boolean, errorMessage: any = pcall(function(): ()
                local startedAt: number = os.clock()
                local step: number = 0
                local destroyHeight: number = workspace.FallenPartsDestroyHeight
                if destroyHeight ~= destroyHeight then
                    destroyHeight = -500
                end
                local voidThreshold: number = destroyHeight + 35

                humanoid.AutoRotate = false
                if humanoid.Sit then
                    humanoid.Sit = false
                end

                while os.clock() - startedAt < duration do

                    if targetPlayer.Parent == nil then
                        reason = "left"
                        break
                    end

                    local targetCharacter: Model? = targetPlayer.Character
                    local targetRoot: BasePart? = targetCharacter
                        and targetCharacter:FindFirstChild("HumanoidRootPart")
                        :: BasePart?
                    local targetHumanoid: Humanoid? = targetCharacter
                        and targetCharacter:FindFirstChildOfClass("Humanoid")
                        :: Humanoid?
                    if not targetRoot or not targetRoot.Parent then
                        reason = "gone"
                        break
                    end
                    if targetHumanoid and targetHumanoid.Health <= 0 then
                        touchedTarget = true
                        reason = "killed"
                        break
                    end
                    if targetRoot.Position.Y <= voidThreshold then
                        touchedTarget = true
                        reason = "void"
                        break
                    end

                    local _, liveHumanoid: Humanoid?, liveRoot: BasePart? =
                        getCharacterParts()
                    if not liveHumanoid or not liveRoot then
                        reason = "died"
                        break
                    end
                    if liveHumanoid.Health <= 0 then
                        reason = "died"
                        break
                    end
                    if liveRoot.Anchored then
                        liveRoot.Anchored = false
                    end
                    humanoid = liveHumanoid
                    root = liveRoot

                    step += 1

                    local phase: number = (step % 6) / 6 * math.pi * 2
                    local vertical: number = (step % 2 == 0) and 1.1 or -1.1
                    liveRoot.CFrame = targetRoot.CFrame
                        * CFrame.new(math.cos(phase) * 1.6, vertical, math.sin(phase) * 1.6)
                    local sign: number = (step % 2 == 0) and 1 or -1
                    liveRoot.AssemblyLinearVelocity =
                        Vector3.new(power * sign, power, power * -sign)
                    liveRoot.AssemblyAngularVelocity =
                        Vector3.new(power, power, power)

                    RunService.Stepped:Wait()
                    if liveRoot.Parent then
                        liveRoot.AssemblyLinearVelocity =
                            Vector3.new(power * -sign, power, power * sign)
                    end
                    RunService.Heartbeat:Wait()
                end
            end)

            local _, finalHumanoid: Humanoid?, finalRoot: BasePart? = getCharacterParts()
            if finalRoot and finalRoot.Parent then
                finalRoot.AssemblyLinearVelocity = Vector3.zero
                finalRoot.AssemblyAngularVelocity = Vector3.zero
                if universalFlingSettings.returnToStart then
                    finalRoot.CFrame = savedCFrame + Vector3.new(0, 2, 0)
                end
            end
            if finalHumanoid then
                finalHumanoid.AutoRotate = savedAutoRotate
                finalHumanoid.PlatformStand = false
            end
            if workspace.CurrentCamera then
                workspace.CurrentCamera.CameraSubject =
                    savedCameraSubject or finalHumanoid or humanoid
            end

            setFlingRunning(false)
            if not success then
                notify("fling failed: " .. tostring(errorMessage))
            elseif touchedTarget then
                notify("fling complete: " .. targetPlayer.Name .. " went down.")
            elseif reason == "left" then
                notify("fling stopped: " .. targetPlayer.Name .. " left the game.")
            elseif reason == "gone" then
                notify("Fling stopped: the target character disappeared.")
            elseif reason == "died" then
                notify("Fling stopped: your character died.")
            else
                notify(
                    "Fling stopped after "
                        .. string.format("%.0f", universalFlingSettings.duration)
                        .. "s. Raise Duration or Power for tougher targets."
                )
            end
        end)
    end

    local FlingFeature = createUniversalFeature(
        "Fling",
        "Fling a player, or the nearest player when blank",
        2,
        function()
            local target = findPlayerByText(universalFlingSettings.target)
            if target then
                performFling(target)
            else
                notify("no matching player")
            end
        end,
        {action = true, categoryName = "Blatant"}
    )
    addTextOption(FlingFeature, "Target player", universalFlingSettings.target, function(value)
        universalFlingSettings.target = value
    end, false)

    addNumberOption(
        FlingFeature,
        "Duration (s)",
        universalFlingSettings.duration,
        1,
        20,
        function(value: number): ()
            universalFlingSettings.duration = value
        end
    )
    addNumberOption(
        FlingFeature,
        "Power",
        universalFlingSettings.power,
        0.25,
        4,
        function(value: number): ()
            universalFlingSettings.power = value
        end
    )
    addToggleOption(
        FlingFeature,
        "Return to start",
        universalFlingSettings.returnToStart,
        function(value: boolean): ()
            universalFlingSettings.returnToStart = value
        end
    )
    addFeatureTooltip(
        FlingFeature,
        "Runs until the target goes down or the duration expires, then puts you back."
    )

    activeCleanup = function(): ()
        setFlingRunning(false)
    end
    Module.Initialized = true
    return FlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/ImproveFps.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ImproveFps",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption

    local fpsSettings: {[string]: boolean} = {
        textures = true,
        particles = true,
        shadows = true,
        materials = false,
    }
    local fpsModeEnabled: boolean = false
    local ImproveFpsFeature: any = nil
    local function selectedEffectCount(): number
        local count: number = 0
        for _name: string, selected: boolean in pairs(fpsSettings) do
            if selected then count += 1 end
        end
        return count
    end

    local fpsVisualCache: any = setmetatable({}, {__mode = "k"})

    local function cacheFpsProperty(object: any, property: string): ()
        local data: any = fpsVisualCache[object]
        if not data then
            data = {}
            fpsVisualCache[object] = data
        end
        if data[property] == nil then
            data[property] = object[property]
        end
    end

    local function applyFpsObject(object: Instance): ()
        local target: any = object
        if fpsSettings.textures and (object:IsA("Decal") or object:IsA("Texture")) then
            cacheFpsProperty(object, "Transparency")
            target.Transparency = 1
        elseif fpsSettings.textures and object:IsA("MeshPart") then
            cacheFpsProperty(object, "TextureID")
            target.TextureID = ""
        end

        if fpsSettings.particles
            and (object:IsA("ParticleEmitter")
                or object:IsA("Trail")
                or object:IsA("Beam")
                or object:IsA("Smoke")
                or object:IsA("Fire")
                or object:IsA("Sparkles")) then
            cacheFpsProperty(object, "Enabled")
            target.Enabled = false
        end

        if object:IsA("BasePart") then
            if fpsSettings.shadows then
                cacheFpsProperty(object, "CastShadow")
                object.CastShadow = false
            end
            if fpsSettings.materials then
                cacheFpsProperty(object, "Material")
                cacheFpsProperty(object, "Reflectance")
                object.Material = Enum.Material.SmoothPlastic
                object.Reflectance = 0
            end
        end
    end

    local function restoreFpsObjects(): ()
        for object: any, properties: any in pairs(fpsVisualCache) do
            if object and object.Parent then
                for property: string, value: any in pairs(properties) do
                    pcall(function(): ()
                        object[property] = value
                    end)
                end
            end
        end
        fpsVisualCache = setmetatable({}, {__mode = "k"})
    end

    local function toggleImproveFps(enabled: boolean): ()
        fpsModeEnabled = enabled
        disconnectFeatureConnection("ImproveFPS")
        restoreFpsObjects()

        if not enabled then
            if ImproveFpsFeature then ImproveFpsFeature:SetStatus(nil) end
            return
        end
        ImproveFpsFeature:SetStatus(tostring(selectedEffectCount()) .. " effects")

        task.spawn(function(): ()
            for index: number, object: Instance in ipairs(workspace:GetDescendants()) do
                if not fpsModeEnabled then
                    return
                end
                pcall(applyFpsObject, object)
                if index % 250 == 0 then
                    task.wait()
                end
            end
        end)
        featureConnections.ImproveFPS = workspace.DescendantAdded:Connect(
            function(object: Instance): ()
                if fpsModeEnabled then
                    pcall(applyFpsObject, object)
                end
            end
        )
    end

    local function refreshFps(): ()
        if fpsModeEnabled then
            toggleImproveFps(true)
        end
    end

    ImproveFpsFeature = createUniversalFeature(
        "Improve FPS",
        "Apply only the selected reversible optimizations",
        26,
        toggleImproveFps,
        {categoryName = "Other"}
    )
    addToggleOption(ImproveFpsFeature, "Remove textures", true, function(value: boolean): ()
        fpsSettings.textures = value
        refreshFps()
    end)
    addToggleOption(ImproveFpsFeature, "Disable particles", true, function(value: boolean): ()
        fpsSettings.particles = value
        refreshFps()
    end)
    addToggleOption(ImproveFpsFeature, "Disable shadows", true, function(value: boolean): ()
        fpsSettings.shadows = value
        refreshFps()
    end)
    addToggleOption(ImproveFpsFeature, "Simple materials", false, function(value: boolean): ()
        fpsSettings.materials = value
        refreshFps()
    end)

    activeCleanup = function(): ()
        toggleImproveFps(false)
    end
    Module.Initialized = true
    return ImproveFpsFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/Fullbright.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Fullbright",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local Lighting: any = host.Lighting
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local featureConnections: any = host.featureConnections
    local TaskManager: any = host.TaskManager

    local fullbrightSettings = {
        brightness = 3,
        clockTime = 14,
    }
    local originalLighting: any = nil

    local function toggleFullbright(enabled: boolean): ()
        disconnectFeatureConnection("Fullbright")

        if not enabled then
            if originalLighting then
                Lighting.Brightness = originalLighting.brightness
                Lighting.ClockTime = originalLighting.clockTime
                Lighting.GlobalShadows = originalLighting.globalShadows
                Lighting.FogEnd = originalLighting.fogEnd
                Lighting.Ambient = originalLighting.ambient
                Lighting.OutdoorAmbient = originalLighting.outdoorAmbient
            end
            return
        end

        originalLighting = {
            brightness = Lighting.Brightness,
            clockTime = Lighting.ClockTime,
            globalShadows = Lighting.GlobalShadows,
            fogEnd = Lighting.FogEnd,
            ambient = Lighting.Ambient,
            outdoorAmbient = Lighting.OutdoorAmbient,
        }

        featureConnections.Fullbright = TaskManager:Connect(function()
            Lighting.Brightness = fullbrightSettings.brightness
            Lighting.ClockTime = fullbrightSettings.clockTime
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 100000
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        end)
    end

    local FullbrightFeature = createUniversalFeature(
        "Fullbright",
        "Keep the scene bright and remove global shadows",
        15,
        toggleFullbright,
        {categoryName = "Render"}
    )
    addNumberOption(
        FullbrightFeature,
        "Brightness",
        fullbrightSettings.brightness,
        0,
        10,
        function(value)
            fullbrightSettings.brightness = value
        end
    )
    addNumberOption(
        FullbrightFeature,
        "Clock time",
        fullbrightSettings.clockTime,
        0,
        24,
        function(value)
            fullbrightSettings.clockTime = value
        end
    )

    activeCleanup = function(): ()
        toggleFullbright(false)
    end
    Module.Initialized = true
    return FullbrightFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/FreezeMovements.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "FreezeMovements",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addCycleOption: any = host.addCycleOption
    local addInformationOption: any = host.addInformationOption
    local freezeSettings = {mode = "Anchor"}
    local FreezeFeature: any = nil
    local originalFreezeState = setmetatable({}, {__mode = "k"})

    local function restoreFreezeMovements()
        for humanoid, original in pairs(originalFreezeState) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = original.walkSpeed
                humanoid.JumpPower = original.jumpPower
                humanoid.AutoRotate = original.autoRotate
                if original.root and original.root.Parent then
                    original.root.Anchored = original.rootAnchored
                end
            end
        end
        originalFreezeState = setmetatable({}, {__mode = "k"})
    end

    local function toggleFreezeMovements(enabled)
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()

        if not enabled then
            if FreezeFeature then
                FreezeFeature:SetStatus(nil)
            end
            return
        end

        FreezeFeature:SetStatus(freezeSettings.mode)
        featureConnections.FreezeMovements = TaskManager:Connect(function()
            local _, humanoid, root = getCharacterParts()
            if not humanoid or not root then
                return
            end

            if not originalFreezeState[humanoid] then
                originalFreezeState[humanoid] = {
                    walkSpeed = humanoid.WalkSpeed,
                    jumpPower = humanoid.JumpPower,
                    autoRotate = humanoid.AutoRotate,
                    root = root,
                    rootAnchored = root.Anchored,
                }
            end

            local original = originalFreezeState[humanoid]
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.AutoRotate = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.Anchored = freezeSettings.mode == "Anchor"
                and true
                or original.rootAnchored
        end)
    end

    FreezeFeature = createUniversalFeature(
        "Freeze Movements",
        "Prevent the local character from moving",
        1,
        toggleFreezeMovements,
        {
            categoryName = "Blatant",
            configKey = "Movement.FreezeMovements",
        }
    )
    addCycleOption(
        FreezeFeature,
        "Freeze mode",
        {"Anchor", "Humanoid"},
        1,
        function(value)
            freezeSettings.mode = value
            if FreezeFeature.enabled then
                FreezeFeature:SetStatus(value)
            end
        end
    )
    addInformationOption(
        FreezeFeature,
        "Anchor stops all physics; Humanoid only blocks character controls."
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()
    end
    Module.Initialized = true
    return FreezeFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Blatant/Speed.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Speed",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local movementInput: any = context.services.movementInput
    local framework: any = context.framework
    local LocalPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace

    local runtime: any = {
        originalWalkSpeed = setmetatable({}, {__mode = "k"}) :: any,
        nextTeleportAt = 0,
    }

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? =
            character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? =
            character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function restoreWalkSpeed(): ()
        for humanoid: Humanoid, value: number in pairs(runtime.originalWalkSpeed) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = value
            end
        end
        runtime.originalWalkSpeed = setmetatable({}, {__mode = "k"}) :: any
    end

    local function moveDirection(): Vector3
        local camera: Camera? = currentWorkspace.CurrentCamera
        local forward: number, right: number = 0, 0
        if movementInput.getVector then
            forward, right = movementInput.getVector()
        end
        if forward == 0 and right == 0 then
            local _, humanoid: Humanoid? = characterParts()
            local move: Vector3 = humanoid and humanoid.MoveDirection or Vector3.zero
            return move.Magnitude > 0.05 and move.Unit or Vector3.zero
        end
        if not camera then
            return Vector3.zero
        end
        local look: Vector3 = (camera :: Camera).CFrame.LookVector
        local side: Vector3 = (camera :: Camera).CFrame.RightVector
        local flatLook: Vector3 = Vector3.new(look.X, 0, look.Z)
        local flatSide: Vector3 = Vector3.new(side.X, 0, side.Z)
        if flatLook.Magnitude < 0.001 then
            return Vector3.zero
        end
        local direction: Vector3 =
            flatLook.Unit * forward + flatSide.Unit * right
        return direction.Magnitude > 0.05 and direction.Unit or Vector3.zero
    end

    local function blocked(root: BasePart, step: Vector3): Vector3
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.RespectCanCollide = true
        local ignore: {Instance} = {LocalPlayer.Character :: Instance}
        for _, player: Player in ipairs(host.Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                table.insert(ignore, player.Character :: Instance)
            end
        end
        parameters.FilterDescendantsInstances = ignore
        local hit: RaycastResult? =
            currentWorkspace:Raycast(root.Position, step, parameters)
        if not hit then
            return step
        end
        return ((hit :: RaycastResult).Position + (hit :: RaycastResult).Normal)
            - root.Position
    end

    local speed: any
    speed = framework.Categories.Blatant:CreateModule({
        Name = "SpeedHack",
        Category = "Blatant",
        ConfigKey = "Universal.Speed",
        Order = 1,
        Tooltip = "Move faster, by whichever of five methods this game lets "
            .. "through.",
        Function = function(enabled: boolean): ()
            runtime.nextTeleportAt = 0
            if not enabled then
                speed:SetStatus(nil)
                restoreWalkSpeed()
                return
            end
            speed:SetStatus(
                tostring(speed.Options["Mode"].Value)
                    .. " "
                    .. tostring(math.round(speed.Options["Speed"].Value))
            )
            speed:Clean(restoreWalkSpeed)
            speed:Loop(function(deltaTime: number): ()
                local options: any = speed.Options
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root then
                    return
                end
                local resolvedHumanoid: Humanoid = humanoid :: Humanoid
                local resolvedRoot: BasePart = root :: BasePart
                if resolvedHumanoid.Health <= 0 then
                    return
                end

                local mode: string = options["Mode"].Value
                local target: number = options["Speed"].Value

                if mode == "WalkSpeed" then
                    if runtime.originalWalkSpeed[resolvedHumanoid] == nil then
                        runtime.originalWalkSpeed[resolvedHumanoid] =
                            resolvedHumanoid.WalkSpeed
                    end
                    resolvedHumanoid.WalkSpeed = target
                    return
                end
                restoreWalkSpeed()

                local direction: Vector3 = moveDirection()
                if direction.Magnitude < 0.05 then
                    return
                end

                if options["Auto jump"].Value
                    and resolvedHumanoid.FloorMaterial ~= Enum.Material.Air then
                    resolvedHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end

                local velocity: Vector3 = resolvedRoot.AssemblyLinearVelocity
                if mode == "Velocity" then
                    resolvedRoot.AssemblyLinearVelocity = Vector3.new(
                        direction.X * target,
                        velocity.Y,
                        direction.Z * target
                    )
                    return
                end
                if mode == "Impulse" then
                    local wanted: Vector3 = direction * target
                    local difference: Vector3 = Vector3.new(
                        wanted.X - velocity.X,
                        0,
                        wanted.Z - velocity.Z
                    )
                    if difference.Magnitude > 2 then
                        resolvedRoot:ApplyImpulse(
                            difference * resolvedRoot.AssemblyMass
                        )
                    end
                    return
                end

                local extra: number =
                    math.max(target - resolvedHumanoid.WalkSpeed, 0)
                if mode == "Teleport" then
                    local now: number = os.clock()
                    if now < runtime.nextTeleportAt then
                        return
                    end
                    runtime.nextTeleportAt = now + options["Burst delay"].Value
                    local step: Vector3 = direction * extra
                        * options["Burst delay"].Value
                    if options["Wall check"].Value then
                        step = blocked(resolvedRoot, step)
                    end
                    resolvedRoot.CFrame = resolvedRoot.CFrame + step
                    return
                end

                local step: Vector3 = direction * extra * deltaTime
                if options["Wall check"].Value then
                    step = blocked(resolvedRoot, step)
                end
                resolvedRoot.CFrame = resolvedRoot.CFrame + step
            end)
        end,
    })

    speed:CreateDropdown({
        Name = "Mode",
        List = {"WalkSpeed", "Velocity", "Impulse", "CFrame", "Teleport"},
        Index = 1,
        Function = function(value: string): ()
            if speed.Enabled then
                speed:SetStatus(
                    value .. " " .. tostring(math.round(speed.Options["Speed"].Value))
                )
            end
        end,
        Tooltip = "WalkSpeed is the quietest and the first thing a game "
            .. "clamps; CFrame works where the others are ignored; Teleport is "
            .. "the fastest and the most obvious.",
    })
    speed:CreateSlider({
        Name = "Speed",
        Min = 16,
        Max = 200,
        Default = 32,
        Function = function(value: number): ()
            if speed.Enabled then
                speed:SetStatus(
                    tostring(speed.Options["Mode"].Value)
                        .. " "
                        .. tostring(math.round(value))
                )
            end
        end,
        Tooltip = "Studs per second. A default character walks at 16, sprints "
            .. "in most games at 24-28; past about 60 you are visibly not "
            .. "running.",
    })
    speed:CreateToggle({
        Name = "Wall check",
        Show = {Option = "Mode", Values = {"CFrame", "Teleport"}},
        Default = true,
        Tooltip = "Stop at geometry instead of stepping through it. Only the "
            .. "two modes that move you directly can go through a wall.",
    })
    speed:CreateSlider({
        Name = "Burst delay",
        Show = {Option = "Mode", Values = {"Teleport"}},
        Min = 0.05,
        Max = 1,
        Default = 0.2,
        Tooltip = "Seconds between jumps. Shorter is faster and reads as "
            .. "teleporting; longer reads as lag.",
    })
    speed:CreateToggle({
        Name = "Auto jump",
        Show = {Option = "Mode", Values = {"Velocity", "Impulse", "CFrame", "Teleport"}},
        Default = false,
        Tooltip = "Hop continuously while moving, for games that only clamp a "
            .. "character that is standing on something.",
    })
    speed:CreateNote(
        "If nothing happens, the game is clamping that method — try the next "
            .. "one down the list. WalkSpeed and Velocity are the two that "
            .. "look like a person moving."
    )

    activeCleanup = function(): ()
        restoreWalkSpeed()
    end
    Module.Initialized = true
    return speed
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Combat/Hitboxes.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Hitboxes",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local entityLibrary: any = context.entity
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer

    type HitboxSettings = {
        part: string,
        expand: number,
        reveal: boolean,
        transparency: number,
        teamCheck: boolean,
        includeNpcs: boolean,
        noCollision: boolean,
    }

    type HitboxWritten = {
        size: Vector3,
        transparency: number,
        canCollide: boolean,
        massless: boolean,
    }

    type OriginalHitboxState = {
        size: Vector3,
        transparency: number,
        canCollide: boolean,
        massless: boolean,

        written: HitboxWritten,
    }

    local hitboxSettings: HitboxSettings = {
        part = "Root",
        expand = 6,
        reveal = false,
        transparency = 60,
        teamCheck = true,
        includeNpcs = false,
        noCollision = true,
    }
    local originalHitboxes: {[BasePart]: OriginalHitboxState} =
        setmetatable({}, {__mode = "k"}) :: any

    local function restoreHitboxPart(part: BasePart): ()
        local original: OriginalHitboxState? = originalHitboxes[part]
        if not original then
            return
        end
        if part.Parent then
            part.Size = (original :: OriginalHitboxState).size
            part.Transparency = (original :: OriginalHitboxState).transparency
            part.CanCollide = (original :: OriginalHitboxState).canCollide
            part.Massless = (original :: OriginalHitboxState).massless
        end
        originalHitboxes[part] = nil
    end

    local function restoreHitboxes(): ()
        for part: BasePart in pairs(originalHitboxes) do
            restoreHitboxPart(part)
        end
        originalHitboxes = setmetatable({}, {__mode = "k"}) :: any
    end

    local function applyHitboxToPart(part: BasePart): ()
        local original: OriginalHitboxState? = originalHitboxes[part]
        if not original then
            original = {
                size = part.Size,
                transparency = part.Transparency,
                canCollide = part.CanCollide,
                massless = part.Massless,
                written = {
                    size = part.Size,
                    transparency = part.Transparency,
                    canCollide = part.CanCollide,
                    massless = part.Massless,
                },
            }
            originalHitboxes[part] = original
        end
        local resolved: OriginalHitboxState = original :: OriginalHitboxState
        local last: HitboxWritten = resolved.written

        if part.Size ~= last.size then
            resolved.size = part.Size
        end
        if part.Transparency ~= last.transparency then
            resolved.transparency = part.Transparency
        end
        if part.CanCollide ~= last.canCollide then
            resolved.canCollide = part.CanCollide
        end
        if part.Massless ~= last.massless then
            resolved.massless = part.Massless
        end

        local expand: number = hitboxSettings.expand
        local nextSize: Vector3 = resolved.size + Vector3.new(expand, expand, expand)
        local nextTransparency: number = hitboxSettings.reveal
            and math.clamp(hitboxSettings.transparency / 100, 0, 1)
            or resolved.transparency
        local nextCanCollide: boolean = not hitboxSettings.noCollision and resolved.canCollide

        if part.Size ~= nextSize then
            part.Size = nextSize
        end
        if part.Transparency ~= nextTransparency then
            part.Transparency = nextTransparency
        end
        if part.CanCollide ~= nextCanCollide then
            part.CanCollide = nextCanCollide
        end
        if not part.Massless then
            part.Massless = true
        end
        last.size = nextSize
        last.transparency = nextTransparency
        last.canCollide = nextCanCollide
        last.massless = true
    end

    local function applyHitboxCharacter(character: Model): ()
        local wanted: {string} = hitboxSettings.part == "Head"
            and {"Head"}
            or (hitboxSettings.part == "Both" and {"HumanoidRootPart", "Head"})
            or {"HumanoidRootPart"}
        for _, child: Instance in ipairs(character:GetChildren()) do
            if not child:IsA("BasePart") then
                continue
            end
            local part: BasePart = child :: BasePart
            if table.find(wanted, part.Name) then
                applyHitboxToPart(part)
            else
                restoreHitboxPart(part)
            end
        end
    end

    local function hitboxTargets(): {Model}
        local targets: {Model} = {}
        entityLibrary:Refresh()
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then
                continue
            end
            if hitboxSettings.teamCheck and entityLibrary:IsFriendly(player) then
                continue
            end
            if entityLibrary:IsProtected(player) then
                continue
            end
            local character: Model? = player.Character
            local humanoid: Humanoid? = character
                and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if character and humanoid and humanoid.Health > 0 then
                table.insert(targets, character :: Model)
            end
        end
        if hitboxSettings.includeNpcs then
            for _, npc: any in ipairs(entityLibrary.NPCList or {}) do
                if (not hitboxSettings.teamCheck or not npc.IsFriendly)
                    and npc.Character
                    and npc.Humanoid
                    and npc.Humanoid.Health > 0 then
                    table.insert(targets, npc.Character)
                end
            end
        end
        return targets
    end

    local function sweepHitboxes(): ()
        local alive: {[BasePart]: boolean} = {}
        for _, character: Model in ipairs(hitboxTargets()) do
            applyHitboxCharacter(character)
            for _, child: Instance in ipairs(character:GetChildren()) do
                if child:IsA("BasePart") and originalHitboxes[child :: BasePart] then
                    alive[child :: BasePart] = true
                end
            end
        end

        for part: BasePart in pairs(originalHitboxes) do
            if not alive[part] then
                restoreHitboxPart(part)
            end
        end
    end

    local hitboxes: any
    hitboxes = framework.Categories.Combat:CreateModule({
        Name = "Hitboxes",
        Category = "Combat",
        Order = 3,
        Tooltip = "Expand the part enemies are hit on, in studs. Teammates and "
            .. "friends are left alone, and every part is restored exactly when "
            .. "it stops being a target.",
        Function = function(enabled: boolean): ()
            restoreHitboxes()
            if not enabled then
                hitboxes:SetStatus(nil)
                return
            end
            hitboxes:SetStatus(
                hitboxSettings.part .. " +" .. tostring(math.round(hitboxSettings.expand))
            )
            hitboxes:Clean(restoreHitboxes)

            hitboxes:Loop(function(): ()
                sweepHitboxes()
            end)
        end,
    })
    hitboxes:CreateDropdown({
        Name = "Part",
        List = {"Root", "Head", "Both"},
        Index = 1,
        Function = function(value: string): ()
            hitboxSettings.part = value
            if hitboxes.Enabled then
                hitboxes:SetStatus(
                    value .. " +" .. tostring(math.round(hitboxSettings.expand))
                )
            end
        end,
        Tooltip = "Which part of the character is expanded. Parts the new "
            .. "mode no longer owns are restored on the next sweep.",
    })
    hitboxes:CreateSlider({
        Name = "Expand",
        Min = 0,
        Max = 30,
        Default = hitboxSettings.expand,
        Function = function(value: number): ()
            hitboxSettings.expand = value
            if hitboxes.Enabled then
                hitboxes:SetStatus(
                    hitboxSettings.part .. " +" .. tostring(math.round(value))
                )
            end
        end,
        Tooltip = "Studs added to the target part. Past roughly 10 the box is "
            .. "wider than the character is tall and anyone watching can see "
            .. "hits landing on nothing.",
    })
    hitboxes:CreateToggle({
        Name = "Team check",
        Default = hitboxSettings.teamCheck,
        Function = function(value: boolean): ()
            hitboxSettings.teamCheck = value
        end,
        Tooltip = "Leave teammates at their real size.",
    })
    hitboxes:CreateToggle({
        Name = "Include NPCs",
        Default = hitboxSettings.includeNpcs,
        Function = function(value: boolean): ()
            hitboxSettings.includeNpcs = value
        end,
    })
    hitboxes:CreateToggle({
        Name = "Show hitbox",
        Default = hitboxSettings.reveal,
        Function = function(value: boolean): ()
            hitboxSettings.reveal = value
        end,
        Tooltip = "Draw the expanded part so you can see what you are actually "
            .. "aiming at.",
    })
    hitboxes:CreateSlider({
        Name = "Show transparency %",
        Show = {Option = "Show hitbox"},
        Min = 0,
        Max = 95,
        Default = hitboxSettings.transparency,
        Function = function(value: number): ()
            hitboxSettings.transparency = value
        end,
    })
    hitboxes:CreateToggle({
        Name = "No collision",
        Default = hitboxSettings.noCollision,
        Function = function(value: boolean): ()
            hitboxSettings.noCollision = value
        end,
        Tooltip = "An expanded part that still collides pushes its owner "
            .. "around the map, which everyone in the server can see.",
    })

    activeCleanup = function(): ()
        restoreHitboxes()
    end
    Module.Initialized = true
    return hitboxes
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Render/ProjectileCalibration.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "ProjectileCalibration",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeController: any = nil
local activeRegistry: any = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local calibrationService: any = context.services.projectileCalibration
    local product: any = host.PRODUCT
    local notify: any = host.notify
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local addActionOption: any = host.addActionOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager
    local LocalPlayer: any = host.LocalPlayer
    local HttpService: any = host.HttpService
    local Stats: any = host.Stats

    local controllerFactory = (function(): any
        type PendingActivation = {
            tool: Tool,
            activatedAt: number,
            origin: Vector3?,
            aim: Vector3?,
            pingMs: number,
        }
        type ProjectileSample = {
            t: number,
            position: {number},
            velocity: {number},
            speed: number,
        }
        type ProjectileTrack = {
            instance: BasePart,
            toolName: string,
            projectileName: string,
            startedAt: number,
            launchDelayMs: number,
            pingMs: number,
            origin: Vector3,
            previousAt: number?,
            previousPosition: Vector3?,
            speeds: {number},
            accelerations: {number},
            verticalAccelerations: {number},
            samples: {ProjectileSample},
            distance: number,
            destroyConnection: RBXScriptConnection?,
        }
        type BucketRecord = {
            count: number,
            speedSum: number,
            speedSquaredSum: number,
            delaySum: number,
        }
        type Controller = {
            setEnabled: (self: Controller, enabled: boolean) -> (),
            save: (self: Controller, reason: string?) -> boolean,
            delete: (self: Controller) -> boolean,
            status: (self: Controller) -> string,
            destroy: (self: Controller) -> (),
            tuning: {[string]: number},
        }

        local tuning: {[string]: number} = {
            bucketWidthMs = 5,
            maxBucketMs = 250,
            sampleWindowSeconds = 2.5,
            maxSamplesPerTrack = 150,
            minProjectileSpeed = 10,
            matchDistanceStuds = 40,
            maxPendingActivations = 10,
            candidateLifetimeSeconds = 1.1,
        }

        local executorEnvironment: {[string]: any} = getfenv() :: any
        local mouse: Mouse = LocalPlayer:GetMouse()
        local outputRoot: string = product.storageFolder
        local outputTelemetry: string = outputRoot .. "/Telemetry"
        local outputFolder: string = outputTelemetry .. "/Universal"
        local outputPath: string = outputFolder
            .. "/Place_"
            .. tostring(game.PlaceId)
            .. "_Projectile_Calibration.json"
        local runtime: any = {
            enabled = false,
            dirty = false,
            startedAt = os.clock(),
            pending = {} :: {PendingActivation},
            tracks = {} :: {[BasePart]: ProjectileTrack},
            events = {} :: {{[string]: any}},
            buckets = {} :: {[string]: BucketRecord},
            connections = {} :: {RBXScriptConnection},
            observedTools = setmetatable({}, {__mode = "k"}) :: {[Tool]: boolean},
            observedCandidates = setmetatable({}, {__mode = "k"}) :: {[BasePart]: boolean},
            sampler = nil :: any,
            totalActivations = 0,
            totalProjectiles = 0,
            rejectedCandidates = 0,
        }
        local controller: Controller
        local saveSnapshot: (reason: string) -> boolean
        local finishTrack: (part: BasePart, reason: string) -> ()

        local function finite(value: number): boolean
            return value == value and value > -math.huge and value < math.huge
        end

        local function vectorArray(value: Vector3): {number}
            return {value.X, value.Y, value.Z}
        end

        local function median(values: {number}): number?
            if #values == 0 then
                return nil
            end
            local sorted: {number} = table.clone(values)
            table.sort(sorted)
            local middle: number = math.floor((#sorted + 1) / 2)
            if #sorted % 2 == 1 then
                return sorted[middle]
            end
            return (sorted[middle] + sorted[middle + 1]) * 0.5
        end

        local function pingBucketKey(pingMs: number): string
            local width: number = math.max(1, tuning.bucketWidthMs)
            local ceiling: number = math.max(width, tuning.maxBucketMs)
            if pingMs > ceiling then
                return tostring(ceiling) .. "+"
            end
            local lower: number = math.clamp(
                math.floor(pingMs / width) * width,
                0,
                math.max(0, ceiling - width)
            )
            local upper: number = lower + width
            return string.format("%03d-%03d", lower, upper)
        end

        local function ensureBucket(key: string): BucketRecord
            local existing: BucketRecord? = runtime.buckets[key]
            if existing then
                return existing
            end
            local created: BucketRecord = {
                count = 0,
                speedSum = 0,
                speedSquaredSum = 0,
                delaySum = 0,
            }
            runtime.buckets[key] = created
            return created
        end

        local function bucketPayload(): {[string]: any}
            local payload: {[string]: any} = {}
            for key: string, bucket: BucketRecord in pairs(runtime.buckets) do
                local meanSpeed: number = bucket.count > 0
                        and bucket.speedSum / bucket.count
                    or 0
                local variance: number = bucket.count > 1
                        and math.max(
                            0,
                            bucket.speedSquaredSum / bucket.count
                                - meanSpeed * meanSpeed
                        )
                    or 0
                payload[key] = {
                    count = bucket.count,
                    meanSpeed = meanSpeed,
                    speedStdDev = math.sqrt(variance),
                    meanLaunchDelayMs = bucket.count > 0
                            and bucket.delaySum / bucket.count
                        or 0,
                }
            end
            return payload
        end

        local function getPingMilliseconds(): number
            local pingMs: number = 0
            pcall(function(): ()
                local network: Instance? = Stats:FindFirstChild("Network")
                local serverItems: Instance? = network
                    and network:FindFirstChild("ServerStatsItem")
                local pingItem: any = serverItems
                    and serverItems:FindFirstChild("Data Ping")
                if pingItem and type(pingItem.GetValue) == "function" then
                    pingMs = tonumber(pingItem:GetValue()) or 0
                end
            end)
            return math.max(0, pingMs)
        end

        local function appendEvent(event: {[string]: any}): ()
            if #runtime.events >= 180 then
                table.remove(runtime.events, 1)
            end
            table.insert(runtime.events, event)
            runtime.dirty = true
        end

        saveSnapshot = function(reason: string): boolean
            if type(executorEnvironment.writefile) ~= "function" then
                return false
            end
            local payload: {[string]: any} = {
                schema = 1,
                kind = "universal-projectile-analytics",
                placeId = game.PlaceId,
                gameId = game.GameId,
                savedAt = DateTime.now():ToIsoDate(),
                reason = reason,
                bucketSpec = {
                    metric = "Data Ping",
                    widthMs = tuning.bucketWidthMs,
                    minimumMs = 0,
                    maximumMs = tuning.maxBucketMs,
                    overflow = tostring(tuning.maxBucketMs) .. "+",
                },
                summary = {
                    activations = runtime.totalActivations,
                    projectiles = runtime.totalProjectiles,
                    rejectedCandidates = runtime.rejectedCandidates,
                    elapsedSeconds = os.clock() - runtime.startedAt,
                },
                pingBuckets = bucketPayload(),
                projectiles = runtime.events,
            }
            local encodedOk: boolean, encoded: any = pcall(
                HttpService.JSONEncode,
                HttpService,
                payload
            )
            if not encodedOk or type(encoded) ~= "string" then
                return false
            end
            if type(executorEnvironment.makefolder) == "function" then
                pcall(executorEnvironment.makefolder, outputRoot)
                pcall(executorEnvironment.makefolder, outputTelemetry)
                pcall(executorEnvironment.makefolder, outputFolder)
            end
            local writeOk: boolean = pcall(
                executorEnvironment.writefile,
                outputPath,
                encoded
            )
            if not writeOk then
                return false
            end
            runtime.dirty = false
            return true
        end

        local function disconnectAll(): ()
            if runtime.sampler then
                runtime.sampler:Disconnect()
                runtime.sampler = nil
            end
            for _, connection: RBXScriptConnection in ipairs(runtime.connections) do
                connection:Disconnect()
            end
            table.clear(runtime.connections)
            for part: BasePart, track: ProjectileTrack in pairs(runtime.tracks) do
                if track.destroyConnection then
                    track.destroyConnection:Disconnect()
                end
                runtime.tracks[part] = nil
            end
            table.clear(runtime.pending)
            runtime.observedTools = setmetatable({}, {__mode = "k"})
            runtime.observedCandidates = setmetatable({}, {__mode = "k"})
        end

        local function compactPending(now: number): ()
            while #runtime.pending > 0
                and now - runtime.pending[1].activatedAt
                    > tuning.candidateLifetimeSeconds do
                table.remove(runtime.pending, 1)
            end
            while #runtime.pending > tuning.maxPendingActivations do
                table.remove(runtime.pending, 1)
            end
        end

        local function isCharacterPart(part: BasePart): boolean
            local model: Model? = part:FindFirstAncestorOfClass("Model")
            return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
        end

        local function hasProjectileHint(part: BasePart): boolean
            local name: string = string.lower(part.Name)
            local parentName: string = part.Parent and string.lower(part.Parent.Name) or ""
            local combined: string = name .. " " .. parentName
            return string.find(combined, "projectile", 1, true) ~= nil
                or string.find(combined, "bullet", 1, true) ~= nil
                or string.find(combined, "arrow", 1, true) ~= nil
                or string.find(combined, "rocket", 1, true) ~= nil
                or string.find(combined, "missile", 1, true) ~= nil
                or string.find(combined, "knife", 1, true) ~= nil
                or string.find(combined, "grenade", 1, true) ~= nil
                or string.find(combined, "shell", 1, true) ~= nil
                or string.find(combined, "bolt", 1, true) ~= nil
                or string.find(combined, "orb", 1, true) ~= nil
                or part:GetAttribute("Projectile") == true
                or part:GetAttribute("ProjectileSpeed") ~= nil
                or part:GetAttribute("ThrowSpeed") ~= nil
        end

        local function resolveCandidate(instance: Instance): BasePart?
            if not instance:IsA("BasePart") then
                return nil
            end
            local part: BasePart = instance
            if part.Anchored
                or isCharacterPart(part)
                or (LocalPlayer.Character and part:IsDescendantOf(LocalPlayer.Character)) then
                return nil
            end
            local root: BasePart = part.AssemblyRootPart or part
            if runtime.observedCandidates[root] or isCharacterPart(root) then
                return nil
            end
            return root
        end

        local function ensureSampler(): ()
            if runtime.sampler then
                return
            end
            runtime.sampler = TaskManager:Connect(function(_deltaTime: number): ()
                local now: number = os.clock()
                local completed: {BasePart} = {}
                for part: BasePart, track: ProjectileTrack in pairs(runtime.tracks) do
                    if not part.Parent
                        or now - track.startedAt >= tuning.sampleWindowSeconds then
                        table.insert(completed, part)
                        continue
                    end
                    local position: Vector3 = part.Position
                    local velocity: Vector3 = part.AssemblyLinearVelocity
                    local speed: number = velocity.Magnitude
                    if track.previousPosition and track.previousAt then
                        local deltaTime: number = now - track.previousAt
                        if deltaTime >= 1 / 240 then
                            local measuredVelocity: Vector3 =
                                (position - track.previousPosition) / deltaTime
                            local measuredSpeed: number = measuredVelocity.Magnitude
                            if measuredSpeed >= 1 and measuredSpeed <= 5000 then
                                table.insert(track.speeds, measuredSpeed)
                                if #track.samples > 0 then
                                    local previousSample: ProjectileSample =
                                        track.samples[#track.samples]
                                    local previousVelocity: Vector3 = Vector3.new(
                                        previousSample.velocity[1],
                                        previousSample.velocity[2],
                                        previousSample.velocity[3]
                                    )
                                    local acceleration: Vector3 =
                                        (measuredVelocity - previousVelocity) / deltaTime
                                    if acceleration.Magnitude <= 10000 then
                                        table.insert(track.accelerations, acceleration.Magnitude)
                                        table.insert(track.verticalAccelerations, acceleration.Y)
                                    end
                                end
                            end
                            track.distance += (position - track.previousPosition).Magnitude
                        end
                    end
                    if #track.samples < tuning.maxSamplesPerTrack then
                        table.insert(track.samples, {
                            t = now - track.startedAt,
                            position = vectorArray(position),
                            velocity = vectorArray(velocity),
                            speed = speed,
                        })
                    end
                    track.previousPosition = position
                    track.previousAt = now
                end
                for _, part: BasePart in ipairs(completed) do
                    finishTrack(part, "sample-window-complete")
                end
                if next(runtime.tracks) == nil and runtime.sampler then
                    runtime.sampler:Disconnect()
                    runtime.sampler = nil
                end
            end)
        end

        finishTrack = function(part: BasePart, reason: string): ()
            local track: ProjectileTrack? = runtime.tracks[part]
            if not track then
                return
            end
            runtime.tracks[part] = nil
            if track.destroyConnection then
                track.destroyConnection:Disconnect()
                track.destroyConnection = nil
            end
            local speed: number? = median(track.speeds)
            if not speed or not finite(speed) or speed < 1 then
                runtime.rejectedCandidates += 1
                return
            end
            local acceleration: number? = median(track.accelerations)
            local verticalAcceleration: number? = median(track.verticalAccelerations)
            local bucketKey: string = pingBucketKey(track.pingMs)
            local bucket: BucketRecord = ensureBucket(bucketKey)
            bucket.count += 1
            bucket.speedSum += speed
            bucket.speedSquaredSum += speed * speed
            bucket.delaySum += track.launchDelayMs
            runtime.totalProjectiles += 1
            appendEvent({
                tool = track.toolName,
                projectile = track.projectileName,
                pingMs = track.pingMs,
                pingBucket = bucketKey,
                launchDelayMs = track.launchDelayMs,
                medianSpeed = speed,
                medianAcceleration = acceleration,
                medianVerticalAcceleration = verticalAcceleration,
                distanceStuds = track.distance,
                durationSeconds = os.clock() - track.startedAt,
                reason = reason,
                samples = track.samples,
            })
        end

        local function considerCandidate(instance: Instance): ()
            if not runtime.enabled or #runtime.pending == 0 then
                return
            end
            local part: BasePart? = resolveCandidate(instance)
            if not part then
                return
            end
            local now: number = os.clock()
            compactPending(now)
            if #runtime.pending == 0 then
                return
            end
            local hinted: boolean = hasProjectileHint(part)
            local speed: number = part.AssemblyLinearVelocity.Magnitude
            if not hinted and speed < tuning.minProjectileSpeed then
                return
            end
            local selectedIndex: number? = nil
            local selectedScore: number = math.huge
            for index: number = #runtime.pending, 1, -1 do
                local pending: PendingActivation = runtime.pending[index]
                if not part:IsDescendantOf(pending.tool) and pending.origin then
                    local offset: Vector3 = part.Position - pending.origin
                    local distance: number = offset.Magnitude
                    if distance <= 40 then
                        local alignmentPenalty: number = 0
                        if pending.aim and distance > 0.01 then
                            local desired: Vector3 = pending.aim - pending.origin
                            if desired.Magnitude > 0.01 then
                                local alignment: number = offset.Unit:Dot(desired.Unit)
                                if alignment < 0.35 and not hinted then
                                    continue
                                end
                                alignmentPenalty = (1 - alignment) * 0.25
                            end
                        end
                        local score: number = now - pending.activatedAt
                            + distance * 0.01
                            + alignmentPenalty
                            + (hinted and 0 or 0.2)
                        if score < selectedScore then
                            selectedScore = score
                            selectedIndex = index
                        end
                    end
                end
            end
            if not selectedIndex then
                runtime.rejectedCandidates += 1
                return
            end
            local pending: PendingActivation = table.remove(runtime.pending, selectedIndex)
            runtime.observedCandidates[part] = true
            local track: ProjectileTrack = {
                instance = part,
                toolName = pending.tool.Name,
                projectileName = part:GetFullName(),
                startedAt = now,
                launchDelayMs = math.max(0, (now - pending.activatedAt) * 1000),
                pingMs = pending.pingMs,
                origin = pending.origin :: Vector3,
                previousAt = now,
                previousPosition = part.Position,
                speeds = {},
                accelerations = {},
                verticalAccelerations = {},
                samples = {},
                distance = 0,
                destroyConnection = nil,
            }
            runtime.tracks[part] = track
            track.destroyConnection = part.Destroying:Connect(function(): ()
                finishTrack(part, "destroyed")
            end)
            ensureSampler()
        end

        local function observeTool(tool: Tool): ()
            if runtime.observedTools[tool] then
                return
            end
            runtime.observedTools[tool] = true
            table.insert(runtime.connections, tool.Activated:Connect(function(): ()
                if not runtime.enabled then
                    return
                end
                local originPart: BasePart? = tool:FindFirstChild("Handle") :: BasePart?
                local characterRoot: BasePart? = LocalPlayer.Character
                    and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    :: BasePart?
                local origin: Vector3? = originPart and originPart:IsA("BasePart")
                        and originPart.Position
                    or characterRoot and characterRoot.Position
                    or nil
                if not origin then
                    return
                end
                local aim: Vector3? = nil
                pcall(function(): ()
                    aim = mouse.Hit.Position
                end)
                runtime.totalActivations += 1
                table.insert(runtime.pending, {
                    tool = tool,
                    activatedAt = os.clock(),
                    origin = origin,
                    aim = aim,
                    pingMs = getPingMilliseconds(),
                })
                compactPending(os.clock())
            end))
        end

        local function observeContainer(container: Instance?): ()
            if not container then
                return
            end
            for _, child: Instance in ipairs(container:GetChildren()) do
                if child:IsA("Tool") then
                    observeTool(child)
                end
            end
            table.insert(runtime.connections, container.ChildAdded:Connect(function(
                child: Instance
            ): ()
                if child:IsA("Tool") then
                    observeTool(child)
                end
            end))
        end

        controller = {} :: Controller
        controller.tuning = tuning

        function controller:setEnabled(enabled: boolean): ()
            if runtime.enabled == enabled then
                return
            end
            if not enabled then
                runtime.enabled = false
                disconnectAll()
                return
            end
            runtime.enabled = true
            runtime.startedAt = os.clock()
            observeContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
            observeContainer(LocalPlayer.Character)
            table.insert(runtime.connections, LocalPlayer.CharacterAdded:Connect(function(
                character: Model
            ): ()
                observeContainer(character)
            end))
            table.insert(runtime.connections, workspace.DescendantAdded:Connect(
                considerCandidate
            ))
        end

        function controller:save(reason: string?): boolean
            return saveSnapshot(reason or "manual")
        end

        function controller:delete(): boolean
            local deleteFile: any = executorEnvironment.delfile
            local isFile: any = executorEnvironment.isfile
            if type(deleteFile) ~= "function" then
                return false
            end
            local exists: boolean = true
            if type(isFile) == "function" then
                local checked: boolean, result: any = pcall(isFile, outputPath)
                exists = checked and result == true
            end
            if exists then
                local deleted: boolean = pcall(deleteFile, outputPath)
                if not deleted then
                    return false
                end
            end
            runtime.events = {}
            runtime.buckets = {}
            runtime.totalActivations = 0
            runtime.totalProjectiles = 0
            runtime.rejectedCandidates = 0
            runtime.dirty = false
            return true
        end

        function controller:status(): string
            return string.format(
                "Universal · activations %d · projectiles %d · buckets %d",
                runtime.totalActivations,
                runtime.totalProjectiles,
                (function(): number
                    local count: number = 0
                    for _key: string in pairs(runtime.buckets) do
                        count += 1
                    end
                    return count
                end)()
            )
        end

        function controller:destroy(): ()
            self:setEnabled(false)
        end

        return controller
    end)()

    local calibration: any = controllerFactory
    calibrationService.set(calibration)
    activeRegistry = calibrationService
    calibration:setEnabled(true)

    local tuning: any = calibration.tuning

    local ProjectileCalibrationFeature: any = createUniversalFeature(
        "Projectile Calibration",
        "Automatic per-game projectile analytics with tunable ping buckets",
        17,
        function(_enabled: boolean): () end,
        {category = true, categoryName = "Other"}
    )
    tuning =
        calibration.tuning
    addNumberOption(
        ProjectileCalibrationFeature,
        "Bucket width (ms)",
        tuning.bucketWidthMs,
        1,
        25,
        function(value: number): ()
            tuning.bucketWidthMs = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Bucket ceiling (ms)",
        tuning.maxBucketMs,
        25,
        500,
        function(value: number): ()
            tuning.maxBucketMs = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Sample window (s)",
        tuning.sampleWindowSeconds,
        1,
        6,
        function(value: number): ()
            tuning.sampleWindowSeconds = value
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Max samples / track",
        tuning.maxSamplesPerTrack,
        30,
        600,
        function(value: number): ()
            tuning.maxSamplesPerTrack = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Match radius (studs)",
        tuning.matchDistanceStuds,
        10,
        120,
        function(value: number): ()
            tuning.matchDistanceStuds = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Min projectile speed",
        tuning.minProjectileSpeed,
        1,
        100,
        function(value: number): ()
            tuning.minProjectileSpeed = math.round(value)
        end
    )
    addActionOption(ProjectileCalibrationFeature, "Show status", function(): ()
        notify(calibration:status())
    end)
    addActionOption(ProjectileCalibrationFeature, "Save analytics", function(): ()
        if calibration:save("manual") then
            notify("analytics saved")
        else
            notify("save failed; check F9")
        end
    end)
    addActionOption(ProjectileCalibrationFeature, "Delete analytics", function(): ()
        if calibration:delete() then
            notify("analytics deleted")
        else
            notify("delete failed; check F9")
        end
    end)
    addInformationOption(
        ProjectileCalibrationFeature,
        "Runs automatically. Save writes the current session; Delete clears it. MM2 prediction never consumes this dataset."
    )

    activeController = calibration
    Module.Initialized = true
    return calibration
end

function Module.destroy(): ()
    if activeController and type(activeController.destroy) == "function" then
        pcall(function(): ()
            activeController:destroy()
        end)
    end
    activeController = nil
    if activeRegistry then
        activeRegistry.set(nil)
    end
    activeRegistry = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/SpinBot.lua"] = [[export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

local Module = {
    Name = "SpinBot",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local getCharacterParts: any = context.host.getCharacterParts
    local baselines: any = setmetatable({}, {__mode = "k"})
    local currentRoot: BasePart? = nil

    local function restoreRoot(root: BasePart): ()
        local baseline: any = baselines[root]
        if not baseline then
            return
        end
        if root.Parent then
            root.AssemblyAngularVelocity = baseline.angularVelocity
            if baseline.cframeTouched then
                root.CFrame = CFrame.new(root.Position)
                    * (baseline.cframe - baseline.cframe.Position)
            end
            local humanoid: Humanoid? = root.Parent:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.AutoRotate = baseline.autoRotate
            end
        end
        baselines[root] = nil
    end

    local function restore(): ()
        for root: BasePart in pairs(baselines) do
            restoreRoot(root)
        end
        currentRoot = nil
        baselines = setmetatable({}, {__mode = "k"})
    end

    local card: any
    card = framework.Categories.Fun:CreateModule({
        Name = "SpinBot",
        Category = "Fun",
        ConfigKey = "Universal.SpinBot",
        Order = 40,
        Tooltip = "Rotates your character continuously around the selected axis.",
        Function = function(enabled: boolean): ()
            if not enabled then
                restore()
                card:SetStatus(nil)
                return
            end
            card:SetStatus(card.Options["Mode"].Value)
            card:Loop(function(deltaTime: number): ()
                local _character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not humanoid or not root or humanoid.Health <= 0 then
                    if currentRoot then
                        restoreRoot(currentRoot :: BasePart)
                        currentRoot = nil
                    end
                    return
                end
                if currentRoot and currentRoot ~= root then
                    restoreRoot(currentRoot :: BasePart)
                end
                currentRoot = root
                if not baselines[root] then
                    baselines[root] = {
                        angularVelocity = root.AssemblyAngularVelocity,
                        autoRotate = humanoid.AutoRotate,
                        cframe = root.CFrame,
                        cframeTouched = false,
                    }
                end
                humanoid.AutoRotate = false
                local speed: number = card.Options["Speed"].Value
                local axisName: string = card.Options["Axis"].Value
                local axis: Vector3 = axisName == "X" and Vector3.new(1, 0, 0)
                    or axisName == "Z" and Vector3.new(0, 0, 1)
                    or Vector3.new(0, 1, 0)
                if card.Options["Mode"].Value == "Velocity" then
                    root.AssemblyAngularVelocity = axis * math.rad(speed)
                else
                    root.AssemblyAngularVelocity = Vector3.zero
                    baselines[root].cframeTouched = true
                    local angle: number = math.rad(speed) * deltaTime
                    local rotation: CFrame = axisName == "X" and CFrame.Angles(angle, 0, 0)
                        or axisName == "Z" and CFrame.Angles(0, 0, angle)
                        or CFrame.Angles(0, angle, 0)
                    root.CFrame = root.CFrame * rotation
                end
            end)
            card:Clean(restore)
        end,
    })

    card:CreateDropdown({
        Name = "Mode",
        List = {"CFrame", "Velocity"},
        Index = 1,
        Tooltip = "CFrame turns the root directly. Velocity asks the physics "
            .. "engine to spin the assembly, which a server that owns your "
            .. "character can clamp.",
        Function = function(value: string): ()
            if card then
                card:SetStatus(value)
            end
        end,
    })
    card:CreateDropdown({
        Name = "Axis",
        List = {"Y", "X", "Z"},
        Index = 1,
        Tooltip = "Y turns you in place. X and Z tumble.",
    })
    card:CreateSlider({
        Name = "Speed",
        Min = 30,
        Max = 1440,
        Step = 15,
        Default = 360,
        Tooltip = "Degrees per second. 360 is one turn a second.",
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/Disguise.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Disguise",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function looksNumeric(text: string): boolean
    return string.match(text, "^%s*%d+%s*$") ~= nil
end

local function trimmed(text: string): string
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- Miniature Animate script for the local body double. The real character
-- keeps its own animations; the double copies the pose through these tracks.
local PUPPET_ANIMATIONS: {{key: string, field: string, priority: any}} = {
    {key = "idle", field = "IdleAnimation", priority = Enum.AnimationPriority.Idle},
    {key = "walk", field = "WalkAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "run", field = "RunAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "jump", field = "JumpAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "fall", field = "FallAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "climb", field = "ClimbAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "swim", field = "SwimAnimation", priority = Enum.AnimationPriority.Movement},
}

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local spoofAvatar: any = context.services.spoofAvatar
    local currentWorkspace: Workspace = host.workspace or workspace

    local runtime: any = {
        busy = false,
        generation = 0,
        target = nil :: any?,
        puppet = nil :: Model?,
        puppetParts = {} :: {BasePart},
        puppetTracks = {} :: {[string]: AnimationTrack},
        puppetHidden = false,
        diedWatch = nil :: RBXScriptConnection?,
        originals = nil :: any?,
        applied = false,
    }

    local disguise: any

    local function currentCharacter(): Model?
        local character: Model? = localPlayer.Character
        if character and character.Parent then
            return character
        end
        return nil
    end

    local function currentHumanoid(): Humanoid?
        local character: Model? = currentCharacter()
        if not character then
            return nil
        end
        return (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
    end

    local function characterDescription(humanoid: Humanoid): HumanoidDescription?
        local existing: Instance? = humanoid:FindFirstChild("HumanoidDescription")
        if existing and existing:IsA("HumanoidDescription") then
            return existing :: HumanoidDescription
        end
        local ok: boolean, found: any = pcall(function(): any
            return (humanoid :: any).HumanoidDescription
        end)
        if ok and typeof(found) == "Instance" then
            return found :: HumanoidDescription
        end
        return nil
    end

    -- Client-side transparency: only this client stops seeing the real body.
    local hidingConnection: RBXScriptConnection? = nil

    local function hidePart(part: BasePart): ()
        if part.LocalTransparencyModifier ~= 1 then
            part.LocalTransparencyModifier = 1
        end
    end

    local function hideCharacter(character: Model): ()
        for _, descendant: Instance in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") then
                hidePart(descendant :: BasePart)
            end
        end
        if hidingConnection then
            return
        end
        hidingConnection = character.DescendantAdded:Connect(function(descendant: Instance): ()
            if descendant:IsA("BasePart") then
                hidePart(descendant :: BasePart)
            end
        end)
    end

    local function showCharacter(): ()
        if hidingConnection then
            pcall(function(): ()
                (hidingConnection :: RBXScriptConnection):Disconnect()
            end)
            hidingConnection = nil
        end
        local character: Model? = currentCharacter()
        if character then
            for _, descendant: Instance in ipairs((character :: Model):GetDescendants()) do
                if descendant:IsA("BasePart") then
                    (descendant :: BasePart).LocalTransparencyModifier = 0
                end
            end
        end
    end

    -- Chat spoof: TextChatService lets the client rewrite how an incoming
    -- message is displayed, so your own messages show the disguise's name
    -- (only on your screen).
    local chatSpoofed: boolean = false

    local function patternEscape(text: string): string
        return (string.gsub(text, "%W", "%%%1"))
    end

    local function installChatSpoof(targetName: string): ()
        local ok: boolean, service: any = pcall(function(): any
            return game:GetService("TextChatService")
        end)
        if not ok or typeof(service) ~= "Instance" then
            return
        end
        chatSpoofed = true
        local myName: string = localPlayer.Name
        local myDisplay: string = localPlayer.DisplayName
        local safeTarget: string = (string.gsub(targetName, "%%", "%%%%"))
        pcall(function(): ()
            (service :: any).OnIncomingMessage = function(message: any): any
                local source: any = (message :: any).TextSource
                if not source or source.UserId ~= localPlayer.UserId then
                    return nil
                end
                local prefix: string = tostring((message :: any).PrefixText or "")
                local replaced: string? = nil
                if string.find(prefix, myDisplay, 1, true) then
                    replaced = string.gsub(
                        prefix,
                        patternEscape(myDisplay),
                        safeTarget,
                        1
                    )
                elseif string.find(prefix, myName, 1, true) then
                    replaced = string.gsub(prefix, patternEscape(myName), safeTarget, 1)
                end
                if not replaced then
                    return nil
                end
                local properties: any = Instance.new("TextChatMessageProperties")
                properties.PrefixText = replaced
                return properties
            end
        end)
    end

    local function removeChatSpoof(): ()
        if not chatSpoofed then
            return
        end
        chatSpoofed = false
        local ok: boolean, service: any = pcall(function(): any
            return game:GetService("TextChatService")
        end)
        if ok and typeof(service) == "Instance" then
            pcall(function(): ()
                (service :: any).OnIncomingMessage = nil
            end)
        end
    end

    -- Capture the real avatar once: display name, emote wheel and animation
    -- ids, so everything can be restored exactly on disable.
    local function rememberOriginals(humanoid: Humanoid): ()
        if runtime.originals then
            return
        end
        local description: HumanoidDescription? = nil
        local ok: boolean, applied: any = pcall(function(): any
            return humanoid:GetAppliedDescription()
        end)
        if ok and typeof(applied) == "Instance" then
            description = applied :: HumanoidDescription
        end
        local emotes: any = {}
        local equippedNames: {string} = {}
        local wheel: HumanoidDescription? = characterDescription(humanoid)
        if wheel then
            local emotesOk: boolean, current: any = pcall(function(): any
                return (wheel :: HumanoidDescription):GetEmotes()
            end)
            if emotesOk and type(current) == "table" then
                emotes = current
            end
            local equippedOk: boolean, equipped: any = pcall(function(): any
                return (wheel :: HumanoidDescription):GetEquippedEmotes()
            end)
            if equippedOk and type(equipped) == "table" then
                for _, entry: any in ipairs(equipped) do
                    local name: string = tostring(
                        type(entry) == "table"
                            and (entry.name or entry.Name)
                            or entry
                    )
                    if name ~= "" and name ~= "nil" then
                        table.insert(equippedNames, name)
                    end
                end
            end
        end
        runtime.originals = {
            displayName = humanoid.DisplayName,
            emotes = emotes,
            equippedNames = equippedNames,
            myDescription = description,
        }
    end

    local function restoreOriginals(): ()
        local originals: any = runtime.originals
        if not originals then
            return
        end
        local humanoid: Humanoid? = currentHumanoid()
        if humanoid then
            pcall(function(): ()
                (humanoid :: Humanoid).DisplayName = originals.displayName
            end)
            local wheel: HumanoidDescription? = characterDescription(humanoid :: Humanoid)
            if wheel then
                pcall(function(): ()
                    (wheel :: HumanoidDescription):SetEmotes(originals.emotes)
                    if #originals.equippedNames > 0 then
                        (wheel :: HumanoidDescription):SetEquippedEmotes(originals.equippedNames)
                    end
                end)
            end
        end
    end

    local function teardownPuppet(): ()
        local puppet: Model? = runtime.puppet
        runtime.puppet = nil
        runtime.puppetTracks = {}
        runtime.puppetParts = {}
        runtime.puppetHidden = false
        spoofAvatar.setRig(nil)
        if puppet then
            pcall(function(): ()
                (puppet :: Model):Destroy()
            end)
        end
    end

    local function setPuppetHidden(hidden: boolean): ()
        if runtime.puppetHidden == hidden then
            return
        end
        runtime.puppetHidden = hidden
        for _, part: BasePart in ipairs(runtime.puppetParts) do
            part.LocalTransparencyModifier = hidden and 1 or 0
        end
    end

    local function playPuppetTrack(key: string, fade: number): ()
        local track: AnimationTrack? = runtime.puppetTracks[key]
        if not track then
            return
        end
        for otherKey: string, other: AnimationTrack in pairs(runtime.puppetTracks) do
            if otherKey ~= key and other.IsPlaying then
                pcall(function(): ()
                    other:Stop(fade)
                end)
            end
        end
        if not (track :: AnimationTrack).IsPlaying then
            pcall(function(): ()
                (track :: AnimationTrack):Play(fade)
            end)
        end
    end

    -- Builds the local body double: a fully local rig from
    -- CreateHumanoidModelFromDescription that mirrors the real body. Your
    -- own avatar is never touched, so no game can reject or flag the swap,
    -- and the double carries no Humanoid, so the engine cannot apply the
    -- second-humanoid forces that fling characters.
    local function buildPuppet(target: any): ()
        local character: Model? = currentCharacter()
        local humanoid: Humanoid? = character
            and (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not character or not humanoid then
            return
        end
        rememberOriginals(humanoid :: Humanoid)
        teardownPuppet()

        runtime.generation += 1
        local generation: number = runtime.generation
        local rigType: Enum.HumanoidRigType = (humanoid :: Humanoid).RigType
        local description: HumanoidDescription = target.description

        local created: boolean, rig: any = pcall(function(): any
            return (host.Players :: Players):CreateHumanoidModelFromDescription(
                description,
                rigType
            )
        end)
        if generation ~= runtime.generation then
            if created and typeof(rig) == "Instance" then
                pcall(function(): ()
                    (rig :: Model):Destroy()
                end)
            end
            return
        end
        if not created or typeof(rig) ~= "Instance" then
            disguise:Notify("could not build the disguise body")
            return
        end

        local puppet: Model = rig :: Model
        puppet.Name = "WurstDisguise"
        -- Marked so NPC detection, targeting and ESP treat the double as
        -- scenery instead of a second character standing on top of you.
        puppet:SetAttribute("WurstDisguise", true)
        local puppetHumanoid: Humanoid? = puppet:FindFirstChildOfClass("Humanoid")
        local animator: Animator? = nil
        if puppetHumanoid then
            -- A second Humanoid beside your own makes your humanoid apply
            -- its special humanoid-vs-humanoid collisions against the
            -- double's root, which launches your character into the air.
            -- An AnimationController drives identical animation tracks with
            -- no humanoid physics at all, so the double stays harmless.
            local controller: AnimationController =
                Instance.new("AnimationController")
            controller.Name = "WurstDisguiseController"
            controller.Parent = puppet
            local oldHumanoid: Humanoid = puppetHumanoid :: Humanoid
            animator = oldHumanoid:FindFirstChildOfClass("Animator") :: Animator?
            if animator then
                (animator :: Animator).Parent = controller
            else
                local made: Animator = Instance.new("Animator")
                made.Parent = controller
                animator = made
            end
            oldHumanoid:Destroy()
        end
        for _, descendant: Instance in ipairs(puppet:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local part: BasePart = descendant :: BasePart
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
                part.Massless = true
                if part.Name == "HumanoidRootPart" then
                    part.Anchored = true
                end
                table.insert(runtime.puppetParts, part)
            end
        end

        -- Anti-fling armour. The double carries no Humanoid (an
        -- AnimationController drives it instead), so the engine cannot
        -- apply the second-humanoid forces that launch characters. On top
        -- of that, every part is moved into a collision group that never
        -- collides with any registered group - even a game that forces
        -- CanCollide back on cannot make the double touch anything.
        pcall(function(): ()
            local physics: PhysicsService = game:GetService("PhysicsService")
            local groupName: string = "WurstDisguise"
            if not physics:IsCollisionGroupRegistered(groupName) then
                physics:RegisterCollisionGroup(groupName)
            end
            for _, group: any in ipairs(physics:GetRegisteredCollisionGroups()) do
                physics:CollisionGroupSetCollidable(
                    groupName,
                    tostring(group.name),
                    false
                )
            end
            for _, part: BasePart in ipairs(runtime.puppetParts) do
                part.CollisionGroup = groupName
            end
        end)

        puppet:PivotTo((character :: Model):GetPivot())
        puppet.Parent = currentWorkspace

        if not animator then
            disguise:Notify("the disguise rig has no animator")
        end
        if animator then
            local source: HumanoidDescription =
                (not disguise.Options["Take animations"].Value and runtime.originals
                    and runtime.originals.myDescription)
                or description
            for _, definition: any in ipairs(PUPPET_ANIMATIONS) do
                local animationId: number = tonumber((source :: any)[definition.field]) or 0
                if animationId > 0 then
                    local animation: Animation = Instance.new("Animation")
                    animation.Name = "WurstDisguise" .. definition.key
                    animation.AnimationId = "rbxassetid://" .. tostring(animationId)
                    animation.Parent = puppet
                    local loaded: boolean, track: any = pcall(function(): any
                        return (animator :: Animator):LoadAnimation(animation)
                    end)
                    if loaded and typeof(track) == "Instance" then
                        (track :: AnimationTrack).Priority = definition.priority
                        runtime.puppetTracks[definition.key] = track :: AnimationTrack
                    else
                        animation:Destroy()
                    end
                end
            end
        end

        runtime.puppet = puppet
        spoofAvatar.setRig(puppet)
        runtime.applied = true
    end

    local function publishEmotes(target: any): ()
        if not disguise.Options["Take emotes"].Value then
            spoofAvatar.setEmotes({})
            return
        end
        local collected: {any} = {}
        local ok: boolean, emotes: any = pcall(function(): any
            return (target.description :: HumanoidDescription):GetEmotes()
        end)
        if ok and type(emotes) == "table" then
            for name: string, ids: any in pairs(emotes) do
                if type(ids) == "table" and type(ids[1]) == "number" then
                    table.insert(collected, {name = name, id = ids[1]})
                end
            end
        end
        table.sort(collected, function(left: any, right: any): boolean
            return left.name < right.name
        end)
        spoofAvatar.setEmotes(collected)
    end

    local function applyToCharacter(target: any): ()
        local character: Model? = currentCharacter()
        local humanoid: Humanoid? = character
            and (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not character or not humanoid then
            publishEmotes(target)
            return
        end
        rememberOriginals(humanoid :: Humanoid)

        if disguise.Options["Hide my real body"].Value then
            hideCharacter(character :: Model)
        else
            showCharacter()
        end
        buildPuppet(target)
        spoofAvatar.setDescription(target.description)

        -- Name above your head, for your eyes only.
        if disguise.Options["Take name"].Value then
            pcall(function(): ()
                (humanoid :: Humanoid).DisplayName = target.name
            end)
        elseif runtime.originals then
            pcall(function(): ()
                (humanoid :: Humanoid).DisplayName = runtime.originals.displayName
            end)
        end

        -- Chat messages: show the disguise's name on your own messages.
        if disguise.Options["Show name in chat"].Value then
            installChatSpoof(target.name)
        else
            removeChatSpoof()
        end

        -- Emote wheel: swap the character's HumanoidDescription emotes.
        if disguise.Options["Take emotes"].Value then
            local wheel: HumanoidDescription? = characterDescription(humanoid :: Humanoid)
            if wheel then
                local emotesOk: boolean, emotes: any = pcall(function(): any
                    return (target.description :: HumanoidDescription):GetEmotes()
                end)
                local equippedOk: boolean, equipped: any = pcall(function(): any
                    return (target.description :: HumanoidDescription):GetEquippedEmotes()
                end)
                if emotesOk and type(emotes) == "table" then
                    local names: {string} = {}
                    if equippedOk and type(equipped) == "table" then
                        for _, entry: any in ipairs(equipped) do
                            local name: string = tostring(
                                type(entry) == "table"
                                    and (entry.name or entry.Name)
                                    or entry
                            )
                            if name ~= "" and name ~= "nil" then
                                table.insert(names, name)
                            end
                        end
                    end
                    pcall(function(): ()
                        (wheel :: HumanoidDescription):SetEmotes(emotes)
                        if #names > 0 then
                            (wheel :: HumanoidDescription):SetEquippedEmotes(names)
                        end
                    end)
                end
            end
        elseif runtime.originals then
            local wheel: HumanoidDescription? = characterDescription(humanoid :: Humanoid)
            if wheel then
                pcall(function(): ()
                    (wheel :: HumanoidDescription):SetEmotes(runtime.originals.emotes)
                    if #runtime.originals.equippedNames > 0 then
                        (wheel :: HumanoidDescription):SetEquippedEmotes(
                            runtime.originals.equippedNames
                        )
                    end
                end)
            end
        end

        publishEmotes(target)
        disguise:SetStatus(target.name .. " · " .. tostring(target.userId))
    end

    local function restoreEverything(): ()
        teardownPuppet()
        showCharacter()
        restoreOriginals()
        removeChatSpoof()
        spoofAvatar.setDescription(nil)
        spoofAvatar.setEmotes({})
        runtime.applied = false
        disguise:SetStatus(nil)
    end

    local function onCharacterAdded(): ()
        -- The previous body and its double are gone; start the new one clean.
        teardownPuppet()
        hidingConnection = nil
        runtime.diedWatch = nil
        if not disguise.Enabled or not runtime.target then
            return
        end
        if runtime.applied and not disguise.Options["Keep on respawn"].Value then
            return
        end
        local target: any = runtime.target
        task.spawn(function(): ()
            task.wait(0.5)
            if disguise.Enabled and runtime.target == target then
                applyToCharacter(target)
            end
        end)
    end

    disguise = framework.Categories.Utility:CreateModule({
        Name = "Disguise",
        Category = "Fun",
        Order = 1,
        ConfigKey = "Universal.Disguise",
        Tooltip = "Wear another user's avatar locally: a body double mirrors "
            .. "you with their look, name above your head, chat name and "
            .. "emote wheel. Only your screen shows it.",
        Function = function(enabled: boolean): ()
            if not enabled then
                restoreEverything()
                return
            end
            disguise:Event(localPlayer.CharacterAdded, onCharacterAdded)
            disguise:Render(function(): ()
                local puppet: Model? = runtime.puppet
                local character: Model? = currentCharacter()
                if not puppet or not character then
                    return
                end
                local humanoid: Humanoid? =
                    (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
                local root: BasePart? =
                    (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
                    or (character :: Model).PrimaryPart
                if not humanoid or not root then
                    return
                end

                -- Reveal the real ragdoll the moment the body dies.
                local watch: RBXScriptConnection? = runtime.diedWatch
                if not watch or not watch.Connected then
                    runtime.diedWatch = (humanoid :: Humanoid).Died:Once(function(): ()
                        teardownPuppet()
                        showCharacter()
                    end)
                end

                local pivot: CFrame = (character :: Model):GetPivot()
                local resolvedPuppet: Model = puppet :: Model
                resolvedPuppet:PivotTo(pivot)

                -- Do not block the view when the camera dives into the double.
                local camera: Camera? = currentWorkspace.CurrentCamera
                if camera then
                    local distance: number =
                        ((camera :: Camera).CFrame.Position - pivot.Position).Magnitude
                    setPuppetHidden(distance < 3)
                end

                -- Copy the real body's motion state onto the double.
                local resolvedHumanoid: Humanoid = humanoid :: Humanoid
                local state: Enum.HumanoidStateType = resolvedHumanoid:GetState()
                local velocity: Vector3 = (root :: BasePart).AssemblyLinearVelocity
                local horizontal: number = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
                if state == Enum.HumanoidStateType.Climbing then
                    playPuppetTrack("climb", 0.2)
                elseif state == Enum.HumanoidStateType.Swimming then
                    playPuppetTrack("swim", 0.2)
                elseif state == Enum.HumanoidStateType.Jumping then
                    playPuppetTrack("jump", 0.1)
                elseif state == Enum.HumanoidStateType.Freefall then
                    playPuppetTrack("fall", 0.2)
                elseif horizontal > 0.75 then
                    -- Mirror Roblox's own Animate script: while moving, the
                    -- walk track is the base and plays at speed / 16, while
                    -- the run track fades in on top of it, its weight
                    -- growing as the speed approaches 16.
                    local tracks: any = runtime.puppetTracks
                    local walk: AnimationTrack? = tracks["walk"]
                    local run: AnimationTrack? = tracks["run"]
                    if not walk and not run then
                        playPuppetTrack("idle", 0.2)
                    else
                        for key: string, other: AnimationTrack in pairs(tracks) do
                            if key ~= "walk" and key ~= "run" and other.IsPlaying then
                                pcall(function(): ()
                                    other:Stop(0.2)
                                end)
                            end
                        end
                        local runWeight: number = math.clamp(horizontal / 16, 0, 1)
                        if walk then
                            if not (walk :: AnimationTrack).IsPlaying then
                                (walk :: AnimationTrack):Play(0.2, 1 - runWeight)
                            else
                                pcall(function(): ()
                                    (walk :: AnimationTrack):AdjustWeight(
                                        1 - runWeight,
                                        0.2
                                    )
                                end)
                            end
                            pcall(function(): ()
                                (walk :: AnimationTrack):AdjustSpeed(horizontal / 16)
                            end)
                        end
                        if run then
                            if not (run :: AnimationTrack).IsPlaying then
                                (run :: AnimationTrack):Play(0.2, runWeight)
                            else
                                pcall(function(): ()
                                    (run :: AnimationTrack):AdjustWeight(
                                        runWeight,
                                        0.2
                                    )
                                end)
                            end
                        end
                    end
                else
                    playPuppetTrack("idle", 0.3)
                end
            end)

            if runtime.target then
                -- Module toggled back on: put the last disguise back on.
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
                return
            end
            local remembered: string = trimmed(
                tostring(disguise.Options["User ID or name"].Value or "")
            )
            if remembered ~= "" then
                task.spawn(function(): ()
                    Module.wear(context, disguise, runtime, applyToCharacter)
                end)
                return
            end
            disguise:SetStatus("waiting")
            disguise:Notify("type a user id or name, then press Apply")
        end,
    })

    disguise:CreateTextBox({
        Name = "User ID or name",
        Default = "",
        Tooltip = "Whose avatar to wear. With the module on, pressing enter "
            .. "puts it on immediately.",
        Function = function(value: string): ()
            if not disguise.Enabled or trimmed(value) == "" then
                return
            end
            task.spawn(function(): ()
                Module.wear(context, disguise, runtime, applyToCharacter)
            end)
        end,
    })
    disguise:CreateButton({
        Name = "Apply",
        Tooltip = "Fetch the avatar in the box and wear it now.",
        Function = function(): ()
            if not disguise.Enabled then
                disguise:Notify("switch the module on first")
                return
            end
            task.spawn(function(): ()
                Module.wear(context, disguise, runtime, applyToCharacter)
            end)
        end,
    })
    disguise:CreateToggle({
        Name = "Keep on respawn",
        Default = true,
        Tooltip = "Put the disguise back on every time you respawn.",
    })
    disguise:CreateToggle({
        Name = "Take animations",
        Default = true,
        Tooltip = "Walk, run, idle, jump, fall, climb and swim like their "
            .. "animation package, blending walk and run the way Roblox's "
            .. "own Animate script does. Off keeps your own animation set "
            .. "on the double.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateToggle({
        Name = "Take name",
        Default = true,
        Tooltip = "Show their name above your head instead of yours.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateToggle({
        Name = "Show name in chat",
        Default = true,
        Tooltip = "When you send a chat message, you see the disguise's "
            .. "nickname on it instead of yours.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateToggle({
        Name = "Take emotes",
        Default = true,
        Tooltip = "Fill your emote wheel and the Emote Player list with the "
            .. "emotes they have equipped.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateToggle({
        Name = "Hide my real body",
        Default = true,
        Tooltip = "The disguise is a local body double; this hides the real "
            .. "one on your screen. Tools stay attached to the hidden body.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateButton({
        Name = "Reset to my avatar",
        Tooltip = "Take the disguise off without switching the module off.",
        Function = function(): ()
            runtime.target = nil
            restoreEverything()
            disguise:Notify("back to your own avatar")
        end,
    })
    disguise:CreateNote(
        "Client sided only: the server, other players and the player list "
            .. "still see the real you. Chat and the name above your head "
            .. "show the disguise on your screen only. Emotes played from "
            .. "the Emote Player appear on the double; the wheel plays on "
            .. "the hidden real body."
    )

    activeCleanup = function(): ()
        restoreEverything()
    end
    Module.Initialized = true
    return disguise
end

function Module.wear(
    context: Runtime,
    disguise: any,
    runtime: any,
    applyToCharacter: (any) -> ()
): ()
    if runtime.busy then
        return
    end
    local players: Players = context.host.Players
    local text: string = trimmed(
        tostring(disguise.Options["User ID or name"].Value or "")
    )
    if text == "" then
        disguise:Notify("type a user id or name first")
        return
    end

    runtime.busy = true
    local userId: number = 0
    if looksNumeric(text) then
        userId = tonumber(text) or 0
    else
        local resolved: boolean, id: any = pcall(function(): number
            return players:GetUserIdFromNameAsync(text)
        end)
        if resolved and type(id) == "number" then
            userId = id
        end
    end
    if userId <= 0 then
        runtime.busy = false
        disguise:Notify("no such user")
        return
    end

    local fetched: boolean, description: any = pcall(function(): any
        return players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not fetched or typeof(description) ~= "Instance" then
        runtime.busy = false
        disguise:Notify("could not read that avatar")
        return
    end

    -- Resolve a friendly label: display name when reachable, username else.
    local name: string = tostring(userId)
    local named: boolean, username: any = pcall(function(): string
        return players:GetNameFromUserIdAsync(userId)
    end)
    if named and type(username) == "string" and username ~= "" then
        name = username
    end
    local displayed: boolean, display: any = pcall(function(): string
        local body: string = (game :: any):HttpGet(
            "https://users.roblox.com/v1/users/" .. tostring(userId)
        )
        local decoded: any = game:GetService("HttpService"):JSONDecode(body)
        return tostring(decoded.displayName)
    end)
    if displayed and type(display) == "string" and display ~= "" then
        name = display
    end

    runtime.busy = false
    runtime.target = {
        description = description,
        name = name,
        userId = userId,
    }
    applyToCharacter(runtime.target)
    disguise:Notify("disguised as " .. name .. " - only you can see it")
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/AnimationChanger.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AnimationChanger",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,

    builtinPacks = nil :: any,
}

local activeCleanup: (() -> ())? = nil

local SLOTS: {{field: string, keys: {string}}} = {
    {field = "SwimAnimation", keys = {"swim"}},
    {field = "ClimbAnimation", keys = {"climb"}},
    {field = "RunAnimation", keys = {"run"}},
    {field = "WalkAnimation", keys = {"walk"}},
    {field = "JumpAnimation", keys = {"jump"}},
    {field = "FallAnimation", keys = {"fall"}},
    {field = "MoodAnimation", keys = {"mood"}},
    {field = "IdleAnimation", keys = {"idle"}},
}

local ANIMATE_SLOTS: {[string]: {string}} = {
    IdleAnimation = {"idle"},
    WalkAnimation = {"walk"},
    RunAnimation = {"run"},
    JumpAnimation = {"jump"},
    FallAnimation = {"fall"},
    ClimbAnimation = {"climb"},
    SwimAnimation = {"swim", "swimidle"},
    MoodAnimation = {"mood"},
}

local BUILTIN_PACKS: {{name: string, ids: {[string]: number}}} = {
    {name = "Astronaut", ids = {IdleAnimation = 1090133099, WalkAnimation = 1090131576, RunAnimation = 1090130630, JumpAnimation = 1090132507, FallAnimation = 1090132063, SwimAnimation = 1090133583, ClimbAnimation = 1090134016}},
    {name = "Bubbly", ids = {IdleAnimation = 1018553897, WalkAnimation = 1018549681, RunAnimation = 1018548665, JumpAnimation = 1018553240, FallAnimation = 1018552770, SwimAnimation = 1018554245, ClimbAnimation = 1018554668}},
    {name = "Cartoony", ids = {IdleAnimation = 837011741, WalkAnimation = 837010234, RunAnimation = 837009922, JumpAnimation = 837011171, FallAnimation = 837010685, SwimAnimation = 837012509, ClimbAnimation = 837013990}},
    {name = "Elder", ids = {IdleAnimation = 892268340, WalkAnimation = 892267099, RunAnimation = 892265784, JumpAnimation = 892267917, FallAnimation = 892267521, SwimAnimation = 892268710, ClimbAnimation = 892269341}},
    {name = "Knight", ids = {IdleAnimation = 734327140, WalkAnimation = 734326330, RunAnimation = 734325948, JumpAnimation = 734326930, FallAnimation = 734326679, SwimAnimation = 734327363, ClimbAnimation = 734329002}},
    {name = "Levitation", ids = {IdleAnimation = 619542203, WalkAnimation = 619544080, RunAnimation = 619543231, JumpAnimation = 619542888, FallAnimation = 619541867, SwimAnimation = 619543721, ClimbAnimation = 619541458}},
    {name = "Mage", ids = {IdleAnimation = 754637456, WalkAnimation = 754636298, RunAnimation = 754635032, JumpAnimation = 754637084, FallAnimation = 754636589, SwimAnimation = 754638471, ClimbAnimation = 754639239}},
    {name = "Ninja", ids = {IdleAnimation = 658832408, WalkAnimation = 658831143, RunAnimation = 658830056, JumpAnimation = 658832070, FallAnimation = 658831500, SwimAnimation = 658832807, ClimbAnimation = 658833139}},
    {name = "Pirate", ids = {IdleAnimation = 837024662, WalkAnimation = 837023892, RunAnimation = 837023444, JumpAnimation = 837024350, FallAnimation = 837024147, SwimAnimation = 837025054, ClimbAnimation = 837025325}},
    {name = "Robot", ids = {IdleAnimation = 619521748, WalkAnimation = 619522849, RunAnimation = 619522386, JumpAnimation = 619522088, FallAnimation = 619521521, SwimAnimation = 619522642, ClimbAnimation = 619521311}},
    {name = "Stylish", ids = {IdleAnimation = 619511648, WalkAnimation = 619512767, RunAnimation = 619512153, JumpAnimation = 619511974, FallAnimation = 619511417, SwimAnimation = 619512450, ClimbAnimation = 619509955}},
    {name = "Superhero", ids = {IdleAnimation = 619528125, WalkAnimation = 619529601, RunAnimation = 619528716, JumpAnimation = 619528412, FallAnimation = 619527817, SwimAnimation = 619529095, ClimbAnimation = 619527470}},
    {name = "Toy", ids = {IdleAnimation = 973771666, WalkAnimation = 973767371, RunAnimation = 973766674, JumpAnimation = 973770652, FallAnimation = 973768058, SwimAnimation = 973772659, ClimbAnimation = 973773170}},
    {name = "Vampire", ids = {IdleAnimation = 1113742618, WalkAnimation = 1113741192, RunAnimation = 1113740510, JumpAnimation = 1113742359, FallAnimation = 1113742092, SwimAnimation = 1113742944, ClimbAnimation = 1113743239}},
    {name = "Werewolf", ids = {IdleAnimation = 1113752682, WalkAnimation = 1113751657, RunAnimation = 1113750642, JumpAnimation = 1113752285, FallAnimation = 1113751889, SwimAnimation = 1113752975, ClimbAnimation = 1113754738}},
    {name = "Zombie", ids = {IdleAnimation = 619535834, WalkAnimation = 619537468, RunAnimation = 619536621, JumpAnimation = 619536283, FallAnimation = 619535616, SwimAnimation = 619537096, ClimbAnimation = 619535091}},
}
Module.builtinPacks = BUILTIN_PACKS

local function slotForName(name: string): string?
    local lowered: string = string.lower(name)
    for _, slot: {field: string, keys: {string}} in ipairs(SLOTS) do
        for _, key: string in ipairs(slot.keys) do
            if string.find(lowered, key, 1, true) then
                return slot.field
            end
        end
    end
    return nil
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer

    local runtime: any = {
        packs = {} :: {any},
        byLabel = {} :: {[string]: any},
        selected = nil :: string?,
        original = nil :: {[string]: number}?,
        settingSelection = false,
    }

    local SAVED_KEY: string = "Universal.AnimationChanger.SavedIDs"
    local function reloadPacks(): ()
        runtime.packs = {}
        runtime.byLabel = {}
        for _, pack: any in ipairs(BUILTIN_PACKS) do
            local entry: any = {label = pack.name, ids = pack.ids}
            table.insert(runtime.packs, entry)
            runtime.byLabel[entry.label] = entry
        end
        local saved: any = host.configData
            and host.configData.values[SAVED_KEY]
        if type(saved) == "string" and saved ~= "" then
            for idText: string in string.gmatch(saved, "[^,]+") do
                local id: number? = tonumber(idText)
                if id then
                    local entry: any = {
                        label = "Saved " .. tostring(id),
                        id = id,
                    }
                    table.insert(runtime.packs, entry)
                    runtime.byLabel[entry.label] = entry
                end
            end
        end
    end
    reloadPacks()

    local function avatarEditor(): any?
        local ok: boolean, service: any = pcall(function(): any
            return game:GetService("AvatarEditorService")
        end)
        return ok and service or nil
    end

    local function currentHumanoid(): Humanoid?
        local character: Model? = localPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    end

    local function rememberOriginal(): ()
        if runtime.original then
            return
        end
        local humanoid: Humanoid? = currentHumanoid()
        if not humanoid then
            return
        end
        local ok: boolean, description: any = pcall(function(): any
            return (humanoid :: Humanoid):GetAppliedDescription()
        end)
        if not ok or typeof(description) ~= "Instance" then
            return
        end
        local saved: {[string]: number} = {}
        for _, slot: {field: string, keys: {string}} in ipairs(SLOTS) do
            local read: boolean, value: any = pcall(function(): any
                return (description :: any)[slot.field]
            end)
            saved[slot.field] = (read and type(value) == "number") and value or 0
        end
        runtime.original = saved
    end

    local animations: any
    animations = framework.Categories.Utility:CreateModule({
        Name = "Animation Changer",
        Category = "Fun",
        Order = 2,
        ConfigKey = "Universal.AnimationChanger",
        Tooltip = "Wear a Roblox animation pack: idle, walk, run, jump, fall, "
            .. "climb and swim.",
        Function = function(enabled: boolean): ()
            if not enabled then
                animations:SetStatus(nil)
                Module.restore(context, runtime)
                return
            end
            animations:SetStatus(
                runtime.selected and string.sub(runtime.selected, 1, 15) or "custom"
            )
            rememberOriginal()

            animations:Event(localPlayer.CharacterAdded, function(): ()
                task.spawn(function(): ()
                    task.wait(0.4)
                    if animations.Enabled then
                        Module.apply(context, animations, runtime, true)
                    end
                end)
            end)
            task.spawn(function(): ()
                Module.apply(context, animations, runtime, true)
            end)
        end,
    })

    animations:CreateList({
        Name = "Pack",
        Items = function(): {string}
            local labels: {string} = {}
            for _, pack: any in ipairs(runtime.packs) do
                table.insert(labels, pack.label)
            end
            return labels
        end,
        Tooltip = "Animation bundles published by Roblox. UGC is filtered out "
            .. "by the search itself.",
        Function = function(_selected: any, names: {string}): ()
            if runtime.settingSelection then
                return
            end
            local chosen: string? = nil
            for _, name: string in ipairs(names) do
                if name ~= runtime.selected then
                    chosen = name
                    break
                end
            end
            chosen = chosen or names[1]
            runtime.settingSelection = true
            for _, name: string in ipairs(names) do
                if name ~= chosen then
                    pcall(function(): ()
                        animations.Options["Pack"]:Set(name, false)
                    end)
                end
            end
            runtime.settingSelection = false
            runtime.selected = chosen
            if animations.Enabled then
                animations:SetStatus(chosen and string.sub(chosen, 1, 15) or "custom")
            end
        end,
    })
    animations:CreateTextBox({
        Name = "Custom ID",
        Default = "",
        Tooltip = "Optional: a bundle id, worn instead of the pick above "
            .. "when filled in. Useful for a pack the search misses.",
    })
    animations:CreateButton({
        Name = "Apply",
        Tooltip = "Wear the selected pack now.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.apply(context, animations, runtime, false)
            end)
        end,
    })
    animations:CreateButton({
        Name = "Reset",
        Tooltip = "Put the animations the character arrived with back.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.restore(context, runtime)
                animations:Notify("animations restored")
            end)
        end,
    })
    animations:CreateButton({
        Name = "Save ID",
        Tooltip = "Keeps the bundle id from Custom ID in the Pack list, so "
            .. "it survives rejoins and reinjects.",
        Function = function(): ()
            local typed: number? = tonumber(
                tostring(animations.Options["Custom ID"].Value or "")
            )
            if not typed or typed <= 0 then
                animations:Notify("put a bundle id in Custom ID first")
                return
            end
            local store: any = host.configData
            if not store then
                return
            end
            local saved: string = type(store.values[SAVED_KEY]) == "string"
                and store.values[SAVED_KEY]
                or ""
            for idText: string in string.gmatch(saved, "[^,]+") do
                if tonumber(idText) == typed then
                    animations:Notify(tostring(typed) .. " is already saved")
                    return
                end
            end
            store.values[SAVED_KEY] = saved == ""
                and tostring(typed)
                or (saved .. "," .. tostring(typed))
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
            reloadPacks()
            pcall(function(): ()
                animations.Options["Pack"]:Refresh()
            end)
            animations:Notify("saved " .. tostring(typed))
        end,
    })
    animations:CreateNote(
        "R15 only — an R6 character has no animation fields to swap. A game "
            .. "that ships its own animation script overrides both paths."
    )

    activeCleanup = function(): ()
        Module.restore(context, runtime)
        runtime.packs = {}
        runtime.byLabel = {}
        runtime.selected = nil
        runtime.original = nil
    end
    Module.Initialized = true
    return animations
end

function Module.resolveClipId(assetId: number): number?
    local loaded: {Instance} = {}
    local ok: boolean = pcall(function(): ()
        loaded = game:GetObjects("rbxassetid://" .. tostring(assetId))
    end)
    if not ok then
        return nil
    end

    local resolved: number? = nil
    for _, root: Instance in ipairs(loaded) do
        if root:IsA("KeyframeSequence") then
            resolved = assetId
        end
        local candidates: {Instance} = {root}
        for _, descendant: Instance in ipairs(root:GetDescendants()) do
            table.insert(candidates, descendant)
        end
        for _, candidate: Instance in ipairs(candidates) do
            if candidate:IsA("Animation") then
                local id: number? = tonumber(
                    string.match((candidate :: Animation).AnimationId, "%d+")
                )
                if id and id > 0 then
                    resolved = id
                    break
                end
            end
        end
        root:Destroy()
        if resolved then
            break
        end
    end

    for _, root: Instance in ipairs(loaded) do
        pcall(function(): ()
            root:Destroy()
        end)
    end
    return resolved
end

function Module.resolveBundle(bundleId: number): {[string]: number}
    local ids: {[string]: number} = {}
    pcall(function(): ()
        local service: any = game:GetService("AvatarEditorService")
        local details: any = service:GetItemDetails(
            bundleId,
            Enum.AvatarItemType.Bundle
        )
        local items: any = details
            and (details.BundledItems or details.bundledItems or details.Items)
        if type(items) ~= "table" then
            return
        end
        for _, item: any in ipairs(items) do
            local name: string = tostring(item.Name or item.name or "")
            local id: number? = tonumber(item.Id or item.id)
            local slot: string? = slotForName(name)
            if id and slot and not ids[slot] then
                local clipId: number? = Module.resolveClipId(id)
                if clipId then
                    ids[slot] = clipId
                end
            end
        end
    end)
    return ids
end

function Module.patchAnimateScript(
    character: Model,
    ids: {[string]: number}
): boolean
    local animate: Instance? = character:FindFirstChild("Animate")
    if not animate then
        return false
    end
    local touched: boolean = false
    for field: string, assetId: number in pairs(ids) do
        for _, containerName: string in ipairs(ANIMATE_SLOTS[field] or {}) do
            local container: Instance? = (animate :: Instance):FindFirstChild(
                containerName
            )
            if not container then
                continue
            end
            for _, child: Instance in ipairs((container :: Instance):GetChildren()) do
                if child:IsA("Animation") then
                    (child :: Animation).AnimationId =
                        "rbxassetid://" .. tostring(assetId)
                    touched = true
                end
            end
        end
    end
    if not touched then
        return false
    end
    local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
    local animator: Animator? = humanoid
        and humanoid:FindFirstChildOfClass("Animator") :: Animator?
    if animator then
        pcall(function(): ()
            for _, track: AnimationTrack in
                ipairs((animator :: Animator):GetPlayingAnimationTracks())
            do
                track:Stop(0)
            end
        end)
    end

    if animate:IsA("LocalScript") then
        pcall(function(): ()
            local script: LocalScript = animate :: LocalScript
            script.Disabled = true
            task.wait()
            script.Disabled = false
        end)
    end
    return true
end

function Module.apply(
    context: Runtime,
    animations: any,
    runtime: any,
    quiet: boolean
): ()
    local host: any = context.host
    local localPlayer: Player = host.LocalPlayer
    local character: Model? = localPlayer.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not character or not humanoid then
        if not quiet then
            animations:Notify("no character yet")
        end
        return
    end

    local typed: number? = tonumber(animations.Options["Custom ID"].Value)
    local pack: any = runtime.selected and runtime.byLabel[runtime.selected]
    local wearing: string = ""
    local descriptionIds: {[string]: number} = {}
    if typed and typed > 0 then
        descriptionIds = Module.resolveBundle(typed)
        wearing = "bundle " .. tostring(typed)
    elseif pack and pack.ids then
        descriptionIds = pack.ids
        wearing = tostring(pack.label)
    elseif pack and pack.id then
        descriptionIds = Module.resolveBundle(pack.id)
        wearing = tostring(pack.label)
    else
        if not quiet then
            animations:Notify("pick a pack first")
        end
        return
    end
    if next(descriptionIds) == nil then
        if not quiet then
            animations:Notify("that bundle has no animations")
        end
        return
    end

    local applied: boolean = false
    local ok: boolean, description: any = pcall(function(): any
        return (humanoid :: Humanoid):GetAppliedDescription()
    end)
    if ok and typeof(description) == "Instance" then
        for field: string, assetId: number in pairs(descriptionIds) do
            pcall(function(): ()
                (description :: any)[field] = assetId
            end)
        end
        applied = pcall(function(): ()
            (humanoid :: Humanoid):ApplyDescription(
                description :: HumanoidDescription
            )
        end)
    end

    local animateIds: {[string]: number} = {}
    for field: string, assetId: number in pairs(descriptionIds) do
        local clip: number? = nil
        pcall(function(): ()
            clip = Module.resolveClipId(assetId)
        end)
        animateIds[field] = clip or assetId
    end
    applied = Module.patchAnimateScript(character :: Model, animateIds) or applied

    if not quiet then
        animations:Notify(
            applied
                and ("wearing " .. wearing)
                or "nothing accepted the swap"
        )
    end
end

function Module.restore(context: Runtime, runtime: any): ()
    local saved: {[string]: number}? = runtime.original
    if not saved then
        return
    end
    local host: any = context.host
    local localPlayer: Player = host.LocalPlayer
    local character: Model? = localPlayer.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not character or not humanoid then
        return
    end
    local ok: boolean, description: any = pcall(function(): any
        return (humanoid :: Humanoid):GetAppliedDescription()
    end)
    if ok and typeof(description) == "Instance" then
        for field: string, assetId: number in pairs(saved :: {[string]: number}) do
            pcall(function(): ()
                (description :: any)[field] = assetId
            end)
        end
        pcall(function(): ()
            (humanoid :: Humanoid):ApplyDescription(
                description :: HumanoidDescription
            )
        end)
    end
    Module.patchAnimateScript(character :: Model, saved :: {[string]: number})
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
        ["src/games/universal/Utility/EmotePlayer.lua"] = [[export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "EmotePlayer",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Emotes play through the character's (or the Disguise double's) own
-- Animator; this priority sits above the movement animations games force
-- onto characters, so idle/walk tracks do not stomp the emote.
local EMOTE_PRIORITY: Enum.AnimationPriority = Enum.AnimationPriority.Action2

-- How long to wait for the animation data to arrive before giving up.
local LOAD_TIMEOUT: number = 5

local function trimmed(text: string): string
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- A catalog emote's page id is usually NOT the id of the animation behind
-- it: pasting the shop id into an Animation fails to load. InsertService can
-- pull the marketplace asset locally, and the Animation instance inside it
-- carries the real animation id.
local function resolveCatalogEmoteId(assetId: number): number?
    local loaded: boolean, model: any = pcall(function(): any
        return game:GetService("InsertService"):LoadAsset(assetId)
    end)
    if not loaded or typeof(model) ~= "Instance" then
        return nil
    end
    local found: number? = nil
    pcall(function(): ()
        local candidates: {Instance} = {model :: Instance}
        for _, descendant: Instance in ipairs((model :: Instance):GetDescendants()) do
            table.insert(candidates, descendant)
        end
        for _, instance: Instance in ipairs(candidates) do
            if instance:IsA("Animation") then
                local id: number = tonumber(
                    string.match((instance :: Animation).AnimationId or "", "%d+")
                ) or 0
                if id > 0 then
                    found = id
                    break
                end
            end
        end
    end)
    pcall(function(): ()
        (model :: Instance):Destroy()
    end)
    return found
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local spoofAvatar: any = context.services.spoofAvatar

    local runtime: any = {
        current = nil :: any?,
        catalog = {} :: {any},
        byLabel = {} :: {[string]: number},
        searching = false,
        settingSelection = false,
        selected = nil :: string?,
    }

    -- While Disguise is wearing a body double, the real body is invisible:
    -- emotes must play on the double to be seen at all. The double runs on
    -- an AnimationController (no Humanoid), so search the whole rig.
    local function puppetAnimator(): Animator?
        local rig: Model? = spoofAvatar.getRig and spoofAvatar.getRig() or nil
        if not rig then
            return nil
        end
        local existing: Animator? =
            (rig :: Model):FindFirstChildWhichIsA("Animator", true) :: Animator?
        if existing then
            return existing
        end
        local controller: AnimationController? =
            (rig :: Model):FindFirstChildOfClass("AnimationController") :: AnimationController?
        if not controller then
            return nil
        end
        local created: boolean, made: any = pcall(function(): any
            local instance: Animator = Instance.new("Animator")
            instance.Parent = controller
            return instance
        end)
        return created and made or nil
    end

    local function animator(): Animator?
        local preferred: Animator? = puppetAnimator()
        if preferred then
            return preferred
        end
        local character: Model? = localPlayer.Character
        if not character or not (character :: Model).Parent then
            return nil
        end
        local humanoid: Humanoid? =
            (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
        if humanoid then
            local existing: Animator? =
                (humanoid :: Humanoid):FindFirstChildOfClass("Animator") :: Animator?
            if existing then
                return existing
            end
        end
        -- Some games parent the Animator elsewhere (the root part, say).
        local anywhere: Animator? =
            (character :: Model):FindFirstChildWhichIsA("Animator", true) :: Animator?
        if anywhere then
            return anywhere
        end
        local created: boolean, made: any = pcall(function(): any
            if not humanoid then
                return nil
            end
            local instance: Animator = Instance.new("Animator")
            instance.Parent = humanoid
            return instance
        end)
        return created and made or nil
    end

    local SAVED_KEY: string = "Universal.EmotePlayer.SavedIDs"
    local function labels(): {string}
        local rows: {string} = {}
        runtime.byLabel = {}
        for _, emote: any in ipairs(spoofAvatar.getEmotes()) do
            if type(emote) == "table" and type(emote.id) == "number" then
                local label: string = tostring(emote.name) .. "  ·  avatar"
                runtime.byLabel[label] = emote.id
                table.insert(rows, label)
            end
        end
        for _, item: any in ipairs(runtime.catalog) do
            runtime.byLabel[item.label] = item.id
            table.insert(rows, item.label)
        end
        local saved: any = host.configData
            and host.configData.values[SAVED_KEY]
        if type(saved) == "string" and saved ~= "" then
            for idText: string in string.gmatch(saved, "[^,]+") do
                local id: number? = tonumber(idText)
                if id then
                    local label: string = "Saved " .. tostring(id)
                    runtime.byLabel[label] = id
                    table.insert(rows, label)
                end
            end
        end
        return rows
    end

    local function stop(): ()
        local current: any? = runtime.current
        runtime.current = nil
        if not current then
            return
        end
        pcall(function(): ()
            (current :: any).track:Stop(0.15)
        end)
        pcall(function(): ()
            (current :: any).track:Destroy()
        end)
        pcall(function(): ()
            (current :: any).animation:Destroy()
        end)
    end

    local emotes: any
    emotes = framework.Categories.Utility:CreateModule({
        Name = "Emote Player",
        Category = "Fun",
        Order = 3,
        ConfigKey = "Universal.EmotePlayer",
        Tooltip = "Play any emote by id - Roblox's own or UGC - with live "
            .. "speed and loop control.",
        Function = function(enabled: boolean): ()
            if not enabled then
                emotes:SetStatus(nil)
                stop()
                return
            end
            emotes:SetStatus(
                runtime.selected and string.sub(runtime.selected, 1, 15) or "custom"
            )
            emotes:Event(localPlayer.CharacterAdded, function(): ()
                stop()
            end)
            emotes:Clean(stop)
        end,
    })

    emotes:CreateList({
        Name = "Emote",
        Items = labels,
        EmptyText = "nothing yet - search or wear a disguise",
        Tooltip = "Pick what to play: emotes from the avatar you are "
            .. "wearing, plus whatever the last search returned.",
        Function = function(_selected: any, names: {string}): ()
            if runtime.settingSelection then
                return
            end
            local chosen: string? = nil
            for _, name: string in ipairs(names) do
                if name ~= runtime.selected then
                    chosen = name
                    break
                end
            end
            chosen = chosen or names[1]
            runtime.settingSelection = true
            for _, name: string in ipairs(names) do
                if name ~= chosen then
                    pcall(function(): ()
                        emotes.Options["Emote"]:Set(name, false)
                    end)
                end
            end
            runtime.settingSelection = false
            runtime.selected = chosen
            if emotes.Enabled then
                emotes:SetStatus(chosen and string.sub(chosen, 1, 15) or "custom")
            end
        end,
    })
    emotes:CreateTextBox({
        Name = "Custom ID",
        Default = "",
        Tooltip = "Optional: overrides the pick above when filled in. Any "
            .. "emote id, Roblox or UGC - catalog page ids work too.",
    })
    emotes:CreateButton({
        Name = "Play",
        Tooltip = "Play the picked emote, or the custom id. The id is "
            .. "verified first: it must exist on the marketplace, be an "
            .. "animation or emote asset, and really deliver its animation "
            .. "data - otherwise you get the exact reason it failed.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.play(context, emotes, runtime, animator, stop)
            end)
        end,
    })
    emotes:CreateButton({
        Name = "Stop",
        Tooltip = "Stop whatever is playing.",
        Function = function(): ()
            stop()
            if emotes.Enabled then
                emotes:SetStatus(nil)
            end
        end,
    })
    emotes:CreateSlider({
        Name = "Speed",
        Min = 0.1,
        Max = 5,
        Step = 0.05,
        Default = 1,
        Tooltip = "Playback rate. Changes apply to the emote that is "
            .. "playing right now.",
        Function = function(value: number): ()
            local current: any? = runtime.current
            if current then
                pcall(function(): ()
                    (current :: any).track:AdjustSpeed(value)
                end)
            end
        end,
    })
    emotes:CreateToggle({
        Name = "Loop",
        Default = false,
        Tooltip = "Keep the emote running until you stop it. Toggling it "
            .. "mid-emote applies immediately.",
        Function = function(value: boolean): ()
            local current: any? = runtime.current
            if current then
                pcall(function(): ()
                    (current :: any).track.Looped = value
                end)
            end
        end,
    })
    emotes:CreateTextBox({
        Name = "Search",
        Default = "",
        Tooltip = "A name to look for in the catalog.",
    })
    emotes:CreateButton({
        Name = "Find emotes",
        Tooltip = "Search the catalog for the name above; results land in "
            .. "the Emote list.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.search(context, emotes, runtime)
            end)
        end,
    })

    emotes:CreateNote(
        "Ids are verified for real: the marketplace must know the id, it "
            .. "must be an animation or emote asset, and its animation data "
            .. "must actually arrive before anything is announced as "
            .. "playing. Emotes are client sided - only your screen shows "
            .. "them."
    )

    activeCleanup = function(): ()
        stop()
        runtime.catalog = {}
        runtime.byLabel = {}
        runtime.selected = nil
    end
    Module.Initialized = true
    return emotes
end

function Module.search(context: Runtime, emotes: any, runtime: any): ()
    if runtime.searching then
        return
    end
    local keyword: string = trimmed(tostring(emotes.Options["Search"].Value or ""))
    if keyword == "" then
        emotes:Notify("type something to look for")
        return
    end
    runtime.searching = true
    local found: {any} = {}

    local ok: boolean = pcall(function(): ()
        local service: any = game:GetService("AvatarEditorService")
        local params: any = CatalogSearchParams.new()
        params.SearchKeyword = keyword
        pcall(function(): ()
            params.AssetTypes = {Enum.AvatarAssetType.EmoteAnimation}
        end)
        local pages: any = service:SearchCatalog(params)
        for _ = 1, 2 do
            for _, item: any in ipairs(pages:GetCurrentPage()) do
                local id: number? = tonumber(item.Id or item.id)
                local name: string = tostring(item.Name or item.name or "Emote")
                if id then
                    table.insert(found, {
                        id = id,
                        label = name .. "  ·  " .. tostring(id),
                    })
                end
            end
            if pages.IsFinished then
                break
            end
            pages:AdvanceToNextPageAsync()
        end
    end)

    runtime.searching = false
    if not ok then
        emotes:Notify("the catalog refused the search")
        return
    end
    runtime.catalog = found
    pcall(function(): ()
        emotes.Options["Emote"]:Refresh()
    end)
    emotes:Notify(tostring(#found) .. " emotes found")
end

function Module.play(
    context: Runtime,
    emotes: any,
    runtime: any,
    animator: () -> Animator?,
    stop: () -> ()
): ()
    local typed: number? = tonumber(
        trimmed(tostring(emotes.Options["Custom ID"].Value or ""))
    )
    local assetId: number = typed or 0
    if assetId <= 0 and runtime.selected then
        assetId = runtime.byLabel[runtime.selected] or 0
    end
    if assetId <= 0 then
        emotes:Notify("pick an emote or fill in Custom ID")
        return
    end
    -- Asset ids are integers; anything else (67676757576767676867, text,
    -- decimals) is rejected before a single request is made.
    if assetId ~= math.floor(assetId) or assetId > 2 ^ 53 then
        emotes:Notify(tostring(assetId) .. " is not a valid asset id")
        return
    end

    local target: Animator? = animator()
    if not target then
        emotes:Notify("no character to animate")
        return
    end

    -- Communication point #1: ask the marketplace what this id actually
    -- is. This is what turns a blind "Playing Emote" into a real answer -
    -- an id that does not exist, or that is a shirt instead of an
    -- animation, is rejected with its exact reason.
    local ok: boolean, info: any = pcall(function(): any
        return game:GetService("MarketplaceService"):GetProductInfo(
            assetId,
            Enum.InfoType.Asset
        )
    end)
    if not ok or type(info) ~= "table" then
        emotes:Notify(
            "id " .. tostring(assetId) .. " does not exist on the marketplace"
        )
        return
    end
    local typeId: number = tonumber(info.AssetTypeId) or -1
    if
        typeId ~= Enum.AssetType.Animation.Value
        and typeId ~= Enum.AssetType.EmoteAnimation.Value
    then
        local typeName: string = "different asset"
        for _, item: EnumItem in ipairs(Enum.AssetType:GetEnumItems()) do
            if item.Value == typeId then
                typeName = item.Name
                break
            end
        end
        emotes:Notify(
            "id " .. tostring(assetId) .. " is a " .. typeName .. ", not an emote"
        )
        return
    end
    local label: string = tostring(info.Name or assetId)

    local animationId: number = assetId
    if typeId == Enum.AssetType.EmoteAnimation.Value then
        -- A catalog emote's page id is not the animation id behind it:
        -- unpack the real animation from the marketplace item.
        emotes:SetStatus("resolving")
        local resolved: number? = resolveCatalogEmoteId(assetId)
        if not resolved or resolved <= 0 then
            emotes:SetStatus(nil)
            emotes:Notify("could not unpack the emote " .. label .. " locally")
            return
        end
        animationId = resolved
    end

    local function attempt(id: number): (Animation?, AnimationTrack?)
        local animation: Animation = Instance.new("Animation")
        animation.Name = "WurstEmote"
        animation.AnimationId = "rbxassetid://" .. tostring(id)
        -- Keep it in the data model while it loads; destroying (or leaving
        -- limbo) early can silently cancel the fetch.
        animation.Parent = (target :: Animator).Parent or (target :: Animator)
        local loaded: boolean, track: any = pcall(function(): any
            return (target :: Animator):LoadAnimation(animation)
        end)
        if loaded and typeof(track) == "Instance" then
            return animation, track
        end
        animation:Destroy()
        return nil, nil
    end

    local function start(animation: Animation, track: AnimationTrack): any
        stop()
        local playing: any = {track = track, animation = animation}
        runtime.current = playing
        track.Priority = EMOTE_PRIORITY
        track.Looped = emotes.Options["Loop"].Value == true
        pcall(function(): ()
            track:Play(0.1)
            track:AdjustSpeed(emotes.Options["Speed"].Value)
        end)
        track.Stopped:Once(function(): ()
            if runtime.current == playing then
                runtime.current = nil
            end
            pcall(function(): ()
                track:Destroy()
            end)
            pcall(function(): ()
                animation:Destroy()
            end)
        end)
        return playing
    end

    emotes:SetStatus("loading")
    local animation: Animation?, track: AnimationTrack? = attempt(animationId)
    if not track or not animation then
        emotes:SetStatus(nil)
        emotes:Notify("the rig refused to load id " .. tostring(animationId))
        return
    end

    -- Communication point #2: the official loaded check. A track only has
    -- a Length once its animation data has arrived (IsLoaded is not a real
    -- AnimationTrack member); no data in time means the id is genuinely
    -- broken - deleted, private, or not playable here - and it is reported
    -- as a failure instead of a fake success.
    local playing: any = start(animation :: Animation, track :: AnimationTrack)
    local deadline: number = os.clock() + LOAD_TIMEOUT
    while
        runtime.current == playing
        and (playing.track :: AnimationTrack).Length <= 0
        and os.clock() < deadline
    do
        task.wait(0.1)
    end
    if runtime.current ~= playing then
        -- Stopped or replaced while loading; nothing to report.
        return
    end
    if (playing.track :: AnimationTrack).Length <= 0 then
        stop()
        emotes:Notify(
            "id "
                .. tostring(animationId)
                .. " never delivered its animation data"
        )
        return
    end
    emotes:Notify("playing " .. label .. " - only your screen shows it")
    emotes:SetStatus(string.sub(label, 1, 15))
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
]],
    },
}
