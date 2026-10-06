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
    local getGunLeadSeconds: any = core.getGunLeadSeconds
    local getGunOriginCFrame: any = core.getGunOriginCFrame
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local getWeaponServiceModule: any = core.getWeaponServiceModule
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local mm2Settings: any = core.mm2Settings
    local motionSamples: any = core.motionSamples

    type GunPrediction = {
        aimPart: BasePart,
        targetPosition: Vector3,
        endpoint: Vector3,
        velocity: Vector3,
        leadSeconds: number,
        confidence: number,
    }

    type GunAimOptions = {
        -- Silent aim does not travel through the world: the shot is authored at
        -- the target, so line of sight is irrelevant and must not veto the
        -- solution (that is why silent aim used to fall back to a raw,
        -- unpredicted position).
        ignoreVisibility: boolean?,
        leadScale: number?,
    }

    local function computeGunAim(
        target: Player,
        origin: CFrame,
        options: GunAimOptions?
    ): (CFrame?, GunPrediction?)
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
            return nil, nil
        end

        local velocity: Vector3 = getFilteredVelocity(target, root)
        local sample: MotionSample? = motionSamples[target]
        local stability: number = sample and sample.stability or 1
        local acceleration: Vector3 = sample and sample.acceleration or Vector3.zero
        local grounded: boolean = sample and sample.grounded or false
        local horizontalVelocity: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
        local leadSeconds: number, verticalLeadSeconds: number =
            getGunLeadSeconds()
        local leadScale: number = resolvedOptions.leadScale or 1
        leadSeconds *= leadScale
        verticalLeadSeconds *= leadScale
        if horizontalVelocity.Magnitude < 1.5 and math.abs(velocity.Y) < 1.5 then
            leadSeconds = math.min(leadSeconds, 0.04)
            verticalLeadSeconds = math.min(verticalLeadSeconds, 0.04)
        end

        local moveDirection: Vector3 = humanoid.MoveDirection
        if horizontalVelocity.Magnitude < 1.5
            and moveDirection.Magnitude > 0.05 then
            local desiredSpeed: number = humanoid.WalkSpeed
            local desiredVelocity: Vector3 = moveDirection.Unit * desiredSpeed
            velocity = Vector3.new(
                desiredVelocity.X,
                velocity.Y,
                desiredVelocity.Z
            )
        end

        local raycastParams: RaycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.IgnoreWater = true
        local ignored: {Instance} = {}
        if LocalPlayer.Character then
            table.insert(ignored, LocalPlayer.Character)
        end
        raycastParams.FilterDescendantsInstances = ignored
        local localHead: BasePart? = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("Head")
            :: BasePart?
        if localHead and localHead:IsA("BasePart") and not ignoreVisibility then
            local muzzleBlocked: RaycastResult? = workspace:Raycast(
                localHead.Position,
                origin.Position - localHead.Position,
                raycastParams
            )
            if muzzleBlocked then
                return nil, nil
            end
        end

        local candidates: {string} = {
            "UpperTorso",
            "Torso",
            "HumanoidRootPart",
            "Head",
        }
        -- With no visibility constraint there is nothing to degrade towards: the
        -- full prediction is always the best answer.
        local leadScales: {number} = ignoreVisibility
            and {1}
            or {1, 0.82, 0.6, 0.35, 0}
        for _, leadScale: number in ipairs(leadScales) do
            local scaledLead: number = leadSeconds * leadScale
            local scaledVerticalLead: number =
                verticalLeadSeconds * leadScale
            for _, partName: string in ipairs(candidates) do
                local part: BasePart? = character:FindFirstChild(partName) :: BasePart?
                if part and part:IsA("BasePart") then
                    local horizontalAcceleration: Vector3 = Vector3.new(
                        acceleration.X,
                        0,
                        acceleration.Z
                    )
                    local displacement: Vector3 = Vector3.new(
                        velocity.X * scaledLead,
                        0,
                        velocity.Z * scaledLead
                    ) + horizontalAcceleration * (
                        0.25 * scaledLead * scaledLead
                    )
                    if grounded then
                        displacement = Vector3.new(
                            displacement.X,
                            math.clamp(velocity.Y, -2.5, 2.5)
                                * scaledVerticalLead,
                            displacement.Z
                        )
                    else
                        displacement = Vector3.new(
                            displacement.X,
                            velocity.Y * scaledVerticalLead
                                - 0.5
                                    * workspace.Gravity
                                    * scaledVerticalLead
                                    * scaledVerticalLead,
                            displacement.Z
                        )
                    end

                    local predicted: Vector3 = part.Position + displacement
                    local delta: Vector3 = predicted - origin.Position
                    if delta.Magnitude > 0.05 then
                        local direction: Vector3 = delta.Unit
                        local endpoint: Vector3 = predicted
                        local result: RaycastResult? = nil
                        if not ignoreVisibility and mm2Settings.shootWallCheck then
                            result = workspace:Raycast(
                                origin.Position,
                                predicted - origin.Position,
                                raycastParams
                            )
                        end
                        if ignoreVisibility
                            or not mm2Settings.shootWallCheck
                            or not result
                            or result.Instance:IsDescendantOf(character) then
                            local confidence: number = math.clamp(
                                stability
                                    * (1 - math.min(acceleration.Magnitude / 240, 0.45)),
                                0.2,
                                1
                            )
                            return CFrame.lookAt(
                                endpoint,
                                endpoint + direction
                            ), {
                                aimPart = part,
                                targetPosition = predicted,
                                endpoint = endpoint,
                                velocity = velocity,
                                leadSeconds = scaledLead,
                                confidence = confidence,
                            }
                        end
                    end
                end
            end
        end
        return nil, nil
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
            -- Residual lead error scales with speed and latency. Laying the
            -- segment along the movement axis keeps the body on the ray even when
            -- the estimate lands slightly early or late.
            sweep = math.clamp(
                horizontal.Magnitude * prediction.leadSeconds * 0.9,
                0.75,
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
        local aim: CFrame? = nil
        local prediction: GunPrediction? = nil
        if origin then
            aim, prediction = computeGunAim(
                target,
                origin,
                silent and {ignoreVisibility = true} or nil
            )
        end

        if not remote
            or not remote:IsA("RemoteEvent")
            or not origin
            or not aim then
            notify(
                silent
                    and "The murderer has no usable body to aim at."
                    or "The murderer is unavailable or obstructed."
            )
            return false
        end

        state.mm2ShotFeedback.queue(target, gun, origin, aim, prediction)

        if silent and prediction then
            local shotOrigin: CFrame, shotEnd: CFrame =
                buildSilentShot(target, prediction :: GunPrediction)
            remote:FireServer(shotOrigin, shotEnd)
            return true
        end

        -- Match the real client's argument shape: a rotated origin that looks at
        -- the impact point, and a plain position for the endpoint (the vanilla gun
        -- never sends a rotated second CFrame).
        local endpoint: Vector3 = prediction and prediction.endpoint or aim.Position
        remote:FireServer(
            CFrame.lookAt(origin.Position, endpoint),
            CFrame.new(endpoint)
        )
        return true
    end

    local function shootMurderer(): ()
        fireGunAtTarget(getSelectedShootTarget())
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
        shootMurderer()
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
