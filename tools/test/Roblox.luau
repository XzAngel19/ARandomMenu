--!strict
--
-- Minimal Roblox stand-in for the headless module tests.
--
-- The point is not to reimplement the engine: it is to give the module files
-- the handful of behaviours they actually depend on — instance parenting,
-- signals, vector maths, camera projection and raycasts — so their logic can be
-- exercised, and their teardown proved, without a game client. Anything a
-- module does not use is deliberately absent, so a test failing here means the
-- module reached for something new rather than the mock being incomplete.

export type MockWorld = {
    players: any,
    localPlayer: any,
    camera: any,
    workspace: any,
    raycastResult: any,
    clock: number,
    addPlayer: (name: string, team: any, position: any) -> any,
    removePlayer: (player: any) -> (),
}

local Mock = {}

local function class(name: string): any
    return name
end

-- Vectors ------------------------------------------------------------------

local Vector3Meta: any = {}
Vector3Meta.__index = Vector3Meta

local function vector3(x: number, y: number, z: number): any
    return setmetatable({X = x, Y = y, Z = z}, Vector3Meta)
end

function Vector3Meta.__add(a: any, b: any): any
    return vector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function Vector3Meta.__sub(a: any, b: any): any
    return vector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

function Vector3Meta.__mul(a: any, b: any): any
    if type(b) == "number" then
        return vector3(a.X * b, a.Y * b, a.Z * b)
    end
    if type(a) == "number" then
        return vector3(b.X * a, b.Y * a, b.Z * a)
    end
    return vector3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

function Vector3Meta.__div(a: any, b: number): any
    return vector3(a.X / b, a.Y / b, a.Z / b)
end

function Vector3Meta.__eq(a: any, b: any): boolean
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

