--[[
    VIOLENT — standalone client-sided Luau menu (UI replica of the reference)

    GENERATED FILE. Edit violent-ui/src/*.lua and run:
        python3 violent-ui/build.py

    Usage (script executor):
        loadstring(game:HttpGet("<raw url to this file>"))()

    Or paste this whole file into the executor's editor and run it.

    Visibility : RightShift toggles both windows.
    Teardown   : getgenv().VIOLENT_UI.Destroy()

    Every feature callback is an intentionally empty stub (see Stubs.lua).
    The script draws the interface only; it performs no game actions.
]]

local __defs, __cache = {}, {}

local function define(name, factory)
    __defs[name] = factory
end

local function require(name)
    local cached = __cache[name]
    if cached ~= nil then
        return cached
    end
    local factory = __defs[name]
    assert(factory ~= nil, "[VIOLENT] missing module: " .. tostring(name))
    local module = factory()
    __cache[name] = module
    return module
end

define("Theme", function()
--[[
	Theme.lua
	Palette, typography and layout metrics for the Violent menu replica.

	Every number here was measured against the reference screenshot
	(307 x 507 px window) and scaled by ~1.15 to the 352 px design width used
	by the runtime. Change the tokens here, not inside the components.
]]

local Theme = {}

Theme.Name = "VIOLENT"
Theme.Version = "1.0.0"

-- Sampled from the reference. The window body is translucent black, which is
-- why the upper rows read slate blue (sky behind) and the lower rows read
-- near-black (ground behind). The tint lives in Transparency, below.
Theme.Color = {
	accent        = Color3.fromRGB(255, 20, 147),  -- header, selected colours
	accentSoft    = Color3.fromRGB(255, 95, 181),  -- highlighted row fill
	accentDeep    = Color3.fromRGB(193, 26, 126),  -- section underline
	accentGlow    = Color3.fromRGB(176, 40, 200),  -- ESP preview bloom
	swatchMagenta = Color3.fromRGB(254, 0, 232),
	swatchPink    = Color3.fromRGB(254, 24, 179),
	swatchWhite   = Color3.fromRGB(255, 255, 255),

	black         = Color3.fromRGB(0, 0, 0),
	tab           = Color3.fromRGB(0, 0, 0),
	text          = Color3.fromRGB(242, 244, 245),
	textMuted     = Color3.fromRGB(169, 176, 181),
	textDim       = Color3.fromRGB(140, 146, 150),
	textOnAccent  = Color3.fromRGB(14, 12, 13),
	white         = Color3.fromRGB(255, 255, 255),

	previewTop    = Color3.fromRGB(44, 49, 59),
	previewBottom = Color3.fromRGB(90, 17, 120),
	figure        = Color3.fromRGB(205, 187, 214),
	bone          = Color3.fromRGB(246, 238, 246),
	healthHigh    = Color3.fromRGB(32, 224, 48),
	healthUpper   = Color3.fromRGB(160, 240, 24),
	healthMid     = Color3.fromRGB(255, 226, 26),
	healthLow     = Color3.fromRGB(255, 26, 26),
}

Theme.Transparency = {
	body = 0.24,     -- the whole menu body: game world shows through
	tab = 0,         -- page header strip stays solid black
	footer = 0.16,   -- status bar
	preview = 0.20,  -- ESP preview panel
}

-- Layout, in design pixels. UIScale handles resolution.
Theme.Metric = {
	windowWidth = 352,
	windowHeight = 588,
	headerHeight = 85,
	tabHeight = 32,
	rowHeight = 29,
	sectionHeight = 38,
	dropdownHeight = 34,
	dividerHeight = 3,
	footerHeight = 30,
	paddingX = 10,
	paddingRight = 7,
	checkbox = 22,
	swatchWidth = 27,
	swatchHeight = 20,
	titleUnderline = 4,
	previewWidth = 330,
	previewHeight = 340,
	previewStrip = 8,
	previewBoxWidth = 134,
	previewBoxHeight = 212,
	windowGap = 20,
}

Theme.Text = {
	logo = 50,
	body = 15,
	value = 14,
	tab = 14,
	counter = 13,
	section = 18,
	footer = 15,
	previewTitle = 24,
	previewBody = 11,
}

-- Font lookup is defensive: executors occasionally ship a trimmed Enum.Font or
-- an older client. Everything falls back to a font that has existed forever.
local function enumFont(name)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	if ok and value ~= nil then
		return value
	end
	return nil
end

local function firstFont(names, fallback)
	for _, name in ipairs(names) do
		local font = enumFont(name)
		if font then
			return font
		end
	end
	return fallback
end

Theme.Font = {
	display = firstFont({ "LuckiestGuy", "GothamBlack", "Bangers", "Arcade" }, Enum.Font.Legacy),
	section = firstFont({ "FredokaOne", "LuckiestGuy", "GothamBlack", "Arcade" }, Enum.Font.Legacy),
	body = firstFont({ "GothamMedium", "Gotham", "SourceSansSemibold", "Arial" }, Enum.Font.SourceSans),
	bodyBold = firstFont({ "GothamBold", "Gotham", "SourceSansBold", "ArialBold" }, Enum.Font.SourceSansBold),
}

-- "Release, v1.4" is set in an italic serif in the reference. FontFace is
-- guarded because not every executor exposes Font.new.
do
	local ok, face = pcall(function()
		return Font.new(
			"rbxasset://fonts/families/Garamond.json",
			Enum.FontWeight.Regular,
			Enum.FontStyle.Italic
		)
	end)
	if ok and face ~= nil then
		Theme.Font.serifItalic = face
	else
		Theme.Font.serifItalic = firstFont({ "Garamond", "Bodoni", "Merriweather", "Antique" }, Theme.Font.body)
	end
end

return Theme
end)

define("Util", function()
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
end)

define("State", function()
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
end)

define("Stubs", function()
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
end)

define("Controls", function()
--[[
	Controls.lua
	Row-level components: toggle (checkbox), numeric value, colour swatch,
	section title and the release selector. Each builder returns a small
	control table with Set/Get helpers; none of them contains feature logic.
]]

local Theme = require("Theme")
local Util = require("Util")

local Controls = {}

local M = Theme.Metric
local C = Theme.Color
local T = Theme.Text

local function newRow(parent, height)
	local row = Util.button({
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height or M.rowHeight),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	return row
end

local function rowLabel(row, text, rightInset)
	return Util.label({
		Name = "Label",
		Text = text,
		Position = UDim2.new(0, M.paddingX, 0, 0),
		Size = UDim2.new(1, -(M.paddingX + (rightInset or 34)), 1, 0),
		TextSize = T.body,
		TextColor3 = C.text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
end

-- Subtle hover wash. Returns a lock setter so selected rows keep their fill.
local function attachHover(row)
	local locked = false
	row.MouseEnter:Connect(function()
		if locked then
			return
		end
		row.BackgroundColor3 = C.white
		row.BackgroundTransparency = 0.93
	end)
	row.MouseLeave:Connect(function()
		if locked then
			return
		end
		row.BackgroundTransparency = 1
	end)
	return function(value)
		locked = value
		if not value then
			row.BackgroundTransparency = 1
		end
	end
end

-- Checkbox: white 2 px border, transparent inside, hand-drawn check mark.
local function makeCheckbox(parent)
	local box = Util.new("Frame", {
		Name = "Checkbox",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -M.paddingRight, 0.5, 0),
		Size = UDim2.fromOffset(M.checkbox, M.checkbox),
		BackgroundColor3 = C.black,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Util.stroke(box, { color = C.white, thickness = 2 })
	Util.corner(box, 1)

	local check = Util.new("Frame", {
		Name = "Check",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = box,
	})

	-- Two arms meeting at a vertex near (9, 14) inside the 22 px box.
	Util.new("Frame", {
		Size = UDim2.fromOffset(5, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -3.75, 0.5, 1.25),
		Rotation = 45,
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		Parent = check,
	})
	Util.new("Frame", {
		Size = UDim2.fromOffset(12, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 2, 0.5, -1.5),
		Rotation = -48,
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		Parent = check,
	})

	return box, check
end

--[[ Toggle row ]]-------------------------------------------------------------
function Controls.Toggle(parent, spec, callbacks)
	local row = newRow(parent)
	rowLabel(row, spec.label, M.checkbox + M.paddingRight + 12)
	local _, check = makeCheckbox(row)

	local control = { Frame = row }

	function control.Set(value)
		check.Visible = value and true or false
	end

	control.Set(spec.value ~= false)
	attachHover(row)

	row.MouseButton1Click:Connect(function()
		local nextValue = not check.Visible
		control.Set(nextValue)
		if callbacks and callbacks.onChanged then
			callbacks.onChanged(nextValue)
		end
	end)

	return control
end

--[[ Numeric value row ]]------------------------------------------------------
function Controls.Value(parent, spec, callbacks)
	local row = newRow(parent)
	rowLabel(row, spec.label, 54)

	local valueLabel = Util.label({
		Name = "Value",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -M.paddingRight, 0.5, 0),
		Size = UDim2.fromOffset(52, M.rowHeight),
		TextSize = T.value,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local control = { Frame = row }
	local format = spec.format or "%s"
	local step = spec.step or 1
	local minValue = spec.min or 0
	local maxValue = spec.max or 100

	local function render(value)
		valueLabel.Text = string.format(format, value)
	end

	function control.Set(value)
		render(value)
	end

	control.Set(spec.value)

	attachHover(row)
	row.MouseButton1Click:Connect(function()
		local nextValue = spec.value + step
		if nextValue > maxValue + 0.0001 then
			nextValue = minValue
		end
		spec.value = nextValue
		render(nextValue)
		if callbacks and callbacks.onChanged then
			callbacks.onChanged(nextValue)
		end
	end)

	return control
end

--[[ Colour row ]]-------------------------------------------------------------
function Controls.Color(parent, spec, callbacks)
	local row = newRow(parent)
	local label = rowLabel(row, spec.label, M.swatchWidth + M.paddingRight + 12)
	local setLocked = attachHover(row)

	local swatch = Util.button({
		Name = "Swatch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -M.paddingRight, 0.5, 0),
		Size = UDim2.fromOffset(M.swatchWidth, M.swatchHeight),
		BackgroundColor3 = spec.value,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = row,
	})
	local swatchStroke = Util.stroke(swatch, { color = C.black, thickness = 2 })

	local control = { Frame = row, Swatch = swatch }
	local selected = false

	function control.Set(value)
		spec.value = value
		swatch.BackgroundColor3 = value
	end

	function control.SetSelected(value)
		selected = value and true or false
		setLocked(selected)
		row.BackgroundColor3 = C.accentSoft
		row.BackgroundTransparency = selected and 0 or 1
		label.TextColor3 = selected and C.textOnAccent or C.text
		swatchStroke.Color = C.black
	end

	function control.Get()
		return spec.value
	end

	control.Set(spec.value)
	control.SetSelected(spec.id == spec.selectedId)

	row.MouseButton1Click:Connect(function()
		if callbacks and callbacks.onSelect then
			callbacks.onSelect(control)
		end
	end)

	-- The swatch swallows its own click (GuiButton), so it selects the row and
	-- then advertises the empty colour-picker hook.
	swatch.MouseButton1Click:Connect(function()
		if callbacks and callbacks.onSelect then
			callbacks.onSelect(control)
		end
		if callbacks and callbacks.onPick then
			callbacks.onPick(control)
		end
	end)

	return control
end

--[[ Section title ]]----------------------------------------------------------
function Controls.Section(parent, spec)
	local holder = Util.new("Frame", {
		Name = "Section",
		Size = UDim2.new(1, 0, 0, M.sectionHeight),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local shadow = Util.new("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Font.section,
		Text = spec.label,
		TextColor3 = C.black,
		TextSize = T.section,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 2, 0, 3),
		Size = UDim2.new(0, 0, 0, 28),
		Rotation = -2,
		Parent = holder,
	})

	local label = Util.displayText({
		Text = spec.label,
		TextSize = T.section,
		Font = Theme.Font.section,
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 1),
		Size = UDim2.new(0, 0, 0, 28),
		Rotation = -2,
		Parent = holder,
	})

	local underlineShadow = Util.new("Frame", {
		BackgroundColor3 = C.black,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 4, 0, 26),
		Size = UDim2.fromOffset(60, M.titleUnderline),
		Rotation = -2,
		Parent = holder,
	})

	local underline = Util.new("Frame", {
		BackgroundColor3 = C.accentDeep,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 3, 0, 24),
		Size = UDim2.fromOffset(60, M.titleUnderline),
		Rotation = -2,
		Parent = holder,
	})

	local function syncWidth()
		local width = math.max(label.AbsoluteSize.X + 10, 24)
		underline.Size = UDim2.fromOffset(width, M.titleUnderline)
		underlineShadow.Size = UDim2.fromOffset(width, M.titleUnderline)
	end

	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncWidth)
	task.defer(syncWidth)

	return { Frame = holder }
end

--[[ Release selector ]]-------------------------------------------------------
local function makeCaret(parent, direction, offsetY)
	local holder = Util.new("Frame", {
		Name = direction > 0 and "CaretUp" or "CaretDown",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(16, 9),
		Position = UDim2.new(0.5, 0, 0, offsetY),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = parent,
	})

	for index = 1, 2 do
		local mirrored = index == 2
		Util.new("Frame", {
			BackgroundColor3 = C.white,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(8, 2),
			Position = UDim2.new(0, mirrored and 6.5 or 1.5, 0.5, 0),
			Rotation = (mirrored and -1 or 1) * 40 * direction,
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = holder,
		})
	end
end

function Controls.Selector(parent, spec, callbacks)
	local row = newRow(parent, M.dropdownHeight)

	local label = Util.label({
		Name = "Label",
		Text = spec.label,
		Position = UDim2.new(0, M.paddingX, 0, 0),
		Size = UDim2.new(1, -(M.paddingX + 60), 1, 0),
		TextSize = 18,
		TextColor3 = C.text,
		Parent = row,
	})
	local serif = Theme.Font.serifItalic
	if typeof(serif) == "Font" then
		Util.apply(label, "FontFace", serif)
	else
		label.Font = serif
	end

	local caretHolder = Util.new("Frame", {
		Name = "Carets",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(16, 24),
		Parent = row,
	})
	makeCaret(caretHolder, -1, 1)
	makeCaret(caretHolder, 1, 13)

	-- Small white rule at the far right of the selector row.
	Util.new("Frame", {
		Name = "Rule",
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -M.paddingX, 0.5, 0),
		Size = UDim2.fromOffset(14, 2),
		Parent = row,
	})

	attachHover(row)

	local control = { Frame = row }

	function control.Set(text)
		label.Text = text
	end

	local up = Util.button({
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, -8, 0, 2),
		Size = UDim2.fromOffset(16, 10),
		Parent = row,
	})
	local down = Util.button({
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, -8, 0, 14),
		Size = UDim2.fromOffset(16, 8),
		Parent = row,
	})
	up.MouseButton1Click:Connect(function()
		if callbacks and callbacks.onStep then
			callbacks.onStep(1)
		end
	end)
	down.MouseButton1Click:Connect(function()
		if callbacks and callbacks.onStep then
			callbacks.onStep(-1)
		end
	end)

	return control
end

return Controls
end)

define("Window", function()
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
end)

define("Page", function()
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
end)

define("Preview", function()
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
end)

define("Menu", function()
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
end)

define("Main", function()
--[[
	Main.lua
	Entry point. Builds the ScreenGui in the safest container the executor
	offers, mounts the menu, binds the visibility key (RightShift) and returns
	the public API.

	Standalone: no game-specific code, no Studio assumptions, no features.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Theme = require("Theme")
local Util = require("Util")
local Menu = require("Menu")
local Stubs = require("Stubs")

local Main = {
	Name = Theme.Name,
	Version = Theme.Version,
	Visible = true,
}

local env = (typeof(getgenv) == "function" and getgenv()) or _G

-- Replace a previous build instead of stacking a second copy.
local previous = env.VIOLENT_UI
if type(previous) == "table" and type(previous.Destroy) == "function" then
	pcall(previous.Destroy)
end

local screen = Util.new("ScreenGui", {
	Name = "ViolentUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 90,
})
Util.protectGui(screen)

-- Parent into the hidden-UI container when available; CoreGui and PlayerGui
-- are the fallbacks. The parent call itself is guarded: some executors expose
-- gethui() but still refuse the assignment.
local function mount(gui)
	local ok = pcall(function()
		gui.Parent = Util.guiParent()
	end)
	if ok and gui.Parent ~= nil then
		return
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
	if player then
		local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
		if playerGui then
			gui.Parent = playerGui
		end
	end
end

mount(screen)

local menu = Menu.new(screen)

Main.Menu = menu
Main.Screen = screen
Main.State = menu.State
Main.Stubs = Stubs

function Main.SetVisible(visible)
	menu:SetVisible(visible)
	Main.Visible = menu.Visible
end

function Main.Toggle()
	Main.SetVisible(not menu.Visible)
end

-- RightShift shows/hides both windows (UI-only behaviour).
local keyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightShift then
		Main.Toggle()
	end
end)

-- Keep the board scaled to the viewport. Positions are only laid out once so
-- dragging is never undone by a resolution change.
Main.__lastViewport = Util.viewportSize()
local viewportConnection = RunService.RenderStepped:Connect(function()
	local viewport = Util.viewportSize()
	if viewport ~= Main.__lastViewport then
		Main.__lastViewport = viewport
		menu:RefreshScale(false)
	end
end)

function Main.Destroy()
	if Main.__destroyed then
		return
	end
	Main.__destroyed = true

	pcall(function()
		keyConnection:Disconnect()
	end)
	pcall(function()
		viewportConnection:Disconnect()
	end)
	pcall(function()
		menu:Destroy()
	end)
	pcall(function()
		screen:Destroy()
	end)

	if env.VIOLENT_UI == Main then
		env.VIOLENT_UI = nil
	end
end

env.VIOLENT_UI = Main

Stubs.Ready()

return Main
end)

return require("Main")
