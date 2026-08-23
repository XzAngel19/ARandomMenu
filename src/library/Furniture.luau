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
-- The Java's own default: #FFFFFF drawn at half alpha as the y=6..17 band —
-- a stripe, not a slab. The ghost-era dark seed that lived here was why the
-- band came out black; schema 2 already swept any stored copy of it.
local WURSTLOGO_BACKGROUND: Color3 = Color3.fromRGB(255, 255, 255)
local WURSTLOGO_TEXT: Color3 = Color3.fromRGB(0, 0, 0)

-- The prototype's #brand block: 14 px from the left edge, 10 from the top.
local FURNITURE_MARGIN_X: number = 14
local FURNITURE_MARGIN_Y: number = 10

-- Wurst draws its logo 72×18 logical; at the GUI scale 2 the interface is
-- drawn at that is 144×36 (wurst_128.png is 505×128, so 142 keeps the exact
-- aspect at 36 tall).
local LOGO_HEIGHT: number = 36
local LOGO_WIDTH: number = 142

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
-- The bitmap line: 16 px glyphs on the contract's 18 px line (8/9 logical).
local HACKLIST_FONT_SIZE: number = 16
local HACKLIST_LINE_HEIGHT: number = 18
local HACKLIST_TOP: number = 56
-- 24 and a quarter second: the old 14 px over 0.15 s was invisible,
-- which read as "Animations does nothing".
local HACKLIST_SLIDE: number = 24

-- Wurst's WurstLogo defaults: a white chip with black text, visible always.
local WURSTLOGO_VISIBILITY: string = "Always"

