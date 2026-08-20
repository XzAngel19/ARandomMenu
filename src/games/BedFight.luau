--!strict
--
-- BedFight (place 71480482338212).
--
-- Everything here is taken from the saved place in `reference/`, not guessed:
--
--   * beds live in `Workspace.BedsContainer`, each a Model with `Mattress`,
--     `BedHitbox` and a `BedLegs` folder;
--   * generators are Parts under `Workspace.<Map>.Generators.<Kind>Generators`,
--     each carrying a `ProgressGui.TimerLabel` with the countdown the game
--     itself draws;
--   * round state is in `ReplicatedStorage.GameInfo` — `Status`, `GameMode`,
--     `AllBedsBroken`, `Map`, and a `DeathBarrierInfo` configuration;
--   * the swing is `PlayerGui.MobileGui.ButtonsFrame.Sword`, whose
--     `MouseButton1Down`/`MouseButton1Click` the game listens on. There is no
--     Tool anywhere in this game.
--
-- What this module deliberately does not do is fire `SwordHit`, `MineBlock`,
-- `PlaceBlock` or `PurchaseItemShopItem` directly: their argument shapes are
-- not in the dump, and a remote called with the wrong arguments is a kick, not
-- a feature. Everything below either reads the world or presses the game's own
-- controls.

