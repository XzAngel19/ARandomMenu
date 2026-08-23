--!strict
--
-- Headless tests: Menu style is live, exclusive, and persisted.
--
-- SetMenuStyle stays the one exclusive state machine (never both
-- surfaces), but the Navigator is no longer a main surface: there is no
-- Menu style row and no Navigator keybind. RightShift toggles the menu;
-- the Navigator opens from the dock's magnifier (state.navigator.Open).

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
        "the default toggle key is RightShift",
        string.find(source, "savedToggleKey = Enum.KeyCode.RightShift", 1, true) ~= nil
    )
    check(
        "the Navigator has no keybind",
        string.find(bundle or "", "The Navigator has no keybind any more", 1, true) ~= nil
            and string.find(bundle or "", "RightShift opens Navigator", 1, true) == nil
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
        "RightShift is the selected menu key",
        state.toggleKey ~= nil
            and state.toggleKey.Name == "RightShift",
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

    -- No Menu style row any more: the style is not a player setting. The
    -- published value always reads Wurst and no cycle option exists.
    local ui: any = state.windows and state.windows.Get and state.windows.Get("UISettings")
    check("UI Settings still exists", ui ~= nil)
    check(
        "the published Menu style is always Wurst",
        state.uiSettings == nil
            or tostring(state.uiSettings["Menu style"]) == "Wurst"
    )
    local styleRow: any = nil
    if ui ~= nil and ui.root ~= nil then
        for _, descendant: any in ipairs(ui.root:GetDescendants()) do
            if tostring(descendant.Name) == "Option_Menustyle" then
                styleRow = descendant
            end
        end
    end
    check("no Menu style row is built", styleRow == nil)
    check(
        "the style stays Wurst after the machine round-trip",
        state.menuStyle == "Wurst",
        tostring(state.menuStyle)
    )

    -- RightShift toggles the menu now. Start closed so the key opens it.
    if state.navigator and type(state.navigator.Close) == "function" then
        state.navigator.Close()
    end
    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(false)
    end
    local input: any = world.services.UserInputService
    input.InputBegan:Fire({
        UserInputType = world.globals.Enum.UserInputType.Keyboard,
        KeyCode = world.globals.Enum.KeyCode.RightShift,
    }, false)
    check("RightShift opens the Wurst menu", Inspect.wurstVisible(state) == true)
    check(
        "RightShift never opens the Navigator",
        Inspect.navigatorVisible(state) == false
    )

    -- The magnifier is the Navigator's only door: the dock carries it and
    -- it drives state.navigator.Open/Close.
    local lupa: any = nil
    if state.pill ~= nil or env.ScreenGui ~= nil then
        local roots: {any} = {}
        if env.ScreenGui then
            table.insert(roots, env.ScreenGui)
        end
        for _, root: any in ipairs(roots) do
            for _, descendant: any in ipairs(root:GetDescendants()) do
                if tostring(descendant.Name) == "LupaRing" then
                    lupa = descendant
                end
            end
        end
    end
    check("the dock carries the magnifier icon", lupa ~= nil)
    if state.navigator and type(state.navigator.Open) == "function" then
        state.navigator.Open()
        check(
            "the magnifier path opens the Navigator",
            Inspect.navigatorVisible(state) == true
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
