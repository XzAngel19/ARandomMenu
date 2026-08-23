--!strict
--
-- Widget library.
--
-- Every control a module's panel is made of: the option row itself, the
-- toggle, the action button, the slider, the two-handle range, the cycle, the
-- single- and multi-select lists, the key slot, the text box, the colour
-- swatch and the colour picker behind it.
--
-- These lived in `ARandomMenu.luau` and were the single largest thing in it —
-- close to two thousand lines of interface code sitting in the same function
-- scope as the window, the rail and the loader, which is how that function
-- ended up three locals away from Luau's 200-register ceiling. None of it is
-- shell logic: a widget knows how to draw a control, read and write its stored
-- value and call a module back, and nothing else.
--
-- The shell hands the library its primitives (`create`, `makeButton`, the
-- design tokens, the config store) and gets back the builders, which it then
-- publishes into the environment every downloaded module runs in. That is the
-- only coupling left: a module calls `addToggleOption(...)` exactly as before
-- and cannot tell where the function came from.

export type OptionDefinition = {
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

-- The builders the shell installs into the module environment, by the exact
-- name a module calls them with.
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

-- The prototype's component metrics, verbatim (docs/design/prototype/
-- spec.json, `components`) — which since the Java audit carry Wurst's own
-- geometry at GUI scale 2: an 8 px bitmap line rendered at 16, a 3-logical
-- slider rail at 6, an 8×8 knob at 16×16. The parity gate reads these names
-- and fails a drift, so a number that changes here changes in the prototype
-- first.
local LABEL_FONT_SIZE: number = 16
local SLIDER_BAR_HEIGHT: number = 6
local SLIDER_KNOB_WIDTH: number = 16
local SLIDER_KNOB_HEIGHT: number = 16
-- Wurst's child metrics (spec.wurst.chrome, logical 2 → 4 at scale 2).
local CHILD_INSET: number = 4
local CHILD_GAP: number = 4

