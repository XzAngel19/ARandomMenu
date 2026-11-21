-- SpeedHubX / Modules / Pages / Killer.luau
-- "Killer" tab. Not visible in the reference image and intentionally an
-- empty stub page: no combat controls or logic are invented.

return function(Deps: any)
	local Controls = Deps.Controls

	local function Build(ctx: any)
		local page = ctx.Page

		Controls.Section(page, "Killer")
		Controls.Paragraph(
			page,
			"Stub Tab",
			"This tab is intentionally empty -- no features are implemented."
		)
	end

	return Build
end
