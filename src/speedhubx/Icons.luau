--!nocheck
--[[
    Speed Hub X — Icons
    ====================
    Every glyph in the reference screenshot (scan-face, house, pickaxe,
    fist, mountains, chevrons, the close "x") is re-drawn here from
    plain Frames.  No external image assets are required, so the script
    works on any executor, anywhere, with zero asset-id dependencies.

    Icons are intentionally simple stylised approximations of the
    originals, drawn at a 23x23 design size.
]]

local Util = require("Util")

local Icons = {}

---------------------------------------------------------------------------
-- Rounded bar between two points (container-local coordinates).
-- Roblox rotation is clockwise-positive with 0 = vertical bar.
---------------------------------------------------------------------------
local function rotationFor(direction)
    return math.deg(math.atan2(direction.X, -direction.Y))
end

local function bar(container, p1, p2, thickness, color, transparency)
    local delta = p2 - p1
    local length = delta.Magnitude
    local mid = (p1 + p2) / 2
    local frame = Util.create("Frame", {
        BackgroundColor3 = color,
        BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, mid.X, 0, mid.Y),
        Size = UDim2.new(0, thickness, 0, length + thickness * 0.6),
        Rotation = rotationFor(delta),
        Corner = math.floor(thickness / 2 + 0.5),
    })
    frame.Parent = container
    return frame
end

local function ring(container, center, diameter, thickness, color, transparency)
    local frame = Util.create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, center.X, 0, center.Y),
        Size = UDim2.new(0, diameter, 0, diameter),
        Corner = 999,
        Stroke = {
            Color = color,
            Thickness = thickness,
            Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        },
    })
    frame.Parent = container
    return frame
end

local function dot(container, center, diameter, color, transparency)
    local frame = Util.create("Frame", {
        BackgroundColor3 = color,
        BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, center.X, 0, center.Y),
        Size = UDim2.new(0, diameter, 0, diameter),
        Corner = 999,
    })
    frame.Parent = container
    return frame
end

local function outline(container, center, size, cornerRadius, thickness, color, transparency)
    local frame = Util.create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, center.X, 0, center.Y),
        Size = UDim2.new(0, size.X, 0, size.Y),
        Corner = cornerRadius,
        Stroke = {
            Color = color,
            Thickness = thickness,
            Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        },
    })
    frame.Parent = container
    return frame
end

local function container(size)
    return Util.create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(size or 23, size or 23),
    })
end

local function v2(x, y)
    return Vector2.new(x, y)
end

---------------------------------------------------------------------------
-- Home — face inside corner brackets ("scan" glyph)
---------------------------------------------------------------------------
function Icons.scanFace(color, transparency)
    local c = color or Color3.fromRGB(218, 218, 218)
    local root = container(23)
    local o = transparency or 0
    local arm = 6.2   -- bracket arm length
    local thick = 2.1
    local inset = 1.2
    -- four corner brackets
    local corners = {
        v2(inset, inset),                    -- top-left
        v2(23 - inset, inset),               -- top-right
        v2(inset, 23 - inset),               -- bottom-left
        v2(23 - inset, 23 - inset),          -- bottom-right
    }
    for _, cornerPoint in ipairs(corners) do
        local signX = cornerPoint.X < 12 and 1 or -1
        local signY = cornerPoint.Y < 12 and 1 or -1
        bar(root, cornerPoint, v2(cornerPoint.X + arm * signX, cornerPoint.Y), thick, c, o)
        bar(root, cornerPoint, v2(cornerPoint.X, cornerPoint.Y + arm * signY), thick, c, o)
    end
    -- face ring
    ring(root, v2(11.5, 12.8), 12.5, 1.9, c, o)
    -- eyes
    dot(root, v2(8.6, 11.6), 1.9, c, o)
    dot(root, v2(14.4, 11.6), 1.9, c, o)
    -- smile: bottom half of a ring, clipped by a frame
    local clip = Util.create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 5, 0, 12.6),
        Size = UDim2.new(0, 13, 0, 6.4),
        ClipsDescendants = true,
    })
    clip.Parent = root
    ring(clip, v2(6.5, 0), 10.5, 1.9, c, o)
    return root
end

