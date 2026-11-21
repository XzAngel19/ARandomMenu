-- SpeedHubX / Modules / Pages / Misc.luau
-- "Misc" tab. Not visible in the reference image; it only hosts settings
-- for the menu itself (scale / dragging). These are UI-chrome behaviours,
-- not gameplay features -- all gameplay callbacks remain empty stubs.

return function(Deps: any)
	local Controls = Deps.Controls

	local function Build(ctx: any)
		local page = ctx.Page
		local app = ctx.App

		Controls.Section(page, "Misc")

		Controls.Slider(page, {
			Title = "Menu Scale",
			Description = "Scale of this menu only",
			Min = 60,
			Max = 110,
			Default = 100,
			Step = 5,
			Format = function(value: number): string
				return tostring(value) .. "%"
			end,
			Callback = function(value: number)
				app.SetScale(value / 100)
			end,
		})

		Controls.Toggle(page, {
			Title = "Window Dragging",
			Description = "Drag the menu by its title bar",
			Default = true,
			Callback = function(enabled: boolean)
				app.SetDraggingEnabled(enabled)
			end,
		})

		Controls.Paragraph(
			page,
			"About",
			"Speed Hub X | Version: 3.7.0 -- standalone executor GUI replica."
		)
	end

	return Build
end
