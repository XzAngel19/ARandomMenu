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

    -- One motion model, one lead time, one error budget.
    --
    -- Everything the solver needs is a measured quantity: the target's filtered
    -- velocity and acceleration from the core's motion sampler, whether it is on
    -- the ground, and the shot horizon the core derives from the round trip (see
    -- GUN_LEAD in base.lua). There is no per-ping special case and no ladder of
    -- fallback leads: the same expression runs at 20 ms and at 350 ms, and the
    -- only thing that changes with ping is the horizon itself.
    -- Only the fields a caller actually reads. The solver computes more than
    -- this internally (horizon, turn rate/discount), but those stay local: a
    -- field nobody consumes is just dead weight (KISS/YAGNI).
    type GunPrediction = {
        targetPosition: Vector3,
        endpoint: Vector3,
        velocity: Vector3,
        errorRadius: number,
        leadSeconds: number,
        leadSensitivity: number,
    }

    type GunAimOptions = {
        -- Silent aim does not travel through the world: the shot is authored at
        -- the target, so line of sight is irrelevant and must not veto the
        -- solution.
        ignoreVisibility: boolean?,
    }

    -- Half width of the capsule the server will score the ray against. Used to
    -- turn the prediction error into a yes/no answer instead of a guess.
    local BODY_HALF_WIDTH: number = 1.0
    -- Floor for the error budget: even a perfect model does not know where a
    -- strafing player will be, so never claim better than this.
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

    -- Where the target will be when the server scores the shot, plus how much
    -- that answer is worth. Returns nil when there is nothing to shoot at or the
    -- prediction is worse than the body is wide.
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
        local acceleration: Vector3 = sample and sample.acceleration or Vector3.zero
        local grounded: boolean = sample and sample.grounded
            or humanoid.FloorMaterial ~= Enum.Material.Air
        -- How well the target's heading from one sample ago predicts this one.
        -- Straight running scores ~1, a hard turn scores ~0. Without a reading
        -- (first frame after a teleport, dead sampler) we assume a brisk turn.
        local turnRate: number = getGunTurnRate(
            sample and sample.character == character and sample.stability or nil
        )

        -- A player who has not moved for a frame is standing still: use the
        -- Humanoid's intent so the first shot after a stop is not led at all,
        -- and the first shot after a start is led at walking speed.
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
        local displacement: Vector3 = Vector3.new(
            velocity.X * lead,
            0,
            velocity.Z * lead
        ) + horizontalAcceleration * (0.25 * lead * lead)

        if grounded then
            -- On the ground there is no flight to integrate: the only vertical
            -- error is the noise in the sampled velocity.
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
        local delta: Vector3 = predicted - origin.Position
        if delta.Magnitude <= 0.05 then
            return nil, nil, "too close"
        end

        if not ignoreVisibility and mm2Settings.shootWallCheck then
            local raycastParams: RaycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.IgnoreWater = true
            raycastParams.FilterDescendantsInstances = {
                LocalPlayer.Character :: Instance,
            }
            local result: RaycastResult? = workspace:Raycast(
                origin.Position,
                predicted - origin.Position,
                raycastParams
            )
            if result and not result.Instance:IsDescendantOf(character :: Model) then
                return nil, nil, "obstructed"
            end
        end

        -- Error budget: the sideways distance a turn of the measured rate puts
        -- between the target and the point we solved for, plus the sampler's own
        -- uncertainty, floored so a straight-line runner is never treated as a
        -- guaranteed hit. This is the number that decides the shot, and it is
        -- reported verbatim so a miss can be read back off the telemetry.
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

    -- Is somebody else's body sitting on the silent-aim segment? Hitting the
    -- wrong player as sheriff is an instant loss, so the sweep collapses to a
    -- point rather than risking it.
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

    -- Silent aim authors the shot at the target instead of at the muzzle, so the
    -- only thing that decides a hit is how close the authored point is to where
    -- the server believes the target is. That is exactly what the Shoot solver
    -- already computes, so silent aim now consumes the same prediction instead of
    -- the raw, one-frame-old root position it used before.
    --
    -- The bullet appears where arg1 sits, so arg1 is the visual spawn point.
    -- Four authored geometries are offered as a live A/B (the menu cannot
    -- assert which one scores best - the server's hit test is inferred, not
    -- known), and every shot is tagged with its variant so the Spawn A/B
    -- status and the Game Learning log can count real hits per geometry:
    --
    --   Front   in front of the torso, shooter's side, at torso height.
    --           Straight-on shots travel straight and level.
    --   Through the whole segment pierces the torso (front to far side):
    --           the longest possible segment inside the body, so a predicted
    --           point off by up to ~1 stud still leaves the segment crossing
    --           the capsule.
    --   Top     the old geometry: 1.6 studs above the impact point. The
    --           vertical segment through the body axis crosses more of the
    --           capsule than Front does, which is why it may have scored more.
    --   Behind  authored on the far side of the torso; the bullet visibly
    --           travels toward the shooter.
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
    ): (CFrame, CFrame, number)
        local predicted: Vector3 = prediction.targetPosition
        local velocity: Vector3 = prediction.velocity
        local horizontal: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)

        local direction: Vector3? = nil
        local sweep: number = 0
        if horizontal.Magnitude > 1.5 then
            direction = horizontal.Unit
            -- This option is a literal geometric extension, not an invented
            -- error value: each end of the authored ray moves by exactly the
            -- configured distance along measured horizontal target movement.
            sweep = getSilentSweepDistance()
        end
        local sweepStart: Vector3 =
            direction and -direction * sweep or Vector3.zero
        local sweepEnd: Vector3 =
            direction and direction * sweep or Vector3.zero

        -- Horizontal direction from the shooter to the predicted point: the
        -- bullet appears on the shooter's side of the torso. The offset is
        -- clamped to 60 % of the flat distance so at point blank the origin
        -- never lands past the body.
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
            -- Front to far side: the segment crosses the full body.
            startPoint = predicted - approach * approachOffset + sweepStart
            endPoint = predicted + approach * SILENT_PIERCE_STUDS + sweepEnd
        elseif variant == "Top" then
            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
                + sweepStart
            endPoint = predicted + sweepEnd
        elseif variant == "Behind" and approach then
            startPoint = predicted + approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif approach then
            -- "Front" (default) and the fallback for Behind without approach.
            startPoint = predicted - approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif direction then
            startPoint = predicted + sweepStart
            endPoint = predicted + sweepEnd
        else
            -- Shooter directly above the target with no movement axis to lean
            -- on: the old lifted origin is the only usable geometry.
            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            endPoint = predicted
        end

        if sweep > 0 and bystanderOnSegment(target, startPoint, endPoint) then
            -- Collapse to a point on the body: hitting the wrong player as
            -- sheriff is an instant loss.
            if variant ~= "Top" and approach then
                startPoint = predicted - approach * approachOffset
            else
                startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            end
            endPoint = predicted
        end

        return CFrame.lookAt(startPoint, endPoint), CFrame.new(endPoint),
            approachOffset
    end

    -- Options for one trigger pull. `silent` authors the shot at the target
    -- (through walls, any distance); `maxError` is an optional accuracy gate the
    -- auto-fire uses so it only takes high-probability shots; `quiet` suppresses
    -- the toast notifications the manual key press relies on (and, with it, the
    -- one yielding call, so the auto-fire never yields inside a frame callback).
    type FireOptions = {
        silent: boolean?,
        maxError: number?,
        quiet: boolean?,
    }

    -- Set by the most recent reject() call so the auto-shoot loop can surface
    -- the reason once per change even when quiet mode suppresses the toast.
    -- Declared before fireGunAtTarget so reject() captures it as an upvalue.
    local lastRejectReason: string = ""

    -- Fire one packet at the solved point.
    --
    -- The remote takes two CFrames: a rotated frame that looks from the muzzle at
    -- the impact point, and the impact point itself as a plain position. That is
    -- the shape the legitimate client sends, so the packet is indistinguishable at
    -- any ping; the only thing the solver changes is where the point sits.
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
                -- Auto-fire runs inside a frame callback that must not yield; let
                -- the equip settle and try again on the next tick.
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
            -- A longer ray does not make the motion estimate more accurate.
            -- Keep this gate tied to the solver's error budget, not the visual
            -- sweep length, so changing sweep cannot force a speculative shot.
            return reject("Shot accuracy is too low to fire.")
        end

        if silent then
            -- The silent packet is authored at the target, so the feedback must
            -- expect the GunFired origin there, not at the muzzle.
            local variant: string = mm2Settings.silentSpawn
            local shotOrigin: CFrame, shotEnd: CFrame, offset: number =
                buildSilentShot(target, resolved, origin, variant)
            state.mm2ShotFeedback.queue(target, gun, shotOrigin, aim, resolved)
            if state.mm2ShotFeedback.pending then
                state.mm2ShotFeedback.pending.silentSpawn = variant
            end
            -- Published through the game bridge so the passive Game Learning
            -- log can tag this shot with its authored geometry.
            state.lastSilentShotInfo = {
                variant = variant,
                at = os.clock(),
                offset = math.floor(offset * 10) / 10,
            }
            remote:FireServer(shotOrigin, shotEnd)
            -- The silent packet never triggers tool.Activated, so feed the
            -- authored geometry to the calibration + passive loggers directly.
            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "gun",
                tool = gun,
                toolName = gun and gun.Name or "Gun",
                originPos = shotOrigin.Position,
                aimPos = shotEnd.Position,
                target = target,
                silent = true,
                variant = variant,
            })
            return true
        end

        -- arg1 must sit at the muzzle. Captured vanilla packets show the server
        -- ignoring arg1's rotation entirely (muzzle frames up to 176 deg away
        -- from the endpoint still register), so the hit geometry comes from the
        -- two positions: a segment that starts and ends on the target is zero
        -- long and never registers. `aim` is deliberately positioned at the
        -- target (the feedback module reads aim.Position as the aim point), so
        -- the shot frame is built from the muzzle - this is what the vanilla
        -- client sends.
        state.mm2ShotFeedback.queue(target, gun, origin, aim, resolved)
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
        })
        return true
    end

    local shootFeatureActive: boolean = false
    local autoShootActive: boolean = false

    -- Shared motion sampling + gun-fired observer. Both the manual Shoot and
    -- Auto Shoot need live filtered velocities, so the sampler stays alive while
    -- either is on and is torn down only when both are off.
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
                    motionElapsed += deltaTime
                    if motionElapsed < 1 / 30 then
                        return
                    end
                    motionElapsed = 0
                    for _, player: Player in ipairs(Players:GetPlayers()) do
                        local root: BasePart? = player.Character
                            and player.Character:FindFirstChild("HumanoidRootPart")
                            :: BasePart?
                        if root and isPlayerAlive(player) then
                            getFilteredVelocity(player, root)
                        end
                    end
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

    -- ----- Auto Shoot -----
    -- Fires on its own the moment a high-probability solution exists. Normal mode
    -- shoots from the muzzle and respects the wall check, so it holds fire until
    -- the murderer peeks out from cover (that is the peek detection); Silent mode
    -- authors the shot at the target and fires from any distance, through walls.
    local autoSettings = {
        mode = "Normal" :: string,
        maxError = 0.6,
        fireDelay = 0.5,
    }
    local lastAutoShot: number = -math.huge
    local lastGunCheck: number = -math.huge
    local lastAutoReject: {message: string, at: number}? = nil

    -- Keep the sheriff gun in hand the moment it is available (round start,
    -- role handout, picking the dropped gun), not only when a target shows up:
    -- otherwise the first auto shot is delayed by the equip animation.
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
        -- Hold the fire rate, then look for a shot every tick once it is off
        -- cooldown so a peek is answered immediately.
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
            -- Quiet mode swallows the reject reason; surface it once per reason
            -- change so a waiting auto shooter is not a mystery.
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
            autoElapsed += deltaTime
            if autoElapsed < 1 / 30 then
                return
            end
            autoElapsed = 0
            autoShootTick()
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
    local function refreshShootOptions(): ()
        if ShootTargetBox then
            setOptionVisible(
                ShootFeature,
                ShootTargetBox.Parent :: GuiObject,
                mm2Settings.shootMode == "Custom"
            )
        end
    end
    addCycleOption(
        ShootFeature,
        "Mode",
        {"Manual", "Custom"},
        1,
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
        "Holds fire while a wall blocks the muzzle. SilentAIM skips it: it "
            .. "authors the shot at the target."
    )
    addToggleOption(
        ShootFeature,
        "SilentAIM",
        mm2Settings.silentAim,
        function(value: boolean): ()
            mm2Settings.silentAim = value
        end,
        "Authors the shot at the target: same prediction as Shoot, ignores walls."
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
            .. "No local physics change; a ray that would cross a bystander is "
            .. "collapsed to a point.",
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
    addActionOption(ShootFeature, "Spawn A/B status", function(): ()
        notify(spawnStatsText())
    end)
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
        -0.1,
        0.1,
        function(value: number): ()
            mm2Settings.gunLeadBias = math.clamp(value, -0.1, 0.1)
        end,
        "Manual time correction in seconds (positive = lead further ahead). "
            .. "It is added to the prediction horizon, bounded to +/-0.1s, and "
            .. "does not change character physics.",
        0.005
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
        0.1,
        1,
        function(value: number): ()
            autoSettings.maxError = value
        end,
        "Only fire when the predicted error is within this many studs. In "
            .. "Silent mode the sweep cap relaxes it: the authored segment "
            .. "already covers the error up to its length.",
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
