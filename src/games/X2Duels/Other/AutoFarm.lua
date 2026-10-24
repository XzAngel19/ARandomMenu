-- Halloween PumpkinCurrency farming for X2 Duels.
-- This is intentionally independent from Auto Win and its match/round logic.

local Module = {
    Name = "X2Duels Auto Farm",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local moduleCleanup: () -> () = function(): () end

local function buildAutoFarm(runtime: any): ()
    local host: any = getfenv()
    local state: any = runtime.State or host.state
    local players: Players = game:GetService("Players")
    local localPlayer: Player = players.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    assert(state.mvsdScroll and state.mvsdFeatures,
        "X2Duels Auto Farm requires the MVS menu section")

    local settings: {[string]: any} = {
        enabled = false,
        interval = 0.12,
    }
    local coins: {[Model]: BasePart} = {}
    local retryAt: {[Model]: number} = {}
    local connections: {any} = {}
    local nextRefreshAt: number = 0
    local nextFarmAt: number = 0
    local savedRoot: BasePart? = nil
    local savedCharacter: Model? = nil
    local savedCFrame: CFrame? = nil
    local farmCard: any = nil

    local function setStatus(text: string?): ()
        if farmCard and type(farmCard.SetStatus) == "function" then
            farmCard:SetStatus(text)
        end
    end

    local function rootOf(): BasePart?
        local character: Model? = localPlayer.Character
        if not character then
            return nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return nil
        end
        local root: Instance? = character:FindFirstChild("HumanoidRootPart")
        return root and root:IsA("BasePart") and root :: BasePart or nil
    end

    local function rememberPosition(root: BasePart): ()
        if savedRoot == root and savedCFrame ~= nil then
            return
        end
        savedRoot = root
        savedCharacter = localPlayer.Character
        savedCFrame = root.CFrame
    end

    local function restoreSavedPosition(): ()
        local root: BasePart? = savedRoot
        local character: Model? = savedCharacter
        local cframe: CFrame? = savedCFrame
        savedRoot = nil
        savedCharacter = nil
        savedCFrame = nil
        if not root or not character or not cframe or not root.Parent
            or localPlayer.Character ~= character then
            return
        end
        pcall(function(): ()
            root.CFrame = cframe
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local function addCoin(instance: Instance): ()
        if not instance:IsA("Model")
            or not string.match(instance.Name, "^PumpkinCurrency_%d+$") then
            return
        end
        local pumpkin: Instance? = instance:FindFirstChild("Pumpkin", true)
        if pumpkin and pumpkin:IsA("BasePart") then
            coins[instance :: Model] = pumpkin :: BasePart
        end
    end

    local function addCoinFromDescendant(instance: Instance): ()
        local current: Instance? = instance
        local depth: number = 0
        while current and current ~= currentWorkspace and depth < 6 do
            if current:IsA("Model")
                and string.match(current.Name, "^PumpkinCurrency_%d+$") then
                addCoin(current)
                return
            end
            current = current.Parent
            depth += 1
        end
    end

    local function refreshCoins(): ()
        table.clear(coins)
        for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if descendant:IsA("Model") then
                addCoin(descendant)
            end
        end
        for model: Model, _time: number in pairs(retryAt) do
            if not coins[model] then
                retryAt[model] = nil
            end
        end
    end

    local function isAvailable(model: Model, part: BasePart): boolean
        -- The place file stores these spawnables with CanTouch=false. A live
        -- event controller may enable them, so do not permanently discard a
        -- visible pumpkin from that editor-state property alone.
        if not model.Parent or not part.Parent or part.Transparency >= 0.95 then
            return false
        end
        local modelCollected: any = model:GetAttribute("Collected")
        local partCollected: any = part:GetAttribute("Collected")
        return modelCollected ~= true and partCollected ~= true
    end

    local function nearestCoin(root: BasePart, now: number): (Model?, BasePart?, number)
        local bestModel: Model? = nil
        local bestPart: BasePart? = nil
        local bestDistance: number = math.huge
        local remaining: number = 0
        for model: Model, part: BasePart in pairs(coins) do
            if isAvailable(model, part) then
                remaining += 1
                if (retryAt[model] or 0) <= now then
                    local distance: number = (part.Position - root.Position).Magnitude
                    if distance < bestDistance then
                        bestDistance = distance
                        bestModel = model
                        bestPart = part
                    end
                end
            end
        end
        return bestModel, bestPart, remaining
    end

    local function touchCoin(model: Model, part: BasePart, root: BasePart): ()
        rememberPosition(root)
        local currentCFrame: CFrame = root.CFrame
        root.CFrame = CFrame.fromMatrix(
            part.Position + Vector3.new(0, 1.25, 0),
            currentCFrame.RightVector,
            currentCFrame.UpVector
        )
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        -- Fire the same contact path as walking into the spawnable. The
        -- captured log does not establish CollectEventSpawnable's arguments,
        -- so this module deliberately does not fabricate a remote request.
        local fireTouch: any = host.firetouchinterest
        if type(fireTouch) == "function" then
            pcall(fireTouch, root, part, 0)
            pcall(fireTouch, root, part, 1)
        end
        retryAt[model] = os.clock() + 4
    end

    local function update(_deltaTime: number): ()
        if not settings.enabled then
            return
        end
        local now: number = os.clock()
        if now >= nextRefreshAt then
            nextRefreshAt = now + 10
            refreshCoins()
        end
        if now < nextFarmAt then
            return
        end
        local root: BasePart? = rootOf()
        if not root then
            setStatus("No character")
            nextFarmAt = now + 0.5
            return
        end
        local model: Model?, part: BasePart?, remaining: number = nearestCoin(root, now)
        if not model or not part then
            setStatus(remaining > 0 and "Retrying pumpkins" or "No pumpkins")
            nextFarmAt = now + 0.5
            return
        end
        touchCoin(model, part, root)
        nextFarmAt = now + settings.interval
        setStatus("Farming · " .. tostring(remaining) .. " visible")
    end

    moduleCleanup = function(): ()
        settings.enabled = false
        restoreSavedPosition()
        setStatus(nil)
        if host.featureConnections.X2DuelsAutoFarm then
            host.disconnectFeatureConnection("X2DuelsAutoFarm")
        end
        for _, connection: any in ipairs(connections) do
            pcall(function(): () connection:Disconnect() end)
        end
        table.clear(connections)
        table.clear(coins)
        table.clear(retryAt)
    end

    farmCard = host.createUniversalFeature(
        "Auto Farm",
        "Farm Halloween PumpkinCurrency spawnables through native contact; independent from Auto Win",
        1,
        function(enabled: boolean): ()
            settings.enabled = enabled
            nextRefreshAt = 0
            nextFarmAt = 0
            table.clear(retryAt)
            if enabled then
                savedRoot = nil
                savedCharacter = nil
                savedCFrame = nil
                setStatus("Scanning pumpkins")
            else
                restoreSavedPosition()
                setStatus(nil)
            end
        end,
        {
            parent = state.mvsdScroll,
            registry = state.mvsdFeatures,
            categoryName = "Exploits",
        }
    )
    host.addNumberOption(farmCard, "Step interval", 0.12, 0.06, 0.5, function(value: number): ()
        settings.interval = value
    end)
    host.addInformationOption(
        farmCard,
        "Finds PumpkinCurrency_* in lobby and match maps. Attempts are not counted as confirmed currency."
    )

    table.insert(connections, currentWorkspace.DescendantAdded:Connect(function(instance: Instance): ()
        if settings.enabled then
            addCoinFromDescendant(instance)
        end
    end))
    table.insert(connections, currentWorkspace.DescendantRemoving:Connect(function(instance: Instance): ()
        if instance:IsA("Model") then
            coins[instance :: Model] = nil
            retryAt[instance :: Model] = nil
        end
    end))
    table.insert(connections, localPlayer.CharacterAdded:Connect(function(): ()
        savedRoot = nil
        savedCharacter = nil
        savedCFrame = nil
        nextRefreshAt = 0
        nextFarmAt = 0
        table.clear(retryAt)
    end))
    host.featureConnections.X2DuelsAutoFarm = runtime.TaskManager:Connect(update)
end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    assert(type(runtime) == "table" and runtime.TaskManager,
        "X2Duels Auto Farm requires Runtime.TaskManager")
    Module.Runtime = runtime
    local ok: boolean, failure: any = pcall(buildAutoFarm, runtime)
    if not ok then
        moduleCleanup()
        Module.Runtime = nil
        error(failure)
    end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    moduleCleanup()
    moduleCleanup = function(): () end
    Module.Runtime = nil
    Module.Initialized = false
end

return Module
