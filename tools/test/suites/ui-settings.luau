--!strict
--
-- Headless tests: the UI Settings window, written before the window exists.
--
-- Official Wurst builds this window in ClickGui.init() as four feature
-- buttons (WurstLogo, HackList, Keybinds, WurstOptions) and then every
-- ClickGUI setting. The defaults are the ones in spec.json `wurst.settings`.
-- A window that ships Background as anything but #404040, or that invents
-- GlobalToggle / Isolate windows, has to fail here the day it appears.
--
-- Until the window is published the suite records the gap and stays green.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local host: any = ctx.host
    local Inspect: any = require("../inspect")

    section("UI Settings")

    local windows: any = host.state and host.state.windows
    local published: any = host.state and host.state.uiSettings

    local function findWindow(): any
        if type(windows) ~= "table" or type(windows.Get) ~= "function" then
            return nil
        end
        for _, id: string in ipairs({
            "ClickGui_UI Settings",
            "UI Settings",
            "ClickGui_UISettings",
            "UISettings",
        }) do
            local window: any = windows.Get(id)
            if window ~= nil then
                return window
            end
        end
        return nil
    end

    local window: any = findWindow()
    if window ~= nil then
        check(
            "the impossible 0-1000 Max height row is not user-facing",
            Inspect.findNamed(window.root, "Option_Maxheight") == nil
                and Inspect.findNamed(window.root, "Option_MaxHeight") == nil
        )
    end
    if published == nil and window == nil then
        check("UI Settings is not published yet; default tests wait on it", true)
        return
    end

    check("UI Settings is reachable", published ~= nil or window ~= nil)

    local settings: any = published
    if type(settings) ~= "table" then
        settings = window and (window.settings or window)
    end
    if type(settings) ~= "table" then
        check("UI Settings exposes a settings table", false)
        return
    end

    local function asHex(colour: any): string?
        if type(colour) == "string" then
            return string.upper(colour)
        end
        if type(colour) == "table" and colour.R ~= nil then
            return string.format(
                "#%02X%02X%02X",
                math.round(colour.R * 255),
                math.round(colour.G * 255),
                math.round(colour.B * 255)
            )
        end
        return nil
    end

    local function read(container: any, names: {string}): any
        for _, name: string in ipairs(names) do
            local value: any = container[name]
            if value ~= nil then
                return value
            end
        end
        return nil
    end

    local background: string? = asHex(read(settings, {
        "Background",
        "background",
        "BACKGROUND",
    }))
    check(
        "Background defaults to Wurst #404040",
        background == "#404040",
        tostring(background)
    )

    local accent: string? = asHex(read(settings, {
        "Accent",
        "accent",
        "ACCENT",
    }))
    check(
        "Accent defaults to Wurst #101010",
        accent == "#101010",
        tostring(accent)
    )

    local text: string? = asHex(read(settings, {
        "Text",
        "text",
        "TEXT",
    }))
    check(
        "Text defaults to Wurst #F0F0F0",
        text == "#F0F0F0",
        tostring(text)
    )

    local opacity: any = read(settings, { "Opacity", "opacity", "OPACITY" })
    if type(opacity) == "number" then
        check("Opacity defaults to Wurst 0.5, not the prototype 0.86", opacity == 0.5, tostring(opacity))
    end

    local tooltipOpacity: any = read(settings, {
        "Tooltip opacity",
        "tooltipOpacity",
        "TOOLTIP_OPACITY",
    })
    if type(tooltipOpacity) == "number" then
        check(
            "Tooltip opacity defaults to Wurst 0.75, not the prototype 0.95",
            tooltipOpacity == 0.75,
            tostring(tooltipOpacity)
        )
    end

    local maxHeight: any = read(settings, {
        "Max height",
        "maxHeight",
        "MAX_HEIGHT",
    })
    if type(maxHeight) == "number" then
        check(
            "Max height defaults to Wurst 200, not 340 or 300",
            maxHeight == 200,
            tostring(maxHeight)
        )
    end

    check(
        "official Wurst has no GlobalToggle",
        settings.GlobalToggle == nil and settings.globalToggle == nil
    )
    check(
        "official Wurst has no Isolate windows",
        settings.Isolate == nil
            and settings.isolate == nil
            and settings.isolateWindows == nil
    )
end
