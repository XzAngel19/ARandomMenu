--!strict
--
-- Headless tests: entity.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Entity library")

    local EntityFile: any = require("../../../src/library/Entity")
    Mock.inject(world, EntityFile.init)
    local entity: any = EntityFile.init(host)

    local enemy: any = world.addPlayer("Enemy", "Red", world.vector3(0, 0, -30))
    local ally: any = world.addPlayer("Ally", "Blue", world.vector3(10, 0, -10))
    -- Forced: the mocked clock is frozen between steps, and Refresh coalesces
    -- calls that land inside the same frame.
    entity:Refresh(true)

    check("list excludes the local player", #entity.List == 2,
        "found " .. tostring(#entity.List))
    check("enemy is not friendly", entity:Get(enemy).IsFriendly == false)
    check("ally is friendly", entity:Get(ally).IsFriendly == true)
    check("distance is measured", entity:Get(enemy).Distance == 30,
        tostring(entity:Get(enemy).Distance))

    local bones: {any} = entity:Rig(entity:Get(enemy))
    check("R15 rig resolves bones", #bones == 14, "found " .. tostring(#bones))

    world.raycastResult = nil
    check("no obstruction means visible", entity:VisibleFrom(entity:Get(enemy)) == true)
    world.raycastResult = {Instance = Mock.newInstance("Part"), Position = world.vector3(0, 0, -5)}
    check("obstruction hides the target", entity:VisibleFrom(entity:Get(enemy)) == false)
    world.raycastResult = nil

    local closest: any = entity:ClosestToRay(
        world.vector3(0, 0, 0),
        world.vector3(0, 0, -1),
        {IgnoreWalls = true}
    )
    check("closest to ray skips teammates", closest ~= nil and closest.Player == enemy)

    -- Player ESP -----------------------------------------------------------------

    ctx.EntityFile = EntityFile
    ctx.entity = entity
    ctx.enemy = enemy
    ctx.ally = ally
end
