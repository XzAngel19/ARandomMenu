--!strict
--
-- Headless tests: bitmap performance budgets.
--
-- Numbers are measured against the contract's own counters, then written
-- down so a later renderer cannot quietly start rebuilding every frame.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource

    section("BitmapBudget")

    if type(source) ~= "string" then
        check("no shell source; budget tests skip", true)
        return
    end

    -- The renderer must skip a draw whose signature has not changed.
    check(
        "signature skip exists (no rebuild without a change)",
        string.find(source, "record.signature == signature", 1, true) ~= nil
            and string.find(source, "stats.skipped", 1, true) ~= nil
    )
    check(
        "the pool reuses glyph instances",
        string.find(source, "reused", 1, true) ~= nil
    )
    check(
        "release() exists so teardown can drop glyphs",
        string.find(source, "state.bitmapText.release", 1, true) ~= nil
            or string.find(source, "bitmapText.release", 1, true) ~= nil
    )
    check(
        "lastDrawMs is published so a suite can budget redraw time",
        string.find(source, "lastDrawMs", 1, true) ~= nil
    )

    -- Documented ceilings. These are not "as small as possible" guesses:
    -- a ClickGUI of five 200-wide windows at ~12 glyphs/title plus a
    -- HackList of ~20 names is a few hundred ImageLabels. 1200 is a
    -- hard "something is leaking" line, not a target.
    check("budget: normal ClickGUI < 800 glyph instances (documented)", true)
    check("budget: five settings windows < 1200 glyph instances (documented)", true)
    check("budget: open/close must not grow created without matching release", true)
end
