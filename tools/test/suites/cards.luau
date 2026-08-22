--!strict
--
-- Headless tests: cards.
--
-- The harness used to build cards through a recording stub, so the factory
-- that actually ships never ran. Cards.luau is a library with the same
-- init(host) shape as Widgets.luau; this drives that function the way a
-- module creation does.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Cards")

    -- The settings-window contract lives on the window manager; the factory
    -- opens option panels through it, so the suite needs the real manager.
    if host.state.windows == nil then
        local WindowFile: any = require("../../../src/library/WindowManager")
        Mock.inject(world, WindowFile.init)
        WindowFile.init(host)
    end

    host.FEATURE_CATEGORIES = {
        Fly = "Movement",
        ["Kill Aura"] = "Combat",
    }
    host.DEFAULT_FEATURE_CATEGORY = "General"
    host.UniversalScroll = Mock.newInstance("ScrollingFrame")
    host.UniversalScroll.Name = "UniversalScroll"
    host.UniversalScroll.Parent = host.ScreenGui
    host.universalFeatures = {}
    host.movementFeatures = {}
    host.mm2Features = {}
    host.applyFeaturePresentation = function(feature: any, _isDefault: boolean): ()
        feature.presented = true
    end
    host.refreshFeatureToggle = function(feature: any): ()
        feature.refreshed = true
    end
    host.state.applyCardSkin = function(feature: any, hovered: boolean?): ()
        feature.skinned = true
        feature.hovering = hovered == true
    end
    host.state.floatingUi = {
        registerFeature = function(feature: any): ()
            host.state.registeredCards = host.state.registeredCards or {}
            host.state.registeredCards[feature.configKey] = feature
        end,
        toggleFavorite = function(_feature: any): () end,
    }

    local CardFile: any = require("../../../src/library/Cards")
    Mock.inject(world, CardFile.init)
    local cards: any = CardFile.init(host)
    check("the library publishes the factory",
        type(cards) == "table" and type(cards.createUniversalFeature) == "function")

    local createCard: any = cards.createUniversalFeature
    local toggled: {boolean} = {}
    local fly: any = createCard("Fly", "Move through the air", 1, function(on: boolean): ()
        table.insert(toggled, on)
    end)

    check("the card is created with its title",
        fly ~= nil and fly.title ~= nil and fly.title.Text == "Fly")
    check("the row is parented to the board",
        fly.row ~= nil and fly.row:IsDescendantOf(host.ScreenGui))
    check("taxonomy files Fly under Movement",
        fly.categoryName == "Movement"
            and fly.row:GetAttribute("FeatureCategory") == "Movement")
    check("a toggle card is a toggle",
        fly.kind == "toggle" and fly.isAction == false and fly.isHoldAction == false)
    check("the card carries an activation target",
        fly.activationTarget ~= nil and fly.activationTarget.Name == "ActivationTarget")
    check("creating a card skins it", fly.skinned == true)
    check("creating a card presents it", fly.presented == true)
    check("creating a card registers it with the overlay layer",
        host.state.registeredCards ~= nil
            and host.state.registeredCards[fly.configKey] == fly)

    fly.activationTarget.MouseButton1Click:Fire()
    check("activating a toggle calls the module",
        fly.enabled == true and toggled[#toggled] == true)
    check("the enabled state is stored",
        host.configData.states[fly.configKey] == true)
    fly.activationTarget.MouseButton1Click:Fire()
    check("activating again turns it off",
        fly.enabled == false and toggled[#toggled] == false)

    local gizmo: any = createCard("Gizmo", "Unclassified", 2, function(): () end)
    check("an unclassified card falls through to Wurst Other",
        gizmo.categoryName == "Other"
            and gizmo.row:GetAttribute("FeatureCategory") == "Other")

    local ran: number = 0
    local jump: any = createCard("High Jump", "Jump once", 3, function(): ()
        ran += 1
    end, {kind = "action"})
    check("an action card is an action",
        jump.kind == "action" and jump.isAction == true)
    jump.activationTarget.MouseButton1Click:Fire()
    check("activating an action runs the module once", ran == 1)
    check("an action keeps no enabled state", jump.enabled == false)

    local held: {boolean} = {}
    local sprint: any = createCard("Sprint", "Hold to run", 4, function(_on: boolean): ()
    end, {
        kind = "hold",
        onHold = function(active: boolean): ()
            table.insert(held, active)
        end,
    })
    check("a hold card is a hold",
        sprint.kind == "hold" and sprint.isHoldAction == true and sprint.isAlwaysOn == true)
    local heldBeforeClick: number = #held
    sprint.activationTarget.MouseButton1Click:Fire()
    check("clicking a hold card does nothing",
        #held == heldBeforeClick and sprint.enabled == false)
    sprint.setHeld(true)
    check("holding the key calls onHold", held[#held] == true)
    sprint.setHeld(false)
    check("releasing the key calls onHold off", held[#held] == false)

    local expandable: any = createCard("Aura", "Has options", 5, function(): () end)
    local optionRow: any = Mock.newInstance("Frame")
    optionRow.Visible = true
    optionRow.Size = world.globals.UDim2.fromOffset(0, 34)
    optionRow.Parent = expandable.options
    table.insert(expandable.optionRows, optionRow)
    -- The widget builders call updateExpandedSize as each row lands; the
    -- suite bypasses them, so it remeasures by hand — which is also what
    -- creates the arrow, since the arrow does not exist before the first
    -- real option does.
    expandable.updateExpandedSize(false)
    check("an option row publishes hasSettings", expandable.hasSettings == true)
    check("the options panel starts closed", expandable.options.Visible == false)
    local rowHeightBefore: number = expandable.row.Size.Y.Offset
    expandable.arrow.MouseButton1Click:Fire()
    check("the triangle opens a settings window of its own",
        expandable.expanded == true
            and expandable.settingsWindow ~= nil
            and expandable.options.Visible == true)
    check("the options moved into that window",
        expandable.options.Parent == expandable.settingsWindow.body)
    check("the category row keeps exactly its height",
        expandable.row.Size.Y.Offset == rowHeightBefore,
        tostring(expandable.row.Size.Y.Offset))
    local firstWindow: any = expandable.settingsWindow
    expandable.arrow.MouseButton1Click:Fire()
    check("reopening reuses the window, never duplicates",
        expandable.settingsWindow == firstWindow)

    local bare: any = createCard("Anti-AFK", "Nothing to configure", 6, function(): () end, {
        noOptions = true,
    })
    check("a noOptions card reports no options", bare.hasOptions() == false)
    check("a noOptions card has no settings metadata", bare.hasSettings ~= true)
    check("a noOptions card draws no arrow at all", bare.arrow == nil)
    bare.toggleExpansion()
    check("a noOptions card does not open a panel",
        bare.expanded == false and bare.options.Visible == false)

    host.configData.states["Universal.Speed"] = true
    local restoredOn: boolean = false
    local speed: any = createCard("Speed", "Go faster", 7, function(on: boolean): ()
        restoredOn = on
    end)
    check("a stored enabled state is restored",
        speed.enabled == true and restoredOn == true)

    CardFile.destroy()
end
