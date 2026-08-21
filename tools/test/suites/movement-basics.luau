--!strict
--
-- Headless tests: the movement cards no suite had loaded.
--
-- Speed, Freeze Movements, High Jump, Jump Power, Noclip and Spider. Three
-- questions each: do the options exist under the names the card says, does
-- switching it on do what the card promises, and does switching it off put
-- the world back exactly as it was. The third one is where the bugs live.
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
    humanoid.MoveDirection = vector3(0, 0, 0)
    humanoid.WalkSpeed = 16
    humanoid.JumpPower = 50
    humanoid.AutoRotate = true
    humanoid.UseJumpPower = false
    root.Anchored = false
    humanoid.FloorMaterial = world.globals.Enum.Material.Plastic
    local stateChanges: {any} = {}
    humanoid.ChangeState = function(_self: any, state: any): ()
        table.insert(stateChanges, state)
    end

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

    if not host.state.movementFeatures then
        host.state.movementFeatures = {}
    end
    if not host.state.universalScroll then
        host.state.universalScroll = host.create("Frame", {Name = "UniversalScroll"})
    end

    local baseline: number = stub.taskCount()

    section("Speed")

    local SpeedFile: any = require("../../../src/modules/Movement/Speed")
    Mock.inject(world, SpeedFile.init)
    local speed: any = SpeedFile.init(context)

    check("card is registered", speed.Name == "Speed")
    for _, name: string in ipairs({
        "Mode",
        "Speed",
        "Wall check",
        "Burst delay",
        "Auto jump",
    }) do
        check("option: " .. name, speed.Options[name] ~= nil)
    end

    local function hidden(name: string): boolean
        return host.state.hiddenOptionRows
            and host.state.hiddenOptionRows[name] == true
    end
    check("wall check hides for the modes that cannot pass through one",
        hidden("Wall check"))
    check("burst delay hides outside Teleport", hidden("Burst delay"))

    speed.Options["Mode"].Value = "WalkSpeed"
    speed:RefreshVisibility()
    speed.Feature.activate()
    stub.step(1 / 60)
    check("the WalkSpeed engine writes the slider value",
        humanoid.WalkSpeed == speed.Options["Speed"].Value,
        "walkspeed is " .. tostring(humanoid.WalkSpeed))
    check("the HUD status names the live engine and speed",
        speed.Status == "WalkSpeed 32", tostring(speed.Status))
    speed.Feature.activate()
    check("the HUD status clears with the module", speed.Status == nil)
    check("and puts the character's own speed back",
        humanoid.WalkSpeed == 16, "walkspeed is " .. tostring(humanoid.WalkSpeed))

    section("Freeze Movements")

    local FreezeFile: any = require("../../../src/modules/Movement/FreezeMovements")
    Mock.inject(world, FreezeFile.init)
    local freeze: any = FreezeFile.init(context)

    check("card is registered", freeze.name == "Freeze Movements")
    check("option: Freeze mode",
        freeze.options ~= nil and freeze.options["Freeze mode"] ~= nil)

    freeze.activate()
    stub.step(1 / 60)
    check("anchor mode stops the character cold",
        humanoid.WalkSpeed == 0 and humanoid.JumpPower == 0
            and humanoid.AutoRotate == false and root.Anchored == true)
    freeze.activate()
    check("and returns every field it touched",
        humanoid.WalkSpeed == 16 and humanoid.JumpPower == 50
            and humanoid.AutoRotate == true and root.Anchored == false)

    section("High Jump")

    local HighJumpFile: any = require("../../../src/modules/Movement/HighJump")
    Mock.inject(world, HighJumpFile.init)
    local highJump: any = HighJumpFile.init(context)

    check("card is registered", highJump.name == "High Jump")
    check("option: Jump velocity",
        highJump.options ~= nil and highJump.options["Jump velocity"] ~= nil)

    root.AssemblyLinearVelocity = vector3(4, 0, -2)
    stateChanges.stateChangesCleared = true
    stateChanges = {}
    highJump.activate()
    check("one press launches at the slider velocity",
        root.AssemblyLinearVelocity.Y == highJump.options["Jump velocity"].value,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))
    check("horizontal velocity is kept",
        root.AssemblyLinearVelocity.X == 4 and root.AssemblyLinearVelocity.Z == -2)
    check("the humanoid is left in freefall so the landing reads right",
        #stateChanges == 1
            and stateChanges[1] == world.globals.Enum.HumanoidStateType.Freefall)

    section("Jump Power")

    local JumpPowerFile: any = require("../../../src/modules/Movement/JumpPower")
    Mock.inject(world, JumpPowerFile.init)
    local jumpPower: any = JumpPowerFile.init(context)

    check("card is registered", jumpPower.name == "Jump Power")
    check("option: Power",
        jumpPower.options ~= nil and jumpPower.options["Power"] ~= nil)

    jumpPower.activate()
    stub.step(1 / 60)
    check("the jump is rewritten through the humanoid's own fields",
        humanoid.UseJumpPower == true
            and humanoid.JumpPower == jumpPower.options["Power"].value,
        "jump power is " .. tostring(humanoid.JumpPower))
    jumpPower.activate()
    check("and both fields go back to what they were",
        humanoid.UseJumpPower == false and humanoid.JumpPower == 50)

    section("Noclip")

    local NoclipFile: any = require("../../../src/modules/Movement/Noclip")
    Mock.inject(world, NoclipFile.init)
    local noclip: any = NoclipFile.init(context)

    check("card is registered", noclip.name == "Noclip")
    local head: any = character:FindFirstChild("Head")
    root.CanCollide = true
    head.CanCollide = false

    noclip.activate()
    stub.step(1 / 60)
    check("every part of the character stops colliding",
        root.CanCollide == false and head.CanCollide == false)
    noclip.activate()
    check("each part gets its own value back, not a blanket true",
        root.CanCollide == true and head.CanCollide == false)

    section("Spider")

    local SpiderFile: any = require("../../../src/modules/Movement/Spider")
    Mock.inject(world, SpiderFile.init)
    local spider: any = SpiderFile.init(context)

    check("card is registered", spider.name == "Spider")
    for _, name: string in ipairs({"Mode", "Climb speed", "Climb state"}) do
        check("option: " .. name, spider.options ~= nil
            and spider.options[name] ~= nil)
    end

    humanoid.MoveDirection = vector3(0, 0, -1)
    spider.activate()
    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = vector3(0, 0, -2),
        Normal = vector3(0, 0, 1),
        Distance = 1.5,
    }
    stub.step(1 / 60)
    check("walking into a wall climbs it",
        root.AssemblyLinearVelocity.Y == spider.options["Climb speed"].value,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))

    world.raycastResult = nil
    root.AssemblyLinearVelocity = vector3(3, 30, -3)
    stub.step(1 / 60)
    check("the climb stops the instant the wall does",
        root.AssemblyLinearVelocity.Y == 0,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))
    spider.activate()
    check("disabling releases the task", stub.taskCount() == baseline)

    -- Leave the shared character as the next suite expects it.
    humanoid.MoveDirection = vector3(0, 0, 0)
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    root.CanCollide = nil
    head.CanCollide = nil
    root.Anchored = false
    humanoid.UseJumpPower = false
    humanoid.JumpPower = 50
    world.raycastResult = nil
end