---------------------------------------------------------------------------
-- Main — house
---------------------------------------------------------------------------
function Icons.house(color, transparency)
    local c = color or Color3.fromRGB(218, 218, 218)
    local root = container(23)
    local o = transparency or 0
    -- roof (two strokes meeting at the apex)
    bar(root, v2(2.8, 11.6), v2(11.5, 3.4), 2.2, c, o)
    bar(root, v2(11.5, 3.4), v2(20.2, 11.6), 2.2, c, o)
    -- body outline
    outline(root, v2(11.5, 14.6), Vector2.new(13.2, 7.6), 2.2, 2.2, c, o)
    -- door
    outline(root, v2(11.5, 15.6), Vector2.new(4.2, 5.2), 2.1, 1.8, c, o)
    return root
end

---------------------------------------------------------------------------
-- Farming — pickaxe
---------------------------------------------------------------------------
function Icons.pickaxe(color, transparency)
    local c = color or Color3.fromRGB(218, 218, 218)
    local root = container(23)
    local o = transparency or 0
    -- handle: apex at top, descending to bottom-right
    bar(root, v2(9.4, 6.2), v2(18.6, 20.4), 2.6, c, o)
    -- head: shallow arc across the top (two strokes)
    bar(root, v2(2.6, 9.0), v2(10.4, 2.2), 2.6, c, o)
    bar(root, v2(10.4, 2.2), v2(20.6, 7.6), 2.6, c, o)
    -- small inner curve hint
    bar(root, v2(4.4, 11.9), v2(8.6, 8.6), 1.7, c, o)
    return root
end

---------------------------------------------------------------------------
-- Killer — fist
---------------------------------------------------------------------------
function Icons.fist(color, transparency)
    local c = color or Color3.fromRGB(218, 218, 218)
    local root = container(23)
    local o = transparency or 0
    -- knuckle bumps along the top
    local knuckleXs = { 4.6, 9.0, 13.4, 17.2 }
    for index, x in ipairs(knuckleXs) do
        local height = index == 1 and 6.2 or (index == 4 and 5.2 or 7.2)
        bar(root, v2(x, 8.6), v2(x, 8.6 - height), 2.6, c, o)
    end
    -- palm outline
    outline(root, v2(10.6, 13.4), Vector2.new(16.4, 9.4), 4.6, 2.2, c, o)
    -- finger grooves
    for _, x in ipairs({ 7.6, 11.4, 15.0 }) do
        bar(root, v2(x, 12.6), v2(x, 17.4), 1.7, c, o)
    end
    -- thumb curl on the right side
    ring(root, v2(19.4, 13.6), 5.6, 2.0, c, o)
    return root
end

---------------------------------------------------------------------------
-- Misc — two peaks over a base line ("image" glyph)
---------------------------------------------------------------------------
function Icons.mountains(color, transparency)
    local c = color or Color3.fromRGB(218, 218, 218)
    local root = container(23)
    local o = transparency or 0
    -- big peak (left)
    bar(root, v2(2.2, 15.8), v2(8.4, 4.2), 2.2, c, o)
    bar(root, v2(8.4, 4.2), v2(14.6, 15.8), 2.2, c, o)
    -- small peak (right)
    bar(root, v2(11.2, 15.8), v2(15.9, 8.0), 2.0, c, o)
    bar(root, v2(15.9, 8.0), v2(20.8, 15.8), 2.0, c, o)
    -- base line
    bar(root, v2(1.4, 18.6), v2(21.6, 18.6), 1.9, c, o)
    -- tiny wave line across the middle
    bar(root, v2(4.6, 12.2), v2(7.6, 10.6), 1.3, c, o)
    bar(root, v2(7.6, 10.6), v2(10.4, 12.4), 1.3, c, o)
    return root
end

---------------------------------------------------------------------------
-- Chevron (^) — rotate 180° for the expanded state
---------------------------------------------------------------------------
function Icons.chevron(color, transparency)
    local c = color or Color3.fromRGB(238, 238, 238)
    local root = container(23)
    local o = transparency or 0
    bar(root, v2(4.5, 15.5), v2(11.5, 7.5), 2.3, c, o)
    bar(root, v2(11.5, 7.5), v2(18.5, 15.5), 2.3, c, o)
    return root
end

---------------------------------------------------------------------------
-- Close (×)
---------------------------------------------------------------------------
function Icons.close(color, transparency, size)
    local c = color or Color3.fromRGB(245, 245, 245)
    local s = size or 17
    local root = container(s)
    local o = transparency or 0
    local inset = 1.8
    bar(root, v2(inset, inset), v2(s - inset, s - inset), 2.4, c, o)
    bar(root, v2(s - inset, inset), v2(inset, s - inset), 2.4, c, o)
    return root
end

return Icons
