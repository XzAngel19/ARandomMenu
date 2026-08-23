--!strict
--
-- Headless tests: movement cards on the kernel.
--
-- Fly, Vehicle Speed, Phase Dash and Infinite Jump build their panels through
-- the framework now, so the checks assert the Show rules each one declared (a
-- row is on screen only while its mode owns it) and the enable/disable edges
-- the kernel took over: a session ends with the task list it started with and
-- the properties it touched put back.
--
-- Runs from the split runner's context, or from run-b.luau on a fresh world.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    -- The stand-in humanoid does not model movement state; the modules only
    -- read these, so plain values are enough.
    local character: any = world.localPlayer.Character
    local humanoid: any = character:FindFirstChildOfClass("Humanoid")
    local root: any = character:FindFirstChild("HumanoidRootPart")
    humanoid.MoveDirection = world.vector3(0, 0, 0)
    humanoid.WalkSpeed = 16
    humanoid.FloorMaterial = world.globals.Enum.Material.Air
    humanoid.ChangeState = function(_self: any, _state: any): () end
    local vector3: any = world.vector3

    -- A module context with the real kernel, built the way the shell builds
    -- one — unless the shared runner already built it for every suite.
    local context: any = ctx.espContext
    if not context then
        local FrameworkFile: any = require("../../../src/core/Framework")
        Mock.inject(world, FrameworkFile.init)
        local framework: any = FrameworkFile.init(host)
        local EntityFile: any = require("../../../src/library/Entity")
        Mock.inject(world, EntityFile.init)
        local entity: any = EntityFile.init(host)
        context = {
            framework = framework,
            entity = entity,
            weapons = nil,
            render = nil,
            host = host,
            services = host.services,
        }
    end
    ctx.espContext = context

    local function rows(name: string): any
        return host.state.hiddenOptionRows
            and host.state.hiddenOptionRows[name] == true
    end

    section("Flight")

    local FlyFile: any = require("../../../src/modules/Movement/Fly")
    Mock.inject(world, FlyFile.init)
    local fly: any = FlyFile.init(context)

    check("card is registered under its Wurst name", fly.Name == "Flight")
    for _, name: string in ipairs({
        "Method",
        "Float",
        "Horizontal speed",
        "Vertical speed",
        "Response multiplier",
        "Burst interval (s)",
        "Wall check",
        "PlatformStand",
        "Face camera",
        "Up key",
        "Down key",
    }) do
        check("option: " .. name, fly.Options[name] ~= nil)
    end

    check("presentation-only Advanced settings is gone",
        fly.Options["Advanced settings"] == nil)
    check("ordinary controls are available without an extra gate",
        not rows("Burst interval (s)") and not rows("Wall check")
            and not rows("PlatformStand") and not rows("Up key"))
    ctx.setOption(fly, "Method", "Impulse")
    check("response stays hidden for an engine that does not smooth",
        rows("Response multiplier"),
        "Impulse is not in the Response rule's value list")
    ctx.setOption(fly, "Method", "Velocity")
    check("response appears for the engines that track it",
        not rows("Response multiplier"))

    -- CFrame steering: the one engine whose loop needs neither Lerp nor
    -- ApplyImpulse, which the stand-in does not model.
    ctx.setOption(fly, "Method", "CFrame")

    local baseline: number = stub.taskCount()
    fly.Feature.activate()
    check("a session takes exactly one task", stub.taskCount() == baseline + 1)
    check("the HUD status names the active flight engine",
        fly.Status == "CFrame", tostring(fly.Status))
    stub.step(1 / 60)
    stub.step(1 / 60)
    check("the flight loop runs against the stand-in character",
        root.AssemblyLinearVelocity ~= nil)

    -- Wall-clock, not the mocked os.clock. Raise only with a comment saying
    -- what got more expensive.
    local BUDGET_FLY_FRAME_SECONDS: number = 0.010
    local flyPerFrame: number = ctx.measureFrames(stub.step, 20)
    check(
        "Fly stays inside the per-frame time budget",
        flyPerFrame <= BUDGET_FLY_FRAME_SECONDS,
        string.format("%.4fs/frame", flyPerFrame)
    )

    fly.Feature.activate()
    check("disabling releases the task", stub.taskCount() == baseline)
    check("disable zeroes the leftover velocity",
        root.AssemblyLinearVelocity.X == 0 and root.AssemblyLinearVelocity.Y == 0)

    -- WalkSpeed is the one method that borrows a property, so it is the one
    -- that has to give it back.
    ctx.setOption(fly, "Method", "WalkSpeed")
    fly.Feature.activate()
    stub.step(1 / 60)
    check("the WalkSpeed engine writes the slider speed",
        humanoid.WalkSpeed == fly.Options["Horizontal speed"].Value,
        "walkspeed is " .. tostring(humanoid.WalkSpeed))
    fly.Feature.activate()
    check("and restores what the character had",
        humanoid.WalkSpeed == 16, "walkspeed is " .. tostring(humanoid.WalkSpeed))

    section("Vehicle Speed")

    local VehicleFile: any = require("../../../src/modules/Movement/VehicleSpeed")
    Mock.inject(world, VehicleFile.init)
    local vehicle: any = VehicleFile.init(context)

    check("the card is registered", vehicle.Name == "Vehicle Speed")
    for _, name: string in ipairs({"Mode", "Multiplier", "Motor torque"}) do
        check("option: " .. name, vehicle.Options[name] ~= nil)
    end
    for _, removed: string in ipairs({
        "Speed", "Vertical speed", "PlatformStand", "Air control %", "Sprint key", "Auto jump",
    }) do
        check("character option removed: " .. removed, vehicle.Options[removed] == nil)
    end
    check("the four routes are ordered from least to most invasive",
        table.concat(vehicle.Feature.options["Mode"].list or {}, ",")
            == "Multiplier,Motors,Velocity,Seat")
    check("motor torque hides outside the motor route", rows("Motor torque"))
    ctx.setOption(vehicle, "Mode", "Motors")
    check("motor torque appears for the motor route", not rows("Motor torque"))
    ctx.setOption(vehicle, "Mode", "Multiplier")

    local vehicleModel: any = Mock.newInstance("Model")
    vehicleModel.Name = "TestVehicle"
    vehicleModel.Parent = world.workspace
    local chassis: any = Mock.newInstance("Part")
    chassis.Name = "Chassis"
    chassis.Parent = vehicleModel
    local seat: any = Mock.newInstance("VehicleSeat")
    seat.Name = "DriverSeat"
    seat.MaxSpeed = 40
    seat.Torque = 1200
    seat.TurnSpeed = 1.5
    seat.ThrottleFloat = 1
    seat.AssemblyRootPart = chassis
    seat.Parent = vehicleModel
    world.globals.Enum.ActuatorType = world.globals.Enum.ActuatorType or {Motor = "Motor"}
    local hinge: any = Mock.newInstance("HingeConstraint")
    hinge.ActuatorType = world.globals.Enum.ActuatorType.Motor
    hinge.AngularVelocity = 10
    hinge.MotorMaxTorque = 100
    hinge.Parent = vehicleModel
    humanoid.SeatPart = seat

    chassis.AssemblyLinearVelocity = world.vector3(0, 0, -10)
    local vehicleBaseline: number = stub.taskCount()
    vehicle.Feature.activate()
    check("vehicle status reports the route", vehicle.Status == "multiplier")
    stub.step(1 / 60)
    check("the current vehicle speed is multiplied", chassis.AssemblyLinearVelocity.Z == -20)
    stub.step(1 / 60)
    check("the multiplier does not compound frame over frame", chassis.AssemblyLinearVelocity.Z == -20)
    chassis.AssemblyLinearVelocity = world.vector3(20, 0, 0)
    stub.step(1 / 60)
    check("the multiplier keeps the vehicle's steering direction",
        chassis.AssemblyLinearVelocity.X > 0 and math.abs(chassis.AssemblyLinearVelocity.Z) < 0.001)
    vehicle.Feature.activate()
    check("disabling releases the task", stub.taskCount() == vehicleBaseline)

    ctx.setOption(vehicle, "Mode", "Motors")
    ctx.setOption(vehicle, "Multiplier", 2)
    ctx.setOption(vehicle, "Motor torque", 1000)
    vehicle.Feature.activate()
    stub.step(1 / 60)
    check("the motor route multiplies wheel speed without compounding",
        hinge.AngularVelocity == 20 and hinge.MotorMaxTorque == 1000)
    stub.step(1 / 60)
    check("motor speed remains stable on the next frame", hinge.AngularVelocity == 20)
    vehicle.Feature.activate()
    check("seat and motor originals are restored exactly",
        hinge.AngularVelocity == 10 and hinge.MotorMaxTorque == 100
            and seat.MaxSpeed == 40 and seat.Torque == 1200 and seat.TurnSpeed == 1.5)

    humanoid.SeatPart = nil
    root.AssemblyRootPart = root
    root.AssemblyLinearVelocity = world.vector3(3, 4, 5)
    local originalWalkSpeed: number = humanoid.WalkSpeed
    ctx.setOption(vehicle, "Mode", "Multiplier")
    vehicle.Feature.activate()
    stub.step(1 / 60)
    check("an unseated character is never treated as a vehicle",
        root.AssemblyLinearVelocity.X == 3 and root.AssemblyLinearVelocity.Y == 4
            and root.AssemblyLinearVelocity.Z == 5 and humanoid.WalkSpeed == originalWalkSpeed)
    vehicle.Feature.activate()
    root.AssemblyRootPart = nil
    root.AssemblyLinearVelocity = world.vector3(0, 0, 0)
    vehicleModel:Destroy()

    section("Phase Dash")

    local DashFile: any = require("../../../src/modules/Movement/PhaseDash")
    Mock.inject(world, DashFile.init)
    local dash: any = DashFile.init(context)

    for _, name: string in ipairs({
        "Mode",
        "Dash distance",
        "Cooldown",
        "Exit speed",
        "Slide speed",
        "Collision padding",
        "Flash duration (s)",
        "Preserve velocity",
    }) do
        check("option: " .. name, dash.Options[name] ~= nil)
    end

    check("slide speed hides while the dash blinks", rows("Slide speed"))
    check("blink's own rows are out",
        not rows("Dash distance") and not rows("Collision padding"))
    ctx.setOption(dash, "Mode", "Slide")
    check("slide swaps the panel's rows",
        not rows("Slide speed") and rows("Dash distance"))

    local binding: any = world.bindings and world.bindings["Phase Dash"]
    check("the dash key is the card's own slot", binding ~= nil)
    world.raycastResult = nil
    ctx.setOption(dash, "Mode", "Blink")
    dash.Feature.activate()
    check("the dash key is inert while the card is off", (function(): boolean
        root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
        dash.Feature.activate() -- on, then straight back off
        binding.press()
        return root.CFrame.Position.Z == 0
    end)())
    dash.Feature.activate()
    check("phase dash reports its active engine", dash.Status == "Blink")
    root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
    binding.press()
    check("one press blinks the full distance forward",
        root.CFrame.Position.Z == -dash.Options["Dash distance"].Value,
        "landed at " .. tostring(root.CFrame.Position.Z))
    root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
    binding.press()
    check("the cooldown holds the second press",
        root.CFrame.Position.Z == 0)
    stub.step(1)
    root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
    binding.press()
    check("and releases it once it has passed",
        root.CFrame.Position.Z == -dash.Options["Dash distance"].Value)

    section("Infinite Jump")

    local JumpFile: any = require("../../../src/modules/Movement/InfiniteJump")
    Mock.inject(world, JumpFile.init)
    local jump: any = JumpFile.init(context)

    for _, name: string in ipairs({
        "Mode",
        "Jump power",
        "Jump interval (s)",
        "Rise speed",
    }) do
        check("option: " .. name, jump.Options[name] ~= nil)
    end

    check("rise speed hides while jumps launch", rows("Rise speed"))
    ctx.setOption(jump, "Mode", "Rise")
    check("rise owns its speed and drops the others",
        not rows("Rise speed") and rows("Jump power") and rows("Jump interval (s)"))
    ctx.setOption(jump, "Mode", "Fall")
    check("fall cancelling never launches, so there is no power to set",
        rows("Jump power"))
    ctx.setOption(jump, "Mode", "Normal")

    jump.Feature.activate()
    check("infinite jump reports its active engine", jump.Status == "Normal")
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    world.fireJumpRequest()
    check("a jump request launches at the slider power",
        root.AssemblyLinearVelocity.Y == jump.Options["Jump power"].Value,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))
    world.fireJumpRequest()
    check("the interval floor holds the second request",
        root.AssemblyLinearVelocity.Y == jump.Options["Jump power"].Value,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))
    stub.step(0.2)
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    world.fireJumpRequest()
    check("and lets the next one through once it has passed",
        root.AssemblyLinearVelocity.Y == jump.Options["Jump power"].Value)
    jump.Feature.activate()
    check("disabling releases the task", stub.taskCount() == baseline)

    -- Leave the shared character as the next suite expects it.
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    humanoid.WalkSpeed = 16
end
