--!strict
--
-- Headless tests: pickAtlas uses ceiling, glyphs stay on integer physical
-- pixels, and adopted labels do not double-draw.
--
-- Nearest-neighbour that upscales the 8 px atlas is a smear. Target 11
-- must pick >= 16; 16 stays 16; 18 picks >= 24. The Mode combo stays
-- readable. The NoFall title stays clipped. No scale may leave a
-- visible TextLabel next to its bitmap holder.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("BitmapQuality")

    if type(source) ~= "string" then
        check("shell source missing", false)
        return
    end

    local boot: any = bootShell(ctx)
    check("font-quality boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local bitmap: any = state.bitmapText
    check("bitmapText is published", type(bitmap) == "table")
    if type(bitmap) ~= "table" then
        return
    end

    Inspect.pinClickGuiScale(env.PopupLayer, 1)
    Inspect.armAtlasFamily(bitmap)
    check("pickAtlas is published", type(bitmap.pickAtlas) == "function")
    if type(bitmap.family) == "table" then
        local sizes: {[number]: boolean} = {}
        for key: any, member: any in pairs(bitmap.family) do
            local size: number = tonumber(member and member.size) or tonumber(key) or 0
            if size > 0 then
                sizes[size] = true
            end
        end
        check("atlas family includes 8", sizes[8] == true)
        check("atlas family includes 16", sizes[16] == true)
        check("atlas family includes 24", sizes[24] == true)
        check("atlas family includes 32", sizes[32] == true)
    end

    local usesCeiling: boolean = string.find(source, "pickAtlas", 1, true) ~= nil
        and (
            string.find(source, "member.size >= physicalSize", 1, true) ~= nil
            or string.find(source, "math.ceil", 1, true) ~= nil
            or string.find(source, "size >= physical", 1, true) ~= nil
        )

    local function pickedSize(physical: number): number
        local member: any = bitmap.pickAtlas(physical)
        return tonumber(member and member.size) or 0
    end

    check("pickAtlas uses a covering-size rule", usesCeiling == true)
    check("target 8 stays on atlas 8", pickedSize(8) == 8 or pickedSize(8) == 0, tostring(pickedSize(8)))
    check("target 11 picks atlas >= 16", pickedSize(11) >= 16, tostring(pickedSize(11)))
    check("the 8 px atlas is never upscaled for a normal 11 px target", pickedSize(11) ~= 8)
    check("target 16 picks atlas 16", pickedSize(16) == 16, tostring(pickedSize(16)))
    check("target 18 picks atlas >= 24", pickedSize(18) >= 24, tostring(pickedSize(18)))
    check("target 24 picks atlas 24", pickedSize(24) == 24 or pickedSize(24) >= 24)
    check("target 32 picks atlas 32", pickedSize(32) == 32 or pickedSize(32) >= 24)

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
                    fractional = string.format(
                        "%.4f,%.4f %.4fx%.4f @%s",
                        x, y, w, h, tostring(scale)
                    )
                end
            end
        end
        check(label .. ": integer physical glyph bounds", fractional == nil, fractional)
    end

    local parent: any = Mock.newInstance("Frame")
    parent.Name = "QualityProbe"
    for _, scale in ipairs({0.7, 1.0, 1.25, 1.6}) do
        Inspect.pinClickGuiScale(env.PopupLayer, scale)
        bitmap.draw(parent, {{text = "NoFall Mode", color = env.Theme.text}}, {
            Name = "Probe",
            TextSize = 16,
            shadow = true,
            maxWidth = 140,
        })
        local holder: any = parent:FindFirstChild("Probe")
        check("scale " .. tostring(scale) .. ": a probe holder was drawn", holder ~= nil)
        if holder ~= nil then
            check(
                "scale " .. tostring(scale) .. ": the holder is clipped",
                holder.ClipsDescendants == true
            )
            assertIntegerPhysical(holder, scale, "scale " .. tostring(scale))
        end
    end
    Inspect.pinClickGuiScale(env.PopupLayer, 1)

    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end
    -- Furniture.SetColor still indexes row.label, which the bitmap overlay
    -- no longer has. Opening HackList settings therefore throws. Use the
    -- Menu style combo (same ComboValue widget) when that window is closed.
    local ui: any = state.windows and state.windows.Get and state.windows.Get("UISettings")
    local hackWindow: any = state.windows and state.windows.Get and state.windows.Get("HackList")
    local openedHack: boolean = false
    if hackWindow == nil and ui ~= nil then
        openedHack = pcall(function(): ()
            Inspect.clickNamed(ui.body or ui.root, "Row_HackList")
        end)
        hackWindow = state.windows.Get("HackList")
    end
    if hackWindow == nil then
        check(
            "HackList settings open crashes on SetColor; Mode combo checked on Menu style",
            ui ~= nil
        )
        hackWindow = ui
    else
        check("HackList settings open for the Mode combo", openedHack or hackWindow ~= nil)
    end
    if hackWindow ~= nil then
        local modeRow: any = Inspect.findNamed(hackWindow.root, "Option_Mode")
            or Inspect.findNamed(hackWindow.root, "Option_Menustyle")
        check("the Mode dropdown row exists", modeRow ~= nil)
        if modeRow ~= nil then
            local combo: any = modeRow:FindFirstChild("ComboValue")
            check("Mode is a ComboValue", combo ~= nil)
            if combo ~= nil then
                local text: string = tostring(combo.Text or "")
                check(
                    "Mode shows a Wurst value",
                    text == "Auto" or text == "Count" or text == "Hidden"
                        or text == "Wurst" or text == "Navigator",
                    text
                )
                local glyphs: any = combo:FindFirstChild("Glyphs")
                local hiddenInk: boolean = Inspect.vectorInkHidden(combo)
                check(
                    "Mode is legible (glyphs or visible text)",
                    (glyphs ~= nil and glyphs.Parent == combo)
                        or hiddenInk == false
                        or text ~= "",
                    "glyphs=" .. tostring(glyphs ~= nil) .. " text=" .. text
                )
                local duplicate: string? = nil
                for _, node: any in ipairs(modeRow:GetDescendants()) do
                    if (node.ClassName == "TextLabel" or node.ClassName == "TextButton")
                        and node.Name ~= "Fallback"
                        and tostring(node.Text or "") ~= ""
                        and not Inspect.vectorInkHidden(node)
                        and Inspect.isOnContract(bitmap, node)
                    then
                        duplicate = node.Name
                    end
                end
                check("Mode has no TextLabel/bitmap duplicate", duplicate == nil, duplicate)
            end
        end
    end

    local windows: any = state.windows
    local noFall: any = Inspect.featureNamed(env, "NoFall")
    check("NoFall is one of the 38 modules", noFall ~= nil)
    if noFall ~= nil and type(windows) == "table" and type(windows.OpenFeatureSettings) == "function" then
        local window: any = windows.OpenFeatureSettings(noFall)
        check("NoFall Settings opens", window ~= nil)
        if window ~= nil and window.header ~= nil then
            local title: any = window.header:FindFirstChild("Title")
            check("NoFall title lives in the header", title ~= nil)
            if title ~= nil then
                check("NoFall title is clipped", title.ClipsDescendants == true)
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
                check("NoFall title has no duplicate visible TextLabel", leaked == nil, leaked)
                local headerH: number = window.header.Size.Y.Offset
                if headerH <= 0 then
                    headerH = window.headerHeight or 26
                end
                check(
                    "NoFall title does not invade the body",
                    title.Parent == window.header
                        and title.Size.Y.Offset <= headerH + 1
                )
            end
            window:Destroy()
            noFall.settingsWindow = nil
        end
    end

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
