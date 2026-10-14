local Module = {
    Name = "MM2 Knife Throw",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Knife Throw requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local getFilteredVelocity: any = core.getFilteredVelocity
    local trajectoryCalibration: any = core.trajectoryCalibration

    local knifeThrowSettings = {
        enabled = false,
        mode = "Normal",
        fireDelay = 1,
        range = 120,
        spawnOffset = 5,
        throwHz = 60,
        animation = true,
    }
    local lastThrow = -math.huge

    local function isValidTarget(player: Player): boolean
        if player == LocalPlayer
            or isProtectedTarget(player)
            or not isPlayerAlive(player)
            or getPlayerRole(player) == "Murderer" then
            return false
        end
        return player.Character ~= nil
            and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
    end

    local function findNearestTarget(maxDistance: number): Player?
        local localRoot: BasePart? = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not localRoot then
            return nil
        end
        local closest: Player? = nil
        local closestDistance: number = maxDistance
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local targetRoot: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if targetRoot then
                    local distance: number =
                        (targetRoot.Position - localRoot.Position).Magnitude
                    if distance <= closestDistance then
                        closest = player
                        closestDistance = distance
                    end
                end
            end
        end
        return closest
    end

    local function getReadyKnife(): Tool?
        if findMurderer() ~= LocalPlayer then
            return nil
        end
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil
        end

        local knife: Tool? = getPlayerWeapon(LocalPlayer, "Knife")
        if not knife or knife:GetAttribute("Disabled") == true then
            return nil
        end
        if knife.Parent ~= character then
            local humanoid: Humanoid? =
                character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if humanoid then
                humanoid:EquipTool(knife)
            end
            return nil
        end
        return knife
    end

    local function predictAim(target: Player, originPos: Vector3): Vector3
        local root: BasePart =
            target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
        local knifeSpeed: number = 96
        local estimates: any = trajectoryCalibration
            and trajectoryCalibration.getEstimates
            and trajectoryCalibration.getEstimates()
        if estimates and estimates.knifeSpeed and estimates.knifeSpeed > 1 then
            knifeSpeed = estimates.knifeSpeed
        end
        local flightTime: number =
            (root.Position - originPos).Magnitude / knifeSpeed
        local velocity: Vector3 = getFilteredVelocity(target, root)
        return root.Position + velocity * flightTime
    end

    local throwTrack: any = nil
    local throwTrackHumanoid: Humanoid? = nil
    local function playThrowAnimation(knife: Tool): ()
        if not knifeThrowSettings.animation then
            return
        end
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then
            return
        end
        local anim: Animation? =
            knife:FindFirstChildWhichIsA("Animation", true) :: Animation?
        if not anim then

            throwTrack = nil
            throwTrackHumanoid = nil
            return
        end
        if not throwTrack or throwTrackHumanoid ~= humanoid then
            throwTrack = nil
            throwTrackHumanoid = nil
            local ok: boolean, track: any = pcall(function(): any
                return (humanoid :: Humanoid):LoadAnimation(anim :: Animation)
            end)
            if ok then
                throwTrack = track
                throwTrackHumanoid = humanoid
            end
        end
        if throwTrack then
            pcall(function(): ()
                throwTrack:Play(0.1, 1, 1)
            end)
        end
    end

    local function throwKnife(): ()
        if os.clock() - lastThrow < knifeThrowSettings.fireDelay then
            return
        end
        local silent: boolean = knifeThrowSettings.mode == "Silent"
        local knife: Tool? = getReadyKnife()
        if not knife then
            return
        end
        local events: Instance? = knife:FindFirstChild("Events")
        local remote: Instance? = events and events:FindFirstChild("KnifeThrown")
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        local character: Model? = LocalPlayer.Character
        local throwerPart: BasePart? = character
            and (character:FindFirstChild("RightHand")
                or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
        if not throwerPart then
            return
        end

        local target: Player? =
            findNearestTarget(silent and 100000 or knifeThrowSettings.range)
        if not target then
            return
        end
        local targetRoot: BasePart =
            target.Character:FindFirstChild("HumanoidRootPart") :: BasePart

        local originPos: Vector3
        if silent then

            local toThrower: Vector3 = throwerPart.Position - targetRoot.Position
            if toThrower.Magnitude > 0.1 then
                toThrower = toThrower.Unit
            else
                toThrower = Vector3.new(0, 0, 1)
            end
            originPos = targetRoot.Position + toThrower * knifeThrowSettings.spawnOffset
        else
            originPos = throwerPart.Position
        end

        local aimPos: Vector3 = predictAim(target, originPos)
        playThrowAnimation(knife)
        remote:FireServer(CFrame.new(originPos), CFrame.new(aimPos))
        lastThrow = os.clock()
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "knife",
            tool = knife,
            toolName = knife.Name,
            originPos = originPos,
            aimPos = aimPos,
            target = target,
            silent = silent,
        })
    end

    local function toggleKnifeThrow(enabled: boolean): ()
        knifeThrowSettings.enabled = enabled
        disconnectFeatureConnection("MM2KnifeThrow")
        if not enabled then
            return
        end
        lastThrow = -math.huge
        local elapsed: number = 0
        featureConnections.MM2KnifeThrow =
            TaskManager:Connect(function(deltaTime: number): ()
                elapsed += deltaTime
                if elapsed < 1 / 30 then
                    return
                end
                elapsed = 0
                throwKnife()
            end)
    end

    local KnifeThrowFeature: any = state.mm2KnifeFeature
    if not KnifeThrowFeature then
        KnifeThrowFeature = createUniversalFeature(
            "Knife",
            "Knife aura and knife throw, each behind its own option below",
            6,
            function(enabled: boolean): ()
                if not enabled then
                    toggleKnifeThrow(false)
                end
            end,
            {
                categoryName = "Exploits",
                parent = MM2Scroll,
                registry = mm2Features,
            }
        )
        state.mm2KnifeFeature = KnifeThrowFeature
    end

    state.mm2KnifeThrowOff = function(): ()
        toggleKnifeThrow(false)
    end

    addToggleOption(
        KnifeThrowFeature,
        "Knife Throw",
        false,
        toggleKnifeThrow,
        "Auto-throws the knife at the nearest target. Silent spawns the blade"
            .. " beside the target so it connects at any distance or through walls."
    )
    addCycleOption(
        KnifeThrowFeature,
        "Mode",
        {"Normal", "Silent"},
        1,
        function(value: string): ()
            knifeThrowSettings.mode = value
        end
    )
    addNumberOption(
        KnifeThrowFeature,
        "Fire delay",
        knifeThrowSettings.fireDelay,
        0.2,
        3,
        function(value: number): ()
            knifeThrowSettings.fireDelay = value
        end,
        "Seconds between automatic throws.",
        0.1
    )
    addNumberOption(
        KnifeThrowFeature,
        "Range",
        knifeThrowSettings.range,
        10,
        400,
        function(value: number): ()
            knifeThrowSettings.range = value
        end,
        "Maximum target distance for normal throws. Silent ignores this.",
        5
    )
    addNumberOption(
        KnifeThrowFeature,
        "Spawn offset",
        knifeThrowSettings.spawnOffset,
        1,
        15,
        function(value: number): ()
            knifeThrowSettings.spawnOffset = value
        end,
        "Silent only: how far beside the target the blade spawns.",
        1
    )
    addToggleOption(
        KnifeThrowFeature,
        "Throw animation",
        knifeThrowSettings.animation,
        function(value: boolean): ()
            knifeThrowSettings.animation = value
        end,
        "Plays the knife's throw animation right before each auto throw so it "
            .. "looks like a normal throw. Cosmetic only; turn it off to throw "
            .. "with zero wind-up."
    )
    addNumberOption(
        KnifeThrowFeature,
        "Throw Hz",
        knifeThrowSettings.throwHz,
        20,
        120,
        function(value: number): ()
            knifeThrowSettings.throwHz = math.clamp(math.round(value), 20, 120)
        end,
        "Target checks per second while auto throw is on. 60 is the sweet "
            .. "spot: remote players replicate at ~20 Hz, so more only costs "
            .. "CPU.",
        5
    )

    activeCleanup = function(): ()
        toggleKnifeThrow(false)
        state.mm2KnifeThrowOff = nil
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
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
