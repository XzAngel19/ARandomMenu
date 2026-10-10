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
    "Blatant",
}

local CATEGORY_ALIASES: {[string]: string} = {
    ["Visuals"] = "Render",
    ["Protection"] = "Movement",
    ["Utility"] = "Other",
    ["World"] = "Other",
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
            local leftOrder: number = tonumber(
                left:GetAttribute("FeatureSortOrder")
            ) or math.huge
            local rightOrder: number = tonumber(
                right:GetAttribute("FeatureSortOrder")
            ) or math.huge
            if leftOrder ~= rightOrder then
                return leftOrder < rightOrder
            end
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
