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
    local shouldHoldForNetwork: any = core.shouldHoldForNetwork
    local getNetworkStatus: any = core.getNetworkStatus
    local predictionMath: any = core.predictionMath
    local isWeaponPathClear: any = core.isWeaponPathClear
    local trajectoryCalibration: any = core.trajectoryCalibration
    local knifeControl: any = core.knifeControl
    local setWeaponStatus: any = core.setWeaponStatus

    local knifeThrowSettings = {
        enabled = false,
        mode = "Normal",
        fireDelay = 1,
        cadence = "Auto",
        range = 120,
        spawnOffset = 5,
        throwHz = 60,
        animation = true,
        latencyModel = "Replica RTT",
        networkPolicy = "Best effort",
        motionModel = "Linear",
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
        -- Replica RTT is the new-profile default; keep packet-only A/B. Solve the moving-target
        -- flight instead of using distance-to-the-old-position / blade speed.
        local multiplier: number = knifeThrowSettings.latencyModel == "Replica RTT" and 1 or 0.5
        local packetTime: number = math.clamp(getEstimatedLatency(true) * multiplier
            + knifeThrowSettings.leadBias, 0, 1.2)
        if knifeThrowSettings.motionModel == "Vertical (experimental)" then
            local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid then lastPrediction = nil; return nil end
            local grounded = core.isMotionGrounded(humanoid, velocity)
            local gravity = workspace.Gravity
            local floorY: number? = nil
            local roughTime = math.clamp((root.Position - originPos).Magnitude / knifeSpeed + packetTime, 0, 6.2)
            if not grounded then
                local displacement = Vector3.new(velocity.X * roughTime,
                    velocity.Y * roughTime - 0.5 * gravity * roughTime * roughTime, velocity.Z * roughTime)
                floorY = core.getLandingRootY(root, humanoid, displacement)
            end
            local offset, flight = predictionMath.verticalIntercept(root.Position - originPos, velocity,
                knifeSpeed, packetTime, gravity, grounded, floorY and floorY - root.Position.Y)
            if not offset or not flight then lastPrediction = nil; return nil end
            if not grounded then
                local probePoint = originPos + offset
                local actualFloor = core.getLandingRootY(root, humanoid, probePoint - root.Position)
                if actualFloor ~= floorY then
                    floorY = actualFloor
                    offset, flight = predictionMath.verticalIntercept(root.Position - originPos, velocity,
                        knifeSpeed, packetTime, gravity, false, floorY and floorY - root.Position.Y)
                    if not offset or not flight then lastPrediction = nil; return nil end
                    local moved = originPos + offset - probePoint
                    if floorY and Vector3.new(moved.X, 0, moved.Z).Magnitude > 2 then
                        lastPrediction = nil; return nil -- sampled ground is no longer near the solved endpoint
                    end
                end
            end
            lastPrediction = {networkLead = packetTime, flightTime = flight, speed = knifeSpeed,
                motionModel = "Vertical (experimental)", grounded = grounded, gravity = gravity,
                landingRootY = floorY, targetVelocity = {velocity.X, velocity.Y, velocity.Z},
                targetRoot = {root.Position.X, root.Position.Y, root.Position.Z}}
            return originPos + offset
        end
        local positionAtSpawn: Vector3 = root.Position + velocity * packetTime
        local flightTime: number? = predictionMath.interceptTime(
            positionAtSpawn - originPos, velocity, knifeSpeed
        )
        if flightTime == nil then lastPrediction = nil; return nil end
        lastPrediction = {networkLead = packetTime, flightTime = flightTime, speed = knifeSpeed, motionModel = "Linear"}
        return positionAtSpawn + velocity * flightTime
    end

    local function getThrowCadence(knife: Tool?): (number, string, boolean)
        local perk = core.getPlayerPerk and core.getPlayerPerk(LocalPlayer)
        local sleight = type(perk) == "string" and string.lower(perk) == "sleight"
        local cooldown = knife and knife:GetAttribute("ThrowCooldown")
        if knife and (not predictionMath.finite(cooldown) or cooldown < 0.1 or cooldown > 5) then
            cooldown = knife:GetAttribute("ThrowDelay")
        end
        local delay, source = predictionMath.knifeCadence(knifeThrowSettings.cadence,
            knifeThrowSettings.fireDelay, cooldown, sleight)
        return delay, source, sleight
    end

    local throwTrack: any = nil
    local throwTrackHumanoid: Humanoid? = nil
    local throwTrackKnife: Tool? = nil
    local throwTrackId: string? = nil
    local throwAnimation: Animation? = nil
    local animationGeneration = 0
    local animationHooks = {}
    local animationStatus = "idle"
    local function stopThrowAnimation(): ()
        animationGeneration += 1
        for _, connection in ipairs(animationHooks) do pcall(function() connection:Disconnect() end) end
        table.clear(animationHooks)
        if throwTrack then
            pcall(function(): () throwTrack:Stop(0.05) end)
            pcall(function(): () throwTrack:Destroy() end)
        end
        throwTrack = nil
        throwTrackHumanoid = nil
        throwTrackKnife = nil
        throwTrackId = nil
        throwAnimation = nil
        animationStatus = "released"
    end

    local function selectThrowAnimation(knife: Tool, humanoid: Humanoid): Animation?
        local best, bestScore = nil, 0
        local rig = tostring(humanoid.RigType)
        for _, descendant in ipairs(knife:GetDescendants()) do
            if descendant:IsA("Animation") then
                local name = string.lower(descendant.Name):gsub("%W", "")
                local parentName = descendant.Parent and descendant.Parent.Name or ""
                local context = string.lower(name .. parentName)
                local wrongRig = (string.find(rig, "R15", 1, true) and string.find(context, "r6", 1, true))
                    or (string.find(rig, "R6", 1, true) and string.find(context, "r15", 1, true))
                local normalized = name:gsub("r15", ""):gsub("r6", "")
                local score = ({throwrelease=4, knifethrow=3, throw=2})[normalized] or 0
                if not wrongRig and score > bestScore then best, bestScore = descendant, score end
            end
        end
        return best
    end

    local function playThrowAnimation(knife: Tool, interval: number?, sleight: boolean?): ()
        if not knifeThrowSettings.animation then return end
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid or knife.Parent ~= character then stopThrowAnimation(); return end
        if throwTrackHumanoid ~= humanoid or throwTrackKnife ~= knife then
            stopThrowAnimation()
            throwTrackHumanoid, throwTrackKnife = humanoid, knife
            throwAnimation = selectThrowAnimation(knife, humanoid)
            if knife.Unequipped then table.insert(animationHooks, knife.Unequipped:Connect(stopThrowAnimation)) end
            if humanoid.Died then table.insert(animationHooks, humanoid.Died:Connect(stopThrowAnimation)) end
            if knife.DescendantAdded then
                table.insert(animationHooks, knife.DescendantAdded:Connect(function(child)
                    if child:IsA("Animation") then stopThrowAnimation() end
                end))
            end
        end
        local anim = throwAnimation
        if not anim then animationStatus = "no known release animation (charge/idle skipped)"; return end
        local animator: Animator? = humanoid:FindFirstChildOfClass("Animator") :: Animator?
        if not animator then animationStatus = "no Animator"; return end
        if type(animator.GetPlayingAnimationTracks) == "function" then
            for _, native in ipairs(animator:GetPlayingAnimationTracks()) do
                if native ~= throwTrack and native.IsPlaying and native.Animation
                    and native.Animation.AnimationId == anim.AnimationId then
                    if throwTrack then pcall(function() throwTrack:Stop(0.05) end) end
                    animationStatus = "native throw already playing"
                    return
                end
            end
        end
        if not throwTrack or throwTrackId ~= anim.AnimationId then
            if throwTrack then
                pcall(function() throwTrack:Stop(0.05) end)
                pcall(function() throwTrack:Destroy() end)
            end
            throwTrack = animator:LoadAnimation(anim)
            throwTrackId = anim.AnimationId
        end
        local duration = math.clamp(interval or 0.5, 0.1, 5)
        local speed = sleight and 2 or 1
        if throwTrack.Length > 0 then speed = math.clamp(math.max(speed, throwTrack.Length / (duration * 0.85)), 1, 4) end
        animationGeneration += 1
        local generation, track = animationGeneration, throwTrack
        if track.IsPlaying then track:Stop(0.03) end
        track.Looped = false
        track.Priority = Enum.AnimationPriority.Action
        track:Play(0.04, 1, speed)
        animationStatus = string.format("release %.2fx", speed)
        -- Stop only our track; a stale timer cannot stop the next throw/native animation.
        task.delay(duration * 0.9, function(): ()
            if generation == animationGeneration and track == throwTrack then
                pcall(function() track:Stop(0.06) end)
            end
        end)
    end

    local function throwKnife(): ()
        local effectiveDelay, cadenceSource, sleight = getThrowCadence(getPlayerWeapon(LocalPlayer, "Knife"))
        if os.clock() - lastThrow < effectiveDelay then
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

        if type(shouldHoldForNetwork) == "function" and shouldHoldForNetwork(knifeThrowSettings.networkPolicy) then
            setWeaponStatus("Throw", "Network unstable: Hold spikes policy."); return
        end
        local aimPos: Vector3? = predictAim(target, originPos)
        if not aimPos or (aimPos - originPos).Magnitude < 0.05 then
            setWeaponStatus("Throw", "No usable intercept for the selected motion model"); return
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
                fireDelay = effectiveDelay, manualFireDelay = knifeThrowSettings.fireDelay,
                cadence = knifeThrowSettings.cadence, cadenceSource = cadenceSource, sleight = sleight,
                spawnOffset = knifeThrowSettings.spawnOffset,
                range = knifeThrowSettings.range, latencyModel = knifeThrowSettings.latencyModel,
                motionModel = knifeThrowSettings.motionModel, networkPolicy = knifeThrowSettings.networkPolicy,
                network = type(getNetworkStatus) == "function" and getNetworkStatus() or nil,
                leadBias = knifeThrowSettings.leadBias, prediction = lastPrediction},
        })
        -- Nothing cosmetic may delay the packet, cooldown, or telemetry timestamp.
        local animated, animationFailure = pcall(playThrowAnimation, knife, effectiveDelay, sleight)
        if not animated then animationStatus = "error: " .. string.sub(tostring(animationFailure), 1, 160) end
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
    local function refreshKnifeOptions(): ()
        for _, row in ipairs(KnifeThrowFeature.optionRows) do
            if row.Name == "Option_Firedelay" then row.Visible = knifeThrowSettings.cadence == "Manual" end
        end
        KnifeThrowFeature.updateExpandedSize()
    end
    addCycleOption(KnifeThrowFeature, "Throw cadence", {"Auto", "Manual"}, 1, function(value: string): ()
        knifeThrowSettings.cadence = value
        refreshKnifeOptions()
    end, "Auto uses explicit weapon throw cooldown; otherwise 0.50s normal / 0.25s detected Sleight. Fallback policy, not a measured server limit. Manual keeps your saved Fire delay.")
    addNumberOption(
        KnifeThrowFeature,
        "Fire delay",
        knifeThrowSettings.fireDelay,
        0.1,
        3,
        function(value: number): ()
            knifeThrowSettings.fireDelay = math.clamp(value, 0.1, 3)
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
        "Plays only a recognized release, not charge/idle. Avoids duplicate native tracks, releases the arm before the next throw, and cleans up on unequip/death. Cosmetic; never delays the request."
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
            .. "helps response granularity on high-FPS clients. Selected cadence is always respected; no catch-up burst.",
        5
    )

    addCycleOption(KnifeThrowFeature, "Network policy", {"Best effort", "Hold spikes"}, 1,
        function(value: string): () knifeThrowSettings.networkPolicy = value end,
        "Independent of Gun. Best effort adds no network wait; Hold spikes pauses only on detected instability or missing data.")
    if state.addTelemetryOption and type(core.getNetworkStatus) == "function" then
        state.addTelemetryOption(KnifeThrowFeature, "Live status", function(): any
            local net = core.getNetworkStatus(true); net.weapon = core.weaponStatus("Throw"); return net
        end)
    end
    addCycleOption(KnifeThrowFeature, "Knife motion", {"Linear", "Vertical (experimental)"}, 1,
        function(value: string): () knifeThrowSettings.motionModel = value; lastPrediction = nil end,
        "Linear preserves v19. Vertical solves target gravity plus a sampled landing floor with at most two map probes per throw. Knife flight stays straight; not future-input knowledge or an accuracy guarantee.")
    addCycleOption(KnifeThrowFeature, "Knife latency model", {"Packet RTT/2", "Replica RTT"}, 2,
        function(value: string): () knifeThrowSettings.latencyModel = value end,
        "RTT/2 covers packet travel only; RTT also budgets replicated-position age. Experimental A/B, not a server measurement.")
    addNumberOption(KnifeThrowFeature, "Knife lead bias", 0, -0.15, 0.15,
        function(value: number): () knifeThrowSettings.leadBias = math.clamp(value, -0.15, 0.15) end,
        "Extra seconds of target motion before flight. Change one variable per test.", 0.005)
    addActionOption(KnifeThrowFeature, "Throw prediction status", function(): ()
        local p = lastPrediction
        local delay, source = getThrowCadence(getPlayerWeapon(LocalPlayer, "Knife"))
        local text = core.weaponStatus("Throw") .. " | motion " .. tostring(knifeThrowSettings.motionModel) .. string.format(" | %s | range %.0f | checks %.0f Hz | delay %.2fs",
            knifeThrowSettings.latencyModel, knifeThrowSettings.range, knifeThrowSettings.throwHz, delay)
            .. " | " .. source .. " | animation " .. animationStatus
            .. (p and string.format(" | last network lead %.3fs + flight %.3fs at %.1f studs/s",
                p.networkLead, p.flightTime, p.speed) or " | no solved throw yet")
        print("[Wurst:MM2:Throw] " .. text); notify(text)
    end)
    refreshKnifeOptions()
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
