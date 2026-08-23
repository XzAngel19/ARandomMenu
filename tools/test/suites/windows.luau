--!strict
--
-- Headless tests: the window manager.
--
-- The behaviours are decided in the prototype and already live on
-- `state.windows`: Create, Adopt, Get, Raise, Reclamp, SetMenuVisible.
-- Collapse, pin, snap-at-eight and "nothing fully off-screen" are the
-- contract the ClickGUI rebuild has to keep.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Windows")

    local WindowFile: any = require("../../../src/library/WindowManager")
    Mock.inject(world, WindowFile.init)
    local windows: any = WindowFile.init(host)
    check("the manager is published on state.windows", rawequal(windows, host.state.windows))
    for _, name: string in ipairs({
        "Create",
        "Adopt",
        "Get",
        "Raise",
        "Reclamp",
        "SetMenuVisible",
    }) do
        check("surface: " .. name, type(windows[name]) == "function")
    end

    local vec2: any = world.globals.Vector2.new
    local mouse: any = world.globals.Enum.UserInputType.MouseButton1
    local move: any = world.globals.Enum.UserInputType.MouseMovement

    local function sizeOf(window: any, width: number, height: number): ()
        -- The mock does not keep AbsoluteSize in step with Size; snap and
        -- clamp read AbsoluteSize, so the suite has to tell the truth.
        window.root.Size = world.globals.UDim2.fromOffset(width, height)
        window.root.AbsoluteSize = vec2(width, height)
    end

    local function createWindow(id: string, x: number, y: number, width: number, height: number): any
        local window: any = windows.Create({
            id = id,
            title = id,
            size = vec2(width, height),
            position = vec2(x, y),
        })
        sizeOf(window, width, height)
        window:SetVisible(true)
        return window
    end

    local combat: any = createWindow("combat", 100, 120, 186, 220)
    local movement: any = createWindow("movement", 320, 120, 186, 220)
    local visuals: any = createWindow("visuals", 540, 120, 186, 220)
    check("Create returns three windows",
        windows.Get("combat") == combat
            and windows.Get("movement") == movement
            and windows.Get("visuals") == visuals)
    for _, window: any in ipairs({combat, movement, visuals}) do
        local outline: any = window.root:FindFirstChild("WindowOutline")
        check(
            "every managed window owns the same visible outline: " .. window.id,
            outline ~= nil and outline.Transparency <= 0.08
        )
    end
    check("Get misses an unknown id", windows.Get("no-such-window") == nil)

    local function offset(window: any): (number, number)
        return window.root.Position.X.Offset, window.root.Position.Y.Offset
    end

    local combatX: number, combatY: number = offset(combat)
    check("Create honours the requested position",
        combatX == 100 and combatY == 120,
        tostring(combatX) .. "," .. tostring(combatY))

    -- Collapse: the body hides and the title bar stays.
    check("a new window is expanded", combat.collapsed == false)
    check("the body is on screen while expanded", combat.body.Visible ~= false)
    combat:SetCollapsed(true)
    check("collapse is recorded", combat.collapsed == true)
    check("collapse hides the body", combat.body.Visible == false)
    check("collapse is persisted",
        host.configData.ui.windows.combat.collapsed == true)

    -- Pin: the window survives the GUI being closed.
    movement:SetPinned(true)
    check("pin is recorded", movement.pinned == true)
    check("pin is persisted", host.configData.ui.windows.movement.pinned == true)
    windows.SetMenuVisible(false)
    check("a pinned window stays visible when the menu hides",
        movement.root.Visible == true)
    check("an unpinned window hides with the menu",
        visuals.root.Visible == false)
    -- SetMenuVisible(false) hid the unpinned ones; snap needs them on
    -- screen, and the show path does not restore wasVisible yet.
    combat:SetVisible(true)
    movement:SetVisible(true)
    visuals:SetVisible(true)

    -- Raise: last raised sits on top.
    local beforeZ: number = combat.root.ZIndex
    windows.Raise("combat")
    check("Raise puts the window above the others",
        combat.root.ZIndex > movement.root.ZIndex
            and combat.root.ZIndex > visuals.root.ZIndex,
        "combat " .. tostring(combat.root.ZIndex)
            .. " movement " .. tostring(movement.root.ZIndex)
            .. " before " .. tostring(beforeZ))

    -- Drag. The header is the handle; UserInputService carries the motion.
    local function drag(window: any, fromX: number, fromY: number, toX: number, toY: number): ()
        local handle: any = window.header or window.root
        handle.InputBegan:Fire({
            UserInputType = mouse,
            Position = vec2(fromX, fromY),
        })
        host.UserInputService.InputChanged:Fire({
            UserInputType = move,
            Position = vec2(toX, toY),
        })
        host.UserInputService.InputEnded:Fire({
            UserInputType = mouse,
            Position = vec2(toX, toY),
        })
    end

    -- Snap: within eight pixels of another window's edge the drag lands
    -- flush; at nine it does not. Combat is at x=100, width=186, so its
    -- right edge is 286. Visuals is dragged so its left edge approaches.
    visuals.root.Position = world.globals.UDim2.fromOffset(500, 120)
    sizeOf(visuals, 186, 220)
    -- wanted x = start + pointer - dragStart. Start at 500; a pointer
    -- delta of (286+8)-500 = -206 lands 8px from the edge.
    drag(visuals, 500, 120, 500 - 206, 120)
    local snappedX: number = visuals.root.Position.X.Offset
    check("snap at eight pixels lands flush on the other window",
        snappedX == 286,
        "landed at " .. tostring(snappedX))

    visuals.root.Position = world.globals.UDim2.fromOffset(500, 120)
    -- Nine pixels off: delta (286+9)-500 = -205.
    drag(visuals, 500, 120, 500 - 205, 120)
    local unsnappedX: number = visuals.root.Position.X.Offset
    check("snap at nine pixels does not pull",
        unsnappedX == 295,
        "landed at " .. tostring(unsnappedX))

    -- Viewport edge, same eight-vs-nine. Clamp's left line is MARGIN=6.
    visuals.root.Position = world.globals.UDim2.fromOffset(40, 120)
    drag(visuals, 40, 120, 40 - (40 - 14), 120)
    -- wanted x = 14; abs(14-6)=8, snaps to 6.
    check("snap at eight pixels lands flush on the viewport",
        visuals.root.Position.X.Offset == 6,
        "landed at " .. tostring(visuals.root.Position.X.Offset))

    visuals.root.Position = world.globals.UDim2.fromOffset(40, 120)
    drag(visuals, 40, 120, 40 - (40 - 15), 120)
    check("nine pixels off the viewport does not snap",
        visuals.root.Position.X.Offset == 15,
        "landed at " .. tostring(visuals.root.Position.X.Offset))

    -- Nothing fully off-screen: a saved position past the edge is pulled in.
    visuals.root.Position = world.globals.UDim2.fromOffset(-400, 4000)
    windows.Reclamp()
    local clampedX: number, clampedY: number = offset(visuals)
    local screen: any = world.camera.ViewportSize
    check("Reclamp never leaves a window fully off-screen",
        clampedX >= 0
            and clampedY >= 0
            and clampedX < screen.X
            and clampedY < screen.Y,
        tostring(clampedX) .. "," .. tostring(clampedY))

    -- Serialise, tear down, boot again from the same config.
    local saved: any = host.configData.ui.windows
    check("collapse survived in the config", saved.combat.collapsed == true)
    check("pin survived in the config", saved.movement.pinned == true)
    local savedVisualsX: number = saved.visuals.x

    WindowFile.destroy()
    check("destroy unpublishes state.windows", host.state.windows == nil)

    local restored: any = WindowFile.init(host)
    local combat2: any = restored.Create({
        id = "combat",
        title = "Combat",
        size = vec2(186, 220),
        position = vec2(14, 14),
    })
    local movement2: any = restored.Create({
        id = "movement",
        title = "Movement",
        size = vec2(186, 220),
        position = vec2(14, 14),
    })
    local visuals2: any = restored.Create({
        id = "visuals",
        title = "Visuals",
        size = vec2(186, 220),
        position = vec2(14, 14),
    })
    check("a second boot restores collapse", combat2.collapsed == true)
    check("a second boot restores pin", movement2.pinned == true)
    check("a second boot restores position",
        visuals2.root.Position.X.Offset == savedVisualsX,
        "got " .. tostring(visuals2.root.Position.X.Offset)
            .. " saved " .. tostring(savedVisualsX))

    WindowFile.destroy()
end
