export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "MM2 Fling",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(runtime: any): any
    local host: any = state.frameworkEnvironment
    assert(state.mm2Core, "MM2 Fling requires the MM2 core")
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local activity: any = services.activity
    local protectedTargets: any = services.protectedTargets
    local gameBridge: any = services.gameBridge
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption

    local workspace: any = host.workspace
    local RunService: any = host.RunService

    local flingRunning: boolean = false

    local flingTargetName: string = ""

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running)
    end

    local performFling: (Player) -> ()

    local FLING_DURATION: number = 6
    local FLING_POWER: number = 1
    -- Ownership is retried, not spammed: SetNetworkOwner is a request the
    -- server can refuse, and calling it every frame is noise.
    local OWNERSHIP_RETRY: number = 10

    performFling = function(targetPlayer: Player): ()
        if not Module.Initialized then return end
        if protectedTargets.isProtected(targetPlayer) then
            notify("player protected")
            return
        end
        if flingRunning then
            notify("fling already running")
            return
        end

        setFlingRunning(true)
        task.spawn(function(): ()
            local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not humanoid or not root then
                setFlingRunning(false)
                notify("character not ready")
                return
            end

            local savedCFrame: CFrame = root.CFrame
            local savedAutoRotate: boolean = humanoid.AutoRotate
            local touchedTarget: boolean = false
            local reason: string = "timeout"

            local power: number = 9e4 * math.clamp(FLING_POWER, 0.25, 4)
            local duration: number = math.clamp(FLING_DURATION, 1, 20)

            local success: boolean, errorMessage: any = pcall(function(): ()
                local startedAt: number = os.clock()
                local step: number = 0
                local destroyHeight: number = workspace.FallenPartsDestroyHeight
                if destroyHeight ~= destroyHeight then
                    destroyHeight = -500
                end
                local voidThreshold: number = destroyHeight + 35

                humanoid.AutoRotate = false
                if humanoid.Sit then
                    humanoid.Sit = false
                end

                while flingRunning and os.clock() - startedAt < duration do

                    if targetPlayer.Parent == nil then
                        reason = "left"
                        break
                    end

                    local targetCharacter: Model? = targetPlayer.Character
                    local targetRoot: BasePart? = targetCharacter
                        and targetCharacter:FindFirstChild("HumanoidRootPart")
                        :: BasePart?
                    local targetHumanoid: Humanoid? = targetCharacter
                        and targetCharacter:FindFirstChildOfClass("Humanoid")
                        :: Humanoid?
                    if not targetRoot or not targetRoot.Parent then
                        reason = "gone"
                        break
                    end
                    if targetHumanoid and targetHumanoid.Health <= 0 then
                        touchedTarget = true
                        reason = "killed"
                        break
                    end
                    if targetRoot.Position.Y <= voidThreshold then
                        touchedTarget = true
                        reason = "void"
                        break
                    end

                    -- Done already? A fling that worked leaves the target
                    -- moving fast; stop spending frames on it.
                    local targetSpeed: number = 0
                    pcall(function(): ()
                        targetSpeed = targetRoot.AssemblyLinearVelocity.Magnitude
                    end)
                    if targetSpeed > 150 then
                        touchedTarget = true
                        reason = "flung"
                        break
                    end

                    local _, liveHumanoid: Humanoid?, liveRoot: BasePart? =
                        getCharacterParts()
                    if not liveHumanoid or not liveRoot then
                        reason = "died"
                        break
                    end
                    if liveHumanoid.Health <= 0 then
                        reason = "died"
                        break
                    end
                    if liveRoot ~= root or liveHumanoid ~= humanoid or liveRoot.Anchored then
                        reason = "died"
                        break
                    end
                    humanoid = liveHumanoid
                    root = liveRoot

                    step += 1

                    -- Two layers, cheapest first. Roblox characters are
                    -- jointed assemblies: one angular velocity on any part
                    -- spins the whole body, so a client that owns the
                    -- target's assembly only has to ask for it once and the
                    -- target leaves without any contact dance.
                    if step % OWNERSHIP_RETRY == 0 then
                        pcall(function(): ()
                            (targetRoot :: any):SetNetworkOwner(LocalPlayer)
                        end)
                    end
                    local owned: boolean = false
                    pcall(function(): ()
                        owned = (targetRoot :: any):GetNetworkOwner()
                            == LocalPlayer
                    end)

                    if owned then
                        pcall(function(): ()
                            targetRoot.AssemblyAngularVelocity =
                                Vector3.new(power, power, power)
                            targetRoot.AssemblyLinearVelocity =
                                Vector3.new(0, power * 0.01, 0)
                        end)
                    else
                        -- No ownership: sit inside the target and spin.
                        -- The solver ejects the interpenetration, and the
                        -- target's own assembly takes the impulse. One
                        -- contact write per frame is deliberate -- the old
                        -- alternating velocity was cancelled by the next
                        -- CFrame and the 1.6-stud orbit kept the bodies
                        -- too far apart to overlap, which is why it needed
                        -- so many attempts.
                        pcall(function(): ()
                            liveRoot.CFrame = targetRoot.CFrame
                        end)
                        pcall(function(): ()
                            liveRoot.AssemblyAngularVelocity =
                                Vector3.new(power, power, power)
                            liveRoot.AssemblyLinearVelocity =
                                Vector3.new(0, power * 0.02, 0)
                        end)
                    end

                    RunService.Heartbeat:Wait()
                end
            end)

            local _, finalHumanoid: Humanoid?, finalRoot: BasePart? = getCharacterParts()
            if finalRoot == root and finalRoot and finalRoot.Parent then
                finalRoot.AssemblyLinearVelocity = Vector3.zero
                finalRoot.AssemblyAngularVelocity = Vector3.zero
                finalRoot.CFrame = savedCFrame + Vector3.new(0, 2, 0)
            end
            if finalHumanoid == humanoid and finalHumanoid then
                finalHumanoid.AutoRotate = savedAutoRotate
            end

            setFlingRunning(false)
            if not Module.Initialized then return end
            if not success then
                notify("fling failed: " .. tostring(errorMessage))
            elseif touchedTarget then
                notify("fling complete: " .. targetPlayer.Name .. " went down.")
            elseif reason == "left" then
                notify("fling stopped: " .. targetPlayer.Name .. " left the game.")
            elseif reason == "gone" then
                notify("Fling stopped: the target character disappeared.")
            elseif reason == "died" then
                notify("Fling stopped: your character died.")
            else
                notify(
                    "Fling stopped after "
                        .. string.format("%.0f", FLING_DURATION)
                        .. "s of flight."
                )
            end
        end)
    end

    local function findPlayerByRole(match: (string) -> boolean): Player?
        if type(gameBridge.playerRole) ~= "function" then
            return nil
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local ok: boolean, role: any = pcall(gameBridge.playerRole, player)
                if ok and type(role) == "string" and match(role) then
                    local alive: boolean = player.Character
                        and player.Character:FindFirstChildOfClass("Humanoid")
                            and (player.Character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health > 0
                    if alive then
                        return player
                    end
                end
            end
        end
        return nil
    end

    local FlingFeature: any = createUniversalFeature(
        "Fling",
        "MM2 only: fling the murderer, sheriff or innocents",
        2,
        function() end,
        {category = true, categoryName = "Exploits", registry = mm2Features, configKey = "MM2.Fling"}
    )
    addActionOption(FlingFeature, "Fling Murderer", function(): ()
        local target: Player? = findPlayerByRole(function(role: string): boolean
            return role == "Murderer"
        end)
        if target then
            performFling(target)
        else
            notify("No murderer was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling Sheriff", function(): ()
        local target: Player? = findPlayerByRole(function(role: string): boolean
            return role == "Sheriff" or role == "Hero"
        end)
        if target then
            performFling(target)
        else
            notify("No sheriff or hero was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling All Innocents", function(): ()
        if type(gameBridge.playerRole) ~= "function" then
            notify("No roles available in this game.")
            return
        end
        task.spawn(function(): ()
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local ok: boolean, role: any = pcall(gameBridge.playerRole, player)
                    if ok and role == "Innocent" then
                        performFling(player)
                        repeat
                            task.wait(0.05)
                        until not activity.isActive("fling")
                    end
                end
            end
        end)
    end)
    addTextOption(
        FlingFeature,
        "Target player",
        "",
        function(value: string): ()
            flingTargetName = value
        end,
        false,
        "Exact or partial name"
    )
    addActionOption(FlingFeature, "Fling", function(): ()
        local needle: string = string.lower(
            string.gsub(flingTargetName or "", "%s+", "")
        )
        if needle == "" then
            notify("Type a player name in the Target player box first.")
            return
        end
        local exact: Player? = nil
        local partial: Player? = nil
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local name: string = string.lower(player.Name)
                if string.gsub(name, "%s+", "") == needle then
                    exact = player
                    break
                end
                if not partial and string.find(name, needle, 1, true) then
                    partial = player
                end
            end
        end
        local target: Player? = exact or partial
        if target then
            performFling(target)
        else
            notify("No player named \"" .. flingTargetName .. "\" was found.")
        end
    end)
    addInformationOption(
        FlingFeature,
        "MM2 only. Choose a role action, or enter a player name and press Fling."
    )

    activeCleanup = function(): ()
        setFlingRunning(false)
    end
    Module.Initialized = true
    return FlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
