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
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addFeatureTooltip: any = host.addFeatureTooltip

    local addTextOption: any = host.addTextOption
    local workspace: any = host.workspace
    local RunService: any = host.RunService

    local flingRunning: boolean = false

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running)
    end
    local findPlayerByText: (string) -> Player?
    local performFling: (Player) -> ()

    type UniversalFlingSettings = {
        target: string,
        duration: number,
        power: number,
        returnToStart: boolean,
    }

    local universalFlingSettings: UniversalFlingSettings = {
        target = "",
        duration = 6,
        power = 1,
        returnToStart = true,
    }

    findPlayerByText = function(text: string): Player?
        local query: string = string.lower(text)
        if query == "" then
            local _, _, localRoot = getCharacterParts()
            local nearest: Player? = nil
            local nearestDistance: number = math.huge

            if localRoot then
                for _, player: Player in ipairs(Players:GetPlayers()) do
                    local root: BasePart? = player.Character
                        and player.Character:FindFirstChild("HumanoidRootPart")
                        :: BasePart?
                    if player ~= LocalPlayer and root then
                        local distance: number = (root.Position - localRoot.Position).Magnitude
                        if distance < nearestDistance then
                            nearest = player
                            nearestDistance = distance
                        end
                    end
                end
            end
            return nearest
        end

        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local username: string = string.lower(player.Name)
                local displayName: string = string.lower(player.DisplayName)
                if string.sub(username, 1, #query) == query
                    or string.sub(displayName, 1, #query) == query then
                    return player
                end
            end
        end

        return nil
    end

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

            local power: number = 9e4 * math.clamp(universalFlingSettings.power, 0.25, 4)
            local duration: number = math.clamp(universalFlingSettings.duration, 1, 20)

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
                if universalFlingSettings.returnToStart then
                    finalRoot.CFrame = savedCFrame + Vector3.new(0, 2, 0)
                end
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
                        .. string.format("%.0f", universalFlingSettings.duration)
                        .. "s. Raise Duration or Power for tougher targets."
                )
            end
        end)
    end

    local FlingFeature = createUniversalFeature(
        "Fling",
        "Fling a player, or the nearest player when blank",
        2,
        function()
            local target = findPlayerByText(universalFlingSettings.target)
            if target then
                performFling(target)
            else
                notify("no matching player")
            end
        end,
        {action = true, categoryName = "Other"}
    )
    addTextOption(FlingFeature, "Target player", universalFlingSettings.target, function(value)
        universalFlingSettings.target = value
    end, false)

    addNumberOption(
        FlingFeature,
        "Duration (s)",
        universalFlingSettings.duration,
        1,
        20,
        function(value: number): ()
            universalFlingSettings.duration = value
        end
    )
    addNumberOption(
        FlingFeature,
        "Power",
        universalFlingSettings.power,
        0.25,
        4,
        function(value: number): ()
            universalFlingSettings.power = value
        end
    )
    addToggleOption(
        FlingFeature,
        "Return to start",
        universalFlingSettings.returnToStart,
        function(value: boolean): ()
            universalFlingSettings.returnToStart = value
        end
    )
    addFeatureTooltip(
        FlingFeature,
        "Runs until the target goes down or the duration expires, then puts you back."
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
