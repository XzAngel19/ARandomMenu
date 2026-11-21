--[[
	Page.lua
	A page is the black tab strip ("VISUALS / HUD" + counter) plus the
	scrollable list of rows underneath it. The page API is what Menu.lua talks
	to; the row components live in Controls.lua.
]]

local Theme = require("Theme")
local Util = require("Util")
local Controls = require("Controls")

local M = Theme.Metric
local C = Theme.Color
local T = Theme.Text

local Page = {}
Page.__index = Page

function Page.new(window, spec)
	spec = spec or {}
	local body = window:GetBody()

	local strip = Util.new("Frame", {
		Name = "TabStrip",
		BackgroundColor3 = C.tab,
		BackgroundTransparency = Theme.Transparency.tab,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, M.tabHeight),
		Parent = body,
	})

	local title = Util.label({
		Name = "PageName",
		Text = spec.name or "",
		Position = UDim2.fromOffset(M.paddingX, 0),
		Size = UDim2.new(1, -(M.paddingX * 2 + 70), 1, 0),
		TextSize = T.tab,
		TextColor3 = C.text,
		Parent = strip,
	})

	local counter = Util.label({
		Name = "Counter",
		Text = spec.counter or "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -M.paddingX, 0.5, 0),
		Size = UDim2.fromOffset(70, M.tabHeight),
		TextSize = T.counter,
		TextColor3 = C.textMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = strip,
	})

	local scroll = Util.new("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, M.tabHeight),
		Size = UDim2.new(1, 0, 1, -M.tabHeight),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0,
		ScrollingEnabled = true,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ClipsDescendants = true,
		Parent = body,
	})

	Util.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 0),
		Parent = scroll,
	})

	local self = setmetatable({
		Window = window,
		Frame = body,
		Strip = strip,
		Scroll = scroll,
		Counter = counter,
		Name = spec.name or "",
		Order = 0,
	}, Page)

	function self:NextOrder()
		self.Order += 1
		return self.Order
	end

	function self:SetCounter(text)
		counter.Text = text
	end

	function self:AddSection(title)
		local spec = { label = title }
		local control = Controls.Section(scroll, spec)
		control.Frame.LayoutOrder = self:NextOrder()
		return control
	end

	function self:AddToggle(spec, callbacks)
		local control = Controls.Toggle(scroll, spec, callbacks)
		control.Frame.LayoutOrder = self:NextOrder()
		return control
	end

	function self:AddValue(spec, callbacks)
		local control = Controls.Value(scroll, spec, callbacks)
		control.Frame.LayoutOrder = self:NextOrder()
		return control
	end

	function self:AddColor(spec, callbacks)
		local control = Controls.Color(scroll, spec, callbacks)
		control.Frame.LayoutOrder = self:NextOrder()
		return control
	end

	function self:AddSelector(spec, callbacks)
		local control = Controls.Selector(scroll, spec, callbacks)
		control.Frame.LayoutOrder = self:NextOrder()
		return control
	end

	return self
end

return Page
