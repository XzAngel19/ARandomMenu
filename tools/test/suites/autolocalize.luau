--!strict
--
-- Headless tests: ClickGUI strings must not go through Roblox AutoLocalize.
--
-- The capture translated "Other" → "Otras razones", "Text" → "Texto",
-- "Disabled" → "Desactivado", "Zoom" → "Hacer zoom". Official Wurst has
-- no locale table. Helpers have to set AutoLocalize = false. Until A
-- lands that, the suite records the gap.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    section("AutoLocalize")

    local bundle: any = ctx.bundleSource
    local source: any = ctx.shellSource
    if type(bundle) ~= "string" or type(source) ~= "string" then
        check("sources available for AutoLocalize", false)
        return
    end

    check(
        "the ClickGUI does not opt in to AutoLocalize",
        string.find(bundle, "AutoLocalize = true", 1, true) == nil
            and string.find(source, "AutoLocalize = true", 1, true) == nil
    )

    local helpersSetFalse: boolean = string.find(
        source,
        "AutoLocalize = false",
        1,
        true
    ) ~= nil or string.find(bundle, "AutoLocalize = false", 1, true) ~= nil
    check("helpers disable AutoLocalize", helpersSetFalse)

    -- After A lands the flag, a boot must keep the English tokens the
    -- capture lost.
    for _, token: string in ipairs({ "Other", "Text", "Disabled", "Zoom" }) do
        check(
            "the English token " .. token .. " survives in the bundle",
            string.find(bundle, token, 1, true) ~= nil
                or string.find(source, token, 1, true) ~= nil
        )
    end

    -- The suite-wide host is a harness fixture created before the production
    -- shell executes, so its ScreenGui does not prove the live root's flag.
    -- Hold the live assignment directly instead of testing the mock fixture.
    check(
        "the live ScreenGui root disables AutoLocalize",
        string.find(source, "ScreenGui.AutoLocalize = false", 1, true) ~= nil
    )
end
