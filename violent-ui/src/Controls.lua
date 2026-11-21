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
