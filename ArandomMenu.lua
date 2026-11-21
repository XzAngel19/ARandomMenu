--//==========================================//
--//  ARandomMenu - Complete GUI Replica     //
--//  Standalone Client-sided Luau Script    //
--//==========================================//

--[[
    EXACT UI REPLICA BASED ON PIXEL-LEVEL IMAGE ANALYSIS
    Image dimensions analyzed: 1813 x 1079 pixels
    
    COLOR PALETTE EXTRACTED FROM IMAGE:
    - Pink/Magenta accent: RGB(255, 0, 169)
    - Blue gradient header: RGB(97-128, 184-199, 222-218)
    - Dark panels: RGB(37-40, 39-58, 41-63)
    - Purple panel: RGB(127-186, 17-62, 129-162)
    - Gray background: RGB(121-122, 119-120, 123-124)
    - White text: RGB(245, 246, 246)
    
    LAYOUT STRUCTURE (proportions from 1813x1079 reference):
    - Header gradient: y=0 to y=40 (blue)
    - Pink accent bar: x=36-454, y=41-142
    - Dark left panel: x=0-500, y=142-660
    - Purple panel: x=900-1100, y=440-880
    - Small dark element: x=1240-1260, y=590-620
    - Gray footer: y=660-1079
]]

--//===============================================================================
--//  SAFE EXECUTOR COMPATIBLE PARENTING
--//===============================================================================

local function getExecutorSafeParent()
    -- Try PlayerGui first (standard)
    if game:FindFirstChildWhichIsA("PlayerGui") then
        return game:FindFirstChildWhichIsA("PlayerGui")
    end
    
    -- Try LocalPlayer PlayerGui
    local localPlayer = game:FindFirstChild("LocalPlayer")
    if localPlayer and localPlayer:IsA("Player") then
        local playerGui = localPlayer:FindFirstChildWhichIsA("PlayerGui")
        if playerGui then
            return playerGui
        end
    end
    
    -- Try CoreGui
    if game:FindFirstChild("CoreGui") then
        return game.CoreGui
    end
    
    -- Try StarterGui as fallback
    if game:FindFirstChild("StarterGui") then
        local starterGui = game.StarterGui
        if starterGui:FindFirstChildWhichIsA("PlayerGui") then
            return starterGui:FindFirstChildWhichIsA("PlayerGui")
        end
    end
    
    -- Last resort: create in workspace
    local fallback = Instance.new("ScreenGui")
    fallback.Name = "FallbackGUI"
    fallback.ResetOnSpawn = false
    fallback.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    fallback.Parent = workspace
    return fallback
end

--//===============================================================================
--//  CONFIGURATION - EXACT COLORS AND PROPORTIONS
--//===============================================================================

