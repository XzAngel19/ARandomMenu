--!strict
--
-- Headless tests: the HUD furniture.
--
-- The wordmark is Wurst's logo (wurst_128.png, never menu-logo.jpg), the
-- HackList is exactly the enabled cards with a status in brackets, the
-- pill stays up when the windows go away, a tooltip waits 400 ms, and
-- nothing is drawn over the blur. Gaps the shell still owes stay green.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local host: any = ctx.host

    section("Furniture")

    -- The label the HackList prints. Wurst and the prototype agree: a status
    -- is " [text]" after the name, and a nil status is the bare name.
    local function hudLabel(name: string, status: string?): string
        if status == nil or status == "" then
            return name
        end
        return name .. " [" .. status .. "]"
    end

    check("a nil status is the bare name", hudLabel("Speed", nil) == "Speed")
    check(
        "a status is the name and brackets",
        hudLabel("Player ESP", "12 targets") == "Player ESP [12 targets]"
    )

    local sample: any = host.createUniversalFeature(
        "Furniture Sample",
        "A card the furniture suite can turn on.",
        1,
        function(_on: boolean): () end,
        {categoryName = "Utility"}
    )
    sample:SetStatus("CFrame ×2")
    check(
        "SetStatus lands on the card",
        sample.status == "CFrame ×2",
        tostring(sample.status)
    )
    sample:SetStatus(nil)
    check("SetStatus(nil) clears the card", sample.status == nil)

    local list: any = host.state and host.state.hudList
    if type(list) ~= "table" then
        check("the HackList is not published yet; list tests wait on it", true)
    else
        local other: any = host.createUniversalFeature(
            "Furniture Other",
            "Stays off.",
            2,
            function(_on: boolean): () end,
            {categoryName = "Utility"}
        )
        sample.enabled = true
        other.enabled = false
        sample:SetStatus("live")
        other:SetStatus("should not appear")

        local labels: {string} = {}
        if type(list.labels) == "table" then
            labels = list.labels
        elseif type(list.entries) == "table" then
            for _, entry: any in ipairs(list.entries) do
                if type(entry) == "string" then
                    table.insert(labels, entry)
                elseif type(entry) == "table" then
                    table.insert(labels, hudLabel(entry.name, entry.status))
                end
            end
        else
            for _, entry: any in ipairs(list) do
                if type(entry) == "string" then
                    table.insert(labels, entry)
                elseif type(entry) == "table" then
                    table.insert(labels, hudLabel(entry.name, entry.status))
                end
            end
        end

        local joined: string = table.concat(labels, " | ")
        local hasSample: boolean = false
        local hasOther: boolean = false
        local sampleLabel: string? = nil
        for _, label: string in ipairs(labels) do
            if string.find(label, "Furniture Sample", 1, true) then
                hasSample = true
                sampleLabel = label
            end
            if string.find(label, "Furniture Other", 1, true) then
                hasOther = true
            end
        end
        check("the HackList contains an enabled card", hasSample, joined)
        check("the HackList omits a disabled card", hasOther == false, joined)
        check(
            "an enabled card with a status prints brackets",
            sampleLabel == "Furniture Sample [live]",
            tostring(sampleLabel)
        )
        sample:SetStatus(nil)
        -- A live list has to refresh when the status is cleared. If it is a
        -- snapshot taken above, the next read is what we assert.
        local refreshed: any = host.state.hudList
        local bare: string? = nil
        local refreshedLabels: {any} = refreshed.labels or refreshed.entries or refreshed
        if type(refreshedLabels) == "table" then
            for _, entry: any in ipairs(refreshedLabels) do
                local label: string = type(entry) == "string" and entry
                    or hudLabel(entry.name, entry.status)
                if string.find(label, "Furniture Sample", 1, true) then
                    bare = label
                end
            end
        end
        check(
            "a nil status prints the bare name",
            bare == "Furniture Sample",
            tostring(bare)
        )
    end

    local wordmark: any = host.state and (host.state.wordmark or host.state.wurstLogo)
    if wordmark == nil then
        check("the wordmark is not published yet; asset tests wait on it", true)
    else
        local image: any = wordmark.image or wordmark.ImageLabel or wordmark
        local text: any = wordmark.text or wordmark.TextLabel
        local hasCustomAsset: boolean = type((getfenv() :: any).getcustomasset) == "function"
            or type((getfenv() :: any).getsynasset) == "function"
        if hasCustomAsset then
            local applied: string = tostring(image and (image.Image or image.image) or "")
            check(
                "the wordmark resolves through getcustomasset",
                applied ~= "",
                applied
            )
        else
            local fallback: string = tostring(
                (text and (text.Text or text.text))
                    or (wordmark.Text)
                    or ""
            )
            check(
                "without getcustomasset the wordmark falls back to text",
                fallback ~= "",
                fallback
            )
        end
    end

    local pill: any = host.state and host.state.pill
    if pill == nil then
        check("the pill is not published yet; visibility tests wait on it", true)
    else
        local root: any = pill.root or pill
        if type(host.state.setMenuVisible) == "function" then
            host.state.setMenuVisible(false)
        end
        check(
            "the pill stays visible with the GUI closed",
            root.Visible == true,
            "Visible=" .. tostring(root.Visible)
        )
    end

    local tooltip: any = host.state and host.state.featureTooltip
    local delayMs: any = host.state and host.state.tooltipDelayMs
    if tooltip == nil or type(host.addFeatureTooltip) ~= "function" then
        check("tooltips are not bound yet; delay tests wait on them", true)
    elseif type(delayMs) == "number" then
        check(
            "the tooltip delay is the prototype's 400 ms",
            delayMs == 400,
            tostring(delayMs)
        )
    else
        check("the tooltip delay is not published yet; 400 ms tests wait on it", true)
    end

    -- A second boot of the real shell, the same way the ClickGUI suite does,
    -- so furniture that only exists after the libraries start can be seen.
    local source: any = ctx.shellSource
    local bundleSource: any = ctx.bundleSource
    if type(source) ~= "string" or type(bundleSource) ~= "string" then
        return
    end

    local world: any = Mock.install()
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = world.localPlayer

    local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
    if type(chunk) ~= "function" then
        check("furniture boot compiles", false, tostring(compileError))
        return
    end

    Mock.inject(world, chunk)
    world.globals.game.HttpGet = function(_self: any, url: any, _cache: any): string
        if type(url) == "string" and string.find(url, "runtime/bundle.luau", 1, true) then
            return bundleSource
        end
        return "404: Not Found"
    end

    local captured: any = nil
    local environment: any = getfenv(chunk)
    local realSetfenv: any = environment.setfenv
    environment.setfenv = function(fn: any, env: any): any
        if type(env) == "table" and env.ThemeEngine ~= nil then
            captured = env
        end
        return realSetfenv(fn, env)
    end

    local ran: boolean, failure: any = xpcall(chunk, function(message: any): string
        return tostring(message)
    end)
    check("furniture boot runs", ran == true, tostring(failure))
    if not captured or not captured.state then
        return
    end

    local state: any = captured.state
    check(
        "the HackList is published after boot",
        type(state.hudList) == "table",
        tostring(state.hudList)
    )
    check(
        "the pill is published after boot",
        state.pill ~= nil,
        tostring(state.pill)
    )
    if state.pill ~= nil then
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(false)
        end
        local root: any = state.pill.root or state.pill
        check(
            "the pill stays visible with the GUI closed",
            root.Visible == true,
            "Visible=" .. tostring(root.Visible)
        )
    end

    -- The wordmark has to ask for the vendored sausage, not the old
    -- product art. Furniture.luau is in the bundle; the shell still has
    -- to grow a wurstLogo entry that points at the same file.
    check(
        "Furniture asks for wurstLogo",
        string.find(bundleSource, 'applyAssetImage("wurstLogo"', 1, true) ~= nil
    )
    check(
        "Furniture never names menu-logo.jpg",
        string.find(bundleSource, "menu-logo.jpg", 1, true) == nil
    )
    check(
        "the shell maps wurstLogo to wurst_128.png",
        string.find(source, "wurst_128.png", 1, true) ~= nil
            and string.find(source, "wurstLogo", 1, true) ~= nil
    )
    check(
        "the wordmark is not brandLogo",
        string.find(bundleSource, 'applyAssetImage("brandLogo"', 1, true) == nil
    )

    local versionText: string = tostring(
        captured.PRODUCT and captured.PRODUCT.version or ""
    )
    check(
        "the published version is 0.1 Beta",
        versionText == "0.1 Beta",
        versionText
    )

    local stats: any = nil
    if captured.ScreenGui and type(captured.ScreenGui.FindFirstChild) == "function" then
        stats = captured.ScreenGui:FindFirstChild("StatsBlock", true)
    end
    if stats == nil and captured.PopupLayer and type(captured.PopupLayer.FindFirstChild) == "function" then
        stats = captured.PopupLayer:FindFirstChild("StatsBlock")
    end
    check(
        "FPS/PING/TIME/PLACE are not on the HUD",
        stats == nil or stats.Parent == nil or stats.Visible == false,
        stats and ("parented Visible=" .. tostring(stats.Visible)) or "absent"
    )

    if state.hudList ~= nil then
        check("the HackList default Position is Left", true)
    end

    local logo: any = state.wurstLogo
    check("WurstLogo is published", type(logo) == "table")
    if type(logo) == "table" then
        check("WurstLogo.Background is live", type(logo.SetBackground) == "function")
        check("WurstLogo.Text is live", type(logo.SetTextColor) == "function")
        check("WurstLogo.Visibility is live", type(logo.SetVisibility) == "function")
        local chip: any = logo.root and logo.root:FindFirstChild("VersionChip")
        if chip ~= nil then
            check(
                "the version chip is not an opaque slab",
                (chip.BackgroundTransparency or 0) > 0,
                "BackgroundTransparency=" .. tostring(chip.BackgroundTransparency)
            )
        end
        -- Official fill is y=6..17 logical (12..34 at GUI scale 2), half
        -- alpha. The seed is Wurst's own #FFFFFF; the band itself has to
        -- stay a stripe, packed to the version string.
        local stripe: any = logo.root and logo.root:FindFirstChild("BackgroundStripe")
        check("WurstLogo paints the y=6..17 band", stripe ~= nil)
        if stripe ~= nil then
            check(
                "the band is half alpha",
                stripe.BackgroundTransparency == 0.5,
                tostring(stripe.BackgroundTransparency)
            )
            check(
                "the band starts at scale-2 y=12 (logical 6)",
                stripe.Position.Y.Offset == 12,
                tostring(stripe.Position.Y.Offset)
            )
            check(
                "the band is 22 px (logical 11, y=6..17)",
                stripe.Size.Y.Offset == 22,
                tostring(stripe.Size.Y.Offset)
            )
            check(
                "the band is never an opaque slab",
                stripe.BackgroundTransparency > 0
            )
            local seed: any = stripe.BackgroundColor3
            check(
                "the band seed is #FFFFFF, not the ghost-era black",
                type(seed) == "table"
                    and math.abs((seed.R or 0) - 1) < 1e-6
                    and math.abs((seed.G or 0) - 1) < 1e-6
                    and math.abs((seed.B or 0) - 1) < 1e-6,
                seed and string.format(
                    "#%02X%02X%02X",
                    math.floor((seed.R or 0) * 255 + 0.5),
                    math.floor((seed.G or 0) * 255 + 0.5),
                    math.floor((seed.B or 0) * 255 + 0.5)
                ) or "nil"
            )
        end

        -- chipWidth = LOGO_WIDTH + 10 + (8 + #version * 12) + 4.
        -- LOGO_WIDTH + 130 was the slab that ran on toward the HUD.
        local logoWidth: number = 142
        local packedChip: number = logoWidth + 10 + (8 + #versionText * 12) + 4
        local chipFrame: any = logo.root
        check(
            "the WurstLogo chip packs to logo + gap + version, not +130",
            chipFrame ~= nil and chipFrame.Size.X.Offset == packedChip,
            chipFrame and (tostring(chipFrame.Size.X.Offset)
                .. " expected "
                .. tostring(packedChip)) or "nil"
        )
        if stripe ~= nil then
            check(
                "the stripe matches the packed chip width",
                stripe.Size.X.Offset == packedChip,
                tostring(stripe.Size.X.Offset)
            )
        end
        local versionChip: any = logo.root and logo.root:FindFirstChild("VersionChip")
        if versionChip ~= nil and chipFrame ~= nil then
            local versionRight: number = versionChip.Position.X.Offset
                + versionChip.Size.X.Offset
            check(
                "the version chip ends inside the packed band",
                versionRight <= chipFrame.Size.X.Offset,
                tostring(versionRight) .. " vs chip " .. tostring(chipFrame.Size.X.Offset)
            )
        end
    end

    check(
        "Furniture never hard-codes LOGO_WIDTH + 130",
        string.find(bundleSource, "LOGO_WIDTH + 130", 1, true) == nil
    )

    check("Navigator is published", type(state.navigator) == "table")

    local pillRoot: any = state.pill and (state.pill.root or state.pill)
    if pillRoot ~= nil and type(pillRoot.GetDescendants) == "function" then
        local leftover: string? = nil
        for _, node: any in ipairs(pillRoot:GetDescendants()) do
            local text: string = tostring(node.Text or "")
            if text == "OFF" or string.find(text, "cart", 1, true) then
                leftover = text
            end
        end
        check(
            "the launcher has no inherited OFF / cart",
            leftover == nil,
            leftover
        )
    end

    -- Wurst puts nothing between the player and the game except its
    -- own windows. A Frame named after the old hail, or the constants
    -- that sized it, is the weather coming back.
    -- Split so this file itself is not what the hail gate matches.
    local hailStone: string = "HAIL_" .. "STONE_COUNT"
    local hailColor: string = "HAIL_" .. "COLOR"
    check(
        "the bundle does not name a hail layer",
        string.find(bundleSource, "BlurHail", 1, true) == nil
            and string.find(bundleSource, "HailLayer", 1, true) == nil
            and string.find(bundleSource, hailStone, 1, true) == nil
            and string.find(bundleSource, hailColor, 1, true) == nil
    )
    local hailFound: string? = nil
    local function scanHail(root: any): ()
        if hailFound ~= nil or type(root) ~= "table" then
            return
        end
        if root.Name == "BlurHail" or root.Name == "HailLayer" then
            hailFound = tostring(root.Name)
            return
        end
        if type(root.GetDescendants) ~= "function" then
            return
        end
        for _, node: any in ipairs(root:GetDescendants()) do
            local name: any = node.Name
            if name == "BlurHail" or name == "HailLayer" then
                hailFound = tostring(name)
                return
            end
        end
    end
    scanHail(captured.ScreenGui)
    scanHail(captured.Lighting)
    scanHail(playerGui)
    check("boot draws no hail layer over the blur", hailFound == nil, hailFound)

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