function Module.init(context: any): WidgetLibrary
    -- Wurst draws every arrow and checkmark in its own green, regardless of
    -- the player's palette — the reference screenshots show green triangles
    -- on a magenta theme and on a pink one. Not a theme token on purpose.
    -- Inside init because Color3 only exists once the environment is
    -- installed.
    local WURST_GREEN: Color3 = Color3.fromRGB(0, 204, 0)
    local host: any = context
    -- Services come from the shell rather than from `GetService` so the whole
    -- menu watches one input stream: a second UserInputService handle means a
    -- slider drag and the shell's own pointer tracking see different events.
    local UserInputService: any = host.UserInputService
    local state: any = host.state
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local create: any = host.create
    local makeButton: any = host.makeButton
    local makeTextBox: any = host.makeTextBox
    -- The shell's makeTextBox dresses its box with the old menu's
    -- StyleCorner (radius 0 since the port — invisible, but still an
    -- instance the settings grammar does not own). Every box a widget
    -- creates comes through here: corner gone, Wurst keeps rectangles.
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
    -- Popups (the choice lists and the colour picker) live above every panel
    -- on the shell's own overlay layer rather than inside the row that opened
    -- them, so a list cannot be clipped by its scrolling parent.
    local PopupLayer: any = host.PopupLayer
    local trackUiConnection: any = host.trackUiConnection
    local applyKeySlotStyle: any = host.applyKeySlotStyle
    local beginKeyCapture: any = host.beginKeyCapture
    local bindActionShortcut: any = host.bindActionShortcut
    local runActionButton: any = host.runActionButton
    local colorFromConfig: any = host.colorFromConfig
    local colorToConfig: any = host.colorToConfig
    -- Places a control on the right-hand side of an option row.
    --
    -- Rows are no longer all the same height, so the vertical band a control may
    -- occupy is published by `createOptionRow` as attributes rather than being
    -- assumed. Every add*Option goes through this so sliders, cycle buttons, key
    -- slots and text boxes all line up on the exact same edge: every row, in
    -- every module, ends with a control band that starts at 50% of the row width
    -- and finishes 10px from the right edge. That shared geometry is what keeps
    -- panels with keybinds, sliders, toggles or actions visually symmetric.
    --
    -- On `state` rather than in the returned table: the shell reads it too, and
    -- so does every game module that positions a control of its own, so there
    -- is one place the band is defined and one place to change it.
    -- Pixel sprites, the way the bitmap client draws its icons: stacked
    -- 2×2-px "logical pixels", no Unicode — a font glyph moves with the
    -- typeface, a sprite does not. Wurst's arrows, pin, cross and checkmark
    -- are all four-to-nine rectangles.
    --   kind: "down" | "up" | "right" | "cross" | "pin" | "check"
    -- The container is transparent, centred in its parent, and carries the
    -- name "PixelIcon" so a repaint can find it.
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
        -- The canonical control band. 0.5 is the default so every row type shares
        -- the same rectangle; rows that stack several controls (action pairs)
        -- subdivide this same band instead of drawing outside it.
        local scale: number = widthScale or 0.5
        control.AnchorPoint = Vector2.new(1, 0)
        control.Position = UDim2.new(1, -10, 0, top)
        control.Size = UDim2.new(scale, -10, 0, height)
        control.ZIndex = math.max(control.ZIndex, option.ZIndex + 2)
    end

    -- A single customisation row inside a module's panel: a label on the left, a
    -- control on the right, exactly one line tall.
    --
    -- Each row is a self-contained card — its own soft fill, rounded corners, a
    -- hairline border and a hover highlight — so it is obvious where one setting
    -- stops and the next begins in panels with a lot of controls (Fly).
    --
    -- `hintText` is accepted and deliberately ignored. Modules pass an
    -- explanatory sentence for many of their controls ("Balanced glides, Direct
    -- stops instantly…"), which doubled the height of every panel and buried the
    -- control itself. Dropping it here fixes every module at once — Fly, Fling,
    -- Speed, Hitboxes and everything a game module adds — without touching a
    -- single call site, and keeps the argument valid for older game modules
    -- downloaded from the repository.
    local function createOptionRow(
        feature: any,
        labelText: string,
        _hintText: string?
    ): Frame
        feature.optionCount += 1
        feature.searchText ..= " " .. string.lower(labelText)
        local rowHeight: number = state.layout.optionRowHeight
        -- Wurst's setting line: label left, value right, nothing else. The
        -- row it replaced was a card of its own — fill, rounded corners, a
        -- hairline stroke and a hover tween — which read as a second deck of
        -- cards inside every expansion. A line is flat and free.
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

    -- A non-interactive heading used to break a long customisation panel into
    -- labelled groups ("Flight", "Advanced", ...). It behaves like any other
    -- option row for layout and visibility purposes, so `setOptionVisible` can
    -- hide a whole group's heading along with its controls.
    --
    -- On `state` as well as in the returned table, for the same reason as
    -- `layoutOptionControl`.
    -- Wurst's settings windows carry no group headings — the Java lists
    -- rows and nothing else, and DISPLAY / FILTERS / STYLE on screen were
    -- the old menu's taxonomy showing through. The builder stays because
    -- the modules call it (their grouping intent is real and may matter to
    -- a future surface), but what it returns is invisible and zero-height:
    -- it neither draws nor occupies a line.
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
        -- Wurst's checkbox: a small square in front of the label, filled with
        -- the enabled colour when on. The pill switch it replaces was the old
        -- menu's; nothing in Wurst slides.
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
        -- An 11×11-logical square (22 here), as the Java sizes it — no
        -- corner radius on a checkbox.
        local boxStroke: UIStroke = (create("UIStroke", {
            Parent = box,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Color = Theme.outline,
            Thickness = 1,
            Transparency = 0.35,
        }) :: any) :: UIStroke
        -- The checkmark is a pixel sprite in Wurst's own green, the way the
        -- bitmap client draws it — never a font glyph.
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
        -- The action pair subdivides the same control band every other row uses:
        -- RUN hugs the band's right edge and KEY fills the band's left half, so
        -- action rows share the exact same outer rectangle as toggles, sliders,
        -- cycle buttons and key slots.
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
        -- Sits immediately left of the RUN button inside the same band, positioned
        -- with the pair's combined scale rather than off RUN's AbsoluteSize, which
        -- is still zero on the frame the row is built. 0.24 width + 0.26 width
        -- with a 6px gap reproduces the 0.5-wide band of every other row type, so
        -- the pair never breaks the shared left/right edges.
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
        return string.format("%.7g", value)
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
        -- A stored value is clamped into the row's own range on load: a
        -- config written by an older build (Max height 1000) or edited by
        -- hand must not smuggle an out-of-range number past the slider.
        local value: number = isFiniteNumber(storedValue)
            and math.clamp(storedValue :: number, minimum, maximum)
            or defaultValue
        local integerOnly: boolean = defaultValue % 1 == 0
            and minimum % 1 == 0
            and maximum % 1 == 0

        local option: Frame = createOptionRow(feature, labelText, hintText)
        -- Wurst's SliderComponent is 22 logical tall — 44 here: an 11-tall
        -- text line (label left, value right) over an 11-tall rail zone. The
        -- rail is 3 logical (6 px) and the knob 8×8 (16×16); the parity gate
        -- holds these constants to the spec.
        option.Size = UDim2.new(1, 0, 0, 44)
        local headerLabel: TextLabel? =
            option:FindFirstChild("OptionLabel") :: TextLabel?
        if headerLabel then
            (headerLabel :: TextLabel).Size =
                UDim2.new(0.55, -CHILD_INSET, 0, 22)
        end

        local step: number? = tonumber(stepValue)
        if step ~= nil and step <= 0 then
            step = nil
        end
        -- The row's numeric contract, readable by anything that walks it:
        -- the values are metadata whether or not the labels are bitmap.
        option:SetAttribute("Min", minimum)
        option:SetAttribute("Max", maximum)
        option:SetAttribute("Step", step or (integerOnly and 1 or 0))

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

        -- The interval, spelled on the rail line: minimum at the left end,
        -- maximum at the right, the rail between them. The current value
        -- stays editable in the box above; nobody has to drag to an end to
        -- learn what the ends are.
        local minText: string = formatCompactNumber(minimum)
        local maxText: string = formatCompactNumber(maximum)
        -- Measured through the contract when it is up (A2: nobody
        -- multiplies a constant past measure), the 11-px estimate only for
        -- the harness host. TextSize 14 is what the labels render at.
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
        -- Spell out the accepted interval so a reader knows what the slider spans
        -- without having to drag it to both ends first.
        valueInput.PlaceholderText = formatCompactNumber(minimum)
            .. " – "
            .. formatCompactNumber(maximum)

        local editing: boolean = false
        -- Every path — drag, typed text, stored value — lands on the same
        -- rule: snap to the step (or to integers when the row is integer),
        -- then clamp. NaN and inf never reach here; isFiniteNumber refuses
        -- them at the door.
        local function quantize(raw: number): number
            local stepped: number = raw
            if step ~= nil then
                stepped = minimum
                    + math.round((stepped - minimum) / (step :: number))
                        * (step :: number)
            elseif integerOnly then
                stepped = math.round(stepped)
            end
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
            value = quantize(nextValue)
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
    -- Range row: one slider, two handles.
    --
    -- "Minimum CPS" and "Maximum CPS" as two separate sliders is two rows to read,
    -- two rows to drag, and nothing on screen says they are the two ends of one
    -- interval — you can even leave the minimum above the maximum. The reference
    -- interface uses a single track with a handle at each end for exactly these
    -- settings, and so does this: one row, one range, and the value between the
    -- handles is what the module draws from.
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
        local low: number = math.clamp(
            storedLow or tonumber(definition.defaultLow) or minimum,
            minimum,
            maximum
        )
        local high: number = math.clamp(
            storedHigh or tonumber(definition.defaultHigh) or maximum,
            minimum,
            maximum
        )
        if low > high then
            low, high = high, low
        end
        local integerOnly: boolean = definition.integer ~= false

        local option: Frame = createOptionRow(feature, labelText, definition.hint)
        -- Same 22-logical geometry as the single slider: text line over an
        -- 11-tall rail zone, two 8×8 knobs on the 3-logical rail.
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

        -- Only the span between the two handles is filled: the fill *is* the
        -- interval the module rolls inside.
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

        -- Both ends editable, the way the single-value box already is:
        -- low on the left of the dash, high on the right. Enter or focus
        -- loss confirms; junk restores; the pair keeps low <= high.
        local step: number? = tonumber(definition.step)
        if step ~= nil and step <= 0 then
            step = nil
        end
        option:SetAttribute("Min", minimum)
        option:SetAttribute("Max", maximum)
        option:SetAttribute("Step", step or (integerOnly and 1 or 0))
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

        -- Which handle a press grabs is decided once, on the press, and kept for
        -- the whole drag: deciding it per frame makes the handles swap under the
        -- finger as soon as they cross.
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

        -- The typed path shares the drag path's rules: quantise, clamp,
        -- and keep the pair ordered. Invalid text restores the old value.
        local function quantizeTyped(raw: number): number
            if step ~= nil then
                raw = minimum
                    + math.round((raw - minimum) / (step :: number))
                        * (step :: number)
            elseif integerOnly then
                raw = math.round(raw)
            end
            return math.clamp(raw, minimum, maximum)
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

    -- Choice popup.
    --
    -- One list, reused by every multiple-choice row. Clicking the control opens
    -- the options underneath it and the value is picked directly, instead of
    -- clicking the same button four times to get back to the one you wanted.
    state.closeChoiceList = function(): () end

    -- APPLY-4, 7.54.1's closeInvalidPopups: a popup dies with its owner.
    -- Walk up from the row that opened it to the scrolling body and the
    -- window root; any of these invalidates the popup — the window hiding
    -- (close, or the menu closing), collapsing (the body hides), being
    -- destroyed, or the owner row scrolling out of the body's clip. The
    -- returned connections belong to the popup and are disconnected with
    -- it. The harness's mock instances hold AbsolutePosition at zero, so
    -- the scroll test never false-fires there.
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
            -- Collapse hides the body; scrolling can clip the row away.
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
        state.closeChoiceList()

        local rowHeight: number = 24
        -- Fifty typefaces is not a list you scroll through, so anything longer
        -- than a screenful gets a filter field at the top, the way Vape's own
        -- lists do.
        local searchable: boolean = #values > 8
        local searchHeight: number = searchable and 24 or 0
        local visibleRows: number = math.min(#values, 6)
        local listHeight: number = visibleRows * rowHeight + 8 + searchHeight
        local anchorPosition: Vector2 = anchor.AbsolutePosition
        local anchorSize: Vector2 = anchor.AbsoluteSize
        -- Open upwards when there is no room below: a list that runs off the
        -- bottom of the screen cannot be used at all.
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
        -- No corner radius: every Wurst surface is a rectangle, and the
        -- gate holds the line so a restyle cannot drift.
        -- Every entry the list is about to hold draws on the bitmap
        -- contract; the sweep's connection dies with the list.
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
            state.closeChoiceList = function(): () end
        end
        state.closeChoiceList = close
        -- APPLY-4: the list dies when its owner window closes, collapses,
        -- hides, is destroyed, or the owner row scrolls out of the clip.
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
            -- The picked entry carries a slim accent bar on its left edge
            -- — readable at a glance without a glyph.
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
            item.TextXAlignment = Enum.TextXAlignment.Left
            item.MouseEnter:Connect(function(): ()
                if itemIndex ~= currentIndex then
                    item.BackgroundTransparency = 0.6
                    item.TextColor3 = Theme.text
                end
            end)
            item.MouseLeave:Connect(function(): ()
                item.BackgroundTransparency = itemIndex == currentIndex and 0.25 or 1
                item.TextColor3 = itemIndex == currentIndex
                    and Theme.text
                    or Theme.textMuted
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

        -- Any press that is not on the list dismisses it, which is what every
        -- other menu on the platform does.
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

    -- The shell's settings page picks its interface font with the same list a
    -- module's cycle row uses, so the opener is published rather than
    -- duplicated.
    state.openChoiceList = openChoiceList

    state.addMenuVisibilityListener(function(visible: boolean): ()
        if not visible then
            state.closeChoiceList()
        end
    end)

    -- Multi-choice list.
    --
    -- A dropdown answers "which one"; this answers "which of these", which is the
    -- question a game with nine different swords actually asks. Same popup, same
    -- greys, except every row carries the state mark and toggling one leaves the
    -- list open so you can tick several without reopening it.
    state.openMultiList = function(
        anchor: TextButton,
        items: {string},
        selected: {[string]: boolean},
        onToggle: (string, boolean) -> (),
        onBulk: ((boolean) -> ())?
    ): ()
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
            state.closeChoiceList = function(): () end
        end
        state.closeChoiceList = close
        -- APPLY-4: the list dies when its owner window closes, collapses,
        -- hides, is destroyed, or the owner row scrolls out of the clip.
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
            -- The same empty-or-filled square the option rows use.
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
                -- Left open on purpose: ticking four swords should cost four taps,
                -- not four taps and four reopenings.
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

    -- Option row wrapper for the list above: keeps the selection in the config
    -- file and shows how much of it is ticked.
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
                -- Blank, not a caption: an empty chooser that says
                -- "nothing detected" reads like a broken value. The row
                -- label and the tooltip already explain the control.
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
        -- A module that discovers a new entry (Item Render learning an object by
        -- touch) has to be able to add it and tick it without reaching into the
        -- row's internals, so the row hands out its own controls.
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
        -- Wurst's ComboBox: an 11-logical line (22 here), the current value
        -- right-aligned against an 11-wide arrow box holding the pixel-drawn
        -- green triangle from the screenshots. The whole line is the click
        -- target; nothing about it is a modern button.
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
        -- Flag used by the symmetry pass: modules that already expose an explicit
        -- key row are not given the automatic "Toggle key" row.
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

        -- The row's key is taken by the slot's capture and nothing else: click it,
        -- then press the key.
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
        -- Centred: the placeholder and the value sit in the middle of the field
        -- instead of hugging its left edge.
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
            -- The picker's labels and buttons render on the bitmap
            -- contract too; the panel is persistent, so the sweep is.
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

            -- Two ways to type a colour, side by side under the gradients,
            -- because people arrive with one or the other: a hex string copied
            -- from somewhere, or three numbers out of another tool. Both write the
            -- same colour and both update the preview as soon as the field loses
            -- focus.
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
                -- Whatever was typed, the fields are rewritten from the colour
                -- that is actually selected, so a half-typed value never sticks.
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
        -- APPLY-4 for the picker: it hides when its owner row's window
        -- closes, collapses, hides, dies, or the row scrolls out of the
        -- clip. The watch belongs to this opening; the next open replaces
        -- it, and firing disconnects itself.
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

    -- Published so the shell's teardown can drop the two drag connections the
    -- picker keeps alive between openings.
    state.colorPicker = colorPicker

    local function addColorOption(feature, labelText, defaultColor, callback, hintText)
        local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
        local color = colorFromConfig(configData.values[optionKey], defaultColor)
        local option = createOptionRow(feature, labelText, hintText)
        -- Wurst's colour component is 22 logical tall — 44 here: the label
        -- with its hex right-aligned on the text line, and an 11-logical
        -- (22 px) bar of the colour itself filling the lower half.
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
        -- Read at call time, not captured at init: the card factory is a
        -- library of its own and may not have loaded when this one did.
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

-- Nothing to tear down: every connection the builders make goes through the
-- shell's own `trackUiConnection`, which the shell releases with the window.
function Module.destroy(): ()
    Module.Initialized = false
end

return Module
