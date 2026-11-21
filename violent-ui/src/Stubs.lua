--[[
	Stubs.lua
	Every feature/callback hook the UI exposes, intentionally empty.

	The interface is complete; the behaviour is not. If you wire a real
	feature later, this is the only file that should change (plus whatever
	module you attach behind it). Each entry below is a no-op on purpose.
]]

local Stubs = {}

local function noop() end

-- Generic hooks -------------------------------------------------------------
Stubs.Ready = noop            -- fired after the menu has been mounted
Stubs.Unload = noop           -- fired before the ScreenGui is destroyed
Stubs.MenuShown = noop        -- keybind made the menu visible
Stubs.MenuHidden = noop       -- keybind hid the menu
Stubs.PageChanged = noop      -- page/tab was switched

-- Control hooks -------------------------------------------------------------
Stubs.ToggleChanged = noop    -- (controlId, enabled)
Stubs.ValueChanged = noop     -- (controlId, value)
Stubs.ValueCommitted = noop   -- (controlId, value) after a drag/release
Stubs.ColorSelected = noop    -- (controlId) row became the colour target
Stubs.ColorPicked = noop      -- (controlId, color) swatch requested a colour
Stubs.VersionStepped = noop   -- (+1 / -1) release selector arrow pressed
Stubs.RefreshPreview = noop   -- preview window redraw requested

-- Named per-feature hooks (all empty). Kept separate so a feature module can
-- be attached to exactly one control without touching the component code.
Stubs.Visuals = {
	SetSkeleton = noop,
	SetSkeletonThickness = noop,
	SetSkeletonColor = noop,
	SetHighlightEsp = noop,
	SetHighlightFill = noop,
	SetHighlightOutline = noop,
	SetHighlightFillColor = noop,
	SetHighlightOutlineColor = noop,
	SetHealthBar = noop,
	SetHealthBarSize = noop,
}

-- Control id -> named stub, used by Menu.lua when a row changes.
Stubs.ById = {
	skeleton = Stubs.Visuals.SetSkeleton,
	skeletonThickness = Stubs.Visuals.SetSkeletonThickness,
	skeletonColor = Stubs.Visuals.SetSkeletonColor,
	highlightEsp = Stubs.Visuals.SetHighlightEsp,
	highlightFill = Stubs.Visuals.SetHighlightFill,
	highlightOutline = Stubs.Visuals.SetHighlightOutline,
	highlightFillColor = Stubs.Visuals.SetHighlightFillColor,
	highlightOutlineColor = Stubs.Visuals.SetHighlightOutlineColor,
	showHealthBar = Stubs.Visuals.SetHealthBar,
	healthBarSize = Stubs.Visuals.SetHealthBarSize,
}

return Stubs
