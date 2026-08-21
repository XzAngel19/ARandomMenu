--!strict
--
-- Headless tests: No Fall.
--
-- The card moved onto the kernel so the Impact brake and the State trick can
-- say which mode owns them, and the loop itself runs against a stand-in
-- character falling onto a stand-in floor: the brake clamps the landing to
-- the slider speed in Impact, and never touches velocity in State.
--
-- Runs from the split runner's context, or from run-b.luau on a fresh world.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    local character: any = world.localPlayer.Character
    local humanoid: any = character:FindFirstChildOfClass("Humanoid")
    local root: any = character:FindFirstChild("HumanoidRootPart")
    humanoid.ChangeState = function(_self: any, _state: any): () end

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

    local function hidden(name: string): boolean
        return host.state.hiddenOptionRows
            and host.state.hiddenOptionRows[name] == true
    end

    section("No Fall")

    local NoFallFile: any = require("../../../src/modules/Protection/NoFall")
    Mock.inject(world, NoFallFile.init)
    local noFall: any = NoFallFile.init(context)

    check("card is registered", noFall.Name == "No Fall")
    for _, name: string in ipairs({
        "Mode",
        "Safe landing speed",
        "Reset fall record",
        "Ground scan",
    }) do
        check("option: " .. name, noFall.Options[name] ~= nil)
    end

    check("both modes start with both of their rows",
        not hidden("Safe landing speed") and not hidden("Reset fall record"))
    ctx.setOption(noFall, "Mode", "Impact")
    check("impact owns the brake, not the record reset",
        not hidden("Safe landing speed") and hidden("Reset fall record"))
    ctx.setOption(noFall, "Mode", "State")
    check("state owns the record reset, not the brake",
        hidden("Safe landing speed") and not hidden("Reset fall record"))
    check("ground scan belongs to both", hidden("Ground scan") == false)
    ctx.setOption(noFall, "Mode", "Impact")

    -- A fall: airborne, fast, and a floor the raycast finds right below.
    local vector3: any = world.vector3
    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = vector3(0, 0, 0),
    }
    humanoid.FloorMaterial = world.globals.Enum.Material.Air
    root.AssemblyLinearVelocity = vector3(0, -80, 0)

    local baseline: number = stub.taskCount()
    noFall.Feature.activate()
    check("a session takes exactly one task", stub.taskCount() == baseline + 1)
    stub.step(1 / 60)
    check("impact brakes the fall to the slider speed",
        root.AssemblyLinearVelocity.Y
            == -noFall.Options["Safe landing speed"].Value,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))

    ctx.setOption(noFall, "Mode", "State")
    root.AssemblyLinearVelocity = vector3(0, -80, 0)
    stub.step(1 / 60)
    check("state mode never touches the velocity",
        root.AssemblyLinearVelocity.Y == -80,
        "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))

    noFall.Feature.activate()
    check("disabling releases the task", stub.taskCount() == baseline)
    check("no state change is left pending after disable",
        world.clock > 0)

    -- Leave the shared character as the next suite expects it.
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    humanoid.FloorMaterial = nil
    world.raycastResult = nil
end
