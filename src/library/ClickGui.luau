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

-- Wurst's own proportions, scaled to a Roblox viewport: a column of rows about
-- this wide, and a window that stops growing at this height and scrolls.
local WINDOW_WIDTH: number = 186
local WINDOW_MAX_HEIGHT: number = 340
local GRID_MARGIN: number = 12
local GRID_GAP: number = 8
local TITLE_HEIGHT: number = 22

-- The order Wurst lists its categories in, as far as ours line up with it.
-- Anything a game module invents later lands after these, in the order it
-- arrives.
local CATEGORY_ORDER: {string} = {
    "Combat",
    "Movement",
    "Visuals",
    "Protection",
    "Utility",
    "Spoof",
}

function Module.init(context: any): any
    local host: any = context
    local state: any = host.state
    local create: any = host.create
    local allFeatures: {any} = host.allFeatures

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
    }

    -- Left to right until the next window would not fit, then down. Measured
    -- from the manager's own margin so the first window lines up with anything
    -- the player later snaps to the edge.
    local nextX: number = GRID_MARGIN
    local nextY: number = 96
    local rowHeight: number = 0

    local function nextSlot(height: number): Vector2
        local viewport: Vector2 = workspace.CurrentCamera
            and (workspace.CurrentCamera :: Camera).ViewportSize
            or Vector2.new(1280, 720)
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
        })

        local layout: UIListLayout = create("UIListLayout", {
            Parent = window.body,
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }) :: UIListLayout
        create("UIPadding", {
            Parent = window.body,
            PaddingTop = UDim.new(0, 2),
            PaddingBottom = UDim.new(0, 2),
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 2),
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
            local wanted: number = math.min(
                TITLE_HEIGHT + layout.AbsoluteContentSize.Y + 4,
                WINDOW_MAX_HEIGHT
            )
            window.fullHeight = wanted
            if not window.collapsed then
                window.root.Size = UDim2.fromOffset(WINDOW_WIDTH, wanted)
            end
        end
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
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
        local name: string = tostring(
            (row :: Frame):GetAttribute("FeatureCategory") or "General"
        )
        local record: CategoryWindow = categoryWindow(name)
        record.count += 1;
        (row :: Frame).Parent = record.window.body;
        (row :: Frame).Size = UDim2.new(1, 0, 0, feature.collapsedHeight or 22)
        if record.resize then
            (record.resize :: () -> ())()
        end
    end

    function ClickGui.SetVisible(visible: boolean): ()
        for _, name: string in ipairs(ClickGui.order) do
            local record: CategoryWindow = ClickGui.categories[name]
            record.window:SetVisible(visible)
        end
    end

    -- Categories that exist before a single card does, so the grid comes out in
    -- Wurst's order rather than in whichever order the modules happened to
    -- finish loading.
    for _, name: string in ipairs(CATEGORY_ORDER) do
        categoryWindow(name)
    end

    -- Cards built before this library started — which is all of them, since the
    -- modules load after the libraries.
    for _, feature: any in ipairs(allFeatures) do
        ClickGui.place(feature)
    end

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
