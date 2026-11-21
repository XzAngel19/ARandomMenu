--[[
	Theme.lua
	Palette, typography and layout metrics for the Violent menu replica.

	Every number here was measured against the reference screenshot
	(307 x 507 px window) and scaled by ~1.15 to the 352 px design width used
	by the runtime. Change the tokens here, not inside the components.
]]

local Theme = {}

Theme.Name = "VIOLENT"
Theme.Version = "1.0.0"

-- Sampled from the reference. The window body is translucent black, which is
-- why the upper rows read slate blue (sky behind) and the lower rows read
-- near-black (ground behind). The tint lives in Transparency, below.
Theme.Color = {
	accent        = Color3.fromRGB(255, 20, 147),  -- header, selected colours
	accentSoft    = Color3.fromRGB(255, 95, 181),  -- highlighted row fill
	accentDeep    = Color3.fromRGB(193, 26, 126),  -- section underline
	accentGlow    = Color3.fromRGB(176, 40, 200),  -- ESP preview bloom
	swatchMagenta = Color3.fromRGB(254, 0, 232),
	swatchPink    = Color3.fromRGB(254, 24, 179),
	swatchWhite   = Color3.fromRGB(255, 255, 255),

	black         = Color3.fromRGB(0, 0, 0),
	tab           = Color3.fromRGB(0, 0, 0),
	text          = Color3.fromRGB(242, 244, 245),
	textMuted     = Color3.fromRGB(169, 176, 181),
	textDim       = Color3.fromRGB(140, 146, 150),
	textOnAccent  = Color3.fromRGB(14, 12, 13),
	white         = Color3.fromRGB(255, 255, 255),

	previewTop    = Color3.fromRGB(44, 49, 59),
	previewBottom = Color3.fromRGB(90, 17, 120),
	figure        = Color3.fromRGB(205, 187, 214),
	bone          = Color3.fromRGB(246, 238, 246),
	healthHigh    = Color3.fromRGB(32, 224, 48),
	healthUpper   = Color3.fromRGB(160, 240, 24),
	healthMid     = Color3.fromRGB(255, 226, 26),
	healthLow     = Color3.fromRGB(255, 26, 26),
}

Theme.Transparency = {
	body = 0.24,     -- the whole menu body: game world shows through
	tab = 0,         -- page header strip stays solid black
	footer = 0.16,   -- status bar
	preview = 0.20,  -- ESP preview panel
}

-- Layout, in design pixels. UIScale handles resolution.
Theme.Metric = {
	windowWidth = 352,
	windowHeight = 588,
	headerHeight = 85,
	tabHeight = 32,
	rowHeight = 29,
	sectionHeight = 38,
	dropdownHeight = 34,
	dividerHeight = 3,
	footerHeight = 30,
	paddingX = 10,
	paddingRight = 7,
	checkbox = 22,
	swatchWidth = 27,
	swatchHeight = 20,
	titleUnderline = 4,
	previewWidth = 330,
	previewHeight = 340,
	previewStrip = 8,
	previewBoxWidth = 134,
	previewBoxHeight = 212,
	windowGap = 20,
}

Theme.Text = {
	logo = 50,
	body = 15,
	value = 14,
	tab = 14,
	counter = 13,
	section = 18,
	footer = 15,
	previewTitle = 24,
	previewBody = 11,
}

-- Font lookup is defensive: executors occasionally ship a trimmed Enum.Font or
-- an older client. Everything falls back to a font that has existed forever.
local function enumFont(name)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	if ok and value ~= nil then
		return value
	end
	return nil
end

local function firstFont(names, fallback)
	for _, name in ipairs(names) do
		local font = enumFont(name)
		if font then
			return font
		end
	end
	return fallback
end

Theme.Font = {
	display = firstFont({ "LuckiestGuy", "GothamBlack", "Bangers", "Arcade" }, Enum.Font.Legacy),
	section = firstFont({ "FredokaOne", "LuckiestGuy", "GothamBlack", "Arcade" }, Enum.Font.Legacy),
	body = firstFont({ "GothamMedium", "Gotham", "SourceSansSemibold", "Arial" }, Enum.Font.SourceSans),
	bodyBold = firstFont({ "GothamBold", "Gotham", "SourceSansBold", "ArialBold" }, Enum.Font.SourceSansBold),
}

-- "Release, v1.4" is set in an italic serif in the reference. FontFace is
-- guarded because not every executor exposes Font.new.
do
	local ok, face = pcall(function()
		return Font.new(
			"rbxasset://fonts/families/Garamond.json",
			Enum.FontWeight.Regular,
			Enum.FontStyle.Italic
		)
	end)
	if ok and face ~= nil then
		Theme.Font.serifItalic = face
	else
		Theme.Font.serifItalic = firstFont({ "Garamond", "Bodoni", "Merriweather", "Antique" }, Theme.Font.body)
	end
end

return Theme
