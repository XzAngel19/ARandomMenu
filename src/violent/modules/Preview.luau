local Core, Theme = import("Core"), import("Theme")
local Preview = {}

function Preview.build(context)
    local window = Core.frame(context.canvas, "ESP Preview", 342, 26, 272, 313, Theme.Panel, 0.17)
    Core.frame(window, "TopAccent", 0, 0, 272, 5, Theme.Pink, 0.15)
    Core.frame(window, "AccentShadow", 0, 4, 272, 2, Theme.Black, 0.5)
    local title = Core.text(window, "ESP PREVIEW", 14, 9, 244, 30, 23, Theme.DisplayFont)
    title.TextStrokeTransparency, title.TextStrokeColor3 = 0.8, Theme.Black
    local note = Core.text(window,
        "Roblox doesnt support highlights or selection boxes\nin viewportframes so previews arent possible on\nthose options.",
        13, 40, 253, 37, 12)
    note.TextYAlignment = Enum.TextYAlignment.Top

    -- Purely decorative 2D artwork: no ViewportFrame, parts, Highlight,
    -- SelectionBox, camera, player lookup, or world adornments are created.
    for spread = 18, 2, -2 do
        Core.frame(window, "PurpleGlow", 76 - spread, 101 - spread,
            121 + spread * 2, 193 + spread * 2, Color3.fromRGB(174, 0, 190), 0.985)
    end
    local tint = Core.frame(window, "PreviewTint", 77, 102, 118, 192, Color3.fromRGB(116, 0, 160))
    Core.new("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(60, 61, 65), Color3.fromRGB(114, 0, 159)),
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.78),
            NumberSequenceKeypoint.new(1, 0.3) }), Rotation = 90,
    }, tint)
    local silhouette = Color3.fromRGB(146, 126, 157)
    local function limb(name, x, y, width, height, radius, transparency)
        local part = Core.frame(window, name, x, y, width, height, silhouette, transparency or 0.23)
        Core.new("UICorner", { CornerRadius = UDim.new(0, radius) }, part)
        return part
    end
    limb("Head", 119, 122, 35, 37, 10, 0.12)
    limb("Torso", 119, 154, 36, 74, 8)
    limb("LeftArm", 114, 163, 11, 66, 5, 0.33)
    limb("RightArm", 146, 162, 10, 67, 5, 0.33)
    limb("LeftLeg", 119, 218, 14, 65, 3, 0.32)
    limb("RightLeg", 132, 218, 20, 65, 3, 0.32)
    local skeleton = Color3.fromRGB(225, 215, 223)
    Core.line(window, "Spine", 136, 140, 136, 271, skeleton, 1)
    Core.line(window, "Shoulder", 136, 176, 132, 180, skeleton, 1)
    Core.line(window, "Arm", 132, 180, 132, 220, skeleton, 1)
    Core.line(window, "OtherArm", 137, 162, 137, 219, skeleton, 1)
    Core.line(window, "Hip", 136, 220, 134, 227, skeleton, 1)
    Core.line(window, "Leg", 134, 227, 134, 260, skeleton, 1)

    local outline = Core.frame(window, "StaticBoundingBox", 76, 100, 121, 195, Theme.Black, 1)
    Core.stroke(outline, Theme.Black, 3)
    local inner = Core.frame(outline, "MagentaEdge", 0, 0, 121, 195, Theme.Pink, 1)
    Core.stroke(inner, Color3.fromRGB(91, 0, 80), 1)
    Core.frame(window, "HealthTrack", 70, 99, 3, 197, Theme.Black)
    local health = Core.frame(window, "StaticHealthBar", 70, 140, 1, 155, Theme.White)
    Core.new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 255, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 239, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 32, 50)),
        }),
    }, health)
    Core.drag(context, Core.button(window, "DragPreview", 0, 0, 272, 38), window)
    return window
end

return Preview
