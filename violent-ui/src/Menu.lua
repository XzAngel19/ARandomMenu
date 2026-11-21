--[[
	Menu.lua
	Assembles the window, the VISUALS / HUD page, every row visible in the
	reference screenshot, and the ESP preview panel. Control changes are
	forwarded to State (view state) and Stubs (empty feature hooks).
]]

local Theme = require("Theme")
local Util = require("Util")
local State = require("State")
local Window = require("Window")
local Page = require("Page")
local Preview = require("Preview")
local Stubs = require("Stubs")

local M = Theme.Metric

local Menu = {}
Menu.__index = Menu

-- The page, in the exact order of the reference.
local ROWS = {
	{ kind = "toggle", id = "skeleton", label = "Enable Skeleton" },
	{ kind = "value", id = "skeletonThickness", label = "Skeleton Thickness", step = 1, min = 1, max = 10, format = "%d" },
	{ kind = "color", id = "skeletonColor", label = "Skeleton Color" },
	{ kind = "section", label = "Highlights" },
	{ kind = "toggle", id = "highlightEsp", label = "Highlight ESP" },
	{ kind = "toggle", id = "highlightFill", label = "Highlight Fill" },
	{ kind = "toggle", id = "highlightOutline", label = "Highlight Outline" },
	{ kind = "color", id = "highlightFillColor", label = "Highlight Fill Color" },
	{ kind = "color", id = "highlightOutlineColor", label = "Highlight Outline Color" },
	{ kind = "section", label = "Health bar" },
	{ kind = "toggle", id = "showHealthBar", label = "Show Health Bar" },
	{ kind = "value", id = "healthBarSize", label = "Healt Bar Size", step = 0.5, min = 0.5, max = 10, format = "%.1f" },
	{ kind = "section", label = "text" },
	{ kind = "selector", id = "release", label = "Release, v1.4" },
}

function Menu.new(parent)
	local state = State.new()

	local holder = Util.new("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})

	-- One scale for the whole board keeps both windows locked to each other.
	local scaleObject = Instance.new("UIScale")
	scaleObject.Scale = 1
	scaleObject.Parent = holder

	local window = Window.new({
		parent = holder,
		title = Theme.Name,
		status = "Set color to: " .. state:ColorTargetLabel(),
		getScale = function()
			return scaleObject.Scale
		end,
	})

	local preview = Preview.new({
		parent = holder,
		getScale = function() return scaleObject.Scale end,
	})

	local page = Page.new(window, {
		name = state.pageName,
		counter = state:CounterText(),
	})

	local self = setmetatable({
		Holder = holder,
		Scale = scaleObject,
		Window = window,
		Preview = preview,
		Page = page,
		State = state,
		ColorControls = {},
		Visible = true,
		LaidOut = false,
	}, Menu)

	local function selectColor(selected)
		for _, control in pairs(self.ColorControls) do
			control.SetSelected(control == selected)
		end
		state.colorTarget = selected.Id
		window:SetStatus("Set color to: " .. state:ColorTargetLabel())
		Stubs.ColorSelected(selected.Id)
	end

	for _, spec in ipairs(ROWS) do
		if spec.kind == "section" then
			page:AddSection(spec.label)
		elseif spec.kind == "toggle" then
			page:AddToggle({
				id = spec.id,
				label = spec.label,
				value = state.toggles[spec.id],
			}, {
				onChanged = function(value)
					state.toggles[spec.id] = value
					page:SetCounter(state:CounterText())
					Stubs.ToggleChanged(spec.id, value)
					local named = Stubs.ById[spec.id]
					if named then
						named(value)
					end
				end,
			})
		elseif spec.kind == "value" then
			page:AddValue({
				id = spec.id,
				label = spec.label,
				value = state.values[spec.id],
				step = spec.step,
				min = spec.min,
				max = spec.max,
				format = spec.format,
			}, {
				onChanged = function(value)
					state.values[spec.id] = value
					Stubs.ValueChanged(spec.id, value)
					local named = Stubs.ById[spec.id]
					if named then
						named(value)
					end
				end,
			})
		elseif spec.kind == "color" then
			local control = page:AddColor({
				id = spec.id,
				label = spec.label,
				value = state.colors[spec.id],
				selectedId = state.colorTarget,
			}, {
				onSelect = selectColor,
				onPick = function(picked)
					Stubs.ColorPicked(picked.Id, picked.Get())
				end,
			})
			control.Id = spec.id
			self.ColorControls[spec.id] = control
		elseif spec.kind == "selector" then
			page:AddSelector({
				id = spec.id,
				label = spec.label,
			}, {
				onStep = function(direction)
					Stubs.VersionStepped(direction)
				end,
			})
		end
	end

	self:RefreshScale(true)

	return self
end

function Menu:RefreshScale(resetPosition)
	local viewport = Util.viewportSize()
	local screenScale = math.clamp(
		math.min(viewport.X / 1180, viewport.Y / 820),
		0.7,
		1.35
	)
	self.Scale.Scale = screenScale

	if resetPosition or not self.LaidOut then
		self.LaidOut = true
		local totalWidth = M.windowWidth + M.windowGap + M.previewWidth
		local x = math.max(10, (viewport.X - totalWidth * screenScale) / 2 / screenScale)
		local y = math.max(10, (viewport.Y - M.windowHeight * screenScale) / 2 / screenScale)

		self.Window.Root.Position = UDim2.fromOffset(x, y)
		self.Preview.Root.Position = UDim2.fromOffset(x + M.windowWidth + M.windowGap, y)
	end
end

function Menu:SetStatus(text)
	self.Window:SetStatus(text)
end

function Menu:SetCounter(text)
	self.Page:SetCounter(text)
end

function Menu:SetVisible(visible)
	self.Visible = visible and true or false
	self.Window:SetVisible(self.Visible)
	self.Preview:SetVisible(self.Visible)
	if self.Visible then
		Stubs.MenuShown()
	else
		Stubs.MenuHidden()
	end
end

function Menu:Toggle()
	self:SetVisible(not self.Visible)
end

function Menu:Destroy()
	Stubs.Unload()
	pcall(function()
		self.Window:Destroy()
	end)
	pcall(function()
		self.Preview:Destroy()
	end)
	if self.Holder then
		self.Holder:Destroy()
	end
end

return Menu
