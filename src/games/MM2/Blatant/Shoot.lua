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
    local isWeaponPathClear: any = core.isWeaponPathClear

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
        targetPosition: Vector3,
        endpoint: Vector3,
        velocity: Vector3,
        errorRadius: number,
        leadSeconds: number,
        leadSensitivity: number,

        capturedPosition: Vector3,
        aimRootOffset: Vector3,
    }

    type GunAimOptions = {

        ignoreVisibility: boolean?,
    }

    local BODY_HALF_WIDTH: number = 1.0

    local MINIMUM_ERROR_RADIUS: number = 0.35

    -- Server-side gun cooldown, measured from real MM2 remote logs
    -- (TestingStuff 2026-10-15): accepted shots were never closer than
    -- ~3.13 s apart, and every rapid follow-up (< ~3 s) was silently
    -- dropped by the server - no GunFired echo, no damage, nothing. The
    -- client kept "shooting" and the user kept seeing the same miss,
    -- because the correction shots never actually left the building.
    local GUN_SERVER_COOLDOWN: number = 3.1
    local lastGunFireServer: number = -math.huge

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

        local moveDirection: Vector3 = humanoid.MoveDirection
        local horizontalVelocity: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
        if horizontalVelocity.Magnitude < 1.5
            and moveDirection.Magnitude > 0.05 then
            local desired: Vector3 = moveDirection.Unit * humanoid.WalkSpeed
            velocity = Vector3.new(desired.X, velocity.Y, desired.Z)
            horizontalVelocity = Vector3.new(desired.X, 0, desired.Z)
        end

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
        do
            local ok: boolean, stateName: any = pcall(function(): any
                return (humanoid :: Humanoid):GetState()
            end)
            jumpState = ok
                and (stateName == Enum.HumanoidStateType.Jumping
                    or stateName == Enum.HumanoidStateType.Freefall)
        end
        local effectivelyGrounded: boolean =
            (grounded or math.abs(velocity.Y) <= 0.5) and not jumpState
        local verticalDisplacement: number = 0
        if not effectivelyGrounded then
            local verticalVelocity: number = velocity.Y
            local risingJump: boolean = jumpState
                and verticalVelocity < 8
                and verticalVelocity > -8
            if risingJump then
                verticalVelocity = 8
            end
            verticalDisplacement = math.clamp(
                verticalVelocity * lead
                    - 0.5 * workspace.Gravity * lead * lead,
                -3,
                3
            )
        elseif grounded then
            verticalDisplacement = math.clamp(velocity.Y, -2.5, 2.5) * lead
        end
        displacement = Vector3.new(
            displacement.X,
            verticalDisplacement,
            displacement.Z
        )

        local predicted: Vector3 = part.Position + displacement
        local delta: Vector3 = predicted - origin.Position
        if delta.Magnitude <= 0.05 then
            return nil, nil, "too close"
        end

        if not ignoreVisibility and mm2Settings.shootWallCheck then
            if not isWeaponPathClear(origin.Position, predicted, character) then
                -- Partial visibility: when the target hugs a wall and only a
                -- sliver sticks out (a hand with the knife, an arm, a corner
                -- of the torso), aim the shot at that visible part instead of
                -- rejecting it. The whole character shares the same lead
                -- displacement, so each candidate is simply its part position
                -- moved by the same prediction.
                local rescued: boolean = false
                -- The rewind window accepts the RAW observed position, and
                -- during a peek the raw torso is usually exposed while the
                -- LED point still sits inside the wall. Try the raw position
                -- of the current aim part first (biggest part, no lead).
                do
                    local rawPoint: Vector3 = (part :: BasePart).Position
                    local rawDelta: Vector3 = rawPoint - origin.Position
                    if rawDelta.Magnitude > 0.05
                        and isWeaponPathClear(
                            origin.Position,
                            rawPoint,
                            character
                        ) then
                        predicted = rawPoint
                        delta = rawDelta
                        rescued = true
                    end
                end
                if not rescued then
                    local rootCFrame: CFrame = (root :: BasePart).CFrame
                    -- Probe points across the torso box before falling back
                    -- to limbs: a corner that hides the CENTRE of the torso
                    -- usually still leaves half of the box exposed, and that
                    -- sliver is a far better shot than a leg ("detectando la
                    -- pierna cuando no era necesario"). The ray origin is the
                    -- gun, not the eye, so what looks fully exposed on screen
                    -- can be centre-blocked from the muzzle.
                    local probeOffsets: {Vector3} = {
                        rootCFrame.RightVector * 0.55,
                        rootCFrame.RightVector * -0.55,
                        rootCFrame.UpVector * 0.35,
                        rootCFrame.RightVector * 0.35 + rootCFrame.UpVector * 0.25,
                        rootCFrame.RightVector * -0.35 + rootCFrame.UpVector * 0.25,
                    }
                    for _, partName: string in ipairs(VISIBILITY_PARTS) do
                        local candidate: Instance? =
                            (character :: Model):FindFirstChild(partName)
                        if candidate
                            and candidate:IsA("BasePart") then
                            local candidatePart: BasePart =
                                candidate :: BasePart
                            local variants: {Vector3} = {
                                candidatePart.Position + displacement,
                                candidatePart.Position,
                            }
                            if table.find(AIM_PARTS, partName) ~= nil then
                                for _, offset: Vector3 in ipairs(probeOffsets) do
                                    table.insert(
                                        variants,
                                        candidatePart.Position + offset + displacement
                                    )
                                    table.insert(
                                        variants,
                                        candidatePart.Position + offset
                                    )
                                end
                            end
                            for _, basePoint: Vector3 in ipairs(variants) do
                                local candidatePoint: Vector3 = basePoint
                                local candidateDelta: Vector3 =
                                    candidatePoint - origin.Position
                                if candidateDelta.Magnitude > 0.05
                                    and isWeaponPathClear(
                                        origin.Position,
                                        candidatePoint,
                                        character
                                    ) then
                                    predicted = candidatePoint
                                    delta = candidateDelta
                                    rescued = true
                                    break
                                end
                            end
                            if rescued then
                                break
                            end
                        end
                    end
                end
                if not rescued then
                    return nil, nil, "obstructed"
                end
            end
        end

        local turnError: number = displacement.Magnitude
            * math.sin(math.min(horizon * turnRate * 0.5, math.pi * 0.5))
        local jitter: number = math.min(acceleration.Magnitude / 240, 0.45)
        local errorRadius: number = math.max(
            MINIMUM_ERROR_RADIUS,
            turnError + jitter
        )
        local allowedErrorBudget: number = ignoreVisibility and (BODY_HALF_WIDTH * 1.75) or BODY_HALF_WIDTH
        if errorRadius > allowedErrorBudget then
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
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
        local backpack: Backpack? = LocalPlayer:FindFirstChildOfClass("Backpack")
        if not gun and backpack then
            return reject("You do not have the sheriff gun.")
        end
        if gun and gun.Parent == backpack and humanoid:IsA("Humanoid") then
            humanoid:EquipTool(gun)
            if quiet then

                return reject("Equipping the sheriff gun.")
            end
            task.wait()
        end

        gun = getPlayerWeapon(LocalPlayer, "Gun", true) or gun
        local remote: Instance? = gun and gun:FindFirstChild("Shoot")
        local origin: CFrame? = getGunOriginCFrame(character, gun)

        local aim: CFrame?, prediction: GunPrediction?, reason: string? = nil
        if origin then
            aim, prediction, reason = computeGunAim(
                target,
                origin :: CFrame,
                silent and {ignoreVisibility = true} or nil
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

        -- One packet per server cooldown window, for BOTH modes: the real
        -- logs show the server silently drops any shot fired less than
        -- ~3.1 s after the previous one (no echo, no damage), so a rapid
        -- re-fire never tests a correction - it just looks like the same
        -- miss again.
        if os.clock() - lastGunFireServer < GUN_SERVER_COOLDOWN then
            return reject("Gun is cooling down - the server drops rapid shots.")
        end

        if silent then

            local variant: string = mm2Settings.silentSpawn
            local shotOrigin: CFrame?, shotEnd: CFrame?, offset: number =
                buildSilentShot(target, resolved, origin, variant)
            if not shotOrigin or not shotEnd then
                return reject("Another player blocks the silent shot.")
            end
            state.mm2ShotFeedback.queue(target, gun, shotOrigin, aim, resolved)
            if state.mm2ShotFeedback.pending then
                state.mm2ShotFeedback.pending.silentSpawn = variant
            end

            state.lastSilentShotInfo = {
                variant = variant,
                at = os.clock(),
                offset = math.floor(offset * 10) / 10,
            }
            lastGunFireServer = os.clock()
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
                    sweep = mm2Settings.silentSweep, motionHz = mm2Settings.motionSampleHz},
            })
            macroUnequip(gun)
            return true
        end

        state.mm2ShotFeedback.queue(target, gun, origin, aim, resolved)
        -- The endpoint must be the PREDICTED TARGET POINT itself. Real MM2
        -- logs (2026-10-15) show the server validates it against the
        -- target's rewound position: v27 extended it 4 studs past the
        -- target to "pierce" the hitbox segment, and every single extended
        -- shot was rejected outright (0 GunFired echoes in a 5-shot
        -- session) - the shot died mid-air exactly like the bug it tried
        -- to fix. The server's own acceptance window (~277 ms rewind) is
        -- what forgives a slightly short lead.
        lastGunFireServer = os.clock()
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
                motionHz = mm2Settings.motionSampleHz, leadBias = mm2Settings.gunLeadBias},
        })
        macroUnequip(gun)
        return true
    end

    local shootFeatureActive: boolean = false
    local autoShootActive: boolean = false

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

    local function triggerManualShot(): ()
        if not shootFeatureActive then
            notify("Enable Shoot first.")
            return
        end
        fireGunAtTarget(getSelectedShootTarget())
    end

    local function toggleShootMurderer(enabled: boolean): ()
        shootFeatureActive = enabled
        refreshShootInfrastructure()
    end

    local autoSettings = {
        mode = "Normal" :: string,
        maxError = 0.6,
        fireDelay = 0.5,
    }
    local lastAutoShot: number = -math.huge
    local lastGunCheck: number = -math.huge
    local lastAutoReject: {message: string, at: number}? = nil

    local function equipSheriffGun(): ()
        local backpack: Backpack? = LocalPlayer:FindFirstChildOfClass("Backpack")
        if not backpack then
            return
        end
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
        if gun and gun.Parent == backpack then
            local humanoid: Humanoid? = LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                :: Humanoid?
            if humanoid then
                humanoid:EquipTool(gun)
            end
        end
    end

    local function autoShootTick(): ()
        if os.clock() - lastGunCheck >= 0.5 then
            lastGunCheck = os.clock()
            equipSheriffGun()
        end

        if os.clock() - lastAutoShot < autoSettings.fireDelay then
            return
        end
        local target: Player? = getSelectedShootTarget()
        if not target then
            return
        end
        lastRejectReason = ""
        local fired: boolean = fireGunAtTarget(target, {
            silent = autoSettings.mode == "Silent",
            maxError = autoSettings.maxError,
            quiet = true,
        })
        if fired then
            lastAutoShot = os.clock()
            lastAutoReject = nil
        elseif lastRejectReason ~= "" then

            if lastAutoReject == nil or lastAutoReject.message ~= lastRejectReason then
                lastAutoReject = {message = lastRejectReason, at = os.clock()}
                notify("Auto Shoot waiting: " .. lastRejectReason)
            end
        end
    end

    local function toggleAutoShoot(enabled: boolean): ()
        autoShootActive = enabled
        disconnectFeatureConnection("MM2AutoShoot")
        refreshShootInfrastructure()
        if not enabled then
            return
        end
        lastAutoShot = -math.huge
        local autoElapsed: number = 0
        featureConnections.MM2AutoShoot = TaskManager:Connect(function(
            deltaTime: number
        ): ()
            local due: boolean
            due, autoElapsed = predictionMath.sampleDue(autoElapsed, deltaTime, 60)
            if due then autoShootTick() end
        end)
    end

    local ShootFeature = createUniversalFeature(
        "Shoot",
        "Hitscan aim with filtered motion, RTT compensation, and miss feedback",
        4,
        toggleShootMurderer,
        {
            categoryName = "Blatant",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    local ShootTargetBox
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
        "Mode",
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
    addToggleOption(
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
        "Manual correction in seconds on top of the automatic half-ping "
            .. "lead (our view of the target trails the server by ~RTT/2, so "
            .. "the aim leads by exactly that). Positive aims further ahead, "
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

    local AutoShootFeature = createUniversalFeature(
        "Auto Shoot",
        "Fires by itself when a high-probability shot exists. Normal holds for line"
            .. " of sight and answers peeks; Silent shoots the murderer from any"
            .. " distance, through walls.",
        5,
        toggleAutoShoot,
        {
            categoryName = "Blatant",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addCycleOption(
        AutoShootFeature,
        "Mode",
        {"Normal", "Silent"},
        1,
        function(value: string): ()
            autoSettings.mode = value
        end
    )
    addNumberOption(
        AutoShootFeature,
        "Max error",
        autoSettings.maxError,
        0.35,
        1,
        function(value: number): ()
            autoSettings.maxError = value
        end,
        "Only fire when predicted error is within this many studs. Applies "
            .. "to both Normal and Silent; extra sweep never overrides this "
            .. "gate. The solver never reports below 0.35, so the slider "
            .. "starts there.",
        0.05
    )
    addNumberOption(
        AutoShootFeature,
        "Fire delay",
        autoSettings.fireDelay,
        0.1,
        2,
        function(value: number): ()
            autoSettings.fireDelay = value
        end,
        "Seconds between automatic shots.",
        0.05
    )

    activeCleanup = function(): ()
        toggleShootMurderer(false)
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
