--!strict
--
-- Headless tests: the protection cards no suite had loaded.
--
-- Anti-Fling, Anti-Void and SafeWalk. The three questions again, with the
-- third one doing the work: Anti-Fling has to put the character back where
-- it stood and stand down during a fling of your own, and Anti-Void has to
-- leave no platform behind once its three seconds are up.
--
-- Runs from the split runner's context, or from run-b.luau on a fresh world.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    local vector3: any = world.vector3
    local character: any = world.localPlayer.Character
    local humanoid: any = character:FindFirstChildOfClass("Humanoid")
    local root: any = character:FindFirstChild("HumanoidRootPart")
    humanoid.FloorMaterial = world.globals.Enum.Material.Plastic
    humanoid.ChangeState = function(_self: any, _state: any): () end

    local context: any = ctx.espContext
    if not context then
        local FrameworkFile: any = require("../../../src/core/Framework")
        Mock.inject(world, FrameworkFile.init)
        local framework: any = FrameworkFile.init(host)
        context = {framework = framework, entity = nil, weapons = nil, render = nil, host = host}
    end
    ctx.espContext = context

    local baseline: number = stub.taskCount()

    section("Anti-Fling")

    local AntiFlingFile: any = require("../../../src/modules/Protection/AntiFling")
    Mock.inject(world, AntiFlingFile.init)
    local antiFling: any = AntiFlingFile.init(context)

    check("card is registered", antiFling.name == "Anti-Fling")
    check("option: Velocity limit",
        antiFling.options ~= nil and antiFling.options["Velocity limit"] ~= nil)

    antiFling.activate()
    stub.step(1 / 60)
    check("anti-fling reports that it is armed", antiFling.status == "standing by")
    local safeCFrame: any = root.CFrame

    root.CFrame = world.globals.CFrame.new(vector3(400, 50, 400))
    root.AssemblyLinearVelocity = vector3(5000, 5000, 5000)
    stub.step(1 / 60)
    check("an extreme velocity is killed and the body returns to safety",
        root.AssemblyLinearVelocity.Magnitude == 0
            and root.CFrame.Position.X == safeCFrame.Position.X,
        "position is " .. tostring(root.CFrame.Position.X))
    check("anti-fling distinguishes an active block",
        antiFling.status == "blocking", tostring(antiFling.status))

    -- Your own fling is deliberate; Anti-Fling used to read a global that was
    -- nil and never stood down for it. This is that regression.
    host.state.flingRunning = true
    root.AssemblyLinearVelocity = vector3(5000, 5000, 5000)
    stub.step(1 / 60)
    check("it stands down while a fling of your own is running",
        root.AssemblyLinearVelocity.Magnitude > 0)
    host.state.flingRunning = nil

    root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    antiFling.activate()
    check("disabling releases the task", stub.taskCount() == baseline)

    section("Anti-Void")

    local AntiVoidFile: any = require("../../../src/modules/Protection/AntiVoid")
    Mock.inject(world, AntiVoidFile.init)
    local antiVoid: any = AntiVoidFile.init(context)

    check("card is registered", antiVoid.name == "Anti-Void")

    antiVoid.activate()
    -- One grounded frame to record where ground was, then a lethal fall.
    root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
    stub.step(1 / 60)
    humanoid.FloorMaterial = world.globals.Enum.Material.Air
    root.CFrame = world.globals.CFrame.new(vector3(0, -200, 0))
    root.Position = vector3(0, -200, 0)
    root.AssemblyLinearVelocity = vector3(10, -80, 10)
    stub.step(1.2)
    check("a lethal fall is caught: the fall velocity is taken away",
        root.AssemblyLinearVelocity.Y == 0
            and root.AssemblyLinearVelocity.X == 10 * 0.25,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))
    check("and the rescue platform is gone again",
        world.globals.workspace:FindFirstChild("RTM_AntiVoidPlatform") == nil)

    -- A short fall near ground rescues nothing.
    root.CFrame = world.globals.CFrame.new(vector3(0, -3, 0))
    root.Position = vector3(0, -3, 0)
    root.AssemblyLinearVelocity = vector3(0, -10, 0)
    stub.step(1.2)
    check("an ordinary hop is left alone",
        root.AssemblyLinearVelocity.Y == -10)
    antiVoid.activate()
    check("disabling releases the task", stub.taskCount() == baseline)

    section("SafeWalk")

    local SafeWalkFile: any = require("../../../src/modules/Protection/SafeWalk")
    Mock.inject(world, SafeWalkFile.init)
    local safeWalk: any = SafeWalkFile.init(context)

    check("card is registered", safeWalk.name == "SafeWalk")
    check("option: Edge look-ahead",
        safeWalk.options ~= nil and safeWalk.options["Edge look-ahead"] ~= nil)

    humanoid.MoveDirection = vector3(0, 0, -1)
    humanoid.FloorMaterial = world.globals.Enum.Material.Plastic
    safeWalk.activate()

    world.raycastResult = nil
    root.AssemblyLinearVelocity = vector3(12, 0, -8)
    stub.step(1 / 60)
    check("no ground ahead stops the walk before the edge",
        root.AssemblyLinearVelocity.X == 0 and root.AssemblyLinearVelocity.Z == 0)

    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = vector3(0, -3, -3),
        Normal = vector3(0, 1, 0),
        Distance = 3,
    }
    root.AssemblyLinearVelocity = vector3(12, 0, -8)
    stub.step(1 / 60)
    check("ground ahead keeps the walk",
        root.AssemblyLinearVelocity.X == 12 and root.AssemblyLinearVelocity.Z == -8)
    safeWalk.activate()
    check("disabling releases the task", stub.taskCount() == baseline)

    -- Leave the shared character as the next suite expects it.
    humanoid.MoveDirection = vector3(0, 0, 0)
    humanoid.FloorMaterial = world.globals.Enum.Material.Air
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
    world.raycastResult = nil
end
