export type Rect = {
    left: number,
    right: number,
    top: number,
    bottom: number,
    width: number,
    height: number,
    centreX: number,
    centreY: number,
}

export type DrawingSet = {
    root: Frame,
    Line: (self: DrawingSet, group: string, index: number, from: Vector2, to: Vector2, thickness: number, colour: Color3) -> (),
    Box: (self: DrawingSet, rect: Rect, mode: string, thickness: number, colour: Color3) -> (),
    Fill: (self: DrawingSet, rect: Rect?, colour: Color3, transparency: number) -> (),
    Label: (self: DrawingSet, slot: string, text: string, at: Vector2, anchorY: number, size: number, colour: Color3, plate: boolean) -> (),
    HideLabel: (self: DrawingSet, slot: string) -> (),
    HideLines: (self: DrawingSet, group: string, first: number, last: number) -> (),
    Bar: (self: DrawingSet, at: Vector2, height: number, fraction: number) -> (),
    HideBar: (self: DrawingSet) -> (),
    Show: (self: DrawingSet, visible: boolean) -> (),
    Highlight: (self: DrawingSet, adornee: Instance?, colour: Color3, fill: number, mode: string) -> (),
    Destroy: (self: DrawingSet) -> (),
}

export type RenderLibrary = {
    Layer: (self: RenderLibrary, name: string) -> Frame,
    Set: (self: RenderLibrary, layer: Frame, key: any) -> DrawingSet,
    Release: (self: RenderLibrary, layer: Frame, key: any) -> (),
    ReleaseAll: (self: RenderLibrary, layer: Frame) -> (),
    Project: (self: RenderLibrary, camera: Camera, position: Vector3) -> Vector2?,
    ModelRect: (self: RenderLibrary, camera: Camera, model: Model) -> Rect?,
    Destroy: (self: RenderLibrary) -> (),
}

