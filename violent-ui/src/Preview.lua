--[[
	Preview.lua
	The right-hand "ESP PREVIEW" window: pink title strip, explanatory copy,
	and a static preview box with the health gradient, bloom, player silhouette
	and skeleton overlay. Purely decorative; it reads no game state.
]]

local Theme = require("Theme")
local Util = require("Util")

local M = Theme.Metric
local C = Theme.Color
local T = Theme.Text

local Preview = {}
Preview.__index = Preview

local function gradient(parent, colorSequence, rotation)
	local instance = Instance.new("UIGradient")
	instance.Color = colorSequence
	instance.Rotation = rotation or 0
	instance.Parent = parent
	return instance
end

local function silhouettePart(parent, position, size, radius, transparency)
	local part = Util.new("Frame", {
		BackgroundColor3 = C.figure,
		BackgroundTransparency = transparency or 0.35,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		Parent = parent,
	})
	if radius and radius > 0 then
		Util.corner(part, radius)
	end
	return part
end

local function bone(parent, position, size, rotation)
	local line = Util.new("Frame", {
		BackgroundColor3 = C.bone,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		Rotation = rotation or 0,
		Parent = parent,
	})
	return line
end

local function buildFigure(inner)
	local centerX = 0.5

	-- Coarse body mass, matching the reference silhouette.
	silhouettePart(inner, UDim2.new(centerX, -21, 0, 6), UDim2.fromOffset(42, 44), 15, 0.3)
	silhouettePart(inner, UDim2.new(centerX, -26, 0, 48), UDim2.fromOffset(52, 68), 9, 0.34)
	silhouettePart(inner, UDim2.new(centerX, -33, 0, 52), UDim2.fromOffset(14, 68), 7, 0.38)
	silhouettePart(inner, UDim2.new(centerX, 19, 0, 52), UDim2.fromOffset(14, 68), 7, 0.38)
	silhouettePart(inner, UDim2.new(centerX, -24, 0, 112), UDim2.fromOffset(48, 20), 7, 0.34)
	silhouettePart(inner, UDim2.new(centerX, -22, 0, 128), UDim2.fromOffset(20, 76), 7, 0.36)
	silhouettePart(inner, UDim2.new(centerX, 2, 0, 128), UDim2.fromOffset(20, 76), 7, 0.36)

	-- Skeleton overlay: spine, clavicle, arms and femurs.
	bone(inner, UDim2.new(centerX, -1, 0, 48), UDim2.fromOffset(2, 86))
	bone(inner, UDim2.new(centerX, -12, 0, 58), UDim2.fromOffset(24, 2))
	bone(inner, UDim2.new(centerX, -10, 0, 64), UDim2.fromOffset(2, 34), 24)
	bone(inner, UDim2.new(centerX, 9, 0, 64), UDim2.fromOffset(2, 34), -24)
	bone(inner, UDim2.new(centerX, -1, 0, 132), UDim2.fromOffset(2, 44))
	bone(inner, UDim2.new(centerX, -6, 0, 176), UDim2.fromOffset(12, 2))
	bone(inner, UDim2.new(centerX, -1, 0, 16), UDim2.fromOffset(2, 26))
end

