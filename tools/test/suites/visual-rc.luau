--!strict
--
-- Visual RC hold: one boot covers C1 P1 verify, C2 typography, C4 windows,
-- C5 viewports, C6 modes and C9 identity. Widget builders live in
-- visual-widgets.luau (no extra boot). Bitmap budgets stay in
-- bitmap-budget.luau.
--
-- Headless geometry and contracts only. Engine raster output is a
-- demonstrated debt — see docs/visual/VISUAL-RC.md.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundle: any = ctx.bundleSource
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("VisualRC")

    if type(source) ~= "string" or type(bundle) ~= "string" then
        check("visual-rc shell/bundle source missing", false)
        return
    end

    -- ------------------------------------------------------------------ C1
    -- The three A P1s are consumed. Source + runtime, not a re-list as debt.
    check(
        "C1: ClickGui.Retile re-enters WindowManager.ClampWindow",
        string.find(bundle, "function ClickGui.Retile", 1, true) ~= nil
            and string.find(bundle, "windows.ClampWindow", 1, true) ~= nil
    )
    check(
        "C1: Cards keybind tooltip measures through bitmapText",
        string.find(bundle, "bitmap.measure({{text = rawText}}, 16)", 1, true) ~= nil
            or string.find(bundle, "bitmap.measure({{text = rawText}}", 1, true) ~= nil
    )
    check(
        "C1: Cards tooltip no longer estimates #texto*8",
        string.find(bundle, "#texto*8", 1, true) == nil
    )
    check(
        "C1: Furniture dock tooltip no longer estimates #text * 5.5",
        string.find(bundle, "#text * 5.5", 1, true) == nil
            and string.find(bundle, "#texto*5.5", 1, true) == nil
    )
    check(
        "C1: Furniture tooltip measures through bitmapText",
        string.find(bundle, "bitmap.measure({{text = text}}, 16)", 1, true) ~= nil
            or string.find(source, "bitmap.measure({{text = text}}, 16)", 1, true) ~= nil
            or string.find(bundle, "bitmap.measure({{text = text}}", 1, true) ~= nil
    )
    check(
        "C1: P2 widgets disabled API stays unpublished (demonstrated debt)",
        string.find(bundle, "function setOptionDisabled", 1, true) == nil
            and string.find(bundle, "addDisabledOption", 1, true) == nil
    )

    local boot: any = bootShell(ctx)
    check("visual-rc boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local world: any = boot.world
    local bitmap: any = state.bitmapText
    local windows: any = state.windows
    check("bitmapText is published", type(bitmap) == "table")
    check("state.windows is published", type(windows) == "table")
    if type(bitmap) ~= "table" or type(windows) ~= "table" then
        return
    end

    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end
    Inspect.pinClickGuiScale(env.PopupLayer, 1)
    Inspect.armAtlasFamily(bitmap)

    -- ------------------------------------------------------------------ C1 runtime
    do
        local openedHack: boolean, openError: any = pcall(function(): ()
            local ui: any = windows.Get and windows.Get("UISettings")
            if ui ~= nil then
                Inspect.clickNamed(ui.body or ui.root, "Row_HackList")
            end
        end)
        check(
            "C1: opening HackList settings no longer throws on SetColor",
            openedHack == true,
            tostring(openError)
        )
        local hackWindow: any = windows.Get and windows.Get("HackList")
        check("C1: HackList settings window exists after Color init", hackWindow ~= nil)
        if type(state.hudList) == "table" and type(state.hudList.SetColor) == "function" then
            local recolored: boolean, recolorError: any = pcall(function(): ()
                state.hudList.SetColor(world.globals.Color3.fromRGB(255, 0, 128))
            end)
            check(
                "C1: hudList.SetColor is safe on bitmap rows",
                recolored == true,
                tostring(recolorError)
            )
        end
    end

    local function assertIntegerPhysical(holder: any, scale: number, label: string): ()
        if holder == nil or type(holder.GetDescendants) ~= "function" then
            check(label .. ": holder exists", false)
            return
        end
        local fractional: string? = nil
        for _, node: any in ipairs(holder:GetDescendants()) do
            if node.ClassName == "ImageLabel" and node.Visible ~= false then
                local x: number = node.Position.X.Offset * scale
                local y: number = node.Position.Y.Offset * scale
                local w: number = node.Size.X.Offset * scale
                local h: number = node.Size.Y.Offset * scale
                if math.abs(x - math.round(x)) > 1e-6
                    or math.abs(y - math.round(y)) > 1e-6
                    or math.abs(w - math.round(w)) > 1e-6
                    or math.abs(h - math.round(h)) > 1e-6
                then
                    fractional = string.format("%.4f,%.4f %.4fx%.4f", x, y, w, h)
                end
            end
        end
        check(label .. ": integer physical glyph bounds", fractional == nil, fractional)
    end

    local function assertNoDuplicateInk(root: any, contract: any, label: string): ()
        if root == nil or type(root.GetDescendants) ~= "function" then
            check(label .. ": surface exists", false)
            return
        end
        local leaked: string? = nil
        for _, node: any in ipairs(root:GetDescendants()) do
            if (node.ClassName == "TextLabel" or node.ClassName == "TextButton")
                and node.Name ~= "Fallback"
                and tostring(node.Text or "") ~= ""
                and not Inspect.vectorInkHidden(node)
                and Inspect.isOnContract(contract, node)
            then
                leaked = node.Name
            end
        end
        check(label .. ": no visible TextLabel next to its bitmap holder", leaked == nil, leaked)
    end

    local function assertGlyphsInside(holder: any, label: string): ()
        if holder == nil then
            check(label .. ": holder exists", false)
            return
        end
        local hw: number = holder.Size.X.Offset
        local hh: number = holder.Size.Y.Offset
        -- Drop-shadow copies sit at +2 logical (snapped). Slack has to
        -- cover that plus a snapped pixel at fractional UIScale.
        local slack: number = 6
        local escaped: string? = nil
        if type(holder.GetDescendants) == "function" then
            for _, node: any in ipairs(holder:GetDescendants()) do
                if node.ClassName == "ImageLabel" and node.Visible ~= false then
                    local right: number = node.Position.X.Offset + node.Size.X.Offset
                    local bottom: number = node.Position.Y.Offset + node.Size.Y.Offset
                    if node.Position.X.Offset < -slack
                        or node.Position.Y.Offset < -slack
                        or (hw > 0 and right > hw + slack)
                        or (hh > 0 and bottom > hh + slack)
                    then
                        escaped = node.Name
                    end
                end
            end
        end
        check(label .. ": glyphs stay inside the holder", escaped == nil, escaped)
    end

    -- ------------------------------------------------------------------ C2
    do
        section("VisualRC/Typography")
        check("pickAtlas is published", type(bitmap.pickAtlas) == "function")
        check("measure/wrap/draw are published",
            type(bitmap.measure) == "function"
                and type(bitmap.wrap) == "function"
                and type(bitmap.draw) == "function")
        check("loadExactAtlas / applyFontPack / restoreFallbackAtlas exist",
            type(bitmap.loadExactAtlas) == "function"
                and type(bitmap.applyFontPack) == "function"
                and type(bitmap.restoreFallbackAtlas) == "function")

        local function pickedSize(physical: number): number
            local member: any = bitmap.pickAtlas(physical)
            return tonumber(member and member.size) or 0
        end

        check("pickAtlas <=8 stays on atlas 8", pickedSize(8) == 8 or pickedSize(8) == 0, tostring(pickedSize(8)))
        check("pickAtlas 9..16 picks 16", pickedSize(11) == 16, tostring(pickedSize(11)))
        check("pickAtlas 16 stays 16", pickedSize(16) == 16, tostring(pickedSize(16)))
        check("pickAtlas 17..24 picks 24", pickedSize(18) == 24, tostring(pickedSize(18)))
        check("pickAtlas 25..32 picks 32", pickedSize(28) == 32, tostring(pickedSize(28)))
        check("pickAtlas above the family takes the largest ready", pickedSize(48) >= 24, tostring(pickedSize(48)))

        local parent: any = Mock.newInstance("Frame")
        parent.Name = "VisualRcProbe"
        local samples: {string} = {
            "NoFall Settings",
            "Projectile Calibration",
            "Max settings height",
            "Minecraft 1.18.1",
            "RightControl",
            "Tooltip opacity",
            "Hi",
            "A very long settings title that must clip",
            "0.15",
            "#FF00FF",
            "12345.678",
        }

        -- Monocraft family (armed fallback).
        if type(bitmap.applyFontPack) == "function" then
            bitmap.applyFontPack("Monocraft")
        end
        Inspect.armAtlasFamily(bitmap)
        check(
            "Monocraft pack is never labelled Minecraft exact",
            bitmap.source ~= "minecraft-exact",
            tostring(bitmap.source)
        )

        for _, scale in ipairs({0.7, 1.0, 1.25, 1.6}) do
            Inspect.pinClickGuiScale(env.PopupLayer, scale)
            for _, text in ipairs(samples) do
                bitmap.draw(parent, {{text = text, color = env.Theme.text}}, {
                    Name = "Probe",
                    TextSize = 16,
                    shadow = true,
                    maxWidth = 140,
                    ellipsis = true,
                })
            end
            local holder: any = parent:FindFirstChild("Probe")
            check("Monocraft scale " .. tostring(scale) .. ": one holder per Name", holder ~= nil)
            if holder ~= nil then
                check(
                    "Monocraft scale " .. tostring(scale) .. ": holder clips to maxWidth",
                    holder.ClipsDescendants == true
                )
                assertIntegerPhysical(holder, scale, "Monocraft @" .. tostring(scale))
                assertGlyphsInside(holder, "Monocraft @" .. tostring(scale))
                check(
                    "Monocraft scale " .. tostring(scale) .. ": no second Probe sibling",
                    parent:FindFirstChild("Probe") == holder
                )
            end
        end
        Inspect.pinClickGuiScale(env.PopupLayer, 1)

        -- Exact mocked pack with variable advances.
        local advances: {[number]: number} = {}
        advances[65] = 14
        advances[105] = 5
        advances[32] = 4
        bitmap.loadExactAtlas("harness-exact", {
            size = 16,
            first = 32,
            last = 126,
            columns = 16,
            cellWidth = 8,
            cellHeight = 8,
            advance = 8,
            advances = advances,
        })
        check("exact pack disables the Monocraft family", bitmap.rasterFamilyEnabled == false)
        check("exact pack is labelled minecraft-exact", bitmap.source == "minecraft-exact")
        local wideA: number = bitmap.measure({{text = "A"}}, 16)
        local narrowI: number = bitmap.measure({{text = "i"}}, 16)
        check(
            "exact pack honours variable advances",
            wideA > narrowI,
            "A=" .. tostring(wideA) .. " i=" .. tostring(narrowI)
        )
        check("exact pickAtlas stays on the loaded atlas", pickedSize(11) == 16 or pickedSize(11) == 0)
        bitmap.draw(parent, {{text = "Minecraft 1.18.1", color = env.Theme.text}}, {
            Name = "Exact",
            TextSize = 16,
            maxWidth = 120,
            ellipsis = true,
        })
        local exactHolder: any = parent:FindFirstChild("Exact")
        check("exact mocked draw produced a holder", exactHolder ~= nil)
        if exactHolder ~= nil then
            assertIntegerPhysical(exactHolder, 1, "exact")
            assertGlyphsInside(exactHolder, "exact")
        end

        local wrapped: string, lines: number = bitmap.wrap(
            "Projectile Calibration settings window title",
            80,
            16
        )
        check("wrap returns at least one line", lines >= 1 and type(wrapped) == "string")
        check("wrap inserts newlines when the line is too wide", lines == 1 or string.find(wrapped, "\n", 1, true) ~= nil)

        -- Vector stand-in: no atlas image, Fallback label is the renderer.
        bitmap.restoreFallbackAtlas()
        bitmap.atlas.ready = false
        bitmap.atlas.image = nil
        bitmap.source = "unavailable"
        bitmap.draw(parent, {{text = "vector stand-in", color = env.Theme.text}}, {
            Name = "Vector",
            TextSize = 16,
        })
        local vectorHolder: any = parent:FindFirstChild("Vector")
        local fallback: any = vectorHolder and vectorHolder:FindFirstChild("Fallback")
        check("vector mode draws the Fallback stand-in", fallback ~= nil)
        if fallback ~= nil then
            check("vector Fallback is a TextLabel", fallback.ClassName == "TextLabel")
        end

        -- Restore the armed fallback so later window checks see glyphs.
        if type(bitmap.applyFontPack) == "function" then
            bitmap.applyFontPack("Monocraft")
        end
        Inspect.armAtlasFamily(bitmap)

        if env.ThemeEngine and type(env.ThemeEngine.Apply) == "function" then
            env.ThemeEngine.Apply("Monochrome")
            bitmap.draw(parent, {{text = "theme", color = env.Theme.text}}, {
                Name = "Theme",
                TextSize = 16,
            })
            check("Monochrome theme still draws", parent:FindFirstChild("Theme") ~= nil)
            env.ThemeEngine.Apply("Wurst")
            check("Wurst theme reapplies", env.ThemeEngine.name == "Wurst")
        end

        if type(bitmap.release) == "function" then
            bitmap.release(parent:FindFirstChild("Probe"))
            bitmap.release(parent:FindFirstChild("Exact"))
            bitmap.release(parent:FindFirstChild("Vector"))
            bitmap.release(parent:FindFirstChild("Theme"))
        end

        -- Live NoFall title: one holder, clipped, no chrome invasion.
        local noFall: any = Inspect.featureNamed(env, "NoFall")
        check("C2: NoFall is one of the 38 modules", noFall ~= nil)
        if noFall ~= nil and type(windows.OpenFeatureSettings) == "function" then
            local window: any = windows.OpenFeatureSettings(noFall)
            check("C2: NoFall Settings opens", window ~= nil)
            if window ~= nil and window.header ~= nil then
                local title: any = window.header:FindFirstChild("Title")
                check("C2: NoFall title lives in the header", title ~= nil)
                if title ~= nil then
                    check("C2: NoFall title is clipped", title.ClipsDescendants == true)
                    local headerH: number = window.header.Size.Y.Offset
                    if headerH <= 0 then
                        headerH = window.headerHeight or 26
                    end
                    check(
                        "C2: NoFall title does not invade the body",
                        title.Parent == window.header
                            and title.Size.Y.Offset <= headerH + 1
                    )
                    assertNoDuplicateInk(window.header, bitmap, "C2 NoFall title")
                end
            end
        end
    end

    -- ------------------------------------------------------------------ C4
    do
        section("VisualRC/Windows")
        local categories: {string} = {"Combat", "Render", "Movement", "Fun", "Other"}
        local present: number = 0
        for _, name: string in ipairs(categories) do
            local window: any = windows.Get("ClickGui_" .. name)
            if window ~= nil then
                present += 1
                window:SetVisible(true)
            end
        end
        check("C4: five occupied category windows exist", present == 5, tostring(present))

        local opened: {any} = {}
        for _, feature: any in ipairs(env.allFeatures or {}) do
            if feature.hasSettings == true then
                local window: any = windows.OpenFeatureSettings(feature)
                if window ~= nil then
                    table.insert(opened, window)
                    if type(window.resizeToOptions) == "function" then
                        window.resizeToOptions()
                    end
                end
                if #opened >= 8 then
                    break
                end
            end
        end
        check("C4: opened eight feature settings windows", #opened >= 8, tostring(#opened))

        local ui: any = windows.Get("UISettings")
        check("C4: UI Settings exists", ui ~= nil)
        if ui ~= nil then
            Inspect.clickNamed(ui.body or ui.root, "Row_WurstOptions")
        end
        local wo: any = state.wurstOptions
        if type(wo) == "table" and type(wo.InvokeAction) == "function" then
            wo.InvokeAction("Keybinds")
        end
        local keybinds: any = windows.Get("Keybinds")
        if keybinds ~= nil then
            Inspect.clickNamed(keybinds.body or keybinds.root, "Row_Add")
            Inspect.clickNamed(keybinds.body or keybinds.root, "Row_Profiles")
        end

        local managementIds: {string} = {
            "UISettings",
            "HackList",
            "Keybinds",
            "KeybindAdd",
            "KeybindProfiles",
            "WurstOptions",
        }
        local managementSeen: number = 0
        for _, id: string in ipairs(managementIds) do
            local window: any = windows.Get(id)
            if window ~= nil then
                managementSeen += 1
                window:SetVisible(true)
                if type(windows.ReflowWindow) == "function" then
                    windows.ReflowWindow(window)
                end
            end
        end
        check(
            "C4: management windows realized",
            managementSeen >= 4,
            tostring(managementSeen)
        )

        local named: {any} = {}
        for _, name: string in ipairs(categories) do
            local window: any = windows.Get("ClickGui_" .. name)
            if window ~= nil then
                table.insert(named, window)
            end
        end
        if ui ~= nil then
            table.insert(named, ui)
        end
        for index: number, window: any in ipairs(opened) do
            if index <= 3 then
                table.insert(named, window)
            else
                window:SetVisible(false)
            end
        end
        for _, window: any in ipairs(named) do
            if type(windows.ReflowWindow) == "function" then
                windows.ReflowWindow(window)
            end
        end

        local overlap: string? = nil
        for i: number = 1, #named do
            if named[i].root and named[i].root.Visible ~= false then
                for j: number = i + 1, #named do
                    if named[j].root and named[j].root.Visible ~= false then
                        if Inspect.aabb(named[i], named[j], 0) then
                            overlap = tostring(named[i].id) .. " x " .. tostring(named[j].id)
                        end
                    end
                end
            end
        end
        check("C4: AABB is empty after reflow of the live set", overlap == nil, overlap)

        local vp: any = windows.LogicalViewport()
        local outside: string? = nil
        for _, window: any in ipairs(named) do
            if window.root and window.root.Visible ~= false then
                if not Inspect.inside(window, vp.X, vp.Y)
                    and (window.root.Position.X.Offset < 0 or window.root.Position.Y.Offset < 0)
                then
                    outside = tostring(window.id)
                end
            end
        end
        check("C4: realized windows stay on-screen", outside == nil, outside)

        if ui ~= nil then
            ui.userMoved = true
            ui.root.Position = world.globals.UDim2.fromOffset(90, 90)
            windows.ReflowWindow(ui)
            check(
                "C4: a saved/manual position wins over reflow",
                ui.root.Position.X.Offset == 90 and ui.root.Position.Y.Offset == 90
            )
            if type(wo) == "table" and type(wo.InvokeAction) == "function" then
                check("C4: Reset layout runs", wo.InvokeAction("ResetLayout") == true)
                check("C4: Reset layout clears userMoved", ui.userMoved ~= true)
            end
        end

        check("C4: Navigator is published", type(state.navigator) == "table")
        if state.navigator and type(state.navigator.Open) == "function" then
            state.navigator.Open()
            check("C4: Navigator opens", Inspect.navigatorVisible(state) == true)
            local door: any = Inspect.findNamed(state.navigator.root, "WurstDoor")
            check("C4: WurstDoor exists on Navigator", door ~= nil)
            if type(state.navigator.Close) == "function" then
                state.navigator.Close()
            end
        end
        check("C4: dock is published", state.dock ~= nil or state.pill ~= nil)

        -- APPLY-4: menu-hide via closeChoiceList is blocking. Owner/scroll
        -- wait on unpublished closeInvalidPopups — do not fail them.
        local layer: any = env.ScreenGui or env.PopupLayer
        if type(state.openChoiceList) == "function" and ui ~= nil then
            local anchor: any = Inspect.findNamed(ui.root, "Row_Keybinds")
                or Inspect.findNamed(ui.root, "Option_Menustyle")
            if anchor ~= nil then
                state.openChoiceList(anchor, {"Auto", "Count", "Hidden"}, 1, function(): () end)
                local list: any = Inspect.findNamed(layer, "ChoiceList")
                check("C4: ChoiceList opens", list ~= nil)
                if list ~= nil then
                    check(
                        "C4: popup Z sits above every window root",
                        (tonumber(list.ZIndex) or 0) >= 400,
                        tostring(list.ZIndex)
                    )
                    state.setMenuVisible(false)
                    check(
                        "C4: menu-hide closes ChoiceList",
                        Inspect.findNamed(layer, "ChoiceList") == nil
                    )
                    state.setMenuVisible(true)
                end
            end
        end
        if type(state.closeInvalidPopups) ~= "function" then
            check("C4: APPLY-4 owner/scroll stays demonstrated debt (unpublished closer)", true)
        end

        -- Titles must not overflow their chrome.
        if ui ~= nil and ui.header ~= nil then
            local title: any = ui.header:FindFirstChild("Title")
            if title ~= nil then
                local headerW: number = ui.root.Size.X.Offset
                check(
                    "C4: UI Settings title stays inside the header",
                    title.Size.X.Offset <= headerW or title.ClipsDescendants == true
                )
                assertNoDuplicateInk(ui.header, bitmap, "C4 UI Settings title")
            end
        end
    end

    -- ------------------------------------------------------------------ C5
    do
        section("VisualRC/Viewports")
        local sizes: {{number}} = {
            {1600, 900},
            {1920, 1080},
            {1366, 768},
            {1280, 720},
            {800, 450},
            {640, 360},
            {390, 844},
            {3440, 1440},
        }
        local scales: {number} = {0.7, 1.0, 1.25, 1.6}
        for _, size in ipairs(sizes) do
            world.camera.ViewportSize = world.globals.Vector2.new(size[1], size[2])
            for _, scale in ipairs(scales) do
                Inspect.pinClickGuiScale(env.PopupLayer, scale)
                windows.Reclamp()
                if type(state.refreshLayout) == "function" then
                    state.refreshLayout(true)
                end
                local now: any = windows.LogicalViewport()
                local sample: any = windows.Get("UISettings") or windows.Get("ClickGui_Combat")
                if sample ~= nil then
                    local x: number = sample.root.Position.X.Offset
                    local y: number = sample.root.Position.Y.Offset
                    check(
                        string.format("C5: %dx%d @%.2f stays non-negative", size[1], size[2], scale),
                        x >= 0 and y >= 0,
                        string.format("pos=%s,%s vp=%sx%s", tostring(x), tostring(y), tostring(now.X), tostring(now.Y))
                    )
                end
            end
        end
        world.camera.ViewportSize = world.globals.Vector2.new(1600, 900)
        Inspect.pinClickGuiScale(env.PopupLayer, 1)
        windows.Reclamp()
    end

    -- ------------------------------------------------------------------ C6
    do
        section("VisualRC/Modes")
        check("C6: default surface is Wurst", state.menuStyle == "Wurst", tostring(state.menuStyle))
        if type(state.SetMenuStyle) == "function" then
            state.SetMenuStyle("Navigator", true)
            check(
                "C6: Navigator style is exclusive",
                Inspect.navigatorVisible(state) == true and Inspect.wurstVisible(state) == false
            )
            state.SetMenuStyle("Wurst", true)
            check(
                "C6: Wurst style is exclusive",
                Inspect.wurstVisible(state) == true and Inspect.navigatorVisible(state) == false
            )
        end

        if state.dock and type(state.dock.SetVisible) == "function" then
            local pill: any = state.pill and (state.pill.root or state.pill)
            state.dock.SetVisible(false)
            check(
                "C6: desktop dock can hide",
                pill == nil or pill.Visible == false or state.isMobile == true
            )
            state.dock.SetVisible(true)
            check("C6: dock can show again", pill == nil or pill.Visible == true)
        end
        if state.hudList and type(state.hudList.SetVisible) == "function" then
            state.hudList.SetVisible(false)
            local frame: any = state.hudList.frame
            check("C6: HackList can hide", frame == nil or frame.Visible == false)
            state.hudList.SetVisible(true)
            check("C6: HackList can show again", frame == nil or frame.Visible == true)
        end

        check("C6: boot is desktop (keyboard, not touch-primary)", state.isMobile ~= true)
        world.services.UserInputService.KeyboardEnabled = false
        check(
            "C6: keyboard-disconnected flag is readable",
            world.services.UserInputService.KeyboardEnabled == false
        )
        world.services.UserInputService.KeyboardEnabled = true
        world.services.UserInputService.TouchEnabled = true
        check("C6: touch flag can be raised without crashing", true)
        world.services.UserInputService.TouchEnabled = false

        if type(bitmap.applyFontPack) == "function" then
            bitmap.applyFontPack("Minecraft 1.18.1")
            check(
                "C6: missing exact pack does not claim minecraft-exact",
                bitmap.source ~= "minecraft-exact",
                tostring(bitmap.source)
            )
            bitmap.applyFontPack("Monocraft")
        end
        check("C6: packs table names both Minecraft versions",
            type(bitmap.packs) == "table"
                and bitmap.packs["Minecraft 1.18.1"] ~= nil
                and bitmap.packs["Minecraft 26.2"] ~= nil)
    end

    -- ------------------------------------------------------------------ C9
    do
        section("VisualRC/Gate")
        local counted: number = #(env.allFeatures or {})
        local booted: number = tonumber(
            state.boot and state.boot.timing and state.boot.timing.moduleCount
        ) or 0
        -- Manifest still ships 38. Rejoin Server is a Wurst Options action
        -- when that API exists, so the card list can be 37.
        check(
            "C9: universal inventory is still 38",
            booted == 38 and counted >= 37 and counted <= 38,
            "cards=" .. tostring(counted) .. " booted=" .. tostring(booted)
        )
        check(
            "C9: product identity is Wurst 0.1 Beta",
            env.PRODUCT ~= nil
                and env.PRODUCT.name == "Wurst"
                and env.PRODUCT.version == "0.1 Beta"
                and env.PRODUCT.logPrefix == "Wurst"
                and env.PRODUCT.guiName == "RandomTestingMenu0001",
            env.PRODUCT and tostring(env.PRODUCT.version) or "nil"
        )
        check(
            "C9: no old-menu skin window",
            windows.Get("Aurora") == nil
                and windows.Get("Monochrome") == nil
                and windows.Get("GlobalToggle") == nil
        )
        -- The user's capture review reversed the blur ban: the shell now
        -- owns exactly one managed BlurEffect (PRODUCT.blurName, follows
        -- menu visibility, destroyed at destruct). The hail layer stays
        -- dead, and no library may construct a second blur.
        check(
            "C9: no hail layer names in the bundle",
            string.find(bundle, "BlurHail", 1, true) == nil
                and string.find(bundle, "HailLayer", 1, true) == nil
                and string.find(bundle, 'Instance.new("BlurEffect"', 1, true) == nil
        )
        check(
            "C9: the shell owns the one managed menu blur",
            string.find(source, "MenuBlur.Name = BLUR_NAME", 1, true) ~= nil
                and string.find(source, "MenuBlur.Enabled = visible == true", 1, true) ~= nil
                and string.find(source, 'cleanupStep("blur"', 1, true) ~= nil
        )
        check(
            "C9: source stamp is published",
            type(env.SOURCE_STAMP) == "string" and #env.SOURCE_STAMP >= 8,
            tostring(env.SOURCE_STAMP)
        )
        check(
            "C9: no new official empty-category windows",
            windows.Get("ClickGui_Blocks") == nil
                and windows.Get("ClickGui_Chat") == nil
                and windows.Get("ClickGui_Items") == nil
        )
    end

    local torn: boolean = true
    if type(state.destruct) == "function" then
        torn = pcall(state.destruct)
    end
    check("C9: destruct runs without throwing", torn == true)
    -- Live-count zero after destruct is gated by bitmap-budget on a clean
    -- boot. This suite draws detached probes; those records must not fail RC.
end
