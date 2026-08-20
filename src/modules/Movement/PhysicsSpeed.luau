--!strict
--
-- Physics Speed.
--
-- Speed for the things the humanoid does not own: a vehicle seat's MaxSpeed,
-- the torque of the hinges driving its wheels, and PlatformStand while you are
-- in one. Every original value is recorded per instance and put back, because
-- a seat left at ten times its torque stays broken for everyone who sits in it
-- afterwards.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "PhysicsSpeed",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addCycleOption: any = host.addCycleOption
    local addFeatureTooltip: any = host.addFeatureTooltip
    local addKeyOption: any = host.addKeyOption
    local UserInputService: any = host.UserInputService
    local workspace: any = host.workspace
    type PhysicsSpeedSettings = {
        mode: string,
        speed: number,
        verticalSpeed: number,
        platformStand: boolean,
        customProperties: boolean,
        motorTorque: number,
        wallCheck: boolean,
        autoJump: boolean,
        jumpVelocity: number,
        acceleration: number,
        burstInterval: number,
        airControl: number,
        sprintMultiplier: number,
        sprintKey: Enum.KeyCode,
        preserveMomentum: boolean,
    }

    type VehicleSeatState = {
        maxSpeed: number,
        torque: number,
        turnSpeed: number,
    }

    type HingeState = {
        angularVelocity: number,
        motorMaxTorque: number,
    }

    local physicsSpeedSettings: PhysicsSpeedSettings = {
        mode = "Smooth",
        speed = 50,
        verticalSpeed = 50,
        platformStand = false,
        customProperties = true,
        motorTorque = 50000,
        wallCheck = true,
        autoJump = false,
        jumpVelocity = 45,
        acceleration = 14,
        burstInterval = 0.2,
        airControl = 0.72,
        sprintMultiplier = 1.65,
        sprintKey = Enum.KeyCode.LeftShift,
        preserveMomentum = false,
    }
    -- The physics-speed helpers are scoped to a block so their registers go
    -- back to the bootstrap function, which sits at Luau's 200-local ceiling.
    local restorePhysicsMotors: () -> ()
    local togglePhysicsSpeed: (boolean) -> ()
    do
    local physicsSpeedTeleportClock: number = 0
    local originalVehicleSeats: {[VehicleSeat]: VehicleSeatState} =
        setmetatable({}, {__mode = "k"}) :: any
    local originalMotorHinges: {[HingeConstraint]: HingeState} =
        setmetatable({}, {__mode = "k"}) :: any

    function restorePhysicsMotors(): ()
        for seat: VehicleSeat, original: VehicleSeatState in pairs(originalVehicleSeats) do
            if seat.Parent then
                seat.MaxSpeed = original.maxSpeed
                seat.Torque = original.torque
                seat.TurnSpeed = original.turnSpeed
            end
        end
        originalVehicleSeats = setmetatable({}, {__mode = "k"}) :: any

        for hinge: HingeConstraint, original: HingeState in pairs(originalMotorHinges) do
            if hinge.Parent then
                hinge.AngularVelocity = original.angularVelocity
                hinge.MotorMaxTorque = original.motorMaxTorque
            end
        end
        originalMotorHinges = setmetatable({}, {__mode = "k"}) :: any
    end

    local function getPhysicsSpeedTarget(): (BasePart?, Humanoid?, VehicleSeat?)
        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
            return nil, humanoid, nil
        end

        local seatPart: BasePart? = humanoid.SeatPart
        if seatPart and seatPart:IsA("VehicleSeat") then
            return seatPart.AssemblyRootPart or seatPart, humanoid, seatPart
        end
        if seatPart then
            return seatPart.AssemblyRootPart or seatPart, humanoid, nil
        end

        return root.AssemblyRootPart or root, humanoid, nil
    end

    local function tunePhysicsMotors(seat: VehicleSeat): ()
        local model: Model? = seat:FindFirstAncestorOfClass("Model")
        if not model then
            return
        end

        for _, descendant: Instance in ipairs(model:GetDescendants()) do
            if descendant:IsA("VehicleSeat") then
                local original: VehicleSeatState? = originalVehicleSeats[descendant]
                if not original then
                    original = {
                        maxSpeed = descendant.MaxSpeed,
                        torque = descendant.Torque,
                        turnSpeed = descendant.TurnSpeed,
                    }
                    originalVehicleSeats[descendant] = original
                end
                local resolvedOriginal: VehicleSeatState = original :: VehicleSeatState
                descendant.MaxSpeed = physicsSpeedSettings.speed
                descendant.Torque = math.max(
                    resolvedOriginal.torque,
                    physicsSpeedSettings.motorTorque
                )
                descendant.TurnSpeed = math.max(
                    resolvedOriginal.turnSpeed,
                    physicsSpeedSettings.speed * 0.35
                )
            elseif descendant:IsA("HingeConstraint")
                and descendant.ActuatorType == Enum.ActuatorType.Motor then
                local original: HingeState? = originalMotorHinges[descendant]
                if not original then
                    original = {
                        angularVelocity = descendant.AngularVelocity,
                        motorMaxTorque = descendant.MotorMaxTorque,
                    }
                    originalMotorHinges[descendant] = original
                end
                local resolvedOriginal: HingeState = original :: HingeState

                local sign: number = resolvedOriginal.angularVelocity < 0 and -1 or 1
                descendant.AngularVelocity = sign
                    * math.max(
                        math.abs(resolvedOriginal.angularVelocity),
                        physicsSpeedSettings.speed / 3
                    )
                descendant.MotorMaxTorque = math.max(
                    resolvedOriginal.motorMaxTorque,
                    physicsSpeedSettings.motorTorque
                )
            end
        end
    end

    function togglePhysicsSpeed(enabled: boolean): ()
        disconnectFeatureConnection("PhysicsSpeed")
        restorePhysicsMotors()
        physicsSpeedTeleportClock = 0

        state.platformStandController.set("PhysicsSpeed", nil)

        if not enabled then
            return
        end

        featureConnections.PhysicsSpeed =
            TaskManager:Connect(function(deltaTime: number): ()
                local assembly, currentHumanoid, vehicleSeat = getPhysicsSpeedTarget()
                if not assembly or not currentHumanoid then
                    return
                end

                state.platformStandController.set(
                    "PhysicsSpeed",
                    physicsSpeedSettings.platformStand
                )
                state.platformStandController.apply(currentHumanoid)

                if vehicleSeat and physicsSpeedSettings.customProperties then
                    tunePhysicsMotors(vehicleSeat)
                end

                local direction: Vector3 = currentHumanoid.MoveDirection
                if vehicleSeat then
                    direction = vehicleSeat.CFrame.LookVector * vehicleSeat.ThrottleFloat
                else
                    -- Humanoid.MoveDirection reads zero while PlatformStand is on
                    -- and on touch clients whose control module is bypassed, which
                    -- is exactly why Speed stood still with its own PlatformStand
                    -- option enabled. The shared helper answers on every device.
                    local camera: Camera? = workspace.CurrentCamera
                    local forwardScalar: number, rightScalar: number = state.getMoveInput()
                    if camera and (forwardScalar ~= 0 or rightScalar ~= 0) then
                        direction = camera.CFrame.LookVector * forwardScalar
                            + camera.CFrame.RightVector * rightScalar
                    end
                end
                direction = Vector3.new(direction.X, 0, direction.Z)
                if direction.Magnitude > 1 then
                    direction = direction.Unit
                end

                local wallBlocked: boolean = false
                if physicsSpeedSettings.wallCheck
                    and direction.Magnitude > 0.001 then
                    local raycastParams: RaycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                    raycastParams.FilterDescendantsInstances = {
                        currentHumanoid.Parent :: Instance,
                    }
                    local wallHit: RaycastResult? = workspace:Raycast(
                        assembly.Position,
                        direction.Unit * 2.75,
                        raycastParams
                    )
                    if wallHit then
                        direction = Vector3.zero
                        wallBlocked = true
                    end
                end

                if not vehicleSeat
                    and physicsSpeedSettings.autoJump
                    and direction.Magnitude > 0.001
                    and currentHumanoid.FloorMaterial ~= Enum.Material.Air then
                    currentHumanoid.Jump = true
                    local jumpVelocity: Vector3 = assembly.AssemblyLinearVelocity
                    assembly.AssemblyLinearVelocity = Vector3.new(
                        jumpVelocity.X,
                        math.max(jumpVelocity.Y, physicsSpeedSettings.jumpVelocity),
                        jumpVelocity.Z
                    )
                end

                local currentVelocity: Vector3 = assembly.AssemblyLinearVelocity
                local grounded: boolean = currentHumanoid.FloorMaterial ~= Enum.Material.Air
                -- Touch clients hold a placed SPRINT button instead of a key.
                local sprinting: boolean = state.speedSprintHeld == true
                    or (not state.isMobile
                        and UserInputService:IsKeyDown(physicsSpeedSettings.sprintKey))
                local resolvedSpeed: number = physicsSpeedSettings.speed
                    * (sprinting and physicsSpeedSettings.sprintMultiplier or 1)
                if physicsSpeedSettings.mode == "Adaptive" and not grounded then
                    resolvedSpeed *= physicsSpeedSettings.airControl
                end
                local vertical: number = math.clamp(
                    currentVelocity.Y,
                    -physicsSpeedSettings.verticalSpeed,
                    physicsSpeedSettings.verticalSpeed
                )
                local currentHorizontal: Vector3 = Vector3.new(
                    currentVelocity.X,
                    0,
                    currentVelocity.Z
                )
                local keepMomentum: boolean = physicsSpeedSettings.preserveMomentum
                    or physicsSpeedSettings.mode == "Adaptive"
                local targetHorizontal: Vector3 = not wallBlocked
                        and direction.Magnitude > 0.001
                        and direction * resolvedSpeed
                    or not wallBlocked and keepMomentum and currentHorizontal
                    or Vector3.zero
                local targetVelocity: Vector3 = targetHorizontal
                    + Vector3.new(0, vertical, 0)

                if physicsSpeedSettings.mode == "Smooth"
                    or physicsSpeedSettings.mode == "Adaptive" then
                    local alpha: number = 1 - math.exp(
                        -physicsSpeedSettings.acceleration * deltaTime
                    )
                    local smoothedHorizontal: Vector3 = currentHorizontal:Lerp(
                        targetHorizontal,
                        alpha
                    )
                    assembly.AssemblyLinearVelocity = smoothedHorizontal
                        + Vector3.new(0, vertical, 0)
                elseif physicsSpeedSettings.mode == "Boost" then
                    local correction: Vector3 = targetVelocity - currentVelocity
                    assembly:ApplyImpulse(
                        correction
                            * assembly.AssemblyMass
                            * math.clamp(deltaTime * 9, 0, 1)
                    )
                elseif physicsSpeedSettings.mode == "CFrame" then
                    -- Displacement instead of velocity: a speed cap has nothing to
                    -- clamp, and the walk the game already gives us is subtracted
                    -- so the total stays at the slider value.
                    local extra: number = math.max(
                        resolvedSpeed - currentHumanoid.WalkSpeed,
                        0
                    )
                    if not wallBlocked and direction.Magnitude > 0.001 then
                        assembly.CFrame = assembly.CFrame
                            + direction * extra * deltaTime
                    end
                elseif physicsSpeedSettings.mode == "Pulse" then
                    -- Bursts with a coast between them: the average speed stays
                    -- close to a normal player's, only the peaks are fast.
                    local period: number = math.max(
                        physicsSpeedSettings.burstInterval,
                        0.05
                    ) * 2
                    local burst: boolean = (os.clock() % period) < (period * 0.5)
                    local pulseSpeed: number = burst
                        and resolvedSpeed
                        or currentHumanoid.WalkSpeed
                    assembly.AssemblyLinearVelocity = (
                        not wallBlocked and direction * pulseSpeed or Vector3.zero
                    ) + Vector3.new(0, vertical, 0)
                elseif physicsSpeedSettings.mode == "Teleport" then
                    physicsSpeedTeleportClock = physicsSpeedTeleportClock + deltaTime
                    if physicsSpeedTeleportClock >= 0.14 then
                        assembly.CFrame = assembly.CFrame
                            + direction
                                * resolvedSpeed
                                * physicsSpeedTeleportClock
                        physicsSpeedTeleportClock = 0
                    end
                end
            end)
    end
    end

    local PhysicsSpeedFeature = createUniversalFeature(
        "Speed",
        "Fast movement for characters and occupied vehicles",
        9,
        togglePhysicsSpeed
    )
    local SpeedModeButton: TextButton = addCycleOption(
        PhysicsSpeedFeature,
        "Mode",
        {"Adaptive", "Smooth", "Boost", "CFrame", "Pulse", "Teleport"},
        1,
        function(value: string): ()
            physicsSpeedSettings.mode = value
        end
    )
    local SpeedValueRow: Frame = addNumberOption(
        PhysicsSpeedFeature,
        "Speed",
        physicsSpeedSettings.speed,
        5,
        500,
        function(value: number): ()
            physicsSpeedSettings.speed = value
        end
    )
    local SpeedVerticalRow: Frame = addNumberOption(
        PhysicsSpeedFeature,
        "Vertical speed",
        physicsSpeedSettings.verticalSpeed,
        0,
        300,
        function(value: number): ()
            physicsSpeedSettings.verticalSpeed = value
        end
    )
    local SpeedPlatformButton: TextButton = addToggleOption(
        PhysicsSpeedFeature,
        "PlatformStand",
        physicsSpeedSettings.platformStand,
        function(value: boolean): ()
            physicsSpeedSettings.platformStand = value
        end
    )
    local SpeedMotorRow: Frame = addNumberOption(
        PhysicsSpeedFeature,
        "Motor torque",
        physicsSpeedSettings.motorTorque,
        1000,
        250000,
        function(value: number): ()
            physicsSpeedSettings.motorTorque = value
        end
    )
    local speedAdvancedVisible: boolean = false
    local SpeedCustomButton: TextButton = addToggleOption(
        PhysicsSpeedFeature,
        "Custom properties",
        physicsSpeedSettings.customProperties,
        function(value: boolean): ()
            physicsSpeedSettings.customProperties = value
            setOptionVisible(
                PhysicsSpeedFeature,
                SpeedMotorRow,
                speedAdvancedVisible and value
            )
            if not value then
                restorePhysicsMotors()
            end
        end
    )
    local SpeedWallButton: TextButton = addToggleOption(
        PhysicsSpeedFeature,
        "Wall check",
        physicsSpeedSettings.wallCheck,
        function(value: boolean): ()
            physicsSpeedSettings.wallCheck = value
        end
    )
    local SpeedDynamics: any = {}
    SpeedDynamics.acceleration = addNumberOption(
        PhysicsSpeedFeature,
        "Acceleration",
        physicsSpeedSettings.acceleration,
        1,
        40,
        function(value: number): ()
            physicsSpeedSettings.acceleration = value
        end
    )
    SpeedDynamics.burstInterval = addNumberOption(
        PhysicsSpeedFeature,
        "Burst interval (s)",
        physicsSpeedSettings.burstInterval,
        0.05,
        1,
        function(value: number): ()
            physicsSpeedSettings.burstInterval = value
        end
    )
    SpeedDynamics.airControl = addNumberOption(
        PhysicsSpeedFeature,
        "Air control %",
        physicsSpeedSettings.airControl * 100,
        10,
        150,
        function(value: number): ()
            physicsSpeedSettings.airControl = value / 100
        end
    )
    SpeedDynamics.sprintMultiplier = addNumberOption(
        PhysicsSpeedFeature,
        "Sprint multiplier",
        physicsSpeedSettings.sprintMultiplier,
        1,
        4,
        function(value: number): ()
            physicsSpeedSettings.sprintMultiplier = value
        end
    )
    SpeedDynamics.sprintKey = addKeyOption(
        PhysicsSpeedFeature,
        "Sprint key",
        physicsSpeedSettings.sprintKey,
        function(value: Enum.KeyCode): ()
            physicsSpeedSettings.sprintKey = value
        end
    )
    -- Sprint is a hold, so its mobile button is a hold too: tap the row's key
    -- slot to place it, then keep a finger on it to sprint.
    if state.bindMobileActionPlacement then
        state.bindMobileActionPlacement(
            SpeedDynamics.sprintKey,
            "UniversalSpeedSprint",
            "SPRINT",
            function(): () end,
            {
                onPress = function(): ()
                    state.speedSprintHeld = true
                end,
                onRelease = function(): ()
                    state.speedSprintHeld = false
                end,
            }
        )
    end
    SpeedDynamics.preserveMomentum = addToggleOption(
        PhysicsSpeedFeature,
        "Preserve momentum",
        physicsSpeedSettings.preserveMomentum,
        function(value: boolean): ()
            physicsSpeedSettings.preserveMomentum = value
        end
    )
    local SpeedJumpRow: Frame = addNumberOption(
        PhysicsSpeedFeature,
        "Auto-jump velocity",
        physicsSpeedSettings.jumpVelocity,
        20,
        120,
        function(value: number): ()
            physicsSpeedSettings.jumpVelocity = value
        end
    )
    local SpeedAutoJumpButton: TextButton = addToggleOption(
        PhysicsSpeedFeature,
        "Auto jump",
        physicsSpeedSettings.autoJump,
        function(value: boolean): ()
            physicsSpeedSettings.autoJump = value
            setOptionVisible(
                PhysicsSpeedFeature,
                SpeedJumpRow,
                speedAdvancedVisible and value
            )
        end
    )
    local SpeedAdvancedButton: TextButton = addToggleOption(
        PhysicsSpeedFeature,
        "Advanced settings",
        false,
        function(value: boolean): ()
            speedAdvancedVisible = value
            setOptionVisible(PhysicsSpeedFeature, SpeedVerticalRow, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedPlatformButton.Parent :: GuiObject, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedCustomButton.Parent :: GuiObject, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedMotorRow, value and physicsSpeedSettings.customProperties)
            setOptionVisible(PhysicsSpeedFeature, SpeedWallButton.Parent :: GuiObject, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.acceleration, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.burstInterval, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.airControl, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.sprintMultiplier, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.sprintKey.Parent :: GuiObject, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.preserveMomentum.Parent :: GuiObject, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedAutoJumpButton.Parent :: GuiObject, value)
            setOptionVisible(PhysicsSpeedFeature, SpeedJumpRow, value and physicsSpeedSettings.autoJump)
        end
    )
    local SpeedModeRow: GuiObject = SpeedModeButton.Parent :: GuiObject
    local SpeedAdvancedRow: GuiObject = SpeedAdvancedButton.Parent :: GuiObject
    SpeedModeRow.LayoutOrder = 1
    SpeedValueRow.LayoutOrder = 2
    SpeedAdvancedRow.LayoutOrder = 3
    addFeatureTooltip(
        PhysicsSpeedFeature,
        "Adaptive changes air authority and retains flow, Smooth accelerates predictably, "
            .. "Boost uses physical impulse, CFrame moves the character without touching its "
            .. "velocity, Pulse alternates bursts with a normal walk, and Teleport advances in "
            .. "short steps. Sprint, momentum, wall safety, auto-jump and vehicle tuning are "
            .. "independently configurable."
    )

    activeCleanup = function(): ()
        togglePhysicsSpeed(false)
    end
    Module.Initialized = true
    return PhysicsSpeedFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
