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
    Module.Runtime = runtime
    local connectGunFiredSignal: any = core.connectGunFiredSignal
    local disconnectGunFiredObserver: any = core.disconnectGunFiredObserver
    local findMurderer: any = core.findMurderer
    local getFilteredVelocity: any = core.getFilteredVelocity
    local getGunHorizonSeconds: any = core.getGunHorizonSeconds
    local getGunTurnDiscount: any = core.getGunTurnDiscount
    local getGunTurnRate: any = core.getGunTurnRate
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
        if errorRadius > BODY_HALF_WIDTH then
            return nil, nil, "turning too hard"
        end

        local direction: Vector3 = delta.Unit
        return CFrame.lookAt(predicted, predicted + direction), {
            targetPosition = predicted,
            endpoint = predicted,
            velocity = velocity,
            errorRadius = errorRadius,
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
    local function buildSilentShot(
        target: Player,
        prediction: GunPrediction
    ): (CFrame, CFrame)
        local predicted: Vector3 = prediction.targetPosition
        local velocity: Vector3 = prediction.velocity
        local horizontal: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)

        local direction: Vector3 = Vector3.new(0, -1, 0)
        local sweep: number = 0
        if horizontal.Magnitude > 1.5 and mm2Settings.silentSweep > 0 then
            direction = horizontal.Unit
            -- Lay the authored segment along the movement axis, extended by the
            -- solver's own error budget. This replaces the old speed*lead guess
            -- with the one number that already accounts for turn uncertainty and
            -- latency, so the sweep widens exactly when the prediction is least
            -- certain instead of on a separate ad-hoc scale.
            sweep = math.clamp(
                prediction.errorRadius,
                0.5,
                mm2Settings.silentSweep
            )
        end

        local lift: Vector3 = Vector3.new(0, 1.6, 0)
        local startPoint: Vector3 = predicted - direction * sweep + lift
        -- Only a small overshoot: the endpoint has to stay on the body in case the
        -- server scores the hit from the endpoint rather than from the ray.
        local endPoint: Vector3 = predicted + direction * (sweep * 0.35)

        if sweep > 0 and bystanderOnSegment(target, startPoint, endPoint) then
            startPoint = predicted + lift
            endPoint = predicted
        end

        return CFrame.lookAt(startPoint, endPoint), CFrame.new(endPoint)
    end

    -- Fire one packet at the solved point.
    --
    -- The remote takes two CFrames: a rotated frame that looks from the muzzle at
    -- the impact point, and the impact point itself as a plain position. That is
    -- the shape the legitimate client sends, so the packet is indistinguishable at
    -- any ping; the only thing the solver changes is where the point sits.
    local function fireGunAtTarget(target: Player?): boolean
        local character, humanoid = getCharacterParts()
        if not target or not target.Character then
            notify("No selected shoot target was found.")
            return false
        end
        if not character or not humanoid then
            notify("Your character is not available.")
            return false
        end

        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
        local backpack: Backpack? = LocalPlayer:FindFirstChildOfClass("Backpack")
        if not gun and backpack then
            notify("You do not have the sheriff gun.")
            return false
        end
        if gun and gun.Parent == backpack and humanoid:IsA("Humanoid") then
            humanoid:EquipTool(gun)
            task.wait()
        end

        gun = getPlayerWeapon(LocalPlayer, "Gun", true) or gun
        local remote: Instance? = gun and gun:FindFirstChild("Shoot")
        local origin: CFrame? = getGunOriginCFrame(character, gun)

        local silent: boolean = mm2Settings.silentAim
        local aim: CFrame?, prediction: GunPrediction?, reason: string? = nil
        if origin then
            aim, prediction, reason = computeGunAim(
                target,
                origin :: CFrame,
                silent and {ignoreVisibility = true} or nil
            )
        end

        if not remote
            or not remote:IsA("RemoteEvent")
            or not origin
            or not aim
            or not prediction then
            runtime.lastRejectReason = reason
                or (origin and "no solution" or "no gun origin")
            notify(
                silent
                    and "The murderer has no usable body to aim at."
                    or "The murderer is unavailable or obstructed."
            )
            return false
        end
        runtime.lastRejectReason = nil

        state.mm2ShotFeedback.queue(target, gun, origin, aim, prediction)

        local resolved: GunPrediction = prediction :: GunPrediction
        if silent then
            local shotOrigin: CFrame, shotEnd: CFrame =
                buildSilentShot(target, resolved)
            remote:FireServer(shotOrigin, shotEnd)
            runtime.lastShotClock = os.clock()
            runtime.shotTarget = target
            runtime.shotTargetClock = os.clock()
            return true
        end

        remote:FireServer(
            aim :: CFrame,
            CFrame.new(resolved.endpoint)
        )
        runtime.lastShotClock = os.clock()
        runtime.shotTarget = target
        runtime.shotTargetClock = os.clock()
        return true
    end

    local shootFeatureActive: boolean = false
    local function setShootActive(value: boolean): ()
        shootFeatureActive = value
        state.mm2ShotFeedback.shootActive = value
    end

    local function triggerManualShot(): ()
        if not shootFeatureActive then
            notify("Enable Shoot first.")
            return
        end
        fireGunAtTarget(getSelectedShootTarget())
    end
    local function toggleShootMurderer(enabled: boolean): ()
        disconnectFeatureConnection("MM2MotionTracker")
        setShootActive(enabled)

        if not enabled then
            state.mm2ShotFeedback.pending = nil
            state.mm2ShotFeedback.lastAccepted = nil
            state.mm2ShotFeedback.hide()
            disconnectGunFiredObserver()
            return
        end

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
        end
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
        8,
        function(value: number): ()
            mm2Settings.silentSweep = value
        end,
        "Studs of tolerance laid along the target's movement. 0 = single point.",
        0.5
    )
    ShootTargetBox = addTextOption(ShootFeature, "Target player", "", function(
        value: string
    ): ()
        mm2Settings.shootTarget = value
    end, false)
    addToggleOption(
        ShootFeature,
        "Miss cooldown",
        mm2Settings.showMissCooldown,
        function(value: boolean): ()
            mm2Settings.showMissCooldown = value
            if not value then
                state.mm2ShotFeedback.pending = nil
                state.mm2ShotFeedback.lastAccepted = nil
                state.mm2ShotFeedback.hide()
            end
        end
    )
    refreshShootOptions()

    activeCleanup = function(): ()
        toggleShootMurderer(false)
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
