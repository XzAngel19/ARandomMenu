local Module = {
    Name = "MVSD AutoWin",
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
    local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
    local localPlayer: Player = players.LocalPlayer
    local featureConnections: {[string]: any} = {}

    local settings = {
        enabled = false,
        autoQueue = true,
        teleport = true,
        spamDelay = 0.05,
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

    local function findConfirmMapRemote(): RemoteEvent?
        local packages: Instance? = replicatedStorage:FindFirstChild("Packages")
        local networking: Instance? = packages and packages:FindFirstChild("Networking")
        if networking then
            local re: Instance? = networking:FindFirstChild("RE")
            local match: Instance? = re and re:FindFirstChild("Match")
            local confirm: Instance? = match and match:FindFirstChild("ConfirmMatchMap")
            if confirm and confirm:IsA("RemoteEvent") then
                return confirm
            end
        end
        return nil
    end

    local function getNetHitRemote(): RemoteEvent?
        local packages: Instance? = replicatedStorage:FindFirstChild("Packages")
        local net: Instance? = packages and packages:FindFirstChild("Net")
        if net then
            for _, child: Instance in ipairs(net:GetChildren()) do
                if child:IsA("RemoteEvent") and string.find(child.Name, "90e51178") then
                    return child
                end
            end
        end
        return nil
    end

    local function click1v1Queue(): ()
        local confirmRemote: RemoteEvent? = findConfirmMapRemote()
        if confirmRemote then
            pcall(function(): ()
                confirmRemote:FireServer("2a4fb88fa6810854")
            end)
        end

        local pgui: PlayerGui? = localPlayer:FindFirstChildOfClass("PlayerGui")
        if pgui then
            for _, desc: Instance in ipairs(pgui:GetDescendants()) do
                if desc:IsA("TextButton") or desc:IsA("ImageButton") then
                    local nameLow: string = desc.Name:lower()
                    local textLow: string = desc:IsA("TextButton") and desc.Text:lower() or ""
                    if string.find(nameLow, "1v1")
                        or string.find(textLow, "1v1")
                        or string.find(nameLow, "duel")
                        or string.find(textLow, "duel")
                        or string.find(nameLow, "queue")
                        or string.find(textLow, "queue") then
                        pcall(function(): ()
                            for _, conn: any in ipairs(getconnections(desc.Activated)) do
                                conn:Fire()
                            end
                            for _, conn: any in ipairs(getconnections(desc.MouseButton1Click)) do
                                conn:Fire()
                            end
                        end)
                    end
                end
            end
        end
    end

    local isSpamming: boolean = false

    local function autoWinStep(): ()
        if not settings.enabled or isSpamming then return end

        local enemies: {Player} = getActiveEnemies()
        if #enemies == 0 then
            -- If not in match or no enemy alive, try queueing
            if settings.autoQueue then
                click1v1Queue()
            end
            return
        end

        local targetEnemy: Player = enemies[1]
        local enemyChar: Model = targetEnemy.Character :: Model
        local enemyRoot: BasePart? = enemyChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            or enemyChar.PrimaryPart :: BasePart?
        if not enemyRoot then return end

        local myChar: Model? = localPlayer.Character
        local myHumanoid: Humanoid? = myChar and myChar:FindFirstChildOfClass("Humanoid")
        local myRoot: BasePart? = myChar and (myChar:FindFirstChild("HumanoidRootPart") :: BasePart? or myChar.PrimaryPart :: BasePart?)
        if not myChar or not myHumanoid or not myRoot or myHumanoid.Health <= 0 then return end

        isSpamming = true

        -- Teleport directly behind enemy
        if settings.teleport then
            pcall(function(): ()
                myRoot.CFrame = enemyRoot.CFrame * CFrame.new(0, 0, 3) * CFrame.Angles(0, math.pi, 0)
                myRoot.AssemblyLinearVelocity = Vector3.zero
            end)
        end

        -- Equip weapon
        local tool: Tool? = myChar:FindFirstChildOfClass("Tool")
        if not tool then
            local backpack: Backpack? = localPlayer:FindFirstChildOfClass("Backpack")
            if backpack then
                for _, item: Instance in ipairs(backpack:GetChildren()) do
                    if item:IsA("Tool") then
                        myHumanoid:EquipTool(item)
                        tool = item
                        task.wait(0.02)
                        break
                    end
                end
            end
        end

        local origin: Vector3 = myRoot.Position
        local targetPos: Vector3 = enemyRoot.Position
        local dir: Vector3 = (targetPos - origin).Unit

        -- Spam gun remotes
        if tool then
            local fireRemote: Instance? = tool:FindFirstChild("fire")
            if fireRemote and fireRemote:IsA("RemoteEvent") then
                pcall(function(): ()
                    fireRemote:FireServer()
                end)
            end

            local showBeam: Instance? = tool:FindFirstChild("showBeam")
            local handle: BasePart? = tool:FindFirstChild("Handle") :: BasePart?
            if showBeam and showBeam:IsA("RemoteEvent") and handle then
                pcall(function(): ()
                    showBeam:FireServer(origin, targetPos, handle)
                end)
            end

            pcall(function(): ()
                tool:Activate()
            end)
        end

        -- Spam damage confirmation remote
        local netHit: RemoteEvent? = getNetHitRemote()
        if netHit then
            for _ = 1, 3 do
                local actionId: string = "autowin_" .. tostring(math.random(100000, 999999))
                pcall(function(): ()
                    netHit:FireServer(actionId, targetEnemy, dir, origin, targetPos)
                end)
            end
        end

        task.delay(settings.spamDelay, function(): ()
            isSpamming = false
        end)
    end

    local loopThread: thread? = nil

    local function startLoop(): ()
        if loopThread then return end
        loopThread = task.spawn(function(): ()
            while settings.enabled do
                autoWinStep()
                task.wait(settings.spamDelay)
            end
            loopThread = nil
        end)
    end

    local function stopLoop(): ()
        if loopThread then
            task.cancel(loopThread)
            loopThread = nil
        end
        isSpamming = false
    end

    local env: any = getfenv()
    local createUniversalFeature: any = env.createUniversalFeature
    local addToggleOption: any = env.addToggleOption
    local addNumberOption: any = env.addNumberOption
    local addButtonOption: any = env.addButtonOption

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    local AutoWinFeature: any = createUniversalFeature(
        "AutoWin",
        "Automatically queues 1v1, teleports to enemy, and spams silent aim to win in seconds",
        4,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if enabled then
                startLoop()
            else
                stopLoop()
            end
        end,
        {
            parent = parentScroll,
            registry = featuresRegistry,
            categoryName = "Blatant",
        }
    )

    addToggleOption(AutoWinFeature, "Auto 1v1 Queue", true, function(value: boolean): ()
        settings.autoQueue = value
    end, "Automatically clicks/confirms 1v1 queue prompts")

    addToggleOption(AutoWinFeature, "Teleport to Enemy", true, function(value: boolean): ()
        settings.teleport = value
    end, "Teleports behind the opponent on match start")

    addNumberOption(AutoWinFeature, "Spam Rate", 0.05, 0.01, 0.5, function(value: number): ()
        settings.spamDelay = value
    end, "Remote spam interval in seconds", 0.01)

    addButtonOption(AutoWinFeature, "Trigger Win Now", function(): ()
        autoWinStep()
    end, "Executes one instant teleport & hit spam sequence")

    moduleCleanup = function(): ()
        stopLoop()
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
