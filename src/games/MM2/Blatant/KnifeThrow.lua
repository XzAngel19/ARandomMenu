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

        local knife: Tool? = getPlayerWeapon(LocalPlayer, "Knife", true)
        if not knife or knife.Parent ~= character or knife:GetAttribute("Disabled") == true then
            return nil
        end
        return knife
    end

    local function predictAim(target: Player, originPos: Vector3): Vector3?
        -- Rebuilt from the recovered ThrowingKnifeVisuals integrator:
        -- position += Direction * ThrowSpeed * dt (96 studs/s by default).
        -- There is no projectile gravity term in that client model.
        local root: BasePart? = target.Character
            and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then return nil end
        local velocity: Vector3 = getFilteredVelocity(target, root)
        local speed: number = 96
        local knife: Tool? = getReadyKnife()
        if knife then
            local measured: any = knife:GetAttribute("ThrowSpeed")
            if predictionMath.finite(measured) and measured >= 24 and measured <= 300 then speed = measured end
        end
        local latency: number = getEstimatedLatency()
        if not predictionMath.finite(latency) then latency = 0 end
        latency = math.clamp(latency, 0, 0.6)
        local observed: Vector3 = root.Position + velocity * latency
        local relative: Vector3 = observed - originPos
        if not predictionMath.finite(relative.Magnitude) or not predictionMath.finite(velocity.Magnitude) then return nil end
        -- |relative + velocity*t| = speed*t. Stable quadratic roots avoid
        -- cancellation for approaching targets and handle the linear limit.
        local a: number = velocity:Dot(velocity) - speed * speed
        local b: number = 2 * relative:Dot(velocity)
        local c: number = relative:Dot(relative)
        local flight: number? = nil
        if c < 0.0025 then return observed end
        if math.abs(a) < 1e-6 then
            if b < -1e-6 then flight = -c / b end
        else
            local discriminant: number = b*b - 4*a*c
            if discriminant >= 0 then
                local q: number = -0.5 * (b + (b >= 0 and 1 or -1) * math.sqrt(discriminant))
                local t1: number = q / a
                local t2: number = math.abs(q) > 1e-9 and c / q or -1
                if t1 > 0 then flight = t1 end
                if t2 > 0 and (not flight or t2 < flight) then flight = t2 end
            end
        end
        if not flight or not predictionMath.finite(flight) or flight > 4 then return nil end
        return observed + velocity * flight
    end

    type ThrowJoint = {
        joint: Motor6D, c0: CFrame, transform: CFrame,
        initial: CFrame, raised: CFrame, forward: CFrame,
    }
    local throwPose: {ThrowJoint} = {}
    local throwPending: boolean = false
    local function stopThrowAnimation(): ()
        disconnectFeatureConnection("MM2KnifeAnimation")
        throwPending = false
        for _, entry: ThrowJoint in ipairs(throwPose) do
            pcall(function(): ()
                if entry.joint.Parent then
                    entry.joint.C0 = entry.c0
                    entry.joint.Transform = entry.transform
                end
            end)
        end
        table.clear(throwPose)
    end

    local function playThrowAnimation(knife: Tool, onRelease: (() -> ())?): ()
        stopThrowAnimation()
        local character: Model? = LocalPlayer.Character
        if not character or knife.Parent ~= character then return end
        local function release(): ()
            throwPending = false
            if onRelease then onRelease() end
        end
        if not knifeThrowSettings.animation then release(); return end
        -- Parent-space rotation is deliberate. R6 shoulders have a rotated
        -- bind frame: post-multiplying an X rotation swings sideways, not up.
        local function addJoint(partName: string, jointName: string, lift: number, forward: number, roll: number): ()
            local part: Instance? = character:FindFirstChild(partName)
            local joint: any = part and part:FindFirstChild(jointName)
            if not joint or not joint:IsA("Motor6D") then return end
            local c0: CFrame = joint.C0
            local pivot: CFrame = CFrame.new(c0.Position)
            local basis: CFrame = c0 - c0.Position
            table.insert(throwPose, {
                joint = joint, c0 = c0, transform = joint.Transform,
                initial = c0 * joint.Transform,
                raised = pivot * CFrame.Angles(math.rad(lift), 0, math.rad(roll)) * basis,
                forward = pivot * CFrame.Angles(math.rad(forward), 0, 0) * basis,
            })
        end
        if character:FindFirstChild("RightUpperArm") then
            addJoint("RightUpperArm", "RightShoulder", 155, 85, -12)
            addJoint("RightLowerArm", "RightElbow", -85, -8, 0)
            addJoint("RightHand", "RightWrist", -15, 10, 0)
        else
            addJoint("Torso", "Right Shoulder", 155, 85, -12)
        end
        if #throwPose == 0 then release(); return end
        local elapsed: number = 0
        local released: boolean = false
        throwPending = onRelease ~= nil
        featureConnections.MM2KnifeAnimation = TaskManager:Connect(function(dt: number): ()
            if LocalPlayer.Character ~= character or knife.Parent ~= character then
                stopThrowAnimation()
                return
            end
            elapsed += math.max(0, dt)
            local phase: number = elapsed < 0.2 and 1 or (elapsed < 0.3 and 2 or 3)
            local alpha: number = phase == 1 and elapsed / 0.2
                or (phase == 2 and (elapsed - 0.2) / 0.1 or (elapsed - 0.3) / 0.25)
            alpha = math.clamp(alpha, 0, 1)
            alpha = alpha * alpha * (3 - 2 * alpha)
            for _, entry: ThrowJoint in ipairs(throwPose) do
                if not entry.joint.Parent then stopThrowAnimation(); return end
                local from: CFrame = phase == 1 and entry.initial or (phase == 2 and entry.raised or entry.forward)
                local to: CFrame = phase == 1 and entry.raised or (phase == 2 and entry.forward or entry.initial)
                entry.joint.Transform = CFrame.new()
                entry.joint.C0 = from:Lerp(to, alpha)
            end
            -- Apply the forward pose before authoring exactly one packet.
            if elapsed >= 0.3 and not released then
                released = true
                pcall(release)
            end
            if elapsed >= 0.55 then stopThrowAnimation() end
        end, "render")
    end

    local function throwKnife(): ()
        if throwPending or os.clock() - lastThrow < knifeThrowSettings.fireDelay then return end
        local knife: Tool? = getReadyKnife()
        if not knife then stopThrowAnimation(); return end
        local events: Instance? = knife:FindFirstChild("Events")
        local remote: Instance? = events and events:FindFirstChild("KnifeThrown")
        if not remote or not remote:IsA("RemoteEvent") then return end
        local character: Model? = LocalPlayer.Character
        local silent: boolean = knifeThrowSettings.mode == "Silent"
        local function getOrigin(target: Player?): CFrame?
            if not character or character ~= LocalPlayer.Character then return nil end
            local handle: any = knife:FindFirstChild("Handle")
            local hand: any = character:FindFirstChild("RightHand")
                or character:FindFirstChild("Right Arm") or character:FindFirstChild("HumanoidRootPart")
            local source: any = handle and handle:IsA("BasePart") and handle or hand
            if not source then return nil end
            local frame: CFrame = source.CFrame
            if silent and target and target.Character then
                local root: any = target.Character:FindFirstChild("HumanoidRootPart")
                if not root then return nil end
                local direction: Vector3 = frame.Position - root.Position
                direction = direction.Magnitude > 0.1 and direction.Unit or Vector3.new(0, 0, 1)
                return CFrame.new(root.Position + direction * knifeThrowSettings.spawnOffset)
            end
            return frame
        end
        local initialOrigin: CFrame? = getOrigin(nil)
        if not initialOrigin then return end
        local target: Player? = findNearestTarget(silent and 100000 or knifeThrowSettings.range,
            not silent and initialOrigin.Position or nil)
        if not target then return end
        local function sendAtRelease(): ()
            -- Re-read the held weapon, target, muzzle and prediction AFTER the
            -- wind-up. No frozen 300ms-old aim and no automatic re-equipping.
            if getReadyKnife() ~= knife or not isValidTarget(target :: Player) then return end
            local origin: CFrame? = getOrigin(target)
            if not origin then return end
            local root: any = target.Character:FindFirstChild("HumanoidRootPart")
            if not silent and (root.Position - origin.Position).Magnitude > knifeThrowSettings.range then return end
            local aim: Vector3? = predictAim(target :: Player, origin.Position)
            if not aim or (aim - origin.Position).Magnitude < 0.05 then return end
            if not silent and not isWeaponPathClear(origin.Position, aim, target.Character) then return end
            lastThrow = os.clock()
            remote:FireServer(origin, CFrame.new(aim))
            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "knife", tool = knife, toolName = knife.Name,
                originPos = origin.Position, aimPos = aim, target = target, silent = silent,
                settings = {mode = knifeThrowSettings.mode, throwHz = knifeThrowSettings.throwHz,
                    fireDelay = knifeThrowSettings.fireDelay, spawnOffset = knifeThrowSettings.spawnOffset,
                    model = "linear-intercept-v34", windupSeconds = knifeThrowSettings.animation and 0.3 or 0},
            })
        end
        local ok: boolean = pcall(playThrowAnimation, knife, sendAtRelease)
        if not ok then stopThrowAnimation() end
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
        "Auto-throws only while YOU hold the knife; never equips it. Targets the nearest player. Silent spawns the blade"
            .. " beside the target so it connects at any distance or through walls."
    )
    addActionOption(KnifeThrowFeature, "Throw now", function(): ()
        throwKnife()
    end)
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
        0.5,
        3,
        function(value: number): ()
            knifeThrowSettings.fireDelay = math.clamp(value, 0.5, 3)
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
        "Raises the knife, releases once, then recovers. R6 shoulder / R15 shoulder-elbow-wrist. "
            .. "OFF or unequip cancels the pending throw and restores the pose."
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
