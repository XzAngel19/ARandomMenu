-- SpeedHubX / Modules / Bootstrap.luau
-- Composition root: builds the window, builds every tab page, wires the
-- visibility keybind (RightShift) and returns the public App handle.
--
-- Public handle:
--   App.SetVisible(bool) / App.ToggleVisible() / App.IsVisible()
--   App.SelectPage(name)   -- "Home" | "Main" | "Farming" | "Killer" | "Misc"
--   App.SetScale(0.6..1.1) / App.SetDraggingEnabled(bool)  (menu chrome only)
--   App.Destroy()          -- unload: disconnect everything, destroy the GUI
--   App.Window             -- raw window handle from Modules/Window.luau
--
-- Also published as getgenv().SpeedHubX (when getgenv exists) so re-running
-- the script can destroy the previous copy. No feature logic lives here.

return function(Deps: any)
	local Theme = Deps.Theme
	local Util = Deps.Util
	local Features = Deps.Features
	local Window = Deps.Window
	local Pages = Deps.Pages
	local Bucket = Deps.Bucket

	local function Bootstrap(): any
		Util.destroyExisting(Theme.GuiName)

		local destroyed = false
		local app: any = {}

		local window = Window.Build({
			OnClose = function()
				app.SetVisible(false)
			end,
		})
		app.Window = window

		local visible = true

		function app.SetVisible(value: boolean)
			visible = value == true
			window.Frame.Visible = visible
		end

		function app.ToggleVisible()
			app.SetVisible(not visible)
		end

		function app.IsVisible(): boolean
			return visible
		end

		function app.SelectPage(name: string)
			window.SelectPage(name)
		end

		function app.SetScale(value: number)
			window.SetUserScale(value)
		end

		function app.SetDraggingEnabled(value: boolean)
			window.SetDraggingEnabled(value)
		end

		function app.Destroy()
			if destroyed then
				return
			end
			destroyed = true
			if typeof(getgenv) == "function" then
				local ok, env = pcall(getgenv)
				if ok and type(env) == "table" and env.SpeedHubX == app then
					env.SpeedHubX = nil
				end
			end
			Bucket:disconnectAll()
			if window.ScreenGui then
				window.ScreenGui:Destroy()
			end
		end

		-- Build one page per sidebar tab, in sidebar order.
		for _, item in ipairs(Window.NavItems) do
			local buildPage = Pages[item.Name]
			if buildPage then
				buildPage({
					Page = window.CreatePage(item.Name),
					App = app,
					Features = Features,
				})
			end
		end
		window.SelectPage("Main") -- selected (red) tab in the reference image
		app.SetVisible(true)

		-- RightShift shows/hides the menu (ignored while typing).
		Bucket:add(Util.UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			if input.KeyCode == Enum.KeyCode.RightShift and not Util.isTyping() then
				app.ToggleVisible()
			end
		end))

		if typeof(getgenv) == "function" then
			local ok, env = pcall(getgenv)
			if ok and type(env) == "table" then
				env.SpeedHubX = app
			end
		end

		return app
	end

	return Bootstrap
end
