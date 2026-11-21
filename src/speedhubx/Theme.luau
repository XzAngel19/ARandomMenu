--!nocheck
--[[
    Speed Hub X — Theme
    ====================
    Central palette / metric table for the whole interface.
    Every colour, font and size used by the menu lives here so the
    visual language can be re-tuned from one file.

    Values were sampled from the reference screenshot (1920x1017)
    of "Speed Hub X | Version: 3.7.0".
]]

local Theme = {}

Theme.Version = "3.7.0"
Theme.Title = "Speed Hub X | Version: 3.7.0"
Theme.WindowName = "SpeedHubX"

Theme.Colors = {
    -- Window chrome
    WindowBackground = Color3.fromRGB(13, 13, 13),      -- near-black panel
    WindowShadow     = Color3.fromRGB(0, 0, 0),

    -- Sidebar / rows
    RowBackground    = Color3.fromRGB(30, 30, 30),      -- #1E1E1E rows & inactive nav
    RowBackgroundAlt = Color3.fromRGB(40, 40, 40),      -- #282828 dropdown value pill
    RowHover         = Color3.fromRGB(36, 36, 36),      -- subtle hover lift

    -- Text
    TextPrimary      = Color3.fromRGB(241, 241, 241),   -- row titles, headers
    TextSecondary    = Color3.fromRGB(140, 140, 140),   -- subtitles / BETA tags
    TextDim          = Color3.fromRGB(154, 154, 154),   -- nav separator bar
    TextTitle        = Color3.fromRGB(242, 242, 242),   -- title bar label

    -- Accent red (active nav, ON switches, logo, strip)
    AccentTop        = Color3.fromRGB(205, 43, 43),     -- active nav gradient top
    AccentMid        = Color3.fromRGB(176, 26, 26),
    AccentBottom     = Color3.fromRGB(143, 14, 14),     -- active nav gradient bottom
    AccentBright     = Color3.fromRGB(229, 29, 29),     -- toggle knob / dots
    AccentGlowTop    = Color3.fromRGB(255, 64, 64),
    AccentGlowBottom = Color3.fromRGB(196, 15, 15),

    -- Right-edge accent strip
    StripTop         = Color3.fromRGB(69, 8, 8),
    StripMid         = Color3.fromRGB(90, 10, 13),
    StripBottom      = Color3.fromRGB(154, 18, 18),

    -- Toggle tracks / knobs
    ToggleTrackOn    = Color3.fromRGB(38, 38, 38),
    ToggleTrackOff   = Color3.fromRGB(35, 35, 35),
    ToggleKnobOff    = Color3.fromRGB(47, 47, 47),

    -- Chrome extras
    ChromeBlack      = Color3.fromRGB(5, 5, 5),         -- "Supa Tech V2" pill
    LogoBackground   = Color3.fromRGB(10, 10, 10),      -- floating "S" tile
    LogoStroke       = Color3.fromRGB(63, 5, 5),
    WatermarkBarA    = Color3.fromRGB(126, 120, 124),   -- "CAN YOU EVEN SEE ME?" bar
    WatermarkBarB    = Color3.fromRGB(74, 70, 74),
    White            = Color3.fromRGB(255, 255, 255),

    -- Home page status dot
    StatusOff        = Color3.fromRGB(229, 29, 29),
}

Theme.Fonts = {
    Title    = Enum.Font.GothamMedium,  -- window title bar
    Header   = Enum.Font.GothamBold,    -- "Skill" / "Aim" / "Body"
    RowTitle = Enum.Font.GothamBold,    -- row titles ("Auto Ultimate" ...)
    Body     = Enum.Font.Gotham,        -- subtitles, nav labels
    NavLabel = Enum.Font.Gotham,        -- sidebar labels
    Pill     = Enum.Font.GothamBold,    -- dropdown value + watermark
    Black    = Enum.Font.GothamBlack,   -- logo "S", watermark
}

-- Design-space metrics (reference screenshot is 1920x1017, window is 1234x791).
Theme.Metrics = {
    WindowWidth      = 1234,
    WindowHeight     = 791,
    WindowCorner     = 14,
    WindowPosition   = UDim2.new(0.5, 0, 0.4625, 0), -- slightly above centre
    WindowAnchor     = Vector2.new(0.5, 0.5),

    TitleBarHeight   = 64,
    TitlePaddingLeft = 22,
    TitleTextSize    = 20,
    CloseButtonSize  = 40,
    CloseGlyphSize   = 17,

    AccentStripWidth = 3,

    SidebarX         = 26,
    SidebarY         = 88,
    SidebarWidth     = 314,
    NavHeight        = 54,
    NavPitch         = 66,
    NavIconSize      = 23,
    NavIconX         = 22,
    NavSeparatorX    = 62,
    NavLabelX        = 82,
    NavCorner        = 11,
    NavTextSize      = 17,

    ContentX         = 386,
    ContentY         = 88,
    ContentRightPad  = 22,
    ContentBottomPad = 16,

    HeaderTextSize   = 22,
    HeaderHeight     = 30,

    RowHeight        = 66,
    RowCorner        = 12,
    RowTitleSize     = 18,
    RowSubtitleSize  = 13,
    RowTextX         = 22,
    RowTitleY        = 10,
    RowSubtitleY     = 36,

    ToggleTrackSize  = 46,
    ToggleTrackCorner= 12,
    ToggleKnobOnSize = 24,
    ToggleKnobOffSize= 27,
    ToggleKnobOffCorner = 9,
    ToggleRightPad   = 20,

    PillWidth        = 330,
    PillHeight       = 42,
    PillCorner       = 9,
    PillTextSize     = 20,
    PillRightPad     = 14,
    ChevronSize      = 17,
    ChevronGap       = 26,

    OptionsRowHeight = 44,

    LogoSize         = 78,
    LogoCorner       = 15,
    LogoPosition     = UDim2.new(0, 268, 0, 176),

    SupaPillSize     = UDim2.new(0, 168, 0, 26),
    SupaPillPosition = UDim2.new(0, 18, 0, 66),
    SupaPillTextSize = 14,

    WatermarkWidth   = 352,
    WatermarkHeight  = 26,
    WatermarkPosition= UDim2.new(0.5, 0, 0.943, 0),
    WatermarkTextSize= 17,

    DesignWidth      = 1920,
    DesignHeight     = 1017,
}

return Theme
