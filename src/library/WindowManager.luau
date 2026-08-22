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
    -- The pixel-sprite pen the widget library publishes. The harness's host
    -- stub does not carry it, so a stand-in draws an empty container there.
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

    -- ------------------------------------------------------ coordinate space
    -- Two spaces exist and only two: "screen" is the camera's device pixels,
    -- and "logical" is the space window offsets live in, which is screen
    -- divided by the one UIScale the ClickGUI puts over the popup layer.
    -- Everything the manager stores, compares or persists is logical. The
    -- old code mixed them — Position offsets (logical) against ViewportSize
    -- (screen), AbsoluteSize (screen) against Size offsets (logical) — and
    -- every mix was invisible at scale 1 and a layout bug at any other.
    local function screenViewport(): Vector2
        local camera: Camera? = workspace.CurrentCamera
        if camera then
            return (camera :: Camera).ViewportSize
        end
        return Vector2.new(1280, 720)
    end

    -- ClickGui parents one UIScale named ClickGuiScale to the popup layer.
    -- Before it exists (boot order) or without it (harness) the two spaces
    -- coincide.
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

    -- A window's logical rectangle. Size offsets are the truth — under a
    -- UIScale, AbsoluteSize is these numbers multiplied back into screen
    -- pixels, and the mock harness does not keep the two in step anyway.
    local function windowRect(window: any): (number, number, number, number)
        local root: any = window.root
        return root.Position.X.Offset, root.Position.Y.Offset,
            root.Size.X.Offset, root.Size.Y.Offset
    end

    local function clamp(position: Vector2, size: Vector2): Vector2
        local screen: Vector2 = logicalViewport()
        return Vector2.new(
            math.clamp(position.X, MARGIN, math.max(MARGIN, screen.X - size.X - MARGIN)),
            math.clamp(position.Y, MARGIN, math.max(MARGIN, screen.Y - size.Y - MARGIN))
        )
    end

    -- Full containment: after any resize the window must still fit the
    -- viewport whole, so growing a settings window near the bottom edge
    -- walks it back up instead of running it off screen.
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

    -- The window's real logical footprint: what it occupies once its content
    -- has grown, not the guess it was born with. Collapsed windows cost their
    -- title bar; open ones cost the larger of their current size and the full
    -- height their resize recorded, because a window that is about to grow to
    -- fullHeight must reserve that space before it does.
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

    -- The same rectangle in screen pixels, for anything that must compare a
    -- window against raw input coordinates or the camera.
    function manager.AbsoluteRect(window: any): (number, number, number, number)
        local x: number, y: number, w: number, h: number = windowRect(window)
        local origin: Vector2 = logicalToScreen(Vector2.new(x, y))
        local extent: Vector2 = logicalToScreen(Vector2.new(w, h))
        return origin.X, origin.Y, extent.X, extent.Y
    end

    -- Published so every library placing near windows shares this one
    -- coordinate space instead of re-deriving its own against the camera.
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

    -- Candidate lines to land on: the viewport's own edges, and the edges of
    -- every other window that is currently on screen. Snapping only to the
    -- screen would tile windows against the walls and never against each other,
    -- which is the arrangement players actually build.
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
        return Vector2.new(x, y)
    end

    local function raise(window: any): ()
        local index: number? = table.find(manager.list, window)
        if index then
            table.remove(manager.list, index)
        end
        table.insert(manager.list, window)
        for order: number, entry: any in ipairs(manager.list) do
            -- Step 1, not 4: the ScreenGui is Sibling-ordered, so only the
            -- roots compete at this level and fifty windows still stay
            -- under the pill (240), the tooltip (250) and the popups.
            local base: number = BASE_Z + order
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
            -- Width in logical offsets, never AbsoluteSize: under a UIScale
            -- the absolute width is scaled, and writing it back as an offset
            -- widened the window a little on every collapse.
            root.Size = collapsed
                and UDim2.fromOffset(root.Size.X.Offset, window.headerHeight)
                or UDim2.fromOffset(root.Size.X.Offset, window.fullHeight)
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
                -- The pointer moves in screen pixels; the window in logical
                -- offsets. Dividing the delta by the layer scale keeps the
                -- window under the cursor at every scale instead of lagging
                -- it below 1 and overshooting it above.
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
            -- bar, each carrying a pixel-drawn sprite — the reference
            -- screenshots show a red triangle for minimise, a green pin and
            -- a red cross, and none of them is a font glyph. 22 px is the
            -- titleButton's 11 logical at the GUI scale 2 everything is
            -- drawn at.
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
                -- Parked with the rest of the chrome so window:Destroy
                -- releases them; trackUiConnection would keep them alive
                -- until the whole shell dies.
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
                -- The pin sprite is Wurst's green; the square fills while the
                -- window is pinned — on means filled, like a hack row.
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
                -- The minimise triangle is the dark red of the reference
                -- screenshots; it points up while the body shows (fold me)
                -- and down while collapsed (unfold me).
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

    -- ------------------------------------------------------ feature settings
    -- Wurst pops a hack's settings into a window of its own — nothing ever
    -- expands inside a category window. One lazy window per feature, reused
    -- on every open, cascaded on first placement so no two are born on top
    -- of each other, packed to its widest option label, capped by Wurst's
    -- "Max settings height", and following the GUI like every other window
    -- unless pinned. This is the one contract: the row's triangle, the
    -- right-click and the Navigator all come through here.
    -- First placement by rectangle intersection: candidate slots walk a
    -- coarse grid and the first one whose rectangle overlaps no visible
    -- window wins. Only when the whole screen is occupied does it fall back
    -- to stacking from the top-left — a diagonal cascade guessed blind and
    -- still landed on whatever the guess did not know about.
    local function intersects(
        ax: number, ay: number, aw: number, ah: number,
        bx: number, by: number, bw: number, bh: number
    ): boolean
        return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
    end

    local function freeSlot(width: number, height: number): Vector2
        local screen: Vector2 = logicalViewport()
        local step: number = 40
        local yLimit: number = math.max(64, screen.Y - height - MARGIN)
        local xLimit: number = math.max(MARGIN, screen.X - width - MARGIN)
        local y: number = 64
        while y <= yLimit do
            local x: number = MARGIN
            while x <= xLimit do
                local collides: boolean = false
                for _, other: any in ipairs(manager.list) do
                    local root: any = other.root
                    if root and root.Visible ~= false then
                        if intersects(
                            x, y, width, height,
                            root.Position.X.Offset, root.Position.Y.Offset,
                            root.Size.X.Offset, root.Size.Y.Offset
                        ) then
                            collides = true
                            break
                        end
                    end
                end
                if not collides then
                    return Vector2.new(x, y)
                end
                x += step
            end
            y += step
        end
        return Vector2.new(MARGIN, 64)
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
            feature.expanded = true
            if feature.syncArrow then
                feature.syncArrow()
            end
            raise(existing)
            return existing
        end

        -- Packed to content: the widest option label decides, the way Wurst
        -- sizes a settings window. 12 px is the bitmap advance at the 16 px
        -- line; 72 covers the widest value column.
        local width: number = 200
        for _, optionRow: any in ipairs(feature.optionRows or {}) do
            local label: any = optionRow:FindFirstChild("OptionLabel")
            local text: string = label and tostring(label.Text) or ""
            width = math.max(width, 8 + #text * 12 + 24 + 72)
        end
        width = math.min(width, 420)

        -- The expected height decides which slots can even hold the
        -- window, so the search uses the same cap the resize will.
        local expectedLimit: number = tonumber(state.uiMaxSettingsHeight) or 200
        if expectedLimit <= 0 then
            expectedLimit = 600
        end
        local expectedHeight: number = math.min(
            TITLE_HEIGHT + (feature.optionsHeight or 40),
            expectedLimit
        )
        local slot: Vector2 = freeSlot(width, expectedHeight)

        local window: any = manager.Create({
            id = id,
            title = tostring(feature.name) .. " Settings",
            size = Vector2.new(width, TITLE_HEIGHT + 40),
            position = slot,
            closable = true,
            onClose = function(): ()
                feature.expanded = false
                if feature.syncArrow then
                    feature.syncArrow()
                end
            end,
        })
        window.featureSettings = true
        feature.settingsWindow = window

        -- The card's option rows move home: they were built into the card's
        -- hidden panel and live in this window from now on. The category
        -- window keeps exactly its height and rows.
        local options: any = feature.options
        if options then
            options.Visible = true
            options.Position = UDim2.fromOffset(0, 0)
            options.Size = UDim2.new(1, 0, 0, feature.optionsHeight or 40)
            options.Parent = window.body
        end

        local function resizeToOptions(): ()
            local wanted: number = TITLE_HEIGHT + (feature.optionsHeight or 40)
            local limit: number = tonumber(state.uiMaxSettingsHeight) or 200
            if limit <= 0 then
                limit = math.huge
            end
            wanted = math.min(wanted, limit)
            window.fullHeight = wanted
            if not window.collapsed then
                window.root.Size = UDim2.fromOffset(width, wanted)
            end
            -- Growing near an edge must never push the window off screen.
            manager.ClampWindow(window)
        end
        window.resizeToOptions = resizeToOptions
        resizeToOptions()

        -- The width above was packed from character counts, which is an
        -- estimate. Once the labels have really rendered, their TextBounds
        -- are the truth; one deferred re-pack replaces the estimate and
        -- re-clamps. Harness labels never render, so zero bounds are left
        -- alone.
        task.defer(function(): ()
            if not window.root.Parent then
                return
            end
            local widest: number = 0
            for _, optionRow: any in ipairs(feature.optionRows or {}) do
                local label: any = optionRow:FindFirstChild("OptionLabel")
                local bounds: any = label and label.TextBounds
                local measured: number = bounds and tonumber(bounds.X) or 0
                if measured > 0 then
                    widest = math.max(widest, 8 + measured + 24 + 72)
                end
            end
            if widest > 0 then
                width = math.clamp(widest, 160, 420)
                resizeToOptions()
            end
        end)

        feature.expanded = true
        if feature.syncArrow then
            feature.syncArrow()
        end
        window.root.Visible = true
        raise(window)
        return window
    end

    -- Whole-window bring-to-front, published: raising re-stacks every root
    -- (the ScreenGui is Sibling-ordered, so the root's ZIndex carries the
    -- entire window above the rest).
    function manager.BringToFront(window: any): ()
        if window then
            raise(window)
        end
    end

    -- Feature settings windows follow the GUI the way category windows do,
    -- pinned ones excepted — pinning is how a settings window becomes HUD.
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
