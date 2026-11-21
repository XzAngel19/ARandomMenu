-- SpeedHubX / Modules / Pages / Home.luau
-- "Home" tab. Not visible in the reference image, so it only carries
-- menu-chrome actions (hide / unload) and version info -- no invented
-- gameplay features.

return function(Deps: any)
	local Controls = Deps.Controls

	local function Build(ctx: any)
		local page = ctx.Page
		local app = ctx.App

		Controls.Section(page, "Home")

		Controls.Paragraph(
			page,
			"Speed Hub X",
			"Version: 3.7.0  |  UI replica -- every feature callback is an empty stub."
		)

		Controls.Button(page, {
			Title = "Hide Menu",
			Description = "Press RightShift to show it again",
			Callback = function()
				app.SetVisible(false)
			end,
		})

		Controls.Button(page, {
			Title = "Unload Menu",
			Description = "Destroy the GUI and disconnect all UI connections",
			Callback = function()
				app.Destroy()
			end,
		})
	end

	return Build
end
