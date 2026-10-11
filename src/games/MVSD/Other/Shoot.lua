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
    local userInput: UserInputService = game:GetService("UserInputService")
    local localPlayer: Player = players.LocalPlayer
    local camera: Camera = workspace.CurrentCamera or (workspace:WaitForChild("Camera") :: Camera)

    local featureConnections: {[string]: any} = {}

    local settings = {
        enabled = false,
        wallCheck = true,
        macro = true,
    }

    local function isSameTeam(a: Player, b: Player): boolean
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

    local function getClosestVisibleEnemy(): (Player?, BasePart?)
        local myChar: Model? = localPlayer.Character
        local myRoot: BasePart? = myChar and (myChar:FindFirstChild("HumanoidRootPart") :: BasePart? or myChar.PrimaryPart :: BasePart?)
        if not myRoot then
            return nil, nil
        end

        local bestEnemy: Player? = nil
        local bestPart: BasePart? = nil
        local closestDist: number = math.huge

        for _, player: Player in ipairs(players:GetPlayers()) do
            if player ~= localPlayer
                and player:GetAttribute("Died") ~= true
                and isInMatch(player)
                and not isSameTeam(localPlayer, player) then
                local character: Model? = player.Character
                local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
                local root: BasePart? = character and (character:FindFirstChild("HumanoidRootPart") :: BasePart? or character:FindFirstChild("Head") :: BasePart?)
                if character and humanoid and humanoid.Health > 0 and root then
                    local targetPos: Vector3 = root.Position
                    local dist: number = (targetPos - myRoot.Position).Magnitude
                    if dist < closestDist then
                        if not settings.wallCheck or checkLineOfSight(camera.CFrame.Position, targetPos, character) then
                            closestDist = dist
                            bestEnemy = player
                            bestPart = root
                        end
                    end
                end
            end
        end

        return bestEnemy, bestPart
    end

    local isFiring: boolean = false

    local function executeLegalShot(): ()
        if isFiring or not settings.enabled then return end
        local character: Model? = localPlayer.Character
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not humanoid or humanoid.Health <= 0 then return end

        local tool: Tool? = character:FindFirstChildOfClass("Tool")
        if not tool then
            -- Check backpack for gun
            local backpack: Backpack? = localPlayer:FindFirstChildOfClass("Backpack")
            if backpack then
                for _, item: Instance in ipairs(backpack:GetChildren()) do
                    if item:IsA("Tool") and (item:FindFirstChild("fire") or item:FindFirstChild("showBeam") or string.find(item.Name:lower(), "gun")) then
                        tool = item
                        humanoid:EquipTool(tool)
                        task.wait(0.05)
                        break
                    end
                end
            end
        end

        if not tool then return end

        local _, targetPart = getClosestVisibleEnemy()
        if not targetPart then return end

        isFiring = true

        -- Aim camera at target
        local handle: BasePart? = tool:FindFirstChild("Handle") :: BasePart?
        local origin: Vector3 = handle and handle.Position or camera.CFrame.Position
        local targetPos: Vector3 = targetPart.Position

        -- Fire tool legal events
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

        pcall(function(): ()
            tool:Activate()
        end)

        -- Macro: automatically unequips the gun 0.01 seconds after firing
        if settings.macro then
            task.delay(0.01, function(): ()
                if humanoid and humanoid.Parent then
                    pcall(function(): ()
                        humanoid:UnequipTools()
                    end)
                end
                isFiring = false
            end)
        else
            task.delay(0.1, function(): ()
                isFiring = false
            end)
        end
    end

    local function onInputBegan(input: InputObject, gameProcessed: boolean): ()
        if not settings.enabled or gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.E then
            local character: Model? = localPlayer.Character
            local tool: Tool? = character and character:FindFirstChildOfClass("Tool")
            if tool and (tool:FindFirstChild("fire") or tool:FindFirstChild("showBeam") or string.find(tool.Name:lower(), "gun")) then
                executeLegalShot()
            end
        end
    end

    local env: any = getfenv()
    local createUniversalFeature: any = env.createUniversalFeature
    local addToggleOption: any = env.addToggleOption
    local addButtonOption: any = env.addButtonOption

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    local ShootFeature: any = createUniversalFeature(
        "Shoot",
        "Fires legal shots at enemy with line-of-sight check and 0.01s auto-unequip macro",
        2,
        function(enabled: boolean): ()
            settings.enabled = enabled
        end,
        {
            parent = parentScroll,
            registry = featuresRegistry,
            categoryName = "Other",
        }
    )

    addToggleOption(ShootFeature, "WallCheck", true, function(value: boolean): ()
        settings.wallCheck = value
    end, "Only fire when target is visible")

    addToggleOption(ShootFeature, "Macro", true, function(value: boolean): ()
        settings.macro = value
    end, "Automatically unequips gun 0.01 seconds after firing")

    addButtonOption(ShootFeature, "Fire Shot", function(): ()
        executeLegalShot()
    end, "Triggers a single legal shot now")

    featureConnections.InputBegan = userInput.InputBegan:Connect(onInputBegan)

    moduleCleanup = function(): ()
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
