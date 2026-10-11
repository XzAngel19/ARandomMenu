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
    local localPlayer: Player = players.LocalPlayer
    local camera: Camera = workspace.CurrentCamera or (workspace:WaitForChild("Camera") :: Camera)

    local featureConnections: {[string]: any} = {}
    local TaskManager: any = runtime and runtime.TaskManager
        or {
            Connect = function(_self: any, signal: any, fn: any): any
                return signal:Connect(fn)
            end,
        }

    local settings = {
        enabled = false,
        wallCheck = false,
        shootRate = 0.1,
        noReload = true,
        fovRadius = 250,
        showFov = true,
    }

    local fovCircle: DrawingCircle? = nil
    pcall(function(): ()
        if typeof(Drawing) == "table" and type(Drawing.new) == "function" then
            local circle: DrawingCircle = Drawing.new("Circle") :: any
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

    local function pickTarget(): (Player?, BasePart?)
        local enemies: {Player} = getActiveEnemies()
        if #enemies == 0 then
            return nil, nil
        end

        local mousePos: Vector2 = userInput:GetMouseLocation()
        local camPos: Vector3 = camera.CFrame.Position
        local eligible: {{player: Player, part: BasePart, dist2d: number}} = {}

        for _, enemy: Player in ipairs(enemies) do
            local character: Model = enemy.Character :: Model
            local targetPart: BasePart = (character:FindFirstChild("Head") :: BasePart?)
                or (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
                or (character.PrimaryPart :: BasePart)
            if targetPart then
                local screenPos: Vector3, onScreen: boolean = camera:WorldToViewportPoint(targetPart.Position)
                if screenPos.Z > 0 then
                    local dist2d: number = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist2d <= settings.fovRadius then
                        if not settings.wallCheck or checkLineOfSight(camPos, targetPart.Position, character) then
                            table.insert(eligible, {player = enemy, part = targetPart, dist2d = dist2d})
                        end
                    end
                end
            end
        end

        if #eligible == 0 then
            return nil, nil
        end

        -- Pick a random enemy among the eligible ones (user requested: le de a un enemigo Random)
        local chosen = eligible[math.random(1, #eligible)]
        return chosen.player, chosen.part
    end

    -- Find Net RE remote for damage confirmation
    local function getNetHitRemote(): RemoteEvent?
        local packages: Instance? = replicatedStorage:FindFirstChild("Packages")
        local net: Instance? = packages and packages:FindFirstChild("Net")
        if net then
            local hitRemote: Instance? = net:FindFirstChild("RE/90e51178756085355b8b52b11bf99988da480bb4072b33bcbc7ec931a7da2d68")
            if hitRemote and hitRemote:IsA("RemoteEvent") then
                return hitRemote
            end
            for _, child: Instance in ipairs(net:GetChildren()) do
                if child:IsA("RemoteEvent") and string.find(child.Name, "90e51178") then
                    return child
                end
            end
        end
        return nil
    end

    -- Hook Raycast so wall shots hit enemy
    local originalRaycast: any = nil
    local originalNamecall: any = nil

    local function installRaycastHook(): ()
        if originalRaycast ~= nil then return end
        local genv: any = getgenv and getgenv() or getfenv()
        local hookfn: any = genv.hookfunction or genv.replaceclosure or hookfunc
        if type(hookfn) ~= "function" then
            return
        end

        originalRaycast = hookfn(workspace.Raycast, function(self: any, origin: Vector3, direction: Vector3, params: RaycastParams?): any
            if settings.enabled then
                local _, targetPart = pickTarget()
                if targetPart then
                    local fakeDist: number = (targetPart.Position - origin).Magnitude
                    return {
                        Instance = targetPart,
                        Position = targetPart.Position,
                        Normal = Vector3.new(0, 1, 0),
                        Material = Enum.Material.Plastic,
                        Distance = fakeDist,
                    }
                end
            end
            return originalRaycast(self, origin, direction, params)
        end)
    end

    local function uninstallRaycastHook(): ()
        if originalRaycast ~= nil then
            local genv: any = getgenv and getgenv() or getfenv()
            local hookfn: any = genv.hookfunction or genv.replaceclosure or hookfunc
            if type(hookfn) == "function" then
                pcall(hookfn, workspace.Raycast, originalRaycast)
            end
            originalRaycast = nil
        end
    end

    local lastShotTime: number = 0

    local function handleWeaponActivation(tool: Tool): ()
        if not settings.enabled then return end
        local now: number = os.clock()
        if now - lastShotTime < settings.shootRate then return end
        lastShotTime = now

        local targetPlayer, targetPart = pickTarget()
        if not targetPlayer or not targetPart then return end

        local handle: BasePart? = tool:FindFirstChild("Handle") :: BasePart?
        local origin: Vector3 = handle and handle.Position or camera.CFrame.Position
        local targetPos: Vector3 = targetPart.Position

        -- Gun fire and showBeam remotes
        local fireRemote: Instance? = tool:FindFirstChild("fire")
        if fireRemote and fireRemote:IsA("RemoteEvent") then
            pcall(function(): ()
                fireRemote:FireServer()
            end)
        end

        local showBeamRemote: Instance? = tool:FindFirstChild("showBeam")
        if showBeamRemote and showBeamRemote:IsA("RemoteEvent") and handle then
            pcall(function(): ()
                showBeamRemote:FireServer(origin, targetPos, handle)
            end)
        end

        -- Direct Net Hit Remote
        local netHit: RemoteEvent? = getNetHitRemote()
        if netHit then
            local actionId: string = "silent_" .. tostring(math.random(100000, 999999))
            local direction: Vector3 = (targetPos - origin).Unit
            pcall(function(): ()
                netHit:FireServer(actionId, targetPlayer, direction, origin, targetPos)
            end)
        end

        -- No reload bypass & cooldown bypass
        if settings.noReload then
            pcall(function(): ()
                tool:SetAttribute("Ammo", tool:GetAttribute("MaxAmmo") or 6)
                tool:SetAttribute("Reloading", false)
            end)
        end
        pcall(function(): ()
            tool:SetAttribute("CanShoot", true)
            tool:SetAttribute("Cooldown", 0)
        end)
    end

    -- Hook tool activation & continuous loop
    local function onHeartbeat(): ()
        if fovCircle then
            local mousePos: Vector2 = userInput:GetMouseLocation()
            fovCircle.Position = mousePos
            fovCircle.Radius = settings.fovRadius
            fovCircle.Visible = settings.enabled and settings.showFov
        end

        if not settings.enabled then return end

        local character: Model? = localPlayer.Character
        local tool: Tool? = character and character:FindFirstChildOfClass("Tool")
        if tool then
            if settings.noReload then
                if tool:GetAttribute("Reloading") == true then
                    tool:SetAttribute("Reloading", false)
                end
                local maxAmmo: any = tool:GetAttribute("MaxAmmo")
                if maxAmmo and tool:GetAttribute("Ammo") ~= maxAmmo then
                    tool:SetAttribute("Ammo", maxAmmo)
                end
            end
            tool:SetAttribute("CanShoot", true)
        end
    end

    -- Hook input / click to intercept shots
    local function onInputBegan(input: InputObject, gameProcessed: boolean): ()
        if not settings.enabled or gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local character: Model? = localPlayer.Character
            local tool: Tool? = character and character:FindFirstChildOfClass("Tool")
            if tool and (tool:FindFirstChild("fire") or tool:FindFirstChild("showBeam")) then
                handleWeaponActivation(tool)
            end
        end
    end

    installRaycastHook()

    local env: any = getfenv()
    local createUniversalFeature: any = env.createUniversalFeature
    local addToggleOption: any = env.addToggleOption
    local addNumberOption: any = env.addNumberOption

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    local SilentAimFeature: any = createUniversalFeature(
        "Silent Aim",
        "Redirects gun raycasts to hit random enemies even through walls",
        1,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if fovCircle then
                fovCircle.Visible = enabled and settings.showFov
            end
            if enabled then
                installRaycastHook()
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

    addNumberOption(SilentAimFeature, "Shoot Rate", 0.1, 0.01, 1, function(value: number): ()
        settings.shootRate = value
    end, "Cooldown bypass rate in seconds", 0.01)

    addToggleOption(SilentAimFeature, "No Reload", true, function(value: boolean): ()
        settings.noReload = value
    end, "Keeps ammo maxed and bypasses reload animation")

    addNumberOption(SilentAimFeature, "FOV", 250, 50, 600, function(value: number): ()
        settings.fovRadius = value
        if fovCircle then
            fovCircle.Radius = value
        end
    end, "Silent Aim target selection radius in pixels", 10)

    addToggleOption(SilentAimFeature, "Show FOV", true, function(value: boolean): ()
        settings.showFov = value
        if fovCircle then
            fovCircle.Visible = settings.enabled and value
        end
    end, "Renders visual FOV circle on screen")

    featureConnections.Heartbeat = runService.Heartbeat:Connect(onHeartbeat)
    featureConnections.InputBegan = userInput.InputBegan:Connect(onInputBegan)

    moduleCleanup = function(): ()
        uninstallRaycastHook()
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
    Module.Runtime = nil
    Module.Menu = nil
end

return Module