local Module = {
    Name = "BedFight",
    PlaceId = 71480482338212,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local runtimeState: any = {
    connections = {} :: {[string]: any},
    bedMarks = {} :: {[Instance]: any},
    generatorMarks = {} :: {[Instance]: any},
    infoPanel = nil :: any,
    voidPanel = nil :: any,
    lastSafe = nil :: Vector3?,
}

-- Beds and generators are placed when the map loads and then stay put, so the
-- world is swept on a timer rather than every frame; the marks themselves are
-- updated every frame from the cached list.
local mapCache: any = {beds = {}, generators = {}, at = -1}

local function clearMarks(store: {[Instance]: any}): ()
    for instance: Instance, mark: any in pairs(store) do
        pcall(function(): ()
            mark:Destroy()
        end)
        store[instance] = nil
    end
end

local function gameInfo(): Instance?
    local replicated: Instance? = game:GetService("ReplicatedStorage")
    return replicated and replicated:FindFirstChild("GameInfo") or nil
end

local function readValue(name: string): any
    local info: Instance? = gameInfo()
    if not info then
        return nil
    end
    local value: Instance? = info:FindFirstChild(name)
    if value and (value:IsA("StringValue") or value:IsA("BoolValue") or value:IsA("NumberValue")) then
        return (value :: any).Value
    end
    return nil
end

-- Beds: the container is fixed, the map folder is not, so both are swept.
local function scanBeds(): {Model}
    local beds: {Model} = {}
    local container: Instance? = workspace:FindFirstChild("BedsContainer")
    if container then
        for _, child: Instance in ipairs(container:GetChildren()) do
            if child:IsA("Model") then
                table.insert(beds, child :: Model)
            end
        end
    end
    for _, descendant: Instance in ipairs(workspace:GetChildren()) do
        local folder: Instance? = descendant:FindFirstChild("Beds")
        if folder then
            for _, child: Instance in ipairs(folder:GetChildren()) do
                if child:IsA("Model") then
                    table.insert(beds, child :: Model)
                end
            end
        end
    end
    return beds
end

local function scanGenerators(): {BasePart}
    local generators: {BasePart} = {}
    for _, mapChild: Instance in ipairs(workspace:GetChildren()) do
        local folder: Instance? = mapChild:FindFirstChild("Generators")
        if not folder then
            continue
        end
        for _, kind: Instance in ipairs(folder:GetChildren()) do
            for _, part: Instance in ipairs(kind:GetChildren()) do
                if part:IsA("BasePart") then
                    table.insert(generators, part :: BasePart)
                end
            end
        end
    end
    return generators
end

local function refreshMap(): ()
    local now: number = os.clock()
    if now - mapCache.at < 2 then
        return
    end
    mapCache.at = now
    mapCache.beds = scanBeds()
    mapCache.generators = scanGenerators()
end

local function collectBeds(): {Model}
    refreshMap()
    return mapCache.beds
end

local function collectGenerators(): {BasePart}
    refreshMap()
    return mapCache.generators
end

local function anchorOf(model: Model): BasePart?
    local hitbox: Instance? = model:FindFirstChild("BedHitbox")
    if hitbox and hitbox:IsA("BasePart") then
        return hitbox :: BasePart
    end
    local mattress: Instance? = model:FindFirstChild("Mattress")
    if mattress and mattress:IsA("BasePart") then
        return mattress :: BasePart
    end
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

function Module.init(runtime: any): any
    local environment: any = getfenv()
    local host: any = environment
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addColorOption: any = host.addColorOption
    local addInformationOption: any = host.addInformationOption
    local create: any = host.create
    local makeTextLabel: any = host.makeTextLabel
    local TaskManager: any = host.TaskManager
    local state: any = host.state
    local LocalPlayer: Player = host.LocalPlayer

    local scroll: any = state.bedFightScroll
    local registry: any = state.bedFightFeatures

    local settings: any = {
        bedColour = Color3.fromRGB(236, 236, 240),
        generatorColour = Color3.fromRGB(150, 220, 255),
        showDistance = true,
        showTimers = true,
        maxDistance = 2000,
    }

    -- Bed ESP ---------------------------------------------------------------
    local function clearBeds(): ()
        clearMarks(runtimeState.bedMarks)
    end

    local function renderBeds(): ()
        local root: BasePart? = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local origin: Vector3 = root and (root :: BasePart).Position or Vector3.zero
        local seen: {[Instance]: boolean} = {}

        for _, bed: Model in ipairs(collectBeds()) do
            local anchor: BasePart? = anchorOf(bed)
            if not anchor then
                continue
            end
            local resolved: BasePart = anchor :: BasePart
            local distance: number = (resolved.Position - origin).Magnitude
            if distance > settings.maxDistance then
                continue
            end
            seen[bed] = true
            local mark: any = runtimeState.bedMarks[bed]
            if not mark or not mark.Parent then
                local billboard: BillboardGui = create("BillboardGui", {
                    Parent = resolved,
                    Name = "RTM_BedMark",
                    AlwaysOnTop = true,
                    LightInfluence = 0,
                    Size = UDim2.fromOffset(150, 22),
                    StudsOffset = Vector3.new(0, 2.4, 0),
                }) :: BillboardGui
                local label: TextLabel = makeTextLabel(billboard, "Bed", 12)
                label.Name = "Label"
                label.Size = UDim2.fromScale(1, 1)
                label.TextXAlignment = Enum.TextXAlignment.Center
                runtimeState.bedMarks[bed] = billboard
                mark = billboard
            end
            local label: TextLabel? = mark:FindFirstChild("Label") :: TextLabel?
            if label then
                label.TextColor3 = settings.bedColour
                label.Text = settings.showDistance
                        and ("Bed  " .. tostring(math.round(distance)) .. "m")
                    or "Bed"
            end
        end

        for bed: Instance, mark: any in pairs(runtimeState.bedMarks) do
            if not seen[bed] or not bed.Parent then
                pcall(function(): ()
                    mark:Destroy()
                end)
                runtimeState.bedMarks[bed] = nil
            end
        end
    end

    local BedFeature: any = createUniversalFeature(
        "Bed ESP",
        "Every bed on the map, with its distance",
        1,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightBeds")
            clearBeds()
            if not enabled then
                return
            end
            host.featureConnections.BedFightBeds =
                TaskManager:Connect(function(): ()
                    renderBeds()
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Visuals"}
    )
    addToggleOption(BedFeature, "Show distance", true, function(value: boolean): ()
        settings.showDistance = value
    end)
    addColorOption(BedFeature, "Colour", settings.bedColour, function(value: Color3): ()
        settings.bedColour = value
    end)
    addNumberOption(
        BedFeature,
        "Max distance",
        settings.maxDistance,
        100,
        5000,
        function(value: number): ()
            settings.maxDistance = value
        end
    )

    -- Generator ESP ---------------------------------------------------------
    local GeneratorFeature: any = createUniversalFeature(
        "Generator ESP",
        "Diamond and emerald generators, with the game's own countdown",
        2,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightGenerators")
            clearMarks(runtimeState.generatorMarks)
            if not enabled then
                return
            end
            host.featureConnections.BedFightGenerators =
                TaskManager:Connect(function(): ()
                    local root: BasePart? = LocalPlayer.Character
                        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    local origin: Vector3 = root and (root :: BasePart).Position or Vector3.zero
                    local seen: {[Instance]: boolean} = {}

                    for _, generator: BasePart in ipairs(collectGenerators()) do
                        local distance: number = (generator.Position - origin).Magnitude
                        if distance > settings.maxDistance then
                            continue
                        end
                        seen[generator] = true
                        local mark: any = runtimeState.generatorMarks[generator]
                        if not mark or not mark.Parent then
                            local billboard: BillboardGui = create("BillboardGui", {
                                Parent = generator,
                                Name = "RTM_GeneratorMark",
                                AlwaysOnTop = true,
                                LightInfluence = 0,
                                Size = UDim2.fromOffset(150, 20),
                                StudsOffset = Vector3.new(0, 3, 0),
                            }) :: BillboardGui
                            local label: TextLabel = makeTextLabel(billboard, "", 11)
                            label.Name = "Label"
                            label.Size = UDim2.fromScale(1, 1)
                            label.TextXAlignment = Enum.TextXAlignment.Center
                            runtimeState.generatorMarks[generator] = billboard
                            mark = billboard
                        end
                        local label: TextLabel? = mark:FindFirstChild("Label") :: TextLabel?
                        if not label then
                            continue
                        end
                        -- The game already renders a countdown above every
                        -- generator; reading it is more honest than timing it
                        -- ourselves and being a second out.
                        local kind: string = generator.Parent
                            and generator.Parent.Name:gsub("Generators", "")
                            or "Generator"
                        local timer: string = ""
                        if settings.showTimers then
                            local progress: Instance? = generator:FindFirstChild("ProgressGui")
                            local timerLabel: Instance? = progress
                                and progress:FindFirstChild("TimerLabel")
                            if timerLabel and timerLabel:IsA("TextLabel") then
                                timer = "  " .. (timerLabel :: TextLabel).Text
                            end
                        end
                        label.TextColor3 = settings.generatorColour
                        label.Text = kind
                            .. (settings.showDistance
                                and ("  " .. tostring(math.round(distance)) .. "m")
                                or "")
                            .. timer
                    end

                    for generator: Instance, mark: any in pairs(runtimeState.generatorMarks) do
                        if not seen[generator] or not generator.Parent then
                            pcall(function(): ()
                                mark:Destroy()
                            end)
                            runtimeState.generatorMarks[generator] = nil
                        end
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Visuals"}
    )
    addToggleOption(GeneratorFeature, "Show timers", true, function(value: boolean): ()
        settings.showTimers = value
    end)
    addColorOption(
        GeneratorFeature,
        "Colour",
        settings.generatorColour,
        function(value: Color3): ()
            settings.generatorColour = value
        end
    )

    -- Round info ------------------------------------------------------------
    local InfoFeature: any = createUniversalFeature(
        "Round Info",
        "Status, mode and whether every bed is gone",
        3,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightInfo")
            if runtimeState.infoPanel then
                pcall(function(): ()
                    runtimeState.infoPanel.root:Destroy()
                end)
                runtimeState.infoPanel = nil
            end
            if not enabled then
                return
            end
            local root: Frame = create("Frame", {
                Parent = host.ScreenGui,
                Name = "BedFightInfo",
                AnchorPoint = Vector2.new(1, 0),
                BackgroundColor3 = Color3.fromRGB(14, 14, 16),
                BackgroundTransparency = 0.15,
                BorderSizePixel = 0,
                Position = UDim2.new(1, -18, 0, 90),
                Size = UDim2.fromOffset(196, 56),
                ZIndex = 60,
            }) :: Frame
            create("UICorner", {Parent = root, CornerRadius = UDim.new(0, 4)})
            create("UIStroke", {
                Parent = root,
                Color = Color3.fromRGB(92, 92, 98),
                Transparency = 0.6,
                Thickness = 1,
            })
            local statusLabel: TextLabel = makeTextLabel(root, "", 12)
            statusLabel.Position = UDim2.fromOffset(10, 8)
            statusLabel.Size = UDim2.new(1, -20, 0, 15)
            statusLabel.ZIndex = 61
            local modeLabel: TextLabel = makeTextLabel(root, "", 10)
            modeLabel.Position = UDim2.fromOffset(10, 24)
            modeLabel.Size = UDim2.new(1, -20, 0, 13)
            modeLabel.TextColor3 = Color3.fromRGB(158, 158, 166)
            modeLabel.ZIndex = 61
            local bedLabel: TextLabel = makeTextLabel(root, "", 10)
            bedLabel.Position = UDim2.fromOffset(10, 38)
            bedLabel.Size = UDim2.new(1, -20, 0, 13)
            bedLabel.TextColor3 = Color3.fromRGB(158, 158, 166)
            bedLabel.ZIndex = 61
            runtimeState.infoPanel = {root = root}

            host.featureConnections.BedFightInfo =
                TaskManager:Connect(function(): ()
                    statusLabel.Text = tostring(readValue("Status") or "—")
                    modeLabel.Text = "Mode: " .. tostring(readValue("GameMode") or "—")
                    local broken: any = readValue("AllBedsBroken")
                    bedLabel.Text = "Beds: "
                        .. (broken == true and "all broken" or "standing")
                        .. "  ·  "
                        .. tostring(#collectBeds())
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Utility"}
    )
    addInformationOption(
        InfoFeature,
        "Read from ReplicatedStorage.GameInfo, which the server keeps current."
    )

    -- Auto swing ------------------------------------------------------------
    local swingSettings: any = {rate = 9}
    local SwingFeature: any = createUniversalFeature(
        "Auto Swing",
        "Presses the game's own sword button on a timer",
        4,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightSwing")
            if not enabled then
                return
            end
            local nextAt: number = 0
            host.featureConnections.BedFightSwing =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 1 / math.max(swingSettings.rate, 0.5)
                    -- This game has no Tool to activate: the swing is the
                    -- touch button, and the weapon library knows how to press
                    -- it exactly as a finger does.
                    local weapons: any = state.weaponLibrary
                    if weapons then
                        weapons:Swing()
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Combat"}
    )
    addNumberOption(
        SwingFeature,
        "Swings per second",
        swingSettings.rate,
        1,
        20,
        function(value: number): ()
            swingSettings.rate = value
        end
    )
    addInformationOption(
        SwingFeature,
        "Equip a weapon first; the button swings whatever is in the hotbar slot."
    )

    -- Bed Nuker -------------------------------------------------------------
    --
    -- The bed is broken by hitting it, and hitting in this game is the touch
    -- button plus the weapon's own contact events — the same pair Kill Aura
    -- uses on players. `MineBlock` is right there in ReplicatedStorage, but its
    -- arguments are not in the dump, so this drives the game's own controls
    -- instead of inventing a call. Turn on the Remote Logger, break one bed by
    -- hand, and the log will say exactly what a future version could send.
    local nukerSettings: any = {range = 24, rate = 12}
    local NukerFeature: any = createUniversalFeature(
        "Bed Nuker",
        "Hits the nearest bed in range as fast as the game allows",
        5,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightNuker")
            if not enabled then
                return
            end
            local nextAt: number = 0
            host.featureConnections.BedFightNuker =
                TaskManager:Connect(function(): ()
                    local character: Model? = LocalPlayer.Character
                    local root: BasePart? = character
                        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not root then
                        return
                    end
                    local resolvedRoot: BasePart = root :: BasePart

                    local target: BasePart? = nil
                    local best: number = nukerSettings.range
                    for _, bed: Model in ipairs(collectBeds()) do
                        local anchor: BasePart? = anchorOf(bed)
                        if not anchor then
                            continue
                        end
                        local distance: number =
                            ((anchor :: BasePart).Position - resolvedRoot.Position).Magnitude
                        if distance < best then
                            target = anchor
                            best = distance
                        end
                    end
                    if not target then
                        return
                    end

                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 1 / math.max(nukerSettings.rate, 0.5)

                    local weapons: any = state.weaponLibrary
                    if weapons then
                        weapons:Swing()
                    end
                    -- Contact as well as the swing: a pickaxe that damages on
                    -- touch never registers from the button alone.
                    local fire: any = environment.firetouchinterest
                    if type(fire) ~= "function" then
                        return
                    end
                    for _, part: Instance in ipairs(character:GetDescendants()) do
                        if not part:IsA("BasePart") then
                            continue
                        end
                        pcall(fire, part, target, 1)
                        pcall(fire, part, target, 0)
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Combat"}
    )
    addNumberOption(
        NukerFeature,
        "Range",
        nukerSettings.range,
        6,
        80,
        function(value: number): ()
            nukerSettings.range = value
        end
    )
    addNumberOption(
        NukerFeature,
        "Hits per second",
        nukerSettings.rate,
        1,
        30,
        function(value: number): ()
            nukerSettings.rate = value
        end
    )
    addInformationOption(
        NukerFeature,
        "Equip the pickaxe first: this presses the game's own controls, so "
            .. "whatever is in your hand is what swings."
    )

    -- Scaffold ----------------------------------------------------------------
    --
    -- Real blocks, not a local platform: this game places a block when you
    -- press its own build control while pointing at where the block should go,
    -- so that is what this does. It equips a block from the hotbar, aims the
    -- camera down behind you, and presses.
    --
    -- The one thing it cannot do yet is call `PlaceBlock` directly — the dump
    -- has the remote but not its arguments. Run the Remote Logger, place one
    -- block by hand, and the log will name them; the call then replaces the
    -- button press with no other change.
    local scaffoldSettings: any = {rate = 6, reach = 6, pitch = true}

    -- Both GUI lookups are cached for a second: they walk the PlayerGui, and
    -- the scaffold asks several times a second.
    local guiCache: any = {at = -1, block = nil, place = nil}

    local function blockSlot(): GuiButton?
        if os.clock() - guiCache.at < 1 then
            return guiCache.block
        end
        local playerGui: Instance? = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil
        end
        -- Hotbar slots are named after the item, and every building block in
        -- this game is wool, planks, stone or their coloured variants.
        local blockWords: {string} = {"wool", "plank", "stone", "wood", "brick", "block"}
        for _, descendant: Instance in ipairs(playerGui:GetDescendants()) do
            if not descendant:IsA("GuiButton") then
                continue
            end
            local lowered: string = string.lower(descendant.Name)
            for _, word: string in ipairs(blockWords) do
                if string.find(lowered, word, 1, true) then
                    guiCache.block = descendant :: GuiButton
                    guiCache.at = os.clock()
                    return guiCache.block
                end
            end
        end
        guiCache.block = nil
        guiCache.at = os.clock()
        return nil
    end

    local function placeControl(): GuiButton?
        if guiCache.place and (guiCache.place :: GuiButton).Parent then
            return guiCache.place
        end
        local playerGui: Instance? = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil
        end
        for _, descendant: Instance in ipairs(playerGui:GetDescendants()) do
            if not descendant:IsA("GuiButton") then
                continue
            end
            local lowered: string = string.lower(descendant.Name)
            if string.find(lowered, "place", 1, true)
                or string.find(lowered, "build", 1, true) then
                guiCache.place = descendant :: GuiButton
                return guiCache.place
            end
        end
        return nil
    end

    local ScaffoldFeature: any = createUniversalFeature(
        "Scaffold",
        "Places the game's own blocks under you while you walk over nothing",
        6,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightScaffold")
            if not enabled then
                return
            end
            local nextAt: number = 0
            host.featureConnections.BedFightScaffold =
                TaskManager:Connect(function(): ()
                    local character: Model? = LocalPlayer.Character
                    local root: BasePart? = character
                        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    local humanoid: Humanoid? = character
                        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                    if not root or not humanoid then
                        return
                    end
                    local resolvedRoot: BasePart = root :: BasePart
                    local resolvedHumanoid: Humanoid = humanoid :: Humanoid

                    -- Only over a gap: placing a block on solid ground is how
                    -- you get a tower you did not ask for.
                    local parameters: RaycastParams = RaycastParams.new()
                    parameters.FilterType = Enum.RaycastFilterType.Exclude
                    parameters.IgnoreWater = true
                    parameters.FilterDescendantsInstances = {character :: any}
                    local below: RaycastResult? = workspace:Raycast(
                        resolvedRoot.Position,
                        Vector3.new(0, -(resolvedHumanoid.HipHeight + scaffoldSettings.reach), 0),
                        parameters
                    )
                    if below then
                        return
                    end

                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 1 / math.max(scaffoldSettings.rate, 0.5)

                    local slot: GuiButton? = blockSlot()
                    local weapons: any = state.weaponLibrary
                    if slot and weapons then
                        -- Equipping is a press of the slot, the same as a tap.
                        weapons:PressButton(slot :: GuiButton)
                    end

                    local camera: Camera? = workspace.CurrentCamera
                    if scaffoldSettings.pitch and camera then
                        -- Look at where the block has to go for the frame the
                        -- placement is fired on, then let the player's own
                        -- camera continue: the game raycasts from the camera.
                        local resolvedCamera: Camera = camera :: Camera
                        local original: CFrame = resolvedCamera.CFrame
                        resolvedCamera.CFrame = CFrame.lookAt(
                            original.Position,
                            resolvedRoot.Position - Vector3.new(0, 4, 0)
                        )
                        task.defer(function(): ()
                            if resolvedCamera.Parent then
                                resolvedCamera.CFrame = original
                            end
                        end)
                    end

                    local control: GuiButton? = placeControl()
                    if control and weapons then
                        weapons:PressButton(control :: GuiButton)
                        return
                    end
                    -- Desktop: placement is the mouse.
                    local click: any = environment.mouse1click
                    if type(click) == "function" then
                        pcall(click)
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Movement"}
    )
    addNumberOption(
        ScaffoldFeature,
        "Blocks per second",
        scaffoldSettings.rate,
        1,
        20,
        function(value: number): ()
            scaffoldSettings.rate = value
        end
    )
    addNumberOption(
        ScaffoldFeature,
        "Gap depth",
        scaffoldSettings.reach,
        2,
        30,
        function(value: number): ()
            scaffoldSettings.reach = value
        end
    )
    addToggleOption(
        ScaffoldFeature,
        "Aim down",
        true,
        function(value: boolean): ()
            scaffoldSettings.pitch = value
        end
    )
    addInformationOption(
        ScaffoldFeature,
        "Uses the game's own hotbar and build control. Log PlaceBlock with the "
            .. "Remote Logger and it can be called directly instead."
    )

    -- Void warning ------------------------------------------------------------
    --
    -- The death barrier is a Configuration in GameInfo with its height and
    -- distance in it, so the warning is the game's own number rather than a
    -- guess about where the map ends.
    local voidSettings: any = {margin = 25, rescue = true}
    local VoidFeature: any = createUniversalFeature(
        "Anti Void",
        "Catches you before the map's own kill plane does",
        7,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightVoid")
            if runtimeState.voidPanel then
                pcall(function(): ()
                    runtimeState.voidPanel:Destroy()
                end)
                runtimeState.voidPanel = nil
            end
            if not enabled then
                return
            end
            local warning: Frame = create("Frame", {
                Parent = host.ScreenGui,
                Name = "BedFightVoidWarning",
                AnchorPoint = Vector2.new(0.5, 0),
                BackgroundColor3 = Color3.fromRGB(18, 14, 14),
                BackgroundTransparency = 0.1,
                BorderSizePixel = 0,
                Position = UDim2.new(0.5, 0, 0, 74),
                Size = UDim2.fromOffset(210, 26),
                Visible = false,
                ZIndex = 62,
            }) :: Frame
            create("UICorner", {Parent = warning, CornerRadius = UDim.new(0, 4)})
            local label: TextLabel = makeTextLabel(warning, "", 12)
            label.Size = UDim2.fromScale(1, 1)
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextColor3 = Color3.fromRGB(232, 160, 160)
            label.ZIndex = 63
            runtimeState.voidPanel = warning

            host.featureConnections.BedFightVoid =
                TaskManager:Connect(function(): ()
                    local info: Instance? = gameInfo()
                    local barrier: Instance? = info
                        and info:FindFirstChild("DeathBarrierInfo")
                    local heightValue: Instance? = barrier
                        and barrier:FindFirstChild("MaxHeight")
                    local root: BasePart? = LocalPlayer.Character
                        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not root or not heightValue or not heightValue:IsA("NumberValue") then
                        warning.Visible = false
                        return
                    end
                    local resolvedRoot: BasePart = root :: BasePart
                    local floor: number = (heightValue :: NumberValue).Value
                    local drop: number = resolvedRoot.Position.Y - floor

                    -- Remember the last place the ground held: that is where a
                    -- rescue puts you back, rather than somewhere arbitrary.
                    local parameters: RaycastParams = RaycastParams.new()
                    parameters.FilterType = Enum.RaycastFilterType.Exclude
                    parameters.IgnoreWater = true
                    parameters.FilterDescendantsInstances = {LocalPlayer.Character :: any}
                    local ground: RaycastResult? = workspace:Raycast(
                        resolvedRoot.Position,
                        Vector3.new(0, -12, 0),
                        parameters
                    )
                    if ground then
                        runtimeState.lastSafe = resolvedRoot.Position
                    end

                    warning.Visible = drop < voidSettings.margin * 2
                    if warning.Visible then
                        label.Text = "Void in " .. tostring(math.round(drop)) .. " studs"
                    end

                    if not voidSettings.rescue or drop > voidSettings.margin then
                        return
                    end
                    -- Past the margin with nothing under you: stop the fall and
                    -- put the character back where the ground last was.
                    resolvedRoot.AssemblyLinearVelocity = Vector3.zero
                    if runtimeState.lastSafe then
                        resolvedRoot.CFrame =
                            CFrame.new(runtimeState.lastSafe + Vector3.new(0, 4, 0))
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Protection"}
    )
    addNumberOption(
        VoidFeature,
        "Rescue margin",
        voidSettings.margin,
        5,
        120,
        function(value: number): ()
            voidSettings.margin = value
        end
    )
    addToggleOption(VoidFeature, "Rescue", true, function(value: boolean): ()
        voidSettings.rescue = value
    end)
    addInformationOption(
        VoidFeature,
        "The kill height comes from GameInfo.DeathBarrierInfo, so the margin is "
            .. "measured against the game's own plane."
    )

    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    local environment: any = getfenv()
    local host: any = environment
    for _, name: string in
        ipairs({
            "BedFightBeds",
            "BedFightGenerators",
            "BedFightInfo",
            "BedFightSwing",
            "BedFightNuker",
            "BedFightVoid",
            "BedFightScaffold",
        })
    do
        if host.disconnectFeatureConnection then
            pcall(host.disconnectFeatureConnection, name)
        end
    end
    clearMarks(runtimeState.bedMarks)
    clearMarks(runtimeState.generatorMarks)
    if runtimeState.infoPanel then
        pcall(function(): ()
            runtimeState.infoPanel.root:Destroy()
        end)
        runtimeState.infoPanel = nil
    end
    if runtimeState.voidPanel then
        pcall(function(): ()
            runtimeState.voidPanel:Destroy()
        end)
        runtimeState.voidPanel = nil
    end
    Module.Initialized = false
end

return Module
