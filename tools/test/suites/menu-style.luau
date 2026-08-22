--!strict
--
-- Headless tests: the shipped menu is Wurst, not the old product.
--
-- Default theme Wurst. ClickGUI bind RightControl. Navigator bind
-- RightShift, and only Navigator. Switching theme must not flip modules.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundle: any = ctx.bundleSource
    local bootShell: any = require("../boot_shell")

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

    -- Persistence: a stored key still wins, but a fresh boot without a
    -- store keeps RightControl.
    check(
        "a fresh store does not persist an old guiStyle",
        env.configData == nil
            or env.configData.ui == nil
            or env.configData.ui.guiStyle == nil
    )

    local enabledBefore: {[string]: boolean} = {}
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if type(feature.name) == "string" then
            enabledBefore[feature.name] = feature.enabled == true
        end
    end
    if env.ThemeEngine and type(env.ThemeEngine.Apply) == "function" then
        env.ThemeEngine.Apply("Monochrome")
        env.ThemeEngine.Apply("Wurst")
    end
    local flipped: string? = nil
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if type(feature.name) == "string"
            and (feature.enabled == true) ~= enabledBefore[feature.name]
        then
            flipped = feature.name
        end
    end
    check("changing style does not toggle modules", flipped == nil, flipped)

    check("SetMenuStyle is the central style state machine",
        type(state.SetMenuStyle) == "function")
    state.SetMenuStyle("Navigator", true)
    check("Navigator style opens immediately and closes ClickGUI",
        state.menuStyle == "Navigator"
            and state.navigator.root.Visible == true
            and state.visible == false)
    check("Navigator style persists",
        env.configData.values["UI.MenuStyle"] == "Navigator")
    state.SetMenuStyle("Wurst", true)
    check("Wurst style closes Navigator and opens ClickGUI immediately",
        state.menuStyle == "Wurst"
            and state.navigator.root.Visible == false
            and state.visible == true)
    check("only one menu surface is ever visible",
        not (state.visible and state.navigator.root.Visible))
    check("Navigator publishes a Wurst ClickGUI escape action",
        type(state.navigator.OpenWurst) == "function"
            and state.navigator.wurstButton ~= nil)
    state.navigator.Open()
    state.navigator.OpenWurst()
    check("Navigator escape action saves Wurst and opens it",
        state.menuStyle == "Wurst"
            and state.visible == true
            and state.navigator.root.Visible == false)

    -- Wurst exclusive: no second ClickGUI skin lives as a window.
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
