--[[
	State.lua
	Pure view-state for the menu: checkbox values, numeric values, colour
	values, the active colour target and the 29/51 counter.

	Nothing in here touches the game. Feature code is expected to subscribe to
	the stubs in Stubs.lua, not to read State directly.
]]

local Theme = require("Theme")

local State = {}
State.__index = State

-- 24 of the 51 enabled features live on other pages that this replica does not
-- draw; the five visible checkboxes start enabled, which is the 29 in the
-- reference screenshot's "29/51".
local BASE_ENABLED = 24
local TOTAL_ENABLED = 51

function State.new()
	local self = setmetatable({}, State)

	self.toggles = {
		skeleton = true,
		highlightEsp = true,
		highlightFill = true,
		highlightOutline = true,
		showHealthBar = true,
	}

	self.values = {
		skeletonThickness = 1,
		healthBarSize = 2.5,
	}

	self.colors = {
		skeletonColor = Theme.Color.swatchWhite,
		highlightFillColor = Theme.Color.swatchMagenta,
		highlightOutlineColor = Theme.Color.swatchPink,
	}

	self.colorTarget = "highlightOutlineColor"
	self.colorLabels = {
		skeletonColor = "Skeleton Color",
		highlightFillColor = "Highlight Fill Color",
		highlightOutlineColor = "Highlight Outline Color",
	}

	self.versionLabel = "Release, v1.4"
	self.pageName = "VISUALS / HUD"

	return self
end

function State:EnabledCount()
	local count = BASE_ENABLED
	for _, enabled in pairs(self.toggles) do
		if enabled then
			count += 1
		end
	end
	return count
end

function State:CounterText()
	return string.format("%d/%d", self:EnabledCount(), TOTAL_ENABLED)
end

function State:ColorTargetLabel()
	return self.colorLabels[self.colorTarget] or "None"
end

return State
