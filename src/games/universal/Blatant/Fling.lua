export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Fling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local activity: any = context.services.activity
    local protectedTargets: any = context.services.protectedTargets
    local gameBridge: any = context.services.gameBridge
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addInformationOption: any = host.addInformationOption

    local workspace: any = host.workspace
    local RunService: any = host.RunService

    local flingRunning: boolean = false

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running)
    end

    local performFling: (Player) -> ()

    -- Fixed flight profile: the old per-user Duration/Power options were
    -- replaced by the role actions; 6 s at power 1 matches what the old
    -- defaults produced.
    local FLING_DURATION: number = 6
    local FLING_POWER: number = 1

    performFling = function(targetPlayer: Player): ()
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
            local savedCameraSubject: (Humanoid | BasePart)? = workspace.CurrentCamera
                and workspace.CurrentCamera.CameraSubject
                :: (Humanoid | BasePart)?
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

                while os.clock() - startedAt < duration do

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
                    if liveRoot.Anchored then
                        liveRoot.Anchored = false
                    end
                    humanoid = liveHumanoid
                    root = liveRoot

                    step += 1

                    local phase: number = (step % 6) / 6 * math.pi * 2
                    local vertical: number = (step % 2 == 0) and 1.1 or -1.1
                    liveRoot.CFrame = targetRoot.CFrame
                        * CFrame.new(math.cos(phase) * 1.6, vertical, math.sin(phase) * 1.6)
                    local sign: number = (step % 2 == 0) and 1 or -1
                    liveRoot.AssemblyLinearVelocity =
                        Vector3.new(power * sign, power, power * -sign)
                    liveRoot.AssemblyAngularVelocity =
                        Vector3.new(power, power, power)

                    RunService.Stepped:Wait()
                    if liveRoot.Parent then
                        liveRoot.AssemblyLinearVelocity =
                            Vector3.new(power * -sign, power, power * sign)
                    end
                    RunService.Heartbeat:Wait()
                end
            end)

            local _, finalHumanoid: Humanoid?, finalRoot: BasePart? = getCharacterParts()
            if finalRoot and finalRoot.Parent then
                finalRoot.AssemblyLinearVelocity = Vector3.zero
                finalRoot.AssemblyAngularVelocity = Vector3.zero
                finalRoot.CFrame = savedCFrame + Vector3.new(0, 2, 0)
            end
            if finalHumanoid then
                finalHumanoid.AutoRotate = savedAutoRotate
                finalHumanoid.PlatformStand = false
            end
            if workspace.CurrentCamera then
                workspace.CurrentCamera.CameraSubject =
                    savedCameraSubject or finalHumanoid or humanoid
            end

            setFlingRunning(false)
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

    -- Role lookup goes through the game bridge, so these actions only exist
    -- where the game exposes roles (MM2). In other games the provider is
    -- nil and every action reports that no roles were found.
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
        "Role-based fling actions (murderer, sheriff, all innocents)",
        2,
        function() end,
        {category = true, categoryName = "Blatant"}
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
    addInformationOption(
        FlingFeature,
        "Role names come from the game (MM2: Murderer / Sheriff / Innocent). "
            .. "The card replaced the old text-target Fling and Role Fling."
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
