-- Egg Hub | GUI.
local playersService = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local httpService = game:GetService("HttpService")

local WINDOW_WIDTH = 400
local WINDOW_HEIGHT = 600
local TITLE_HEIGHT = 34
local TAB_HEIGHT = 30
local MIN_WIDTH = 320
local MIN_HEIGHT = 480
local MAX_WIDTH = 700
local MAX_HEIGHT = 1050
local CONFIG_FOLDER = "EggHub"
local CONFIG_FILE = "EggHub/EggHub.json"
local TAB_NAMES = { "Main", "Extra", "Visuals", "Config" }
local TITLE_TEXT = "Angel Hub | Steal an Egg"

local ACCENT_A = Color3.fromRGB(225, 225, 225)
local ACCENT_B = Color3.fromRGB(110, 110, 116)
local BACKGROUND_TOP = Color3.fromRGB(25, 25, 27)
local BACKGROUND_BOTTOM = Color3.fromRGB(9, 9, 10)
local ROW_COLOR = Color3.fromRGB(34, 34, 36)
local ELEMENT_COLOR = Color3.fromRGB(17, 17, 19)
local TEXT_COLOR = Color3.fromRGB(238, 238, 238)
local OFF_TEXT_COLOR = Color3.fromRGB(192, 192, 196)
local DIM_TEXT_COLOR = Color3.fromRGB(120, 120, 124)

local TEXT_FONT = Enum.Font.SourceSans
local BOLD_FONT = Enum.Font.SourceSansBold

local FAST_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MEDIUM_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local COLOR_PRESETS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 145, 55),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(70, 255, 120),
	Color3.fromRGB(65, 225, 255),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(185, 95, 255),
	Color3.fromRGB(255, 95, 195),
	Color3.fromRGB(25, 25, 28),
}

local localPlayer = playersService.LocalPlayer

local EggHub = {
	values = {},
	pages = {},
	tabButtons = {},
	tabIndex = {},
	searchables = {},
	sections = {},
	boxes = {},
	sectionBoxes = {},
	setters = {},
	actions = {},
	connections = {},
	keybinds = {},
	keyLabels = {},
	listening = nil,
	defaults = {},
	menuKey = Enum.KeyCode.RightShift,
}

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in properties do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function tween(instance, info, goal)
	local newTween = tweenService:Create(instance, info, goal)
	newTween:Play()
	return newTween
end

local function connectInput(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(EggHub.connections, connection)
	return connection
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function addGradient(parent, rotation)
	return create("UIGradient", { Color = ColorSequence.new(ACCENT_A, ACCENT_B), Rotation = rotation }, parent)
end

local function addStroke(parent, color, transparency, thickness)
	return create("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function createCard(className, parent, text, height)
	local card = create(className, {
		Name = text,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = ROW_COLOR,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
	}, EggHub.sectionBoxes[parent] or parent)

	create("UICorner", { CornerRadius = UDim.new(0, 5) }, card)
	local stroke = addStroke(card, ACCENT_A, 1)
	card.ClipsDescendants = true

	local group = EggHub.currentGroup
	if group then
		table.insert(group.cards, card)
		card:SetAttribute("GroupHidden", group.collapsed)
		card.Visible = not group.collapsed
	end

	card.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end

		local offset = Vector2.new(input.Position.X, input.Position.Y) - card.AbsolutePosition
		local ripple = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(offset.X, offset.Y),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, card)

		create("UICorner", { CornerRadius = UDim.new(1, 0) }, ripple)
		local diameter = math.max(card.AbsoluteSize.X, card.AbsoluteSize.Y) * 2

		tween(ripple, MEDIUM_TWEEN, { Size = UDim2.fromOffset(diameter, diameter), BackgroundTransparency = 1 }).Completed:Connect(function()
			ripple:Destroy()
		end)
	end)

	card.MouseEnter:Connect(function()
		tween(card, FAST_TWEEN, { BackgroundTransparency = 0.35 })
		tween(stroke, FAST_TWEEN, { Transparency = 0.55 })
	end)

	card.MouseLeave:Connect(function()
		tween(card, FAST_TWEEN, { BackgroundTransparency = 0.65 })
		tween(stroke, FAST_TWEEN, { Transparency = 1 })
	end)

	return card, stroke
end

