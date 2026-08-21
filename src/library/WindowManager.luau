--!strict
--
-- Window manager.
--
-- Every floating thing the menu draws is the same object: a rectangle with a
-- title bar you drag, a body that can be hidden, a position that survives a
-- reload, and a place in the stack. That was written out longhand once per
-- window kind — the favourites list, the overlay menu, the four overlays and
-- their settings panels each carried their own copy of drag, clamp, z-order and
-- persistence, and only the copies that happened to be edited together stayed
-- in agreement.
--
-- The behaviours are Wurst's, because the ClickGUI is what this is for:
--
--   collapse   the body hides and the title bar stays, so a window you are not
--              using costs one row instead of a screenful.
--   pin        the window survives the GUI being closed. Three pinned windows
--              is how a player builds a HUD out of the four things they use.
--   snap       within eight pixels of a viewport edge or another window's edge,
--              the drag lands flush. Wurst's windows tile because players tile
--              them; making that free is most of why its layout looks tidy.
--   max height the body scrolls past a limit instead of the window growing off
--              the bottom of the screen.
--
-- Positions are stored per profile under `configData.ui.windows`, keyed by the
-- window's id rather than its title, so renaming a window in the interface does
-- not move it back to the middle of the screen.

export type WindowDefinition = {
    id: string,
    title: string?,
    size: Vector2,
    position: Vector2,
    -- An overlay with no chrome: no title bar, no border, dragged by its whole
    -- surface. The radar and the text readout are these.
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

-- How close a dragged edge has to be before it lands flush.
local SNAP_DISTANCE: number = 8
-- Every window sits above the page content and below the colour picker and the
-- tooltips, which have to be able to appear over anything.
local BASE_Z: number = 150
local MARGIN: number = 6
-- The prototype's title bar. Named rather than inline because the parity gate
-- reads this constant and holds it to spec.json. 26 is Wurst's own 13 logical
-- pixels at the GUI scale 2 everything here is drawn at — C read it out of
-- the Java, and the prototype was changed first.
local TITLE_HEIGHT: number = 26
-- The prototype's `.tbar` font size, held by the same gate. The title used
-- to go through makeTextLabel, whose 1.35 multiplier rendered it at 16 px —
-- visibly heavier than the spec on every window at once.
local TITLE_FONT_SIZE: number = 11.5

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

    configData.ui = configData.ui or {}
    configData.ui.windows = configData.ui.windows or {}

    local manager: any = {
        list = {} :: {any},
        byId = {} :: {[string]: any},
    }

    local function viewport(): Vector2
        local camera: Camera? = workspace.CurrentCamera
        if camera then
            return (camera :: Camera).ViewportSize
        end
        return Vector2.new(1280, 720)
    end

    local function clamp(position: Vector2, size: Vector2): Vector2
        local screen: Vector2 = viewport()
        return Vector2.new(
            math.clamp(position.X, MARGIN, math.max(MARGIN, screen.X - size.X - MARGIN)),
            math.clamp(position.Y, MARGIN, math.max(MARGIN, screen.Y - size.Y - MARGIN))
        )
    end

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

    -- Candidate lines to land on: the viewport's own edges, and the edges of
    -- every other window that is currently on screen. Snapping only to the
    -- screen would tile windows against the walls and never against each other,
    -- which is the arrangement players actually build.
    local function snap(window: any, position: Vector2, size: Vector2): Vector2
        local screen: Vector2 = viewport()
        local xLines: {number} = {MARGIN, screen.X - size.X - MARGIN}
        local yLines: {number} = {MARGIN, screen.Y - size.Y - MARGIN}
        for _, other: any in ipairs(manager.list) do
            if other ~= window and other.root.Visible then
                local otherPosition: Vector2 = Vector2.new(
                    other.root.Position.X.Offset,
                    other.root.Position.Y.Offset
                )
                local otherSize: Vector2 = other.root.AbsoluteSize
                table.insert(xLines, otherPosition.X)
                table.insert(xLines, otherPosition.X + otherSize.X)
                table.insert(xLines, otherPosition.X - size.X)
                table.insert(yLines, otherPosition.Y)
                table.insert(yLines, otherPosition.Y + otherSize.Y)
                table.insert(yLines, otherPosition.Y - size.Y)
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
        return Vector2.new(x, y)
    end

    local function raise(window: any): ()
        local index: number? = table.find(manager.list, window)
        if index then
            table.remove(manager.list, index)
        end
        table.insert(manager.list, window)
        for order: number, entry: any in ipairs(manager.list) do
            local base: number = BASE_Z + order * 4
            entry.root.ZIndex = base
            -- Windows whose children declare a depth get restacked with the
            -- window. Without it a raised overlay draws its own body under the
            -- window it was just lifted above.
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

    -- The primitive. `Create` builds a window and then calls this; anything
    -- that already has a frame of its own — the overlays, whose look predates
    -- the ClickGUI and is not being changed yet — calls it directly and keeps
    -- its own chrome. One mechanism, two front doors, rather than a second
    -- copy of drag and clamp living in the library that draws overlays.
    function manager.Adopt(root: Frame, definition: any): any
        local id: string = definition.id
        local saved: any = configData.ui.windows[id]
        if type(saved) ~= "table" then
            -- Overlays stored their position under a different key before the
            -- manager existed. Read it once so nobody's HUD jumps back to the
            -- middle of the screen on the update that introduced this.
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
            -- The manager makes these, so the manager releases them. They are
            -- also handed to the shell's tracker, which only runs at teardown:
            -- a window destroyed before that used to leave its drag listeners
            -- connected to an instance that no longer existed.
            connections = {} :: {RBXScriptConnection},
        }

        local function own(connection: RBXScriptConnection): RBXScriptConnection
            table.insert(window.connections, connection)
            trackUiConnection(connection)
            return connection
        end

        if type(saved) == "table" and saved.x and saved.y then
            local landed: Vector2 = clamp(
                Vector2.new(saved.x, saved.y),
                Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
            )
            root.Position = UDim2.fromOffset(landed.X, landed.Y)
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
                and UDim2.fromOffset(root.AbsoluteSize.X, window.headerHeight)
                or UDim2.fromOffset(root.AbsoluteSize.X, window.fullHeight)
            persist(window)
        end

        function window:SetPinned(pinned: boolean): ()
            window.pinned = pinned
            persist(window)
        end

        function window:Raise(): ()
            raise(window)
        end

        function window:Destroy(): ()
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

        -- A surface with no title bar is dragged by all of itself; one with a
        -- header drags only from there, which keeps its content clickable.
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
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                dragStart = Vector2.new(input.Position.X, input.Position.Y)
                startPosition = Vector2.new(
                    root.Position.X.Offset,
                    root.Position.Y.Offset
                )
                raise(window)
            end
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
                local size: Vector2 = root.AbsoluteSize
                local wanted: Vector2 = startPosition + pointer - dragStart
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

        -- Assigned by Adopt below. The chrome's click handlers close over it,
        -- which is safe because they only run afterwards; anything that has to
        -- *read* the state to paint itself is deferred into `paintChrome`,
        -- because that does run immediately and used to index a nil table.
        local window: any = nil
        local paintChrome: {() -> ()} = {}
        -- The chrome is wired before Adopt exists to own it, so its
        -- connections are parked here and handed over below.
        local chromeConnections: {RBXScriptConnection} = {}
        local header: Frame? = nil
        local closeButton: TextButton? = nil

        if not bare then
            -- A Wurst window is a rectangle: no corner radius anywhere, one
            -- thin border. The border binds to the outline token, which the
            -- UI Settings Accent row repaints — Wurst's Accent colours title
            -- bars *and* borders.
            local edge: UIStroke = (create("UIStroke", {
                Parent = root,
                Color = Theme.outline,
                Transparency = 0.15,
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

            local buttonX: number = -5
            -- Wurst's chrome controls are small squares sitting in the title
            -- bar — a box with a symbol, not a bare glyph. 16 px is 8 logical
            -- at the GUI scale 2 the interface is drawn at.
            local function chromeButton(symbol: string): TextButton
                local button: TextButton = (create("TextButton", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = bar,
                    Active = true,
                    AutoButtonColor = false,
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                    BackgroundTransparency = 0.72,
                    BorderSizePixel = 0,
                    FontFace = CONTROL_FONT,
                    Text = symbol,
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
                button.Size = UDim2.fromOffset(16, 16)
                button.ZIndex = 3
                bind(button, "TextColor3", "accentText")
                -- Parked with the rest of the chrome so window:Destroy
                -- releases them; trackUiConnection would keep them alive
                -- until the whole shell dies.
                table.insert(chromeConnections, button.MouseEnter:Connect(function(): ()
                    button.BackgroundTransparency = 0.45
                end))
                table.insert(chromeConnections, button.MouseLeave:Connect(function(): ()
                    button.BackgroundTransparency = 0.72
                end))
                buttonX -= 19
                return button
            end

            if definition.closable ~= false then
                closeButton = chromeButton("×")
            end
            if definition.pinnable ~= false then
                -- The pin is a square that fills with the enabled token while
                -- the window is pinned — the same "on means filled" grammar
                -- as a hack row.
                local pin: TextButton = chromeButton("▪")
                local function paintPin(): ()
                    pin.BackgroundTransparency = window.pinned and 0 or 0.72
                    pin.BackgroundColor3 = window.pinned
                        and Theme.enabled
                        or Color3.fromRGB(0, 0, 0)
                    pin.TextColor3 = window.pinned
                        and Theme.enabledText
                        or Theme.accentText
                end
                table.insert(paintChrome, paintPin)
                table.insert(chromeConnections, pin.MouseButton1Click:Connect(function(): ()
                    window:SetPinned(not window.pinned)
                    paintPin()
                end))
            end
            if definition.collapsible ~= false then
                local chevron: TextButton = chromeButton("–")
                table.insert(chromeConnections, chevron.MouseButton1Click:Connect(function(): ()
                    window:SetCollapsed(not window.collapsed)
                    chevron.Text = window.collapsed and "+" or "–"
                end))
                table.insert(paintChrome, function(): ()
                    chevron.Text = window.collapsed and "+" or "–"
                end)
            end
            header = bar
        end

        -- Scrolling, always. A window whose content fits looks identical to a
        -- plain frame, and one whose content does not stops growing off the
        -- bottom of the screen instead of being unreachable.
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

    -- A window that survives the GUI closing is the point of pinning it.
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

    -- Wurst's ClickGUI Opacity setting: the body of every window at one
    -- alpha. The title bar stays opaque — Wurst fades only the background.
    -- Remembered on the manager so a window created after the slider moved
    -- is born at the same alpha.
    manager.bodyTransparency = 0.5
    function manager.SetOpacity(alpha: number): ()
        manager.bodyTransparency = math.clamp(1 - alpha, 0, 1)
        for _, window: any in ipairs(manager.list) do
            if window.headerHeight and window.headerHeight > 0 then
                window.root.BackgroundTransparency = manager.bodyTransparency
            end
        end
    end

    -- A saved position is kept, but a smaller screen must never leave a window
    -- stranded outside the viewport.
    function manager.Reclamp(): ()
        for _, window: any in ipairs(manager.list) do
            local landed: Vector2 = clamp(
                Vector2.new(
                    window.root.Position.X.Offset,
                    window.root.Position.Y.Offset
                ),
                window.root.AbsoluteSize
            )
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
