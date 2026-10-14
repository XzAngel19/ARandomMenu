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
    local knifeControl: any = core.knifeControl
    local setWeaponStatus: any = core.setWeaponStatus

    local knifeThrowSettings = {
        enabled = false,
        mode = "Normal",
        fireDelay = 1,
        range = 120,
        spawnOffset = 5,
        throwHz = 60,
        animation = true,
        latencyModel = "Packet RTT/2",
        leadBias = 0,
    }
    local lastThrow = -math.huge
    local lastPrediction: any = nil

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
            setWeaponStatus("Throw", "Waiting for Murderer role")
            return nil
        end
        local character: Model? = LocalPlayer.Character
        if not character then
            setWeaponStatus("Throw", "Waiting for character")
            return nil
        end

        local knife: Tool? = getPlayerWeapon(LocalPlayer, "Knife")
        if not knife then
            setWeaponStatus("Throw", "Knife not found (tool/tag/remotes)"); return nil
        end
        if knife:GetAttribute("Disabled") == true or knife.Enabled == false then
            setWeaponStatus("Throw", "Knife disabled/cooling down"); return nil
        end
        if knife.Parent ~= character then
            local humanoid: Humanoid? =
                character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if humanoid then
                humanoid:EquipTool(knife)
            end
            setWeaponStatus("Throw", "Equipping Knife")
            return nil
        end
        return knife
    end

    local function predictAim(target: Player, originPos: Vector3): Vector3?
        local root: BasePart =
            target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
        local knifeSpeed: number = 96
        local ok: boolean, estimates: any = pcall(function(): any
            return trajectoryCalibration:getEstimates()
        end)
        local learned: number? = ok and type(estimates) == "table" and estimates.liveKnifeSpeed or nil
        if core.mm2Settings.useKnifeSpeedCalibration and predictionMath.finite(learned)
            and (estimates.liveKnifeSamples or 0) >= 3 and learned >= 24 and learned <= 300 then
            knifeSpeed = learned
        end
        local velocity: Vector3 = getFilteredVelocity(target, root)
        -- Default: v10 packet-flight lead. Solve the remaining moving-target
        -- flight instead of using distance-to-the-old-position / blade speed.
        local multiplier: number = knifeThrowSettings.latencyModel == "Replica RTT" and 1 or 0.5
        local packetTime: number = math.clamp(getEstimatedLatency() * multiplier
            + knifeThrowSettings.leadBias, 0, 0.6)
        local positionAtSpawn: Vector3 = root.Position + velocity * packetTime
        local flightTime: number? = predictionMath.interceptTime(
            positionAtSpawn - originPos, velocity, knifeSpeed
        )
        if flightTime == nil then return nil end
        lastPrediction = {networkLead = packetTime, flightTime = flightTime, speed = knifeSpeed}
        return positionAtSpawn + velocity * flightTime
    end

    local throwTrack: any = nil
    local throwTrackHumanoid: Humanoid? = nil
    local throwTrackKnife: Tool? = nil
    local throwTrackId: string? = nil
    local function stopThrowAnimation(): ()
        if throwTrack then
            pcall(function(): () throwTrack:Stop(0) end)
            pcall(function(): () throwTrack:Destroy() end)
        end
        throwTrack = nil
        throwTrackHumanoid = nil
        throwTrackKnife = nil
        throwTrackId = nil
    end

    local function playThrowAnimation(knife: Tool): ()
        if not knifeThrowSettings.animation then return end
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then stopThrowAnimation(); return end
        -- A random first Animation can be Equip or Stab. Unknown tools simply
        -- skip this cosmetic operation; they never delay/block the packet.
        local anim: Animation? = nil
        for _, descendant: Instance in ipairs(knife:GetDescendants()) do
            if descendant:IsA("Animation")
                and string.find(string.lower(descendant.Name), "throw", 1, true) then
                anim = descendant :: Animation
                break
            end
        end
        if not anim then stopThrowAnimation(); return end
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
                throwTrack:Play(0.1, 1, 1)
            end)
        end
    end

    local function throwKnife(): ()
        if os.clock() - lastThrow < knifeThrowSettings.fireDelay then
            setWeaponStatus("Throw", "Fire delay")
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
            setWeaponStatus("Throw", "Missing Knife.Events.KnifeThrown RemoteEvent")
            return
        end
        local character: Model? = LocalPlayer.Character
        local throwerPart: BasePart? = character
            and (character:FindFirstChild("RightHand")
                or character:FindFirstChild("Right Arm")
                or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
        if not throwerPart then
            setWeaponStatus("Throw", "Missing hand/root")
            return
        end

        local target: Player? =
            findNearestTarget(silent and 100000 or knifeThrowSettings.range,
                not silent and throwerPart.Position or nil)
        if not target then
            setWeaponStatus("Throw", "No valid visible target in Throw Range (or protected/dead)")
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
        if not aimPos or (aimPos - originPos).Magnitude < 0.05 then
            setWeaponStatus("Throw", "No usable constant-velocity intercept"); return
        end
        if not silent and not isWeaponPathClear(originPos, aimPos, target.Character) then
            setWeaponStatus("Throw", "Predicted path blocked"); return
        end
        local sentAt: number = os.clock()
        local sent, failure = pcall(function(): ()
            remote:FireServer(CFrame.new(originPos), CFrame.new(aimPos))
        end)
        if not sent then
            lastThrow = sentAt -- bounded retry even when the executor throws
            setWeaponStatus("Throw", "Send error: " .. tostring(failure)); return
        end
        lastThrow = sentAt
        setWeaponStatus("Throw", "Sent to " .. target.Name .. "; projectile/hit not yet confirmed")
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "knife",
            sentAt = sentAt,
            tool = knife,
            toolName = knife.Name,
            originPos = originPos,
            aimPos = aimPos,
            target = target,
            silent = silent,
            settings = {mode = knifeThrowSettings.mode, throwHz = knifeThrowSettings.throwHz,
                fireDelay = knifeThrowSettings.fireDelay, spawnOffset = knifeThrowSettings.spawnOffset,
                range = knifeThrowSettings.range, latencyModel = knifeThrowSettings.latencyModel,
                leadBias = knifeThrowSettings.leadBias, prediction = lastPrediction},
        })
        -- Nothing cosmetic may delay the packet, cooldown, or telemetry timestamp.
        pcall(playThrowAnimation, knife)
    end

    local function toggleKnifeThrow(enabled: boolean): ()
        if knifeThrowSettings.enabled == enabled and (not enabled
            or (featureConnections.MM2KnifeThrow and featureConnections.MM2KnifeThrow.Connected)) then return end
        knifeThrowSettings.enabled = enabled
        setWeaponStatus("Throw", enabled and "Searching" or "Paused (master or Throw OFF)")
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
                if due then
                    local ok, failure = pcall(throwKnife)
                    if not ok then
                        lastThrow = os.clock()
                        setWeaponStatus("Throw", "Error: " .. tostring(failure))
                        warn("[Wurst:MM2:Throw] " .. tostring(failure))
                    end
                end
            end)
    end

    knifeControl:register("throw", toggleKnifeThrow)

    local KnifeThrowFeature: any = state.mm2KnifeFeature
    if not KnifeThrowFeature then
        KnifeThrowFeature = createUniversalFeature(
            "Knife",
            "Knife aura and knife throw, each behind its own option below",
            6,
            function(enabled: boolean): () knifeControl:setMaster(enabled) end,
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
        function(value: boolean): () knifeControl:setWanted("throw", value) end,
        "Requires Knife master ON. Silent changes the authored origin; server acceptance and damage are not guaranteed."
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
            knifeThrowSettings.fireDelay = math.clamp(value, 0.2, 3)
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
            knifeThrowSettings.range = math.clamp(value, 10, 400)
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
            knifeThrowSettings.spawnOffset = math.clamp(value, 1, 15)
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

    addCycleOption(KnifeThrowFeature, "Knife latency model", {"Packet RTT/2", "Replica RTT"}, 1,
        function(value: string): () knifeThrowSettings.latencyModel = value end,
        "RTT/2 covers packet travel only; RTT also budgets replicated-position age. Experimental A/B, not a server measurement.")
    addNumberOption(KnifeThrowFeature, "Knife lead bias", 0, -0.15, 0.15,
        function(value: number): () knifeThrowSettings.leadBias = math.clamp(value, -0.15, 0.15) end,
        "Extra seconds of target motion before flight. Change one variable per test.", 0.005)
    addActionOption(KnifeThrowFeature, "Throw prediction status", function(): ()
        local p = lastPrediction
        notify(core.weaponStatus("Throw") .. " | " .. core.weaponStatus("Throw error") .. string.format(" | %s | range %.0f | checks %.0f Hz | delay %.2fs",
            knifeThrowSettings.latencyModel, knifeThrowSettings.range, knifeThrowSettings.throwHz, knifeThrowSettings.fireDelay)
            .. (p and string.format(" | last network lead %.3fs + flight %.3fs at %.1f studs/s",
                p.networkLead, p.flightTime, p.speed) or " | no solved throw yet"))
    end)
    featureConnections.MM2KnifeThrowCharacter = LocalPlayer.CharacterAdded:Connect(stopThrowAnimation)
    activeCleanup = function(): ()
        knifeControl:remove("throw")
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
