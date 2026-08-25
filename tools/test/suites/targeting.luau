--!strict
--
-- Targeting and camera-assist contracts.
--
-- The selector is allowed to read entities and raycast for visibility, but it
-- must not mutate camera, tools, remotes or input. Aim Assist is the only
-- module in this pair that writes the local camera.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local entity: any = ctx.entity
    local enemy: any = ctx.enemy
    local ally: any = ctx.ally
    local framework: any = ctx.framework
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Targeting service")

    local TargetingFile: any = require("../../../src/library/Targeting")
    Mock.inject(world, TargetingFile.init)
    local targeting: any = TargetingFile.init(host)
    local candidates: {any} = targeting:List(entity, {
        FOV = 220,
        MaxDistance = 100,
        TargetPart = "Head",
        TeamCheck = true,
        VisibilityCheck = false,
        Priority = "Cursor",
    })
    check("Targeting selects an enemy", #candidates == 1 and candidates[1].player == enemy)
    check("Targeting skips teammates", candidates[1] ~= nil and candidates[1].player ~= ally)
    check("Targeting returns screen-space distance", candidates[1] ~= nil
        and type(candidates[1].cursorDistance) == "number")

    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = world.vector3(0, 2, -5),
    }
    local blocked: {any} = targeting:List(entity, {
        FOV = 220,
        MaxDistance = 100,
        TargetPart = "Head",
        TeamCheck = true,
        VisibilityCheck = true,
    })
    check("visibility policy rejects an obstructed target", #blocked == 0)
    world.raycastResult = nil

    host.services.protectedTargets.setProvider(function(player: any): boolean
        return player == enemy
    end)
    local protected: {any} = targeting:List(entity, {
        FOV = 220,
        MaxDistance = 100,
        TargetPart = "Head",
        VisibilityCheck = false,
    })
    check("Friend List policy is shared by Targeting", #protected == 0)
    host.services.protectedTargets.setProvider(nil)
    TargetingFile.destroy()

    section("Aim Assist")

    local targetingAgain: any = TargetingFile.init(host)
    local AimFile: any = require("../../../src/modules/Combat/AimAssist")
    Mock.inject(world, AimFile.init)
    local camera: any = world.workspace.CurrentCamera
    local originalLook: any = camera.CFrame.LookVector
    local context: any = {
        framework = framework,
        entity = entity,
        weapons = nil,
        render = nil,
        libraries = {targeting = targetingAgain},
        host = host,
        services = host.services,
    }
    local aim: any = AimFile.init(context)
    check("Aim Assist card is registered", aim ~= nil and aim.Name == "Aim Assist")
    check("Aim Assist has no hook option", aim.Options["Hook"] == nil)
    host.state.visible = false
    host.state.keyCaptureCallback = nil
    host.state.waitingForKey = false
    world.focusedTextBox = nil
    local clicksBefore: number = world.mouseClicks or 0
    aim:Toggle(true)
    stub.step(0.016)
    local changed: boolean = camera.CFrame.LookVector ~= originalLook
    check("Aim Assist only moves the local camera", changed)
    check("Aim Assist reports the selected target", string.find(tostring(aim.Status), "Enemy", 1, true) ~= nil,
        tostring(aim.Status))
    host.services.activity.set("mvsdSilentAim", true)
    stub.step(0.016)
    check("Aim Assist yields to a game-specific aim adapter", aim.Status == "paused",
        tostring(aim.Status))
    host.services.activity.set("mvsdSilentAim", false)
    aim:Toggle(false)
    check("Aim Assist disable removes its frame task", aim.Enabled == false)
    check("Aim Assist does not activate tools", (world.mouseClicks or 0) == clicksBefore)
    AimFile.destroy()
    TargetingFile.destroy()

    section("Learning")

    local LearningFile: any = require("../../../src/modules/Utility/Learning")
    Mock.inject(world, LearningFile.init)
    local learning: any = LearningFile.init({
        framework = framework,
        host = host,
        services = host.services,
    })
    check("Learning card is registered", learning ~= nil and learning.Name == "Learning")
    check("Learning is a group card", learning.Feature.kind == "group")
    local callback: any = learning.Feature.options["Capture now"]
        and learning.Feature.options["Capture now"].run
    check("Learning exposes a manual capture action", type(callback) == "function")
    local before: number = world.screenCaptures
    if callback then
        callback()
    end
    check("Learning captures only after the action", world.screenCaptures == before + 1)
    local foundMetadata: boolean = false
    for path: string, contents: any in pairs(world.files) do
        if string.find(path, "Learning/", 1, true)
            and string.find(path, "%.json$")
            and type(contents) == "string" then
            foundMetadata = true
            break
        end
    end
    check("Learning writes a local metadata sidecar", foundMetadata)
    LearningFile.destroy()
end
