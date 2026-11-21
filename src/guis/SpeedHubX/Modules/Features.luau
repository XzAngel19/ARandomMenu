-- SpeedHubX / Modules / Features.luau
-- STUB FEATURE CALLBACKS -- INTENTIONALLY EMPTY.
--
-- Every control in the menu is wired to one of these functions so the UI is
-- fully interactive (toggles flip, the dropdown selects, values are stored),
-- but no gameplay, combat, farming, movement, automation or exploit logic
-- exists anywhere in this package. Implementations belong outside this
-- replica; replacing a body here is the only hook point.

return function(_Deps: any)
	local Features = {}

	-- Skill section (Main tab)
	function Features.AutoUltimate(_enabled: boolean) end
	function Features.AutoDash(_enabled: boolean) end

	-- Aim section (Main tab)
	function Features.AimPartChanged(_aimPart: string) end
	function Features.Aimlock(_enabled: boolean) end

	-- Body section (Main tab)
	function Features.AntiKnockback(_enabled: boolean) end
	function Features.AntiStun(_enabled: boolean) end
	function Features.AntiBusy(_enabled: boolean) end

	return Features
end
