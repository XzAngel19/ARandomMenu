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
    local mm2Settings: any = core.mm2Settings
    local lastKnifePrediction: any = nil
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
        local closest: Player? = nil
        local closestDistance: number = math.huge
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local targetRoot: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if targetRoot then
                    local distance: number =
                        (targetRoot.Position - localRoot.Position).Magnitude
                    if distance < closestDistance and resolveKnifeAim(player, origin) ~= nil then
                        closest = player
                        closestDistance = distance
                    end
                end
            end
        end
        return closest
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

    local function predictAim(target: Player, originPos: Vector3): Vector3?
        lastKnifePrediction = nil
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
        if not flight or not predictionMath.finite(flight) then return nil end
        local reference = observed + velocity * flight
        lastKnifePrediction = {motionSource="velocity", model="reference-v41", referenceEndpoint=reference}
        return reference
    end

    local KNIFE_VISIBILITY_PARTS: {string} = {
        "UpperTorso", "Torso", "HumanoidRootPart", "Head",
        "RightHand", "LeftHand", "RightLowerArm", "LeftLowerArm", "RightUpperArm", "LeftUpperArm",
        "Right Arm", "Left Arm", "RightLowerLeg", "LeftLowerLeg", "RightFoot", "LeftFoot", "Right Leg", "Left Leg",
    }
    local KNIFE_PATH_OPTIONS = {ignoreTarget = true}
    local KNIFE_VISIBLE_OPTIONS = {requireTarget = true}
    resolveKnifeAim = function(target: Player, origin: Vector3): Vector3?
        local predicted: Vector3? = predictAim(target, origin)
        if not predicted then return nil end
        local character: Model? = target.Character
        local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not character or not root then return nil end
        if isWeaponPathClear(origin, root.Position, character, nil, KNIFE_VISIBLE_OPTIONS)
            and isWeaponPathClear(origin, predicted, character, nil, KNIFE_PATH_OPTIONS) then return predicted end
        -- Same recovered ray filter and torso-first visibility strategy as
        -- Shoot, but keep projectile lead: no hitscan/raw-position rewind here.
        local lead: Vector3 = predicted - root.Position
        for _, name: string in ipairs(KNIFE_VISIBILITY_PARTS) do
            local part: Instance? = character:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                local body: BasePart = part :: BasePart
                local points: {Vector3} = {body.Position + lead}
                if name == "UpperTorso" or name == "Torso" or name == "HumanoidRootPart" then
                    local right: Vector3 = body.CFrame.RightVector * math.min(body.Size.X * 0.4, 0.55)
                    local up: Vector3 = body.CFrame.UpVector * math.min(body.Size.Y * 0.3, 0.35)
                    for _, offset: Vector3 in ipairs({right, -right, up, -up}) do
                        table.insert(points, body.Position + offset + lead)
                    end
                end
                for _, point: Vector3 in ipairs(points) do
                    if (point - origin).Magnitude > 0.05
                        and isWeaponPathClear(origin, point - lead, character, nil, KNIFE_VISIBLE_OPTIONS)
                        and isWeaponPathClear(origin, point, character, nil, KNIFE_PATH_OPTIONS) then return point end
                end
            end
        end
        return nil
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
                    cadence = "animation-cycle", model = lastKnifePrediction and lastKnifePrediction.model or "reference-v41",
                    referencePoint = lastKnifePrediction and {lastKnifePrediction.referenceEndpoint.X, lastKnifePrediction.referenceEndpoint.Y, lastKnifePrediction.referenceEndpoint.Z}, windupSeconds = 0.3},
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
