export type WindowDefinition = {
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
