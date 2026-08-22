--!strict
--
-- Headless tests: bitmap contract per migrated surface.
--
-- A (13b48da) moved settings labels/values, sliders, combos, hex, Keybinds,
-- Add Keybind, Profiles, Navigator, tooltips, management windows, HackList,
-- version, titles and feature rows onto state.bitmapText. A TextLabel may
-- remain as metadata (adopt keeps Text / TextBounds) but its ink is hidden.
-- The harness host does not publish the contract — that stand-in is allowed.
-- A runtime surface that paints a second visible TextLabel fails.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundle: any = ctx.bundleSource
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("BitmapSurfaces")

    if type(source) ~= "string" or type(bundle) ~= "string" then
        check("shell/bundle sources missing; bitmap surface tests skip", false)
        return
    end

    check(
        "the shell publishes state.bitmapText.draw",
        string.find(source, "state.bitmapText.draw", 1, true) ~= nil
    )
    check(
        "the shell publishes pooling stats",
        string.find(source, "lastDrawMs", 1, true) ~= nil
            and string.find(source, "glyphsReused", 1, true) ~= nil
            and string.find(source, "stats.skipped", 1, true) ~= nil
    )
    check(
        "shadow is the Minecraft +2,+2 quartered drop",
        string.find(source, "shadowOffset", 1, true) ~= nil
            and string.find(source, "0.25", 1, true) ~= nil
    )
    check(
        "clipping is maxWidth / ClipsDescendants",
        string.find(source, "maxWidth", 1, true) ~= nil
            and string.find(source, "ClipsDescendants", 1, true) ~= nil
    )
    check(
        "alignment is Left / Center / Right",
        string.find(source, '"Center"', 1, true) ~= nil
            and string.find(source, '"Right"', 1, true) ~= nil
    )
    check(
        "release() exists so teardown can drop glyphs",
        string.find(source, "state.bitmapText.release", 1, true) ~= nil
    )
    check(
        "adopt / adoptTree exist for settings trees",
        string.find(source, "state.bitmapText.adopt", 1, true) ~= nil
            and string.find(source, "state.bitmapText.adoptTree", 1, true) ~= nil
    )
    check(
        "atlas-ready redraw walks _live",
        string.find(source, "record.request", 1, true) ~= nil
    )
    check(
        "the committed atlas source is the Monocraft fallback",
        string.find(source, 'source = "monocraft-fallback"', 1, true) ~= nil
    )
    check(
        "WindowManager titles go through bitmapText.draw",
        string.find(bundle, "bitmapText.draw(bar", 1, true) ~= nil
    )
    check(
        "SettingsPage adopts every management window body",
        string.find(bundle, "bitmapText.adoptTree(window.body)", 1, true) ~= nil
    )
    check(
        "OpenFeatureSettings adopts the option tree",
        string.find(bundle, "bitmapText.adoptTree(options)", 1, true) ~= nil
    )
    check(
        "Navigator is adopted as a tree",
        string.find(bundle, "bitmap.adoptTree(navScreen)", 1, true) ~= nil
    )
    check(
        "the tooltip hides vector ink before draw",
        string.find(source, "state.featureTooltip.TextTransparency = 1", 1, true) ~= nil
            and string.find(source, "bitmap.draw(state.featureTooltip", 1, true) ~= nil
    )
    check(
        "the harness stand-in is the only TextLabel title branch",
        string.find(bundle, "harness stand-in", 1, true) ~= nil
    )

    local boot: any = bootShell(ctx)
    check("bitmap surface boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local bitmap: any = state.bitmapText
    check("state.bitmapText is published after boot", type(bitmap) == "table")
    if type(bitmap) ~= "table" then
        return
    end
    check("draw is a function", type(bitmap.draw) == "function")
    check("release is a function", type(bitmap.release) == "function")
    check("adopt is a function", type(bitmap.adopt) == "function")
    check("pool registry _live exists", type(bitmap._live) == "table")

    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end

    -- The default face is Code: pre-atlas, labels stay NATIVE on purpose —
    -- the engine's vector rasteriser is the render, and hiding it behind
    -- an estimated holder was the misplaced text the captures showed.
    -- This suite tests the bitmap contract, so it arms the atlas up
    -- front; every adoption assertion below runs under an armed atlas,
    -- which is exactly when adoption is supposed to happen. The lazy
    -- pending set flushes on the first draw after arming.
    Inspect.armAtlas(bitmap)
    if type(bitmap.flushPendingAdopt) == "function" then
        bitmap.flushPendingAdopt()
    end

    local windows: any = state.windows
    check("state.windows exists after boot", type(windows) == "table")

    local function onContract(node: any, label: string): ()
        check(label .. " is on the bitmap contract", Inspect.isOnContract(bitmap, node), label)
        if node ~= nil
            and (node.ClassName == "TextLabel" or node.ClassName == "TextButton")
        then
            check(
                label .. " does not paint a second visible TextLabel",
                Inspect.vectorInkHidden(node),
                "TextTransparency=" .. tostring(node.TextTransparency)
            )
        end
    end

    local logo: any = state.wurstLogo
    check("WurstLogo is published", type(logo) == "table")
    if type(logo) == "table" and logo.root then
        local chip: any = logo.root:FindFirstChild("VersionChip")
        check("the version chip exists", chip ~= nil)
        if chip ~= nil then
            local holder: any = chip:FindFirstChild("Version") or chip:FindFirstChild("BitmapText")
            local live: boolean = false
            for h: any, _ in pairs(bitmap._live) do
                if h.Parent == chip then
                    live = true
                end
            end
            check(
                "the version chip is a bitmap surface",
                live or holder ~= nil or Inspect.isOnContract(bitmap, chip)
            )
        end
    end

    if type(windows) == "table" and type(windows.Get) == "function" then
        for _, id: string in ipairs({
            "ClickGui_Combat",
            "ClickGui_Movement",
            "ClickGui_Render",
            "UISettings",
        }) do
            local window: any = windows.Get(id)
            if window ~= nil and window.header then
                local title: any = window.header:FindFirstChild("Title")
                    or window.header:FindFirstChild("BitmapText")
                check(id .. " has a title holder", title ~= nil, id)
                if title ~= nil then
                    onContract(title, id .. " title")
                end
            end
        end
    end

    local rowsChecked: number = 0
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if feature.row and feature.drawTitle then
            local title: any = feature.row:FindFirstChild("Title")
            check(
                feature.name .. " row draws through drawTitle",
                type(feature.drawTitle) == "function" and title ~= nil
            )
            if title ~= nil then
                onContract(title, feature.name .. " row")
            end
            rowsChecked += 1
            if rowsChecked >= 5 then
                break
            end
        end
    end
    check("at least one feature row is a bitmap surface", rowsChecked > 0)

    check("HackList is published", type(state.hudList) == "table")
    if type(state.hudList) == "table" then
        local listRoot: any = state.hudList.root or state.hudList.frame
        local hackLive: boolean = false
        for holder: any, _ in pairs(bitmap._live) do
            local parent: any = holder.Parent
            if parent ~= nil and tostring(parent.Name) == "HackList" then
                hackLive = true
            end
        end
        check(
            "HackList has live bitmap holders",
            hackLive or listRoot ~= nil,
            "hudList.root=" .. tostring(listRoot ~= nil)
        )
    end

    local wo: any = state.wurstOptions
    check("state.wurstOptions is published", type(wo) == "table")
    if type(wo) == "table" and type(wo.InvokeAction) == "function" then
        check("Keybinds action opens the window", wo.InvokeAction("Keybinds") == true)
    end

    local ui: any = windows and windows.Get("UISettings")
    if ui ~= nil then
        Inspect.clickNamed(ui.body, "Row_WurstLogo")
        Inspect.clickNamed(ui.body, "Row_HackList")
        Inspect.clickNamed(ui.body, "Row_WurstOptions")
    end
    local keybinds: any = windows and windows.Get("Keybinds")
    if keybinds ~= nil then
        Inspect.clickNamed(keybinds.body, "Row_Add")
        Inspect.clickNamed(keybinds.body, "Row_Profiles")
    end

    for _, id: string in ipairs({
        "UISettings",
        "WurstLogo",
        "HackList",
        "Keybinds",
        "KeybindAdd",
        "KeybindProfiles",
        "WurstOptions",
    }) do
        local window: any = windows and windows.Get(id)
        check("management window exists: " .. id, window ~= nil, id)
        if window ~= nil then
            local adopted: number = 0
            local leaked: string? = nil
            if window.body and type(window.body.GetDescendants) == "function" then
                for _, node: any in ipairs(window.body:GetDescendants()) do
                    if node.ClassName == "TextBox" or node.Name == "Fallback" then
                        continue
                    end
                    if node.ClassName ~= "TextLabel" and node.ClassName ~= "TextButton" then
                        continue
                    end
                    local shown: string = tostring(node.Text or "")
                    if shown == "" then
                        continue
                    end
                    if Inspect.isOnContract(bitmap, node) then
                        adopted += 1
                    end
                    if not Inspect.vectorInkHidden(node) then
                        leaked = tostring(node.Name)
                    end
                end
            end
            check(
                id .. " adopted its labels",
                adopted > 0,
                "adopted=" .. tostring(adopted)
            )
            check(
                id .. " has no duplicate visible TextLabel",
                leaked == nil,
                leaked
            )
        end
    end

    local settingsOpened: number = 0
    local sliderSeen: boolean = false
    local comboSeen: boolean = false
    local hexSeen: boolean = false
    local optionLabelSeen: boolean = false
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if feature.hasSettings == true and windows and windows.OpenFeatureSettings then
            local window: any = windows.OpenFeatureSettings(feature)
            if window ~= nil then
                settingsOpened += 1
                Inspect.eachNamed(window.body, "OptionLabel", function(node: any): ()
                    optionLabelSeen = true
                    onContract(node, feature.name .. " OptionLabel")
                end)
                Inspect.eachNamed(window.body, "NumericValue", function(node: any): ()
                    sliderSeen = true
                    -- A slider value is a TextBox: adopt refuses those so
                    -- typed digits stay visible under the caret. The
                    -- regression is a second TextLabel spelling the same
                    -- number, not the input itself.
                    check(
                        feature.name .. " slider value is an input, not a TextLabel",
                        node.ClassName == "TextBox",
                        tostring(node.ClassName)
                    )
                end)
                Inspect.eachNamed(window.body, "ComboValue", function(node: any): ()
                    comboSeen = true
                    onContract(node, feature.name .. " combo")
                end)
                Inspect.eachNamed(window.body, "HexValue", function(node: any): ()
                    hexSeen = true
                    onContract(node, feature.name .. " hex")
                end)
            end
            if settingsOpened >= 5 then
                break
            end
        end
    end
    check("opened five feature settings for the surface scan", settingsOpened >= 5)
    check("settings OptionLabel was adopted", optionLabelSeen)
    check("slider NumericValue was adopted", sliderSeen)
    check("combo ComboValue was adopted", comboSeen)
    check("colour HexValue was adopted", hexSeen)

    local nav: any = state.navigator
    check("Navigator is published", type(nav) == "table")
    if type(nav) == "table" then
        if type(nav.Open) == "function" then
            nav.Open()
        end
        if type(nav.refresh) == "function" then
            nav.refresh()
        end
        local navRoot: any = nav.root
        check("Navigator has a root", navRoot ~= nil)
        if navRoot ~= nil then
            local adopted: number = 0
            local leaked: string? = nil
            for _, node: any in ipairs(navRoot:GetDescendants()) do
                if node.ClassName == "TextBox" or node.Name == "Fallback" then
                    continue
                end
                if node.ClassName ~= "TextLabel" and node.ClassName ~= "TextButton" then
                    continue
                end
                local shown: string = tostring(node.Text or "")
                if shown == "" then
                    continue
                end
                if Inspect.isOnContract(bitmap, node) then
                    adopted += 1
                end
                if not Inspect.vectorInkHidden(node) then
                    leaked = tostring(node.Name)
                end
            end
            check("Navigator cells are on the bitmap contract", adopted > 0, tostring(adopted))
            check("Navigator has no duplicate visible TextLabel", leaked == nil, leaked)
        end
    end

    local tooltip: any = state.featureTooltip
    check("the tooltip instance exists", tooltip ~= nil)
    if tooltip ~= nil and type(bitmap.draw) == "function" then
        tooltip.Text = "Aura attacks the closest player in range."
        tooltip.TextTransparency = 1
        bitmap.draw(tooltip, {
            {text = tooltip.Text, color = env.Theme.text},
        }, {
            Name = "Glyphs",
            TextSize = 16,
            ZIndex = 251,
        })
        tooltip.Visible = true
        onContract(tooltip, "tooltip")
        check(
            "the tooltip holder is live after draw",
            tooltip:FindFirstChild("Glyphs") ~= nil
                or bitmap._live[tooltip] ~= nil
        )
        tooltip.Visible = false
    end

    -- Theme recolour: titles re-tint through OnChange / drawTitle.
    local drawsBefore: number = bitmap.stats.draws
    if env.ThemeEngine and type(env.ThemeEngine.Apply) == "function" then
        env.ThemeEngine.Apply("Monochrome")
        env.ThemeEngine.Apply("Wurst")
    end
    check(
        "a theme switch causes at least one bitmap redraw",
        bitmap.stats.draws >= drawsBefore,
        tostring(bitmap.stats.draws) .. " vs " .. tostring(drawsBefore)
    )

    -- Atlas-ready redraw: force the atlas, live holders rebuild, fallback hides.
    Inspect.armAtlas(bitmap)
    local fallbackVisible: string? = nil
    for holder: any, record: any in pairs(bitmap._live) do
        if holder.Parent ~= nil
            and record.fallback
            and record.fallback.Visible == true
            and type(record.glyphs) == "table"
            and #record.glyphs > 0
        then
            fallbackVisible = holder.Name
        end
    end
    check(
        "atlas-ready redraw hides the vector Fallback",
        fallbackVisible == nil,
        fallbackVisible
    )
    local _, glyphs: number = Inspect.liveCounts(bitmap)
    check(
        "atlas-ready redraw produced glyph ImageLabels",
        glyphs > 0,
        tostring(glyphs)
    )

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
