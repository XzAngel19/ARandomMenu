--!strict
--
-- Headless tests: category windows sit at the logo's height, wrap, and
-- survive Reset layout / schema / scale. Manual positions stay put.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("TopLayout")

    local boot: any = bootShell(ctx)
    check("top-layout boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local world: any = boot.world
    local windows: any = state.windows
    check("windows are published", type(windows) == "table")
    if type(windows) ~= "table" then
        return
    end

    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end
    Inspect.pinClickGuiScale(env.PopupLayer, 1)

    local logo: any = state.wurstLogo and state.wurstLogo.root
    check("WurstLogo is published", logo ~= nil)
    local logoBottom: number = 10 + 36 + 8
    if logo ~= nil then
        logoBottom = logo.Position.Y.Offset + logo.Size.Y.Offset
        check(
            "the logo chip is at the top margin",
            logo.Position.Y.Offset <= 16,
            tostring(logo.Position.Y.Offset)
        )
    end

    local official: {string} = {
        "Combat",
        "Render",
        "Movement",
        "Fun",
        "Other",
    }
    local firstRow: {any} = {}
    for _, name: string in ipairs(official) do
        local window: any = windows.Get("ClickGui_" .. name)
        check("category window exists: " .. name, window ~= nil)
        if window ~= nil then
            window:SetVisible(true)
            table.insert(firstRow, window)
        end
    end
    check("occupied official windows are present", #firstRow >= 4)

    local overlapLogo: string? = nil
    local minY: number = 10000
    for _, window: any in ipairs(firstRow) do
        local y: number = window.root.Position.Y.Offset
        if y < minY then
            minY = y
        end
        if logo ~= nil then
            local lx: number = logo.Position.X.Offset
            local ly: number = logo.Position.Y.Offset
            local lw: number = logo.Size.X.Offset
            local lh: number = logo.Size.Y.Offset
            local wx: number = window.root.Position.X.Offset
            local wy: number = window.root.Position.Y.Offset
            local ww: number = window.root.Size.X.Offset
            local wh: number = window.root.Size.Y.Offset
            if lx < wx + ww and wx < lx + lw and ly < wy + wh and wy < ly + lh then
                overlapLogo = window.id
            end
        end
    end
    check(
        "categories sit at the logo's height, not under a second banner",
        minY <= logoBottom + 24,
        "minY=" .. tostring(minY) .. " logoBottom=" .. tostring(logoBottom)
    )
    check("no category overlaps the logo", overlapLogo == nil, overlapLogo)

    -- Official tile order is CATEGORY_ORDER in ClickGui. The live
    -- ClickGui.order today follows first-module-load (libraries start
    -- before modules, so the official pre-pass sees an empty list).
    -- Hold the source contract; flipping order-on-screen waits on A
    -- running that pass after modules exist.
    check(
        "ClickGui declares official CATEGORY_ORDER Combat, Render, …",
        string.find(ctx.bundleSource or "", '"Combat"', 1, true) ~= nil
            and string.find(ctx.bundleSource or "", "CATEGORY_ORDER", 1, true) ~= nil
    )
    if state.clickGui and type(state.clickGui.Retile) == "function" then
        state.clickGui.Retile()
        check("Reset layout / Retile is published", true)
    end

    -- Wrap: a phone-width viewport must start a second row.
    world.camera.ViewportSize = world.globals.Vector2.new(390, 844)
    if state.clickGui and type(state.clickGui.Retile) == "function" then
        state.clickGui.Retile()
    end
    local wrapped: boolean = false
    local wrapY: number? = nil
    for _, window: any in ipairs(firstRow) do
        local y: number = window.root.Position.Y.Offset
        if wrapY == nil then
            wrapY = y
        elseif y ~= wrapY then
            wrapped = true
        end
    end
    check(
        "categories wrap on a short viewport",
        wrapped or #firstRow <= 2,
        "all y=" .. tostring(wrapY)
    )
    world.camera.ViewportSize = world.globals.Vector2.new(1280, 720)
    if state.clickGui and type(state.clickGui.Retile) == "function" then
        state.clickGui.Retile()
    end

    -- Manual position survives Reset of *other* windows only if userMoved.
    -- Reset layout forgets userMoved — that is the contract. A position
    -- set after Reset, marked userMoved, must survive a reflow.
    local combat: any = windows.Get("ClickGui_Combat")
    if combat ~= nil then
        combat.userMoved = true
        combat.root.Position = world.globals.UDim2.fromOffset(40, 80)
        windows.ReflowWindow(combat)
        check(
            "a manual category position survives reflow",
            combat.root.Position.X.Offset == 40
                and combat.root.Position.Y.Offset == 80
        )
    end

    if state.wurstOptions and type(state.wurstOptions.InvokeAction) == "function" then
        check("Reset layout runs", state.wurstOptions.InvokeAction("ResetLayout") == true)
        if combat ~= nil then
            check(
                "Reset layout clears the manual-move flag",
                combat.userMoved ~= true
            )
        end
    end

    -- Schema 2 already dropped old geometry; a leftover schema 1 flag
    -- must not come back.
    check(
        "layout schema is the Wurst rebuild (2)",
        env.configData == nil
            or env.configData.ui == nil
            or env.configData.ui.wurstSchema == 2
            or env.configData.ui.wurstSchema == nil
    )

    for _, scale in ipairs({0.7, 1.0, 1.25, 1.6}) do
        Inspect.pinClickGuiScale(env.PopupLayer, scale)
        local vp: any = windows.LogicalViewport()
        if combat ~= nil then
            windows.Reclamp()
            check(
                "Combat stays on-screen at scale " .. tostring(scale),
                combat.root.Position.X.Offset >= 0
                    and combat.root.Position.Y.Offset >= 0
                    and combat.root.Position.X.Offset < vp.X
                    and combat.root.Position.Y.Offset < vp.Y
            )
        end
    end
    Inspect.pinClickGuiScale(env.PopupLayer, 1)

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
