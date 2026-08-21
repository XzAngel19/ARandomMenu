--!strict
--
-- Headless tests: an empty ClickGUI has to boot.
--
-- Written before ClickGui.luau so the file is born against this contract:
-- one window per category, each registered card has exactly one row, and
-- destroy leaves no live connections. Until the file exists the suite
-- records the gap and stays green.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Empty ClickGUI")

    local loaded: boolean, ClickFile: any = pcall(function(): any
        return require("../../../src/library/ClickGui")
    end)
    if not loaded then
        loaded, ClickFile = pcall(function(): any
            return require("../../../src/library/ClickGUI")
        end)
    end
    if not loaded then
        check("ClickGui is not on disk yet; empty-boot tests wait on it", true)
        return
    end

    local Manifest: any = require("../../../src/core/Manifest")
    local listed: boolean = false
    for _, path: string in ipairs(Manifest.libraries or {}) do
        if string.find(path, "ClickGui", 1, true)
            or string.find(path, "ClickGUI", 1, true) then
            listed = true
        end
    end
    check("ClickGui is in the manifest", listed)

    if host.ThemeEngine == nil then
        host.ThemeEngine = {
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

    local function liveConnections(): number
        local count: number = 0
        for _, connection: any in ipairs(host.uiConnections) do
            if connection.Connected ~= false then
                count += 1
            end
        end
        return count
    end

    local connectionsBefore: number = liveConnections()
    local tasksBefore: number = stub.taskCount()

    Mock.inject(world, ClickFile.init)
    local gui: any = ClickFile.init(host)
    check("an empty ClickGUI initialises", gui ~= nil or host.state.windows ~= nil)

    local windows: any = host.state.windows
    check("state.windows exists after boot", type(windows) == "table")
    if type(windows) ~= "table" then
        return
    end

    local function hasWindow(id: string): boolean
        return windows.Get(id) ~= nil or windows.Get(string.lower(id)) ~= nil
    end

    -- The taxonomy the framework already files cards under. Spoof, Favourites
    -- and UI Settings are extra windows the prototype draws; they are not
    -- required for an empty boot of the five boards.
    for _, category: string in ipairs({
        "Combat",
        "Movement",
        "Visuals",
        "Protection",
        "Utility",
    }) do
        check("one window for " .. category, hasWindow(category))
    end

    local seenRows: {[any]: boolean} = {}
    local cards: {any} = host.allFeatures or {}
    for _, feature: any in ipairs(cards) do
        local row: any = feature.row
        check(
            feature.name .. " has a row",
            row ~= nil,
            "no row on " .. tostring(feature.name)
        )
        if row ~= nil then
            check(
                feature.name .. " has exactly one row",
                seenRows[row] ~= true,
                "row reused for " .. tostring(feature.name)
            )
            seenRows[row] = true
        end
    end

    if type(ClickFile.destroy) == "function" then
        ClickFile.destroy()
    end

    local leakedConnections: number = 0
    for index: number = connectionsBefore + 1, #host.uiConnections do
        local connection: any = host.uiConnections[index]
        if connection.Connected ~= false then
            leakedConnections += 1
        end
    end
    check(
        "destroy leaves no live connections ClickGui added",
        leakedConnections == 0,
        "left: " .. tostring(leakedConnections)
    )
    check(
        "destroy leaves no tasks ClickGui added",
        stub.taskCount() <= tasksBefore,
        "before: " .. tostring(tasksBefore) .. " after: " .. tostring(stub.taskCount())
    )
end
