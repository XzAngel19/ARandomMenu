--!strict
--
-- Headless tests: movement cards on the kernel.
--
-- Fly, Physics Speed, Phase Dash and Infinite Jump build their panels through
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

    -- The shell publishes its palette and services to every downloaded file;
    -- the harness keeps them on the host only. Two lines make them globals
    -- again, the way the module environments see them.
    if world.globals.Theme == nil then
        world.globals.Theme = host.Theme
    end
    if world.globals.TweenService == nil then
        world.globals.TweenService = world.globals.game:GetService("TweenService")
    end

    -- The stand-in vector has arithmetic but not Lerp, which both speed
    -- engines smooth with. Patched here for the suites; belongs in the mock
    -- proper (asked for in the PR) the moment its owner can take it.
    do
        local vector3lib: any = world.globals.Vector3
        local originalNew: any = vector3lib.new
        local function withLerp(value: any): any
            if value ~= nil and value.Lerp == nil then
                function value:Lerp(other: any, alpha: number): any
                    return originalNew(
                        self.X + (other.X - self.X) * alpha,
                        self.Y + (other.Y - self.Y) * alpha,
                        self.Z + (other.Z - self.Z) * alpha
                    )
                end
            end
            return value
        end
        vector3lib.new = function(...: any): any
            return withLerp(originalNew(...))
        end
        withLerp(vector3lib.zero)
        withLerp(vector3lib.one)
    end

    -- The shell publishes these helpers; the harness host did not, because no
    -- module that needed them ran headless before this pass. Idempotent, so
    -- the shared runner can hand us a context that already has them.
    if not host.getCharacterParts then
        host.getCharacterParts = function(): (any, any, any)
            local character: any = world.localPlayer.Character
            return character,
                character and character:FindFirstChildOfClass("Humanoid"),
                character and character:FindFirstChild("HumanoidRootPart")
        end
    end
    if not host.state.onJumpRequest then
        local jumpCallbacks: {any} = {}
        world.jumpCallbacks = jumpCallbacks
        world.fireJumpRequest = function(): ()
            for _, callback: any in ipairs(table.clone(jumpCallbacks)) do
                callback()
            end
        end
        host.state.onJumpRequest = function(callback: any): any
            table.insert(jumpCallbacks, callback)
            return {
                Connected = true,
                Disconnect = function(self: any): ()
                    self.Connected = false
                    local index: number? = table.find(jumpCallbacks, callback)
                    if index then
                        table.remove(jumpCallbacks, index :: number)
                    end
                end,
            }
        end
    end

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
        }
    end
    ctx.espContext = context

    local function rows(name: string): any
        return host.state.hiddenOptionRows
            and host.state.hiddenOptionRows[name] == true
    end

    section("Fly")

    local FlyFile: any = require("../../../src/modules/Movement/Fly")
    Mock.inject(world, FlyFile.init)
    local fly: any = FlyFile.init(context)

    check("card is registered under its own name", fly.Name == "Fly")
    for _, name: string in ipairs({
        "Method",
        "Float",
        "Horizontal speed",
        "Vertical speed",
        "Advanced settings",
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

    check("the advanced block starts folded",
        rows("Response multiplier") and rows("Burst interval (s)")
            and rows("Wall check") and rows("PlatformStand")
            and rows("Face camera") and rows("Up key") and rows("Down key"),
        "a gated row is visible before Advanced settings is on")

    ctx.setOption(fly, "Advanced settings", true)
    check("the switch reveals the block it labels",
        not rows("Burst interval (s)") and not rows("Wall check"))
    ctx.setOption(fly, "Method", "Impulse")
    check("response stays hidden for an engine that does not smooth",
        rows("Response multiplier"),
        "Impulse is not in the Response rule's value list")
    ctx.setOption(fly, "Method", "Velocity")
    check("response appears for the engines that track it",
        not rows("Response multiplier"))
    ctx.setOption(fly, "Advanced settings", false)
    check("switching it off folds the whole block again",
        rows("Response multiplier") and rows("Burst interval (s)"))

    -- CFrame steering: the one engine whose loop needs neither Lerp nor
    -- ApplyImpulse, which the stand-in does not model.
    ctx.setOption(fly, "Method", "CFrame")

    local baseline: number = stub.taskCount()
    fly.Feature.activate()
    check("a session takes exactly one task", stub.taskCount() == baseline + 1)
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

    section("Physics Speed")

    local PhysicsFile: any = require("../../../src/modules/Movement/PhysicsSpeed")
    Mock.inject(world, PhysicsFile.init)
    local physics: any = PhysicsFile.init(context)

    check("the card no longer shares Speed's name",
        physics.Name == "Physics Speed",
        "a second card named Speed collided with it in the config keys")
    for _, name: string in ipairs({
        "Mode",
        "Speed",
        "Advanced settings",
        "Vertical speed",
        "PlatformStand",
        "Custom properties",
        "Motor torque",
        "Wall check",
        "Acceleration",
        "Burst interval (s)",
        "Air control %",
        "Sprint multiplier",
        "Sprint key",
        "Preserve momentum",
        "Auto jump",
        "Auto-jump velocity",
    }) do
        check("option: " .. name, physics.Options[name] ~= nil)
    end

    check("the advanced rows start folded",
        rows("Vertical speed") and rows("Acceleration") and rows("Sprint key"))
    check("burst interval hides while the mode cannot burst", rows("Burst interval (s)"))
    ctx.setOption(physics, "Advanced settings", true)
    check("adaptive owns acceleration and air control",
        not rows("Acceleration") and not rows("Air control %"))
    ctx.setOption(physics, "Mode", "Pulse")
    check("pulse swaps them for the burst interval",
        rows("Acceleration") and rows("Air control %") and not rows("Burst interval (s)"))
    ctx.setOption(physics, "Custom properties", false)
    check("motor torque only exists while properties are customised",
        rows("Motor torque"))
    ctx.setOption(physics, "Auto jump", true)
    check("the jump velocity follows its switch",
        not rows("Auto-jump velocity"))

    ctx.setOption(physics, "Mode", "Adaptive")
    ctx.setOption(physics, "Custom properties", true)
    physics.Feature.activate()
    check("a session takes exactly one task",
        stub.taskCount() == baseline + 1)
    stub.step(1 / 60)
    stub.step(1 / 60)

    -- Wall-clock, not the mocked os.clock. Raise only with a comment saying
    -- what got more expensive.
    local BUDGET_PHYSICS_FRAME_SECONDS: number = 0.010
    local physicsPerFrame: number = ctx.measureFrames(stub.step, 20)
    check(
        "Physics Speed stays inside the per-frame time budget",
        physicsPerFrame <= BUDGET_PHYSICS_FRAME_SECONDS,
        string.format("%.4fs/frame", physicsPerFrame)
    )

    physics.Feature.activate()
    check("disabling releases the task", stub.taskCount() == baseline)

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
