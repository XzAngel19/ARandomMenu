--!strict
--
-- Vehicle Speed.
--
-- Speed moves a character; this moves the assembly the character is sitting
-- in. Four routes exist because vehicle scripts disagree about what they leave
-- writable. Multiplier comes first because it keeps the velocity direction the
-- vehicle produced, so steering remains the game's. Motors, a direct chassis
-- velocity and the VehicleSeat properties are progressively more invasive.
--
-- Every seat and hinge property is restored from its own recorded value. A
-- vehicle left with boosted torque remains broken for the next driver, so
-- restoring an assumed default is not enough.

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
    local framework: any = context.framework
    local getCharacterParts: any = context.host.getCharacterParts

    type VehicleSeatState = {
        maxSpeed: number,
        torque: number,
        turnSpeed: number,
    }
    type HingeState = {
        angularVelocity: number,
        motorMaxTorque: number,
    }

    local settings = {
        mode = "Multiplier",
        multiplier = 2,
        motorTorque = 50000,
    }
    local originalVehicleSeats: {[VehicleSeat]: VehicleSeatState} =
        setmetatable({}, {__mode = "k"}) :: any
    local originalMotorHinges: {[HingeConstraint]: HingeState} =
        setmetatable({}, {__mode = "k"}) :: any
    -- The excess is separate from the vehicle's own speed. Subtracting last
    -- frame's excess before applying the multiplier again is what prevents
    -- 2x from becoming 4x, 8x and then a car in orbit.
    local velocityExcess: {[BasePart]: number} =
        setmetatable({}, {__mode = "k"}) :: any
    local motorExcess: {[HingeConstraint]: number} =
        setmetatable({}, {__mode = "k"}) :: any

    local function clearBoostHistory(): ()
        velocityExcess = setmetatable({}, {__mode = "k"}) :: any
        motorExcess = setmetatable({}, {__mode = "k"}) :: any
    end

    local function restoreVehicle(): ()
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
        clearBoostHistory()
    end

    local function resolveVehicle(): (BasePart?, Model?, VehicleSeat?)
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            getCharacterParts()
        if not character or not humanoid or not root then
            return nil, nil, nil
        end
        local seatPart: BasePart? = humanoid.SeatPart
        local assembly: BasePart? = nil
        if seatPart then
            assembly = seatPart.AssemblyRootPart or seatPart
        else
            -- Some games weld the character straight onto a chassis. The
            -- assembly root leaving the character is the general signal; an
            -- ordinary standing character must never fall through to Speed.
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

    local function rememberParts(model: Model?): ()
        if not model then
            return
        end
        for _, descendant: Instance in ipairs(model:GetDescendants()) do
            if descendant:IsA("VehicleSeat")
                and originalVehicleSeats[descendant] == nil then
                originalVehicleSeats[descendant] = {
                    maxSpeed = descendant.MaxSpeed,
                    torque = descendant.Torque,
                    turnSpeed = descendant.TurnSpeed,
                }
            elseif descendant:IsA("HingeConstraint")
                and descendant.ActuatorType == Enum.ActuatorType.Motor
                and originalMotorHinges[descendant] == nil then
                originalMotorHinges[descendant] = {
                    angularVelocity = descendant.AngularVelocity,
                    motorMaxTorque = descendant.MotorMaxTorque,
                }
            end
        end
    end

    local function boostedBase(current: number, previousExcess: number): number
        local base: number = math.max(current - previousExcess, 0)
        if base < 0.01 and current > 0.01 then
            base = current / math.max(settings.multiplier, 1)
        end
        return base
    end

    local function boostVelocity(assembly: BasePart, forcedDirection: Vector3?): ()
        local current: Vector3 = assembly.AssemblyLinearVelocity
        local horizontal: Vector3 = Vector3.new(current.X, 0, current.Z)
        local speed: number = horizontal.Magnitude
        if speed < 0.01 then
            velocityExcess[assembly] = 0
            return
        end
        local base: number = boostedBase(speed, velocityExcess[assembly] or 0)
        local target: number = base * settings.multiplier
        local direction: Vector3 = forcedDirection or horizontal.Unit
        direction = Vector3.new(direction.X, 0, direction.Z)
        if direction.Magnitude < 0.01 then
            return
        end
        direction = direction.Unit
        assembly.AssemblyLinearVelocity = direction * target
            + Vector3.new(0, current.Y, 0)
        velocityExcess[assembly] = math.max(target - base, 0)
    end

    local function boostMotors(model: Model?): ()
        rememberParts(model)
        for hinge: HingeConstraint, original: HingeState in pairs(originalMotorHinges) do
            if not hinge.Parent or (model and not hinge:IsDescendantOf(model)) then
                continue
            end
            local current: number = hinge.AngularVelocity
            local sign: number = current < 0 and -1 or 1
            local magnitude: number = math.abs(current)
            local base: number = boostedBase(magnitude, motorExcess[hinge] or 0)
            local target: number = base * settings.multiplier
            hinge.AngularVelocity = sign * target
            hinge.MotorMaxTorque = math.max(
                original.motorMaxTorque * settings.multiplier,
                settings.motorTorque
            )
            motorExcess[hinge] = math.max(target - base, 0)
        end
    end

    local function boostSeatProperties(model: Model?, seat: VehicleSeat?): ()
        rememberParts(model)
        if seat and originalVehicleSeats[seat] == nil then
            originalVehicleSeats[seat] = {
                maxSpeed = seat.MaxSpeed,
                torque = seat.Torque,
                turnSpeed = seat.TurnSpeed,
            }
        end
        for candidate: VehicleSeat, original: VehicleSeatState in pairs(originalVehicleSeats) do
            if not candidate.Parent
                or (model and not candidate:IsDescendantOf(model)) then
                continue
            end
            candidate.MaxSpeed = original.maxSpeed * settings.multiplier
            candidate.Torque = original.torque * settings.multiplier
            candidate.TurnSpeed = original.turnSpeed * settings.multiplier
        end
    end

    local vehicleSpeed: any
    vehicleSpeed = framework.Categories.Movement:CreateModule({
        Name = "Vehicle Speed",
        Category = "Movement",
        Tooltip = "Multiplies the speed of the vehicle you are driving. Try "
            .. "Multiplier first, then Motors, Velocity and Seat.",
        Function = function(enabled: boolean): ()
            restoreVehicle()
            if not enabled then
                vehicleSpeed:SetStatus(nil)
                return
            end
            vehicleSpeed:SetStatus(string.lower(settings.mode))
            vehicleSpeed:Loop(function(): ()
                local assembly: BasePart?, model: Model?, seat: VehicleSeat? =
                    resolveVehicle()
                if not assembly then
                    return
                end
                if settings.mode == "Multiplier" then
                    boostVelocity(assembly :: BasePart, nil)
                elseif settings.mode == "Motors" then
                    boostMotors(model)
                elseif settings.mode == "Velocity" then
                    local direction: Vector3? = seat
                        and (seat :: VehicleSeat).CFrame.LookVector
                            * (seat :: VehicleSeat).ThrottleFloat
                        or nil
                    boostVelocity(assembly :: BasePart, direction)
                else
                    boostSeatProperties(model, seat)
                end
            end)
            vehicleSpeed:Clean(restoreVehicle)
        end,
    })

    vehicleSpeed:CreateDropdown({
        Name = "Mode",
        List = {"Multiplier", "Motors", "Velocity", "Seat"},
        Index = 1,
        Function = function(value: string): ()
            restoreVehicle()
            settings.mode = value
            if vehicleSpeed.Enabled then
                vehicleSpeed:SetStatus(string.lower(value))
            end
        end,
        Tooltip = "Multiplier preserves the vehicle's current steering; Motors "
            .. "drives wheel constraints; Velocity rewrites the chassis; Seat "
            .. "changes classic VehicleSeat properties.",
    })
    vehicleSpeed:CreateSlider({
        Name = "Multiplier",
        Min = 1,
        Max = 10,
        Default = settings.multiplier,
        Function = function(value: number): ()
            clearBoostHistory()
            settings.multiplier = value
        end,
        Tooltip = "A driver asks for 2x, not an absolute walking speed. The "
            .. "vehicle still supplies its own direction and base speed.",
    })
    vehicleSpeed:CreateSlider({
        Name = "Motor torque",
        Show = {Option = "Mode", Values = {"Motors"}},
        Min = 1000,
        Max = 250000,
        Default = settings.motorTorque,
        Function = function(value: number): ()
            settings.motorTorque = value
        end,
    })
    vehicleSpeed:CreateNote(
        "If one route is clamped, try the next. Every seat and motor property "
            .. "returns to the value this vehicle had before the module touched it."
    )

    activeCleanup = restoreVehicle
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
