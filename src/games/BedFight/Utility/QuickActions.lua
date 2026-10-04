local Module = {
    Name = "BedFight Quick Actions",
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

local mapCache: any = {beds = {}, generators = {}, at = -1}

local function clearMarks(store: {[Instance]: any}): ()
    for instance: Instance, mark: any in pairs(store) do
        pcall(function(): ()
            mark:Destroy()
        end)
        store[instance] = nil
    end
end

local remoteCache: any = {}

local function remote(path: string): Instance?
    local cached: any = remoteCache[path]
    if cached and cached.Parent then
        return cached
    end
    local replicated: Instance? = game:GetService("ReplicatedStorage")
    local current: Instance? = replicated and replicated:FindFirstChild("Remotes")
    if not current then
        return nil
    end
    for segment: string in string.gmatch(path, "[^%.]+") do
        current = current and current:FindFirstChild(segment)
        if not current then
            return nil
        end
    end
    remoteCache[path] = current
    return current
end

local function fireRemote(path: string, ...: any): boolean
    local target: Instance? = remote(path)
    if not target then
        return false
    end
    local arguments: {any} = table.pack(...)
    return pcall(function(): ()
        (target :: any):FireServer(table.unpack(arguments, 1, arguments.n))
    end)
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

    local registerEspExtra: any = host.registerEspExtra
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption
    local create: any = host.create
    local makeTextLabel: any = host.makeTextLabel
    local TaskManager: any = host.TaskManager
    local state: any = host.state
    local LocalPlayer: Player = host.LocalPlayer
    local selectedFeature: string = 'Quick Actions'
    local rawCreateFeature: any = createUniversalFeature
    local rawRegisterEsp: any = registerEspExtra
    local rawAddToggle: any = addToggleOption
    local rawAddNumber: any = addNumberOption
    local rawAddText: any = addTextOption
    local rawAddInformation: any = addInformationOption
    local rawAddAction: any = host.addActionOption
    createUniversalFeature = function(featureName: string, ...: any): any
        if featureName ~= selectedFeature then return {__skip = true} end
        return rawCreateFeature(featureName, ...)
    end
    registerEspExtra = function(definition: any): any
        if definition.Name ~= selectedFeature then return nil end
        return rawRegisterEsp(definition)
    end
    addToggleOption = function(feature: any, ...: any): any
        if feature.__skip then return nil end
        return rawAddToggle(feature, ...)
    end
    addNumberOption = function(feature: any, ...: any): any
        if feature.__skip then return nil end
        return rawAddNumber(feature, ...)
    end
    addTextOption = function(feature: any, ...: any): any
        if feature.__skip then return nil end
        return rawAddText(feature, ...)
    end
    addInformationOption = function(feature: any, ...: any): any
        if feature.__skip then return nil end
        return rawAddInformation(feature, ...)
    end
    host.addActionOption = function(feature: any, ...: any): any
        if feature.__skip then return nil end
        return rawAddAction(feature, ...)
    end

    local scroll: any = state.bedFightScroll
    local registry: any = state.bedFightFeatures

    local auraSettings: any = {

        range = 20,
        rate = 8,
        weapon = "",
        teamCheck = false,
        maxTargets = 3,
    }
    local placeSettings: any = {
        block = "",
        variant = 3,
        grid = 3,
        rate = 8,
        ahead = 1,
    }

    local function equippedWeaponName(): string
        if auraSettings.weapon ~= "" then
            return auraSettings.weapon
        end
        local camera: Camera? = workspace.CurrentCamera
        local viewModel: Instance? = camera and camera:FindFirstChild("ViewModel")
        if viewModel then
            for _, child: Instance in ipairs(viewModel:GetChildren()) do
                if child:IsA("Model") or child:IsA("BasePart") then
                    return child.Name
                end
            end
        end
        return "Wooden Sword"
    end

    local function characterOf(player: Player): Model?
        local container: Instance? = workspace:FindFirstChild("PlayersContainer")
        local named: Instance? = container and container:FindFirstChild(player.Name)
        if named and named:IsA("Model") then
            return named :: Model
        end
        return player.Character
    end

    local settings: any = {
        bedColour = Color3.fromRGB(236, 236, 240),
        generatorColour = Color3.fromRGB(150, 220, 255),
        showDistance = true,
        showTimers = true,
        maxDistance = 2000,
    }

    local function clearBeds(): ()
        clearMarks(runtimeState.bedMarks)
    end

    local function renderLibrary(): any
        return state.renderLibrary
    end

    local function worldLayer(name: string): Frame?
        local library: any = renderLibrary()
        if not library then
            return nil
        end
        return library:Layer(name)
    end

    local function renderBeds(): ()
        local library: any = renderLibrary()
        local layer: Frame? = worldLayer("BedFightEspLayer")
        local camera: Camera? = workspace.CurrentCamera
        if not library or not layer or not camera then
            return
        end
        local resolvedLayer: Frame = layer :: Frame
        resolvedLayer.Visible = true
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
            local projected: Vector2? = library:Project(camera :: Camera, resolved.Position)
            if not projected then
                continue
            end
            seen[bed] = true
            runtimeState.bedMarks[bed] = true
            local drawings: any = library:Set(resolvedLayer, bed)
            drawings:Show(true)
            drawings:Label(
                "NameTag",
                settings.showDistance
                        and ("Bed  " .. tostring(math.round(distance)) .. "m")
                    or "Bed",
                projected :: Vector2,
                0.5,
                12,
                settings.bedColour,
                true
            )
        end

        for bed: Instance in pairs(runtimeState.bedMarks) do
            if not seen[bed] or not bed.Parent then
                library:Release(resolvedLayer, bed)
                runtimeState.bedMarks[bed] = nil
            end
        end
    end

    local function setBedEsp(enabled: boolean): ()
        host.disconnectFeatureConnection("BedFightBeds")
        clearBeds()
        local library: any = renderLibrary()
        local layer: Frame? = worldLayer("BedFightEspLayer")
        if library and layer and not enabled then
            library:ReleaseAll(layer)
            layer.Visible = false
        end
        if not enabled then
            return
        end
        host.featureConnections.BedFightBeds =
            TaskManager:Connect(function(): ()
                renderBeds()
            end)
    end

    registerEspExtra({
        Name = "Beds",
        Default = false,
        Color = settings.bedColour,
        Tooltip = "Every bed on the map, through walls.",
        Toggle = setBedEsp,
        SetColor = function(value: Color3): ()
            settings.bedColour = value
        end,
        Options = {
            {
                Kind = "toggle",
                Name = "distance",
                Default = true,
                Set = function(value: boolean): ()
                    settings.showDistance = value
                end,
            },
            {
                Kind = "number",
                Name = "max distance",
                Default = settings.maxDistance,
                Min = 100,
                Max = 5000,
                Set = function(value: number): ()
                    settings.maxDistance = value
                end,
            },
        },
    })

    local function setGeneratorEsp(enabled: boolean): ()
        host.disconnectFeatureConnection("BedFightGenerators")
        local library: any = renderLibrary()
        local layer: Frame? = worldLayer("BedFightEspLayer")
        if library and layer then
            for generator: Instance in pairs(runtimeState.generatorMarks) do
                library:Release(layer, generator)
            end
        end
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
                            Name = "Wurst_GeneratorMark",
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
    end

    registerEspExtra({
        Name = "Generators",
        Default = false,
        Color = settings.generatorColour,
        Tooltip = "Diamond and emerald generators, with the game's own "
            .. "countdown.",
        Toggle = setGeneratorEsp,
        SetColor = function(value: Color3): ()
            settings.generatorColour = value
        end,
        Options = {
            {
                Kind = "toggle",
                Name = "timers",
                Default = true,
                Set = function(value: boolean): ()
                    settings.showTimers = value
                end,
            },
        },
    })


    local nukerSettings: any = {
        range = 18,
        rate = 8,
        serverHit = false,
        mine = false,
    }
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

                    if nukerSettings.serverHit then
                        local owner: Instance? = (target :: BasePart)
                            :FindFirstAncestorOfClass("Model")
                        if owner then
                            fireRemote(
                                "ItemsRemotes.SwordHit",
                                owner,
                                equippedWeaponName()
                            )
                        end
                    end
                    if nukerSettings.mine then

                        local origin: BasePart? = character
                            and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                        if origin then
                            local from: Vector3 = (origin :: BasePart).Position
                            local to: Vector3 = (target :: BasePart).Position
                            local heading: Vector3 = to - from
                            heading = heading.Magnitude > 0.001
                                and heading.Unit
                                or Vector3.new(0, -1, 0)
                            fireRemote(
                                "ItemsRemotes.MineBlock",
                                "Wooden Pickaxe",
                                target,
                                Vector3.new(
                                    math.round(to.X),
                                    math.round(to.Y),
                                    math.round(to.Z)
                                ),
                                from,
                                heading
                            )
                        end
                    end

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
        20,
        function(value: number): ()
            nukerSettings.rate = value
        end
    )
    addToggleOption(NukerFeature, "Server hit", false, function(value: boolean): ()
        nukerSettings.serverHit = value
    end)
    addToggleOption(NukerFeature, "Mine remote", false, function(value: boolean): ()
        nukerSettings.mine = value
    end)
    addInformationOption(
        NukerFeature,
        "Safe band: 18 studs and under ten hits a second. This presses the "
            .. "game's own controls, so whatever is in your hand is what "
            .. "swings; the two remote paths are opt-in and the server may or "
            .. "may not accept either for a bed."
    )

    local scaffoldSettings: any = {rate = 6, reach = 6, variant = 3}

    local guiCache: any = {at = -1, block = nil}

    local function blockSlot(): GuiButton?
        if os.clock() - guiCache.at < 1 then
            return guiCache.block
        end
        local playerGui: Instance? = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil
        end

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

    local function scaffoldBlockName(): string
        local camera: Camera? = workspace.CurrentCamera
        local viewModel: Instance? = camera and camera:FindFirstChild("ViewModel")
        if viewModel then
            for _, child: Instance in ipairs(viewModel:GetChildren()) do
                local name: string = string.lower(child.Name)
                if string.find(name, "wool", 1, true)
                    or string.find(name, "plank", 1, true)
                    or string.find(name, "block", 1, true) then
                    return child.Name
                end
            end
        end
        local slot: GuiButton? = blockSlot()
        if slot then
            return slot.Name
        end
        return "Wool"
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

                        weapons:PressButton(slot :: GuiButton)
                    end

                    local grid: number = 3
                    local base: Vector3 = resolvedRoot.Position
                        - Vector3.new(0, resolvedHumanoid.HipHeight + 1, 0)
                    fireRemote(
                        "ItemsRemotes.PlaceBlock",
                        scaffoldBlockName(),
                        scaffoldSettings.variant,
                        Vector3.new(
                            math.floor(base.X / grid + 0.5) * grid,
                            math.floor(base.Y / grid + 0.5) * grid,
                            math.floor(base.Z / grid + 0.5) * grid
                        )
                    )
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
    addNumberOption(
        ScaffoldFeature,
        "Variant",
        scaffoldSettings.variant,
        0,
        12,
        function(value: number): ()
            scaffoldSettings.variant = value
        end
    )
    addInformationOption(
        ScaffoldFeature,
        "Fires PlaceBlock as captured: block name, hotbar slot (3 and 5 in the "
            .. "logs), world position. Variant is that slot. Server Scaffold is "
            .. "the same remote with tiles ahead and a typed block name."
    )

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

                    resolvedRoot.AssemblyLinearVelocity = Vector3.zero
                    if runtimeState.lastSafe then
                        resolvedRoot.CFrame =
                            CFrame.new(runtimeState.lastSafe + Vector3.new(0, 4, 0))
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Movement"}
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

    local ServerAuraFeature: any = createUniversalFeature(
        "Server Aura",
        "Reports hits straight to the server, no swing needed",
        8,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightServerAura")
            if not enabled then
                return
            end
            local nextAt: number = 0
            host.featureConnections.BedFightServerAura =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 1 / math.max(auraSettings.rate, 0.5)

                    local root: BasePart? = LocalPlayer.Character
                        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not root then
                        return
                    end
                    local origin: Vector3 = (root :: BasePart).Position
                    local weapon: string = equippedWeaponName()
                    local sent: number = 0

                    for _, player: Player in ipairs(host.Players:GetPlayers()) do
                        if player == LocalPlayer then
                            continue
                        end
                        if sent >= math.round(auraSettings.maxTargets) then
                            break
                        end
                        if auraSettings.teamCheck
                            and player.Team ~= nil
                            and player.Team == LocalPlayer.Team then
                            continue
                        end
                        local targets: any = runtime.Services.protectedTargets
                        if targets.isProtected(player) then
                            continue
                        end
                        local character: Model? = characterOf(player)
                        local victimRoot: Instance? = character
                            and character:FindFirstChild("HumanoidRootPart")
                        local humanoid: Instance? = character
                            and character:FindFirstChildOfClass("Humanoid")
                        if not character or not victimRoot or not humanoid then
                            continue
                        end
                        if (humanoid :: Humanoid).Health <= 0 then
                            continue
                        end
                        if ((victimRoot :: BasePart).Position - origin).Magnitude
                            > auraSettings.range then
                            continue
                        end
                        fireRemote("ItemsRemotes.SwordHit", character, weapon)
                        sent += 1
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Combat"}
    )
    addNumberOption(ServerAuraFeature, "Range", auraSettings.range, 5, 40, function(value: number): ()
        auraSettings.range = value
    end)
    addNumberOption(ServerAuraFeature, "Hits per second", auraSettings.rate, 1, 20, function(value: number): ()
        auraSettings.rate = value
    end)
    addNumberOption(ServerAuraFeature, "Max targets", auraSettings.maxTargets, 1, 12, function(value: number): ()
        auraSettings.maxTargets = value
    end)
    addToggleOption(ServerAuraFeature, "Team check", false, function(value: boolean): ()
        auraSettings.teamCheck = value
    end)
    addTextOption(ServerAuraFeature, "Weapon name", "", function(value: string): ()
        auraSettings.weapon = value
    end)
    addInformationOption(
        ServerAuraFeature,
        "Safe band: 20-28 studs of range and single-digit hits per second. "
            .. "Past 28 studs no legitimate swing could have reached, and that "
            .. "is what gets accounts collected in a ban wave. Leave the weapon "
            .. "empty and it reads whichever view model you hold; the Friend "
            .. "List is respected."
    )

    local function equippedBlockName(): string
        if placeSettings.block ~= "" then
            return placeSettings.block
        end

        local camera: Camera? = workspace.CurrentCamera
        local viewModel: Instance? = camera and camera:FindFirstChild("ViewModel")
        if viewModel then
            for _, child: Instance in ipairs(viewModel:GetChildren()) do
                local name: string = string.lower(child.Name)
                if string.find(name, "wool", 1, true)
                    or string.find(name, "plank", 1, true)
                    or string.find(name, "block", 1, true) then
                    return child.Name
                end
            end
        end
        return "Wool"
    end

    local function snap(value: number, grid: number): number
        return math.floor(value / grid + 0.5) * grid
    end

    local ServerScaffoldFeature: any = createUniversalFeature(
        "Server Scaffold",
        "Places real blocks under and ahead of you through the game's remote",
        9,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightServerScaffold")
            if not enabled then
                return
            end
            local nextAt: number = 0
            host.featureConnections.BedFightServerScaffold =
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

                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end

                    local parameters: RaycastParams = RaycastParams.new()
                    parameters.FilterType = Enum.RaycastFilterType.Exclude
                    parameters.IgnoreWater = true
                    parameters.FilterDescendantsInstances = {character :: any}
                    local drop: number = resolvedHumanoid.HipHeight + placeSettings.grid + 1
                    local below: RaycastResult? = workspace:Raycast(
                        resolvedRoot.Position,
                        Vector3.new(0, -drop, 0),
                        parameters
                    )
                    if below then
                        return
                    end
                    nextAt = now + 1 / math.max(placeSettings.rate, 0.5)

                    local grid: number = placeSettings.grid
                    local block: string = equippedBlockName()
                    local base: Vector3 = resolvedRoot.Position
                        - Vector3.new(0, resolvedHumanoid.HipHeight + 1, 0)

                    local heading: Vector3 = resolvedHumanoid.MoveDirection
                    if heading.Magnitude < 0.05 then
                        heading = resolvedRoot.CFrame.LookVector
                    end
                    heading = Vector3.new(heading.X, 0, heading.Z)
                    if heading.Magnitude > 0.05 then
                        heading = heading.Unit
                    else
                        heading = Vector3.zero
                    end

                    for step: number = 0, math.round(placeSettings.ahead) do
                        local spot: Vector3 = base + heading * (grid * step)
                        fireRemote(
                            "ItemsRemotes.PlaceBlock",
                            block,
                            placeSettings.variant,
                            Vector3.new(
                                snap(spot.X, grid),
                                snap(spot.Y, grid),
                                snap(spot.Z, grid)
                            )
                        )
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Movement"}
    )
    addNumberOption(ServerScaffoldFeature, "Blocks per second", placeSettings.rate, 1, 20, function(value: number): ()
        placeSettings.rate = value
    end)
    addNumberOption(ServerScaffoldFeature, "Tiles ahead", placeSettings.ahead, 0, 5, function(value: number): ()
        placeSettings.ahead = value
    end)
    addNumberOption(ServerScaffoldFeature, "Grid size", placeSettings.grid, 1, 6, function(value: number): ()
        placeSettings.grid = value
    end)
    addNumberOption(ServerScaffoldFeature, "Variant", placeSettings.variant, 0, 12, function(value: number): ()
        placeSettings.variant = value
    end)
    addTextOption(ServerScaffoldFeature, "Block name", "", function(value: string): ()
        placeSettings.block = value
    end)
    addInformationOption(
        ServerScaffoldFeature,
        "Variant is the second argument, which the client sent as 5 once and 3 "
            .. "another time — most likely the hotbar slot. Leave the block "
            .. "empty to use whatever you are holding, or type one and hold "
            .. "nothing at all."
    )

    local minerSettings: any = {
        tool = "Wooden Pickaxe",

        range = 24,
        rate = 8,
        perTick = 2,
        filter = "",
    }

    local function minableBlocks(origin: Vector3, range: number, filter: string): {BasePart}
        local found: {BasePart} = {}
        local container: Instance? = workspace:FindFirstChild("PlayersBlocksContainer")
        if not container then
            return found
        end
        local wanted: string = string.lower(filter)
        for _, group: Instance in ipairs(container:GetChildren()) do
            for _, block: Instance in ipairs(group:GetChildren()) do
                if not block:IsA("BasePart") then
                    continue
                end
                if wanted ~= ""
                    and not string.find(string.lower(block.Name), wanted, 1, true) then
                    continue
                end
                if ((block :: BasePart).Position - origin).Magnitude > range then
                    continue
                end
                table.insert(found, block :: BasePart)
            end
        end
        table.sort(found, function(first: BasePart, second: BasePart): boolean
            return (first.Position - origin).Magnitude
                < (second.Position - origin).Magnitude
        end)
        return found
    end

    local function mineBlock(block: BasePart, origin: Vector3): ()
        local target: Vector3 = block.Position
        local direction: Vector3 = target - origin
        if direction.Magnitude > 0.001 then
            direction = direction.Unit
        else
            direction = Vector3.new(0, -1, 0)
        end

        fireRemote(
            "ItemsRemotes.MineBlock",
            minerSettings.tool,
            block,
            Vector3.new(
                math.round(target.X),
                math.round(target.Y),
                math.round(target.Z)
            ),
            origin,
            direction
        )
    end

    local MinerFeature: any = createUniversalFeature(
        "Server Miner",
        "Mines the blocks around you without holding a pickaxe",
        10,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightMiner")
            if not enabled then
                return
            end
            local nextAt: number = 0
            host.featureConnections.BedFightMiner =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 1 / math.max(minerSettings.rate, 0.5)

                    local root: BasePart? = LocalPlayer.Character
                        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if not root then
                        return
                    end
                    local origin: Vector3 = (root :: BasePart).Position
                    local blocks: {BasePart} =
                        minableBlocks(origin, minerSettings.range, minerSettings.filter)
                    for index: number = 1, math.min(#blocks, math.round(minerSettings.perTick)) do
                        mineBlock(blocks[index], origin)
                    end
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Combat"}
    )
    addTextOption(MinerFeature, "Pickaxe", minerSettings.tool, function(value: string): ()
        minerSettings.tool = value
    end)
    addTextOption(MinerFeature, "Only blocks named", "", function(value: string): ()
        minerSettings.filter = value
    end)
    addNumberOption(MinerFeature, "Range", minerSettings.range, 5, 48, function(value: number): ()
        minerSettings.range = value
    end)
    addNumberOption(MinerFeature, "Mines per second", minerSettings.rate, 1, 20, function(value: number): ()
        minerSettings.rate = value
    end)
    addNumberOption(MinerFeature, "Blocks per tick", minerSettings.perTick, 1, 12, function(value: number): ()
        minerSettings.perTick = value
    end)
    addInformationOption(
        MinerFeature,
        "Safe band: about 24 studs and under ten mines a second. The pickaxe "
            .. "is a name, not an object, so nothing has to be equipped — but a "
            .. "player mining thirty blocks a second from across the map is the "
            .. "easiest thing in the game to spot."
    )

    local buySettings: any = {category = "Blocks", item = "Wool", rate = 2, nearest = true}

    local function shopPrompt(): BasePart?
        local root: BasePart? = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local origin: Vector3 = root and (root :: BasePart).Position or Vector3.zero
        local best: BasePart? = nil
        local bestDistance: number = math.huge
        for _, mapChild: Instance in ipairs(workspace:GetChildren()) do
            local prompts: Instance? = mapChild:FindFirstChild("ItemShopPrompts")
            if not prompts then
                continue
            end
            for _, prompt: Instance in ipairs(prompts:GetChildren()) do
                if not prompt:IsA("BasePart") then
                    continue
                end
                local distance: number = ((prompt :: BasePart).Position - origin).Magnitude
                if distance < bestDistance then
                    best = prompt :: BasePart
                    bestDistance = distance
                end
            end
        end
        return best
    end

    local BuyFeature: any = createUniversalFeature(
        "Auto Buy",
        "Buys a shop item on a timer through the game's own purchase remote",
        10,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedFightBuy")
            if not enabled then
                return
            end
            local nextAt: number = 0
            host.featureConnections.BedFightBuy =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 1 / math.max(buySettings.rate, 0.2)
                    local prompt: BasePart? = shopPrompt()
                    if not prompt then
                        return
                    end
                    fireRemote(
                        "PurchaseItemShopItem",
                        prompt,
                        buySettings.category,
                        buySettings.item
                    )
                end)
        end,
        {parent = scroll, registry = registry, categoryName = "Other"}
    )
    addTextOption(BuyFeature, "Category", buySettings.category, function(value: string): ()
        buySettings.category = value
    end)
    addTextOption(BuyFeature, "Item", buySettings.item, function(value: string): ()
        buySettings.item = value
    end)
    addNumberOption(BuyFeature, "Purchases per second", buySettings.rate, 1, 10, function(value: number): ()
        buySettings.rate = value
    end)
    addInformationOption(
        BuyFeature,
        "Observed categories: Blocks, Swords, Pickaxes, Armor. The nearest "
            .. "shop prompt on the map is the one passed to the server. Two a "
            .. "second looks like a person holding the button; twenty does not."
    )

    local QuickFeature: any = createUniversalFeature(
        "Quick Actions",
        "One-shot calls with the arguments the game itself uses",
        11,
        function(): () end,
        {
            parent = scroll,
            registry = registry,
            categoryName = "Other",
            category = true,
        }
    )
    local quickSettings: any = {
        tool = "Wooden Sword",
        armor = "",
        slot = "Pants",
        drop = "Blue Wool",
    }
    addTextOption(QuickFeature, "Tool", quickSettings.tool, function(value: string): ()
        quickSettings.tool = value
    end)
    host.addActionOption(QuickFeature, "Equip tool", function(): ()
        fireRemote("ItemsRemotes.EquipTool", quickSettings.tool)
    end)
    addTextOption(QuickFeature, "Armor", quickSettings.armor, function(value: string): ()
        quickSettings.armor = value
    end)
    addTextOption(QuickFeature, "Armor slot", quickSettings.slot, function(value: string): ()
        quickSettings.slot = value
    end)
    host.addActionOption(QuickFeature, "Wear armor", function(): ()
        fireRemote("WearArmor", quickSettings.armor, quickSettings.slot)
    end)
    addTextOption(QuickFeature, "Drop item", quickSettings.drop, function(value: string): ()
        quickSettings.drop = value
    end)
    host.addActionOption(QuickFeature, "Drop all of it", function(): ()

        fireRemote("ItemsRemotes.DropItem", quickSettings.drop, "All")
    end)
    addInformationOption(
        QuickFeature,
        "EquipTool takes the item's name; WearArmor takes the armor and the "
            .. "slot, which the client sent as (\"\", \"Pants\")."
    )

    host.addActionOption = rawAddAction
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
            "BedFightServerAura",
            "BedFightServerScaffold",
            "BedFightBuy",
            "BedFightMiner",
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
