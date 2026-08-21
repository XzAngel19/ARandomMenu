--!strict
--
-- Headless tests: the floating layer.
--
-- Loaded by tools/test/run.luau. Favourites, the overlay menu and the four
-- overlays reach the rest of the menu through one table, so the checks follow
-- that table rather than the instance tree.
--
return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Floating windows")

    -- Eighteen hundred lines that lived in the shell and that nothing has ever
    -- run: the favourites list, the overlay menu and the four overlays. The
    -- whole subsystem reaches the rest of the menu through one table, so the
    -- checks follow that table rather than the instance tree.
    local FloatingFile: any = require("../../../src/library/FloatingWindows")
    Mock.inject(world, FloatingFile.init)
    local tasksBefore: number = stub.taskCount()
    local floating: any = FloatingFile.init(host)

    check("the library publishes its surface", floating ~= nil
        and rawequal(floating, host.state.floatingUi))
    for _, name: string in ipairs({
        "registerFeature",
        "unregisterFeature",
        "refreshFeature",
        "toggleFavorite",
        "openSettings",
        "reclamp",
    }) do
        check("surface: " .. name, type(floating[name]) == "function")
    end

    -- Four overlays, each with a window and a settings window of its own.
    for _, id: string in ipairs({"SessionInfo", "TextGUI", "TargetInfo", "Radar"}) do
        check("overlay: " .. id, floating.overlays[id] ~= nil)
    end

    -- A card registers itself as it is built, and favouriting it is what puts
    -- a row in the list. The config is the thing that has to remember it.
    local card: any = {
        configKey = "Universal.Fly",
        name = "Fly",
        enabled = false,
        categoryName = "Movement",
    }
    floating.registerFeature(card)
    check("registering a card files it", floating.favorites["Universal.Fly"] == card)
    check("registering does not favourite it",
        host.configData.ui.favorites["Universal.Fly"] == nil)

    local favouriteSavesBefore: number = host.saves
    floating.toggleFavorite(card)
    check("favouriting is remembered",
        host.configData.ui.favorites["Universal.Fly"] == true)
    check("favouriting saves the config", host.saves > favouriteSavesBefore)
    floating.toggleFavorite(card)
    check("unfavouriting clears the entry rather than storing false",
        host.configData.ui.favorites["Universal.Fly"] == nil,
        tostring(host.configData.ui.favorites["Universal.Fly"]))

    -- A card that goes away with its module must not leave a row behind.
    floating.unregisterFeature(card)
    check("unregistering forgets the card",
        floating.favorites["Universal.Fly"] == nil)

    -- Every window is draggable and closable, so every one of them has to be
    -- inside the viewport after a resize; `reclamp` is what a viewport change
    -- calls, and it must not throw on a window nobody has opened.
    local reclampOk: boolean = pcall(floating.reclamp)
    check("reclamping every window is safe", reclampOk)

    local openOk: boolean = pcall(floating.openSettings, "Radar")
    check("a settings window opens on demand", openOk
        and floating.settingsWindows.Radar ~= nil)

    -- Two per-frame loops: the overlay redraw and the profile card's clock.
    -- In the shell they ran for the life of the menu and were swept up when
    -- the task manager was destroyed. A library is started and stopped on its
    -- own, so it has to hand them back — and this is the check that noticed it
    -- did not.
    check("the layer takes its per-frame loops", stub.taskCount() > tasksBefore,
        "before: " .. tostring(tasksBefore) .. " after: " .. tostring(stub.taskCount()))

    -- Wall-clock, not the mocked os.clock. Raise only with a comment saying
    -- what got more expensive. Two loops (overlay redraw and the profile
    -- clock) ran for the life of the menu with no ceiling of their own.
    local BUDGET_FLOATING_FRAME_SECONDS: number = 0.010
    local floatingPerFrame: number = ctx.measureFrames(stub.step, 20)
    check(
        "the floating layer stays inside the per-frame time budget",
        floatingPerFrame <= BUDGET_FLOATING_FRAME_SECONDS,
        string.format("%.4fs/frame", floatingPerFrame)
    )

    FloatingFile.destroy()
    check("and gives every one of them back on destroy",
        stub.taskCount() == tasksBefore,
        "left: " .. tostring(stub.taskCount() - tasksBefore))
end
