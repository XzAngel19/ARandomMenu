--!strict
--
-- The screen furniture: everything Wurst draws on the HUD that is neither a
-- window nor a row. Today that is the wordmark — Wurst's own logo with the
-- version next to it, top-left, on the white chip Wurst gives it — the
-- stats block under it (FPS, ping, session time, place), the HackList:
-- every enabled module down the right edge, with whatever bracketed status
-- it publishes through card:SetStatus — and the pill: the floating rounded
-- toolbar lifted from Roblox's own in-game top bar, which is the launcher
-- and the one piece of chrome that stays when the ClickGUI closes.
--
-- All of it lives on the same layer as the windows so the one UIScale the
-- ClickGUI installs moves the whole interface together, and all of it stays
-- on screen while the ClickGUI is closed: in Wurst these are HUD elements
-- (WurstLogo's Visibility default is Always), not chrome that belongs to the
-- GUI screen. The only thing a player should lose by closing the menu is the
-- windows.

local Module = {
    Name = "Furniture",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Wurst's own defaults for the logo chip: WurstLogo.Background #FFFFFF,
-- WurstLogo.Text #000000. Deliberately not theme tokens — the chip is white
-- in every Wurst screenshot regardless of palette, which is what makes the
-- sausage readable on any background.
local WURSTLOGO_BACKGROUND: Color3 = Color3.fromRGB(255, 255, 255)
local WURSTLOGO_TEXT: Color3 = Color3.fromRGB(0, 0, 0)

-- The prototype's #brand block: 14 px from the left edge, 10 from the top,
-- stats 8 px under the wordmark.
local FURNITURE_MARGIN_X: number = 14
local FURNITURE_MARGIN_Y: number = 10
local STATS_GAP: number = 8

-- wurst_128.png is 505×128; at the chip's 22 px it renders 87 px wide.
local LOGO_HEIGHT: number = 22
local LOGO_WIDTH: number = 87

local STATS_FONT_SIZE: number = 11
local STATS_LINE_HEIGHT: number = 17

-- Wurst's HackList defaults (docs/wurst-features.md). Everything here is a
-- live setting once the HackList settings window has been opened; these are
-- the values a fresh install shows, and they are Wurst's own — including
-- Position = Left, under the logo, exactly where Wurst hangs the list.
local HACKLIST_MODE: string = "Auto"
local HACKLIST_POSITION: string = "Left"
local HACKLIST_COLOR: Color3 = Color3.fromRGB(255, 255, 255)
local HACKLIST_SORT_BY: string = "Name"
local HACKLIST_REVERSE: boolean = false
local HACKLIST_ANIMATIONS: boolean = true
local HACKLIST_FONT_SIZE: number = 13
local HACKLIST_LINE_HEIGHT: number = 18
local HACKLIST_TOP: number = 56
local HACKLIST_SLIDE: number = 14

-- Wurst's WurstLogo defaults: a white chip with black text, visible always.
local WURSTLOGO_VISIBILITY: string = "Always"

-- The pill's proportions come from the prototype's #pill rule: 32 px round
-- buttons in a capsule with 5×7 padding, floating 12 px under the top edge.
local PILL_BUTTON: number = 32
local PILL_PADDING_X: number = 7
local PILL_PADDING_Y: number = 5
local PILL_GAP: number = 2
local PILL_TOP: number = 12
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
    local Stats: any = host.Stats
    local TITLE_FONT: any = host.TITLE_FONT
    local CONTROL_FONT: any = host.CONTROL_FONT
    local TweenService: any = host.TweenService
    local allFeatures: {any} = host.allFeatures
    local configData: any = host.configData
    local queueConfigSave: any = host.queueConfigSave
    local refreshFeatureToggle: any = host.refreshFeatureToggle
    local notify: any = host.notify
    local UserInputService: any = host.UserInputService
    local colorFromConfig: any = host.colorFromConfig

    local Furniture: any = {
        handles = {} :: {any},
        connections = {} :: {RBXScriptConnection},
    }

    -- ------------------------------------------------------------- wordmark
    -- Wurst's WurstLogo feature: the sausage and the version on a white chip.
    -- Until the image resolves (or on an executor without getcustomasset) the
    -- chip carries the product name as text, so the corner is never blank.
    local chip: Frame = (create("Frame", {
        Parent = PopupLayer,
        Name = "WurstLogo",
        Active = false,
        BackgroundColor3 = WURSTLOGO_BACKGROUND,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(FURNITURE_MARGIN_X, FURNITURE_MARGIN_Y),
        Size = UDim2.fromOffset(LOGO_WIDTH + 46, LOGO_HEIGHT + 8),
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
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21,
    }) :: any) :: TextLabel

    local versionLabel: TextLabel = (create("TextLabel", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = chip,
        Name = "Version",
        BackgroundTransparency = 1,
        FontFace = TITLE_FONT,
        Position = UDim2.fromOffset(LOGO_WIDTH + 8, 4),
        Size = UDim2.fromOffset(34, LOGO_HEIGHT),
        Text = "v" .. tostring(PRODUCT.version),
        TextColor3 = WURSTLOGO_TEXT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21,
    }) :: any) :: TextLabel

    if type(state.applyAssetImage) == "function" then
        state.applyAssetImage("wurstLogo", logoImage, function(): ()
            logoImage.Visible = true
            logoFallback.Visible = false
        end)
    end

    -- Wurst's WurstLogo settings, read from the store at boot and edited
    -- live by the WurstLogo settings window.
    local function setLogoBackground(color: Color3): ()
        chip.BackgroundColor3 = color
    end
    local function setLogoTextColor(color: Color3): ()
        versionLabel.TextColor3 = color
        logoFallback.TextColor3 = color
    end
    local function setLogoVisibility(value: string): ()
        -- We ship no updater, so "Only when outdated" can never fire; it
        -- hides the chip rather than pretending to know about versions.
        chip.Visible = value == "Always"
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

    -- ---------------------------------------------------------- stats block
    -- Small, monospace, and rebuilt twice a second — cheap enough that the
    -- values can read the live theme instead of binding each fragment.
    local statsLabel: TextLabel = (create("TextLabel", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = PopupLayer,
        Name = "StatsBlock",
        Active = false,
        BackgroundTransparency = 1,
        FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
        Position = UDim2.fromOffset(
            FURNITURE_MARGIN_X,
            FURNITURE_MARGIN_Y + LOGO_HEIGHT + 8 + STATS_GAP
        ),
        RichText = true,
        Size = UDim2.fromOffset(220, STATS_LINE_HEIGHT * 4),
        Text = "",
        TextColor3 = Theme.text,
        TextSize = STATS_FONT_SIZE,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 20,
    }) :: any) :: TextLabel
    ThemeEngine.Bind(statsLabel, "TextColor3", "text")

    local function colorHex(color: Color3): string
        return string.format(
            "#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5)
        )
    end

    local function escapeRich(text: string): string
        return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end

    local sessionStartedAt: number = os.clock()
    local frameCount: number = 0
    local statsElapsed: number = 0

    local function pingMilliseconds(): number?
        local ok: boolean, value: any = pcall(function(): number
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and type(value) == "number" then
            return math.floor(value + 0.5)
        end
        return nil
    end

    local function renderStats(framesPerSecond: number): ()
        local accent: string = colorHex(Theme.accent)
        local function line(label: string, value: string): string
            return label
                .. ' <font color="'
                .. accent
                .. '"><b>'
                .. value
                .. "</b></font>"
        end
        local ping: number? = pingMilliseconds()
        local rows: {string} = {
            line("FPS  ", tostring(framesPerSecond)),
            line("PING ", ping and tostring(ping) .. "ms" or "—"),
        }
        -- A phone keeps FPS and ping and drops the rest: four lines under a
        -- wordmark is a quarter of a small screen's corner.
        if not state.layout.compact then
            local seconds: number = math.floor(os.clock() - sessionStartedAt)
            table.insert(rows, line(
                "TIME ",
                string.format("%02d:%02d", seconds // 60, seconds % 60)
            ))
            table.insert(rows, line(
                "PLACE",
                escapeRich(tostring(state.activeGameName or "—"))
            ))
        end
        statsLabel.Text = table.concat(rows, "\n")
    end

    table.insert(Furniture.handles, TaskManager:Connect(function(): ()
        frameCount += 1
    end, "render"))

    table.insert(Furniture.handles, TaskManager:Connect(function(
        deltaTime: number
    ): ()
        statsElapsed += deltaTime
        if statsElapsed < 0.5 then
            return
        end
        local framesPerSecond: number =
            math.floor(frameCount / statsElapsed + 0.5)
        frameCount = 0
        statsElapsed = 0
        renderStats(framesPerSecond)
    end))
    renderStats(0)

    -- ------------------------------------------------------------- HackList
    -- Wurst's list of what is on, one line per enabled module, newest state
    -- at most a quarter of a second old. Every card already publishes its
    -- bracketed status through card:SetStatus, so the line is the module's
    -- name plus that bracket — `Speed [CFrame ×2]` — exactly the read the
    -- prototype's #hud gives it. There is no toggle event to subscribe to
    -- (refreshFeatureToggle is a plain function), so the list polls; Wurst's
    -- own Width sort has to be recomputed per tick for the same reason.
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

    -- The live HackList settings, read from the store at boot; the HackList
    -- settings window edits them through the setters published below.
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

    local function hudOnLeft(): boolean
        -- A phone always keeps the list on the left under the stats block,
        -- where a thumb does not cover it (UI-V2, Mobile); a desktop follows
        -- Wurst's Position setting, whose default is Left, under the logo.
        return state.layout.compact or hudPosition == "Left"
    end

    local function placeHudList(): ()
        if hudOnLeft() then
            hudFrame.AnchorPoint = Vector2.new(0, 0)
            local statsLines: number = state.layout.compact and 2 or 4
            hudFrame.Position = UDim2.new(
                0,
                FURNITURE_MARGIN_X,
                0,
                FURNITURE_MARGIN_Y + LOGO_HEIGHT + 8
                    + STATS_GAP
                    + STATS_LINE_HEIGHT * statsLines
                    + STATS_GAP
            )
            hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        else
            hudFrame.AnchorPoint = Vector2.new(1, 0)
            hudFrame.Position = UDim2.new(1, -12, 0, HACKLIST_TOP)
            hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        end
    end
    placeHudList()
    state.onLayout(placeHudList)

    -- One container per entry: the list layout owns the container's slot,
    -- so the label inside it is free to slide the prototype's 14 px without
    -- fighting the layout for its position.
    local hudRows: {[string]: any} = {}

    local function hudAlignment(): Enum.TextXAlignment
        return hudOnLeft()
            and Enum.TextXAlignment.Left
            or Enum.TextXAlignment.Right
    end

    local function composeHudText(name: string, status: string?): string
        local text: string = escapeRich(name)
        if status and status ~= "" then
            text = text
                .. ' <font color="'
                .. colorHex(Theme.textMuted)
                .. '">['
                .. escapeRich(status)
                .. "]</font>"
        end
        return text
    end

    local function animationsOn(): boolean
        return hudAnimations and state.animationsEnabled ~= false
    end

    local function newHudRow(name: string): any
        local container: Frame = (create("Frame", {
            Parent = hudFrame,
            Name = name,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, HACKLIST_LINE_HEIGHT),
            ZIndex = 20,
        }) :: any) :: Frame
        local label: TextLabel = (create("TextLabel", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = container,
            Name = "Entry",
            BackgroundTransparency = 1,
            FontFace = CONTROL_FONT,
            Position = UDim2.fromOffset(0, 0),
            RichText = true,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            TextColor3 = hudColor,
            TextSize = HACKLIST_FONT_SIZE,
            TextXAlignment = hudAlignment(),
            ZIndex = 20,
        }) :: any) :: TextLabel
        if animationsOn() then
            label.Position = UDim2.fromOffset(HACKLIST_SLIDE, 0)
            label.TextTransparency = 1
            TweenService:Create(
                label,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {
                    Position = UDim2.fromOffset(0, 0),
                    TextTransparency = 0,
                }
            ):Play()
        end
        return {container = container, label = label}
    end

    local function dropHudRow(row: any): ()
        if animationsOn() then
            local tween: Tween = TweenService:Create(
                row.label,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {
                    Position = UDim2.fromOffset(HACKLIST_SLIDE, 0),
                    TextTransparency = 1,
                }
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

    local function refreshHudList(): ()
        local entries: {any} = {}
        for _, feature: any in ipairs(allFeatures) do
            if feature.enabled == true and not feature.isCategory then
                table.insert(entries, {
                    name = tostring(feature.name),
                    status = feature.status,
                })
            end
        end

        -- Wurst's two sort axes. Width is the rendered width of the line;
        -- the prototype's #hud sorts by text length for the same effect,
        -- and that is the measure used here — widest first, as Wurst draws.
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

        -- Wurst's Mode: Hidden renders nothing; Count renders the number of
        -- active hacks; Auto renders the whole list only while it fits on
        -- the screen, and falls back to the count when it does not.
        if hudMode == "Hidden" then
            entries = {}
        elseif #entries > 0 then
            local camera: Camera? = workspace.CurrentCamera
            local screenHeight: number = camera
                and (camera :: Camera).ViewportSize.Y
                or 720
            local available: number = screenHeight - HACKLIST_TOP - 12
            local overflows: boolean =
                #entries * (HACKLIST_LINE_HEIGHT + 1) > available
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
            if not row then
                row = newHudRow(entry.name)
                hudRows[entry.name] = row
            end
            row.container.LayoutOrder = order
            row.label.Text = composeHudText(entry.name, entry.status)
            row.label.TextXAlignment = hudAlignment()
        end
        for name: string, row: any in pairs(hudRows) do
            if not wanted[name] then
                hudRows[name] = nil
                dropHudRow(row)
            end
        end
    end

    table.insert(Furniture.handles, TaskManager:Connect(function(
        deltaTime: number
    ): ()
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

    state.hudList = {
        frame = hudFrame,
        refresh = refreshHudList,
        -- The HackList settings window drives these; persistence belongs to
        -- its rows, which write the same keys this file read at boot.
        SetMode = function(value: string): ()
            hudMode = value
            forceHudRefresh()
        end,
        SetPosition = function(value: string): ()
            hudPosition = value
            placeHudList()
            forceHudRefresh()
        end,
        SetColor = function(color: Color3): ()
            hudColor = color
            for _, row: any in pairs(hudRows) do
                row.label.TextColor3 = color
            end
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
        end,
    }

    -- ----------------------------------------------------------------- pill
    -- The five per cent of this menu that is Roblox rather than Wurst: the
    -- floating capsule from the game's own top bar, as the launcher. It is
    -- the only rounded, soft element on screen and the only chrome that is
    -- still there when the ClickGUI is closed — on a phone it is the way
    -- back in, which is why the shell's old circle stands down below.
    --
    -- Two buttons, because two targets exist: the GUI toggle and panic.
    -- Search, configs, keybinds and UI settings join the capsule when their
    -- windows do; a button that only raises a toast would be a control that
    -- lies about having an effect.
    local pillButtons: number = 2
    local pillWidth: number = PILL_PADDING_X * 2
        + PILL_BUTTON * pillButtons
        + PILL_GAP * (pillButtons - 1)
        + 9 -- the 1 px separator and its 4 px margins

    local pillFrame: Frame = (create("Frame", {
        Parent = PopupLayer,
        Name = "Pill",
        Active = true,
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor3 = Color3.fromRGB(16, 18, 28),
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0, PILL_TOP),
        Size = UDim2.fromOffset(pillWidth, PILL_BUTTON + PILL_PADDING_Y * 2),
        ZIndex = 240,
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

    -- The pill keeps the prototype's own dark glass regardless of theme —
    -- it imitates Roblox chrome, not Wurst chrome — so only the *active*
    -- state of a button reads the theme.
    local PILL_IDLE_TEXT: Color3 = Color3.fromRGB(232, 232, 238)

    local function showPillTip(anchor: GuiObject, text: string): ()
        local tooltip: TextLabel? = state.featureTooltip
        if not tooltip then
            return
        end
        state.tooltipToken = state.tooltipToken + 1;
        (tooltip :: TextLabel).Text = text;
        (tooltip :: TextLabel).Size = UDim2.fromOffset(
            math.clamp(#text * 5.5 + 24, 120, 320),
            30
        );
        (tooltip :: TextLabel).Position = UDim2.fromOffset(
            anchor.AbsolutePosition.X,
            anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 8
        );
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
        PILL_PADDING_X,
        "≡",
        16,
        "Show or hide the menu",
        function(): ()
            state.setMenuVisible(not state.visible)
        end
    )

    create("Frame", {
        Parent = pillFrame,
        Name = "PillSeparator",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(
            PILL_PADDING_X + PILL_BUTTON + 4,
            PILL_PADDING_Y + (PILL_BUTTON - 18) // 2
        ),
        Size = UDim2.fromOffset(1, 18),
        ZIndex = 241,
    })

    pillButton(
        2,
        PILL_PADDING_X + PILL_BUTTON + 9 + PILL_GAP,
        "OFF",
        10,
        "Panic: disable every module",
        function(): ()
            local disabled: number = 0
            for _, feature: any in ipairs(allFeatures) do
                if feature.enabled == true then
                    -- One module that throws while switching off must not
                    -- keep the ones after it running; this mirrors the
                    -- shell's own teardown loop.
                    pcall(feature.onToggle, false)
                    feature.enabled = false
                    configData.states[feature.configKey] = false
                    disabled += 1
                    refreshFeatureToggle(feature)
                end
            end
            queueConfigSave()
            refreshHudList()
            notify(
                disabled == 1
                    and "Panic: 1 module disabled"
                    or ("Panic: " .. tostring(disabled) .. " modules disabled")
            )
        end
    )

    -- The menu button fills with the accent while the GUI is open, exactly
    -- like the prototype's `.on` state. Repainted on both the things that
    -- change it: visibility and the theme.
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
    state.addMenuVisibilityListener(function(): ()
        restyleMenuButton()
    end)
    ThemeEngine.OnChange(function(): ()
        restyleMenuButton()
    end)

    -- `root`, not `frame`: every other surface the menu publishes — a managed
    -- window, a drawing set — names its top instance that way, and the suite
    -- that checks the pill stays on screen with the GUI closed was reading
    -- `root` and finding nil.
    state.pill = {
        root = pillFrame,
        restyle = restyleMenuButton,
    }
    -- The shell's fallback circle stands down now that the pill exists.
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
        chip:Destroy()
        statsLabel:Destroy()
        hudFrame:Destroy()
        pillFrame:Destroy()
        state.hudList = nil
        state.wurstLogo = nil
        state.pill = nil
        -- The fallback launcher becomes the way in again.
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
