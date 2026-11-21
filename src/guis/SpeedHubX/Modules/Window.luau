-- SpeedHubX / Modules / Window.luau
-- Core window builder + sidebar navigation.
--
-- Layout replicated from the reference image:
--   * 1020 x 640 near-black window, 10px corner, thin dark-red edge
--   * "Speed Hub X | Version: 3.7.0" top-left, X close button top-right
--   * 260px sidebar: Home / Main (selected, red) / Farming / Killer / Misc
--   * scrolling content area on the right, one page per sidebar tab

export type NavItem = {
	Name: string,
	Icon: string,
}
export type BuildOptions = {
	Parent: Instance,
	OnClose: (() -> ())?,
}

return function(Deps: any)
	local Theme = Deps.Theme
	local Util = Deps.Util
	local Bucket = Deps.Bucket
	local new = Util.new

	local Window = {}

	-- Text glyphs stand in for the image icons so the menu needs no
	-- external/uploaded assets (executor-safe, works in any place).
	Window.NavItems = {
		{ Name = "Home", Icon = "⊞" },
		{ Name = "Main", Icon = "⌂" },
		{ Name = "Farming", Icon = "⛏" },
		{ Name = "Killer", Icon = "☠" },
		{ Name = "Misc", Icon = "▤" },
	} :: { NavItem }

	function Window.Build(options: BuildOptions): any
		local screenGui = new("ScreenGui", {
			Name = Theme.GuiName,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			AutoLocalize = false,
			DisplayOrder = 999,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}) :: ScreenGui

		local scale = new("UIScale", { Scale = 1, Parent = screenGui }) :: UIScale

		local frame = new("Frame", {
			Name = "Window",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Color.Window,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Theme.Metric.WindowSize.X, Theme.Metric.WindowSize.Y),
			Parent = screenGui,
		}) :: Frame
		new("UICorner", {
			CornerRadius = UDim.new(0, Theme.Metric.WindowCorner),
			Parent = frame,
		})
		-- Thin dark-red edge visible on the right/bottom in the screenshot.
		new("UIStroke", {
			Color = Theme.Color.Edge,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = frame,
		})

		-- Title bar (also the drag handle)
		local titleBar = new("Frame", {
			Name = "TitleBar",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 76),
			Parent = frame,
		}) :: Frame

		new("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 26, 0, 0),
			Size = UDim2.new(1, -110, 1, 0),
			Font = Theme.Font.Title,
			TextSize = Theme.TextSize.Title,
			TextColor3 = Theme.Color.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = Theme.Title,
			Parent = titleBar,
		})

		local closeButton = new("TextButton", {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(40, 40),
			Font = Theme.Font.Label,
			TextSize = 22,
			TextColor3 = Theme.Color.Text,
			Text = "✕",
			Parent = titleBar,
		}) :: TextButton

		-- Sidebar navigation
		local sidebar = new("Frame", {
			Name = "Sidebar",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, Theme.Metric.WindowPadding, 0, 92),
			Size = UDim2.new(0, Theme.Metric.SidebarWidth, 1, -112),
			Parent = frame,
		}) :: Frame
		new("UIListLayout", {
			Padding = UDim.new(0, Theme.Metric.NavButtonGap),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = sidebar,
		})

		-- Content host (pages are stacked ScrollingFrames)
		local contentX = Theme.Metric.WindowPadding + Theme.Metric.SidebarWidth + Theme.Metric.ContentGap
		local content = new("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, contentX, 0, 84),
			Size = UDim2.new(1, -contentX - Theme.Metric.WindowPadding, 1, -104),
			Parent = frame,
		}) :: Frame

		local handle: any = {
			ScreenGui = screenGui,
			Frame = frame,
			Scale = scale,
			Pages = {},
			CurrentPage = nil,
		}

		local navButtons: { [string]: TextButton } = {}

		local function repaintNav()
			for name, button in pairs(navButtons) do
				local selected = name == handle.CurrentPage
				button.BackgroundColor3 = selected and Theme.Color.Accent or Theme.Color.NavIdle
				local label = button:FindFirstChild("Label") :: TextLabel?
				if label then
					label.TextColor3 = selected and Theme.Color.AccentText or Theme.Color.TextDim
				end
			end
			for name, page in pairs(handle.Pages) do
				(page :: ScrollingFrame).Visible = name == handle.CurrentPage
			end
		end

		--- Create (or fetch) the scrolling page for a tab.
		function handle.CreatePage(name: string): ScrollingFrame
			if handle.Pages[name] then
				return handle.Pages[name]
			end
			local page = new("ScrollingFrame", {
				Name = "Page_" .. name,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				ScrollBarImageColor3 = Theme.Color.ScrollBar,
				ScrollBarThickness = 3,
				Size = UDim2.fromScale(1, 1),
				Visible = false,
				Parent = content,
			}) :: ScrollingFrame
			new("UIListLayout", {
				Padding = UDim.new(0, Theme.Metric.CardGap),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = page,
			})
			new("UIPadding", {
				PaddingRight = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 8),
				Parent = page,
			})
			handle.Pages[name] = page
			return page
		end

		function handle.SelectPage(name: string)
			if not handle.Pages[name] then
				return
			end
			handle.CurrentPage = name
			repaintNav()
		end

		for index, item in ipairs(Window.NavItems) do
			local button = new("TextButton", {
				Name = "Nav_" .. item.Name,
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Color.NavIdle,
				BorderSizePixel = 0,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, Theme.Metric.NavButtonHeight),
				Text = "",
				Parent = sidebar,
			}) :: TextButton
			new("UICorner", {
				CornerRadius = UDim.new(0, 8),
				Parent = button,
			})
			new("TextLabel", {
				Name = "Label",
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 14, 0, 0),
				Size = UDim2.new(1, -20, 1, 0),
				Font = Theme.Font.Label,
				TextSize = Theme.TextSize.Nav,
				TextColor3 = Theme.Color.TextDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = item.Icon .. "  |  " .. item.Name,
				Parent = button,
			})
			navButtons[item.Name] = button
			Bucket:add(button.MouseButton1Click:Connect(function()
				handle.SelectPage(item.Name)
			end))
			Bucket:add(button.MouseEnter:Connect(function()
				if handle.CurrentPage ~= item.Name then
					button.BackgroundColor3 = Theme.Color.NavHover
				end
			end))
			Bucket:add(button.MouseLeave:Connect(function()
				if handle.CurrentPage ~= item.Name then
					button.BackgroundColor3 = Theme.Color.NavIdle
				end
			end))
			handle.CreatePage(item.Name)
		end

		if options.OnClose then
			Bucket:add(closeButton.MouseButton1Click:Connect(options.OnClose))
		end

		-- Keep the fixed-size window usable on small viewports.
		local userScale = 1
		local function fitToViewport()
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local viewport = camera.ViewportSize
			local fit = math.min(
				viewport.X / (Theme.Metric.WindowSize.X + 40),
				viewport.Y / (Theme.Metric.WindowSize.Y + 40)
			)
			scale.Scale = math.clamp(fit, 0.55, 1) * userScale
		end
		handle.SetUserScale = function(value: number)
			userScale = math.clamp(value, 0.5, 1.2)
			fitToViewport()
		end
		fitToViewport()
		local camera = workspace.CurrentCamera
		if camera then
			Bucket:add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToViewport))
		end

		handle.SelectPage("Main")
		handle.RepaintNav = repaintNav

		local setDraggingEnabled = Util.makeDraggable(frame, titleBar, Bucket)
		handle.SetDraggingEnabled = setDraggingEnabled

		-- Safe parenting with fallback (gethui -> CoreGui -> PlayerGui).
		Util.protectGui(screenGui)
		local parent = Util.bestParent()
		if parent then
			pcall(function()
				screenGui.Parent = parent
			end)
		end
		if not screenGui.Parent then
			Util.parentGui(screenGui)
		end
		handle.ParentSource = screenGui.Parent and screenGui.Parent.Name or "none"

		return handle
	end

	return Window
end
