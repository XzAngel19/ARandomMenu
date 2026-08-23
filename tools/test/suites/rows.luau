--!strict
--
-- Headless tests: a ClickGUI row is a FeatureButton.
--
-- Official Wurst draws a name and, when the feature has settings, an
-- 11-logical-px arrow. No star, no hamburger. The keybind square is an
-- approved Roblox adaptation (user-requested) and replaces the old ban
-- on desktop key slots. The leftover KEY pill is still forbidden.

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
        -- The name is centred on the whole row (ref-wurst-719); the bind
        -- square floats over the left end and the arrow over the right,
        -- with the same 28 px clearance on both sides — symmetric insets
        -- are exactly what keeps the centre unmoved while neither surface
        -- can be invaded by a long name.
        check(
            "the title's insets are symmetric, so its centre is the row's",
            bare.title.Size.X.Offset == -2 * bare.title.Position.X.Offset,
            "offset " .. tostring(bare.title.Size.X.Offset)
                .. " position " .. tostring(bare.title.Position.X.Offset)
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
    -- The widget builders remeasure as each row lands, and the remeasure is
    -- what creates the arrow; the suite bypasses the builders, so it calls
    -- the same remeasure by hand.
    withOptions.updateExpandedSize(false)
    check("hasSettings=true reports options", withOptions.hasOptions() == true)
    if withOptions.syncArrow then
        withOptions.syncArrow()
    end
    check("hasSettings=true shows a triangle", withOptions.arrow ~= nil)
    if withOptions.arrow ~= nil then
        check("a row with options has a settings control", withOptions.arrow ~= nil)
        check(
            "the settings arrow is visible only once options exist",
            withOptions.arrow.Visible == true
        )
        -- The triangle is a pixel sprite now, not a font glyph: the button
        -- carries no text and a PixelIcon container instead.
        local sprite: any = withOptions.arrow:FindFirstChild("PixelIcon")
        check(
            "the control is a pixel triangle, not a hamburger or a glyph",
            tostring(withOptions.arrow.Text or "") == "" and sprite ~= nil,
            tostring(withOptions.arrow.Text or "")
        )
        withOptions.arrow.MouseButton1Click:Fire()
        check(
            "the triangle opens the settings panel",
            withOptions.expanded == true and withOptions.options.Visible == true
        )
    end

    -- ----------------------------------------------------- keybind square
    -- The user-approved square on the left end of bindable rows. The
    -- harness host's bindActionShortcut does not populate
    -- state.shortcutBindings the way the shell does, so this section
    -- patches it to mirror the shell's contract and re-initialises Cards:
    -- a binding with the canonical assign (same key clears), keyed by the
    -- shortcut id.
    CardFile.destroy()
    host.state.shortcutBindings = host.state.shortcutBindings or {}
    local originalBind: any = host.bindActionShortcut
    host.bindActionShortcut = function(
        button: any,
        shortcutId: string,
        label: string,
        callback: any,
        options: any?
    ): ()
        originalBind(button, shortcutId, label, callback, options)
        local binding: any = {
            id = shortcutId,
            key = world.globals.Enum.KeyCode.Unknown,
        }
        binding.assign = function(keyCode: any): boolean
            local cleared: boolean = keyCode == binding.key
            binding.key = cleared
                and world.globals.Enum.KeyCode.Unknown
                or keyCode
            return not cleared
        end
        host.state.shortcutBindings[shortcutId] = binding
    end
    Mock.inject(world, CardFile.init)
    cards = CardFile.init(host)
    createCard = cards.createUniversalFeature

    local activations: number = 0
    local aura: any = createCard("Square Aura", "A toggle.", 110, function(_on: boolean): ()
        activations += 1
    end)
    local square: any = aura.bindSquare
    check("a bindable toggle grows the square", square ~= nil)
    local actionCard: any = createCard("Square Action", "Runs once.", 111,
        function(): () end, {kind = "action"})
    check(
        "a bindable action card gets the approved keybind square",
        actionCard.bindSquare ~= nil
    )
    local groupCard: any = createCard("Square Group", "A heading.", 112,
        function(): () end, {kind = "group"})
    check("a group gets no square", groupCard.bindSquare == nil)

    if square ~= nil then
        check("the square is named BindSquare", square.Name == "BindSquare")
        check("the square carries no corner",
            square:FindFirstChildOfClass("UICorner") == nil)
        check("an unbound square is empty", square.Text == "")
        check("the readable square is 18x18 on the 22 row",
            square.Size.X.Offset == 18 and square.Size.Y.Offset == 18)
        check("the square floats left without moving the title's centre",
            square.Position.X.Offset == 4)
        local stroke: any = square:FindFirstChild("StyleStroke")
        check("the square's stroke is the canonical StyleStroke", stroke ~= nil)

        local binding: any = host.state.shortcutBindings[aura.configKey]
        check("the square found the row's real binding", binding ~= nil)
        local enabledBefore: boolean = aura.enabled == true

        -- Click starts the canonical capture; nothing activates.
        square.MouseButton1Click:Fire()
        check("clicking the square starts the canonical capture",
            world.keyCapture ~= nil and world.keyCapture.button == square)
        check("starting a capture never activates", activations == 0)
        check("starting a capture never flips enabled",
            (aura.enabled == true) == enabledBefore)

        -- The next key assigns through binding.assign; still no activation.
        world.keyCapture.callback(world.globals.Enum.KeyCode.E)
        check("the captured key lands on the binding",
            binding.key == world.globals.Enum.KeyCode.E)
        check("assigning never activates", activations == 0)
        check("assigning never flips enabled",
            (aura.enabled == true) == enabledBefore)
        if stroke ~= nil then
            check("a bound square reads as the discreet green",
                stroke.Transparency == 0.25,
                tostring(stroke.Transparency))
        end

        -- A second row bound to the same key is a conflict on both.
        local rival: any = createCard("Square Rival", "Another toggle.", 113,
            function(_on: boolean): () end)
        local rivalBinding: any = host.state.shortcutBindings[rival.configKey]
        if rivalBinding then
            rivalBinding.key = world.globals.Enum.KeyCode.E
            aura.syncBindSquare()
            if stroke ~= nil then
                check("a shared key paints the conflict edge",
                    stroke.Transparency == 0.15,
                    tostring(stroke.Transparency))
            end
            rivalBinding.key = world.globals.Enum.KeyCode.Unknown
            aura.syncBindSquare()
        end

        -- Clicking again while capturing cancels without assigning.
        square.MouseButton1Click:Fire()
        check("recapture arms the machine again",
            world.keyCapture ~= nil and world.keyCapture.button == square)
        if host.state.keyCaptureCancel then
            square.MouseButton1Click:Fire()
            check("clicking the square again cancels",
                binding.key == world.globals.Enum.KeyCode.E)
        end

        -- The canonical clear: capturing the bound key empties the slot.
        square.MouseButton1Click:Fire()
        world.keyCapture.callback(world.globals.Enum.KeyCode.E)
        check("capturing the bound key clears it",
            binding.key == world.globals.Enum.KeyCode.Unknown)
        if stroke ~= nil then
            check("a cleared square returns to the quiet edge",
                stroke.Transparency == 0.6,
                tostring(stroke.Transparency))
        end
        check("no path ever activated the module", activations == 0)
        check("no path ever flipped enabled",
            (aura.enabled == true) == enabledBefore)
    end
    host.bindActionShortcut = originalBind

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
