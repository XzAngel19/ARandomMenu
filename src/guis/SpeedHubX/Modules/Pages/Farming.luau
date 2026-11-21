-- SpeedHubX / Modules / Pages / Farming.luau
-- "Farming" tab. Not visible in the reference image and intentionally an
-- empty stub page: no farming/automation controls or logic are invented.

return function(Deps: any)
	local Controls = Deps.Controls

	local function Build(ctx: any)
		local page = ctx.Page

		Controls.Section(page, "Farming")
		Controls.Paragraph(
			page,
			"Stub Tab",
			"This tab is intentionally empty -- no features are implemented."
		)
	end

	return Build
end
