export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Speed",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local movementInput: any = context.services.movementInput
    local framework: any = context.framework
    local LocalPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace

    type VehicleSeatState = {
        maxSpeed: number,
        torque: number,
        turnSpeed: number,
    }
    type HingeState = {
        angularVelocity: number,
        motorMaxTorque: number,
    }

    local runtime: any = {
        originalWalkSpeed = setmetatable({}, {__mode = "k"}) :: any,
        nextTeleportAt = 0,
        originalVehicleSeats = setmetatable({}, {__mode = "k"}) :: {[VehicleSeat]: VehicleSeatState},
        originalMotorHinges = setmetatable({}, {__mode = "k"}) :: {[HingeConstraint]: HingeState},
        velocityExcess = setmetatable({}, {__mode = "k"}) :: {[BasePart]: number},
        motorExcess = setmetatable({}, {__mode = "k"}) :: {[HingeConstraint]: number},
    }

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? =
            character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? =
            character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function restoreWalkSpeed(): ()
        for humanoid: Humanoid, value: number in pairs(runtime.originalWalkSpeed) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = value
            end
        end
        runtime.originalWalkSpeed = setmetatable({}, {__mode = "k"}) :: any
    end

    local function clearVehicleBoostHistory(): ()
        runtime.velocityExcess = setmetatable({}, {__mode = "k"}) :: any
        runtime.motorExcess = setmetatable({}, {__mode = "k"}) :: any
    end

    local function restoreVehicle(): ()
        for seat: VehicleSeat, original: VehicleSeatState in pairs(runtime.originalVehicleSeats) do
            if seat.Parent then
                seat.MaxSpeed = original.maxSpeed
                seat.Torque = original.torque
                seat.TurnSpeed = original.turnSpeed
            end
        end
        runtime.originalVehicleSeats = setmetatable({}, {__mode = "k"}) :: any
        for hinge: HingeConstraint, original: HingeState in pairs(runtime.originalMotorHinges) do
            if hinge.Parent then
                hinge.AngularVelocity = original.angularVelocity
                hinge.MotorMaxTorque = original.motorMaxTorque
            end
        end
        runtime.originalMotorHinges = setmetatable({}, {__mode = "k"}) :: any
        clearVehicleBoostHistory()
    end

    local function resolveVehicle(): (BasePart?, Model?, VehicleSeat?)
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            characterParts()
        if not character or not humanoid or not root then
            return nil, nil, nil
        end
        local seatPart: BasePart? = humanoid.SeatPart
        local assembly: BasePart? = nil
        if seatPart then
            assembly = seatPart.AssemblyRootPart or seatPart
        else
            assembly = root.AssemblyRootPart
            if not assembly or assembly:IsDescendantOf(character) then
                return nil, nil, nil
            end
        end
        local resolvedAssembly: BasePart = assembly :: BasePart
        local model: Model? = (seatPart or resolvedAssembly):FindFirstAncestorOfClass("Model")
        local vehicleSeat: VehicleSeat? = seatPart
                and seatPart:IsA("VehicleSeat")
                and seatPart :: VehicleSeat
            or nil
        return resolvedAssembly, model, vehicleSeat
    end

    local function rememberVehicleParts(model: Model?): ()
        if not model then
            return
        end
        for _, descendant: Instance in ipairs(model:GetDescendants()) do
            if descendant:IsA("VehicleSeat")
                and runtime.originalVehicleSeats[descendant] == nil then
                runtime.originalVehicleSeats[descendant] = {
                    maxSpeed = descendant.MaxSpeed,
                    torque = descendant.Torque,
                    turnSpeed = descendant.TurnSpeed,
                }
            elseif descendant:IsA("HingeConstraint")
                and descendant.ActuatorType == Enum.ActuatorType.Motor
                and runtime.originalMotorHinges[descendant] == nil then
                runtime.originalMotorHinges[descendant] = {
                    angularVelocity = descendant.AngularVelocity,
                    motorMaxTorque = descendant.MotorMaxTorque,
                }
            end
        end
    end

    local function boostedVehicleBase(current: number, previousExcess: number, multiplier: number): number
        local base: number = math.max(current - previousExcess, 0)
        if base < 0.01 and current > 0.01 then
            base = current / math.max(multiplier, 1)
        end
        return base
    end

    local function boostVehicleVelocity(assembly: BasePart, forcedDirection: Vector3?, multiplier: number): ()
        local current: Vector3 = assembly.AssemblyLinearVelocity
        local horizontal: Vector3 = Vector3.new(current.X, 0, current.Z)
        local curSpeed: number = horizontal.Magnitude
        if curSpeed < 0.01 then
            runtime.velocityExcess[assembly] = 0
            return
        end
        local base: number = boostedVehicleBase(curSpeed, runtime.velocityExcess[assembly] or 0, multiplier)
        local target: number = base * multiplier
        local direction: Vector3 = forcedDirection or horizontal.Unit
        direction = Vector3.new(direction.X, 0, direction.Z)
        if direction.Magnitude < 0.01 then
            return
        end
        direction = direction.Unit
        assembly.AssemblyLinearVelocity = direction * target + Vector3.new(0, current.Y, 0)
        runtime.velocityExcess[assembly] = math.max(target - base, 0)
    end

    local function boostVehicleMotors(model: Model?, multiplier: number, motorTorque: number): ()
        rememberVehicleParts(model)
        for hinge: HingeConstraint, original: HingeState in pairs(runtime.originalMotorHinges) do
            if not hinge.Parent or (model and not hinge:IsDescendantOf(model)) then
                continue
            end
            local current: number = hinge.AngularVelocity
            local sign: number = current < 0 and -1 or 1
            local magnitude: number = math.abs(current)
            local base: number = boostedVehicleBase(magnitude, runtime.motorExcess[hinge] or 0, multiplier)
            local target: number = base * multiplier
            hinge.AngularVelocity = sign * target
            hinge.MotorMaxTorque = math.max(
                original.motorMaxTorque * multiplier,
                motorTorque
            )
            runtime.motorExcess[hinge] = math.max(target - base, 0)
        end
    end

    local function boostVehicleSeatProperties(model: Model?, seat: VehicleSeat?, multiplier: number): ()
        rememberVehicleParts(model)
        if seat and runtime.originalVehicleSeats[seat] == nil then
            runtime.originalVehicleSeats[seat] = {
                maxSpeed = seat.MaxSpeed,
                torque = seat.Torque,
                turnSpeed = seat.TurnSpeed,
            }
        end
        for candidate: VehicleSeat, original: VehicleSeatState in pairs(runtime.originalVehicleSeats) do
            if not candidate.Parent or (model and not candidate:IsDescendantOf(model)) then
                continue
            end
            candidate.MaxSpeed = original.maxSpeed * multiplier
            candidate.Torque = original.torque * multiplier
            candidate.TurnSpeed = original.turnSpeed * multiplier
        end
    end

    local function moveDirection(): Vector3
        local camera: Camera? = currentWorkspace.CurrentCamera
        local forward: number, right: number = 0, 0
        if movementInput.getVector then
            forward, right = movementInput.getVector()
        end
        if forward == 0 and right == 0 then
            local _, humanoid: Humanoid? = characterParts()
            local move: Vector3 = humanoid and humanoid.MoveDirection or Vector3.zero
            return move.Magnitude > 0.05 and move.Unit or Vector3.zero
        end
        if not camera then
            return Vector3.zero
        end
        local look: Vector3 = (camera :: Camera).CFrame.LookVector
        local side: Vector3 = (camera :: Camera).CFrame.RightVector
        local flatLook: Vector3 = Vector3.new(look.X, 0, look.Z)
        local flatSide: Vector3 = Vector3.new(side.X, 0, side.Z)
        if flatLook.Magnitude < 0.001 then
            return Vector3.zero
        end
        local direction: Vector3 =
            flatLook.Unit * forward + flatSide.Unit * right
        return direction.Magnitude > 0.05 and direction.Unit or Vector3.zero
    end

    local function blocked(root: BasePart, step: Vector3): Vector3
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.RespectCanCollide = true
        local ignore: {Instance} = {LocalPlayer.Character :: Instance}
        for _, player: Player in ipairs(host.Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                table.insert(ignore, player.Character :: Instance)
            end
        end
        parameters.FilterDescendantsInstances = ignore
        local hit: RaycastResult? =
            currentWorkspace:Raycast(root.Position, step, parameters)
        if not hit then
            return step
        end
        return ((hit :: RaycastResult).Position + (hit :: RaycastResult).Normal)
            - root.Position
    end

    local speed: any
    speed = framework.Categories.Movement:CreateModule({
        Name = "Speed",
        Category = "Movement",
        ConfigKey = "Universal.Speed",
        Order = 1,
        Tooltip = "Move faster on foot or in vehicles, by whichever method works best.",
        Function = function(enabled: boolean): ()
            runtime.nextTeleportAt = 0
            restoreWalkSpeed()
            restoreVehicle()
            if not enabled then
                speed:SetStatus(nil)
                return
            end
            speed:SetStatus(
                tostring(speed.Options["Mode"].Value)
                    .. " "
                    .. tostring(math.round(speed.Options["Speed"].Value))
            )
            speed:Clean(function(): ()
                restoreWalkSpeed()
                restoreVehicle()
            end)
            speed:Loop(function(deltaTime: number): ()
                local options: any = speed.Options
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root then
                    return
                end
                local resolvedHumanoid: Humanoid = humanoid :: Humanoid
                local resolvedRoot: BasePart = root :: BasePart
                if resolvedHumanoid.Health <= 0 then
                    return
                end

                -- Vehicle Speed handler
                if options["Vehicle speed"] and options["Vehicle speed"].Value then
                    local assembly: BasePart?, model: Model?, seat: VehicleSeat? =
                        resolveVehicle()
                    if assembly then
                        local vehMode: string = options["Vehicle mode"] and options["Vehicle mode"].Value or "Multiplier"
                        local vehMultiplier: number = options["Vehicle multiplier"] and options["Vehicle multiplier"].Value or 2
                        local motorTorque: number = options["Motor torque"] and options["Motor torque"].Value or 50000
                        if vehMode == "Multiplier" then
                            boostVehicleVelocity(assembly :: BasePart, nil, vehMultiplier)
                        elseif vehMode == "Motors" then
                            boostVehicleMotors(model, vehMultiplier, motorTorque)
                        elseif vehMode == "Velocity" then
                            local direction: Vector3? = seat
                                and (seat :: VehicleSeat).CFrame.LookVector
                                    * (seat :: VehicleSeat).ThrottleFloat
                                or nil
                            boostVehicleVelocity(assembly :: BasePart, direction, vehMultiplier)
                        else
                            boostVehicleSeatProperties(model, seat, vehMultiplier)
                        end
                        return
                    end
                end

                -- On-foot character speed handler
                local mode: string = options["Mode"].Value
                local target: number = options["Speed"].Value

                if mode == "WalkSpeed" then
                    if runtime.originalWalkSpeed[resolvedHumanoid] == nil then
                        runtime.originalWalkSpeed[resolvedHumanoid] =
                            resolvedHumanoid.WalkSpeed
                    end
                    resolvedHumanoid.WalkSpeed = target
                    return
                end
                restoreWalkSpeed()

                local direction: Vector3 = moveDirection()
                if direction.Magnitude < 0.05 then
                    return
                end

                if options["Auto jump"].Value
                    and resolvedHumanoid.FloorMaterial ~= Enum.Material.Air then
                    resolvedHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end

                local velocity: Vector3 = resolvedRoot.AssemblyLinearVelocity
                if mode == "Velocity" then
                    resolvedRoot.AssemblyLinearVelocity = Vector3.new(
                        direction.X * target,
                        velocity.Y,
                        direction.Z * target
                    )
                    return
                end
                if mode == "Impulse" then
                    local wanted: Vector3 = direction * target
                    local difference: Vector3 = Vector3.new(
                        wanted.X - velocity.X,
                        0,
                        wanted.Z - velocity.Z
                    )
                    if difference.Magnitude > 2 then
                        resolvedRoot:ApplyImpulse(
                            difference * resolvedRoot.AssemblyMass
                        )
                    end
                    return
                end

                local extra: number =
                    math.max(target - resolvedHumanoid.WalkSpeed, 0)
                if mode == "Teleport" then
                    local now: number = os.clock()
                    if now < runtime.nextTeleportAt then
                        return
                    end
                    runtime.nextTeleportAt = now + options["Burst delay"].Value
                    local step: Vector3 = direction * extra
                        * options["Burst delay"].Value
                    if options["Wall check"].Value then
                        step = blocked(resolvedRoot, step)
                    end
                    resolvedRoot.CFrame = resolvedRoot.CFrame + step
                    return
                end

                local step: Vector3 = direction * extra * deltaTime
                if options["Wall check"].Value then
                    step = blocked(resolvedRoot, step)
                end
                resolvedRoot.CFrame = resolvedRoot.CFrame + step
            end)
        end,
    })

    speed:CreateDropdown({
        Name = "Mode",
        List = {"WalkSpeed", "Velocity", "Impulse", "CFrame", "Teleport"},
        Index = 1,
        Function = function(value: string): ()
            if speed.Enabled then
                speed:SetStatus(
                    value .. " " .. tostring(math.round(speed.Options["Speed"].Value))
                )
            end
        end,
        Tooltip = "WalkSpeed is the quietest; Velocity and Impulse are smooth physics; CFrame and Teleport step directly.",
    })
    speed:CreateSlider({
        Name = "Speed",
        Min = 16,
        Max = 200,
        Default = 32,
        Function = function(value: number): ()
            if speed.Enabled then
                speed:SetStatus(
                    tostring(speed.Options["Mode"].Value)
                        .. " "
                        .. tostring(math.round(value))
                )
            end
        end,
        Tooltip = "Studs per second for on-foot movement.",
    })
    speed:CreateToggle({
        Name = "Wall check",
        Show = {Option = "Mode", Values = {"CFrame", "Teleport"}},
        Default = true,
        Tooltip = "Stop at geometry instead of stepping through it.",
    })
    speed:CreateSlider({
        Name = "Burst delay",
        Show = {Option = "Mode", Values = {"Teleport"}},
        Min = 0.05,
        Max = 1,
        Default = 0.2,
        Tooltip = "Seconds between teleport steps.",
    })
    speed:CreateToggle({
        Name = "Auto jump",
        Show = {Option = "Mode", Values = {"Velocity", "Impulse", "CFrame", "Teleport"}},
        Default = false,
        Tooltip = "Hop continuously while moving.",
    })

    -- Vehicle Speed section integrated into Speed
    speed:CreateToggle({
        Name = "Vehicle speed",
        Default = false,
        Function = function(enabled: boolean): ()
            if not enabled then
                restoreVehicle()
            end
        end,
        Tooltip = "Boosts any vehicle or mount you are currently driving.",
    })
    speed:CreateDropdown({
        Name = "Vehicle mode",
        Show = {Option = "Vehicle speed", Values = {true}},
        List = {"Multiplier", "Motors", "Velocity", "Seat"},
        Index = 1,
        Function = function(): ()
            restoreVehicle()
        end,
        Tooltip = "Multiplier preserves vehicle steering; Motors powers wheel constraints; Velocity pushes the chassis; Seat boosts VehicleSeat properties.",
    })
    speed:CreateSlider({
        Name = "Vehicle multiplier",
        Show = {Option = "Vehicle speed", Values = {true}},
        Min = 1,
        Max = 10,
        Default = 2,
        Function = function(): ()
            clearVehicleBoostHistory()
        end,
        Tooltip = "Speed multiplier applied to vehicle driving speed.",
    })
    speed:CreateSlider({
        Name = "Motor torque",
        Show = {Option = "Vehicle speed", Values = {true}},
        Min = 1000,
        Max = 250000,
        Default = 50000,
        Tooltip = "Torque limit for motor hinges.",
    })

    activeCleanup = function(): ()
        restoreWalkSpeed()
        restoreVehicle()
    end
    Module.Initialized = true
    return speed
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
