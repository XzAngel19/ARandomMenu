--!strict
--
-- Headless tests: the visuals cards no suite had loaded.
--
-- Field of View, Fullbright, X-Ray and Zoom Unlocker. Each one borrows a
-- piece of the client — the camera, the lighting, the map's transparency, the
-- player's zoom bounds — and the third question is the whole suite: every
-- piece goes back to exactly what it was.
--
-- Runs from the split runner's context, or from run-b.luau on a fresh world.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    if host.Lighting == nil then
        host.Lighting = world.globals.game:GetService("Lighting")
    end

    local camera: any = world.globals.workspace.CurrentCamera

    local context: any = ctx.espContext
    if not context then
        local FrameworkFile: any = require("../../../src/core/Framework")
        Mock.inject(world, FrameworkFile.init)
        local framework: any = FrameworkFile.init(host)
        context = {framework = framework, entity = nil, weapons = nil, render = nil, host = host}
    end
    ctx.espContext = context

    local baseline: number = stub.taskCount()

    section("Field of View")

    camera.FieldOfView = 70
    local FovFile: any = require("../../../src/modules/Visuals/FieldOfView")
    Mock.inject(world, FovFile.init)
    local fov: any = FovFile.init(context)

    check("card is registered", fov.name == "FOV")
    check("option: Field of view",
        fov.options ~= nil and fov.options["Field of view"] ~= nil)

    fov.activate()
    stub.step(1 / 60)
    check("the camera is held at the slider value",
        camera.FieldOfView == fov.options["Field of view"].value,
        "fov is " .. tostring(camera.FieldOfView))
    fov.activate()
    check("and returns to the player's own on disable",
        camera.FieldOfView == 70)

    section("Fullbright")

    host.Lighting.Brightness = 1
    host.Lighting.ClockTime = 0
    local FullbrightFile: any = require("../../../src/modules/Visuals/Fullbright")
    Mock.inject(world, FullbrightFile.init)
    local fullbright: any = FullbrightFile.init(context)

    check("card is registered", fullbright.name == "Fullbright")
    for _, name: string in ipairs({"Brightness", "Clock time"}) do
        check("option: " .. name,
            fullbright.options ~= nil and fullbright.options[name] ~= nil)
    end

    fullbright.activate()
    stub.step(1 / 60)
    check("lighting is driven bright",
        host.Lighting.Brightness > 1 and host.Lighting.ClockTime ~= 0)
    fullbright.activate()
    check("and the game's lighting returns exactly",
        host.Lighting.Brightness == 1 and host.Lighting.ClockTime == 0)

    section("X-Ray")

    local mapPart: any = Mock.newInstance("Part")
    mapPart.Name = "Wall"
    mapPart.LocalTransparencyModifier = 0.1
    mapPart.Parent = world.globals.workspace
    local characterPart: any = world.localPlayer.Character:FindFirstChild("Head")

    local XRayFile: any = require("../../../src/modules/Visuals/XRay")
    Mock.inject(world, XRayFile.init)
    local xray: any = XRayFile.init(context)

    check("card is registered", xray.name == "X-Ray")

    xray.activate()
    check("map geometry fades from this client only",
        mapPart.LocalTransparencyModifier >= 0.72,
        "modifier is " .. tostring(mapPart.LocalTransparencyModifier))
    -- Untouched means zero, not nil: every BasePart answers this and Roblox
    -- defaults it to zero. The suite read nil while the stand-in was the only
    -- thing that ever left it unset.
    check("the local character stays solid",
        characterPart.LocalTransparencyModifier == 0,
        "modifier is " .. tostring(characterPart.LocalTransparencyModifier))
    xray.activate()
    check("and the map's own transparency returns exactly",
        mapPart.LocalTransparencyModifier == 0.1)

    section("Zoom Unlocker")

    local localPlayer: any = world.localPlayer
    localPlayer.CameraMinZoomDistance = 2
    localPlayer.CameraMaxZoomDistance = 128
    localPlayer.CameraMode = world.globals.Enum.CameraMode.LockFirstPerson

    local ZoomFile: any = require("../../../src/modules/Visuals/ZoomUnlocker")
    Mock.inject(world, ZoomFile.init)
    local zoom: any = ZoomFile.init(context)

    check("card is registered", zoom.name == "Zoom Unlocker")
    for _, name: string in ipairs({
        "Maximum distance",
        "Minimum distance",
        "Unlock forced first person",
    }) do
        check("option: " .. name, zoom.options ~= nil and zoom.options[name] ~= nil)
    end

    zoom.activate()
    stub.step(1 / 60)
    check("the zoom range opens to the sliders",
        localPlayer.CameraMaxZoomDistance == zoom.options["Maximum distance"].value
            and localPlayer.CameraMinZoomDistance
                == zoom.options["Minimum distance"].value)
    check("forced first person is unlocked",
        localPlayer.CameraMode == world.globals.Enum.CameraMode.Classic)
    zoom.activate()
    check("and every camera bound goes back to what it was",
        localPlayer.CameraMinZoomDistance == 2
            and localPlayer.CameraMaxZoomDistance == 128
            and localPlayer.CameraMode == world.globals.Enum.CameraMode.LockFirstPerson)

    check("nothing is left running", stub.taskCount() == baseline)

    -- Leave the shared world as the next suite expects it.
    camera.FieldOfView = 70
    localPlayer.CameraMode = nil
    mapPart.Parent = nil
end
