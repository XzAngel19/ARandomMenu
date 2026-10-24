-- Halloween PumpkinCurrency and round-team PumpCoins farming for X2 Duels.
-- This is intentionally independent from Auto Win and its combat logic.

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
    local farms: {[Model]: {BasePart}} = {}
    local farmTeams: {[Model]: any} = {}
    local podiums: {Model} = {}
    local retryAt: {[Instance]: number} = {}
    local connections: {any} = {}
    local nextRefreshAt: number = 0
    local nextStructureAt: number = 0
    local nextFarmAt: number = 0
    local savedRoot: BasePart? = nil
    local savedCharacter: Model? = nil
    local savedCFrame: CFrame? = nil
    local farmCard: any = nil
    local roundTeam: string? = nil
    local roundStarted: boolean = false
    local podiumEvidence: boolean = false

    local TEAM_NAMES: {[string]: boolean} = {
        team = true,
        teamvalue = true,
        teamname = true,
        teamid = true,
        side = true,
        faction = true,
        matchteam = true,
    }
    local VALUE_CLASSES: {[string]: boolean} = {
        StringValue = true,
        ObjectValue = true,
        IntValue = true,
        NumberValue = true,
        BoolValue = true,
        TeamValue = true,
    }

    local function setStatus(text: string?): ()
        if farmCard and type(farmCard.SetStatus) == "function" then
            farmCard:SetStatus(text)
        end
    end

    local function normalized(value: any): string?
        if value == nil or value == false then
            return nil
        end
        if typeof(value) == "Instance" then
            local ok: boolean, name: any = pcall(function(): any
                return value.Name
            end)
            return ok and normalized(name) or nil
        end
        local text: string = string.lower(
            string.match(tostring(value), "^%s*(.-)%s*$") or ""
        )
        if text == "" or text == "nil" or text == "none" or text == "false" then
            return nil
        end
        return text
    end

    local function readValue(instance: Instance): any
        if not VALUE_CLASSES[instance.ClassName] then
            return nil
        end
        local ok: boolean, value: any = pcall(function(): any
            return (instance :: any).Value
        end)
        return ok and value or nil
    end

    local function teamOf(player: Player): string?
        for _, name: string in ipairs({
            "Team", "TeamName", "TeamId", "TeamID", "Side", "Faction", "MatchTeam",
        }) do
            local ok: boolean, value: any = pcall(function(): any
                return player:GetAttribute(name)
            end)
            local token: string? = ok and normalized(value) or nil
            if token then return token end
        end
        local ok: boolean, team: any = pcall(function(): any
            return player.Team
        end)
        return ok and normalized(team) or nil
    end

    local function playerFromValue(value: any): Player?
        if typeof(value) == "Instance" then
            if value:IsA("Player") then
                return value :: Player
            end
            if value:IsA("Model") then
                local ok: boolean, player: any = pcall(function(): any
                    return players:GetPlayerFromCharacter(value :: Model)
                end)
                if ok and player then return player end
                for _, candidate: Player in ipairs(players:GetPlayers()) do
                    if candidate.Character == value then return candidate end
                end
            end
            return nil
        end
        if type(value) == "number" then
            local ok: boolean, player: any = pcall(function(): any
                return players:GetPlayerByUserId(value)
            end)
            return ok and player or nil
        end
        if type(value) ~= "string" then
            return nil
        end
        local text: string = string.match(value, "^%s*(.-)%s*$") or ""
        local userId: number? = tonumber(text)
        if userId then
            local ok: boolean, player: any = pcall(function(): any
                return players:GetPlayerByUserId(userId)
            end)
            if ok and player then return player end
        end
        local lowered: string = string.lower(text)
        for _, candidate: Player in ipairs(players:GetPlayers()) do
            if string.lower(candidate.Name) == lowered
                or string.lower(candidate.DisplayName) == lowered then
                return candidate
            end
        end
        return nil
    end

    local function playerEntries(container: Instance): {Player}
        local members: Instance = container
        for _, descendant: Instance in ipairs(container:GetDescendants()) do
            if string.lower(descendant.Name) == "teammembers" then
                members = descendant
                break
            end
        end
        local result: {Player} = {}
        local seen: {[Player]: boolean} = {}
        local function visit(node: Instance): ()
            for _, child: Instance in ipairs(node:GetChildren()) do
                local key: string = string.lower(child.Name)
                if not TEAM_NAMES[key] then
                    local player: Player? = playerFromValue(readValue(child))
                    if player and not seen[player] then
                        seen[player] = true
                        table.insert(result, player)
                    end
                end
                visit(child)
            end
        end
        visit(members)
        return result
    end

    local function findTeamToken(container: Instance): string?
        for _, name: string in ipairs({
            "Team", "TeamName", "TeamId", "TeamID", "Side", "Faction", "MatchTeam",
        }) do
            local ok: boolean, value: any = pcall(function(): any
                return container:GetAttribute(name)
            end)
            local token: string? = ok and normalized(value) or nil
            if token then return token end
        end
        local function fromEntry(entry: Instance): string?
            if not TEAM_NAMES[string.lower(entry.Name)] then
                return nil
            end
            local value: any = readValue(entry)
            local player: Player? = playerFromValue(value)
            if player then return teamOf(player) end
            return normalized(value)
        end
        local direct: string? = fromEntry(container)
        if direct then return direct end
        for _, descendant: Instance in ipairs(container:GetDescendants()) do
            local token: string? = fromEntry(descendant)
            if token then return token end
        end
        return nil
    end

    local function describe(container: Instance): (string?, {Player})
        local token: string? = findTeamToken(container)
        local entries: {Player} = playerEntries(container)
        if not token then
            for _, player: Player in ipairs(entries) do
                token = teamOf(player)
                if token then break end
            end
        end
        return token, entries
    end

    -- Team membership comes from podium values/players, never from whichever
    -- character model happens to be closest to the local root.
    local function claimRoundTeamFromPodiums(): ()
        podiumEvidence = #podiums > 0
        roundStarted = false
        roundTeam = nil
        if not podiumEvidence then
            roundTeam = teamOf(localPlayer)
            return
        end

        local infos: {any} = {}
        local ownToken: string? = nil
        for _, podium: Model in ipairs(podiums) do
            local token: string?, entries: {Player} = describe(podium)
            table.insert(infos, {token = token, entries = entries})
            if not ownToken then
                for _, player: Player in ipairs(entries) do
                    if player == localPlayer then
                        ownToken = token or teamOf(localPlayer)
                        break
                    end
                end
            end
        end
        local localTeam: string? = teamOf(localPlayer)
        if not ownToken and localTeam then
            for _, info: any in ipairs(infos) do
                if info.token == localTeam then
                    ownToken = localTeam
                    break
                end
            end
        end
        -- This is the actual local team, not a claim based on a nearby model.
        ownToken = ownToken or localTeam
        roundTeam = ownToken
        if not ownToken then return end
        for _, info: any in ipairs(infos) do
            if info.token and info.token ~= ownToken then
                roundStarted = true -- at least one opposing podium entry
                return
            end
        end
    end

    local function ownerPlayer(model: Model): Player?
        for _, child: Instance in ipairs(model:GetChildren()) do
            local key: string = string.lower(child.Name)
            if key == "owner" or key == "player" or key == "user"
                or key == "userid" or key == "owneruserid" then
                local player: Player? = playerFromValue(readValue(child))
                if player then return player end
            end
        end
        for _, name: string in ipairs({"OwnerUserId", "UserId", "PlayerUserId"}) do
            local ok: boolean, value: any = pcall(function(): any
                return model:GetAttribute(name)
            end)
            if ok and value ~= nil then
                local player: Player? = playerFromValue(value)
                if player then return player end
            end
        end
        for _, name: string in ipairs({"Owner", "Player"}) do
            local ok: boolean, value: any = pcall(function(): any
                return model:GetAttribute(name)
            end)
            if ok and value ~= nil then
                local player: Player? = playerFromValue(value)
                if player then return player end
            end
        end
        return playerFromValue(model.Name)
    end

    local function friendlyFarm(model: Model): boolean
        if not roundStarted then
            return false
        end
        local owner: Player? = ownerPlayer(model)
        if owner then
            if owner == localPlayer then return true end
            local ownerTeam: string? = teamOf(owner)
            return roundTeam ~= nil and ownerTeam == roundTeam
        end
        local entries: {Player} = playerEntries(model)
        for _, player: Player in ipairs(entries) do
            if player == localPlayer then return true end
        end
        local token: string? = farmTeams[model] or findTeamToken(model)
        local effectiveTeam: string? = roundTeam or teamOf(localPlayer)
        if token and effectiveTeam then
            return token == effectiveTeam
        end
        if effectiveTeam then
            for _, player: Player in ipairs(entries) do
                local playerTeam: string? = teamOf(player)
                if playerTeam and playerTeam == effectiveTeam then
                    return true
                end
            end
        end
        -- No ownership/team evidence means no teleport, even if it is close.
        return false
    end

    local function rootOf(): BasePart?
        local character: Model? = localPlayer.Character
        if not character then return nil end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return nil end
        local root: Instance? = character:FindFirstChild("HumanoidRootPart")
        return root and root:IsA("BasePart") and root :: BasePart or nil
    end

    local function rememberPosition(root: BasePart): ()
        if savedRoot == root and savedCFrame ~= nil then return end
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
            if descendant:IsA("Model") then addCoin(descendant) end
        end
        for key: Instance, _time: number in pairs(retryAt) do
            if not key.Parent then retryAt[key] = nil end
        end
    end

    local function isAvailable(model: Model, part: BasePart): boolean
        -- The editor stores these spawnables with CanTouch=false. A live
        -- event controller may enable them, so do not discard them permanently.
        if not model.Parent or not part.Parent or part.Transparency >= 0.95 then
            return false
        end
        return model:GetAttribute("Collected") ~= true
            and part:GetAttribute("Collected") ~= true
    end

    local function isFarmAvailable(model: Model, part: BasePart): boolean
        -- PumpCoins are often invisible TouchTransmitter parts: transparency
        -- is not a collected state for this family.
        if not model.Parent or not part.Parent then return false end
        return model:GetAttribute("Collected") ~= true
            and part:GetAttribute("Collected") ~= true
    end

    local function nearestCoin(root: BasePart, now: number): (Model?, BasePart?, number)
        local bestModel: Model? = nil
        local bestPart: BasePart? = nil
        local bestDistance: number = math.huge
        local remaining: number = 0
        for model: Model, part: BasePart in pairs(coins) do
            if isAvailable(model, part) then
                remaining += 1
                if (retryAt[part] or 0) <= now then
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

    local function nearestOwned(root: BasePart, now: number): (Model?, BasePart?, number)
        if not roundStarted then
            return nil, nil, 0
        end
        local bestModel: Model? = nil
        local bestPart: BasePart? = nil
        local bestDistance: number = math.huge
        local remaining: number = 0
        for model: Model, parts: {BasePart} in pairs(farms) do
            if friendlyFarm(model) then
                for _, part: BasePart in ipairs(parts) do
                    if isFarmAvailable(model, part) then
                        remaining += 1
                        if (retryAt[part] or 0) <= now then
                            local distance: number = (part.Position - root.Position).Magnitude
                            if distance < bestDistance then
                                bestDistance = distance
                                bestModel = model
                                bestPart = part
                            end
                        end
                    end
                end
            end
        end
        return bestModel, bestPart, remaining
    end

    local function touchCoin(model: Model, part: BasePart, root: BasePart): ()
        rememberPosition(root)
        local currentCFrame: CFrame = root.CFrame
        local currencyCFrame: CFrame = part.CFrame
        -- Use the currency's own CFrame, including invisible PumpCoins, never
        -- an owner character's HumanoidRootPart as a proxy for the coin.
        root.CFrame = CFrame.fromMatrix(
            currencyCFrame.Position + Vector3.new(0, 1.25, 0),
            currentCFrame.RightVector,
            currentCFrame.UpVector
        )
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        local prompt: Instance? = part:FindFirstChildOfClass("ProximityPrompt")
        local touch: Instance? = part:FindFirstChildOfClass("TouchTransmitter")
        local fireTouch: any = host.firetouchinterest
        local firePrompt: any = host.fireproximityprompt
        if prompt and not touch and type(firePrompt) == "function" then
            pcall(firePrompt, prompt)
        elseif type(fireTouch) == "function" then
            pcall(fireTouch, root, part, 0)
            pcall(fireTouch, root, part, 1)
        end
        retryAt[part] = os.clock() + 4
    end

    local function isPumpContainer(instance: Instance): boolean
        local name: string = string.lower(instance.Name)
        return name == "pumpcoins" or name == "pumpcoin" or name == "pumpkincoins"
    end

    local function ancestorModel(instance: Instance): Model?
        local current: Instance? = instance.Parent
        while current and current ~= currentWorkspace do
            if current:IsA("Model") then return current :: Model end
            current = current.Parent
        end
        return instance:IsA("Model") and instance :: Model or nil
    end

    local function hasInteraction(part: BasePart): boolean
        return part:FindFirstChildOfClass("TouchTransmitter") ~= nil
            or part:FindFirstChildOfClass("ProximityPrompt") ~= nil
    end

    local function currencyParts(model: Model): {BasePart}
        local result: {BasePart} = {}
        local seen: {[BasePart]: boolean} = {}
        local function addContainer(container: Instance): ()
            if container:IsA("BasePart") and hasInteraction(container :: BasePart) then
                seen[container :: BasePart] = true
                table.insert(result, container :: BasePart)
            end
            for _, descendant: Instance in ipairs(container:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    local part: BasePart = descendant :: BasePart
                    if not seen[part] and hasInteraction(part) then
                        seen[part] = true
                        table.insert(result, part)
                    end
                end
            end
        end
        if isPumpContainer(model) then addContainer(model) end
        for _, descendant: Instance in ipairs(model:GetDescendants()) do
            if isPumpContainer(descendant) then addContainer(descendant) end
        end
        return result
    end

    local function refreshStructures(): ()
        table.clear(farms)
        table.clear(farmTeams)
        table.clear(podiums)
        local farmSet: {[Model]: boolean} = {}
        local podiumSet: {[Model]: boolean} = {}
        for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if isPumpContainer(descendant) then
                local model: Model? = ancestorModel(descendant)
                if model then farmSet[model] = true end
            elseif string.lower(descendant.Name) == "teammembers" then
                local model: Model? = ancestorModel(descendant)
                if model then podiumSet[model] = true end
            end
        end
        for model: Model, _present: boolean in pairs(farmSet) do
            local parts: {BasePart} = currencyParts(model)
            if #parts > 0 then
                farms[model] = parts
                farmTeams[model] = findTeamToken(model)
            end
        end
        for model: Model, _present: boolean in pairs(podiumSet) do
            table.insert(podiums, model)
        end
        claimRoundTeamFromPodiums()
    end

    local function update(_deltaTime: number): ()
        if not settings.enabled then return end
        local now: number = os.clock()
        if now >= nextRefreshAt then
            nextRefreshAt = now + 10
            refreshCoins()
        end
        if now >= nextStructureAt then
            nextStructureAt = now + 2
            refreshStructures()
        end
        if now < nextFarmAt then return end
        local root: BasePart? = rootOf()
        if not root then
            setStatus("No character")
            nextFarmAt = now + 0.5
            return
        end

        local farmModel: Model?, farmPart: BasePart?, farmRemaining: number =
            nearestOwned(root, now)
        if farmModel and farmPart then
            touchCoin(farmModel, farmPart, root)
            nextFarmAt = now + settings.interval
            setStatus("Farming team coins · " .. tostring(farmRemaining))
            return
        end

        local model: Model?, part: BasePart?, remaining: number = nearestCoin(root, now)
        if model and part then
            touchCoin(model, part, root)
            nextFarmAt = now + settings.interval
            setStatus("Farming · " .. tostring(remaining) .. " visible")
            return
        end
        if not roundStarted and next(farms) ~= nil then
            setStatus("Waiting for round team")
        elseif farmRemaining > 0 or remaining > 0 then
            setStatus("Retrying currency")
        else
            setStatus("No currency")
        end
        nextFarmAt = now + 0.5
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
        table.clear(farms)
        table.clear(farmTeams)
        table.clear(podiums)
        table.clear(retryAt)
    end

    farmCard = host.createUniversalFeature(
        "Auto Farm",
        "Farm friendly PumpCoins and Halloween PumpkinCurrency through native contact",
        1,
        function(enabled: boolean): ()
            settings.enabled = enabled
            nextRefreshAt = 0
            nextStructureAt = 0
            nextFarmAt = 0
            table.clear(retryAt)
            if enabled then
                savedRoot = nil
                savedCharacter = nil
                savedCFrame = nil
                setStatus("Scanning currency")
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
        "PumpCoins use podium player/team evidence; nearby enemy models are rejected. Attempts are not confirmed currency."
    )

    table.insert(connections, currentWorkspace.DescendantAdded:Connect(function(instance: Instance): ()
        nextStructureAt = 0
        if settings.enabled then addCoinFromDescendant(instance) end
    end))
    table.insert(connections, currentWorkspace.DescendantRemoving:Connect(function(instance: Instance): ()
        nextStructureAt = 0
        if instance:IsA("Model") then coins[instance :: Model] = nil end
        retryAt[instance] = nil
    end))
    table.insert(connections, localPlayer.CharacterAdded:Connect(function(): ()
        savedRoot = nil
        savedCharacter = nil
        savedCFrame = nil
        nextRefreshAt = 0
        nextStructureAt = 0
        nextFarmAt = 0
        table.clear(retryAt)
    end))
    host.featureConnections.X2DuelsAutoFarm = runtime.TaskManager:Connect(update)
end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
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
