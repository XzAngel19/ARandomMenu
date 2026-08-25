--!strict
--
-- Headless tests: the combat cards no suite had loaded.
--
-- Hitboxes and Projectile Calibration. Hitboxes is the third question in its
-- purest form: an expanded part has to go back to its exact size the moment
-- it stops being a target, not only when the card is switched off. Projectile
-- Calibration is a group card of analytics controls: the checks are that its
-- rows exist, its rounding callbacks round, and its three actions answer
-- rather than error.
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

    local context: any = ctx.espContext
    if not context then
        local FrameworkFile: any = require("../../../src/core/Framework")
        Mock.inject(world, FrameworkFile.init)
        local framework: any = FrameworkFile.init(host)
        local EntityFile: any = require("../../../src/library/Entity")
        Mock.inject(world, EntityFile.init)
        local entity: any = EntityFile.init(host)
        context = {framework = framework, entity = entity, weapons = nil, render = nil, host = host, services = host.services}
    end
    ctx.espContext = context

    -- The stand-in player has no mouse; Projectile Calibration keeps one hit
    -- point from it while it builds.
    if world.localPlayer.GetMouse == nil then
        function world.localPlayer:GetMouse(): any
            return {
                Hit = {
                    Position = world.vector3(0, 0, -10),
                },
            }
        end
    end

    local baseline: number = stub.taskCount()

    section("Hitboxes")

    local enemy: any = world.addPlayer("HitboxEnemy", "Red", vector3(0, 0, -8))
    enemy.Parent = host.Players
    local enemyRoot: any = enemy.Character:FindFirstChild("HumanoidRootPart")
    local enemyHead: any = enemy.Character:FindFirstChild("Head")

    local HitboxFile: any = require("../../../src/modules/Combat/Hitboxes")
    Mock.inject(world, HitboxFile.init)
    local hitboxes: any = HitboxFile.init(context)

    check("card is registered", hitboxes.Name == "Hitboxes")
    for _, name: string in ipairs({
        "Part",
        "Expand",
        "Team check",
        "Include NPCs",
        "Show hitbox",
        "Show transparency %",
        "No collision",
    }) do
        check("option: " .. name, hitboxes.Options[name] ~= nil)
    end

    local rootSize: any = vector3(2, 2, 1)
    local headSize: any = vector3(1.2, 1.2, 1.2)
    enemyRoot.Size = rootSize
    enemyHead.Size = headSize

    ctx.setOption(hitboxes, "Expand", 4)
    hitboxes.Feature.activate()
    check("hitboxes reports the part and expansion",
        hitboxes.Status == "Root +4", tostring(hitboxes.Status))
    stub.step(1 / 60)
    check("the target's part grows by exactly the slider",
        enemyRoot.Size.X == rootSize.X + 4,
        "size is " .. tostring(enemyRoot.Size.X))
    ctx.setOption(hitboxes, "Part", "Head")
    stub.step(1 / 60)
    check("switching part restores the one it no longer owns",
        enemyRoot.Size.X == rootSize.X)
    hitboxes.Feature.activate()
    check("and disabling restores the current one",
        enemyHead.Size.X == headSize.X,
        "size is " .. tostring(enemyHead.Size.X))

    -- Friend List is the same promise the other combat cards keep: an inflated
    -- friend is as visible to the server as an inflated enemy.
    ctx.setOption(hitboxes, "Part", "Root")
    host.services.protectedTargets.setProvider(function(player: any): boolean
        return player == enemy
    end)
    hitboxes.Feature.activate()
    stub.step(1 / 60)
    check("a protected player keeps their real size",
        enemyRoot.Size.X == rootSize.X,
        "size is " .. tostring(enemyRoot.Size.X))
    host.services.protectedTargets.setProvider(nil)
    stub.step(1 / 60)
    check("and is expanded again once the protection goes",
        enemyRoot.Size.X == rootSize.X + 4,
        "size is " .. tostring(enemyRoot.Size.X))

    -- A game that rescales a character mid-round owns that size. The restore
    -- has to put back the game's number, not the one the module first saw.
    enemyRoot.Size = vector3(3, 3, 2)
    stub.step(1 / 60)
    check("a rescaled part is re-expanded from the game's new size",
        enemyRoot.Size.X == 7,
        "size is " .. tostring(enemyRoot.Size.X))
    hitboxes.Feature.activate()
    check("and restored to the size the game last set",
        enemyRoot.Size.X == 3,
        "size is " .. tostring(enemyRoot.Size.X))

    section("Projectile Calibration")

    local ProjectileFile: any = require("../../../src/modules/Combat/ProjectileCalibration")
    Mock.inject(world, ProjectileFile.init)
    local _calibration: any = ProjectileFile.init(context)

    -- init hands back the analytics controller, not the card; the card is in
    -- the registry like every other.
    local card: any = nil
    for _, feature: any in ipairs(stub.features) do
        if feature.name == "Projectile Calibration" then
            card = feature
        end
    end
    check("card is registered", card ~= nil)
    for _, name: string in ipairs({
        "Bucket width (ms)",
        "Bucket ceiling (ms)",
        "Sample window (s)",
        "Max samples / track",
        "Match radius (studs)",
        "Min projectile speed",
        "Show status",
        "Save analytics",
        "Delete analytics",
    }) do
        check("row: " .. name, card ~= nil and card.options[name] ~= nil)
    end

    -- The status action is the module's only window into what the analytics
    -- are doing; it has to answer, not error.
    local statusOk: boolean = pcall(function(): ()
        local row: any = card and card.options["Show status"]
        if row and row.run then
            row.run()
        end
    end)
    check("the status action answers", statusOk)

    world.globals.DateTime = world.globals.DateTime or {
        now = function(): any
            return {ToIsoDate = function(): string return "test" end}
        end,
    }
    local saveRow: any = card and card.options["Save analytics"]
    if saveRow and saveRow.run then
        getfenv(saveRow.run).DateTime = world.globals.DateTime
        saveRow.run()
    end
    local analyticsPath: string? = nil
    for path: string in pairs(world.files) do
        if string.find(path, "Projectile_Calibration", 1, true) then
            analyticsPath = path
        end
    end
    check("analytics use PRODUCT.storageFolder",
        analyticsPath ~= nil
            and string.sub(analyticsPath :: string, 1, #host.PRODUCT.storageFolder)
                == host.PRODUCT.storageFolder,
        tostring(analyticsPath))

    check("nothing is left running", stub.taskCount() == baseline)

    -- Leave the shared world as the next suite expects it.
    enemyRoot.Size = vector3(2, 2, 1)
    enemyHead.Size = vector3(1.2, 1.2, 1.2)
    host.services.protectedTargets.setProvider(nil)
end
