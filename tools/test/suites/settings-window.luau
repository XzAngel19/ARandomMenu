--!strict
--
-- Headless tests: a feature's settings are their own WindowManager window.
--
-- Official Wurst opens "<Feature> Settings" as a closable window. The port
-- lands that through WindowManager.OpenFeatureSettings: one lazy window per
-- feature, reused, cascaded, packed, capped by Max settings height, id
-- FeatureSettings_<configKey>. Triangle, right-click and Navigator Space
-- all come through that one function.

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
    -- Wurst's own default; OpenFeatureSettings caps the body to this.
    host.state.uiMaxSettingsHeight = 200

    local WindowFile: any = require("../../../src/library/WindowManager")
    -- Earlier suites leave the manager standing with leftover windows.
    -- A clean cascade is the only way the placement gates stay deterministic.
    if WindowFile.Initialized then
        WindowFile.destroy()
    end
    Mock.inject(world, WindowFile.init)
    WindowFile.init(host)

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

    local windows: any = host.state.windows
    check(
        "OpenFeatureSettings is the published contract",
        type(windows) == "table" and type(windows.OpenFeatureSettings) == "function"
    )
    check(
        "BringToFront is published",
        type(windows) == "table" and type(windows.BringToFront) == "function"
    )

    local function settingsId(feature: any): string
        return "FeatureSettings_"
            .. tostring(feature.configKey or feature.name):gsub("%W", "")
    end

    local function findSettings(feature: any): any
        if type(windows) ~= "table" or type(windows.Get) ~= "function" then
            return nil
        end
        return windows.Get(settingsId(feature)) or feature.settingsWindow
    end

    local function windowTitle(window: any): string
        local header: any = window and window.header
        local label: any = header and header:FindFirstChild("Title")
        return tostring(label and label.Text or "")
    end

    local function offsetOf(window: any): (number, number)
        return window.root.Position.X.Offset, window.root.Position.Y.Offset
    end

    local function sizeOf(window: any): (number, number)
        -- The mock does not keep AbsoluteSize in step with Size. Placement
        -- and clamp both write Size.X/Y.Offset, so that is the truth.
        return window.root.Size.X.Offset, window.root.Size.Y.Offset
    end

    local function insideViewport(window: any): boolean
        local screen: any = world.camera.ViewportSize
        local x: number, y: number = offsetOf(window)
        local width: number, height: number = sizeOf(window)
        -- WindowManager.MARGIN = 6. Create clamps to that inset.
        return x >= 6
            and y >= 6
            and x + width <= screen.X - 6
            and y + height <= screen.Y - 6
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

    local categoryHeight: number = feature.row.Size.Y.Offset
    if type(feature.toggleExpansion) == "function" then
        feature.toggleExpansion()
    end

    local first: any = findSettings(feature)
    check(
        "OpenFeatureSettings publishes FeatureSettings_<configKey>",
        first ~= nil,
        settingsId(feature)
    )
    check(
        "the feature keeps a handle on that window",
        feature.settingsWindow ~= nil and rawequal(feature.settingsWindow, first)
    )
    check(
        "the window title is \"<Feature> Settings\"",
        windowTitle(first) == "Aura Sample Settings",
        windowTitle(first)
    )
    check(
        "opening settings does not change the category row height",
        feature.row.Size.Y.Offset == categoryHeight,
        tostring(categoryHeight) .. " -> " .. tostring(feature.row.Size.Y.Offset)
    )
    check(
        "options live in the settings window body, not the category row",
        feature.options ~= nil
            and first ~= nil
            and feature.options.Parent == first.body
    )
    check(
        "a first-open settings window is fully inside the viewport",
        first ~= nil and insideViewport(first),
        first and (tostring(first.root.Position.X.Offset)
            .. ","
            .. tostring(first.root.Position.Y.Offset)
            .. " "
            .. tostring(first.root.Size.X.Offset)
            .. "x"
            .. tostring(first.root.Size.Y.Offset))
            or "nil"
    )
    check(
        "Max settings height caps the first-open window",
        first ~= nil and first.root.Size.Y.Offset <= 200,
        first and tostring(first.root.Size.Y.Offset) or "nil"
    )

    if type(feature.toggleExpansion) == "function" then
        feature.toggleExpansion()
        feature.toggleExpansion()
    end
    local secondLook: any = findSettings(feature)
    check(
        "opening twice reuses the same window",
        first ~= nil and rawequal(first, secondLook)
    )

    if feature.arrow ~= nil then
        feature.arrow.MouseButton1Click:Fire()
        check("the triangle opens the same window", findSettings(feature) ~= nil)
    end
    if feature.activationTarget ~= nil then
        feature.activationTarget.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.MouseButton2,
        })
        check("right-click opens the same window", findSettings(feature) ~= nil)
    end

    if first ~= nil then
        check("a settings window is closable", first.closeButton ~= nil)
        if type(first.SetCollapsed) == "function" then
            first:SetCollapsed(true)
            check("a settings window can collapse", first.collapsed == true)
            first:SetCollapsed(false)
        end
        if type(first.SetPinned) == "function" then
            first:SetPinned(true)
            check("a settings window can be pinned", first.pinned == true)
        end
        first:SetVisible(false)
        first:SetVisible(true)
        check("a closed settings window can reopen", first.root.Visible == true)
    end

    -- A second feature so the cascade, intersection and BringToFront
    -- gates have two first-open windows to compare.
    local other: any = createCard(
        "Other Sample",
        "Also has options.",
        203,
        function(_on: boolean): () end
    )
    widgets.addToggleOption(other, "Extra flag", false, function(): () end)
    if other.syncArrow then
        other.syncArrow()
    end
    other.toggleExpansion()
    local otherWindow: any = findSettings(other)
    check(
        "a second feature gets its own settings window",
        otherWindow ~= nil and not rawequal(otherWindow, first)
    )
    check(
        "the second settings window is fully inside the viewport",
        otherWindow ~= nil and insideViewport(otherWindow)
    )

    if first ~= nil and otherWindow ~= nil then
        local ax: number, ay: number = offsetOf(first)
        local bx: number, by: number = offsetOf(otherWindow)
        check(
            "two first-open settings are not born at the same origin",
            ax ~= bx or ay ~= by,
            tostring(ax) .. "," .. tostring(ay)
                .. " vs "
                .. tostring(bx) .. "," .. tostring(by)
        )
        local aw: number, ah: number = sizeOf(first)
        local bw: number, bh: number = sizeOf(otherWindow)
        local overlap: boolean = ax < bx + bw
            and bx < ax + aw
            and ay < by + bh
            and by < ay + ah
        check(
            "two first-open settings have zero AABB intersection after layout",
            overlap == false,
            tostring(ax) .. "," .. tostring(ay) .. " " .. tostring(aw) .. "x" .. tostring(ah)
                .. " vs "
                .. tostring(bx) .. "," .. tostring(by) .. " " .. tostring(bw) .. "x" .. tostring(bh)
        )

        windows.BringToFront(first)
        check(
            "BringToFront raises that window's root above the other",
            first.root.ZIndex > otherWindow.root.ZIndex,
            "first "
                .. tostring(first.root.ZIndex)
                .. " other "
                .. tostring(otherWindow.root.ZIndex)
        )
    end

    -- Weak "next to its category": when the category sits on the left and
    -- there is room to its right, the settings window must not open on
    -- top of it. Flush-to-edge (category.right + gap) is still owed — A's
    -- cascade parks at 45% of the viewport, which already satisfies
    -- "to the right when there is space".
    local combatCategory: any = windows.Create({
        id = "ClickGui_Combat",
        title = "Combat",
        size = world.globals.Vector2.new(200, 150),
        position = world.globals.Vector2.new(10, 64),
        closable = false,
    })
    combatCategory:SetVisible(true)
    local combatFeature: any = createCard(
        "Kill Aura",
        "A Combat module with options.",
        204,
        function(_on: boolean): () end,
        {categoryName = "Combat"}
    )
    widgets.addToggleOption(combatFeature, "Players", true, function(): () end)
    if combatFeature.syncArrow then
        combatFeature.syncArrow()
    end
    combatFeature.toggleExpansion()
    local combatSettings: any = findSettings(combatFeature)
    check("a Combat module opens a settings window", combatSettings ~= nil)
    if combatSettings ~= nil then
        local categoryRight: number = combatCategory.root.Position.X.Offset
            + combatCategory.root.Size.X.Offset
        local settingsX: number = combatSettings.root.Position.X.Offset
        local settingsW: number = combatSettings.root.Size.X.Offset
        local screen: any = world.camera.ViewportSize
        local roomOnRight: boolean = categoryRight + settingsW + 6 < screen.X
        if roomOnRight then
            check(
                "with room on the right, settings sit to the right of the category",
                settingsX >= categoryRight,
                "settings.x="
                    .. tostring(settingsX)
                    .. " category.right="
                    .. tostring(categoryRight)
            )
        else
            check(
                "no room on the right of the category; adjacent placement waits",
                true
            )
        end
        check(
            "the Combat settings window stays inside the viewport",
            insideViewport(combatSettings)
        )
    end

    if type(bare.toggleExpansion) == "function" then
        bare.toggleExpansion()
    end
    check(
        "a module without options never creates a Settings window",
        findSettings(bare) == nil and bare.settingsWindow == nil
    )

    local tasksBefore: number = stub.taskCount()
    local connectionsBefore: number = #host.uiConnections
    if type(CardFile.destroy) == "function" then
        CardFile.destroy()
    end
    if type(WindowFile.destroy) == "function" then
        WindowFile.destroy()
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