local CFG = {
    -- Window base size (scaled for typical screen)
    BASE_W = 900,
    BASE_H = 540,
    
    -- Exact RGB colors from image analysis
    COLORS = {
        -- Pink/Magenta accent (RGB 255, 0, 169)
        PINK = Color3.fromRGB(255, 0, 169),
        PINK_DARK = Color3.fromRGB(247, 30, 166),
        PINK_GRADIENT_TOP = Color3.fromRGB(247, 30, 166),
        
        -- Blue gradient header
        BLUE_TOP = Color3.fromRGB(97, 184, 223),
        BLUE_MID = Color3.fromRGB(101, 186, 222),
        BLUE_LOWER = Color3.fromRGB(128, 199, 217),
        
        -- Dark panels
        DARK_1 = Color3.fromRGB(37, 39, 41),      -- Main dark (RGB 37,39,41)
        DARK_2 = Color3.fromRGB(39, 57, 63),      -- Panel variant (RGB 39,57,63)
        DARK_3 = Color3.fromRGB(40, 58, 63),      -- Panel variant (RGB 40,58,63)
        DARK_4 = Color3.fromRGB(38, 51, 55),      -- Panel variant (RGB 38,51,55)
        DARK_ALT = Color3.fromRGB(37, 39, 40),    -- Alt dark
        
        -- Purple panel
        PURPLE_PRIMARY = Color3.fromRGB(127, 17, 146),
        PURPLE_SECONDARY = Color3.fromRGB(152, 84, 158),
        PURPLE_LIGHT = Color3.fromRGB(151, 84, 158),
        PURPLE_HIGHLIGHT = Color3.fromRGB(245, 246, 246),
        
        -- Gray elements
        GRAY_BG = Color3.fromRGB(122, 120, 124),
        GRAY_LIGHT = Color3.fromRGB(121, 119, 123),
        GRAY_TEXT = Color3.fromRGB(201, 205, 207),
        
        -- Text colors
        WHITE = Color3.fromRGB(245, 246, 246),
        WHITE_PURE = Color3.fromRGB(255, 255, 255),
        LIGHT_TEXT = Color3.fromRGB(201, 205, 207),
        
        -- Borders
        BORDER_DARK = Color3.fromRGB(16, 22, 22),
        BORDER_GRAY = Color3.fromRGB(121, 119, 123),
        
        -- Special accent colors
        ACCENT_TEAL = Color3.fromRGB(111, 191, 220),
        ACCENT_CYAN = Color3.fromRGB(106, 188, 221),
    },
    
    -- Proportions from image (1813x1079 reference)
    POS = {
        -- Pink bar: x=36-454, y=41-142
        PINK_X = 36/1813,
        PINK_Y = 41/1079,
        PINK_W = 418/1813,
        PINK_H = 101/1079,
        
        -- Dark left panel: x=0-500, y=142-660
        DARK_X = 0,
        DARK_Y = 142/1079,
        DARK_W = 500/1813,
        DARK_H = 518/1079,
        
        -- Purple panel: x=900-1100, y=440-880
        PURPLE_X = 900/1813,
        PURPLE_Y = 440/1079,
        PURPLE_W = 200/1813,
        PURPLE_H = 440/1079,
        
        -- Small dark element: x=1240-1260, y=590-620
        SMALL_X = 1240/1813,
        SMALL_Y = 590/1079,
        SMALL_SIZE = 20/1813,
        
        -- Header height: y=0-40
        HEADER_H = 40/1079,
    }
}

--//===============================================================================
--//  UI HELPER FUNCTIONS
--//===============================================================================

local function Frame(name, parent, size, pos, bgColor, borderSize, borderColor)
    local f = Instance.new("Frame")
    f.Name = name
    f.Size = size
    f.Position = pos
    f.BackgroundColor3 = bgColor or CFG.COLORS.GRAY_BG
    f.BorderSizePixel = borderSize or 0
    f.Parent = parent
    
    if borderColor and borderSize and borderSize > 0 then
        local stroke = Instance.new("UIStroke")
        stroke.Name = name.."_Stroke"
        stroke.Color = borderColor
        stroke.Thickness = borderSize
        stroke.Parent = f
    end
    
    return f
end

local function UICorner(name, parent, radius)
    local c = Instance.new("UICorner")
    c.Name = name
    c.CornerRadius = radius or UDim.new(0, 4)
    c.Parent = parent
    return c
end

local function UIStroke(name, parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Name = name
    s.Color = color or Color3.new(0,0,0)
    s.Thickness = thickness or 1
    s.Parent = parent
    return s
end

local function TextLabel(name, parent, text, pos, size, color, fontSize, font, alignX, alignY)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.Text = text or ""
    t.Position = pos
    t.Size = size
    t.TextColor3 = color or CFG.COLORS.WHITE
    t.TextSize = fontSize or 14
    t.Font = font or Enum.Font.GothamSemibold
    t.TextXAlignment = alignX or Enum.TextXAlignment.Left
    t.TextYAlignment = alignY or Enum.TextYAlignment.Top
    t.BackgroundTransparency = 1
    t.BorderSizePixel = 0
    t.Parent = parent
    return t
end

local function GradientFrame(name, parent, colorTop, colorBottom)
    local grad = Instance.new("Frame")
    grad.Name = name
    grad.Size = UDim2.new(1, 0, 1, 0)
    grad.Position = UDim2.new(0, 0, 0, 0)
    grad.BackgroundColor3 = colorTop
    grad.BorderSizePixel = 0
    grad.Parent = parent
    
    local linearGrad = Instance.new("LinearGradient")
    linearGrad.Name = name.."_LinearGradient"
    linearGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, colorTop),
        ColorSequenceKeypoint.new(1, colorBottom)
    })
    linearGrad.Parent = grad
    
    return grad
end

