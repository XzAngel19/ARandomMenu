--!strict
--
-- Headless tests: the NoFall Settings title must stay inside the header.
--
-- A title that walks into the body or the chrome is a bitmap artefact:
-- the holder is too wide, unclipped, or duplicated. One holder, clipped
-- to the chrome span, at every user scale.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("BitmapArtifact")

    local boot: any = bootShell(ctx)
    check("artifact boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local bitmap: any = state.bitmapText
    local windows: any = state.windows
    check("bitmapText and windows are published", bitmap ~= nil and windows ~= nil)
    if bitmap == nil or windows == nil then
        return
    end

    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end
    Inspect.pinClickGuiScale(env.PopupLayer, 1)
    Inspect.armAtlas(bitmap)

    local noFall: any = nil
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if feature.name == "NoFall" or feature.configKey == "Universal.NoFall" then
            noFall = feature
            break
        end
    end
    check("NoFall is one of the inventory modules", noFall ~= nil)
    if noFall == nil then
        return
    end

    local window: any = windows.OpenFeatureSettings(noFall)
    check("NoFall Settings opens", window ~= nil)
    if window == nil then
        return
    end
    check(
        "the window title is NoFall Settings",
        window.id == "FeatureSettings_UniversalNoFall"
            or (window.header ~= nil),
        tostring(window.id)
    )

    local function titleHolder(): any
        if window.header == nil then
            return nil
        end
        return window.header:FindFirstChild("Title")
    end

    local function countTitles(): number
        local count: number = 0
        if window.header == nil or type(window.header.GetDescendants) ~= "function" then
            return 0
        end
        if window.header:FindFirstChild("Title") then
            count += 1
        end
        return count
    end

    local function assertTitle(label: string): ()
        local holder: any = titleHolder()
        check(label .. ": glyphs live in the header", holder ~= nil and holder.Parent == window.header)
        if holder == nil or window.header == nil then
            return
        end
        check(label .. ": the holder is clipped", holder.ClipsDescendants == true)
        check(label .. ": one Title holder", countTitles() == 1, tostring(countTitles()))

        local leaked: string? = nil
        for _, node: any in ipairs(window.header:GetDescendants()) do
            if (node.ClassName == "TextLabel" or node.ClassName == "TextButton")
                and node.Name ~= "Fallback"
                and tostring(node.Text or "") ~= ""
                and not Inspect.vectorInkHidden(node)
            then
                leaked = node.Name
            end
        end
        check(label .. ": no duplicate visible TextLabel", leaked == nil, leaked)

        local headerH: number = window.header.Size.Y.Offset
        if headerH <= 0 then
            headerH = window.headerHeight or 26
        end
        -- Centered in the bar: a 17 px glyph in a 26 px header must not
        -- cross into the body (y = header height).
        check(
            label .. ": title does not invade the body",
            holder.Parent == window.header
                and holder.Size.Y.Offset <= headerH + 1,
            "holder.h=" .. tostring(holder.Size.Y.Offset) .. " header.h=" .. tostring(headerH)
        )
        if window.body then
            check(
                label .. ": the body is not the title parent",
                holder.Parent ~= window.body
            )
        end

        local chromeLeft: number = window.header.Size.X.Offset
        if chromeLeft <= 0 then
            chromeLeft = window.root.Size.X.Offset
        end
        -- Chrome buttons occupy the last 68 px (two or three 22 px squares
        -- plus inset). maxWidth is size.X - 68.
        local holderRight: number = holder.Position.X.Offset + holder.Size.X.Offset
        check(
            label .. ": title does not invade close/pin",
            holderRight <= chromeLeft - 50 or holder.ClipsDescendants == true,
            "right=" .. tostring(holderRight) .. " chrome=" .. tostring(chromeLeft)
        )

        local liveInHeader: number = 0
        for live: any, _ in pairs(bitmap._live) do
            if live.Parent == window.header or live == holder then
                liveInHeader += 1
            end
        end
        check(
            label .. ": one live bitmap holder in the header",
            liveInHeader == 1,
            tostring(liveInHeader)
        )
    end

    assertTitle("first open")

    local first: any = titleHolder()
    window:SetVisible(false)
    local again: any = windows.OpenFeatureSettings(noFall)
    check("reopen reuses the same window", rawequal(window, again))
    local second: any = titleHolder()
    check("reopen does not duplicate the title holder", first == second)
    assertTitle("reopen")

    if env.ThemeEngine and type(env.ThemeEngine.Apply) == "function" then
        env.ThemeEngine.Apply("Monochrome")
        assertTitle("theme Monochrome")
        env.ThemeEngine.Apply("Wurst")
        assertTitle("theme Wurst")
        check("theme switch still has one Title holder", countTitles() == 1)
    end

    for _, scale in ipairs({0.7, 1.0, 1.25, 1.6}) do
        Inspect.pinClickGuiScale(env.PopupLayer, scale)
        if type(window.resizeToOptions) == "function" then
            window.resizeToOptions()
        end
        if type(bitmap.draw) == "function" and first ~= nil then
            -- Force a redraw at the new scale; the same holder must remain.
            Inspect.armAtlas(bitmap)
        end
        assertTitle("scale " .. tostring(scale))
    end
    Inspect.pinClickGuiScale(env.PopupLayer, 1)

    window:Destroy()
    noFall.settingsWindow = nil
    local leftover: number = 0
    for holder: any, _ in pairs(bitmap._live) do
        if holder.Parent == nil then
            continue
        end
        local walk: any = holder
        while walk ~= nil do
            if walk.Name == "Window_FeatureSettings_UniversalNoFall" then
                leftover += 1
            end
            walk = walk.Parent
        end
    end
    check("teardown leaves zero NoFall title holders", leftover == 0, tostring(leftover))

    if type(state.destruct) == "function" then
        state.destruct()
    end
    local live: number, glyphs: number = Inspect.liveCounts(bitmap)
    check(
        "destruct leaves zero live bitmap records",
        live == 0 and glyphs == 0,
        "holders=" .. tostring(live)
    )
end
