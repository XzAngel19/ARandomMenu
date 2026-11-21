local Core, Theme = import("Core"), import("Theme")
local Controls, Features = import("Controls"), import("Features")
local Window = {}

function Window.build(context)
    local window = Core.frame(context.canvas, "Violent", 20, 27, 305, 508, Theme.Black, 0.25)
    local header = Core.frame(window, "Header", 0, 0, 305, 76, Theme.Pink)
    local logo = Core.text(header, "VIOLENT", 0, 5, 305, 66, 44, Theme.DisplayFont)
    logo.TextXAlignment = Enum.TextXAlignment.Center
    logo.TextStrokeColor3, logo.TextStrokeTransparency = Theme.Black, 0
    Core.new("UIStroke", { Color = Theme.Black, Thickness = 1.5 }, logo)
    Core.drag(context, Core.button(header, "DragMenu", 0, 0, 305, 76), window)

    -- The reference has one category strip, not a sidebar or extra tabs.
    local navigation = Core.frame(window, "Navigation", 0, 76, 305, 28, Theme.Black)
    Core.text(navigation, "VISUALS / HUD", 8, 0, 235, 28, 15)
    local counter = Core.text(navigation, "29/51", 253, 0, 44, 28, 15)
    counter.TextXAlignment = Enum.TextXAlignment.Right

    local body = Core.new("ScrollingFrame", {
        Name = "Controls", Position = UDim2.fromOffset(0, 104), Size = UDim2.fromOffset(305, 351),
        CanvasSize = UDim2.fromOffset(0, 358), ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y, BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(39, 51, 54), BackgroundTransparency = 0.18,
        ClipsDescendants = true, Active = true,
    }, window)
    Core.new("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(190, 219, 227), Color3.fromRGB(36, 32, 36)),
        Rotation = 90,
    }, body)

    local footer = Core.frame(window, "Footer", 0, 455, 305, 28, Theme.Black, 0.1)
    local release = Core.text(footer, "Release, v1.4", 9, 0, 126, 28, 14, Enum.Font.SourceSansItalic)
    release.RichText = true
    release.Text = "<b><i>Release, v1.4</i></b>"
    local up = Core.button(footer, "ScrollUp", 139, 0, 23, 14)
    local down = Core.button(footer, "ScrollDown", 139, 14, 23, 14)
    Core.line(up, "ChevronLeft", 6, 10, 11, 5, Theme.White, 2)
    Core.line(up, "ChevronRight", 11, 5, 16, 10, Theme.White, 2)
    Core.line(down, "ChevronLeft", 6, 3, 11, 8, Theme.White, 2)
    Core.line(down, "ChevronRight", 11, 8, 16, 3, Theme.White, 2)
    context:connect(up.Activated, function() body.CanvasPosition = Vector2.new(0, 0) end)
    context:connect(down.Activated, function() body.CanvasPosition = Vector2.new(0, 7) end)
    Core.frame(window, "FooterAccent", 0, 483, 305, 4, Theme.Selection, 0.3)
    local status = Core.frame(window, "Status", 0, 487, 305, 21, Theme.Black, 0.05)
    context.status = Core.text(status, "Set color to: Highlight Outline Color", 7, 0, 294, 21, 13)
    context.rows = {}

    Controls.toggle(context, body, "Enable Skeleton", "EnableSkeleton", 0, true, Features.EnableSkeleton)
    Controls.number(context, body, "Skeleton Thickness", "SkeletonThickness", 26, 1, 0.5, 5, 0.5,
        Features.SkeletonThickness)
    Controls.color(context, body, "Skeleton Color", "SkeletonColor", 53, Color3.fromRGB(246, 255, 255),
        Features.SkeletonColor)
    Controls.section(body, "Highlights", 78)
    Controls.toggle(context, body, "Highlight ESP", "HighlightESP", 105, true, Features.HighlightESP)
    Controls.toggle(context, body, "Highlight Fill", "HighlightFill", 132, true, Features.HighlightFill)
    Controls.toggle(context, body, "Highlight Outline", "HighlightOutline", 158, true, Features.HighlightOutline)
    Controls.color(context, body, "Highlight Fill Color", "HighlightFillColor", 185,
        Color3.fromRGB(255, 0, 243), Features.HighlightFillColor)
    Controls.color(context, body, "Highlight Outline Color", "HighlightOutlineColor", 212,
        Theme.Pink, Features.HighlightOutlineColor, true)
    Controls.section(body, "Health Bar", 239)
    Controls.toggle(context, body, "Show Health Bar", "ShowHealthBar", 266, true, Features.ShowHealthBar)
    Controls.number(context, body, "Health Bar Size", "HealthBarSize", 293, 2.5, 0.5, 10, 0.5,
        Features.HealthBarSize)
    Controls.section(body, "Text", 319)
    -- Only this clipped sliver is visible under Text in the source image.
    -- Decorative, not a fabricated feature whose label wasn't provided.
    Core.frame(body, "ClippedReferenceDetail", 279, 341, 19, 17, Color3.fromRGB(185, 188, 188))

    context:connect(context.input.InputBegan, function(input, processed)
        if processed or context.input:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            context.gui.Enabled = not context.gui.Enabled
            if context.popup then context.popup:Destroy(); context.popup = nil end
            return
        end
        if not context.gui.Enabled or context.popup then return end
        local key = input.KeyCode
        local index = table.find(context.rows, context.selected) or 1
        if key == Enum.KeyCode.Up or key == Enum.KeyCode.Down then
            index = (index - 1 + (key == Enum.KeyCode.Down and 1 or -1)) % #context.rows + 1
            context.rows[index]:select()
        elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.Space then
            local selected = context.selected
            if selected then selected:activate() end
        elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.Right then
            local selected = context.selected
            if selected and selected.adjust then selected:adjust(key == Enum.KeyCode.Right and 1 or -1) end
        end
    end)
    return window
end

return Window
