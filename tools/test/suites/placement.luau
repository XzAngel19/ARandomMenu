--!strict
--
-- Headless tests: WindowManager placement after A's FindFreeRect.
--
-- Official 7.19/7.54.1 parks a settings window beside its category
-- (right, then left, then below). The port searches those anchors
-- then a grid, with a 10 px gap, and reflows after the real measure.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Placement")

    local WindowFile: any = require("../../../src/library/WindowManager")
    if WindowFile.Initialized then
        WindowFile.destroy()
    end
    Mock.inject(world, WindowFile.init)
    local windows: any = WindowFile.init(host)

    -- Earlier ClickGui suites leave a UIScale on the shared PopupLayer
    -- (ClickGui's fit-to-1600×900 is 0.8 on the harness 1280×720). Pin
    -- it to 1 so logical == screen for the viewport assertions, then
    -- drive the scale cases through the same instance.
    local scaleNode: any = host.PopupLayer
        and host.PopupLayer:FindFirstChild("ClickGuiScale")
    if scaleNode == nil then
        scaleNode = host.create("UIScale", {
            Parent = host.PopupLayer,
            Name = "ClickGuiScale",
            Scale = 1,
        })
    end
    scaleNode.Scale = 1

    check("FindFreeRect is published", type(windows.FindFreeRect) == "function")
    check("PlaceWindow is published", type(windows.PlaceWindow) == "function")
    check("ReflowWindow is published", type(windows.ReflowWindow) == "function")
    check("MeasureWindow is published", type(windows.MeasureWindow) == "function")
    check("LogicalViewport is published", type(windows.LogicalViewport) == "function")

    local vec2: any = world.globals.Vector2.new
    local function make(id: string, x: number, y: number, w: number, h: number): any
        local window: any = windows.Create({
            id = id,
            title = id,
            size = vec2(w, h),
            position = vec2(x, y),
        })
        window.root.Size = world.globals.UDim2.fromOffset(w, h)
        window.fullHeight = h
        window:SetVisible(true)
        return window
    end

    local function aabb(a: any, b: any, gap: number): boolean
        local ax, ay = a.root.Position.X.Offset, a.root.Position.Y.Offset
        local aw, ah = a.root.Size.X.Offset, a.root.Size.Y.Offset
        local bx, by = b.root.Position.X.Offset, b.root.Position.Y.Offset
        local bw, bh = b.root.Size.X.Offset, b.root.Size.Y.Offset
        return ax < bx + bw + gap
            and bx < ax + aw + gap
            and ay < by + bh + gap
            and by < ay + ah + gap
    end

    local function inside(window: any, vw: number, vh: number): boolean
        local x, y = window.root.Position.X.Offset, window.root.Position.Y.Offset
        local w, h = window.root.Size.X.Offset, window.root.Size.Y.Offset
        return x >= 6 and y >= 6 and x + w <= vw - 6 and y + h <= vh - 6
    end

    -- Feature settings + management windows all go through the same verbs.
    for _, kind in ipairs({
        "FeatureSettings_Sample",
        "UISettings",
        "WurstLogoSettings",
        "HackListSettings",
        "Keybinds",
        "Profiles",
        "WurstOptions",
    }) do
        check("placement verbs exist for " .. kind, type(windows.PlaceWindow) == "function")
    end

    local combat: any = make("ClickGui_Combat", 10, 64, 200, 150)
    local slot: any = windows.FindFreeRect(vec2(200, 80), combat)
    check(
        "FindFreeRect parks to the right of the category when there is room",
        slot.X >= combat.root.Position.X.Offset + combat.root.Size.X.Offset,
        tostring(slot.X) .. "," .. tostring(slot.Y)
    )
    check("the preferred slot stays inside the default viewport", slot.X >= 6 and slot.Y >= 6)

    local settings: any = make("FeatureSettings_Aura", slot.X, slot.Y, 200, 80)
    windows.PlaceWindow(settings, {anchor = combat})
    check(
        "PlaceWindow does not overlap the category (gap 10)",
        not aabb(combat, settings, 10),
        tostring(settings.root.Position.X.Offset) .. "," .. tostring(settings.root.Position.Y.Offset)
    )

    -- Deferred resize: grow the settings window and reflow.
    settings.root.Size = world.globals.UDim2.fromOffset(200, 180)
    settings.fullHeight = 180
    windows.ReflowWindow(settings)
    check(
        "after ReflowWindow the grown settings still miss the category",
        not aabb(combat, settings, 10)
    )
    check(
        "after ReflowWindow the window is still inside 1280x720",
        inside(settings, 1280, 720)
    )

    -- Second settings window must not share an origin or an AABB.
    local other: any = make("FeatureSettings_Other", 10, 64, 200, 90)
    windows.PlaceWindow(other, {anchor = combat, force = true})
    windows.ReflowWindow(other)
    check(
        "two placed settings are not superimposed",
        other.root.Position.X.Offset ~= settings.root.Position.X.Offset
            or other.root.Position.Y.Offset ~= settings.root.Position.Y.Offset
    )
    check(
        "two placed settings have zero AABB intersection after reflow",
        not aabb(settings, other, 0)
    )

    -- Manual move wins; reflow only clamps.
    settings.userMoved = true
    local parkedX: number = 40
    local parkedY: number = 40
    settings.root.Position = world.globals.UDim2.fromOffset(parkedX, parkedY)
    windows.ReflowWindow(settings)
    check(
        "ReflowWindow leaves a user-moved window where it is (if on-screen)",
        settings.root.Position.X.Offset == parkedX
            and settings.root.Position.Y.Offset == parkedY
    )

    -- Saved position off-screen is pulled in.
    settings.root.Position = world.globals.UDim2.fromOffset(-400, 4000)
    windows.ClampWindow(settings)
    local clampedX: number = settings.root.Position.X.Offset
    local clampedY: number = settings.root.Position.Y.Offset
    check(
        "ClampWindow pulls an off-screen window back",
        clampedX >= 0
            and clampedY >= 0
            and clampedX < 1280
            and clampedY < 720,
        tostring(clampedX) .. "," .. tostring(clampedY)
    )

    -- Viewports.
    for _, size in ipairs({
        {1600, 900},
        {1366, 768},
        {1280, 560},
        {2560, 1080},
        {390, 844},
    }) do
        world.camera.ViewportSize = vec2(size[1], size[2])
        windows.Reclamp()
        local vp: any = windows.LogicalViewport()
        check(
            "LogicalViewport tracks " .. tostring(size[1]) .. "x" .. tostring(size[2]),
            math.abs(vp.X - size[1]) < 1 and math.abs(vp.Y - size[2]) < 1,
            tostring(vp.X) .. "x" .. tostring(vp.Y)
        )
        check(
            "combat stays inside " .. tostring(size[1]) .. "x" .. tostring(size[2]),
            inside(combat, size[1], size[2])
        )
    end
    world.camera.ViewportSize = vec2(1280, 720)

    -- Scales 0.7 / 1 / 1.25 / 1.6: a placed window must sit inside
    -- whatever logical viewport that factor produces.
    for _, scale in ipairs({0.7, 1.0, 1.25, 1.6}) do
        scaleNode.Scale = scale
        local vp: any = windows.LogicalViewport()
        local grown: any = make(
            "ScaleProbe" .. tostring(scale),
            20,
            80,
            200,
            100
        )
        windows.PlaceWindow(grown, {force = true})
        windows.ReflowWindow(grown)
        check(
            "a window placed at scale " .. tostring(scale) .. " stays in the logical viewport",
            grown.root.Position.X.Offset >= 6
                and grown.root.Position.Y.Offset >= 6
                and grown.root.Position.X.Offset + grown.root.Size.X.Offset <= vp.X - 6
                and grown.root.Position.Y.Offset + grown.root.Size.Y.Offset <= vp.Y - 6,
            "vp=" .. tostring(vp.X) .. "x" .. tostring(vp.Y)
        )
        grown:Destroy()
    end
    scaleNode.Scale = 1

    -- BringToFront stays under the pill (240).
    windows.BringToFront(combat)
    check(
        "a raised window root stays below the pill (Z 240)",
        combat.root.ZIndex < 240,
        tostring(combat.root.ZIndex)
    )
    check(
        "a raised window root stays below the tooltip (Z 250)",
        combat.root.ZIndex < 250
    )

    WindowFile.destroy()
end
