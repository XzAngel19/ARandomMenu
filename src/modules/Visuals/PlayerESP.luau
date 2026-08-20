--!strict
--
-- Player ESP.
--
-- One module, one drawing pass, one pool of instances per player. Everything
-- it can draw — box, skeleton, name, health, distance, held tool, tracer and
-- chams — is an independent switch, because "ESP" in most menus means a single
-- box you cannot turn off and a name you cannot move.
--
-- The overlay is built from ordinary GuiObjects instead of the executor
-- `Drawing` API: Drawing is missing or partially implemented on a lot of
-- executors, and a Frame rotated to fit two screen points draws the same line
-- everywhere.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "PlayerESP",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

type Drawings = {
    root: Frame,
    box: {Frame},
    skeleton: {Frame},
    tracer: Frame,
    healthTrack: Frame,
    healthFill: Frame,
    name: TextLabel,
    details: TextLabel,
    highlight: Highlight?,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local create: any = host.create
    local players: Players = host.Players

    local container: Frame = create("Frame", {
        Parent = host.ScreenGui,
        Name = "PlayerEspLayer",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        -- Behind every panel the menu draws: the overlay is world information,
        -- not interface, and must never cover a control.
        ZIndex = 0,
    }) :: Frame

    local pool: {[Player]: Drawings} = {}
    local accumulator: number = 0

    local esp: any
    esp = framework.Categories.Visuals:CreateModule({
        Name = "Player ESP",
        Category = "Visuals",
        Order = 1,
        Tooltip = "Boxes, skeletons, name tags, health, tracers and chams, "
            .. "each independently switchable.",
        Function = function(enabled: boolean): ()
            container.Visible = enabled
            if not enabled then
                for player: Player in pairs(pool) do
                    Module.release(pool, player)
                end
                return
            end
            esp:Loop(function(deltaTime: number): ()
                accumulator += deltaTime
                local interval: number = esp.Options["Refresh interval"].Value
                if accumulator < interval then
                    return
                end
                accumulator = 0
                Module.render(context, container, pool, esp)
            end)
            esp:Event(players.PlayerRemoving, function(player: Player): ()
                Module.release(pool, player)
            end)
            esp:Clean(function(): ()
                for player: Player in pairs(pool) do
                    Module.release(pool, player)
                end
                container.Visible = false
            end)
        end,
    })

    esp:CreateSection("Display")
    esp:CreateDropdown({
        Name = "Boxes",
        List = {"Corner", "Full", "Off"},
        Index = 1,
        Tooltip = "Corner draws four brackets, Full draws the whole rectangle.",
    })
    esp:CreateSlider({
        Name = "Box thickness",
        Min = 1,
        Max = 5,
        Default = 1,
    })
    esp:CreateToggle({
        Name = "Skeleton",
        Default = false,
        Tooltip = "Draw the rig's bones. Works on both R6 and R15.",
    })
    esp:CreateToggle({
        Name = "Name tags",
        Default = true,
        Tooltip = "Display name above the box.",
    })
    esp:CreateToggle({
        Name = "Health bar",
        Default = true,
        Tooltip = "Vertical bar on the left edge of the box.",
    })
    esp:CreateToggle({
        Name = "Health text",
        Default = false,
        Tooltip = "Print the exact hit points next to the name.",
    })
    esp:CreateToggle({
        Name = "Distance",
        Default = true,
        Tooltip = "Studs between you and the target.",
    })
    esp:CreateToggle({
        Name = "Held tool",
        Default = false,
        Tooltip = "Name of whatever the target currently has equipped.",
    })
    esp:CreateDropdown({
        Name = "Tracers",
        List = {"Off", "Bottom", "Centre", "Cursor"},
        Index = 1,
        Tooltip = "Where the line to each target starts.",
    })
    esp:CreateDropdown({
        Name = "Chams",
        List = {"Off", "Overlay", "Outline"},
        Index = 1,
        Tooltip = "Overlay fills the body through walls, Outline only rims it.",
    })

    esp:CreateSection("Filters")
    esp:CreateToggle({
        Name = "Team check",
        Default = false,
        Tooltip = "Skip players on your own team.",
    })
    esp:CreateToggle({
        Name = "Visibility check",
        Default = false,
        Tooltip = "Recolour targets that are behind geometry.",
    })
    esp:CreateSlider({
        Name = "Max distance",
        Min = 50,
        Max = 5000,
        Default = 2000,
    })

    esp:CreateSection("Style")
    esp:CreateToggle({
        Name = "Team colours",
        Default = true,
        Tooltip = "Draw each player in their own team's colour. Falls back to "
            .. "the colours below for teamless games.",
    })
    esp:CreateToggle({
        Name = "Name plate",
        Default = true,
        Tooltip = "Put the name on a dark plate so it stays readable against "
            .. "a bright map.",
    })
    esp:CreateColor({
        Name = "Enemy colour",
        Default = Color3.fromRGB(236, 236, 240),
    })
    esp:CreateColor({
        Name = "Friendly colour",
        Default = Color3.fromRGB(120, 190, 255),
    })
    esp:CreateColor({
        Name = "Hidden colour",
        Default = Color3.fromRGB(150, 150, 158),
    })
    esp:CreateSlider({
        Name = "Text size",
        Min = 8,
        Max = 24,
        Default = 13,
    })
    esp:CreateSlider({
        Name = "Refresh interval",
        Min = 0,
        Max = 0.2,
        Default = 0,
        Tooltip = "Seconds between redraws. 0 redraws every frame.",
    })

    activeCleanup = function(): ()
        for player: Player in pairs(pool) do
            Module.release(pool, player)
        end
        container:Destroy()
    end
    Module.Initialized = true
    return esp
end

-- Instance pool. A player keeps the same drawings for as long as they are in
-- the server, so a frame costs property writes rather than allocations.
function Module.acquire(
    host: any,
    container: Frame,
    pool: {[Player]: any},
    player: Player
): any
    local existing: any = pool[player]
    if existing then
        return existing
    end
    local create: any = host.create
    local root: Frame = create("Frame", {
        Parent = container,
        Name = player.Name,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 0,
    }) :: Frame

    local function line(name: string): Frame
        return create("Frame", {
            Parent = root,
            Name = name,
            AnchorPoint = Vector2.new(0.5, 0.5),
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(0, 1),
            Visible = false,
            ZIndex = 1,
        }) :: Frame
    end

    local box: {Frame} = {}
    -- Eight segments: four sides for Full, and the same eight halves reused as
    -- the brackets in Corner mode.
    for index: number = 1, 8 do
        box[index] = line("Box" .. tostring(index))
    end

    local skeleton: {Frame} = {}
    for index: number = 1, 14 do
        skeleton[index] = line("Bone" .. tostring(index))
    end

    local healthTrack: Frame = create("Frame", {
        Parent = root,
        Name = "HealthTrack",
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = Color3.fromRGB(12, 12, 14),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 1,
    }) :: Frame
    local healthFill: Frame = create("Frame", {
        Parent = healthTrack,
        Name = "HealthFill",
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = Color3.fromRGB(120, 220, 140),
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2,
    }) :: Frame

    local nameLabel: TextLabel = host.makeTextLabel(root, player.DisplayName, 13)
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Name = "NameTag"
    host.create("UICorner", {Parent = nameLabel, CornerRadius = UDim.new(0, 3)})
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Visible = false
    nameLabel.ZIndex = 2

    local detailsLabel: TextLabel = host.makeTextLabel(root, "", 12)
    detailsLabel.AnchorPoint = Vector2.new(0.5, 0)
    detailsLabel.Name = "Details"
    detailsLabel.TextXAlignment = Enum.TextXAlignment.Center
    detailsLabel.Visible = false
    detailsLabel.ZIndex = 2

    local drawings: any = {
        root = root,
        box = box,
        skeleton = skeleton,
        tracer = line("Tracer"),
        healthTrack = healthTrack,
        healthFill = healthFill,
        name = nameLabel,
        details = detailsLabel,
        highlight = nil,
    }
    pool[player] = drawings
    return drawings
end

function Module.release(pool: {[Player]: any}, player: Player): ()
    local drawings: any = pool[player]
    if not drawings then
        return
    end
    pool[player] = nil
    if drawings.highlight then
        pcall(function(): ()
            drawings.highlight:Destroy()
        end)
    end
    pcall(function(): ()
        drawings.root:Destroy()
    end)
end

-- Draw a line between two screen points by rotating a 1px frame onto them.
local function drawLine(
    frame: Frame,
    from: Vector2,
    to: Vector2,
    thickness: number,
    colour: Color3
): ()
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

local function hideAll(frames: {Frame}): ()
    for _, frame: Frame in ipairs(frames) do
        frame.Visible = false
    end
end

function Module.render(
    context: Runtime,
    container: Frame,
    pool: {[Player]: any},
    esp: any
): ()
    local host: any = context.host
    local entityLibrary: any = context.entity
    local currentWorkspace: Workspace = host.workspace or workspace
    local camera: Camera? = currentWorkspace.CurrentCamera
    if not camera then
        return
    end
    local resolvedCamera: Camera = camera :: Camera
    local options: any = esp.Options
    local viewport: Vector2 = resolvedCamera.ViewportSize

    entityLibrary:Refresh()
    local seen: {[Player]: boolean} = {}

    for _, entity: any in ipairs(entityLibrary.List) do
        local player: Player = entity.Player
        if options["Team check"].Value and entity.IsFriendly then
            continue
        end
        if entity.Distance > options["Max distance"].Value then
            continue
        end

        local rootPosition: Vector3 = entity.RootPart.Position
        local screenPoint: Vector3, onScreen: boolean =
            resolvedCamera:WorldToViewportPoint(rootPosition)
        if not onScreen then
            continue
        end

        seen[player] = true
        local drawings: any = Module.acquire(host, container, pool, player)

        local visible: boolean = not options["Visibility check"].Value
            or entityLibrary:VisibleFrom(entity)
        local colour: Color3 = entity.IsFriendly
                and options["Friendly colour"].Value
            or (visible and options["Enemy colour"].Value
                or options["Hidden colour"].Value)
        -- A team game already colour-codes itself; borrowing that is both
        -- prettier and more informative than two greys.
        if options["Team colours"].Value and entity.Team then
            -- Read defensively: `Team` is a Team instance in a normal game,
            -- but plenty of games hang their own value off the player, and a
            -- missing TeamColor must dim the ESP, not stop it.
            local teamOk: boolean, teamColour: any = pcall(function(): Color3
                return (entity.Team :: any).TeamColor.Color
            end)
            if teamOk and typeof(teamColour) == "Color3" then
                colour = visible
                    and teamColour
                    or (teamColour :: Color3):Lerp(Color3.new(0, 0, 0), 0.45)
            end
        end

        -- Box geometry from the character's own extents, so a crouching or
        -- oversized rig gets a box that actually fits it.
        local extents: Vector3 = entity.Character:GetExtentsSize()
        local topPoint: Vector3 =
            resolvedCamera:WorldToViewportPoint(rootPosition + Vector3.new(0, extents.Y * 0.5 + 0.4, 0))
        local bottomPoint: Vector3 =
            resolvedCamera:WorldToViewportPoint(rootPosition - Vector3.new(0, extents.Y * 0.5, 0))
        local height: number = math.abs(bottomPoint.Y - topPoint.Y)
        local width: number = math.max(height * 0.52, 6)
        local centreX: number = screenPoint.X
        local top: number = math.min(topPoint.Y, bottomPoint.Y)
        local left: number = centreX - width * 0.5
        local right: number = centreX + width * 0.5
        local bottom: number = top + height

        local thickness: number = math.round(options["Box thickness"].Value)
        local boxMode: string = options["Boxes"].Value
        local corners: {Vector2} = {
            Vector2.new(left, top),
            Vector2.new(right, top),
            Vector2.new(right, bottom),
            Vector2.new(left, bottom),
        }
        if boxMode == "Off" then
            hideAll(drawings.box)
        elseif boxMode == "Full" then
            for index: number = 1, 4 do
                drawLine(
                    drawings.box[index],
                    corners[index],
                    corners[index % 4 + 1],
                    thickness,
                    colour
                )
            end
            for index: number = 5, 8 do
                drawings.box[index].Visible = false
            end
        else
            -- Corner brackets: a quarter of each side, drawn from both ends.
            local segment: number = math.max(math.min(width, height) * 0.28, 3)
            local index: number = 1
            for corner: number = 1, 4 do
                local from: Vector2 = corners[corner]
                local nextCorner: Vector2 = corners[corner % 4 + 1]
                local previousCorner: Vector2 = corners[(corner + 2) % 4 + 1]
                drawLine(
                    drawings.box[index],
                    from,
                    from + (nextCorner - from).Unit * segment,
                    thickness,
                    colour
                )
                drawLine(
                    drawings.box[index + 1],
                    from,
                    from + (previousCorner - from).Unit * segment,
                    thickness,
                    colour
                )
                index += 2
            end
        end

        -- Skeleton.
        if options["Skeleton"].Value then
            local bones: {{BasePart}} = entityLibrary:Rig(entity)
            for index: number = 1, #drawings.skeleton do
                local pair: {BasePart}? = bones[index]
                if not pair then
                    drawings.skeleton[index].Visible = false
                    continue
                end
                local first: Vector3, firstVisible: boolean =
                    resolvedCamera:WorldToViewportPoint(pair[1].Position)
                local second: Vector3, secondVisible: boolean =
                    resolvedCamera:WorldToViewportPoint(pair[2].Position)
                if firstVisible and secondVisible then
                    drawLine(
                        drawings.skeleton[index],
                        Vector2.new(first.X, first.Y),
                        Vector2.new(second.X, second.Y),
                        1,
                        colour
                    )
                else
                    drawings.skeleton[index].Visible = false
                end
            end
        else
            hideAll(drawings.skeleton)
        end

        -- Health bar, pinned to the left edge so it never overlaps the name.
        if options["Health bar"].Value then
            local fraction: number = math.clamp(entity.Health / entity.MaxHealth, 0, 1)
            drawings.healthTrack.Visible = true
            drawings.healthTrack.Position = UDim2.fromOffset(
                math.round(left - 4),
                math.round(top)
            )
            drawings.healthTrack.Size = UDim2.fromOffset(2, math.round(height))
            drawings.healthFill.Size = UDim2.fromScale(1, fraction)
            drawings.healthFill.BackgroundColor3 = Color3.fromRGB(
                math.round(255 * (1 - fraction)),
                math.round(200 * fraction + 40),
                math.round(120 * fraction)
            )
        else
            drawings.healthTrack.Visible = false
        end

        -- Name tag and the details line under the box.
        local textSize: number = math.round(options["Text size"].Value)
        if options["Name tags"].Value then
            drawings.name.Visible = true
            drawings.name.Text = player.DisplayName
            drawings.name.TextColor3 = colour
            drawings.name.TextSize = textSize
            drawings.name.Position = UDim2.fromOffset(
                math.round(centreX),
                math.round(top - 3)
            )
            drawings.name.Size = UDim2.fromOffset(math.max(width * 3, 120), textSize + 4)
            -- The plate is what keeps a name readable over snow, sand or a
            -- lit sky; without it ESP text disappears half the map.
            drawings.name.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
            drawings.name.BackgroundTransparency =
                options["Name plate"].Value and 0.35 or 1
        else
            drawings.name.Visible = false
        end

        local details: {string} = {}
        if options["Distance"].Value then
            table.insert(details, tostring(math.round(entity.Distance)) .. "m")
        end
        if options["Health text"].Value then
            table.insert(
                details,
                tostring(math.round(entity.Health))
                    .. "/"
                    .. tostring(math.round(entity.MaxHealth))
            )
        end
        if options["Held tool"].Value then
            local tool: Instance? = entity.Character:FindFirstChildOfClass("Tool")
            if tool then
                table.insert(details, tool.Name)
            end
        end
        if #details > 0 then
            drawings.details.Visible = true
            drawings.details.Text = table.concat(details, "  ")
            drawings.details.TextColor3 = colour
            drawings.details.TextSize = math.max(textSize - 2, 8)
            drawings.details.Position = UDim2.fromOffset(
                math.round(centreX),
                math.round(bottom + 2)
            )
            drawings.details.Size = UDim2.fromOffset(math.max(width * 3, 120), textSize)
        else
            drawings.details.Visible = false
        end

        -- Tracer.
        local tracerMode: string = options["Tracers"].Value
        if tracerMode == "Off" then
            drawings.tracer.Visible = false
        else
            local origin: Vector2
            if tracerMode == "Bottom" then
                origin = Vector2.new(viewport.X * 0.5, viewport.Y)
            elseif tracerMode == "Centre" then
                origin = viewport * 0.5
            else
                local pointer: Vector2 = host.UserInputService:GetMouseLocation()
                origin = pointer
            end
            drawLine(
                drawings.tracer,
                origin,
                Vector2.new(centreX, bottom),
                1,
                colour
            )
        end

        -- Chams. `Highlight` is a native class, so it works on every executor
        -- and survives the character being re-parented.
        local chamsMode: string = options["Chams"].Value
        if chamsMode == "Off" then
            if drawings.highlight then
                drawings.highlight:Destroy()
                drawings.highlight = nil
            end
        else
            local highlight: Highlight? = drawings.highlight
            if not highlight or not highlight.Parent then
                highlight = Instance.new("Highlight")
                highlight.Name = "RTM_Chams"
                highlight.Parent = entity.Character
                drawings.highlight = highlight
            end
            local resolvedHighlight: Highlight = highlight :: Highlight
            resolvedHighlight.Adornee = entity.Character
            resolvedHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            resolvedHighlight.FillColor = colour
            resolvedHighlight.OutlineColor = colour
            resolvedHighlight.FillTransparency = chamsMode == "Outline" and 1 or 0.55
            resolvedHighlight.OutlineTransparency = 0
        end
    end

    for player: Player in pairs(pool) do
        if not seen[player] then
            Module.release(pool, player)
        end
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