-- The pill's proportions come from the prototype's #pill rule: 32 px round
-- buttons in a capsule with 5×7 padding, floating 12 px under the top edge.
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

    -- A reinject that raced its own cleanup once left two of everything on
    -- screen — two logos, two pills, two lists. The furniture is idempotent
    -- now: whatever of it already lives on this layer dies before the new
    -- set is built.
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
        -- The dock lives on the raw ScreenGui (outside the ClickGUI's
        -- UIScale); a reinject must not leave two of it either.
        if ScreenGui then
            local screenGhost: Instance? = ScreenGui:FindFirstChild(ghostName)
            while screenGhost do
                screenGhost:Destroy()
                screenGhost = ScreenGui:FindFirstChild(ghostName)
            end
        end
    end

    -- ------------------------------------------------------------- wordmark
    -- Wurst's WurstLogo feature. The sausage sits on the game with nothing
    -- behind it; only the version string gets the white chip, which is what
    -- WURSTLOGO_BACKGROUND is the default for. Painting the whole block white
    -- put the transparent logo on a white slab, which is not how Wurst looks
    -- anywhere.
    -- The chip ends immediately after the version string — the band must
    -- never run on toward the HD icon or any other UI. 15 px is the
    -- estimated advance at the 20 px line the version now draws at — the
    -- user asked for this text bigger, and it is the product's face.
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

    -- Wurst's WurstLogo background: a half-alpha band behind rows 6..17 of
    -- the 18-logical-tall logo — 12..34 at the GUI scale 2 everything is
    -- drawn at — spanning the mark and the version string. The default is
    -- the Java's own: #FFFFFF at getColorI(128), i.e. 50% alpha. It is a
    -- stripe, never an opaque box; the WurstLogo Settings window recolours
    -- it live.
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

    -- The version string rides the background stripe, so it uses Wurst's own
    -- default text colour (#000000) — readable now that the band exists. Its
    -- frame matches the stripe's band exactly, so the text centres on the
    -- same baseline the band was drawn for.
    local versionChip: Frame = (create("Frame", {
        Parent = chip,
        Name = "VersionChip",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(LOGO_WIDTH + 10, 12),
        Size = UDim2.fromOffset(versionWidth, 22),
        ZIndex = 20,
    }) :: any) :: Frame

    -- The version renders on the bitmap contract; the TextLabel branch is
    -- the harness stand-in, since the shell always publishes
    -- state.bitmapText. Colour is captured per draw, so the WurstLogo Text
    -- setting redraws instead of repainting a property.
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

    -- The band's width came from a character-count estimate; the rendered
    -- truth replaces it — bitmap contract's measure() on the glyph path,
    -- TextBounds on the stand-in. Either way the chip, the stripe and the
    -- version frame shrink-wrap the actual text — the band ends exactly
    -- after "0.1 Beta", never a pixel into the game's own UI.
    local function fitLogoBand(): ()
        local measured: number = 0
        if drawsVersion and type(bitmapText.measure) == "function" then
            -- Measured at the 20 px line the version actually draws at.
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
        -- The atlas advance (11) is narrower than the packing estimate
        -- (12): when the real glyphs land, the band re-fits to them.
        table.insert(bitmapText.onReady, fitLogoBand)
    end
    task.defer(fitLogoBand)

    if type(state.applyAssetImage) == "function" then
        state.applyAssetImage("wurstLogo", logoImage, function(): ()
            logoImage.Visible = true
            logoFallback.Visible = false
        end)
    end

    -- Wurst's WurstLogo settings, read from the store at boot and edited
    -- live by the WurstLogo settings window.
    local logoAlways: boolean = true
    local function refreshLogoVisibility(): ()
        -- The wordmark belongs to the ClickGUI screen here (the user's call;
        -- Wurst itself draws it in-game at all times), and the Visibility
        -- setting can still remove it: we ship no updater, so "Only when
        -- outdated" can never fire.
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

    -- The old menu's FPS/PING/TIME/PLACE readout is gone entirely — Wurst
    -- draws the sausage and the version in that corner and nothing else.

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
        -- A phone always keeps the list on the left, where a thumb does not
        -- cover it (UI-V2, Mobile); a desktop follows Wurst's Position
        -- setting, whose default is Left, under the logo.
        return state.layout.compact or hudPosition == "Left"
    end

    -- Assigned once the Navigator below exists; the left-hand list starts
    -- under whatever the ClickGUI is currently showing in that corner.
    local navigatorBottom: () -> number = function(): number
        return FURNITURE_MARGIN_Y + LOGO_HEIGHT + 8
    end

    local function placeHudList(): ()
        if hudOnLeft() then
            hudFrame.AnchorPoint = Vector2.new(0, 0)
            hudFrame.Position = UDim2.new(
                0,
                FURNITURE_MARGIN_X,
                0,
                navigatorBottom()
            )
            hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        else
            -- The popup layer carries the ClickGUI's UIScale, so scale-1
            -- coordinates land past the physical screen edge — "Position:
            -- Right" flew off-screen exactly like the toasts did. The
            -- window manager already maps physical to logical; its right
            -- edge is the real one.
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

    -- One container per entry: the list layout owns the container's slot,
    -- so the label inside it is free to slide the prototype's 14 px without
    -- fighting the layout for its position.
    local hudRows: {[string]: any} = {}

    local function animationsOn(): boolean
        return hudAnimations and state.animationsEnabled ~= false
    end

    -- One container per entry; the glyph line inside it is drawn through
    -- the bitmap text contract, so these entries rasterise from the atlas
    -- the moment it resolves and fall back to Monocraft text until then.
    local hudRainbowClock: number = 0
    local function hudEntryColor(order: number?): Color3
        -- Two different livings, the way the user drew the line:
        --   Rainbow     the whole hue wheel, each row a step behind — a real
        --               rainbow rolling down the list.
        --   Animations  variants of the selected list colour. Multiplying
        --               RGB brightness preserves the chosen hue; neutral
        --               colours stay neutral (white breathes through greys
        --               instead of borrowing cyan).
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
        -- Spelled out instead of UDim2 addition: the harness's UDim2
        -- stand-in has no arithmetic.
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

    -- Show HackList: the overlay only. Hidden means the frame is not
    -- Visible and the poll skips its rebuild; module state and statuses
    -- are untouched — the list simply is not drawn. Seeded by the UI
    -- Settings replay, which runs before this library.
    local hudVisible: boolean = state.uiShowHackList ~= false

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
            -- Fit is judged in the HackList's own space: the list draws in
            -- logical pixels under the ClickGUI's UIScale, so the screen
            -- height must come through the same conversion or Auto flips to
            -- the count at the wrong number of rows.
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
        -- The rainbow rides every frame the list is visible, throttled to
        -- ~30 repaints a second; the pooled draw makes each one a recolour
        -- of a handful of rows, not a rebuild.
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

    -- The atlas resolves off-thread; the moment it lands, the list redraws
    -- through it instead of waiting for the next enable/disable.
    if state.bitmapText and type(state.bitmapText.onReady) == "table" then
        table.insert(state.bitmapText.onReady, forceHudRefresh)
    end

    hudFrame.Visible = hudVisible
    local function setHackListVisible(value: boolean): ()
        hudVisible = value ~= false
        hudFrame.Visible = hudVisible
        if hudVisible then
            forceHudRefresh()
            -- Animations, visibly: every line slides back in when the
            -- list appears, not only when a single module toggles.
            for _, row: any in pairs(hudRows) do
                slideHudRow(row)
            end
        end
    end
    Furniture.SetHackListVisible = setHackListVisible

    state.hudList = {
        frame = hudFrame,
        refresh = refreshHudList,
        SetVisible = setHackListVisible,
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
            -- Overlay rows are bitmap holders (`row.holder`), not vector
            -- labels. Writing `.label` threw the moment HackList settings
            -- opened and the Color option replayed. Recolor the live
            -- contract colour and rebuild the list through draw().
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

    -- ------------------------------------------------------------ Navigator
    -- Wurst's Navigator, as its own GUI rather than furniture on the ClickGUI
    -- screen: a dimmed layer over the game, the search focused on open, a
    -- flat three-column grid ordered by how often the player has activated
    -- each feature (persisted per game), Enter firing the selection, Space
    -- opening its settings, arrows and Tab moving the selection, Escape and
    -- Backspace-on-an-empty-query closing. Two platform notes: Roblox
    -- exposes no fourth mouse button, so Wurst's Mouse4-to-close cannot
    -- exist here, and Backspace only closes when the query is empty because
    -- it is also how the query is edited.
    local NAV_COLUMNS: number = 3
    local NAV_CELL_WIDTH: number = 150
    local NAV_CELL_HEIGHT: number = 22
    local NAV_CELL_GAP: number = 3
    local NAV_WIDTH: number = NAV_COLUMNS * NAV_CELL_WIDTH
        + (NAV_COLUMNS - 1) * NAV_CELL_GAP

    local navScreen: Frame = (create("Frame", {
        -- Raw ScreenGui space: PopupLayer carries ClickGUI scale, which made
        -- this supposedly full-screen surface cover only part of a phone.
        Parent = ScreenGui or PopupLayer,
        Name = "Navigator",
        Active = true,
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        -- The root owns input and safe screen coordinates, but it is visually
        -- transparent. Only the compact Wurst panel below is dimmed; covering
        -- the whole game made Navigator feel like a second full menu.
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 246,
    }) :: any) :: Frame
    -- Navigator cells are rebuilt on every query; the sweep adopts each
    -- generation onto the bitmap contract as it appears. The search box
    -- is a TextBox and stays native — a caret over hidden text is a bug.
    do
        local bitmap: any = state.bitmapText
        if bitmap and type(bitmap.adoptTree) == "function" then
            table.insert(Furniture.connections, bitmap.adoptTree(navScreen))
        end
    end

    -- The dock remains the one door between Navigator and ClickGUI. A second
    -- top-left "Wurst ClickGUI" bar duplicated it and made the full-screen
    -- surface look like another layout layered over the game.

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

    -- Space: the selection's settings, the way Navigator's arrow does it —
    -- the feature's card expands inside its category window, with the GUI
    -- open so the window is actually on screen.
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
            table.insert(Furniture.connections, entry.MouseButton1Click:Connect(function(): ()
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

    -- Whether the ClickGUI was up when the Navigator took the screen, so
    -- closing it can put things back the way they were. One surface at a
    -- time: the user's order, and also just how a full-screen overlay
    -- should behave.
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
        -- Focused on open, as the Java focuses its search field. This is a
        -- deliberate screen the player asked for; stealing the keyboard is
        -- the point.
        navSearch:CaptureFocus()
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
            -- Wurst keeps Navigator up after a toggle; so does this, with
            -- the field ready for the next query.
            navSearch:CaptureFocus()
        end
    end))

    -- The keyboard, while the screen is up. Arrows and Tab move the
    -- selection even while the search box owns the caret.
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

    -- The Navigator has no keybind any more — user order. RightShift is
    -- the menu key; the Navigator opens from the dock's magnifier button
    -- and nowhere else.

    state.navigator = {
        root = navScreen,
        refresh = rebuildNavigator,
        Open = openNavigator,
        Close = closeNavigator,
    }

    -- ----------------------------------------------------------------- dock
    -- The launcher is the small Roblox adaptation around the Wurst surface.
    -- Desktop keeps the direct module search. Touch devices already have the
    -- Navigator's focused search, so their persistent dock is only the two
    -- doors and does not cover the hotbar with a redundant text field.
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
        -- Above the Navigator's dim (246) either way: as a ScreenGui
        -- sibling the dock already outranks the whole popup layer, and
        -- on the PopupLayer fallback this keeps it over the dim and the
        -- grid, under the toasts (300). The dock is the way out of every
        -- surface; nothing may bury it.
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

    -- The pill keeps the prototype's own dark glass regardless of theme —
    -- it imitates Roblox chrome, not Wurst chrome — so only the *active*
    -- state of a button reads the theme.
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
            -- Above the dock, which sits at the bottom now.
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
            -- With the Navigator open, the dock button is the way back to
            -- Wurst: switch the style, close the Navigator, open the
            -- ClickGUI, persist — the state machine does all four. The
            -- user is never trapped in a surface.
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

    -- The magnifier: the one and only door into the Navigator. Drawn as
    -- an icon (ring plus handle) rather than a glyph, because no font in
    -- the stack promises a magnifier codepoint.
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

    -- Desktop search stays vector for its caret. Enter submits, clears the
    -- box and reports success, ambiguity or no match. Mobile search belongs
    -- to Navigator, so this shell is hidden and has no TextBox on touch.
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
        -- The dock talks to exactly one resolver: D's registry,
        -- state.moduleSearch.Execute. Every submit consumes and clears the
        -- query before invoking it. If FocusLost and the mobile-keyboard
        -- signal both fire for the same Enter, the second event sees an empty
        -- box; a later deliberate submit is never rejected by a wall-clock
        -- debounce. Nothing runs while typing and no results list exists.
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
        -- The on-screen keyboard's submit, where the platform offers it.
        pcall(function(): ()
            table.insert(
                Furniture.connections,
                (searchBox :: any).ReturnPressedFromOnScreenKeyboard:Connect(
                    submitSearch
                )
            )
        end)
    end

    -- Show dock. Desktop can hide the launcher (RightControl still
    -- opens the menu — the key handler never lived in the dock); the
    -- preference persists but never reaches a touch-primary device,
    -- where the dock is the only door and stays visible regardless of
    -- any stored desktop value. Hiding never destroys: Visible only.
    -- Executors on phones often emulate a mouse. The shell's device decision
    -- is authoritative: a phone can never lose its only launcher because an
    -- emulated MouseEnabled flag made it look like desktop.
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
    state.addMenuVisibilityListener(function(visible: boolean): ()
        restyleMenuButton()
        -- The wordmark belongs to the ClickGUI screen; the HackList stays —
        -- it is the in-game HUD. Navigator is its own screen now and ignores
        -- the ClickGUI entirely.
        refreshLogoVisibility()
        placeHudList()
        -- Boot placement runs while the GUI is closed, when every window is
        -- hidden and therefore invisible to the free-rectangle search. The
        -- moment the GUI really shows, any auto-placed settings or
        -- management window standing on a neighbour reflows to a free
        -- rectangle. Registered here, in the last library, so every other
        -- visibility listener has already restored what should be showing;
        -- hand-moved windows are never touched.
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
        -- Navigator is a raw full-screen surface, outside the ClickGUI's
        -- token-bound tree. Repaint it on every theme tick so UI Rainbow and
        -- manual colour changes stay synchronized instead of freezing at the
        -- colour that happened to be active when it opened.
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
        hudFrame:Destroy()
        navScreen:Destroy()
        pillFrame:Destroy()
        state.hudList = nil
        state.wurstLogo = nil
        state.navigator = nil
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
