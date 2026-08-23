--!strict
--
-- Headless tests: the HUD furniture.
--
-- The wordmark is Wurst's logo (wurst_128.png, never menu-logo.jpg), the
-- HackList is exactly the enabled cards with a status in brackets, the
-- pill stays up when the windows go away, a tooltip waits 400 ms, and
-- nothing is drawn over the blur. Host-stub gaps are not green checks.

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

    check(
        "the HackList default Position is Left",
        string.find(bundleSource, 'HACKLIST_POSITION: string = "Left"', 1, true) ~= nil
    )
    check(
        "the tooltip delay is Furniture's 400 ms",
        string.find(bundleSource, "TOOLTIP_DELAY_MS: number = 400", 1, true) ~= nil
    )
    if type(state.hudList) == "table" and type(state.hudList.refresh) == "function" then
        local live: any = nil
        for _, feature: any in ipairs(captured.allFeatures or {}) do
            if feature.isCategory ~= true then
                live = feature
                break
            end
        end
        check("a live card exists for the HackList", live ~= nil)
        if live ~= nil then
            local wasEnabled: boolean = live.enabled == true
            if type(state.hudList.SetAnimations) == "function" then
                -- The mock applies tween goals but never fires Completed,
                -- so a sliding drop would leave the row parented forever.
                state.hudList.SetAnimations(false)
            end
            live.enabled = true
            live:SetStatus("live")
            state.hudList.refresh()
            local frame: any = state.hudList.frame
            check(
                "the HackList draws an enabled card",
                frame ~= nil and frame:FindFirstChild(tostring(live.name)) ~= nil,
                tostring(live.name)
            )
            live.enabled = false
            state.hudList.refresh()
            check(
                "the HackList omits a disabled card",
                frame == nil or frame:FindFirstChild(tostring(live.name)) == nil,
                tostring(live.name)
            )
            live.enabled = wasEnabled
            live:SetStatus(nil)
            state.hudList.refresh()
        end
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

        -- chipWidth = LOGO_WIDTH + 10 + (8 + #version * 15) + 4 — the
        -- version draws at the 20 px line now (user order: bigger), and
        -- 15 is the estimated advance at that size.
        local logoWidth: number = 142
        local packedChip: number = logoWidth + 10 + (8 + #versionText * 15) + 4
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