function Preview.new(options)
	options = options or {}

	local width = M.previewWidth
	local height = M.previewHeight

	local root = Util.new("Frame", {
		Name = "EspPreview",
		Size = UDim2.fromOffset(width, height),
		Position = options.position or UDim2.fromOffset(0, 0),
		BackgroundColor3 = C.black,
		BackgroundTransparency = Theme.Transparency.preview,
		BorderSizePixel = 0,
		Parent = options.parent,
	})
	Util.stroke(root, { color = C.black, thickness = 2 })

	-- Pink title strip --------------------------------------------------------
	Util.new("Frame", {
		Name = "Strip",
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, M.previewStrip),
		Parent = root,
	})

	-- Title -------------------------------------------------------------------
	Util.new("TextLabel", {
		Name = "TitleShadow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Font.display,
		Text = "ESP PREVIEW",
		TextColor3 = C.black,
		TextSize = T.previewTitle,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(11, 17),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = root,
	})

	Util.displayText({
		Name = "Title",
		Text = "ESP PREVIEW",
		TextSize = T.previewTitle,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(9, 15),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = root,
	})

	-- Copy (wrapped exactly like the reference) --------------------------------
	Util.label({
		Name = "Description",
		Text = "Roblox doesnt support highlights or selection boxes\n"
			.. "in viewportframes so previews arent possible on\n"
			.. "those options.",
		Position = UDim2.fromOffset(9, 52),
		Size = UDim2.new(1, -18, 0, 46),
		TextSize = T.previewBody,
		TextColor3 = Color3.fromRGB(228, 236, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = false,
		Parent = root,
	})

	-- Preview box -------------------------------------------------------------
	local boxWidth = M.previewBoxWidth
	local boxHeight = M.previewBoxHeight
	local boxTop = 108

	-- Bloom, drawn as two stacked strokes because UIStroke has no blur.
	for index, glow in ipairs({
		{ inset = 30, thickness = 14, transparency = 0.88 },
		{ inset = 18, thickness = 9, transparency = 0.72 },
		{ inset = 9, thickness = 5, transparency = 0.5 },
	}) do
		local halo = Util.new("Frame", {
			Name = "Glow" .. index,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, boxTop - glow.inset / 2),
			Size = UDim2.fromOffset(boxWidth + glow.inset, boxHeight + glow.inset),
			Parent = root,
		})
		Util.stroke(halo, {
			color = C.accentGlow,
			thickness = glow.thickness,
			transparency = glow.transparency,
		})
	end

	-- Health gradient on the left edge of the box.
	local healthBack = Util.new("Frame", {
		Name = "HealthBar",
		BackgroundColor3 = C.black,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -(boxWidth / 2) - 4, 0, boxTop),
		Size = UDim2.fromOffset(7, boxHeight),
		Parent = root,
	})
	Util.stroke(healthBack, { color = C.black, thickness = 1 })

	local healthFill = Util.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		Parent = healthBack,
	})
	gradient(
		healthFill,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.healthHigh),
			ColorSequenceKeypoint.new(0.32, C.healthUpper),
			ColorSequenceKeypoint.new(0.62, C.healthMid),
			ColorSequenceKeypoint.new(0.84, Color3.fromRGB(255, 122, 0)),
			ColorSequenceKeypoint.new(1, C.healthLow),
		}),
		90
	)

	-- Black caps at both ends of the health bar, as in the reference.
	for _, y in ipairs({ 0, boxHeight - 6 }) do
		Util.new("Frame", {
			BackgroundColor3 = C.black,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 6),
			Parent = healthBack,
		})
	end

	-- Box: black outline, pink rim, purple gradient interior.
	local box = Util.new("Frame", {
		Name = "PreviewBox",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, boxTop),
		Size = UDim2.fromOffset(boxWidth, boxHeight),
		BackgroundColor3 = C.swatchPink,
		BorderSizePixel = 0,
		Parent = root,
	})
	Util.stroke(box, { color = C.black, thickness = 2 })

	local inner = Util.new("Frame", {
		Name = "Interior",
		BackgroundColor3 = C.previewTop,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		Parent = box,
	})
	gradient(
		inner,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.previewTop),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(72, 42, 94)),
			ColorSequenceKeypoint.new(1, C.previewBottom),
		}),
		90
	)

	buildFigure(inner)

	local self = setmetatable({
		Root = root,
		Box = box,
		Inner = inner,
		Width = width,
		Height = height,
		Connections = {},
	}, Preview)

	Util.drag(root, root, options.getScale, self.Connections)

	function self:GetRoot()
		return root
	end

	function self:SetVisible(visible)
		root.Visible = visible
	end

	function self:Destroy()
		for _, connection in ipairs(self.Connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(self.Connections)
		root:Destroy()
	end

	return self
end

return Preview
