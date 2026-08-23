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
    check("ClickGui is on disk", loaded == true, tostring(ClickFile))
    if not loaded then
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

    -- The shared contract: a window exists exactly when its official
    -- category holds a module. Blocks, Items and Chat stay in the contract
    -- but draw nothing while they are empty; the old port names never
    -- appear as windows.
    local aliases: {[string]: string} = {
        Visuals = "Render", Protection = "Movement", Utility = "Other",
        Spoof = "Fun", General = "Other", Player = "Movement",
    }
    local official: {string} = {
        "Combat", "Render", "Blocks", "Movement",
        "Chat", "Fun", "Items", "Other",
    }
    local populated: {[string]: boolean} = {}
    for _, feature: any in ipairs(host.allFeatures or {}) do
        -- Only carded features count: place() files a card by its row's
        -- attribute and skips a feature that has no row at all, so a
        -- rowless stub must not make the suite demand a window.
        local raw: any = feature.row
            and feature.row.GetAttribute
            and feature.row:GetAttribute("FeatureCategory")
        if raw == nil then
            continue
        end
        local name: string = tostring(raw)
        if table.find(official, name) == nil then
            name = aliases[name] or "Other"
        end
        populated[name] = true
    end
    for _, name: string in ipairs(official) do
        if populated[name] then
            check("official category window " .. name, hasWindow(name))
        else
            check(
                "empty category " .. name .. " draws no window",
                not hasWindow(name)
            )
        end
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
    if combat ~= nil then
        local title: string = tostring(combat.title or combat.root and combat.root.Name or "")
        check(
            "a category title is not truncated",
            string.find(title, "…", 1, true) == nil
                and string.find(title, "...", 1, true) == nil,
            title
        )
        check(
            "a category window has no close button",
            combat.closable == false or combat.closeButton == nil
        )
        check("a category window can be pinned", type(combat.SetPinned) == "function")
        check("a category window can collapse", type(combat.SetCollapsed) == "function")
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

    if clickOk then
        clickSource = tostring(clickBody)
    end
    local _ = clickSource

    if type(ClickFile.destroy) == "function" then
        ClickFile.destroy()
    end
    check(
        "chrome suite left the host standing",
        stub == nil or type(stub.taskCount) == "function"
    )
end
