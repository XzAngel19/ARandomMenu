-- Egg Hub | GUI.
local playersService = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local httpService = game:GetService("HttpService")

local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 560
local TITLE_HEIGHT = 34
local TAB_HEIGHT = 30
local MIN_WIDTH = 460
local MIN_HEIGHT = 420
local MAX_WIDTH = 980
local MAX_HEIGHT = 860
local CONFIG_FOLDER = "EggHub"
local CONFIG_FILE = "EggHub/EggHub.json"
local TAB_NAMES = { "Main", "Extra", "Visuals", "Config" }
local TITLE_TEXT = "Egg Hub | Steal an Egg"

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
	Color3.fromRGB(70, 255, 120),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(210, 90, 255),
	Color3.fromRGB(0, 0, 0),
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

	button.Activated:Connect(callback or function() end)
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

local function addColor(parent, text, default)
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
		BackgroundColor3 = default or COLOR_PRESETS[1],
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, holder)

	create("UICorner", { CornerRadius = UDim.new(0, 4) }, swatch)
	addStroke(swatch, Color3.new(1, 1, 1), 0.5)

	local index = 1
	EggHub.values[text] = default or COLOR_PRESETS[1]
	EggHub.defaults[text] = default or COLOR_PRESETS[1]

	EggHub.setters[text] = function(value)
		swatch.BackgroundColor3 = value
		EggHub.values[text] = value
	end

	swatch.Activated:Connect(function()
		index = index % #COLOR_PRESETS + 1
		EggHub.setters[text](COLOR_PRESETS[index])
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

	if typeof(shared) == "table" then
		shared.EggHubGui = screenGui
		shared.EggHub = EggHub
	end

	screenGui.Destroying:Connect(function()
		for _, connection in EggHub.connections do
			connection:Disconnect()
		end

		table.clear(EggHub.connections)
	end)

	local toastHolder = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(230, 320),
		BackgroundTransparency = 1,
		ZIndex = 20,
	}, screenGui)

	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}, toastHolder)

	EggHub.notify = function(name, enabled)
		if not toastHolder.Parent then
			return
		end

		local toast = create("CanvasGroup", {
			Size = UDim2.fromOffset(230, 34),
			BackgroundColor3 = Color3.fromRGB(18, 18, 20),
			BorderSizePixel = 0,
			GroupTransparency = 1,
		}, toastHolder)

		create("UICorner", { CornerRadius = UDim.new(0, 7) }, toast)
		addStroke(toast, Color3.new(1, 1, 1), 0.8)

		create("Frame", {
			Size = UDim2.new(0, 3, 1, -12),
			Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = enabled and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(230, 100, 100),
			BorderSizePixel = 0,
		}, toast)

		create("TextLabel", {
			Size = UDim2.new(1, -80, 1, 0),
			Position = UDim2.fromOffset(18, 0),
			BackgroundTransparency = 1,
			Text = name,
			TextColor3 = TEXT_COLOR,
			TextSize = 13,
			Font = TEXT_FONT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, toast)

		create("TextLabel", {
			Size = UDim2.fromOffset(46, 34),
			Position = UDim2.new(1, -54, 0, 0),
			BackgroundTransparency = 1,
			Text = enabled and "ON" or "OFF",
			TextColor3 = enabled and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(230, 100, 100),
			TextSize = 12,
			Font = BOLD_FONT,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, toast)

		tween(toast, FAST_TWEEN, { GroupTransparency = 0 })

		task.delay(2, function()
			tween(toast, MEDIUM_TWEEN, { GroupTransparency = 1 }).Completed:Wait()
			toast:Destroy()
		end)
	end

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
	addSlider(extraLeft, "Speed Value", 16, 1000000000, 16, 0)
	addToggle(extraLeft, "Speed Auto Match Biome", nil, false)

	addSection(extraLeft, "Fly")
	addToggle(extraLeft, "Enable Fly", nil, false)
	addCycle(extraLeft, "Fly Method", { "Velocity", "CFrame", "Humanoid" })
	addSlider(extraLeft, "Fly Speed", 1, 500, 60, 0)
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
	addList(extraRight, "Biome", { "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric", "Cosmic" }, 110)
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

	local function saveSettings()
		if not writefile then
			return setStatus("Saving is not supported here.")
		end

		local ok, result = pcall(function()
			if makefolder and isfolder and not isfolder(CONFIG_FOLDER) then
				makefolder(CONFIG_FOLDER)
			end

			writefile(CONFIG_FILE, httpService:JSONEncode(EggHub.values))
		end)

		setStatus(ok and "Settings saved." or ("Save failed: " .. tostring(result)))
	end

	local function loadSettings()
		if not (readfile and isfile and isfile(CONFIG_FILE)) then
			return setStatus("No saved settings found.")
		end

		local ok, data = pcall(function()
			return httpService:JSONDecode(readfile(CONFIG_FILE))
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

	addSection(configRight, "Theme")
	addColor(configRight, "Theme Colour", Color3.fromRGB(225, 225, 225))
	addButton(configRight, "Save Theme")
	addButton(configRight, "Load Theme")

	addSection(configRight, "Unload")

	local function detach() end

	addButton(configRight, "Unload", function()
		detach()
		tween(windowScale, FAST_TWEEN, { Scale = 0 }).Completed:Connect(function()
			screenGui:Destroy()
		end)
	end)

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

					writefile(CONFIG_FILE, httpService:JSONEncode(EggHub.values))
				end)
			end

			task.wait(5)
		end
	end)

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
