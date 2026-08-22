--!strict
--
-- Headless tests: a feature's settings are their own WindowManager window.
--
-- Official Wurst opens "<Feature> Settings" as a closable window. The port
-- still expands options inside the category row (Cards.luau parents
-- Options to the row). Flipping this suite to fail today is a permanent
-- red. The moment A publishes that window, every check below is live.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("SettingsWindow")

    host.FEATURE_CATEGORIES = host.FEATURE_CATEGORIES or {Fly = "Movement"}
    host.DEFAULT_FEATURE_CATEGORY = host.DEFAULT_FEATURE_CATEGORY or "Other"
    host.UniversalScroll = host.UniversalScroll or Mock.newInstance("ScrollingFrame")
    host.universalFeatures = host.universalFeatures or {}
    host.movementFeatures = host.movementFeatures or {}
    host.applyFeaturePresentation = host.applyFeaturePresentation
        or function(_feature: any, _isDefault: boolean): () end
    host.refreshFeatureToggle = host.refreshFeatureToggle
        or function(_feature: any): () end
    if host.state.applyCardSkin == nil then
        host.state.applyCardSkin = function(feature: any, _hovered: boolean?): ()
            feature.skinned = true
        end
    end
    host.state.isMobile = false

    if host.state.windows == nil then
        local WindowFile: any = require("../../../src/library/WindowManager")
        Mock.inject(world, WindowFile.init)
        WindowFile.init(host)
    end

    local CardFile: any = require("../../../src/library/Cards")
    Mock.inject(world, CardFile.init)
    local cards: any = CardFile.init(host)
    local createCard: any = cards.createUniversalFeature

    local WidgetFile: any = require("../../../src/library/Widgets")
    local widgets: any = host._widgets
    if type(widgets) ~= "table" then
        Mock.inject(world, WidgetFile.init)
        widgets = WidgetFile.init(host)
        host._widgets = widgets
    end

    local feature: any = createCard(
        "Aura Sample",
        "Has options.",
        201,
        function(_on: boolean): () end
    )
    widgets.addToggleOption(feature, "Debug draw", false, function(): () end)
    if feature.syncArrow then
        feature.syncArrow()
    end
    check("hasSettings is derived from real option rows", feature.hasSettings == true)

    local bare: any = createCard(
        "Bare Sample",
        "Nothing to configure.",
        202,
        function(_on: boolean): () end,
        {noOptions = true}
    )
    check("a module without options never reports hasSettings", bare.hasSettings ~= true)

    local windows: any = host.state.windows
    local function settingsId(name: string): string
        return name .. " Settings"
    end
    local function findSettings(name: string): any
        if type(windows) ~= "table" or type(windows.Get) ~= "function" then
            return nil
        end
        return windows.Get(settingsId(name))
            or windows.Get(name:gsub("%W", "") .. "Settings")
    end

    local landed: any = findSettings(feature.name)
        or (feature.options ~= nil and feature.options.Parent ~= feature.row)
    if landed == nil or landed == false then
        check(
            "SettingsWindow is not landed; independent-window tests wait on A",
            true
        )
        check(
            "inline options still live on the category row",
            feature.options ~= nil and feature.options.Parent == feature.row
        )
        local heightBefore: number = feature.row.Size.Y.Offset
        if type(feature.toggleExpansion) == "function" then
            feature.toggleExpansion()
        end
        check(
            "opening inline settings still grows the category row (the defect)",
            feature.row.Size.Y.Offset >= heightBefore,
            tostring(heightBefore) .. " -> " .. tostring(feature.row.Size.Y.Offset)
        )
        check(
            "a module without options never creates a Settings window",
            findSettings(bare.name) == nil
        )
        CardFile.destroy()
        return
    end

    -- A landed the surface. Everything below is blocking.
    local categoryHeight: number = feature.row.Size.Y.Offset
    if type(feature.toggleExpansion) == "function" then
        feature.toggleExpansion()
    end
    check(
        "opening settings does not change the category row height",
        feature.row.Size.Y.Offset == categoryHeight,
        tostring(categoryHeight) .. " -> " .. tostring(feature.row.Size.Y.Offset)
    )
    check(
        "options are not descendants of the category row",
        feature.options == nil
            or feature.options.Parent ~= feature.row
    )
    local first: any = findSettings(feature.name)
    check("a WindowManager window named \"<Feature> Settings\" exists", first ~= nil)
    if type(feature.toggleExpansion) == "function" then
        feature.toggleExpansion()
        feature.toggleExpansion()
    end
    local second: any = findSettings(feature.name)
    check("opening twice reuses the same window", first ~= nil and rawequal(first, second))

    if feature.arrow ~= nil then
        feature.arrow.MouseButton1Click:Fire()
        check("the triangle opens the same window", findSettings(feature.name) ~= nil)
    end
    if feature.activationTarget ~= nil then
        feature.activationTarget.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.MouseButton2,
        })
        check("right-click opens the same window", findSettings(feature.name) ~= nil)
    end

    local window: any = findSettings(feature.name)
    if window ~= nil then
        check("a settings window is closable", window.closeButton ~= nil)
        if type(window.SetCollapsed) == "function" then
            window:SetCollapsed(true)
            check("a settings window can collapse", window.collapsed == true)
            window:SetCollapsed(false)
        end
        if type(window.SetPinned) == "function" then
            window:SetPinned(true)
            check("a settings window can be pinned", window.pinned == true)
        end
        window:SetVisible(false)
        window:SetVisible(true)
        check("a closed settings window can reopen", window.root.Visible == true)
    end

    check(
        "a module without options never creates a Settings window",
        findSettings(bare.name) == nil
    )

    local tasksBefore: number = stub.taskCount()
    local connectionsBefore: number = #host.uiConnections
    if type(CardFile.destroy) == "function" then
        CardFile.destroy()
    end
    check(
        "teardown leaves no extra tasks",
        stub.taskCount() <= tasksBefore,
        tostring(stub.taskCount())
    )
    local leaked: number = 0
    for index: number = connectionsBefore + 1, #host.uiConnections do
        if host.uiConnections[index].Connected ~= false then
            leaked += 1
        end
    end
    check("teardown leaves no live connections the suite added", leaked == 0)
end