local function addSection(parent, text)
	local box = create("Frame", {
		Name = text .. " Box",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(22, 22, 24),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		LayoutOrder = #EggHub.boxes + 1,
	}, parent)

	create("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
	addStroke(box, Color3.fromRGB(105, 105, 110), 0.55)
	create("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 170)), Rotation = 90 }, box)
	create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, box)
	create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, box)

	local holder = create("Frame", { Name = text, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, box)
	local marker = create("Frame", {
		Size = UDim2.fromOffset(3, 12),
		Position = UDim2.new(0, 3, 0.5, -7),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(1, 0) }, marker)
	addGradient(marker, 90)
	tweenService:Create(marker, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.5 }):Play()

	create("TextLabel", {
		Size = UDim2.new(1, -14, 1, -4),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = string.upper(text),
		TextColor3 = ACCENT_A,
		TextSize = 11,
		Font = BOLD_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local line = create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, holder)

	local gradient = addGradient(line, 0)
	gradient.Transparency = NumberSequence.new(0.3, 1)

	EggHub.sectionBoxes[parent] = box
	table.insert(EggHub.boxes, box)
	table.insert(EggHub.sections, holder)
end

local function addToggle(parent, text, keybind, default)
	local holder, stroke = createCard("TextButton", parent, text, 28)
	holder.Text = ""
	holder.AutoButtonColor = false

	local box = create("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(0, 8, 0.5, -8),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
	local boxStroke = addStroke(box, default and ACCENT_A or DIM_TEXT_COLOR, default and 0 or 0.5)

	local check = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = default and UDim2.fromOffset(10, 10) or UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, box)

	create("UICorner", { CornerRadius = UDim.new(0, 3) }, check)
	addGradient(check, 45)

	local label = create("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(32, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = default and TEXT_COLOR or OFF_TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local accentBar = create("Frame", {
		Size = UDim2.new(0, 3, 1, -10),
		Position = UDim2.fromOffset(0, 5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = default and 0 or 1,
		BorderSizePixel = 0,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(1, 0) }, accentBar)
	addGradient(accentBar, 90)

	local state = default
	EggHub.values[text] = state
	EggHub.defaults[text] = default

	EggHub.setters[text] = function(value)
		state = value == true
		EggHub.values[text] = state

		tween(check, POP_TWEEN, { Size = state and UDim2.fromOffset(10, 10) or UDim2.fromOffset(0, 0) })
		tween(boxStroke, FAST_TWEEN, { Color = state and ACCENT_A or DIM_TEXT_COLOR, Transparency = state and 0 or 0.5 })
		tween(label, FAST_TWEEN, { TextColor3 = state and TEXT_COLOR or OFF_TEXT_COLOR })
		tween(accentBar, FAST_TWEEN, { BackgroundTransparency = state and 0 or 1 })
	end

	if keybind then
		local keybindName = text .. " Keybind"
		local keybindButton = create("TextButton", {
			Size = UDim2.fromOffset(52, 22),
			Position = UDim2.new(1, -58, 0.5, -11),
			BackgroundTransparency = 1,
			Text = "[" .. keybind .. "]",
			TextColor3 = DIM_TEXT_COLOR,
			TextSize = 12,
			Font = TEXT_FONT,
			TextXAlignment = Enum.TextXAlignment.Right,
			AutoButtonColor = false,
		}, holder)

		local function applyKey(keyName)
			local keyCode = nil
			for _, item in Enum.KeyCode:GetEnumItems() do
				if item.Name == keyName then
					keyCode = item
					break
				end
			end

			EggHub.keybinds[text] = keyCode
			EggHub.values[keybindName] = keyCode and keyName or ""
			keybindButton.Text = keyCode and ("[" .. keyName .. "]") or "[None]"
			keybindButton.Visible = EggHub.values["Keybind Hints"] ~= false
		end

		EggHub.defaults[keybindName] = keybind
		EggHub.setters[keybindName] = applyKey
		EggHub.keyLabels[text] = keybindButton
		applyKey(keybind)

		keybindButton.MouseEnter:Connect(function()
			tween(keybindButton, FAST_TWEEN, { TextColor3 = ACCENT_A })
		end)

		keybindButton.MouseLeave:Connect(function()
			if not EggHub.listening then
				tween(keybindButton, FAST_TWEEN, { TextColor3 = DIM_TEXT_COLOR })
			end
		end)

		keybindButton.Activated:Connect(function()
			if EggHub.cancelListening then
				EggHub.cancelListening()
			end

			local previousKey = EggHub.values[keybindName]
			keybindButton.Text = "[...]"
			tween(keybindButton, FAST_TWEEN, { TextColor3 = ACCENT_A })

			EggHub.cancelListening = function()
				EggHub.listening = nil
				EggHub.cancelListening = nil
				tween(keybindButton, FAST_TWEEN, { TextColor3 = DIM_TEXT_COLOR })
				applyKey(previousKey)
			end

			EggHub.listening = function(keyCode)
				EggHub.listening = nil
				EggHub.cancelListening = nil
				tween(keybindButton, FAST_TWEEN, { TextColor3 = DIM_TEXT_COLOR })
				applyKey(keyCode == Enum.KeyCode.Escape and "" or keyCode.Name)
			end
		end)
	end

	holder.MouseButton1Down:Connect(function()
		tween(holder, FAST_TWEEN, { BackgroundTransparency = 0 })
		tween(stroke, FAST_TWEEN, { Transparency = 0 })
	end)

	holder.MouseButton1Up:Connect(function()
		tween(holder, FAST_TWEEN, { BackgroundTransparency = 0.35 })
		tween(stroke, FAST_TWEEN, { Transparency = 0.55 })
	end)

	holder.Activated:Connect(function()
		EggHub.setters[text](not state)
		if EggHub.notify then
			EggHub.notify(text, state)
		end
	end)

	holder.MouseEnter:Connect(function()
		tween(label, FAST_TWEEN, { Position = UDim2.fromOffset(36, 0) })
	end)

	holder.MouseLeave:Connect(function()
		tween(label, FAST_TWEEN, { Position = UDim2.fromOffset(32, 0) })
	end)

	table.insert(EggHub.searchables, holder)
end

local function addSlider(parent, text, minValue, maxValue, default, decimals)
	local holder = createCard("Frame", parent, text, 44)
	local startAlpha = (default - minValue) / (maxValue - minValue)

	create("TextLabel", {
		Size = UDim2.new(1, -70, 0, 20),
		Position = UDim2.fromOffset(10, 3),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local valueLabel = create("TextLabel", {
		Size = UDim2.fromOffset(56, 20),
		Position = UDim2.new(1, -66, 0, 3),
		BackgroundTransparency = 1,
		Text = tostring(default),
		TextColor3 = OFF_TEXT_COLOR,
		TextSize = 13,
		Font = BOLD_FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, holder)

	local bar = create("Frame", {
		Size = UDim2.new(1, -20, 0, 6),
		Position = UDim2.fromOffset(10, 29),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
	addStroke(bar, Color3.new(1, 1, 1), 0.88)

	local fill = create("Frame", { Size = UDim2.fromScale(startAlpha, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, bar)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	addGradient(fill, 0)

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.new(startAlpha, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, bar)

	create("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	addStroke(knob, ACCENT_A, 0, 2)
	local knobScale = create("UIScale", {}, knob)

	local hitbox = create("Frame", { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 21), BackgroundTransparency = 1 }, holder)

	EggHub.values[text] = default
	EggHub.defaults[text] = default

	local dragging = false

	local function setValue(value)
		local factor = 10 ^ decimals
		value = math.floor(math.clamp(value, minValue, maxValue) * factor + 0.5) / factor
		local snapped = (value - minValue) / (maxValue - minValue)

		tween(fill, SLIDE_TWEEN, { Size = UDim2.fromScale(snapped, 1) })
		tween(knob, SLIDE_TWEEN, { Position = UDim2.new(snapped, 0, 0.5, 0) })
		valueLabel.Text = tostring(value)
		EggHub.values[text] = value
	end

	EggHub.setters[text] = setValue

	local function updateFromX(positionX)
		local alpha = math.clamp((positionX - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		setValue(minValue + (maxValue - minValue) * alpha)
	end

	hitbox.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end

		dragging = true
		tween(knobScale, POP_TWEEN, { Scale = 1.35 })
		tween(valueLabel, FAST_TWEEN, { TextColor3 = ACCENT_A })
		updateFromX(input.Position.X)
	end)

	connectInput(userInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			updateFromX(input.Position.X)
		end
	end)

	connectInput(userInputService.InputEnded, function(input)
		if not dragging or not isPress(input) then
			return
		end

		dragging = false
		tween(knobScale, POP_TWEEN, { Scale = 1 })
		tween(valueLabel, FAST_TWEEN, { TextColor3 = OFF_TEXT_COLOR })
	end)

	table.insert(EggHub.searchables, holder)
end

local function addCycle(parent, text, options)
	local holder = createCard("Frame", parent, text, 56)

	create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 3),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local button = create("TextButton", {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 26),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
		Text = options[1],
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		AutoButtonColor = false,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
	local buttonStroke = addStroke(button, DIM_TEXT_COLOR, 0.6)

	local index = 1
	EggHub.values[text] = options[1]
	EggHub.defaults[text] = options[1]

	EggHub.setters[text] = function(value)
		local found = table.find(options, value)
		if not found then
			return
		end

		index = found
		EggHub.values[text] = options[index]
		button.Text = options[index]
	end

	button.MouseEnter:Connect(function()
		tween(buttonStroke, FAST_TWEEN, { Color = ACCENT_A, Transparency = 0 })
	end)

	button.MouseLeave:Connect(function()
		tween(buttonStroke, FAST_TWEEN, { Color = DIM_TEXT_COLOR, Transparency = 0.6 })
	end)

	button.Activated:Connect(function()
		index = index % #options + 1
		EggHub.values[text] = options[index]
		button.Text = options[index]
		button.TextTransparency = 1
		tween(button, FAST_TWEEN, { TextTransparency = 0 })
	end)

	table.insert(EggHub.searchables, holder)
end

local function addButton(parent, text, callback)
	local holder = createCard("Frame", parent, text, 34)

	local button = create("TextButton", {
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 5),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		AutoButtonColor = false,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
	local buttonStroke = addStroke(button, DIM_TEXT_COLOR, 0.6)

	button.MouseEnter:Connect(function()
		tween(buttonStroke, FAST_TWEEN, { Color = ACCENT_A, Transparency = 0 })
		tween(button, FAST_TWEEN, { BackgroundColor3 = Color3.fromRGB(28, 28, 30) })
	end)

	button.MouseLeave:Connect(function()
		tween(buttonStroke, FAST_TWEEN, { Color = DIM_TEXT_COLOR, Transparency = 0.6 })
		tween(button, FAST_TWEEN, { BackgroundColor3 = ELEMENT_COLOR })
	end)

	button.MouseButton1Down:Connect(function()
		tween(button, FAST_TWEEN, { BackgroundColor3 = Color3.fromRGB(46, 46, 48) })
	end)

	button.MouseButton1Up:Connect(function()
		tween(button, FAST_TWEEN, { BackgroundColor3 = Color3.fromRGB(28, 28, 30) })
	end)

	if callback then
		EggHub.actions[text] = callback
	end

	button.Activated:Connect(function()
		local fn = EggHub.actions[text]
		if fn then
			fn()
		end
	end)
	table.insert(EggHub.searchables, holder)
end

local function addText(parent, text, placeholder, default)
	local holder = createCard("Frame", parent, text, 34)

	create("TextLabel", {
		Size = UDim2.new(0.42, -8, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 12,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local box = create("TextBox", {
		Size = UDim2.new(0.58, -12, 0, 22),
		Position = UDim2.new(0.42, 0, 0.5, -11),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = DIM_TEXT_COLOR,
		Text = default or "",
		TextColor3 = TEXT_COLOR,
		TextSize = 12,
		Font = TEXT_FONT,
		ClearTextOnFocus = false,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
	local boxStroke = addStroke(box, DIM_TEXT_COLOR, 0.6)

	box.Focused:Connect(function()
		tween(boxStroke, FAST_TWEEN, { Color = ACCENT_A, Transparency = 0 })
	end)

	box.FocusLost:Connect(function()
		tween(boxStroke, FAST_TWEEN, { Color = DIM_TEXT_COLOR, Transparency = 0.6 })
	end)

	EggHub.values[text] = default or ""
	EggHub.defaults[text] = default or ""

	EggHub.setters[text] = function(value)
		box.Text = tostring(value)
		EggHub.values[text] = box.Text
	end

	box:GetPropertyChangedSignal("Text"):Connect(function()
		EggHub.values[text] = box.Text
	end)

	table.insert(EggHub.searchables, holder)
end

local function addKeybind(parent, text, default)
	local holder = createCard("Frame", parent, text, 28)

	create("TextLabel", {
		Size = UDim2.new(1, -70, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local keybindButton = create("TextButton", {
		Size = UDim2.fromOffset(58, 22),
		Position = UDim2.new(1, -64, 0.5, -11),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
		Text = default and ("[" .. default .. "]") or "[None]",
		TextColor3 = DIM_TEXT_COLOR,
		TextSize = 12,
		Font = TEXT_FONT,
		AutoButtonColor = false,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, keybindButton)
	addStroke(keybindButton, DIM_TEXT_COLOR, 0.6)

	local keybindName = text .. " Value"
	EggHub.defaults[keybindName] = default
	EggHub.values[keybindName] = default or ""

	local function applyKey(keyName)
		EggHub.values[keybindName] = keyName or ""
		keybindButton.Text = (keyName and keyName ~= "") and ("[" .. keyName .. "]") or "[None]"
	end

	EggHub.setters[keybindName] = applyKey

	keybindButton.Activated:Connect(function()
		if EggHub.cancelListening then
			EggHub.cancelListening()
		end

		local previousKey = EggHub.values[keybindName]
		keybindButton.Text = "[...]"

		EggHub.cancelListening = function()
			EggHub.listening = nil
			EggHub.cancelListening = nil
			applyKey(previousKey)
		end

		EggHub.listening = function(keyCode)
			EggHub.listening = nil
			EggHub.cancelListening = nil
			applyKey(keyCode == Enum.KeyCode.Escape and "" or keyCode.Name)
		end
	end)

	table.insert(EggHub.searchables, holder)
end

local function openCircularColorPicker(titleText, currentColor, onChange)
	local gui = EggHub.screenGui
	if not gui then
		return
	end

	if EggHub.colorPickerPopup and EggHub.colorPickerPopup.Parent then
		local prevTitle = EggHub.colorPickerPopup:GetAttribute("ActiveTarget")
		EggHub.colorPickerPopup:Destroy()
		EggHub.colorPickerPopup = nil
		if prevTitle == titleText then
			return
		end
	end

	local h, s, v = Color3.toHSV(currentColor or Color3.new(1, 1, 1))
	local wheelSize = 136
	local radius = wheelSize * 0.5

	local popup = create("Frame", {
		Name = "EggHubColorWheelPopup",
		Size = UDim2.fromOffset(186, 206),
		Position = UDim2.new(0.5, 212, 0.5, -103),
		BackgroundColor3 = Color3.fromRGB(16, 16, 18),
		BorderSizePixel = 0,
		ZIndex = 60,
	}, gui)
	popup:SetAttribute("ActiveTarget", titleText)
	EggHub.colorPickerPopup = popup

	create("UICorner", { CornerRadius = UDim.new(0, 8) }, popup)
	addStroke(popup, ACCENT_A, 0.25, 1.5)

	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		ZIndex = 61,
	}, popup)

	create("TextLabel", {
		Size = UDim2.new(1, -56, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = titleText,
		TextColor3 = TEXT_COLOR,
		TextSize = 12,
		Font = BOLD_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 62,
	}, header)

	local closeBtn = create("TextButton", {
		Size = UDim2.fromOffset(44, 18),
		Position = UDim2.new(1, -50, 0, 4),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
		Text = "Done",
		TextColor3 = TEXT_COLOR,
		TextSize = 11,
		Font = BOLD_FONT,
		AutoButtonColor = false,
		ZIndex = 62,
	}, header)
	create("UICorner", { CornerRadius = UDim.new(0, 4) }, closeBtn)
	addStroke(closeBtn, Color3.new(1, 1, 1), 0.7)

	closeBtn.Activated:Connect(function()
		if popup.Parent then
			popup:Destroy()
		end
		if EggHub.colorPickerPopup == popup then
			EggHub.colorPickerPopup = nil
		end
	end)

	-- Circular HSV color wheel built from 60 radial gradient wedges inside a circular clip.
	local wheelContainer = create("Frame", {
		Size = UDim2.fromOffset(wheelSize, wheelSize),
		Position = UDim2.fromOffset(10, 32),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 61,
	}, popup)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, wheelContainer)

	local sliceCount = 60
	for i = 0, sliceCount - 1 do
		local frac = i / sliceCount
		local angleDeg = frac * 360
		local wedge = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, radius + 4),
			Rotation = angleDeg + 90,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 62,
		}, wheelContainer)
		create("UIGradient", {
			Color = ColorSequence.new(Color3.fromHSV(frac, 1, 1), Color3.new(1, 1, 1)),
			Rotation = 90,
		}, wedge)
	end

	-- Brightness overlay on the wheel so dragging Value darkens the wheel smoothly.
	local wheelShade = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = v,
		BorderSizePixel = 0,
		ZIndex = 63,
	}, wheelContainer)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, wheelShade)

	local wheelBorder = create("Frame", {
		Size = UDim2.fromOffset(wheelSize, wheelSize),
		Position = UDim2.fromOffset(10, 32),
		BackgroundTransparency = 1,
		ZIndex = 65,
	}, popup)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, wheelBorder)
	addStroke(wheelBorder, Color3.new(1, 1, 1), 0.6)

	local wheelDot = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 66,
	}, wheelBorder)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, wheelDot)
	addStroke(wheelDot, Color3.new(0, 0, 0), 0.1, 1.5)

	-- Vertical Value/Brightness slider bar beside the wheel.
	local valBar = create("Frame", {
		Size = UDim2.fromOffset(18, wheelSize),
		Position = UDim2.fromOffset(wheelSize + 20, 32),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 62,
	}, popup)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, valBar)
	addStroke(valBar, Color3.new(1, 1, 1), 0.6)
	local valGrad = create("UIGradient", {
		Color = ColorSequence.new(Color3.fromHSV(h, s, 1), Color3.new(0, 0, 0)),
		Rotation = 90,
	}, valBar)

	local valKnob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(1, 4, 0, 5),
		Position = UDim2.new(0.5, 0, 1 - v, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 64,
	}, valBar)
	create("UICorner", { CornerRadius = UDim.new(0, 2) }, valKnob)
	addStroke(valKnob, Color3.new(0, 0, 0), 0.1)

	-- Bottom preview swatch + hex readout.
	local sampleBox = create("Frame", {
		Size = UDim2.fromOffset(36, 18),
		Position = UDim2.fromOffset(10, 178),
		BackgroundColor3 = currentColor,
		BorderSizePixel = 0,
		ZIndex = 62,
	}, popup)
	create("UICorner", { CornerRadius = UDim.new(0, 4) }, sampleBox)
	addStroke(sampleBox, Color3.new(1, 1, 1), 0.5)

	local hexLabel = create("TextLabel", {
		Size = UDim2.new(1, -60, 0, 18),
		Position = UDim2.fromOffset(54, 178),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = DIM_TEXT_COLOR,
		TextSize = 12,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	}, popup)

	local function refreshVisuals()
		local chosen = Color3.fromHSV(h, s, v)
		local radAngle = h * math.pi * 2
		local rPx = s * (radius - 4)
		wheelDot.Position = UDim2.fromOffset(radius + math.cos(radAngle) * rPx, radius + math.sin(radAngle) * rPx)
		wheelShade.BackgroundTransparency = v
		valGrad.Color = ColorSequence.new(Color3.fromHSV(h, s, 1), Color3.new(0, 0, 0))
		valKnob.Position = UDim2.new(0.5, 0, 1 - v, 0)
		sampleBox.BackgroundColor3 = chosen
		hexLabel.Text = string.format("#%02X%02X%02X", math.round(chosen.R * 255), math.round(chosen.G * 255), math.round(chosen.B * 255))
		onChange(chosen)
	end

	local draggingWheel = false
	local draggingVal = false

	local function updateWheelFromPos(posX, posY)
		local absPos = wheelBorder.AbsolutePosition
		local absSize = wheelBorder.AbsoluteSize
		local cx = absPos.X + absSize.X * 0.5
		local cy = absPos.Y + absSize.Y * 0.5
		local dx = posX - cx
		local dy = posY - cy
		local dist = math.sqrt(dx * dx + dy * dy)
		local r = math.max(absSize.X * 0.5, 1)
		h = (math.atan2(dy, dx) / (2 * math.pi)) % 1
		s = math.clamp(dist / r, 0, 1)
		refreshVisuals()
	end

	local function updateValFromPos(posY)
		local top = valBar.AbsolutePosition.Y
		local height = math.max(valBar.AbsoluteSize.Y, 1)
		v = 1 - math.clamp((posY - top) / height, 0, 1)
		refreshVisuals()
	end

	wheelBorder.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingWheel = true
			updateWheelFromPos(input.Position.X, input.Position.Y)
		end
	end)

	valBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingVal = true
			updateValFromPos(input.Position.Y)
		end
	end)

	local changedConn = userInputService.InputChanged:Connect(function(input)
		if not popup.Parent then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			if draggingWheel then
				updateWheelFromPos(input.Position.X, input.Position.Y)
			elseif draggingVal then
				updateValFromPos(input.Position.Y)
			end
		end
	end)

	local endedConn = userInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingWheel = false
			draggingVal = false
		end
	end)

	popup.Destroying:Connect(function()
		if changedConn.Connected then changedConn:Disconnect() end
		if endedConn.Connected then endedConn:Disconnect() end
	end)

	refreshVisuals()
end

local function addColor(parent, text, default)
	local initialColor = default or COLOR_PRESETS[1]
	local holder = createCard("Frame", parent, text, 28)

	create("TextLabel", {
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local swatch = create("TextButton", {
		Size = UDim2.fromOffset(28, 18),
		Position = UDim2.new(1, -36, 0.5, -9),
		BackgroundColor3 = initialColor,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, swatch)
	addStroke(swatch, Color3.new(1, 1, 1), 0.5)

	local function coerceColor(value)
		if typeof(value) == "Color3" then
			return value
		end
		if type(value) == "table" and type(value.__color3) == "table" then
			local c = value.__color3
			return Color3.new(tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1)
		end
		return initialColor
	end

	EggHub.values[text] = initialColor
	EggHub.defaults[text] = initialColor

	EggHub.setters[text] = function(value)
		local resolved = coerceColor(value)
		swatch.BackgroundColor3 = resolved
		EggHub.values[text] = resolved
	end

	swatch.Activated:Connect(function()
		openCircularColorPicker(text, EggHub.values[text] or initialColor, function(newColor)
			EggHub.setters[text](newColor)
		end)
	end)

	table.insert(EggHub.searchables, holder)
end

local function addList(parent, text, items, height)
	height = height or 90
	local holder = createCard("Frame", parent, text, height + 24)

	create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 2),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 12,
		Font = BOLD_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local scroller = create("ScrollingFrame", {
		Size = UDim2.new(1, -16, 0, height),
		Position = UDim2.fromOffset(8, 22),
		BackgroundColor3 = ELEMENT_COLOR,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, scroller)
	create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, scroller)
	create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2) }, scroller)

	local rows = {}
	EggHub.values[text] = items[1]
	EggHub.defaults[text] = items[1]

	local function select(name)
		EggHub.values[text] = name
		for itemName, row in rows do
			row.BackgroundTransparency = itemName == name and 0.5 or 1
		end
	end

	for _, itemName in items do
		local row = create("TextButton", {
			Size = UDim2.new(1, -4, 0, 20),
			BackgroundColor3 = ACCENT_A,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = itemName,
			TextColor3 = TEXT_COLOR,
			TextSize = 12,
			Font = TEXT_FONT,
			AutoButtonColor = false,
		}, scroller)

		create("UICorner", { CornerRadius = UDim.new(0, 3) }, row)
		rows[itemName] = row

		row.Activated:Connect(function()
			select(itemName)
		end)
	end

	EggHub.setters[text] = select
	table.insert(EggHub.searchables, holder)
end

local function addCounter(parent, text, default)
	local holder = createCard("Frame", parent, text, 26)

	create("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local valueLabel = create("TextLabel", {
		Size = UDim2.fromOffset(50, 20),
		Position = UDim2.new(1, -58, 0.5, -10),
		BackgroundTransparency = 1,
		Text = tostring(default or 0),
		TextColor3 = ACCENT_A,
		TextSize = 13,
		Font = BOLD_FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, holder)

	EggHub.values[text] = default or 0
	EggHub.defaults[text] = default or 0

	EggHub.setters[text] = function(value)
		valueLabel.Text = tostring(value)
		EggHub.values[text] = value
	end

	table.insert(EggHub.searchables, holder)
end

local function beginGroup(parent, text)
	local group = { cards = {}, collapsed = true }
	local holder = createCard("Frame", parent, text .. " Options", 30)

	local button = create("TextButton", {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 4),
		BackgroundColor3 = ELEMENT_COLOR,
		BorderSizePixel = 0,
		Text = "+  Show " .. text,
		TextColor3 = OFF_TEXT_COLOR,
		TextSize = 12,
		Font = TEXT_FONT,
		AutoButtonColor = false,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
	local buttonStroke = addStroke(button, DIM_TEXT_COLOR, 0.6)

	button.MouseEnter:Connect(function()
		tween(buttonStroke, FAST_TWEEN, { Color = ACCENT_A, Transparency = 0 })
	end)

	button.MouseLeave:Connect(function()
		tween(buttonStroke, FAST_TWEEN, { Color = DIM_TEXT_COLOR, Transparency = 0.6 })
	end)

	button.Activated:Connect(function()
		group.collapsed = not group.collapsed
		button.Text = (group.collapsed and "+  Show " or "-  Hide ") .. text

		for _, card in group.cards do
			card:SetAttribute("GroupHidden", group.collapsed)
			card.Visible = not group.collapsed
		end
	end)

	table.insert(EggHub.searchables, holder)
	EggHub.currentGroup = group
end

local function endGroup()
	EggHub.currentGroup = nil
end

local function createColumn(parent, position)
	local column = create("ScrollingFrame", {
		Size = UDim2.new(0.5, -6, 1, 0),
		Position = position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = ACCENT_A,
		ScrollBarImageTransparency = 0.4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent)

	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, column)
	create("UIPadding", { PaddingRight = UDim.new(0, 6) }, column)

	return column
end

local function makeDraggable(handle, target)
	local dragStart, startPosition

	handle.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end

		dragStart = input.Position
		startPosition = target.Position
	end)

	connectInput(userInputService.InputChanged, function(input)
		if not dragStart or not isMove(input) then
			return
		end

		local delta = input.Position - dragStart
		target.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
	end)

	connectInput(userInputService.InputEnded, function(input)
		if isPress(input) then
			dragStart = nil
		end
	end)
end

local function createTitleButton(parent, text, offset, hoverColor)
	local button = create("TextButton", {
		Size = UDim2.fromOffset(24, 22),
		Position = UDim2.new(1, offset, 0.5, -11),
		BackgroundColor3 = ELEMENT_COLOR,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = TEXT_COLOR,
		TextSize = 13,
		Font = BOLD_FONT,
		AutoButtonColor = false,
	}, parent)

	create("UICorner", { CornerRadius = UDim.new(0, 5) }, button)

	button.MouseEnter:Connect(function()
		tween(button, FAST_TWEEN, { BackgroundColor3 = hoverColor, BackgroundTransparency = 0.1 })
	end)

	button.MouseLeave:Connect(function()
		tween(button, FAST_TWEEN, { BackgroundColor3 = ELEMENT_COLOR, BackgroundTransparency = 0.4 })
	end)

	button.MouseButton1Down:Connect(function()
		tween(button, FAST_TWEEN, { BackgroundTransparency = 0.4 })
	end)

	return button
end

local function switchTab(name)
	for pageName, page in EggHub.pages do
		local selected = pageName == name
		page.Visible = selected
		tween(EggHub.tabButtons[pageName], FAST_TWEEN, { TextColor3 = selected and TEXT_COLOR or DIM_TEXT_COLOR })

		if selected then
			page.GroupTransparency = 1
			tween(page, MEDIUM_TWEEN, { GroupTransparency = 0 })
		end
	end

	EggHub.selected = name
	tween(EggHub.indicator, MEDIUM_TWEEN, { Position = UDim2.new((EggHub.tabIndex[name] - 1) / #TAB_NAMES, 6, 0, 3) })
end

local function initializeScript()
	if typeof(shared) == "table" and shared.EggHubGui then
		pcall(function()
			shared.EggHubGui:Destroy()
		end)
	end

	local guiParent = localPlayer:WaitForChild("PlayerGui")

	if typeof(gethui) == "function" then
		local success, hiddenParent = pcall(gethui)
		if success and hiddenParent then
			guiParent = hiddenParent
		end
	end

	local screenGui = create("ScreenGui", {
		Name = "EggHubGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, guiParent)

	EggHub.screenGui = screenGui

	if typeof(shared) == "table" then
		shared.EggHubGui = screenGui
		shared.EggHub = EggHub
	end

	screenGui.Destroying:Connect(function()
		if type(EggHub.onUnload) == "function" then
			pcall(EggHub.onUnload)
		end
		for _, connection in EggHub.connections do
			connection:Disconnect()
		end

		table.clear(EggHub.connections)
	end)

	-- Toast notifications intentionally disabled per user request.
	EggHub.notify = function() end

	local window = create("Frame", {
		Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
		Position = UDim2.new(0.5, -WINDOW_WIDTH / 2, 0.5, -WINDOW_HEIGHT / 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, screenGui)

	create("UICorner", { CornerRadius = UDim.new(0, 8) }, window)
	create("UIGradient", { Color = ColorSequence.new(BACKGROUND_TOP, BACKGROUND_BOTTOM), Rotation = 90 }, window)

	local windowStroke = addStroke(window, Color3.new(1, 1, 1), 0.2, 1.5)
	addGradient(windowStroke, 45)

	local windowScale = create("UIScale", { Scale = 0.85 }, window)
	tween(windowScale, POP_TWEEN, { Scale = 1 })

	local sheen = create("Frame", { Size = UDim2.new(1, 0, 0, 140), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, window)
	create("UIGradient", { Transparency = NumberSequence.new(0.965, 1), Rotation = 90 }, sheen)

	local titleBar = create("Frame", { Size = UDim2.new(1, 0, 0, TITLE_HEIGHT), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, window)
	local titleGradient = addGradient(titleBar, 0)
	titleGradient.Transparency = NumberSequence.new(0.8, 0.92)

	local titleLine = create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, titleBar)

	addGradient(titleLine, 0)

	create("TextLabel", {
		Size = UDim2.new(1, -260, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		RichText = true,
		Text = "<b>" .. TITLE_TEXT .. "</b>",
		TextColor3 = TEXT_COLOR,
		TextSize = 14,
		Font = BOLD_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, titleBar)

	local searchBox = create("TextBox", {
		Size = UDim2.fromOffset(130, 22),
		Position = UDim2.new(1, -200, 0.5, -11),
		BackgroundColor3 = ELEMENT_COLOR,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		PlaceholderText = "Search",
		PlaceholderColor3 = DIM_TEXT_COLOR,
		Text = "",
		TextColor3 = TEXT_COLOR,
		TextSize = 12,
		Font = TEXT_FONT,
		ClearTextOnFocus = false,
	}, titleBar)

	create("UICorner", { CornerRadius = UDim.new(0, 5) }, searchBox)
	local searchStroke = addStroke(searchBox, ACCENT_A, 1)

	searchBox.Focused:Connect(function()
		tween(searchStroke, FAST_TWEEN, { Transparency = 0 })
	end)

	searchBox.FocusLost:Connect(function()
		tween(searchStroke, FAST_TWEEN, { Transparency = 1 })
	end)

	local minimizeButton = createTitleButton(titleBar, "-", -60, ACCENT_B)
	local closeButton = createTitleButton(titleBar, "X", -32, Color3.fromRGB(230, 60, 70))

	makeDraggable(titleBar, window)

	local minimized = false
	local windowWidth = WINDOW_WIDTH
	local windowHeight = WINDOW_HEIGHT

	minimizeButton.Activated:Connect(function()
		minimized = not minimized
		EggHub.resizeHandle.Visible = not minimized
		tween(window, MEDIUM_TWEEN, { Size = UDim2.fromOffset(windowWidth, minimized and TITLE_HEIGHT or windowHeight) })
	end)

	closeButton.Activated:Connect(function()
		tween(windowScale, FAST_TWEEN, { Scale = 0 }).Completed:Connect(function()
			screenGui:Destroy()
		end)
	end)

	local tabBar = create("Frame", { Size = UDim2.new(1, 0, 0, TAB_HEIGHT), Position = UDim2.fromOffset(0, TITLE_HEIGHT), BackgroundTransparency = 1 }, window)

	local indicator = create("Frame", {
		Size = UDim2.new(1 / #TAB_NAMES, -12, 1, -6),
		Position = UDim2.new(0, 6, 0, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
	}, tabBar)

	create("UICorner", { CornerRadius = UDim.new(0, 6) }, indicator)
	addStroke(indicator, Color3.new(1, 1, 1), 0.8)

	local underline = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(0.5, 0, 0, 2),
		Position = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, indicator)

	create("UICorner", { CornerRadius = UDim.new(1, 0) }, underline)
	addGradient(underline, 0)
	EggHub.indicator = indicator

	local contentTop = TITLE_HEIGHT + TAB_HEIGHT + 8
	local content = create("Frame", { Size = UDim2.new(1, -20, 1, -(contentTop + 10)), Position = UDim2.fromOffset(10, contentTop), BackgroundTransparency = 1 }, window)

	local resizeHandle = create("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 10,
	}, window)

	EggHub.resizeHandle = resizeHandle

	for gripIndex = 1, 3 do
		create("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.fromOffset(gripIndex * 4, 1),
			Position = UDim2.new(1, -3, 1, -3 - (3 - gripIndex) * 4 - 2),
			BackgroundColor3 = DIM_TEXT_COLOR,
			BorderSizePixel = 0,
		}, resizeHandle)
	end

	local resizing = false
	local resizeStart, startWidth, startHeight

	resizeHandle.MouseEnter:Connect(function()
		for _, grip in resizeHandle:GetChildren() do
			tween(grip, FAST_TWEEN, { BackgroundColor3 = ACCENT_A })
		end
	end)

	resizeHandle.MouseLeave:Connect(function()
		if resizing then
			return
		end

		for _, grip in resizeHandle:GetChildren() do
			tween(grip, FAST_TWEEN, { BackgroundColor3 = DIM_TEXT_COLOR })
		end
	end)

	resizeHandle.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end

		resizing = true
		resizeStart = input.Position
		startWidth, startHeight = windowWidth, windowHeight
	end)

	connectInput(userInputService.InputChanged, function(input)
		if not resizing or not isMove(input) then
			return
		end

		local delta = input.Position - resizeStart
		windowWidth = math.clamp(startWidth + delta.X, MIN_WIDTH, MAX_WIDTH)
		windowHeight = math.clamp(startHeight + delta.Y, MIN_HEIGHT, MAX_HEIGHT)
		window.Size = UDim2.fromOffset(windowWidth, windowHeight)
	end)

	connectInput(userInputService.InputEnded, function(input)
		if not resizing or not isPress(input) then
			return
		end

		resizing = false
		for _, grip in resizeHandle:GetChildren() do
			tween(grip, FAST_TWEEN, { BackgroundColor3 = DIM_TEXT_COLOR })
		end
	end)

	for index, name in TAB_NAMES do
		local button = create("TextButton", {
			Size = UDim2.fromScale(1 / #TAB_NAMES, 1),
			Position = UDim2.fromScale((index - 1) / #TAB_NAMES, 0),
			BackgroundTransparency = 1,
			Text = name,
			TextColor3 = DIM_TEXT_COLOR,
			TextSize = 13,
			Font = BOLD_FONT,
			AutoButtonColor = false,
		}, tabBar)

		local page = create("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)

		button.MouseEnter:Connect(function()
			if EggHub.selected ~= name then
				tween(button, FAST_TWEEN, { TextColor3 = OFF_TEXT_COLOR })
			end
		end)

		button.MouseLeave:Connect(function()
			if EggHub.selected ~= name then
				tween(button, FAST_TWEEN, { TextColor3 = DIM_TEXT_COLOR })
			end
		end)

		button.Activated:Connect(function()
			switchTab(name)
		end)

		EggHub.pages[name] = page
		EggHub.tabButtons[name] = button
		EggHub.tabIndex[name] = index
	end

	-- Main tab.
	local mainLeft = createColumn(EggHub.pages.Main, UDim2.fromOffset(0, 0))
	local mainRight = createColumn(EggHub.pages.Main, UDim2.new(0.5, 6, 0, 0))

	addSection(mainLeft, "Auto Steal Egg")
	addToggle(mainLeft, "Enable Auto Steal Egg", nil, false)
	addCycle(mainLeft, "Egg Priority", { "Closest", "Highest Rarity", "Closest + Rarity" })
	addSlider(mainLeft, "Pickup Range", 5, 150, 30, 0)
	addToggle(mainLeft, "Auto Return To Pen", nil, true)
	addCycle(mainLeft, "Return Pathing", { "Walk", "Teleport" })
	addSlider(mainLeft, "Return Delay", 0, 5, 0, 1)

	addSection(mainLeft, "Anti Guardian")
	addToggle(mainLeft, "Enable Anti Guardian", nil, false)
	addToggle(mainLeft, "Anti Ragdoll", nil, false)
	addToggle(mainLeft, "Ignore Speed Threshold", nil, false)

	addSection(mainLeft, "Anti Bear Trap")
	addToggle(mainLeft, "Enable Anti Bear Trap", nil, false)
	addSlider(mainLeft, "Trap Detection Range", 5, 50, 15, 0)

	addSection(mainRight, "Baseball Bat")
	addToggle(mainRight, "Auto Swing Bat", nil, false)
	addSlider(mainRight, "Swing Range", 3, 20, 8, 0)
	addToggle(mainRight, "Target Nearest Player", nil, true)
	addButton(mainRight, "Swing Bat")

	addSection(mainRight, "Target Rarity")
	addList(mainRight, "Target Rarity List", { "Common", "Uncommon", "Rare", "Legendary", "Mythic", "Secret" }, 90)

	addSection(mainRight, "Egg Spawn Timer")
	addCounter(mainRight, "Next Spawn In", 0)
	addToggle(mainRight, "Notify On Reset", nil, true)

	-- Extra tab.
	local extraLeft = createColumn(EggHub.pages.Extra, UDim2.fromOffset(0, 0))
	local extraRight = createColumn(EggHub.pages.Extra, UDim2.new(0.5, 6, 0, 0))

	addSection(extraLeft, "Speed")
	addToggle(extraLeft, "Enable Speed", nil, false)
	addCycle(extraLeft, "Speed Mode", { "WalkSpeed", "Velocity", "CFrame" })
	addSlider(extraLeft, "Speed Value", 16, 300, 32, 0)
	addToggle(extraLeft, "Speed Auto Match Biome", nil, false)

	addSection(extraLeft, "Fly")
	addToggle(extraLeft, "Enable Fly", nil, false)
	addCycle(extraLeft, "Fly Method", { "Humanoid", "Velocity", "CFrame" })
	addSlider(extraLeft, "Fly Speed", 16, 200, 50, 0)
	addKeybind(extraLeft, "Fly Up Key", "Space")
	addKeybind(extraLeft, "Fly Down Key", "LeftControl")

	addSection(extraLeft, "Auto Train Speed")
	addToggle(extraLeft, "Enable Auto Train", nil, false)
	addCycle(extraLeft, "Train Mode", { "Treadmill", "Instant" })
	addSlider(extraLeft, "Target Speed", 100, 700000000, 10000, 0)

	addSection(extraLeft, "Auto Hatch")
	addToggle(extraLeft, "Enable Auto Hatch", nil, true)
	addCycle(extraLeft, "Hatch Mode", { "Instant", "Normal" })

	addSection(extraRight, "Auto Collect Pet Income")
	addToggle(extraRight, "Enable Auto Collect", nil, true)
	addCounter(extraRight, "Income Collected", 0)

	addSection(extraRight, "Auto Sell Pets")
	addToggle(extraRight, "Enable Auto Sell", nil, false)
	addCycle(extraRight, "Sell Mode", { "By Rarity", "By Size", "All" })
	addCycle(extraRight, "Min Rarity To Keep", { "Common", "Uncommon", "Rare", "Legendary", "Mythic", "Secret" })

	addSection(extraRight, "Biome Teleport")
	addList(extraRight, "Biome", {
		"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
		"Abyss Ocean", "Prehistoric", "Stormlands", "Cosmic",
		"Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest", "Alien"
	}, 110)
	addButton(extraRight, "Teleport To Biome")

	addSection(extraRight, "Auto Claim Rare Spawns")
	addToggle(extraRight, "Enable Auto Claim Rare", nil, false)
	addSlider(extraRight, "Claim Search Range", 50, 2000, 300, 0)

	-- Visuals tab.
	local visualsLeft = createColumn(EggHub.pages.Visuals, UDim2.fromOffset(0, 0))
	local visualsRight = createColumn(EggHub.pages.Visuals, UDim2.new(0.5, 6, 0, 0))

	addSection(visualsLeft, "Egg ESP")
	addToggle(visualsLeft, "Enable Egg ESP", nil, true)
	addToggle(visualsLeft, "Colour By Rarity", nil, true)
	addSlider(visualsLeft, "Egg ESP Max Distance", 50, 5000, 1000, 0)
	addColor(visualsLeft, "Egg ESP Colour", Color3.fromRGB(255, 210, 70))

	addSection(visualsLeft, "Pet ESP")
	addToggle(visualsLeft, "Enable Pet ESP", nil, false)
	addToggle(visualsLeft, "Show Mutation", nil, true)
	addToggle(visualsLeft, "Show Size", nil, true)
	addSlider(visualsLeft, "Pet ESP Max Distance", 50, 5000, 1000, 0)

	addSection(visualsLeft, "Player ESP")
	addToggle(visualsLeft, "Enable Player ESP", nil, false)
	addCycle(visualsLeft, "Player ESP Style", { "Corner", "Full", "Off" })
	addToggle(visualsLeft, "Player ESP Distance", nil, true)

	addSection(visualsRight, "Rare Egg Notification")
	addToggle(visualsRight, "Enable Rare Egg Notification", nil, true)
	addToggle(visualsRight, "Notify Sound", nil, true)

	addSection(visualsRight, "Guardian ESP")
	addToggle(visualsRight, "Enable Guardian ESP", nil, false)
	addToggle(visualsRight, "Show Threshold Speed", nil, true)

	addSection(visualsRight, "Biome Boundary")
	addToggle(visualsRight, "Enable Biome Boundary", nil, false)
	addColor(visualsRight, "Boundary Colour", Color3.fromRGB(70, 160, 255))

	-- Config tab.
	local configLeft = createColumn(EggHub.pages.Config, UDim2.fromOffset(0, 0))
	local configRight = createColumn(EggHub.pages.Config, UDim2.new(0.5, 6, 0, 0))

	local statusLabel = create("TextLabel", {
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.new(0, 4, 1, -20),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = DIM_TEXT_COLOR,
		TextSize = 12,
		Font = TEXT_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, EggHub.pages.Config)

	local function setStatus(message)
		statusLabel.Text = message
		statusLabel.TextTransparency = 0

		task.delay(3, function()
			if statusLabel.Text == message then
				tween(statusLabel, MEDIUM_TWEEN, { TextTransparency = 1 })
			end
		end)
	end

	local function resolveConfigPath()
		local rawName = tostring(EggHub.values["Config Name"] or "")
		local sanitized = string.gsub(rawName, "[^%w%-%_%. ]", "")
		sanitized = string.match(sanitized, "^%s*(.-)%s*$") or ""
		if sanitized == "" or sanitized == "my config" then
			return CONFIG_FILE
		end
		return CONFIG_FOLDER .. "/" .. sanitized .. ".json"
	end

	local function encodeSettingsPayload()
		local encoded = {}
		for k, v in EggHub.values do
			if typeof(v) == "Color3" then
				encoded[k] = { __color3 = { v.R, v.G, v.B } }
			elseif typeof(v) == "EnumItem" then
				encoded[k] = v.Name
			else
				encoded[k] = v
			end
		end
		return httpService:JSONEncode(encoded)
	end

	local function saveSettings()
		if not writefile then
			return setStatus("Saving is not supported here.")
		end

		local path = resolveConfigPath()
		local ok, result = pcall(function()
			if makefolder and isfolder and not isfolder(CONFIG_FOLDER) then
				makefolder(CONFIG_FOLDER)
			end

			writefile(path, encodeSettingsPayload())
		end)

		setStatus(ok and ("Settings saved (" .. path .. ").") or ("Save failed: " .. tostring(result)))
	end

	local function loadSettings()
		local path = resolveConfigPath()
		if not (readfile and isfile) then
			return setStatus("Loading is not supported here.")
		end
		if not isfile(path) and isfile(CONFIG_FILE) then
			path = CONFIG_FILE
		end
		if not isfile(path) then
			return setStatus("No saved settings found.")
		end

		local ok, data = pcall(function()
			return httpService:JSONDecode(readfile(path))
		end)

		if not ok or typeof(data) ~= "table" then
			return setStatus("Settings file is corrupted.")
		end

		for name, value in data do
			local setter = EggHub.setters[name]
			if setter then
				pcall(setter, value)
			end
		end

		setStatus("Settings loaded.")
	end

	local function resetSettings()
		for name, value in EggHub.defaults do
			EggHub.setters[name](value)
		end

		setStatus("Settings reset.")
	end

	addSection(configLeft, "Menu")
	addCycle(configLeft, "Menu Keybind", { "RightShift", "Insert", "RightControl", "Delete", "End" })
	addButton(configLeft, "Start Calibration")
	addToggle(configLeft, "Don't Show Again", nil, false)

	addSection(configLeft, "Configs")
	addText(configLeft, "Config Name", "my config")
	addButton(configLeft, "Create", saveSettings)
	addButton(configLeft, "Load", loadSettings)
	addButton(configLeft, "Save", saveSettings)
	addButton(configLeft, "Reset", resetSettings)
	addToggle(configLeft, "Autoload", nil, false)

	addSection(configLeft, "Utility")
	addToggle(configLeft, "Anti AFK", nil, true)
	addButton(configLeft, "Rejoin Server")

	addSection(configRight, "Unload")

	local featureCleanup = {}
	local unloaded = false

	local function detach()
		if unloaded then
			return
		end
		unloaded = true
		for i = #featureCleanup, 1, -1 do
			pcall(featureCleanup[i])
		end
		table.clear(featureCleanup)
	end

	EggHub.onUnload = detach

	addButton(configRight, "Unload", function()
		detach()
		tween(windowScale, FAST_TWEEN, { Scale = 0 }).Completed:Connect(function()
			screenGui:Destroy()
		end)
	end)

	-- Steal an Egg feature implementation.
	local function installFeatures()
		local runService = game:GetService("RunService")
		local replicatedStorage = game:GetService("ReplicatedStorage")
		local collectionService = game:GetService("CollectionService")
		local teleportService = game:GetService("TeleportService")
		local soundService = game:GetService("SoundService")
		local virtualUser = pcall(function() return game:GetService("VirtualUser") end) and game:GetService("VirtualUser") or nil

		local function addCleanup(fn)
			table.insert(featureCleanup, fn)
		end

		local function connectFeature(signal, fn)
			if not signal then
				warn("[Egg Hub] connect skipped: nil signal")
				return nil
			end
			local ok, conn = pcall(function()
				return signal:Connect(fn)
			end)
			if not ok or not conn then
				warn("[Egg Hub] connect failed: " .. tostring(conn))
				return nil
			end
			table.insert(EggHub.connections, conn)
			addCleanup(function()
				pcall(function()
					if conn.Connected then
						conn:Disconnect()
					end
				end)
			end)
			return conn
		end

		local function safeRequire(inst)
			if not inst then
				return nil
			end
			local ok, mod = pcall(require, inst)
			return ok and mod or nil
		end

		-- Lazy-resolved game modules & remotes from place 107778070777162.
		local sharedFolder = replicatedStorage:FindFirstChild("Shared")
		local clientFolder = replicatedStorage:FindFirstChild("Client")
		local dataFolder = replicatedStorage:FindFirstChild("Data")
		local utilFolder = sharedFolder and sharedFolder:FindFirstChild("Util")

		local Remotes = safeRequire(sharedFolder and sharedFolder:FindFirstChild("Remotes"))
		local EggState = safeRequire(clientFolder and clientFolder:FindFirstChild("EggState"))
		local PlotState = safeRequire(clientFolder and clientFolder:FindFirstChild("PlotState"))
		local SpeedPowerProjection = safeRequire(clientFolder and clientFolder:FindFirstChild("SpeedPowerProjection"))
		local SaveMod = safeRequire(sharedFolder and sharedFolder:FindFirstChild("Save"))
		local AssetsData = safeRequire(dataFolder and dataFolder:FindFirstChild("Assets"))
		local RarityData = safeRequire(dataFolder and dataFolder:FindFirstChild("Rarity"))
		local GuardsData = safeRequire(dataFolder and dataFolder:FindFirstChild("Guards"))
		local AreaEggCycle = safeRequire(utilFolder and utilFolder:FindFirstChild("AreaEggCycle"))
		local TreadmillUtil = safeRequire(utilFolder and utilFolder:FindFirstChild("TreadmillUtil"))
		local AreaEggSlotIdentity = safeRequire(utilFolder and utilFolder:FindFirstChild("AreaEggSlotIdentity"))

		local function getNetworkingRemote(name)
			local pkgs = replicatedStorage:FindFirstChild("Packages")
			local net = pkgs and pkgs:FindFirstChild("Networking")
			return net and net:FindFirstChild(name) or nil
		end

		local RARITY_FALLBACK_RANK = {
			Common = 1,
			Uncommon = 2,
			Rare = 3,
			Epic = 4,
			Legendary = 5,
			BrainrotGod = 6,
			Mythic = 6,
			Rainbow = 6,
			Cosmic = 7,
			Secret = 8,
			Eternal = 9,
			Limited = 9,
			Divine = 10,
			Titan = 11,
			LightDark = 12,
			SuperRare = 6,
			Transcendent = 12,
		}

		local RARITY_FALLBACK_COLOR = {
			Common = Color3.fromRGB(151, 151, 151),
			Uncommon = Color3.fromRGB(85, 220, 110),
			Rare = Color3.fromRGB(70, 160, 255),
			Epic = Color3.fromRGB(196, 2, 255),
			Legendary = Color3.fromRGB(254, 132, 36),
			Mythic = Color3.fromRGB(254, 44, 102),
			Secret = Color3.fromRGB(255, 65, 65),
			Cosmic = Color3.fromRGB(115, 70, 255),
			Divine = Color3.fromRGB(251, 255, 0),
			Titan = Color3.fromRGB(255, 64, 64),
			Eternal = Color3.fromRGB(255, 30, 240),
			Limited = Color3.fromRGB(174, 80, 254),
			LightDark = Color3.fromRGB(196, 148, 255),
		}

		local GUARD_SPEED_TABLE = {
			["Forest"] = 16,
			["Lake"] = 35,
			["Desert"] = 62,
			["Jungle"] = 82,
			["Snow"] = 98,
			["Volcano"] = 113,
			["Abyss Ocean"] = 130,
			["Prehistoric"] = 152,
			["Stormlands"] = 180.2,
			["Cosmic"] = 200,
			["Cherry Blossom"] = 222,
			["Titan Temple"] = 229.5,
			["Light Dark"] = 244.8,
			["Enchanted Forest"] = 251.075,
			["Alien"] = 279,
		}

		local function getCharacterParts()
			local char = localPlayer.Character
			if not char then
				return nil, nil, nil
			end
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")
			if not (hum and root and root:IsA("BasePart") and hum.Health > 0) then
				return nil, nil, nil
			end
			return char, hum, root
		end

		local function getRarityInfo(rarityNameOrCategory)
			if type(rarityNameOrCategory) == "string" and AssetsData and AssetsData.Directory then
				local entry = AssetsData.Directory[rarityNameOrCategory]
				if entry and entry.Rarity then
					return entry.Rarity._id or entry.Rarity.DisplayName or "Common", entry.Rarity.Rank or 1, entry.Rarity.Color or RARITY_FALLBACK_COLOR.Common
				end
			end
			if type(rarityNameOrCategory) == "string" and RarityData and RarityData.Rarities then
				local r = RarityData.Rarities[rarityNameOrCategory]
				if r then
					return r._id or r.DisplayName or rarityNameOrCategory, r.Rank or 1, r.Color or RARITY_FALLBACK_COLOR.Common
				end
			end
			local key = tostring(rarityNameOrCategory or "Common")
			return key, RARITY_FALLBACK_RANK[key] or 1, RARITY_FALLBACK_COLOR[key] or Color3.fromRGB(255, 210, 70)
		end

		local function getTargetRarityRank()
			local selected = EggHub.values["Target Rarity List"] or "Common"
			local _, rank = getRarityInfo(selected)
			return rank
		end

		-- Anticheat & physics pushback mitigation (ObbyAntiTPClientController + AntiCollisionHighSeedPushBack).
		local savedAntiTpAttr = workspace:GetAttribute("ClientObbyAntiTp")
		local antiTpDisabledByHub = false
		local disabledPushbackScripts = {}

		local function setPushbackDisabled(disabled)
			local char = localPlayer.Character
			if not char then
				return
			end
			local pushback = char:FindFirstChild("AntiCollisionHighSeedPushBack")
			if pushback and pushback:IsA("LocalScript") then
				pcall(function()
					if disabled then
						if not pushback.Disabled then
							disabledPushbackScripts[pushback] = true
							pushback.Disabled = true
						end
					elseif disabledPushbackScripts[pushback] then
						pushback.Disabled = false
						disabledPushbackScripts[pushback] = nil
					end
				end)
			end
		end

		local function updateAnticheatMitigation()
			local needsBypass = EggHub.values["Enable Speed"]
				or EggHub.values["Enable Fly"]
				or (EggHub.values["Enable Auto Steal Egg"] and EggHub.values["Return Pathing"] == "Teleport")
				or EggHub.values["Enable Auto Claim Rare"]

			if needsBypass then
				if not antiTpDisabledByHub then
					savedAntiTpAttr = workspace:GetAttribute("ClientObbyAntiTp")
					antiTpDisabledByHub = true
				end
				if workspace:GetAttribute("ClientObbyAntiTp") ~= false then
					workspace:SetAttribute("ClientObbyAntiTp", false)
				end
			elseif antiTpDisabledByHub then
				antiTpDisabledByHub = false
				workspace:SetAttribute("ClientObbyAntiTp", savedAntiTpAttr)
			end

			setPushbackDisabled(EggHub.values["Enable Speed"] or EggHub.values["Enable Fly"])
		end

		addCleanup(function()
			if antiTpDisabledByHub then
				antiTpDisabledByHub = false
				pcall(function()
					workspace:SetAttribute("ClientObbyAntiTp", savedAntiTpAttr)
				end)
			end
			for scriptObj in disabledPushbackScripts do
				pcall(function()
					if scriptObj and scriptObj.Parent then
						scriptObj.Disabled = false
					end
				end)
			end
			table.clear(disabledPushbackScripts)
		end)

		local function getGuardAreasFolder()
			local world = workspace:FindFirstChild("World")
			local areas = world and world:FindFirstChild("Areas")
			return areas and areas:FindFirstChild("GuardAreas") or nil
		end

		local function getSeparationLine()
			local world = workspace:FindFirstChild("World")
			local areas = world and world:FindFirstChild("Areas")
			return areas and areas:FindFirstChild("SeparationLine") or nil
		end

		local function getBiomeSpeed(areaName)
			local guardAreas = getGuardAreasFolder()
			if guardAreas then
				local areaModel = guardAreas:FindFirstChild(areaName)
				local guard = areaModel and areaModel:FindFirstChild("Guard")
				local gHum = guard and guard:FindFirstChildOfClass("Humanoid")
				if gHum and gHum.WalkSpeed > 0 then
					return gHum.WalkSpeed
				end
			end
			if GuardsData and GuardsData.Directory then
				local cfg = GuardsData.Directory[areaName]
				if cfg and cfg.WalkSpeed then
					return cfg.WalkSpeed
				end
			end
			return GUARD_SPEED_TABLE[areaName] or 16
		end

		local function getCurrentBiomeName(pos)
			local guardAreas = getGuardAreasFolder()
			if not guardAreas then
				return nil
			end
			local closestName = nil
			local closestDist = math.huge
			for _, areaModel in guardAreas:GetChildren() do
				local bounds = areaModel:FindFirstChild("Bounds")
				if bounds and bounds:IsA("BasePart") then
					local localPos = bounds.CFrame:PointToObjectSpace(pos)
					local half = bounds.Size * 0.5
					if math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z then
						return areaModel.Name
					end
					local dist = (bounds.Position - pos).Magnitude
					if dist < closestDist then
						closestDist = dist
						closestName = areaModel.Name
					end
				end
			end
			return closestDist <= 220 and closestName or nil
		end

		local airFloorPart = nil
		local travelToken = 0
		local currentTravelTask = nil

		local function ensureAirFloor()
			if airFloorPart and airFloorPart.Parent == workspace then
				return airFloorPart
			end
			if airFloorPart then
				pcall(function() airFloorPart:Destroy() end)
			end
			local p = Instance.new("Part")
			p.Name = "EggHubAirFloor"
			p.Size = Vector3.new(14, 1, 14)
			p.Anchored = true
			p.CanCollide = true
			p.CanTouch = false
			p.CanQuery = false
			p.Transparency = 1
			p.CastShadow = false
			p.Material = Enum.Material.Plastic
			p.Archivable = false
			p.Parent = workspace
			airFloorPart = p
			return p
		end

		local function destroyAirFloor()
			if airFloorPart then
				pcall(function() airFloorPart:Destroy() end)
				airFloorPart = nil
			end
		end

		local function positionAirFloorUnder(root, hum, targetFeetY)
			local floor = ensureAirFloor()
			local hip = hum and hum.HipHeight or 2
			local halfY = root.Size.Y * 0.5
			local floorCenterY = (targetFeetY or root.Position.Y) - (halfY + hip + 0.5)
			floor.CFrame = CFrame.new(root.Position.X, floorCenterY, root.Position.Z)
		end

		local function setBarriersNoclip(enabled)
			local world = workspace:FindFirstChild("World")
			local areas = world and world:FindFirstChild("Areas")
			if areas then
				local wall = areas:FindFirstChild("WallStartCollision")
				if wall and wall:IsA("BasePart") then
					wall.CanCollide = not enabled
				end
			end
			local plots = workspace:FindFirstChild("Plots")
			if plots then
				for _, plotModel in plots:GetChildren() do
					for _, desc in plotModel:GetDescendants() do
						if desc:IsA("BasePart") and (desc.Name == "Gate" or desc.Name == "Fence" or desc.Name == "Barrier") then
							desc.CanCollide = not enabled
						end
					end
				end
			end
		end

		local function getLocalPenTargetCFrame()
			if PlotState and type(PlotState.ResolvePlot) == "function" then
				local ok, plot = pcall(PlotState.ResolvePlot)
				if ok and plot then
					if plot.RespawnPointCFrame then
						return plot.RespawnPointCFrame + Vector3.new(0, 3, 0)
					end
					if plot.CenterPoint and plot.CenterPoint:IsA("BasePart") then
						return plot.CenterPoint.CFrame + Vector3.new(0, 4, 0)
					end
					if plot.PetArea and plot.PetArea:IsA("BasePart") then
						return plot.PetArea.CFrame + Vector3.new(0, 4, 0)
					end
				end
			end
			local plots = workspace:FindFirstChild("Plots")
			if plots then
				for _, plotModel in plots:GetChildren() do
					local sign = plotModel:FindFirstChild("PlotSign")
					local yourBase = sign and sign:FindFirstChild("YourBase", true)
					if yourBase and yourBase:IsA("BillboardGui") and yourBase.Enabled then
						local spawnPt = plotModel:FindFirstChild("SpawnPoint") or plotModel:FindFirstChild("CenterPoint")
						if spawnPt and spawnPt:IsA("BasePart") then
							return spawnPt.CFrame + Vector3.new(0, 4, 0)
						end
					end
				end
			end
			local world = workspace:FindFirstChild("World")
			local areas = world and world:FindFirstChild("Areas")
			local startArea = areas and areas:FindFirstChild("StartArea")
			if startArea and startArea:IsA("BasePart") then
				return startArea.CFrame + Vector3.new(0, 5, 0)
			end
			return nil
		end

		local function getSafeDeliveryCFrame()
			local penCf = getLocalPenTargetCFrame()
			if penCf then
				return penCf
			end
			local sep = getSeparationLine()
			if sep and sep:IsA("BasePart") then
				return CFrame.new(sep.Position - sep.CFrame.LookVector * 12 + Vector3.new(0, 4, 0))
			end
			return nil
		end

		local function isCarryingEgg()
			if EggState and type(EggState.ReadCarryState) == "function" then
				local ok, state = pcall(EggState.ReadCarryState)
				if ok and state then
					return state.IsCarrying == true
				end
			end
			local char = localPlayer.Character
			return char ~= nil and char:GetAttribute("CarryingEgg") == true
		end

		-- Anticheat-safe step-glide teleport: stays grounded via EggHubAirFloor,
		-- keeps PlatformStand = false, and adapts speed automatically if rubberbanded.
		local function safeTeleportTo(targetCFrame, opts)
			local _, hum, root = getCharacterParts()
			if not (hum and root and targetCFrame) then
				return false
			end
			local targetPos = targetCFrame.Position
			local dist = (targetPos - root.Position).Magnitude
			if dist <= 10 then
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = targetCFrame
				return true
			end

			travelToken += 1
			local myToken = travelToken
			local prevAttr = workspace:GetAttribute("ClientObbyAntiTp")
			workspace:SetAttribute("ClientObbyAntiTp", false)
			setBarriersNoclip(true)

			local carrying = isCarryingEgg()
			local baseWs = math.max(hum.WalkSpeed, 16)
			local maxSpeed = carrying
				and math.clamp(math.max(baseWs * 1.85, 36), 36, 175)
				or math.clamp(math.max(baseWs * 1.9, 115), 115, 250)
			if opts and type(opts.maxSpeed) == "number" then
				maxSpeed = math.min(maxSpeed, opts.maxSpeed)
			end
			local cruiseSpeed = maxSpeed

			local function runGlide()
				local lastExpected = root.Position
				local cruiseY = math.max(root.Position.Y, targetPos.Y, 74)
				local startedAt = os.clock()
				while not unloaded and travelToken == myToken do
					local _, curHum, curRoot = getCharacterParts()
					if not (curHum and curRoot) or curHum.Health <= 0 then
						break
					end
					if os.clock() - startedAt > 45 then
						break
					end
					local dt = runService.Heartbeat:Wait()
					dt = math.clamp(dt or 0.016, 0.005, 0.05)

					-- Detect server rubberband and adapt speed down smoothly.
					if (curRoot.Position - lastExpected).Magnitude > 35 then
						cruiseSpeed = math.max(32, cruiseSpeed * 0.68)
						lastExpected = curRoot.Position
					end

					local curPos = curRoot.Position
					local flatGoal = Vector3.new(targetPos.X, curPos.Y, targetPos.Z)
					local flatDelta = flatGoal - curPos
					local flatDist = flatDelta.Magnitude

					local stepY = targetPos.Y
					if flatDist > 22 then
						stepY = cruiseY
					end

					local nextPos
					if flatDist <= math.max(cruiseSpeed * dt, 3) then
						nextPos = targetPos
					else
						local dir = flatDelta.Unit
						local nextXZ = curPos + dir * (cruiseSpeed * dt)
						local nextY = curPos.Y + math.clamp(stepY - curPos.Y, -60 * dt, 60 * dt)
						nextPos = Vector3.new(nextXZ.X, nextY, nextXZ.Z)
					end

					curHum.Sit = false
					curHum.PlatformStand = false
					curRoot.AssemblyLinearVelocity = Vector3.zero
					curRoot.AssemblyAngularVelocity = Vector3.zero
					curRoot.CFrame = CFrame.new(nextPos) * targetCFrame.Rotation
					positionAirFloorUnder(curRoot, curHum, nextPos.Y)
					lastExpected = nextPos

					if (nextPos - targetPos).Magnitude <= 4 then
						curRoot.CFrame = targetCFrame
						break
					end
				end

				if travelToken == myToken then
					setBarriersNoclip(false)
					if not EggHub.values["Enable Fly"] then
						destroyAirFloor()
					end
					if not unloaded and not antiTpDisabledByHub then
						pcall(function()
							workspace:SetAttribute("ClientObbyAntiTp", prevAttr)
						end)
					end
				end
			end

			if opts and opts.blocking then
				runGlide()
			else
				currentTravelTask = task.spawn(runGlide)
			end
			return true
		end

		-- Resolve Speed Value safely on the natural 16..300 WalkSpeed scale.
		local function resolveEffectiveWalkSpeed()
			local _, _, root = getCharacterParts()
			if EggHub.values["Speed Auto Match Biome"] and root then
				local biome = getCurrentBiomeName(root.Position)
				if biome then
					return math.clamp(getBiomeSpeed(biome) + 4, 16, 300)
				end
			end
			local raw = tonumber(EggHub.values["Speed Value"]) or 32
			if raw <= 300 then
				return math.clamp(raw, 16, 300)
			end
			if TreadmillUtil and type(TreadmillUtil.SpeedPowerToWalkSpeed) == "function" then
				local ok, ws = pcall(TreadmillUtil.SpeedPowerToWalkSpeed, raw)
				if ok and type(ws) == "number" then
					return math.clamp(ws, 16, 300)
				end
			end
			return math.clamp(16 + math.log10(raw / 16) * 40, 16, 300)
		end

		-- =================================================================
		-- 1) SPEED & FLY (Stealth AirFloor Fly + Natural WalkSpeed Bypass)
		-- =================================================================
		local savedWalkSpeed = nil
		local flyTargetY = nil
		local wasFlying = false

		local function keyNameToEnum(keyName)
			if type(keyName) ~= "string" or keyName == "" then
				return nil
			end
			return Enum.KeyCode[keyName]
		end

		local function getFlyMoveVector(hum)
			local cam = workspace.CurrentCamera
			local horiz = Vector3.zero
			if cam then
				local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
				local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
				look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
				right = right.Magnitude > 0.01 and right.Unit or Vector3.new(1, 0, 0)
				if userInputService:IsKeyDown(Enum.KeyCode.W) then horiz += look end
				if userInputService:IsKeyDown(Enum.KeyCode.S) then horiz -= look end
				if userInputService:IsKeyDown(Enum.KeyCode.D) then horiz += right end
				if userInputService:IsKeyDown(Enum.KeyCode.A) then horiz -= right end
			end
			if horiz.Magnitude < 0.01 and hum and hum.MoveDirection.Magnitude > 0.05 then
				horiz = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
			end
			horiz = horiz.Magnitude > 0.01 and horiz.Unit or Vector3.zero

			local vert = 0
			local upKey = keyNameToEnum(EggHub.values["Fly Up Key Value"] or "Space")
			local downKey = keyNameToEnum(EggHub.values["Fly Down Key Value"] or "LeftControl")
			if upKey and userInputService:IsKeyDown(upKey) then
				vert += 1
			end
			if downKey and userInputService:IsKeyDown(downKey) then
				vert -= 1
			end
			return horiz, vert
		end

		local function stopFlyState(hum, root)
			flyTargetY = nil
			destroyAirFloor()
			if hum then
				hum.PlatformStand = false
				if savedWalkSpeed and not EggHub.values["Enable Speed"] then
					pcall(function() hum.WalkSpeed = savedWalkSpeed end)
				end
			end
			if root then
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end

		addCleanup(function()
			travelToken += 1
			setBarriersNoclip(false)
			destroyAirFloor()
			local _, hum, root = getCharacterParts()
			if hum then
				hum.PlatformStand = false
				if savedWalkSpeed then
					pcall(function() hum.WalkSpeed = savedWalkSpeed end)
					savedWalkSpeed = nil
				end
			end
			if root then
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end)

		connectFeature(runService.Heartbeat, function(dt)
			if unloaded then
				return
			end
			dt = math.min(dt, 0.05)
			updateAnticheatMitigation()

			local _, hum, root = getCharacterParts()
			if not (hum and root) then
				destroyAirFloor()
				flyTargetY = nil
				wasFlying = false
				return
			end

			local flyEnabled = EggHub.values["Enable Fly"] == true
			local speedEnabled = EggHub.values["Enable Speed"] == true

			if flyEnabled then
				wasFlying = true
				local flyMethod = EggHub.values["Fly Method"] or "Humanoid"
				local flySpeed = math.clamp(tonumber(EggHub.values["Fly Speed"]) or 50, 16, 200)
				local horizDir, vertDir = getFlyMoveVector(hum)

				if savedWalkSpeed == nil then
					savedWalkSpeed = hum.WalkSpeed
				end
				if flyTargetY == nil then
					flyTargetY = root.Position.Y
				end
				if vertDir ~= 0 then
					flyTargetY += vertDir * math.min(flySpeed * 0.75, 85) * dt
				end

				-- Never set PlatformStand = true or Physics state; keep grounded on EggHubAirFloor.
				hum.PlatformStand = false
				positionAirFloorUnder(root, hum, flyTargetY)

				if flyMethod == "Humanoid" then
					if math.abs(hum.WalkSpeed - flySpeed) > 0.1 then
						hum.WalkSpeed = flySpeed
					end
					if vertDir ~= 0 then
						root.CFrame = CFrame.new(root.Position.X, flyTargetY, root.Position.Z) * root.CFrame.Rotation
					end
				elseif flyMethod == "Velocity" then
					local vel = root.AssemblyLinearVelocity
					root.AssemblyLinearVelocity = Vector3.new(horizDir.X * flySpeed, (flyTargetY - root.Position.Y) * 10, horizDir.Z * flySpeed)
					if horizDir.Magnitude < 0.01 and vertDir == 0 then
						root.AssemblyLinearVelocity = Vector3.new(0, math.clamp((flyTargetY - root.Position.Y) * 8, -20, 20), 0)
					else
						local _ = vel
					end
				else -- CFrame
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					local stepXZ = horizDir * math.min(flySpeed * dt, 16)
					local nextPos = Vector3.new(root.Position.X + stepXZ.X, flyTargetY, root.Position.Z + stepXZ.Z)
					root.CFrame = CFrame.new(nextPos) * root.CFrame.Rotation
				end
			elseif wasFlying then
				wasFlying = false
				stopFlyState(hum, root)
			end

			if speedEnabled then
				local targetSpeed = resolveEffectiveWalkSpeed()
				local mode = EggHub.values["Speed Mode"] or "WalkSpeed"
				if savedWalkSpeed == nil then
					savedWalkSpeed = hum.WalkSpeed
				end

				if mode == "WalkSpeed" then
					if math.abs(hum.WalkSpeed - targetSpeed) > 0.1 then
						hum.WalkSpeed = targetSpeed
					end
				elseif not flyEnabled then
					if hum.MoveDirection.Magnitude > 0.05 then
						local moveDir = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z).Unit
						if mode == "Velocity" then
							local curVel = root.AssemblyLinearVelocity
							root.AssemblyLinearVelocity = Vector3.new(moveDir.X * targetSpeed, curVel.Y, moveDir.Z * targetSpeed)
						elseif mode == "CFrame" then
							local step = math.min(math.max(targetSpeed - hum.WalkSpeed, 0) * dt, 12)
							if step > 0.01 then
								root.CFrame = root.CFrame + moveDir * step
							end
						end
					end
				end
			elseif savedWalkSpeed ~= nil and not flyEnabled then
				if math.abs(hum.WalkSpeed - savedWalkSpeed) > 0.1 then
					hum.WalkSpeed = savedWalkSpeed
				end
				savedWalkSpeed = nil
			end
		end)

		-- =================================================================
		-- 2) ANTI GUARDIAN / ANTI RAGDOLL / IGNORE SPEED THRESHOLD
		-- =================================================================
		local function enforceAntiRagdoll(char, hum)
			if not (char and hum) then
				return
			end
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			local state = hum:GetState()
			if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			if not EggHub.values["Enable Fly"] and hum.PlatformStand then
				hum.PlatformStand = false
			end
			hum.AutoRotate = true
			for _, desc in char:GetDescendants() do
				if (desc:IsA("BallSocketConstraint") or desc:IsA("HingeConstraint")) and (desc:GetAttribute("RagdollConstraint") ~= nil or string.find(desc.Name, "Ragdoll", 1, true)) then
					desc.Enabled = false
				elseif desc:IsA("Motor6D") and not desc.Enabled then
					desc.Enabled = true
				end
			end
		end

		local function applyAntiGuardianPass()
			local antiGuardian = EggHub.values["Enable Anti Guardian"] == true
			local ignoreThreshold = EggHub.values["Ignore Speed Threshold"] == true
			if not (antiGuardian or ignoreThreshold) then
				return
			end

			local guardAreas = getGuardAreasFolder()
			if guardAreas then
				for _, areaModel in guardAreas:GetChildren() do
					for _, childName in { "Guard", "ForestGuardStaging" } do
						local guard = areaModel:FindFirstChild(childName)
						if guard then
							if antiGuardian and guard:GetAttribute("TargetPlayer") == localPlayer.Name then
								guard:SetAttribute("TargetPlayer", "")
							end
							for _, part in guard:GetDescendants() do
								if part:IsA("BasePart") then
									if antiGuardian then
										part.CanTouch = false
										part.CanCollide = false
									end
									if ignoreThreshold then
										part.CanQuery = false
									end
								end
							end
						end
					end
				end
			end
		end

		-- =================================================================
		-- 3) ANTI BEAR TRAP
		-- =================================================================
		local function applyAntiBearTrapPass()
			if not EggHub.values["Enable Anti Bear Trap"] then
				return
			end
			local _, hum, root = getCharacterParts()
			if not root then
				return
			end
			local maxRange = tonumber(EggHub.values["Trap Detection Range"]) or 15
			local char = localPlayer.Character
			if char and char:GetAttribute("IsTrapped") == true then
				char:SetAttribute("IsTrapped", false)
				if hum then
					hum.PlatformStand = false
				end
				root.Anchored = false
			end

			for _, trap in collectionService:GetTagged("PlacedTrap") do
				local posPart = trap:IsA("BasePart") and trap or trap:FindFirstChild("Hitbox") or (trap:IsA("Model") and trap.PrimaryPart)
				if posPart and posPart:IsA("BasePart") and (posPart.Position - root.Position).Magnitude <= maxRange then
					posPart.CanTouch = false
					posPart.CanCollide = false
					if trap:IsA("BasePart") then
						trap.CanTouch = false
						trap.CanCollide = false
					end
				end
			end
		end

		-- =================================================================
		-- 4) BASEBALL BAT
		-- =================================================================
		local lastBatSwing = 0

		local function findBatTool()
			local char = localPlayer.Character
			if char then
				local equipped = char:FindFirstChildWhichIsA("Tool")
				if equipped and (equipped:GetAttribute("GearName") or string.find(string.lower(equipped.Name), "bat") or string.find(string.lower(equipped.Name), "axe") or string.find(string.lower(equipped.Name), "sword")) then
					return equipped, true
				end
			end
			local backpack = localPlayer:FindFirstChildOfClass("Backpack")
			if backpack then
				for _, item in backpack:GetChildren() do
					if item:IsA("Tool") and (item:GetAttribute("GearName") or string.find(string.lower(item.Name), "bat") or string.find(string.lower(item.Name), "axe") or string.find(string.lower(item.Name), "sword")) then
						return item, false
					end
				end
			end
			return nil, false
		end

		local function swingBatOnce()
			local _, hum, root = getCharacterParts()
			if not (hum and root) then
				return
			end
			local tool, isEquipped = findBatTool()
			if tool and not isEquipped then
				pcall(function() hum:EquipTool(tool) end)
			end
			local targetPlayer = nil
			if EggHub.values["Target Nearest Player"] ~= false then
				local swingRange = tonumber(EggHub.values["Swing Range"]) or 8
				local bestDist = swingRange
				for _, plr in playersService:GetPlayers() do
					if plr ~= localPlayer and plr.Character then
						local tRoot = plr.Character:FindFirstChild("HumanoidRootPart")
						local tHum = plr.Character:FindFirstChildOfClass("Humanoid")
						if tRoot and tHum and tHum.Health > 0 then
							local dist = (tRoot.Position - root.Position).Magnitude
							if dist <= bestDist then
								bestDist = dist
								targetPlayer = plr
							end
						end
					end
				end
			end
			if Remotes and Remotes.BatSwing and Remotes.BatSwing.Trigger then
				pcall(function()
					Remotes.BatSwing.Trigger:FireServer(targetPlayer, httpService:GenerateGUID(false))
				end)
			else
				local batRemote = getNetworkingRemote("RE/BatSwing/Trigger")
				if batRemote then
					pcall(function()
						batRemote:FireServer(targetPlayer, httpService:GenerateGUID(false))
					end)
				end
			end
			if tool then
				pcall(function() tool:Activate() end)
			end
		end

		EggHub.actions["Swing Bat"] = swingBatOnce

		-- =================================================================
		-- 5) EGG SPAWN TIMER & RARE EGG NOTIFICATION
		-- =================================================================
		local lastSpawnCountdown = nil
		local notifiedRareUids = {}
		local pendingNotifies = {}
		local pendingIncomeDelta = 0

		local function queueNotify(msg, okFlag)
			table.insert(pendingNotifies, { msg = msg, ok = okFlag })
		end

		local function playNotifySound()
			if not EggHub.values["Notify Sound"] then
				return
			end
			pcall(function()
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://4590657391"
				s.Volume = 0.6
				s.Parent = soundService
				s:Play()
				task.delay(2.5, function()
					if s.Parent then s:Destroy() end
				end)
			end)
		end

		local function getNextEggResetSeconds()
			local now = workspace:GetServerTimeNow()
			if AreaEggCycle and type(AreaEggCycle.TimeUntilNextPeriod) == "function" then
				local ok, secs = pcall(AreaEggCycle.TimeUntilNextPeriod, now)
				if ok and type(secs) == "number" then
					return math.max(0, secs)
				end
			end
			local period = tonumber(workspace:GetAttribute("AreaEggCyclePeriodSeconds")) or 120
			local anchorAt = tonumber(workspace:GetAttribute("AreaEggCycleAnchorAt")) or 0
			local elapsed = (now - anchorAt) % period
			return math.max(0, period - elapsed)
		end

		local function checkRareFieldEgg(record)
			if not record or not record.Uid or notifiedRareUids[record.Uid] then
				return
			end
			local rarityName, rank = getRarityInfo(record.AssetCategory)
			if rank >= 6 or rank >= math.max(getTargetRarityRank(), 5) then
				notifiedRareUids[record.Uid] = true
				if EggHub.values["Enable Rare Egg Notification"] then
					local areaLabel = record.AreaId or "Field"
					queueNotify(tostring(record.AssetCategory or rarityName) .. " (" .. rarityName .. ") @ " .. areaLabel, true)
					playNotifySound()
				end
			end
		end

		if EggState and EggState.FieldShifted then
			connectFeature(EggState.FieldShifted, checkRareFieldEgg)
		end

		-- =================================================================
		-- 6) AUTO STEAL EGG & AUTO CLAIM RARE SPAWNS
		-- =================================================================
		local lastStealAttempt = 0
		local returningAt = nil
		local activeReturnGlide = false

		local function getFieldEggList()
			if EggState and type(EggState.ReadFieldEggs) == "function" then
				local ok, snap = pcall(EggState.ReadFieldEggs)
				if ok and snap and snap.Records then
					return snap.Records
				end
			end
			return {}
		end

		local function findFieldEggModel(uid)
			local strUid = tostring(uid)
			local slotFolder = workspace:FindFirstChild("AreaEggSlotsClient")
			if slotFolder then
				local inSlot = slotFolder:FindFirstChild(strUid)
				if inSlot then
					return inSlot
				end
			end
			return workspace:FindFirstChild(strUid)
		end

		local function carryFieldEgg(record)
			if not record then
				return false
			end
			local slotKey = nil
			if AreaEggSlotIdentity and type(AreaEggSlotIdentity.LooksLikeFirstAreaUid) == "function" and AreaEggSlotIdentity.LooksLikeFirstAreaUid(record.Uid) then
				slotKey = AreaEggSlotIdentity.SlotKey(record.AreaId, record.NestId)
			end
			if EggState and type(EggState.CarryFieldEgg) == "function" then
				local ok, success = pcall(EggState.CarryFieldEgg, record.Uid, slotKey)
				if ok and success then
					return true
				end
			end
			local rf = getNetworkingRemote("RF/EggWorld/AskFieldEggCarry")
			if rf then
				local ok, success = pcall(function()
					return rf:InvokeServer({ Uid = record.Uid, FirstAreaSlotKey = slotKey })
				end)
				if ok and success == true then
					return true
				end
			end
			if type(fireproximityprompt) == "function" then
				local eggModel = findFieldEggModel(record.Uid)
				local prompt = eggModel and eggModel:FindFirstChildWhichIsA("ProximityPrompt", true)
				if prompt then
					pcall(fireproximityprompt, prompt)
					return true
				end
			end
			return false
		end

		local function runReturnToPen()
			if activeReturnGlide then
				return
			end
			local deliveryCf = getSafeDeliveryCFrame()
			if not deliveryCf then
				return
			end
			local _, hum, root = getCharacterParts()
			if not (hum and root) then
				return
			end
			if EggHub.values["Return Pathing"] == "Teleport" then
				activeReturnGlide = true
				task.spawn(function()
					pcall(safeTeleportTo, deliveryCf, { blocking = true })
					activeReturnGlide = false
				end)
			else
				hum:MoveTo(deliveryCf.Position)
			end
		end

		local function runAutoStealAndRareClaim()
			local now = os.clock()
			local _, hum, root = getCharacterParts()
			if not (hum and root) then
				return
			end

			if isCarryingEgg() then
				if EggHub.values["Auto Return To Pen"] or EggHub.values["Enable Auto Claim Rare"] then
					if not returningAt then
						local delaySecs = tonumber(EggHub.values["Return Delay"]) or 0
						returningAt = now + delaySecs
					end
					if now >= returningAt and not activeReturnGlide then
						runReturnToPen()
						returningAt = now + 0.5
					end
				end
				return
			end
			returningAt = nil

			if activeReturnGlide or now - lastStealAttempt < 0.45 then
				return
			end

			local records = getFieldEggList()
			if #records == 0 then
				return
			end

			-- Auto Claim Rare Spawns takes priority when enabled.
			if EggHub.values["Enable Auto Claim Rare"] then
				local searchRange = tonumber(EggHub.values["Claim Search Range"]) or 300
				local minRareRank = math.max(getTargetRarityRank(), 6)
				local bestRare, bestRank, bestDist = nil, -1, math.huge
				for _, rec in records do
					if rec.BoundsCFrame then
						local dist = (rec.BoundsCFrame.Position - root.Position).Magnitude
						local _, rank = getRarityInfo(rec.AssetCategory)
						if dist <= searchRange and rank >= minRareRank then
							if rank > bestRank or (rank == bestRank and dist < bestDist) then
								bestRare, bestRank, bestDist = rec, rank, dist
							end
						end
					end
				end
				if bestRare then
					lastStealAttempt = now
					activeReturnGlide = true
					task.spawn(function()
						if bestDist > 10 then
							pcall(safeTeleportTo, CFrame.new(bestRare.BoundsCFrame.Position + Vector3.new(0, 3, 0)), { blocking = true })
						end
						if carryFieldEgg(bestRare) then
							local deliveryCf = getSafeDeliveryCFrame()
							if deliveryCf then
								pcall(safeTeleportTo, deliveryCf, { blocking = true })
							end
						end
						activeReturnGlide = false
					end)
					return
				end
			end

			if not EggHub.values["Enable Auto Steal Egg"] then
				return
			end

			local pickupRange = tonumber(EggHub.values["Pickup Range"]) or 30
			local minRank = getTargetRarityRank()
			local priority = EggHub.values["Egg Priority"] or "Closest"
			local bestRec, bestScore = nil, -math.huge

			for _, rec in records do
				if rec.BoundsCFrame then
					local dist = (rec.BoundsCFrame.Position - root.Position).Magnitude
					local _, rank = getRarityInfo(rec.AssetCategory)
					if dist <= pickupRange and rank >= minRank then
						local score
						if priority == "Highest Rarity" then
							score = rank * 10000 - dist
						elseif priority == "Closest + Rarity" then
							score = rank * 120 - dist
						else
							score = -dist
						end
						if score > bestScore then
							bestScore = score
							bestRec = rec
						end
					end
				end
			end

			if bestRec then
				lastStealAttempt = now
				if carryFieldEgg(bestRec) and EggHub.values["Auto Return To Pen"] then
					local delaySecs = tonumber(EggHub.values["Return Delay"]) or 0
					returningAt = os.clock() + delaySecs
				end
			end
		end

		-- =================================================================
		-- 7) AUTO TRAIN SPEED / AUTO HATCH / AUTO COLLECT / AUTO SELL / BIOME TP
		-- =================================================================
		local lastTrainAt = 0
		local trainingActive = false
		local lastHatchAt = 0
		local hatchedCooldown = {}
		local lastCollectAt = 0
		local incomeTotal = 0
		local lastSellAt = 0

		local function runAutoTrain()
			local doffRemote = (Remotes and Remotes.Treadmill and Remotes.Treadmill.AskDoff) or getNetworkingRemote("RF/Treadmill/AskDoff")
			if not EggHub.values["Enable Auto Train"] then
				if trainingActive and doffRemote then
					trainingActive = false
					task.spawn(function() pcall(function() doffRemote:InvokeServer() end) end)
				end
				return
			end
			local now = os.clock()
			if now - lastTrainAt < 1.35 then
				return
			end
			local targetSpeed = tonumber(EggHub.values["Target Speed"]) or 10000
			local curSpeedPower = 0
			local treadmillLevel = 1
			if SpeedPowerProjection and type(SpeedPowerProjection.ReadProjected) == "function" then
				local ok, val = pcall(SpeedPowerProjection.ReadProjected)
				if ok and type(val) == "number" then
					curSpeedPower = val
				end
			end
			if SaveMod and type(SaveMod.Await) == "function" then
				local ok, save = pcall(SaveMod.Await)
				if ok and save then
					if curSpeedPower == 0 and type(save.SpeedPower) == "number" then
						curSpeedPower = save.SpeedPower
					end
					if type(save.TreadmillUpgradeLevel) == "number" then
						treadmillLevel = save.TreadmillUpgradeLevel
					end
				end
			end
			if treadmillLevel <= 0 then
				return
			end
			if curSpeedPower >= targetSpeed then
				if trainingActive and doffRemote then
					trainingActive = false
					task.spawn(function() pcall(function() doffRemote:InvokeServer() end) end)
				end
				return
			end
			lastTrainAt = now

			local plot = PlotState and type(PlotState.ResolvePlot) == "function" and select(2, pcall(PlotState.ResolvePlot)) or nil
			local treadmillBottom = plot and plot.PlotFolder and plot.PlotFolder:FindFirstChild("TreadmillBottom")
			local trainMode = EggHub.values["Train Mode"] or "Treadmill"
			local wearRemote = (Remotes and Remotes.Treadmill and Remotes.Treadmill.AskWearStill) or getNetworkingRemote("RF/Treadmill/AskWearStill")

			if wearRemote then
				task.spawn(function()
					local _, _, root = getCharacterParts()
					if trainMode == "Treadmill" and treadmillBottom and treadmillBottom:IsA("BasePart") and root then
						if (root.Position - treadmillBottom.Position).Magnitude > 6 then
							pcall(safeTeleportTo, treadmillBottom.CFrame + Vector3.new(0, 3.5, 0), { blocking = true })
						end
					end
					local ok, entered = pcall(function()
						return wearRemote:InvokeServer()
					end)
					if ok and entered == true then
						trainingActive = true
					elseif trainMode == "Instant" and treadmillBottom and treadmillBottom:IsA("BasePart") then
						pcall(safeTeleportTo, treadmillBottom.CFrame + Vector3.new(0, 3.5, 0), { blocking = true })
						local ok2, entered2 = pcall(function() return wearRemote:InvokeServer() end)
						if ok2 and entered2 == true then
							trainingActive = true
						end
					end
				end)
			end
		end

		local function runAutoHatch()
			if not EggHub.values["Enable Auto Hatch"] then
				return
			end
			local now = os.clock()
			if now - lastHatchAt < 0.75 then
				return
			end
			lastHatchAt = now

			if not (EggState and type(EggState.ReadOwnerEggs) == "function") then
				return
			end
			local ok, owned = pcall(EggState.ReadOwnerEggs, localPlayer.UserId)
			if not ok or type(owned) ~= "table" then
				return
			end

			local hatchMode = EggHub.values["Hatch Mode"] or "Instant"
			for uid, record in owned do
				if record and record.Placement ~= nil and (hatchedCooldown[uid] or 0) <= now then
					local readyOk, isReady = pcall(EggState.IsReadyToHatch, uid)
					if readyOk and isReady then
						hatchedCooldown[uid] = now + 2.5
						task.spawn(function()
							if EggState.BeginHatch then
								pcall(EggState.BeginHatch, uid)
							end
							if hatchMode == "Normal" then
								task.wait(0.6)
							end
							if EggState.FinishHatch then
								pcall(EggState.FinishHatch, uid)
							end
						end)
					end
				end
			end
		end

		local function addCollectedIncome(amount)
			local n = tonumber(amount) or 0
			if n <= 0 then
				return
			end
			incomeTotal += math.floor(n)
			if EggHub.setters["Income Collected"] then
				EggHub.setters["Income Collected"](incomeTotal)
			end
		end

		if Remotes and Remotes.PenRoster and Remotes.PenRoster.CoinsGathered then
			connectFeature(Remotes.PenRoster.CoinsGathered.OnClientEvent, function(list)
				if EggHub.values["Enable Auto Collect"] and type(list) == "table" then
					for _, item in list do
						if item and item.amount then
							pendingIncomeDelta += (tonumber(item.amount) or 0)
						end
					end
				end
			end)
		end

		local function runAutoCollect()
			if not EggHub.values["Enable Auto Collect"] then
				return
			end
			local now = os.clock()
			if now - lastCollectAt < 3 then
				return
			end
			lastCollectAt = now

			local fetchRemote = (Remotes and Remotes.AwayEarnings and Remotes.AwayEarnings.FetchSummary) or getNetworkingRemote("RF/AwayEarnings/FetchSummary")
			local claimRemote = (Remotes and Remotes.AwayEarnings and Remotes.AwayEarnings.AskCollect) or getNetworkingRemote("RF/AwayEarnings/AskCollect")
			if fetchRemote and claimRemote then
				task.spawn(function()
					local ok, summary = pcall(function() return fetchRemote:InvokeServer() end)
					if ok and type(summary) == "table" and (tonumber(summary.TotalAmount) or 0) >= 5 then
						local cOk, success, _, res = pcall(function()
							return claimRemote:InvokeServer({ Kind = "Claim" })
						end)
						if cOk and success == true and type(res) == "table" and res.AwardedAmount then
							addCollectedIncome(res.AwardedAmount)
						end
					end
				end)
			end
		end

		local function runAutoSell()
			if not EggHub.values["Enable Auto Sell"] then
				return
			end
			local now = os.clock()
			if now - lastSellAt < 2.5 then
				return
			end
			lastSellAt = now

			if not (SaveMod and type(SaveMod.Await) == "function") then
				return
			end
			local ok, save = pcall(SaveMod.Await)
			if not ok or type(save) ~= "table" or type(save.Inventory) ~= "table" then
				return
			end

			local equippedSet = {}
			if type(save.EquippedAssets) == "table" then
				for k, v in save.EquippedAssets do
					if type(v) == "string" then
						equippedSet[v] = true
					elseif type(k) == "string" and v == true then
						equippedSet[k] = true
					end
				end
			end
			if AssetRoster and type(AssetRoster.ReadOwnerAssets) == "function" then
				local rOk, ownerAssets = pcall(AssetRoster.ReadOwnerAssets, localPlayer.UserId)
				if rOk and type(ownerAssets) == "table" then
					for uid in ownerAssets do
						equippedSet[uid] = true
					end
				end
			end

			local sellMode = EggHub.values["Sell Mode"] or "By Rarity"
			local minKeep = EggHub.values["Min Rarity To Keep"] or "Common"
			local _, minKeepRank = getRarityInfo(minKeep)
			local toSell = {}

			for uid, rawItem in save.Inventory do
				if not equippedSet[uid] and type(rawItem) == "table" and not rawItem.IsFavorite and not rawItem.Favorite and not rawItem.InFuse and not rawItem.Locked then
					local cat = rawItem.Category or rawItem.AssetCategory or rawItem.c
					local scale = tonumber(rawItem.Scale or rawItem.AssetScale or rawItem.s) or 1
					local _, rank = getRarityInfo(cat)
					local shouldSell = false
					if sellMode == "All" then
						shouldSell = true
					elseif sellMode == "By Rarity" then
						shouldSell = rank < minKeepRank
					elseif sellMode == "By Size" then
						shouldSell = scale < 1.1 and rank < minKeepRank
					end
					if shouldSell then
						table.insert(toSell, uid)
						if #toSell >= 64 then
							break
						end
					end
				end
			end

			if #toSell > 0 then
				local sellRemote = (Remotes and Remotes.PetSatchel and Remotes.PetSatchel.SellSelection) or getNetworkingRemote("RE/PetSatchel/SellSelection")
				if sellRemote then
					pcall(function()
						sellRemote:FireServer({ Assets = toSell, Eggs = {} })
					end)
				end
			end
		end

		EggHub.actions["Teleport To Biome"] = function()
			local biomeName = EggHub.values["Biome"] or "Forest"
			local guardAreas = getGuardAreasFolder()
			if not guardAreas then
				return
			end
			local area = guardAreas:FindFirstChild(biomeName)
			if not area then
				return
			end
			local exitPt = area:FindFirstChild("ClosestExitPoint")
			local bounds = area:FindFirstChild("Bounds")
			local targetCf = nil
			if exitPt and exitPt:IsA("BasePart") then
				targetCf = exitPt.CFrame + Vector3.new(0, 4, 0)
			elseif bounds and bounds:IsA("BasePart") then
				targetCf = CFrame.new(bounds.Position.X, bounds.Position.Y + bounds.Size.Y * 0.5 + 4, bounds.Position.Z)
			end
			if targetCf then
				safeTeleportTo(targetCf)
			end
		end

		-- =================================================================
		-- 8) VISUALS: EGG ESP / PET ESP / PLAYER ESP / GUARDIAN ESP / BIOME BOUNDARY
		-- Highlights & SelectionBoxes live in workspace.CurrentCamera (renders immediately without respawn).
		-- BillboardGuis live in PlayerGui ScreenGui (ResetOnSpawn = false).
		-- =================================================================
		local espGuiParent = localPlayer:FindFirstChildOfClass("PlayerGui")
			or localPlayer:WaitForChild("PlayerGui", 3)
			or (typeof(gethui) == "function" and select(2, pcall(gethui)))
			or coreGui
		local espFolder = Instance.new("ScreenGui")
		espFolder.Name = "EggHubESP"
		espFolder.ResetOnSpawn = false
		espFolder.IgnoreGuiInset = true
		pcall(function()
			espFolder.Parent = espGuiParent
		end)

		local espWorldFolder = Instance.new("Folder")
		espWorldFolder.Name = "EggHubWorldESP"
		espWorldFolder.Archivable = false
		espWorldFolder.Parent = workspace.CurrentCamera or workspace

		connectFeature(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
			if not unloaded and espWorldFolder.Parent ~= nil then
				espWorldFolder.Parent = workspace.CurrentCamera or workspace
			end
		end)

		local eggEspMap = {}
		local petEspMap = {}
		local guardEspMap = {}
		local boundaryMap = {}
		local playerEspMap = {}

		local function clearVisualMap(map)
			for key, entry in map do
				if entry.highlight then pcall(function() entry.highlight:Destroy() end) end
				if entry.billboard then pcall(function() entry.billboard:Destroy() end) end
				if entry.box then pcall(function() entry.box:Destroy() end) end
				if entry.drawings then
					for _, d in entry.drawings do
						pcall(function() d.Visible = false; d:Remove() end)
					end
				end
				map[key] = nil
			end
		end

		local function makeBillboard(name, adornee, size, offset, textColor)
			local bb = Instance.new("BillboardGui")
			bb.Name = name
			bb.Adornee = adornee
			bb.Size = size or UDim2.fromOffset(140, 32)
			bb.StudsOffset = offset or Vector3.new(0, 2.5, 0)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 5000
			bb.Parent = espFolder

			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.fromScale(1, 1)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.SourceSansBold
			lbl.TextSize = 13
			lbl.TextColor3 = textColor or Color3.new(1, 1, 1)
			lbl.TextStrokeTransparency = 0.2
			lbl.Text = ""
			lbl.Parent = bb
			return bb, lbl
		end

		local function makeHighlight(name, adornee, color)
			local hl = Instance.new("Highlight")
			hl.Name = name
			hl.Adornee = adornee
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.FillColor = color
			hl.OutlineColor = color
			hl.FillTransparency = 0.72
			hl.OutlineTransparency = 0.05
			hl.Parent = espWorldFolder
			return hl
		end

		local function getModelPart(model)
			if not model then return nil end
			if model:IsA("BasePart") then return model end
			if model:IsA("Model") then
				return model.PrimaryPart or model:FindFirstChild("Hitbox") or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("CENTER") or model:FindFirstChildWhichIsA("BasePart")
			end
			return nil
		end

		local function updateEggEsp(rootPos)
			if not EggHub.values["Enable Egg ESP"] then
				clearVisualMap(eggEspMap)
				return
			end
			local maxDist = tonumber(EggHub.values["Egg ESP Max Distance"]) or 1000
			local byRarity = EggHub.values["Colour By Rarity"] ~= false
			local customColor = EggHub.values["Egg ESP Colour"] or Color3.fromRGB(255, 210, 70)
			local fieldByUid = {}
			local records = getFieldEggList()
			for _, rec in records do
				fieldByUid[tostring(rec.Uid)] = rec
			end

			local candidates = {}
			local slotFolder = workspace:FindFirstChild("AreaEggSlotsClient")
			if slotFolder then
				for _, child in slotFolder:GetChildren() do
					candidates[child] = fieldByUid[child.Name] or false
				end
			end
			for uidStr, rec in fieldByUid do
				local worldEgg = workspace:FindFirstChild(uidStr)
				if worldEgg and not candidates[worldEgg] then
					candidates[worldEgg] = rec
				end
			end
			local placedFolder = workspace:FindFirstChild("PlacedEggRenders")
			if placedFolder then
				for _, child in placedFolder:GetChildren() do
					if not candidates[child] then
						candidates[child] = fieldByUid[child.Name] or false
					end
				end
			end

			local seen = {}
			for eggModel, rec in candidates do
				local part = getModelPart(eggModel)
				if part then
					local dist = (part.Position - rootPos).Magnitude
					if dist <= maxDist then
						seen[eggModel] = true
						local cat = (type(rec) == "table" and rec.AssetCategory) or eggModel:GetAttribute("AssetCategory") or eggModel.Name
						local rarityName, _, rarityColor = getRarityInfo(cat)
						local col = byRarity and rarityColor or customColor
						local entry = eggEspMap[eggModel]
						if not entry then
							local bb, lbl = makeBillboard("EggESP", part, UDim2.fromOffset(160, 34), Vector3.new(0, 2.8, 0), col)
							entry = { highlight = makeHighlight("EggHL", eggModel, col), billboard = bb, label = lbl }
							eggEspMap[eggModel] = entry
						end
						entry.highlight.FillColor = col
						entry.highlight.OutlineColor = col
						entry.label.TextColor3 = col
						entry.label.Text = string.format("%s [%s]\n%.0fm", tostring(cat), rarityName, dist)
					end
				end
			end

			for key, entry in eggEspMap do
				if not seen[key] or not key.Parent then
					pcall(function() entry.highlight:Destroy() end)
					pcall(function() entry.billboard:Destroy() end)
					eggEspMap[key] = nil
				end
			end
		end

		local function updatePetEsp(rootPos)
			if not EggHub.values["Enable Pet ESP"] then
				clearVisualMap(petEspMap)
				return
			end
			local maxDist = tonumber(EggHub.values["Pet ESP Max Distance"]) or 1000
			local showMut = EggHub.values["Show Mutation"] ~= false
			local showSize = EggHub.values["Show Size"] ~= false
			local petsFolder = workspace:FindFirstChild("ClientRenderedAssets")
			local seen = {}

			if petsFolder then
				for _, petModel in petsFolder:GetChildren() do
					local part = getModelPart(petModel)
					if part then
						local dist = (part.Position - rootPos).Magnitude
						if dist <= maxDist then
							seen[petModel] = true
							local entry = petEspMap[petModel]
							local col = Color3.fromRGB(115, 225, 255)
							if not entry then
								local bb, lbl = makeBillboard("PetESP", part, UDim2.fromOffset(170, 38), Vector3.new(0, 3, 0), col)
								entry = { highlight = makeHighlight("PetHL", petModel, col), billboard = bb, label = lbl }
								petEspMap[petModel] = entry
							end
							local labelParts = { petModel:GetAttribute("AssetCategory") or petModel.Name }
							if showMut then
								local mut = petModel:GetAttribute("Mutations") or petModel:GetAttribute("BaseMutation")
								if mut and mut ~= "" then
									table.insert(labelParts, "[" .. tostring(mut) .. "]")
								end
							end
							if showSize then
								local sc = tonumber(petModel:GetAttribute("AssetScale"))
								if sc then
									table.insert(labelParts, string.format("x%.2f", sc))
								end
							end
							entry.label.Text = table.concat(labelParts, " ") .. string.format("\n%.0fm", dist)
						end
					end
				end
			end

			for key, entry in petEspMap do
				if not seen[key] or not key.Parent then
					pcall(function() entry.highlight:Destroy() end)
					pcall(function() entry.billboard:Destroy() end)
					petEspMap[key] = nil
				end
			end
		end

		local function updateGuardianEsp(rootPos)
			if not EggHub.values["Enable Guardian ESP"] then
				clearVisualMap(guardEspMap)
				return
			end
			local showSpeed = EggHub.values["Show Threshold Speed"] ~= false
			local guardAreas = getGuardAreasFolder()
			local seen = {}
			if guardAreas then
				for _, areaModel in guardAreas:GetChildren() do
					local guard = areaModel:FindFirstChild("ForestGuardStaging") or areaModel:FindFirstChild("Guard")
					if not guard then
						for _, ch in areaModel:GetChildren() do
							if ch:IsA("Model") and ch:FindFirstChildOfClass("Humanoid") then
								guard = ch
								break
							end
						end
					end
					local part = getModelPart(guard)
					if guard and part then
						seen[guard] = true
						local col = guard:GetAttribute("Sleeping") == true and Color3.fromRGB(255, 190, 70) or Color3.fromRGB(255, 65, 65)
						local entry = guardEspMap[guard]
						if not entry then
							local bb, lbl = makeBillboard("GuardESP", part, UDim2.fromOffset(170, 36), Vector3.new(0, 4.5, 0), col)
							entry = { highlight = makeHighlight("GuardHL", guard, col), billboard = bb, label = lbl }
							guardEspMap[guard] = entry
						end
						entry.highlight.FillColor = col
						entry.highlight.OutlineColor = col
						entry.label.TextColor3 = col
						local dist = (part.Position - rootPos).Magnitude
						local ws = getBiomeSpeed(areaModel.Name)
						entry.label.Text = showSpeed
							and string.format("%s Guard (%.0f WS)\n%.0fm", areaModel.Name, ws, dist)
							or string.format("%s Guard\n%.0fm", areaModel.Name, dist)
					end
				end
			end
			for key, entry in guardEspMap do
				if not seen[key] or not key.Parent then
					pcall(function() entry.highlight:Destroy() end)
					pcall(function() entry.billboard:Destroy() end)
					guardEspMap[key] = nil
				end
			end
		end

		local function updateBiomeBoundary()
			if not EggHub.values["Enable Biome Boundary"] then
				clearVisualMap(boundaryMap)
				return
			end
			local col = EggHub.values["Boundary Colour"] or Color3.fromRGB(70, 160, 255)
			local guardAreas = getGuardAreasFolder()
			local seen = {}
			if guardAreas then
				for _, areaModel in guardAreas:GetChildren() do
					local bounds = areaModel:FindFirstChild("Bounds")
					if bounds and bounds:IsA("BasePart") then
						seen[bounds] = true
						local entry = boundaryMap[bounds]
						if not entry then
							local sb = Instance.new("SelectionBox")
							sb.Name = "BiomeBoundaryBox"
							sb.Adornee = bounds
							sb.LineThickness = 0.14
							sb.SurfaceTransparency = 0.88
							sb.Parent = espWorldFolder
							entry = { box = sb }
							boundaryMap[bounds] = entry
						end
						entry.box.Color3 = col
						entry.box.SurfaceColor3 = col
					end
				end
			end
			local sep = getSeparationLine()
			if sep and sep:IsA("BasePart") then
				seen[sep] = true
				local entry = boundaryMap[sep]
				if not entry then
					local sb = Instance.new("SelectionBox")
					sb.Name = "SeparationLineBox"
					sb.Adornee = sep
					sb.LineThickness = 0.14
					sb.SurfaceTransparency = 0.85
					sb.Parent = espWorldFolder
					entry = { box = sb }
					boundaryMap[sep] = entry
				end
				entry.box.Color3 = col
				entry.box.SurfaceColor3 = col
			end
			for key, entry in boundaryMap do
				if not seen[key] or not key.Parent then
					pcall(function() entry.box:Destroy() end)
					boundaryMap[key] = nil
				end
			end
		end

		local hasDrawing = type(Drawing) == "table" or type(Drawing) == "function"
		local function newLineDrawing(col)
			if not hasDrawing then
				return nil
			end
			local ok, line = pcall(Drawing.new, "Line")
			if not ok or not line then
				return nil
			end
			line.Thickness = 1.6
			line.Color = col
			line.Transparency = 1
			line.Visible = false
			return line
		end

		local function ensurePlayerDrawings(entry, col)
			if entry.drawings or not hasDrawing then
				return
			end
			local lines = {}
			for i = 1, 8 do
				local ln = newLineDrawing(col)
				if not ln then
					for _, prev in lines do pcall(function() prev:Remove() end) end
					return
				end
				lines[i] = ln
			end
			entry.drawings = lines
		end

		local function updatePlayerEsp(rootPos)
			local style = EggHub.values["Player ESP Style"] or "Corner"
			if not EggHub.values["Enable Player ESP"] or style == "Off" then
				clearVisualMap(playerEspMap)
				return
			end
			local showDist = EggHub.values["Player ESP Distance"] ~= false
			local seen = {}
			for _, plr in playersService:GetPlayers() do
				if plr ~= localPlayer and plr.Character then
					local tRoot = plr.Character:FindFirstChild("HumanoidRootPart")
					local tHum = plr.Character:FindFirstChildOfClass("Humanoid")
					if tRoot and tHum and tHum.Health > 0 then
						seen[plr] = true
						local entry = playerEspMap[plr]
						local col = style == "Corner" and Color3.fromRGB(110, 225, 255) or Color3.fromRGB(255, 255, 255)
						if not entry then
							local bb, lbl = makeBillboard("PlayerESP", tRoot, UDim2.fromOffset(150, 28), Vector3.new(0, 3.2, 0), col)
							entry = { highlight = makeHighlight("PlayerHL", plr.Character, col), billboard = bb, label = lbl }
							ensurePlayerDrawings(entry, col)
							playerEspMap[plr] = entry
						end
						if entry.highlight.Adornee ~= plr.Character then
							entry.highlight.Adornee = plr.Character
						end
						if entry.billboard.Adornee ~= tRoot then
							entry.billboard.Adornee = tRoot
						end
						entry.highlight.FillTransparency = style == "Full" and 0.65 or 0.92
						entry.highlight.OutlineColor = col
						entry.label.TextColor3 = col
						local dist = (tRoot.Position - rootPos).Magnitude
						entry.label.Text = showDist and string.format("%s [%.0fm]", plr.DisplayName, dist) or plr.DisplayName
					end
				end
			end
			for key, entry in playerEspMap do
				if not seen[key] or not key.Character or not key.Character.Parent then
					pcall(function() entry.highlight:Destroy() end)
					pcall(function() entry.billboard:Destroy() end)
					if entry.drawings then
						for _, d in entry.drawings do
							pcall(function() d.Visible = false; d:Remove() end)
						end
					end
					playerEspMap[key] = nil
				end
			end
		end

		connectFeature(runService.RenderStepped, function()
			if unloaded then return end
			local style = EggHub.values["Player ESP Style"] or "Corner"
			local enabled = EggHub.values["Enable Player ESP"] == true and style ~= "Off"
			local cam = workspace.CurrentCamera
			if not enabled or not cam then
				for _, entry in playerEspMap do
					if entry.drawings then
						for _, d in entry.drawings do d.Visible = false end
					end
				end
				return
			end
			for plr, entry in playerEspMap do
				if entry.drawings then
					local char = plr.Character
					local tRoot = char and char:FindFirstChild("HumanoidRootPart")
					if tRoot then
						local topPos, onScreenTop = cam:WorldToViewportPoint(tRoot.Position + Vector3.new(0, 3, 0))
						local botPos, onScreenBot = cam:WorldToViewportPoint(tRoot.Position - Vector3.new(0, 3, 0))
						if onScreenTop or onScreenBot then
							local h = math.max(math.abs(botPos.Y - topPos.Y), 16)
							local w = h * 0.58
							local x = topPos.X - w * 0.5
							local y = topPos.Y
							local col = style == "Corner" and Color3.fromRGB(110, 225, 255) or Color3.fromRGB(255, 255, 255)
							local lines = entry.drawings
							if style == "Full" then
								local pts = {
									{ Vector2.new(x, y), Vector2.new(x + w, y) },
									{ Vector2.new(x + w, y), Vector2.new(x + w, y + h) },
									{ Vector2.new(x + w, y + h), Vector2.new(x, y + h) },
									{ Vector2.new(x, y + h), Vector2.new(x, y) },
								}
								for i = 1, 8 do
									local ln = lines[i]
									if i <= 4 then
										ln.From, ln.To, ln.Color, ln.Visible = pts[i][1], pts[i][2], col, true
									else
										ln.Visible = false
									end
								end
							else
								local cw = math.max(w * 0.28, 4)
								local ch = math.max(h * 0.22, 4)
								local pts = {
									{ Vector2.new(x, y), Vector2.new(x + cw, y) },
									{ Vector2.new(x, y), Vector2.new(x, y + ch) },
									{ Vector2.new(x + w, y), Vector2.new(x + w - cw, y) },
									{ Vector2.new(x + w, y), Vector2.new(x + w, y + ch) },
									{ Vector2.new(x, y + h), Vector2.new(x + cw, y + h) },
									{ Vector2.new(x, y + h), Vector2.new(x, y + h - ch) },
									{ Vector2.new(x + w, y + h), Vector2.new(x + w - cw, y + h) },
									{ Vector2.new(x + w, y + h), Vector2.new(x + w, y + h - ch) },
								}
								for i = 1, 8 do
									local ln = lines[i]
									ln.From, ln.To, ln.Color, ln.Visible = pts[i][1], pts[i][2], col, true
								end
							end
						else
							for _, d in entry.drawings do d.Visible = false end
						end
					else
						for _, d in entry.drawings do d.Visible = false end
					end
				end
			end
		end)

		addCleanup(function()
			clearVisualMap(eggEspMap)
			clearVisualMap(petEspMap)
			clearVisualMap(guardEspMap)
			clearVisualMap(boundaryMap)
			clearVisualMap(playerEspMap)
			if espWorldFolder.Parent then
				pcall(function() espWorldFolder:Destroy() end)
			end
			if espFolder.Parent then
				espFolder:Destroy()
			end
		end)

		-- =================================================================
		-- 9) CONFIG UTILITY: ANTI AFK / REJOIN / CALIBRATION
		-- =================================================================
		connectFeature(localPlayer.Idled, function()
			if EggHub.values["Anti AFK"] and virtualUser then
				pcall(function()
					virtualUser:CaptureController()
					virtualUser:ClickButton2(Vector2.new())
				end)
			end
		end)

		EggHub.actions["Rejoin Server"] = function()
			pcall(function()
				if game.JobId and game.JobId ~= "" then
					teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
				else
					teleportService:Teleport(game.PlaceId, localPlayer)
				end
			end)
		end

		EggHub.actions["Start Calibration"] = function()
			local char = localPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local biome = getCurrentBiomeName(root.Position) or "Lobby"
				EggHub.notify("Calibrated (" .. biome .. ")", true)
			else
				EggHub.notify("Calibrated", true)
			end
			setStatus("Calibration complete.")
		end

		-- =================================================================
		-- 10) CHARACTER & PERIODIC SCHEDULER LOOP (ZERO LAGSPIKE)
		-- =================================================================
		local function bindCharacter(char)
			setPushbackDisabled(EggHub.values["Enable Speed"] or EggHub.values["Enable Fly"])
			local hum = char:WaitForChild("Humanoid", 5)
			if hum then
				connectFeature(hum.StateChanged, function()
					if EggHub.values["Anti Ragdoll"] then
						enforceAntiRagdoll(char, hum)
					end
				end)
				connectFeature(hum:GetPropertyChangedSignal("WalkSpeed"), function()
					if unloaded then return end
					if EggHub.values["Enable Fly"] and (EggHub.values["Fly Method"] or "Humanoid") == "Humanoid" then
						local fs = math.clamp(tonumber(EggHub.values["Fly Speed"]) or 50, 16, 200)
						if math.abs(hum.WalkSpeed - fs) > 0.1 then
							hum.WalkSpeed = fs
						end
					elseif EggHub.values["Enable Speed"] and (EggHub.values["Speed Mode"] or "WalkSpeed") == "WalkSpeed" then
						local ws = resolveEffectiveWalkSpeed()
						if math.abs(hum.WalkSpeed - ws) > 0.1 then
							hum.WalkSpeed = ws
						end
					end
				end)
			end
		end

		connectFeature(localPlayer.CharacterAdded, bindCharacter)
		if localPlayer.Character then
			task.spawn(bindCharacter, localPlayer.Character)
		end

		local warned = {}
		local function safe(name, fn, ...)
			local ok, err = pcall(fn, ...)
			if not ok and not warned[name] then
				warned[name] = true
				warn("[Egg Hub] " .. name .. ": " .. tostring(err))
			end
		end

		task.delay(3, function()
			if unloaded or not screenGui.Parent then
				return
			end
			print("[Egg Hub] eggs:", workspace:FindFirstChild("AreaEggSlotsClient"))
			print("[Egg Hub] pets:", workspace:FindFirstChild("ClientRenderedAssets"))
			print("[Egg Hub] guards:", getGuardAreasFolder())
			print("[Egg Hub] Remotes:", Remotes, "EggState:", EggState, "PlotState:", PlotState)
		end)

		local function stepFeaturesOnce()
			if unloaded or not screenGui.Parent then
				return false
			end
			local now = os.clock()

			safe("IncomeSync", function()
				if pendingIncomeDelta > 0 then
					local delta = pendingIncomeDelta
					pendingIncomeDelta = 0
					addCollectedIncome(delta)
				end
				if #pendingNotifies > 0 then
					for _, item in pendingNotifies do
						EggHub.notify(item.msg, item.ok)
					end
					table.clear(pendingNotifies)
				end
			end)

			local char, hum = getCharacterParts()
			safe("AntiRagdoll", function()
				if EggHub.values["Anti Ragdoll"] and char and hum then
					enforceAntiRagdoll(char, hum)
				end
			end)
			safe("AntiGuardian", applyAntiGuardianPass)
			safe("AntiBearTrap", applyAntiBearTrapPass)
			safe("Bat", function()
				if EggHub.values["Auto Swing Bat"] and now - lastBatSwing >= 0.45 then
					lastBatSwing = now
					swingBatOnce()
				end
			end)
			safe("AutoSteal", runAutoStealAndRareClaim)
			safe("AutoTrain", runAutoTrain)
			safe("AutoHatch", runAutoHatch)
			safe("AutoCollect", runAutoCollect)
			safe("AutoSell", runAutoSell)

			-- Egg Spawn Timer update
			safe("Timer", function()
				local rem = math.ceil(getNextEggResetSeconds())
				if EggHub.setters["Next Spawn In"] and EggHub.values["Next Spawn In"] ~= rem then
					EggHub.setters["Next Spawn In"](rem)
				end
				if lastSpawnCountdown ~= nil and rem > lastSpawnCountdown + 15 and EggHub.values["Notify On Reset"] then
					EggHub.notify("Eggs Respawned!", true)
				end
				lastSpawnCountdown = rem
			end)

			local _, _, root = getCharacterParts()
			local rootPos = root and root.Position or (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero)
			safe("EggESP", updateEggEsp, rootPos)
			safe("PetESP", updatePetEsp, rootPos)
			safe("GuardESP", updateGuardianEsp, rootPos)
			safe("Boundary", updateBiomeBoundary)
			safe("PlayerESP", updatePlayerEsp, rootPos)
			return true
		end

		EggHub._stepFeaturesOnce = stepFeaturesOnce

		task.spawn(function()
			while not unloaded and screenGui.Parent do
				pcall(stepFeaturesOnce)
				task.wait(0.15)
			end
		end)
	end

	task.spawn(function()
		while screenGui.Parent do
			local keyName = EggHub.values["Menu Keybind"]
			EggHub.menuKey = Enum.KeyCode.RightShift

			for _, item in Enum.KeyCode:GetEnumItems() do
				if item.Name == keyName then
					EggHub.menuKey = item
					break
				end
			end

			if EggHub.values["Autoload"] and writefile then
				pcall(function()
					if makefolder and isfolder and not isfolder(CONFIG_FOLDER) then
						makefolder(CONFIG_FOLDER)
					end

					writefile(resolveConfigPath(), encodeSettingsPayload())
				end)
			end

			task.wait(5)
		end
	end)

	local okF, errF = pcall(installFeatures)
	if not okF then
		warn("[Egg Hub] installFeatures: " .. tostring(errF))
	end

	if readfile and isfile and isfile(CONFIG_FILE) then
		pcall(function()
			local data = httpService:JSONDecode(readfile(CONFIG_FILE))
			if typeof(data) == "table" and data["Autoload"] == true then
				for name, value in data do
					local setter = EggHub.setters[name]
					if setter then
						pcall(setter, value)
					end
				end
			end
		end)
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		local query = string.lower(searchBox.Text)

		for _, element in EggHub.searchables do
			element.Visible = (query == "" or string.find(string.lower(element.Name), query, 1, true) ~= nil) and not element:GetAttribute("GroupHidden")
		end

		for _, section in EggHub.sections do
			section.Visible = query == ""
		end

		for _, box in EggHub.boxes do
			local anyVisible = query == ""

			for _, child in box:GetChildren() do
				if child:IsA("GuiObject") and child.Visible and not table.find(EggHub.sections, child) then
					anyVisible = true
					break
				end
			end

			box.Visible = anyVisible
		end
	end)

	connectInput(userInputService.InputBegan, function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if EggHub.listening then
			return EggHub.listening(input.KeyCode)
		end

		if gameProcessed then
			return
		end

		if input.KeyCode == EggHub.menuKey then
			screenGui.Enabled = not screenGui.Enabled
			return
		end

		for featureName, keyCode in EggHub.keybinds do
			if keyCode == input.KeyCode then
				EggHub.setters[featureName](not EggHub.values[featureName])
				EggHub.notify(featureName, EggHub.values[featureName])
			end
		end
	end)

	task.spawn(function()
		while screenGui.Parent do
			local visible = EggHub.values["Keybind Hints"] ~= false

			for _, keybindButton in EggHub.keyLabels do
				keybindButton.Visible = visible
			end

			task.wait(0.5)
		end
	end)

	switchTab("Main")
end

local function onInitializeError(error)
	warn("Failed to initialize.")
	warn(error)
	warn(debug.traceback())
end

xpcall(initializeScript, onInitializeError)
