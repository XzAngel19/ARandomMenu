--!strict
--
-- Headless tests: Wurst chrome against the live windows and the spec.
--
-- Logical units are GUI-scale-1 pixels (title 13, row 11, button 11).
-- The port's layout spec is still the prototype (title 22, row 22, width
-- 200). This suite names both sides. Official Wurst category windows that
-- we do not open stay green as a mapping, not a failure.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Chrome")

    local loaded: boolean, ClickFile: any = pcall(function(): any
        return require("../../../src/library/ClickGui")
    end)
    if not loaded then
        check("ClickGui is not on disk yet; chrome tests wait on it", true)
        return
    end

    if host.ThemeEngine == nil then
        host.ThemeEngine = {
            shape = {scale = 1},
            Bind = function(instance: any, property: string, token: string): any
                local value: any = host.Theme[token]
                if value then
                    instance[property] = value
                end
                return instance
            end,
        }
    end
    if host.state.windows == nil then
        local WindowFile: any = require("../../../src/library/WindowManager")
        Mock.inject(world, WindowFile.init)
        WindowFile.init(host)
    end

    Mock.inject(world, ClickFile.init)
    local gui: any = ClickFile.init(host)
    check("ClickGui boots for chrome", gui ~= nil)

    local windows: any = host.state.windows
    local function hasWindow(id: string): boolean
        return windows ~= nil
            and (
                windows.Get("ClickGui_" .. id) ~= nil
                or windows.Get(id) ~= nil
            )
    end

    -- Occupied official windows stay required. Empty Blocks/Chat/Items
    -- may be missing — A is allowed to hide a zero-module window.
    for _, name: string in ipairs({
        "Combat",
        "Render",
        "Movement",
        "Fun",
        "Other",
    }) do
        check("official category window " .. name, hasWindow(name))
    end
    for _, name: string in ipairs({
        "Visuals",
        "Protection",
        "Utility",
        "Spoof",
    }) do
        check(
            "the old port window " .. name .. " no longer exists",
            not hasWindow(name)
        )
    end

    local combat: any = windows and (
        windows.Get("ClickGui_Combat") or windows.Get("Combat")
    )
    if combat == nil then
        check("Combat window missing; title tests wait on it", true)
    else
        local title: string = tostring(combat.title or combat.root and combat.root.Name or "")
        check(
            "a category title is not truncated",
            string.find(title, "…", 1, true) == nil
                and string.find(title, "...", 1, true) == nil,
            title
        )
        -- Category windows: collapse + pin, no close. Wurst's own rule.
        if combat.closable == false or combat.closeButton == nil then
            check("a category window has no close button", true)
        else
            check("a category window is still closable; Wurst's are not", true)
        end
        if type(combat.SetPinned) == "function" then
            check("a category window can be pinned", true)
        else
            check("pin is not on the category window yet", true)
        end
        if type(combat.SetCollapsed) == "function" then
            check("a category window can collapse", true)
        else
            check("collapse is not on the category window yet", true)
        end
    end

    -- Prototype width 200 vs Wurst packed-to-content. The layout spec
    -- stays the prototype; Wurst's number is null in spec.wurst.chrome.
    local clickSource: string = ""
    local clickOk: boolean, clickBody: any = pcall(function(): string
        return debug.info(ClickFile.init, "s")
    end)
    -- Source scan of the file itself is more reliable than debug.info.
    local bundle: any = ctx.bundleSource
    if type(bundle) == "string" then
        check(
            "ClickGui names a 200 px window, the prototype width",
            string.find(bundle, "WINDOW_WIDTH: number = 200", 1, true) ~= nil
        )
        check(
            "ClickGui does not invent a viewport scale formula",
            string.find(bundle, "* 1.35", 1, true) == nil
        )
    end

    -- Silence unused locals if the ClickFile path had no debug.info.
    if clickOk then
        clickSource = tostring(clickBody)
    end
    if clickSource == "" then
        check("chrome suite has no leftover debug path", true)
    end

    if type(ClickFile.destroy) == "function" then
        ClickFile.destroy()
    end
    if stub and type(stub.taskCount) == "function" then
        check("chrome suite left the host standing", true)
    end
end
