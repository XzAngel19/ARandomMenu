local Module = {
    Name = "MM2 Shoot",
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
    assert(type(core) == "table", "MM2 Shoot requires the MM2 core module")
    local trajectoryCalibration: any = core.trajectoryCalibration
    Module.Runtime = runtime
    local connectGunFiredSignal: any = core.connectGunFiredSignal
    local disconnectGunFiredObserver: any = core.disconnectGunFiredObserver
    local findMurderer: any = core.findMurderer
    local getFilteredVelocity: any = core.getFilteredVelocity
    local getGunHorizonSeconds: any = core.getGunHorizonSeconds
    local getGunTurnDiscount: any = core.getGunTurnDiscount
    local getGunTurnRate: any = core.getGunTurnRate
    local getGunLeadSensitivity: any = core.getGunLeadSensitivity
    local getGunLeadStatus: any = core.getGunLeadStatus
    local resetAutoLeadCorrection: any = core.resetAutoLeadCorrection
    local getGunOriginCFrame: any = core.getGunOriginCFrame
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local getWeaponServiceModule: any = core.getWeaponServiceModule
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local mm2Settings: any = core.mm2Settings
    local motionSamples: any = core.motionSamples
    local predictionMath: any = core.predictionMath
    local isMotionGrounded: any = core.isMotionGrounded
    local LIVE_TARGET_PATH = {requireTarget = true}
    local function isWeaponPathClear(origin: Vector3, endpoint: Vector3, target: Model?, requireTarget: boolean?): boolean
        -- Use the recovered WeaponService cursor filter (including its
        -- transparent-part handling), not v32's speculative strict mode.
        return core.isWeaponPathClear(origin, endpoint, target, nil, requireTarget and LIVE_TARGET_PATH or nil)
    end

    local shootMacro: boolean = false
    local function macroUnequip(gun: Tool?): ()
        if not shootMacro or not gun then
            return
        end
        task.delay(0.01, function(): ()
            pcall(function(): ()
                local backpack: Instance? = LocalPlayer:FindFirstChildOfClass("Backpack")
                local character: Model? = LocalPlayer.Character
                if backpack and character and gun.Parent == character then
                    gun.Parent = backpack
                end
            end)
        end)
    end

    type GunPrediction = {
        motionSource: string?,
        targetPosition: Vector3,
        endpoint: Vector3,
        velocity: Vector3,
        errorRadius: number,
        leadSeconds: number,
        leadSensitivity: number,

        capturedPosition: Vector3,
        aimRootOffset: Vector3,
        model: string?,
        referenceEndpoint: Vector3?,
    }

    type GunAimOptions = {

        ignoreVisibility: boolean?,
        allowUncertain: boolean?,
    }

    local BODY_HALF_WIDTH: number = 1.0

    local MINIMUM_ERROR_RADIUS: number = 0.35

    local AIM_PARTS: {string} = {
        "UpperTorso",
        "Torso",
        "HumanoidRootPart",
        "Head",
    }

    -- Searched only when the main aim point is wall-blocked, in priority
    -- order: big center-mass parts first, then the limbs that typically poke
    -- out of cover (a hand holding the knife around a corner).
    local VISIBILITY_PARTS: {string} = {
        "UpperTorso",
        "Torso",
        "HumanoidRootPart",
        "Head",
        "RightHand",
        "LeftHand",
        "RightLowerArm",
        "LeftLowerArm",
        "RightUpperArm",
        "LeftUpperArm",
        "RightLowerLeg",
        "LeftLowerLeg",
        "RightFoot",
        "LeftFoot",
        "Right Arm",
        "Left Arm",
        "Right Leg",
        "Left Leg",
    }

    local function findAimPart(character: Model): BasePart?
        for _, partName: string in ipairs(AIM_PARTS) do
            local part: BasePart? = character:FindFirstChild(partName) :: BasePart?
            if part and part:IsA("BasePart") then
                return part
            end
        end
        return nil
    end

    local function computeGunAim(
        target: Player,
        origin: CFrame,
        options: GunAimOptions?
    ): (CFrame?, GunPrediction?, string?)
        local resolvedOptions: GunAimOptions = options or {}
        local ignoreVisibility: boolean = resolvedOptions.ignoreVisibility == true
        local character: Model? = target.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local root: BasePart? = character
            and character:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        if not character or not humanoid or humanoid.Health <= 0 or not root then
            return nil, nil, "no body"
        end

        local part: BasePart? = findAimPart(character :: Model)
        if not part then
            return nil, nil, "no body"
        end

        local velocity: Vector3 = getFilteredVelocity(target, root :: BasePart)
        local sample: MotionSample? = motionSamples[target]
        if sample and (sample.character ~= character or os.clock() - sample.sampledAt > 0.25) then
            sample = nil
        end
        local acceleration: Vector3 = sample and sample.acceleration or Vector3.zero
        -- Do not use `a and false or fallback`: airborne false is meaningful.
        local grounded: boolean = isMotionGrounded(humanoid, velocity)

        local turnRate: number = getGunTurnRate(
            sample and sample.character == character and sample or nil
        )

        -- Remote MoveDirection is not authoritative velocity (the supplied
        -- traces contain opposing direction/velocity samples). Do not invent
        -- WalkSpeed motion for a target whose measured velocity is zero.
        local horizontalVelocity: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)

        local horizon: number = getGunHorizonSeconds()
        local discount: number = getGunTurnDiscount(horizon, turnRate)
        local lead: number = horizon * discount
        local leadSensitivity: number = type(getGunLeadSensitivity) == "function"
            and getGunLeadSensitivity(horizon, turnRate)
            or discount

        local horizontalAcceleration: Vector3 = Vector3.new(
            acceleration.X,
            0,
            acceleration.Z
        )

        -- Never lead further than the time the target needs to stop. A
        -- strafing player that reverses (peeking in and out of cover) would
        -- otherwise be overshot ahead of his movement ("como prediciendo el
        -- futuro"); the same damping shrinks the lead the moment the target
        -- decelerates, so the aim tracks back toward his real path.
        local horizontalSpeed: number = horizontalVelocity.Magnitude
        if horizontalSpeed > 1 and lead > 0 then
            local opposing: number =
                -horizontalAcceleration:Dot(horizontalVelocity.Unit)
            if opposing > 0 then
                local stopTime: number =
                    horizontalSpeed / math.max(opposing, 1)
                if stopTime < lead then
                    lead = stopTime
                end
            end
        end

        local displacement: Vector3 = Vector3.new(
            velocity.X * lead,
            0,
            velocity.Z * lead
        ) + horizontalAcceleration * (0.25 * lead * lead)

        -- Vertical safety. Remote characters often read FloorMaterial = Air
        -- on our client, so a player walking flat ground can be misclassified
        -- as airborne; combined with the old ballistic drop this buried shots
        -- several studs BELOW the target ("el tiro sale demasiado abajo").
        -- A hitscan gun has no bullet drop of its own, and a walker on flat
        -- ground has no vertical motion to predict, so: near-zero vertical
        -- velocity means zero vertical lead, and the airborne term is capped.
        -- The humanoid STATE (Jumping/Freefall) replicates with the humanoid
        -- itself and can arrive before the physics velocity does, so an
        -- early jump gets a minimum upward assumption instead of a flat shot.
        local jumpState: boolean = false
        local risingJumpState: boolean = false
        do
            local ok: boolean, stateName: any = pcall(function(): any
                return (humanoid :: Humanoid):GetState()
            end)
            risingJumpState = ok and stateName == Enum.HumanoidStateType.Jumping
            jumpState = ok
                and (stateName == Enum.HumanoidStateType.Jumping
                    or stateName == Enum.HumanoidStateType.Freefall)
        end
        local effectivelyGrounded: boolean =
            (grounded or math.abs(velocity.Y) <= 0.5) and not jumpState
        local verticalDisplacement: number = 0
        if not effectivelyGrounded then
            local verticalVelocity: number = velocity.Y
            local risingJump: boolean = risingJumpState
                and verticalVelocity < 8
                and verticalVelocity > -8
            if risingJump then
                verticalVelocity = 8
            end
            verticalDisplacement = math.clamp(
                verticalVelocity * lead
                    - 0.5 * workspace.Gravity * lead * lead,
                -3,
                6 -- v31 shot :40: +4.16 observed, +4.18 ballistic; old +3 clipped it
            )
        elseif grounded then
            verticalDisplacement = math.clamp(velocity.Y, -2.5, 2.5) * lead
        end
        displacement = Vector3.new(
            displacement.X,
            verticalDisplacement,
            displacement.Z
        )

        local referenceEndpoint = part.Position + displacement
        local adaptive = mm2Settings.predictionModel == "Adaptive"
        local motionSource = "velocity"
        local adaptiveError = MINIMUM_ERROR_RADIUS
        if adaptive then
            local history = sample and sample.history
            local measuredAcceleration = Vector3.zero
            local measuredTurn = 0
            if history and #history >= 3 then
                local current, previous, earlier = history[#history], history[#history - 1], history[#history - 2]
                local dt = current.at - previous.at
                if dt >= 1 / 240 and dt < 0.25 and os.clock() - current.at < 0.25 then
                    local beforeDt = previous.at - earlier.at
                    local cv = Vector3.new(current.velocity.X, 0, current.velocity.Z)
                    local pv = Vector3.new(previous.velocity.X, 0, previous.velocity.Z)
                    local ev = Vector3.new(earlier.velocity.X, 0, earlier.velocity.Z)
                    if beforeDt >= 1 / 240 and cv.Magnitude > 1 and pv.Magnitude > 1 and ev.Magnitude > 1 then
                        local currentAngle = math.atan2(pv.X * cv.Z - pv.Z * cv.X, pv:Dot(cv))
                        local beforeAngle = math.atan2(ev.X * pv.Z - ev.Z * pv.X, ev:Dot(pv))
                        local rate, beforeRate = currentAngle / dt, beforeAngle / beforeDt
                        if rate * beforeRate > 0 and math.abs(currentAngle) < math.pi / 3
                            and math.abs(rate) >= math.abs(beforeRate) * 0.5
                            and math.abs(rate) <= math.abs(beforeRate) * 2 then measuredTurn = rate end
                        if cv.Magnitude < pv.Magnitude - 0.1 and pv.Magnitude < ev.Magnitude - 0.1
                            and cv.Unit:Dot(pv.Unit) > 0.9 then
                            measuredAcceleration = (cv - pv) / dt
                        end
                    end
                end
            end
            -- Ignore curvature/deceleration smaller than the existing body
            -- uncertainty floor; tiny replicated heading jitter is not a turn.
            if math.abs(measuredTurn) * horizontalVelocity.Magnitude * horizon * horizon * 0.5 < MINIMUM_ERROR_RADIUS then measuredTurn = 0 end
            if measuredAcceleration.Magnitude * horizon * horizon * 0.5 < MINIMUM_ERROR_RADIUS then measuredAcceleration = Vector3.zero end
            local sensitivity
            displacement, adaptiveError, sensitivity = predictionMath.gunAdaptive(
                velocity, measuredAcceleration, horizon, workspace.Gravity, grounded, jumpState, measuredTurn)
            if measuredTurn == 0 and measuredAcceleration.Magnitude == 0 and horizontalVelocity.Magnitude >= 0.05 then
                -- No supported curve/brake: retain A's horizontal estimate,
                -- not an unvalidated CV replacement of every trajectory.
                displacement = Vector3.new(referenceEndpoint.X - part.Position.X, displacement.Y, referenceEndpoint.Z - part.Position.Z)
            end
            local observedVelocity = horizontalVelocity.Magnitude < 1 and predictionMath.observedHorizontalVelocity(sample and sample.positionHistory) or nil
            if observedVelocity and measuredTurn == 0 and measuredAcceleration.Magnitude == 0 then
                local observedLead = observedVelocity * horizon
                local difference = observedLead - Vector3.new(displacement.X,0,displacement.Z)
                if difference.Magnitude > MINIMUM_ERROR_RADIUS then
                    displacement = Vector3.new(observedLead.X,displacement.Y,observedLead.Z)
                    lead, leadSensitivity = horizon, 1
                    motionSource = "position"
                end
            end
            local correctedJump = grounded and jumpState and math.abs(velocity.Y) <= 6
                or risingJumpState and math.abs(velocity.Y) < 8
            -- Preserve the proven vertical estimate except the two identified
            -- state/velocity disagreement cases; floor geometry still wins.
            local vertical = correctedJump and displacement.Y or verticalDisplacement
            displacement = Vector3.new(displacement.X, math.clamp(vertical, -3, 6), displacement.Z)
            if measuredTurn ~= 0 or measuredAcceleration.Magnitude > 0 then
                lead = horizon
                leadSensitivity = sensitivity
            end
            -- Only a real collidable floor under the predicted landing point
            -- can clamp a fall. No invented jump velocity or bullet gravity.
            if displacement.Y < 0 then
                pcall(function()
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances = {character, LocalPlayer.Character}
                    params.RespectCanCollide = true
                    params.IgnoreWater = true
                    local start = root.Position + Vector3.new(displacement.X, 0, displacement.Z)
                    local distance = math.min(64, math.abs(displacement.Y) + humanoid.HipHeight + root.Size.Y * 0.5 + 2)
                    local hit = workspace:Raycast(start, Vector3.new(0, -distance, 0), params)
                    if hit then
                        local floorDelta = hit.Position.Y + humanoid.HipHeight + root.Size.Y * 0.5 - root.Position.Y
                        if floorDelta <= 0.25 then displacement = Vector3.new(displacement.X, math.max(displacement.Y, floorDelta), displacement.Z) end
                    end
                end)
            end
        end
        local predicted: Vector3 = part.Position + displacement
        local delta: Vector3 = predicted - origin.Position
        if delta.Magnitude <= 0.05 then
            return nil, nil, "too close"
        end

        if not ignoreVisibility and mm2Settings.shootWallCheck then
            -- Visibility is a CURRENT-body test, never proof supplied by a
            -- predicted point in empty space. A closed peek must fail even
            -- when an old/future lead position has an unobstructed ray.
            local visible: Vector3? = nil
            local visiblePart: BasePart? = nil
            for _, partName: string in ipairs(VISIBILITY_PARTS) do
                local candidate: Instance? = character:FindFirstChild(partName)
                if candidate and candidate:IsA("BasePart") then
                    local body: BasePart = candidate :: BasePart
                    local points: {Vector3} = {body.Position}
                    local right: Vector3 = body.CFrame.RightVector * math.min(body.Size.X * 0.35, 0.55)
                    local up: Vector3 = body.CFrame.UpVector * math.min(body.Size.Y * 0.25, 0.35)
                    local probeOffsets: {Vector3} = {right, -right}
                    if table.find(AIM_PARTS, partName) then
                        table.insert(probeOffsets, up)
                        table.insert(probeOffsets, right * 0.64 + up * 0.71)
                        table.insert(probeOffsets, -right * 0.64 + up * 0.71)
                    end
                    for _, offset: Vector3 in ipairs(probeOffsets) do table.insert(points, body.Position + offset) end
                    for _, point: Vector3 in ipairs(points) do
                        if (point - origin.Position).Magnitude > 0.05
                            and isWeaponPathClear(origin.Position, point, character, true) then
                            visible = point
                            visiblePart = body
                            break
                        end
                    end
                end
                if visible then break end
            end
            if not visible or not visiblePart then return nil, nil, "obstructed" end
            -- Keep the solver's lead, anchored to the visible part NOW. If
            -- cover blocks that lead, the currently exposed sliver wins.
            part = visiblePart
            local ledPoint: Vector3 = visible + displacement
            predicted = isWeaponPathClear(origin.Position, ledPoint, character) and ledPoint or visible
            delta = predicted - origin.Position
        end

        local turnError: number = displacement.Magnitude
            * math.sin(math.min(horizon * turnRate * 0.5, math.pi * 0.5))
        local jitter: number = math.min(acceleration.Magnitude / 240, 0.45)
        local errorRadius: number = math.max(
            MINIMUM_ERROR_RADIUS,
            turnError + jitter
        )
        local allowedErrorBudget: number = ignoreVisibility and (BODY_HALF_WIDTH * 1.75) or BODY_HALF_WIDTH
        if adaptive then errorRadius = math.max(errorRadius, adaptiveError) end
        if not adaptive and errorRadius > allowedErrorBudget and not resolvedOptions.allowUncertain then
            return nil, nil, "turning too hard"
        end

        local direction: Vector3 = delta.Unit
        return CFrame.lookAt(predicted, predicted + direction), {
            targetPosition = predicted,
            endpoint = predicted,
            velocity = velocity,
            errorRadius = errorRadius,
            leadSeconds = lead,
            leadSensitivity = leadSensitivity,
            capturedPosition = part.Position,
            aimRootOffset = part.Position - (root :: BasePart).Position,
            motionSource = motionSource,
            model = adaptive and "adaptive-v44" or "reference-v41",
            referenceEndpoint = referenceEndpoint,
        }, nil
    end

    local function getSelectedShootTarget(): Player?
        local target
        if mm2Settings.shootMode == "Custom"
            and mm2Settings.shootTarget ~= "" then
            target = findPlayerByText(mm2Settings.shootTarget)
        else
            target = findMurderer()
        end
        if not target
            or target == LocalPlayer
            or not isPlayerAlive(target)
            or isProtectedTarget(target) then
            return nil
        end
        if mm2Settings.shootMode ~= "Custom"
            and getPlayerRole(target) ~= "Murderer" then
            return nil
        end
        return target
    end

    local function bystanderOnSegment(
        target: Player,
        startPoint: Vector3,
        endPoint: Vector3
    ): boolean
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Include
        parameters.IgnoreWater = true
        local bodies: {Instance} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= target
                and player ~= LocalPlayer
                and player.Character
                and isPlayerAlive(player) then
                table.insert(bodies, player.Character)
            end
        end
        if #bodies == 0 then
            return false
        end
        parameters.FilterDescendantsInstances = bodies
        return workspace:Raycast(startPoint, endPoint - startPoint, parameters) ~= nil
    end

    local SILENT_ORIGIN_STUDS: number = 2.5
    local SILENT_PIERCE_STUDS: number = 1.0
    local SILENT_LIFT_STUDS: number = 1.6
    local MAX_SILENT_SWEEP: number = 1.5

    local function getSilentSweepDistance(): number
        local configured: number = tonumber(mm2Settings.silentSweep) or 0
        return math.clamp(configured, 0, MAX_SILENT_SWEEP)
    end

    local function buildSilentShot(
        target: Player,
        prediction: GunPrediction,
        muzzleOrigin: CFrame?,
        variant: string
    ): (CFrame?, CFrame?, number)
        local predicted: Vector3 = prediction.targetPosition
        local velocity: Vector3 = prediction.velocity
        local horizontal: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)

        local direction: Vector3? = nil
        local sweep: number = 0
        if horizontal.Magnitude > 1.5 then
            direction = horizontal.Unit

            sweep = getSilentSweepDistance()
        end
        local sweepStart: Vector3 =
            direction and -direction * sweep or Vector3.zero
        local sweepEnd: Vector3 =
            direction and direction * sweep or Vector3.zero

        local approach: Vector3? = nil
        local approachOffset: number = SILENT_ORIGIN_STUDS
        if muzzleOrigin then
            local toTarget: Vector3 = predicted - muzzleOrigin.Position
            local flat: Vector3 = Vector3.new(toTarget.X, 0, toTarget.Z)
            if flat.Magnitude > 0.05 then
                approach = flat.Unit
                approachOffset = math.min(
                    SILENT_ORIGIN_STUDS,
                    math.max(1.0, flat.Magnitude * 0.6)
                )
            end
        end

        local startPoint: Vector3
        local endPoint: Vector3
        if variant == "Through" and approach then

            local captured: Vector3 = prediction.capturedPosition or predicted
            startPoint = captured - approach * 1.0 + sweepStart
            endPoint = predicted + approach * SILENT_PIERCE_STUDS + sweepEnd
        elseif variant == "Top" then
            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
                + sweepStart
            endPoint = predicted + sweepEnd
        elseif variant == "Behind" and approach then
            startPoint = predicted + approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif approach then

            startPoint = predicted - approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif direction then
            startPoint = predicted + sweepStart
            endPoint = predicted + sweepEnd
        else

            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            endPoint = predicted
        end

        if (endPoint - startPoint).Magnitude <= 0.05 then
            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            endPoint = predicted
        end
        -- Through has length even when the configurable extra sweep is zero.
        if bystanderOnSegment(target, startPoint, endPoint) then

            if variant ~= "Top" and approach then
                startPoint = predicted - approach * approachOffset
            else
                startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            end
            endPoint = predicted
            if bystanderOnSegment(target, startPoint, endPoint) then
                return nil, nil, 0
            end
        end

        return CFrame.lookAt(startPoint, endPoint), CFrame.new(endPoint),
            approachOffset
    end

    type FireOptions = {
        silent: boolean?,
        maxError: number?,
        quiet: boolean?,
        whenReady: boolean?,
    }

    local lastRejectReason: string = ""

    local function fireGunAtTarget(
        target: Player?,
        options: FireOptions?
    ): boolean
        local opts: FireOptions = options or {}
        local silent: boolean = mm2Settings.silentAim
        if opts.silent ~= nil then
            silent = opts.silent
        end
        local quiet: boolean = opts.quiet == true
        local function reject(message: string): boolean
            lastRejectReason = message
            if not quiet then
                notify(message)
            end
            return false
        end

        local character, humanoid = getCharacterParts()
        if not target or not target.Character then
            return reject("No selected shoot target was found.")
        end
        if not character or not humanoid then
            return reject("Your character is not available.")
        end
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun", true)
        if not gun or gun.Parent ~= character then
            return reject("Equip the sheriff gun yourself to shoot.")
        end
        if gun.Enabled == false or gun:GetAttribute("Disabled") == true
            or gun:GetAttribute("Reloading") == true or gun:GetAttribute("IsReloading") == true then
            return reject("The gun is disabled or reloading.")
        end

        local remote: Instance? = gun and gun:FindFirstChild("Shoot")
        local origin: CFrame? = getGunOriginCFrame(character, gun)

        local aim: CFrame?, prediction: GunPrediction?, reason: string? = nil
        if origin then
            aim, prediction, reason = computeGunAim(
                target,
                origin :: CFrame,
                {ignoreVisibility = silent, allowUncertain = opts.whenReady == true}
            )
        end

        local rejectMessages: {[string]: string} = {
            ["no body"] = "The murderer has no usable body to aim at.",
            ["too close"] = "The murderer is too close to shoot cleanly.",
            ["obstructed"] = "A wall blocks the shot.",
            ["turning too hard"] = "The murderer is turning too hard to lead.",
        }
        if not remote
            or not remote:IsA("RemoteEvent")
            or not origin
            or not aim
            or not prediction then
            local message: string = rejectMessages[reason or ""]
                or (
                    not origin
                        and "The gun has no usable origin."
                        or (silent
                            and "The murderer has no usable body to aim at."
                            or "The murderer is unavailable or obstructed.")
                )
            return reject(message)
        end

        local resolved: GunPrediction = prediction :: GunPrediction
        if opts.maxError
            and resolved.errorRadius > opts.maxError then

            return reject("Shot accuracy is too low to fire.")
        end

        -- Do not infer a reload from our last REQUEST: a rejected packet
        -- never proves the server fired. Native Tool/attribute readiness is
        -- checked above; no speculative 3.1-second local lockout.
        if silent then

            local variant: string = mm2Settings.silentSpawn
            local shotOrigin: CFrame?, shotEnd: CFrame?, offset: number =
                buildSilentShot(target, resolved, origin, variant)
            if not shotOrigin or not shotEnd then
                return reject("Another player blocks the silent shot.")
            end
            state.mm2ShotFeedback.queue(target, gun, shotOrigin, shotEnd, resolved)
            if state.mm2ShotFeedback.pending then
                state.mm2ShotFeedback.pending.silentSpawn = variant
            end

            state.lastSilentShotInfo = {
                variant = variant,
                at = os.clock(),
                offset = math.floor(offset * 10) / 10,
            }
            remote:FireServer(shotOrigin, shotEnd)

            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "gun",
                tool = gun,
                toolName = gun and gun.Name or "Gun",
                originPos = shotOrigin.Position,
                aimPos = shotEnd.Position,
                target = target,
                silent = true,
                variant = variant,
                offset = offset,
                settings = {mode = "Silent", spawn = mm2Settings.silentSpawn,
                    sweep = mm2Settings.silentSweep, motionHz = mm2Settings.motionSampleHz,
                    leadSeconds = resolved.leadSeconds, errorRadius = resolved.errorRadius,
                    predictionModel = resolved.model, motionSource = resolved.motionSource,
                    referencePoint = resolved.referenceEndpoint and {resolved.referenceEndpoint.X, resolved.referenceEndpoint.Y, resolved.referenceEndpoint.Z},
                    predictedPoint = {resolved.endpoint.X, resolved.endpoint.Y, resolved.endpoint.Z},
                    sampledVelocity = {resolved.velocity.X, resolved.velocity.Y, resolved.velocity.Z}},
            })
            macroUnequip(gun)
            return true
        end

        state.mm2ShotFeedback.queue(target, gun, origin, aim, resolved)
        -- Author one endpoint, without speculative "piercing" past it.
        -- Echo timing documents transport/visual confirmation, NOT rewind
        -- duration or an authoritative hit-rate denominator.
        remote:FireServer(
            CFrame.lookAt(origin.Position, resolved.endpoint),
            CFrame.new(resolved.endpoint)
        )
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "gun",
            tool = gun,
            toolName = gun and gun.Name or "Gun",
            originPos = origin.Position,
            aimPos = resolved.endpoint,
            target = target,
            silent = false,
            settings = {mode = "Normal", wallCheck = mm2Settings.shootWallCheck,
                motionHz = mm2Settings.motionSampleHz, leadBias = mm2Settings.gunLeadBias,
                wallCheckPolicy = "live-body-first-hit", leadSeconds = resolved.leadSeconds, errorRadius = resolved.errorRadius,
                predictionModel = resolved.model, motionSource = resolved.motionSource,
                referencePoint = resolved.referenceEndpoint and {resolved.referenceEndpoint.X, resolved.referenceEndpoint.Y, resolved.referenceEndpoint.Z},
                predictedPoint = {resolved.endpoint.X, resolved.endpoint.Y, resolved.endpoint.Z},
                sampledVelocity = {resolved.velocity.X, resolved.velocity.Y, resolved.velocity.Z}},
        })
        macroUnequip(gun)
        return true
    end

    local shootOptionsReady: boolean = false
    local shootFeatureActive: boolean = false
    local autoShootActive: boolean = false
    local autoShootWanted: boolean = false
    local ShootFeature: any = nil
    local updateAutoShootConnection: (() -> ())? = nil

    local function refreshShootInfrastructure(): ()
        local wantActive: boolean = shootFeatureActive or autoShootActive
        state.mm2ShotFeedback.shootActive = wantActive
        if wantActive then
            if not featureConnections.MM2MotionTracker then
                local weaponService: any = getWeaponServiceModule()
                if type(weaponService) == "table" then
                    connectGunFiredSignal(weaponService)
                end
                local motionElapsed: number = 0
                featureConnections.MM2MotionTracker = TaskManager:Connect(function(
                    deltaTime: number
                ): ()
                    local due: boolean
                    due, motionElapsed = predictionMath.sampleDue(motionElapsed, deltaTime, mm2Settings.motionSampleHz)
                    if not due then return end
                    -- Only the selected target needs prediction history; the
                    -- solver also reads fresh velocity at the instant of fire.
                    local player: Player? = getSelectedShootTarget()
                    local root: BasePart? = player and player.Character
                        and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if player and root then getFilteredVelocity(player, root) end
                end)
            end
            return
        end
        disconnectFeatureConnection("MM2MotionTracker")
        disconnectGunFiredObserver()
        state.mm2ShotFeedback.pending = nil
        state.mm2ShotFeedback.lastAccepted = nil
        state.mm2ShotFeedback.hide()
    end

    local manualShotPending: boolean = false
    local function triggerManualShot(): ()
        if not shootFeatureActive then
            notify("Enable SilentAIM first.")
            return
        end
        if manualShotPending then return end
        local character, humanoid = getCharacterParts()
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
        if not character or not humanoid or not gun then
            notify("No sheriff gun is available.")
            return
        end
        manualShotPending = true
        local ok: boolean, message: any = pcall(function(): ()
            if gun.Parent ~= character then
                humanoid:EquipTool(gun)
                -- Let the grip/muzzle update before sampling its origin.
                RunService.Heartbeat:Wait()
            end
            -- Never re-equip if the user switched away during that frame.
            if shootFeatureActive and LocalPlayer.Character == character and gun.Parent == character then
                -- An explicit action never waits for a low prediction error.
                -- This flag skips only that gate, not native reload/readiness or LOS.
                fireGunAtTarget(getSelectedShootTarget(), {whenReady = true})
            end
        end)
        manualShotPending = false
        if not ok then notify("Shoot failed: " .. tostring(message)) end
    end

    local function toggleShootMurderer(enabled: boolean): ()
        shootFeatureActive = enabled
        state.mm2SilentAimEnabled = enabled
        if state.mm2KnifeThrowRefresh then state.mm2KnifeThrowRefresh() end
        autoShootActive = shootFeatureActive and autoShootWanted
        refreshShootInfrastructure()
        if updateAutoShootConnection then updateAutoShootConnection() end
    end

    local lastAutoStatus: string? = nil
    local function autoStatus(message: string): ()
        if ShootFeature and lastAutoStatus ~= message then
            lastAutoStatus = message
            ShootFeature:SetStatus(message)
        end
    end

    local function autoShootTick(): ()
        if not shootFeatureActive or not autoShootActive then return end
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun", true)
        if not gun or gun.Parent ~= LocalPlayer.Character then
            autoStatus("Equip gun")
            return
        end
        local target: Player? = getSelectedShootTarget()
        if not target then autoStatus("No target"); return end
        lastRejectReason = ""
        local sent: boolean = fireGunAtTarget(target, {whenReady = true, quiet = true})
        autoStatus(sent and "Auto: request sent" or lastRejectReason)
    end

    updateAutoShootConnection = function(): ()
        disconnectFeatureConnection("MM2AutoShoot")
        autoShootActive = shootOptionsReady and shootFeatureActive and autoShootWanted
        if not autoShootActive then
            lastAutoStatus = nil
            if ShootFeature then ShootFeature:SetStatus(nil) end
            return
        end
        -- One attempt per current frame, with no range/confidence/fire-delay
        -- timer. No cached aim or visibility survives into the next attempt.
        featureConnections.MM2AutoShoot = TaskManager:Connect(autoShootTick)
        autoShootTick()
    end

    local function toggleAutoShoot(enabled: boolean): ()
        autoShootWanted = enabled
        autoShootActive = shootFeatureActive and autoShootWanted
        refreshShootInfrastructure()
        if updateAutoShootConnection then updateAutoShootConnection() end
    end

    -- Preserve explicit bindings and enabled state when the old card becomes
    -- a child option. Never overwrite a setting already saved for the child.
    if type(configData) == "table" then
        local changed: boolean = false
        if configData.states["MM2.Shoot.AutoShoot"] == nil and configData.states["MM2.AutoShoot"] ~= nil then
            local enabled: boolean = configData.states["MM2.AutoShoot"] == true
            configData.states["MM2.Shoot.AutoShoot"] = enabled
            if enabled then configData.states["MM2.Shoot"] = true end
            changed = true
        end
        local oldKey: any = configData.values["Shortcut.MM2AutoShoot"]
        if configData.values["Shortcut.MM2ShootAutoShoot"] == nil and type(oldKey) == "string" then
            configData.values["Shortcut.MM2ShootAutoShoot"] = oldKey
            changed = true
        end
        if changed and type(queueConfigSave) == "function" then queueConfigSave() end
    end

    if type(configData) == "table" and configData.values["MM2.Shoot.Aimmethod"] == nil then
        configData.values["MM2.Shoot.Aimmethod"] = configData.values["MM2.Shoot.Mode"]
    end
    ShootFeature = createUniversalFeature(
        "SilentAIM",
        "Gun aim and Knife Throw. The main assigned key fires/equips Gun; Auto Shoot and Knife Throw use your held weapon. Aim method and lead controls below apply to Gun.",
        4,
        toggleShootMurderer,
        {
            categoryName = "Combat",
            configKey = "MM2.Shoot", -- preserve existing Gun settings and activation key
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2SilentAimFeature = ShootFeature
    addToggleOption(ShootFeature, "Auto Shoot", false, toggleAutoShoot,
        "While SilentAIM is ON and you hold the gun: try every frame as soon as the current target is visible. No distance or prediction-confidence gate. Uses the Gun aim method.", true)
    local ShootTargetBox
    local wallCheckRow: GuiObject? = nil
    local silentSweepRow: GuiObject? = nil
    local silentSpawnRow: GuiObject? = nil
    local spawnStatsRow: GuiObject? = nil
    local function refreshShootOptions(): ()
        if ShootTargetBox then
            setOptionVisible(
                ShootFeature,
                ShootTargetBox.Parent :: GuiObject,
                mm2Settings.shootMode == "Custom"
            )
        end
        -- Silent-only controls stay hidden while the mode is Prediction.
        local silent: boolean = mm2Settings.silentAim == true
        if wallCheckRow then setOptionVisible(ShootFeature, wallCheckRow, not silent) end
        if silentSweepRow then
            setOptionVisible(ShootFeature, silentSweepRow :: GuiObject, silent)
        end
        if silentSpawnRow then
            setOptionVisible(ShootFeature, silentSpawnRow :: GuiObject, silent)
        end
        if spawnStatsRow then
            setOptionVisible(ShootFeature, spawnStatsRow :: GuiObject, silent)
        end
    end
    addCycleOption(
        ShootFeature,
        "Aim method",
        {"Prediction", "Silent AIM"},
        mm2Settings.silentAim and 2 or 1,
        function(value: string): ()
            mm2Settings.silentAim = value == "Silent AIM"
            refreshShootOptions()
        end,
        "Prediction fires from your gun with lead compensation. Silent AIM "
            .. "authors the shot at the target: same prediction, works through "
            .. "walls."
    )
    addCycleOption(
        ShootFeature,
        "Target",
        {"Murder", "Custom"},
        mm2Settings.shootMode == "Custom" and 2 or 1,
        function(value: string): ()
            mm2Settings.shootMode = value
            refreshShootOptions()
        end
    )

    if state.bindFeatureActivationKey then
        state.bindFeatureActivationKey(
            ShootFeature,
            mm2Settings.shootKey,
            triggerManualShot
        )
    end
    local wallButton = addToggleOption(
        ShootFeature,
        "WallCheck",
        mm2Settings.shootWallCheck,
        function(value: boolean): ()
            mm2Settings.shootWallCheck = value
        end,
        "Holds fire while a wall blocks the muzzle. If only a sliver of the "
            .. "target is exposed — a hand or arm around a corner — the shot "
            .. "aims at that visible part. Silent AIM skips it: it authors "
            .. "the shot at the target."
    )
    wallCheckRow = wallButton and wallButton.Parent
    addToggleOption(
        ShootFeature,
        "Macro",
        shootMacro,
        function(value: boolean): ()
            shootMacro = value
        end,
        "Pistol macro: hides the gun 0.01 seconds after every shot."
    )
    silentSweepRow = addNumberOption(
        ShootFeature,
        "Silent sweep",
        mm2Settings.silentSweep,
        0,
        MAX_SILENT_SWEEP,
        function(value: number): ()
            mm2Settings.silentSweep = math.clamp(value, 0, MAX_SILENT_SWEEP)
        end,
        "Exact extra distance in studs at each end of the silent shot ray, "
            .. "along measured horizontal movement. 0 disables it; max 1.5. "
            .. "No local physics change. Segments crossing another player are "
            .. "shortened and checked again, or rejected.",
        0.05
    )
    local silentSpawnValues: {string} = {"Front", "Through", "Top", "Behind"}
    local silentSpawnIndex: number = 1
    for valueIndex: number, value: string in ipairs(silentSpawnValues) do
        if value == mm2Settings.silentSpawn then
            silentSpawnIndex = valueIndex
        end
    end
    local silentSpawnButton = addCycleOption(
        ShootFeature,
        "Silent spawn",
        silentSpawnValues,
        silentSpawnIndex,
        function(value: string): ()
            mm2Settings.silentSpawn = value
        end,
        "Where the silent bullet is authored: Front = in front of the torso "
            .. "at torso height; Through = pierces the torso; Top = the old "
            .. "geometry (1.6 studs above); Behind = far side. Check Spawn A/B "
            .. "status to see which variant actually scores."
    )
    if silentSpawnButton then
        silentSpawnRow = silentSpawnButton.Parent :: GuiObject
    end
    local function spawnStatsText(): string
        local stats: any = state.mm2ShotFeedback and
            state.mm2ShotFeedback.spawnStats or {}
        local parts: {string} = {}
        for _, variant: string in ipairs({"Front", "Through", "Top", "Behind"}) do
            local s: any = stats[variant]
            if s and s.shots > 0 then
                table.insert(
                    parts,
                    string.format(
                        "%s %d/%d",
                        variant,
                        s.hits,
                        s.shots
                    )
                )
            end
        end
        if #parts == 0 then
            return "Spawn A/B: no silent shots counted yet."
        end
        return "Spawn A/B (hits/shots): " .. table.concat(parts, " · ")
    end
    local spawnStatsButton = addActionOption(ShootFeature, "Spawn A/B status", function(): ()
        notify(spawnStatsText())
    end)
    if spawnStatsButton then
        spawnStatsRow = spawnStatsButton.Parent :: GuiObject
    end
    addToggleOption(
        ShootFeature,
        "Auto tune lead",
        mm2Settings.autoTuneLead,
        function(value: boolean): ()
            mm2Settings.autoTuneLead = value
        end,
        "Opt-in calibration from confirmed hits. It learns a separate runtime "
            .. "correction and never rewrites the manual Lead bias slider."
    )
    addNumberOption(
        ShootFeature,
        "Lead bias",
        mm2Settings.gunLeadBias,
        -0.15,
        0.15,
        function(value: number): ()
            mm2Settings.gunLeadBias = math.clamp(value, -0.15, 0.15)
        end,
        "Manual correction in seconds on top of the bounded RTT-based "
            .. "lead estimate. Network delay and sudden direction changes "
            .. "prevent guaranteed hits. Positive aims further ahead, "
            .. "negative aims closer; 0 keeps the automatic model. Capped at "
            .. "+/-0.15s.",
        0.005
    )
    addNumberOption(
        ShootFeature,
        "Motion Hz",
        mm2Settings.motionSampleHz,
        20,
        120,
        function(value: number): ()
            mm2Settings.motionSampleHz = math.clamp(math.round(value), 20, 120)
        end,
        "Selected-target motion samples per second. Default 60; 120 is optional "
            .. "on high-FPS clients, not a network replication boost. Prediction "
            .. "always reads current velocity when firing.",
        5
    )
    addActionOption(ShootFeature, "Lead status", function(): ()
        local status: any = type(getGunLeadStatus) == "function"
            and getGunLeadStatus()
            or nil
        if type(status) ~= "table" then
            notify(string.format(
                "Manual lead bias: %+.3fs | horizon: %.3fs",
                mm2Settings.gunLeadBias,
                getGunHorizonSeconds()
            ))
            return
        end
        notify(string.format(
            "Manual %+.3fs | adaptive %+.3fs (%s; stored %+.3fs) | horizon %.3fs",
            status.manualBias or 0,
            status.autoCorrection or 0,
            status.autoTuneEnabled and "on" or "off",
            status.storedAutoCorrection or 0,
            status.horizon or getGunHorizonSeconds()
        ))
    end)
    addActionOption(ShootFeature, "Reset auto lead correction", function(): ()
        if type(resetAutoLeadCorrection) == "function" then
            resetAutoLeadCorrection()
        end
        notify("Adaptive lead correction reset to zero.")
    end)
    ShootTargetBox = addTextOption(ShootFeature, "Target player", "", function(
        value: string
    ): ()
        mm2Settings.shootTarget = value
    end, false)
    refreshShootOptions()



    -- The visible Auto control is at the top, but arming waits until saved
    -- aim method/target/lead values below have all been restored.
    shootOptionsReady = true
    if updateAutoShootConnection then updateAutoShootConnection() end

    activeCleanup = function(): ()
        toggleShootMurderer(false)
        state.mm2SilentAimFeature = nil
        toggleAutoShoot(false)
        state.mm2ShotFeedback.hide()
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
