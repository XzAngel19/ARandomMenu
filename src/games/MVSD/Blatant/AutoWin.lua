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
    local httpService: HttpService = game:GetService("HttpService")
    local localPlayer: Player = players.LocalPlayer

    local env: any = getfenv()
    local state: any = env.state
    local core: any = state and state.mvsdCore
    local createUniversalFeature: any = env.createUniversalFeature
    local addToggleOption: any = env.addToggleOption
    local addNumberOption: any = env.addNumberOption
    local addActionOption: any = env.addActionOption

    local settings = {
        enabled = false,
        autoQueue = true,
        teleport = true,
        spamDelay = 0.05,
    }

    local AutoWinFeature: any = nil

    local function setStatus(text: string?): ()
        if AutoWinFeature and type(AutoWinFeature.SetStatus) == "function" then
            AutoWinFeature:SetStatus(text)
        end
    end

    -- Only run the win-spam while a match is actually live; otherwise we would
    -- chase lobby players instead of queueing (the previous "teleports to
    -- someone" bug).
    local function inActiveMatch(): boolean
        if core and type(core.matchIdOf) == "function" then
            return core.matchIdOf(localPlayer) ~= nil
        end
        return localPlayer:GetAttribute("Died") ~= nil
    end

    local function findConfirmMapRemote(): RemoteEvent?
        local packages: Instance? = replicatedStorage:FindFirstChild("Packages")
        local networking: Instance? = packages and packages:FindFirstChild("Networking")
        if not networking then
            return nil
        end
        local re: Instance? = networking:FindFirstChild("RE")
        local match: Instance? = re and re:FindFirstChild("Match")
        local confirm: Instance? = match and match:FindFirstChild("ConfirmMatchMap")
        return confirm and confirm:IsA("RemoteEvent") and confirm or nil
    end

    local function getNetHitRemote(): RemoteEvent?
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

    local function fireButtonClick(button: Instance): boolean
        local g: any = getfenv()
        -- Preferred executor path: fire the signal the UI listens to.
        if type(g.firesignal) == "function" then
            local ok: boolean = pcall(function(): ()
                g.firesignal(button.MouseButton1Click)
            end)
            if ok then
                return true
            end
        end
        if type(g.getconnections) == "function" then
            local ok: boolean, conns: any = pcall(g.getconnections, button.MouseButton1Click)
            if ok and type(conns) == "table" then
                local fired: boolean = false
                for _, conn: any in ipairs(conns) do
                    if type(conn) == "table" and type(conn.Function) == "function" then
                        pcall(conn.Function)
                        fired = true
                    elseif type(conn) == "table" and type(conn.Fire) == "function" then
                        pcall(conn.Fire, conn)
                        fired = true
                    end
                end
                if fired then
                    return true
                end
            end
        end
        -- Last resort for engines that let a signal be fired directly.
        local okDirect: boolean = pcall(function(): ()
            (button :: any).MouseButton1Click:Fire()
        end)
        return okDirect
    end

    local QUEUE_WORDS: {string} = {"1v1", "1vs1", "duel", "queue", "play", "start"}

    local function click1v1Queue(): boolean
        local clicked: boolean = false

        local confirmRemote: RemoteEvent? = findConfirmMapRemote()
        if confirmRemote then
            pcall(function(): ()
                confirmRemote:FireServer("2a4fb88fa6810854")
            end)
        end

        local pgui: Instance? = localPlayer:FindFirstChildOfClass("PlayerGui")
        if not pgui then
            return clicked
        end

        -- Pass 1: an exact 1v1 button. Pass 2: any queue/duel/play button.
        for pass: number = 1, 2 do
            for _, desc: Instance in ipairs(pgui:GetDescendants()) do
                if not (desc:IsA("TextButton") or desc:IsA("ImageButton")) then
                    continue
                end
                local nameLow: string = desc.Name:lower()
                local textLow: string = ""
                if desc:IsA("TextButton") then
                    local okText: boolean, text: any = pcall(function(): any
                        return (desc :: TextButton).Text
                    end)
                    if okText and type(text) == "string" then
                        textLow = text:lower()
                    end
                end
                local isExact: boolean = string.find(nameLow, "1v1", 1, true) ~= nil
                    or string.find(textLow, "1v1", 1, true) ~= nil
                    or string.find(textLow, "1vs1", 1, true) ~= nil
                local isQueue: boolean = false
                for _, word: string in ipairs(QUEUE_WORDS) do
                    if string.find(nameLow, word, 1, true) or string.find(textLow, word, 1, true) then
                        isQueue = true
                        break
                    end
                end
                if (pass == 1 and isExact) or (pass == 2 and isQueue) then
                    if fireButtonClick(desc) then
                        clicked = true
                    end
                end
            end
            if clicked then
                break
            end
        end
        return clicked
    end

    local isSpamming: boolean = false

    local function autoWinStep(): ()
        if not settings.enabled or isSpamming then
            return
        end

        if not inActiveMatch() then
            if settings.autoQueue then
                local clicked: boolean = click1v1Queue()
                setStatus(clicked and "Queued 1v1" or "Looking for 1v1 button")
            end
            return
        end

        local enemies: {Player} = core and core.enemies() or {}
        if #enemies == 0 then
            setStatus("Waiting for opponent")
            return
        end

        local targetEnemy: Player = enemies[1]
        local enemyChar: Model? = targetEnemy.Character
        local enemyRoot: BasePart? = enemyChar and (enemyChar:FindFirstChild("HumanoidRootPart") :: BasePart?
            or enemyChar.PrimaryPart :: BasePart?)
        if not enemyRoot then
            return
        end

        local myChar: Model? = localPlayer.Character
        local myHumanoid: Humanoid? = myChar and myChar:FindFirstChildOfClass("Humanoid")
        local myRoot: BasePart? = myChar and (myChar:FindFirstChild("HumanoidRootPart") :: BasePart? or myChar.PrimaryPart :: BasePart?)
        if not myChar or not myHumanoid or not myRoot or myHumanoid.Health <= 0 then
            return
        end

        isSpamming = true
        setStatus("Winning vs " .. targetEnemy.Name)

        if settings.teleport then
            pcall(function(): ()
                myRoot.CFrame = enemyRoot.CFrame * CFrame.new(0, 0, 3) * CFrame.Angles(0, math.pi, 0)
                myRoot.AssemblyLinearVelocity = Vector3.zero
            end)
        end

        local gun: Instance? = core and core.findGun() or nil
        if gun and not core.isEquipped(gun) then
            core.equip(gun)
        end
        if not gun then
            gun = core and core.equippedTool() or nil
        end

        local origin: Vector3 = myRoot.Position
        local targetPos: Vector3 = enemyRoot.Position
        local direction: Vector3 = (targetPos - origin).Unit

        if gun then
            local fireRemote: Instance? = gun:FindFirstChild("fire")
            if fireRemote and fireRemote:IsA("RemoteEvent") then
                pcall(function(): ()
                    fireRemote:FireServer()
                end)
            end
            local showBeam: Instance? = gun:FindFirstChild("showBeam")
            local handle: BasePart? = gun:FindFirstChild("Handle") :: BasePart?
            if showBeam and showBeam:IsA("RemoteEvent") and handle then
                pcall(function(): ()
                    showBeam:FireServer(origin, targetPos, handle)
                end)
            end
        end

        local netHit: RemoteEvent? = getNetHitRemote()
        if netHit then
            for _ = 1, 3 do
                local guid: string = httpService:GenerateGUID(false)
                pcall(function(): ()
                    netHit:FireServer(guid, targetEnemy, direction, origin, targetPos)
                end)
            end
        end

        task.delay(settings.spamDelay, function(): ()
            isSpamming = false
        end)
    end

    local loopThread: thread? = nil

    local function startLoop(): ()
        if loopThread then
            return
        end
        loopThread = task.spawn(function(): ()
            while settings.enabled do
                pcall(autoWinStep)
                task.wait(settings.spamDelay)
            end
            loopThread = nil
        end)
    end

    local function stopLoop(): ()
        if loopThread then
            pcall(function(): ()
                task.cancel(loopThread)
            end)
            loopThread = nil
        end
        isSpamming = false
    end

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    AutoWinFeature = createUniversalFeature(
        "AutoWin",
        "Clicks the 1v1 queue, teleports to the opponent and spams hits to win",
        4,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if enabled then
                startLoop()
            else
                stopLoop()
                setStatus(nil)
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
    end, "Clicks the 1v1 queue button while you are in the lobby")

    addToggleOption(AutoWinFeature, "Teleport to Enemy", true, function(value: boolean): ()
        settings.teleport = value
    end, "Teleports behind the opponent on match start")

    addNumberOption(AutoWinFeature, "Spam Rate", 0.05, 0.01, 0.5, function(value: number): ()
        settings.spamDelay = value
    end, "Remote spam interval in seconds", 0.01)

    addActionOption(AutoWinFeature, "Join 1v1", function(): ()
        local clicked: boolean = click1v1Queue()
        setStatus(clicked and "Queued 1v1" or "No 1v1 button found")
    end, "Clicks the 1v1 queue button once")

    addActionOption(AutoWinFeature, "Trigger Win Now", function(): ()
        autoWinStep()
    end, "Runs one teleport + hit spam sequence")

    moduleCleanup = function(): ()
        stopLoop()
        setStatus(nil)
    end

    Module.Events = {}
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
