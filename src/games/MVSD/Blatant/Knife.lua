local Module = {
    Name = "MVSD Knife",
    PlaceId = 135856908115931,
    Events = {} :: {[string]: any},
    Initialized = false,
    Menu = nil :: any,
    Runtime = nil :: any,
}

local moduleCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    Module.Runtime = runtime
    Module.Menu = runtime and runtime.Menu

    local players: Players = game:GetService("Players")
    local runService: RunService = game:GetService("RunService")
    local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
    local localPlayer: Player = players.LocalPlayer
    local camera: Camera = workspace.CurrentCamera or (workspace:WaitForChild("Camera") :: Camera)

    local featureConnections: {[string]: any} = {}

    local settings = {
        enabled = false,
        hitboxIncrease = true,
        hitboxSize = 20,
        silentAim = true,
        knifeRate = 0.1,
    }

    local originalHitboxes: {[BasePart]: Vector3} = {}

    local function isSameTeam(a: Player, b: Player): boolean
        -- base.lua resolves the side from every source Duels exposes; the
        -- attribute-only check below is only the fallback when it is missing.
        local core: any = state and state.mvsdCore
        if core and type(core.isTeammate) == "function" then
            local other: Player? = nil
            if a == localPlayer then
                other = b
            elseif b == localPlayer then
                other = a
            end
            if other ~= nil then
                return core.isTeammate(other) == true
            end
        end
        local aAttr: any = a:GetAttribute("Team")
        local bAttr: any = b:GetAttribute("Team")
        if aAttr ~= nil and bAttr ~= nil then
            return aAttr == bAttr
        end
        if a.Team ~= nil and b.Team ~= nil then
            return a.Team == b.Team
        end
        return false
    end

    local function isInMatch(player: Player): boolean
        local localGame: any = localPlayer:GetAttribute("Game")
        local playerGame: any = player:GetAttribute("Game")
        if localGame ~= nil and playerGame ~= nil then
            return localGame == playerGame
        end
        return true
    end

    local function getActiveEnemies(): {Player}
        local enemies: {Player} = {}
        for _, player: Player in ipairs(players:GetPlayers()) do
            if player ~= localPlayer
                and player:GetAttribute("Died") ~= true
                and isInMatch(player)
                and not isSameTeam(localPlayer, player) then
                local character: Model? = player.Character
                local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
                local root: BasePart? = character and (character:FindFirstChild("HumanoidRootPart") :: BasePart? or character:FindFirstChild("Head") :: BasePart?)
                if character and humanoid and humanoid.Health > 0 and root then
                    table.insert(enemies, player)
                end
            end
        end
        return enemies
    end

    local function restoreAllHitboxes(): ()
        for part: BasePart, origSize: Vector3 in pairs(originalHitboxes) do
            if part and part.Parent then
                pcall(function(): ()
                    part.Size = origSize
                    part.Transparency = 1
                    part.CanCollide = false
                end)
            end
        end
        table.clear(originalHitboxes)
    end

    local function updateHitboxes(): ()
        if not settings.enabled or not settings.hitboxIncrease then
            restoreAllHitboxes()
            return
        end

        local enemies: {Player} = getActiveEnemies()
        local activeSet: {[BasePart]: boolean} = {}

        for _, enemy: Player in ipairs(enemies) do
            local character: Model = enemy.Character :: Model
            local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if root then
                activeSet[root] = true
                if not originalHitboxes[root] then
                    originalHitboxes[root] = root.Size
                end
                pcall(function(): ()
                    root.Size = Vector3.new(settings.hitboxSize, settings.hitboxSize, settings.hitboxSize)
                    root.Transparency = 0.7
                    root.CanCollide = false
                end)
            end
        end

        -- Clean up players no longer in match
        for part: BasePart, origSize: Vector3 in pairs(originalHitboxes) do
            if not activeSet[part] then
                if part and part.Parent then
                    pcall(function(): ()
                        part.Size = origSize
                        part.Transparency = 1
                        part.CanCollide = false
                    end)
                end
                originalHitboxes[part] = nil
            end
        end
    end

    -- Knife Throw remotes
    local function getKnifeThrowRemotes(): (RemoteEvent?, RemoteEvent?, RemoteEvent?)
        local packages: Instance? = replicatedStorage:FindFirstChild("Packages")
        local net: Instance? = packages and packages:FindFirstChild("Net")
        if not net then return nil, nil, nil end

        local prepRemote: RemoteEvent? = nil
        local throwRemote: RemoteEvent? = nil
        local hitRemote: RemoteEvent? = nil

        for _, child: Instance in ipairs(net:GetChildren()) do
            if child:IsA("RemoteEvent") then
                if string.find(child.Name, "78a946aa") then
                    prepRemote = child
                elseif string.find(child.Name, "bfabffda") then
                    throwRemote = child
                elseif string.find(child.Name, "90e51178") then
                    hitRemote = child
                end
            end
        end

        return prepRemote, throwRemote, hitRemote
    end

    local lastKnifeThrowTime: number = 0

    local function executeKnifeSilentAim(): ()
        if not settings.enabled or not settings.silentAim then return end
        local now: number = os.clock()
        if now - lastKnifeThrowTime < settings.knifeRate then return end
        lastKnifeThrowTime = now

        local enemies: {Player} = getActiveEnemies()
        if #enemies == 0 then return end
        local targetEnemy: Player = enemies[math.random(1, #enemies)]
        local character: Model = targetEnemy.Character :: Model
        local targetRoot: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            or character:FindFirstChild("Head") :: BasePart?
        if not targetRoot then return end

        local myChar: Model? = localPlayer.Character
        local myRoot: BasePart? = myChar and (myChar:FindFirstChild("HumanoidRootPart") :: BasePart? or myChar.PrimaryPart :: BasePart?)
        local origin: Vector3 = myRoot and myRoot.Position or camera.CFrame.Position
        local targetPos: Vector3 = targetRoot.Position

        local prepRemote, throwRemote, hitRemote = getKnifeThrowRemotes()
        local actionId: string = "knife_" .. tostring(math.random(100000, 999999))

        if prepRemote then
            pcall(function(): ()
                prepRemote:FireServer(actionId)
            end)
        end

        if throwRemote then
            pcall(function(): ()
                local knifeCFrame: CFrame = CFrame.new(origin, targetPos)
                throwRemote:FireServer(actionId, knifeCFrame, targetPos)
            end)
        end

        if hitRemote then
            pcall(function(): ()
                local dir: Vector3 = (targetPos - origin).Unit
                hitRemote:FireServer(actionId, targetEnemy, dir, origin, targetPos)
            end)
        end
    end

    local function onHeartbeat(): ()
        if not settings.enabled then return end
        updateHitboxes()

        -- Cooldown bypass for equipped knife
        local character: Model? = localPlayer.Character
        local tool: Tool? = character and character:FindFirstChildOfClass("Tool")
        if tool and string.find(tool.Name:lower(), "knife") then
            tool:SetAttribute("CanSlash", true)
            tool:SetAttribute("CanThrow", true)
            tool:SetAttribute("Cooldown", 0)
        end
    end

    -- Hook knife activation
    local userInput: UserInputService = game:GetService("UserInputService")
    local function onInputBegan(input: InputObject, gameProcessed: boolean): ()
        if not settings.enabled or gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
            local character: Model? = localPlayer.Character
            local tool: Tool? = character and character:FindFirstChildOfClass("Tool")
            if tool and string.find(tool.Name:lower(), "knife") then
                executeKnifeSilentAim()
            end
        end
    end

    local env: any = getfenv()
    local createUniversalFeature: any = env.createUniversalFeature
    local addToggleOption: any = env.addToggleOption
    local addNumberOption: any = env.addNumberOption

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    local KnifeFeature: any = createUniversalFeature(
        "Knife",
        "Hitbox increase and remote silent aim knife teleportation",
        3,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if not enabled then
                restoreAllHitboxes()
            end
        end,
        {
            parent = parentScroll,
            registry = featuresRegistry,
            categoryName = "Blatant",
        }
    )

    addToggleOption(KnifeFeature, "Hitbox Increase", true, function(value: boolean): ()
        settings.hitboxIncrease = value
        if not value then
            restoreAllHitboxes()
        end
    end, "Expands enemy humanoid hitbox for massive slash range")

    addNumberOption(KnifeFeature, "Hitbox Size", 20, 5, 45, function(value: number): ()
        settings.hitboxSize = value
    end, "Hitbox size in studs", 1)

    addToggleOption(KnifeFeature, "SilentAIM", true, function(value: boolean): ()
        settings.silentAim = value
    end, "Teleports knives directly to enemies via remote")

    addNumberOption(KnifeFeature, "Knife Rate", 0.1, 0.02, 1, function(value: number): ()
        settings.knifeRate = value
    end, "Knife attack cooldown rate in seconds", 0.02)

    featureConnections.Heartbeat = runService.Heartbeat:Connect(onHeartbeat)
    featureConnections.InputBegan = userInput.InputBegan:Connect(onInputBegan)

    moduleCleanup = function(): ()
        restoreAllHitboxes()
        for _, conn: any in pairs(featureConnections) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
        table.clear(featureConnections)
    end

    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(moduleCleanup)
    moduleCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
    Module.Menu = nil
end

return Module
