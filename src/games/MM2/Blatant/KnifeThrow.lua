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
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Knife Throw requires MM2 Prediction")
    local mm2Settings: any = core.mm2Settings
    local lastKnifePrediction: any = nil
    local lastKnifeError: string? = nil
    local isWeaponPathClear: any = core.isWeaponPathClear
    local trajectoryCalibration: any = core.trajectoryCalibration

    -- One preset: held knife, nearest visible target, normal origin,
    -- always-on animation/LOS. The animation owns the throw cadence.
    local knifeThrowSettings = {enabled = false}

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

    local resolveKnifeAim: (Player, Vector3) -> Vector3?
    local function findNearestTarget(origin: Vector3): Player?
        local localRoot: BasePart? = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not localRoot then
            return nil
        end
        local candidates: {{player: Player, distance: number}} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local targetRoot: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if targetRoot then
                    table.insert(candidates, {
                        player = player,
                        distance = (targetRoot.Position - localRoot.Position).Magnitude,
                    })
                end
            end
        end
        table.sort(candidates, function(left: any, right: any): boolean
            return left.distance < right.distance
        end)
        -- Corridor checks are rays: cap them per frame. The nearest three
        -- visible targets are enough; blocked players do not starve the rest.
        for index: number = 1, math.min(#candidates, 3) do
            local candidate: any = candidates[index]
            if resolveKnifeAim(candidate.player, origin) ~= nil then
                return candidate.player
            end
        end
        return nil
    end

    local function getReadyKnife(): Tool?
        if state.mm2SilentAimEnabled ~= true then return nil end
        if findMurderer() ~= LocalPlayer then
            return nil
        end
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil
        end

        local knife: Tool? = getPlayerWeapon(LocalPlayer, "Knife", true)
        if not knife or knife.Parent ~= character or knife.Enabled == false or knife:GetAttribute("Disabled") == true then
            return nil
        end
        return knife
    end

    local function readKnifeSpeed(knife: Tool?): number
        -- ThrowingKnifeVisuals: position += Direction * ThrowSpeed * dt,
        -- default 96 studs/s, no gravity term.
        local speed: number = 96
        if knife then
            local measured: any = knife:GetAttribute("ThrowSpeed")
            if type(measured) == "number"
                and measured == measured
                and measured >= 24
                and measured <= 300 then
                speed = measured
            end
        end
        return speed
    end

    -- The blade is a physical straight projectile, so graze tolerance matters:
    -- a single centre ray passes a wall the real knife then clips. STRICT means
    -- transparent parts are only ignored when they cannot collide; an invisible
    -- solid wall still stops the blade. The corridor is sampled with a small
    -- cross of rays around the centre line.
    local KNIFE_CORRIDOR_RADIUS: number = 0.5
    -- The blade keeps flying until it hits something, so there is no range
    -- limit: only an absurd lead (a vanished target, a broken sample) is
    -- refused. Ordinary long throws stay available.
    local MAX_KNIFE_DISTANCE: number = 400

    local function knifeCorridorClear(
        origin: Vector3,
        endpoint: Vector3,
        targetCharacter: Model
    ): boolean
        local delta: Vector3 = endpoint - origin
        local distance: number = delta.Magnitude
        if distance < 0.05 then
            return false
        end
        local direction: Vector3 = delta.Unit
        local right: Vector3 = direction:Cross(Vector3.new(0, 1, 0))
        if right.Magnitude < 1e-3 then
            right = Vector3.new(1, 0, 0)
        else
            right = right.Unit
        end
        local up: Vector3 = right:Cross(direction).Unit
        local offsets: {Vector3} = {
            Vector3.zero,
            right * KNIFE_CORRIDOR_RADIUS,
            right * -KNIFE_CORRIDOR_RADIUS,
            up * KNIFE_CORRIDOR_RADIUS,
            up * -KNIFE_CORRIDOR_RADIUS,
        }
        for _, offset: Vector3 in ipairs(offsets) do
            if not isWeaponPathClear(
                origin + offset,
                endpoint + offset,
                targetCharacter,
                true,
                {ignoreTarget = true}
            ) then
                return false
            end
        end
        return true
    end

    -- The blade is a straight projectile. The predictor solves the intercept
    -- (including the measured transport delay); WallCheck then verifies the
    -- exact corridor and that the target is not currently behind cover.
    resolveKnifeAim = function(target: Player, origin: Vector3): Vector3?
        lastKnifePrediction = nil
        lastKnifeError = nil
        local endpoint: Vector3?, info: any, reason: string? =
            prediction.knifeAim(target, origin, readKnifeSpeed(getReadyKnife()))
        if not endpoint then
            lastKnifeError = reason
            return nil
        end
        local character: Model? = target.Character
        if not character then
            return nil
        end
        if (endpoint - origin).Magnitude > MAX_KNIFE_DISTANCE then
            lastKnifeError = "too far"
            return nil
        end
        -- Cheapest rejection first: if the target is behind cover right now,
        -- the blade would fly into that wall whatever the future pose says.
        -- Here the target is NOT excluded, so reaching it proves line of sight.
        local captured: Vector3 = info and info.capturedPosition or endpoint
        if not isWeaponPathClear(origin, captured, character, true, nil) then
            lastKnifeError = "covered"
            return nil
        end
        if not knifeCorridorClear(origin, endpoint, character) then
            lastKnifeError = "obstructed"
            return nil
        end
        lastKnifePrediction = info
        return endpoint
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
            if onRelease then onRelease() end
        end
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
        if not knifeThrowSettings.enabled or throwPending then return end
        local knife: Tool? = getReadyKnife()
        if not knife then stopThrowAnimation(); return end
        local events: Instance? = knife:FindFirstChild("Events")
        local remote: Instance? = events and events:FindFirstChild("KnifeThrown")
        if not remote or not remote:IsA("RemoteEvent") then return end
        local character: Model? = LocalPlayer.Character
        local function getOrigin(): CFrame?
            if not character or character ~= LocalPlayer.Character then return nil end
            local handle: Instance? = knife:FindFirstChild("Handle")
            local hand: Instance? = character:FindFirstChild("RightHand")
                or character:FindFirstChild("Right Arm") or character:FindFirstChild("HumanoidRootPart")
            local source: Instance? = handle and handle:IsA("BasePart") and handle or hand
            if not source or not source:IsA("BasePart") then return nil end
            return (source :: BasePart).CFrame
        end
        local initialOrigin: CFrame? = getOrigin()
        if not initialOrigin or not findNearestTarget(initialOrigin.Position) then return end
        local function sendAtRelease(): ()
            if not knifeThrowSettings.enabled or getReadyKnife() ~= knife then return end
            local origin: CFrame? = getOrigin()
            if not origin then return end
            -- Select again at release: do not cling to a target that closed
            -- its peek during windup when another player is now visible.
            local target: Player? = findNearestTarget(origin.Position)
            if not target then return end
            local aim: Vector3? = resolveKnifeAim(target, origin.Position)
            if not aim or (aim - origin.Position).Magnitude < 0.05 then return end
            remote:FireServer(origin, CFrame.new(aim))
            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "knife", tool = knife, toolName = knife.Name,
                originPos = origin.Position, aimPos = aim, target = target, silent = false,
                settings = {mode = "Normal", animation = true, wallCheck = true,
                    motionSource = lastKnifePrediction and lastKnifePrediction.motionSource,
                    cadence = "animation-cycle",
                    model = lastKnifePrediction and lastKnifePrediction.model or "kinematic-v51",
                    referencePoint = lastKnifePrediction and {lastKnifePrediction.capturedPosition.X, lastKnifePrediction.capturedPosition.Y, lastKnifePrediction.capturedPosition.Z},
                    predictedPoint = lastKnifePrediction and {lastKnifePrediction.endpoint.X, lastKnifePrediction.endpoint.Y, lastKnifePrediction.endpoint.Z},
                    sampledVelocity = lastKnifePrediction and {lastKnifePrediction.velocity.X, lastKnifePrediction.velocity.Y, lastKnifePrediction.velocity.Z},
                    leadSeconds = lastKnifePrediction and lastKnifePrediction.leadSeconds,
                    flightSeconds = lastKnifePrediction and lastKnifePrediction.flightSeconds,
                    sampleAge = lastKnifePrediction and lastKnifePrediction.sampleAge,
                    samples = lastKnifePrediction and lastKnifePrediction.samples,
                    windupSeconds = 0.3},
            })
        end
        local ok: boolean = pcall(playThrowAnimation, knife, sendAtRelease)
        if not ok then stopThrowAnimation() end
    end

    local function refreshKnifeThrow(): ()
        disconnectFeatureConnection("MM2KnifeThrow")
        if not knifeThrowSettings.enabled or state.mm2SilentAimEnabled ~= true then
            stopThrowAnimation()
            return
        end
        featureConnections.MM2KnifeThrow = TaskManager:Connect(throwKnife)
    end
    local function toggleKnifeThrow(enabled: boolean): ()
        knifeThrowSettings.enabled = enabled
        if state.mm2KnifeRuntime then state.mm2KnifeRuntime.throwWanted = enabled end
        refreshKnifeThrow()
    end

    local feature: any = state.mm2SilentAimFeature
    assert(feature, "Knife Throw requires SilentAIM")
    local key = "MM2.Shoot.KnifeThrow"
    if configData.states[key] == nil then
        local previous = configData.states["Universal.KillAura.KnifeThrow"]
        if previous == nil then previous = configData.states["MM2.Knife.KnifeThrow"] end
        configData.states[key] = previous
    end
    local bind = "Shortcut.MM2ShootKnifeThrow"
    if configData.values[bind] == nil then
        configData.values[bind] = configData.values["Shortcut.UniversalKillAuraKnifeThrow"]
            or configData.values["Shortcut.MM2KnifeKnifeThrow"]
    end
    state.mm2KnifeThrowRefresh = refreshKnifeThrow
    state.mm2KnifeThrowOff = function(): () toggleKnifeThrow(false) end
    local button = addToggleOption(feature, "Knife Throw", false, toggleKnifeThrow,
        "SilentAIM ON + held knife: repeats throws at visible targets. Full animation and WallCheck are automatic.", true)
    -- Both automatic attacks belong at the top, ahead of Gun tuning. The
    -- option is created by a later module, so move its real row, not only its
    -- registry entry. The compact UI has no visible information headings.
    local row = button and button.Parent
    local index = row and table.find(feature.optionRows, row)
    if index then
        table.remove(feature.optionRows, index)
        table.insert(feature.optionRows, 2, row)
        for order, optionRow in ipairs(feature.optionRows) do optionRow.LayoutOrder = order end
    end
    if type(queueConfigSave) == "function" then queueConfigSave() end

    featureConnections.MM2KnifeThrowCharacter = LocalPlayer.CharacterAdded:Connect(stopThrowAnimation)
    activeCleanup = function(): ()
        toggleKnifeThrow(false)
        disconnectFeatureConnection("MM2KnifeThrowCharacter")
        state.mm2KnifeThrowOff = nil
        state.mm2KnifeThrowRefresh = nil
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
