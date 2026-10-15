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
    local getLandingRootY: any = core.getLandingRootY
    local setWeaponStatus: any = core.setWeaponStatus

    local legacyGeneration = 0
    local activeLegacyGroupId: string? = nil
    local legacyBox: BasePart? = nil
    local legacyCharacter: Model? = nil
    local function clearLegacyHitbox(): ()
        if legacyBox then pcall(function(): () legacyBox:Destroy() end) end
        legacyBox, legacyCharacter = nil, nil
    end
    local function syncLegacyHitbox(target: Player?): ()
        local character = target and target.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if mm2Settings.predictionProfile ~= "Old" or not mm2Settings.oldHitbox or not root then
            clearLegacyHitbox(); return
        end
        if legacyCharacter ~= character or not legacyBox or legacyBox.Parent ~= character then
            clearLegacyHitbox()
            local box = Instance.new("Part")
            box.Name = "WurstHitbox"
            box.Transparency = 1
            box.Anchored = true
            box.Massless = true
            box.CanCollide, box.CanTouch, box.CanQuery = false, true, true
            box.CFrame = root.CFrame
            box.Parent = character
            legacyBox, legacyCharacter = box, character
        end
        local size = math.clamp(mm2Settings.oldHitboxSize or 8, 1, 40)
        local dimensions = Vector3.new(size, size * 1.2, size)
        if legacyBox.Size ~= dimensions then legacyBox.Size = dimensions end
        if legacyBox.CFrame ~= root.CFrame then legacyBox.CFrame = root.CFrame end
    end

    local diagnostics = {checks = 0, sentNormal = 0, sentSilent = 0, burstGroups = 0, rejected = {}}
    state.mm2ShootDiagnostics = diagnostics
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
        snapshot: any,
    }

    type GunAimOptions = {

        ignoreVisibility: boolean?,
        profile: string?,
        horizon: number?,
        leadBias: number?,
        burstCount: number?,
    }

    local BODY_HALF_WIDTH: number = 1.0

    local MINIMUM_ERROR_RADIUS: number = 0.35

    local AIM_PARTS: {string} = {
        "UpperTorso",
        "Torso",
        "HumanoidRootPart",
        "Head",
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
            sample and sample.character == character and sample.stability or nil,
            sample and sample.sampleInterval or nil
        )

        local profile = resolvedOptions.profile or (ignoreVisibility and "Actual")
            or mm2Settings.predictionProfile or "Actual"
        local motionModel = mm2Settings.gunMotionModel or "V17"
        if profile == "Old" then motionModel = "Classic 66d"
        elseif profile == "Experimental" then motionModel = "Intent blend" end
        if motionModel == "Classic 66d" then
            -- Restore the v10 per-sample response, not its historical latency mean.
            -- Only the separate Old profile can add legacy Hitbox/Burst.
            local similarity = sample and (sample.classicStability or sample.stability)
            turnRate = type(similarity) == "number"
                and math.clamp((1 - math.clamp(similarity, 0, 1)) * 6, 0, math.pi * 1.5)
                or math.pi * 0.5
        end
        local measuredVelocity = velocity
        local moveDirection: Vector3 = humanoid.MoveDirection
        local horizontalVelocity: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
        if motionModel ~= "Intent blend" and horizontalVelocity.Magnitude < 1.5
            and moveDirection.Magnitude > 0.05 then
            local desired: Vector3 = moveDirection.Unit * humanoid.WalkSpeed
            velocity = Vector3.new(desired.X, velocity.Y, desired.Z)
            horizontalVelocity = Vector3.new(desired.X, 0, desired.Z)
        end

        if motionModel == "Intent blend" then
            velocity = predictionMath.blendIntent(velocity, moveDirection)
        end
        local horizon: number = resolvedOptions.horizon or getGunHorizonSeconds()
        if profile == "Old" then horizon = math.clamp(horizon + (resolvedOptions.leadBias or 0), 0.03, 0.6) end
        local discount: number = getGunTurnDiscount(horizon, turnRate)
        if motionModel == "Intent blend" then discount = 1 end
        local lead: number = horizon * discount
        local leadSensitivity: number = type(getGunLeadSensitivity) == "function"
            and getGunLeadSensitivity(horizon, turnRate)
            or discount
        if motionModel == "Intent blend" then leadSensitivity = 1 end

        local horizontalAcceleration: Vector3 = Vector3.new(
            acceleration.X,
            0,
            acceleration.Z
        )
        if motionModel == "Intent blend" then horizontalAcceleration = Vector3.zero end
        local displacement: Vector3 = Vector3.new(
            velocity.X * lead,
            0,
            velocity.Z * lead
        ) + horizontalAcceleration * (0.25 * lead * lead)

        if grounded then

            displacement = Vector3.new(
                displacement.X,
                math.clamp(velocity.Y, -2.5, 2.5) * lead,
                displacement.Z
            )
        else
            displacement = Vector3.new(
                displacement.X,
                velocity.Y * lead - 0.5 * workspace.Gravity * lead * lead,
                displacement.Z
            )
        end

        local predicted: Vector3 = part.Position + displacement
        local landingRootY: number? = nil
        if mm2Settings.gunLandingGuard and not grounded and displacement.Y < 0 then
            landingRootY = getLandingRootY(root, humanoid, displacement)
            if landingRootY then
                predicted = Vector3.new(predicted.X,
                    math.max(predicted.Y, landingRootY + part.Position.Y - root.Position.Y), predicted.Z)
                displacement = predicted - part.Position
            end
        end
        local delta: Vector3 = predicted - origin.Position
        if delta.Magnitude <= 0.05 then
            return nil, nil, "too close"
        end

        if not ignoreVisibility and mm2Settings.shootWallCheck
            and not isWeaponPathClear(origin.Position, predicted, character) then
            return nil, nil, "obstructed"
        end

        local turnError: number = displacement.Magnitude
            * math.sin(math.min(horizon * turnRate * 0.5, math.pi * 0.5))
        local jitter: number = math.min(acceleration.Magnitude / 240, 0.45)
        local errorRadius: number = math.max(
            MINIMUM_ERROR_RADIUS,
            turnError + jitter
        )
        local bodyHalfWidth = BODY_HALF_WIDTH
        if profile == "Old" and mm2Settings.oldHitbox then
            bodyHalfWidth = math.max(BODY_HALF_WIDTH, math.clamp(mm2Settings.oldHitboxSize or 8, 1, 40) * 0.5)
        end
        local allowedErrorBudget: number = ignoreVisibility and (bodyHalfWidth * 1.75) or bodyHalfWidth
        if (profile == "Old" or mm2Settings.manualErrorGate) and errorRadius > allowedErrorBudget then
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
            snapshot = {
                profile = profile, epoch = mm2Settings.predictionEpoch or 0,
                burstCount = resolvedOptions.burstCount or 1,
                allowedErrorBudget = allowedErrorBudget,
                model = motionModel, timingModel = mm2Settings.gunTimingModel, horizon = horizon, lead = lead, turnRate = turnRate,
                grounded = grounded, errorRadius = errorRadius,
                landingGuard = mm2Settings.gunLandingGuard, landingRootY = landingRootY,
                root = {root.Position.X, root.Position.Y, root.Position.Z},
                part = {part.Position.X, part.Position.Y, part.Position.Z},
                measuredVelocity = {measuredVelocity.X, measuredVelocity.Y, measuredVelocity.Z},
                usedVelocity = {velocity.X, velocity.Y, velocity.Z},
                acceleration = {acceleration.X, acceleration.Y, acceleration.Z},
                moveDirection = {moveDirection.X, moveDirection.Y, moveDirection.Z},
                autoLeadCorrection = type(getGunLeadStatus) == "function" and getGunLeadStatus().autoCorrection or 0,
                sampleAge = sample and os.clock() - sample.sampledAt or nil,
                sampleInterval = sample and sample.sampleInterval or nil,
            },
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
        profile: string?,
        horizon: number?,
        leadBias: number?,
        generation: number?,
        burst: any,
        suppressMacro: boolean?,
        silent: boolean?,
        maxError: number?,
        quiet: boolean?,
    }

    local lastRejectReason: string = ""

    local function fireGunAtTarget(
        target: Player?,
        options: FireOptions?
    ): boolean
        lastRejectReason = ""
        local opts: FireOptions = options or {}
        diagnostics.checks += 1
        local silent: boolean = mm2Settings.silentAim
        if opts.silent ~= nil then
            silent = opts.silent
        end
        local quiet: boolean = opts.quiet == true
        local function reject(message: string): boolean
            lastRejectReason = message
            local diagnosticReason = string.find(message, "Send error:", 1, true) and "Send error" or message
            diagnostics.rejected[diagnosticReason] = (diagnostics.rejected[diagnosticReason] or 0) + 1
            setWeaponStatus("Shoot", message)
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

        if (opts.generation ~= nil and opts.generation ~= legacyGeneration)
            or (opts.burst and opts.burst.groupId ~= activeLegacyGroupId)
            or (opts.burst and opts.burst.epoch ~= nil and opts.burst.epoch ~= (mm2Settings.predictionEpoch or 0)) then
            return reject("Shot cancelled: controls changed.")
        end
        gun = getPlayerWeapon(LocalPlayer, "Gun", true) or gun
        if gun and (gun:GetAttribute("Disabled") == true or gun.Enabled == false) then
            return reject("Gun disabled/cooling down.")
        end
        local remote: Instance? = gun and gun:FindFirstChild("Shoot")
        local origin: CFrame? = getGunOriginCFrame(character, gun)

        local aim: CFrame?, prediction: GunPrediction?, reason: string? = nil
        if origin then
            aim, prediction, reason = computeGunAim(
                target,
                origin :: CFrame,
                {ignoreVisibility = silent, profile = silent and "Actual" or opts.profile,
                    horizon = opts.horizon, leadBias = opts.leadBias, burstCount = opts.burst and opts.burst.count or 1}
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

        if silent then

            local variant: string = mm2Settings.silentSpawn
            local shotOrigin: CFrame?, shotEnd: CFrame?, offset: number =
                buildSilentShot(target, resolved, origin, variant)
            if not shotOrigin or not shotEnd then
                return reject("Another player blocks the silent shot.")
            end

            state.lastSilentShotInfo = {
                variant = variant,
                at = os.clock(),
                offset = math.floor(offset * 10) / 10,
            }
            local sentAt: number = os.clock()
            local sent, failure = pcall(function(): () remote:FireServer(shotOrigin, shotEnd) end)
            if not sent then return reject("Send error: " .. tostring(failure)) end
            diagnostics.sentSilent += 1
            setWeaponStatus("Shoot", "Silent sent to " .. target.Name .. "; not a confirmed hit")
            state.mm2ShotFeedback.queue(target, gun, shotOrigin, shotEnd, resolved, variant)

            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "gun",
                sentAt = sentAt,
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
                    prediction = resolved.snapshot, manualErrorGate = mm2Settings.manualErrorGate,
                    leadBias = mm2Settings.gunLeadBias, horizon = getGunHorizonSeconds(),
                    adaptiveTiming = mm2Settings.adaptiveGunTiming, autoTune = mm2Settings.autoTuneLead},
            })
            macroUnequip(gun)
            return true
        end

        if resolved.snapshot and resolved.snapshot.profile == "Old" then pcall(syncLegacyHitbox, target) end
        local sentAt: number = os.clock()
        local sent, failure = pcall(function(): ()
            remote:FireServer(CFrame.lookAt(origin.Position, resolved.endpoint), CFrame.new(resolved.endpoint))
        end)
        if not sent then return reject("Send error: " .. tostring(failure)) end
        diagnostics.sentNormal += 1
        setWeaponStatus("Shoot", "Normal sent to " .. target.Name .. "; not a confirmed hit")
        state.mm2ShotFeedback.queue(target, gun, origin, aim, resolved)
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "gun",
            sentAt = sentAt,
            tool = gun,
            toolName = gun and gun.Name or "Gun",
            originPos = origin.Position,
            aimPos = resolved.endpoint,
            target = target,
            silent = false,
            settings = {mode = "Normal", wallCheck = mm2Settings.shootWallCheck,
                burst = opts.burst,
                legacyHitbox = resolved.snapshot and resolved.snapshot.profile == "Old" and mm2Settings.oldHitbox or false,
                legacyHitboxSize = resolved.snapshot and resolved.snapshot.profile == "Old" and mm2Settings.oldHitboxSize or nil,
                motionHz = mm2Settings.motionSampleHz, leadBias = mm2Settings.gunLeadBias,
                prediction = resolved.snapshot, manualErrorGate = mm2Settings.manualErrorGate,
                horizon = resolved.snapshot and resolved.snapshot.horizon or getGunHorizonSeconds(),
                adaptiveTiming = mm2Settings.adaptiveGunTiming,
                autoTune = mm2Settings.autoTuneLead},
        })
        if not opts.suppressMacro then macroUnequip(gun) end
        return true
    end

    local lastLegacyGroup = -math.huge
    local legacyGroupSerial = 0
    local function fireGunBurst(target: Player?, options: FireOptions?): boolean
        local opts = options or {}
        local silent = opts.silent
        if silent == nil then silent = mm2Settings.silentAim end
        if silent or mm2Settings.predictionProfile ~= "Old" then return fireGunAtTarget(target, opts) end
        -- One bounded group per 0.5 s, shared by manual and Auto. No catch-up loop.
        if os.clock() - lastLegacyGroup < 0.5 then return false end
        lastLegacyGroup = os.clock()
        local count = math.clamp(math.floor(mm2Settings.oldBurst or 1), 1, 4)
        local baseHorizon = getGunHorizonSeconds()
        local step = baseHorizon * 0.5
        local biases = {0, step, -step, 2 * step}
        legacyGroupSerial += 1
        diagnostics.burstGroups += 1
        local groupId = string.format("old:%.6f:%d", os.clock(), legacyGroupSerial)
        activeLegacyGroupId = groupId
        local generation = legacyGeneration
        local epoch = mm2Settings.predictionEpoch or 0
        local sent = 0
        local usedHorizons = {}
        for index = 1, count do
            if legacyGeneration ~= generation or activeLegacyGroupId ~= groupId
                or (mm2Settings.predictionEpoch or 0) ~= epoch then break end
            local key = string.format("%.6f", math.clamp(baseHorizon + biases[index], 0.03, 0.6))
            if usedHorizons[key] then continue end
            usedHorizons[key] = true
            local fired = fireGunAtTarget(target, {
                silent = false, profile = "Old", horizon = baseHorizon, leadBias = biases[index],
                maxError = opts.maxError, quiet = opts.quiet or index > 1,
                generation = generation, suppressMacro = true,
                burst = {groupId = groupId, index = index, count = count, bias = biases[index], epoch = epoch},
            })
            if fired then sent += 1 end
            if string.find(lastRejectReason, "Send error:", 1, true) then break end
        end
        if sent > 0 then
            macroUnequip(getPlayerWeapon(LocalPlayer, "Gun", true))
            setWeaponStatus("Shoot", string.format("Old: %d/%d requests sent; not confirmed impacts", sent, count))
        end
        return sent > 0
    end

    local autoSettings = {
        mode = "Normal" :: string,
        maxError = 0.6,
        fireDelay = 0.5,
    }

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
                local lastHitboxUpdate = -math.huge
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
                    if os.clock() - lastHitboxUpdate >= 0.1 then
                        lastHitboxUpdate = os.clock()
                        local wantsBox = mm2Settings.predictionProfile == "Old" and mm2Settings.oldHitbox
                            and ((shootFeatureActive and not mm2Settings.silentAim)
                                or (autoShootActive and autoSettings.mode == "Normal"))
                        local equipped = wantsBox and getPlayerWeapon(LocalPlayer, "Gun", true)
                        pcall(syncLegacyHitbox, equipped and player or nil)
                    end
                end)
            end
            return
        end
        legacyGeneration += 1
        clearLegacyHitbox()
        disconnectFeatureConnection("MM2MotionTracker")
        disconnectGunFiredObserver()
        state.mm2ShotFeedback.pending = nil
        table.clear(state.mm2ShotFeedback.pendingShots)
        state.mm2ShotFeedback.lastAccepted = nil
        state.mm2ShotFeedback.hide()
    end

    local function triggerManualShot(): ()
        if not shootFeatureActive then
            notify("Enable Shoot first.")
            return
        end
        fireGunBurst(getSelectedShootTarget())
    end

    local function toggleShootMurderer(enabled: boolean): ()
        legacyGeneration += 1
        shootFeatureActive = enabled
        refreshShootInfrastructure()
    end

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
            setWeaponStatus("Shoot", "No valid selected target (role/custom/protection)")
            return
        end
        lastRejectReason = ""
        local fired: boolean = fireGunBurst(target, {
            silent = autoSettings.mode == "Silent",
            maxError = autoSettings.maxError,
            quiet = true,
        })
        if fired or string.find(lastRejectReason, "Send error:", 1, true) then
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
        legacyGeneration += 1
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
    local predictionRows = {
        Option_Predictionprofile=true, Option_WallCheck=true, Option_Motionmodel=true, Option_Guntiming=true,
        Option_Landingguard=true, Option_Holduncertainmanualshots=true,
        Option_Autotunelead=true, Option_Leadbias=true, Option_MotionHz=true,
        Option_Leadstatus=true, Option_Resetautoleadcorrection=true,
    }
    local silentRows = {Option_Silentsweep=true, Option_Silentspawn=true, Option_SpawnABstatus=true}
    local function refreshShootOptions(): ()
        for _, row in ipairs(ShootFeature.optionRows) do
            local visible = true
            if predictionRows[row.Name] then visible = not mm2Settings.silentAim end
            if silentRows[row.Name] then visible = mm2Settings.silentAim end
            if row.Name == "Option_Motionmodel" then
                visible = not mm2Settings.silentAim and (mm2Settings.predictionProfile or "Actual") == "Actual"
            end
            if row.Name == "Option_Holduncertainmanualshots" then
                visible = not mm2Settings.silentAim and mm2Settings.predictionProfile ~= "Old"
            end
            if row.Name == "Option_Hitbox" or row.Name == "Option_Burst" or row.Name == "Option_Oldstatus" then
                visible = not mm2Settings.silentAim and mm2Settings.predictionProfile == "Old"
            end
            if row.Name == "Option_Hitboxsize" then
                visible = not mm2Settings.silentAim and mm2Settings.predictionProfile == "Old" and mm2Settings.oldHitbox == true
            end
            if row.Name == "Option_Targetplayer" then visible = mm2Settings.shootMode == "Custom" end
            row.Visible = visible
        end
        ShootFeature.updateExpandedSize()
    end
    addCycleOption(ShootFeature, "Mode", {"Prediction", "Silent AIM"}, 1, function(value: string): ()
        legacyGeneration += 1
        clearLegacyHitbox()
        mm2Settings.silentAim = value == "Silent AIM"
        refreshShootOptions()
    end, "Prediction fires from your gun. Silent AIM configures the target-side ray; it retains the shared prediction settings.")
    addCycleOption(ShootFeature, "Target", {"Murder", "Custom"}, 1, function(value: string): ()
        legacyGeneration += 1
        clearLegacyHitbox()
        mm2Settings.shootMode = value
        refreshShootOptions()
    end)
    addTextOption(ShootFeature, "Target player", "", function(value: string): ()
        legacyGeneration += 1
        clearLegacyHitbox()
        mm2Settings.shootTarget = value
    end, false)

    addCycleOption(ShootFeature, "Prediction profile", {"Old", "Actual", "Experimental"}, 2,
        function(value: string): ()
            if mm2Settings.predictionProfile ~= value then core.resetAutoLeadCorrection() end
            legacyGeneration += 1
            clearLegacyHitbox()
            mm2Settings.predictionProfile = value
            refreshShootOptions()
        end,
        "Old: corrected 66d with local Hitbox and bounded Burst. Actual: your v19 solver settings. Experimental: intent blend with existing vertical/landing physics; not a proven winner. Silent and Knife stay separate.")
    addToggleOption(ShootFeature, "Hitbox", mm2Settings.oldHitbox == true, function(value: boolean): ()
        legacyGeneration += 1
        mm2Settings.oldHitbox = value
        if not value then clearLegacyHitbox() end
        refreshShootOptions()
    end, "Old only: local volume and a wider solver error allowance. Does NOT enlarge the server hitbox. Auto Max error still applies. Local query/touch volume is not a server hitbox; synthetic contacts are excluded from target-hit labels.")
    addNumberOption(ShootFeature, "Hitbox size", mm2Settings.oldHitboxSize or 8, 1, 40, function(value: number): ()
        legacyGeneration += 1
        mm2Settings.oldHitboxSize = math.clamp(value, 1, 40)
    end, "Local volume width in studs; Old allows up to half this width as predicted error. Not a server collision size.", 1)
    addNumberOption(ShootFeature, "Burst", mm2Settings.oldBurst or 1, 1, 4, function(value: number): ()
        legacyGeneration += 1
        mm2Settings.oldBurst = math.clamp(math.floor(value), 1, 4)
    end, "Old only: 1-4 requests at legacy lead offsets, base prediction first. At most one group per 0.5 seconds; server cooldown still applies. Multi-request groups do not train timing or auto lead.", 1)
    addActionOption(ShootFeature, "Old status", function(): ()
        local text = string.format("Old 66d | local Hitbox %s / %.1f studs | Burst %d | groups %d | not a server acceptance count",
            tostring(mm2Settings.oldHitbox), mm2Settings.oldHitboxSize or 8, mm2Settings.oldBurst or 1, diagnostics.burstGroups)
        print("[Wurst:MM2:Old] " .. text); notify(text)
    end)

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
            legacyGeneration += 1
            mm2Settings.shootWallCheck = value
        end,
        "Holds fire while a wall blocks the muzzle. SilentAIM skips it: it "
            .. "authors the shot at the target."
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
    addNumberOption(
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
    addCycleOption(
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
                        "%s: %d hit-part / %d signals / %d attempts / %d unknown",
                        variant, s.hits, s.confirmed, s.shots, s.unconfirmed
                    )
                )
            end
        end
        if #parts == 0 then
            return "Spawn A/B: no silent shots counted yet."
        end
        return "Spawn A/B (observations, not kill rate): " .. table.concat(parts, " · ")
    end
    addActionOption(ShootFeature, "Spawn A/B status", function(): ()
        notify(spawnStatsText())
    end)
    addCycleOption(ShootFeature, "Motion model", {"Classic 66d", "V17", "Intent blend"}, 1,
        function(value: string): ()
            if mm2Settings.gunMotionModel ~= value then core.resetAutoLeadCorrection() end
            legacyGeneration += 1
            mm2Settings.gunMotionModel = value
        end,
        "Classic restores v10 motion response with safe timing. V17 keeps time-normalized turn damping. Intent blend is experimental; offline average error improved, tail errors did not uniformly improve.")
    addCycleOption(ShootFeature, "Gun timing", {"RTT", "V17 floor"}, 1, function(value: string): ()
        if mm2Settings.gunTimingModel ~= value then core.resetAutoLeadCorrection() end
        legacyGeneration += 1
        mm2Settings.gunTimingModel = value
    end, "RTT removes the unverified 200ms floor; both modes retain 33.3ms of legacy age/frame margin. V17 floor is the previous baseline. Neither is an impact timestamp measurement.")
    addToggleOption(ShootFeature, "Landing guard", true, function(value: boolean): ()
        if mm2Settings.gunLandingGuard ~= value then core.resetAutoLeadCorrection() end
        legacyGeneration += 1
        mm2Settings.gunLandingGuard = value
    end, "One bounded downward map ray prevents descending ballistic aim below a detected floor. No hitbox edits. Does not predict future jump input or guarantee terrain contact.")
    addToggleOption(ShootFeature, "Hold uncertain manual shots", false, function(value: boolean): ()
        legacyGeneration += 1
        mm2Settings.manualErrorGate = value
    end, "OFF sends the best available manual solution, without a fake enlarged hitbox. Auto Shoot still obeys its own Max error. No accuracy percentage is implied.")
    addActionOption(ShootFeature, "Shoot diagnostics", function(): ()
        local parts = {string.format("%d solver checks | %d Normal sent | %d Silent sent",
            diagnostics.checks, diagnostics.sentNormal, diagnostics.sentSilent)}
        for reason, count in pairs(diagnostics.rejected) do
            table.insert(parts, tostring(count) .. " checks rejected: " .. reason)
        end
        local text = table.concat(parts, "\n")
        print("[Wurst:MM2] " .. text); notify(text)
    end)
    addToggleOption(
        ShootFeature,
        "Auto tune lead",
        mm2Settings.autoTuneLead,
        function(value: boolean): ()
            legacyGeneration += 1
            if mm2Settings.autoTuneLead ~= value then
                mm2Settings.predictionEpoch = (mm2Settings.predictionEpoch or 0) + 1
            end
            mm2Settings.autoTuneLead = value
        end,
        "Opt-in calibration from confirmed hits. It learns a separate runtime "
            .. "correction and never rewrites the manual Lead bias slider."
    )
    addNumberOption(
        ShootFeature,
        "Lead bias",
        mm2Settings.gunLeadBias,
        -0.1,
        0.1,
        function(value: number): ()
            if mm2Settings.gunLeadBias ~= math.clamp(value, -0.1, 0.1) then core.resetAutoLeadCorrection() end
            legacyGeneration += 1
            mm2Settings.gunLeadBias = math.clamp(value, -0.1, 0.1)
        end,
        "Manual time correction in seconds (positive = lead further ahead). "
            .. "It is added to the prediction horizon, bounded to +/-0.1s, and "
            .. "does not change character physics.",
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
    refreshShootOptions()

    local AutoShootFeature = createUniversalFeature(
        "Auto Shoot",
        "Automatic requests with a prediction-error gate. Uses Shoot Target; its Mode is independent of Shoot Mode; server acceptance is not guaranteed.",
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
        {"Prediction", "Silent AIM"},
        1,
        function(value: string): ()
            legacyGeneration += 1
            clearLegacyHitbox()
            autoSettings.mode = value == "Silent AIM" and "Silent" or "Normal"
        end
    )
    addNumberOption(
        AutoShootFeature,
        "Max error",
        autoSettings.maxError,
        MINIMUM_ERROR_RADIUS,
        1,
        function(value: number): ()
            autoSettings.maxError = math.clamp(value, MINIMUM_ERROR_RADIUS, 1)
        end,
        "Only fire when predicted error is within this many studs. Applies "
            .. "to both Normal and Silent; extra sweep never overrides this gate.",
        0.05
    )
    addNumberOption(
        AutoShootFeature,
        "Fire delay",
        autoSettings.fireDelay,
        0.1,
        2,
        function(value: number): ()
            autoSettings.fireDelay = math.clamp(value, 0.1, 2)
        end,
        "Seconds between automatic shots.",
        0.05
    )

    addActionOption(ShootFeature, "Shoot status", function(): ()
        local text = core.weaponStatus("Shoot") .. " | " .. core.weaponStatus("Gun observation")
            .. " | Prediction profile " .. tostring(mm2Settings.predictionProfile or "Actual")
            .. " | Actual/Silent model " .. tostring(mm2Settings.gunMotionModel)
            .. " | timing " .. tostring(mm2Settings.gunTimingModel)
            .. " | manual hold " .. tostring(mm2Settings.manualErrorGate)
            .. string.format(" | manual %s | auto %s (%s) | max error %.2f | horizon %.3fs | adaptive timing %s",
                mm2Settings.silentAim and "Silent AIM" or "Prediction",
                autoSettings.mode == "Silent" and "Silent AIM" or "Prediction",
                autoShootActive and "ON" or "OFF", autoSettings.maxError,
                getGunHorizonSeconds(), tostring(mm2Settings.adaptiveGunTiming))
        print("[Wurst:MM2] " .. text); notify(text)
    end)
    refreshShootOptions()
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
