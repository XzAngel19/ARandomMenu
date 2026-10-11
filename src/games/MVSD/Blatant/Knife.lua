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
    local httpService: HttpService = game:GetService("HttpService")
    local localPlayer: Player = players.LocalPlayer
    local camera: Camera = workspace.CurrentCamera or (workspace:WaitForChild("Camera") :: Camera)

    local env: any = getfenv()
    local state: any = env.state
    local core: any = state and state.mvsdCore
    local createUniversalFeature: any = env.createUniversalFeature
    local addToggleOption: any = env.addToggleOption
    local addNumberOption: any = env.addNumberOption

    local featureConnections: {[string]: any} = {}

    local settings = {
        enabled = false,
        hitboxIncrease = true,
        hitboxSize = 20,
        silentAim = true,
        autoEquip = true,
        knifeRate = 0.1,
    }

    local KnifeFeature: any = nil
    local originalHitboxes: {[BasePart]: Vector3} = {}

    local function setStatus(text: string?): ()
        if KnifeFeature and type(KnifeFeature.SetStatus) == "function" then
            KnifeFeature:SetStatus(text)
        end
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
        local enemies: {Player} = core and core.enemies() or {}
        local activeSet: {[BasePart]: boolean} = {}
        for _, enemy: Player in ipairs(enemies) do
            local character: Model? = enemy.Character
            local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
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
        for part: BasePart, _origSize: Vector3 in pairs(originalHitboxes) do
            if not activeSet[part] then
                if part and part.Parent then
                    pcall(function(): ()
                        part.Size = originalHitboxes[part]
                        part.Transparency = 1
                        part.CanCollide = false
                    end)
                end
                originalHitboxes[part] = nil
            end
        end
    end

    local function getKnifeRemotes(): (RemoteEvent?, RemoteEvent?, RemoteEvent?)
        local packages: Instance? = replicatedStorage:FindFirstChild("Packages")
        local net: Instance? = packages and packages:FindFirstChild("Net")
        if not net then
            return nil, nil, nil
        end
        local re: Instance? = net:FindFirstChild("RE")
        local container: Instance = re or net
        local prepRemote: RemoteEvent? = nil
        local throwRemote: RemoteEvent? = nil
        local hitRemote: RemoteEvent? = nil
        for _, child: Instance in ipairs(container:GetChildren()) do
            if child:IsA("RemoteEvent") then
                if string.find(child.Name, "78a946aa", 1, true) then
                    prepRemote = child
                elseif string.find(child.Name, "bfabffda", 1, true) then
                    throwRemote = child
                elseif string.find(child.Name, "90e51178", 1, true) then
                    hitRemote = child
                end
            end
        end
        return prepRemote, throwRemote, hitRemote
    end

    local lastKnife: number = 0

    local function executeKnifeSilentAim(): ()
        if not settings.silentAim then
            return
        end
        local knife: Instance? = core and core.findKnife() or nil
        if not knife then
            setStatus("No knife found")
            return
        end
        if settings.autoEquip and not core.isEquipped(knife) then
            core.equip(knife)
        end

        local enemies: {Player} = core and core.enemies() or {}
        if #enemies == 0 then
            setStatus("No target")
            return
        end
        local targetEnemy: Player = enemies[math.random(1, #enemies)]
        local character: Model? = targetEnemy.Character
        local targetRoot: BasePart? = character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?
            or character:FindFirstChild("Head") :: BasePart?)
        if not targetRoot then
            return
        end

        setStatus(nil)
        local myChar: Model? = localPlayer.Character
        local myRoot: BasePart? = myChar and (myChar:FindFirstChild("HumanoidRootPart") :: BasePart? or myChar.PrimaryPart :: BasePart?)
        local origin: Vector3 = myRoot and myRoot.Position or camera.CFrame.Position
        local targetPos: Vector3 = targetRoot.Position

        local prepRemote, throwRemote, hitRemote = getKnifeRemotes()
        local guid: string = httpService:GenerateGUID(false)

        if prepRemote then
            pcall(function(): ()
                prepRemote:FireServer(guid)
            end)
        end
        if throwRemote then
            pcall(function(): ()
                local knifeCFrame: CFrame = CFrame.new(origin, targetPos)
                throwRemote:FireServer(guid, knifeCFrame, (targetPos - origin).Unit)
            end)
        end
        if hitRemote then
            pcall(function(): ()
                local direction: Vector3 = (targetPos - origin).Unit
                hitRemote:FireServer(guid, targetEnemy, direction, origin, targetPos)
            end)
        end
    end

    local function onHeartbeat(): ()
        if not settings.enabled then
            return
        end
        updateHitboxes()

        local now: number = os.clock()
        if now - lastKnife < settings.knifeRate then
            return
        end
        lastKnife = now
        executeKnifeSilentAim()

        local knife: Instance? = core and core.findKnife() or nil
        if knife then
            pcall(function(): ()
                knife:SetAttribute("CanSlash", true)
                knife:SetAttribute("CanThrow", true)
                knife:SetAttribute("Cooldown", 0)
            end)
        end
    end

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    KnifeFeature = createUniversalFeature(
        "Knife",
        "Expands enemy hitboxes and teleports knife hits onto them",
        3,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if not enabled then
                restoreAllHitboxes()
                setStatus(nil)
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
    end, "Grows enemy root parts for a massive slash range")

    addNumberOption(KnifeFeature, "Hitbox Size", 20, 5, 45, function(value: number): ()
        settings.hitboxSize = value
    end, "Hitbox size in studs", 1)

    addToggleOption(KnifeFeature, "SilentAIM", true, function(value: boolean): ()
        settings.silentAim = value
    end, "Teleports knife hits to enemies via remote")

    addToggleOption(KnifeFeature, "Auto Equip", true, function(value: boolean): ()
        settings.autoEquip = value
    end, "Equips the knife automatically")

    addNumberOption(KnifeFeature, "Knife Rate", 0.1, 0.02, 1, function(value: number): ()
        settings.knifeRate = value
    end, "Seconds between knife attacks", 0.02)

    featureConnections.Heartbeat = runService.Heartbeat:Connect(onHeartbeat)

    moduleCleanup = function(): ()
        restoreAllHitboxes()
        setStatus(nil)
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
    Module.Menu = nil
    Module.Runtime = nil
end

return Module
