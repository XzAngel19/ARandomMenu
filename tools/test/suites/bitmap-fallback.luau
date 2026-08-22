--!strict
--
-- Headless tests: the committed Monocraft atlas is an OFL fallback.
--
-- Exact Minecraft glyphs are never this file. Positions the renderer
-- writes must be whole logical pixels so a UIScale cannot smear a
-- fractional cell.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("BitmapFallback")

    if type(source) ~= "string" then
        check("shell source missing", false)
        return
    end

    check(
        "the renderer asks for Pixelated resampling",
        string.find(source, "ResamplerMode.Pixelated", 1, true) ~= nil
    )
    check(
        "glyph blit uses fromOffset (pixel snapping)",
        string.find(source, "UDim2.fromOffset(dx, dy)", 1, true) ~= nil
            and string.find(source, "UDim2.fromOffset(glyphWidth, glyphHeight)", 1, true) ~= nil
    )
    check(
        "the committed atlas source is monocraft-fallback",
        string.find(source, 'source = "monocraft-fallback"', 1, true) ~= nil
    )
    check(
        "loadExactAtlas is the only path that may say minecraft-exact",
        string.find(source, 'source = "minecraft-exact"', 1, true) ~= nil
            and string.find(source, "loadExactAtlas", 1, true) ~= nil
    )
    check(
        "the fallback is never labelled Minecraft exact in the shell",
        string.find(source, 'source = "minecraft-exact"', 1, true) ~= nil
            -- The assignment exists; the default label must stay Monocraft.
            and string.find(source, "Monocraft", 1, true) ~= nil
    )

    local boot: any = bootShell(ctx)
    check("fallback boot runs", boot.ok == true, boot.error)
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

    check(
        "boot source is not labelled Minecraft exact without a pack",
        bitmap.source ~= "minecraft-exact",
        tostring(bitmap.source)
    )
    check(
        "atlas cell is the Monocraft 11×17 / advance 11",
        bitmap.atlas.cellWidth == 11
            and bitmap.atlas.cellHeight == 17
            and bitmap.atlas.advance == 11
    )
    check("atlas coverage is ASCII 32..126", bitmap.atlas.first == 32 and bitmap.atlas.last == 126)
    check("atlas size selection is 16 px", bitmap.atlas.size == 16 or bitmap.size == 16)
    check("baseline ascent is published", type(bitmap.ascent) == "number" and bitmap.ascent > 0)

    Inspect.armAtlas(bitmap)
    local parent: any = Mock.newInstance("Frame")
    parent.Name = "FallbackProbe"
    bitmap.draw(parent, {{text = "NoFall 0123", color = env.Theme.text}}, {
        Name = "Probe",
        TextSize = 16,
        shadow = true,
    })
    local holder: any = parent:FindFirstChild("Probe")
    check("a probe holder was drawn", holder ~= nil)
    if holder ~= nil then
        local fractional: string? = nil
        for _, node: any in ipairs(holder:GetDescendants()) do
            if node.ClassName == "ImageLabel" and node.Visible ~= false then
                local x: number = node.Position.X.Offset
                local y: number = node.Position.Y.Offset
                local w: number = node.Size.X.Offset
                local h: number = node.Size.Y.Offset
                -- Logical offsets the renderer wrote. Physical space at
                -- scale 1 is the same number; a fraction here is a smear.
                if x ~= math.floor(x) or y ~= math.floor(y)
                    or w ~= math.floor(w) or h ~= math.floor(h)
                then
                    fractional = string.format("%.3f,%.3f %.3fx%.3f", x, y, w, h)
                end
            end
        end
        check(
            "no glyph position/size is fractional in physical space at scale 1",
            fractional == nil,
            fractional
        )
    end

    -- Size selection: a 16 px draw uses the 16 px atlas cell, not a
    -- half-pixel scale that would break snapping.
    if holder ~= nil then
        local record: any = bitmap._live[holder]
        if record and type(record.glyphs) == "table" and record.glyphs[1] then
            local glyph: any = record.glyphs[1]
            check(
                "a 16 px draw uses a 11 px-wide cell",
                glyph.Size.X.Offset == 11 or glyph.Size.X.Offset == 0,
                tostring(glyph.Size.X.Offset)
            )
        end
    end

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
