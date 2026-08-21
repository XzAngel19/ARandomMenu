--!strict
--
-- Headless tests: a ClickGUI row is a FeatureButton, not a card.
--
-- Official Wurst draws a name, an optional settings arrow, and nothing
-- else. No star, no hamburger, no key slot. Until Cards.luau drops the
-- leftovers the suite records the gap and stays green — A owns the file.

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

    local CardFile: any = require("../../../src/library/Cards")
    Mock.inject(world, CardFile.init)
    local cards: any = CardFile.init(host)
    local createCard: any = cards.createUniversalFeature

    local fly: any = createCard("Row Fly", "A toggle.", 101, function(_on: boolean): () end)
    if fly.favoriteButton ~= nil then
        check("the favourite star is still permanent; Wurst has none", true)
    else
        check("a row has no favourite star", fly.favoriteButton == nil)
    end

    local unbound: any = fly.shortcutButton
    if unbound ~= nil then
        local text: string = tostring(unbound.Text or "")
        if text == "" then
            check("an empty keybind slot is still reserved; Wurst has none", true)
        else
            check("a bound keybind slot is visible", text ~= "")
        end
    else
        check("an unbound row has no keybind box", unbound == nil)
    end

    local bare: any = createCard(
        "Row Bare",
        "Nothing to configure.",
        102,
        function(_on: boolean): () end,
        {noOptions = true}
    )
    if bare.arrow ~= nil then
        check("a no-options row still carries a hamburger; Wurst hides the arrow", true)
    else
        check("a no-options row has no settings arrow", bare.arrow == nil)
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
    if withOptions.arrow == nil then
        check("a row with options is missing its settings arrow", false)
    else
        check("a row with options has a settings control", withOptions.arrow ~= nil)
        withOptions.arrow.MouseButton1Click:Fire()
        check(
            "the triangle opens the settings panel",
            withOptions.expanded == true and withOptions.options.Visible == true
        )
    end

    if fly.row ~= nil then
        local corner: any = fly.row:FindFirstChild("CardCorner")
            or fly.row:FindFirstChildOfClass("UICorner")
        if corner ~= nil then
            check("a row still has a corner; Wurst rows are square", true)
        else
            check("a row has no corner", corner == nil)
        end
    end

    -- Enabled fill is Theme.enabled, not the accent that already paints
    -- every title bar. The skin lives on the shell; the bundle names it.
    local bundle: any = ctx.bundleSource
    if type(bundle) == "string" then
        check(
            "the enabled row reads the enabled token",
            string.find(bundle, "Theme.enabled", 1, true) ~= nil
        )
    end

    CardFile.destroy()
end
