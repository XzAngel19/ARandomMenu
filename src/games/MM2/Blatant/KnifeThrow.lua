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
    local getEstimatedLatency: any = core.getEstimatedLatency
    local predictionMath: any = core.predictionMath
    local isWeaponPathClear: any = core.isWeaponPathClear
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

    local function findNearestTarget(maxDistance: number, origin: Vector3?): Player?
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
                    if distance <= closestDistance and (not origin
                        or isWeaponPathClear(origin, targetRoot.Position, player.Character)) then
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

    local function predictAim(target: Player, originPos: Vector3): Vector3?
        local root: BasePart =
            target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
        local knifeSpeed: number = 96
        local estimates: any = nil
        local ok: boolean, estimatesValue: any = pcall(function(): any
            return trajectoryCalibration:getEstimates()
        end)
        if ok and type(estimatesValue) == "table" then
            estimates = estimatesValue
        end
        if estimates and predictionMath.finite(estimates.knifeSpeed)
            and estimates.knifeSpeed >= 24 and estimates.knifeSpeed <= 300 then
            knifeSpeed = estimates.knifeSpeed
        end
        local velocity: Vector3 = getFilteredVelocity(target, root)
        -- Packet-flight lead: the blade spawns on the server a full round
        -- trip after we author the throw, and our observation of the target
        -- is a round trip old, so the target keeps moving for that whole
        -- window. The calibration measures exactly that window (observed
        -- spawn delay, ~240 ms on record); use it when enough throws
        -- confirmed it, otherwise fall back to the live RTT estimate.
        local packetTime: number = getEstimatedLatency()
        if estimates
            and predictionMath.finite(estimates.knifeSpawnDelayMs)
            and (estimates.confirmedSpawnDelays or 0) >= 3 then
            packetTime = math.clamp(
                estimates.knifeSpawnDelayMs / 1000,
                0.05,
                0.6
            )
        end
        local positionAtSpawn: Vector3 = root.Position + velocity * packetTime
        -- Solve the remaining moving-target flight instead of using
        -- distance-to-the-old-position / blade speed.
        local flightTime: number? = predictionMath.interceptTime(
            positionAtSpawn - originPos, velocity, knifeSpeed
        )
        if flightTime == nil then return nil end
        return positionAtSpawn + velocity * flightTime
    end

    local throwTrack: any = nil
    local throwTrackHumanoid: Humanoid? = nil
    local throwTrackKnife: Tool? = nil
    local throwTrackId: string? = nil
    local function stopThrowAnimation(): ()
        if throwTrack then
            pcall(function(): () throwTrack:Stop(0.2) end)
            pcall(function(): () throwTrack:Destroy() end)
        end
        throwTrack = nil
        throwTrackHumanoid = nil
        throwTrackKnife = nil
        throwTrackId = nil
    end

    local function playThrowAnimation(knife: Tool): ()
        if not knifeThrowSettings.animation then return end
        -- Prefer the weapon's own throw track. Do not layer a generic
        -- tool lunge over it: both write the same shoulder at once.
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then return end
        local anim: Animation? = nil
        for _, descendant: Instance in ipairs(knife:GetDescendants()) do
            if descendant:IsA("Animation")
                and string.find(string.lower(descendant.Name), "throw", 1, true) then
                anim = descendant :: Animation
                break
            end
        end
        if not anim then
            stopThrowAnimation()
            -- Legacy R6 fallback only. Never destroy a toolanim owned by
            -- the game, and never layer this over a known throw animation.
            if not knife:FindFirstChild("toolanim") then
                local marker: StringValue = Instance.new("StringValue")
                marker.Name = "toolanim"
                marker.Value = "Lunge"
                marker.Parent = knife
                task.delay(0.3, function(): ()
                    if marker.Parent == knife then marker:Destroy() end
                end)
            end
            return
        end
        if throwTrackHumanoid ~= humanoid or throwTrackKnife ~= knife
            or throwTrackId ~= anim.AnimationId then
            stopThrowAnimation()
            local animator: Animator? = humanoid:FindFirstChildOfClass("Animator") :: Animator?
            if not animator then return end
            local ok: boolean, track: any = pcall(function(): any
                return animator:LoadAnimation(anim :: Animation)
            end)
            if ok then
                throwTrack = track
                throwTrackHumanoid = humanoid
                throwTrackKnife = knife
                throwTrackId = anim.AnimationId
            end
        end
        if throwTrack then
            pcall(function(): ()
                throwTrack.Looped = false
                if throwTrack.IsPlaying then throwTrack:Stop(0.05) end
                throwTrack:Play(0.1, 1, 1)
                throwTrack.TimePosition = 0
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
            findNearestTarget(silent and 100000 or knifeThrowSettings.range,
                not silent and throwerPart.Position or nil)
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

        local aimPos: Vector3? = predictAim(target, originPos)
        if not aimPos or (aimPos - originPos).Magnitude < 0.05 then return end
        if not silent and not isWeaponPathClear(originPos, aimPos, target.Character) then return end
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
            settings = {mode = knifeThrowSettings.mode, throwHz = knifeThrowSettings.throwHz,
                fireDelay = knifeThrowSettings.fireDelay, spawnOffset = knifeThrowSettings.spawnOffset},
        })
        -- Nothing cosmetic may delay the packet, cooldown, or telemetry timestamp.
        pcall(playThrowAnimation, knife)
    end

    local function toggleKnifeThrow(enabled: boolean): ()
        knifeThrowSettings.enabled = enabled
        if state.mm2KnifeRuntime then
            state.mm2KnifeRuntime.throwWanted = enabled
        end
        disconnectFeatureConnection("MM2KnifeThrow")
        if not enabled then
            stopThrowAnimation()
            return
        end
        lastThrow = -math.huge
        local elapsed: number = 0
        featureConnections.MM2KnifeThrow =
            TaskManager:Connect(function(deltaTime: number): ()
                local due: boolean
                due, elapsed = predictionMath.sampleDue(elapsed, deltaTime, knifeThrowSettings.throwHz)
                if due then throwKnife() end
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
        "Throw Range",
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
            if not value then stopThrowAnimation() end
        end,
        "Plays an identified throw animation after sending the packet. Cosmetic "
            .. "only; unknown animations are skipped and OFF releases the track."
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
        "Target checks per second, not throws per second. Default 60; 120 only "
            .. "helps response granularity on high-FPS clients. Fire delay is "
            .. "always respected.",
        5
    )

    featureConnections.MM2KnifeThrowCharacter = LocalPlayer.CharacterAdded:Connect(stopThrowAnimation)
    activeCleanup = function(): ()
        toggleKnifeThrow(false)
        disconnectFeatureConnection("MM2KnifeThrowCharacter")
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
