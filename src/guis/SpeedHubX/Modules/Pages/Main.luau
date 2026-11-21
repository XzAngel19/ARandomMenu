-- SpeedHubX / Modules / Pages / Main.luau
-- The "Main" tab -- a 1:1 replica of the visible page in the reference
-- image (the default selected tab). Order, labels, descriptions, default
-- toggle states and the dropdown value match the screenshot exactly.
-- All callbacks are the empty stubs from Modules/Features.luau.

return function(Deps: any)
	local Controls = Deps.Controls
	local Features = Deps.Features

	local function Build(ctx: any)
		local page = ctx.Page

		-- Skill ------------------------------------------------------------
		Controls.Section(page, "Skill")

		Controls.Toggle(page, {
			Title = "Auto Ultimate",
			Description = "This is Meaning Auto Use Ultimate",
			Default = true, -- red indicator in the screenshot
			Callback = Features.AutoUltimate,
		})

		Controls.Toggle(page, {
			Title = "Auto Dash",
			Description = "This is Meaning Auto Use Dash",
			Default = true, -- red indicator in the screenshot
			Callback = Features.AutoDash,
		})

		-- Aim --------------------------------------------------------------
		Controls.Section(page, "Aim")

		Controls.Dropdown(page, {
			Title = "Choose Aim Part",
			Options = { "Head", "HumanoidRootPart", "Torso" },
			Default = "Head", -- value shown in the screenshot
			Callback = Features.AimPartChanged,
		})

		Controls.Toggle(page, {
			Title = "Aimlock",
			Description = "Aimlock = Lock Camera Player",
			Default = false,
			Callback = Features.Aimlock,
		})

		-- Body -------------------------------------------------------------
		Controls.Section(page, "Body")

		Controls.Toggle(page, {
			Title = "Anti-Knockback",
			Description = "BETA",
			Default = false,
			Callback = Features.AntiKnockback,
		})

		Controls.Toggle(page, {
			Title = "Anti-Stun",
			Description = "BETA",
			Default = false,
			Callback = Features.AntiStun,
		})

		Controls.Toggle(page, {
			Title = "Anti-Busy",
			Description = "BETA",
			Default = false,
			Callback = Features.AntiBusy,
		})
	end

	return Build
end
