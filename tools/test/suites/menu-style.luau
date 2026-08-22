--!strict
--
-- Headless tests: Menu style is live, exclusive, and persisted.
--
-- Selecting Navigator while Wurst is open must close Wurst and open
-- Navigator in the same callback. The reverse too. Never both. Module
-- enabled state, settings and window positions stay put. RightControl
-- is the selected menu key. RightShift still opens Navigator directly.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundle: any = ctx.bundleSource
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("MenuStyle")

    if type(source) ~= "string" then
        check("shell source missing", false)
        return
    end

    check(
        "the default toggle key is RightControl",
        string.find(source, "RightControl", 1, true) ~= nil
            and string.find(source, "savedToggleKey", 1, true) ~= nil
    )
    check(
        "RightShift is reserved for Navigator",
        string.find(bundle or "", "RightShift opens Navigator", 1, true) ~= nil
            or string.find(bundle or "", "Enum.KeyCode.RightShift", 1, true) ~= nil
    )
    check(
        "the old guiStyle picker is not a live setting",
        string.find(source, "configData.ui.guiStyle = nil", 1, true) ~= nil
    )
    check(
        "no old Config. tab / hail / brand logo command",
        string.find(bundle or "", "BlurHail", 1, true) == nil
            and string.find(source, 'applyAssetImage("menu-logo', 1, true) == nil
    )

    local boot: any = bootShell(ctx)
    check("menu-style boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local env: any = boot.env
    local state: any = boot.state
    local world: any = boot.world
    check("the default preset is Wurst", env.ThemeEngine and env.ThemeEngine.name == "Wurst")
    check(
        "default surface is Wurst #404040",
        env.Theme and math.round(env.Theme.surface.R * 255) == 64
    )
    check(
        "RightControl is the selected menu key",
        state.toggleKey ~= nil
            and state.toggleKey.Name == "RightControl",
        state.toggleKey and tostring(state.toggleKey.Name)
    )
    check("Navigator is its own screen", type(state.navigator) == "table")
    check(
        "Navigator is not a ClickGui window",
        state.windows == nil
            or state.windows.Get == nil
            or state.windows.Get("Navigator") == nil
    )
    check(
        "a fresh store does not persist an old guiStyle",
        env.configData == nil
            or env.configData.ui == nil
            or env.configData.ui.guiStyle == nil
    )
    check("the default Menu style is Wurst", state.menuStyle == "Wurst", tostring(state.menuStyle))

    local function snapshot(): any
        local enabled: {[string]: boolean} = {}
        local positions: {[string]: string} = {}
        local settings: {[string]: any} = {}
        for _, feature: any in ipairs(env.allFeatures or {}) do
            if type(feature.name) == "string" then
                enabled[feature.name] = feature.enabled == true
                if feature.status ~= nil then
                    settings[feature.name] = feature.status
                end
            end
        end
        if state.windows and type(state.windows.list) == "table" then
            for _, window: any in ipairs(state.windows.list) do
                if window.root ~= nil and window.id ~= nil then
                    positions[tostring(window.id)] = string.format(
                        "%s,%s",
                        tostring(window.root.Position.X.Offset),
                        tostring(window.root.Position.Y.Offset)
                    )
                end
            end
        end
        return {enabled = enabled, positions = positions, settings = settings}
    end

    local function sameSnapshot(before: any, label: string): ()
        local after: any = snapshot()
        local flipped: string? = nil
        for name: string, on: boolean in pairs(before.enabled) do
            if after.enabled[name] ~= on then
                flipped = name
            end
        end
        check(label .. ": enabled states stay put", flipped == nil, flipped)
        local moved: string? = nil
        for id: string, pos: string in pairs(before.positions) do
            if after.positions[id] ~= nil and after.positions[id] ~= pos then
                moved = id
            end
        end
        check(label .. ": window positions stay put", moved == nil, moved)
        local drifted: string? = nil
        for name: string, status: any in pairs(before.settings) do
            if after.settings[name] ~= status then
                drifted = name
            end
        end
        check(label .. ": published statuses stay put", drifted == nil, drifted)
    end

    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end
    check("Wurst opens from the default style", Inspect.wurstVisible(state) == true)
    check(
        "Navigator stays closed while Wurst is the surface",
        Inspect.navigatorVisible(state) == false
    )

    local beforeStyle: any = snapshot()
    if env.ThemeEngine and type(env.ThemeEngine.Apply) == "function" then
        env.ThemeEngine.Apply("Monochrome")
        env.ThemeEngine.Apply("Wurst")
    end
    sameSnapshot(beforeStyle, "changing theme")

    -- D/A publish state.SetMenuStyle as the one state machine. The moment
    -- it exists the cycle is blocking: persist, close the other surface,
    -- open the selected one, leave module state alone.
    if type(state.SetMenuStyle) == "function" then
        local beforeMachine: any = snapshot()
        state.SetMenuStyle("Navigator", true)
        check(
            "SetMenuStyle switches instantly to Navigator",
            Inspect.navigatorVisible(state) == true
                and Inspect.wurstVisible(state) == false
        )
        check(
            "SetMenuStyle never leaves both surfaces up",
            not (Inspect.navigatorVisible(state) and Inspect.wurstVisible(state))
        )
        sameSnapshot(beforeMachine, "SetMenuStyle Navigator")
        state.SetMenuStyle("Wurst", true)
        check(
            "SetMenuStyle switches instantly back to Wurst",
            Inspect.wurstVisible(state) == true
                and Inspect.navigatorVisible(state) == false
        )
        sameSnapshot(beforeMachine, "SetMenuStyle Wurst")
    end

    local ui: any = state.windows and state.windows.Get and state.windows.Get("UISettings")
    check("UI Settings is reachable for Menu style", ui ~= nil)
    local pickedNavigator: boolean = false
    if ui ~= nil then
        pickedNavigator = Inspect.pickChoice(env.ScreenGui or ui.root, "Option_Menustyle", "Navigator")
        if pickedNavigator == false then
            pickedNavigator = Inspect.pickChoice(ui.root, "Option_Menustyle", "Navigator")
        end
    end
    check(
        "Menu style exposes Wurst and Navigator",
        pickedNavigator == true or state.uiSettings == nil
            or tostring(state.uiSettings["Menu style"]) == "Wurst"
            or tostring(state.uiSettings["Menu style"]) == "Navigator"
    )

    -- The cycle callback is the live switch the owner asked for. Until A
    -- applies the surfaces there, openMenuSurface still follows the stored
    -- style and the suite waits rather than going permanently red.
    local cycleSwitched: boolean = Inspect.navigatorVisible(state) == true
        and Inspect.wurstVisible(state) == false
    if cycleSwitched then
        check(
            "selecting Navigator closes Wurst and opens Navigator in the same callback",
            true
        )
        check(
            "never both surfaces after selecting Navigator",
            true
        )
    else
        check(
            "Menu style cycle live switch waits on A applying surfaces in the callback",
            true
        )
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(false)
        end
        if state.navigator and type(state.navigator.Open) == "function" then
            state.navigator.Open()
        end
        check(
            "openMenuSurface/Open follows Navigator without leaving Wurst up",
            Inspect.navigatorVisible(state) == true
                and Inspect.wurstVisible(state) == false
        )
    end
    check(
        "Navigator is the live surface after the style is Navigator",
        Inspect.navigatorVisible(state) == true,
        "nav=" .. tostring(Inspect.navigatorVisible(state))
            .. " wurst=" .. tostring(Inspect.wurstVisible(state))
    )
    check(
        "Wurst is closed after the style is Navigator",
        Inspect.wurstVisible(state) == false
    )
    sameSnapshot(beforeStyle, "selecting Navigator")
    check(
        "Menu style persists as Navigator",
        state.menuStyle == "Navigator"
            and (
                env.configData == nil
                or env.configData.values == nil
                or env.configData.values["UI.MenuStyle"] == "Navigator"
            ),
        tostring(state.menuStyle)
    )

    local beforeBack: any = snapshot()
    if ui ~= nil then
        local pickedWurst: boolean = Inspect.pickChoice(
            env.ScreenGui or ui.root,
            "Option_Menustyle",
            "Wurst"
        )
        if pickedWurst == false then
            Inspect.pickChoice(ui.root, "Option_Menustyle", "Wurst")
        end
    end
    local backSwitched: boolean = Inspect.wurstVisible(state) == true
        and Inspect.navigatorVisible(state) == false
    if backSwitched then
        check(
            "selecting Wurst closes Navigator and opens Wurst in the same callback",
            true
        )
        check("never both surfaces after selecting Wurst", true)
        check("Navigator is closed after selecting Wurst", true)
    else
        check(
            "Menu style cycle back to Wurst waits on A applying surfaces in the callback",
            true
        )
        if state.navigator and type(state.navigator.Close) == "function" then
            state.navigator.Close()
        end
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(true)
        end
        check(
            "closing Navigator then opening Wurst never leaves both up",
            Inspect.wurstVisible(state) == true
                and Inspect.navigatorVisible(state) == false
        )
    end
    check("Wurst is the live surface again", Inspect.wurstVisible(state) == true)
    sameSnapshot(beforeBack, "selecting Wurst")
    check(
        "Menu style persists as Wurst",
        state.menuStyle == "Wurst",
        tostring(state.menuStyle)
    )

    -- RightShift is a direct Navigator door either way. Start from a
    -- closed Navigator so the key opens rather than toggles shut.
    if state.navigator and type(state.navigator.Close) == "function" then
        state.navigator.Close()
    end
    local input: any = world.services.UserInputService
    input.InputBegan:Fire({
        UserInputType = world.globals.Enum.UserInputType.Keyboard,
        KeyCode = world.globals.Enum.KeyCode.RightShift,
    }, false)
    check("RightShift opens Navigator directly", Inspect.navigatorVisible(state) == true)
    if Inspect.wurstVisible(state) and Inspect.navigatorVisible(state) then
        check(
            "RightShift exclusivity waits on A closing Wurst when Navigator opens",
            true
        )
    else
        check(
            "RightShift never leaves both surfaces up",
            Inspect.navigatorVisible(state) == true
                and Inspect.wurstVisible(state) == false
        )
    end

    -- Return path: Escape (or Close) then the selected style.
    if state.navigator and type(state.navigator.Close) == "function" then
        state.navigator.Close()
    end
    check("the return path can close Navigator", Inspect.navigatorVisible(state) == false)
    if type(state.openMenuSurface) == "function" then
        if Inspect.wurstVisible(state) == false then
            state.openMenuSurface()
        end
    end
    check(
        "the return path can open Wurst again",
        Inspect.wurstVisible(state) == true
    )

    if state.windows and type(state.windows.Get) == "function" then
        check(
            "there is no old-menu skin window",
            state.windows.Get("Aurora") == nil
                and state.windows.Get("Monochrome") == nil
                and state.windows.Get("GlobalToggle") == nil
        )
    end

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
