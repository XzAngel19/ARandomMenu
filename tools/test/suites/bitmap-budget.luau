--!strict
--
-- Headless tests: bitmap performance, measured on the live contract.
--
-- Ceilings come from one harness run against A's 13b48da tree (see
-- docs/bitmap-budgets.md). They are leak lines, not targets. A later
-- renderer that rebuilds every frame, or that leaks holders across
-- destruct, crosses them.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("BitmapBudget")

    local source: any = ctx.shellSource
    if type(source) ~= "string" then
        check("no shell source; budget tests skip", false)
        return
    end

    check(
        "signature skip exists (no rebuild without a change)",
        string.find(source, "record.signature == signature", 1, true) ~= nil
            and string.find(source, "stats.skipped", 1, true) ~= nil
    )
    check(
        "the pool reuses glyph instances",
        string.find(source, "glyphsReused", 1, true) ~= nil
    )
    check(
        "release() exists so teardown can drop glyphs",
        string.find(source, "state.bitmapText.release", 1, true) ~= nil
    )

    local boot: any = bootShell(ctx)
    check("budget boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local bitmap: any = state.bitmapText
    check("state.bitmapText is published", type(bitmap) == "table")
    if type(bitmap) ~= "table" then
        return
    end

    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end

    -- Isolated holder: signature skip, reuse, release. The atlas is armed
    -- so ImageLabels exist and reused can actually climb.
    Inspect.armAtlas(bitmap)
    local probeParent: any = Mock.newInstance("Frame")
    probeParent.Name = "BudgetProbe"
    local textColor: any = env.Theme and env.Theme.text
    local skipped0: number = bitmap.stats.skipped
    local created0: number = bitmap.stats.glyphsCreated
    local reused0: number = bitmap.stats.glyphsReused
    bitmap.draw(probeParent, {{text = "BudgetHello", color = textColor}}, {
        Name = "Probe",
        TextSize = 16,
        shadow = true,
    })
    local createdAfterFirst: number = bitmap.stats.glyphsCreated
    check(
        "the first draw creates glyphs",
        createdAfterFirst > created0,
        tostring(createdAfterFirst - created0)
    )
    bitmap.draw(probeParent, {{text = "BudgetHello", color = textColor}}, {
        Name = "Probe",
        TextSize = 16,
        shadow = true,
    })
    check(
        "unchanged signature increments skipped",
        bitmap.stats.skipped == skipped0 + 1,
        tostring(bitmap.stats.skipped - skipped0)
    )
    check(
        "created does not grow without a change",
        bitmap.stats.glyphsCreated == createdAfterFirst,
        tostring(bitmap.stats.glyphsCreated - createdAfterFirst)
    )
    bitmap.draw(probeParent, {{text = "BudgetHello!", color = textColor}}, {
        Name = "Probe",
        TextSize = 16,
        shadow = true,
    })
    check(
        "a changed draw reuses pooled glyphs",
        bitmap.stats.glyphsReused > reused0,
        tostring(bitmap.stats.glyphsReused - reused0)
    )
    local probeHolder: any = probeParent:FindFirstChild("Probe")
    bitmap.release(probeHolder)
    check(
        "release() drops the holder from _live",
        probeHolder == nil or bitmap._live[probeHolder] == nil
    )
    check(
        "release() destroys the holder",
        probeHolder == nil or probeHolder.Parent == nil
    )

    -- Measured 2026-08-22 against this harness (A 13b48da, atlas armed):
    -- idle ClickGUI 402 glyphs / 45 holders. Five settings 1273 / 197.
    -- Navigator added none on top of that. Destruct left 0.
    -- Re-measured after A4: the numeric rows spell min and max on the
    -- rail (UI Settings alone adds eight such labels) and UI Settings
    -- gained the Menu style row — idle measured 552 on 2026-08-22. The
    -- ceiling keeps C's ~35% leak margin over the measure; it is still a
    -- leak alarm, not a target.
    local IDLE_GLYPH_CEILING: number = 700
    local FIVE_SETTINGS_CEILING: number = 1600
    local NAVIGATOR_CEILING: number = 800
    local HACKLIST_CEILING: number = 250

    Inspect.armAtlas(bitmap)
    local _idleHolders: number, idleGlyphs: number = Inspect.liveCounts(bitmap)
    check(
        "idle ClickGUI respects the measured glyph ceiling",
        idleGlyphs <= IDLE_GLYPH_CEILING,
        tostring(idleGlyphs) .. " > " .. tostring(IDLE_GLYPH_CEILING)
    )

    local hackGlyphs: number = 0
    for holder: any, record: any in pairs(bitmap._live) do
        local walk: any = holder
        local underHack: boolean = false
        while walk ~= nil do
            if tostring(walk.Name) == "HackList" then
                underHack = true
                break
            end
            walk = walk.Parent
        end
        if underHack and type(record.glyphs) == "table" then
            for _, glyph: any in ipairs(record.glyphs) do
                if glyph.Visible ~= false then
                    hackGlyphs += 1
                end
            end
        end
    end
    check(
        "HackList respects the measured glyph ceiling",
        hackGlyphs <= HACKLIST_CEILING,
        tostring(hackGlyphs)
    )

    local windows: any = state.windows
    local opened: {any} = {}
    if type(windows) == "table" and type(windows.OpenFeatureSettings) == "function" then
        for _, feature: any in ipairs(env.allFeatures or {}) do
            if feature.hasSettings == true then
                local window: any = windows.OpenFeatureSettings(feature)
                if window ~= nil then
                    table.insert(opened, window)
                end
                if #opened >= 5 then
                    break
                end
            end
        end
    end
    check("opened five settings windows for the budget", #opened >= 5)
    Inspect.armAtlas(bitmap)
    local _fiveHolders: number, fiveGlyphs: number = Inspect.liveCounts(bitmap)
    check(
        "five settings windows respect the measured glyph ceiling",
        fiveGlyphs <= FIVE_SETTINGS_CEILING,
        tostring(fiveGlyphs) .. " > " .. tostring(FIVE_SETTINGS_CEILING)
    )

    -- Open/close 20 times must not create a new pool each cycle.
    local createdBeforeCycle: number = bitmap.stats.glyphsCreated
    if #opened > 0 then
        local sample: any = opened[1]
        local feature: any = nil
        for _, card: any in ipairs(env.allFeatures or {}) do
            if card.settingsWindow == sample then
                feature = card
                break
            end
        end
        if feature ~= nil then
            for _ = 1, 20 do
                sample:SetVisible(false)
                windows.OpenFeatureSettings(feature)
            end
        end
    end
    check(
        "open/close 20 times does not leak created glyphs",
        bitmap.stats.glyphsCreated - createdBeforeCycle < 80,
        tostring(bitmap.stats.glyphsCreated - createdBeforeCycle)
    )

    if state.navigator and type(state.navigator.Open) == "function" then
        -- Isolate navigator cost from the five settings: close them first.
        for _, window: any in ipairs(opened) do
            window:SetVisible(false)
        end
        Inspect.armAtlas(bitmap)
        local _, beforeNav: number = Inspect.liveCounts(bitmap)
        state.navigator.Open()
        if type(state.navigator.refresh) == "function" then
            state.navigator.refresh()
        end
        Inspect.armAtlas(bitmap)
        local _, navGlyphs: number = Inspect.liveCounts(bitmap)
        local navOnly: number = math.max(0, navGlyphs - beforeNav)
        -- The screen itself is adopted at boot; refresh may add cells.
        check(
            "Navigator respects the measured glyph ceiling",
            navOnly <= NAVIGATOR_CEILING,
            "delta=" .. tostring(navOnly) .. " total=" .. tostring(navGlyphs)
        )
        if type(state.navigator.Close) == "function" then
            state.navigator.Close()
        end
    end

    if type(state.destruct) == "function" then
        state.destruct()
    end
    local liveAfter: number, glyphsAfter: number = Inspect.liveCounts(bitmap)
    check(
        "destruct leaves zero live bitmap records",
        liveAfter == 0 and glyphsAfter == 0,
        "holders=" .. tostring(liveAfter) .. " glyphs=" .. tostring(glyphsAfter)
    )
end
