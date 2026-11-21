--[[
	Window.lua
	The window shell: pink header with the VIOLENT wordmark, translucent body,
	pink divider and the black status/footer bar. Drag is bound to the header.
]]

local Theme = require("Theme")
local Util = require("Util")

local M = Theme.Metric
local C = Theme.Color
local T = Theme.Text

local Window = {}
Window.__index = Window

function Window.new(options)
	options = options or {}

	local width = options.width or M.windowWidth
	local height = options.height or M.windowHeight

	local root = Util.new("Frame", {
		Name = options.name or "Window",
		Size = UDim2.fromOffset(width, height),
		Position = options.position or UDim2.fromOffset(0, 0),
		BackgroundColor3 = C.black,
		BackgroundTransparency = Theme.Transparency.body,
		BorderSizePixel = 0,
		Parent = options.parent,
	})
	Util.stroke(root, { color = C.black, thickness = 2 })

	-- Header ------------------------------------------------------------------
	local header = Util.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, M.headerHeight),
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = root,
	})

	local logoHolder = Util.new("Frame", {
		Name = "Logo",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 1, -4),
		Parent = header,
	})

	Util.new("TextLabel", {
		Name = "LogoShadow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Font.display,
		Text = options.title or Theme.Name,
		TextColor3 = C.black,
		TextSize = T.logo,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromScale(1, 1),
		Parent = logoHolder,
	})

	Util.displayText({
		Name = "LogoText",
		Text = options.title or Theme.Name,
		TextSize = T.logo,
		StrokeThickness = 3,
		Size = UDim2.fromScale(1, 1),
		Parent = logoHolder,
	})

	-- Body --------------------------------------------------------------------
	local body = Util.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, M.headerHeight),
		Size = UDim2.new(1, 0, 1, -(M.headerHeight + M.dividerHeight + M.footerHeight)),
		Parent = root,
	})

	-- Footer ------------------------------------------------------------------
	local divider = Util.new("Frame", {
		Name = "Divider",
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -M.footerHeight),
		Size = UDim2.new(1, 0, 0, M.dividerHeight),
		Parent = root,
	})

	local footer = Util.new("Frame", {
		Name = "Footer",
		BackgroundColor3 = C.black,
		BackgroundTransparency = Theme.Transparency.footer,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, M.footerHeight),
		Parent = root,
	})

	local status = Util.label({
		Name = "Status",
		Text = options.status or "",
		Position = UDim2.fromOffset(M.paddingX, 0),
		Size = UDim2.new(1, -(M.paddingX * 2), 1, 0),
		TextSize = T.footer,
		TextColor3 = C.text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = footer,
	})

	local self = setmetatable({
		Root = root,
		Header = header,
		Body = body,
		Footer = footer,
		Divider = divider,
		Width = width,
		Height = height,
		Connections = {},
	}, Window)

	Util.drag(root, header, options.getScale, self.Connections)

	function self:GetRoot()
		return root
	end

	function self:GetBody()
		return body
	end

	function self:SetStatus(text)
		status.Text = text
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

return Window
