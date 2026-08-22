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
local HACKLIST_SLIDE: number = 14

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
    -- never run on toward the HD icon or any other UI. 12 px is the bitmap
    -- advance at the 16 px line.
    local versionText: string = tostring(PRODUCT.version)
    local versionWidth: number = 8 + #versionText * 12
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
                TextSize = 16,
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
            TextSize = 16,
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
            measured = tonumber(bitmapText.measure(
                {{text = versionText}}, 16
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
    local hudVisible: boolean = configData.values["UI.ShowHackList"] ~= false
    hudFrame.Visible = hudVisible

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

    local function animationsOn(): boolean
        return hudAnimations and state.animationsEnabled ~= false
    end

    -- One container per entry; the glyph line inside it is drawn through
    -- the bitmap text contract, so these entries rasterise from the atlas
    -- the moment it resolves and fall back to Monocraft text until then.
    local function drawHudEntry(row: any, name: string, status: string?): ()
        local segments: {any} = {{text = name, color = hudColor}}
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
                TextSize = HACKLIST_FONT_SIZE,
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
            Size = UDim2.new(1, 0, 0, HACKLIST_LINE_HEIGHT),
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
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
            local isNew: boolean = row == nil
            if not row then
                row = newHudRow(entry.name)
                hudRows[entry.name] = row
            end
            row.container.LayoutOrder = order
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

    -- The atlas resolves off-thread; the moment it lands, the list redraws
    -- through it instead of waiting for the next enable/disable.
    if state.bitmapText and type(state.bitmapText.onReady) == "table" then
        table.insert(state.bitmapText.onReady, forceHudRefresh)
    end

    state.hudList = {
        frame = hudFrame,
        refresh = refreshHudList,
        SetVisible = function(visible: boolean): ()
            hudVisible = visible
            hudFrame.Visible = visible
            if visible then
                forceHudRefresh()
            end
        end,
        IsVisible = function(): boolean
            return hudVisible
        end,
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
    local NAV_LIMIT: number = 36
    local NAV_WIDTH: number = NAV_COLUMNS * NAV_CELL_WIDTH
        + (NAV_COLUMNS - 1) * 3

    local navScreen: Frame = (create("Frame", {
        Parent = PopupLayer,
        Name = "Navigator",
        Active = true,
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.45,
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

    local navColumn: Frame = (create("Frame", {
        Parent = navScreen,
        Name = "Column",
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0, 90),
        Size = UDim2.fromOffset(NAV_WIDTH, 26),
        ZIndex = 247,
    }) :: any) :: Frame

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
        Size = UDim2.new(1, 0, 0, 24),
        Text = "",
        TextColor3 = Theme.text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 248,
    }) :: any) :: TextBox
    create("UIPadding", {
        Parent = navSearch,
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
    })
    navSearch.Size = UDim2.new(1, -126, 0, 24)
    local wurstClickGui: TextButton = (create("TextButton", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = navColumn,
        Name = "WurstClickGUI",
        Active = true,
        AutoButtonColor = false,
        BackgroundColor3 = Theme.background,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -120, 0, 0),
        Size = UDim2.fromOffset(120, 24),
        Text = "Wurst ClickGUI",
        TextColor3 = Theme.text,
        TextSize = 12,
        ZIndex = 248,
    }) :: any) :: TextButton
    table.insert(Furniture.connections, wurstClickGui.MouseButton1Click:Connect(function(): ()
        if type(state.SetMenuStyle) == "function" then
            state.SetMenuStyle("Wurst", true)
        end
    end))

    local navResults: Frame = (create("Frame", {
        Parent = navColumn,
        Name = "Results",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 30),
        Size = UDim2.new(1, 0, 0, 0),
        ZIndex = 247,
    }) :: any) :: Frame
    create("UIGridLayout", {
        Parent = navResults,
        CellPadding = UDim2.fromOffset(3, 3),
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
            if index > NAV_LIMIT then
                break
            end
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
                TextSize = 12,
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
        navColumn.Size = UDim2.fromOffset(
            NAV_WIDTH,
            30 + rows * (NAV_CELL_HEIGHT + 3)
        )
        navResults.Size = UDim2.new(1, 0, 0, rows * (NAV_CELL_HEIGHT + 3))
        paintNavSelection()
    end

    local function openNavigator(): ()
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

    -- RightShift opens Navigator, Wurst's own default bind — unless the
    -- player's stored menu key is still RightShift from an older build, in
    -- which case the menu keeps its key and Navigator waits for a rebind.
    table.insert(Furniture.connections, UserInputService.InputBegan:Connect(function(
        input: InputObject,
        gameProcessed: boolean
    ): ()
        if gameProcessed or input.KeyCode ~= Enum.KeyCode.RightShift then
            return
        end
        if state.toggleKey == Enum.KeyCode.RightShift then
            return
        end
        if navScreen.Visible then
            closeNavigator()
        else
            openNavigator()
        end
    end))

    state.navigator = {
        root = navScreen,
        refresh = rebuildNavigator,
        Open = openNavigator,
        Close = closeNavigator,
        OpenWurst = function(): ()
            if type(state.SetMenuStyle) == "function" then
                state.SetMenuStyle("Wurst", true)
            end
        end,
        wurstButton = wurstClickGui,
    }

    -- ----------------------------------------------------------------- dock
    -- The launcher, bottom-centre: [ Search module... ][ ≡ ]. The five per
    -- cent of this menu that is Roblox rather than Wurst. It lives on the
    -- raw ScreenGui, outside the ClickGUI's UIScale, sits 70 px above the
    -- bottom so it clears where most games park their hotbar, and stays
    -- visible with the GUI closed — it is how the GUI opens. Enter in the
    -- search box resolves a module by name through
    -- state.invokeModuleSearch (success / not found / ambiguous all
    -- notify), then clears itself; it never runs administrative actions.
    -- The ≡ button opens whichever surface UI.MenuStyle selects.
    local DOCK_SEARCH_WIDTH: number = 190
    local DOCK_BOTTOM_MARGIN: number = 70
    local pillWidth: number = PILL_PADDING_X * 2
        + DOCK_SEARCH_WIDTH
        + PILL_GAP
        + PILL_BUTTON

    local dockVisible: boolean = state.isMobile
        or configData.values["UI.ShowDock"] ~= false
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
        Visible = dockVisible,
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
        state.tooltipToken = state.tooltipToken + 1;
        (tooltip :: TextLabel).Text = text;
        (tooltip :: TextLabel).Size = UDim2.fromOffset(
            math.clamp(#text * 5.5 + 24, 120, 320),
            30
        );
        (tooltip :: TextLabel).Position = UDim2.fromOffset(
            anchor.AbsolutePosition.X,
            -- Above the dock, which sits at the bottom now.
            anchor.AbsolutePosition.Y - 38
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
            ZIndex = 249,
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
        PILL_PADDING_X + DOCK_SEARCH_WIDTH + PILL_GAP,
        "≡",
        16,
        "Show or hide the menu",
        function(): ()
            if type(state.openMenuSurface) == "function" then
                state.openMenuSurface()
            else
                state.setMenuVisible(not state.visible)
            end
        end
    )

    -- The search half of the dock. A TextBox stays vector for its caret;
    -- Enter submits, the box clears, and the resolver notifies success,
    -- not-found or ambiguous. On touch the platform keyboard opens with
    -- focus, which is the mobile path.
    local searchShell: Frame = (create("Frame", {
        Parent = pillFrame,
        Name = "DockSearch",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.94,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(PILL_PADDING_X, PILL_PADDING_Y),
        Size = UDim2.fromOffset(DOCK_SEARCH_WIDTH, PILL_BUTTON),
        ZIndex = 249,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = searchShell,
        CornerRadius = UDim.new(1, 0),
    })
    local submitLocked: boolean = false
    local function submitSearch(query: string): any
        if submitLocked or query:gsub("%s", "") == "" then
            return nil
        end
        submitLocked = true
        task.defer(function(): ()
            submitLocked = false
        end)
        local search: any = state.moduleSearch
        if search and type(search.Execute) == "function" then
            local result: any = search.Execute(query)
            if result.status == "success" then
                return result.entry
            end
        end
        return nil
    end

    local dockSearchBox: TextBox? = nil
    local dockSubmitButton: TextButton? = nil
    if type(makeTextBox) == "function" then
        local searchBox: TextBox = (makeTextBox(searchShell, "") :: any) :: TextBox
        dockSearchBox = searchBox
        searchBox.Name = "DockSearchBox"
        searchBox.BackgroundTransparency = 1
        searchBox.ClearTextOnFocus = false
        searchBox.PlaceholderText = "Search module..."
        searchBox.Position = UDim2.fromOffset(12, 0)
        searchBox.Size = UDim2.new(1, -42, 1, 0)
        searchBox.TextColor3 = PILL_IDLE_TEXT
        searchBox.TextSize = 13
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.ZIndex = 249
        local boxCorner: UICorner? = searchBox:FindFirstChild("StyleCorner") :: UICorner?
        if boxCorner then
            boxCorner:Destroy()
        end
        local boxStroke: UIStroke? = searchBox:FindFirstChild("StyleStroke") :: UIStroke?
        if boxStroke then
            boxStroke:Destroy()
        end
        local submitButton: TextButton = (create("TextButton", {
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = searchShell,
            Name = "Submit",
            Active = true,
            AnchorPoint = Vector2.new(1, 0),
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -4, 0, 0),
            Size = UDim2.fromOffset(28, PILL_BUTTON),
            Text = ">",
            TextColor3 = PILL_IDLE_TEXT,
            TextSize = 13,
            ZIndex = 249,
        }) :: any) :: TextButton
        dockSubmitButton = submitButton
        local function submitBox(): ()
            local query: string = tostring(searchBox.Text or "")
            searchBox.Text = ""
            submitSearch(query)
        end
        table.insert(Furniture.connections,
            submitButton.MouseButton1Click:Connect(submitBox))
        table.insert(Furniture.connections,
            searchBox.FocusLost:Connect(function(enterPressed: boolean): ()
                if enterPressed == true then
                    submitBox()
                end
            end))
        table.insert(Furniture.connections,
            searchBox.InputBegan:Connect(function(input: InputObject): ()
                if input.KeyCode == Enum.KeyCode.Return
                    or input.KeyCode == Enum.KeyCode.KeypadEnter then
                    submitBox()
                end
            end))
    end

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
    end)

    -- `root`, not `frame`: every other surface the menu publishes — a managed
    -- window, a drawing set — names its top instance that way, and the suite
    -- that checks the pill stays on screen with the GUI closed was reading
    -- `root` and finding nil.
    state.commandDock = {
        root = pillFrame,
        search = dockSearchBox,
        submit = dockSubmitButton,
        Submit = submitSearch,
        SetVisible = function(visible: boolean): ()
            dockVisible = state.isMobile or visible
            pillFrame.Visible = dockVisible
        end,
        IsVisible = function(): boolean
            return pillFrame.Visible
        end,
    }
    state.pill = {
        root = pillFrame,
        restyle = restyleMenuButton,
        SetVisible = state.commandDock.SetVisible,
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
        state.commandDock = nil
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
