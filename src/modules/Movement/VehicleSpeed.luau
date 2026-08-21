--!strict
--
-- Vehicle Speed.
--
-- Speed for the things the humanoid does not own: a vehicle seat's MaxSpeed,
-- the torque of the hinges driving its wheels, and PlatformStand while you are
-- in one. Every original value is recorded per instance and put back, because
-- a seat left at ten times its torque stays broken for everyone who sits in it
-- afterwards.
--
-- It used to be called "Physics Speed", which said what it touched rather than
-- what it is for, and the name cost us a real bug: the vehicle work was already
-- here and nobody looking for it found it. Speed moves a character; this moves
-- whatever the character is sitting in.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "VehicleSpeed",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local state: any = host.state
    local getCharacterParts: any = host.getCharacterParts
    local UserInputService: any = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace

    type VehicleSpeedSettings = {
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

    local vehicleSpeedSettings: VehicleSpeedSettings = {
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
    -- The restore helper is shared with the option that can trigger it
    -- mid-session, so it is declared here and assigned in the block below,
    -- which also keeps the physics helpers' registers local to that block.
    local restorePhysicsMotors: () -> ()
    local vehicleSpeed: any
    do
    local vehicleTeleportClock: number = 0
    local originalVehicleSeats: {[VehicleSeat]: VehicleSeatState} =
        setmetatable({}, {__mode = "k"}) :: any
    local originalMotorHinges: {[HingeConstraint]: HingeState} =
        setmetatable({}, {__mode = "k"}) :: any

    restorePhysicsMotors = function(): ()
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

    local function getVehicleSpeedTarget(): (BasePart?, Humanoid?, VehicleSeat?)
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
                descendant.MaxSpeed = vehicleSpeedSettings.speed
                descendant.Torque = math.max(
                    resolvedOriginal.torque,
                    vehicleSpeedSettings.motorTorque
                )
                descendant.TurnSpeed = math.max(
                    resolvedOriginal.turnSpeed,
                    vehicleSpeedSettings.speed * 0.35
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
                        vehicleSpeedSettings.speed / 3
                    )
                descendant.MotorMaxTorque = math.max(
                    resolvedOriginal.motorMaxTorque,
                    vehicleSpeedSettings.motorTorque
                )
            end
        end
    end

    vehicleSpeed = framework.Categories.Movement:CreateModule({
        Name = "Vehicle Speed",
        Category = "Movement",
        Tooltip = "Fast movement for characters and occupied vehicles. Adaptive "
            .. "changes air authority and retains flow, Smooth accelerates "
            .. "predictably, Boost uses physical impulse, CFrame moves the "
            .. "character without touching its velocity, Pulse alternates "
            .. "bursts with a normal walk, and Teleport advances in short "
            .. "steps.",
        Function = function(enabled: boolean): ()
            restorePhysicsMotors()
            vehicleTeleportClock = 0
            state.platformStandController.set("VehicleSpeed", nil)

            if not enabled then
                return
            end

            vehicleSpeed:Loop(function(deltaTime: number): ()
                local assembly, currentHumanoid, vehicleSeat = getVehicleSpeedTarget()
                if not assembly or not currentHumanoid then
                    return
                end

                state.platformStandController.set(
                    "VehicleSpeed",
                    vehicleSpeedSettings.platformStand
                )
                state.platformStandController.apply(currentHumanoid)

                if vehicleSeat and vehicleSpeedSettings.customProperties then
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
                    local camera: Camera? = currentWorkspace.CurrentCamera
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
                if vehicleSpeedSettings.wallCheck
                    and direction.Magnitude > 0.001 then
                    local raycastParams: RaycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                    raycastParams.FilterDescendantsInstances = {
                        currentHumanoid.Parent :: Instance,
                    }
                    local wallHit: RaycastResult? = currentWorkspace:Raycast(
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
                    and vehicleSpeedSettings.autoJump
                    and direction.Magnitude > 0.001
                    and currentHumanoid.FloorMaterial ~= Enum.Material.Air then
                    currentHumanoid.Jump = true
                    local jumpVelocity: Vector3 = assembly.AssemblyLinearVelocity
                    assembly.AssemblyLinearVelocity = Vector3.new(
                        jumpVelocity.X,
                        math.max(jumpVelocity.Y, vehicleSpeedSettings.jumpVelocity),
                        jumpVelocity.Z
                    )
                end

                local currentVelocity: Vector3 = assembly.AssemblyLinearVelocity
                local grounded: boolean = currentHumanoid.FloorMaterial ~= Enum.Material.Air
                -- Touch clients hold a placed SPRINT button instead of a key.
                local sprinting: boolean = state.speedSprintHeld == true
                    or (not state.isMobile
                        and UserInputService:IsKeyDown(vehicleSpeedSettings.sprintKey))
                local resolvedSpeed: number = vehicleSpeedSettings.speed
                    * (sprinting and vehicleSpeedSettings.sprintMultiplier or 1)
                if vehicleSpeedSettings.mode == "Adaptive" and not grounded then
                    resolvedSpeed *= vehicleSpeedSettings.airControl
                end
                local vertical: number = math.clamp(
                    currentVelocity.Y,
                    -vehicleSpeedSettings.verticalSpeed,
                    vehicleSpeedSettings.verticalSpeed
                )
                local currentHorizontal: Vector3 = Vector3.new(
                    currentVelocity.X,
                    0,
                    currentVelocity.Z
                )
                local keepMomentum: boolean = vehicleSpeedSettings.preserveMomentum
                    or vehicleSpeedSettings.mode == "Adaptive"
                local targetHorizontal: Vector3 = not wallBlocked
                        and direction.Magnitude > 0.001
                        and direction * resolvedSpeed
                    or not wallBlocked and keepMomentum and currentHorizontal
                    or Vector3.zero
                local targetVelocity: Vector3 = targetHorizontal
                    + Vector3.new(0, vertical, 0)

                if vehicleSpeedSettings.mode == "Smooth"
                    or vehicleSpeedSettings.mode == "Adaptive" then
                    local alpha: number = 1 - math.exp(
                        -vehicleSpeedSettings.acceleration * deltaTime
                    )
                    local smoothedHorizontal: Vector3 = currentHorizontal:Lerp(
                        targetHorizontal,
                        alpha
                    )
                    assembly.AssemblyLinearVelocity = smoothedHorizontal
                        + Vector3.new(0, vertical, 0)
                elseif vehicleSpeedSettings.mode == "Boost" then
                    local correction: Vector3 = targetVelocity - currentVelocity
                    assembly:ApplyImpulse(
                        correction
                            * assembly.AssemblyMass
                            * math.clamp(deltaTime * 9, 0, 1)
                    )
                elseif vehicleSpeedSettings.mode == "CFrame" then
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
                elseif vehicleSpeedSettings.mode == "Pulse" then
                    -- Bursts with a coast between them: the average speed stays
                    -- close to a normal player's, only the peaks are fast.
                    local period: number = math.max(
                        vehicleSpeedSettings.burstInterval,
                        0.05
                    ) * 2
                    local burst: boolean = (os.clock() % period) < (period * 0.5)
                    local pulseSpeed: number = burst
                        and resolvedSpeed
                        or currentHumanoid.WalkSpeed
                    assembly.AssemblyLinearVelocity = (
                        not wallBlocked and direction * pulseSpeed or Vector3.zero
                    ) + Vector3.new(0, vertical, 0)
                elseif vehicleSpeedSettings.mode == "Teleport" then
                    vehicleTeleportClock = vehicleTeleportClock + deltaTime
                    if vehicleTeleportClock >= 0.14 then
                        assembly.CFrame = assembly.CFrame
                            + direction
                                * resolvedSpeed
                                * vehicleTeleportClock
                        vehicleTeleportClock = 0
                    end
                end
            end)
        end,
    })
    end

    vehicleSpeed:CreateDropdown({
        Name = "Mode",
        List = {"Adaptive", "Smooth", "Boost", "CFrame", "Pulse", "Teleport"},
        Index = 1,
        Function = function(value: string): ()
            vehicleSpeedSettings.mode = value
        end,
    })
    vehicleSpeed:CreateSlider({
        Name = "Speed",
        Min = 5,
        Max = 500,
        Default = vehicleSpeedSettings.speed,
        Function = function(value: number): ()
            vehicleSpeedSettings.speed = value
        end,
    })
    -- Every row below declares that it belongs to the switch after the block
    -- (and, where a mode owns it, to that mode) instead of the switch walking
    -- a list.
    local advanced: any = {Option = "Advanced settings"}
    vehicleSpeed:CreateSlider({
        Name = "Vertical speed",
        Show = advanced,
        Min = 0,
        Max = 300,
        Default = vehicleSpeedSettings.verticalSpeed,
        Function = function(value: number): ()
            vehicleSpeedSettings.verticalSpeed = value
        end,
    })
    vehicleSpeed:CreateToggle({
        Name = "PlatformStand",
        Show = advanced,
        Default = vehicleSpeedSettings.platformStand,
        Function = function(value: boolean): ()
            vehicleSpeedSettings.platformStand = value
        end,
    })
    vehicleSpeed:CreateToggle({
        Name = "Custom properties",
        Show = advanced,
        Default = vehicleSpeedSettings.customProperties,
        Function = function(value: boolean): ()
            vehicleSpeedSettings.customProperties = value
            if not value then
                restorePhysicsMotors()
            end
        end,
        Tooltip = "Rewrite the seat and wheel motors of a vehicle you are "
            .. "sitting in; the originals go back the moment this is off.",
    })
    vehicleSpeed:CreateSlider({
        Name = "Motor torque",
        Show = {advanced, {Option = "Custom properties"}},
        Min = 1000,
        Max = 250000,
        Default = vehicleSpeedSettings.motorTorque,
        Function = function(value: number): ()
            vehicleSpeedSettings.motorTorque = value
        end,
    })
    vehicleSpeed:CreateToggle({
        Name = "Wall check",
        Show = advanced,
        Default = vehicleSpeedSettings.wallCheck,
        Function = function(value: boolean): ()
            vehicleSpeedSettings.wallCheck = value
        end,
        Tooltip = "Stop against solid geometry instead of moving through it.",
    })
    vehicleSpeed:CreateSlider({
        Name = "Acceleration",
        Show = {advanced, {Option = "Mode", Values = {"Adaptive", "Smooth"}}},
        Min = 1,
        Max = 40,
        Default = vehicleSpeedSettings.acceleration,
        Function = function(value: number): ()
            vehicleSpeedSettings.acceleration = value
        end,
    })
    vehicleSpeed:CreateSlider({
        Name = "Burst interval (s)",
        Show = {advanced, {Option = "Mode", Values = {"Pulse"}}},
        Min = 0.05,
        Max = 1,
        Default = vehicleSpeedSettings.burstInterval,
        Function = function(value: number): ()
            vehicleSpeedSettings.burstInterval = value
        end,
    })
    vehicleSpeed:CreateSlider({
        Name = "Air control %",
        Show = {advanced, {Option = "Mode", Values = {"Adaptive"}}},
        Min = 10,
        Max = 150,
        Default = vehicleSpeedSettings.airControl * 100,
        Function = function(value: number): ()
            vehicleSpeedSettings.airControl = value / 100
        end,
    })
    vehicleSpeed:CreateSlider({
        Name = "Sprint multiplier",
        Show = advanced,
        Min = 1,
        Max = 4,
        Default = vehicleSpeedSettings.sprintMultiplier,
        Function = function(value: number): ()
            vehicleSpeedSettings.sprintMultiplier = value
        end,
    })
    local sprintKey: any = vehicleSpeed:CreateBind({
        Name = "Sprint key",
        Show = advanced,
        Default = vehicleSpeedSettings.sprintKey,
        Function = function(value: Enum.KeyCode): ()
            vehicleSpeedSettings.sprintKey = value
        end,
    })
    -- Sprint is a hold, so its mobile button is a hold too: tap the row's key
    -- slot to place it, then keep a finger on it to sprint.
    if state.bindMobileActionPlacement then
        state.bindMobileActionPlacement(
            sprintKey.Object,
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
    vehicleSpeed:CreateToggle({
        Name = "Preserve momentum",
        Show = advanced,
        Default = vehicleSpeedSettings.preserveMomentum,
        Function = function(value: boolean): ()
            vehicleSpeedSettings.preserveMomentum = value
        end,
    })
    vehicleSpeed:CreateToggle({
        Name = "Auto jump",
        Show = advanced,
        Default = vehicleSpeedSettings.autoJump,
        Function = function(value: boolean): ()
            vehicleSpeedSettings.autoJump = value
        end,
    })
    vehicleSpeed:CreateSlider({
        Name = "Auto-jump velocity",
        Show = {advanced, {Option = "Auto jump"}},
        Min = 20,
        Max = 120,
        Default = vehicleSpeedSettings.jumpVelocity,
        Function = function(value: number): ()
            vehicleSpeedSettings.jumpVelocity = value
        end,
    })
    vehicleSpeed:CreateToggle({
        Name = "Advanced settings",
        Default = false,
        Tooltip = "Everything above works on its own; this reveals the rest.",
    })

    activeCleanup = function(): ()
        restorePhysicsMotors()
        state.platformStandController.set("VehicleSpeed", nil)
    end
    Module.Initialized = true
    return vehicleSpeed
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
