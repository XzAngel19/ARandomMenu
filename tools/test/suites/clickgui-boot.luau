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
    check("ClickGui is on disk", loaded == true, tostring(ClickFile))
    if not loaded then
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
    if gui and gui.categories then
        for categoryName: string, category: any in pairs(gui.categories) do
            local count: number = tonumber(category.count) or 0
            local required: number = 26 + count * 22
                + math.max(count - 1, 0) * 2 + 4
            if required <= 200 then
                check(
                    "short category shows every row: " .. categoryName,
                    tonumber(category.window.fullHeight) >= required,
                    tostring(category.window.fullHeight) .. " < " .. tostring(required)
                )
            end
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
    -- Machine-readable inventory. Count comes from the snapshot so the next
    -- deliberate addition does not retouch this suite.
    local matrix: {[string]: any} = {
        ["Friend List"] = {kind = "roblox-only"},
        ItemESP = {kind = "adapted", counterpart = "ItemESP"},
        PlayerESP = {kind = "adapted", counterpart = "PlayerESP"},
        Chams = {kind = "adapted", counterpart = "Chams"},
        Arrows = {kind = "adapted", counterpart = "Arrows"},
        NPCESP = {kind = "adapted", counterpart = "EntityESP NPCs"},
        Killaura = {kind = "adapted", counterpart = "Killaura"},
        ["Remote Logger"] = {kind = "roblox-only"},
        ["Click Teleport"] = {kind = "roblox-only"},
        ["Auto Clicker"] = {kind = "roblox-only"},
        TriggerBot = {kind = "adapted", counterpart = "TriggerBot"},
        ["X-Ray"] = {kind = "adapted", counterpart = "X-Ray"},
        HighJump = {kind = "adapted", counterpart = "HighJump"},
        Spider = {kind = "adapted", counterpart = "Spider"},
        WallHop = {kind = "roblox-only"},
        SafeWalk = {kind = "adapted", counterpart = "SafeWalk"},
        ["Rejoin Server"] = {kind = "adapted", counterpart = "AutoReconnect"},
        Zoom = {kind = "adapted", counterpart = "Zoom"},
        ["Interact Extender"] = {kind = "adapted", counterpart = "Reach"},
        ["Phase Dash"] = {kind = "roblox-only"},
        NoFall = {kind = "adapted", counterpart = "NoFall"},
        Flight = {kind = "adapted", counterpart = "Flight"},
        ["Vehicle Speed"] = {kind = "adapted", counterpart = "BoatFly"},
        ["Anti-Void"] = {kind = "roblox-only"},
        Gravity = {kind = "roblox-only"},
        ["Jump Power"] = {kind = "adapted", counterpart = "HighJump"},
        ["Infinite Jump"] = {kind = "roblox-only"},
        FOV = {kind = "roblox-only"},
        Noclip = {kind = "exact", counterpart = "Noclip"},
        AntiAFK = {kind = "adapted", counterpart = "AntiAFK"},
        ["Anti-Fling"] = {
            kind = "adapted", counterpart = "AntiKnockback/AntiEntityPush",
        },
        ["Lag Switch"] = {kind = "adapted", counterpart = "Blink"},
        Fling = {kind = "roblox-only"},
        ["Improve FPS"] = {kind = "roblox-only"},
        Fullbright = {kind = "adapted", counterpart = "Fullbright"},
        ["Freeze Movements"] = {kind = "adapted", counterpart = "Blink"},
        SpeedHack = {kind = "adapted", counterpart = "SpeedHack"},
        Hitboxes = {kind = "roblox-only"},
        ["Projectile Calibration"] = {
            kind = "adapted", counterpart = "Trajectories",
        },
        SpinBot = {kind = "adapted", counterpart = "SpinBot"},
        Disguise = {kind = "roblox-only"},
        ["Animation Changer"] = {kind = "roblox-only"},
        ["Emote Player"] = {kind = "roblox-only"},
    }
    local matrixCount: number = 0
    for _name: string in pairs(matrix) do
        matrixCount += 1
    end
    check(
        "module matrix matches the inventory snapshot",
        matrixCount == ctx.inventory.count,
        tostring(matrixCount)
    )

    local framework: any = host.state.framework
    local modulesByFeature: {[any]: any} = {}
    local openedSettings: {any} = {}
    if framework then
        for _, module: any in pairs(framework.Modules or {}) do
            modulesByFeature[module.Feature] = module
        end
    end

    for _, entry: any in ipairs(Manifest.modules or {}) do
        local displayName: string = entry.name
        local feature: any = cardsByName[displayName]
        local matrixEntry: any = matrix[displayName]
        check("module appears in parity matrix: " .. displayName,
            matrixEntry ~= nil, displayName)
        if matrixEntry then
            check("module parity kind is valid: " .. displayName,
                table.find({"exact", "adapted", "roblox-only"}, matrixEntry.kind) ~= nil)
            check("Roblox-only has no fake counterpart: " .. displayName,
                matrixEntry.kind ~= "roblox-only" or matrixEntry.counterpart == nil)
        end
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
        local metadata: {any} = feature.optionMetadata or {}
        check("module metadata follows settings rows: " .. displayName,
            #metadata == #feature.optionRows,
            tostring(#metadata) .. " ~= " .. tostring(#feature.optionRows))
        for index: number, option: any in ipairs(metadata) do
            check(displayName .. " metadata identity " .. tostring(index),
                type(option.id) == "string" and option.id ~= ""
                    and type(option.configKey) == "string"
                    and option.configKey ~= ""
                    and type(option.label) == "string"
                    and type(option.type) == "string")
            if option.type == "slider" or option.type == "range" then
                check(displayName .. " metadata range " .. option.label,
                    type(option.min) == "number" and type(option.max) == "number"
                        and option.min <= option.max
                        and type(option.step) == "number"
                        and option.step >= 0)
            elseif option.type == "dropdown" then
                check(displayName .. " metadata values " .. option.label,
                    type(option.values) == "table" and #option.values > 0)
            elseif option.type == "action" then
                check(displayName .. " metadata action " .. option.label,
                    option.action == true and type(option.callback) == "function")
            elseif option.type == "bind" then
                check(displayName .. " metadata bind " .. option.label,
                    option.bind == true)
            elseif option.type == "color" then
                check(displayName .. " metadata color " .. option.label,
                    option.color == true)
            end
        end

        if realSettings then
            local module: any = modulesByFeature[feature]
            local valuesBefore: {[string]: any} = {}
            if module then
                for optionName: string, option: any in pairs(module.Options or {}) do
                    valuesBefore[optionName] = option.Value
                end
            elseif type(feature.options) == "table" then
                for optionName: string, option: any in pairs(feature.options) do
                    if type(option) == "table" and option.value ~= nil then
                        valuesBefore[optionName] = option.value
                    end
                end
            end

            local visibilityBefore: {[any]: boolean} = {}
            for _, optionRow: any in ipairs(feature.optionRows or {}) do
                visibilityBefore[optionRow] = optionRow.Visible == true
            end
            local rowHeight: number = feature.row.Size.Y.Offset
            local category: any = gui and gui.categories
                and gui.categories[entry.category]
            local categoryHeight: number? = category and category.window.fullHeight
            local enabledBefore: boolean = feature.enabled == true
            local first: any = windows.OpenFeatureSettings(feature)

            local settingsId: string = "FeatureSettings_"
                .. tostring(feature.configKey or feature.name):gsub("%W", "")
            check("module settings window opens: " .. feature.name, first ~= nil)
            check("category row height stays fixed: " .. feature.name,
                feature.row.Size.Y.Offset == rowHeight,
                tostring(rowHeight) .. " -> " .. tostring(feature.row.Size.Y.Offset))
            if categoryHeight ~= nil then
                check("category window height stays fixed: " .. feature.name,
                    category.window.fullHeight == categoryHeight,
                    tostring(categoryHeight) .. " -> "
                        .. tostring(category.window.fullHeight))
            end
            check("opening settings keeps enabled state: " .. feature.name,
                (feature.enabled == true) == enabledBefore)
            check("settings leave the category row: " .. feature.name,
                first ~= nil and feature.options.Parent == first.body)
            for optionRow: any, wasVisible: boolean in pairs(visibilityBefore) do
                check("Show survives settings open: " .. feature.name
                        .. "/" .. tostring(optionRow.Name),
                    (optionRow.Visible == true) == wasVisible)
            end

            if module then
                for optionName: string, option: any in pairs(module.Options or {}) do
                    check(feature.name .. " value survives open: " .. optionName,
                        option.Value == valuesBefore[optionName])
                    if option.Show then
                        local rules: {any} = option.Show.Option and {option.Show}
                            or option.Show
                        local expected: boolean = true
                        for _, rule: any in ipairs(rules) do
                            local source: any = module.Options[rule.Option]
                            local holds: boolean = false
                            if source ~= nil then
                                holds = type(rule.Values) == "table"
                                        and table.find(rule.Values, source.Value) ~= nil
                                    or type(rule.Values) ~= "table"
                                        and source.Value == true
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
                        check(feature.name .. " Show survives reparent: " .. optionName,
                            row ~= nil and row.Visible == expected,
                            "expected " .. tostring(expected))
                    end
                end
            end

            if first and first.closeButton then
                first.closeButton.MouseButton1Click:Fire()
            end
            check("closing settings keeps module enabled: " .. feature.name,
                (feature.enabled == true) == enabledBefore)
            check("settings window closes: " .. feature.name,
                first ~= nil and first.root.Visible == false)
            local second: any = windows.OpenFeatureSettings(feature)
            check("reopening settings reuses the window: " .. feature.name,
                first ~= nil and rawequal(first, second))
            check("reopening settings restores visibility: " .. feature.name,
                second ~= nil and second.root.Visible == true)
            check("reopening keeps category height: " .. feature.name,
                feature.row.Size.Y.Offset == rowHeight)
            for optionRow: any, wasVisible: boolean in pairs(visibilityBefore) do
                check("Show survives settings reopen: " .. feature.name
                        .. "/" .. tostring(optionRow.Name),
                    (optionRow.Visible == true) == wasVisible)
            end
            table.insert(openedSettings, {
                feature = feature,
                id = settingsId,
                window = second,
            })
            if second and second.closeButton then
                second.closeButton.MouseButton1Click:Fire()
            end
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

    for _, record: any in ipairs(openedSettings) do
        local window: any = record.window
        if window then
            window:Destroy()
            record.feature.settingsWindow = nil
            check("settings teardown unregisters window: " .. record.feature.name,
                windows.Get(record.id) == nil)
            check("settings teardown destroys root: " .. record.feature.name,
                window.root.Parent == nil or window.root.Destroyed == true)
            check("settings teardown disconnects window: " .. record.feature.name,
                #window.connections == 0)
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
