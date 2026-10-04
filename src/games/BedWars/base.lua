export type Runtime = {
    Services: any,
    State: any,
}

local Module = {
    Name = "BedWars",
    PlaceId = 8444591321,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local runtimeState: any = {
    connections = {} :: {[string]: any},
    remoteCache = {} :: {[string]: Instance?},
}

local function remote(name: string): Instance?
    local cached: Instance? = runtimeState.remoteCache[name]
    if cached and cached.Parent then
        return cached
    end
    local replicated: Instance? = game:GetService("ReplicatedStorage")
    if not replicated then
        return nil
    end
    local found: Instance? = nil
    for _, child: Instance in ipairs(replicated:GetDescendants()) do
        if child.Name == name
            and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then

            found = child
            break
        end
    end
    if found == nil then
        return nil
    end
    runtimeState.remoteCache[name] = found
    return found :: Instance
end

local function fire(name: string, ...: any): boolean
    local target: Instance? = remote(name)
    if not target then
        return false
    end
    local resolved: Instance = target :: Instance

    local args: any = table.pack(...)
    if resolved:IsA("RemoteFunction") then
        return pcall(function(): ()
            (resolved :: any):InvokeServer(table.unpack(args, 1, args.n))
        end)
    end
    return pcall(function(): ()
        (resolved :: any):FireServer(table.unpack(args, 1, args.n))
    end)
end

function Module.init(runtime: any): any
    local environment: any = getfenv()
    local host: any = environment
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addTextOption: any = host.addTextOption
    local create: any = host.create
    local makeTextLabel: any = host.makeTextLabel
    local TaskManager: any = host.TaskManager
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local _services: any = runtime.Services or (host.services or {})

    local registry: any = state.bedWarsFeatures

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local own: Model? = LocalPlayer.Character
        if not own then
            return nil, nil, nil
        end
        return own,
            own:FindFirstChildOfClass("Humanoid") :: Humanoid?,
            own:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function camera(): Camera?
        return workspace.CurrentCamera
    end

    local function equippedWeapon(): Instance?
        local own: Model? = LocalPlayer.Character
        if not own then
            return nil
        end
        for _, child: Instance in ipairs(own:GetChildren()) do
            if child:IsA("Accessory") then
                return child
            end
        end
        return nil
    end

    local function sameTeam(player: Player): boolean
        return LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
    end

    local ownedConnections: {string} = {
        "BedWarsAura", "BedWarsClicker", "BedWarsPlace", "BedWarsNuke",
        "BedWarsEspAdded", "BedWarsEspRemoved", "BedWarsChest", "BedWarsAutoTool",
        "BedWarsInventory", "BedWarsAimbot", "BedWarsDrop", "BedWarsTracer",
        "BedWarsShop",
    }
    runtimeState.disconnectAll = function(): ()
        for _, key: string in ipairs(ownedConnections) do
            host.disconnectFeatureConnection(key)
        end

        if type(runtimeState.cleanupPanels) == "function" then
            pcall(runtimeState.cleanupPanels)
        end
        if type(runtimeState.cleanupTracer) == "function" then
            pcall(runtimeState.cleanupTracer)
        end
    end

    local InventoryFeature: any = nil
    local ShopFeature: any = nil
    local AimbotFeature: any = nil
    local DropFeature: any = nil
    local TracerFeature: any = nil
    local PlaceFeature: any = nil
    local NukeFeature: any = nil
    local EspFeature: any = nil
    local ChestFeature: any = nil
    local AutoToolFeature: any = nil

    local function swordHitPayload(targetRoot: BasePart): {[string]: any}?
        local _own: Model?, _humanoid: Humanoid?, root: BasePart? = characterParts()
        local view: Camera? = camera()
        if not root or not view then
            return nil
        end
        local weapon: Instance? = equippedWeapon()
        if not weapon then
            return nil
        end
        local origin: Vector3 = (view :: Camera).CFrame.Position
        local target: Vector3 = targetRoot.Position
        local direction: Vector3 = target - origin
        return {
            entityInstance = targetRoot.Parent,
            chargedAttack = {chargeRatio = 0},
            validate = {
                targetPosition = {value = target},
                selfPosition = {value = (root :: BasePart).Position},
                raycast = {
                    cameraPosition = {value = origin},
                    cursorDirection = {
                        value = direction.Magnitude > 0.001
                            and direction.Unit
                            or (view :: Camera).CFrame.LookVector,
                    },
                },
            },
            weapon = weapon,
        }
    end

    local placeSettings: any = {block = "wool_white", rate = 8}

    local function placeAt(position: Vector3): boolean
        return fire("PlaceBlock", {
            mouseBlockInfo = {placementPosition = position},
            blockType = placeSettings.block,
            blockData = 0,
            position = position,
        })
    end

    PlaceFeature = createUniversalFeature(
        "Fast Place",
        "Places the selected block at the aimed position",
        2,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsPlace")
            if not enabled then
                if PlaceFeature then
                    PlaceFeature:SetStatus(nil)
                end
                return
            end
            PlaceFeature:SetStatus(placeSettings.block)
            local nextAt: number = 0
            host.featureConnections.BedWarsPlace =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    local view: Camera? = camera()
                    local own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    if not view or not own or not root or not humanoid
                        or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end
                    local origin: Vector3 = (view :: Camera).CFrame.Position
                    local direction: Vector3 = (view :: Camera).CFrame.LookVector
                    local parameters: RaycastParams = RaycastParams.new()
                    parameters.FilterType = Enum.RaycastFilterType.Exclude
                    parameters.FilterDescendantsInstances = {own :: Model}
                    local hit: RaycastResult? =
                        workspace:Raycast(origin, direction * 20, parameters)
                    if not hit then
                        return
                    end
                    nextAt = now + 1 / math.max(placeSettings.rate, 0.5)
                    placeAt((hit :: RaycastResult).Position)
                end)
        end,
        {categoryName = "Blocks", registry = registry}
    )
    addNumberOption(PlaceFeature, "Blocks per second", placeSettings.rate, 1, 20,
        function(value: number): ()
            placeSettings.rate = value
        end)

    local nukeSettings: any = {range = 20, rate = 6}

    NukeFeature = createUniversalFeature(
        "Nuker",
        "Breaks tagged beds inside range",
        3,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsNuke")
            if not enabled then
                if NukeFeature then
                    NukeFeature:SetStatus(nil)
                end
                return
            end
            NukeFeature:SetStatus("0 beds")
            local nextAt: number = 0
            host.featureConnections.BedWarsNuke =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    local _own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    if not root or not humanoid or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end
                    local collectionService: any = game:GetService("CollectionService")
                    local origin: Vector3 = (root :: BasePart).Position
                    local nearest: BasePart? = nil
                    local nearestDistance: number = nukeSettings.range
                    local seen: number = 0
                    for _, tagged: Instance in ipairs(collectionService:GetTagged("bed")) do
                        if not tagged:IsA("BasePart") then
                            continue
                        end
                        seen += 1
                        local part: BasePart = tagged :: BasePart
                        local distance: number = (part.Position - origin).Magnitude
                        if distance < nearestDistance then
                            nearest = part
                            nearestDistance = distance
                        end
                    end
                    NukeFeature:SetStatus(tostring(seen) .. " beds")
                    if not nearest then
                        return
                    end
                    nextAt = now + 1 / math.max(nukeSettings.rate, 0.5)
                    local position: Vector3 = (nearest :: BasePart).Position
                    fire("DamageBlock", {
                        blockRef = {blockPosition = position},
                        hitPosition = position,
                        hitNormal = (origin - position).Unit,
                    })
                end)
        end,
        {categoryName = "Blocks", registry = registry}
    )
    addNumberOption(NukeFeature, "Range", nukeSettings.range, 5, 60,
        function(value: number): ()
            nukeSettings.range = value
        end)

    local espSettings: any = {beds = true, pots = true}
    local espMarks: {[Instance]: any} = {}

    local function clearEspMarks(): ()
        for instance: Instance, mark: any in pairs(espMarks) do
            pcall(function(): ()
                mark:Destroy()
            end)
            espMarks[instance] = nil
        end
    end

    local function markBlock(instance: Instance, label: string): ()
        if espMarks[instance] or not instance:IsA("BasePart") then
            return
        end
        local billboard: any = create("BillboardGui", {
            Name = "Wurst_BedWars_" .. label,
            Size = UDim2.fromOffset(72, 20),
            StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
            AlwaysOnTop = true,
            Adornee = instance,
            Parent = instance,
        })
        makeTextLabel(billboard, label, 14)
        espMarks[instance] = billboard
    end

    EspFeature = createUniversalFeature(
        "Objective ESP",
        "Marks tagged beds and desert pots through walls",
        4,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsEspAdded")
            host.disconnectFeatureConnection("BedWarsEspRemoved")
            clearEspMarks()
            if not enabled then
                if EspFeature then
                    EspFeature:SetStatus(nil)
                end
                return
            end
            local collectionService: any = game:GetService("CollectionService")

            local function add(instance: Instance): ()
                if espSettings.beds and collectionService:HasTag(instance, "bed") then
                    markBlock(instance, "Bed")
                elseif espSettings.pots and instance.Name == "desert_pot" then
                    markBlock(instance, "Pot")
                end
            end
            local function remove(instance: Instance): ()
                local mark: any = espMarks[instance]
                if mark then
                    pcall(function(): ()
                        mark:Destroy()
                    end)
                    espMarks[instance] = nil
                end
            end

            for _, instance: Instance in ipairs(collectionService:GetTagged("bed")) do
                add(instance)
            end
            for _, instance: Instance in ipairs(collectionService:GetTagged("block")) do
                add(instance)
            end
            host.featureConnections.BedWarsEspAdded =
                collectionService:GetInstanceAddedSignal("block"):Connect(add)
            host.featureConnections.BedWarsEspRemoved =
                collectionService:GetInstanceRemovedSignal("block"):Connect(remove)
            EspFeature:SetStatus("on")
        end,
        {categoryName = "Render", registry = registry}
    )
    addToggleOption(EspFeature, "Beds", espSettings.beds, function(value: boolean): ()
        espSettings.beds = value
    end)
    addToggleOption(EspFeature, "Desert pots", espSettings.pots, function(value: boolean): ()
        espSettings.pots = value
    end)

    ChestFeature = createUniversalFeature(
        "Chest Steal",
        "Opens nearby chests without walking to them",
        5,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsChest")
            if not enabled then
                if ChestFeature then
                    ChestFeature:SetStatus(nil)
                end
                return
            end
            ChestFeature:SetStatus("on")
            local nextAt: number = 0
            host.featureConnections.BedWarsChest =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 0.5
                    fire("Inventory/SetObservedChest")
                end)
        end,
        {categoryName = "Other", registry = registry}
    )

    AutoToolFeature = createUniversalFeature(
        "Auto Tool",
        "Puts the matching item in hand before you need it",
        6,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsAutoTool")
            if not enabled then
                if AutoToolFeature then
                    AutoToolFeature:SetStatus(nil)
                end
                return
            end
            AutoToolFeature:SetStatus("on")
            host.featureConnections.BedWarsAutoTool =
                TaskManager:Connect(function(): ()
                    local inventory: Instance? = game:GetService("ReplicatedStorage")
                    inventory = inventory
                        and inventory:FindFirstChild("Inventories") :: Instance?
                    inventory = inventory
                        and inventory:FindFirstChild(LocalPlayer.Name) :: Instance?
                    if not inventory then
                        return
                    end
                    local wanted: Instance? = nil
                    for _, child: Instance in ipairs((inventory :: Instance):GetChildren()) do
                        if child.Name:find("pickaxe") or child.Name:find("axe") then
                            wanted = child
                            break
                        end
                    end
                    if wanted then
                        fire("SetInvItem", {hand = wanted})
                    end
                end)
        end,
        {categoryName = "Other", registry = registry}
    )

    local inventorySettings: any = {range = 60, maxRows = 12}
    local inventoryRuntime: any = {panel = nil, signature = ""}

    local function destroyInventoryPanel(): ()
        if inventoryRuntime.panel then
            pcall(function(): ()
                inventoryRuntime.panel:Destroy()
            end)
            inventoryRuntime.panel = nil
        end
        inventoryRuntime.signature = ""
    end

    local function aimedPlayer(): Player?
        local view: Camera? = camera()
        if not view then
            return nil
        end
        local origin: Vector3 = (view :: Camera).CFrame.Position
        local direction: Vector3 = (view :: Camera).CFrame.LookVector
        local best: Player? = nil
        local bestScore: number = inventorySettings.range
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then
                continue
            end
            local character: Model? = player.Character
            local humanoid: Humanoid? = character
                and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            local part: BasePart? = character
                and character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not humanoid or not part or (humanoid :: Humanoid).Health <= 0 then
                continue
            end
            local offset: Vector3 = (part :: BasePart).Position - origin
            local distance: number = offset.Magnitude
            if distance > inventorySettings.range then
                continue
            end

            if distance > 0.001 and offset.Unit:Dot(direction) < 0.86 then
                continue
            end
            if distance < bestScore then
                best = player
                bestScore = distance
            end
        end
        return best
    end

    local function inventoryOf(player: Player): Instance?
        local replicated: Instance? = game:GetService("ReplicatedStorage")
        local inventories: Instance? = replicated
            and replicated:FindFirstChild("Inventories") :: Instance?
        return inventories
            and inventories:FindFirstChild(player.Name) :: Instance?
    end

    local function renderInventory(player: Player, folder: Instance): ()
        local names: {string} = {}
        for _, item: Instance in ipairs(folder:GetChildren()) do
            table.insert(names, item.Name)
        end
        table.sort(names)
        local signature: string = player.Name .. "|" .. table.concat(names, ",")
        if signature == inventoryRuntime.signature and inventoryRuntime.panel then
            return
        end
        inventoryRuntime.signature = signature
        destroyInventoryPanel()

        local rows: number = math.min(#names, inventorySettings.maxRows)
        local root: Frame = create("Frame", {
            Parent = host.ScreenGui,
            Name = "Wurst_BedWarsInventory",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = Color3.fromRGB(14, 14, 16),
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -18, 0, 90),
            Size = UDim2.fromOffset(196, 34 + rows * 18),
            ZIndex = 60,
        }) :: Frame
        create("UICorner", {Parent = root, CornerRadius = UDim.new(0, 4)})
        makeTextLabel(root, player.Name, 14)
        for index: number = 1, rows do
            makeTextLabel(root, names[index], 14)
        end
        if #names > rows then
            makeTextLabel(root, "+" .. tostring(#names - rows) .. " more", 14)
        end
        inventoryRuntime.panel = root
    end

    InventoryFeature = createUniversalFeature(
        "Inventory ESP",
        "Reads the inventory of the player you are looking at",
        8,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsInventory")
            destroyInventoryPanel()
            if not enabled then
                if InventoryFeature then
                    InventoryFeature:SetStatus(nil)
                end
                return
            end
            InventoryFeature:SetStatus("searching")
            local nextAt: number = 0
            host.featureConnections.BedWarsInventory =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 0.25
                    local player: Player? = aimedPlayer()
                    if not player then
                        destroyInventoryPanel()
                        InventoryFeature:SetStatus("searching")
                        return
                    end
                    local folder: Instance? = inventoryOf(player :: Player)
                    if not folder then
                        destroyInventoryPanel()
                        InventoryFeature:SetStatus("no data")
                        return
                    end
                    renderInventory(player :: Player, folder :: Instance)
                    InventoryFeature:SetStatus((player :: Player).Name)
                end)
        end,
        {categoryName = "Render", registry = registry}
    )
    addNumberOption(InventoryFeature, "Range", inventorySettings.range, 10, 200,
        function(value: number): ()
            inventorySettings.range = value
        end)

    local projectileSettings: any = {
        range = 120,
        delay = 0.5,
        wallCheck = true,
        teamCheck = true,

        speed = 100,
    }
    local projectileRuntime: any = {nextAt = 0}

    local PROJECTILE_WORDS: {string} = {"bow", "arrow", "pearl", "snowball", "egg", "potion"}

    local function projectileWeapon(): Instance?
        local own: Model? = LocalPlayer.Character
        if not own then
            return nil
        end
        for _, child: Instance in ipairs((own :: Model):GetChildren()) do
            if not child:IsA("Accessory") then
                continue
            end
            for _, word: string in ipairs(PROJECTILE_WORDS) do
                if child.Name:find(word) then
                    return child
                end
            end
        end
        return nil
    end

    local function solveTrajectory(
        origin: Vector3,
        targetPosition: Vector3,
        targetVelocity: Vector3,
        speed: number,
        gravity: number
    ): (Vector3?, number?)
        if speed <= 0 then
            return nil, nil
        end

        local function demand(flight: number): Vector3
            local aim: Vector3 = targetPosition + targetVelocity * flight
            local drop: Vector3 = Vector3.new(0, 0.5 * gravity * flight * flight, 0)
            return ((aim - origin) + drop) / flight
        end

        local SCAN_STEP: number = 0.02
        local low: number = SCAN_STEP
        local high: number? = nil
        local flight: number = low
        for _ = 1, 300 do
            flight += SCAN_STEP
            if demand(flight).Magnitude <= speed then
                high = flight
                break
            end
            low = flight
        end
        if not high then
            return nil, nil
        end
        for _ = 1, 24 do
            local mid: number = (low + (high :: number)) / 2
            if demand(mid).Magnitude > speed then
                low = mid
            else
                high = mid
            end
        end
        local solved: number = high :: number
        return demand(solved), solved
    end
    Module.solveTrajectory = solveTrajectory

    local function randomId(length: number): string
        local alphabet: string =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        local out: {string} = {}
        for _ = 1, length do
            local index: number = math.random(1, #alphabet)
            table.insert(out, alphabet:sub(index, index))
        end
        return table.concat(out)
    end

    AimbotFeature = createUniversalFeature(
        "Projectile Aimbot",
        "Solves the shot and fires the game's own projectile remote",
        9,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsAimbot")
            projectileRuntime.nextAt = 0
            if not enabled then
                if AimbotFeature then
                    AimbotFeature:SetStatus(nil)
                end
                return
            end
            AimbotFeature:SetStatus("no projectile")
            host.featureConnections.BedWarsAimbot =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < projectileRuntime.nextAt then
                        return
                    end
                    local weapon: Instance? = projectileWeapon()
                    if not weapon then
                        AimbotFeature:SetStatus("no projectile")
                        return
                    end
                    local own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    local view: Camera? = camera()
                    if not own or not humanoid or not root or not view
                        or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end

                    local origin: Vector3 = (view :: Camera).CFrame.Position
                    local best: Player? = nil
                    local bestPart: BasePart? = nil
                    local bestDistance: number = projectileSettings.range
                    for _, player: Player in ipairs(Players:GetPlayers()) do
                        if player == LocalPlayer then
                            continue
                        end
                        if projectileSettings.teamCheck and sameTeam(player) then
                            continue
                        end
                        local character: Model? = player.Character
                        local otherHumanoid: Humanoid? = character
                            and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                        local part: BasePart? = character
                            and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                        if not otherHumanoid or not part
                            or (otherHumanoid :: Humanoid).Health <= 0 then
                            continue
                        end
                        local distance: number =
                            ((part :: BasePart).Position - origin).Magnitude
                        if distance > bestDistance then
                            continue
                        end
                        if projectileSettings.wallCheck then
                            local parameters: RaycastParams = RaycastParams.new()
                            parameters.FilterType = Enum.RaycastFilterType.Exclude
                            parameters.FilterDescendantsInstances = {
                                own :: Model,
                                character :: Model,
                            }
                            local blocked: RaycastResult? = workspace:Raycast(
                                origin,
                                (part :: BasePart).Position - origin,
                                parameters
                            )
                            if blocked then
                                continue
                            end
                        end
                        best = player
                        bestPart = part :: BasePart
                        bestDistance = distance
                    end

                    if not best or not bestPart then
                        AimbotFeature:SetStatus("searching")
                        return
                    end

                    local speed: number = projectileSettings.speed
                    local gravity: number = workspace.Gravity
                    local target: BasePart = bestPart :: BasePart
                    local velocity: Vector3?, flight: number? = solveTrajectory(
                        origin,
                        target.Position,
                        target.AssemblyLinearVelocity,
                        speed,
                        gravity
                    )
                    if not velocity then
                        AimbotFeature:SetStatus("out of range")
                        return
                    end
                    projectileRuntime.nextAt = now + projectileSettings.delay
                    local itemType: string = (weapon :: Instance).Name
                    fire("ProjectileFire",
                        weapon,
                        itemType,
                        itemType,
                        origin,
                        origin - Vector3.new(0, 2, 0),
                        velocity :: Vector3,
                        randomId(8),
                        {drawDurationSec = 0.15, shotId = randomId(8)},
                        os.time()
                    )
                    AimbotFeature:SetStatus(string.format(
                        "%s · %.2fs",
                        (best :: Player).Name,
                        flight :: number
                    ))
                end)
        end,
        {categoryName = "Combat", registry = registry}
    )
    addNumberOption(AimbotFeature, "Range", projectileSettings.range, 10, 300,
        function(value: number): ()
            projectileSettings.range = value
        end)
    addNumberOption(AimbotFeature, "Seconds between shots", projectileSettings.delay,
        0.1, 2,
        function(value: number): ()
            projectileSettings.delay = value
        end)
    addToggleOption(AimbotFeature, "Wall check", projectileSettings.wallCheck,
        function(value: boolean): ()
            projectileSettings.wallCheck = value
        end)
    addToggleOption(AimbotFeature, "Team check", projectileSettings.teamCheck,
        function(value: boolean): ()
            projectileSettings.teamCheck = value
        end)

    local dropSettings: any = {rate = 8}
    local dropRuntime: any = {controller = nil, missing = false}

    local function dropController(): any
        if dropRuntime.controller then
            return dropRuntime.controller
        end
        if dropRuntime.missing then
            return nil
        end
        local replicated: Instance? = game:GetService("ReplicatedStorage")
        if not replicated then
            return nil
        end
        for _, descendant: Instance in ipairs(replicated:GetDescendants()) do
            if descendant.Name == "ItemDropController" and descendant:IsA("ModuleScript") then
                local ok: boolean, loaded: any = pcall(require, descendant)
                if ok and type(loaded) == "table"
                    and type(loaded.dropItemInHand) == "function" then
                    dropRuntime.controller = loaded
                    return loaded
                end

                dropRuntime.missing = true
                return nil
            end
        end
        dropRuntime.missing = true
        return nil
    end

    DropFeature = createUniversalFeature(
        "Fast Drop",
        "Drops what is in hand through the game's own controller",
        10,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsDrop")
            if not enabled then
                if DropFeature then
                    DropFeature:SetStatus(nil)
                end
                return
            end
            DropFeature:SetStatus("idle")
            local nextAt: number = 0
            host.featureConnections.BedWarsDrop =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    local controller: any = dropController()
                    if not controller then
                        DropFeature:SetStatus("no controller")
                        return
                    end
                    nextAt = now + 1 / math.max(dropSettings.rate, 0.5)
                    local ok: boolean = pcall(function(): ()
                        controller.dropItemInHand()
                    end)
                    DropFeature:SetStatus(ok and "dropping" or "refused")
                end)
        end,
        {categoryName = "Other", registry = registry}
    )
    addNumberOption(DropFeature, "Drops per second", dropSettings.rate, 1, 20,
        function(value: number): ()
            dropSettings.rate = value
        end)

    local tracerRuntime: any = {folder = nil, points = {} :: {any}}
    local TRACER_SAMPLES: number = 12

    local function clearTracer(): ()
        if tracerRuntime.folder then
            pcall(function(): ()
                tracerRuntime.folder:Destroy()
            end)
            tracerRuntime.folder = nil
        end
        tracerRuntime.points = {}
    end

    TracerFeature = createUniversalFeature(
        "Projectile Tracers",
        "Draws the arc the shot in hand would take",
        11,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsTracer")
            clearTracer()
            if not enabled then
                if TracerFeature then
                    TracerFeature:SetStatus(nil)
                end
                return
            end
            TracerFeature:SetStatus("no projectile")
            local nextAt: number = 0
            host.featureConnections.BedWarsTracer =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 0.1
                    local weapon: Instance? = projectileWeapon()
                    local view: Camera? = camera()
                    if not weapon or not view then
                        clearTracer()
                        TracerFeature:SetStatus("no projectile")
                        return
                    end
                    local own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    if not own or not humanoid or not root
                        or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end

                    local origin: Vector3 = (view :: Camera).CFrame.Position
                    local forward: Vector3 = (view :: Camera).CFrame.LookVector
                    local gravity: number = workspace.Gravity
                    local speed: number = projectileSettings.speed

                    local maxRange: number = speed * speed / math.max(gravity, 1)
                    local aimPoint: Vector3 = origin + forward * maxRange * 0.9
                    local velocity: Vector3?, flight: number? = solveTrajectory(
                        origin, aimPoint, Vector3.new(0, 0, 0), speed, gravity
                    )
                    if not velocity then
                        clearTracer()
                        TracerFeature:SetStatus("no arc")
                        return
                    end

                    local launch: Vector3 = velocity :: Vector3
                    local total: number = flight :: number
                    if not tracerRuntime.folder then
                        tracerRuntime.folder = create("Folder", {
                            Name = "Wurst_BedWarsTracer",
                            Parent = workspace,
                        })
                    end
                    local folder: any = tracerRuntime.folder
                    for index: number = 1, TRACER_SAMPLES do
                        local at: number = total * index / TRACER_SAMPLES
                        local position: Vector3 = origin + launch * at
                            - Vector3.new(0, 0.5 * gravity * at * at, 0)
                        local point: any = tracerRuntime.points[index]
                        if not point or not point.Parent then
                            point = create("Part", {
                                Name = "T" .. tostring(index),
                                Parent = folder,
                                Size = Vector3.new(0.3, 0.3, 0.3),
                                Anchored = true,
                                CanCollide = false,
                                CanQuery = false,
                                CanTouch = false,
                                Material = Enum.Material.Neon,
                                Color = Color3.fromRGB(120, 200, 255),
                                Transparency = 0.25,
                            })
                            tracerRuntime.points[index] = point
                        end
                        point.CFrame = CFrame.new(position)
                    end
                    TracerFeature:SetStatus(string.format("%.2fs", total))
                end)
        end,
        {categoryName = "Render", registry = registry}
    )

    local function pressableKind(name: string): string?
        if name:find("sword") then
            return "Sword"
        end
        if name:find("wool") then
            return "Wool"
        end
        if name:find("pickaxe") then
            return "Pickaxe"
        end
        return nil
    end

    local function gamePressables(): {{any}}
        local own: Model? = LocalPlayer.Character
        if not own then
            return {}
        end
        local inventory: Instance? = game:GetService("ReplicatedStorage")
        inventory = inventory and inventory:FindFirstChild("Inventories") :: Instance?
        inventory = inventory and inventory:FindFirstChild(LocalPlayer.Name) :: Instance?
        local pool: {Instance} = {}
        for _, child: Instance in ipairs((own :: Model):GetChildren()) do
            if child:IsA("Accessory") then
                table.insert(pool, child)
            end
        end
        if inventory then
            for _, child: Instance in ipairs((inventory :: Instance):GetChildren()) do
                table.insert(pool, child)
            end
        end
        local out: {{any}} = {}
        local seen: {[string]: boolean} = {}
        for _, item: Instance in ipairs(pool) do
            local kind: string? = pressableKind(item.Name)
            if kind and not seen[kind :: string] then
                seen[kind :: string] = true
                table.insert(out, {kind :: string, item})
            end
        end
        return out
    end

    local function aimedSurface(): Vector3?
        local own: Model? = LocalPlayer.Character
        local view: Camera? = camera()
        if not own or not view then
            return nil
        end
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = {own :: Model}
        local hit: RaycastResult? = workspace:Raycast(
            (view :: Camera).CFrame.Position,
            (view :: Camera).CFrame.LookVector * 20,
            parameters
        )
        return hit and (hit :: RaycastResult).Position or nil
    end

    local function gamePress(label: string, target: any?): boolean
        if label == "Sword" then

            local targetRoot: BasePart? = target and target.RootPart
            if targetRoot then
                local view: Camera? = camera()
                if not view then
                    return false
                end
                local payload: {[string]: any}? = swordHitPayload(targetRoot :: BasePart)
                if not payload then
                    return false
                end
                return fire("SwordHit", payload :: any)
            end

            return fire("SwordSwingMiss", {
                chargeRatio = 0,
                weapon = equippedWeapon(),
            })
        end
        local position: Vector3? = aimedSurface()
        if not position then
            return false
        end
        if label == "Wool" then
            return placeAt(position :: Vector3)
        end
        if label == "Pickaxe" then
            return fire("DamageBlock", {
                blockRef = {blockPosition = position :: Vector3},
                hitPosition = position :: Vector3,
                hitNormal = Vector3.new(0, 1, 0),
            })
        end
        return false
    end

    local weaponLibrary: any = state.weaponLibrary
    if weaponLibrary and type(weaponLibrary.RegisterGameSource) == "function" then
        weaponLibrary:RegisterGameSource({scan = gamePressables, press = gamePress})
        runtimeState.unregisterWeapons = function(): ()
            weaponLibrary:RegisterGameSource(nil)
        end
    end

    local shopSettings: any = {
        item = "wool_white",
        amount = 16,
        price = 8,
        rate = 4,
        shopId = "3_item_shop_2",
    }

    ShopFeature = createUniversalFeature(
        "Shop Clicker",
        "Buys the same item over and over from the shop you are standing at",
        12,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsShop")
            if not enabled then
                if ShopFeature then
                    ShopFeature:SetStatus(nil)
                end
                return
            end
            ShopFeature:SetStatus(shopSettings.item)
            local nextAt: number = 0
            host.featureConnections.BedWarsShop =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 1 / math.max(shopSettings.rate, 0.5)
                    fire("BedwarsPurchaseItem", {
                        shopItem = {
                            currency = "iron",
                            itemType = shopSettings.item,
                            amount = shopSettings.amount,
                            price = shopSettings.price,
                            category = "Blocks",
                        },
                        shopId = shopSettings.shopId,
                    })
                end)
        end,
        {categoryName = "Other", registry = registry}
    )
    addTextOption(ShopFeature, "Item type", shopSettings.item, function(value: string): ()
        shopSettings.item = value
        if ShopFeature then
            ShopFeature:SetStatus(value)
        end
    end)
    addNumberOption(ShopFeature, "Amount", shopSettings.amount, 1, 64,
        function(value: number): ()
            shopSettings.amount = math.round(value)
        end)
    addNumberOption(ShopFeature, "Price", shopSettings.price, 1, 9999,
        function(value: number): ()
            shopSettings.price = math.round(value)
        end)
    addNumberOption(ShopFeature, "Buys per second", shopSettings.rate, 1, 20,
        function(value: number): ()
            shopSettings.rate = value
        end)

    runtimeState.cleanupPanels = function(): ()
        destroyInventoryPanel()
    end
    runtimeState.cleanupTracer = function(): ()
        clearTracer()
    end

    Module.Initialized = true
    return {
        place = PlaceFeature,
        nuke = NukeFeature,
        esp = EspFeature,
        chest = ChestFeature,
        autoTool = AutoToolFeature,
        inventory = InventoryFeature,
        aimbot = AimbotFeature,
        drop = DropFeature,
        tracer = TracerFeature,
        shop = ShopFeature,
    }
end

function Module.destroy(): ()
    Module.solveTrajectory = nil
    if type(runtimeState.unregisterWeapons) == "function" then
        pcall(runtimeState.unregisterWeapons)
    end
    runtimeState.unregisterWeapons = nil
    if type(runtimeState.disconnectAll) == "function" then
        pcall(runtimeState.disconnectAll)
    end
    runtimeState.disconnectAll = nil
    runtimeState.remoteCache = {}
    Module.Initialized = false
end

return Module
