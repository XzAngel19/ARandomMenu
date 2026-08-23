--!strict
--
-- Headless tests: C5 language/responsive hold.
--
-- The integrator's capture batch (afe8223) deleted the Spanish runtime
-- strings, hid DockSearchBox on phones, capped the mobile pill at 100 px,
-- dropped the Max height row, and made Keybind Manager the other door
-- into a row's bind square. This suite is the hold.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("HeightContract")

    local desktop: any = bootShell(ctx)
    check("capture-gates desktop boot runs", desktop.ok == true, desktop.error)
    if not desktop.ok then
        return
    end

    local state: any = desktop.state
    local env: any = desktop.env
    local world: any = desktop.world
    check(
        "state.uiMaxHeight stays 200",
        state.uiMaxHeight == 200,
        tostring(state.uiMaxHeight)
    )
    check(
        "state.uiMaxSettingsHeight stays 200",
        state.uiMaxSettingsHeight == 200,
        tostring(state.uiMaxSettingsHeight)
    )

    local ui: any = state.windows and state.windows.Get and state.windows.Get("UISettings")
    check("UI Settings is published", ui ~= nil and ui.root ~= nil)
    if ui ~= nil and ui.root ~= nil then
        check(
            "UI Settings has no Option_Maxheight row",
            Inspect.findNamed(ui.root, "Option_Maxheight") == nil
                and Inspect.findNamed(ui.root, "Option_MaxHeight") == nil
                and Inspect.findNamed(ui.root, "Option_Maxsettingsheight") == nil
        )
    end

    -- A short viewport must win over the 200 cap: otherwise phones still
    -- grow a settings window off the bottom of the screen. Pin the layer
    -- scale first — ClickGui's fit-to-1600×900 floors at 0.7, and a 160 px
    -- screen at that factor is still 229 logical pixels, which lets 200 win.
    if world.camera ~= nil then
        world.camera.ViewportSize = world.vector2(400, 160)
    end
    Inspect.pinClickGuiScale(env, 1)
    local sample: any = Inspect.featureNamed(env, "Killaura")
        or Inspect.featureNamed(env, "Flight")
    if sample ~= nil
        and state.windows
        and type(state.windows.OpenFeatureSettings) == "function"
    then
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(true)
        end
        state.windows.OpenFeatureSettings(sample)
        local settings: any = sample.settingsWindow
        local height: number = settings and settings.root and settings.root.Size.Y.Offset or 0
        check(
            "viewport clamping still wins over the 200 cap",
            settings ~= nil and height > 0 and height <= 160 - 12,
            tostring(height)
        )
    else
        check("a settings window exists to measure the viewport cap", false)
    end

    section("KeybindManagerSquare")

    local feature: any = Inspect.featureNamed(env, "Flight")
        or Inspect.featureNamed(env, "Killaura")
        or Inspect.featureNamed(env, "SpeedHack")
    local square: any = Inspect.findBindSquare(feature)
    check("a live bindable row carries the square", square ~= nil)
    if square ~= nil
        and type(state.wurstOptions) == "table"
        and type(state.wurstOptions.InvokeAction) == "function"
    then
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(true)
        end
        state.wurstOptions.InvokeAction("Keybinds")
        local keybinds: any = state.windows and state.windows.Get("Keybinds")
        check("Keybind Manager opens", keybinds ~= nil and keybinds.root ~= nil)

        local added: boolean = Inspect.clickNamed(
            keybinds and keybinds.root,
            "Row_Add"
        )
        check("Add Keybind is reachable", added == true)
        local addRoot: any = state.windows and state.windows.Get("KeybindAdd")
        local addName: string = "Add_" .. tostring(feature and feature.name or ""):gsub("%W", "")
        local picked: boolean = Inspect.clickNamed(addRoot and addRoot.root, addName)
        check("the manager lists the live module", picked == true, addName)
        if state.keyCaptureCallback then
            state.keyCaptureCallback(world.globals.Enum.KeyCode.Q)
        elseif world.keyCapture and world.keyCapture.callback then
            world.keyCapture.callback(world.globals.Enum.KeyCode.Q)
        end
        check(
            "assigning through the manager updates the row square",
            tostring(square.Text or "") == "Q",
            tostring(square.Text)
        )

        local reset: boolean = Inspect.clickNamed(
            keybinds and keybinds.root,
            "Row_Resetkeybinds"
        )
        check("Reset keybinds is reachable", reset == true)
        check(
            "resetting through the manager clears the row square",
            tostring(square.Text or "") == "",
            tostring(square.Text)
        )
    else
        check("Keybind Manager is published on this boot", false)
    end

    if type(state.destruct) == "function" then
        pcall(state.destruct)
    end

    section("MobileCapture")

    ctx.prepareWorld = function(mobileWorld: any): ()
        mobileWorld.services.UserInputService.TouchEnabled = true
        mobileWorld.services.UserInputService.KeyboardEnabled = false
        mobileWorld.services.UserInputService.MouseEnabled = false
    end
    local mobile: any = bootShell(ctx)
    ctx.prepareWorld = nil
    check("mobile capture boot runs", mobile.ok == true, mobile.error)
    if not mobile.ok then
        return
    end

    local mobileState: any = mobile.state
    local mobileEnv: any = mobile.env
    check("mobile boot is touch-primary", mobileState.isMobile == true)
    local pill: any = mobileState.pill and (mobileState.pill.root or mobileState.pill)
    check("the mobile pill exists", pill ~= nil)
    check(
        "no DockSearchBox on a touch-primary device",
        Inspect.findNamed(pill, "DockSearchBox") == nil
            and Inspect.dockSearch(mobileState) == nil
    )
    check(
        "mobile pill width is at most 100 px",
        pill ~= nil and pill.Size.X.Offset <= 100,
        pill and tostring(pill.Size.X.Offset) or "missing"
    )
    local navigatorSearch: any = mobileState.navigator
        and mobileState.navigator.root
        and Inspect.findNamed(mobileState.navigator.root, "Search")
    check("Navigator still has Search", navigatorSearch ~= nil)

    local phone: any = Inspect.featureNamed(mobileEnv, "Flight")
        or Inspect.featureNamed(mobileEnv, "Killaura")
        or (mobileEnv.allFeatures and mobileEnv.allFeatures[1])
    local slot: any = phone and phone.shortcutButton
    check(
        "the mobile shortcut slot stays left of the title lane",
        slot ~= nil
            and slot.Position.X.Offset == 4
            and slot.Size.X.Offset == 22,
        slot and tostring(slot.Position.X.Offset) or "missing"
    )
    if slot ~= nil and phone ~= nil and phone.title ~= nil then
        check(
            "the mobile shortcut ends before the title starts",
            slot.Position.X.Offset + slot.Size.X.Offset
                <= phone.title.Position.X.Offset
        )
    end

    if type(mobileState.destruct) == "function" then
        pcall(mobileState.destruct)
    end
end
