--!strict
--
-- Headless tests: a ClickGUI row is a FeatureButton.
--
-- Official Wurst draws a name and, when the feature has settings, an
-- 11-logical-px arrow. No star, no hamburger, no key slot. A landed that
-- shape; a leftover coming back fails.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Rows")

    host.FEATURE_CATEGORIES = host.FEATURE_CATEGORIES or {Fly = "Movement"}
    host.DEFAULT_FEATURE_CATEGORY = host.DEFAULT_FEATURE_CATEGORY or "General"
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

    local CardFile: any = require("../../../src/library/Cards")
    Mock.inject(world, CardFile.init)
    local cards: any = CardFile.init(host)
    local createCard: any = cards.createUniversalFeature

    local fly: any = createCard("Row Fly", "A toggle.", 101, function(_on: boolean): () end)
    check("a row has no favourite star", fly.favoriteButton == nil)
    check(
        "a desktop row has no keybind box",
        fly.shortcutButton == nil,
        tostring(fly.shortcutButton)
    )
    check(
        "the row has no LinesGlyph child",
        fly.row == nil or fly.row:FindFirstChild("LinesGlyph") == nil
    )

    local bare: any = createCard(
        "Row Bare",
        "Nothing to configure.",
        102,
        function(_on: boolean): () end,
        {noOptions = true}
    )
    check("hasSettings=false reports no options", bare.hasOptions() == false)
    if bare.syncArrow then
        bare.syncArrow()
    end
    check(
        "hasSettings=false keeps the arrow unparented from the layout",
        bare.arrow == nil or bare.arrow.Visible == false,
        "Visible=" .. tostring(bare.arrow and bare.arrow.Visible)
    )
    if bare.title and bare.title.Size then
        check(
            "hasSettings=false reserves no arrow column",
            bare.title.Size.X.Offset == -8,
            "title offset " .. tostring(bare.title.Size.X.Offset)
        )
    end

    local withOptions: any = createCard(
        "Row Aura",
        "Has options.",
        103,
        function(_on: boolean): () end
    )
    local optionRow: any = Mock.newInstance("Frame")
    optionRow.Visible = true
    optionRow.Size = world.globals.UDim2.fromOffset(0, 34)
    optionRow.Parent = withOptions.options
    table.insert(withOptions.optionRows, optionRow)
    check("hasSettings=true reports options", withOptions.hasOptions() == true)
    if withOptions.syncArrow then
        withOptions.syncArrow()
    end
    check("hasSettings=true shows a triangle", withOptions.arrow ~= nil)
    if withOptions.arrow ~= nil then
        check(
            "the settings arrow is visible only once options exist",
            withOptions.arrow.Visible == true
        )
        local glyph: string = tostring(withOptions.arrow.Text or "")
        check(
            "the control is a triangle, not a hamburger",
            glyph == "▼" or glyph == "▲",
            glyph
        )
        withOptions.arrow.MouseButton1Click:Fire()
        check(
            "the triangle opens the settings panel",
            withOptions.expanded == true and withOptions.options.Visible == true
        )
    end

    if fly.row ~= nil then
        local corner: any = fly.row:FindFirstChild("CardCorner")
            or fly.row:FindFirstChildOfClass("UICorner")
        check("a row has no corner", corner == nil)
    end

    local bundle: any = ctx.bundleSource
    if type(bundle) == "string" then
        check(
            "the enabled row reads the enabled token",
            string.find(bundle, "Theme.enabled", 1, true) ~= nil
        )
        check(
            "Cards no longer names a Favorite button",
            string.find(bundle, 'Name = "Favorite"', 1, true) == nil
        )
    end

    CardFile.destroy()
end
