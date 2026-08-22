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

    -- A window id is a persistence key, so the categories namespace theirs:
    -- "Utility" as a bare key would collide the day anything else wants to be
    -- called Utility, and the collision would silently restore one window's
    -- position onto the other.
    local function hasWindow(id: string): boolean
        return windows.Get("ClickGui_" .. id) ~= nil
            or windows.Get(id) ~= nil
            or windows.Get(string.lower(id)) ~= nil
    end

    -- The shared category contract: one window per official Wurst category
    -- that holds a module; an empty category keeps its place in the
    -- contract and draws nothing.
    local bootAliases: {[string]: string} = {
        Visuals = "Render", Protection = "Movement", Utility = "Other",
        Spoof = "Fun", General = "Other", Player = "Movement",
    }
    local bootOfficial: {string} = {
        "Combat", "Render", "Blocks", "Movement",
        "Chat", "Fun", "Items", "Other",
    }
    local bootPopulated: {[string]: boolean} = {}
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
        if table.find(bootOfficial, name) == nil then
            name = bootAliases[name] or "Other"
        end
        bootPopulated[name] = true
    end
    for _, category: string in ipairs(bootOfficial) do
        if bootPopulated[category] then
            check("one window for " .. category, hasWindow(category))
        else
            check(
                "empty category " .. category .. " draws no window",
                not hasWindow(category)
            )
        end
    end
    for _, inherited: string in ipairs({
        "Visuals", "Protection", "Utility", "Spoof", "General",
    }) do
        check("no inherited category window: " .. inherited,
            gui == nil or gui.categories == nil or gui.categories[inherited] == nil)
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

    -- Exercise every universal module through the same cards the ClickGUI
    -- reparents. This catches dependencies on old pages, scroll hosts and tabs
    -- that focused gameplay tests do not see.
    local cardsByName: {[string]: any} = {}
    for _, feature: any in ipairs(cards) do
        if type(feature.name) == "string" then
            cardsByName[feature.name] = feature
        end
    end
    local framework: any = host.state.framework
    local modulesByFeature: {[any]: any} = {}
    if framework then
        for _, module: any in pairs(framework.Modules or {}) do
            modulesByFeature[module.Feature] = module
        end
    end

    for _, entry: any in ipairs(Manifest.modules or {}) do
        local displayName: string = entry.name
        local feature: any = cardsByName[displayName]
        check("module card loaded: " .. displayName, feature ~= nil, displayName)
        if not feature then
            continue
        end

        local officialCategory: boolean = table.find({
            "Combat", "Render", "Blocks", "Movement",
            "Chat", "Fun", "Items", "Other",
        }, entry.category) ~= nil
        check("module manifest category is official: " .. displayName,
            officialCategory, tostring(entry.category))
        check("module card category matches manifest: " .. displayName,
            feature.categoryName == entry.category,
            tostring(feature.categoryName) .. " ~= " .. tostring(entry.category))
        check("module never falls into General: " .. displayName,
            feature.categoryName ~= "General")
        local realSettings: boolean = type(feature.hasOptions) == "function"
            and feature.hasOptions()
        check("module hasSettings is derived: " .. displayName,
            feature.hasSettings == realSettings,
            tostring(feature.hasSettings) .. " ~= " .. tostring(realSettings))

        if realSettings
            and feature.arrow then
            feature.arrow.MouseButton1Click:Fire()
            check("module options expand: " .. feature.name,
                feature.expanded == true and feature.options.Visible == true)
            local module: any = modulesByFeature[feature]
            if module then
                for optionName: string, option: any in pairs(module.Options or {}) do
                    if option.Show then
                        local rules: {any} = option.Show.Option and {option.Show} or option.Show
                        local expected: boolean = true
                        for _, rule: any in ipairs(rules) do
                            local source: any = module.Options[rule.Option]
                            local holds: boolean = false
                            if source ~= nil then
                                holds = type(rule.Values) == "table"
                                        and table.find(rule.Values, source.Value) ~= nil
                                    or type(rule.Values) ~= "table" and source.Value == true
                            end
                            if rule.Invert == true then
                                holds = not holds
                            end
                            expected = expected and holds
                        end
                        local row: any = option.Object
                        if row and row.ClassName ~= "Frame" then
                            row = row.Parent
                        end
                        check(feature.name .. " Show: " .. optionName,
                            row ~= nil and row.Visible == expected,
                            "expected " .. tostring(expected))
                    end
                end
            end
            feature.arrow.MouseButton1Click:Fire()
        end

        local focusedElsewhere: boolean = entry.path
                == "src/modules/Utility/RejoinServer.luau"
            or entry.path == "src/modules/Utility/LagSwitch.luau"
            or entry.path == "src/modules/Movement/HighJump.luau"
            or entry.path == "src/modules/Movement/ClickTeleport.luau"
        if feature.kind == "toggle" and not focusedElsewhere then
            if feature.enabled == true then
                pcall(feature.activate)
            end
            local moduleTasks: number = stub.taskCount()
            local moduleConnections: number = 0
            for _name: string in pairs(host.featureConnections) do
                moduleConnections += 1
            end
            local ok: boolean, failure: any = pcall(function(): ()
                feature.activate()
                stub.step(1 / 60)
                feature.activate()
            end)
            check("module toggles cleanly: " .. feature.name, ok, tostring(failure))
            check("module teardown releases tasks: " .. feature.name,
                stub.taskCount() == moduleTasks,
                "before: " .. tostring(moduleTasks) .. " after: " .. tostring(stub.taskCount()))
            local remainingConnections: number = 0
            for _name: string in pairs(host.featureConnections) do
                remainingConnections += 1
            end
            check("module teardown releases named connections: " .. feature.name,
                remainingConnections == moduleConnections,
                "before: " .. tostring(moduleConnections)
                    .. " after: " .. tostring(remainingConnections))
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
