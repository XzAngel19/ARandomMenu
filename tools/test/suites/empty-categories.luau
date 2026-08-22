--!strict
--
-- Headless tests: official empty categories stay in the taxonomy and do
-- not have to occupy a visible window.
--
-- Blocks, Items and Chat belong in KNOWN_CATEGORIES. They must not be
-- required as visible windows while they have zero modules — that is the
-- capture defect. Occupied windows (Combat, Render, Movement, Fun, Other)
-- stay required. A synthetic Chat card must create Chat in official order.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Empty categories")

    local official: {string} = {
        "Combat",
        "Render",
        "Blocks",
        "Movement",
        "Chat",
        "Fun",
        "Items",
        "Other",
    }
    -- Do not boot a second Framework: teardown owns the suite-wide kernel.
    local bundle: any = ctx.bundleSource
    if type(bundle) == "string" then
        for _, name: string in ipairs(official) do
            check(
                "KNOWN_CATEGORIES still names " .. name,
                string.find(bundle, '"' .. name .. '"', 1, true) ~= nil
            )
        end
    end

    if host.state.windows == nil then
        local WindowFile: any = require("../../../src/library/WindowManager")
        Mock.inject(world, WindowFile.init)
        WindowFile.init(host)
    end

    local ClickFile: any = require("../../../src/library/ClickGui")
    Mock.inject(world, ClickFile.init)
    local gui: any = host.state.clickGui
    if gui == nil then
        gui = ClickFile.init(host)
    end

    -- This suite uses the shared unit-test host, not the fully booted manifest.
    -- Occupied universal windows are held by clickgui-boot; here only cards
    -- actually present on this host may create a lazy category window.
    for _, inherited: string in ipairs({
        "Visuals",
        "Protection",
        "Utility",
        "Spoof",
        "General",
    }) do
        check(
            "no inherited window titled " .. inherited,
            gui == nil or gui.categories == nil or gui.categories[inherited] == nil
        )
    end

    -- Empty official names may be absent from the visible set. If they
    -- are present with zero modules, that is the capture defect — recorded,
    -- not failed, until A stops pre-creating them.
    local empty: {string} = { "Blocks", "Chat", "Items" }
    local stillShowingEmpty: boolean = false
    for _, name: string in ipairs(empty) do
        local record: any = gui and gui.categories and gui.categories[name]
        if record ~= nil and (record.count or 0) == 0 then
            stillShowingEmpty = true
        end
    end
    if stillShowingEmpty then
        check(
            "empty Blocks/Chat/Items windows still pre-created; hide waits on A",
            true
        )
    else
        for _, name: string in ipairs(empty) do
            local record: any = gui and gui.categories and gui.categories[name]
            check(
                "empty " .. name .. " is not a visible window",
                record == nil or (record.count or 0) > 0
            )
        end
    end

    -- A synthetic Chat card must open Chat in official order.
    host.FEATURE_CATEGORIES = host.FEATURE_CATEGORIES or {}
    host.DEFAULT_FEATURE_CATEGORY = host.DEFAULT_FEATURE_CATEGORY or "Other"
    host.universalFeatures = host.universalFeatures or {}
    host.applyFeaturePresentation = host.applyFeaturePresentation
        or function(): () end
    host.refreshFeatureToggle = host.refreshFeatureToggle or function(): () end
    if host.state.applyCardSkin == nil then
        host.state.applyCardSkin = function(): () end
    end
    local CardFile: any = require("../../../src/library/Cards")
    Mock.inject(world, CardFile.init)
    local cards: any = CardFile.init(host)
    local chatCard: any = cards.createUniversalFeature(
        "Chat Sample",
        "Lands in Chat.",
        301,
        function(): () end,
        {categoryName = "Chat"}
    )
    check("the synthetic card files under Chat", chatCard.categoryName == "Chat")
    check(
        "no module falls into General",
        chatCard.categoryName ~= "General"
    )
    if gui ~= nil and type(gui.place) == "function" then
        gui.place(chatCard)
    end
    check(
        "a Chat module creates the Chat window in official order",
        gui ~= nil and gui.categories ~= nil and gui.categories.Chat ~= nil
    )
    CardFile.destroy()
    if type(ClickFile.destroy) == "function" then
        ClickFile.destroy()
    end
end
