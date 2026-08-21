--!strict
--
-- The screen furniture: everything Wurst draws on the HUD that is neither a
-- window nor a row. Today that is the wordmark — Wurst's own logo with the
-- version next to it, top-left, on the white chip Wurst gives it — and the
-- stats block under it (FPS, ping, session time, place).
--
-- All of it lives on the same layer as the windows so the one UIScale the
-- ClickGUI installs moves the whole interface together, and all of it stays
-- on screen while the ClickGUI is closed: in Wurst these are HUD elements
-- (WurstLogo's Visibility default is Always), not chrome that belongs to the
-- GUI screen. The only thing a player should lose by closing the menu is the
-- windows.

local Module = {
    Name = "Furniture",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Wurst's own defaults for the logo chip: WurstLogo.Background #FFFFFF,
-- WurstLogo.Text #000000. Deliberately not theme tokens — the chip is white
-- in every Wurst screenshot regardless of palette, which is what makes the
-- sausage readable on any background.
local WURSTLOGO_BACKGROUND: Color3 = Color3.fromRGB(255, 255, 255)
local WURSTLOGO_TEXT: Color3 = Color3.fromRGB(0, 0, 0)

-- The prototype's #brand block: 14 px from the left edge, 10 from the top,
-- stats 8 px under the wordmark.
local FURNITURE_MARGIN_X: number = 14
local FURNITURE_MARGIN_Y: number = 10
local STATS_GAP: number = 8

-- wurst_128.png is 505×128; at the chip's 22 px it renders 87 px wide.
local LOGO_HEIGHT: number = 22
local LOGO_WIDTH: number = 87

local STATS_FONT_SIZE: number = 11
local STATS_LINE_HEIGHT: number = 17

function Module.init(context: any): any
    local host: any = context
    local state: any = host.state
    local create: any = host.create
    local PRODUCT: any = host.PRODUCT
    local Theme: any = host.Theme
    local ThemeEngine: any = host.ThemeEngine
    local TaskManager: any = host.TaskManager
    local PopupLayer: any = host.PopupLayer
    local Stats: any = host.Stats
    local TITLE_FONT: any = host.TITLE_FONT

    local Furniture: any = {
        handles = {} :: {any},
    }

    -- ------------------------------------------------------------- wordmark
    -- Wurst's WurstLogo feature: the sausage and the version on a white chip.
    -- Until the image resolves (or on an executor without getcustomasset) the
    -- chip carries the product name as text, so the corner is never blank.
    local chip: Frame = (create("Frame", {
        Parent = PopupLayer,
        Name = "WurstLogo",
        Active = false,
        BackgroundColor3 = WURSTLOGO_BACKGROUND,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(FURNITURE_MARGIN_X, FURNITURE_MARGIN_Y),
        Size = UDim2.fromOffset(LOGO_WIDTH + 46, LOGO_HEIGHT + 8),
        ZIndex = 20,
    }) :: any) :: Frame

    local logoImage: ImageLabel = (create("ImageLabel", {
        Parent = chip,
        Name = "Logo",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        Position = UDim2.fromOffset(4, 4),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.fromOffset(LOGO_WIDTH, LOGO_HEIGHT),
        Visible = false,
        ZIndex = 21,
    }) :: any) :: ImageLabel

    local logoFallback: TextLabel = (create("TextLabel", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = chip,
        Name = "LogoFallback",
        BackgroundTransparency = 1,
        FontFace = TITLE_FONT,
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(LOGO_WIDTH, LOGO_HEIGHT),
        Text = string.upper(tostring(PRODUCT.name)),
        TextColor3 = WURSTLOGO_TEXT,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21,
    }) :: any) :: TextLabel

    create("TextLabel", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = chip,
        Name = "Version",
        BackgroundTransparency = 1,
        FontFace = TITLE_FONT,
        Position = UDim2.fromOffset(LOGO_WIDTH + 8, 4),
        Size = UDim2.fromOffset(34, LOGO_HEIGHT),
        Text = "v" .. tostring(PRODUCT.version),
        TextColor3 = WURSTLOGO_TEXT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21,
    })

    if type(state.applyAssetImage) == "function" then
        state.applyAssetImage("wurstLogo", logoImage, function(): ()
            logoImage.Visible = true
            logoFallback.Visible = false
        end)
    end

    -- ---------------------------------------------------------- stats block
    -- Small, monospace, and rebuilt twice a second — cheap enough that the
    -- values can read the live theme instead of binding each fragment.
    local statsLabel: TextLabel = (create("TextLabel", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = PopupLayer,
        Name = "StatsBlock",
        Active = false,
        BackgroundTransparency = 1,
        FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
        Position = UDim2.fromOffset(
            FURNITURE_MARGIN_X,
            FURNITURE_MARGIN_Y + LOGO_HEIGHT + 8 + STATS_GAP
        ),
        RichText = true,
        Size = UDim2.fromOffset(220, STATS_LINE_HEIGHT * 4),
        Text = "",
        TextColor3 = Theme.text,
        TextSize = STATS_FONT_SIZE,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 20,
    }) :: any) :: TextLabel
    ThemeEngine.Bind(statsLabel, "TextColor3", "text")

    local function colorHex(color: Color3): string
        return string.format(
            "#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5)
        )
    end

    local function escapeRich(text: string): string
        return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end

    local sessionStartedAt: number = os.clock()
    local frameCount: number = 0
    local statsElapsed: number = 0

    local function pingMilliseconds(): number?
        local ok: boolean, value: any = pcall(function(): number
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and type(value) == "number" then
            return math.floor(value + 0.5)
        end
        return nil
    end

    local function renderStats(framesPerSecond: number): ()
        local accent: string = colorHex(Theme.accent)
        local function line(label: string, value: string): string
            return label
                .. ' <font color="'
                .. accent
                .. '"><b>'
                .. value
                .. "</b></font>"
        end
        local ping: number? = pingMilliseconds()
        local rows: {string} = {
            line("FPS  ", tostring(framesPerSecond)),
            line("PING ", ping and tostring(ping) .. "ms" or "—"),
        }
        -- A phone keeps FPS and ping and drops the rest: four lines under a
        -- wordmark is a quarter of a small screen's corner.
        if not state.layout.compact then
            local seconds: number = math.floor(os.clock() - sessionStartedAt)
            table.insert(rows, line(
                "TIME ",
                string.format("%02d:%02d", seconds // 60, seconds % 60)
            ))
            table.insert(rows, line(
                "PLACE",
                escapeRich(tostring(state.activeGameName or "—"))
            ))
        end
        statsLabel.Text = table.concat(rows, "\n")
    end

    table.insert(Furniture.handles, TaskManager:Connect(function(): ()
        frameCount += 1
    end, "render"))

    table.insert(Furniture.handles, TaskManager:Connect(function(
        deltaTime: number
    ): ()
        statsElapsed += deltaTime
        if statsElapsed < 0.5 then
            return
        end
        local framesPerSecond: number =
            math.floor(frameCount / statsElapsed + 0.5)
        frameCount = 0
        statsElapsed = 0
        renderStats(framesPerSecond)
    end))
    renderStats(0)

    activeCleanup = function(): ()
        for _, handle: any in ipairs(Furniture.handles) do
            pcall(function(): ()
                handle:Disconnect()
            end)
        end
        Furniture.handles = {}
        chip:Destroy()
        statsLabel:Destroy()
    end
    Module.Initialized = true
    return Furniture
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
