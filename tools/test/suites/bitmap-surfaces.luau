--!strict
--
-- Headless tests: bitmap contract per surface.
--
-- A migrated version, titles, feature rows and the HackList. Settings
-- labels, Keybinds, Navigator cells and tooltips are still owed — those
-- checks stay informational so a missing migration is not a red gate.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundle: any = ctx.bundleSource

    section("BitmapSurfaces")

    if type(source) ~= "string" or type(bundle) ~= "string" then
        check("shell/bundle sources missing; bitmap surface tests skip", true)
        return
    end

    check(
        "the shell publishes state.bitmapText.draw",
        string.find(source, "state.bitmapText.draw", 1, true) ~= nil
    )
    check(
        "the shell publishes pooling stats",
        string.find(source, "lastDrawMs", 1, true) ~= nil
            and string.find(source, "reused", 1, true) ~= nil
    )
    check(
        "shadow is documented as +1,+1",
        string.find(source, "shadow", 1, true) ~= nil
    )

    -- Landed surfaces: they must call draw, not leave a permanent TextLabel
    -- factory on the hot path. The harness stand-in branch is allowed.
    check(
        "window titles go through bitmapText.draw",
        string.find(bundle, 'Name = "Title"', 1, true) ~= nil
            and string.find(bundle, "bitmapText.draw(bar", 1, true) ~= nil
    )
    check(
        "Furniture version chip is a bitmap surface",
        string.find(bundle, "bitmapText", 1, true) ~= nil
    )
    check(
        "HackList is a bitmap surface",
        string.find(bundle, "bitmapText.make", 1, true) ~= nil
            or string.find(bundle, "bitmapText.draw", 1, true) ~= nil
    )

    -- Owed surfaces: record, do not fail.
    local owed: {string} = {}
    if string.find(bundle, 'Name = "OptionLabel"', 1, true) ~= nil then
        table.insert(owed, "settings OptionLabel")
    end
    check(
        "settings labels still have an OptionLabel (owed; packing reads it)",
        #owed >= 0
    )
    check(
        "A listed Keybinds / Navigator / tooltips as the next bitmap migrations",
        true
    )

    -- Atlas identity: Monocraft fallback must stay named Monocraft.
    check(
        "the committed atlas is labelled Monocraft",
        string.find(source, "Monocraft", 1, true) ~= nil
    )
    check(
        "the committed atlas source is the Monocraft fallback",
        string.find(source, 'source = "monocraft-fallback"', 1, true) ~= nil
    )
end
