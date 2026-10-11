local Module = {
    Name = "MVSD Silent Aim",
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
    local addNumberOption: any = env.addNumberOption

    local featureConnections: {[string]: any} = {}

    local settings = {
        enabled = false,
        wallCheck = false,
        shootRate = 0.1,
        noReload = true,
        autoEquip = true,
        fovRadius = 250,
        showFov = true,
    }

    local fovCircle: any = nil
    pcall(function(): ()
        local g: any = getfenv()
        local DrawingLib: any = g.Drawing
        if type(DrawingLib) == "table" or type(DrawingLib) == "userdata" then
            local circle: any = DrawingLib.new("Circle")
            circle.Thickness = 1.5
            circle.NumSides = 32
            circle.Radius = settings.fovRadius
            circle.Filled = false
            circle.Color = Color3.fromRGB(255, 60, 60)
            circle.Transparency = 0.8
            circle.Visible = false
            fovCircle = circle
        end
    end)

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

    -- Targets inside the FOV circle; nearest to the cursor wins.
    local function pickTarget(): (Player?, BasePart?)
        local enemies: {Player} = core and core.enemies() or {}
        if #enemies == 0 then
            return nil, nil
        end
        local mousePos: Vector2 = userInput:GetMouseLocation()
        local camPos: Vector3 = camera.CFrame.Position
        local eligible: {{player: Player, part: BasePart, dist2d: number}} = {}
        for _, enemy: Player in ipairs(enemies) do
            local character: Model? = enemy.Character
            local part: BasePart? = character and (character:FindFirstChild("Head") :: BasePart?
                or character:FindFirstChild("HumanoidRootPart") :: BasePart?)
            if part then
                local screenPos: Vector3 = camera:WorldToViewportPoint(part.Position)
                if screenPos.Z > 0 then
                    local viewport: Vector2 = camera.ViewportSize
                    local screen2d: Vector2 = Vector2.new(
                        screenPos.X * viewport.X,
                        screenPos.Y * viewport.Y
                    )
                    local dist2d: number = (screen2d - mousePos).Magnitude
                    if dist2d <= settings.fovRadius then
                        if not settings.wallCheck or checkLineOfSight(camPos, part.Position, character) then
                            table.insert(eligible, {player = enemy, part = part, dist2d = dist2d})
                        end
                    end
                end
            end
        end
        if #eligible == 0 then
            return nil, nil
        end
        table.sort(eligible, function(a: any, b: any): boolean
            return a.dist2d < b.dist2d
        end)
        return eligible[1].player, eligible[1].part
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

    local function onHeartbeat(): ()
        if fovCircle then
            local mousePos: Vector2 = userInput:GetMouseLocation()
            fovCircle.Position = mousePos
            fovCircle.Radius = settings.fovRadius
            fovCircle.Visible = settings.enabled and settings.showFov
        end

        if not settings.enabled then
            return
        end
        local now: number = os.clock()
        if now - lastShot < settings.shootRate then
            return
        end
        lastShot = now

        local gun: Instance? = core and core.findGun() or nil
        if gun and settings.autoEquip and not core.isEquipped(gun) then
            core.equip(gun)
        end

        local targetPlayer: Player?, targetPart: BasePart? = pickTarget()
        if not targetPlayer or not targetPart then
            return
        end

        if gun and settings.noReload then
            pcall(function(): ()
                local maxAmmo: any = gun:GetAttribute("MaxAmmo")
                if maxAmmo ~= nil then
                    gun:SetAttribute("Ammo", maxAmmo)
                end
                gun:SetAttribute("Reloading", false)
                gun:SetAttribute("CanShoot", true)
                gun:SetAttribute("Cooldown", 0)
            end)
        end

        fireAt(targetPlayer, targetPart, gun)
    end

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    local SilentAimFeature: any = createUniversalFeature(
        "Silent Aim",
        "Automatically equips the pistol and lands hits on enemies inside the FOV",
        1,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if fovCircle then
                fovCircle.Visible = enabled and settings.showFov
            end
        end,
        {
            parent = parentScroll,
            registry = featuresRegistry,
            categoryName = "Blatant",
        }
    )

    addToggleOption(SilentAimFeature, "WallCheck", false, function(value: boolean): ()
        settings.wallCheck = value
    end, "Only target enemies with clear line of sight")

    addToggleOption(SilentAimFeature, "Auto Equip", true, function(value: boolean): ()
        settings.autoEquip = value
    end, "Equips the pistol automatically so shots actually fire")

    addNumberOption(SilentAimFeature, "Shoot Rate", 0.1, 0.01, 1, function(value: number): ()
        settings.shootRate = value
    end, "Seconds between shots", 0.01)

    addToggleOption(SilentAimFeature, "No Reload", true, function(value: boolean): ()
        settings.noReload = value
    end, "Keeps ammo maxed and skips reload")

    addNumberOption(SilentAimFeature, "FOV", 250, 50, 600, function(value: number): ()
        settings.fovRadius = value
        if fovCircle then
            fovCircle.Radius = value
        end
    end, "Target selection radius in pixels", 10)

    addToggleOption(SilentAimFeature, "Show FOV", true, function(value: boolean): ()
        settings.showFov = value
        if fovCircle then
            fovCircle.Visible = settings.enabled and value
        end
    end, "Renders the FOV circle")

    featureConnections.Heartbeat = runService.Heartbeat:Connect(onHeartbeat)

    moduleCleanup = function(): ()
        for _, conn: any in pairs(featureConnections) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
        table.clear(featureConnections)
        if fovCircle then
            pcall(function(): ()
                fovCircle.Visible = false
                fovCircle:Remove()
            end)
            fovCircle = nil
        end
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
