-- SpeedHubX / Modules / Controls.luau
-- Section / Toggle / Dropdown / Slider / Button / Paragraph factories.
--
-- Controls are pure UI: they keep their own value, repaint themselves and
-- invoke the supplied callback. Callbacks in this package are the empty
-- stubs from Modules/Features.luau, so controls never touch gameplay.
--
-- Every factory returns a handle: { Value, Set(value, fireCallback?), Frame }.

export type ToggleOptions = {
	Title: string,
	Description: string?,
	Default: boolean?,
	Callback: ((boolean) -> ())?,
}
export type DropdownOptions = {
	Title: string,
	Options: { string },
	Default: string?,
	Callback: ((string) -> ())?,
}
export type SliderOptions = {
	Title: string,
	Description: string?,
	Min: number,
	Max: number,
	Default: number?,
	Step: number?,
	Format: ((number) -> string)?,
	Callback: ((number) -> ())?,
}
export type ButtonOptions = {
	Title: string,
	Description: string?,
	Callback: (() -> ())?,
}

return function(Deps: any)
	local Theme = Deps.Theme
	local Util = Deps.Util
	local Bucket = Deps.Bucket
	local new = Util.new

	local Controls = {}

	local function corner(radius: number): UICorner
		return new("UICorner", { CornerRadius = UDim.new(0, radius) }) :: UICorner
	end

	-- Shared dark card shell used by Toggle / Slider / Button / Paragraph.
	local function card(parent: Instance, height: number): Frame
		local frame = new("Frame", {
			Name = "Card",
			BackgroundColor3 = Theme.Color.Card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
			Parent = parent,
		}) :: Frame
		corner(Theme.Metric.CardCorner).Parent = frame
		return frame
	end

	local function titleAndDescription(
		parent: Instance,
		title: string,
		description: string?
	): (TextLabel, TextLabel?)
		local titleLabel = new("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 16, 0, description and 10 or 0),
			Size = UDim2.new(1, -76, 0, 22),
			Font = Theme.Font.Label,
			TextSize = Theme.TextSize.Label,
			TextColor3 = Theme.Color.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = description and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			Text = title,
			Parent = parent,
		}) :: TextLabel
		if not description then
			titleLabel.Size = UDim2.new(1, -76, 1, 0)
			return titleLabel, nil
		end
		local descriptionLabel = new("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 16, 0, 34),
			Size = UDim2.new(1, -76, 0, 18),
			Font = Theme.Font.Description,
			TextSize = Theme.TextSize.Description,
			TextColor3 = Theme.Color.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = description,
			Parent = parent,
		}) :: TextLabel
		return titleLabel, descriptionLabel
	end

	--- Section header, e.g. "Skill" / "Aim" / "Body".
	function Controls.Section(parent: Instance, text: string): TextLabel
		local label = new("TextLabel", {
			Name = "Section",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			Font = Theme.Font.Section,
			TextSize = Theme.TextSize.Section,
			TextColor3 = Theme.Color.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Text = text,
			Parent = parent,
		}) :: TextLabel
		return label
	end

	--- Toggle row: dark card, title/description on the left and a square
	--- track with a red dot (on) / grey dot (off) on the right, as in the
	--- reference image. The whole card is clickable.
	function Controls.Toggle(parent: Instance, options: ToggleOptions): any
		local value = options.Default == true

		local button = new("TextButton", {
			Name = "Toggle_" .. options.Title,
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Color.Card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, Theme.Metric.CardHeight),
			Text = "",
			Parent = parent,
		}) :: TextButton
		corner(Theme.Metric.CardCorner).Parent = button
		titleAndDescription(button, options.Title, options.Description)

		local size = Theme.Metric.ToggleSize
		local track = new("Frame", {
			Name = "Track",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Color.ValueBox,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(size, size),
			Parent = button,
		}) :: Frame
		corner(8).Parent = track

		local knob = new("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			Parent = track,
		}) :: Frame
		corner(9).Parent = knob

		local handle: any = {}

		local function repaint()
			knob.BackgroundColor3 = value and Theme.Color.IndicatorOn or Theme.Color.KnobOff
		end

		function handle.Set(newValue: boolean, fireCallback: boolean?)
			value = newValue == true
			handle.Value = value
			repaint()
			if fireCallback and options.Callback then
				options.Callback(value)
			end
		end

		function handle.Get(): boolean
			return value
		end

		handle.Value = value
		handle.Frame = button

		Bucket:add(button.MouseButton1Click:Connect(function()
			handle.Set(not value, true)
			handle.Value = value
		end))
		Bucket:add(button.MouseEnter:Connect(function()
			button.BackgroundColor3 = Theme.Color.CardHover
		end))
		Bucket:add(button.MouseLeave:Connect(function()
			button.BackgroundColor3 = Theme.Color.Card
		end))

		repaint()
		return handle
	end

	--- Dropdown row: label on the left, caret, and a wide value box on the
	--- right ("Head" in the reference image). Clicking expands the option
	--- list directly under the row. Selection is UI state only.
	function Controls.Dropdown(parent: Instance, options: DropdownOptions): any
		local value = options.Default or options.Options[1] or ""

		local container = new("Frame", {
			Name = "Dropdown_" .. options.Title,
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Theme.Metric.DropdownHeight),
			Parent = parent,
		}) :: Frame
		new("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = container,
		})

		local row = new("TextButton", {
			Name = "Row",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Color.Card,
			BorderSizePixel = 0,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Theme.Metric.DropdownHeight),
			Text = "",
			Parent = container,
		}) :: TextButton
		corner(Theme.Metric.CardCorner).Parent = row

		new("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 16, 0, 0),
			Size = UDim2.new(0.45, 0, 1, 0),
			Font = Theme.Font.Label,
			TextSize = Theme.TextSize.Label,
			TextColor3 = Theme.Color.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = options.Title,
			Parent = row,
		})

		local caret = new("TextLabel", {
			Name = "Caret",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -296, 0.5, 0),
			Size = UDim2.fromOffset(24, 24),
			Font = Theme.Font.Label,
			TextSize = 18,
			TextColor3 = Theme.Color.TextDim,
			Text = "^",
			Parent = row,
		}) :: TextLabel

		local valueBox = new("Frame", {
			Name = "ValueBox",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Color.ValueBox,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 272, 0, 38),
			Parent = row,
		}) :: Frame
		corner(6).Parent = valueBox

		local valueLabel = new("TextLabel", {
			Name = "Value",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Theme.Font.Value,
			TextSize = Theme.TextSize.Value,
			TextColor3 = Theme.Color.Text,
			Text = value,
			Parent = valueBox,
		}) :: TextLabel

		local list = new("Frame", {
			Name = "Options",
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Color.Card,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			Visible = false,
			Parent = container,
		}) :: Frame
		corner(Theme.Metric.CardCorner).Parent = list
		new("UIListLayout", {
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
		new("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			Parent = list,
		})

		local handle: any = {}
		local open = false

		local function repaint()
			valueLabel.Text = value
			list.Visible = open
			caret.Text = open and "v" or "^"
		end

		function handle.Set(newValue: string, fireCallback: boolean?)
			value = newValue
			repaint()
			if fireCallback and options.Callback then
				options.Callback(value)
			end
		end

		function handle.Get(): string
			return value
		end

		handle.Frame = container

		for index, option in ipairs(options.Options) do
			local optionButton = new("TextButton", {
				Name = "Option_" .. option,
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Color.ValueBox,
				BorderSizePixel = 0,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 34),
				Font = Theme.Font.Label,
				TextSize = Theme.TextSize.Label,
				TextColor3 = Theme.Color.TextDim,
				Text = option,
				Parent = list,
			}) :: TextButton
			corner(6).Parent = optionButton
			Bucket:add(optionButton.MouseButton1Click:Connect(function()
				open = false
				handle.Set(option, true)
			end))
		end

		Bucket:add(row.MouseButton1Click:Connect(function()
			open = not open
			repaint()
		end))

		repaint()
		return handle
	end

	--- Slider row (reusable component; used by the Misc tab for the menu's
	--- own scale setting). Supports mouse and touch; value is UI state only.
	function Controls.Slider(parent: Instance, options: SliderOptions): any
		local minimum = options.Min
		local maximum = options.Max
		local step = options.Step or 1
		local value = math.clamp(options.Default or minimum, minimum, maximum)

		local frame = card(parent, 78)
		frame.Name = "Slider_" .. options.Title
		titleAndDescription(frame, options.Title, options.Description)

		local valueLabel = new("TextLabel", {
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -16, 0, 10),
			Size = UDim2.fromOffset(90, 22),
			Font = Theme.Font.Value,
			TextSize = 16,
			TextColor3 = Theme.Color.Text,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		}) :: TextLabel

		local bar = new("Frame", {
			Name = "Bar",
			BackgroundColor3 = Theme.Color.ValueBox,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 16, 1, -24),
			Size = UDim2.new(1, -32, 0, 6),
			Parent = frame,
		}) :: Frame
		corner(3).Parent = bar

		local fill = new("Frame", {
			Name = "Fill",
			BackgroundColor3 = Theme.Color.SliderFill,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			Parent = bar,
		}) :: Frame
		corner(3).Parent = fill

		local knob = new("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Color.Text,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			Parent = bar,
		}) :: Frame
		corner(7).Parent = knob

		local hitbox = new("TextButton", {
			Name = "Hitbox",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, -8),
			Size = UDim2.new(1, 0, 1, 16),
			Text = "",
			Parent = bar,
		}) :: TextButton

		local handle: any = {}
		local dragging = false

		local function format(v: number): string
			if options.Format then
				return options.Format(v)
			end
			return tostring(v)
		end

		local function repaint()
			local alpha = (value - minimum) / math.max(maximum - minimum, 0.0001)
			fill.Size = UDim2.fromScale(alpha, 1)
			knob.Position = UDim2.new(alpha, 0, 0.5, 0)
			valueLabel.Text = format(value)
		end

		function handle.Set(newValue: number, fireCallback: boolean?)
			local snapped = minimum + math.round((newValue - minimum) / step) * step
			value = math.clamp(snapped, minimum, maximum)
			repaint()
			if fireCallback and options.Callback then
				options.Callback(value)
			end
		end

		function handle.Get(): number
			return value
		end

		handle.Frame = frame

		local function setFromInput(input: InputObject)
			local alpha = math.clamp(
				(input.Position.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1),
				0,
				1
			)
			handle.Set(minimum + alpha * (maximum - minimum), true)
		end

		Bucket:add(hitbox.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = true
				setFromInput(input)
			end
		end))
		Bucket:add(Util.UserInputService.InputChanged:Connect(function(input: InputObject)
			if dragging
				and (input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch)
			then
				setFromInput(input)
			end
		end))
		Bucket:add(Util.UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
			end
		end))

		repaint()
		return handle
	end

	--- Full-width clickable card (no buttons are visible on the Main tab of
	--- the reference image; used on the Home tab for Hide / Unload).
	function Controls.Button(parent: Instance, options: ButtonOptions): any
		local button = new("TextButton", {
			Name = "Button_" .. options.Title,
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Color.Card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, Theme.Metric.CardHeight),
			Text = "",
			Parent = parent,
		}) :: TextButton
		corner(Theme.Metric.CardCorner).Parent = button
		titleAndDescription(button, options.Title, options.Description)
		new("TextLabel", {
			Name = "Chevron",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(20, 20),
			Font = Theme.Font.Label,
			TextSize = 18,
			TextColor3 = Theme.Color.TextMuted,
			Text = ">",
			Parent = button,
		})
		if options.Callback then
			Bucket:add(button.MouseButton1Click:Connect(options.Callback))
		end
		Bucket:add(button.MouseEnter:Connect(function()
			button.BackgroundColor3 = Theme.Color.CardHover
		end))
		Bucket:add(button.MouseLeave:Connect(function()
			button.BackgroundColor3 = Theme.Color.Card
		end))
		return { Frame = button }
	end

	--- Static info card.
	function Controls.Paragraph(parent: Instance, title: string, description: string): Frame
		local frame = card(parent, 62)
		frame.Name = "Paragraph_" .. title
		frame.AutomaticSize = Enum.AutomaticSize.Y
		titleAndDescription(frame, title, description)
		return frame
	end

	return Controls
end
