local Module = {
    Name = "MVSD Shoot",
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
    local userInput: UserInputService = game:GetService("UserInputService")
    local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
    local httpService: HttpService = game:GetService("HttpService")
    local localPlayer: Player = players.LocalPlayer
    local camera: Camera = workspace.CurrentCamera or (workspace:WaitForChild("Camera") :: Camera)

    local env: any = getfenv()
    local state: any = env.state
    local core: any = state and state.mvsdCore
    local createUniversalFeature: any = env.createUniversalFeature
    local addToggleOption: any = env.addToggleOption
    local addActionOption: any = env.addActionOption
    local addNumberOption: any = env.addNumberOption
    local notify: any = env.notify or function(_text: string) end

    local featureConnections: {[string]: any} = {}

    local settings = {
        enabled = false,
        wallCheck = true,
        macro = true,
        autoEquip = true,
        fireRate = 0.15,
    }

    local ShootFeature: any = nil

    local function setStatus(text: string?): ()
        if ShootFeature and type(ShootFeature.SetStatus) == "function" then
            ShootFeature:SetStatus(text)
        end
    end

    local function getHitRemote(): RemoteEvent?
        local packages: Instance? = replicatedStorage:FindFirstChild("Packages")
        local net: Instance? = packages and packages:FindFirstChild("Net")
        if not net then
            return nil
        end
        local re: Instance? = net:FindFirstChild("RE")
        local container: Instance = re or net
        for _, child: Instance in ipairs(container:GetChildren()) do
            if child:IsA("RemoteEvent") and string.find(child.Name, "90e51178", 1, true) then
                return child
            end
        end
        return nil
    end

    local function checkLineOfSight(origin: Vector3, targetPos: Vector3, ignoreModel: Model?): boolean
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local filterList: {Instance} = {camera}
        if localPlayer.Character then
            table.insert(filterList, localPlayer.Character)
        end
        if ignoreModel then
            table.insert(filterList, ignoreModel)
        end
        rayParams.FilterDescendantsInstances = filterList
        rayParams.IgnoreWater = true
        local direction: Vector3 = targetPos - origin
        local result: RaycastResult? = workspace:Raycast(origin, direction, rayParams)
        return result == nil
    end

    local function pickTarget(respectWall: boolean): (Player?, BasePart?, boolean)
        local enemies: {Player} = core and core.enemies() or {}
        if #enemies == 0 then
            return nil, nil, false
        end
        local camPos: Vector3 = camera.CFrame.Position
        local bestPlayer: Player? = nil
        local bestPart: BasePart? = nil
        local bestDist: number = math.huge
        local anyOccluded: boolean = false
        for _, enemy: Player in ipairs(enemies) do
            local character: Model? = enemy.Character
            local part: BasePart? = character and (character:FindFirstChild("Head") :: BasePart?
                or character:FindFirstChild("HumanoidRootPart") :: BasePart?)
            if part then
                local clear: boolean = checkLineOfSight(camPos, part.Position, character)
                if not clear then
                    anyOccluded = true
                end
                if not respectWall or clear then
                    local dist: number = (part.Position - camPos).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestPlayer = enemy
                        bestPart = part
                    end
                end
            end
        end
        return bestPlayer, bestPart, anyOccluded
    end

    local function fireAt(targetPlayer: Player, targetPart: BasePart, tool: Instance?): ()
        local handle: BasePart? = tool and (tool:FindFirstChild("Handle") :: BasePart?) or nil
        local origin: Vector3 = handle and handle.Position or camera.CFrame.Position
        local targetPos: Vector3 = targetPart.Position

        local fireRemote: Instance? = tool and tool:FindFirstChild("fire")
        if fireRemote and fireRemote:IsA("RemoteEvent") then
            pcall(function(): ()
                fireRemote:FireServer()
            end)
        end

        local showBeamRemote: Instance? = tool and tool:FindFirstChild("showBeam")
        if showBeamRemote and showBeamRemote:IsA("RemoteEvent") then
            pcall(function(): ()
                showBeamRemote:FireServer(origin, targetPos, handle)
            end)
        end

        local hitRemote: RemoteEvent? = getHitRemote()
        if hitRemote then
            local guid: string = httpService:GenerateGUID(false)
            local direction: Vector3 = (targetPos - origin).Unit
            pcall(function(): ()
                hitRemote:FireServer(guid, targetPlayer, direction, origin, targetPos)
            end)
        end
    end

    local lastShot: number = 0

    local function executeLegalShot(): ()
        local gun: Instance? = core and core.findGun() or nil
        if not gun then
            setStatus("No pistol found")
            return
        end
        if settings.autoEquip and not core.isEquipped(gun) then
            core.equip(gun)
        end

        local targetPlayer: Player?, targetPart: BasePart?, anyOccluded: boolean =
            pickTarget(settings.wallCheck)

        if not targetPlayer or not targetPart then
            if settings.wallCheck and anyOccluded then
                setStatus("A wall is blocking the target")
            else
                setStatus("No target")
            end
            return
        end

        setStatus(nil)
        fireAt(targetPlayer, targetPart, gun)

        if settings.macro then
            task.delay(0.01, function(): ()
                pcall(function(): ()
                    local character: Model? = localPlayer.Character
                    if character and gun.Parent == character then
                        local backpack: Instance? = localPlayer:FindFirstChildOfClass("Backpack")
                        if backpack then
                            gun.Parent = backpack
                        end
                    end
                end)
            end)
        end
    end

    local function onHeartbeat(): ()
        if not settings.enabled then
            return
        end
        local now: number = os.clock()
        if now - lastShot < settings.fireRate then
            return
        end
        lastShot = now
        executeLegalShot()
    end

    local function onInputBegan(input: InputObject, gameProcessed: boolean): ()
        if not settings.enabled or gameProcessed then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            executeLegalShot()
        end
    end

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    ShootFeature = createUniversalFeature(
        "Shoot",
        "Legal Duels shots: equips the pistol, respects walls and unequips right after",
        2,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if not enabled then
                setStatus(nil)
            end
        end,
        {
            parent = parentScroll,
            registry = featuresRegistry,
            categoryName = "Other",
        }
    )

    addToggleOption(ShootFeature, "WallCheck", true, function(value: boolean): ()
        settings.wallCheck = value
        if not value then
            setStatus(nil)
        end
    end, "Refuse to fire when a wall blocks the target and show it on the card")

    addToggleOption(ShootFeature, "Auto Equip", true, function(value: boolean): ()
        settings.autoEquip = value
    end, "Equips the pistol automatically if it is in your backpack")

    addToggleOption(ShootFeature, "Macro", true, function(value: boolean): ()
        settings.macro = value
    end, "Unequips the gun 0.01 seconds after firing")

    addNumberOption(ShootFeature, "Fire Rate", 0.15, 0.05, 1, function(value: number): ()
        settings.fireRate = value
    end, "Seconds between automatic shots", 0.05)

    addActionOption(ShootFeature, "Fire Shot", function(): ()
        executeLegalShot()
    end, "Fires one legal shot now")

    featureConnections.Heartbeat = runService.Heartbeat:Connect(onHeartbeat)
    featureConnections.InputBegan = userInput.InputBegan:Connect(onInputBegan)

    moduleCleanup = function(): ()
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