local Module = {
    Name = "Render",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: RenderLibrary? = nil

function Module.init(context: any): RenderLibrary
    local host: any = context
    local create: any = host.create
    local screenGui: Instance = host.ScreenGui

    local library: any = {}

    local pools: any = setmetatable({}, {__mode = "k"})

    function library:Layer(name: string): Frame
        local existing: Instance? = screenGui:FindFirstChild(name)
        if existing and existing:IsA("Frame") then
            return existing :: Frame
        end
        local layer: Frame = create("Frame", {
            Parent = screenGui,
            Name = name,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Visible = false,

            ZIndex = 0,
        }) :: Frame
        pools[layer] = {}
        return layer
    end

    local function newSet(layer: Frame, key: any): DrawingSet
        local root: Frame = create("Frame", {
            Parent = layer,
            Name = typeof(key) == "Instance" and (key :: Instance).Name or tostring(key),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 0,
        }) :: Frame

        local set: any = {
            root = root,
            lines = {} :: {[string]: {Frame}},
            labels = {} :: {[string]: TextLabel},
            fill = nil :: Frame?,
            highlight = nil :: Highlight?,
        }

        local function line(group: string, index: number): Frame
            local bucket: {Frame} = set.lines[group]
            if not bucket then
                bucket = {}
                set.lines[group] = bucket
            end
            local existing: Frame? = bucket[index]
            if existing then
                return existing :: Frame
            end
            local frame: Frame = create("Frame", {
                Parent = root,

                Name = group .. tostring(index),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BorderSizePixel = 0,
                Size = UDim2.fromOffset(0, 1),
                Visible = false,
                ZIndex = 1,
            }) :: Frame
            bucket[index] = frame
            return frame
        end

        function set:Line(
            group: string,
            index: number,
            from: Vector2,
            to: Vector2,
            thickness: number,
            colour: Color3
        ): ()
            local frame: Frame = line(group, index)
            local delta: Vector2 = to - from
            local length: number = delta.Magnitude
            if length < 0.5 then
                frame.Visible = false
                return
            end
            frame.Visible = true
            frame.BackgroundColor3 = colour
            frame.Position = UDim2.fromOffset(
                math.round((from.X + to.X) * 0.5),
                math.round((from.Y + to.Y) * 0.5)
            )
            frame.Size = UDim2.fromOffset(math.round(length), thickness)
            frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        end

        function set:HideLines(group: string, first: number, last: number): ()
            local bucket: {Frame}? = set.lines[group]
            if not bucket then
                return
            end
            for index: number = first, last do
                local frame: Frame? = (bucket :: {Frame})[index]
                if frame then
                    (frame :: Frame).Visible = false
                end
            end
        end

        function set:Box(
            rect: Rect,
            mode: string,
            thickness: number,
            colour: Color3
        ): ()
            if mode == "Off" then
                set:HideLines("Box", 1, 8)
                return
            end
            local corners: {Vector2} = {
                Vector2.new(rect.left, rect.top),
                Vector2.new(rect.right, rect.top),
                Vector2.new(rect.right, rect.bottom),
                Vector2.new(rect.left, rect.bottom),
            }
            if mode == "Full" then
                for index: number = 1, 4 do
                    set:Line(
                        "Box",
                        index,
                        corners[index],
                        corners[index % 4 + 1],
                        thickness,
                        colour
                    )
                end
                set:HideLines("Box", 5, 8)
                return
            end
            local segment: number =
                math.max(math.min(rect.width, rect.height) * 0.28, 3)
            local index: number = 1
            for corner: number = 1, 4 do
                local from: Vector2 = corners[corner]
                local nextCorner: Vector2 = corners[corner % 4 + 1]
                local previousCorner: Vector2 = corners[(corner + 2) % 4 + 1]
                set:Line(
                    "Box",
                    index,
                    from,
                    from + (nextCorner - from).Unit * segment,
                    thickness,
                    colour
                )
                set:Line(
                    "Box",
                    index + 1,
                    from,
                    from + (previousCorner - from).Unit * segment,
                    thickness,
                    colour
                )
                index += 2
            end
        end

        function set:Fill(rect: Rect?, colour: Color3, transparency: number): ()
            if not set.fill then
                set.fill = create("Frame", {
                    Parent = root,
                    Name = "BoxFill",
                    BackgroundColor3 = colour,
                    BackgroundTransparency = transparency,
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 0,
                }) :: Frame
            end
            local frame: Frame = set.fill :: Frame
            if not rect then
                frame.Visible = false
                return
            end
            local resolved: Rect = rect :: Rect
            frame.Visible = true
            frame.BackgroundColor3 = colour
            frame.BackgroundTransparency = transparency
            frame.Position =
                UDim2.fromOffset(math.round(resolved.left), math.round(resolved.top))
            frame.Size =
                UDim2.fromOffset(math.round(resolved.width), math.round(resolved.height))
        end

        function set:Label(
            slot: string,
            text: string,
            at: Vector2,
            anchorY: number,
            size: number,
            colour: Color3,
            plate: boolean
        ): ()
            local label: TextLabel? = set.labels[slot]
            if not label then
                label = create("TextLabel", {
                    Parent = root,
                    Name = slot,
                    AnchorPoint = Vector2.new(0.5, anchorY),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Color3.fromRGB(10, 10, 12),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Text = "",
                    TextColor3 = Color3.fromRGB(236, 236, 240),
                    TextSize = size,

                    TextTruncate = Enum.TextTruncate.None,
                    TextXAlignment = Enum.TextXAlignment.Center,
                    TextYAlignment = Enum.TextYAlignment.Center,
                    Visible = false,
                    ZIndex = 2,
                }) :: TextLabel
                create("UIPadding", {
                    Parent = label,
                    PaddingLeft = UDim.new(0, 5),
                    PaddingRight = UDim.new(0, 5),
                })
                create("UICorner", {Parent = label, CornerRadius = UDim.new(0, 3)})
                set.labels[slot] = label
            end
            local resolved: TextLabel = label :: TextLabel
            resolved.Visible = true
            resolved.Text = text
            resolved.TextColor3 = colour
            resolved.TextSize = size
            resolved.BackgroundTransparency = plate and 0.35 or 1
            resolved.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
            resolved.Size = UDim2.fromOffset(0, size + 6)
        end

        function set:HideLabel(slot: string): ()
            local label: TextLabel? = set.labels[slot]
            if label then
                (label :: TextLabel).Visible = false
            end
        end

        function set:Bar(at: Vector2, height: number, fraction: number): ()
            if not set.barTrack then
                set.barTrack = create("Frame", {
                    Parent = root,
                    Name = "HealthTrack",
                    AnchorPoint = Vector2.new(1, 0),
                    BackgroundColor3 = Color3.fromRGB(12, 12, 14),
                    BackgroundTransparency = 0.35,
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 1,
                }) :: Frame
                set.barFill = create("Frame", {
                    Parent = set.barTrack,
                    Name = "HealthFill",
                    AnchorPoint = Vector2.new(0, 1),
                    BackgroundColor3 = Color3.fromRGB(120, 220, 140),
                    BorderSizePixel = 0,
                    Position = UDim2.fromScale(0, 1),
                    Size = UDim2.fromScale(1, 1),
                    ZIndex = 2,
                }) :: Frame
            end
            local track: Frame = set.barTrack :: Frame
            local fill: Frame = set.barFill :: Frame
            local clamped: number = math.clamp(fraction, 0, 1)
            track.Visible = true
            track.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
            track.Size = UDim2.fromOffset(2, math.round(height))
            fill.Size = UDim2.fromScale(1, clamped)
            fill.BackgroundColor3 = Color3.fromRGB(
                math.round(255 * (1 - clamped)),
                math.round(200 * clamped + 40),
                math.round(120 * clamped)
            )
        end

        function set:HideBar(): ()
            if set.barTrack then
                (set.barTrack :: Frame).Visible = false
            end
        end

        function set:Show(visible: boolean): ()
            root.Visible = visible
            if set.highlight then
                (set.highlight :: Highlight).Enabled = visible
            end
        end

        function set:Highlight(
            adornee: Instance?,
            colour: Color3,
            fill: number,
            mode: string
        ): ()
            if not adornee or mode == "Off" then
                if set.highlight then
                    (set.highlight :: Highlight):Destroy()
                    set.highlight = nil
                end
                return
            end
            local highlight: Highlight? = set.highlight
            if not highlight or not (highlight :: Highlight).Parent then
                highlight = create("Highlight", {
                    Parent = adornee,
                    Name = "Wurst_Chams",
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                }) :: Highlight
                set.highlight = highlight
            end
            local resolved: Highlight = highlight :: Highlight
            resolved.Adornee = adornee
            resolved.Parent = adornee
            resolved.Enabled = root.Visible
            resolved.DepthMode = mode == "Occluded"
                    and Enum.HighlightDepthMode.Occluded
                or Enum.HighlightDepthMode.AlwaysOnTop
            resolved.FillColor = colour
            resolved.OutlineColor = colour
            resolved.FillTransparency = mode == "Outline" and 1 or fill
            resolved.OutlineTransparency = 0
        end

        function set:Destroy(): ()
            if set.highlight then
                pcall(function(): ()
                    (set.highlight :: Highlight):Destroy()
                end)
            end
            pcall(function(): ()
                root:Destroy()
            end)
        end

        return (set :: any) :: DrawingSet
    end

    function library:Set(layer: Frame, key: any): DrawingSet
        local pool: any = pools[layer]
        if not pool then
            pool = {}
            pools[layer] = pool
        end
        local existing: any = pool[key]
        if existing then
            return existing
        end
        local set: DrawingSet = newSet(layer, key)
        pool[key] = set
        return set
    end

    function library:Release(layer: Frame, key: any): ()
        local pool: any = pools[layer]
        local set: any = pool and pool[key]
        if not set then
            return
        end
        pool[key] = nil
        set:Destroy()
    end

    function library:ReleaseAll(layer: Frame): ()
        local pool: any = pools[layer]
        if not pool then
            return
        end
        for key: any, set: any in pairs(pool) do
            pool[key] = nil
            set:Destroy()
        end
    end

    function library:Project(camera: Camera, position: Vector3): Vector2?
        -- The host ScreenGui ignores the GUI inset, so drawings live in raw
        -- screen space and WorldToScreenPoint is the matching projection.
        -- Points merely outside the viewport still project so skeleton lines
        -- keep their bearings at the screen edge; only points behind the
        -- camera are rejected.
        local point: Vector3 = camera:WorldToScreenPoint(position)
        if point.Z <= 0 then
            return nil
        end
        return Vector2.new(point.X, point.Y)
    end

    -- Builds a screen rectangle from world sample points. Points behind the
    -- camera are dropped, the rest contribute to the bounds, and the final
    -- rectangle is clamped to the viewport so a target that is merely close
    -- can never produce a box larger than the screen. Models that are fully
    -- off-screen return nil so callers can hide their drawings cleanly.
    local function rectFromPoints(
        camera: Camera,
        viewport: Vector2,
        points: {Vector3},
        minimumAspect: number?
    ): Rect?
        local minimumX: number, minimumY: number = math.huge, math.huge
        local maximumX: number, maximumY: number = -math.huge, -math.huge
        local inFront: number = 0
        for _, position: Vector3 in ipairs(points) do
            local point: Vector3 = camera:WorldToScreenPoint(position)
            if point.Z > 0 then
                inFront += 1
                if point.X < minimumX then minimumX = point.X end
                if point.Y < minimumY then minimumY = point.Y end
                if point.X > maximumX then maximumX = point.X end
                if point.Y > maximumY then maximumY = point.Y end
            end
        end
        if inFront < 2 then
            return nil
        end
        minimumX -= 2
        maximumX += 2
        minimumY -= 2
        maximumY += 2
        local width: number = maximumX - minimumX
        local height: number = maximumY - minimumY
        if minimumAspect and height > 0 and height * minimumAspect > width then
            width = height * minimumAspect
            local centreX: number = (minimumX + maximumX) * 0.5
            minimumX = centreX - width * 0.5
            maximumX = centreX + width * 0.5
        end
        if maximumX < 0 or minimumX > viewport.X
            or maximumY < 0 or minimumY > viewport.Y then
            return nil
        end
        local left: number = math.max(minimumX, 0)
        local right: number = math.min(maximumX, viewport.X)
        local top: number = math.max(minimumY, 0)
        local bottom: number = math.min(maximumY, viewport.Y)
        if right - left < 1 or bottom - top < 1 then
            return nil
        end
        return {
            left = left,
            right = right,
            top = top,
            bottom = bottom,
            width = right - left,
            height = bottom - top,
            centreX = (left + right) * 0.5,
            centreY = (top + bottom) * 0.5,
        }
    end

    function library:ModelRect(camera: Camera, model: Model): Rect?
        if not model.Parent then
            return nil
        end
        local viewport: Vector2 = camera.ViewportSize
        local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? = model:FindFirstChild("HumanoidRootPart") :: BasePart?
            or model.PrimaryPart
        if humanoid and root then
            -- Character rig: measure a handful of body landmarks instead of
            -- walking every part. The head and feet anchor the height, the
            -- four torso landmarks anchor the width at any rotation, and any
            -- landmark that falls behind the camera is simply dropped so the
            -- box degrades gracefully instead of flipping or vanishing.
            local head: BasePart? = model:FindFirstChild("Head") :: BasePart?
            local rootPosition: Vector3 = root.Position
            local topPosition: Vector3 = head
                and (head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.35, 0))
                or (rootPosition + Vector3.new(0, 3, 0))
            local bottomPosition: Vector3 = rootPosition
                - Vector3.new(0, math.max(humanoid.HipHeight + root.Size.Y * 0.5, 2.5), 0)
            local rootCFrame: CFrame = root.CFrame
            return rectFromPoints(camera, viewport, {
                topPosition,
                bottomPosition,
                rootPosition,
                rootCFrame * Vector3.new(1.35, 0, 0),
                rootCFrame * Vector3.new(-1.35, 0, 0),
                rootCFrame * Vector3.new(0, 0, 0.75),
                rootCFrame * Vector3.new(0, 0, -0.75),
            }, 0.38)
        end

        -- Anything without a live humanoid rig: take the engine-side bounding
        -- box and project its eight corners. One engine call and eight
        -- projections, instead of walking and projecting every descendant
        -- part each frame.
        local boundsOk: boolean, boundsCFrame: any, boundsSize: any =
            pcall(model.GetBoundingBox, model)
        if not boundsOk or typeof(boundsSize) ~= "Vector3" or boundsSize.Magnitude <= 0 then
            return nil
        end
        local half: Vector3 = boundsSize * 0.5
        return rectFromPoints(camera, viewport, {
            boundsCFrame * Vector3.new(half.X, half.Y, half.Z),
            boundsCFrame * Vector3.new(-half.X, half.Y, half.Z),
            boundsCFrame * Vector3.new(half.X, -half.Y, half.Z),
            boundsCFrame * Vector3.new(-half.X, -half.Y, half.Z),
            boundsCFrame * Vector3.new(half.X, half.Y, -half.Z),
            boundsCFrame * Vector3.new(-half.X, half.Y, -half.Z),
            boundsCFrame * Vector3.new(half.X, -half.Y, -half.Z),
            boundsCFrame * Vector3.new(-half.X, -half.Y, -half.Z),
        })
    end

    function library:Destroy(): ()
        for layer: any, pool: any in pairs(pools) do
            for key: any, set: any in pairs(pool) do
                pool[key] = nil
                pcall(function(): ()
                    set:Destroy()
                end)
            end
            pcall(function(): ()
                (layer :: Frame):Destroy()
            end)
        end
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = (library :: any) :: RenderLibrary
    Module.Initialized = true
    return (library :: any) :: RenderLibrary
end

function Module.destroy(): ()
    local library: RenderLibrary? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