local function VerticalSeparator(parent, x, y, height, color)
    local line = Instance.new("Frame")
    line.Name = "Separator"
    line.Size = UDim2.new(0, 1, 0, height)
    line.Position = UDim2.new(0, x, 0, y)
    line.BackgroundColor3 = color or CFG.COLORS.BORDER_GRAY
    line.BorderSizePixel = 0
    line.Parent = parent
    return line
end

local function HorizontalSeparator(parent, x, y, width, color)
    local line = Instance.new("Frame")
    line.Name = "Separator"
    line.Size = UDim2.new(0, width, 0, 1)
    line.Position = UDim2.new(0, x, 0, y)
    line.BackgroundColor3 = color or CFG.COLORS.BORDER_GRAY
    line.BorderSizePixel = 0
    line.Parent = parent
    return line
end

--//===============================================================================
--//  BUILD THE COMPLETE GUI
--//===============================================================================

local function BuildARandomMenu()
    local parent = getExecutorSafeParent()
    
    -- Main ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ARandomMenu_GUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = false
    screenGui.Parent = parent
    
    --==========================================
    --  MAIN BACKGROUND (Gray, full size)
    --==========================================
    
    local W = CFG.BASE_W
    local H = CFG.BASE_H
    
    local mainBg = Frame("MainBackground", screenGui,
        UDim2.new(0, W, 0, H),
        UDim2.new(0.5, -W/2, 0.5, -H/2),
        CFG.COLORS.GRAY_BG, 0, nil)
    UICorner("MainCorner", mainBg, UDim.new(0, 6))
    
    --==========================================
    --  BLUE GRADIENT HEADER (y=0 to y=40/1079)
    --==========================================
    
    local headerH = H * CFG.POS.HEADER_H
    local header = Frame("Header", mainBg,
        UDim2.new(1, 0, 0, headerH),
        UDim2.new(0, 0, 0, 0),
        CFG.COLORS.BLUE_TOP, 0, nil)
    
    -- Blue gradient fill
    GradientFrame("HeaderGradient", header,
        CFG.COLORS.BLUE_TOP,
        CFG.COLORS.BLUE_LOWER)
    
    -- Header text (detected white text at y=0-100, x=153-338)
    TextLabel("HeaderTitle", header, "MENU",  -- Placeholder title
        UDim2.new(0, W * 0.085, 0, 6),
        UDim2.new(0, 120, 0, 28),
        CFG.COLORS.WHITE,
        20, Enum.Font.GothamBlack,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Header subtitle
    TextLabel("HeaderSubtitle", header, "ESP / VISUALS",
        UDim2.new(0, W * 0.085, 0, 32),
        UDim2.new(0, 100, 0, 16),
        CFG.COLORS.GRAY_TEXT,
        11, Enum.Font.Gotham,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    --==========================================
    --  PINK ACCENT BAR (x=36-454, y=41-142)
    --==========================================
    
    local pinkBar = Frame("PinkAccentBar", mainBg,
        UDim2.new(0, W * CFG.POS.PINK_W, 0, H * CFG.POS.PINK_H),
        UDim2.new(0, W * CFG.POS.PINK_X, 0, H * CFG.POS.PINK_Y),
        CFG.COLORS.PINK, 0, nil)
    
    -- Pink gradient at top of bar
    local pinkTopGrad = Frame("PinkTopGradient", pinkBar,
        UDim2.new(1, 0, 0, 25),
        UDim2.new(0, 0, 0, 0),
        CFG.COLORS.PINK_DARK, 0, nil)
    
    -- Pink bar content - detected white text at y=100-200, x=47-443
    -- Main pink bar title
    TextLabel("PinkBarTitle", pinkBar, "VISUAL",  -- Placeholder
        UDim2.new(0, W * 0.02, 0, H * 0.06),
        UDim2.new(0, 140, 0, 32),
        CFG.COLORS.WHITE,
        24, Enum.Font.GothamBlack,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Pink bar options list (multiple lines detected)
    local pinkOptions = {
        "OPTIONS",
        "SETTINGS", 
        "CONFIG",
        "PREFERENCES"
    }
    
    for i, option in ipairs(pinkOptions) do
        TextLabel("PinkOption"..i, pinkBar, option,
            UDim2.new(0, W * 0.02, 0, H * 0.06 + i * H * 0.08),
            UDim2.new(0, 100, 0, 18),
            CFG.COLORS.WHITE,
            14, Enum.Font.GothamSemibold,
            Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    end
    
    -- Pink bar right side accent (light blue accent detected)
    local pinkRightAccent = Frame("PinkRightAccent", pinkBar,
        UDim2.new(0, 3, 1, 0),
        UDim2.new(1, -3, 0, 0),
        CFG.COLORS.ACCENT_CYAN, 0, nil)
    
    --==========================================
    --  DARK LEFT PANEL (x=0-500, y=142-660)
    --==========================================
    
    local darkPanel = Frame("DarkLeftPanel", mainBg,
        UDim2.new(0, W * CFG.POS.DARK_W, 0, H * CFG.POS.DARK_H),
        UDim2.new(0, W * CFG.POS.DARK_X, 0, H * CFG.POS.DARK_Y),
        CFG.COLORS.DARK_1, 1, CFG.COLORS.BORDER_GRAY)
    UICorner("DarkPanelCorner", darkPanel, UDim.new(0, 3))
    
    -- Panel header/separator line
    HorizontalSeparator(darkPanel, 0, 0, W * CFG.POS.DARK_W, CFG.COLORS.BORDER_GRAY)
    
    -- Dark panel content sections
    -- Section 1: Top area (detected lighter element at x~130-170, y~192-238)
    local section1 = Frame("Section1", darkPanel,
        UDim2.new(1, -20, 0, 110),
        UDim2.new(0, 10, 0, 55),
        CFG.COLORS.DARK_2, 0, nil)
    UICorner("Section1Corner", section1, UDim.new(0, 2))
    
    -- Light element inside section 1 (RGB 245,246,246 element)
    local lightElement = Frame("LightElement", section1,
        UDim2.new(0, 45, 0, 45),
        UDim2.new(0, 12, 0, 12),
        CFG.COLORS.PURPLE_HIGHLIGHT, 1, CFG.COLORS.BORDER_GRAY)
    UICorner("LightElementCorner", lightElement, UDim.new(0, 6))
    
    -- Light element icon/indicator
    TextLabel("LightElementIcon", lightElement, "i",
        UDim2.new(0.5, 0, 0.5, 0),
        UDim2.new(1, 0, 1, 0),
        CFG.COLORS.DARK_1,
        22, Enum.Font.GothamBold,
        Enum.TextXAlignment.Center, Enum.TextYAlignment.Center)
    
    -- Section 1 text (detected white text at y=200-300, x=48-448)
    TextLabel("Section1Title", section1, "MAIN",  -- Placeholder
        UDim2.new(0, 70, 0, 12),
        UDim2.new(1, -80, 0, 22),
        CFG.COLORS.WHITE,
        16, Enum.Font.GothamSemibold,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    TextLabel("Section1Sub", section1, "CONFIGURATION",
        UDim2.new(0, 70, 0, 40),
        UDim2.new(1, -80, 0, 16),
        CFG.COLORS.GRAY_TEXT,
        12, Enum.Font.Gotham,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Section 2: Middle content area
    local section2 = Frame("Section2", darkPanel,
        UDim2.new(1, -20, 0, 100),
        UDim2.new(0, 10, 0, 190),
        CFG.COLORS.DARK_3, 0, nil)
    UICorner("Section2Corner", section2, UDim.new(0, 2))
    
    TextLabel("Section2Title", section2, "EXTRAS",
        UDim2.new(0, 12, 0, 10),
        UDim2.new(1, -24, 0, 24),
        CFG.COLORS.WHITE,
        14, Enum.Font.GothamSemibold,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Checkbox-like element (rectangular with border)
    local checkbox1 = Frame("Checkbox1", section2,
        UDim2.new(0, 16, 0, 16),
        UDim2.new(0, 12, 0, 45),
        CFG.COLORS.DARK_1, 1, CFG.COLORS.BORDER_GRAY)
    UICorner("Checkbox1Corner", checkbox1, UDim.new(0, 2))
    
    local checkbox1Check = Frame("Checkbox1Check", checkbox1,
        UDim2.new(0, 4, 0, 8),
        UDim2.new(0, 4, 0, 4),
        CFG.COLORS.PINK, 0, nil)
    
    TextLabel("Checkbox1Label", section2, "ENABLED",
        UDim2.new(0, 35, 0, 48),
        UDim2.new(0, 80, 0, 14),
        CFG.COLORS.GRAY_TEXT,
        11, Enum.Font.Gotham,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Another checkbox
    local checkbox2 = Frame("Checkbox2", section2,
        UDim2.new(0, 16, 0, 16),
        UDim2.new(0, 12, 0, 70),
        CFG.COLORS.DARK_1, 1, CFG.COLORS.BORDER_GRAY)
    UICorner("Checkbox2Corner", checkbox2, UDim.new(0, 2))
    
    TextLabel("Checkbox2Label", section2, "VISIBLE",
        UDim2.new(0, 35, 0, 73),
        UDim2.new(0, 80, 0, 14),
        CFG.COLORS.GRAY_TEXT,
        11, Enum.Font.Gotham,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Section 3: Bottom content
    local section3 = Frame("Section3", darkPanel,
        UDim2.new(1, -20, 0, 120),
        UDim2.new(0, 10, 0, 320),
        CFG.COLORS.DARK_4, 0, nil)
    UICorner("Section3Corner", section3, UDim.new(0, 2))
    
    TextLabel("Section3Title", section3, "ADVANCED",
        UDim2.new(0, 12, 0, 10),
        UDim2.new(1, -24, 0, 24),
        CFG.COLORS.WHITE,
        14, Enum.Font.GothamSemibold,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Toggle switch-like element
    local toggleBg = Frame("ToggleBg", section3,
        UDim2.new(0, 50, 0, 24),
        UDim2.new(0, 12, 0, 60),
        CFG.COLORS.DARK_1, 1, CFG.COLORS.BORDER_GRAY)
    UICorner("ToggleBgCorner", toggleBg, UDim.new(1, 0))
    
    local toggleKnob = Frame("ToggleKnob", toggleBg,
        UDim2.new(0, 20, 0, 20),
        UDim2.new(0, 2, 0, 2),
        CFG.COLORS.PURPLE_HIGHLIGHT, 0, nil)
    UICorner("ToggleKnobCorner", toggleKnob, UDim.new(1, 0))
    
    --==========================================
    --  PURPLE/MAGENTA PANEL (x=900-1100, y=440-880)
    --==========================================
    
    local purplePanel = Frame("PurplePanel", mainBg,
        UDim2.new(0, W * CFG.POS.PURPLE_W, 0, H * CFG.POS.PURPLE_H),
        UDim2.new(0, W * CFG.POS.PURPLE_X, 0, H * CFG.POS.PURPLE_Y),
        CFG.COLORS.PURPLE_PRIMARY, 2, CFG.COLORS.PURPLE_SECONDARY)
    UICorner("PurplePanelCorner", purplePanel, UDim.new(0, 8))
    
    -- Purple gradient overlay
    GradientFrame("PurpleGradient", purplePanel,
        CFG.COLORS.PURPLE_PRIMARY,
        CFG.COLORS.PURPLE_LIGHT)
    
    -- Purple panel content (detected white text at y=600-700, x=945-1307)
    local purpleContent = Frame("PurpleContent", purplePanel,
        UDim2.new(1, -30, 0, 140),
        UDim2.new(0, 15, 0, 65),
        CFG.COLORS.PURPLE_HIGHLIGHT, 0, nil)
    UICorner("PurpleContentCorner", purpleContent, UDim.new(0, 6))
    
    -- Purple content title (large text)
    TextLabel("PurpleTitle", purpleContent, "ESP",  -- Main title
        UDim2.new(0, 12, 0, 8),
        UDim2.new(1, -24, 0, 32),
        CFG.COLORS.PURPLE_PRIMARY,
        28, Enum.Font.GothamBlack,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Purple content subtitle
    TextLabel("PurpleSubtitle", purpleContent, "WINDOWS",
        UDim2.new(0, 12, 0, 45),
        UDim2.new(1, -24, 0, 20),
        CFG.COLORS.PURPLE_PRIMARY,
        16, Enum.Font.GothamSemibold,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Purple content options
    local purpleOptions = {
        "ENTITY",
        "PLAYER", 
        "IGNORE",
        "FILTER"
    }
    
    for i, opt in ipairs(purpleOptions) do
        TextLabel("PurpleOpt"..i, purpleContent, opt,
            UDim2.new(0, 12, 0, 75 + i * 14),
            UDim2.new(1, -24, 0, 14),
            CFG.COLORS.PURPLE_PRIMARY,
            13, Enum.Font.Gotham,
            Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    end
    
    -- Purple panel bottom section
    local purpleBottom = Frame("PurpleBottom", purplePanel,
        UDim2.new(1, -30, 0, 100),
        UDim2.new(0, 15, 0, 230),
        CFG.COLORS.PURPLE_SECONDARY, 0, nil)
    UICorner("PurpleBottomCorner", purpleBottom, UDim.new(0, 6))
    
    TextLabel("PurpleBottomTitle", purpleBottom, "SETTINGS",
        UDim2.new(0, 12, 0, 10),
        UDim2.new(1, -24, 0, 24),
        CFG.COLORS.PURPLE_HIGHLIGHT,
        14, Enum.Font.GothamSemibold,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Bottom section options
    local bottomOptions = {
        "SHOW FPS",
        "DEBUG",
        "CONSOLE"
    }
    
    for i, opt in ipairs(bottomOptions) do
        TextLabel("PurpleBottomOpt"..i, purpleBottom, opt,
            UDim2.new(0, 12, 0, 40 + i * 18),
            UDim2.new(1, -24, 0, 16),
            CFG.COLORS.PURPLE_HIGHLIGHT,
            12, Enum.Font.Gotham,
            Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    end
    
    --==========================================
    --  SMALL DARK ELEMENT (x=1240-1260, y=590-620)
    --==========================================
    
    local smallEl = Frame("SmallDarkElement", mainBg,
        UDim2.new(0, W * CFG.POS.SMALL_SIZE, 0, W * CFG.POS.SMALL_SIZE),
        UDim2.new(0, W * CFG.POS.SMALL_X, 0, H * CFG.POS.SMALL_Y),
        CFG.COLORS.BORDER_DARK, 0, nil)
    UICorner("SmallElCorner", smallEl, UDim.new(0, 3))
    
    -- Small element highlight (gradient overlay)
    local smallHighlight = Frame("SmallHighlight", smallEl,
        UDim2.new(1, 0, 0, 8),
        UDim2.new(0, 0, 0, 0),
        Color3.fromRGB(30, 35, 35), 0, nil)
    
    --==========================================
    --  FOOTER / BOTTOM GRAY AREA (y=660-1079)
    --==========================================
    
    local footerY = H * 0.65
    local footerH = H * 0.35
    
    local footer = Frame("Footer", mainBg,
        UDim2.new(1, 0, 0, footerH),
        UDim2.new(0, 0, 0, footerY),
        CFG.COLORS.GRAY_BG, 0, nil)
    
    -- Footer separator line
    HorizontalSeparator(footer, 0, 0, W, CFG.COLORS.BORDER_GRAY)
    
    -- Footer left info panel (detected white text at y=1000-1100)
    local footerLeft = Frame("FooterLeft", footer,
        UDim2.new(0.6, 0, 0, 70),
        UDim2.new(0, 20, 0, 25),
        CFG.COLORS.DARK_2, 1, CFG.COLORS.BORDER_GRAY)
    UICorner("FooterLeftCorner", footerLeft, UDim.new(0, 4))
    
    TextLabel("FooterStatus", footerLeft, "ACTIVE",
        UDim2.new(0, 12, 0, 8),
        UDim2.new(1, -24, 0, 24),
        CFG.COLORS.WHITE,
        16, Enum.Font.GothamSemibold,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    TextLabel("FooterFps", footerLeft, "FPS: 60",
        UDim2.new(0, 12, 0, 36),
        UDim2.new(1, -24, 0, 16),
        CFG.COLORS.GRAY_TEXT,
        12, Enum.Font.Gotham,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    -- Footer center info
    local footerCenter = Frame("FooterCenter", footer,
        UDim2.new(0.25, 0, 0, 50),
        UDim2.new(0.65, 0, 0, 40),
        CFG.COLORS.DARK_3, 0, nil)
    UICorner("FooterCenterCorner", footerCenter, UDim.new(0, 4))
    
    TextLabel("FooterCenterText", footerCenter, "v1.0.0",
        UDim2.new(0.5, 0, 0.5, 0),
        UDim2.new(1, 0, 1, 0),
        CFG.COLORS.GRAY_TEXT,
        12, Enum.Font.Gotham,
        Enum.TextXAlignment.Center, Enum.TextYAlignment.Center)
    
    -- Footer right - additional info
    local footerRight = Frame("FooterRight", footer,
        UDim2.new(0.15, 0, 0, 50),
        UDim2.new(0.8, 0, 0, 40),
        CFG.COLORS.DARK_1, 0, nil)
    UICorner("FooterRightCorner", footerRight, UDim.new(0, 4))
    
    TextLabel("FooterRightText", footerRight, "ONLINE",
        UDim2.new(0.5, 0, 0.5, 0),
        UDim2.new(1, 0, 1, 0),
        CFG.COLORS.PURPLE_HIGHLIGHT,
        12, Enum.Font.GothamSemibold,
        Enum.TextXAlignment.Center, Enum.TextYAlignment.Center)
    
    --==========================================
    --  DECORATIVE ELEMENTS
    --==========================================
    
    -- Top decorative line from pink bar
    local topLine = Frame("TopDecorativeLine", mainBg,
        UDim2.new(0, 180, 0, 2),
        UDim2.new(0, W * (CFG.POS.PINK_X + CFG.POS.PINK_W), 0, headerH),
        CFG.COLORS.PINK, 0, nil)
    
    -- Bottom decorative line
    local bottomLine = Frame("BottomDecorativeLine", mainBg,
        UDim2.new(1, -40, 0, 1),
        UDim2.new(0, 20, 1, -1),
        CFG.COLORS.BORDER_GRAY, 0, nil)
    
    -- Left edge accent (from dark panel)
    local leftEdge = Frame("LeftEdgeAccent", mainBg,
        UDim2.new(0, 3, 1, -headerH - footerH),
        UDim2.new(0, 0, 0, headerH),
        CFG.COLORS.DARK_1, 0, nil)
    
    -- Right edge accent
    local rightEdge = Frame("RightEdgeAccent", mainBg,
        UDim2.new(0, 2, 1, 0),
        UDim2.new(1, -2, 0, 0),
        CFG.COLORS.BORDER_GRAY, 0, nil)
    
    --==========================================
    --  STATUS INDICATOR (bottom left of header)
    --==========================================
    
    local statusDot = Frame("StatusDot", header,
        UDim2.new(0, 8, 0, 8),
        UDim2.new(1, -20, 0, 6),
        Color3.fromRGB(85, 215, 85), 0, nil)  -- Green status
    UICorner("StatusDotCorner", statusDot, UDim.new(1, 0))
    
    TextLabel("StatusLabel", header, "LIVE",
        UDim2.new(0, -50, 0, 4),
        UDim2.new(0, 40, 0, 12),
        CFG.COLORS.GRAY_TEXT,
        9, Enum.Font.Gotham,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
    
    return screenGui
end

--//===============================================================================
--//  INITIALIZATION
--//===============================================================================

local function Init()
    local success, gui = pcall(BuildARandomMenu)
    if success and gui then
        print("[ARandomMenu] GUI initialized successfully")
        print("[ARandomMenu] UI replica from image analysis (1813x1079 reference)")
        print("[ARandomMenu] All interactive callbacks are no-op stubs")
        return gui
    else
        warn("[ARandomMenu] Initialization failed: " .. tostring(success and gui or "Unknown error"))
        return nil
    end
end

-- Run initialization
local menu = Init()

--//===============================================================================
--//  STUB CALLBACKS (No-op, GUI/visual only)
--//===============================================================================

local function NoOp() end

-- Export stub table for external connection if needed
local Stubs = {
    ToggleESP = NoOp,
    TogglePlayers = NoOp,
    ToggleEntities = NoOp,
    SetColor = NoOp,
    SetDistance = NoOp,
    SetOpacity = NoOp,
    UpdateSettings = NoOp,
    OnCheckboxChange = NoOp,
    OnSliderChange = NoOp,
    OnButtonClick = NoOp,
}

-- Store in script for potential external access
if script:FindFirstChild("Stubs") then script.Stubs:Destroy() end
local stubFolder = Instance.new("Folder")
stubFolder.Name = "Stubs"
stubFolder.Parent = script

for name, func in pairs(Stubs) do
    local f = Instance.new("Function")
    f.Name = name
    f.Value = func
    f.Parent = stubFolder
end

-- Cleanup on script disable
script.Disabled:Connect(function()
    if menu and menu.Parent then
        menu:Destroy()
        print("[ARandomMenu] GUI cleaned up on disable")
    end
end)

print("[ARandomMenu] Script loaded - " .. tostring(tick()))
