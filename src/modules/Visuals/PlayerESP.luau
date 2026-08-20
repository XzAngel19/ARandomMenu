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
    local visibilityCache: any = setmetatable({}, {__mode = "k"})

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
                Module.render(context, container, pool, esp, visibilityCache)
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
        Name = "Filled box",
        Default = false,
        Tooltip = "Wash the inside of the box in the target's colour. Reads "
            .. "at a glance across a map; noisy in a crowd.",
    })
    esp:CreateToggle({
        Name = "Skeleton",
        Default = false,
        Tooltip = "Draw the rig's bones. Works on both R6 and R15.",
    })
    esp:CreateToggle({
        Name = "Name tags",
        Default = true,
        Tooltip = "The player's name above the box.",
    })
    esp:CreateToggle({
        Name = "Display name",
        Default = true,
        Tooltip = "Show the display name rather than the account name.",
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
    -- One colour, not three.
    --
    -- "Enemy", "friendly" and "hidden" were three rows to answer one question,
    -- and two of them were unreachable in half the games this runs in: a game
    -- with roles never draws a "friendly", and a game without a visibility
    -- check never draws a "hidden". There is one colour now; a target behind
    -- geometry is the same colour darkened, and a team game or a game with
    -- roles overrides it per player.
    esp:CreateColor({
        Name = "Colour",
        Default = Color3.fromRGB(236, 236, 240),
        Tooltip = "Used for every target the game gives no colour of its own.",
    })
    esp:CreateToggle({
        Name = "Team colours",
        Default = true,
        Tooltip = "Draw each player in their own team's colour where the game "
            .. "has teams.",
    })
    esp:CreateToggle({
        Name = "Name plate",
        Default = true,
        Tooltip = "Put the name on a dark plate so it stays readable against "
            .. "a bright map.",
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
        Default = 0.03,
        Tooltip = "Seconds between redraws. 0 redraws every frame, which no "
            .. "display needs and every frame budget notices.",
    })

    -- What the game adds.
    --
    -- Roles and per-game objects are not built into this module: the game
    -- module registers them through the shared bridge and the rows appear
    -- here, in the one ESP card, so a role colour works with corner boxes,
    -- full boxes, chams, tracers and name tags at the same time. In a game
    -- nobody wrote a module for, none of these rows exist.
    local extraRuntime: any = {
        roles = nil :: any,
        extras = {} :: {any},
        sections = {roles = false, world = false},
    }
    Module.bridge = extraRuntime

    local function addRoleRows(provider: any): ()
        if extraRuntime.roles then
            return
        end
        extraRuntime.roles = provider
        -- A game that names its roles has already answered everything the
        -- generic rows were asking. In MM2 there are no teams to check, the
        -- murderer is not "an enemy" and nobody is "friendly": leaving those
        -- rows on screen is four controls that do nothing next to the ones
        -- that do. They are hidden, not deleted, so switching games (or a
        -- module reload) brings them back.
        for _, redundant: string in
            ipairs({"Team check", "Visibility check", "Team colours", "Colour"})
        do
            local row: any = esp.Options[redundant]
            if row then
                pcall(function(): ()
                    row:SetVisible(false)
                end)
            end
        end
        if not extraRuntime.sections.roles then
            extraRuntime.sections.roles = true
            esp:CreateSection("Roles · " .. tostring(provider.Name or "Game"))
        end
        esp:CreateToggle({
            Name = "Role colours",
            Default = true,
            Tooltip = "Colour every drawing by what the player is in this "
                .. "game instead of by team.",
        })
        esp:CreateToggle({
            Name = "Show role",
            Default = true,
            Tooltip = "Print the role next to the name.",
        })
        for _, roleName: string in ipairs(provider.Roles or {}) do
            esp:CreateColor({
                Name = roleName .. " colour",
                Default = (provider.Colors or {})[roleName]
                    or Color3.fromRGB(236, 236, 240),
                Function = function(value: Color3): ()
                    -- The game module keeps its own copy so its own drawing
                    -- (a marker, a cham it manages) matches the ESP.
                    if type(provider.SetColor) == "function" then
                        pcall(provider.SetColor, roleName, value)
                    end
                end,
            })
        end
    end

    local function addExtraRows(extra: any): ()
        if not extraRuntime.sections.world then
            extraRuntime.sections.world = true
            esp:CreateSection("World")
        end
        table.insert(extraRuntime.extras, extra)
        esp:CreateToggle({
            Name = extra.Name,
            Default = extra.Default == true,
            Tooltip = extra.Tooltip,
            Function = function(value: boolean): ()
                if type(extra.Toggle) == "function" then
                    pcall(extra.Toggle, value)
                end
            end,
        })
        if extra.Color then
            esp:CreateColor({
                Name = extra.Name .. " colour",
                Default = extra.Color,
                Function = function(value: Color3): ()
                    if type(extra.SetColor) == "function" then
                        pcall(extra.SetColor, value)
                    end
                end,
            })
        end
        -- An extra keeps whatever tuning it had as a card of its own — a
        -- distance, a fill, a switch — so folding it in here costs the player
        -- nothing. The rows are prefixed with the object's name because two
        -- games can both want to call something "Max distance".
        for _, definition: any in ipairs(extra.Options or {}) do
            local rowName: string = extra.Name .. " " .. definition.Name
            if definition.Kind == "toggle" then
                esp:CreateToggle({
                    Name = rowName,
                    Default = definition.Default == true,
                    Tooltip = definition.Tooltip,
                    Function = function(value: boolean): ()
                        if type(definition.Set) == "function" then
                            pcall(definition.Set, value)
                        end
                    end,
                })
            else
                esp:CreateSlider({
                    Name = rowName,
                    Min = definition.Min or 0,
                    Max = definition.Max or 100,
                    Default = definition.Default or definition.Min or 0,
                    Tooltip = definition.Tooltip,
                    Function = function(value: number): ()
                        if type(definition.Set) == "function" then
                            pcall(definition.Set, value)
                        end
                    end,
                })
            end
        end
    end

    if host.state and type(host.state.onGameBridge) == "function" then
        host.state.onGameBridge(function(kind: string, payload: any): ()
            if kind == "roles" then
                addRoleRows(payload)
            elseif kind == "extra" then
                addExtraRows(payload)
            end
        end)
    end

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

    -- Behind the box lines and behind the labels: a wash, not a panel.
    local fill: Frame = create("Frame", {
        Parent = root,
        Name = "BoxFill",
        BackgroundColor3 = Color3.fromRGB(236, 236, 240),
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 0,
    }) :: Frame

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

    -- The overlay owns its own labels.
    --
    -- They used to come from the menu's text helper, which registers a label
    -- with the interface's text-scale system: that multiplies every size by
    -- 1.35, re-applies it on every layout pass and re-fits it to its box, all
    -- behind the module's back. A name tag the ESP had sized at 13 came out
    -- several times bigger, and the plate behind it was three times the width
    -- of the box because it was sized from the box instead of from the text.
    --
    -- These are plain instances nothing else touches, and the plate is sized
    -- by the text itself: AutomaticSize on X plus five pixels of padding, so
    -- the tag is exactly as wide as the name in it.
    local function espLabel(name: string, size: number, anchorY: number): TextLabel
        local label: TextLabel = create("TextLabel", {
            Parent = root,
            Name = name,
            AnchorPoint = Vector2.new(0.5, anchorY),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Color3.fromRGB(10, 10, 12),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            TextColor3 = Color3.fromRGB(236, 236, 240),
            TextSize = size,
            -- Nothing to truncate: the box grows to the text rather than the
            -- text being cut to the box.
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
        return label
    end

    local nameLabel: TextLabel = espLabel("NameTag", 13, 1)
    local detailsLabel: TextLabel = espLabel("Details", 12, 0)

    local drawings: any = {
        root = root,
        fill = fill,
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
    esp: any,
    visibilityCache: any
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
            -- Cheapest possible rejection, before any projection, raycast or
            -- instance lookup happens for this player.
            continue
        end

        -- Geometry, properly. The old box took the character's extents, dropped
        -- two points through WorldToViewportPoint and made the width a fixed
        -- fraction of the height: a rig with its arms out, a camera at an
        -- angle, or a target near the edge of the screen all produced a box
        -- that was the wrong shape, and a corner behind the camera projects to
        -- a huge negative coordinate, which is where the sudden stretching
        -- came from. This projects all eight corners of the model's own
        -- bounding box and takes the extremes, skipping the target entirely if
        -- any corner is behind the lens.
        local boundsCFrame: CFrame, boundsSize: Vector3 =
            entity.Character:GetBoundingBox()
        local half: Vector3 = boundsSize * 0.5
        local minimumX: number = math.huge
        local minimumY: number = math.huge
        local maximumX: number = -math.huge
        local maximumY: number = -math.huge
        local anyVisible: boolean = false
        local behindCamera: boolean = false

        for cornerIndex: number = 0, 7 do
            local corner: Vector3 = boundsCFrame * Vector3.new(
                (cornerIndex % 2 == 0) and -half.X or half.X,
                (math.floor(cornerIndex / 2) % 2 == 0) and -half.Y or half.Y,
                (math.floor(cornerIndex / 4) % 2 == 0) and -half.Z or half.Z
            )
            local projected: Vector3, visible: boolean =
                resolvedCamera:WorldToViewportPoint(corner)
            if projected.Z <= 0 then
                behindCamera = true
                break
            end
            anyVisible = anyVisible or visible
            minimumX = math.min(minimumX, projected.X)
            minimumY = math.min(minimumY, projected.Y)
            maximumX = math.max(maximumX, projected.X)
            maximumY = math.max(maximumY, projected.Y)
        end
        if behindCamera or not anyVisible then
            continue
        end

        seen[player] = true
        local drawings: any = Module.acquire(host, container, pool, player)

        -- One raycast per player per frame is what turns ESP into a frame-rate
        -- problem in a full server, so the answer is cached briefly. Nobody
        -- can see a tenth of a second of staleness in a colour.
        local visible: boolean = true
        if options["Visibility check"].Value then
            local cache: any = visibilityCache[player]
            local now: number = os.clock()
            if not cache or now - cache.at > 0.12 then
                cache = {at = now, value = entityLibrary:VisibleFrom(entity)}
                visibilityCache[player] = cache
            end
            visible = cache.value
        end
        local colour: Color3 = options["Colour"].Value
        -- A role beats a team: in a game with roles, "murderer" is the fact
        -- the colour is there to carry, and the team is usually meaningless.
        local role: string? = nil
        if host.state and type(host.state.playerRole) == "function" then
            role = host.state.playerRole(player)
        end
        local roleOption: any = role and options[role .. " colour"] or nil
        local useRoleColour: boolean = roleOption ~= nil
            and options["Role colours"] ~= nil
            and options["Role colours"].Value == true
        if useRoleColour then
            colour = roleOption.Value
        end
        -- A team game already colour-codes itself; borrowing that is both
        -- prettier and more informative than one grey.
        if not useRoleColour and options["Team colours"].Value and entity.Team then
            -- Read defensively: `Team` is a Team instance in a normal game,
            -- but plenty of games hang their own value off the player, and a
            -- missing TeamColor must dim the ESP, not stop it.
            local teamOk: boolean, teamColour: any = pcall(function(): Color3
                return (entity.Team :: any).TeamColor.Color
            end)
            if teamOk and typeof(teamColour) == "Color3" then
                colour = teamColour
            end
        end
        -- One rule for "behind something", whatever the colour came from.
        if not visible then
            colour = colour:Lerp(Color3.new(0, 0, 0), 0.45)
        end

        -- The box is the projected bounding box, padded a little so it frames
        -- the character instead of cutting into it.
        local padding: number = 2
        local left: number = minimumX - padding
        local right: number = maximumX + padding
        local top: number = minimumY - padding
        local bottom: number = maximumY + padding
        local width: number = math.max(right - left, 4)
        local height: number = math.max(bottom - top, 6)
        local centreX: number = (left + right) * 0.5
        -- Two ways a projected box goes wrong, and both used to leave the
        -- last frame's drawings on screen: a target off the edge (a name
        -- floating in a corner) and a target standing inside the camera, whose
        -- eight corners spread across a box the size of a city. Hiding the set
        -- is the answer to both — releasing it would rebuild every instance
        -- the moment the target came back.
        drawings.root.Visible = true
        if right < 0 or left > viewport.X or bottom < 0 or top > viewport.Y then
            drawings.root.Visible = false
            continue
        end
        if width > viewport.X * 2.5 or height > viewport.Y * 2.5 then
            drawings.root.Visible = false
            continue
        end

        local thickness: number = math.round(options["Box thickness"].Value)
        local boxMode: string = options["Boxes"].Value
        if options["Filled box"].Value and boxMode ~= "Off" then
            drawings.fill.Visible = true
            drawings.fill.BackgroundColor3 = colour
            drawings.fill.Position =
                UDim2.fromOffset(math.round(left), math.round(top))
            drawings.fill.Size =
                UDim2.fromOffset(math.round(width), math.round(height))
        else
            drawings.fill.Visible = false
        end
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
            local shown: string = options["Display name"].Value
                and player.DisplayName
                or player.Name
            drawings.name.Text = (role
                    and options["Show role"] ~= nil
                    and options["Show role"].Value)
                and (shown .. "  [" .. (role :: string) .. "]")
                or shown
            drawings.name.TextColor3 = colour
            drawings.name.TextSize = textSize
            drawings.name.Position = UDim2.fromOffset(
                math.round(centreX),
                math.round(top - 3)
            )
            -- Width is the text's business (AutomaticSize.X); only the line
            -- height is set here.
            drawings.name.Size = UDim2.fromOffset(0, textSize + 6)
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
            drawings.details.BackgroundTransparency =
                options["Name plate"].Value and 0.45 or 1
            drawings.details.Position = UDim2.fromOffset(
                math.round(centreX),
                math.round(bottom + 2)
            )
            drawings.details.Size =
                UDim2.fromOffset(0, math.max(textSize - 2, 8) + 6)
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
