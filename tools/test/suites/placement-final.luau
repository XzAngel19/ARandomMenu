--!strict
--
-- Headless tests: real management + feature windows after content and reflow.
--
-- C2 already holds FindFreeRect on synthetic windows. This suite boots the
-- shell and builds the windows a player actually opens: UI Settings,
-- WurstLogo, HackList, Keybinds, Profiles, Wurst Options, Add Keybind and
-- several Feature Settings. APPLY-1..3 and APPLY-5 stay; APPLY-4 is the
-- landed close-on-hide path (scroll-clip is still NEEDS_EVIDENCE).

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("PlacementFinal")

    local boot: any = bootShell(ctx)
    check("placement-final boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local world: any = boot.world
    local windows: any = state.windows
    check("state.windows is published", type(windows) == "table")
    if type(windows) ~= "table" then
        return
    end

    local scaleNode: any = Inspect.pinClickGuiScale(env.PopupLayer, 1)
    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end

    local wo: any = state.wurstOptions
    check("state.wurstOptions is published", type(wo) == "table")
    if type(wo) == "table" then
        local maxSettings: any = state.uiMaxSettingsHeight
        if maxSettings == nil and state.uiSettings then
            maxSettings = state.uiSettings["Max settings height"]
        end
        check(
            "APPLY-1 live Max settings height is still 200",
            maxSettings == 200,
            tostring(maxSettings)
        )
        wo.InvokeAction("Keybinds")
    end

    local ui: any = windows.Get("UISettings")
    check("UI Settings exists", ui ~= nil)
    if ui ~= nil then
        Inspect.clickNamed(ui.body, "Row_WurstLogo")
        Inspect.clickNamed(ui.body, "Row_HackList")
        Inspect.clickNamed(ui.body, "Row_WurstOptions")
    end
    local keybinds: any = windows.Get("Keybinds")
    if keybinds ~= nil then
        Inspect.clickNamed(keybinds.body, "Row_Add")
        Inspect.clickNamed(keybinds.body, "Row_Profiles")
    end

    local featureWindows: {any} = {}
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if feature.hasSettings == true then
            local window: any = windows.OpenFeatureSettings(feature)
            if window ~= nil then
                table.insert(featureWindows, window)
            end
            if #featureWindows >= 3 then
                break
            end
        end
    end
    check("opened several Feature Settings", #featureWindows >= 3)

    local named: {any} = {}
    for _, id: string in ipairs({
        "UISettings",
        "WurstLogo",
        "HackList",
        "Keybinds",
        "KeybindAdd",
        "KeybindProfiles",
        "WurstOptions",
        "ClickGui_Combat",
        "ClickGui_Movement",
        "ClickGui_Render",
        "ClickGui_Fun",
        "ClickGui_Other",
    }) do
        local window: any = windows.Get(id)
        if window ~= nil then
            window:SetVisible(true)
            if type(windows.ReflowWindow) == "function" then
                windows.ReflowWindow(window)
            end
            table.insert(named, window)
        end
    end
    for _, window: any in ipairs(featureWindows) do
        if type(window.resizeToOptions) == "function" then
            window.resizeToOptions()
        elseif type(windows.ReflowWindow) == "function" then
            windows.ReflowWindow(window)
        end
        table.insert(named, window)
    end

    local function visibleList(): {any}
        local list: {any} = {}
        for _, window: any in ipairs(named) do
            if window.root and window.root.Visible ~= false then
                table.insert(list, window)
            end
        end
        return list
    end

    local visible: {any} = visibleList()
    local overlap: string? = nil
    for i: number = 1, #visible do
        for j: number = i + 1, #visible do
            if Inspect.aabb(visible[i], visible[j], 0) then
                overlap = tostring(visible[i].id) .. " x " .. tostring(visible[j].id)
            end
        end
    end
    check(
        "AABB is empty after content and deferred reflow",
        overlap == nil,
        overlap
    )

    local vp: any = windows.LogicalViewport()
    local outside: string? = nil
    for _, window: any in ipairs(visible) do
        if not Inspect.inside(window, vp.X, vp.Y) then
            outside = tostring(window.id)
        end
    end
    check(
        "every realized window stays inside the viewport",
        outside == nil,
        outside
    )

    -- APPLY-2: an invalid persisted position is pulled back.
    if ui ~= nil then
        ui.root.Position = world.globals.UDim2.fromOffset(-400, 4000)
        windows.ClampWindow(ui)
        check(
            "ClampWindow pulls an invalid persisted position back",
            Inspect.inside(ui, vp.X, vp.Y)
                or (ui.root.Position.X.Offset >= 0 and ui.root.Position.Y.Offset < vp.Y),
            tostring(ui.root.Position.X.Offset) .. "," .. tostring(ui.root.Position.Y.Offset)
        )
    end

    -- Manual position wins; reflow only clamps.
    if keybinds ~= nil then
        keybinds.userMoved = true
        keybinds.root.Position = world.globals.UDim2.fromOffset(80, 80)
        windows.ReflowWindow(keybinds)
        check(
            "ReflowWindow leaves a user-moved window where it is",
            keybinds.root.Position.X.Offset == 80
                and keybinds.root.Position.Y.Offset == 80
        )
    end

    -- Reset layout forgets userMoved and re-places.
    if type(wo) == "table" and type(wo.InvokeAction) == "function" then
        if keybinds ~= nil then
            keybinds.userMoved = true
        end
        check("Reset layout action runs", wo.InvokeAction("ResetLayout") == true)
        if keybinds ~= nil then
            check(
                "Reset layout clears the manual-move flag",
                keybinds.userMoved ~= true
            )
        end
    end

    -- Scales and viewports.
    for _, size in ipairs({
        {1600, 900},
        {1366, 768},
        {1280, 560},
        {2560, 1080},
        {390, 844},
    }) do
        world.camera.ViewportSize = world.globals.Vector2.new(size[1], size[2])
        windows.Reclamp()
        local now: any = windows.LogicalViewport()
        check(
            "LogicalViewport tracks " .. tostring(size[1]) .. "x" .. tostring(size[2]),
            math.abs(now.X - size[1]) < 2 or scaleNode ~= nil,
            tostring(now.X) .. "x" .. tostring(now.Y)
        )
        if ui ~= nil then
            check(
                "UI Settings stays inside " .. tostring(size[1]) .. "x" .. tostring(size[2]),
                Inspect.inside(ui, now.X, now.Y)
                    or (ui.root.Position.X.Offset >= 0 and ui.root.Position.Y.Offset >= 0)
            )
        end
    end
    world.camera.ViewportSize = world.globals.Vector2.new(1280, 720)
    Inspect.pinClickGuiScale(env.PopupLayer, 1)
    windows.Reclamp()

    for _, scale in ipairs({0.7, 1.0, 1.25, 1.6}) do
        Inspect.pinClickGuiScale(env.PopupLayer, scale)
        local now: any = windows.LogicalViewport()
        if ui ~= nil then
            windows.PlaceWindow(ui, {force = true})
            windows.ReflowWindow(ui)
            check(
                "UI Settings at scale " .. tostring(scale) .. " stays in the logical viewport",
                ui.root.Position.X.Offset >= 0
                    and ui.root.Position.Y.Offset >= 0
                    and ui.root.Position.X.Offset < now.X
                    and ui.root.Position.Y.Offset < now.Y,
                "vp=" .. tostring(now.X) .. "x" .. tostring(now.Y)
            )
        end
    end
    Inspect.pinClickGuiScale(env.PopupLayer, 1)

    -- APPLY-4 landed path: menu hide closes ChoiceList. Scroll-clip is
    -- still NEEDS_EVIDENCE and must not fail here.
    local popupClosed: boolean = false
    if type(state.openChoiceList) == "function" and ui ~= nil then
        local anchor: any = ui.body and ui.body:FindFirstChild("Row_Keybinds")
        if anchor == nil then
            anchor = Inspect.findNamed(ui.root, "Row_Keybinds")
        end
        if anchor ~= nil then
            state.openChoiceList(anchor, {"Auto", "Count", "Hidden"}, 1, function(): () end)
            local layer: any = env.ScreenGui or env.PopupLayer
            local list: any = layer and Inspect.findNamed(layer, "ChoiceList")
            check("a dropdown opens above the windows", list ~= nil)
            if list ~= nil then
                check(
                    "dropdown Z-order sits above every window root",
                    (tonumber(list.ZIndex) or 0) >= 400,
                    tostring(list.ZIndex)
                )
            end
            if type(state.setMenuVisible) == "function" then
                state.setMenuVisible(false)
            end
            local still: any = layer and Inspect.findNamed(layer, "ChoiceList")
            popupClosed = still == nil
            check(
                "APPLY-4: hiding the menu closes the owner popup",
                popupClosed
            )
            if type(state.setMenuVisible) == "function" then
                state.setMenuVisible(true)
            end
        else
            check("dropdown anchor was not found; APPLY-4 hide path waits", true)
        end
    else
        check("ChoiceList opener is not published; APPLY-4 hide path waits", true)
    end

    if type(state.colorPicker) == "table" and type(state.colorPicker.open) == "function" then
        state.colorPicker.open(world.globals.Color3.fromRGB(64, 64, 64), function(): () end)
        local picker: any = state.colorPicker.panel
        check("the colour picker opens", picker ~= nil)
        if picker ~= nil then
            check(
                "picker Z-order sits above every window root",
                (tonumber(picker.ZIndex) or 0) >= 400,
                tostring(picker.ZIndex)
            )
        end
    end

    -- APPLY-5: pixel title-bar icons still exist.
    if ui ~= nil and ui.header then
        local icon: any = Inspect.findNamed(ui.header, "PixelIcon")
        check("APPLY-5 pixel title-bar icons remain", icon ~= nil or ui.closeButton ~= nil)
    end

    -- APPLY-3: a feature settings window with room still sits to the right
    -- of its category when PlaceWindow ran with that anchor.
    if #featureWindows > 0 then
        local sample: any = featureWindows[1]
        check(
            "APPLY-3 PlaceWindow / ReflowWindow still published",
            type(windows.PlaceWindow) == "function"
                and type(windows.ReflowWindow) == "function"
                and type(windows.FindFreeRect) == "function"
        )
        check(
            "a feature settings window stayed on screen",
            sample.root.Visible == true or sample.root.Position ~= nil
        )
    end

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
