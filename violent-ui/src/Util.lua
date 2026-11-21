--[[
	Util.lua
	Instance construction helpers, strokes, text defaults, safe parenting and
	window dragging. Everything here is executor-safe (no Studio-only APIs).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require("Theme")

local Util = {}

-- Assign a property without letting a missing/renamed property kill the build.
function Util.apply(instance, key, value)
	pcall(function()
		instance[key] = value
	end)
end

--[[
	Util.new(className, properties, children)
	Creates the instance, applies every property except Parent, parents the
	children, and only then parents the result: fewer layout rebuilds and no
	half-constructed frames flashing on screen.
]]
function Util.new(className, properties, children)
	local instance = Instance.new(className)
	local parent = nil

	if properties then
		parent = properties.Parent
		for key, value in pairs(properties) do
			if key ~= "Parent" then
				Util.apply(instance, key, value)
			end
		end
	end

	if children then
		for _, child in ipairs(children) do
			if child then
				child.Parent = instance
			end
		end
	end

	if parent then
		instance.Parent = parent
	end

	return instance
end

function Util.stroke(parent, options)
	options = options or {}
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = options.mode or Enum.ApplyStrokeMode.Border
	stroke.Color = options.color or Theme.Color.white
	stroke.Thickness = options.thickness or 1
	stroke.Transparency = options.transparency or 0
	if options.lineJoin then
		Util.apply(stroke, "LineJoinMode", options.lineJoin)
	end
	stroke.Parent = parent
	return stroke
end

function Util.corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 0)
	corner.Parent = parent
	return corner
end

function Util.padding(parent, left, right, top, bottom)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingRight = UDim.new(0, right or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingBottom = UDim.new(0, bottom or 0)
	padding.Parent = parent
	return padding
end

-- TextLabel with the menu's baseline styling.
function Util.label(properties)
	local props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Font.body,
		RichText = false,
		Text = "",
		TextColor3 = Theme.Color.text,
		TextSize = Theme.Text.body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	for key, value in pairs(properties or {}) do
		props[key] = value
	end
	return Util.new("TextLabel", props)
end

function Util.button(properties)
	local props = {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		RichText = false,
		Text = "",
		TextTransparency = 1,
	}
	for key, value in pairs(properties or {}) do
		props[key] = value
	end
	return Util.new("TextButton", props)
end

-- White text with a solid black outline, used for the logo and section titles.
function Util.displayText(properties)
	local props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Font.display,
		RichText = false,
		TextColor3 = Theme.Color.white,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	for key, value in pairs(properties or {}) do
		props[key] = value
	end
	local strokeThickness = props.StrokeThickness or 2
	props.StrokeThickness = nil
	local label = Util.new("TextLabel", props)
	Util.stroke(label, {
		mode = Enum.ApplyStrokeMode.Contextual,
		color = Theme.Color.black,
		thickness = strokeThickness,
	})
	return label
end

-- Safe place to parent the ScreenGui: executor hidden UI, then CoreGui, then
-- the local player's PlayerGui. Never assumes Studio.
function Util.guiParent()
	if typeof(gethui) == "function" then
		local ok, result = pcall(gethui)
		if ok and result ~= nil then
			return result
		end
	end

	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and coreGui ~= nil then
		return coreGui
	end

	local player = Players.LocalPlayer
	if player == nil then
		for _ = 1, 100 do
			player = Players.LocalPlayer
			if player ~= nil then
				break
			end
			task.wait(0.05)
		end
	end
	if player == nil then
		error("[Violent] LocalPlayer unavailable", 0)
	end
	return player:WaitForChild("PlayerGui")
end

function Util.protectGui(screenGui)
	if typeof(syn) == "table" and type(syn.protect_gui) == "function" then
		pcall(syn.protect_gui, screenGui)
	elseif typeof(protect_gui) == "function" then
		pcall(protect_gui, screenGui)
	end
end

function Util.viewportSize()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

--[[
	Util.drag(frame, handle, getScale, sink)
	Moves `frame` while `handle` is dragged. Positions stay in the holder's
	design-pixel space, so the delta is divided by the current UIScale.
]]
function Util.drag(frame, handle, getScale, sink)
	local dragging = false
	local dragStart = nil
	local startPos = nil

	local began
	began = handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		dragging = true
		dragStart = input.Position
		startPos = frame.Position

		local ended
		ended = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				if ended then
					ended:Disconnect()
				end
			end
		end)
	end)

	local moved = UserInputService.InputChanged:Connect(function(input)
		if not dragging or not startPos then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local scale = getScale and getScale() or 1
		if scale <= 0 then
			scale = 1
		end

		local delta = input.Position - dragStart
		local viewport = Util.viewportSize()
		local maxX = (viewport.X / scale) - 48
		local maxY = (viewport.Y / scale) - 48
		local x = math.clamp(startPos.X.Offset + delta.X / scale, -frame.AbsoluteSize.X + 48, maxX)
		local y = math.clamp(startPos.Y.Offset + delta.Y / scale, 0, maxY)

		frame.Position = UDim2.new(startPos.X.Scale, x, startPos.Y.Scale, y)
	end)

	if sink then
		table.insert(sink, began)
		table.insert(sink, moved)
	end

	return function()
		dragging = false
	end
end

return Util