function Vector3Meta.__index(self: any, key: string): any
    if key == "Magnitude" then
        return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
    end
    if key == "Unit" then
        local magnitude: number = math.sqrt(
            self.X * self.X + self.Y * self.Y + self.Z * self.Z
        )
        if magnitude == 0 then
            return vector3(0, 0, 0)
        end
        return vector3(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
    end
    return rawget(Vector3Meta, key)
end

function Vector3Meta.Dot(self: any, other: any): number
    return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

function Vector3Meta.Lerp(self: any, other: any, alpha: number): any
    return vector3(
        self.X + (other.X - self.X) * alpha,
        self.Y + (other.Y - self.Y) * alpha,
        self.Z + (other.Z - self.Z) * alpha
    )
end

local Vector2Meta: any = {}

local function vector2(x: number, y: number): any
    return setmetatable({X = x, Y = y}, Vector2Meta)
end

function Vector2Meta.__add(a: any, b: any): any
    return vector2(a.X + b.X, a.Y + b.Y)
end

function Vector2Meta.__sub(a: any, b: any): any
    return vector2(a.X - b.X, a.Y - b.Y)
end

function Vector2Meta.__mul(a: any, b: any): any
    if type(b) == "number" then
        return vector2(a.X * b, a.Y * b)
    end
    return vector2(a.X * b.X, a.Y * b.Y)
end

function Vector2Meta.__index(self: any, key: string): any
    if key == "Magnitude" then
        return math.sqrt(self.X * self.X + self.Y * self.Y)
    end
    if key == "Unit" then
        local magnitude: number = math.sqrt(self.X * self.X + self.Y * self.Y)
        if magnitude == 0 then
            return vector2(0, 0)
        end
        return vector2(self.X / magnitude, self.Y / magnitude)
    end
    return rawget(Vector2Meta, key)
end

-- CFrames -------------------------------------------------------------------
--
-- Only the four things the modules touch: a position, the two direction
-- vectors, and adding a Vector3 to move it.

local CFrameMeta: any = {}
CFrameMeta.__index = CFrameMeta

local function cframe(position: any, look: any?): any
    return setmetatable({
        Position = position,
        LookVector = look or vector3(0, 0, -1),
        RightVector = vector3(1, 0, 0),
        UpVector = vector3(0, 1, 0),
    }, CFrameMeta)
end

function CFrameMeta.__add(a: any, b: any): any
    return cframe(a.Position + b, a.LookVector)
end

function CFrameMeta.__sub(a: any, b: any): any
    return cframe(a.Position - b, a.LookVector)
end

function CFrameMeta.__mul(a: any, b: any): any
    -- Only the case the ESP needs: a point in the CFrame's own space, with no
    -- rotation applied, which is enough to place the eight box corners.
    if type(b) == "table" and b.X and b.Y and b.Z then
        return a.Position + b
    end
    return a
end

function CFrameMeta.PointToObjectSpace(self: any, point: any): any
    return point - self.Position
end

-- Signals ------------------------------------------------------------------

-- Anything a pointer can be over. Kept as a set rather than a chain of
-- comparisons because every instance creation checks it.
local POINTER_CLASSES: {[string]: boolean} = {
    Frame = true,
    ScrollingFrame = true,
    TextLabel = true,
    TextButton = true,
    TextBox = true,
    ImageLabel = true,
    ImageButton = true,
    CanvasGroup = true,
    ScreenGui = true,
}

local function signal(): any
    local handlers: {any} = {}
    local object: any = {}
    function object:Connect(callback: any): any
        table.insert(handlers, callback)
        local connection: any = {Connected = true}
        function connection:Disconnect(): ()
            connection.Connected = false
            local index: number? = table.find(handlers, callback)
            if index then
                table.remove(handlers, index)
            end
        end
        return connection
    end
    -- Roblox's own one-shot connect. Modules use it for "clean this up when
    -- it ends" work, and a stub without it fails only at runtime.
    function object:Once(callback: any): any
        local connection: any
        connection = object:Connect(function(...: any): ()
            connection:Disconnect()
            callback(...)
        end)
        return connection
    end
    function object:Fire(...: any): ()
        for _, handler: any in ipairs(table.clone(handlers)) do
            handler(...)
        end
    end
    function object:Count(): number
        return #handlers
    end
    return object
end

Mock.signal = signal

-- Instances ----------------------------------------------------------------

local function newInstance(className: string): any
    local instance: any = {
        ClassName = className,
        Name = className,
        Children = {},
        Attributes = {},
        Destroyed = false,
    }
    instance.AncestryChanged = signal()
    -- adoptTree (and anything else that watches a live tree) hangs off
    -- DescendantAdded. Without it a window body that is empty at subscribe
    -- time never adopts the rows built a moment later.
    instance.DescendantAdded = signal()
    instance.DescendantRemoving = signal()
    instance.ChildAdded = signal()
    instance.ChildRemoved = signal()
    -- Roblox's own defaults for anything drawable. Reading an unset property
    -- used to give nil, so a builder doing `control.ZIndex = math.max(
    -- control.ZIndex, ...)` — which is how every option row stacks its
    -- control above its label — failed on arithmetic against nil instead of
    -- being testable.
    if POINTER_CLASSES[className] then
        instance.ZIndex = 1
        instance.Visible = true
        instance.Text = ""
        instance.TextSize = 14
        -- Roblox's own default. The capture translated "Other" because
        -- nobody set this false. Suites assert the product opts out.
        instance.AutoLocalize = true
        instance.TextTransparency = 0
        -- Roblox always answers these; a test that never laid anything out
        -- still gets a rectangle rather than nil, so arithmetic on a size —
        -- which is what clamping a window inside the viewport is — reaches an
        -- assertion instead of a stack trace.
        instance.AbsolutePosition = vector2(0, 0)
        instance.AbsoluteSize = vector2(100, 20)
    end
    if className == "UIListLayout" or className == "UIGridLayout" then
        instance.AbsoluteContentSize = vector2(0, 0)
    end
    if className == "ScrollingFrame" then
        instance.AbsoluteWindowSize = vector2(400, 300)
        instance.AbsolutePosition = vector2(0, 0)
        instance.AbsoluteSize = vector2(400, 300)
    end

    setmetatable(instance, {
        __index = function(self: any, key: string): any
            if key == "Parent" then
                return rawget(self, "_parent")
            end
            local watched: any = rawget(self, "WatchedValues")
            if watched then
                return watched[key]
            end
            return nil
        end,
        __newindex = function(self: any, key: string, value: any): ()
            if key == "Parent" then
                local previous: any = rawget(self, "_parent")
                if previous then
                    local index: number? = table.find(previous.Children, self)
                    if index then
                        table.remove(previous.Children, index)
                    end
                    local function fireRemoved(node: any): ()
                        local ancestor: any = previous
                        while ancestor do
                            local sig: any = rawget(ancestor, "DescendantRemoving")
                            if sig then
                                sig:Fire(node)
                            end
                            ancestor = rawget(ancestor, "_parent")
                        end
                        for _, child: any in ipairs(node.Children) do
                            fireRemoved(child)
                        end
                    end
                    fireRemoved(self)
                    local removed: any = rawget(previous, "ChildRemoved")
                    if removed then
                        removed:Fire(self)
                    end
                end
                rawset(self, "_parent", value)
                if value then
                    table.insert(value.Children, self)
                    local function fireAdded(node: any): ()
                        local ancestor: any = value
                        while ancestor do
                            local sig: any = rawget(ancestor, "DescendantAdded")
                            if sig then
                                sig:Fire(node)
                            end
                            ancestor = rawget(ancestor, "_parent")
                        end
                        for _, child: any in ipairs(node.Children) do
                            fireAdded(child)
                        end
                    end
                    fireAdded(self)
                    local added: any = rawget(value, "ChildAdded")
                    if added then
                        added:Fire(self)
                    end
                end
                return
            end
            -- A watched property is held off the instance itself, because Lua
            -- only calls `__newindex` while the key is absent. Writing it
            -- fires the listener; everything else takes the plain path.
            local watchers: any = rawget(self, "PropertySignals")
            if watchers and watchers[key] then
                rawget(self, "WatchedValues")[key] = value
                watchers[key]:Fire()
                return
            end
            rawset(self, key, value)
        end,
    })

    function instance:GetGuiObjectsAtPosition(_x: number, _y: number): {any}
        return rawget(self, "HitTest") or {}
    end

    function instance:IsA(query: string): boolean
        if self.ClassName == query then
            return true
        end
        if query == "BasePart" then
            return self.ClassName == "Part" or self.ClassName == "MeshPart"
        end
        if query == "GuiObject" then
            return POINTER_CLASSES[self.ClassName] == true
                and self.ClassName ~= "ScreenGui"
        end
        if query == "GuiButton" then
            return self.ClassName == "TextButton" or self.ClassName == "ImageButton"
        end
        if query == "LayerCollector" then
            return self.ClassName == "ScreenGui"
        end
        if query == "Tool" then
            return self.ClassName == "Tool"
        end
        if query == "Player" then
            return self.ClassName == "Player"
        end
        if query == "Model" then
            return self.ClassName == "Model"
        end
        return false
    end

    function instance:FindFirstChild(name: string): any
        for _, child: any in ipairs(self.Children) do
            if child.Name == name then
                return child
            end
        end
        return nil
    end

    function instance:WaitForChild(name: string, _timeout: number?): any
        local child: any = instance:FindFirstChild(name)
        if child then
            return child
        end
        error(name .. " was never added", 0)
    end

    function instance:FindFirstChildWhichIsA(query: string): any
        for _, child: any in ipairs(self.Children) do
            if child:IsA(query) then
                return child
            end
        end
        return nil
    end

    function instance:FindFirstChildOfClass(query: string): any
        for _, child: any in ipairs(self.Children) do
            if child.ClassName == query then
                return child
            end
        end
        return nil
    end

    function instance:FindFirstAncestorOfClass(query: string): any
        local parent: any = self.Parent
        while parent do
            if parent.ClassName == query then
                return parent
            end
            parent = parent.Parent
        end
        return nil
    end

    function instance:GetChildren(): {any}
        return table.clone(self.Children)
    end

    function instance:IsDescendantOf(ancestor: any): boolean
        local parent: any = self.Parent
        while parent do
            if parent == ancestor then
                return true
            end
            parent = parent.Parent
        end
        return false
    end

    function instance:GetPivot(): any
        return rawget(self, "CFrame") or cframe(rawget(self, "Position") or vector3(0, 0, 0))
    end

    function instance:GetDescendants(): {any}
        local result: {any} = {}
        for _, child: any in ipairs(self.Children) do
            table.insert(result, child)
            for _, nested: any in ipairs(child:GetDescendants()) do
                table.insert(result, nested)
            end
        end
        return result
    end

    function instance:GetExtentsSize(): any
        return vector3(4, 5, 2)
    end

    function instance:GetBoundingBox(): (any, any)
        local root: any = self:FindFirstChild("HumanoidRootPart")
        local origin: any = root and rawget(root, "Position") or vector3(0, 0, 0)
        return cframe(origin), vector3(4, 5, 2)
    end

    function instance:SetAttribute(key: string, value: any): ()
        self.Attributes[key] = value
    end

    function instance:GetAttribute(key: string): any
        return self.Attributes[key]
    end

    function instance:Destroy(): ()
        for _, child: any in ipairs(table.clone(self.Children)) do
            child:Destroy()
        end
        self.Parent = nil
        rawset(self, "Destroyed", true)
    end

    -- One signal per property, kept: handing back a fresh one on every call
    -- meant a listener was attached to a signal nothing would ever fire.
    function instance:GetPropertyChangedSignal(property: string): any
        local watchers: any = rawget(self, "PropertySignals")
        if not watchers then
            watchers = {}
            rawset(self, "PropertySignals", watchers)
            rawset(self, "WatchedValues", {})
        end
        local existing: any = watchers[property]
        if not existing then
            rawget(self, "WatchedValues")[property] = rawget(self, property)
            rawset(self, property, nil)
            existing = signal()
            watchers[property] = existing
        end
        return existing
    end

    function instance:Activate(): ()
        rawset(self, "Activations", (rawget(self, "Activations") or 0) + 1)
    end

    -- Buttons carry the signals a tap raises, so a module can be watched
    -- pressing them.
    if className == "TextButton" or className == "ImageButton" then
        instance.MouseButton1Click = signal()
        instance.MouseButton1Down = signal()
        instance.MouseButton1Up = signal()
        instance.MouseButton2Click = signal()
        instance.Activated = signal()
    end
    -- Pointer signals on everything that can be drawn. The widget library
    -- hangs its hover feedback, its slider drags and its "click outside to
    -- close" behaviour off these, so a stand-in without them can build a
    -- control but never operate one.
    if POINTER_CLASSES[className] then
        instance.MouseEnter = signal()
        instance.MouseLeave = signal()
        instance.MouseMoved = signal()
        instance.InputBegan = signal()
        instance.InputChanged = signal()
        instance.InputEnded = signal()
    end
    if className == "TextBox" then
        instance.Focused = signal()
        instance.FocusLost = signal()
        -- Controls that write into their own field have to know whether the
        -- player is mid-edit, or a background refresh overwrites what is
        -- being typed. The harness is never focused unless a test says so.
        function instance:IsFocused(): boolean
            return rawget(self, "Focusing") == true
        end
        function instance:CaptureFocus(): ()
            rawset(self, "Focusing", true)
            self.Focused:Fire()
        end
        function instance:ReleaseFocus(enterPressed: boolean?): ()
            rawset(self, "Focusing", false)
            self.FocusLost:Fire(enterPressed == true)
        end
    end
    if className == "Tool" then
        -- Kill Aura learns which weapon you swing by watching this one.
        instance.Activated = signal()
    end
    if className == "Model" or className == "Backpack" then
        instance.ChildAdded = signal()
    end
    if className == "Part" or className == "MeshPart" then
        -- Roblox answers this on every BasePart, and its default is zero.
        -- The stand-in left it nil, so X-Ray taking `math.max` of it — which
        -- cannot fail on a real client — died on the first loose part in the
        -- world.
        instance.LocalTransparencyModifier = 0
        -- A part always has a size. Hitboxes adds studs to what it finds;
        -- nil here made every suite invent its own starting number.
        instance.Size = vector3(1, 1, 1)
    end
    if className == "Sound" then
        instance.IsPlaying = false
        function instance:Play(): ()
            instance.IsPlaying = true
        end
        function instance:Stop(): ()
            instance.IsPlaying = false
        end
    end
    if className == "Humanoid" then
        -- The session panel counts deaths, and a stand-in humanoid that never
        -- announces one makes that counter untestable.
        instance.Died = signal()
        instance.HealthChanged = signal()
        instance.StateChanged = signal()
    end

    return instance
end

Mock.newInstance = newInstance

-- Globals ------------------------------------------------------------------

-- The globals are handed out as a table rather than written into this file's
-- environment: the Luau CLI sandboxes every module in its own environment, so
-- the only way to give a module file its `Instance`, `Vector3` and `Enum` is to
-- write them into that module's own environment (see `Mock.inject`).
function Mock.install(): MockWorld
    local world: any = {clock = 1000, raycastResult = nil}

    local globals: any = {}

    globals.Instance = {new = newInstance}
    globals.Vector3 = {
        new = vector3,
        zero = vector3(0, 0, 0),
        one = vector3(1, 1, 1),
    }
    globals.Vector2 = {new = vector2, zero = vector2(0, 0)}
    -- Colours carry `ToHSV` because the colour picker converts in both
    -- directions every time a cursor moves, and a stand-in that only stored
    -- RGB would make the picker untestable.
    local function colour(r: number, g: number, b: number): any
        local value: any = {R = r, G = g, B = b, _kind = "Color3"}
        function value:ToHSV(): (number, number, number)
            local high: number = math.max(self.R, self.G, self.B)
            local low: number = math.min(self.R, self.G, self.B)
            local span: number = high - low
            local hue: number = 0
            if span > 0 then
                if high == self.R then
                    hue = ((self.G - self.B) / span) % 6
                elseif high == self.G then
                    hue = (self.B - self.R) / span + 2
                else
                    hue = (self.R - self.G) / span + 4
                end
                hue /= 6
            end
            return hue, high > 0 and span / high or 0, high
        end
        function value:Lerp(other: any, alpha: number): any
            return colour(
                self.R + (other.R - self.R) * alpha,
                self.G + (other.G - self.G) * alpha,
                self.B + (other.B - self.B) * alpha
            )
        end
        return value
    end
    globals.Color3 = {
        new = colour,
        fromRGB = function(r: number, g: number, b: number): any
            return colour(r / 255, g / 255, b / 255)
        end,
        fromHSV = function(h: number, s: number, v: number): any
            local sector: number = (h % 1) * 6
            local index: number = math.floor(sector)
            local fraction: number = sector - index
            local p: number = v * (1 - s)
            local q: number = v * (1 - s * fraction)
            local t: number = v * (1 - s * (1 - fraction))
            local table3: {{number}} = {
                {v, t, p}, {q, v, p}, {p, v, t},
                {p, q, v}, {t, p, v}, {v, p, q},
            }
            local picked: {number} = table3[index + 1] or {v, v, v}
            return colour(picked[1], picked[2], picked[3])
        end,
    }
    globals.ColorSequenceKeypoint = {
        new = function(at: number, value: any): any
            return {Time = at, Value = value}
        end,
    }
    globals.ColorSequence = {
        new = function(first: any, second: any): any
            return {Keypoints = {first, second}}
        end,
    }
    globals.NumberSequenceKeypoint = {
        new = function(at: number, value: number): any
            return {Time = at, Value = value}
        end,
    }
    globals.NumberSequence = {
        new = function(first: any, second: any?): any
            return {Keypoints = {first, second}}
        end,
    }
    globals.TweenInfo = {
        new = function(duration: number, style: any?, direction: any?): any
            return {Time = duration, EasingStyle = style, EasingDirection = direction}
        end,
    }
    globals.UDim = {
        new = function(scale: number, offset: number): any
            return {Scale = scale, Offset = offset}
        end,
    }
    globals.UDim2 = {
        new = function(xs: number, xo: number, ys: number, yo: number): any
            return {X = {Scale = xs, Offset = xo}, Y = {Scale = ys, Offset = yo}}
        end,
        fromOffset = function(x: number, y: number): any
            return {X = {Scale = 0, Offset = x}, Y = {Scale = 0, Offset = y}}
        end,
        fromScale = function(x: number, y: number): any
            return {X = {Scale = x, Offset = 0}, Y = {Scale = y, Offset = 0}}
        end,
    }

    local function enumFolder(names: {string}): any
        local folder: any = {}
        local items: {any} = {}
        for index: number, name: string in ipairs(names) do
            local item: any = {Name = name, Value = index, _kind = "EnumItem"}
            folder[name] = item
            table.insert(items, item)
        end
        function folder:GetEnumItems(): {any}
            return items
        end
        return folder
    end
    globals.Enum = {
        KeyCode = enumFolder({
            "Unknown",
            "Space",
            "LeftControl",
            "RightControl",
            "RightShift",
            "Escape",
            "Backspace",
            "Tab",
            "Return",
            "Up",
            "Down",
            "Left",
            "Right",
            "E",
            "Q",
            "W",
            "A",
            "S",
            "D",
            "ButtonA",
        }),
        RaycastFilterType = enumFolder({"Exclude", "Include"}),
        HighlightDepthMode = enumFolder({"AlwaysOnTop", "Occluded"}),
        TextXAlignment = enumFolder({"Center", "Left", "Right"}),
        TextYAlignment = enumFolder({"Center", "Top", "Bottom"}),
        HumanoidStateType = enumFolder({"Jumping", "Freefall", "Running"}),
        EasingStyle = enumFolder({"Quad", "Sine", "Linear", "Back", "Quart"}),
        EasingDirection = enumFolder({"Out", "In", "InOut"}),
        Material = enumFolder({"Air", "Plastic", "SmoothPlastic"}),
        UserInputType = enumFolder({
            "Touch",
            "MouseButton1",
            "MouseButton2",
            "MouseMovement",
            "Keyboard",
        }),
        ApplyStrokeMode = enumFolder({"Contextual", "Border"}),
        SortOrder = enumFolder({"LayoutOrder", "Name"}),
        ScaleType = enumFolder({"Crop", "Fit", "Stretch"}),
        AnimationPriority = enumFolder({"Action", "Movement", "Idle", "Core"}),
        AutomaticSize = enumFolder({"None", "X", "Y", "XY"}),
        ScrollingDirection = enumFolder({"X", "Y", "XY"}),
        FillDirection = enumFolder({"Horizontal", "Vertical"}),
        HorizontalAlignment = enumFolder({"Left", "Center", "Right"}),
        VerticalAlignment = enumFolder({"Top", "Center", "Bottom"}),
        TextTruncate = enumFolder({"None", "AtEnd", "SplitWord"}),
        AvatarItemType = enumFolder({"Asset", "Bundle"}),
        AvatarAssetType = enumFolder({"EmoteAnimation"}),
        BundleType = enumFolder({"Animations", "BodyParts"}),
        CatalogSortType = enumFolder({"MostFavorited", "Relevance"}),
        Font = enumFolder({
            "Unknown",
            "BuilderSans",
            "SourceSans",
            "Gotham",
            "GothamMedium",
            "GothamSemibold",
            "GothamBold",
            "GothamBlack",
            "Code",
            "Arcade",
        }),
        CameraMode = enumFolder({
            "Classic",
            "LockFirstPerson",
        }),
        FontWeight = enumFolder({
            "Thin",
            "ExtraLight",
            "Light",
            "Regular",
            "Medium",
            "SemiBold",
            "Bold",
            "ExtraBold",
            "Heavy",
        }),
        FontStyle = enumFolder({"Normal", "Italic"}),
        ZIndexBehavior = enumFolder({"Global", "Sibling"}),
        InfoType = enumFolder({"Asset", "Product", "GamePass"}),
        ThumbnailType = enumFolder({"HeadShot", "AvatarBust", "AvatarThumbnail"}),
        ThumbnailSize = enumFolder({"Size48x48", "Size180x180", "Size420x420"}),
    }

    globals.CFrame = {
        new = function(x: any, y: number?, z: number?): any
            if type(x) == "number" then
                return cframe(vector3(x, y or 0, z or 0))
            end
            return cframe(x)
        end,
        lookAt = function(from: any, to: any): any
            local delta: any = to - from
            local magnitude: number = delta.Magnitude
            return cframe(from, magnitude > 0 and delta.Unit or vector3(0, 0, -1))
        end,
        identity = cframe(vector3(0, 0, 0)),
    }
    function CFrameMeta.PointToObjectSpace(self: any, point: any): any
        return point - self.Position
    end

    -- Executor helpers the combat modules reach for.
    globals.getconnections = function(target: any): {any}
        local handlers: {any} = {}
        if type(target) == "table" and type(target.Connect) == "function" then
            table.insert(handlers, {
                Fire = function(): ()
                    target:Fire()
                end,
            })
        end
        return handlers
    end
    globals.firesignal = function(target: any): ()
        if type(target) == "table" and type(target.Fire) == "function" then
            target:Fire()
        end
    end
    globals.mouse1click = function(): ()
        world.mouseClicks = (world.mouseClicks or 0) + 1
    end

    -- Remote logging: the hook is captured so a test can pretend the game
    -- fired one of its own remotes, and writes land in a table rather than on
    -- a disk that does not exist here.
    world.files = {}
    globals.hookmetamethod = function(_target: any, name: string, replacement: any): any
        if name == "__namecall" then
            world.namecallHook = replacement
        end
        return function(): ()
        end
    end
    globals.getnamecallmethod = function(): string
        return world.namecallMethod or "FireServer"
    end
    globals.checkcaller = function(): boolean
        return world.callerIsMenu == true
    end
    globals.writefile = function(path: string, contents: string): ()
        world.files[path] = contents
    end
    globals.isfolder = function(path: string): boolean
        return world.folders ~= nil and world.folders[path] == true
    end
    globals.makefolder = function(path: string): ()
        world.folders = world.folders or {}
        world.folders[path] = true
    end
    globals.setclipboard = function(contents: string): ()
        world.clipboard = contents
    end

    globals.OverlapParams = {
        new = function(): any
            return {FilterType = nil, FilterDescendantsInstances = {}}
        end,
    }

    -- Melee weapons damage through touch events; the mock counts the calls so
    -- a test can prove Kill Aura fired contact on the right parts.
    world.touchFires = 0
    globals.firetouchinterest = function(_handle: any, _part: any, _state: number): ()
        world.touchFires += 1
    end

    globals.RaycastParams = {
        new = function(): any
            return {
                FilterType = nil,
                FilterDescendantsInstances = {},
                IgnoreWater = false,
            }
        end,
    }

    local camera: any = newInstance("Camera")
    camera.CFrame = {
        Position = vector3(0, 5, 0),
        LookVector = vector3(0, 0, -1),
        RightVector = vector3(1, 0, 0),
    }
    camera.ViewportSize = vector2(1280, 720)
    function camera:WorldToViewportPoint(position: any): (any, boolean)
        -- Straight-line projection: enough for the ESP to compute a box, and
        -- deterministic, which a perspective divide would not be. The third
        -- component is depth in front of the lens, exactly like the engine's:
        -- the camera looks down -Z, so depth is the negated world Z.
        local depth: number = -position.Z
        return vector3(640 + position.X * 10, 360 - position.Y * 10, depth),
            depth > 0
    end
    -- Screen space includes the top bar; viewport space does not. Click
    -- Teleport has to use this one, so the mock keeps them distinguishable.
    function camera:ScreenPointToRay(x: number, y: number): any
        world.lastRayCall = "ScreenPointToRay"
        return {
            Origin = self.CFrame.Position,
            Direction = vector3((x - 640) / 640, (396 - y) / 360, -1),
        }
    end
    function camera:ViewportPointToRay(x: number, y: number): any
        world.lastRayCall = "ViewportPointToRay"
        return {
            Origin = self.CFrame.Position,
            Direction = vector3((x - 640) / 640, (360 - y) / 360, -1),
        }
    end

    local mockWorkspace: any = newInstance("Workspace")
    camera.Parent = mockWorkspace
    mockWorkspace.CurrentCamera = camera
    -- The engine always answers this; Anti-Void and Fling do arithmetic on
    -- it without a nil guard because a real client can never see nil here.
    mockWorkspace.FallenPartsDestroyHeight = -500
    -- Item Render keeps its index up to date from these rather than sweeping
    -- the whole workspace.
    mockWorkspace.DescendantAdded = signal()
    mockWorkspace.DescendantRemoving = signal()
    mockWorkspace.Gravity = 196.2
    function mockWorkspace:Raycast(_origin: any, _direction: any, _params: any): any
        return world.raycastResult
    end
    function mockWorkspace:GetPartBoundsInBox(_pivot: any, _size: any, params: any): {any}
        local found: {any} = {}
        for _, instance: any in ipairs(params.FilterDescendantsInstances or {}) do
            for _, child: any in ipairs(instance:GetChildren()) do
                if child.ClassName == "Part" then
                    table.insert(found, child)
                end
            end
        end
        return found
    end

    globals.workspace = mockWorkspace

    -- Services are cached. `GetService` used to hand back a fresh instance on
    -- every call, so two files asking for the same service watched two
    -- different signals and neither ever fired.
    local services: {[string]: any} = {}

    -- Tweens are applied the moment they are played. Nothing in the harness
    -- advances an interpolation, and every property the menu tweens is a
    -- destination the assertions care about, not a path.
    local tweenService: any = newInstance("TweenService")
    world.tweens = 0
    function tweenService:Create(target: any, _info: any, goal: any): any
        local tween: any = {}
        function tween:Play(): ()
            world.tweens += 1
            for key: string, value: any in pairs(goal) do
                target[key] = value
            end
        end
        function tween:Cancel(): () end
        function tween:Pause(): () end
        tween.Completed = signal()
        return tween
    end
    services.TweenService = tweenService
    globals.TweenService = tweenService

    local inputService: any = newInstance("UserInputService")
    inputService.TouchEnabled = false
    inputService.KeyboardEnabled = true
    inputService.MouseEnabled = true
    inputService.GamepadEnabled = false
    inputService.InputBegan = signal()
    inputService.InputChanged = signal()
    inputService.InputEnded = signal()
    inputService.WindowFocusReleased = signal()
    inputService.JumpRequest = signal()
    function inputService:GetFocusedTextBox(): any
        return world.focusedTextBox
    end
    function inputService:IsKeyDown(_key: any): boolean
        return world.keyDown == true
    end
    function inputService:IsMouseButtonPressed(_button: any): boolean
        return world.mouseDown == true
    end
    function inputService:GetMouseLocation(): any
        return vector2(640, 360)
    end
    services.UserInputService = inputService

    local runService: any = newInstance("RunService")
    runService.Heartbeat = signal()
    runService.RenderStepped = signal()
    runService.Stepped = signal()
    services.RunService = runService

    local httpService: any = newInstance("HttpService")
    function httpService:JSONEncode(_value: any): string
        return "{}"
    end
    function httpService:JSONDecode(_text: string): any
        return {}
    end
    services.HttpService = httpService

    local lighting: any = newInstance("Lighting")
    services.Lighting = lighting

    local physics: any = newInstance("PhysicsService")
    function physics:GetRegisteredCollisionGroups(): {any}
        return {}
    end
    services.PhysicsService = physics

    local market: any = newInstance("MarketplaceService")
    function market:GetProductInfo(_id: number, _infoType: any): any
        return {IconImageAssetId = 0}
    end
    services.MarketplaceService = market

    local collectionService: any = newInstance("CollectionService")
    do
        local tagged: {[string]: {any}} = {}
        local added: {[string]: any} = {}
        function collectionService:HasTag(instance: any, tag: string): boolean
            local list: {any} = tagged[tag]
            return list ~= nil and table.find(list, instance) ~= nil
        end
        function collectionService:GetTagged(tag: string): {any}
            return tagged[tag] or {}
        end
        function collectionService:GetInstanceAddedSignal(tag: string): any
            if added[tag] == nil then
                added[tag] = signal()
            end
            return added[tag]
        end
        function collectionService:AddTag(instance: any, tag: string): ()
            tagged[tag] = tagged[tag] or {}
            if table.find(tagged[tag], instance) == nil then
                table.insert(tagged[tag], instance)
                if added[tag] then
                    added[tag]:Fire(instance)
                end
            end
        end
    end
    services.CollectionService = collectionService
    services.Stats = newInstance("Stats")
    services.CoreGui = newInstance("CoreGui")
    services.ReplicatedStorage = newInstance("ReplicatedStorage")

    globals.game = {
        PlaceId = 0,
        GameId = 0,
        JobId = "test",
        GetService = function(_self: any, name: string): any
            local existing: any = services[name]
            if existing then
                return existing
            end
            local created: any = newInstance(name)
            services[name] = created
            return created
        end,
        HttpGet = function(_self: any, _url: any, _cache: any): string
            -- Enough of a module for the shell's loader to accept the
            -- response and call setfenv, which is how the harness captures
            -- `state` without the real downloads.
            return table.concat({
                "--!strict\n",
                "return {\n",
                "    Name = \"Stub\",\n",
                "    PlaceId = 0,\n",
                "    Events = {},\n",
                "    stamp = \"\",\n",
                "    files = {},\n",
                "    widgets = \"src/library/Widgets.luau\",\n",
                "    core = {},\n",
                "    libraries = {},\n",
                "    modules = {},\n",
                "    init = function(_context: any): any\n",
                "        return {}\n",
                "    end,\n",
                "    destroy = function(): ()\n",
                "    end,\n",
                "}\n",
            })
        end,
    }
    world.services = services
    globals.warn = function(...: any): ()
        print("[warn]", ...)
    end
    globals.typeof = function(value: any): string
        local raw: string = type(value)
        if raw == "table" then
            local kind: any = rawget(value, "_kind")
            if kind == "Color3" then
                return "Color3"
            end
            if kind == "Font" then
                return "Font"
            end
            if kind == "EnumItem" then
                return "EnumItem"
            end
            if rawget(value, "ClassName") ~= nil then
                return "Instance"
            end
            local meta: any = getmetatable(value)
            if meta == Vector3Meta then
                return "Vector3"
            end
            if meta == Vector2Meta then
                return "Vector2"
            end
            if meta == CFrameMeta then
                return "CFrame"
            end
        end
        return raw
    end
    globals.Font = {
        new = function(family: any, weight: any?, style: any?): any
            return {
                Family = family,
                Weight = weight,
                Style = style,
                _kind = "Font",
            }
        end,
        fromEnum = function(item: any): any
            return {
                Family = tostring(item and item.Name or "BuilderSans"),
                Weight = globals.Enum.FontWeight.Regular,
                Style = globals.Enum.FontStyle.Normal,
                _kind = "Font",
            }
        end,
    }
    globals.Random = {
        new = function(_seed: number?): any
            local rng: any = {n = 0}
            function rng:NextNumber(lo: number?, hi: number?): number
                rng.n += 1
                local a: number = lo or 0
                local b: number = hi or 1
                return a + (b - a) * ((rng.n % 10) / 10)
            end
            function rng:NextInteger(lo: number, hi: number): number
                return lo
            end
            return rng
        end,
    }
    globals.loadstring = loadstring
    globals.setfenv = setfenv
    globals.debug = debug
    globals.xpcall = xpcall
    globals.rawequal = rawequal
    globals.require = require
    globals.tick = function(): number
        return world.clock
    end
    -- Roblox's settings() surface. Lag Switch holds IncomingReplicationLag
    -- through it; a suite that needs the property absent nils this global.
    local networkSettings: any = newInstance("NetworkSettings")
    networkSettings.IncomingReplicationLag = 0
    world.networkSettings = networkSettings
    globals.settings = function(): any
        return {
            GetService = function(_self: any, name: string): any
                if name ~= "NetworkSettings" then
                    error("settings(): no " .. name, 2)
                end
                return networkSettings
            end,
        }
    end

    globals.task = {
        spawn = function(callback: any, ...: any): ()
            callback(...)
        end,
        -- Deferred work runs immediately here. Modules use `task.defer` for
        -- "once every row exists" passes (hiding the rows a mode does not
        -- use), and a harness that silently skipped those would be testing a
        -- panel the game never shows.
        defer = function(callback: any, ...: any): ()
            callback(...)
        end,
        delay = function(_seconds: number, callback: any, ...: any): ()
            callback(...)
        end,
        -- Honour the duration so a wait-loop against os.clock can actually
        -- expire. The recovery loader spins `task.wait(0.03)` for up to 12s;
        -- a wait that never moved the clock hung that loop forever the
        -- moment a worker left `pending` above zero.
        wait = function(seconds: number?): number
            local delta: number = seconds or 0
            world.clock += delta
            return delta
        end,
    }

    -- Deterministic time: tests advance the clock themselves so a delay can be
    -- asserted rather than slept through. The standard `os` table is frozen,
    -- so the global is replaced with one that falls through to it.
    local standardOs: any = os
    globals.os = setmetatable({
        clock = function(): number
            return world.clock
        end,
    }, {__index = standardOs})
    globals.math = math
    globals.table = table
    globals.string = string
    globals.pairs = pairs
    globals.ipairs = ipairs
    globals.pcall = pcall
    globals.select = select
    globals.type = type
    globals.tostring = tostring
    globals.tonumber = tonumber
    globals.setmetatable = setmetatable
    globals.getmetatable = getmetatable
    globals.rawget = rawget
    globals.rawset = rawset
    globals.print = print
    globals.error = error
    globals.assert = assert
    globals.next = next
    globals.unpack = unpack
    globals.getfenv = getfenv

    -- Players ---------------------------------------------------------------

    local playersService: any = newInstance("Players")
    playersService.PlayerAdded = signal()
    playersService.PlayerRemoving = signal()
    local roster: {any} = {}

    function playersService:GetPlayers(): {any}
        return table.clone(roster)
    end

    -- Avatar descriptions. `world.avatars[userId]` is what
    -- `GetHumanoidDescriptionFromUserId` hands back, so a test can say what a
    -- given user looks like.
    world.avatars = {}
    function playersService:GetHumanoidDescriptionFromUserId(userId: number): any
        local prepared: any = world.avatars[userId]
        if prepared then
            return prepared
        end
        local description: any = newInstance("HumanoidDescription")
        description.IdleAnimation = 0
        description.WalkAnimation = 0
        description.RunAnimation = 0
        description.JumpAnimation = 0
        description.FallAnimation = 0
        description.ClimbAnimation = 0
        description.SwimAnimation = 0
        description.MoodAnimation = 0
        function description:GetEmotes(): any
            return {}
        end
        world.avatars[userId] = description
        return description
    end

    function playersService:GetUserIdFromNameAsync(name: string): number
        return world.userIdsByName and world.userIdsByName[name] or 0
    end

    function playersService:GetPlayerFromCharacter(character: any): any
        for _, player: any in ipairs(roster) do
            if player.Character == character then
                return player
            end
        end
        return nil
    end

    local function buildCharacter(name: string, position: any): any
        local character: any = newInstance("Model")
        character.Name = name
        -- Parented like a real character: the entity library treats an
        -- unparented model as a corpse mid-respawn.
        character.Parent = mockWorkspace
        local humanoid: any = newInstance("Humanoid")
        humanoid.Name = "Humanoid"
        humanoid.Health = 100
        humanoid.MaxHealth = 100
        humanoid.Parent = character
        humanoid.HipHeight = 2
        humanoid.Died = signal()
        humanoid.StateChanged = signal()
        humanoid.HealthChanged = signal()
        humanoid.Jumping = signal()
        humanoid.Seated = signal()
        function humanoid:EquipTool(tool: any): ()
            tool.Parent = character
        end
        -- Appearance, the two calls the disguise and the animation changer
        -- live on. The applied description is remembered so a test can read
        -- back what was worn.
        local worn: any = newInstance("HumanoidDescription")
        for _, field: string in
            ipairs({
                "IdleAnimation",
                "WalkAnimation",
                "RunAnimation",
                "JumpAnimation",
                "FallAnimation",
                "ClimbAnimation",
                "SwimAnimation",
                "MoodAnimation",
            })
        do
            worn[field] = 0
        end
        function worn:GetEmotes(): any
            return {}
        end
        function humanoid:GetAppliedDescription(): any
            return worn
        end
        function humanoid:ApplyDescription(description: any): ()
            worn = description
            humanoid.AppliedDescription = description
        end
        local animator: any = newInstance("Animator")
        animator.Name = "Animator"
        animator.Parent = humanoid
        animator.Tracks = {}
        function animator:LoadAnimation(animation: any): any
            local track: any = newInstance("AnimationTrack")
            track.AnimationId = animation.AnimationId
            track.IsPlaying = false
            track.Looped = false
            track.Stopped = signal()
            function track:Play(): ()
                track.IsPlaying = true
            end
            function track:Stop(): ()
                track.IsPlaying = false
            end
            function track:AdjustSpeed(speed: number): ()
                track.Speed = speed
            end
            table.insert(animator.Tracks, track)
            return track
        end
        function animator:GetPlayingAnimationTracks(): {any}
            local playing: {any} = {}
            for _, track: any in ipairs(animator.Tracks) do
                if track.IsPlaying then
                    table.insert(playing, track)
                end
            end
            return playing
        end
        local root: any = newInstance("Part")
        root.Name = "HumanoidRootPart"
        root.Position = position
        root.CFrame = cframe(position)
        root.AssemblyLinearVelocity = vector3(0, 0, 0)
        root.Parent = character
        local head: any = newInstance("Part")
        head.Name = "Head"
        head.Position = position + vector3(0, 2, 0)
        head.Parent = character
        -- An R15 rig, so the skeleton path has bones to find.
        for _, partName: string in
            ipairs({
                "UpperTorso",
                "LowerTorso",
                "LeftUpperArm",
                "LeftLowerArm",
                "LeftHand",
                "RightUpperArm",
                "RightLowerArm",
                "RightHand",
                "LeftUpperLeg",
                "LeftLowerLeg",
                "LeftFoot",
                "RightUpperLeg",
                "RightLowerLeg",
                "RightFoot",
            })
        do
            local part: any = newInstance("Part")
            part.Name = partName
            part.Position = position
            part.Parent = character
        end
        return character
    end

    local teams: {[string]: any} = {}
    local teamPalette: {[string]: any} = {
        Red = {R = 0.8, G = 0.2, B = 0.2},
        Blue = {R = 0.2, G = 0.4, B = 0.9},
    }
    local function teamNamed(name: string?): any
        if not name then
            return nil
        end
        local existing: any = teams[name]
        if existing then
            return existing
        end
        -- A real Team instance, because that is what the ESP reads for its
        -- team colours.
        local team: any = newInstance("Team")
        team.Name = name
        team.TeamColor = {Color = teamPalette[name] or {R = 1, G = 1, B = 1}}
        teams[name] = team
        return team
    end

    function world.addPlayer(name: string, team: any, position: any): any
        local player: any = newInstance("Player")
        player.Name = name
        player.DisplayName = name
        player.UserId = world.nextUserId or 1
        world.nextUserId = player.UserId + 1
        player.Team = type(team) == "string" and teamNamed(team) or team
        player.Neutral = false
        player.CharacterAdded = signal()
        player.Idled = signal()
        player.Character = buildCharacter(name, position)
        function player:IsFriendsWithAsync(_userId: number): boolean
            return false
        end
        -- Projectile Calibration reads the mouse at init. A stand-in without
        -- this one method is a module that never starts, which is exactly
        -- the class of failure the integration boot now counts.
        function player:GetMouse(): any
            if world.mouse then
                return world.mouse
            end
            local mouse: any = newInstance("Mouse")
            mouse.Hit = cframe(vector3(0, 0, -40))
            world.mouse = mouse
            return mouse
        end
        local backpack: any = newInstance("Backpack")
        backpack.Name = "Backpack"
        backpack.Parent = player
        table.insert(roster, player)
        playersService.PlayerAdded:Fire(player)
        return player
    end

    function world.removePlayer(player: any): ()
        local index: number? = table.find(roster, player)
        if index then
            table.remove(roster, index)
        end
        playersService.PlayerRemoving:Fire(player)
    end

    local localPlayer: any = world.addPlayer("LocalTester", "Blue", vector3(0, 0, 0))
    playersService.LocalPlayer = localPlayer
    services.Players = playersService

    world.players = playersService
    world.localPlayer = localPlayer
    world.camera = camera
    world.workspace = mockWorkspace
    world.vector3 = vector3
    world.vector2 = vector2
    world.globals = globals
    return (world :: any) :: MockWorld
end

-- Give one module file the mocked globals by writing them into the environment
-- of any function it exported. Every function in that file — including the
-- locals it defined before this call — resolves globals through that same
-- table, so one injection covers the whole module.
function Mock.inject(world: any, fn: any): ()
    local environment: any = getfenv(fn)
    for key: string, value: any in pairs(world.globals) do
        environment[key] = value
    end
end

return Mock
