--!strict
--
-- The ClickGUI.
--
-- Wurst's layout, which is the point of this menu: one window per category,
-- tiled from the top-left corner on first run, dragged wherever the player
-- likes afterwards, and remembered. No tabs, no page, no central window — a
-- category you are not using is a title bar you collapsed or a window you
-- closed, not a tab you have to click away from.
--
-- This is a *layout*, deliberately, and not a second interface. The rows it
-- shows are the cards the menu already builds: the same instance, the same
-- toggle, the same keybind slot, the same options panel, moved from the page
-- they used to sit on into the window for their category. Re-drawing them here
-- would have meant two renderers for one list of modules, which is how a menu
-- ends up with a feature that works in one view and not the other.
--
-- Placement is Wurst's too: windows are laid left to right in a row until the
-- next one would not fit, then down. It looks arranged because it is, and a
-- player who drags one somewhere else keeps that position forever.

export type CategoryWindow = {
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

-- Wurst's own proportions. A ClickGUI window is narrow — its job is to hold a
-- column of one-line rows, not to be a panel — and it is the same width on a
-- phone as on a desktop, because Vape's Roblox menu is deliberately small on a
-- phone and that is what makes it usable over a game rather than instead of
-- one. Nothing here scales with the viewport.
-- Wider than it was. At 160 the longest card names truncated to "Vehicl…" and
-- "Interac…", which is a menu you cannot read.
local WINDOW_WIDTH: number = 200
local WINDOW_MAX_HEIGHT: number = 300
-- Scale is the player's, not a guess of mine.
--
-- This was a viewport-height formula with a 1080 reference and a 1.35 factor,
-- three numbers with no source: the prototype has no reference height and no
-- automatic factor, it has a slider that defaults to 1 and runs 0.7 to 1.6.
-- Agent C's parity gate said so, and it was right — a number I picked while
-- looking at one screen is exactly the kind of decision that gate exists to
-- refuse.
local SCALE_MINIMUM: number = 0.7
local SCALE_MAXIMUM: number = 1.6
-- The screen the port is calibrated against. Every logical measure here is
-- Wurst's at GUI scale 2, which reads right on a 1600×900 viewport; a
-- smaller screen scales the whole layer down uniformly, a larger one up —
-- one number for everything, never a component resized on its own. The
-- player's Scale slider (ThemeEngine.shape.scale, default 1) multiplies on
-- top, so the UI Settings control keeps working.
local CALIBRATION_WIDTH: number = 1600
local CALIBRATION_HEIGHT: number = 900
local GRID_MARGIN: number = 10
local WINDOW_GAP: number = 2
-- Wurst tiles its first-run grid with a 5-logical gap; 10 at the GUI scale 2
-- everything is drawn at.
local GRID_GAP: number = 10
local TITLE_HEIGHT: number = 26

-- Official Wurst 7's windows, in the exact order ClickGui.init() builds them
-- at the pinned commit: Combat, Render, Blocks, Movement, Chat, Fun, Items,
-- Other. All eight exist from boot — an empty category is a stable window a
-- module can land in later, not a window that pops into existence mid-session.
local CATEGORY_ORDER: {string} = {
    "Combat",
    "Render",
    "Blocks",
    "Movement",
    "Chat",
    "Fun",
    "Items",
    "Other",
}

-- The same aliases the shell and the Framework carry — the contract is one,
-- copied because a downloaded file cannot reach the shell's locals at
-- require time, and because the harness boots this file against a host that
-- predates the contract.
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

    -- One UIScale over the whole layer, driven by the theme's own shape token,
    -- so the Scale row in UI Settings moves the entire interface and nothing
    -- has to be re-measured per device.
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

    -- The viewport in the space the windows are laid out in: screen pixels
    -- divided by the scale the layer runs at. nextSlot used the raw camera
    -- viewport, so at any scale other than 1 the first-run grid wrapped at
    -- the wrong edge — too early below 1, past the screen above it.
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
        -- The manifest orders the manager before this, so reaching here means
        -- the manager failed to start. Drawing a ClickGUI with no windows in it
        -- would be worse than saying so.
        error("ClickGui requires the window manager")
    end

    local ClickGui: any = {
        categories = {} :: {[string]: CategoryWindow},
        order = {} :: {string},
        -- Signals this library opens itself, as opposed to the ones the window
        -- manager opens on its behalf and releases with the window.
        connections = {} :: {RBXScriptConnection},
    }

    -- Left to right until the next window would pass the available edge,
    -- then down — Wurst's own first-run rule. With eight category windows
    -- plus UI Settings the row wraps wherever the viewport says, not at a
    -- column count somebody picked.
    local nextX: number = GRID_MARGIN
    local nextY: number = 64
    local rowHeight: number = 0

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
            -- Wurst gives a category window a collapse arrow and a pin, and no
            -- close button. Ours had one, and clicking it hid the category for
            -- good with nothing anywhere to bring it back — the player lost a
            -- sixth of the menu to a button that looked like it closed a panel.
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

        -- The window is exactly as tall as what is in it, until it reaches the
        -- limit and the body scrolls. A window padded out to a fixed height is
        -- how a category with two modules ends up looking broken.
        local function resize(): ()
            -- Wurst's "Max height" setting, live: the UI Settings slider
            -- publishes state.uiMaxHeight, and 0 means no limit, exactly as
            -- Wurst's tooltip says. Until that slider has run once, the
            -- window's own construction cap holds.
            local limit: number = tonumber(state.uiMaxHeight) or WINDOW_MAX_HEIGHT
            if limit <= 0 then
                limit = math.huge
            end
            -- A short viewport caps harder than the slider: a category
            -- taller than the screen cannot be clamped into it, so the
            -- body scrolls instead.
            limit = math.min(limit, logicalViewport().Y - 12)
            local wanted: number = math.min(
                TITLE_HEIGHT + layout.AbsoluteContentSize.Y + 4,
                limit
            )
            window.fullHeight = wanted
            if not window.collapsed then
                window.root.Size = UDim2.fromOffset(WINDOW_WIDTH, wanted)
            end
            -- A category that grows near the bottom edge walks back up
            -- instead of running off the viewport.
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

    -- A card is a row in the window for its category. It keeps every behaviour
    -- it already had; all that changes is where it is parented and that it now
    -- stretches to the window's width instead of the page's.
    function ClickGui.place(feature: any): ()
        local row: Frame? = feature and feature.row
        if not row then
            return
        end
        -- Whatever the card's attribute says — an official window, one of the
        -- port's old names, nothing — the contract resolves it to one of the
        -- eight windows above. A card built before D refiles it must not open
        -- a ninth window with an unofficial name.
        local raw: any = (row :: Frame):GetAttribute("FeatureCategory")
        local name: string = type(normalizeFeatureCategory) == "function"
            and normalizeFeatureCategory(raw)
            or fallbackNormalize(raw)
        local record: CategoryWindow = categoryWindow(name)
        record.count += 1;
        (row :: Frame).Parent = record.window.body;
        (row :: Frame).Size = UDim2.new(1, 0, 0, feature.collapsedHeight or 22)
        if record.resize then
            (record.resize :: () -> ())()
        end
    end

    -- Reset layout: every category window back on the first-run grid, in
    -- the official order, with every saved position already forgotten by
    -- the caller. Settings windows re-cascade the next time they open.
    function ClickGui.Retile(): ()
        nextX = GRID_MARGIN
        nextY = 64
        rowHeight = 0
        for _, name: string in ipairs(ClickGui.order) do
            local record: CategoryWindow = ClickGui.categories[name]
            if record then
                local slot: Vector2 = nextSlot(
                    record.window.fullHeight or WINDOW_MAX_HEIGHT * 0.5
                )
                record.window.root.Position = UDim2.fromOffset(slot.X, slot.Y)
            end
        end
    end

    -- Re-clamp every category window after the Max height slider moves;
    -- each record's own resize already knows how to read the live limit.
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
            -- The whole point of pinning a window in Wurst is that it stays on
            -- screen once the GUI is closed, so three pinned windows become a
            -- HUD. Hiding it with the rest made the pin a button that painted
            -- itself and did nothing else.
            if not visible and record.window.pinned then
                continue
            end
            record.window:SetVisible(visible)
        end
    end

    -- One window per category that actually holds a module, tiled in the
    -- official order with the empty ones omitted — Blocks, Items and Chat
    -- stay in the contract but draw nothing while nothing lives in them.
    -- The first pass walks the official order so the grid comes out in
    -- Wurst's sequence rather than module-load order; a category that gains
    -- its first module later gets its window then, at the next free slot.
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

    -- Cards built before this library started — which is all of them, since the
    -- modules load after the libraries.
    for _, feature: any in ipairs(allFeatures) do
        ClickGui.place(feature)
    end

    -- Applied to the layer the windows live on, so one number moves the whole
    -- interface and nothing has to be re-measured per device.
    local scale: UIScale = create("UIScale", {
        Parent = host.PopupLayer,
        Name = "ClickGuiScale",
        Scale = viewportScale(),
    }) :: UIScale
    -- `onLayout` takes a listener rather than returning a connection, so there
    -- is nothing to collect here; the scale instance is destroyed with the
    -- layer and the listener stops mattering.
    state.onLayout(function(): ()
        scale.Scale = viewportScale()
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
