--!strict
--[[
    A Random Menu
    Standalone, client-sided Roblox GUI.

    Default controls:
      - RightShift: show/hide the menu

    The shell itself is fixed: it is always centred on the screen and its size
    comes from the responsive metrics table (Mobile / Tablet / Desktop). Only
    the floating tool windows and the HUD overlays can be moved.
]]

local bootstrapStatusLabel: TextLabel? = nil
-- Raised by the xpcall handler at the bottom of the file. The loading intro
-- reads it so its scripted narration and its watchdog never overwrite or hide
-- the initialization error message.
local bootstrapFailed: boolean = false
local RUNTIME_COMPATIBILITY_MARKER: string =
    "Initialization error — check executor console"
local RUNTIME_SAFETY_SOURCE_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/4b10e4bfe00aa356afb3e0420a72e745327f6259/ARandomMenu.luau"
local RUNTIME_BUILD_LABEL: string = "loader-v3"

-- Module taxonomy.
--
-- Every feature card is filed under a category and the cards inside a category
-- are then sorted alphabetically, so the list reads
-- "Combat / Fling, Hitboxes… · Player / Fly, High Jump, Infinite Jump…".
-- Anything not listed here (including everything the per-game modules add)
-- falls back to DEFAULT_FEATURE_CATEGORY, which is always rendered last and
-- without a header when it is the only category on a page.
--
-- These live at file scope on purpose: `bootstrap()` is one enormous function
-- and is close to Luau's 200 local-register ceiling.
local DEFAULT_FEATURE_CATEGORY: string = "General"

-- The taxonomy, sorted the way it reads on screen:
--
--   Movement    getting around: speed, flight, jumps, teleports, phasing.
--   Combat      aiming and hitting: only things that help you fight.
--   Visuals     what you can see: ESP, lighting, camera.
--   Protection  what stops something happening to you.
--   Utility     one-shot tools and session helpers that fit nowhere else.
--
-- "Player" used to hold everything that moved the character, which made it a
-- second General; it is "Movement" now, which is what those modules are. And
-- Fling is not a combat aid — it does not help you fight, it throws another
-- player around — so it sits with the other one-shot tools.
local FEATURE_CATEGORIES: {[string]: string} = {
    -- Movement
    ["Click Teleport"] = "Movement",
    ["Fly"] = "Movement",
    ["Freeze Movements"] = "Movement",
    ["High Jump"] = "Movement",
    ["Infinite Jump"] = "Movement",
    ["Jump Power"] = "Movement",
    ["Noclip"] = "Movement",
    ["Phase Dash"] = "Movement",
    ["Speed"] = "Movement",
    ["Spider"] = "Movement",
    ["Walk Speed"] = "Movement",

    -- Combat
    ["Hitboxes"] = "Combat",
    ["Projectile Calibration"] = "Combat",

    -- Visuals
    ["FOV"] = "Visuals",
    ["Fullbright"] = "Visuals",
    ["Player ESP"] = "Visuals",
    ["X-Ray"] = "Visuals",
    ["Zoom Unlocker"] = "Visuals",

    -- Protection
    ["Anti-Fling"] = "Protection",
    ["Anti-Void"] = "Protection",
    ["Safe Walk"] = "Protection",
    ["Soft Landing"] = "Protection",

    -- Utility
    ["Anti-AFK"] = "Utility",
    ["Fling"] = "Utility",
    ["Gravity"] = "Utility",
    ["Improve FPS"] = "Utility",
    ["Interact Extender"] = "Utility",
    ["Lag Switch"] = "Utility",
    ["Rejoin Server"] = "Utility",
}

-- Height reserved at the foot of the navigation rail for the player card.
local PROFILE_CARD_HEIGHT: number = 56

-- Module kinds, on the card.
--
-- Three different contracts used to look identical: a toggle you switch, a
-- button that runs once, and an always-on module whose card is only a
-- container for its options. Every card now carries a chip that says which it
-- is, and the accent stripe is coloured to match, so the difference is visible
-- before you click anything.
--
-- The marker is a shape, not a caption: a word like "TOGGLE" on every card is
-- noise once you have seen it twice, and it eats the width the module name
-- needs.
--
--   toggle  a switch: a track with a knob that slides and lights up.
--   action  a play triangle: press it and something happens once.
--   hold    a hollow ring: live only while a finger is on the key.
--   group   a filled dot inside a ring: always running, nothing to press.

local KIND_COLORS: {[string]: Color3} = {
    toggle = Color3.fromRGB(150, 190, 255),
    action = Color3.fromRGB(245, 195, 120),
    hold = Color3.fromRGB(160, 235, 205),
    group = Color3.fromRGB(190, 175, 245),
}

-- Sort key for a whole category. The catch-all always sinks to the bottom;
-- every real category is ordered alphabetically.
local function featureCategoryRank(category: string): string
    if category == DEFAULT_FEATURE_CATEGORY then
        return "\255" .. category
    end
    return category
end

-- Sidebar monograms.
--
-- The navigation rail collapses to icons on small viewports, so every tab
-- carries a two-character monogram that is legible at 22px. Plain ASCII on
-- purpose: a glyph font would have to be downloaded and could fail to load.
-- Tab artwork.
--
-- A monogram is a fallback, not an icon. Game tabs show the game's own
-- thumbnail — resolved by the engine through `rbxthumb://`, so there is
-- nothing to download — and the two tabs that are not games get a drawn icon.
local TAB_GAME_ICONS: {[string]: number} = {
    Universal = 0,
    MM2 = 142823291,
    TRS = 14315258385,
    VD = 93978595733734,
    MVSD = 135856908115931,
}

local TAB_DRAWN_ICONS: {[string]: string} = {
    Movement = "navMovement",
    Settings = "navSettings",
}

local TAB_MONOGRAMS: {[string]: string} = {
    ["Universal"] = "UN",
    ["Movement"] = "MV",
    ["MM2"] = "M2",
    ["TRS"] = "TR",
    ["VD"] = "VD",
    ["MVSD"] = "MS",
    ["Config."] = "CF",
}

-- ---------------------------------------------------------------------------
-- Design tokens
-- ---------------------------------------------------------------------------
--
-- Radii, motion durations and shadow strengths are declared exactly once so
-- the whole shell keeps a single silhouette and a single rhythm. Sizes that
-- depend on the viewport live in `computeLayoutMetrics` below instead; these
-- are the values that never change with the device.
--
-- They sit at file scope (like the feature taxonomy) because `bootstrap()` is
-- one enormous function and is close to Luau's 200 local-register ceiling.
local UI_RADIUS: {[string]: number} = {
    shell = 12,
    panel = 9,
    card = 7,
    control = 6,
    chip = 5,
}
-- The reference interface animates in roughly 0.16s. Everything the shell
-- tweens uses one of these three durations.
local UI_MOTION: {[string]: number} = {
    fast = 0.1,
    base = 0.16,
    slow = 0.22,
}
-- There is deliberately no ambient shadow behind the shell.
--
-- It used to be faked with stacked rounded frames, but `cornerRadius()` caps
-- every radius at 30px: a frame 44px wider than the shell therefore kept
-- square-ish corners around a tightly rounded window and rendered as four
-- grey blocks poking out of the corners. A convincing soft shadow needs a
-- 9-slice image asset, and this runtime deliberately downloads none, so the
-- shell simply has no shadow.

-- ---------------------------------------------------------------------------
-- Responsive layout metrics
-- ---------------------------------------------------------------------------
--
-- One table drives every size in the interface. Modules never read it: they
-- ask the shared component factories for a card, a row or a control, and the
-- factories size themselves from here. That is what lets phones, tablets and
-- desktops get genuinely different layouts without touching a single game
-- module.
--
-- Three modes rather than one scale factor:
--   * Mobile  — phone (either orientation): near-fullscreen shell, collapsed
--               icon rail, one column, finger-sized controls.
--   * Tablet  — reduced rail, one column unless the content area is wide.
--   * Desktop — full rail with labels, two columns when they fit, more air.
type LayoutMetrics = {
    mode: string,
    compact: boolean,
    touch: boolean,
    shellWidth: number,
    shellHeight: number,
    shellCorner: number,
    sidebarWidth: number,
    sidebarCollapsed: boolean,
    sidebarPadding: number,
    navRowHeight: number,
    navIconSize: number,
    navFontSize: number,
    brandHeight: number,
    headerHeight: number,
    searchHeight: number,
    searchWidth: number,
    contentPadding: number,
    cardSpacing: number,
    cardColumns: number,
    cardHeight: number,
    cardCorner: number,
    controlHeight: number,
    optionRowHeight: number,
    switchWidth: number,
    switchHeight: number,
    iconButton: number,
    keySlotWidth: number,
    touchTarget: number,
    titleFontSize: number,
    bodyFontSize: number,
    captionFontSize: number,
    scrollBar: number,
    launcherHeight: number,
}

local function computeLayoutMetrics(
    viewport: Vector2,
    touchEnabled: boolean
): LayoutMetrics
    local width: number = math.max(240, viewport.X)
    local height: number = math.max(200, viewport.Y)

    -- A phone in landscape is still a phone: a short viewport switches to the
    -- mobile layout even though it is wide.
    local mode: string = "Desktop"
    if width < 620 or height < 430 then
        mode = "Mobile"
    elseif width < 1100 then
        mode = "Tablet"
    end
    local mobile: boolean = mode == "Mobile"
    local tablet: boolean = mode == "Tablet"

    local shellWidth: number
    local shellHeight: number
    if mobile then
        shellWidth = math.round(math.min(width - 10, math.max(280, width * 0.97)))
        shellHeight = math.round(math.min(height - 10, math.max(220, height * 0.94)))
    elseif tablet then
        shellWidth = math.round(math.clamp(width * 0.9, 460, 900))
        shellHeight = math.round(math.clamp(height * 0.84, 380, 760))
    else
        shellWidth = math.round(math.clamp(width * 0.58, 760, 1080))
        shellHeight = math.round(math.clamp(height * 0.74, 420, 700))
    end
    shellWidth = math.max(240, math.min(shellWidth, math.round(width - (mobile and 8 or 28))))
    shellHeight = math.max(200, math.min(shellHeight, math.round(height - (mobile and 8 or 28))))

    local sidebarWidth: number = mobile and 58 or (tablet and 132 or 156)
    local contentPadding: number = mobile and 10 or (tablet and 12 or 14)
    -- Columns are decided by the room the content area actually has, not by
    -- the mode: a phone in landscape gets two columns for the same reason a
    -- desktop does, and a portrait tablet stays on one.
    local contentWidth: number = shellWidth - sidebarWidth - contentPadding * 2
    local cardColumns: number = contentWidth >= 560 and 2 or 1

    return {
        mode = mode,
        compact = mobile,
        touch = touchEnabled,
        shellWidth = shellWidth,
        shellHeight = shellHeight,
        shellCorner = mobile and 10 or UI_RADIUS.shell,
        sidebarWidth = sidebarWidth,
        sidebarCollapsed = mobile,
        sidebarPadding = mobile and 6 or 10,
        navRowHeight = mobile and 40 or (tablet and 32 or 30),
        navIconSize = mobile and 26 or 22,
        navFontSize = mobile and 9 or 11,
        brandHeight = mobile and 40 or 46,
        headerHeight = mobile and 42 or 44,
        searchHeight = mobile and 30 or 28,
        searchWidth = mobile and 150 or (tablet and 190 or 230),
        contentPadding = contentPadding,
        cardSpacing = mobile and 7 or 6,
        cardColumns = cardColumns,
        cardHeight = mobile and 50 or 44,
        cardCorner = UI_RADIUS.card,
        controlHeight = touchEnabled and 32 or 26,
        optionRowHeight = touchEnabled and 38 or 34,
        switchWidth = mobile and 44 or 38,
        switchHeight = mobile and 24 or 20,
        iconButton = mobile and 26 or 24,
        keySlotWidth = mobile and 34 or 46,
        touchTarget = touchEnabled and 32 or 24,
        titleFontSize = mobile and 12 or 12,
        bodyFontSize = mobile and 10 or 10,
        captionFontSize = 9,
        scrollBar = mobile and 3 or 4,
        -- Height of the launcher dock at the foot of the rail. It stacks its
        -- two buttons vertically when the rail is collapsed, which is the
        -- only way they fit, so the dock is taller there.
        launcherHeight = mobile and 58 or 28,
    }
end

-- Which branch the runtime pulls its game modules from.
--
-- The loader and this bootstrap both live on `main`, so an injected menu
-- always ran main's game modules — which is why work reviewed on a branch
-- still looked unchanged in game. Setting `ARANDOMMENU_BRANCH` before loading
-- points the whole runtime (bootstrap *and* the per-game modules it fetches)
-- at that branch instead:
--
--   getgenv().ARANDOMMENU_BRANCH = "arena/01a01c6e-arandommenu"
--   loadstring(game:HttpGet(
--       "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/"
--           .. getgenv().ARANDOMMENU_BRANCH .. "/ARandomMenu.luau"))()
--
-- It defaults to `main`, so normal injections are unaffected.
local RUNTIME_BRANCH: string = "main"
do
    local override: any = (getfenv() :: any).ARANDOMMENU_BRANCH
    if type(override) == "string" and override ~= "" then
        RUNTIME_BRANCH = (override:gsub("^refs/heads/", ""))
    end
end
local RUNTIME_RAW_BASE: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/"
        .. RUNTIME_BRANCH
        .. "/"

local function bootstrap(): ()
local executorGlobals: any = getfenv()

local function cloneReference(instance: any): any
    if type(executorGlobals.cloneref) == "function" then
        local success: boolean, cloned: any = pcall(executorGlobals.cloneref, instance)
        if success then
            return cloned
        end
    end
    return instance
end

local Players: Players = cloneReference(game:GetService("Players"))
local UserInputService: UserInputService = cloneReference(game:GetService("UserInputService"))
local TweenService: TweenService = cloneReference(game:GetService("TweenService"))
local Lighting: Lighting = cloneReference(game:GetService("Lighting"))
local RunService: RunService = cloneReference(game:GetService("RunService"))
local HttpService: HttpService = cloneReference(game:GetService("HttpService"))
local CollectionService: CollectionService = cloneReference(game:GetService("CollectionService"))
local Stats: Stats = cloneReference(game:GetService("Stats"))
local LocalPlayer: Player = Players.LocalPlayer :: Player
local PlayerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local GUI_NAME = "RandomTestingMenu0001"
local BLUR_NAME = "RandomTestingMenu0001Blur"
local CONFIG_FOLDER = "RandomTestingMenu0001"
local CONFIG_PROFILE_FOLDER = CONFIG_FOLDER .. "/Profiles"
local CONFIG_FILE = CONFIG_PROFILE_FOLDER
    .. "/Game_"
    .. tostring(game.GameId > 0 and game.GameId or game.PlaceId)
    .. ".Config"
local REPOSITORY_RAW_BASE = RUNTIME_RAW_BASE

local GAME_MODULES: {[number]: string} = {
    [142823291] = "MM2",
    [14315258385] = "TRS",
    [93978595733734] = "VD",
    [135856908115931] = "MVSD",
}

-- ---------------------------------------------------------------------------
-- Game fingerprinting
-- ---------------------------------------------------------------------------
--
-- MM2 is cloned constantly ("MMV" and friends): same game, different PlaceId,
-- so a PlaceId table alone leaves every copy with no game tab at all. A copy
-- cannot strip the structure the game is *built* on, though — the remotes its
-- rounds run through, the weapon service its guns call, the HUD it clones into
-- PlayerGui — so when the PlaceId is unknown the runtime looks for that
-- structure instead.
--
-- Deliberately conservative: several independent markers must match, and each
-- one is a path the real game genuinely needs, so an unrelated game cannot
-- score high enough by accident. Nothing here waits on the network; it reads
-- what has already replicated.
type GameFingerprint = {
    module: string,
    required: number,
    markers: {(ReplicatedStorage) -> boolean},
}

local GAME_FINGERPRINTS: {GameFingerprint} = {
    {
        module = "MM2",
        required = 4,
        markers = {
            -- The round pipeline: these four remotes are what every MM2 round
            -- is driven by.
            function(replicated: ReplicatedStorage): boolean
                local remotes: Instance? = replicated:FindFirstChild("Remotes")
                local gameplay: Instance? = remotes
                    and remotes:FindFirstChild("Gameplay")
                if not gameplay then
                    return false
                end
                local found: number = 0
                for _, name: string in ipairs({
                    "RoundStart",
                    "RoundEndFade",
                    "GetCurrentPlayerData",
                    "PlayerDataChanged",
                }) do
                    if gameplay:FindFirstChild(name) then
                        found += 1
                    end
                end
                return found >= 3
            end,
            -- The weapon service the knife and gun both go through.
            function(replicated: ReplicatedStorage): boolean
                local services: Instance? =
                    replicated:FindFirstChild("ClientServices")
                local weaponService: Instance? = services
                    and services:FindFirstChild("WeaponService")
                return weaponService ~= nil
                    and weaponService:FindFirstChild("GunFired") ~= nil
            end,
            -- The HUD that carries the round timer and the role selector.
            function(replicated: ReplicatedStorage): boolean
                local mainGui: Instance? = replicated:FindFirstChild("MainGUI")
                local gameFrame: Instance? = mainGui
                    and mainGui:FindFirstChild("Game")
                return gameFrame ~= nil
                    and gameFrame:FindFirstChild("Timer") ~= nil
            end,
            -- MM2 gives the murderer its own collision group.
            function(_replicated: ReplicatedStorage): boolean
                local ok: boolean, groups: any = pcall(function(): any
                    return game:GetService("PhysicsService")
                        :GetRegisteredCollisionGroups()
                end)
                if not ok or type(groups) ~= "table" then
                    return false
                end
                for _, group: any in ipairs(groups) do
                    if type(group) == "table" and group.name == "Murderer" then
                        return true
                    end
                end
                return false
            end,
            -- Coin containers/areas are in every MM2 map.
            function(_replicated: ReplicatedStorage): boolean
                for _, object: Instance in ipairs(workspace:GetChildren()) do
                    if object:IsA("Model")
                        and object.Name ~= "Lobby"
                        and (object:FindFirstChild("CoinContainer")
                            or object:FindFirstChild("CoinAreas")) then
                        return true
                    end
                end
                return false
            end,
        },
    },
}

local function detectGameModuleByStructure(): (string?, number)
    local replicated: ReplicatedStorage = game:GetService("ReplicatedStorage")
    for _, fingerprint: GameFingerprint in ipairs(GAME_FINGERPRINTS) do
        local score: number = 0
        for _, marker: (ReplicatedStorage) -> boolean in ipairs(fingerprint.markers) do
            local ok: boolean, matched: any = pcall(marker, replicated)
            if ok and matched == true then
                score += 1
            end
        end
        if score >= fingerprint.required then
            return fingerprint.module, score
        end
    end
    return nil, 0
end

local ACTIVE_GAME_MODULE: string? = GAME_MODULES[game.PlaceId]
local ACTIVE_GAME_SOURCE: string = ACTIVE_GAME_MODULE and "PlaceId" or "none"
if not ACTIVE_GAME_MODULE then
    -- A clone: recognise the game by what it is made of. The check is retried
    -- briefly because a freshly joined client may still be replicating.
    local detected: string?, score: number = detectGameModuleByStructure()
    local attempts: number = 0
    while not detected and attempts < 6 do
        attempts += 1
        task.wait(0.5)
        detected, score = detectGameModuleByStructure()
    end
    if detected then
        ACTIVE_GAME_MODULE = detected
        ACTIVE_GAME_SOURCE = "fingerprint " .. tostring(score) .. " markers"
    end
end

local GAME_CHECK = {
    MM2 = 142823291,
    TRS = 14315258385,
    VD = 93978595733734,
    MVSD = 135856908115931,
    MM2Active = ACTIVE_GAME_MODULE == "MM2",
    TRSActive = ACTIVE_GAME_MODULE == "TRS",
    VDActive = ACTIVE_GAME_MODULE == "VD",
    MVSDActive = ACTIVE_GAME_MODULE == "MVSD",
}

function GAME_CHECK.matches(identifier: number): boolean
    if game.PlaceId == identifier then
        return true
    end
    -- A recognised clone answers for the game it is a copy of, so modules that
    -- gate on `GAME_CHECK.matches(GAME_CHECK.MM2)` keep working there.
    for placeId: number, moduleName: string in pairs(GAME_MODULES) do
        if placeId == identifier then
            return ACTIVE_GAME_MODULE == moduleName
        end
    end
    return false
end

GAME_CHECK.source = ACTIVE_GAME_SOURCE
-- Neutral monochrome palette. The interface is intentionally themeless: every
-- surface is a shade of black/grey and the single accent is plain white, so no
-- decorative identity leaks into the runtime.
local DEFAULT_HEADER_COLOR: Color3 = Color3.fromRGB(236, 236, 238)
local DEFAULT_MENU_COLOR: Color3 = Color3.fromRGB(8, 8, 9)
local DEFAULT_SURFACE_COLOR: Color3 = Color3.fromRGB(26, 26, 28)
local DEFAULT_BORDER_COLOR: Color3 = Color3.fromRGB(92, 92, 98)

local Theme: {[string]: Color3} = {
    Background = Color3.fromRGB(8, 8, 9),
    Surface = Color3.fromRGB(26, 26, 28),
    SurfaceRaised = Color3.fromRGB(32, 32, 35),
    SurfaceHover = Color3.fromRGB(40, 40, 44),
    SurfacePressed = Color3.fromRGB(48, 48, 52),
    Accent = Color3.fromRGB(236, 236, 238),
    AccentCyan = Color3.fromRGB(236, 236, 238),
    AccentViolet = Color3.fromRGB(196, 196, 202),
    AccentPink = Color3.fromRGB(160, 160, 168),
    AccentSoft = Color3.fromRGB(52, 52, 56),
    DefaultBackground = Color3.fromRGB(8, 8, 9),
    DefaultSidebar = Color3.fromRGB(13, 13, 14),
    DefaultSurface = Color3.fromRGB(26, 26, 28),
    DefaultSurfaceHover = Color3.fromRGB(40, 40, 44),
    DefaultButton = Color3.fromRGB(32, 32, 35),
    DefaultButtonHover = Color3.fromRGB(46, 46, 50),
    DefaultButtonPressed = Color3.fromRGB(56, 56, 61),
    DefaultOutline = Color3.fromRGB(92, 92, 98),
    DefaultAccent = Color3.fromRGB(236, 236, 238),
    DefaultText = Color3.fromRGB(245, 245, 247),
    DefaultTextMuted = Color3.fromRGB(158, 158, 166),
    Text = Color3.fromRGB(245, 245, 247),
    TextMuted = Color3.fromRGB(158, 158, 166),
    Outline = Color3.fromRGB(92, 92, 98),
    -- Status colours stay semantic: they label gameplay data (roles, health,
    -- failures) rather than the menu chrome, so they remain readable while the
    -- interface itself stays monochrome.
    Success = Color3.fromRGB(126, 196, 138),
    Danger = Color3.fromRGB(214, 106, 106),
}
local TITLE_FONT: Font = Font.new(
    "rbxasset://fonts/families/BuilderSans.json",
    Enum.FontWeight.Bold,
    Enum.FontStyle.Normal
)
local THIN_FONT: Font = Font.new(
    "rbxasset://fonts/families/BuilderSans.json",
    Enum.FontWeight.Regular,
    Enum.FontStyle.Normal
)
local CONTROL_FONT: Font = Font.new(
    "rbxasset://fonts/families/BuilderSans.json",
    Enum.FontWeight.SemiBold,
    Enum.FontStyle.Normal
)
local DISPLAY_FONT: Font = TITLE_FONT
local VALVE_FONT: Font = CONTROL_FONT
local TEXT_BASE_MULTIPLIER: number = 1.35
local TEXT_SCALE_MINIMUM: number = 0.8
local TEXT_SCALE_MAXIMUM: number = 1.2
local IS_MOBILE_DEVICE: boolean = UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled

local configData: any = {
    version = 1,
    states = {},
    values = {},
    ui = {},
}
local configSaveQueued = false

local function loadConfig()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        return
    end

    local success, loaded = pcall(function()
        if not isfile(CONFIG_FILE) then
            return nil
        end
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)

    if success and type(loaded) == "table" then
        configData.version = loaded.version or 1
        configData.states = type(loaded.states) == "table" and loaded.states or {}
        configData.values = type(loaded.values) == "table" and loaded.values or {}
        configData.ui = type(loaded.ui) == "table" and loaded.ui or {}
    end

    -- The shell is fixed and centred, so any window geometry written by an
    -- older build is dropped on load instead of being honoured. Floating
    -- window positions (`ui.floatingPositions`) are kept: those windows are
    -- still movable on purpose.
    configData.ui.windowPosition = nil
    configData.ui.windowSize = nil
end

local function saveConfigNow()
    if type(writefile) ~= "function" then
        return
    end

    pcall(function()
        if type(isfolder) == "function"
            and type(makefolder) == "function"
            and not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
        if type(isfolder) == "function"
            and type(makefolder) == "function"
            and not isfolder(CONFIG_PROFILE_FOLDER) then
            makefolder(CONFIG_PROFILE_FOLDER)
        end
        writefile(CONFIG_FILE, HttpService:JSONEncode(configData))
    end)
end

local function queueConfigSave()
    if configSaveQueued then
        return
    end
    configSaveQueued = true
    task.delay(0.35, function()
        configSaveQueued = false
        saveConfigNow()
    end)
end

local function colorFromConfig(value, fallback)
    if type(value) == "table" then
        return Color3.fromRGB(
            math.clamp(tonumber(value[1]) or 0, 0, 255),
            math.clamp(tonumber(value[2]) or 0, 0, 255),
            math.clamp(tonumber(value[3]) or 0, 0, 255)
        )
    end
    return fallback
end

local function colorToConfig(color)
    return {
        math.round(color.R * 255),
        math.round(color.G * 255),
        math.round(color.B * 255),
    }
end

loadConfig()

local function findExistingGui()
    local locations = {PlayerGui}

    local coreGuiOk, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if coreGuiOk and coreGui then
        table.insert(locations, coreGui)
    end

    if type(gethui) == "function" then
        local hiddenGuiOk, hiddenGui = pcall(gethui)
        if hiddenGuiOk and hiddenGui then
            table.insert(locations, hiddenGui)
        end
    end

    for _, location in ipairs(locations) do
        local existing = location:FindFirstChild(GUI_NAME)
        if existing then
            existing:Destroy()
        end
    end
end

findExistingGui()

local oldBlur = Lighting:FindFirstChild(BLUR_NAME)
if oldBlur then
    oldBlur:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui:SetAttribute("BuildId", "0001-S17")

local function parentScreenGui()
    if type(gethui) == "function" then
        local hiddenGuiOk, hiddenGui = pcall(gethui)
        if hiddenGuiOk and hiddenGui then
            local parented = pcall(function()
                ScreenGui.Parent = hiddenGui
            end)
            if parented then
                return
            end
        end
    end

    local coreGuiOk, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if coreGuiOk and coreGui then
        local parented = pcall(function()
            ScreenGui.Parent = coreGui
        end)
        if parented then
            return
        end
    end

    ScreenGui.Parent = PlayerGui
end

parentScreenGui()

local PopupLayer: Frame = Instance.new("Frame")
PopupLayer.Name = "PopupLayer"
PopupLayer.Active = false
PopupLayer.BackgroundTransparency = 1
PopupLayer.BorderSizePixel = 0
PopupLayer.Size = UDim2.fromScale(1, 1)
PopupLayer.ZIndex = 150
PopupLayer.Parent = ScreenGui

local BLUR_STRENGTH: number = 16
local Blur = Instance.new("BlurEffect")
Blur.Name = BLUR_NAME
Blur.Size = 0
-- Start disabled. An enabled BlurEffect that merely has Size 0 still keeps the
-- blur pass alive, so the effect is only ever enabled while it is actually
-- being used and is switched off again the moment the menu hides.
Blur.Enabled = false
Blur.Parent = Lighting

local savedToggleKey = Enum.KeyCode.RightShift
if type(configData.ui.toggleKey) == "string" then
    pcall(function()
        savedToggleKey = Enum.KeyCode[configData.ui.toggleKey]
            or Enum.KeyCode.RightShift
    end)
end

local state: any = {
    visible = true,
    isMobile = IS_MOBILE_DEVICE,
    guiStyle = "Default",
    blurEnabled = configData.ui.blurEnabled ~= false,
    textScale = configData.ui.textScaleCalibrationVersion == 2
        and math.clamp(
            tonumber(configData.ui.textScale) or 1,
            TEXT_SCALE_MINIMUM,
            TEXT_SCALE_MAXIMUM
        )
        or 1,
    mobileMenuButtonVisible = true,
    animationsEnabled = configData.ui.animationsEnabled ~= false,
    -- Free-form pixel size now, not one of four presets, so the stored value
    -- is only sanity-clamped.
    mobileButtonSize = math.clamp(
        tonumber(configData.ui.mobileButtonSize) or 52,
        28,
        120
    ),
    toggleKey = savedToggleKey,
    waitingForKey = false,
    keyCaptureCallback = nil,
    activeTab = "Universal",
    headerColor = DEFAULT_HEADER_COLOR,
    menuColor = DEFAULT_MENU_COLOR,
    hookFunction = (getfenv() :: any).hookfunction,
    hookMetamethod = (getfenv() :: any).hookmetamethod,
    getNamecallMethod = (getfenv() :: any).getnamecallmethod,
    newCClosure = (getfenv() :: any).newcclosure,
    fireTouchInterest = (getfenv() :: any).firetouchinterest,
    requireModule = require,
    uiConnections = {} :: {RBXScriptConnection},
    styledButtons = {} :: {TextButton},
    styledTextBoxes = {} :: {TextBox},
}
configData.ui.guiStyle = nil
configData.ui.textScaleCalibrationVersion = 2

-- ---------------------------------------------------------------------------
-- Layout controller
-- ---------------------------------------------------------------------------
--
-- `state.layout` is the single source of truth for every size in the shell.
-- Anything that has to change when the viewport changes registers a listener
-- through `state.onLayout` and is called again with the new metrics; nothing
-- polls, and no game module ever has to know a pixel value.
--
-- These are plain fields on `state` rather than locals because `bootstrap()`
-- is one function scope sitting near Luau's 200 local-register ceiling.
state.layout = computeLayoutMetrics(
    (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize)
        or Vector2.new(1280, 720),
    UserInputService.TouchEnabled
)
state.layoutListeners = {} :: {(LayoutMetrics) -> ()}

state.onLayout = function(listener: (LayoutMetrics) -> ()): ()
    table.insert(state.layoutListeners, listener)
end

-- `force` re-applies the current metrics even when nothing changed, which is
-- what the initial pass and the style refresh use.
state.refreshLayout = function(force: boolean?): ()
    local camera: Camera? = workspace.CurrentCamera
    local viewport: Vector2 = camera
        and camera.ViewportSize
        or Vector2.new(1280, 720)
    local nextLayout: LayoutMetrics = computeLayoutMetrics(
        viewport,
        UserInputService.TouchEnabled
    )
    local previous: LayoutMetrics = state.layout
    if not force
        and previous.mode == nextLayout.mode
        and previous.shellWidth == nextLayout.shellWidth
        and previous.shellHeight == nextLayout.shellHeight
        and previous.cardColumns == nextLayout.cardColumns then
        return
    end
    state.layout = nextLayout
    for _, listener: (LayoutMetrics) -> () in ipairs(state.layoutListeners) do
        local ok: boolean, failure: any = pcall(listener, nextLayout)
        if not ok then
            warn("[Random Testing Menu] layout listener: " .. tostring(failure))
        end
    end
end

local function trackUiConnection(
    connection: RBXScriptConnection
): RBXScriptConnection
    table.insert(state.uiConnections, connection)
    return connection
end

-- Single owner of the blur effect.
--
-- The blur exists only to dim the game *while the menu is on screen*. It is
-- defined here, next to the shared state, because it must be reachable from
-- every path that can show or hide the menu (keyboard toggle, mobile button,
-- mobile-shortcut placement, destruct). Previously it lived inside the
-- Settings tab builder, which runs asynchronously and much later: any toggle
-- that happened before -- or instead of -- that builder fell through to a
-- fallback branch that flipped `Main.Visible` without ever touching the blur,
-- leaving the screen blurred with the menu closed.
-- Decorations that live on top of the blur (the falling hail layer) publish a
-- setter on `state.blurDecorationSetActive`. They are built much later than
-- the blur controller, so the controller only ever talks to that indirection:
-- if nothing has registered yet the calls are no-ops, and whatever registers
-- later is immediately synchronised with the current blur state. This keeps
-- the "menu closed => nothing left on screen" guarantee the blur itself has.
-- It is kept on `state` rather than in a local because `bootstrap()` is a
-- single function scope sitting near Luau's 200 local-register ceiling.
local function setBlurDecorationActive(active: boolean): ()
    local setActive: any = state.blurDecorationSetActive
    if type(setActive) == "function" then
        pcall(setActive, active)
    end
end

local blurTween: Tween? = nil
local function applyBlur(animate: boolean?): ()
    local shouldBlur: boolean = state.visible == true
        and state.blurEnabled == true
    local targetSize: number = shouldBlur and BLUR_STRENGTH or 0
    setBlurDecorationActive(shouldBlur)

    if blurTween then
        blurTween:Cancel()
        blurTween = nil
    end
    if not Blur.Parent then
        return
    end

    if shouldBlur then
        -- Enable before tweening in so the ramp is visible.
        Blur.Enabled = true
    end

    if animate and state.animationsEnabled ~= false then
        local tween: Tween = TweenService:Create(
            Blur,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = targetSize}
        )
        blurTween = tween
        tween.Completed:Once(function(): ()
            if blurTween == tween then
                blurTween = nil
            end
            -- Release the blur pass once it has finished fading out.
            if not shouldBlur and Blur.Parent then
                Blur.Size = 0
                Blur.Enabled = false
            end
        end)
        tween:Play()
    else
        Blur.Size = targetSize
        Blur.Enabled = shouldBlur
    end
end
state.setBlurVisible = applyBlur

-- Force the blur off regardless of the menu state. Used when the menu is
-- temporarily hidden by an overlay flow and during teardown.
local function suspendBlur(): ()
    if blurTween then
        blurTween:Cancel()
        blurTween = nil
    end
    setBlurDecorationActive(false)
    if Blur.Parent then
        Blur.Size = 0
        Blur.Enabled = false
    end
end
state.suspendBlur = suspendBlur

-- Registration point for the hail layer (or any future blur decoration).
-- Registering immediately pushes the current blur state into the decoration so
-- it can never start out of sync with a menu that is already open or closed.
state.registerBlurDecoration = function(setActive: (boolean) -> ()): ()
    state.blurDecorationSetActive = setActive
    pcall(
        setActive,
        state.visible == true and state.blurEnabled == true
    )
end

-- Authoritative menu visibility entry point. Subsystems (mobile buttons,
-- floating windows) attach their own side effects as listeners as soon as they
-- are built, so this is safe to call at any point during startup and the blur
-- is updated even when a subsystem has not initialized yet.
local menuVisibilityListeners: {(boolean) -> ()} = {}
state.addMenuVisibilityListener = function(listener: (boolean) -> ()): ()
    table.insert(menuVisibilityListeners, listener)
end

local function setMenuVisibleCore(visible: boolean): ()
    state.visible = visible
    if state.mainFrame then
        state.mainFrame.Visible = visible
    end
    for _, listener: (boolean) -> () in ipairs(menuVisibilityListeners) do
        -- One faulty listener must never leave the blur stuck on.
        pcall(listener, visible)
    end
    applyBlur(true)
end
state.setMenuVisible = setMenuVisibleCore

type AssetDefinition = {
    url: string,
    fileName: string,
    fallback: string,
    version: number?,
    assetType: string?,
}

do
local generatedEnvironment: any = nil
if type(executorGlobals.getgenv) == "function" then
    local environmentOk: boolean, resolvedEnvironment: any = pcall(
        executorGlobals.getgenv
    )
    if environmentOk and type(resolvedEnvironment) == "table" then
        generatedEnvironment = resolvedEnvironment
    end
end

local function getEnvironmentValue(name: string): any
    if generatedEnvironment and generatedEnvironment[name] ~= nil then
        return generatedEnvironment[name]
    end
    return executorGlobals[name]
end

local AssetManager: any = {
    cacheRoot = CONFIG_FOLDER,
    cacheFolder = CONFIG_FOLDER .. "/Assets",
    resolved = {} :: {[string]: string},
    resolving = {} :: {[string]: boolean},
    -- Only the two decorative fonts are still resolved at runtime; every
    -- other entry pointed at themed artwork that the neutral interface no
    -- longer renders.
    manifest = {
        candyFont = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Typography/CandyFruits.otf",
            fileName = "candy-fruits-v1.otf",
            fallback = "",
            version = 1,
            assetType = "font/otf",
        },
        valveFont = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Typography/ValveBD.otf",
            fileName = "valve-bd-v1.otf",
            fallback = "",
            version = 1,
            assetType = "font/otf",
        },
        -- Brand artwork. Both are resolved lazily and every consumer keeps a
        -- text fallback, so an executor without getcustomasset simply keeps
        -- the lettering it had.
        brandLogo = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Brand/menu-logo.jpg",
            fileName = "brand-logo-v1.jpg",
            fallback = "",
            version = 1,
            assetType = "image/jpeg",
        },
        navMovement = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/nav-movement.png",
            fileName = "nav-movement-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        navSettings = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/nav-settings.png",
            fileName = "nav-settings-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        windowFavorites = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/window-favorites.png",
            fileName = "window-favorites-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        windowOverlays = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/window-overlays.png",
            fileName = "window-overlays-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        profileBanner = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Brand/profile-banner.png",
            fileName = "profile-banner-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
    } :: {[string]: AssetDefinition},
}

local function selectHttpRequest(): (any, string)
    local synEnvironment: any = getEnvironmentValue("syn")
    local candidates: {{any}} = {
        {getEnvironmentValue("request"), "request"},
        {getEnvironmentValue("http_request"), "http_request"},
        {getEnvironmentValue("httprequest"), "httprequest"},
        {synEnvironment and synEnvironment.request, "syn.request"},
    }
    for _, candidate: {any} in ipairs(candidates) do
        if type(candidate[1]) == "function" then
            return candidate[1], tostring(candidate[2])
        end
    end
    return nil, "game:HttpGet"
end

local function validateAssetBytes(
    bytes: any,
    definition: AssetDefinition
): (boolean, string?)
    if type(bytes) ~= "string" then
        return false, "respuesta no binaria: " .. type(bytes)
    end
    if #bytes < 64 then
        return false, "respuesta demasiado corta: " .. tostring(#bytes) .. " bytes"
    end
    local prefix: string = string.lower(string.sub(bytes, 1, 128))
    if string.find(prefix, "<!doctype html", 1, true)
        or string.find(prefix, "<html", 1, true)
        or string.find(prefix, "404: not found", 1, true) then
        return false, "la respuesta contiene HTML/404"
    end
    if definition.assetType == "font/otf" then
        local fontSignature: string = string.sub(bytes, 1, 4)
        if fontSignature ~= "OTTO" and fontSignature ~= string.char(0, 1, 0, 0) then
            return false, "firma OpenType/TrueType inválida"
        end
        return true, nil
    end
    local isPng: boolean = string.sub(bytes, 1, 8) == "\137PNG\r\n\26\n"
    local isJpeg: boolean = string.byte(bytes, 1) == 0xFF
        and string.byte(bytes, 2) == 0xD8
        and string.byte(bytes, 3) == 0xFF
    if not isPng and not isJpeg then
        return false, "firma PNG inválida"
    end
    return true, nil
end

function AssetManager.ensureCacheFolder(): (boolean, string?)
    local isFolder: any = getEnvironmentValue("isfolder")
    local makeFolder: any = getEnvironmentValue("makefolder")
    local function ensureOne(path: string): (boolean, string?)
        if type(isFolder) == "function" then
            local checked: boolean, exists: any = pcall(isFolder, path)
            if checked and exists then
                return true, nil
            end
        end
        if type(makeFolder) ~= "function" then
            return false, "makefolder no está disponible"
        end
        local created: boolean, createError: any = pcall(makeFolder, path)
        if not created then
            return false, tostring(createError)
        end
        return true, nil
    end

    local rootOk: boolean, rootError: string? = ensureOne(AssetManager.cacheRoot)
    if not rootOk then
        return false, "carpeta principal: " .. tostring(rootError)
    end
    local cacheOk: boolean, cacheError: string? = ensureOne(AssetManager.cacheFolder)
    if not cacheOk then
        return false, "carpeta Assets: " .. tostring(cacheError)
    end
    return true, nil
end

function AssetManager.readVerifiedCache(
    path: string,
    definition: AssetDefinition
): (string?, string?)
    local isFile: any = getEnvironmentValue("isfile")
    local readFile: any = getEnvironmentValue("readfile")
    if type(isFile) ~= "function" or type(readFile) ~= "function" then
        return nil, "isfile/readfile no están disponibles"
    end
    local checked: boolean, exists: any = pcall(isFile, path)
    if not checked or not exists then
        return nil, "archivo no encontrado"
    end
    local readOk: boolean, bytes: any = pcall(readFile, path)
    if not readOk then
        return nil, "readfile: " .. tostring(bytes)
    end
    local valid: boolean, validationError: string? = validateAssetBytes(
        bytes,
        definition
    )
    if not valid then
        return nil, validationError
    end
    return bytes, nil
end

function AssetManager.download(definition: AssetDefinition): (string?, string?)
    local requestFunction: any, _requestName: string = selectHttpRequest()

    local lastError: string = "sin respuesta"
    for attempt: number = 1, 3 do
        local requestOk: boolean, response: any
        if requestFunction then
            requestOk, response = pcall(requestFunction, {
                Url = definition.url,
                Method = "GET",
                Headers = {Accept = definition.assetType or "*/*"},
            })
        else
            requestOk, response = pcall(function(): any
                return {
                    StatusCode = 200,
                    Body = (game :: any):HttpGet(definition.url, true),
                }
            end)
        end

        if requestOk then
            local statusCode: number = 0
            local bytes: any = nil
            if type(response) == "string" then
                statusCode = 200
                bytes = response
            elseif type(response) == "table" then
                statusCode = tonumber(
                    response.StatusCode or response.Status or response.status_code
                ) or 0
                bytes = response.Body or response.body or response.ResponseBody
            end
            local valid: boolean, validationError: string? = validateAssetBytes(
                bytes,
                definition
            )
            if statusCode >= 200 and statusCode < 300 and valid then
                return bytes, nil
            end
            response = "HTTP "
                .. tostring(statusCode)
                .. ": "
                .. tostring(validationError)
        end

        lastError = "intento "
            .. tostring(attempt)
            .. ": "
            .. tostring(response)
        if attempt < 3 then
            task.wait(0.35 * attempt)
        end
    end
    return nil, "descarga agotó tres intentos; " .. lastError
end

function AssetManager.resolve(logicalName: string): (string?, string?)
    local alreadyResolved: string? = AssetManager.resolved[logicalName]
    if alreadyResolved then
        return alreadyResolved, nil
    end
    local definition: AssetDefinition? = AssetManager.manifest[logicalName]
    if not definition then
        return nil, "asset desconocido: " .. logicalName
    end
    local assetFunction: any = getEnvironmentValue("getcustomasset")
        or getEnvironmentValue("getsynasset")
    local writeFile: any = getEnvironmentValue("writefile")
    if type(assetFunction) ~= "function" then
        return nil, "getcustomasset/getsynasset no está disponible"
    end
    if type(writeFile) ~= "function" then
        return nil, "writefile no está disponible"
    end

    local folderOk: boolean, folderError: string? =
        AssetManager.ensureCacheFolder()
    if not folderOk then
        return nil, folderError
    end
    local path: string = AssetManager.cacheFolder .. "/" .. definition.fileName
    local waitTime: number = 0
    while AssetManager.resolving[logicalName] and waitTime < 12 do
        task.wait(0.05)
        waitTime += 0.05
    end
    alreadyResolved = AssetManager.resolved[logicalName]
    if alreadyResolved then
        return alreadyResolved, nil
    end
    if AssetManager.resolving[logicalName] then
        return nil, "tiempo de espera agotado para " .. logicalName
    end
    AssetManager.resolving[logicalName] = true
    local cachedBytes: string?, cacheError: string? =
        AssetManager.readVerifiedCache(path, definition)
    if not cachedBytes then
        print("[RTM:Assets] caché no reutilizable: " .. tostring(cacheError))
        local downloaded: string?, downloadError: string? =
            AssetManager.download(definition)
        if not downloaded then
            AssetManager.resolving[logicalName] = false
            return nil, downloadError
        end
        local written: boolean, writeError: any = pcall(writeFile, path, downloaded)
        if not written then
            AssetManager.resolving[logicalName] = false
            return nil, "writefile: " .. tostring(writeError)
        end
        local verified: string?, verifyError: string? =
            AssetManager.readVerifiedCache(path, definition)
        if not verified then
            AssetManager.resolving[logicalName] = false
            return nil, "verificación posterior: " .. tostring(verifyError)
        end
    end

    local assetOk: boolean, assetId: any = pcall(assetFunction, path)
    if not assetOk or type(assetId) ~= "string" or assetId == "" then
        AssetManager.resolving[logicalName] = false
        return nil, "getcustomasset: " .. tostring(assetId)
    end
    AssetManager.resolved[logicalName] = assetId
    AssetManager.resolving[logicalName] = false
    return assetId, nil
end

function AssetManager.resolveFont(
    logicalName: string,
    fallbackFont: Font,
    weight: Enum.FontWeight,
    style: Enum.FontStyle
): Font
    local assetId: string?, loadError: string? = AssetManager.resolve(logicalName)
    if not assetId then
        warn(
            "[RTM:Assets] fuente fallback para "
                .. logicalName
                .. ": "
                .. tostring(loadError)
        )
        return fallbackFont
    end
    local fontOk: boolean, fontFace: any = pcall(
        Font.new,
        assetId,
        weight,
        style
    )
    if not fontOk or typeof(fontFace) ~= "Font" then
        warn(
            "[RTM:Assets] Font.new fallback para "
                .. logicalName
                .. ": "
                .. tostring(fontFace)
        )
        return fallbackFont
    end
    print("[RTM:Assets] fuente cargada: " .. logicalName)
    return fontFace
end

    DISPLAY_FONT = AssetManager.resolveFont(
        "candyFont",
        TITLE_FONT,
        Enum.FontWeight.Regular,
        Enum.FontStyle.Normal
    )
    VALVE_FONT = AssetManager.resolveFont(
        "valveFont",
        CONTROL_FONT,
        Enum.FontWeight.Bold,
        Enum.FontStyle.Normal
    )
    state.assetManager = AssetManager

-- Resolving an image means a download, a file write and a getcustomasset
-- call, so it happens off the bootstrap thread and the caller keeps whatever
-- it was already showing until the id arrives.
state.applyAssetImage = function(
    logicalName: string,
    image: ImageLabel,
    onApplied: (() -> ())?
): ()
    task.spawn(function(): ()
        local assetId: string?, failure: string? = AssetManager.resolve(logicalName)
        if not assetId then
            warn("[RTM:Assets] " .. logicalName .. ": " .. tostring(failure))
            return
        end
        if not image.Parent then
            return
        end
        image.Image = assetId :: string
        if onApplied then
            onApplied()
        end
    end)
end
end

local registeredText = {}
local defaultTabButtons = {}
local pages = {}
local SectionManager = {
    entries = {},
}

function SectionManager.register(sectionName, builder)
    SectionManager.entries[sectionName] = {
        builder = builder,
        loaded = false,
        loading = false,
    }
end

function SectionManager.clearStatus(page)
    local status = page and page:FindFirstChild("SectionStatus")
    if status then
        status:Destroy()
    end
end

function SectionManager.showStatus(page, message, isError)
    SectionManager.clearStatus(page)
    if not page then
        return
    end

    local status = Instance.new("TextLabel")
    status.Name = "SectionStatus"
    status.BackgroundColor3 = Theme.DefaultSurface
    status.BackgroundTransparency = isError and 0.05 or 0.2
    status.BorderSizePixel = 0
    status.FontFace = CONTROL_FONT
    status.Position = UDim2.fromOffset(18, 18)
    status.Size = UDim2.new(1, -36, 0, isError and 150 or 46)
    status.Text = message
    status.TextColor3 = isError
        and Theme.Danger
        or Theme.DefaultText
    status.TextSize = 13
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.ZIndex = 100
    status.Parent = page
end

function SectionManager.initialize(sectionName: string): (boolean, string?)
    local entry = SectionManager.entries[sectionName]
    if not entry or entry.loaded or entry.loading then
        return entry ~= nil and entry.loaded == true, nil
    end

    local page = pages[sectionName]
    entry.loading = true
    SectionManager.showStatus(page, "Loading " .. sectionName .. "...", false)

    local success, errorMessage = xpcall(entry.builder, function(message)
        local text = tostring(message)
        if debug and type(debug.traceback) == "function" then
            return debug.traceback(text, 2)
        end
        return text
    end)

    entry.loading = false
    if success then
        entry.loaded = true
        SectionManager.clearStatus(page)
        if state.refreshSearch then
            state.refreshSearch()
        end
        return true, nil
    end

    warn(
        "[Random Testing Menu] "
            .. sectionName
            .. " failed to initialize: "
            .. tostring(errorMessage)
    )
    SectionManager.showStatus(
        page,
        sectionName
            .. " INIT ERROR\n"
            .. tostring(errorMessage)
            .. "\n\nRe-execute the updated script after correcting this error.",
        true
    )
    return false, tostring(errorMessage)
end

function SectionManager.initializeAllAsync(): ()
    local sectionNames: {string} = {}
    for sectionName: string in pairs(SectionManager.entries) do
        table.insert(sectionNames, sectionName)
    end
    table.sort(sectionNames)

    local total: number = #sectionNames
    local completed: number = 0
    local failures: number = 0
    -- From here on the status line shows real counts, so the intro's scripted
    -- narration must stop writing to it.
    state.loadingLabelLocked = true
    if state.loadingLabel then
        state.loadingLabel.Text = "Loading modules 0/" .. tostring(total)
    end
    if state.loadingProgressFill then
        state.loadingProgressFill.Size = UDim2.fromScale(0, 1)
    end

    if total == 0 then
        if state.finishLoadingIntro then
            state.finishLoadingIntro(0)
        end
        return
    end

    for _, sectionName: string in ipairs(sectionNames) do
        task.spawn(function(): ()
            print("[RTM:Bootstrap] Inicializando sección " .. sectionName)
            local success: boolean, errorMessage: string? =
                SectionManager.initialize(sectionName)
            if not success then
                failures += 1
                warn(
                    "[RTM:Bootstrap] Sección "
                        .. sectionName
                        .. " falló: "
                        .. tostring(errorMessage)
                )
            end
            completed += 1
            if state.loadingLabel then
                state.loadingLabel.Text = "Loading modules "
                    .. tostring(completed)
                    .. "/"
                    .. tostring(total)
            end
            if state.loadingProgressFill then
                TweenService:Create(
                    state.loadingProgressFill,
                    TweenInfo.new(
                        0.2,
                        Enum.EasingStyle.Quart,
                        Enum.EasingDirection.Out
                    ),
                    {Size = UDim2.fromScale(completed / total, 1)}
                ):Play()
            end
            if completed >= total then
                print(
                    "[RTM:Bootstrap] Carga terminada · fallos="
                        .. tostring(failures)
                )
                task.delay(0.35, function(): ()
                    if state.finishLoadingIntro then
                        state.finishLoadingIntro(failures)
                    end
                end)
            end
        end)
    end
end

local function create(className, properties)
    local object = Instance.new(className)

    for property, value in pairs(properties or {}) do
        if property ~= "Parent" then
            object[property] = value
        end
    end

    if properties and properties.Parent then
        object.Parent = properties.Parent
    end

    return object
end

-- Shared corner-rounding curve.
--
-- Every square-ish surface in the menu goes through this helper instead of
-- hard-coding `UDim.new(0, n)`, so the whole shell keeps one consistent
-- silhouette. The curve is deliberately soft but restrained: corners read as
-- circular arcs rather than hard right angles, yet never turn into pills.
-- Genuine pills/circles (switch tracks, knobs, progress bars, radar) keep
-- using `UDim.new(1, 0)` directly and are unaffected.
--
-- The multiplier and clamp are inlined on purpose: `bootstrap()` is a single
-- enormous function scope and is close to Luau's 200 local-register ceiling,
-- so named constants here would cost registers for no benefit.
-- The window itself passes a larger radius so the shell reads as one smooth,
-- pill-shaped surface; the 30 cap keeps small controls from turning into
-- circles.
local function cornerRadius(radius: number): UDim
    return UDim.new(0, math.clamp(math.round(radius * 1.3), 5, 30))
end

local function addRoundedStyle(
    object: GuiObject,
    radius: number,
    strokeTransparency: number?
): (UICorner, UIStroke)
    local corner: UICorner = Instance.new("UICorner")
    corner.Name = "StyleCorner"
    corner.CornerRadius = cornerRadius(radius)
    corner.Parent = object

    local stroke: UIStroke = Instance.new("UIStroke")
    stroke.Name = "StyleStroke"
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = Theme.Outline
    stroke.Thickness = 1
    stroke.Transparency = strokeTransparency or 0.45
    stroke.Parent = object
    return corner, stroke
end

-- Every label registers the *logical* size it was designed at; the text-scale
-- slider multiplies that. `state.registeredTextIndex` lets the responsive
-- layout change a label's logical size later without the slider snapping it
-- back to the size it happened to be created with.
state.registeredTextIndex = setmetatable({}, {__mode = "k"}) :: any

local function registerText(
    object: TextLabel | TextButton | TextBox,
    normalSize: number
): TextLabel | TextButton | TextBox
    local entry: any = {
        object = object,
        normalSize = normalSize,
    }
    table.insert(registeredText, entry)
    state.registeredTextIndex[object] = entry

    object.TextSize = math.round(
        normalSize * TEXT_BASE_MULTIPLIER * state.textScale
    )
    return object
end

-- Sets the logical size of an already-registered label and applies it with
-- the current text scale.
state.setTextMetric = function(object: any, normalSize: number): ()
    local entry: any = state.registeredTextIndex[object]
    if entry then
        entry.normalSize = normalSize
    end
    object.TextSize = math.round(
        normalSize * TEXT_BASE_MULTIPLIER * state.textScale
    )
end

local function makeTextLabel(
    parent: Instance,
    text: string,
    normalSize: number?
): TextLabel
    return registerText(create("TextLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        FontFace = THIN_FONT,
        Text = text,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }), normalSize or 14) :: TextLabel
end

local function makeButton(
    parent: Instance,
    text: string,
    normalSize: number?
): TextButton
    local isDefaultStyle: boolean = state.guiStyle == "Default"
    local button = registerText(create("TextButton", {
        Parent = parent,
        AutoButtonColor = false,
        BackgroundColor3 = isDefaultStyle
            and Theme.DefaultButton
            or DEFAULT_SURFACE_COLOR,
        BorderSizePixel = 0,
        FontFace = CONTROL_FONT,
        Text = text,
        TextColor3 = isDefaultStyle
            and Theme.DefaultText
            or Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    }), normalSize or 14)

    addRoundedStyle(button, 9, 0.48)
    button:SetAttribute(
        "IdleColor",
        isDefaultStyle and Theme.DefaultButton or DEFAULT_SURFACE_COLOR
    )
    button:SetAttribute(
        "HoverColor",
        isDefaultStyle and Theme.DefaultButtonHover or Theme.SurfaceHover
    )
    button:SetAttribute(
        "PressedColor",
        isDefaultStyle and Theme.DefaultButtonPressed or Theme.SurfacePressed
    )
    table.insert(state.styledButtons, button)

    trackUiConnection(button.MouseEnter:Connect(function()
        if button:GetAttribute("NoHover") or button:GetAttribute("Disabled") then
            return
        end
        local configuredHover: any = button:GetAttribute("HoverColor")
        local hoverColor: Color3 = typeof(configuredHover) == "Color3"
            and configuredHover
            or Theme.SurfaceHover
        TweenService:Create(
            button,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundColor3 = hoverColor}
        ):Play()
    end))

    trackUiConnection(button.MouseLeave:Connect(function()
        if button:GetAttribute("NoHover") then
            return
        end
        local selectedColor: any = button:GetAttribute("SelectedColor")
        local configuredIdle: any = button:GetAttribute("IdleColor")
        local targetColor: Color3 = button:GetAttribute("Selected")
            and (typeof(selectedColor) == "Color3" and selectedColor or Theme.AccentSoft)
            or (typeof(configuredIdle) == "Color3"
                and configuredIdle
                or DEFAULT_SURFACE_COLOR)

        TweenService:Create(
            button,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundColor3 = targetColor}
        ):Play()
    end))

    trackUiConnection(button.MouseButton1Down:Connect(function(): ()
        if button:GetAttribute("Disabled")
            or button:GetAttribute("NoPressEffect") then
            return
        end
        local configuredPressed: any = button:GetAttribute("PressedColor")
        local pressedColor: Color3 = typeof(configuredPressed) == "Color3"
            and configuredPressed
            or Theme.SurfacePressed
        TweenService:Create(
            button,
            TweenInfo.new(0.08, Enum.EasingStyle.Quad),
            {BackgroundColor3 = pressedColor}
        ):Play()
    end))

    trackUiConnection(button.MouseButton1Up:Connect(function(): ()
        if button:GetAttribute("Disabled")
            or button:GetAttribute("NoPressEffect") then
            return
        end
        local selectedColor: any = button:GetAttribute("SelectedColor")
        local configuredHover: any = button:GetAttribute("HoverColor")
        local targetColor: Color3 = button:GetAttribute("Selected")
            and (typeof(selectedColor) == "Color3" and selectedColor or Theme.AccentSoft)
            or (typeof(configuredHover) == "Color3"
                and configuredHover
                or Theme.SurfaceHover)
        TweenService:Create(
            button,
            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad),
            {BackgroundColor3 = targetColor}
        ):Play()
    end))

    return button :: TextButton
end

local function setToggleSwitch(button: TextButton, enabled: boolean, animate: boolean?): ()
    button:SetAttribute("Checked", enabled)
    local track: Frame? = button:FindFirstChild("SwitchTrack") :: Frame?
    local knob: Frame? = track and track:FindFirstChild("Knob") :: Frame?
    if not track or not knob then
        return
    end
    local knobWidth: number = knob.Size.X.Offset
    local targetColor: Color3 = enabled and Theme.DefaultAccent or Theme.SurfacePressed
    local targetPosition: UDim2 = enabled
        and UDim2.new(1, -knobWidth - 3, 0.5, 0)
        or UDim2.new(0, 3, 0.5, 0)
    local targetKnobColor: Color3 = enabled and Theme.DefaultText or Theme.DefaultTextMuted
    if animate and state.animationsEnabled then
        TweenService:Create(track, TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quart), {
            BackgroundColor3 = targetColor,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quart), {
            Position = targetPosition,
            BackgroundColor3 = targetKnobColor,
        }):Play()
    else
        track.BackgroundColor3 = targetColor
        knob.Position = targetPosition
        knob.BackgroundColor3 = targetKnobColor
    end
end

local function createToggleSwitch(
    parent: Instance,
    enabled: boolean,
    width: number?
): TextButton
    local switchWidth: number = width or state.layout.switchWidth
    local switchHeight: number = state.layout.switchHeight
    local button: TextButton = create("TextButton", {
        Parent = parent,
        Active = true,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(switchWidth, math.max(32, switchHeight)),
        Text = "",
    }) :: TextButton
    local track: Frame = create("Frame", {
        Parent = button,
        Name = "SwitchTrack",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.SurfacePressed,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(switchWidth, switchHeight),
        ZIndex = button.ZIndex + 1,
    }) :: Frame
    create("UICorner", {Parent = track, CornerRadius = UDim.new(1, 0)})
    create("UIStroke", {
        Parent = track,
        Color = Theme.DefaultOutline,
        Transparency = 0.58,
        Thickness = 1,
    })
    local knobSize: number = switchHeight - 6
    local knob: Frame = create("Frame", {
        Parent = track,
        Name = "Knob",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.DefaultTextMuted,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(knobSize, knobSize),
        ZIndex = track.ZIndex + 2,
    }) :: Frame
    create("UICorner", {Parent = knob, CornerRadius = UDim.new(1, 0)})
    create("UIStroke", {
        Parent = knob,
        Color = Theme.DefaultOutline,
        Transparency = 0.35,
        Thickness = 1,
    })
    setToggleSwitch(button, enabled, false)
    return button
end

local function applyKeySlotStyle(button: TextButton): ()
    button.ZIndex = math.max(2, button.ZIndex)
    button.BackgroundColor3 = Theme.DefaultSurface
    button.BackgroundTransparency = 0.54
    button.TextColor3 = Theme.DefaultTextMuted
    button:SetAttribute("ThemeRole", "KeySlot")
    button:SetAttribute("IdleColor", Theme.DefaultSurface)
    button:SetAttribute("HoverColor", Theme.DefaultSurfaceHover)
    button:SetAttribute("PressedColor", Theme.DefaultButtonPressed)
    local buttonStroke: UIStroke? = button:FindFirstChildOfClass("UIStroke")
    if buttonStroke then
        buttonStroke.Color = Theme.DefaultOutline
        buttonStroke.Transparency = 0.78
    end
end

state.restyleButtons = function(isDefault: boolean): ()
    for _, button: TextButton in ipairs(state.styledButtons) do
        if button.Parent then
            local role: any = button:GetAttribute("ThemeRole")
            if role ~= "Navigation" and role ~= "Icon" then
                local idleColor: Color3 = isDefault
                    and Theme.DefaultButton
                    or DEFAULT_SURFACE_COLOR
                button:SetAttribute("IdleColor", idleColor)
                button:SetAttribute(
                    "HoverColor",
                    isDefault and Theme.DefaultButtonHover or Theme.SurfaceHover
                )
                button:SetAttribute(
                    "PressedColor",
                    isDefault and Theme.DefaultButtonPressed or Theme.SurfacePressed
                )
                if button:GetAttribute("Selected") ~= true then
                    button.BackgroundColor3 = idleColor
                end
                button.TextColor3 = isDefault and Theme.DefaultText or Theme.Text
                local stroke: UIStroke? =
                    button:FindFirstChild("StyleStroke") :: UIStroke?
                if stroke then
                    stroke.Enabled = true
                    stroke.Color = isDefault and Theme.DefaultOutline or Theme.Outline
                    stroke.Transparency = isDefault and 0.32 or 0.48
                end
                if role == "KeySlot" then
                    button.BackgroundColor3 = Theme.DefaultSurface
                    button.BackgroundTransparency = 0.54
                    button.TextColor3 = Theme.DefaultTextMuted
                    local keyStroke: UIStroke? =
                        button:FindFirstChild("StyleStroke") :: UIStroke?
                    if keyStroke then
                        keyStroke.Color = Theme.DefaultOutline
                        keyStroke.Transparency = 0.78
                    end
                end
            end
        end
    end
end

local function setKeySlotCapture(button: TextButton, active: boolean): ()
    local stroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
    TweenService:Create(
        button,
        TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            BackgroundColor3 = active
                and Theme.DefaultButtonPressed
                or Theme.DefaultSurface,
            TextColor3 = active
                and Theme.DefaultText
                or Theme.DefaultTextMuted,
        }
    ):Play()
    if stroke then
        TweenService:Create(
            stroke,
            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Transparency = active and 0.38 or 0.78}
        ):Play()
    end
end

local function beginKeyCapture(
    button: TextButton,
    callback: (Enum.KeyCode) -> ()
): ()
    if state.waitingForKey then
        state.waitingForKey = false
        if state.keybindButton then
            state.keybindButton.Text = state.toggleKey.Name
            setKeySlotCapture(state.keybindButton, false)
        end
    end
    if state.keyCaptureCancel then
        state.keyCaptureCancel()
    end
    button.Text = "..."
    setKeySlotCapture(button, true)
    local cancelled: boolean = false
    state.keyCaptureCancel = function(): ()
        if cancelled then
            return
        end
        cancelled = true
        state.keyCaptureCallback = nil
        state.keyCaptureCancel = nil
        setKeySlotCapture(button, false)
        if button.Parent and button:GetAttribute("CaptureIdleText") then
            button.Text = tostring(button:GetAttribute("CaptureIdleText"))
        end
    end
    state.keyCaptureCallback = function(keyCode: Enum.KeyCode): ()
        if cancelled then
            return
        end
        cancelled = true
        state.keyCaptureCancel = nil
        setKeySlotCapture(button, false)
        callback(keyCode)
    end
end

local function makeTextBox(parent: Instance, defaultText: any): TextBox
    local isDefaultStyle: boolean = state.guiStyle == "Default"
    local textBox: TextBox = (registerText(create("TextBox", {
        Parent = parent,
        BackgroundColor3 = isDefaultStyle
            and Theme.DefaultButtonPressed
            or Theme.Surface,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        FontFace = THIN_FONT,
        PlaceholderColor3 = isDefaultStyle
            and Theme.DefaultTextMuted
            or Theme.TextMuted,
        Text = tostring(defaultText),
        TextColor3 = isDefaultStyle
            and Theme.DefaultText
            or Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
    }), 13) :: any) :: TextBox
    addRoundedStyle(textBox, 9, 0.5)
    table.insert(state.styledTextBoxes, textBox)
    trackUiConnection(textBox.Focused:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {BackgroundColor3 = state.guiStyle == "Default"
                and Theme.DefaultButtonHover
                or Theme.SurfaceRaised}
        ):Play()
    end))
    trackUiConnection(textBox.FocusLost:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {BackgroundColor3 = state.guiStyle == "Default"
                and Theme.DefaultButtonPressed
                or Theme.Surface}
        ):Play()
    end))
    return textBox
end

state.restyleTextBoxes = function(isDefault: boolean): ()
    for _, textBox: TextBox in ipairs(state.styledTextBoxes) do
        if textBox.Parent then
            textBox.BackgroundColor3 = isDefault
                and Theme.DefaultButtonPressed
                or Theme.Surface
            textBox.TextColor3 = isDefault and Theme.DefaultText or Theme.Text
            textBox.PlaceholderColor3 = isDefault
                and Theme.DefaultTextMuted
                or Theme.TextMuted
            local stroke: UIStroke? =
                textBox:FindFirstChild("StyleStroke") :: UIStroke?
            if stroke then
                stroke.Color = isDefault and Theme.DefaultOutline or Theme.Outline
                stroke.Transparency = isDefault and 0.3 or 0.5
            end
        end
    end
end

local ToastContainer: Frame = (create("Frame", {
    Parent = PopupLayer,
    Name = "ToastContainer",
    AnchorPoint = Vector2.new(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -12, 1, -12),
    Size = UDim2.fromOffset(state.layout.compact and 220 or 300, 300),
    ZIndex = 300,
}) :: any) :: Frame

-- Toasts are a screen-level element, so they follow the viewport rather than
-- the shell: a 300px stack would cover most of a phone.
state.onLayout(function(metrics: LayoutMetrics): ()
    ToastContainer.Size = UDim2.fromOffset(metrics.compact and 220 or 300, 300)
end)

create("UIListLayout", {
    Parent = ToastContainer,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
})

local toastSequence: number = 0

local function notify(message: any): ()
    local text: string = tostring(message)
    print("[Random Testing Menu] " .. text)
    toastSequence += 1

    local toast: CanvasGroup = Instance.new("CanvasGroup")
    toast.Name = "Toast"
    toast.AutomaticSize = Enum.AutomaticSize.Y
    toast.BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultSurface
        or Theme.SurfaceRaised
    toast.BackgroundTransparency = state.guiStyle == "Default" and 0.12 or 0.04
    toast.BorderSizePixel = 0
    toast.GroupTransparency = 1
    toast.LayoutOrder = toastSequence
    toast.Size = UDim2.new(1, 0, 0, state.layout.compact and 46 or 50)
    toast.ZIndex = 301
    toast.Parent = ToastContainer

    create("UICorner", {
        Parent = toast,
        CornerRadius = cornerRadius(UI_RADIUS.panel),
    })
    create("UIStroke", {
        Parent = toast,
        Color = state.guiStyle == "Default"
            and Theme.DefaultOutline
            or Theme.Outline,
        Transparency = state.guiStyle == "Default" and 0.42 or 0.22,
        Thickness = 1,
    })
    local accent: Frame = (create("Frame", {
        Parent = toast,
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultAccent
            or Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 4, 1, 0),
        ZIndex = 302,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = accent,
        CornerRadius = UDim.new(1, 0),
    })

    local label: TextLabel = (makeTextLabel(toast, text, 12) :: any)
        :: TextLabel
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Position = UDim2.fromOffset(16, 10)
    label.Size = UDim2.new(1, -28, 0, 36)
    label.TextColor3 = state.guiStyle == "Default"
        and Theme.DefaultText
        or Theme.Text
    label.TextWrapped = true
    label.ZIndex = 303

    TweenService:Create(
        toast,
        TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {GroupTransparency = 0}
    ):Play()
    task.delay(3.1, function(): ()
        if not toast.Parent then
            return
        end
        local tween: Tween = TweenService:Create(
            toast,
            TweenInfo.new(
                0.2,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In
            ),
            {GroupTransparency = 1}
        )
        tween:Play()
        tween.Completed:Once(function(): ()
            toast:Destroy()
        end)
    end)
end
local initialCamera: Camera? = workspace.CurrentCamera
local initialViewport: Vector2 = initialCamera
    and initialCamera.ViewportSize
    or Vector2.new(1280, 720)

-- The shell size is no longer computed here: it comes from the responsive
-- metrics table, which already knows the device mode. The helper is kept as
-- the single accessor so every caller reads the same numbers.
local function calculateWindowSize(_viewport: Vector2): Vector2
    return Vector2.new(state.layout.shellWidth, state.layout.shellHeight)
end

-- Falling hail rendered over the blur.
--
-- The layer sits between the game and the menu window (ZIndex 0, below the
-- Main frame's default 1) and covers the whole screen, so stones fall from the
-- very top edge down past the bottom. It is driven entirely by the blur
-- controller through `state.registerBlurDecoration`, which means it can never
-- outlive the blur: closing the menu, disabling Blur mode or tearing the menu
-- down all stop it and hide it, exactly like the blur itself.
do
local HAIL_STONE_COUNT: number = state.layout.compact and 34 or 54
local HAIL_COLOR: Color3 = Color3.fromRGB(228, 231, 238)

type HailStone = {
    frame: Frame,
    x: number,
    y: number,
    fallSpeed: number,
    driftSpeed: number,
    swayAmount: number,
    swayRate: number,
    swayPhase: number,
    length: number,
}

local HailLayer: CanvasGroup = (create("CanvasGroup", {
    Parent = ScreenGui,
    Name = "BlurHail",
    Active = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    GroupTransparency = 1,
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    Visible = false,
    ZIndex = 0,
}) :: any) :: CanvasGroup

local hailRandom: Random = Random.new(os.clock() * 1000)
local hailStones: {HailStone} = {}

local function currentViewport(): Vector2
    local camera: Camera? = workspace.CurrentCamera
    local viewport: Vector2 = camera
        and camera.ViewportSize
        or Vector2.new(1280, 720)
    return Vector2.new(
        math.max(viewport.X, 320),
        math.max(viewport.Y, 240)
    )
end

-- `fromTop` seeds a stone just above the screen (used while falling);
-- otherwise the stone is scattered anywhere down the screen, which is what
-- makes the very first frame after opening the menu look like the hail has
-- already been going rather than a single synchronised wave.
local function respawnStone(
    stone: HailStone,
    viewport: Vector2,
    fromTop: boolean
): ()
    local thickness: number = hailRandom:NextNumber(2, 3.4)
    stone.length = hailRandom:NextNumber(7, 18)
    stone.fallSpeed = hailRandom:NextNumber(320, 680)
    stone.driftSpeed = hailRandom:NextNumber(-46, -12)
    stone.swayAmount = hailRandom:NextNumber(2, 9)
    stone.swayRate = hailRandom:NextNumber(0.7, 2.1)
    stone.swayPhase = hailRandom:NextNumber(0, math.pi * 2)
    stone.x = hailRandom:NextNumber(-40, viewport.X + 40)
    stone.y = fromTop
        and hailRandom:NextNumber(-viewport.Y * 0.4, -stone.length)
        or hailRandom:NextNumber(-stone.length, viewport.Y)

    stone.frame.Size = UDim2.fromOffset(
        math.round(thickness),
        math.round(stone.length)
    )
    -- Faster stones are drawn slightly brighter and leaning a touch further
    -- into the wind, which reads as depth without needing more particles.
    local depth: number = (stone.fallSpeed - 320) / 360
    stone.frame.BackgroundTransparency = 0.62 - depth * 0.34
    stone.frame.Rotation = -6 - depth * 5
end

for index: number = 1, HAIL_STONE_COUNT do
    local frame: Frame = (create("Frame", {
        Parent = HailLayer,
        Name = "Stone" .. tostring(index),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor3 = HAIL_COLOR,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(3, 12),
        ZIndex = 1,
    }) :: any) :: Frame
    create("UICorner", {Parent = frame, CornerRadius = UDim.new(1, 0)})

    local stone: HailStone = {
        frame = frame,
        x = 0,
        y = 0,
        fallSpeed = 0,
        driftSpeed = 0,
        swayAmount = 0,
        swayRate = 1,
        swayPhase = 0,
        length = 12,
    }
    respawnStone(stone, currentViewport(), false)
    hailStones[index] = stone
end

local hailConnection: RBXScriptConnection? = nil
local hailFadeTween: Tween? = nil
local hailRunning: boolean = false
local hailRequested: boolean = false
local hailElapsed: number = 0

local function drawStone(stone: HailStone): ()
    stone.frame.Position = UDim2.fromOffset(
        math.round(
            stone.x
                + math.sin(hailElapsed * stone.swayRate + stone.swayPhase)
                    * stone.swayAmount
        ),
        math.round(stone.y)
    )
end

local function stepHail(deltaTime: number): ()
    -- Guard against the huge delta a background//frozen client produces, which
    -- would otherwise teleport every stone off screen at once.
    local step: number = math.min(deltaTime, 1 / 20)
    hailElapsed += step
    local viewport: Vector2 = currentViewport()
    for _, stone: HailStone in ipairs(hailStones) do
        stone.y += stone.fallSpeed * step
        stone.x += stone.driftSpeed * step
        if stone.y - stone.length > viewport.Y
            or stone.x < -80
            or stone.x > viewport.X + 80 then
            respawnStone(stone, viewport, true)
        end
        drawStone(stone)
    end
end

local function disconnectHail(): ()
    if hailConnection then
        hailConnection:Disconnect()
        hailConnection = nil
    end
end

local function cancelHailFade(): ()
    if hailFadeTween then
        hailFadeTween:Cancel()
        hailFadeTween = nil
    end
end

local function applyHail(): ()
    -- Hail is motion, so it follows the "Animations" setting as well as the
    -- blur: with motion off the layer stays completely inert.
    local shouldRun: boolean = hailRequested
        and state.animationsEnabled ~= false
    if shouldRun == hailRunning then
        return
    end
    hailRunning = shouldRun
    cancelHailFade()

    if not HailLayer.Parent then
        disconnectHail()
        return
    end

    if shouldRun then
        local viewport: Vector2 = currentViewport()
        for _, stone: HailStone in ipairs(hailStones) do
            respawnStone(stone, viewport, false)
            drawStone(stone)
        end
        HailLayer.Visible = true
        disconnectHail()
        hailConnection = RunService.RenderStepped:Connect(stepHail)
        local fadeIn: Tween = TweenService:Create(
            HailLayer,
            TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {GroupTransparency = 0}
        )
        hailFadeTween = fadeIn
        fadeIn.Completed:Once(function(): ()
            if hailFadeTween == fadeIn then
                hailFadeTween = nil
            end
        end)
        fadeIn:Play()
        return
    end

    if state.animationsEnabled == false then
        disconnectHail()
        HailLayer.GroupTransparency = 1
        HailLayer.Visible = false
        return
    end

    local fadeOut: Tween = TweenService:Create(
        HailLayer,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {GroupTransparency = 1}
    )
    hailFadeTween = fadeOut
    fadeOut.Completed:Once(function(): ()
        if hailFadeTween == fadeOut then
            hailFadeTween = nil
        end
        -- A newer activation may have won the race while this faded out.
        if hailRunning then
            return
        end
        disconnectHail()
        if HailLayer.Parent then
            HailLayer.GroupTransparency = 1
            HailLayer.Visible = false
        end
    end)
    fadeOut:Play()
end

state.registerBlurDecoration(function(active: boolean): ()
    hailRequested = active
    applyHail()
end)

-- Called by the Animations setting so toggling motion takes effect without
-- having to close and reopen the menu.
state.refreshBlurDecoration = applyHail

-- Hard stop used during teardown: no tweens, no pending callbacks.
state.destroyBlurDecoration = function(): ()
    hailRequested = false
    hailRunning = false
    cancelHailFade()
    disconnectHail()
    if HailLayer.Parent then
        HailLayer.Visible = false
        HailLayer:Destroy()
    end
end
end

local initialWindowSize: Vector2 = calculateWindowSize(initialViewport)

local Main: Frame = (create("Frame", {
    Parent = ScreenGui,
    Name = "Main",
    Active = true,
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Theme.DefaultBackground,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(initialWindowSize.X, initialWindowSize.Y),
    ZIndex = 1,
}) :: any) :: Frame

-- Publish the window so the shared visibility controller defined above can
-- drive it without depending on later initialization order.
state.mainFrame = Main
Main.Visible = state.visible

do
-- The window carries no visible outline and, since this build, no drag
-- surface either: the shell is pinned to the middle of the screen and its
-- rounded silhouette is the only chrome. `MainStroke` is kept on `state` for
-- restyle compatibility, but always stays fully transparent so no grey border
-- ever frames the menu.
local _MainCorner: UICorner, MainStroke: UIStroke =
    addRoundedStyle(Main, state.layout.shellCorner, 1)
MainStroke.Thickness = 1
MainStroke.Color = Theme.DefaultOutline
MainStroke.Transparency = 1
state.mainStroke = MainStroke
end

local Content: Frame = nil :: any

-- The shell has exactly one position: the middle of the screen. It is
-- anchored at its own centre and positioned in scale, so a viewport change
-- can never leave it half off-screen and there is no geometry to persist.
local function centerMain(): ()
    local layout: LayoutMetrics = state.layout
    Main.AnchorPoint = Vector2.new(0.5, 0.5)
    Main.Position = UDim2.fromScale(0.5, 0.5)
    Main.Size = UDim2.fromOffset(layout.shellWidth, layout.shellHeight)
    -- The window owns the only shell radius now; the rail keeps its own in
    -- sync from the layout listener, because `ClipsDescendants` clips to the
    -- rectangle and not to the rounded corner.
    local shellCorner: Instance? = Main:FindFirstChild("StyleCorner")
    if shellCorner and shellCorner:IsA("UICorner") then
        shellCorner.CornerRadius = cornerRadius(layout.shellCorner)
    end
end

state.centerMain = centerMain
state.onLayout(function(): ()
    centerMain()
end)
task.defer(centerMain)

do
local layout: LayoutMetrics = state.layout
local sidebarWidth: number = layout.sidebarWidth

-- `Main` *is* the shell. There used to be a second full-size rounded frame
-- stacked inside it painted the same colour, which bought nothing and gave the
-- corners a second radius to keep in sync.
local DefaultShell: Frame = Main

-- Navigation rail.
--
-- Desktop and tablet show a monogram chip plus the tab name; on phones the
-- rail collapses to the chips alone, which is what frees the horizontal space
-- a 360px-wide screen needs for actual content.
--
-- The rail is rounded like the window because `ClipsDescendants` clips to the
-- window's *rectangle*, not to its rounded corner: a square-cornered rail
-- painted a lighter grey filled the shell's top-left and bottom-left corners
-- and read as a block sticking out behind the ARM chip. Its right-hand side is
-- squared off again by a patch the width of the radius, so only the two
-- corners that sit on the window edge are curved.
local DefaultSidebar: Frame = create("Frame", {
    Parent = DefaultShell,
    Name = "DefaultSidebar",
    Active = true,
    BackgroundColor3 = Theme.DefaultSidebar,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Size = UDim2.new(0, sidebarWidth, 1, 0),
    ZIndex = 10,
}) :: Frame
create("UICorner", {
    Parent = DefaultSidebar,
    Name = "SidebarCorner",
    CornerRadius = cornerRadius(layout.shellCorner),
})
local SidebarSquareEdge: Frame = create("Frame", {
    Parent = DefaultSidebar,
    Name = "SidebarSquareEdge",
    AnchorPoint = Vector2.new(1, 0),
    BackgroundColor3 = Theme.DefaultSidebar,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.new(0, math.max(6, layout.shellCorner), 1, 0),
    ZIndex = 10,
}) :: Frame

-- Hairline that separates the rail from the content instead of a full
-- gradient wash: denser, and it keeps the two regions readable at any size.
local SidebarEdge: Frame = create("Frame", {
    Parent = DefaultShell,
    Name = "SidebarEdge",
    BackgroundColor3 = Theme.DefaultOutline,
    BackgroundTransparency = 0.82,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(sidebarWidth, 0),
    Size = UDim2.new(0, 1, 1, 0),
    ZIndex = 12,
}) :: Frame

-- Wordmark. ARandomMenu keeps its own identity here: full name when the rail
-- is wide, initials when it is collapsed.
local BrandRow: Frame = create("Frame", {
    Parent = DefaultSidebar,
    Name = "Brand",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, layout.brandHeight),
    ZIndex = 13,
}) :: Frame
local BrandMark: TextLabel = makeTextLabel(BrandRow, "ARM", layout.captionFontSize)
BrandMark.Name = "BrandMark"
BrandMark.AnchorPoint = layout.sidebarCollapsed
    and Vector2.new(0.5, 0.5)
    or Vector2.new(0, 0.5)
BrandMark.BackgroundColor3 = Theme.DefaultSurface
BrandMark.BackgroundTransparency = 0.42
BrandMark.FontFace = CONTROL_FONT
BrandMark.Position = layout.sidebarCollapsed
    and UDim2.fromScale(0.5, 0.5)
    or UDim2.new(0, layout.sidebarPadding, 0.5, 0)
BrandMark.Size = UDim2.fromOffset(layout.navIconSize + 4, layout.navIconSize + 4)
BrandMark.TextColor3 = Theme.DefaultText
BrandMark.TextXAlignment = Enum.TextXAlignment.Center
BrandMark.ZIndex = 14
create("UICorner", {Parent = BrandMark, CornerRadius = cornerRadius(UI_RADIUS.chip)})
create("UIStroke", {
    Parent = BrandMark,
    Color = Theme.DefaultOutline,
    Transparency = 0.7,
    Thickness = 1,
})
local BrandIcon: ImageLabel = create("ImageLabel", {
    Parent = BrandMark,
    Name = "BrandIcon",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 15,
}) :: ImageLabel
create("UICorner", {
    Parent = BrandIcon,
    CornerRadius = cornerRadius(UI_RADIUS.chip),
})
if state.applyAssetImage then
    state.applyAssetImage("brandLogo", BrandIcon, function(): ()
        -- The monogram is the fallback; once the logo is up it would only
        -- print over the artwork.
        BrandMark.Text = ""
    end)
end
local BrandName: TextLabel = makeTextLabel(BrandRow, "A Random Menu", 10)
BrandName.Name = "BrandName"
BrandName.AnchorPoint = Vector2.new(0, 0.5)
BrandName.FontFace = CONTROL_FONT
BrandName.Position = UDim2.new(0, layout.sidebarPadding + layout.navIconSize + 12, 0.5, 0)
BrandName.Size = UDim2.new(1, -(layout.sidebarPadding * 2 + layout.navIconSize + 12), 0, 18)
BrandName.TextColor3 = Theme.DefaultTextMuted
BrandName.TextTruncate = Enum.TextTruncate.AtEnd
BrandName.Visible = not layout.sidebarCollapsed
BrandName.ZIndex = 14

local DefaultTabs: Frame = create("Frame", {
    Parent = DefaultSidebar,
    Name = "DefaultNavigation",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, layout.brandHeight),
    -- 60px at the foot of the rail belongs to the profile card, which sits
    -- above the floating-window launchers.
    Size = UDim2.new(
        1,
        0,
        1,
        -(layout.brandHeight + layout.launcherHeight + PROFILE_CARD_HEIGHT + 18)
    ),
    ZIndex = 11,
}) :: Frame
create("UIListLayout", {
    Parent = DefaultTabs,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 2),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
create("UIPadding", {
    Parent = DefaultTabs,
    Name = "NavigationPadding",
    PaddingLeft = UDim.new(0, layout.sidebarPadding),
    PaddingRight = UDim.new(0, layout.sidebarPadding),
    PaddingTop = UDim.new(0, 4),
})

local DefaultContentHost: Frame = create("Frame", {
    Parent = DefaultShell,
    Name = "DefaultContentHost",
    BackgroundColor3 = Theme.DefaultBackground,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(sidebarWidth + 1, 0),
    Size = UDim2.new(1, -(sidebarWidth + 1), 1, 0),
    ZIndex = 20,
}) :: Frame
DefaultContentHost.ClipsDescendants = true

-- Page header: the name of the page on the left, the search field on the
-- right. The search used to live in the rail, where a collapsed rail could
-- not host it; here it stays reachable in every mode.
local DefaultHeader: Frame = create("Frame", {
    Parent = DefaultContentHost,
    Name = "PageHeader",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, layout.headerHeight),
    ZIndex = 22,
}) :: Frame
local HeaderTitle: TextLabel = makeTextLabel(DefaultHeader, "Universal", 13)
HeaderTitle.Name = "PageTitle"
HeaderTitle.AnchorPoint = Vector2.new(0, 0.5)
HeaderTitle.FontFace = CONTROL_FONT
HeaderTitle.Position = UDim2.new(0, layout.contentPadding, 0.5, 0)
HeaderTitle.Size = UDim2.new(
    1,
    -(layout.contentPadding * 2 + layout.searchWidth + 10),
    0,
    20
)
HeaderTitle.TextColor3 = Theme.DefaultText
HeaderTitle.TextTruncate = Enum.TextTruncate.AtEnd
HeaderTitle.ZIndex = 23
local HeaderRule: Frame = create("Frame", {
    Parent = DefaultHeader,
    Name = "HeaderRule",
    AnchorPoint = Vector2.new(0, 1),
    BackgroundColor3 = Theme.DefaultOutline,
    BackgroundTransparency = 0.84,
    BorderSizePixel = 0,
    Position = UDim2.new(0, layout.contentPadding, 1, 0),
    Size = UDim2.new(1, -layout.contentPadding * 2, 0, 1),
    ZIndex = 23,
}) :: Frame

Content = create("Frame", {
    Parent = DefaultContentHost,
    Name = "SharedPageHost",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, layout.headerHeight),
    Size = UDim2.new(1, 0, 1, -layout.headerHeight),
    ZIndex = 21,
}) :: Frame
Content.ClipsDescendants = true

state.shells = {
    default = DefaultShell,
    defaultTabs = DefaultTabs,
    defaultContentHost = DefaultContentHost,
    defaultSidebar = DefaultSidebar,
    defaultHeader = DefaultHeader,
    headerTitle = HeaderTitle,
    brandName = BrandName,
    brandRow = BrandRow,
    sidebarEdge = SidebarEdge,
}

-- One listener re-flows the whole shell when the viewport (and therefore the
-- mode) changes. Nothing else in the file has to know the sidebar width.
state.onLayout(function(metrics: LayoutMetrics): ()
    local width: number = metrics.sidebarWidth
    local sidebarCorner: UICorner? =
        DefaultSidebar:FindFirstChild("SidebarCorner") :: UICorner?
    if sidebarCorner then
        sidebarCorner.CornerRadius = cornerRadius(metrics.shellCorner)
    end
    SidebarSquareEdge.Size =
        UDim2.new(0, math.max(6, metrics.shellCorner), 1, 0)
    DefaultSidebar.Size = UDim2.new(0, width, 1, 0)
    SidebarEdge.Position = UDim2.fromOffset(width, 0)
    BrandRow.Size = UDim2.new(1, 0, 0, metrics.brandHeight)
    BrandMark.AnchorPoint = metrics.sidebarCollapsed
        and Vector2.new(0.5, 0.5)
        or Vector2.new(0, 0.5)
    BrandMark.Position = metrics.sidebarCollapsed
        and UDim2.fromScale(0.5, 0.5)
        or UDim2.new(0, metrics.sidebarPadding, 0.5, 0)
    BrandMark.Size = UDim2.fromOffset(metrics.navIconSize + 4, metrics.navIconSize + 4)
    BrandName.Position =
        UDim2.new(0, metrics.sidebarPadding + metrics.navIconSize + 12, 0.5, 0)
    BrandName.Size = UDim2.new(
        1,
        -(metrics.sidebarPadding * 2 + metrics.navIconSize + 12),
        0,
        18
    )
    BrandName.Visible = not metrics.sidebarCollapsed
    DefaultTabs.Position = UDim2.fromOffset(0, metrics.brandHeight)
    DefaultTabs.Size = UDim2.new(
        1,
        0,
        1,
        -(metrics.brandHeight + metrics.launcherHeight + PROFILE_CARD_HEIGHT + 18)
    )
    local navigationPadding: UIPadding? =
        DefaultTabs:FindFirstChild("NavigationPadding") :: UIPadding?
    if navigationPadding then
        navigationPadding.PaddingLeft = UDim.new(0, metrics.sidebarPadding)
        navigationPadding.PaddingRight = UDim.new(0, metrics.sidebarPadding)
    end
    DefaultContentHost.Position = UDim2.fromOffset(width + 1, 0)
    DefaultContentHost.Size = UDim2.new(1, -(width + 1), 1, 0)
    DefaultHeader.Size = UDim2.new(1, 0, 0, metrics.headerHeight)
    HeaderTitle.Position = UDim2.new(0, metrics.contentPadding, 0.5, 0)
    HeaderTitle.Size = UDim2.new(
        1,
        -(metrics.contentPadding * 2 + metrics.searchWidth + 10),
        0,
        20
    )
    HeaderRule.Position = UDim2.new(0, metrics.contentPadding, 1, 0)
    HeaderRule.Size = UDim2.new(1, -metrics.contentPadding * 2, 0, 1)
    Content.Position = UDim2.fromOffset(0, metrics.headerHeight)
    Content.Size = UDim2.new(1, 0, 1, -metrics.headerHeight)
end)
end

local function setTab(tabName: string): ()
    state.activeTab = tabName

    for name, page in pairs(pages) do
        local selectedPage: boolean = name == tabName
        page.Visible = selectedPage
    end

    local headerTitle: TextLabel? = state.shells.headerTitle
    if headerTitle then
        headerTitle.Text = tabName == "Config." and "Settings" or tabName
    end

    for name: string, button: TextButton in pairs(defaultTabButtons) do
        local selected: boolean = name == tabName
        button:SetAttribute("Selected", selected)
        button.BackgroundColor3 = selected
            and Theme.DefaultSurface
            or Theme.DefaultSidebar
        button.BackgroundTransparency = selected and 0.34 or 1
        button.TextColor3 = selected and Theme.DefaultText or Theme.DefaultTextMuted
        local navLabel: TextLabel? = button:FindFirstChild("NavLabel") :: TextLabel?
        if navLabel then
            navLabel.TextColor3 = selected
                and Theme.DefaultText
                or Theme.DefaultTextMuted
        end
        local tabStroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
        if tabStroke then
            tabStroke.Color = Theme.DefaultOutline
            tabStroke.Transparency = selected and 0.78 or 1
        end
        -- The monogram chip is the only thing left when the rail collapses,
        -- so it carries the selection state too.
        local monogram: TextLabel? = button:FindFirstChild("Monogram") :: TextLabel?
        if monogram then
            monogram.TextColor3 = selected
                and Theme.DefaultText
                or Theme.DefaultTextMuted
            monogram.BackgroundTransparency = selected and 0.28 or 0.62
        end
        -- Selected rows get an accent tick on their leading edge: a compact
        -- selection cue that survives the icon-only rail.
        local marker: Frame? = button:FindFirstChild("SelectionMarker") :: Frame?
        if marker then
            marker.Visible = selected
        end
    end
end

local function createTab(tabName: string, layoutOrder: number): Frame
    local layout: LayoutMetrics = state.layout
    local defaultLabel: string = tabName == "Config." and "Settings" or tabName
    -- The row itself carries no text: a monogram chip and a separate label
    -- are laid out inside it. A UIPadding on the button would also shift its
    -- children, which is exactly what the chip must not do.
    local defaultButton: TextButton = makeButton(
        state.shells.defaultTabs,
        "",
        layout.navFontSize
    )
    defaultButton.Name = tabName .. "DefaultTab"
    defaultButton.LayoutOrder = layoutOrder
    defaultButton.Size = UDim2.new(1, 0, 0, layout.navRowHeight)
    defaultButton.BackgroundColor3 = Theme.DefaultSidebar
    defaultButton.BackgroundTransparency = 1
    defaultButton.TextColor3 = Theme.DefaultTextMuted
    defaultButton.TextXAlignment = Enum.TextXAlignment.Left
    defaultButton.ZIndex = 12
    defaultButton:SetAttribute("ThemeRole", "Navigation")
    defaultButton:SetAttribute("SelectedColor", Theme.DefaultSurface)
    defaultButton:SetAttribute("IdleColor", Theme.DefaultSidebar)
    defaultButton:SetAttribute("HoverColor", Theme.DefaultSurfaceHover)
    defaultButton:SetAttribute("NavigationLabel", defaultLabel)
    local buttonCorner: UICorner? =
        defaultButton:FindFirstChild("StyleCorner") :: UICorner?
    if buttonCorner then
        buttonCorner.CornerRadius = cornerRadius(UI_RADIUS.control)
    end
    local marker: Frame = create("Frame", {
        Parent = defaultButton,
        Name = "SelectionMarker",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.DefaultAccent,
        BorderSizePixel = 0,
        Position = UDim2.new(0, -6, 0.5, 0),
        Size = UDim2.fromOffset(2, math.max(10, layout.navRowHeight - 16)),
        Visible = false,
        ZIndex = 14,
    }) :: Frame
    create("UICorner", {Parent = marker, CornerRadius = UDim.new(1, 0)})

    local monogram: TextLabel = makeTextLabel(
        defaultButton,
        TAB_MONOGRAMS[tabName] or string.upper(string.sub(tabName, 1, 2)),
        layout.captionFontSize
    )
    monogram.Name = "Monogram"
    monogram.AnchorPoint = Vector2.new(0, 0.5)
    monogram.BackgroundColor3 = Theme.DefaultSurface
    monogram.BackgroundTransparency = 0.62
    monogram.FontFace = CONTROL_FONT
    monogram.Position = UDim2.new(0, 0, 0.5, 0)
    monogram.Size = UDim2.fromOffset(layout.navIconSize, layout.navIconSize)
    monogram.TextColor3 = Theme.DefaultTextMuted
    monogram.TextXAlignment = Enum.TextXAlignment.Center
    monogram.ZIndex = 13
    create("UICorner", {Parent = monogram, CornerRadius = cornerRadius(UI_RADIUS.chip)})

    local tabIcon: ImageLabel = create("ImageLabel", {
        Parent = monogram,
        Name = "TabIcon",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        ImageTransparency = 0.08,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 14,
    }) :: ImageLabel
    create("UICorner", {
        Parent = tabIcon,
        CornerRadius = cornerRadius(UI_RADIUS.chip),
    })
    do
        local gameIconId: number? = TAB_GAME_ICONS[tabName]
        local drawnIcon: string? = TAB_DRAWN_ICONS[tabName]
        if gameIconId then
            -- 0 means "whatever place we are in", which is what the Universal
            -- tab is: the game you are actually playing.
            local resolvedId: number = gameIconId > 0 and gameIconId or game.PlaceId
            tabIcon.Image = "rbxthumb://type=GameIcon&id="
                .. tostring(resolvedId)
                .. "&w=150&h=150"
            monogram.Text = ""
        elseif drawnIcon and state.applyAssetImage then
            state.applyAssetImage(drawnIcon, tabIcon, function(): ()
                monogram.Text = ""
            end)
        end
    end

    local navLabel: TextLabel = makeTextLabel(
        defaultButton,
        defaultLabel,
        layout.navFontSize
    )
    navLabel.Name = "NavLabel"
    navLabel.AnchorPoint = Vector2.new(0, 0.5)
    navLabel.FontFace = CONTROL_FONT
    navLabel.Position = UDim2.new(0, layout.navIconSize + 10, 0.5, 0)
    navLabel.Size = UDim2.new(1, -(layout.navIconSize + 16), 1, 0)
    navLabel.TextColor3 = Theme.DefaultTextMuted
    navLabel.TextTruncate = Enum.TextTruncate.AtEnd
    navLabel.Visible = not layout.sidebarCollapsed
    navLabel.ZIndex = 13

    defaultTabButtons[tabName] = defaultButton

    local page: Frame = create("Frame", {
        Parent = Content,
        Name = tabName .. "Page",
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 22,
    })
    page.ClipsDescendants = true
    pages[tabName] = page

    trackUiConnection(defaultButton.MouseButton1Click:Connect(function(): ()
        setTab(tabName)
    end))

    return page
end

-- Navigation rows re-flow with the mode: the label disappears when the rail
-- collapses and the monogram slides to the middle of the chip column.
state.onLayout(function(metrics: LayoutMetrics): ()
    for _, button: TextButton in pairs(defaultTabButtons) do
        button.Size = UDim2.new(1, 0, 0, metrics.navRowHeight)
        local navLabel: TextLabel? = button:FindFirstChild("NavLabel") :: TextLabel?
        if navLabel then
            navLabel.Visible = not metrics.sidebarCollapsed
            navLabel.Position = UDim2.new(0, metrics.navIconSize + 10, 0.5, 0)
            navLabel.Size = UDim2.new(1, -(metrics.navIconSize + 16), 1, 0)
            state.setTextMetric(navLabel, metrics.navFontSize)
        end
        local monogram: TextLabel? = button:FindFirstChild("Monogram") :: TextLabel?
        if monogram then
            monogram.Size = UDim2.fromOffset(metrics.navIconSize, metrics.navIconSize)
            monogram.AnchorPoint = metrics.sidebarCollapsed
                and Vector2.new(0.5, 0.5)
                or Vector2.new(0, 0.5)
            monogram.Position = metrics.sidebarCollapsed
                and UDim2.fromScale(0.5, 0.5)
                or UDim2.new(0, 0, 0.5, 0)
        end
        local marker: Frame? = button:FindFirstChild("SelectionMarker") :: Frame?
        if marker then
            marker.Size = UDim2.fromOffset(2, math.max(10, metrics.navRowHeight - 16))
        end
    end
end)

local UniversalPage = createTab("Universal", 1)
local MovementPage = createTab("Movement", 2)
local MM2Page = createTab("MM2", 3)
createTab("TRS", 4)
createTab("VD", 5)
createTab("MVSD", 6)
local SettingsPage = createTab("Config.", 7)
local function configureGameTabs(): ()
    defaultTabButtons.MM2.Visible = GAME_CHECK.MM2Active
    defaultTabButtons.TRS.Visible = GAME_CHECK.TRSActive
    defaultTabButtons.VD.Visible = GAME_CHECK.VDActive
    defaultTabButtons.MVSD.Visible = GAME_CHECK.MVSDActive

    for _, button: TextButton in pairs(defaultTabButtons) do
        if button.Visible then
            button.Size = UDim2.new(1, 0, 0, state.layout.navRowHeight)
        end
    end
end

configureGameTabs()

do
-- Search lives in the page header, not in the rail: on a phone the rail is
-- only wide enough for the monogram chips.
local searchLayout: LayoutMetrics = state.layout
local DefaultSearchBox: TextBox = makeTextBox(state.shells.defaultHeader, "")
DefaultSearchBox.Name = "DefaultSearch"
DefaultSearchBox.PlaceholderText = "Search modules"
DefaultSearchBox.AnchorPoint = Vector2.new(1, 0.5)
DefaultSearchBox.Position = UDim2.new(1, -searchLayout.contentPadding, 0.5, 0)
DefaultSearchBox.Size =
    UDim2.fromOffset(searchLayout.searchWidth, searchLayout.searchHeight)
DefaultSearchBox.BackgroundColor3 = Theme.DefaultSurface
DefaultSearchBox.BackgroundTransparency = 0.38
DefaultSearchBox.TextColor3 = Theme.DefaultText
DefaultSearchBox.PlaceholderColor3 = Theme.DefaultTextMuted:Lerp(
    Theme.DefaultSurface,
    0.42
)
DefaultSearchBox.TextXAlignment = Enum.TextXAlignment.Left
DefaultSearchBox.TextYAlignment = Enum.TextYAlignment.Center
DefaultSearchBox.ZIndex = 24
-- The clear button sits on the leading edge, so the text always starts after
-- it and the field never looks like it has a stray glyph floating on the right.
create("UIPadding", {
    Parent = DefaultSearchBox,
    PaddingLeft = UDim.new(0, 26),
    PaddingRight = UDim.new(0, 10),
})
local DefaultSearchCorner: UICorner? =
    DefaultSearchBox:FindFirstChild("StyleCorner") :: UICorner?
if DefaultSearchCorner then
    DefaultSearchCorner.CornerRadius = cornerRadius(UI_RADIUS.control)
end
local DefaultSearchStroke: UIStroke? =
    DefaultSearchBox:FindFirstChild("StyleStroke") :: UIStroke?
if DefaultSearchStroke then
    DefaultSearchStroke.Color = Theme.DefaultOutline
    DefaultSearchStroke.Transparency = 0.72
end
local SearchClear: TextButton = makeButton(DefaultSearchBox, "x", 9)
SearchClear.Name = "ClearSearch"
SearchClear.AnchorPoint = Vector2.new(0, 0.5)
SearchClear.BackgroundTransparency = 1
SearchClear.Position = UDim2.new(0, -22, 0.5, 0)
SearchClear.Size = UDim2.fromOffset(22, 22)
SearchClear.TextTransparency = 0.45
SearchClear.Visible = false
SearchClear.ZIndex = 26
SearchClear:SetAttribute("ThemeRole", "Icon")
local SearchClearStroke: UIStroke? =
    SearchClear:FindFirstChild("StyleStroke") :: UIStroke?
if SearchClearStroke then
    SearchClearStroke.Enabled = false
end
trackUiConnection(SearchClear.MouseButton1Click:Connect(function(): ()
    DefaultSearchBox.Text = ""
    DefaultSearchBox:ReleaseFocus()
end))
trackUiConnection(DefaultSearchBox.Focused:Connect(function(): ()
    if DefaultSearchStroke then
        TweenService:Create(DefaultSearchStroke, TweenInfo.new(UI_MOTION.base), {
            Transparency = 0.32,
        }):Play()
    end
end))
trackUiConnection(DefaultSearchBox.FocusLost:Connect(function(): ()
    if DefaultSearchStroke then
        TweenService:Create(DefaultSearchStroke, TweenInfo.new(UI_MOTION.base), {
            Transparency = 0.72,
        }):Play()
    end
end))
state.shells.defaultSearchBox = DefaultSearchBox
state.shells.searchClear = SearchClear
state.searchQuery = ""

state.onLayout(function(metrics: LayoutMetrics): ()
    DefaultSearchBox.Position = UDim2.new(1, -metrics.contentPadding, 0.5, 0)
    DefaultSearchBox.Size =
        UDim2.fromOffset(metrics.searchWidth, metrics.searchHeight)
end)
end

local UniversalScroll = create("ScrollingFrame", {
    Parent = UniversalPage,
    Name = "UniversalScroll",
    Active = true,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarImageColor3 = Theme.DefaultOutline,
    ScrollBarThickness = 6,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Size = UDim2.fromScale(1, 1),
})

create("UIPadding", {
    Parent = UniversalScroll,
    PaddingBottom = UDim.new(0, 18),
    PaddingLeft = UDim.new(0, 18),
    PaddingRight = UDim.new(0, 18),
    PaddingTop = UDim.new(0, 18),
})

create("UIListLayout", {
    Parent = UniversalScroll,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 9),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

state.trsScroll = create("ScrollingFrame", {
    Parent = pages.TRS,
    Name = "TRSScroll",
    Active = true,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarImageColor3 = Theme.DefaultOutline,
    ScrollBarThickness = 6,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Size = UDim2.fromScale(1, 1),
})

create("UIPadding", {
    Parent = state.trsScroll,
    PaddingBottom = UDim.new(0, 18),
    PaddingLeft = UDim.new(0, 18),
    PaddingRight = UDim.new(0, 18),
    PaddingTop = UDim.new(0, 18),
})

create("UIListLayout", {
    Parent = state.trsScroll,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 9),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

state.vdScroll = create("ScrollingFrame", {
    Parent = pages.VD,
    Name = "VDScroll",
    Active = true,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarImageColor3 = Theme.DefaultOutline,
    ScrollBarThickness = 6,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Size = UDim2.fromScale(1, 1),
})

create("UIPadding", {
    Parent = state.vdScroll,
    PaddingBottom = UDim.new(0, 18),
    PaddingLeft = UDim.new(0, 18),
    PaddingRight = UDim.new(0, 18),
    PaddingTop = UDim.new(0, 18),
})

create("UIListLayout", {
    Parent = state.vdScroll,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 9),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

state.mvsdScroll = create("ScrollingFrame", {
    Parent = pages.MVSD,
    Name = "MVSDScroll",
    Active = true,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarImageColor3 = Theme.DefaultOutline,
    ScrollBarThickness = 6,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Size = UDim2.fromScale(1, 1),
})

create("UIPadding", {
    Parent = state.mvsdScroll,
    PaddingBottom = UDim.new(0, 18),
    PaddingLeft = UDim.new(0, 18),
    PaddingRight = UDim.new(0, 18),
    PaddingTop = UDim.new(0, 18),
})

create("UIListLayout", {
    Parent = state.mvsdScroll,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 9),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

do
-- Loading intro.
--
-- The intro is a staged sequence rather than a spinner that vanishes the
-- moment the last module reports in:
--
--   1. the curtain fades up with a slow drifting backdrop glow,
--   2. the wordmark rises into place letter-block by letter-block,
--   3. a ring sweeps while the status line reports each loading stage,
--   4. the progress bar fills, "Ready" is held briefly so it can be read,
--   5. the whole curtain lifts away.
--
-- Steps 1-3 take roughly 1.1s of scripted animation before any narration, so
-- the intro always reads as an intro even when every module loads instantly.
-- A slow load simply keeps stage 3 on screen for longer; nothing here ever
-- delays a slow load further. `state.finishLoadingIntro` may be called at any
-- point, including before the sequence has finished: it records the request
-- and the sequence picks it up at the next stage boundary.
local LoadingCurtain: CanvasGroup = (create("CanvasGroup", {
    Parent = Main,
    Name = "LoadingIntro",
    Active = true,
    -- Deliberately darker than the shell itself: the intro should read as
    -- black, and the shell fades up out of it.
    BackgroundColor3 = Color3.fromRGB(4, 4, 5),
    BackgroundTransparency = state.guiStyle == "Default" and 0 or 0.02,
    BorderSizePixel = 0,
    -- Fully opaque from frame one: the half-built menu behind it must never
    -- flash. The stage-1 "fade up" animates the contents, not the curtain.
    GroupTransparency = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 500,
}) :: any) :: CanvasGroup
create("UICorner", {
    Parent = LoadingCurtain,
    CornerRadius = cornerRadius(state.layout.shellCorner),
})

-- Slow, oversized radial wash behind everything. It is a plain frame with a
-- gradient rather than an image so it costs nothing and needs no asset.
local LoadingGlow: Frame = create("Frame", {
    Parent = LoadingCurtain,
    Name = "Glow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    -- Near-black: the backdrop wash used to be a pale grey at 0.86, which lit
    -- the whole curtain and made the intro read as grey rather than dark.
    BackgroundColor3 = Color3.fromRGB(46, 46, 52),
    BackgroundTransparency = 0.94,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.42),
    Size = UDim2.fromScale(1.4, 0.9),
    ZIndex = 501,
}) :: Frame
create("UIGradient", {
    Parent = LoadingGlow,
    Rotation = 12,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.62),
        NumberSequenceKeypoint.new(1, 1),
    }),
})
-- Breathing loop. Only the size pulses: transparency is owned by the stage-1
-- fade-in, and two tweens fighting over one property would stutter.
local LoadingGlowTween: Tween = TweenService:Create(
    LoadingGlow,
    TweenInfo.new(
        4.2,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut,
        -1,
        true
    ),
    {Size = UDim2.fromScale(1.8, 1.15)}
)
LoadingGlowTween:Play()

local LoadingSpinner: Frame = create("Frame", {
    Parent = LoadingCurtain,
    Name = "Spinner",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.33),
    Size = UDim2.fromOffset(state.layout.compact and 40 or 46, state.layout.compact and 40 or 46),
    ZIndex = 503,
}) :: Frame
create("UICorner", {Parent = LoadingSpinner, CornerRadius = UDim.new(1, 0)})
create("UIStroke", {
    Parent = LoadingSpinner,
    Color = Theme.DefaultOutline,
    Transparency = 0.78,
    Thickness = 2,
})
local LoadingSpinnerHead: Frame = create("Frame", {
    Parent = LoadingSpinner,
    AnchorPoint = Vector2.new(0.5, 0),
    BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultAccent
        or Color3.fromRGB(224, 224, 228),
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 0, 0, 2),
    Size = UDim2.fromOffset(6, 6),
    ZIndex = 504,
}) :: Frame
create("UICorner", {Parent = LoadingSpinnerHead, CornerRadius = UDim.new(1, 0)})

-- Second, slower counter-rotating ring. Two rings at different speeds read as
-- a deliberate loading animation instead of a default busy indicator.
local LoadingSpinnerOuter: Frame = create("Frame", {
    Parent = LoadingCurtain,
    Name = "SpinnerOuter",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.33),
    Size = UDim2.fromOffset(state.layout.compact and 62 or 70, state.layout.compact and 62 or 70),
    ZIndex = 502,
}) :: Frame
create("UICorner", {Parent = LoadingSpinnerOuter, CornerRadius = UDim.new(1, 0)})
create("UIStroke", {
    Parent = LoadingSpinnerOuter,
    Color = Theme.DefaultOutline,
    Transparency = 0.92,
    Thickness = 1,
})
local LoadingSpinnerOuterHead: Frame = create("Frame", {
    Parent = LoadingSpinnerOuter,
    AnchorPoint = Vector2.new(0.5, 0),
    BackgroundColor3 = Color3.fromRGB(190, 190, 198),
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 0, 0, 1),
    Size = UDim2.fromOffset(4, 4),
    ZIndex = 503,
}) :: Frame
create("UICorner", {
    Parent = LoadingSpinnerOuterHead,
    CornerRadius = UDim.new(1, 0),
})

local LoadingSpinnerTween: Tween = TweenService:Create(
    LoadingSpinner,
    TweenInfo.new(
        1.05,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.InOut,
        -1
    ),
    {Rotation = 360}
)
LoadingSpinnerTween:Play()
local LoadingSpinnerOuterTween: Tween = TweenService:Create(
    LoadingSpinnerOuter,
    TweenInfo.new(
        2.6,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.InOut,
        -1
    ),
    {Rotation = -360}
)
LoadingSpinnerOuterTween:Play()

local LoadingTitle: TextLabel = makeTextLabel(
    LoadingCurtain,
    "A Random Menu",
    state.layout.compact and 26 or 30
) :: TextLabel
LoadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
LoadingTitle.FontFace = DISPLAY_FONT
LoadingTitle.Position = UDim2.fromScale(0.5, 0.55)
LoadingTitle.Size = UDim2.new(0.8, 0, 0, 48)
LoadingTitle.TextColor3 = state.guiStyle == "Default"
    and Theme.DefaultText
    or Theme.Text
LoadingTitle.TextTransparency = 1
LoadingTitle.TextXAlignment = Enum.TextXAlignment.Center
LoadingTitle.ZIndex = 503

-- Hairline underline that draws itself out from the centre beneath the
-- wordmark once the wordmark itself has settled.
local LoadingTitleRule: Frame = create("Frame", {
    Parent = LoadingCurtain,
    Name = "TitleRule",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(200, 200, 208),
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.615),
    Size = UDim2.fromOffset(0, 1),
    ZIndex = 503,
}) :: Frame

local LoadingLabel: TextLabel = (makeTextLabel(
    LoadingCurtain,
    "Starting up",
    12
) :: any) :: TextLabel
LoadingLabel.AnchorPoint = Vector2.new(0.5, 0)
LoadingLabel.FontFace = THIN_FONT
LoadingLabel.Position = UDim2.fromScale(0.5, 0.655)
LoadingLabel.Size = UDim2.new(0.72, 0, 0, 28)
LoadingLabel.TextColor3 = state.guiStyle == "Default"
    and Theme.DefaultTextMuted
    or Theme.TextMuted
LoadingLabel.TextTransparency = 1
LoadingLabel.TextXAlignment = Enum.TextXAlignment.Center
LoadingLabel.ZIndex = 503
state.loadingLabel = LoadingLabel
bootstrapStatusLabel = LoadingLabel

local LoadingTrack: Frame = create("Frame", {
    Parent = LoadingCurtain,
    Name = "ProgressTrack",
    AnchorPoint = Vector2.new(0.5, 0),
    BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultSurface
        or Color3.fromRGB(40, 40, 46),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.725),
    Size = UDim2.new(0.48, 0, 0, 3),
    ZIndex = 503,
}) :: Frame
create("UICorner", {Parent = LoadingTrack, CornerRadius = UDim.new(1, 0)})
local LoadingProgressFill: Frame = create("Frame", {
    Parent = LoadingTrack,
    Name = "Progress",
    BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultAccent
        or Theme.Accent,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(0, 1),
    ZIndex = 504,
}) :: Frame
create("UICorner", {Parent = LoadingProgressFill, CornerRadius = UDim.new(1, 0)})
state.loadingProgressFill = LoadingProgressFill

local LoadingBuildLabel: TextLabel = (makeTextLabel(
    LoadingCurtain,
    RUNTIME_BUILD_LABEL,
    10
) :: any) :: TextLabel
LoadingBuildLabel.Name = "BuildLabel"
LoadingBuildLabel.AnchorPoint = Vector2.new(0.5, 1)
LoadingBuildLabel.FontFace = THIN_FONT
LoadingBuildLabel.Position = UDim2.new(0.5, 0, 1, -14)
LoadingBuildLabel.Size = UDim2.new(0.6, 0, 0, 18)
LoadingBuildLabel.TextColor3 = Theme.DefaultTextMuted
LoadingBuildLabel.TextTransparency = 1
LoadingBuildLabel.TextXAlignment = Enum.TextXAlignment.Center
LoadingBuildLabel.ZIndex = 503

-- Sequencing state.
--
-- `introStageReached` is how far the scripted sequence has progressed;
-- `finishRequested` records that loading completed. The exit only runs once
-- both "the sequence reached its last stage" and "loading finished" hold.
local loadingIntroFinished: boolean = false
local finishRequested: boolean = false
local finishFailureCount: number = 0
local introSequenceDone: boolean = false
local exitStarted: boolean = false

local function fadeText(label: TextLabel, target: number, duration: number): ()
    TweenService:Create(
        label,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {TextTransparency = target}
    ):Play()
end

local function runExit(): ()
    if exitStarted or not LoadingCurtain.Parent then
        return
    end
    exitStarted = true

    if finishFailureCount > 0 then
        LoadingLabel.Text = tostring(finishFailureCount)
            .. " module(s) loaded with warnings"
    else
        LoadingLabel.Text = "Ready"
    end
    TweenService:Create(
        LoadingProgressFill,
        TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Size = UDim2.fromScale(1, 1)}
    ):Play()

    -- Hold "Ready" long enough to actually be read, then lift the curtain
    -- with a slight upward drift so it feels like a door opening.
    task.delay(0.55, function(): ()
        if not LoadingCurtain.Parent then
            return
        end
        TweenService:Create(
            LoadingCurtain,
            TweenInfo.new(0.34, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Position = UDim2.fromScale(0, -0.05)}
        ):Play()
        local exitTween: Tween = TweenService:Create(
            LoadingCurtain,
            TweenInfo.new(
                0.42,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out
            ),
            {GroupTransparency = 1}
        )
        exitTween:Play()
        exitTween.Completed:Once(function(): ()
            LoadingSpinnerTween:Cancel()
            LoadingSpinnerOuterTween:Cancel()
            LoadingGlowTween:Cancel()
            LoadingCurtain:Destroy()
        end)
    end)
end

-- The scripted opening. Runs on its own thread so a slow module load never
-- blocks it and it never blocks a module load.
task.spawn(function(): ()
    -- 1. Backdrop settles. The curtain is already opaque; this is the glow
    -- easing up from nothing so the screen does not start fully lit.
    LoadingGlow.BackgroundTransparency = 1
    TweenService:Create(
        LoadingGlow,
        TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0.86}
    ):Play()
    task.wait(0.3)
    if not LoadingCurtain.Parent then
        return
    end

    -- 2. Wordmark rises and fades in, then the rule draws out under it.
    LoadingTitle.Position = UDim2.fromScale(0.5, 0.6)
    TweenService:Create(
        LoadingTitle,
        TweenInfo.new(0.52, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = UDim2.fromScale(0.5, 0.55), TextTransparency = 0}
    ):Play()
    task.wait(0.26)
    if not LoadingCurtain.Parent then
        return
    end
    TweenService:Create(
        LoadingTitleRule,
        TweenInfo.new(0.46, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(state.layout.compact and 150 or 210, 1)}
    ):Play()
    fadeText(LoadingBuildLabel, 0.42, 0.4)
    task.wait(0.24)
    if not LoadingCurtain.Parent then
        return
    end

    -- 3. Status line and progress bar arrive together.
    fadeText(LoadingLabel, 0, 0.3)
    TweenService:Create(
        LoadingTrack,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0}
    ):Play()

    -- Narrate the boot until the module loader starts reporting real
    -- progress. `state.loadingLabelLocked` is raised by SectionManager the
    -- moment it has genuine "Loading modules x/y" counts to show; the
    -- narration must not fight it, and a fast load must not be made to sit
    -- through a script it has already outrun.
    for _, message: string in ipairs({
        "Preparing interface",
        "Registering modules",
        "Linking game profile",
    }) do
        if finishRequested
            or bootstrapFailed
            or state.loadingLabelLocked
            or not LoadingCurtain.Parent then
            break
        end
        LoadingLabel.Text = message
        task.wait(0.32)
    end

    introSequenceDone = true
    if finishRequested then
        runExit()
    end
end)

-- Watchdog. `runExit` is normally driven by the sequence thread; if that
-- thread ever dies unexpectedly the curtain must still come down rather than
-- covering the menu forever.
task.delay(12, function(): ()
    -- A failed bootstrap leaves its error on this very curtain, so the
    -- watchdog must leave it up in that case.
    if LoadingCurtain.Parent and not exitStarted and not bootstrapFailed then
        warn("[Random Testing Menu] Loading intro watchdog fired")
        introSequenceDone = true
        runExit()
    end
end)

state.finishLoadingIntro = function(failureCount: number): ()
    if loadingIntroFinished or not LoadingCurtain.Parent then
        return
    end
    loadingIntroFinished = true
    finishRequested = true
    finishFailureCount = failureCount
    -- If the opening sequence is still playing, let it reach its last stage
    -- and call `runExit` itself; otherwise exit now.
    if introSequenceDone then
        runExit()
    end
end
end

-- Make the shell usable before any optional feature/module initialization runs.
-- A later runtime error must never leave every page hidden.
UniversalScroll.Visible = true
UniversalScroll.CanvasSize = UDim2.fromOffset(0, 0)
setTab("Universal")
print("[RTM:Bootstrap] GUI base visible; construyendo funciones universales")

local universalFeatures = {}
local movementFeatures = {}
local mm2Features = {}
state.trsFeatures = {}
state.vdFeatures = {}
state.mvsdFeatures = {}
local allFeatures: {any} = {}
local featureConnections = {}

-- Every module card re-applies the responsive metrics through its own
-- `applyLayout` hook when the viewport mode changes. Registering the listener
-- once here (instead of once per card) keeps the listener list short and means
-- a card created later is still covered: the pass walks the live registry.
state.onLayout(function(): ()
    for _, feature: any in ipairs(allFeatures) do
        if type(feature.applyLayout) == "function" then
            local ok: boolean, failure: any = pcall(feature.applyLayout)
            if not ok then
                warn("[Random Testing Menu] card layout: " .. tostring(failure))
            end
        end
    end
end)
state.tooltipConnections = {} :: {RBXScriptConnection}
state.bindFeatureTooltip = nil :: ((any, string) -> ())?

type MobileHoldCallbacks = {
    -- Asked at press time. A binding can become (or stop being) a hold after
    -- the button was placed, so the answer cannot be baked in at creation.
    isActive: (() -> boolean)?,
    onPress: (() -> ())?,
    onRelease: (() -> ())?,
}

type MobileActionRecord = {
    id: string,
    label: string,
    button: TextButton,
    callback: () -> (),
    -- Hold-style features (Sprint) drive press/release instead of a single
    -- tap, so a finger on the button behaves exactly like a held key.
    hold: MobileHoldCallbacks?,
    holding: boolean,
    activeInput: InputObject?,
    startPointer: Vector2,
    startPosition: Vector2,
    moved: boolean,
    holdToken: number,
    connections: {RBXScriptConnection},
}

type PendingMobilePlacement = {
    id: string,
    label: string,
    callback: () -> (),
    hold: MobileHoldCallbacks?,
    restoreMenu: boolean,
}

do
local mobileActions: {[string]: MobileActionRecord} = {}
local pendingMobilePlacement: PendingMobilePlacement? = nil

local MobilePlacementOverlay: Frame = (create("Frame", {
    Parent = PopupLayer,
    Name = "MobilePlacementOverlay",
    Active = true,
    BackgroundColor3 = Theme.DefaultBackground,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Visible = false,
    ZIndex = 200,
}) :: any) :: Frame
local MobilePlacementLabel = makeTextLabel(
    MobilePlacementOverlay,
    "TOUCH WHERE THE ACTION BUTTON SHOULD GO",
    16
)
MobilePlacementLabel.FontFace = CONTROL_FONT
MobilePlacementLabel.TextXAlignment = Enum.TextXAlignment.Center
MobilePlacementLabel.Position = UDim2.new(0.08, 0, 0.08, 0)
MobilePlacementLabel.Size = UDim2.new(0.84, 0, 0, 54)
MobilePlacementLabel.ZIndex = 201

local function ensureMobileConfig(): {[string]: any}
    if type(configData.ui.mobileActions) ~= "table" then
        configData.ui.mobileActions = {}
    end
    return configData.ui.mobileActions
end

local function clampMobileButtonPosition(
    position: Vector2,
    size: number
): Vector2
    local camera: Camera? = workspace.CurrentCamera
    local viewport: Vector2 = camera
        and camera.ViewportSize
        or Vector2.new(1280, 720)
    local radius: number = size / 2
    return Vector2.new(
        math.clamp(position.X, radius + 6, math.max(radius + 6, viewport.X - radius - 6)),
        math.clamp(position.Y, radius + 6, math.max(radius + 6, viewport.Y - radius - 6))
    )
end

local function saveMobileActionPosition(record: MobileActionRecord): ()
    local mobileConfig: {[string]: any} = ensureMobileConfig()
    mobileConfig[record.id] = {
        record.button.Position.X.Offset,
        record.button.Position.Y.Offset,
    }
    queueConfigSave()
end

local function removeMobileAction(id: string): ()
    local record: MobileActionRecord? = mobileActions[id]
    if not record then
        return
    end
    mobileActions[id] = nil
    ensureMobileConfig()[id] = nil
    for _, connection: RBXScriptConnection in ipairs(record.connections) do
        connection:Disconnect()
    end
    table.clear(record.connections)
    if record.button.Parent then
        record.button:Destroy()
    end
    queueConfigSave()
    notify(record.label .. " mobile button removed.")
end

local function setMobileActionVisibility(menuVisible: boolean): ()
    for _, record: MobileActionRecord in pairs(mobileActions) do
        record.button.Visible = state.isMobile and not menuVisible
    end
end
state.setMobileActionVisibility = setMobileActionVisibility

local function createMobileAction(
    id: string,
    label: string,
    callback: () -> (),
    requestedPosition: Vector2?,
    hold: MobileHoldCallbacks?
): MobileActionRecord?
    if not state.isMobile then
        return nil
    end

    local existing: MobileActionRecord? = mobileActions[id]
    if existing then
        existing.callback = callback
        existing.label = label
        existing.hold = hold
        return existing
    end

    local size: number = state.mobileButtonSize
    local stored: any = ensureMobileConfig()[id]
    local actionCount: number = 0
    for _ in pairs(mobileActions) do
        actionCount += 1
    end
    local defaultPosition: Vector2 = Vector2.new(
        74 + (actionCount * (size + 10)),
        math.max(size, initialViewport.Y - size - 70)
    )
    local selectedPosition: Vector2 = requestedPosition or (
        type(stored) == "table"
            and Vector2.new(
                tonumber(stored[1]) or defaultPosition.X,
                tonumber(stored[2]) or defaultPosition.Y
            )
            or defaultPosition
    )
    selectedPosition = clampMobileButtonPosition(selectedPosition, size)

    local button = create("TextButton", {
        Parent = ScreenGui,
        Name = "MobileAction_" .. id:gsub("%W", ""),
        Active = true,
        AutoButtonColor = false,
        BackgroundColor3 = Theme.SurfaceRaised,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        FontFace = CONTROL_FONT,
        Position = UDim2.fromOffset(selectedPosition.X, selectedPosition.Y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        Text = label,
        TextColor3 = Theme.Text,
        -- Wrapped and auto-scaled: a long module name is shown in full at a
        -- smaller size instead of being clipped to its first few letters.
        TextScaled = true,
        TextWrapped = true,
        Visible = not state.visible,
        ZIndex = 180,
    }) :: TextButton
    create("UIPadding", {
        Parent = button,
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        PaddingTop = UDim.new(0, 4),
    })
    create("UICorner", {
        Parent = button,
        CornerRadius = cornerRadius(12),
    })
    create("UIStroke", {
        Parent = button,
        Color = Theme.DefaultOutline,
        Transparency = 0.55,
        Thickness = 1,
    })
    create("UITextSizeConstraint", {
        Parent = button,
        MaxTextSize = 12,
        MinTextSize = 6,
    })

    local record: MobileActionRecord = {
        id = id,
        label = label,
        button = button,
        callback = callback,
        hold = hold,
        holding = false,
        activeInput = nil,
        startPointer = Vector2.zero,
        startPosition = selectedPosition,
        moved = false,
        holdToken = 0,
        connections = {},
    }
    mobileActions[id] = record
    saveMobileActionPosition(record)

    table.insert(record.connections, trackUiConnection(
        button.InputBegan:Connect(function(input: InputObject): ()
        if input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        record.activeInput = input
        record.startPointer = Vector2.new(input.Position.X, input.Position.Y)
        record.startPosition = Vector2.new(
            button.Position.X.Offset,
            button.Position.Y.Offset
        )
        record.moved = false
        -- Hold features engage on touch-down and stay engaged until the
        -- finger lifts, so Sprint behaves like a real hold button. Everything
        -- else stays a tap and fires on release.
        local hold: MobileHoldCallbacks? = record.hold
        local holdActive: boolean = hold ~= nil
            and hold.onPress ~= nil
            and (hold.isActive == nil or (hold.isActive :: () -> boolean)())
        if holdActive and not record.holding then
            record.holding = true
            button.BackgroundTransparency = 0.02
            task.spawn((hold :: MobileHoldCallbacks).onPress :: () -> ())
        end
        record.holdToken += 1
        local token: number = record.holdToken
        -- Hold-to-remove would fight a hold *feature*: keeping a finger on the
        -- Sprint button is how you sprint, not how you delete it. Those are
        -- removed from the menu instead, by tapping their key slot again.
        if not holdActive then
            task.delay(0.85, function(): ()
                if mobileActions[id] == record
                    and record.activeInput == input
                    and not record.moved
                    and record.holdToken == token then
                    record.activeInput = nil
                    removeMobileAction(id)
                    notify(record.label .. " button removed.")
                end
            end)
        end
    end)))

    table.insert(record.connections, trackUiConnection(
        UserInputService.InputEnded:Connect(function(
        input: InputObject
    ): ()
        if input.UserInputType ~= Enum.UserInputType.Touch
            or record.activeInput ~= input then
            return
        end
        record.activeInput = nil
        record.holdToken += 1
        if record.holding then
            record.holding = false
            button.BackgroundTransparency = 0.18
            if record.hold and record.hold.onRelease then
                task.spawn(record.hold.onRelease)
            end
            if record.moved then
                saveMobileActionPosition(record)
            end
        elseif record.moved then
            saveMobileActionPosition(record)
        else
            TweenService:Create(
                button,
                TweenInfo.new(0.08, Enum.EasingStyle.Quad),
                {BackgroundTransparency = 0.03}
            ):Play()
            task.delay(0.09, function(): ()
                if button.Parent then
                    TweenService:Create(
                        button,
                        TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad),
                        {BackgroundTransparency = 0.18}
                    ):Play()
                end
            end)
            task.spawn(record.callback)
        end
    end)))

    return record
end

trackUiConnection(UserInputService.InputChanged:Connect(function(
    input: InputObject
): ()
    if input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    for _, record: MobileActionRecord in pairs(mobileActions) do
        if record.activeInput == input then
            local pointer: Vector2 = Vector2.new(
                input.Position.X,
                input.Position.Y
            )
            local delta: Vector2 = pointer - record.startPointer
            if delta.Magnitude >= 7 then
                record.moved = true
                if record.holding then
                    -- The finger is repositioning the button, not using it.
                    record.holding = false
                    record.button.BackgroundTransparency = 0.18
                    if record.hold and record.hold.onRelease then
                        task.spawn(record.hold.onRelease)
                    end
                end
            end
            if record.moved then
                local position: Vector2 = clampMobileButtonPosition(
                    record.startPosition + delta,
                    record.button.AbsoluteSize.X
                )
                record.button.Position = UDim2.fromOffset(
                    position.X,
                    position.Y
                )
            end
        end
    end
end))

local function beginMobileActionPlacement(
    id: string,
    label: string,
    callback: () -> (),
    hold: MobileHoldCallbacks?
): ()
    if not state.isMobile then
        return
    end
    if mobileActions[id] then
        removeMobileAction(id)
        notify(label .. " button removed.")
        return
    end

    pendingMobilePlacement = {
        id = id,
        label = label,
        callback = callback,
        hold = hold,
        restoreMenu = state.visible,
    }
    MobilePlacementLabel.Text = "TOUCH TO PLACE " .. string.upper(label)
        .. (hold
            and "\nHOLD THE BUTTON TO KEEP IT ACTIVE"
            or "\nHOLD THE CIRCLE LATER TO REMOVE IT")
    MobilePlacementOverlay.Visible = true
    Main.Visible = false
    -- The menu is hidden for placement, so drop the blur rather than leaving
    -- the screen dimmed behind the overlay.
    state.suspendBlur()

    local placement: PendingMobilePlacement =
        pendingMobilePlacement :: PendingMobilePlacement
    task.delay(8, function(): ()
        if pendingMobilePlacement == placement then
            pendingMobilePlacement = nil
            MobilePlacementOverlay.Visible = false
            if placement.restoreMenu then
                state.setMenuVisible(true)
            end
            notify("Mobile button placement cancelled.")
        end
    end)
end

trackUiConnection(MobilePlacementOverlay.InputBegan:Connect(function(
    input: InputObject
): ()
    local placement: PendingMobilePlacement? = pendingMobilePlacement
    if not placement
        or input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    pendingMobilePlacement = nil
    MobilePlacementOverlay.Visible = false
    createMobileAction(
        placement.id,
        placement.label,
        placement.callback,
        Vector2.new(input.Position.X, input.Position.Y),
        placement.hold
    )
    if placement.restoreMenu then
        state.setMenuVisible(true)
    end
    notify(placement.label .. " mobile button placed.")
end))

-- Touch key slots are the mobile-button factory.
--
-- A single tap opens placement mode (a second tap on an already-placed button
-- removes it). It used to need a 0.6s hold, which nothing on screen hinted at
-- and which is impossible to guess now that an unbound slot is blank.
local function bindMobileActionPlacement(
    source: TextButton,
    id: string,
    label: string,
    callback: () -> (),
    hold: MobileHoldCallbacks?
): ()
    if not state.isMobile then
        return
    end

    trackUiConnection(source.MouseButton1Click:Connect(function(): ()
        beginMobileActionPlacement(id, label, callback, hold)
    end))

    if ensureMobileConfig()[id] ~= nil then
        createMobileAction(id, label, callback, nil, hold)
    end
end
state.bindMobileActionPlacement = bindMobileActionPlacement

local MobileMenuButton = create("TextButton", {
    Parent = ScreenGui,
    Name = "MobileMenuButton",
    AutoButtonColor = false,
    BackgroundColor3 = Theme.DefaultSurface,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    FontFace = CONTROL_FONT,
    Position = UDim2.new(1, -18, 0, 18),
    AnchorPoint = Vector2.new(1, 0),
    Size = UDim2.fromOffset(52, 52),
    Text = "RTM",
    TextColor3 = Theme.Text,
    TextSize = 11,
    Visible = state.isMobile,
    ZIndex = 190,
}) :: TextButton
create("UICorner", {
    Parent = MobileMenuButton,
    CornerRadius = UDim.new(1, 0),
})
create("UIStroke", {
    Parent = MobileMenuButton,
    Color = Theme.DefaultOutline,
    Transparency = 0.55,
    Thickness = 1,
})

-- The launcher wears the menu's own logo, cropped to the button's circle. The
-- "RTM" lettering underneath stays as the fallback for executors that cannot
-- turn a downloaded file into an asset id.
local MobileMenuIcon: ImageLabel = create("ImageLabel", {
    Parent = MobileMenuButton,
    Name = "BrandIcon",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 191,
}) :: ImageLabel
create("UICorner", {Parent = MobileMenuIcon, CornerRadius = UDim.new(1, 0)})
if state.applyAssetImage then
    state.applyAssetImage("brandLogo", MobileMenuIcon, function(): ()
        MobileMenuButton.Text = ""
    end)
end

trackUiConnection(MobileMenuButton.MouseButton1Click:Connect(function(): ()
    state.setMenuVisible(not state.visible)
end))

-- The launcher is the way back in, so it only exists while the menu is out of
-- sight. It used to sit on top of the open window, which made it look like a
-- second, broken close button.
local function refreshLauncherVisibility(): ()
    MobileMenuButton.Visible = state.isMobile and not state.visible
end
refreshLauncherVisibility()
state.addMenuVisibilityListener(function(): ()
    refreshLauncherVisibility()
end)
state.refreshLauncherVisibility = refreshLauncherVisibility

local function resetMobileActions(): ()
    local ids: {string} = {}
    for id: string in pairs(mobileActions) do
        table.insert(ids, id)
    end
    for _, id: string in ipairs(ids) do
        removeMobileAction(id)
    end
    configData.ui.mobileActions = {}
    queueConfigSave()
end
state.resetMobileActions = resetMobileActions
state.mobileUi = {
    actions = mobileActions,
    setActionVisibility = setMobileActionVisibility,
    resetActions = resetMobileActions,
    clampButtonPosition = clampMobileButtonPosition,
    saveActionPosition = saveMobileActionPosition,
}
-- Placed mobile shortcuts are the inverse of the menu, and this is wired up as
-- soon as the mobile layer exists rather than waiting for the Settings tab.
state.addMenuVisibilityListener(setMobileActionVisibility)
end

type TaskHandle = {
    Connected: boolean,
    Disconnect: (self: TaskHandle) -> (),
}

type ScheduledTask = {
    callback: (...any) -> (),
    handle: TaskHandle,
    failures: number,
}

local TaskManager = {
    tasks = {} :: {[number]: ScheduledTask},
    nextId = 0,
    connection = nil :: RBXScriptConnection?,
}

function TaskManager:Connect(callback: (...any) -> ()): TaskHandle
    self.nextId += 1
    local taskId: number = self.nextId
    local handle: TaskHandle
    handle = {
        Connected = true,
        Disconnect = function(selfHandle: TaskHandle): ()
            if not selfHandle.Connected then
                return
            end
            selfHandle.Connected = false
            TaskManager.tasks[taskId] = nil
        end,
    }
    self.tasks[taskId] = {
        callback = callback,
        handle = handle,
        failures = 0,
    }
    return handle
end

function TaskManager:Destroy(): ()
    for taskId: number, scheduled: ScheduledTask in pairs(self.tasks) do
        scheduled.handle.Connected = false
        self.tasks[taskId] = nil
    end
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

TaskManager.connection = RunService.Heartbeat:Connect(function(
    deltaTime: number
): ()
    for taskId: number, scheduled: ScheduledTask in pairs(TaskManager.tasks) do
        if scheduled.handle.Connected then
            local success: boolean, message: any = pcall(
                scheduled.callback,
                deltaTime
            )
            if success then
                scheduled.failures = 0
            else
                scheduled.failures += 1
                warn(
                    "[Random Testing Menu] scheduled task "
                        .. tostring(taskId)
                        .. " failed: "
                        .. tostring(message)
                )
                if scheduled.failures >= 3 then
                    scheduled.handle:Disconnect()
                end
            end
        end
    end
end)

state.taskManager = TaskManager

-- Generic, automatic projectile telemetry. This dataset is intentionally isolated
-- from every game-specific predictor; MM2 never reads or merges these values.
state.universalProjectileCalibration = (function(): any
    type PendingActivation = {
        tool: Tool,
        activatedAt: number,
        origin: Vector3?,
        aim: Vector3?,
        pingMs: number,
    }
    type ProjectileSample = {
        t: number,
        position: {number},
        velocity: {number},
        speed: number,
    }
    type ProjectileTrack = {
        instance: BasePart,
        toolName: string,
        projectileName: string,
        startedAt: number,
        launchDelayMs: number,
        pingMs: number,
        origin: Vector3,
        previousAt: number?,
        previousPosition: Vector3?,
        speeds: {number},
        accelerations: {number},
        verticalAccelerations: {number},
        samples: {ProjectileSample},
        distance: number,
        destroyConnection: RBXScriptConnection?,
    }
    type BucketRecord = {
        count: number,
        speedSum: number,
        speedSquaredSum: number,
        delaySum: number,
    }
    type Controller = {
        setEnabled: (self: Controller, enabled: boolean) -> (),
        save: (self: Controller, reason: string?) -> boolean,
        delete: (self: Controller) -> boolean,
        status: (self: Controller) -> string,
        destroy: (self: Controller) -> (),
        settings: {[string]: number},
    }

    -- Live-tuning knobs for the analyser. The option panel mutates these
    -- while the tracker keeps running, so a calibration session can be
    -- refined without restarting it.
    local settings: {[string]: number} = {
        bucketWidthMs = 5,
        maxBucketMs = 250,
        sampleWindowSeconds = 2.5,
        maxSamplesPerTrack = 150,
        minProjectileSpeed = 10,
        matchDistanceStuds = 40,
        maxPendingActivations = 10,
        candidateLifetimeSeconds = 1.1,
    }

    local executorEnvironment: {[string]: any} = getfenv() :: any
    local mouse: Mouse = LocalPlayer:GetMouse()
    local outputRoot: string = "RandomTestingMenu0001"
    local outputTelemetry: string = outputRoot .. "/Telemetry"
    local outputFolder: string = outputTelemetry .. "/Universal"
    local outputPath: string = outputFolder
        .. "/Place_"
        .. tostring(game.PlaceId)
        .. "_Projectile_Calibration.json"
    local runtime: any = {
        enabled = false,
        dirty = false,
        startedAt = os.clock(),
        pending = {} :: {PendingActivation},
        tracks = {} :: {[BasePart]: ProjectileTrack},
        events = {} :: {{[string]: any}},
        buckets = {} :: {[string]: BucketRecord},
        connections = {} :: {RBXScriptConnection},
        observedTools = setmetatable({}, {__mode = "k"}) :: {[Tool]: boolean},
        observedCandidates = setmetatable({}, {__mode = "k"}) :: {[BasePart]: boolean},
        sampler = nil :: any,
        totalActivations = 0,
        totalProjectiles = 0,
        rejectedCandidates = 0,
    }
    local controller: Controller
    local saveSnapshot: (reason: string) -> boolean
    local finishTrack: (part: BasePart, reason: string) -> ()

    local function finite(value: number): boolean
        return value == value and value > -math.huge and value < math.huge
    end

    local function vectorArray(value: Vector3): {number}
        return {value.X, value.Y, value.Z}
    end

    local function median(values: {number}): number?
        if #values == 0 then
            return nil
        end
        local sorted: {number} = table.clone(values)
        table.sort(sorted)
        local middle: number = math.floor((#sorted + 1) / 2)
        if #sorted % 2 == 1 then
            return sorted[middle]
        end
        return (sorted[middle] + sorted[middle + 1]) * 0.5
    end

    local function pingBucketKey(pingMs: number): string
        local width: number = math.max(1, settings.bucketWidthMs)
        local ceiling: number = math.max(width, settings.maxBucketMs)
        if pingMs > ceiling then
            return tostring(ceiling) .. "+"
        end
        local lower: number = math.clamp(
            math.floor(pingMs / width) * width,
            0,
            math.max(0, ceiling - width)
        )
        local upper: number = lower + width
        return string.format("%03d-%03d", lower, upper)
    end

    local function ensureBucket(key: string): BucketRecord
        local existing: BucketRecord? = runtime.buckets[key]
        if existing then
            return existing
        end
        local created: BucketRecord = {
            count = 0,
            speedSum = 0,
            speedSquaredSum = 0,
            delaySum = 0,
        }
        runtime.buckets[key] = created
        return created
    end

    local function bucketPayload(): {[string]: any}
        local payload: {[string]: any} = {}
        for key: string, bucket: BucketRecord in pairs(runtime.buckets) do
            local meanSpeed: number = bucket.count > 0
                    and bucket.speedSum / bucket.count
                or 0
            local variance: number = bucket.count > 1
                    and math.max(
                        0,
                        bucket.speedSquaredSum / bucket.count
                            - meanSpeed * meanSpeed
                    )
                or 0
            payload[key] = {
                count = bucket.count,
                meanSpeed = meanSpeed,
                speedStdDev = math.sqrt(variance),
                meanLaunchDelayMs = bucket.count > 0
                        and bucket.delaySum / bucket.count
                    or 0,
            }
        end
        return payload
    end

    local function getPingMilliseconds(): number
        local pingMs: number = 0
        pcall(function(): ()
            local network: Instance? = Stats:FindFirstChild("Network")
            local serverItems: Instance? = network
                and network:FindFirstChild("ServerStatsItem")
            local pingItem: any = serverItems
                and serverItems:FindFirstChild("Data Ping")
            if pingItem and type(pingItem.GetValue) == "function" then
                pingMs = tonumber(pingItem:GetValue()) or 0
            end
        end)
        return math.max(0, pingMs)
    end

    local function appendEvent(event: {[string]: any}): ()
        if #runtime.events >= 180 then
            table.remove(runtime.events, 1)
        end
        table.insert(runtime.events, event)
        runtime.dirty = true
    end

    saveSnapshot = function(reason: string): boolean
        if type(executorEnvironment.writefile) ~= "function" then
            warn("[RTM:UniversalTrajectory] writefile no está disponible.")
            return false
        end
        local payload: {[string]: any} = {
            schema = 1,
            kind = "universal-projectile-analytics",
            placeId = game.PlaceId,
            gameId = game.GameId,
            savedAt = DateTime.now():ToIsoDate(),
            reason = reason,
            bucketSpec = {
                metric = "Data Ping",
                widthMs = settings.bucketWidthMs,
                minimumMs = 0,
                maximumMs = settings.maxBucketMs,
                overflow = tostring(settings.maxBucketMs) .. "+",
            },
            summary = {
                activations = runtime.totalActivations,
                projectiles = runtime.totalProjectiles,
                rejectedCandidates = runtime.rejectedCandidates,
                elapsedSeconds = os.clock() - runtime.startedAt,
            },
            pingBuckets = bucketPayload(),
            projectiles = runtime.events,
        }
        local encodedOk: boolean, encoded: any = pcall(
            HttpService.JSONEncode,
            HttpService,
            payload
        )
        if not encodedOk or type(encoded) ~= "string" then
            warn("[RTM:UniversalTrajectory] JSONEncode falló: " .. tostring(encoded))
            return false
        end
        if type(executorEnvironment.makefolder) == "function" then
            pcall(executorEnvironment.makefolder, outputRoot)
            pcall(executorEnvironment.makefolder, outputTelemetry)
            pcall(executorEnvironment.makefolder, outputFolder)
        end
        local writeOk: boolean, writeError: any = pcall(
            executorEnvironment.writefile,
            outputPath,
            encoded
        )
        if not writeOk then
            warn("[RTM:UniversalTrajectory] writefile falló: " .. tostring(writeError))
            return false
        end
        runtime.dirty = false
        print(
            "[RTM:UniversalTrajectory] Guardado "
                .. outputPath
                .. " ("
                .. tostring(#encoded)
                .. " bytes)"
        )
        return true
    end

    local function disconnectAll(): ()
        if runtime.sampler then
            runtime.sampler:Disconnect()
            runtime.sampler = nil
        end
        for _, connection: RBXScriptConnection in ipairs(runtime.connections) do
            connection:Disconnect()
        end
        table.clear(runtime.connections)
        for part: BasePart, track: ProjectileTrack in pairs(runtime.tracks) do
            if track.destroyConnection then
                track.destroyConnection:Disconnect()
            end
            runtime.tracks[part] = nil
        end
        table.clear(runtime.pending)
        runtime.observedTools = setmetatable({}, {__mode = "k"})
        runtime.observedCandidates = setmetatable({}, {__mode = "k"})
    end

    local function compactPending(now: number): ()
        while #runtime.pending > 0
            and now - runtime.pending[1].activatedAt
                > settings.candidateLifetimeSeconds do
            table.remove(runtime.pending, 1)
        end
        while #runtime.pending > settings.maxPendingActivations do
            table.remove(runtime.pending, 1)
        end
    end

    local function isCharacterPart(part: BasePart): boolean
        local model: Model? = part:FindFirstAncestorOfClass("Model")
        return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function hasProjectileHint(part: BasePart): boolean
        local name: string = string.lower(part.Name)
        local parentName: string = part.Parent and string.lower(part.Parent.Name) or ""
        local combined: string = name .. " " .. parentName
        return string.find(combined, "projectile", 1, true) ~= nil
            or string.find(combined, "bullet", 1, true) ~= nil
            or string.find(combined, "arrow", 1, true) ~= nil
            or string.find(combined, "rocket", 1, true) ~= nil
            or string.find(combined, "missile", 1, true) ~= nil
            or string.find(combined, "knife", 1, true) ~= nil
            or string.find(combined, "grenade", 1, true) ~= nil
            or string.find(combined, "shell", 1, true) ~= nil
            or string.find(combined, "bolt", 1, true) ~= nil
            or string.find(combined, "orb", 1, true) ~= nil
            or part:GetAttribute("Projectile") == true
            or part:GetAttribute("ProjectileSpeed") ~= nil
            or part:GetAttribute("ThrowSpeed") ~= nil
    end

    local function resolveCandidate(instance: Instance): BasePart?
        if not instance:IsA("BasePart") then
            return nil
        end
        local part: BasePart = instance
        if part.Anchored
            or isCharacterPart(part)
            or (LocalPlayer.Character and part:IsDescendantOf(LocalPlayer.Character)) then
            return nil
        end
        local root: BasePart = part.AssemblyRootPart or part
        if runtime.observedCandidates[root] or isCharacterPart(root) then
            return nil
        end
        return root
    end

    local function ensureSampler(): ()
        if runtime.sampler then
            return
        end
        runtime.sampler = TaskManager:Connect(function(_deltaTime: number): ()
            local now: number = os.clock()
            local completed: {BasePart} = {}
            for part: BasePart, track: ProjectileTrack in pairs(runtime.tracks) do
                if not part.Parent
                    or now - track.startedAt >= settings.sampleWindowSeconds then
                    table.insert(completed, part)
                    continue
                end
                local position: Vector3 = part.Position
                local velocity: Vector3 = part.AssemblyLinearVelocity
                local speed: number = velocity.Magnitude
                if track.previousPosition and track.previousAt then
                    local deltaTime: number = now - track.previousAt
                    if deltaTime >= 1 / 240 then
                        local measuredVelocity: Vector3 =
                            (position - track.previousPosition) / deltaTime
                        local measuredSpeed: number = measuredVelocity.Magnitude
                        if measuredSpeed >= 1 and measuredSpeed <= 5000 then
                            table.insert(track.speeds, measuredSpeed)
                            if #track.samples > 0 then
                                local previousSample: ProjectileSample =
                                    track.samples[#track.samples]
                                local previousVelocity: Vector3 = Vector3.new(
                                    previousSample.velocity[1],
                                    previousSample.velocity[2],
                                    previousSample.velocity[3]
                                )
                                local acceleration: Vector3 =
                                    (measuredVelocity - previousVelocity) / deltaTime
                                if acceleration.Magnitude <= 10000 then
                                    table.insert(track.accelerations, acceleration.Magnitude)
                                    table.insert(track.verticalAccelerations, acceleration.Y)
                                end
                            end
                        end
                        track.distance += (position - track.previousPosition).Magnitude
                    end
                end
                if #track.samples < settings.maxSamplesPerTrack then
                    table.insert(track.samples, {
                        t = now - track.startedAt,
                        position = vectorArray(position),
                        velocity = vectorArray(velocity),
                        speed = speed,
                    })
                end
                track.previousPosition = position
                track.previousAt = now
            end
            for _, part: BasePart in ipairs(completed) do
                finishTrack(part, "sample-window-complete")
            end
            if next(runtime.tracks) == nil and runtime.sampler then
                runtime.sampler:Disconnect()
                runtime.sampler = nil
            end
        end)
    end

    finishTrack = function(part: BasePart, reason: string): ()
        local track: ProjectileTrack? = runtime.tracks[part]
        if not track then
            return
        end
        runtime.tracks[part] = nil
        if track.destroyConnection then
            track.destroyConnection:Disconnect()
            track.destroyConnection = nil
        end
        local speed: number? = median(track.speeds)
        if not speed or not finite(speed) or speed < 1 then
            runtime.rejectedCandidates += 1
            return
        end
        local acceleration: number? = median(track.accelerations)
        local verticalAcceleration: number? = median(track.verticalAccelerations)
        local bucketKey: string = pingBucketKey(track.pingMs)
        local bucket: BucketRecord = ensureBucket(bucketKey)
        bucket.count += 1
        bucket.speedSum += speed
        bucket.speedSquaredSum += speed * speed
        bucket.delaySum += track.launchDelayMs
        runtime.totalProjectiles += 1
        appendEvent({
            tool = track.toolName,
            projectile = track.projectileName,
            pingMs = track.pingMs,
            pingBucket = bucketKey,
            launchDelayMs = track.launchDelayMs,
            medianSpeed = speed,
            medianAcceleration = acceleration,
            medianVerticalAcceleration = verticalAcceleration,
            distanceStuds = track.distance,
            durationSeconds = os.clock() - track.startedAt,
            reason = reason,
            samples = track.samples,
        })
    end

    local function considerCandidate(instance: Instance): ()
        if not runtime.enabled or #runtime.pending == 0 then
            return
        end
        local part: BasePart? = resolveCandidate(instance)
        if not part then
            return
        end
        local now: number = os.clock()
        compactPending(now)
        if #runtime.pending == 0 then
            return
        end
        local hinted: boolean = hasProjectileHint(part)
        local speed: number = part.AssemblyLinearVelocity.Magnitude
        if not hinted and speed < settings.minProjectileSpeed then
            return
        end
        local selectedIndex: number? = nil
        local selectedScore: number = math.huge
        for index: number = #runtime.pending, 1, -1 do
            local pending: PendingActivation = runtime.pending[index]
            if not part:IsDescendantOf(pending.tool) and pending.origin then
                local offset: Vector3 = part.Position - pending.origin
                local distance: number = offset.Magnitude
                if distance <= 40 then
                    local alignmentPenalty: number = 0
                    if pending.aim and distance > 0.01 then
                        local desired: Vector3 = pending.aim - pending.origin
                        if desired.Magnitude > 0.01 then
                            local alignment: number = offset.Unit:Dot(desired.Unit)
                            if alignment < 0.35 and not hinted then
                                continue
                            end
                            alignmentPenalty = (1 - alignment) * 0.25
                        end
                    end
                    local score: number = now - pending.activatedAt
                        + distance * 0.01
                        + alignmentPenalty
                        + (hinted and 0 or 0.2)
                    if score < selectedScore then
                        selectedScore = score
                        selectedIndex = index
                    end
                end
            end
        end
        if not selectedIndex then
            runtime.rejectedCandidates += 1
            return
        end
        local pending: PendingActivation = table.remove(runtime.pending, selectedIndex)
        runtime.observedCandidates[part] = true
        local track: ProjectileTrack = {
            instance = part,
            toolName = pending.tool.Name,
            projectileName = part:GetFullName(),
            startedAt = now,
            launchDelayMs = math.max(0, (now - pending.activatedAt) * 1000),
            pingMs = pending.pingMs,
            origin = pending.origin :: Vector3,
            previousAt = now,
            previousPosition = part.Position,
            speeds = {},
            accelerations = {},
            verticalAccelerations = {},
            samples = {},
            distance = 0,
            destroyConnection = nil,
        }
        runtime.tracks[part] = track
        track.destroyConnection = part.Destroying:Connect(function(): ()
            finishTrack(part, "destroyed")
        end)
        ensureSampler()
    end

    local function observeTool(tool: Tool): ()
        if runtime.observedTools[tool] then
            return
        end
        runtime.observedTools[tool] = true
        table.insert(runtime.connections, tool.Activated:Connect(function(): ()
            if not runtime.enabled then
                return
            end
            local originPart: BasePart? = tool:FindFirstChild("Handle") :: BasePart?
            local characterRoot: BasePart? = LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            local origin: Vector3? = originPart and originPart:IsA("BasePart")
                    and originPart.Position
                or characterRoot and characterRoot.Position
                or nil
            if not origin then
                return
            end
            local aim: Vector3? = nil
            pcall(function(): ()
                aim = mouse.Hit.Position
            end)
            runtime.totalActivations += 1
            table.insert(runtime.pending, {
                tool = tool,
                activatedAt = os.clock(),
                origin = origin,
                aim = aim,
                pingMs = getPingMilliseconds(),
            })
            compactPending(os.clock())
        end))
    end

    local function observeContainer(container: Instance?): ()
        if not container then
            return
        end
        for _, child: Instance in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                observeTool(child)
            end
        end
        table.insert(runtime.connections, container.ChildAdded:Connect(function(
            child: Instance
        ): ()
            if child:IsA("Tool") then
                observeTool(child)
            end
        end))
    end

    controller = {} :: Controller
    controller.settings = settings

    function controller:setEnabled(enabled: boolean): ()
        if runtime.enabled == enabled then
            return
        end
        if not enabled then
            runtime.enabled = false
            disconnectAll()
            print("[RTM:UniversalTrajectory] Calibración detenida.")
            return
        end
        runtime.enabled = true
        runtime.startedAt = os.clock()
        observeContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
        observeContainer(LocalPlayer.Character)
        table.insert(runtime.connections, LocalPlayer.CharacterAdded:Connect(function(
            character: Model
        ): ()
            observeContainer(character)
        end))
        table.insert(runtime.connections, workspace.DescendantAdded:Connect(
            considerCandidate
        ))
        print(
            "[RTM:UniversalTrajectory] Activa · buckets "
                .. tostring(settings.bucketWidthMs)
                .. " ms · salida "
                .. outputPath
        )
    end

    function controller:save(reason: string?): boolean
        return saveSnapshot(reason or "manual")
    end

    function controller:delete(): boolean
        local deleteFile: any = executorEnvironment.delfile
        local isFile: any = executorEnvironment.isfile
        if type(deleteFile) ~= "function" then
            warn("[RTM:UniversalTrajectory] delfile no está disponible.")
            return false
        end
        local exists: boolean = true
        if type(isFile) == "function" then
            local checked: boolean, result: any = pcall(isFile, outputPath)
            exists = checked and result == true
        end
        if exists then
            local deleted: boolean, deleteError: any = pcall(deleteFile, outputPath)
            if not deleted then
                warn(
                    "[RTM:UniversalTrajectory] delfile falló: "
                        .. tostring(deleteError)
                )
                return false
            end
        end
        runtime.events = {}
        runtime.buckets = {}
        runtime.totalActivations = 0
        runtime.totalProjectiles = 0
        runtime.rejectedCandidates = 0
        runtime.dirty = false
        print("[RTM:UniversalTrajectory] Dataset de esta sesión eliminado.")
        return true
    end

    function controller:status(): string
        return string.format(
            "Universal · activaciones %d · proyectiles %d · buckets %d",
            runtime.totalActivations,
            runtime.totalProjectiles,
            (function(): number
                local count: number = 0
                for _key: string in pairs(runtime.buckets) do
                    count += 1
                end
                return count
            end)()
        )
    end

    function controller:destroy(): ()
        self:setEnabled(false)
    end

    return controller
end)()
state.universalProjectileCalibration:setEnabled(true)
do
local function applyGuiStyle(_: string, animate: boolean): ()
    state.guiStyle = "Default"
    Content.Parent = state.shells.defaultContentHost
    -- The page host starts below the page header, so it is positioned from
    -- the responsive metrics instead of filling the content host.
    Content.Position = UDim2.fromOffset(0, state.layout.headerHeight)
    Content.Size = UDim2.new(1, 0, 1, -state.layout.headerHeight)
    -- The shell's visibility belongs to the menu toggle, not to a restyle:
    -- `state.shells.default` is the window itself now, so forcing it visible
    -- here would pop the menu open behind the player's back.

    Main.BackgroundColor3 = Theme.DefaultBackground
    state.mainStroke.Color = Theme.DefaultOutline
    state.mainStroke.Transparency = 1
    for _, page: Frame in pairs(pages) do
        page.BackgroundColor3 = Theme.DefaultBackground
        page.BackgroundTransparency = 1
        for _, descendant: Instance in ipairs(page:GetDescendants()) do
            if descendant:IsA("ScrollingFrame") then
                descendant.ScrollBarImageColor3 = Theme.DefaultOutline
            end
        end
    end
    if state.restyleButtons then
        state.restyleButtons(true)
    end
    if state.restyleTextBoxes then
        state.restyleTextBoxes(true)
    end
    if state.restyleAllFeatures then
        state.restyleAllFeatures(true)
    end
    if state.restyleSettings then
        state.restyleSettings(true)
    end
    if state.refreshCardGrids then
        state.refreshCardGrids()
    end
    setTab(state.activeTab)
end
state.applyGuiStyle = applyGuiStyle

applyGuiStyle(state.guiStyle, false)
end

local function disconnectFeatureConnection(name)
    local connection = featureConnections[name]
    if connection then
        connection:Disconnect()
        featureConnections[name] = nil
    end
end

local function getCharacterParts()
    local character = LocalPlayer.Character
    if not character then
        return nil, nil, nil
    end

    return character,
        character:FindFirstChildOfClass("Humanoid"),
        character:FindFirstChild("HumanoidRootPart")
end

-- ---------------------------------------------------------------------------
-- Device-independent input
-- ---------------------------------------------------------------------------
--
-- Modules must never read WASD, Space or a mouse position directly: a phone
-- has none of them, which is exactly why Fly, Infinite Jump and CTRL+Click
-- Teleport did nothing on touch. These three helpers answer the questions a
-- module actually has — "where is the player steering", "is jump held", "what
-- is being aimed at" — using whatever input the device provides.
do
-- Roblox's own control module is the single source of movement input: it
-- already merges keyboard, thumbstick, gamepad and click-to-move. Reading it
-- also keeps working while `PlatformStand` is on, which is when
-- `Humanoid.MoveDirection` goes silent (and why flying on a phone left the
-- character stuck).
local cachedControls: any = nil
local controlsFetchedAt: number = -math.huge

local function getControls(): any
    if cachedControls ~= nil or os.clock() - controlsFetchedAt < 2 then
        return cachedControls
    end
    controlsFetchedAt = os.clock()
    local ok: boolean, controls: any = pcall(function(): any
        local scripts: Instance? = LocalPlayer:FindFirstChildOfClass("PlayerScripts")
        local playerModule: Instance? = scripts and scripts:FindFirstChild("PlayerModule")
        if not playerModule then
            return nil
        end
        return (state.requireModule(playerModule) :: any):GetControls()
    end)
    if ok and type(controls) == "table" then
        cachedControls = controls
    end
    return cachedControls
end

-- Returns the steering intent in camera space: +1 forward, +1 right.
state.getMoveInput = function(): (number, number)
    local controls: any = getControls()
    if controls then
        local ok: boolean, move: any = pcall(controls.GetMoveVector, controls)
        if ok and typeof(move) == "Vector3" and move.Magnitude > 0.001 then
            -- GetMoveVector is camera-relative with -Z forward.
            return -move.Z, move.X
        end
    end

    -- Fallbacks: the humanoid's own direction (world space, resolved against
    -- the camera by the caller) and finally the desktop keys.
    local _, humanoid: Humanoid? = getCharacterParts()
    if humanoid and humanoid.MoveDirection.Magnitude > 0.001 then
        local camera: Camera? = workspace.CurrentCamera
        if camera then
            local forward: Vector3 = camera.CFrame.LookVector
            local right: Vector3 = camera.CFrame.RightVector
            local flatForward: Vector3 = Vector3.new(forward.X, 0, forward.Z)
            local flatRight: Vector3 = Vector3.new(right.X, 0, right.Z)
            if flatForward.Magnitude > 0.001 and flatRight.Magnitude > 0.001 then
                local direction: Vector3 = humanoid.MoveDirection
                return direction:Dot(flatForward.Unit), direction:Dot(flatRight.Unit)
            end
        end
    end

    local forwardScalar: number = 0
    local rightScalar: number = 0
    if UserInputService.KeyboardEnabled then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            forwardScalar += 1
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            forwardScalar -= 1
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            rightScalar += 1
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            rightScalar -= 1
        end
    end
    return forwardScalar, rightScalar
end

-- Jump, from a key, a gamepad button or the touch jump button. `JumpRequest`
-- covers all three, and repeats while the input is held, so a short grace
-- window turns it into a reliable "is jump held" signal.
local lastJumpRequestAt: number = -math.huge
trackUiConnection(UserInputService.JumpRequest:Connect(function(): ()
    lastJumpRequestAt = os.clock()
end))

state.onJumpRequest = function(callback: () -> ()): RBXScriptConnection
    return UserInputService.JumpRequest:Connect(function(): ()
        if state.keyCaptureCallback
            or state.waitingForKey
            or UserInputService:GetFocusedTextBox() then
            return
        end
        callback()
    end)
end

state.isJumpHeld = function(): boolean
    if UserInputService:GetFocusedTextBox() then
        return false
    end
    if UserInputService.KeyboardEnabled
        and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        return true
    end
    if UserInputService.GamepadEnabled
        and UserInputService:IsKeyDown(Enum.KeyCode.ButtonA) then
        return true
    end
    local _, humanoid: Humanoid? = getCharacterParts()
    if humanoid and humanoid.Jump then
        return true
    end
    -- Touch: the jump button re-fires while it is held down.
    return os.clock() - lastJumpRequestAt < 0.2
end

-- Where the player is aiming: the mouse on a desktop, the middle of the
-- screen on touch (a finger is not a cursor).
state.getAimRay = function(): Ray?
    local camera: Camera? = workspace.CurrentCamera
    if not camera then
        return nil
    end
    local pointer: Vector2
    if UserInputService.MouseEnabled then
        pointer = UserInputService:GetMouseLocation()
    else
        pointer = camera.ViewportSize / 2
    end
    return camera:ViewportPointToRay(pointer.X, pointer.Y)
end
end

-- ---------------------------------------------------------------------------
-- Responsive card grid
-- ---------------------------------------------------------------------------
--
-- A page is a stack of category sections; a section is a header plus one or
-- two columns of cards. The number of columns is a layout metric, so the same
-- page renders as a single readable column on a phone and as a two-column
-- board on a desktop without any module knowing about it.
--
--   ScrollingFrame
--   └─ ResponsiveCardGrid
--      ├─ Section_Combat
--      │  ├─ Header
--      │  └─ Body ─ Column1 / Column2
--      ├─ Section_Player
--      └─ Intake            (cards land here until the next layout pass)
-- Only `getFeatureCardParent` escapes this block: every other helper stays
-- inside it so it does not consume one of bootstrap()'s 200 local registers
-- (the same reason the category pass was scoped before this rewrite).
local getFeatureCardParent: (Instance) -> Instance = nil :: any
do
type CardSectionRecord = {
    category: string,
    frame: Frame,
    body: Frame,
    header: Frame?,
    columns: {Frame},
}

type CardGridRecord = {
    container: ScrollingFrame,
    root: Frame,
    intake: Frame,
    sections: {[string]: CardSectionRecord},
    singleColumn: boolean,
}

local cardGrids: {[ScrollingFrame]: CardGridRecord} =
    setmetatable({}, {__mode = "k"}) :: any

-- Settings rows are half label, half control: they are never split into two
-- narrow columns even on a wide desktop.
local function gridColumnCount(record: CardGridRecord): number
    if record.singleColumn then
        return 1
    end
    return math.clamp(state.layout.cardColumns, 1, 2)
end

-- Applies the current metrics to a grid: column widths, gaps and the padding
-- of the scrolling frame that hosts it.
local function updateCardGrid(record: CardGridRecord): ()
    local layout: LayoutMetrics = state.layout
    local columns: number = gridColumnCount(record)
    local gap: number = layout.cardSpacing

    local containerPadding: UIPadding? =
        record.container:FindFirstChildOfClass("UIPadding")
    if containerPadding then
        containerPadding.PaddingLeft = UDim.new(0, layout.contentPadding)
        containerPadding.PaddingRight = UDim.new(0, layout.contentPadding)
        containerPadding.PaddingTop = UDim.new(0, layout.contentPadding)
        containerPadding.PaddingBottom = UDim.new(0, layout.contentPadding + 12)
    end
    record.container.ScrollBarThickness = layout.scrollBar

    local rootLayout: UIListLayout? = record.root:FindFirstChildOfClass("UIListLayout")
    if rootLayout then
        rootLayout.Padding = UDim.new(0, gap + 4)
    end

    for _, section: CardSectionRecord in pairs(record.sections) do
        for index: number, column: Frame in ipairs(section.columns) do
            local columnLayout: UIListLayout? =
                column:FindFirstChildOfClass("UIListLayout")
            if columnLayout then
                columnLayout.Padding = UDim.new(0, gap)
            end
            if columns > 1 then
                column.Size = UDim2.new(0.5, -gap / 2, 0, 0)
                column.Position = index == 1
                    and UDim2.fromScale(0, 0)
                    or UDim2.new(0.5, gap / 2, 0, 0)
                column.Visible = true
            else
                column.Size = UDim2.new(1, 0, 0, 0)
                column.Position = UDim2.fromScale(0, 0)
                column.Visible = index == 1
            end
        end
        if section.header then
            (section.header :: Frame).Size =
                UDim2.new(1, 0, 0, layout.compact and 22 or 24)
        end
    end
end

local function createCardSection(
    record: CardGridRecord,
    category: string
): CardSectionRecord
    local layout: LayoutMetrics = state.layout
    local suffix: string = category == "" and "General" or category:gsub("%W", "")
    local frame: Frame = create("Frame", {
        Parent = record.root,
        Name = "Section_" .. suffix,
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
    }) :: Frame
    create("UIListLayout", {
        Parent = frame,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local body: Frame = create("Frame", {
        Parent = frame,
        Name = "Body",
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 0),
    }) :: Frame

    local columns: {Frame} = {}
    for columnIndex: number = 1, 2 do
        local column: Frame = create("Frame", {
            Parent = body,
            Name = "Column" .. tostring(columnIndex),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 0),
        }) :: Frame
        create("UIListLayout", {
            Parent = column,
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            Padding = UDim.new(0, layout.cardSpacing),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        columns[columnIndex] = column
    end

    local section: CardSectionRecord = {
        category = category,
        frame = frame,
        body = body,
        header = nil,
        columns = columns,
    }
    record.sections[category] = section
    return section
end

-- Lightweight header strip: an uppercase caption plus a hairline that fades
-- out to the right. Compact on purpose — it labels a block, it is not a title.
local function ensureSectionHeader(section: CardSectionRecord): Frame
    local existing: Frame? = section.header
    if existing then
        return existing
    end
    local header: Frame = create("Frame", {
        Parent = section.frame,
        Name = "CategoryHeader",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, state.layout.compact and 22 or 24),
    }) :: Frame
    header:SetAttribute("CategoryHeader", section.category)

    local headerLabel: TextLabel = makeTextLabel(
        header,
        string.upper(section.category),
        9
    )
    headerLabel.Name = "CategoryTitle"
    headerLabel.FontFace = CONTROL_FONT
    headerLabel.Position = UDim2.fromOffset(2, 0)
    headerLabel.Size = UDim2.new(0, 150, 1, 0)
    headerLabel.TextColor3 = Theme.DefaultTextMuted
    headerLabel.TextTransparency = 0.12

    local headerRule: Frame = create("Frame", {
        Parent = header,
        Name = "CategoryRule",
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.DefaultOutline,
        BackgroundTransparency = 0.7,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -2, 0.5, 0),
        Size = UDim2.new(1, -158, 0, 1),
    }) :: Frame
    create("UIGradient", {
        Parent = headerRule,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0.25),
        }),
    })

    section.header = header
    return header
end

-- Full re-flow of one grid: group the cards by category, order the categories
-- (catch-all last) and the cards inside each one, then balance them across the
-- available columns. Cards keep their own LayoutOrder when they are not
-- categorised (the settings page relies on it).
local function refreshCategoryLayout(record: CardGridRecord): ()
    local grouped: {[string]: {GuiObject}} = {}
    local categories: {string} = {}

    local function collect(parent: Instance): ()
        for _, child: Instance in ipairs(parent:GetChildren()) do
            if not child:IsA("GuiObject") then
                continue
            end
            if type(child:GetAttribute("CategoryHeader")) == "string" then
                continue
            end
            local attribute: any = child:GetAttribute("FeatureCategory")
            local category: string = type(attribute) == "string" and attribute or ""
            local bucket: {GuiObject}? = grouped[category]
            if not bucket then
                bucket = {}
                grouped[category] = bucket
                table.insert(categories, category)
            end
            table.insert(bucket :: {GuiObject}, child :: GuiObject)
        end
    end

    collect(record.intake)
    for _, section: CardSectionRecord in pairs(record.sections) do
        for _, column: Frame in ipairs(section.columns) do
            collect(column)
        end
    end

    table.sort(categories, function(left: string, right: string): boolean
        return featureCategoryRank(left) < featureCategoryRank(right)
    end)

    -- Uncategorised pages (settings) never grow a header; a page with a single
    -- category does not need one either.
    local showHeaders: boolean = #categories > 1
    local columns: number = gridColumnCount(record)
    local spacing: number = state.layout.cardSpacing

    for index: number, category: string in ipairs(categories) do
        local section: CardSectionRecord = record.sections[category]
            or createCardSection(record, category)
        section.frame.LayoutOrder = index
        section.frame.Visible = true

        if showHeaders and category ~= "" then
            ensureSectionHeader(section)
        elseif section.header then
            (section.header :: Frame):Destroy()
            section.header = nil
        end

        local cards: {GuiObject} = grouped[category]
        if category == "" then
            table.sort(cards, function(left: GuiObject, right: GuiObject): boolean
                if left.LayoutOrder == right.LayoutOrder then
                    return left.Name < right.Name
                end
                return left.LayoutOrder < right.LayoutOrder
            end)
        else
            table.sort(cards, function(left: GuiObject, right: GuiObject): boolean
                local leftName: any = left:GetAttribute("FeatureSortName")
                local rightName: any = right:GetAttribute("FeatureSortName")
                return tostring(leftName or left.Name)
                    < tostring(rightName or right.Name)
            end)
            for cardIndex: number, card: GuiObject in ipairs(cards) do
                card.LayoutOrder = index * 1000 + cardIndex
            end
        end

        -- Balance by measured height instead of alternating, so one tall
        -- expanded card cannot leave a column half empty.
        local filled: {number} = {0, 0}
        for _, card: GuiObject in ipairs(cards) do
            local target: number = 1
            if columns > 1 and filled[2] < filled[1] then
                target = 2
            end
            if card.Parent ~= section.columns[target] then
                card.Parent = section.columns[target]
            end
            filled[target] += card.AbsoluteSize.Y > 0
                and card.AbsoluteSize.Y + spacing
                or card.Size.Y.Offset + spacing
        end
    end

    -- Sections whose last card was removed.
    for category: string, section: CardSectionRecord in pairs(record.sections) do
        if not grouped[category] then
            section.frame:Destroy()
            record.sections[category] = nil
        end
    end

    updateCardGrid(record)
end

-- Hide a category header (and its whole section) when the active search
-- filtered away every card underneath it, so the page never shows a dangling
-- title or a gap.
local function refreshCategoryVisibility(record: CardGridRecord): ()
    for _, section: CardSectionRecord in pairs(record.sections) do
        local visible: boolean = false
        for _, column: Frame in ipairs(section.columns) do
            for _, child: Instance in ipairs(column:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible then
                    visible = true
                    break
                end
            end
            if visible then
                break
            end
        end
        section.frame.Visible = visible
    end
end

state.refreshCategoryVisibility = function(): ()
    for _, record: CardGridRecord in pairs(cardGrids) do
        refreshCategoryVisibility(record)
    end
end

state.refreshCardGrids = function(): ()
    for _, record: CardGridRecord in pairs(cardGrids) do
        refreshCategoryLayout(record)
        refreshCategoryVisibility(record)
    end
end

-- Re-sorting on every single card creation would be O(n^2) during bootstrap,
-- so creations only mark the layout dirty and one pass runs on the next frame.
do
local categoryLayoutDirty: boolean = false
state.invalidateCategoryLayout = function(): ()
    if categoryLayoutDirty then
        return
    end
    categoryLayoutDirty = true
    task.defer(function(): ()
        categoryLayoutDirty = false
        state.refreshCardGrids()
    end)
end
end

-- A mode change (phone rotated, window resized) re-balances every page.
state.onLayout(function(): ()
    if state.refreshCardGrids then
        state.refreshCardGrids()
    end
end)

getFeatureCardParent = function(container: Instance): Instance
    if not container:IsA("ScrollingFrame") then
        return container
    end

    local record: CardGridRecord? = cardGrids[container]
    if not record then
        container.AutomaticCanvasSize = Enum.AutomaticSize.Y
        local oldLayout: UIListLayout? =
            container:FindFirstChildOfClass("UIListLayout")
        if oldLayout then
            oldLayout:Destroy()
        end

        local root: Frame = create("Frame", {
            Parent = container,
            Name = "ResponsiveCardGrid",
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 0),
        }) :: Frame
        create("UIListLayout", {
            Parent = root,
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            Padding = UDim.new(0, state.layout.cardSpacing + 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        -- Landing area for cards created between two layout passes. It is a
        -- plain single column, so a card is never mispositioned even if it is
        -- rendered for one frame before the pass runs.
        local intake: Frame = create("Frame", {
            Parent = root,
            Name = "Intake",
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 100000,
            Size = UDim2.new(1, 0, 0, 0),
        }) :: Frame
        create("UIListLayout", {
            Parent = intake,
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            Padding = UDim.new(0, state.layout.cardSpacing),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        record = {
            container = container,
            root = root,
            intake = intake,
            sections = {},
            singleColumn = container:GetAttribute("CardGridSingleColumn") == true,
        }
        cardGrids[container] = record
        updateCardGrid(record :: CardGridRecord)
    end

    if state.invalidateCategoryLayout then
        state.invalidateCategoryLayout()
    end
    return (record :: CardGridRecord).intake
end
end

-- (The old check-control factory lived here. Nothing uses a check widget any
-- more: settings toggles are click-to-toggle rows and module options use the
-- switch factory directly, so it was removed rather than left dangling.)

do
type FloatingWindowRecord = {
    id: string,
    root: Frame,
    body: Frame,
    closeButton: TextButton,
}

local FloatingUi: any = {
    favorites = {},
    favoriteRows = {},
    overlays = {},
    featureRows = {},
    windows = {},
}
state.floatingUi = FloatingUi

if type(configData.ui.favorites) ~= "table" then
    configData.ui.favorites = {}
end
if type(configData.ui.overlays) ~= "table" then
    configData.ui.overlays = {}
end
if type(configData.ui.floatingPositions) ~= "table" then
    configData.ui.floatingPositions = {}
end
if type(configData.ui.overlaySettings) ~= "table" then
    configData.ui.overlaySettings = {}
end
local overlaySettings: any = configData.ui.overlaySettings
overlaySettings.TextGUI = type(overlaySettings.TextGUI) == "table"
    and overlaySettings.TextGUI
    or {}
overlaySettings.SessionInfo = type(overlaySettings.SessionInfo) == "table"
    and overlaySettings.SessionInfo
    or {}
overlaySettings.TargetInfo = type(overlaySettings.TargetInfo) == "table"
    and overlaySettings.TargetInfo
    or {}
overlaySettings.Radar = type(overlaySettings.Radar) == "table"
    and overlaySettings.Radar
    or {}
local textGuiSettings: any = overlaySettings.TextGUI
textGuiSettings.sort = textGuiSettings.sort or "Alphabetical"
textGuiSettings.font = textGuiSettings.font or "Builder Sans"
textGuiSettings.colorMode = textGuiSettings.colorMode or "Match GUI"
textGuiSettings.scale = math.clamp(tonumber(textGuiSettings.scale) or 1, 0.75, 2)
textGuiSettings.shadow = textGuiSettings.shadow ~= false
textGuiSettings.gradient = textGuiSettings.gradient == true
textGuiSettings.v4Gradient = textGuiSettings.v4Gradient == true
textGuiSettings.animations = textGuiSettings.animations ~= false
textGuiSettings.watermark = textGuiSettings.watermark == true
textGuiSettings.background = textGuiSettings.background == true
textGuiSettings.hideModules = textGuiSettings.hideModules == true
textGuiSettings.hideRender = textGuiSettings.hideRender == true
textGuiSettings.customText = tostring(textGuiSettings.customText or "")
local sessionSettings: any = overlaySettings.SessionInfo
sessionSettings.showPerformance = sessionSettings.showPerformance ~= false
sessionSettings.showServer = sessionSettings.showServer ~= false
sessionSettings.showRole = sessionSettings.showRole ~= false
sessionSettings.showDeaths = sessionSettings.showDeaths ~= false
sessionSettings.showWins = sessionSettings.showWins ~= false
local targetSettings: any = overlaySettings.TargetInfo
targetSettings.mode = targetSettings.mode or "Smart Priority"
targetSettings.showAvatar = targetSettings.showAvatar ~= false
targetSettings.showHealth = targetSettings.showHealth ~= false
targetSettings.showDistance = targetSettings.showDistance ~= false
local radarSettings: any = overlaySettings.Radar
radarSettings.range = math.clamp(tonumber(radarSettings.range) or 250, 25, 2000)
radarSettings.size = math.clamp(tonumber(radarSettings.size) or 190, 140, 280)
radarSettings.rotation = radarSettings.rotation or "Camera"
radarSettings.colorMode = radarSettings.colorMode or "Smart"
radarSettings.outOfRange = radarSettings.outOfRange or "Clamp"
radarSettings.showNames = radarSettings.showNames == true
radarSettings.showDistance = radarSettings.showDistance == true
radarSettings.showTeam = radarSettings.showTeam ~= false
radarSettings.aliveOnly = radarSettings.aliveOnly ~= false
radarSettings.grid = radarSettings.grid ~= false
radarSettings.rings = radarSettings.rings ~= false

local function getFloatingViewport(): Vector2
    local camera: Camera? = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function clampFloatingPosition(
    position: Vector2,
    size: Vector2
): Vector2
    local viewport: Vector2 = getFloatingViewport()
    return Vector2.new(
        math.clamp(position.X, 6, math.max(6, viewport.X - size.X - 6)),
        math.clamp(position.Y, 6, math.max(6, viewport.Y - size.Y - 6))
    )
end

local function bringFloatingToFront(record: FloatingWindowRecord): ()
    for index: number = #FloatingUi.windows, 1, -1 do
        if FloatingUi.windows[index] == record then
            table.remove(FloatingUi.windows, index)
            break
        end
    end
    table.insert(FloatingUi.windows, record)
    for index: number, window: FloatingWindowRecord in ipairs(FloatingUi.windows) do
        local baseZ: number = 108 + index * 4
        window.root.ZIndex = baseZ
        for _, descendant: Instance in ipairs(window.root:GetDescendants()) do
            if descendant:IsA("GuiObject") then
                local relative: number =
                    tonumber(descendant:GetAttribute("FloatingDepth")) or 1
                descendant.ZIndex = baseZ + relative
            end
        end
    end
end

-- Floating windows.
--
-- Two flavours share this factory:
--   * framed  — favourites, the overlay manager and the per-overlay settings.
--               These are tool windows: header, title, close button, panel
--               background. They are movable on purpose (the fixed shell is
--               the main menu, not these).
--   * chrome-less — the HUD overlays (radar, target info, session info, text
--               GUI). They render their content and nothing else: no panel,
--               no header, no close button, so a circular radar is just a
--               circle on screen instead of a circle inside a box. They stay
--               movable: the content itself is the drag handle.
local function createFloatingWindow(
    id: string,
    titleText: string,
    size: Vector2,
    defaultPosition: Vector2,
    onClose: (() -> ())?,
    chromeless: boolean?
): FloatingWindowRecord
    local bare: boolean = chromeless == true
    local headerHeight: number = bare and 0 or 30
    local saved: any = configData.ui.floatingPositions[id]
    local position: Vector2 = type(saved) == "table"
        and Vector2.new(
            tonumber(saved[1]) or defaultPosition.X,
            tonumber(saved[2]) or defaultPosition.Y
        )
        or defaultPosition
    position = clampFloatingPosition(position, size)

    local root: Frame = create("Frame", {
        Parent = PopupLayer,
        Name = "Floating_" .. id,
        Active = true,
        BackgroundColor3 = Theme.DefaultBackground,
        BackgroundTransparency = bare and 1 or 0.08,
        BorderSizePixel = 0,
        ClipsDescendants = not bare,
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(size.X, size.Y),
        Visible = false,
        ZIndex = 150,
    }) :: Frame
    if not bare then
        create("UICorner", {
            Parent = root,
            CornerRadius = cornerRadius(UI_RADIUS.panel),
        })
        -- Hairline only: the floating windows share the borderless look of
        -- the main shell, so no grey frame draws attention at their corners.
        create("UIStroke", {
            Parent = root,
            Color = Theme.DefaultOutline,
            Transparency = 0.78,
            Thickness = 1,
        })

        local shade: Frame = create("Frame", {
            Parent = root,
            Name = "Readability",
            BackgroundColor3 = Theme.DefaultBackground,
            BackgroundTransparency = 0.28,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
        }) :: Frame
        shade:SetAttribute("FloatingDepth", 2)
    end

    local header: Frame = create("Frame", {
        Parent = root,
        Name = "Header",
        Active = not bare,
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.24,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, headerHeight),
        Visible = not bare,
    }) :: Frame
    header:SetAttribute("FloatingDepth", 3)

    local closeButton: TextButton
    if bare then
        -- Kept so every record has the same shape; never shown.
        closeButton = create("TextButton", {
            Parent = header,
            Name = "Close",
            BackgroundTransparency = 1,
            Text = "",
            Visible = false,
        }) :: TextButton
    else
        local accent: Frame = create("Frame", {
            Parent = header,
            BackgroundColor3 = Theme.DefaultOutline,
            BackgroundTransparency = 0.62,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, headerHeight - 1),
            Size = UDim2.new(1, 0, 0, 1),
        }) :: Frame
        accent:SetAttribute("FloatingDepth", 1)
        local title: TextLabel = makeTextLabel(header, titleText, 10)
        title.FontFace = CONTROL_FONT
        title.Position = UDim2.fromOffset(10, 0)
        title.Size = UDim2.new(1, -40, 1, 0)
        title.TextColor3 = Theme.DefaultText
        title:SetAttribute("FloatingDepth", 2)

        closeButton = makeButton(header, "x", 9)
        closeButton.Name = "Close"
        closeButton.AnchorPoint = Vector2.new(1, 0.5)
        closeButton.BackgroundTransparency = 1
        closeButton.Position = UDim2.new(1, -6, 0.5, 0)
        closeButton.Size = UDim2.fromOffset(22, 22)
        closeButton.TextColor3 = Theme.DefaultTextMuted
        closeButton:SetAttribute("ThemeRole", "Icon")
        closeButton:SetAttribute("FloatingDepth", 3)
        local closeStroke: UIStroke? =
            closeButton:FindFirstChild("StyleStroke") :: UIStroke?
        if closeStroke then
            closeStroke.Enabled = false
        end
    end

    local body: Frame = create("Frame", {
        Parent = root,
        Name = "Body",
        Active = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 1, -headerHeight),
    }) :: Frame
    body:SetAttribute("FloatingDepth", 4)

    -- A chrome-less overlay is mostly transparent, so while the menu is
    -- closed it must not swallow clicks meant for the game underneath: it
    -- only becomes an input surface (and therefore only becomes movable)
    -- while the menu is on screen.
    if bare then
        root.Active = state.visible == true
        -- Faint outline shown only while the menu is open, so it is obvious
        -- which HUD elements can be grabbed and repositioned. It disappears
        -- with the menu, leaving the bare read-out on screen.
        create("UICorner", {
            Parent = root,
            CornerRadius = cornerRadius(UI_RADIUS.control),
        })
        local hint: UIStroke = create("UIStroke", {
            Parent = root,
            Name = "MoveHint",
            Color = Theme.DefaultOutline,
            Thickness = 1,
            Transparency = state.visible and 0.72 or 1,
        }) :: UIStroke
        state.addMenuVisibilityListener(function(visible: boolean): ()
            if not root.Parent then
                return
            end
            root.Active = visible
            hint.Transparency = visible and 0.72 or 1
        end)
    end

    local record: FloatingWindowRecord = {
        id = id,
        root = root,
        body = body,
        closeButton = closeButton,
    }
    -- A chrome-less overlay has no title bar to grab, so the whole surface
    -- drags it; a framed window only drags from its header, which keeps its
    -- content clickable.
    local dragHandle: GuiObject = bare and root or header
    local dragging: boolean = false
    local dragInput: InputObject? = nil
    local dragStart: Vector2 = Vector2.zero
    local startPosition: Vector2 = position

    trackUiConnection(root.InputBegan:Connect(function(): ()
        bringFloatingToFront(record)
    end))
    trackUiConnection(dragHandle.InputBegan:Connect(function(input: InputObject): ()
        if bare and not state.visible then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            dragStart = Vector2.new(input.Position.X, input.Position.Y)
            startPosition = Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
            bringFloatingToFront(record)
        end
    end))
    trackUiConnection(UserInputService.InputChanged:Connect(function(input: InputObject): ()
        if not dragging then
            return
        end
        if input == dragInput
            or (dragInput
                and dragInput.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement) then
            local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
            local nextPosition: Vector2 = clampFloatingPosition(
                startPosition + pointer - dragStart,
                root.AbsoluteSize
            )
            root.Position = UDim2.fromOffset(nextPosition.X, nextPosition.Y)
        end
    end))
    trackUiConnection(UserInputService.InputEnded:Connect(function(input: InputObject): ()
        if dragging
            and (input == dragInput
                or input.UserInputType == Enum.UserInputType.MouseButton1) then
            dragging = false
            dragInput = nil
            configData.ui.floatingPositions[id] = {
                root.Position.X.Offset,
                root.Position.Y.Offset,
            }
            queueConfigSave()
        end
    end))
    trackUiConnection(closeButton.MouseButton1Click:Connect(function(): ()
        root.Visible = false
        if onClose then
            onClose()
        end
    end))
    bringFloatingToFront(record)
    return record
end

function FloatingUi.reclamp(): ()
    for _, record: FloatingWindowRecord in ipairs(FloatingUi.windows) do
        local position: Vector2 = clampFloatingPosition(
            Vector2.new(record.root.Position.X.Offset, record.root.Position.Y.Offset),
            record.root.AbsoluteSize
        )
        record.root.Position = UDim2.fromOffset(position.X, position.Y)
    end
end

-- Movable windows keep their saved position, but a smaller screen must never
-- leave one of them stranded outside the viewport.
state.onLayout(function(): ()
    FloatingUi.reclamp()
end)

local FavoritesWindow: FloatingWindowRecord = createFloatingWindow(
    "Favorites",
    "Favorites",
    Vector2.new(state.layout.compact and 240 or 270, 236),
    Vector2.new(40, 90),
    function(): ()
        configData.ui.favoritesWindowOpen = false
        queueConfigSave()
    end
)
local FavoritesList: ScrollingFrame = create("ScrollingFrame", {
    Parent = FavoritesWindow.body,
    Name = "FavoriteModules",
    Active = true,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    Position = UDim2.fromOffset(8, 8),
    ScrollBarImageColor3 = Theme.DefaultOutline,
    ScrollBarThickness = 3,
    Size = UDim2.new(1, -16, 1, -16),
}) :: ScrollingFrame
FavoritesList:SetAttribute("FloatingDepth", 2)
create("UIListLayout", {
    Parent = FavoritesList,
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local function syncFavoriteButton(feature: any): ()
    if not feature.favoriteButton then
        return
    end
    local selected: boolean = configData.ui.favorites[feature.configKey] == true
    feature.favoriteButton.Text = selected and "★" or "☆"
    feature.favoriteButton.TextColor3 = selected
        and Theme.DefaultAccent
        or Theme.DefaultTextMuted
    feature.favoriteButton.TextTransparency = selected and 0 or 0.34
end

local function refreshFavorites(): ()
    for _, row: GuiObject in ipairs(FloatingUi.favoriteRows) do
        row:Destroy()
    end
    table.clear(FloatingUi.favoriteRows)
    local order: number = 0
    for _, feature: any in ipairs(allFeatures) do
        if configData.ui.favorites[feature.configKey] == true then
            order += 1
            local row: TextButton = create("TextButton", {
                Parent = FavoritesList,
                Name = feature.configKey:gsub("%W", ""),
                AutoButtonColor = false,
                BackgroundColor3 = Theme.DefaultSurface,
                BackgroundTransparency = 0.38,
                BorderSizePixel = 0,
                FontFace = THIN_FONT,
                LayoutOrder = order,
                Size = UDim2.new(1, -4, 0, 36),
                Text = feature.name,
                TextColor3 = feature.enabled
                    and Theme.DefaultAccent
                    or Theme.DefaultText,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
            }) :: TextButton
            create("UICorner", {
                Parent = row,
                CornerRadius = cornerRadius(8),
            })
            row:SetAttribute("FloatingDepth", 3)
            create("UIPadding", {
                Parent = row,
                PaddingLeft = UDim.new(0, 12),
                PaddingRight = UDim.new(0, 38),
            })
            local status: Frame = create("Frame", {
                Parent = row,
                Name = "Status",
                AnchorPoint = Vector2.new(1, 0.5),
                BackgroundColor3 = feature.enabled
                    and Theme.AccentCyan
                    or Theme.DefaultTextMuted,
                BackgroundTransparency = feature.enabled and 0 or 0.58,
                BorderSizePixel = 0,
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = UDim2.fromOffset(feature.enabled and 9 or 7, feature.enabled and 9 or 7),
            }) :: Frame
            create("UICorner", {Parent = status, CornerRadius = UDim.new(1, 0)})
            status:SetAttribute("FloatingDepth", 2)
            row.MouseButton1Click:Connect(function(): ()
                if feature.isCategory then
                    state.setMenuVisible(true)
                    setTab(feature.sectionName)
                end
                feature.activate()
            end)
            table.insert(FloatingUi.favoriteRows, row)
        end
    end
    if order == 0 then
        local empty: TextLabel = create("TextLabel", {
            Parent = FavoritesList,
            BackgroundTransparency = 1,
            FontFace = THIN_FONT,
            LayoutOrder = 1,
            Size = UDim2.new(1, -4, 0, 52),
            Text = "Star a module to keep it here",
            TextColor3 = Theme.DefaultTextMuted,
            TextSize = 13,
            TextTransparency = 0.28,
            TextXAlignment = Enum.TextXAlignment.Center,
        }) :: TextLabel
        empty:SetAttribute("FloatingDepth", 3)
        table.insert(FloatingUi.favoriteRows, empty)
    end
end

function FloatingUi.toggleFavorite(feature: any): ()
    local nextValue: boolean = configData.ui.favorites[feature.configKey] ~= true
    configData.ui.favorites[feature.configKey] = nextValue and true or nil
    syncFavoriteButton(feature)
    refreshFavorites()
    queueConfigSave()
end

function FloatingUi.registerFeature(feature: any): ()
    FloatingUi.favorites[feature.configKey] = feature
    syncFavoriteButton(feature)
    if configData.ui.favorites[feature.configKey] == true then
        refreshFavorites()
    end
end

function FloatingUi.unregisterFeature(feature: any): ()
    FloatingUi.favorites[feature.configKey] = nil
    if configData.ui.favorites[feature.configKey] == true then
        refreshFavorites()
    end
end

function FloatingUi.refreshFeature(feature: any): ()
    if configData.ui.favorites[feature.configKey] == true then
        refreshFavorites()
    end
end

local OverlayMenu: FloatingWindowRecord = createFloatingWindow(
    "OverlayMenu",
    "Overlays",
    Vector2.new(state.layout.compact and 232 or 252, 220),
    Vector2.new(340, 90),
    function(): ()
        configData.ui.overlayMenuOpen = false
        queueConfigSave()
    end
)
local OverlayList: Frame = create("Frame", {
    Parent = OverlayMenu.body,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.new(1, -16, 1, -16),
}) :: Frame
OverlayList:SetAttribute("FloatingDepth", 2)
create("UIListLayout", {
    Parent = OverlayList,
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

-- HUD overlays are chrome-less: their window is exactly the content and
-- nothing else, so the radar is a bare circle, the target read-out is a bare
-- read-out and the session counters are bare text. They keep their own drag
-- handling, and the overlay manager below is what turns them on and off.
local overlayDefinitions: {any} = {
    {id = "SessionInfo", title = "Session Info", size = Vector2.new(210, 118), position = Vector2.new(24, 300)},
    {id = "TextGUI", title = "Text GUI", size = Vector2.new(240, 220), position = Vector2.new(250, 300)},
    {id = "TargetInfo", title = "Target Info", size = Vector2.new(260, 86), position = Vector2.new(510, 300)},
    {id = "Radar", title = "Radar", size = Vector2.new(radarSettings.size, radarSettings.size), position = Vector2.new(820, 280)},
}

local function setOverlayEnabled(id: string, enabled: boolean): ()
    local overlay: any = FloatingUi.overlays[id]
    if not overlay then
        return
    end
    overlay.enabled = enabled
    overlay.window.root.Visible = enabled
    setToggleSwitch(overlay.toggle, enabled, true)
    configData.ui.overlays[id] = enabled
    queueConfigSave()
    if enabled then
        bringFloatingToFront(overlay.window)
    end
end

FloatingUi.settingsWindows = {}
FloatingUi.openSettings = function(id: string): ()
    local window: FloatingWindowRecord? = FloatingUi.settingsWindows[id]
    if window then
        window.root.Visible = not window.root.Visible
        if window.root.Visible then
            bringFloatingToFront(window)
        end
    end
end

for index: number, definition: any in ipairs(overlayDefinitions) do
    local overlayId: string = definition.id
    local overlayWindow: FloatingWindowRecord
    overlayWindow = createFloatingWindow(
        overlayId,
        definition.title,
        definition.size,
        definition.position,
        function(): ()
            setOverlayEnabled(overlayId, false)
        end,
        true
    )
    local managerRow: Frame = create("Frame", {
        Parent = OverlayList,
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.48,
        BorderSizePixel = 0,
        LayoutOrder = index,
        Size = UDim2.new(1, 0, 0, 40),
    }) :: Frame
    managerRow:SetAttribute("FloatingDepth", 3)
    create("UICorner", {
        Parent = managerRow,
        CornerRadius = cornerRadius(8),
    })
    local managerLabel: TextLabel = makeTextLabel(managerRow, definition.title, 10)
    managerLabel.Position = UDim2.fromOffset(10, 0)
    managerLabel.Size = UDim2.new(1, -112, 1, 0)
    managerLabel.TextColor3 = Theme.DefaultTextMuted
    managerLabel:SetAttribute("FloatingDepth", 1)
    local settingsButton: TextButton = makeButton(managerRow, "...", 9)
    settingsButton.Name = "Settings"
    settingsButton.AnchorPoint = Vector2.new(1, 0.5)
    settingsButton.BackgroundTransparency = 1
    settingsButton.Position = UDim2.new(1, -58, 0.5, 0)
    settingsButton.Size = UDim2.fromOffset(28, 28)
    settingsButton:SetAttribute("FloatingDepth", 2)
    local settingsStroke: UIStroke? =
        settingsButton:FindFirstChild("StyleStroke") :: UIStroke?
    if settingsStroke then
        settingsStroke.Enabled = false
    end
    local toggle: TextButton = createToggleSwitch(managerRow, false, 42)
    toggle.AnchorPoint = Vector2.new(1, 0.5)
    toggle.Position = UDim2.new(1, -7, 0.5, 0)
    toggle:SetAttribute("FloatingDepth", 2)
    FloatingUi.overlays[overlayId] = {
        window = overlayWindow,
        toggle = toggle,
        enabled = false,
    }
    trackUiConnection(toggle.MouseButton1Click:Connect(function(): ()
        setOverlayEnabled(overlayId, not FloatingUi.overlays[overlayId].enabled)
    end))
    trackUiConnection(settingsButton.MouseButton1Click:Connect(function(): ()
        FloatingUi.openSettings(overlayId)
    end))
end

local function createOverlaySettingsWindow(
    id: string,
    title: string,
    height: number,
    position: Vector2
): (FloatingWindowRecord, ScrollingFrame)
    -- Settings windows scroll, so their height is capped to the screen: a
    -- 500px panel would run off a phone in landscape.
    local window: FloatingWindowRecord = createFloatingWindow(
        id .. "Settings",
        title,
        Vector2.new(
            state.layout.compact and 268 or 292,
            math.min(height, math.max(180, getFloatingViewport().Y - 24))
        ),
        position,
        nil
    )
    local scroll: ScrollingFrame = create("ScrollingFrame", {
        Parent = window.body,
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(8, 8),
        ScrollBarImageColor3 = Theme.AccentViolet,
        ScrollBarThickness = 3,
        Size = UDim2.new(1, -16, 1, -16),
    }) :: ScrollingFrame
    scroll:SetAttribute("FloatingDepth", 2)
    create("UIListLayout", {
        Parent = scroll,
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    FloatingUi.settingsWindows[id] = window
    return window, scroll
end

local function createCompactSettingRow(parent: Instance, labelText: string): Frame
    local row: Frame = create("Frame", {
        Parent = parent,
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.44,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, 38),
    }) :: Frame
    create("UICorner", {Parent = row, CornerRadius = cornerRadius(8)})
    local label: TextLabel = makeTextLabel(row, labelText, 9)
    label.Position = UDim2.fromOffset(10, 0)
    label.Size = UDim2.new(0.48, -10, 1, 0)
    label.TextColor3 = Theme.DefaultTextMuted
    return row
end

local function addCompactCycle(
    parent: Instance,
    labelText: string,
    values: {string},
    currentValue: string,
    callback: (string) -> ()
): ()
    local row: Frame = createCompactSettingRow(parent, labelText)
    local index: number = table.find(values, currentValue) or 1
    local button: TextButton = makeButton(row, values[index], 8)
    button.Position = UDim2.new(0.48, 4, 0, 4)
    button.Size = UDim2.new(0.52, -8, 1, -8)
    trackUiConnection(button.MouseButton1Click:Connect(function(): ()
        index = index % #values + 1
        button.Text = values[index]
        callback(values[index])
        queueConfigSave()
    end))
end

local function addCompactToggle(
    parent: Instance,
    labelText: string,
    initial: boolean,
    callback: (boolean) -> ()
): ()
    local row: Frame = createCompactSettingRow(parent, labelText)
    local enabled: boolean = initial
    local toggle: TextButton = createToggleSwitch(row, enabled, 42)
    toggle.AnchorPoint = Vector2.new(1, 0.5)
    toggle.Position = UDim2.new(1, -8, 0.5, 0)
    trackUiConnection(toggle.MouseButton1Click:Connect(function(): ()
        enabled = not enabled
        setToggleSwitch(toggle, enabled, true)
        callback(enabled)
        queueConfigSave()
    end))
end

local function addCompactText(
    parent: Instance,
    labelText: string,
    initial: string,
    callback: (string) -> ()
): ()
    local row: Frame = createCompactSettingRow(parent, labelText)
    local box: TextBox = makeTextBox(row, initial)
    box.Position = UDim2.new(0.48, 4, 0, 4)
    box.Size = UDim2.new(0.52, -8, 1, -8)
    box.PlaceholderText = "Custom text"
    box.TextXAlignment = Enum.TextXAlignment.Left
    trackUiConnection(box.FocusLost:Connect(function(): ()
        callback(string.sub(box.Text, 1, 80))
        queueConfigSave()
    end))
end

-- The four settings windows are reachable through `FloatingUi.settingsWindows`
-- (createOverlaySettingsWindow registers each one), so they no longer need
-- block locals that other scopes cannot see.
do
    local textSettingsScroll: ScrollingFrame
    local _textSettingsWindow: FloatingWindowRecord
    _textSettingsWindow, textSettingsScroll = createOverlaySettingsWindow(
        "TextGUI",
        "Text GUI Studio",
        state.layout.compact and 500 or 540,
        Vector2.new(300, 70)
    )
    addCompactCycle(textSettingsScroll, "Sort", {"Alphabetical", "Length", "Enabled order", "Section"}, textGuiSettings.sort, function(value: string): () textGuiSettings.sort = value end)
    addCompactCycle(textSettingsScroll, "Font", {"Builder Sans", "Source Sans", "Gotham", "Code", "Valve"}, textGuiSettings.font, function(value: string): () textGuiSettings.font = value end)
    addCompactCycle(textSettingsScroll, "Color mode", {"Match GUI", "Solid white", "Greyscale", "Rainbow", "By section"}, textGuiSettings.colorMode, function(value: string): () textGuiSettings.colorMode = value end)
    addCompactCycle(textSettingsScroll, "Scale", {"0.75", "1", "1.25", "1.5", "2"}, tostring(textGuiSettings.scale), function(value: string): () textGuiSettings.scale = tonumber(value) or 1 end)
    addCompactToggle(textSettingsScroll, "Shadow", textGuiSettings.shadow, function(value: boolean): () textGuiSettings.shadow = value end)
    addCompactToggle(textSettingsScroll, "Gradient", textGuiSettings.gradient, function(value: boolean): () textGuiSettings.gradient = value end)
    addCompactToggle(textSettingsScroll, "V4 gradient", textGuiSettings.v4Gradient, function(value: boolean): () textGuiSettings.v4Gradient = value end)
    addCompactToggle(textSettingsScroll, "Animations", textGuiSettings.animations, function(value: boolean): () textGuiSettings.animations = value end)
    addCompactToggle(textSettingsScroll, "Watermark", textGuiSettings.watermark, function(value: boolean): () textGuiSettings.watermark = value end)
    addCompactToggle(textSettingsScroll, "Render background", textGuiSettings.background, function(value: boolean): () textGuiSettings.background = value end)
    addCompactToggle(textSettingsScroll, "Hide modules", textGuiSettings.hideModules, function(value: boolean): () textGuiSettings.hideModules = value end)
    addCompactToggle(textSettingsScroll, "Hide render", textGuiSettings.hideRender, function(value: boolean): () textGuiSettings.hideRender = value end)
    addCompactText(textSettingsScroll, "Custom text", textGuiSettings.customText, function(value: string): () textGuiSettings.customText = value end)
end

do
    local radarSettingsScroll: ScrollingFrame
    local _radarSettingsWindow: FloatingWindowRecord
    _radarSettingsWindow, radarSettingsScroll = createOverlaySettingsWindow(
        "Radar",
        "Radar Studio",
        500,
        Vector2.new(630, 70)
    )
    addCompactCycle(radarSettingsScroll, "Range", {"75", "150", "250", "500", "1000", "2000"}, tostring(radarSettings.range), function(value: string): () radarSettings.range = tonumber(value) or 250 end)
    addCompactCycle(radarSettingsScroll, "Radar size", {"160", "190", "220", "250", "280"}, tostring(radarSettings.size), function(value: string): () radarSettings.size = tonumber(value) or 190 end)
    addCompactCycle(radarSettingsScroll, "Rotation", {"Camera", "Player", "North"}, radarSettings.rotation, function(value: string): () radarSettings.rotation = value end)
    addCompactCycle(radarSettingsScroll, "Color mode", {"Smart", "Team", "Health", "MM2 role", "Spectrum"}, radarSettings.colorMode, function(value: string): () radarSettings.colorMode = value end)
    addCompactCycle(radarSettingsScroll, "Out of range", {"Clamp", "Hide"}, radarSettings.outOfRange, function(value: string): () radarSettings.outOfRange = value end)
    addCompactToggle(radarSettingsScroll, "Alive only", radarSettings.aliveOnly, function(value: boolean): () radarSettings.aliveOnly = value end)
    addCompactToggle(radarSettingsScroll, "Show team", radarSettings.showTeam, function(value: boolean): () radarSettings.showTeam = value end)
    addCompactToggle(radarSettingsScroll, "Show names", radarSettings.showNames, function(value: boolean): () radarSettings.showNames = value end)
    addCompactToggle(radarSettingsScroll, "Show distance", radarSettings.showDistance, function(value: boolean): () radarSettings.showDistance = value end)
    addCompactToggle(radarSettingsScroll, "Grid", radarSettings.grid, function(value: boolean): () radarSettings.grid = value end)
    addCompactToggle(radarSettingsScroll, "Range rings", radarSettings.rings, function(value: boolean): () radarSettings.rings = value end)
end

do
    local sessionSettingsScroll: ScrollingFrame
    local _sessionSettingsWindow: FloatingWindowRecord
    _sessionSettingsWindow, sessionSettingsScroll = createOverlaySettingsWindow(
        "SessionInfo",
        "Session Metrics",
        310,
        Vector2.new(960, 70)
    )
    addCompactToggle(sessionSettingsScroll, "Performance", sessionSettings.showPerformance, function(value: boolean): () sessionSettings.showPerformance = value end)
    addCompactToggle(sessionSettingsScroll, "Server data", sessionSettings.showServer, function(value: boolean): () sessionSettings.showServer = value end)
    addCompactToggle(sessionSettingsScroll, "Role and team", sessionSettings.showRole, function(value: boolean): () sessionSettings.showRole = value end)
    addCompactToggle(sessionSettingsScroll, "Deaths", sessionSettings.showDeaths, function(value: boolean): () sessionSettings.showDeaths = value end)
    addCompactToggle(sessionSettingsScroll, "Wins / rounds", sessionSettings.showWins, function(value: boolean): () sessionSettings.showWins = value end)
end

do
    local targetSettingsScroll: ScrollingFrame
    local _targetSettingsWindow: FloatingWindowRecord
    _targetSettingsWindow, targetSettingsScroll = createOverlaySettingsWindow(
        "TargetInfo",
        "Target Priority",
        280,
        Vector2.new(960, 395)
    )
    addCompactCycle(targetSettingsScroll, "Selection", {"Smart Priority", "Nearest cursor", "Nearest distance"}, targetSettings.mode, function(value: string): () targetSettings.mode = value end)
    addCompactToggle(targetSettingsScroll, "Avatar portrait", targetSettings.showAvatar, function(value: boolean): () targetSettings.showAvatar = value end)
    addCompactToggle(targetSettingsScroll, "Health bar", targetSettings.showHealth, function(value: boolean): () targetSettings.showHealth = value end)
    addCompactToggle(targetSettingsScroll, "Distance", targetSettings.showDistance, function(value: boolean): () targetSettings.showDistance = value end)
end

-- Session read-out. With the panel gone the text sits directly on the game,
-- so it carries its own one-pixel shadow instead of relying on a background.
local SessionShadow: TextLabel = makeTextLabel(
    FloatingUi.overlays.SessionInfo.window.body,
    "Session initializing...",
    9
)
SessionShadow.Name = "SessionShadow"
SessionShadow.Position = UDim2.fromOffset(1, 1)
SessionShadow.Size = UDim2.fromScale(1, 1)
SessionShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
SessionShadow.TextTransparency = 0.25
SessionShadow.TextYAlignment = Enum.TextYAlignment.Top
SessionShadow:SetAttribute("FloatingDepth", 1)

local SessionText: TextLabel = makeTextLabel(
    FloatingUi.overlays.SessionInfo.window.body,
    "Session initializing...",
    9
)
SessionText.Position = UDim2.fromOffset(0, 0)
SessionText.Size = UDim2.fromScale(1, 1)
SessionText.TextColor3 = Theme.DefaultText
SessionText.TextYAlignment = Enum.TextYAlignment.Top
SessionText:SetAttribute("FloatingDepth", 2)

local TextGuiBody: Frame = FloatingUi.overlays.TextGUI.window.body
local TextGuiShadow: TextLabel = makeTextLabel(
    TextGuiBody,
    "No active modules",
    10
)
TextGuiShadow.Position = UDim2.fromOffset(1, 1)
TextGuiShadow.Size = UDim2.fromScale(1, 1)
TextGuiShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
TextGuiShadow.TextTransparency = 0.16
TextGuiShadow.TextWrapped = true
TextGuiShadow.TextYAlignment = Enum.TextYAlignment.Top
TextGuiShadow:SetAttribute("FloatingDepth", 1)
local TextGuiLabel: TextLabel = makeTextLabel(
    FloatingUi.overlays.TextGUI.window.body,
    "No active modules",
    10
)
TextGuiLabel.Position = UDim2.fromOffset(0, 0)
TextGuiLabel.Size = UDim2.fromScale(1, 1)
TextGuiLabel.TextColor3 = Theme.AccentCyan
TextGuiLabel.TextWrapped = true
TextGuiLabel.TextYAlignment = Enum.TextYAlignment.Top
TextGuiLabel:SetAttribute("FloatingDepth", 2)
local TextGuiGradient: UIGradient = create("UIGradient", {
    Parent = TextGuiLabel,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.DefaultAccent),
        ColorSequenceKeypoint.new(0.5, Theme.AccentViolet),
        ColorSequenceKeypoint.new(1, Theme.AccentPink),
    }),
    Rotation = 90,
    Enabled = false,
}) :: UIGradient

local TargetBody: Frame = FloatingUi.overlays.TargetInfo.window.body
-- The portrait is content, not chrome, so it keeps its own rounded plate;
-- everything that used to box the whole read-out is gone.
local TargetPortraitFrame: Frame = create("Frame", {
    Parent = TargetBody,
    BackgroundColor3 = Theme.DefaultSurface,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(56, 56),
}) :: Frame
TargetPortraitFrame:SetAttribute("FloatingDepth", 2)
create("UICorner", {Parent = TargetPortraitFrame, CornerRadius = cornerRadius(UI_RADIUS.panel)})
create("UIStroke", {
    Parent = TargetPortraitFrame,
    Color = Theme.DefaultOutline,
    Transparency = 0.55,
    Thickness = 1,
})
local TargetPortrait: ImageLabel = create("ImageLabel", {
    Parent = TargetPortraitFrame,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    Position = UDim2.fromOffset(4, 4),
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.new(1, -8, 1, -8),
    ZIndex = 3,
}) :: ImageLabel
TargetPortrait:SetAttribute("FloatingDepth", 3)
create("UICorner", {Parent = TargetPortrait, CornerRadius = cornerRadius(10)})
local TargetName: TextLabel = makeTextLabel(
    TargetBody,
    "No target",
    11
)
TargetName.FontFace = CONTROL_FONT
TargetName.Position = UDim2.fromOffset(64, 0)
TargetName.Size = UDim2.new(1, -64, 0, 22)
TargetName:SetAttribute("FloatingDepth", 2)
local TargetRole: TextLabel = makeTextLabel(TargetBody, "No priority target", 8)
TargetRole.Position = UDim2.fromOffset(64, 21)
TargetRole.Size = UDim2.new(1, -64, 0, 18)
TargetRole.TextColor3 = Theme.AccentViolet
TargetRole:SetAttribute("FloatingDepth", 2)
local TargetHealthTrack: Frame = create("Frame", {
    Parent = TargetBody,
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(64, 42),
    Size = UDim2.new(1, -64, 0, 6),
}) :: Frame
TargetHealthTrack:SetAttribute("FloatingDepth", 2)
create("UICorner", {Parent = TargetHealthTrack, CornerRadius = UDim.new(1, 0)})
local TargetHealthFill: Frame = create("Frame", {
    Parent = TargetHealthTrack,
    BackgroundColor3 = Theme.AccentCyan,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(0, 1),
}) :: Frame
TargetHealthFill:SetAttribute("FloatingDepth", 1)
create("UICorner", {Parent = TargetHealthFill, CornerRadius = UDim.new(1, 0)})
local TargetDetails: TextLabel = makeTextLabel(
    TargetBody,
    "Waiting for a nearby player",
    9
)
TargetDetails.Position = UDim2.fromOffset(0, 58)
TargetDetails.Size = UDim2.new(1, 0, 0, 28)
TargetDetails.TextColor3 = Theme.DefaultTextMuted
TargetDetails:SetAttribute("FloatingDepth", 2)

local RadarSurface: Frame = create("Frame", {
    Parent = FloatingUi.overlays.Radar.window.body,
    Name = "Surface",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Theme.DefaultSurface,
    BackgroundTransparency = 0.34,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(radarSettings.size, radarSettings.size),
}) :: Frame
RadarSurface:SetAttribute("FloatingDepth", 2)
create("UICorner", {Parent = RadarSurface, CornerRadius = UDim.new(1, 0)})
create("UIStroke", {
    Parent = RadarSurface,
    Color = Theme.DefaultOutline,
    Transparency = 0.55,
})
local radarAxes: {Frame} = {}
for _, rotation: number in ipairs({0, 90}) do
    local axis: Frame = create("Frame", {
        Parent = RadarSurface,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.DefaultOutline,
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Rotation = rotation,
        Size = UDim2.new(1, -16, 0, 1),
    }) :: Frame
    axis:SetAttribute("FloatingDepth", 1)
    table.insert(radarAxes, axis)
end
local radarRings: {Frame} = {}
for _, scale: number in ipairs({0.34, 0.67}) do
    local ring: Frame = create("Frame", {
        Parent = RadarSurface,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(scale, scale),
    }) :: Frame
    ring:SetAttribute("FloatingDepth", 1)
    create("UICorner", {Parent = ring, CornerRadius = UDim.new(1, 0)})
    create("UIStroke", {
        Parent = ring,
        Color = Theme.DefaultOutline,
        Transparency = 0.7,
        Thickness = 1,
    })
    table.insert(radarRings, ring)
end
local RadarNorth: TextLabel = makeTextLabel(RadarSurface, "N", 8)
RadarNorth.AnchorPoint = Vector2.new(0.5, 0)
RadarNorth.Position = UDim2.new(0.5, 0, 0, 5)
RadarNorth.Size = UDim2.fromOffset(20, 18)
RadarNorth.TextColor3 = Theme.AccentCyan
RadarNorth.TextXAlignment = Enum.TextXAlignment.Center
RadarNorth:SetAttribute("FloatingDepth", 3)
local RadarCenter: Frame = create("Frame", {
    Parent = RadarSurface,
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Theme.AccentCyan,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(7, 7),
}) :: Frame
RadarCenter:SetAttribute("FloatingDepth", 3)
create("UICorner", {Parent = RadarCenter, CornerRadius = UDim.new(1, 0)})
local radarBlips: {[Player]: any} = {}
local sessionStartedAt: number = os.clock()
local overlayElapsed: number = 1
local sessionFps: number = 60
local sessionStats: any = {
    deaths = 0,
    wins = 0,
    rounds = 0,
    winsAvailable = false,
    roundsAvailable = false,
    role = nil,
}
state.sessionInfo = {
    setRole = function(role: string?): () sessionStats.role = role end,
    addWin = function(): ()
        sessionStats.winsAvailable = true
        sessionStats.wins += 1
    end,
    addRound = function(): ()
        sessionStats.roundsAvailable = true
        sessionStats.rounds += 1
    end,
}
local deathConnection: RBXScriptConnection? = nil
local sessionBindGeneration: number = 0
local sessionTrackingActive: boolean = true
local function bindSessionCharacter(character: Model): ()
    sessionBindGeneration += 1
    local generation: number = sessionBindGeneration
    if deathConnection then
        deathConnection:Disconnect()
        deathConnection = nil
    end
    local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        or character:WaitForChild("Humanoid", 8) :: Humanoid?
    if humanoid
        and sessionTrackingActive
        and generation == sessionBindGeneration
        and character == LocalPlayer.Character then
        deathConnection = humanoid.Died:Connect(function(): ()
            sessionStats.deaths += 1
        end)
    end
end
if LocalPlayer.Character then
    task.defer(bindSessionCharacter, LocalPlayer.Character)
end
trackUiConnection(LocalPlayer.CharacterAdded:Connect(bindSessionCharacter))

-- Teardown hook for the session counters.
--
-- These three values are locals of this block, so the destruct routine at the
-- bottom of the file could not reach them: assigning them there created three
-- globals instead and left the `Died` connection alive. Exposing the teardown
-- through `state` is what actually stops the tracking.
state.destroySessionTracking = function(): ()
    sessionTrackingActive = false
    sessionBindGeneration += 1
    if deathConnection then
        deathConnection:Disconnect()
        deathConnection = nil
    end
end
local thumbnailCache: {[number]: string} = {}
local thumbnailGeneration: number = 0
local displayedTargetUserId: number = 0
local currentOverlayTarget: Player? = nil
state.getOverlayTarget = function(): Player? return currentOverlayTarget end

local function requestTargetThumbnail(player: Player?): ()
    local userId: number = player and player.UserId or 0
    if userId == displayedTargetUserId then
        return
    end
    displayedTargetUserId = userId
    thumbnailGeneration += 1
    local generation: number = thumbnailGeneration
    TargetPortrait.Image = userId > 0 and (thumbnailCache[userId] or "") or ""
    if userId <= 0 or thumbnailCache[userId] then
        return
    end
    task.spawn(function(): ()
        local success: boolean, image: any, ready: any = pcall(
            Players.GetUserThumbnailAsync,
            Players,
            userId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size180x180
        )
        if success and ready == true and type(image) == "string" and image ~= "" then
            thumbnailCache[userId] = image
            if generation == thumbnailGeneration and TargetPortrait.Parent then
                TargetPortrait.Image = image
            end
        elseif generation == thumbnailGeneration then
            task.delay(1, function(): ()
                if generation == thumbnailGeneration then
                    displayedTargetUserId = 0
                end
            end)
        end
    end)
end

local function getTextGuiFont(): Font
    if textGuiSettings.font == "Source Sans" then
        return Font.fromEnum(Enum.Font.SourceSans)
    elseif textGuiSettings.font == "Gotham" then
        return Font.fromEnum(Enum.Font.Gotham)
    elseif textGuiSettings.font == "Code" then
        return Font.fromEnum(Enum.Font.Code)
    elseif textGuiSettings.font == "Valve" then
        return VALVE_FONT
    end
    return CONTROL_FONT
end

local function getSessionPing(): number?
    local success: boolean, value: any = pcall(function(): number
        local network: any = Stats:FindFirstChild("Network")
        local serverStats: any = network and network:FindFirstChild("ServerStatsItem")
        local ping: any = serverStats and serverStats:FindFirstChild("Data Ping")
        return ping and ping:GetValue() or 0
    end)
    return success and tonumber(value) or nil
end

local lastTextGuiText: string = ""
TaskManager:Connect(function(deltaTime: number): ()
    sessionFps += ((1 / math.max(deltaTime, 1 / 240)) - sessionFps) * 0.12
    overlayElapsed += deltaTime
    if overlayElapsed < 0.12 then
        return
    end
    overlayElapsed = 0
    local now: number = os.clock()
    local elapsed: number = math.max(0, math.floor(now - sessionStartedAt))

    if FloatingUi.overlays.SessionInfo.enabled then
        local role: string? = sessionStats.role
        if state.gameRoleProvider then
            local success: boolean, resolved: any = pcall(
                state.gameRoleProvider,
                LocalPlayer
            )
            if success and type(resolved) == "string" then
                role = resolved
            end
        end
        local lines: {string} = {
            string.format(
                "Injected  %02d:%02d:%02d",
                math.floor(elapsed / 3600),
                math.floor(elapsed / 60) % 60,
                elapsed % 60
            ),
        }
        if sessionSettings.showDeaths then
            table.insert(lines, "Deaths    " .. tostring(sessionStats.deaths))
        end
        if sessionSettings.showWins then
            table.insert(lines, "Wins      " .. (sessionStats.winsAvailable and tostring(sessionStats.wins) or "N/A"))
            table.insert(lines, "Rounds    " .. (sessionStats.roundsAvailable and tostring(sessionStats.rounds) or "N/A"))
        end
        if sessionSettings.showRole then
            table.insert(lines, "Role      " .. tostring(role or "N/A"))
            table.insert(lines, "Team      " .. tostring(LocalPlayer.Team and LocalPlayer.Team.Name or "None"))
        end
        if sessionSettings.showPerformance then
            local ping: number? = getSessionPing()
            table.insert(lines, string.format("FPS       %.0f", math.clamp(sessionFps, 0, 999)))
            table.insert(lines, "Ping      " .. (ping and string.format("%.0f ms", ping) or "N/A"))
        end
        if sessionSettings.showServer then
            table.insert(lines, string.format("Players   %d/%d", #Players:GetPlayers(), Players.MaxPlayers))
            table.insert(lines, "Game      " .. tostring(ACTIVE_GAME_MODULE or "Universal"))
        end
        SessionText.Text = table.concat(lines, "\n")
    end

    if FloatingUi.overlays.TextGUI.enabled then
        local enabledFeatures: {any} = {}
        if not textGuiSettings.hideModules then
            for _, feature: any in ipairs(allFeatures) do
                local lowerName: string = string.lower(feature.name)
                local renderLike: boolean = string.find(lowerName, "esp", 1, true) ~= nil
                    or string.find(lowerName, "visual", 1, true) ~= nil
                    or string.find(lowerName, "x-ray", 1, true) ~= nil
                    or string.find(lowerName, "fov", 1, true) ~= nil
                    or string.find(lowerName, "fullbright", 1, true) ~= nil
                if feature.enabled
                    and not feature.isCategory
                    and not feature.isAction
                    and (not textGuiSettings.hideRender or not renderLike) then
                    table.insert(enabledFeatures, feature)
                end
            end
        end
        table.sort(enabledFeatures, function(left: any, right: any): boolean
            if textGuiSettings.sort == "Length" then
                return #left.name > #right.name
            elseif textGuiSettings.sort == "Enabled order" then
                return (left.enabledAt or 0) < (right.enabledAt or 0)
            elseif textGuiSettings.sort == "Section" then
                local leftKey: string = left.sectionName .. left.name
                local rightKey: string = right.sectionName .. right.name
                return leftKey < rightKey
            end
            return string.lower(left.name) < string.lower(right.name)
        end)
        local textLines: {string} = {}
        if textGuiSettings.watermark then
            table.insert(textLines, "A Random Menu")
        end
        if textGuiSettings.customText ~= "" then
            table.insert(textLines, textGuiSettings.customText)
        end
        for _, feature: any in ipairs(enabledFeatures) do
            table.insert(textLines, feature.name)
        end
        if #textLines == 0 then
            table.insert(textLines, "No active modules")
        end
        local nextText: string = table.concat(textLines, "\n")
        if nextText ~= lastTextGuiText then
            lastTextGuiText = nextText
            TextGuiLabel.Text = nextText
            TextGuiShadow.Text = nextText
            if textGuiSettings.animations then
                TextGuiLabel.TextTransparency = 0.5
                TweenService:Create(TextGuiLabel, TweenInfo.new(0.2), {
                    TextTransparency = 0,
                }):Play()
            end
        end
        TextGuiLabel.FontFace = getTextGuiFont()
        TextGuiShadow.FontFace = TextGuiLabel.FontFace
        TextGuiLabel.TextSize = math.round(14 * textGuiSettings.scale)
        TextGuiShadow.TextSize = TextGuiLabel.TextSize
        TextGuiShadow.Visible = textGuiSettings.shadow
        TextGuiBody.BackgroundColor3 = Theme.DefaultBackground
        TextGuiBody.BackgroundTransparency = textGuiSettings.background and 0.42 or 1
        local textWindowRoot: Frame = FloatingUi.overlays.TextGUI.window.root
        local textHeader: Frame? = textWindowRoot:FindFirstChild("Header") :: Frame?
        local textShade: Frame? = textWindowRoot:FindFirstChild("Readability") :: Frame?
        local textStroke: UIStroke? = textWindowRoot:FindFirstChildOfClass("UIStroke")
        if textHeader then textHeader.Visible = state.visible end
        if textShade then textShade.Visible = state.visible or textGuiSettings.background end
        if textStroke then textStroke.Transparency = state.visible and 0.38 or 1 end
        textWindowRoot.Active = state.visible
        textWindowRoot.BackgroundTransparency = state.visible and 0.08 or 1
        TextGuiBody.Position = state.visible and UDim2.fromOffset(0, 36)
            or UDim2.fromOffset(0, 0)
        TextGuiBody.Size = state.visible and UDim2.new(1, 0, 1, -36)
            or UDim2.fromScale(1, 1)
        local gradientEnabled: boolean = textGuiSettings.gradient
            or textGuiSettings.v4Gradient
            or textGuiSettings.colorMode == "Greyscale"
            or textGuiSettings.colorMode == "Rainbow"
        TextGuiGradient.Enabled = gradientEnabled
        if textGuiSettings.v4Gradient then
            TextGuiGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.DefaultAccent),
                ColorSequenceKeypoint.new(0.34, Theme.AccentViolet),
                ColorSequenceKeypoint.new(0.68, Theme.AccentPink),
                ColorSequenceKeypoint.new(1, Theme.DefaultAccent),
            })
            TextGuiGradient.Rotation = (now * 45) % 360
        elseif textGuiSettings.colorMode == "Rainbow" then
            local hue: number = (now * 0.12) % 1
            TextGuiLabel.TextColor3 = Color3.fromHSV(hue, 0.72, 1)
            TextGuiGradient.Enabled = false
        elseif textGuiSettings.colorMode == "Greyscale" then
            local pulse: number = 0.72 + 0.28 * math.sin(now * 1.6)
            TextGuiLabel.TextColor3 = Color3.fromHSV(0, 0, pulse)
            TextGuiGradient.Enabled = false
        elseif textGuiSettings.colorMode == "Solid white" then
            TextGuiLabel.TextColor3 = Theme.AccentCyan
        elseif textGuiSettings.colorMode == "By section" then
            TextGuiLabel.TextColor3 = Theme.AccentViolet
        else
            TextGuiLabel.TextColor3 = Theme.DefaultAccent
            TextGuiGradient.Rotation = 90
        end
    end

    local targetInfoEnabled: boolean = FloatingUi.overlays.TargetInfo.enabled
    local localCharacter: Model? = LocalPlayer.Character
    local localRoot: BasePart? = localCharacter
        and localCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
    local camera: Camera? = workspace.CurrentCamera
    local selectedTarget: Player? = nil
    local targetRole: string? = nil
    local targetSource: string = "Nearest player"
    local targetAccent: Color3 = Theme.AccentViolet
    if targetInfoEnabled
        and targetSettings.mode == "Smart Priority"
        and state.gameTargetProvider then
        local success: boolean, snapshot: any = pcall(state.gameTargetProvider)
        if success then
            if typeof(snapshot) == "Instance" and snapshot:IsA("Player") then
                selectedTarget = snapshot
            elseif type(snapshot) == "table"
                and typeof(snapshot.player) == "Instance"
                and snapshot.player:IsA("Player") then
                selectedTarget = snapshot.player
                targetRole = snapshot.role
                targetSource = tostring(snapshot.source or "Game priority")
                if typeof(snapshot.accent) == "Color3" then
                    targetAccent = snapshot.accent
                end
            end
        end
    end
    if targetInfoEnabled and not selectedTarget and localRoot then
        local bestScore: number = math.huge
        local pointer: Vector2 = state.isMobile and getFloatingViewport() / 2
            or UserInputService:GetMouseLocation()
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local character: Model? = player.Character
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                local root: BasePart? = character
                    and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if humanoid and humanoid.Health > 0 and root then
                    local distance: number = (root.Position - localRoot.Position).Magnitude
                    local score: number = distance
                    if targetSettings.mode ~= "Nearest distance" and camera then
                        local screenPoint: Vector3, visible: boolean =
                            camera:WorldToViewportPoint(root.Position)
                        score = visible and (Vector2.new(screenPoint.X, screenPoint.Y) - pointer).Magnitude
                            or math.huge
                    end
                    if score < bestScore then
                        bestScore = score
                        selectedTarget = player
                    end
                end
            end
        end
        targetSource = targetSettings.mode
    end
    currentOverlayTarget = targetInfoEnabled and selectedTarget or nil
    if selectedTarget and state.gameRoleProvider and not targetRole then
        local success: boolean, role: any = pcall(state.gameRoleProvider, selectedTarget)
        targetRole = success and type(role) == "string" and role or nil
    end
    if targetRole then
        targetAccent = targetRole == "Murderer" and Theme.Danger
            or ((targetRole == "Sheriff" or targetRole == "Hero")
                and Theme.AccentCyan
                or Theme.Success)
    end
    if targetInfoEnabled then
        local targetCharacter: Model? = selectedTarget and selectedTarget.Character
        local targetHumanoid: Humanoid? = targetCharacter
            and targetCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local targetRoot: BasePart? = targetCharacter
            and targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
        if selectedTarget and targetHumanoid then
            local ratio: number = math.clamp(
                targetHumanoid.Health / math.max(1, targetHumanoid.MaxHealth),
                0,
                1
            )
            local distance: number? = localRoot and targetRoot
                and (targetRoot.Position - localRoot.Position).Magnitude
                or nil
            TargetName.Text = selectedTarget.DisplayName .. "  @" .. selectedTarget.Name
            TargetRole.Text = tostring(targetRole or "Player") .. "  ·  " .. targetSource
            TargetRole.TextColor3 = targetAccent
            TargetDetails.Text = string.format(
                "Health %.0f / %.0f%s",
                targetHumanoid.Health,
                targetHumanoid.MaxHealth,
                targetSettings.showDistance and distance
                    and string.format("  ·  %.0f studs", distance)
                    or ""
            )
            TargetHealthTrack.Visible = targetSettings.showHealth
            TargetHealthFill.Size = UDim2.fromScale(ratio, 1)
            TargetHealthFill.BackgroundColor3 = ratio > 0.5
                and Theme.AccentCyan
                or (ratio > 0.25 and Theme.AccentViolet or Theme.AccentPink)
            TargetPortraitFrame.Visible = targetSettings.showAvatar
            requestTargetThumbnail(selectedTarget)
        else
            TargetName.Text = "No target"
            TargetRole.Text = "No priority target"
            TargetDetails.Text = "Waiting for a valid player"
            TargetHealthFill.Size = UDim2.fromScale(0, 1)
            TargetHealthTrack.Visible = targetSettings.showHealth
            TargetPortraitFrame.Visible = targetSettings.showAvatar
            requestTargetThumbnail(nil)
        end
    end

    if FloatingUi.overlays.Radar.enabled then
        local radarSize: number = radarSettings.size
        RadarSurface.Size = UDim2.fromOffset(radarSize, radarSize)
        -- The window is the circle: no padding for a header that no longer
        -- exists, no square plate around it.
        local radarWindow: FloatingWindowRecord = FloatingUi.overlays.Radar.window
        local nextRadarSize: UDim2 = UDim2.fromOffset(radarSize, radarSize)
        if radarWindow.root.Size ~= nextRadarSize then
            radarWindow.root.Size = nextRadarSize
            FloatingUi.reclamp()
        end
        for _, axis: Frame in ipairs(radarAxes) do axis.Visible = radarSettings.grid end
        for _, ring: Frame in ipairs(radarRings) do ring.Visible = radarSettings.rings end
        RadarNorth.Visible = radarSettings.rotation == "North"
        local activePlayers: {[Player]: boolean} = {}
        local basis: CFrame? = localRoot and localRoot.CFrame or nil
        if localRoot and radarSettings.rotation == "Camera" and camera then
            local look: Vector3 = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
            if look.Magnitude > 0.01 then
                basis = CFrame.lookAt(localRoot.Position, localRoot.Position + look.Unit)
            end
        elseif localRoot and radarSettings.rotation == "North" then
            basis = CFrame.new(localRoot.Position)
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and localRoot and basis then
                local character: Model? = player.Character
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                local targetRoot: BasePart? = character
                    and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                local sameTeam: boolean = LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
                local allowed: boolean = targetRoot ~= nil
                    and (not radarSettings.aliveOnly or (humanoid ~= nil and humanoid.Health > 0))
                    and (radarSettings.showTeam or not sameTeam)
                if allowed and targetRoot then
                    local relative: Vector3 = (basis :: CFrame):PointToObjectSpace(targetRoot.Position)
                    local distance: number = Vector2.new(relative.X, relative.Z).Magnitude
                    if distance <= radarSettings.range or radarSettings.outOfRange == "Clamp" then
                        activePlayers[player] = true
                        local record: any = radarBlips[player]
                        if not record then
                            local blip: Frame = create("Frame", {
                                Parent = RadarSurface,
                                AnchorPoint = Vector2.new(0.5, 0.5),
                                BackgroundColor3 = Theme.AccentPink,
                                BorderSizePixel = 0,
                                Size = UDim2.fromOffset(7, 7),
                            }) :: Frame
                            blip:SetAttribute("FloatingDepth", 4)
                            create("UICorner", {Parent = blip, CornerRadius = UDim.new(1, 0)})
                            local targetRing: UIStroke = create("UIStroke", {
                                Parent = blip,
                                Color = Theme.AccentCyan,
                                Transparency = 1,
                                Thickness = 2,
                            }) :: UIStroke
                            local label: TextLabel = makeTextLabel(blip, "", 7)
                            label.AnchorPoint = Vector2.new(0.5, 0)
                            label.Position = UDim2.new(0.5, 0, 1, 3)
                            label.Size = UDim2.fromOffset(100, 18)
                            label.TextColor3 = Theme.DefaultText
                            label.TextXAlignment = Enum.TextXAlignment.Center
                            record = {blip = blip, label = label, ring = targetRing}
                            radarBlips[player] = record
                        end
                        local radius: number = radarSize / 2 - 12
                        local offset: Vector2 = Vector2.new(relative.X, relative.Z)
                            * (radius / radarSettings.range)
                        if offset.Magnitude > radius then offset = offset.Unit * radius end
                        record.blip.Position = UDim2.fromOffset(
                            radarSize / 2 + offset.X,
                            radarSize / 2 + offset.Y
                        )
                        local role: string? = nil
                        if state.gameRoleProvider then
                            local roleOk: boolean, roleValue: any = pcall(state.gameRoleProvider, player)
                            role = roleOk and type(roleValue) == "string" and roleValue or nil
                        end
                        local color: Color3 = Theme.AccentPink
                        if radarSettings.colorMode == "Health" and humanoid then
                            local healthRatio: number = humanoid.Health / math.max(1, humanoid.MaxHealth)
                            color = Color3.fromHSV(healthRatio * 0.34, 0.8, 1)
                        elseif radarSettings.colorMode == "Team" or radarSettings.colorMode == "Smart" then
                            color = sameTeam and Theme.Success or Theme.Danger
                        end
                        if (radarSettings.colorMode == "MM2 role" or radarSettings.colorMode == "Smart") and role then
                            color = role == "Murderer" and Theme.Danger
                                or ((role == "Sheriff" or role == "Hero") and Theme.AccentCyan
                                    or Theme.Success)
                        elseif radarSettings.colorMode == "Spectrum" then
                            color = Color3.fromHSV((now * 0.1 + player.UserId % 10 / 10) % 1, 0.7, 1)
                        end
                        record.blip.BackgroundColor3 = color
                        record.ring.Transparency = player == currentOverlayTarget and 0 or 1
                        record.blip.Size = UDim2.fromOffset(
                            player == currentOverlayTarget and 10 or 7,
                            player == currentOverlayTarget and 10 or 7
                        )
                        record.label.Visible = radarSettings.showNames or radarSettings.showDistance
                        record.label.Text = (radarSettings.showNames and player.DisplayName or "")
                            .. (radarSettings.showDistance and string.format(" %.0f", distance) or "")
                    end
                end
            end
        end
        for player: Player, record: any in pairs(radarBlips) do
            if not activePlayers[player] then
                record.blip:Destroy()
                radarBlips[player] = nil
            end
        end
    end
end)


-- ---------------------------------------------------------------------------
-- Player card
-- ---------------------------------------------------------------------------
--
-- Who is running the menu, docked at the foot of the rail: the account's own
-- avatar, its display name and handle, and how long this account has been
-- using the menu. The "since" date and the session count are stored in the
-- config file, so they survive rejoins; the session clock restarts with the
-- injection.
--
-- The avatar comes from `rbxthumb://`, which the engine resolves itself — no
-- download, no executor file API, and it works on the first frame.
do
(function(): ()
local profileKey: string = "profile." .. tostring(LocalPlayer.UserId)
local storedFirstSeen: number? = tonumber(configData.values[profileKey .. ".firstSeen"])
local firstSeen: number = storedFirstSeen or os.time()
local sessions: number =
    (tonumber(configData.values[profileKey .. ".sessions"]) or 0) + 1
configData.values[profileKey .. ".firstSeen"] = firstSeen
configData.values[profileKey .. ".sessions"] = sessions
queueConfigSave()
local sessionStart: number = os.clock()

local ProfileCard: Frame = create("Frame", {
    Parent = state.shells.defaultSidebar,
    Name = "PlayerCard",
    AnchorPoint = Vector2.new(0.5, 1),
    BackgroundColor3 = Theme.DefaultSurface,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 0, 1, -(state.layout.launcherHeight + 14)),
    Size = UDim2.new(1, -(state.layout.sidebarPadding * 2), 0, PROFILE_CARD_HEIGHT - 8),
    ZIndex = 24,
}) :: Frame
create("UICorner", {
    Parent = ProfileCard,
    CornerRadius = cornerRadius(UI_RADIUS.control),
})
create("UIStroke", {
    Parent = ProfileCard,
    Color = Theme.DefaultOutline,
    Transparency = 0.68,
    Thickness = 1,
})

local ProfileBanner: ImageLabel = create("ImageLabel", {
    Parent = ProfileCard,
    Name = "Banner",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageTransparency = 0.35,
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 24,
}) :: ImageLabel
create("UICorner", {
    Parent = ProfileBanner,
    CornerRadius = cornerRadius(UI_RADIUS.control),
})
if state.applyAssetImage then
    state.applyAssetImage("profileBanner", ProfileBanner)
end

local Avatar: ImageLabel = create("ImageLabel", {
    Parent = ProfileCard,
    Name = "Avatar",
    AnchorPoint = Vector2.new(0, 0.5),
    BackgroundColor3 = Theme.DefaultBackground,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    Image = "rbxthumb://type=AvatarHeadShot&id="
        .. tostring(LocalPlayer.UserId)
        .. "&w=150&h=150",
    Position = UDim2.new(0, 6, 0.5, 0),
    Size = UDim2.fromOffset(34, 34),
    ZIndex = 25,
}) :: ImageLabel
create("UICorner", {Parent = Avatar, CornerRadius = UDim.new(1, 0)})
create("UIStroke", {
    Parent = Avatar,
    Color = Theme.DefaultOutline,
    Transparency = 0.5,
    Thickness = 1,
})

local ProfileName: TextLabel =
    (makeTextLabel(ProfileCard, LocalPlayer.DisplayName, 11) :: any) :: TextLabel
ProfileName.Name = "DisplayName"
ProfileName.FontFace = CONTROL_FONT
ProfileName.Position = UDim2.fromOffset(46, 6)
ProfileName.Size = UDim2.new(1, -52, 0, 14)
ProfileName.TextColor3 = Theme.DefaultText
ProfileName.TextTruncate = Enum.TextTruncate.AtEnd
ProfileName.ZIndex = 25

local ProfileHandle: TextLabel =
    (makeTextLabel(ProfileCard, "@" .. LocalPlayer.Name, 9) :: any) :: TextLabel
ProfileHandle.Name = "Handle"
ProfileHandle.Position = UDim2.fromOffset(46, 19)
ProfileHandle.Size = UDim2.new(1, -52, 0, 12)
ProfileHandle.TextColor3 = Theme.DefaultTextMuted
ProfileHandle.TextTruncate = Enum.TextTruncate.AtEnd
ProfileHandle.ZIndex = 25

local ProfileMeta: TextLabel = (makeTextLabel(ProfileCard, "", 9) :: any) :: TextLabel
ProfileMeta.Name = "Meta"
ProfileMeta.Position = UDim2.fromOffset(46, 31)
ProfileMeta.Size = UDim2.new(1, -52, 0, 12)
ProfileMeta.TextColor3 = Theme.DefaultTextMuted
ProfileMeta.TextTruncate = Enum.TextTruncate.AtEnd
ProfileMeta.ZIndex = 25

local function describeSession(): string
    local minutes: number = math.floor((os.clock() - sessionStart) / 60)
    if minutes < 60 then
        return tostring(minutes) .. "m"
    end
    return tostring(math.floor(minutes / 60)) .. "h " .. tostring(minutes % 60) .. "m"
end

local function refreshMeta(): ()
    ProfileMeta.Text = os.date("!%d/%m/%Y", firstSeen)
        .. "  ·  "
        .. tostring(sessions)
        .. (sessions == 1 and " sesión" or " sesiones")
        .. "  ·  "
        .. describeSession()
end
refreshMeta()

-- Once a minute is enough for a clock measured in minutes, and it keeps the
-- card off the per-frame budget.
local metaClock: number = 0
trackUiConnection(TaskManager:Connect(function(deltaTime: number): ()
    metaClock += deltaTime
    if metaClock < 30 then
        return
    end
    metaClock = 0
    refreshMeta()
end))

local function applyProfileLayout(metrics: LayoutMetrics): ()
    ProfileCard.Position = UDim2.new(0.5, 0, 1, -(metrics.launcherHeight + 14))
    ProfileCard.Size = metrics.sidebarCollapsed
        and UDim2.fromOffset(40, 40)
        or UDim2.new(1, -(metrics.sidebarPadding * 2), 0, PROFILE_CARD_HEIGHT - 8)
    -- Collapsed rail: the avatar is the card.
    Avatar.AnchorPoint = metrics.sidebarCollapsed
        and Vector2.new(0.5, 0.5)
        or Vector2.new(0, 0.5)
    Avatar.Position = metrics.sidebarCollapsed
        and UDim2.fromScale(0.5, 0.5)
        or UDim2.new(0, 6, 0.5, 0)
    ProfileName.Visible = not metrics.sidebarCollapsed
    ProfileHandle.Visible = not metrics.sidebarCollapsed
    ProfileMeta.Visible = not metrics.sidebarCollapsed
    ProfileBanner.Visible = not metrics.sidebarCollapsed
end
applyProfileLayout(state.layout)
state.onLayout(applyProfileLayout)

state.playerCard = {
    card = ProfileCard,
    avatar = Avatar,
    refresh = refreshMeta,
}
end)()
end
-- Launchers for the movable tool windows, docked at the foot of the rail.
-- They stack vertically when the rail collapses, which is the only way two
-- 32px buttons fit inside a 58px icon rail.
local FloatingButtons: Frame = create("Frame", {
    Parent = state.shells.defaultSidebar,
    Name = "FloatingWindowButtons",
    AnchorPoint = Vector2.new(0.5, 1),
    BackgroundColor3 = Theme.DefaultSurface,
    BackgroundTransparency = 0.42,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 0, 1, -8),
    Size = UDim2.fromOffset(
        state.layout.sidebarCollapsed and 34 or 72,
        state.layout.launcherHeight
    ),
    ZIndex = 24,
}) :: Frame
create("UICorner", {
    Parent = FloatingButtons,
    CornerRadius = cornerRadius(UI_RADIUS.control),
})
create("UIStroke", {
    Parent = FloatingButtons,
    Color = Theme.DefaultOutline,
    Transparency = 0.62,
})
local FloatingButtonsLayout: UIListLayout = create("UIListLayout", {
    Parent = FloatingButtons,
    FillDirection = state.layout.sidebarCollapsed
        and Enum.FillDirection.Vertical
        or Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 2),
}) :: UIListLayout

local function createFloatingLauncher(
    name: string,
    fallbackText: string,
    callback: () -> (),
    iconAsset: string?
): TextButton
    local button: TextButton = makeButton(FloatingButtons, fallbackText, 8)
    button.Name = name
    button.BackgroundTransparency = 1
    button.Size = UDim2.fromOffset(30, 24)
    button.ZIndex = 25
    button:SetAttribute("ThemeRole", "Icon")
    local stroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
    if stroke then
        stroke.Enabled = false
    end
    -- The three-letter labels were placeholders. The icon replaces the text
    -- once it resolves, and the text stays put if it never does.
    if iconAsset and state.applyAssetImage then
        local icon: ImageLabel = create("ImageLabel", {
            Parent = button,
            Name = "Icon",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "",
            ImageTransparency = 0.12,
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            ZIndex = 26,
        }) :: ImageLabel
        create("UICorner", {Parent = icon, CornerRadius = cornerRadius(UI_RADIUS.chip)})
        state.applyAssetImage(iconAsset, icon, function(): ()
            button.Text = ""
        end)
    end
    trackUiConnection(button.MouseButton1Click:Connect(callback))
    return button
end

state.onLayout(function(metrics: LayoutMetrics): ()
    FloatingButtons.Size = UDim2.fromOffset(
        metrics.sidebarCollapsed and 34 or 72,
        metrics.launcherHeight
    )
    FloatingButtonsLayout.FillDirection = metrics.sidebarCollapsed
        and Enum.FillDirection.Vertical
        or Enum.FillDirection.Horizontal
end)

createFloatingLauncher("Favorites", "FAV", function(): ()
    FavoritesWindow.root.Visible = not FavoritesWindow.root.Visible
    configData.ui.favoritesWindowOpen = FavoritesWindow.root.Visible
    if FavoritesWindow.root.Visible then
        refreshFavorites()
        bringFloatingToFront(FavoritesWindow)
    end
    queueConfigSave()
end, "windowFavorites")
createFloatingLauncher("Overlays", "OVR", function(): ()
    OverlayMenu.root.Visible = not OverlayMenu.root.Visible
    configData.ui.overlayMenuOpen = OverlayMenu.root.Visible
    if OverlayMenu.root.Visible then
        bringFloatingToFront(OverlayMenu)
    end
    queueConfigSave()
end, "windowOverlays")

FavoritesWindow.root.Visible = configData.ui.favoritesWindowOpen == true
OverlayMenu.root.Visible = configData.ui.overlayMenuOpen == true
for overlayId: string, overlay: any in pairs(FloatingUi.overlays) do
    setOverlayEnabled(overlayId, configData.ui.overlays[overlayId] == true)
end
refreshFavorites()
end

local function applyFeaturePresentation(feature: any, isDefault: boolean): ()
    local enabled: boolean = feature.kind == "hold"
        and feature.active == true
        or feature.enabled == true
    if feature.row then
        feature.row.BackgroundColor3 = isDefault
            and (enabled and Theme.DefaultSurfaceHover or Theme.DefaultSurface)
            or (enabled and Color3.fromRGB(31, 31, 35) or Theme.Background)
        feature.row.BackgroundTransparency = isDefault
            and (enabled and 0.5 or 0.82)
            or (enabled and 0.08 or 1)
    end
    if feature.stroke then
        feature.stroke.Color = isDefault
            and Theme.DefaultOutline
            or (enabled and Color3.fromRGB(225, 225, 230) or Theme.Outline)
        feature.stroke.Transparency = isDefault
            and (enabled and 0.68 or 1)
            or (enabled and 0.18 or 1)
    end
    if feature.activeStripe then
        feature.activeStripe.BackgroundColor3 = feature.isAction
            and Theme.AccentPink
            or (feature.isCategory and Theme.AccentViolet or Theme.DefaultAccent)

        feature.activeStripe.BackgroundTransparency = enabled
            and 0
            or ((feature.isAction or feature.isCategory or feature.isHoldAction)
                and 0.42
                or 1)
    end
    if feature.activeStripeGradient then
        feature.activeStripeGradient.Enabled = not isDefault
    end
    if feature.title then
        feature.title.TextColor3 = isDefault
            and (enabled and Theme.DefaultAccent or Theme.DefaultText)
            or Theme.Text
    end
    if feature.subtitle then
        feature.subtitle.TextColor3 = isDefault
            and Theme.DefaultTextMuted
            or Theme.TextMuted
    end
    if feature.options then
        feature.options.BackgroundTransparency = 1
    end
    if feature.arrow then
        feature.arrow.TextColor3 = isDefault
            and Theme.DefaultTextMuted
            or Theme.TextMuted
    end
    if feature.shortcutButton then
        feature.shortcutButton.BackgroundColor3 = isDefault
            and Theme.DefaultSurface
            or Theme.SurfaceRaised
        -- A container's slot is inert, so it stays a faint placeholder
        -- instead of being repainted as an interactive key slot.
        local inertSlot: boolean = feature.kind == "group"
        feature.shortcutButton.BackgroundTransparency = inertSlot
            and 0.86
            or (isDefault and 0.54 or 1)
        feature.shortcutButton.TextTransparency = inertSlot and 1 or 0
        feature.shortcutButton.TextColor3 = isDefault
            and Theme.DefaultText
            or Theme.Text
    end
end
state.restyleAllFeatures = function(isDefault: boolean): ()
    for _, feature: any in ipairs(allFeatures) do
        applyFeaturePresentation(feature, isDefault)
    end
end

local function refreshFeatureToggle(feature: any): ()
    if feature.isCategory or feature.isAction then
        return
    end
    -- A hold module has no enabled state: what it shows is whether its key is
    -- being held right now.
    if feature.isHoldAction then
        feature.enabled = feature.active == true
    end
    if feature.activeStripe then
        TweenService:Create(
            feature.activeStripe,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {BackgroundTransparency = feature.enabled
                and 0
                or (feature.isHoldAction and 0.42 or 1)}
        ):Play()
    end
    if feature.row then
        TweenService:Create(
            feature.row,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {
                BackgroundColor3 = feature.enabled
                    and (state.guiStyle == "Default"
                        and Theme.DefaultSurfaceHover
                        or Color3.fromRGB(31, 31, 35))
                    or (state.guiStyle == "Default"
                        and Theme.DefaultSurface
                        or Theme.Background),
                BackgroundTransparency = state.guiStyle == "Default"
                    and (feature.enabled and 0.5 or 0.82)
                    or (feature.enabled and 0.08 or 1),
            }
        ):Play()
    end
    if feature.title then
        TweenService:Create(
            feature.title,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {TextColor3 = state.guiStyle == "Default"
                and (feature.enabled and Theme.DefaultAccent or Theme.DefaultText)
                or (feature.enabled and Color3.fromRGB(255, 255, 255) or Theme.Text)}
        ):Play()
    end
    if feature.stroke then
        TweenService:Create(
            feature.stroke,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {
                Color = feature.enabled
                    and (state.guiStyle == "Default"
                        and Theme.DefaultOutline
                        or Color3.fromRGB(225, 225, 230))
                    or (state.guiStyle == "Default"
                        and Theme.DefaultOutline
                        or Theme.Outline),
                Transparency = state.guiStyle == "Default"
                    and (feature.enabled and 0.68 or 1)
                    or (feature.enabled and 0.18 or 1),
            }
        ):Play()
    end
    -- The switch is the state: knob to the right and lit when the module is
    -- on, back to the left and dim when it is off.
    if feature.kindKnob and feature.kindTrack then
        TweenService:Create(
            feature.kindKnob,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Position = UDim2.new(0, feature.enabled and 12 or 2, 0.5, 0),
                BackgroundTransparency = feature.enabled and 0 or 0.35,
            }
        ):Play()
        TweenService:Create(
            feature.kindTrack,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = feature.enabled and 0.62 or 0.86}
        ):Play()
    end
    if feature.kindCore and feature.kind == "hold" then
        feature.kindCore.BackgroundTransparency = feature.enabled and 0.1 or 1
    end
    if state.floatingUi then
        state.floatingUi.refreshFeature(feature)
    end
end

local function runActionButton(
    button: TextButton,
    idleText: string,
    callback: () -> (),
    successMessage: string,
    errorPrefix: string
): ()
    if button:GetAttribute("Running") == true then
        return
    end
    button:SetAttribute("Running", true)
    button:SetAttribute("Disabled", true)
    button.Active = false
    button.Text = "Running…"
    button.BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultButtonHover
        or Theme.AccentSoft

    task.spawn(function(): ()
        local running: boolean = true
        task.spawn(function(): ()
            local frames: {string} = {"Running·", "Running··", "Running···"}
            local frameIndex: number = 1
            while running and button.Parent do
                button.Text = frames[frameIndex]
                frameIndex = frameIndex % #frames + 1
                task.wait(0.22)
            end
        end)

        local success: boolean, errorMessage: any = pcall(callback)
        running = false
        if button.Parent then
            button.Text = success and "Done" or "Failed"
            button.BackgroundColor3 = success and Theme.AccentSoft or Theme.Danger
        end
        if success then
            notify(successMessage)
        else
            warn(errorPrefix .. ": " .. tostring(errorMessage))
            notify("Error in " .. errorPrefix)
        end
        task.wait(0.45)
        if button.Parent then
            button.Text = idleText
            button.Active = true
            button:SetAttribute("Disabled", false)
            button:SetAttribute("Running", false)
            button.BackgroundColor3 = idleText == "RUN"
                and Theme.AccentSoft
                or Theme.Surface
        end
    end)
end

-- Label for a placed mobile button.
--
-- It used to be squeezed into six characters, so "Infinite Jump" arrived as
-- "INFINI" and several modules became indistinguishable. The full name is kept
-- and the button wraps it over two lines at a smaller size; only genuinely
-- long names are trimmed, on a word boundary.
local function compactShortcutLabel(label: string): string
    local trimmed: string = string.upper(
        (string.gsub(string.gsub(label, "%s+", " "), "^%s*(.-)%s*$", "%1"))
    )
    if trimmed == "" then
        return "ACTION"
    end
    if #trimmed <= 18 then
        return trimmed
    end
    local cut: string = string.sub(trimmed, 1, 18)
    local lastSpace: number? = string.find(string.reverse(cut), " ")
    if lastSpace and lastSpace < 8 then
        cut = string.sub(cut, 1, 18 - lastSpace)
    end
    return cut
end

-- ---------------------------------------------------------------------------
-- Keybinds
-- ---------------------------------------------------------------------------
--
-- Every module card carries one key slot in its header, and that slot is the
-- only place an activation key ever lives — modules no longer bury their key
-- inside the options panel.
--
-- The slot supports two shapes:
--   * tap    — press the key, the module toggles or the action runs.
--   * hold   — the module is active only while the key is held (Sprint).
--
-- On touch devices the same slot is the mobile-button factory: a tap opens
-- placement mode, the button is dropped anywhere on screen, and it drives the
-- same press/release pair, so hold-style features work with a finger too.
--
-- Bindings live in one registry with one global input handler instead of a
-- connection per module, which is what makes hold state reliable: releasing a
-- key always reaches the module that claimed it.
state.shortcutBindings = {} :: {[string]: any}

local function shortcutSlotText(binding: any): string
    -- Blank when unbound. The empty slot is the affordance; a "KEY" caption
    -- only added noise and made no sense on a phone.
    if binding.key == Enum.KeyCode.Unknown then
        return ""
    end
    return binding.key.Name
end

local function setShortcutPressed(binding: any, pressed: boolean): ()
    if binding.pressed == pressed then
        return
    end
    binding.pressed = pressed
    if pressed then
        if binding.onPress then
            task.spawn(binding.onPress)
        end
    elseif binding.onRelease then
        task.spawn(binding.onRelease)
    end
end

state.releaseShortcut = function(id: string): ()
    local binding: any = state.shortcutBindings[id]
    if binding and binding.hold then
        setShortcutPressed(binding, false)
    end
end

local function bindActionShortcut(
    button: TextButton,
    shortcutId: string,
    label: string,
    callback: () -> (),
    options: any?
): ()
    local configuration: any = options or {}
    local optionKey: string = "Shortcut." .. shortcutId:gsub("%W", "")
    local binding: any = {
        id = shortcutId,
        button = button,
        hold = configuration.hold == true,
        key = Enum.KeyCode.Unknown,
        pressed = false,
        onPress = configuration.onPress or callback,
        onRelease = configuration.onRelease,
    }
    local savedName: any = configData.values[optionKey]
    if type(savedName) == "string" and savedName ~= "" then
        local savedKey: Enum.KeyCode? = Enum.KeyCode[savedName]
        if savedKey then
            binding.key = savedKey
        end
    end
    state.shortcutBindings[shortcutId] = binding

    local function refreshButtonText(): ()
        button.Text = shortcutSlotText(binding)
        button:SetAttribute("CaptureIdleText", button.Text)
    end
    binding.refresh = refreshButtonText
    refreshButtonText()

    if state.isMobile then
        -- Touch: the slot is the placement trigger. A tap is enough — the
        -- previous 0.6s hold was undiscoverable on a blank button.
        --
        -- The placed button calls through the binding rather than capturing
        -- the callbacks: a module that re-points its key later (Shoot swaps
        -- "toggle the module" for "fire now") must change what the on-screen
        -- button does too.
        if state.bindMobileActionPlacement then
            state.bindMobileActionPlacement(
                button,
                "Shortcut" .. shortcutId:gsub("%W", ""),
                compactShortcutLabel(label),
                function(): ()
                    if not binding.hold and binding.onPress then
                        binding.onPress()
                    end
                end,
                {
                    isActive = function(): boolean
                        return binding.hold == true
                    end,
                    onPress = function(): ()
                        if binding.hold and binding.onPress then
                            binding.onPress()
                        end
                    end,
                    onRelease = function(): ()
                        if binding.hold and binding.onRelease then
                            binding.onRelease()
                        end
                    end,
                }
            )
        end
        return
    end

    trackUiConnection(button.MouseButton1Click:Connect(function(): ()
        beginKeyCapture(button, function(keyCode: Enum.KeyCode): ()
            -- Pressing the same key again clears the binding.
            binding.key = keyCode == binding.key
                and Enum.KeyCode.Unknown
                or keyCode
            setShortcutPressed(binding, false)
            configData.values[optionKey] = binding.key.Name
            queueConfigSave()
            refreshButtonText()
        end)
    end))
end

-- Modules whose "activation key" used to be an option row call this instead:
-- the key lives in the card's header slot, is seeded with the module's own
-- default the first time, and drives the module directly. On touch the same
-- slot places a mobile button for it.
state.bindFeatureActivationKey = function(
    feature: any,
    defaultKey: Enum.KeyCode?,
    onPress: () -> (),
    onRelease: (() -> ())?
): ()
    local binding: any = state.shortcutBindings[feature.configKey]
    if not binding then
        return
    end
    binding.onPress = onPress
    binding.onRelease = onRelease
    binding.hold = onRelease ~= nil
    if binding.key == Enum.KeyCode.Unknown
        and defaultKey ~= nil
        and defaultKey ~= Enum.KeyCode.Unknown then
        binding.key = defaultKey
    end
    if binding.refresh then
        binding.refresh()
    end
end

-- One handler for every binding. `gameProcessed` is respected so typing in a
-- chat box never fires a module.
do
local function shortcutInputAllowed(gameProcessed: boolean): boolean
    return not gameProcessed
        and not state.keyCaptureCallback
        and not state.waitingForKey
        and UserInputService:GetFocusedTextBox() == nil
end

state.globalShortcutBeganConnection = UserInputService.InputBegan:Connect(
    function(input: InputObject, gameProcessed: boolean): ()
        if input.UserInputType ~= Enum.UserInputType.Keyboard
            or not shortcutInputAllowed(gameProcessed) then
            return
        end
        -- `Unknown` is what an unbound slot holds *and* what some keyboard
        -- events report, so it is never treated as a match: otherwise one
        -- odd keypress would fire every module that has no key assigned.
        if input.KeyCode == Enum.KeyCode.Unknown then
            return
        end
        for _, binding: any in pairs(state.shortcutBindings) do
            if binding.key == input.KeyCode then
                if binding.hold then
                    setShortcutPressed(binding, true)
                elseif binding.onPress then
                    task.spawn(binding.onPress)
                end
            end
        end
    end
)

-- Releases are never filtered by `gameProcessed`: a hold that started must
-- always be able to stop, even if the release lands on a game UI element.
state.globalShortcutEndedConnection = UserInputService.InputEnded:Connect(
    function(input: InputObject): ()
        if input.UserInputType ~= Enum.UserInputType.Keyboard
            or input.KeyCode == Enum.KeyCode.Unknown then
            return
        end
        for _, binding: any in pairs(state.shortcutBindings) do
            if binding.hold and binding.key == input.KeyCode then
                setShortcutPressed(binding, false)
            end
        end
    end
)

-- Losing focus (alt-tab, menu opening) must not leave a hold latched on.
trackUiConnection(UserInputService.WindowFocusReleased:Connect(function(): ()
    for _, binding: any in pairs(state.shortcutBindings) do
        if binding.hold then
            setShortcutPressed(binding, false)
        end
    end
end))
end


local function createUniversalFeature(
    name: string,
    description: string,
    layoutOrder: number,
    onToggle: any,
    configuration: any?
): any
    configuration = configuration or {}
    local registry: any = configuration.registry or universalFeatures
    local sectionName: string = configuration.section
        or (registry == mm2Features and "MM2")
        or (registry == state.trsFeatures and "TRS")
        or (registry == state.vdFeatures and "VD")
        or (registry == state.mvsdFeatures and "MVSD")
        or (registry == movementFeatures and "Movement")
        or "Universal"
    local configKey: string = configuration.configKey
        or (sectionName .. "." .. name:gsub("%W", ""))
    -- A module may declare its own category; otherwise the shared taxonomy
    -- decides, and anything unknown lands in the catch-all bucket.
    local categoryName: string = type(configuration.categoryName) == "string"
        and configuration.categoryName
        or FEATURE_CATEGORIES[name]
        or DEFAULT_FEATURE_CATEGORY

    local feature: any = {
        name = name,
        description = description,
        categoryName = categoryName,
        enabled = false,
        expanded = false,
        -- Module kinds.
        --
        -- Everything about a card — what a click does, what its key slot
        -- does, whether it can be "off", whether it announces itself — is
        -- decided by one kind instead of a pile of independent booleans:
        --
        --   toggle  (default) enable/disable state; click or key flips it.
        --   action            a button: click or key runs it once, no state.
        --   hold              always-on system; the key is a dead-man switch
        --                     that only applies the effect while it is held.
        --                     It can never be turned off and never toasts.
        --   group             an always-on container of options; the card
        --                     expands, and its key slot is inert because
        --                     there is nothing to activate.
        --
        -- Legacy flags still work: `action`, `category` and `holdAction` map
        -- onto the kinds above.
        kind = configuration.kind
            or (configuration.action == true and "action")
            or (configuration.holdAction == true and "hold")
            or (configuration.category == true and "group")
            or "toggle",
        silentAction = configuration.silentAction == true,
        onHold = configuration.onHold,
        optionCount = 0,
        optionRows = {},
        collapsedHeight = state.layout.cardHeight,
        onToggle = onToggle,
        configKey = configKey,
        registry = registry,
        sectionName = sectionName,
        searchText = string.lower(
            name
                .. " "
                .. description
                .. " "
                .. sectionName
                .. " "
                .. categoryName
        ),
        tooltipText = description,
        tooltipBound = false,
    }

    -- Kept as plain flags so existing code (and the game modules downloaded
    -- from the repository) keep reading the same fields.
    feature.isAction = feature.kind == "action"
    feature.isCategory = feature.kind == "group"
    feature.isHoldAction = feature.kind == "hold"
    feature.isAlwaysOn = feature.kind == "hold" or feature.kind == "group"

    local requestedParent: Instance =
        configuration.parent or UniversalScroll
    local row: Frame = (create("Frame", {
        Parent = getFeatureCardParent(requestedParent),
        Name = name:gsub("%W", "") .. "Feature",
        Active = true,
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultSurface
            or Theme.Background,
        BackgroundTransparency = state.guiStyle == "Default" and 0.82 or 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, feature.collapsedHeight),
    }) :: any) :: Frame
    feature.row = row
    -- Ordering metadata read back by the card grid. `layoutOrder` above is
    -- only the pre-sort value; the category pass overwrites it on the next
    -- frame with "category block + alphabetical position".
    row:SetAttribute("FeatureCategory", categoryName)
    row:SetAttribute("FeatureSortName", string.lower(name))
    if state.invalidateCategoryLayout then
        state.invalidateCategoryLayout()
    end
    create("UICorner", {
        Parent = row,
        Name = "CardCorner",
        CornerRadius = cornerRadius(state.layout.cardCorner),
    })
    local cardStroke: UIStroke = (create("UIStroke", {
        Parent = row,
        Color = state.guiStyle == "Default"
            and Theme.DefaultOutline
            or Theme.Outline,
        Transparency = 1,
        Thickness = 1,
    }) :: any) :: UIStroke
    feature.stroke = cardStroke
    local activeStripe: Frame = create("Frame", {
        Parent = row,
        Name = "ActiveStripe",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.DefaultAccent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 2, 1, -14),
        ZIndex = 8,
    }) :: Frame
    create("UICorner", {Parent = activeStripe, CornerRadius = UDim.new(1, 0)})
    feature.activeStripeGradient = create("UIGradient", {
        Parent = activeStripe,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.DefaultAccent),
            ColorSequenceKeypoint.new(0.5, Theme.AccentViolet),
            ColorSequenceKeypoint.new(1, Theme.AccentPink),
        }),
        Rotation = 90,
    })
    feature.activeStripe = activeStripe
    local kindColor: Color3 = KIND_COLORS[feature.kind] or Theme.DefaultAccent
    activeStripe.BackgroundColor3 = kindColor
    if feature.activeStripeGradient then
        (feature.activeStripeGradient :: UIGradient).Enabled = false
    end
    -- Always-on kinds keep a dim stripe lit: they have no "off", and a card
    -- with no stripe at all reads as disabled.
    if feature.isAlwaysOn then
        activeStripe.BackgroundTransparency = 0.55
    end

    -- Kind marker. Drawn from frames rather than written, so it reads the
    -- same at every text size and in every language.
    local kindMark: Frame = create("Frame", {
        Parent = row,
        Name = "KindMark",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 12, 0, math.round(feature.collapsedHeight * 0.74)),
        Size = UDim2.fromOffset(26, 14),
        ZIndex = 9,
    }) :: Frame

    if feature.kind == "action" then
        -- A play triangle, built from two tapered bars: Roblox has no polygon
        -- primitive and a glyph would depend on the font.
        local triangleTop: Frame = create("Frame", {
            Parent = kindMark,
            Name = "PlayTop",
            AnchorPoint = Vector2.new(0.5, 1),
            BackgroundColor3 = kindColor,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 8, 0.5, 1),
            Rotation = 27,
            Size = UDim2.fromOffset(11, 2),
            ZIndex = 10,
        }) :: Frame
        create("UICorner", {Parent = triangleTop, CornerRadius = UDim.new(1, 0)})
        local triangleBottom: Frame = create("Frame", {
            Parent = kindMark,
            Name = "PlayBottom",
            AnchorPoint = Vector2.new(0.5, 0),
            BackgroundColor3 = kindColor,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 8, 0.5, -1),
            Rotation = -27,
            Size = UDim2.fromOffset(11, 2),
            ZIndex = 10,
        }) :: Frame
        create("UICorner", {Parent = triangleBottom, CornerRadius = UDim.new(1, 0)})
        local playSpine: Frame = create("Frame", {
            Parent = kindMark,
            Name = "PlaySpine",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = kindColor,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 3, 0.5, 0),
            Size = UDim2.fromOffset(2, 10),
            ZIndex = 10,
        }) :: Frame
        create("UICorner", {Parent = playSpine, CornerRadius = UDim.new(1, 0)})
    elseif feature.isAlwaysOn then
        local ring: Frame = create("Frame", {
            Parent = kindMark,
            Name = "Ring",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 1, 0.5, 0),
            Size = UDim2.fromOffset(12, 12),
            ZIndex = 10,
        }) :: Frame
        create("UICorner", {Parent = ring, CornerRadius = UDim.new(1, 0)})
        create("UIStroke", {
            Parent = ring,
            Color = kindColor,
            Transparency = 0.25,
            Thickness = 1,
        })
        -- A hold module is live only while its key is down, so its ring stays
        -- hollow until `setHeld` fills it; a group module is always running
        -- and shows the dot from the start.
        local core: Frame = create("Frame", {
            Parent = ring,
            Name = "Core",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = kindColor,
            BackgroundTransparency = feature.kind == "group" and 0.1 or 1,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(6, 6),
            ZIndex = 11,
        }) :: Frame
        create("UICorner", {Parent = core, CornerRadius = UDim.new(1, 0)})
        feature.kindCore = core
    else
        local track: Frame = create("Frame", {
            Parent = kindMark,
            Name = "Track",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = kindColor,
            BackgroundTransparency = 0.86,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(22, 12),
            ZIndex = 10,
        }) :: Frame
        create("UICorner", {Parent = track, CornerRadius = UDim.new(1, 0)})
        create("UIStroke", {
            Parent = track,
            Color = kindColor,
            Transparency = 0.55,
            Thickness = 1,
        })
        local knob: Frame = create("Frame", {
            Parent = track,
            Name = "Knob",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = kindColor,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.fromOffset(8, 8),
            ZIndex = 11,
        }) :: Frame
        create("UICorner", {Parent = knob, CornerRadius = UDim.new(1, 0)})
        feature.kindTrack = track
        feature.kindKnob = knob
    end
    feature.kindMark = kindMark

    local title: TextLabel =
        (makeTextLabel(row, name, state.layout.titleFontSize) :: any) :: TextLabel
    title.FontFace = CONTROL_FONT
    title.Position = UDim2.fromOffset(12, 0)
    -- The kind chip sits under the title, so the title centres in the upper
    -- two thirds of the card instead of the whole of it.
    title.Size = UDim2.new(
        1,
        -(state.layout.cardHeight + 96),
        0,
        math.round(feature.collapsedHeight * 0.62)
    )
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.TextColor3 = state.guiStyle == "Default"
        and Theme.DefaultText
        or Theme.Text
    feature.title = title

    local subtitle: TextLabel =
        (makeTextLabel(row, description, state.layout.bodyFontSize) :: any) :: TextLabel
    subtitle.Name = "Description"
    subtitle.Position = UDim2.fromOffset(12, math.round(feature.collapsedHeight * 0.58))
    subtitle.Size = UDim2.new(1, -(state.layout.cardHeight + 96), 0, 24)
    subtitle.TextColor3 = state.guiStyle == "Default"
        and Theme.DefaultTextMuted
        or Theme.TextMuted
    subtitle.TextTruncate = Enum.TextTruncate.AtEnd
    subtitle.TextWrapped = true
    subtitle.Visible = false
    feature.subtitle = subtitle

    local headerControls: Frame = create("Frame", {
        Parent = row,
        Name = "HeaderControls",
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -8, 0, feature.collapsedHeight / 2),
        Size = UDim2.fromOffset(
            state.layout.iconButton * 2 + state.layout.keySlotWidth + 12,
            state.layout.iconButton + 4
        ),
        ZIndex = 9,
    }) :: Frame
    create("UIListLayout", {
        Parent = headerControls,
        Name = "HeaderControlsLayout",
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, state.layout.compact and 4 or 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local arrow: TextButton =
        (makeButton(headerControls, "...", 10) :: any) :: TextButton
    arrow.Name = "Expand"
    arrow.LayoutOrder = 3
    arrow:SetAttribute("ThemeRole", "Icon")
    arrow:SetAttribute("NoPressEffect", true)
    arrow.BackgroundTransparency = 1
    arrow.Size =
        UDim2.fromOffset(state.layout.iconButton, state.layout.iconButton)
    arrow.TextColor3 = state.guiStyle == "Default"
        and Theme.DefaultTextMuted
        or Theme.TextMuted
    -- Every card shows the three dots, including modules with nothing to
    -- configure (Anti-AFK, Anti-Void, X-Ray...): a row that silently drops a
    -- control makes the list look ragged. A card with no options simply never
    -- opens — the dots are dimmed and the click is ignored, which is checked
    -- at click time because option rows can be added after the card is built.
    arrow.Active = true
    arrow.TextTransparency = configuration.noOptions == true and 0.68 or 0.35
    arrow.ZIndex = 9
    local arrowStroke: UIStroke? = arrow:FindFirstChild("StyleStroke") :: UIStroke?
    if arrowStroke then
        arrowStroke.Enabled = false
    end
    feature.arrow = arrow

    -- A module is expandable when it actually owns at least one option row.
    function feature.hasOptions(): boolean
        if configuration.noOptions == true then
            return false
        end
        for _, optionRow: GuiObject in ipairs(feature.optionRows) do
            if optionRow.Visible then
                return true
            end
        end
        return false
    end

    local activationTarget: TextButton = create("TextButton", {
        Parent = row,
        Name = "ActivationTarget",
        Active = true,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, feature.collapsedHeight),
        Text = "",
        ZIndex = 6,
    }) :: TextButton
    feature.activationTarget = activationTarget
    title.ZIndex = 7

    trackUiConnection(row.MouseEnter:Connect(function(): ()
        if feature.enabled then
            return
        end
        TweenService:Create(
            row,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {
                BackgroundColor3 = state.guiStyle == "Default"
                    and Theme.DefaultSurfaceHover
                    or Theme.SurfaceHover,
                BackgroundTransparency = state.guiStyle == "Default" and 0.66 or 0.78,
            }
        ):Play()
    end))
    trackUiConnection(row.MouseLeave:Connect(function(): ()
        TweenService:Create(
            row,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {
                BackgroundColor3 = feature.enabled
                    and (state.guiStyle == "Default"
                        and Theme.DefaultSurfaceHover
                        or Color3.fromRGB(31, 31, 35))
                    or (state.guiStyle == "Default"
                        and Theme.DefaultSurface
                        or Theme.Background),
                BackgroundTransparency = state.guiStyle == "Default"
                    and (feature.enabled and 0.5 or 0.82)
                    or (feature.enabled and 0.08 or 1),
            }
        ):Play()
    end))

    -- The options panel is a plain container, not a third surface.
    --
    -- It used to draw its own fill, corners and outline *inside* the card,
    -- with every option row drawing its own fill and outline again inside
    -- that: three nested rounded rectangles for one setting. The panel is
    -- transparent now, so an expanded card shows the card and its rows, and
    -- nothing in between.
    local options: Frame = (create("Frame", {
        Parent = row,
        Name = "Options",
        Active = true,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, feature.collapsedHeight),
        Size = UDim2.new(1, -16, 0, 0),
        Visible = false,
        ZIndex = row.ZIndex + 10,
    }) :: any) :: Frame
    feature.options = options
    create("UIPadding", {
        Parent = options,
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 2),
        PaddingTop = UDim.new(0, 2),
    })
    local optionsLayout: UIListLayout = (create("UIListLayout", {
        Parent = options,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }) :: any) :: UIListLayout

    local function updateExpandedSize(animate: boolean?): ()
        -- Rows are no longer a uniform height (hint rows are taller, section
        -- headings shorter), so the fallback used before the layout has
        -- measured anything sums the declared heights instead of assuming 38.
        local visibleOptions: number = 0
        local declaredHeight: number = 0
        for _, optionRow: GuiObject in ipairs(feature.optionRows) do
            if optionRow.Visible then
                visibleOptions += 1
                declaredHeight += optionRow.Size.Y.Offset
            end
        end
        local measuredHeight: number = optionsLayout.AbsoluteContentSize.Y
        if visibleOptions > 0 and measuredHeight <= 0 then
            measuredHeight = declaredHeight
                + math.max(0, visibleOptions - 1) * 6
        end
        -- +8 = the panel's 2px top and 6px bottom UIPadding.
        local optionsHeight: number = measuredHeight + 8
        local targetOptionsSize: UDim2 = UDim2.new(1, -16, 0, optionsHeight)
        local targetRowSize: UDim2 = UDim2.new(
            1,
            0,
            0,
            feature.expanded
                and feature.collapsedHeight + optionsHeight + 6
                or feature.collapsedHeight
        )
        if feature.expanded then
            options.Visible = true
        end
        if animate and state.animationsEnabled then
            TweenService:Create(
                options,
                TweenInfo.new(UI_MOTION.slow, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                {Size = targetOptionsSize}
            ):Play()
            TweenService:Create(
                row,
                TweenInfo.new(UI_MOTION.slow, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                {Size = targetRowSize}
            ):Play()
            arrow.TextColor3 = state.guiStyle == "Default"
                and (feature.expanded and Theme.DefaultText or Theme.DefaultTextMuted)
                or (feature.expanded and Theme.Text or Theme.TextMuted)
            if not feature.expanded then
                task.delay(UI_MOTION.slow + 0.02, function(): ()
                    if not feature.expanded and options.Parent then
                        options.Visible = false
                    end
                end)
            end
        else
            options.Size = targetOptionsSize
            row.Size = targetRowSize
            arrow.TextColor3 = state.guiStyle == "Default"
                and (feature.expanded and Theme.DefaultText or Theme.DefaultTextMuted)
                or (feature.expanded and Theme.Text or Theme.TextMuted)
            options.Visible = feature.expanded
        end
    end
    feature.updateExpandedSize = updateExpandedSize
    trackUiConnection(
        optionsLayout:GetPropertyChangedSignal("AbsoluteContentSize")
            :Connect(function(): ()
                updateExpandedSize(false)
            end)
    )

    trackUiConnection(arrow.MouseButton1Click:Connect(function(): ()
        if not feature.hasOptions() then
            -- Nothing to show: keep the panel shut instead of opening an
            -- empty box under the card.
            arrow.TextTransparency = 0.68
            return
        end
        feature.expanded = not feature.expanded
        updateExpandedSize(true)
    end))

    -- Hold modules.
    --
    -- The module itself is *always* running — it can never be switched off
    -- and never announces itself. `setHeld` only reports whether the player
    -- is currently holding the key (or the placed mobile button), and the
    -- module applies or drops its effect accordingly. The card lights up
    -- while held purely as feedback.
    function feature.setHeld(held: boolean): ()
        if feature.held == held then
            return
        end
        feature.held = held
        local handler: any = feature.onHold
        if type(handler) ~= "function" then
            return
        end
        local ok: boolean, failure: any = pcall(handler, held)
        if not ok then
            warn("[Random Testing Menu] " .. name .. ": " .. tostring(failure))
            return
        end
        feature.active = held
        refreshFeatureToggle(feature)
    end

    local function activateFeature(): ()
        if feature.isHoldAction then
            -- Clicking the card does nothing: a hold module has no on/off
            -- state to flip, and an accidental click must never leave the
            -- effect latched. Only the key slot drives it.
            return
        end
        if feature.isCategory then
            if not feature.hasOptions() then
                return
            end
            feature.expanded = not feature.expanded
            updateExpandedSize(true)
            return
        end
        if feature.isAction then
            if feature.actionRunning then
                return
            end
            feature.actionRunning = true
            task.spawn(function(): ()
                local success: boolean, errorMessage: any = pcall(feature.onToggle)
                feature.actionRunning = false
                if success then
                    -- Actions meant to be spammed from a hotkey (High Jump)
                    -- opt out of the toast: one notification per keypress is
                    -- noise, not feedback.
                    if not feature.silentAction then
                        notify(name .. " ran")
                    end
                else
                    warn("[Random Testing Menu] " .. name .. ": " .. tostring(errorMessage))
                    notify("Could not run " .. name)
                end
            end)
            return
        end

        local requestedState: boolean = not feature.enabled
        local success: boolean, errorMessage: any = pcall(
            feature.onToggle,
            requestedState
        )
        if success then
            feature.enabled = requestedState
            if requestedState then
                feature.enabledAt = os.clock()
            end
            configData.states[feature.configKey] = requestedState
            queueConfigSave()
            notify(name .. (requestedState and " enabled" or " disabled"))
        else
            warn("[Random Testing Menu] " .. name .. ": " .. tostring(errorMessage))
            feature.enabled = false
            pcall(feature.onToggle, false)
            notify("Could not toggle " .. name)
        end
        refreshFeatureToggle(feature)
    end
    feature.activate = activateFeature

    trackUiConnection(activationTarget.MouseButton1Click:Connect(activateFeature))
    do
        local favoriteButton: TextButton =
            (makeButton(headerControls, "☆", 11) :: any) :: TextButton
        favoriteButton.Name = "Favorite"
        favoriteButton.LayoutOrder = 1
        favoriteButton:SetAttribute("ThemeRole", "Icon")
        favoriteButton:SetAttribute("NoPressEffect", true)
        favoriteButton.BackgroundTransparency = 1
        favoriteButton.Size =
            UDim2.fromOffset(state.layout.iconButton, state.layout.iconButton)
        favoriteButton.ZIndex = 9
        local favoriteStroke: UIStroke? =
            favoriteButton:FindFirstChild("StyleStroke") :: UIStroke?
        if favoriteStroke then
            favoriteStroke.Enabled = false
        end
        feature.favoriteButton = favoriteButton
        trackUiConnection(favoriteButton.MouseButton1Click:Connect(function(): ()
            state.floatingUi.toggleFavorite(feature)
        end))
    end
    -- Every card header carries the same three controls — favourite, key
    -- slot, expand — so the whole list reads as one symmetric grid no matter
    -- whether the module is a toggle, an action or a category. The key slot
    -- toggles regular modules, runs actions, and expands/collapses category
    -- headers (the same path `activateFeature` already provides).
    local shortcutButton: TextButton =
        (makeButton(headerControls, "KEY", 9) :: any) :: TextButton
    shortcutButton.Name = "Shortcut"
    shortcutButton.LayoutOrder = 2
    shortcutButton.BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultSurface
        or Theme.SurfaceRaised
    shortcutButton.Size = UDim2.fromOffset(
        state.layout.keySlotWidth,
        state.layout.iconButton
    )
    shortcutButton.ZIndex = 9
    applyKeySlotStyle(shortcutButton)
    shortcutButton.TextScaled = true
    create("UITextSizeConstraint", {
        Parent = shortcutButton,
        MaxTextSize = 11,
        MinTextSize = 7,
    })
    feature.shortcutButton = shortcutButton
    if feature.kind == "group" then
        -- A container has nothing to activate: the slot stays on the card for
        -- symmetry but never captures a key, never places a mobile button and
        -- never fires. Pressing it does nothing, by design.
        shortcutButton.Active = false
        shortcutButton.AutoButtonColor = false
        shortcutButton.Text = ""
        shortcutButton.TextTransparency = 1
        shortcutButton.BackgroundTransparency = 0.86
        shortcutButton:SetAttribute("Disabled", true)
        shortcutButton:SetAttribute("NoHover", true)
        shortcutButton:SetAttribute("CaptureIdleText", "")
    elseif feature.kind == "hold" then
        -- The key is a dead-man switch: held means active, released means
        -- inactive. It never toggles the module on or off.
        bindActionShortcut(
            shortcutButton,
            feature.configKey,
            name,
            function(): () end,
            {
                hold = true,
                onPress = function(): ()
                    feature.setHeld(true)
                end,
                onRelease = function(): ()
                    feature.setHeld(false)
                end,
            }
        )
    else
        bindActionShortcut(
            shortcutButton,
            feature.configKey,
            name,
            activateFeature
        )
    end

    feature.headerControls = headerControls

    -- Re-applies the responsive metrics to this card. The shared listener
    -- registered next to `allFeatures` calls it for every module whenever the
    -- viewport mode changes, which is what makes phone/tablet/desktop layouts
    -- work without a single game module knowing a pixel value.
    feature.applyLayout = function(): ()
        local metrics: LayoutMetrics = state.layout
        local sideWidth: number =
            metrics.iconButton * 2 + metrics.keySlotWidth + 12
        feature.collapsedHeight = metrics.cardHeight
        local cardCorner: UICorner? = row:FindFirstChild("CardCorner") :: UICorner?
        if cardCorner then
            cardCorner.CornerRadius = cornerRadius(metrics.cardCorner)
        end
        title.Size =
            UDim2.new(1, -(sideWidth + 26), 0, metrics.cardHeight)
        state.setTextMetric(title, metrics.titleFontSize)
        subtitle.Position =
            UDim2.fromOffset(12, math.round(metrics.cardHeight * 0.58))
        subtitle.Size = UDim2.new(1, -(sideWidth + 26), 0, 24)
        state.setTextMetric(subtitle, metrics.bodyFontSize)
        headerControls.Position = UDim2.new(1, -8, 0, metrics.cardHeight / 2)
        headerControls.Size =
            UDim2.fromOffset(sideWidth, metrics.iconButton + 4)
        local controlsLayout: UIListLayout? =
            headerControls:FindFirstChild("HeaderControlsLayout") :: UIListLayout?
        if controlsLayout then
            controlsLayout.Padding = UDim.new(0, metrics.compact and 4 or 6)
        end
        arrow.Size = UDim2.fromOffset(metrics.iconButton, metrics.iconButton)
        if feature.favoriteButton then
            feature.favoriteButton.Size =
                UDim2.fromOffset(metrics.iconButton, metrics.iconButton)
        end
        shortcutButton.Size =
            UDim2.fromOffset(metrics.keySlotWidth, metrics.iconButton)
        activationTarget.Size = UDim2.new(1, 0, 0, metrics.cardHeight)
        options.Position = UDim2.fromOffset(8, metrics.cardHeight)
        activeStripe.Size = UDim2.new(0, 2, 1, -14)
        updateExpandedSize(false)
    end
    -- Applied once at creation too, so a card built while the shell is in one
    -- mode never keeps sizes from another.
    feature.applyLayout()

    registry[name] = feature
    table.insert(allFeatures, feature)
    state.floatingUi.registerFeature(feature)
    applyFeaturePresentation(feature, state.guiStyle == "Default")

    -- No "Toggle key" option row any more: every card already carries a key
    -- slot in its header and that slot is the only place an activation key
    -- lives, on desktop and on touch alike.

    -- Always-on modules (hold systems, containers) start their runtime once,
    -- here, instead of waiting for a click that can never come.
    if feature.isAlwaysOn then
        task.defer(function(): ()
            local ok: boolean, failure: any = pcall(feature.onToggle, true)
            if not ok then
                warn("[Random Testing Menu] " .. name .. ": " .. tostring(failure))
            end
        end)
    end

    -- Hold modules are momentary: they are never restored as "on" at startup.
    if not feature.isAction
        and not feature.isCategory
        and not feature.isHoldAction
        and configuration.restore ~= false
        and configData.states[feature.configKey] == true then
        task.defer(function(): ()
            local success: boolean, errorMessage: any = pcall(
                feature.onToggle,
                true
            )
            if success then
                feature.enabled = true
                feature.enabledAt = os.clock()
                refreshFeatureToggle(feature)
            else
                configData.states[feature.configKey] = false
                queueConfigSave()
                warn(
                    "[Random Testing Menu] Could not restore "
                        .. name
                        .. ": "
                        .. tostring(errorMessage)
                )
            end
        end)
    end
    return feature
end

-- Places a control on the right-hand side of an option row.
--
-- Rows are no longer all the same height, so the vertical band a control may
-- occupy is published by `createOptionRow` as attributes rather than being
-- assumed. Every add*Option goes through this so sliders, cycle buttons, key
-- slots and text boxes all line up on the exact same edge: every row, in
-- every module, ends with a control band that starts at 50% of the row width
-- and finishes 10px from the right edge. That shared geometry is what keeps
-- panels with keybinds, sliders, toggles or actions visually symmetric.
--
-- Published on `state` instead of held in a local: `bootstrap()` is a single
-- function scope and is at Luau's 200 local-register ceiling.
state.layoutOptionControl = function(
    option: Frame,
    control: GuiObject,
    widthScale: number?
): ()
    local top: number = tonumber(option:GetAttribute("ControlTop")) or 0
    local height: number = tonumber(option:GetAttribute("ControlHeight"))
        or option.Size.Y.Offset
    -- The canonical control band. 0.5 is the default so every row type shares
    -- the same rectangle; rows that stack several controls (action pairs)
    -- subdivide this same band instead of drawing outside it.
    local scale: number = widthScale or 0.5
    control.AnchorPoint = Vector2.new(1, 0)
    control.Position = UDim2.new(1, -10, 0, top)
    control.Size = UDim2.new(scale, -10, 0, height)
    control.ZIndex = math.max(control.ZIndex, option.ZIndex + 2)
end

-- A single customisation row inside a module's panel: a label on the left, a
-- control on the right, exactly one line tall.
--
-- Each row is a self-contained card — its own soft fill, rounded corners, a
-- hairline border and a hover highlight — so it is obvious where one setting
-- stops and the next begins in panels with a lot of controls (Fly).
--
-- `hintText` is accepted and deliberately ignored. Modules pass an
-- explanatory sentence for many of their controls ("Balanced glides, Direct
-- stops instantly…"), which doubled the height of every panel and buried the
-- control itself. Dropping it here fixes every module at once — Fly, Fling,
-- Speed, Hitboxes and everything a game module adds — without touching a
-- single call site, and keeps the argument valid for older game modules
-- downloaded from the repository.
local function createOptionRow(
    feature: any,
    labelText: string,
    _hintText: string?
): Frame
    feature.optionCount += 1
    feature.searchText ..= " " .. string.lower(labelText)
    local rowHeight: number = state.layout.optionRowHeight
    local option: Frame = (create("Frame", {
        Parent = feature.options,
        Name = "Option_" .. labelText:gsub("%W", ""),
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.76,
        BorderSizePixel = 0,
        LayoutOrder = feature.optionCount,
        Size = UDim2.new(1, 0, 0, rowHeight),
        ZIndex = feature.options.ZIndex + 1,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = option,
        CornerRadius = cornerRadius(UI_RADIUS.control),
    })
    local optionStroke: UIStroke = (create("UIStroke", {
        Parent = option,
        Name = "OptionStroke",
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = Theme.DefaultOutline,
        Thickness = 1,
        Transparency = 0.82,
    }) :: any) :: UIStroke
    table.insert(feature.optionRows, option)

    trackUiConnection(option.MouseEnter:Connect(function(): ()
        TweenService:Create(
            option,
            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.62}
        ):Play()
        TweenService:Create(
            optionStroke,
            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Transparency = 0.62}
        ):Play()
    end))
    trackUiConnection(option.MouseLeave:Connect(function(): ()
        TweenService:Create(
            option,
            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.76}
        ):Play()
        TweenService:Create(
            optionStroke,
            TweenInfo.new(UI_MOTION.fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Transparency = 0.82}
        ):Play()
    end))

    local label: TextLabel =
        (makeTextLabel(option, labelText, 11) :: any) :: TextLabel
    label.Name = "OptionLabel"
    label.TextColor3 = Theme.DefaultText
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.ZIndex = option.ZIndex + 1
    -- The label column always ends at 48% of the row; the control band starts
    -- at 50%, so no label ever collides with any control type and the left
    -- edge of every control is the same in every module.
    label.Position = UDim2.fromOffset(12, 0)
    label.Size = UDim2.new(0.48, -12, 1, 0)

    option:SetAttribute("ControlTop", 6)
    option:SetAttribute("ControlHeight", rowHeight - 12)

    feature.updateExpandedSize()
    return option
end

-- A non-interactive heading used to break a long customisation panel into
-- labelled groups ("Flight", "Advanced", ...). It behaves like any other
-- option row for layout and visibility purposes, so `setOptionVisible` can
-- hide a whole group's heading along with its controls.
--
-- On `state` for the same local-register reason as `layoutOptionControl`.
state.addSectionOption = function(feature: any, titleText: string): Frame
    feature.optionCount += 1
    local section: Frame = (create("Frame", {
        Parent = feature.options,
        Name = "Section_" .. titleText:gsub("%W", ""),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = feature.optionCount,
        Size = UDim2.new(1, 0, 0, 22),
        ZIndex = feature.options.ZIndex + 1,
    }) :: any) :: Frame
    table.insert(feature.optionRows, section)

    local title: TextLabel = (makeTextLabel(
        section,
        string.upper(titleText),
        9
    ) :: any) :: TextLabel
    title.Name = "SectionTitle"
    title.FontFace = CONTROL_FONT
    title.Position = UDim2.fromOffset(4, 0)
    title.Size = UDim2.new(0, 130, 1, 0)
    title.TextColor3 = Theme.DefaultTextMuted
    title.TextTransparency = 0.22
    title.ZIndex = section.ZIndex + 1

    local rule: Frame = create("Frame", {
        Parent = section,
        Name = "SectionRule",
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.DefaultOutline,
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -4, 0.5, 0),
        Size = UDim2.new(1, -142, 0, 1),
        ZIndex = section.ZIndex + 1,
    }) :: Frame
    create("UIGradient", {
        Parent = rule,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0.3),
        }),
    })

    feature.updateExpandedSize()
    return section
end

local function setOptionVisible(
    feature: any,
    option: GuiObject,
    visible: boolean
): ()
    option.Visible = visible
    feature.updateExpandedSize()
end

local function addToggleOption(
    feature: any,
    labelText: string,
    defaultValue: boolean,
    callback: (boolean) -> (),
    hintText: string?
): TextButton
    local optionKey: string =
        feature.configKey .. "." .. labelText:gsub("%W", "")
    local enabled: boolean? = configData.states[optionKey]
    if enabled == nil then
        enabled = defaultValue == true
    end

    local option: Frame = createOptionRow(feature, labelText, hintText)
    local button: TextButton = create("TextButton", {
        Parent = option,
        Name = "OptionClickTarget",
        Active = true,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        ZIndex = option.ZIndex + 2,
    }) :: TextButton
    local switch: TextButton = createToggleSwitch(option, enabled :: boolean, nil)
    switch.Name = "OptionSwitch"
    -- The switch keeps its intrinsic size, so it is pinned to the right edge
    -- of the control band rather than stretched across it. Its right edge
    -- lands on exactly the same x as every other control type, which keeps
    -- toggle-only modules visually aligned with keybind and slider modules.
    switch.AnchorPoint = Vector2.new(1, 0.5)
    switch.Position = UDim2.new(
        1,
        -10,
        0,
        (tonumber(option:GetAttribute("ControlTop")) or 6)
            + (tonumber(option:GetAttribute("ControlHeight")) or 30) / 2
    )
    switch.ZIndex = option.ZIndex + 3
    for _, descendant: Instance in ipairs(switch:GetDescendants()) do
        if descendant:IsA("GuiObject") then
            descendant.ZIndex += option.ZIndex + 2
        end
    end
    local optionLabel: TextLabel? =
        option:FindFirstChild("OptionLabel") :: TextLabel?

    local function refreshOptionState(): ()
        setToggleSwitch(switch, enabled :: boolean, true)
        if optionLabel then
            optionLabel.TextColor3 = (enabled :: boolean)
                and Theme.DefaultText
                or Theme.DefaultTextMuted
        end
    end

    local function toggleOption(): ()
        enabled = not enabled
        refreshOptionState()
        configData.states[optionKey] = enabled
        callback(enabled :: boolean)
        queueConfigSave()
        notify(labelText .. ((enabled :: boolean) and " enabled" or " disabled"))
    end
    trackUiConnection(button.MouseButton1Click:Connect(toggleOption))
    trackUiConnection(switch.MouseButton1Click:Connect(toggleOption))

    refreshOptionState()
    callback(enabled :: boolean)
    return button
end
local function addActionOption(
    feature: any,
    labelText: string,
    callback: () -> (),
    hintText: string?
): TextButton
    local option = createOptionRow(feature, labelText, hintText)
    local button = makeButton(option, "RUN", 11)
    button.BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultButtonHover
        or Theme.AccentSoft
    -- The action pair subdivides the same control band every other row uses:
    -- RUN hugs the band's right edge and KEY fills the band's left half, so
    -- action rows share the exact same outer rectangle as toggles, sliders,
    -- cycle buttons and key slots.
    state.layoutOptionControl(option, button, 0.26)
    local function executeAction(): ()
        runActionButton(
            button,
            "RUN",
            callback,
            labelText .. " completado",
            "[Random Testing Menu] " .. labelText
        )
    end
    trackUiConnection(button.MouseButton1Click:Connect(executeAction))
    local shortcutButton: TextButton =
        (makeButton(option, "KEY", 9) :: any) :: TextButton
    shortcutButton.BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultButton
        or Theme.SurfaceRaised
    -- Sits immediately left of the RUN button inside the same band, positioned
    -- with the pair's combined scale rather than off RUN's AbsoluteSize, which
    -- is still zero on the frame the row is built. 0.24 width + 0.26 width
    -- with a 6px gap reproduces the 0.5-wide band of every other row type, so
    -- the pair never breaks the shared left/right edges.
    state.layoutOptionControl(option, shortcutButton, 0.24)
    shortcutButton.Position = UDim2.new(
        0.74,
        -16,
        shortcutButton.Position.Y.Scale,
        shortcutButton.Position.Y.Offset
    )
    applyKeySlotStyle(shortcutButton)
    shortcutButton.TextScaled = true
    create("UITextSizeConstraint", {
        Parent = shortcutButton,
        MaxTextSize = 11,
        MinTextSize = 7,
    })
    bindActionShortcut(
        shortcutButton,
        feature.configKey .. labelText,
        labelText,
        executeAction
    )
    return button :: TextButton
end

type ActiveSlider = {
    update: (number) -> (),
    finish: () -> (),
}

local activeSlider: ActiveSlider? = nil

trackUiConnection(UserInputService.InputChanged:Connect(function(
    input: InputObject
): ()
    if activeSlider
        and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
        activeSlider.update(input.Position.X)
    end
end))

trackUiConnection(UserInputService.InputEnded:Connect(function(
    input: InputObject
): ()
    if activeSlider
        and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
        local slider: ActiveSlider = activeSlider
        activeSlider = nil
        slider.finish()
    end
end))

local function isFiniteNumber(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function formatCompactNumber(value: number): string
    local magnitude: number = math.abs(value)
    if magnitude >= 1e9 or (magnitude > 0 and magnitude < 1e-4) then
        return string.format("%.3e", value)
    end
    return string.format("%.7g", value)
end

local function addNumberOption(
    feature: any,
    labelText: string,
    defaultValue: number,
    minimum: number,
    maximum: number,
    callback: (number) -> (),
    hintText: string?
): Frame
    local optionKey: string =
        feature.configKey .. "." .. labelText:gsub("%W", "")
    local storedValue: number? = tonumber(configData.values[optionKey])
    local value: number = isFiniteNumber(storedValue)
        and (storedValue :: number)
        or defaultValue
    local integerOnly: boolean = defaultValue % 1 == 0
        and minimum % 1 == 0
        and maximum % 1 == 0

    local option: Frame = createOptionRow(feature, labelText, hintText)
    local slider: TextButton = (create("TextButton", {
        Parent = option,
        Name = "Slider",
        Active = true,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
    }) :: any) :: TextButton
    state.layoutOptionControl(option, slider, 0.5)

    local track: Frame = (create("Frame", {
        Parent = slider,
        Name = "Track",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, -80, 0, state.layout.touch and 7 or 5),
        ZIndex = slider.ZIndex + 1,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = track,
        CornerRadius = UDim.new(1, 0),
    })

    local fill: Frame = (create("Frame", {
        Parent = track,
        Name = "Fill",
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1),
    }) :: any) :: Frame
    create("UICorner", {
        Parent = fill,
        CornerRadius = UDim.new(1, 0),
    })
    create("UIGradient", {
        Parent = fill,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.DefaultAccent),
            ColorSequenceKeypoint.new(0.52, Theme.AccentViolet),
            ColorSequenceKeypoint.new(1, Theme.AccentPink),
        }),
    })

    local knobSize: number = state.layout.touch and 18 or 14
    local knob: Frame = (create("Frame", {
        Parent = track,
        Name = "Knob",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(knobSize, knobSize),
    }) :: any) :: Frame
    create("UICorner", {
        Parent = knob,
        CornerRadius = UDim.new(1, 0),
    })

    local valueInput: TextBox = (makeTextBox(slider, "") :: any) :: TextBox
    valueInput.Name = "NumericValue"
    valueInput.AnchorPoint = Vector2.new(1, 0.5)
    valueInput.Position = UDim2.new(1, 0, 0.5, 0)
    valueInput.Size = UDim2.fromOffset(72, math.min(30, slider.Size.Y.Offset))
    valueInput.TextColor3 = Theme.Text
    valueInput.TextXAlignment = Enum.TextXAlignment.Center
    valueInput.TextTruncate = Enum.TextTruncate.AtEnd
    valueInput.ZIndex = slider.ZIndex + 1
    -- Spell out the accepted interval so a reader knows what the slider spans
    -- without having to drag it to both ends first.
    valueInput.PlaceholderText = formatCompactNumber(minimum)
        .. " – "
        .. formatCompactNumber(maximum)

    local editing: boolean = false
    local function setValue(
        nextValue: number,
        persist: boolean,
        fromSlider: boolean
    ): ()
        if not isFiniteNumber(nextValue) then
            return
        end
        value = nextValue
        if fromSlider then
            value = math.clamp(value, minimum, maximum)
            if integerOnly then
                value = math.round(value)
            end
        end
        local alpha: number = maximum == minimum
            and 0
            or math.clamp((value - minimum) / (maximum - minimum), 0, 1)
        fill.Size = UDim2.fromScale(alpha, 1)
        knob.Position = UDim2.fromScale(alpha, 0.5)
        if not editing then
            valueInput.Text = formatCompactNumber(value)
        end
        callback(value)
        if persist then
            configData.values[optionKey] = value
            queueConfigSave()
        end
    end

    local function updateFromScreenX(screenX: number): ()
        local width: number = math.max(track.AbsoluteSize.X, 1)
        local alpha: number = math.clamp(
            (screenX - track.AbsolutePosition.X) / width,
            0,
            1
        )
        setValue(minimum + (maximum - minimum) * alpha, true, true)
    end

    trackUiConnection(slider.InputBegan:Connect(function(
        input: InputObject
    ): ()
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if input.Position.X > track.AbsolutePosition.X + track.AbsoluteSize.X then
            return
        end
        updateFromScreenX(input.Position.X)
        activeSlider = {
            update = updateFromScreenX,
            finish = function(): ()
                notify(
                    labelText
                        .. ": "
                        .. formatCompactNumber(value)
                )
            end,
        }
    end))

    trackUiConnection(valueInput.Focused:Connect(function(): ()
        editing = true
        valueInput.Text = tostring(value)
        valueInput.CursorPosition = #valueInput.Text + 1
    end))

    trackUiConnection(valueInput.FocusLost:Connect(function(): ()
        local parsed: number? = tonumber(valueInput.Text)
        editing = false
        if not isFiniteNumber(parsed) then
            valueInput.Text = formatCompactNumber(value)
            notify(labelText .. ": invalid numeric value")
            return
        end
        setValue(parsed :: number, true, false)
        notify(labelText .. ": " .. formatCompactNumber(value))
    end))

    task.defer(function(): ()
        if option.Parent then
            setValue(value, false, false)
        end
    end)
    return option
end
-- Choice popup.
--
-- One list, reused by every multiple-choice row. Clicking the control opens
-- the options underneath it and the value is picked directly, instead of
-- clicking the same button four times to get back to the one you wanted.
state.closeChoiceList = function(): () end

local function openChoiceList(
    anchor: TextButton,
    values: {string},
    currentIndex: number,
    onPick: (number) -> ()
): ()
    state.closeChoiceList()

    local rowHeight: number = 22
    local visibleRows: number = math.min(#values, 6)
    local listHeight: number = visibleRows * rowHeight + 8
    local anchorPosition: Vector2 = anchor.AbsolutePosition
    local anchorSize: Vector2 = anchor.AbsoluteSize
    -- Open upwards when there is no room below: a list that runs off the
    -- bottom of the screen cannot be used at all.
    local viewport: Vector2 = ScreenGui.AbsoluteSize
    local below: boolean = anchorPosition.Y + anchorSize.Y + listHeight
        < viewport.Y - 8

    local list: Frame = create("Frame", {
        Parent = ScreenGui,
        Name = "ChoiceList",
        BackgroundColor3 = Theme.DefaultSurface,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(
            math.round(anchorPosition.X),
            math.round(below
                and (anchorPosition.Y + anchorSize.Y + 4)
                or (anchorPosition.Y - listHeight - 4))
        ),
        Size = UDim2.fromOffset(math.round(anchorSize.X), listHeight),
        ZIndex = 400,
    }) :: Frame
    create("UICorner", {Parent = list, CornerRadius = cornerRadius(UI_RADIUS.control)})
    create("UIStroke", {
        Parent = list,
        Color = Theme.DefaultOutline,
        Transparency = 0.4,
        Thickness = 1,
    })

    local scroller: ScrollingFrame = create("ScrollingFrame", {
        Parent = list,
        Name = "Items",
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Position = UDim2.fromOffset(4, 4),
        ScrollBarThickness = 2,
        ScrollBarImageTransparency = 0.6,
        Size = UDim2.new(1, -8, 1, -8),
        ZIndex = 401,
    }) :: ScrollingFrame
    create("UIListLayout", {
        Parent = scroller,
        Padding = UDim.new(0, 1),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local closed: boolean = false
    local outsideConnection: RBXScriptConnection? = nil
    local function close(): ()
        if closed then
            return
        end
        closed = true
        if outsideConnection then
            outsideConnection:Disconnect()
            outsideConnection = nil
        end
        list:Destroy()
        state.closeChoiceList = function(): () end
    end
    state.closeChoiceList = close

    for itemIndex: number, value: string in ipairs(values) do
        local item: TextButton = (create("TextButton", {
            Parent = scroller,
            Name = "Choice" .. tostring(itemIndex),
            AutoButtonColor = false,
            BackgroundColor3 = Theme.DefaultSurfaceHover,
            BackgroundTransparency = itemIndex == currentIndex and 0.35 or 1,
            BorderSizePixel = 0,
            FontFace = CONTROL_FONT,
            LayoutOrder = itemIndex,
            Size = UDim2.new(1, 0, 0, rowHeight - 1),
            Text = value,
            TextColor3 = itemIndex == currentIndex
                and Theme.DefaultText
                or Theme.DefaultTextMuted,
            TextSize = 11,
            ZIndex = 402,
        }) :: any) :: TextButton
        create("UICorner", {Parent = item, CornerRadius = cornerRadius(UI_RADIUS.chip)})
        create("UIPadding", {
            Parent = item,
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        })
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.MouseEnter:Connect(function(): ()
            if itemIndex ~= currentIndex then
                item.BackgroundTransparency = 0.72
            end
        end)
        item.MouseLeave:Connect(function(): ()
            item.BackgroundTransparency = itemIndex == currentIndex and 0.35 or 1
        end)
        item.MouseButton1Click:Connect(function(): ()
            close()
            onPick(itemIndex)
        end)
    end

    -- Any press that is not on the list dismisses it, which is what every
    -- other menu on the platform does.
    outsideConnection = UserInputService.InputBegan:Connect(function(
        input: InputObject
    ): ()
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        task.defer(function(): ()
            if closed then
                return
            end
            local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
            local origin: Vector2 = list.AbsolutePosition
            local size: Vector2 = list.AbsoluteSize
            local inside: boolean = pointer.X >= origin.X
                and pointer.X <= origin.X + size.X
                and pointer.Y >= origin.Y
                and pointer.Y <= origin.Y + size.Y
            if not inside then
                close()
            end
        end)
    end)
    trackUiConnection(outsideConnection :: RBXScriptConnection)
end

state.addMenuVisibilityListener(function(visible: boolean): ()
    if not visible then
        state.closeChoiceList()
    end
end)

local function addCycleOption(
    feature: any,
    labelText: string,
    values: {string},
    initialIndex: number?,
    callback: (string) -> (),
    hintText: string?
): TextButton
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local storedValue = configData.values[optionKey]
    local option = createOptionRow(feature, labelText, hintText)
    local index = initialIndex or 1
    if storedValue ~= nil then
        for valueIndex, value in ipairs(values) do
            if value == storedValue then
                index = valueIndex
                break
            end
        end
    end
    local button = makeButton(option, values[index], 11)
    state.layoutOptionControl(option, button, 0.5)
    button.TextXAlignment = Enum.TextXAlignment.Left
    create("UIPadding", {
        Parent = button,
        Name = "ChoicePadding",
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 20),
    })

    -- A caret, because this opens a list; the old counter ("2/4") only made
    -- sense while the control was a button you had to click four times.
    local caret: Frame = create("Frame", {
        Parent = button,
        Name = "Caret",
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(10, 6),
        ZIndex = button.ZIndex + 1,
    }) :: Frame
    for _, side: number in ipairs({-1, 1}) do
        local blade: Frame = create("Frame", {
            Parent = caret,
            Name = side < 0 and "Left" or "Right",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.DefaultTextMuted,
            BackgroundTransparency = 0.25,
            BorderSizePixel = 0,
            Position = UDim2.new(0.5, side * 2, 0.5, 0),
            Rotation = side * 38,
            Size = UDim2.fromOffset(7, 1),
            ZIndex = button.ZIndex + 2,
        }) :: Frame
        create("UICorner", {Parent = blade, CornerRadius = UDim.new(1, 0)})
    end

    local function refreshChoiceVisual(): ()
        button.Text = values[index]
    end
    refreshChoiceVisual()

    button.MouseButton1Click:Connect(function()
        openChoiceList(button, values, index, function(picked: number): ()
            index = picked
            refreshChoiceVisual()
            callback(values[index])
            configData.values[optionKey] = values[index]
            queueConfigSave()
        end)
    end)

    callback(values[index])
    return button :: TextButton
end

local function addKeyOption(
    feature: any,
    labelText: string,
    defaultKey: Enum.KeyCode,
    callback: (Enum.KeyCode) -> (),
    hintText: string?
): TextButton
    -- Flag used by the symmetry pass: modules that already expose an explicit
    -- key row are not given the automatic "Toggle key" row.
    feature.hasKeyOption = true
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local savedKey = nil
    local savedName = configData.values[optionKey]
    if type(savedName) == "string" and savedName ~= "" then
        pcall(function()
            savedKey = Enum.KeyCode[savedName]
        end)
    end
    local initialKey = savedKey or defaultKey
    local currentKey: Enum.KeyCode = initialKey
    local option = createOptionRow(feature, labelText, hintText)
    local button = makeButton(
        option,
        currentKey == Enum.KeyCode.Unknown and "" or currentKey.Name,
        11
    )
    state.layoutOptionControl(option, button, 0.5)
    applyKeySlotStyle(button)
    button:SetAttribute("CaptureIdleText", button.Text)

    button.MouseButton1Click:Connect(function()
        if state.isMobile then
            return
        end
        beginKeyCapture(button, function(keyCode: Enum.KeyCode): ()
            currentKey = keyCode == currentKey
                and Enum.KeyCode.Unknown
                or keyCode
            button.Text = currentKey == Enum.KeyCode.Unknown
                and ""
                or currentKey.Name
            button:SetAttribute("CaptureIdleText", button.Text)
            callback(currentKey)
            configData.values[optionKey] = currentKey.Name
            queueConfigSave()
        end)
    end)

    callback(currentKey)
    return button :: TextButton
end

local function addTextOption(
    feature: any,
    labelText: string,
    defaultText: string,
    callback: (string) -> (),
    persist: boolean?,
    hintText: string?
): TextBox
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local shouldPersist = persist ~= false
    local initialText = shouldPersist and configData.values[optionKey] or nil
    if initialText == nil then
        initialText = defaultText or ""
    end
    local option = createOptionRow(feature, labelText, hintText)
    local box = makeTextBox(option, initialText)
    box.PlaceholderText = "Enter value"
    -- Centred: the placeholder and the value sit in the middle of the field
    -- instead of hugging its left edge.
    box.TextXAlignment = Enum.TextXAlignment.Center
    state.layoutOptionControl(option, box, 0.5)

    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            callback(box.Text)
        end
    end)

    box:GetPropertyChangedSignal("Text"):Connect(function()
        callback(box.Text)
        if shouldPersist then
            configData.values[optionKey] = box.Text
            queueConfigSave()
        end
    end)

    if not shouldPersist and configData.values[optionKey] ~= nil then
        configData.values[optionKey] = nil
        queueConfigSave()
    end
    callback(initialText)
    return box :: TextBox
end

local colorPicker = {}

colorPicker.open = function(initialColor, onApply)
    if not colorPicker.panel then
        local panel = create("Frame", {
            Parent = PopupLayer,
            Name = "ColorPicker",
            Active = true,
            BackgroundColor3 = Theme.DefaultSurface,
            BorderColor3 = Theme.DefaultOutline,
            BorderSizePixel = 1,
            Position = UDim2.new(0.5, -170, 0.5, -135),
            Size = UDim2.fromOffset(340, 270),
            Visible = false,
            ZIndex = 80,
        })
        create("UICorner", {
            Parent = panel,
            CornerRadius = cornerRadius(8),
        })

        local title = makeTextLabel(panel, "COLOR", 14)
        title.FontFace = CONTROL_FONT
        title.Position = UDim2.fromOffset(15, 8)
        title.Size = UDim2.new(1, -60, 0, 28)
        title.ZIndex = 81

        local close = makeButton(panel, "X", 12)
        close.AutoButtonColor = false
        close.Position = UDim2.new(1, -42, 0, 8)
        close.Size = UDim2.fromOffset(28, 28)
        close.ZIndex = 82

        local sv = makeButton(panel, "", 10)
        sv.AutoButtonColor = false
        sv:SetAttribute("NoHover", true)
        sv.Position = UDim2.fromOffset(15, 44)
        sv.Size = UDim2.fromOffset(205, 165)
        sv.ZIndex = 81
        local saturationGradient = create("UIGradient", {
            Parent = sv,
            Color = ColorSequence.new(
                Color3.fromRGB(255, 255, 255),
                Color3.fromRGB(255, 0, 0)
            ),
        })
        local shade = create("Frame", {
            Parent = sv,
            BackgroundColor3 = Theme.DefaultBackground,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 82,
        })
        create("UIGradient", {
            Parent = shade,
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            }),
        })
        local svCursor = create("Frame", {
            Parent = sv,
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderColor3 = Theme.DefaultSurface,
            BorderSizePixel = 2,
            Size = UDim2.fromOffset(12, 12),
            ZIndex = 83,
        })
        create("UICorner", {
            Parent = svCursor,
            CornerRadius = UDim.new(1, 0),
        })

        local hue = makeButton(panel, "", 10)
        hue.AutoButtonColor = false
        hue:SetAttribute("NoHover", true)
        hue.Position = UDim2.fromOffset(232, 44)
        hue.Size = UDim2.fromOffset(22, 165)
        hue.ZIndex = 81
        create("UIGradient", {
            Parent = hue,
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
                ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
                ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
                ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
                ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
                ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
            }),
        })
        local hueCursor = create("Frame", {
            Parent = hue,
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.fromRGB(245, 245, 245),
            BorderColor3 = Theme.DefaultSurface,
            BorderSizePixel = 1,
            Position = UDim2.new(0.5, 0, 0, 0),
            Size = UDim2.new(1, 6, 0, 5),
            ZIndex = 83,
        })

        local preview = create("Frame", {
            Parent = panel,
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderColor3 = Color3.fromRGB(85, 85, 85),
            BorderSizePixel = 1,
            Position = UDim2.fromOffset(273, 45),
            Size = UDim2.fromOffset(48, 48),
            ZIndex = 81,
        })
        create("UICorner", {
            Parent = preview,
            CornerRadius = UDim.new(1, 0),
        })

        local hex = makeTextBox(panel, "#ffffff")
        hex.Position = UDim2.fromOffset(268, 105)
        hex.Size = UDim2.fromOffset(58, 30)
        hex.TextXAlignment = Enum.TextXAlignment.Center
        hex.ZIndex = 81

        local apply = makeButton(panel, "APPLY", 11)
        apply.AutoButtonColor = false
        apply.Position = UDim2.fromOffset(268, 148)
        apply.Size = UDim2.fromOffset(58, 34)
        apply.ZIndex = 81

        local hint = makeTextLabel(
            panel,
            "Saturation / brightness        Hue",
            10
        )
        hint.TextColor3 = Color3.fromRGB(145, 145, 145)
        hint.Position = UDim2.fromOffset(15, 216)
        hint.Size = UDim2.new(1, -30, 0, 22)
        hint.ZIndex = 81

        colorPicker.panel = panel
        colorPicker.sv = sv
        colorPicker.saturationGradient = saturationGradient
        colorPicker.svCursor = svCursor
        colorPicker.hue = hue
        colorPicker.hueCursor = hueCursor
        colorPicker.preview = preview
        colorPicker.hex = hex
        colorPicker.apply = apply
        colorPicker.drag = nil

        local function updateColor()
            local color = Color3.fromHSV(
                colorPicker.h,
                colorPicker.s,
                colorPicker.v
            )
            colorPicker.current = color
            colorPicker.preview.BackgroundColor3 = color
            colorPicker.saturationGradient.Color = ColorSequence.new(
                Color3.fromRGB(255, 255, 255),
                Color3.fromHSV(colorPicker.h, 1, 1)
            )
            colorPicker.svCursor.Position = UDim2.fromScale(
                colorPicker.s,
                1 - colorPicker.v
            )
            colorPicker.hueCursor.Position = UDim2.new(
                0.5,
                0,
                colorPicker.h,
                0
            )
            local rgb = colorToConfig(color)
            colorPicker.hex.Text = string.format(
                "#%02x%02x%02x",
                rgb[1],
                rgb[2],
                rgb[3]
            )
        end
        colorPicker.update = updateColor

        local function updateFromPointer(kind, position)
            local object = kind == "hue" and hue or sv
            local relative = Vector2.new(position.X, position.Y)
                - object.AbsolutePosition
            if kind == "hue" then
                colorPicker.h = math.clamp(
                    relative.Y / object.AbsoluteSize.Y,
                    0,
                    1
                )
            else
                colorPicker.s = math.clamp(
                    relative.X / object.AbsoluteSize.X,
                    0,
                    1
                )
                colorPicker.v = 1 - math.clamp(
                    relative.Y / object.AbsoluteSize.Y,
                    0,
                    1
                )
            end
            updateColor()
        end

        sv.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                colorPicker.drag = "sv"
                updateFromPointer("sv", input.Position)
            end
        end)
        hue.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                colorPicker.drag = "hue"
                updateFromPointer("hue", input.Position)
            end
        end)
        colorPicker.inputChanged = UserInputService.InputChanged:Connect(function(input)
            if colorPicker.panel.Visible
                and colorPicker.drag
                and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                updateFromPointer(colorPicker.drag, input.Position)
            end
        end)
        colorPicker.inputEnded = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                colorPicker.drag = nil
            end
        end)

        hex.FocusLost:Connect(function()
            local value = string.match(hex.Text, "^#?(%x%x%x%x%x%x)$")
            if value then
                local r = tonumber(string.sub(value, 1, 2), 16)
                local g = tonumber(string.sub(value, 3, 4), 16)
                local b = tonumber(string.sub(value, 5, 6), 16)
                colorPicker.h, colorPicker.s, colorPicker.v =
                    Color3.fromRGB(r, g, b):ToHSV()
                updateColor()
            end
        end)
        close.MouseButton1Click:Connect(function()
            panel.Visible = false
        end)
        apply.MouseButton1Click:Connect(function()
            if colorPicker.callback then
                colorPicker.callback(colorPicker.current)
            end
            panel.Visible = false
        end)
    end

    colorPicker.h, colorPicker.s, colorPicker.v = initialColor:ToHSV()
    colorPicker.callback = onApply
    colorPicker.panel.Visible = true
    colorPicker.update()
end

local function addColorOption(feature, labelText, defaultColor, callback, hintText)
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local color = colorFromConfig(configData.values[optionKey], defaultColor)
    local option = createOptionRow(feature, labelText, hintText)
    local swatch = makeButton(option, "", 10)
    swatch.AutoButtonColor = false
    swatch:SetAttribute("NoHover", true)
    swatch.AnchorPoint = Vector2.new(1, 0)
    swatch.Position = UDim2.new(
        1,
        -10,
        0,
        (tonumber(option:GetAttribute("ControlTop")) or 6) + 1
    )
    swatch.Size = UDim2.fromOffset(28, 28)
    swatch.ZIndex = option.ZIndex + 2
    swatch.BackgroundColor3 = color
    create("UICorner", {
        Parent = swatch,
        CornerRadius = UDim.new(1, 0),
    })

    swatch.MouseButton1Click:Connect(function()
        colorPicker.open(color, function(newColor)
            color = newColor
            swatch.BackgroundColor3 = color
            configData.values[optionKey] = colorToConfig(color)
            callback(color)
            queueConfigSave()
        end)
    end)

    callback(color)
    return swatch
end

local function addInformationOption(feature: any, text: string): ()
    local current: string = feature.tooltipText or feature.description or ""
    local combined: string = current ~= "" and (current .. "\n" .. text) or text
    feature.tooltipText = combined
    feature.description = combined
end

type OptionDefinition = {
    kind: string,
    label: string,
    default: any?,
    minimum: number?,
    maximum: number?,
    values: {string}?,
    callback: any,
    persist: boolean?,
}

type FeatureDefinition = {
    name: string,
    description: string,
    order: number,
    onToggle: any,
    configuration: any?,
    options: {OptionDefinition}?,
}

local function addConfiguredOptions(
    feature: any,
    definitions: {OptionDefinition}
): ()
    for _, definition: OptionDefinition in ipairs(definitions) do
        if definition.kind == "toggle" then
            addToggleOption(
                feature,
                definition.label,
                definition.default == true,
                definition.callback
            )
        elseif definition.kind == "slider" then
            addNumberOption(
                feature,
                definition.label,
                tonumber(definition.default) or 0,
                definition.minimum or 0,
                definition.maximum or 100,
                definition.callback
            )
        elseif definition.kind == "color" then
            addColorOption(
                feature,
                definition.label,
                definition.default :: Color3,
                definition.callback
            )
        elseif definition.kind == "cycle" then
            addCycleOption(
                feature,
                definition.label,
                definition.values or {},
                tonumber(definition.default) or 1,
                definition.callback
            )
        elseif definition.kind == "keybind" then
            addKeyOption(
                feature,
                definition.label,
                definition.default :: Enum.KeyCode,
                definition.callback
            )
        elseif definition.kind == "text" then
            addTextOption(
                feature,
                definition.label,
                tostring(definition.default or ""),
                definition.callback,
                definition.persist
            )
        elseif definition.kind == "action" then
            addActionOption(feature, definition.label, definition.callback)
        elseif definition.kind == "info" then
            addInformationOption(feature, definition.label)
        end
    end
end

local function createFeatureFromDefinition(
    definition: FeatureDefinition
): any
    local feature: any = createUniversalFeature(
        definition.name,
        definition.description,
        definition.order,
        definition.onToggle,
        definition.configuration
    )
    if definition.options then
        addConfiguredOptions(feature, definition.options)
    end
    return feature
end

local function createFeaturesFromDefinitions(
    definitions: {FeatureDefinition}
): {any}
    local createdFeatures: {any} = {}
    for _, definition: FeatureDefinition in ipairs(definitions) do
        table.insert(
            createdFeatures,
            createFeatureFromDefinition(definition)
        )
    end
    return createdFeatures
end

state.components = {
    createFeature = createFeatureFromDefinition,
    createFeatures = createFeaturesFromDefinitions,
    addOptions = addConfiguredOptions,
}
state.featureTooltip = create("TextLabel", {
    Parent = PopupLayer,
    Name = "FeatureTooltip",
    Active = false,
    AutomaticSize = Enum.AutomaticSize.None,
    BackgroundColor3 = Theme.DefaultSurface,
    BackgroundTransparency = 0.04,
    BorderColor3 = Color3.fromRGB(58, 58, 58),
    BorderSizePixel = 1,
    FontFace = THIN_FONT,
    Size = UDim2.fromOffset(320, 30),
    Text = "",
    TextColor3 = Color3.fromRGB(205, 205, 205),
    TextSize = 11,
    TextWrapped = true,
    Visible = false,
    ZIndex = 250,
}) :: TextLabel

create("UICorner", {
    Parent = state.featureTooltip,
    CornerRadius = cornerRadius(4),
})

create("UIPadding", {
    Parent = state.featureTooltip,
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
    PaddingTop = UDim.new(0, 5),
})

state.tooltipToken = 0

local function showFeatureTooltip(row: Frame, text: string, pointer: Vector2?): ()
    state.tooltipToken = state.tooltipToken + 1
    state.featureTooltip.Text = text

    local width: number = math.clamp(#text * 5.5 + 24, 210, 520)
    local lineCount: number = math.max(1, math.ceil((#text * 5.5) / (width - 20)))
    local height: number = math.max(30, lineCount * 15 + 12)
    state.featureTooltip.Size = UDim2.fromOffset(width, height)

    local camera: Camera? = workspace.CurrentCamera
    local viewport: Vector2 = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local anchor: Vector2 = pointer
        or Vector2.new(
            row.AbsolutePosition.X + 16,
            row.AbsolutePosition.Y + row.AbsoluteSize.Y * 0.5
        )
    local x: number = math.clamp(anchor.X + 12, 8, math.max(8, viewport.X - width - 8))
    local y: number = math.clamp(
        anchor.Y - height - 8,
        8,
        math.max(8, viewport.Y - height - 8)
    )

    state.featureTooltip.Position = UDim2.fromOffset(x, y)
    state.featureTooltip.Visible = true
end

local function hideFeatureTooltip(): ()
    state.tooltipToken = state.tooltipToken + 1
    state.featureTooltip.Visible = false
end

local COMPACT_FEATURE_CARDS: boolean = true
local function addFeatureTooltip(feature: any, text: string): ()
    if COMPACT_FEATURE_CARDS then
        return
    end
    feature.tooltipText = text
    if feature.tooltipBound then
        return
    end
    feature.tooltipBound = true

    local row: Frame = feature.row :: Frame
    local heldInput: InputObject? = nil
    local heldStart: Vector2? = nil

    table.insert(state.tooltipConnections, row.MouseLeave:Connect(function(): ()
        heldInput = nil
        heldStart = nil
        hideFeatureTooltip()
    end))

    table.insert(state.tooltipConnections, row.InputBegan:Connect(function(input: InputObject): ()
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        heldInput = input
        heldStart = Vector2.new(input.Position.X, input.Position.Y)
        state.tooltipToken = state.tooltipToken + 1
        local pressToken: number = state.tooltipToken
        task.delay(0.42, function(): ()
            if heldInput == input and state.tooltipToken == pressToken then
                local pointer: Vector2 = input.UserInputType == Enum.UserInputType.Touch
                    and Vector2.new(input.Position.X, input.Position.Y)
                    or UserInputService:GetMouseLocation()
                showFeatureTooltip(row, feature.tooltipText, pointer)
            end
        end)
    end))

    table.insert(state.tooltipConnections, row.InputChanged:Connect(function(input: InputObject): ()
        if heldInput == input and heldStart then
            local current: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
            if (current - heldStart).Magnitude > 12 then
                heldInput = nil
                heldStart = nil
                hideFeatureTooltip()
            end
        end
    end))

    table.insert(state.tooltipConnections, row.InputEnded:Connect(function(input: InputObject): ()
        if heldInput == input then
            heldInput = nil
            heldStart = nil
            hideFeatureTooltip()
        end
    end))
end

state.bindFeatureTooltip = addFeatureTooltip

type FlySettings = {
    method: string,
    floatMethod: string,
    speed: number,
    verticalSpeed: number,
    response: number,
    burstInterval: number,
    wallCheck: boolean,
    platformStand: boolean,
    faceCamera: boolean,
    upKey: Enum.KeyCode,
    downKey: Enum.KeyCode,
}

-- Everything the flight engines mutate between frames lives here rather than
-- as separate upvalues: the engines swap at runtime and each one has to be
-- able to tear down whatever the previous one left behind.
type FlyRuntime = {
    yLevel: number?,
    burstAt: number,
    platform: BasePart?,
    walkSpeed: number?,
}

local findPlayerByText: (string) -> Player? = function(_text: string): Player?
    return nil
end
local performFling: (Player) -> () = function(_target: Player): () end

do
local flySettings: FlySettings = {
    method = "Velocity",
    floatMethod = "Velocity",
    speed = 70,
    verticalSpeed = 56,
    response = 1,
    burstInterval = 0.2,
    wallCheck = true,
    platformStand = true,
    faceCamera = true,
    upKey = Enum.KeyCode.Space,
    downKey = Enum.KeyCode.LeftControl,
}
-- Kept on `state` rather than as another bootstrap local: the function that
-- builds the menu is already at Luau's 200-register ceiling.
state.flyRuntime = {
    yLevel = nil,
    burstAt = 0,
    platform = nil,
    walkSpeed = nil,
} :: FlyRuntime
local flySmoothedVelocity: Vector3 = Vector3.zero
state.platformStandController = {
    owners = {},
    baselines = setmetatable({}, {__mode = "k"}),
    sequence = 0,
}
state.platformStandController.set = function(ownerId: string, value: boolean?): ()
    local controller: any = state.platformStandController
    if value == nil then
        controller.owners[ownerId] = nil
        if next(controller.owners) == nil then
            for humanoid: Humanoid, baseline: boolean in pairs(controller.baselines) do
                if humanoid.Parent then
                    humanoid.PlatformStand = baseline
                end
            end
            controller.baselines = setmetatable({}, {__mode = "k"})
        end
        return
    end
    local owner: any = controller.owners[ownerId]
    if not owner then
        controller.sequence += 1
        owner = {sequence = controller.sequence, value = value}
        controller.owners[ownerId] = owner
    else
        owner.value = value
    end
end
state.platformStandController.apply = function(humanoid: Humanoid): ()
    local controller: any = state.platformStandController
    if controller.baselines[humanoid] == nil then
        controller.baselines[humanoid] = humanoid.PlatformStand
    end
    local selected: any = nil
    for _, owner: any in pairs(controller.owners) do
        if not selected or owner.sequence > selected.sequence then
            selected = owner
        end
    end
    if selected then
        humanoid.PlatformStand = selected.value
    end
end
local flyObjects: {[Instance]: boolean} =
    setmetatable({}, {__mode = "k"}) :: any
local flyTouchVertical: number = 0

local function removeFlyObjects(): ()
    state.platformStandController.set("Fly", nil)

    for object: Instance in pairs(flyObjects) do
        if object.Parent then
            object:Destroy()
        end
    end
    flyObjects = setmetatable({}, {__mode = "k"}) :: any
end

local function ensureFlyConstraints(root: BasePart): (LinearVelocity, AlignOrientation)
    local attachment: Attachment? = root:FindFirstChild("RTM_FlyAttachment") :: Attachment?
    if not attachment then
        local newAttachment: Attachment = Instance.new("Attachment")
        newAttachment.Name = "RTM_FlyAttachment"
        newAttachment.Parent = root
        attachment = newAttachment
    end
    local resolvedAttachment: Attachment = attachment :: Attachment
    flyObjects[resolvedAttachment] = true

    local velocity: LinearVelocity? = root:FindFirstChild("RTM_FlyVelocity") :: LinearVelocity?
    if not velocity then
        local newVelocity: LinearVelocity = Instance.new("LinearVelocity")
        newVelocity.Name = "RTM_FlyVelocity"
        newVelocity.Attachment0 = resolvedAttachment
        newVelocity.MaxForce = math.huge
        newVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
        newVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        newVelocity.Parent = root
        velocity = newVelocity
    end
    flyObjects[velocity :: LinearVelocity] = true

    local orientation: AlignOrientation? =
        root:FindFirstChild("RTM_FlyOrientation") :: AlignOrientation?
    if not orientation then
        local newOrientation: AlignOrientation = Instance.new("AlignOrientation")
        newOrientation.Name = "RTM_FlyOrientation"
        newOrientation.Attachment0 = resolvedAttachment
        newOrientation.MaxTorque = math.huge
        newOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
        newOrientation.Responsiveness = 28
        newOrientation.RigidityEnabled = false
        newOrientation.Parent = root
        orientation = newOrientation
    end
    flyObjects[orientation :: AlignOrientation] = true

    return velocity :: LinearVelocity, orientation :: AlignOrientation
end

local function getFlyDirection(camera: Camera): (Vector3, number, Vector3)
    local cameraForward: Vector3 = Vector3.new(
        camera.CFrame.LookVector.X,
        0,
        camera.CFrame.LookVector.Z
    )
    local cameraRight: Vector3 = Vector3.new(
        camera.CFrame.RightVector.X,
        0,
        camera.CFrame.RightVector.Z
    )
    cameraForward = cameraForward.Magnitude > 0.001
        and cameraForward.Unit
        or Vector3.new(0, 0, -1)
    cameraRight = cameraRight.Magnitude > 0.001
        and cameraRight.Unit
        or Vector3.new(1, 0, 0)

    -- Steering comes from the shared input helper, which reads Roblox's own
    -- control module: keyboard, thumbstick or gamepad, and it keeps answering
    -- while PlatformStand is on — the exact case where `MoveDirection` goes
    -- quiet and flying on a phone left the character frozen in place.
    local forwardScalar: number, rightScalar: number = state.getMoveInput()
    local horizontal: Vector3 = cameraForward * forwardScalar
        + cameraRight * rightScalar
    if horizontal.Magnitude > 1 then
        horizontal = horizontal.Unit
    end

    local vertical: number = 0
    if flyTouchVertical > 0
        or (UserInputService.KeyboardEnabled
            and UserInputService:IsKeyDown(flySettings.upKey)) then
        vertical = vertical + 1
    end
    if flyTouchVertical < 0
        or (UserInputService.KeyboardEnabled
            and UserInputService:IsKeyDown(flySettings.downKey)) then
        vertical = vertical - 1
    end
    -- On touch the jump button doubles as "up" so flying needs no placed
    -- button at all to get off the ground.
    if vertical == 0 and not UserInputService.KeyboardEnabled and state.isJumpHeld() then
        vertical = 1
    end

    return horizontal, vertical, cameraForward
end

-- Flight engines.
--
-- Flying is two separate problems — what pushes you sideways and what keeps
-- you off the ground — and games break them in different ways, so they are
-- two independent engines instead of one preset that only ever changed a
-- smoothing constant (which is why "Balanced", "Direct" and "Precise" all
-- used to fly identically).
--
-- Horizontal:
--   Velocity    AssemblyLinearVelocity is overwritten every frame. Smooth and
--               responsive, and the first thing a velocity clamp notices.
--   Constraint  a LinearVelocity constraint drives the character instead, so
--               games that reset AssemblyLinearVelocity each step cannot undo
--               it. It owns the vertical axis too, so the float engine idles.
--   Impulse     the same target reached with ApplyImpulse: the body keeps its
--               own physics, collides properly and pushes what it touches.
--   CFrame      the root is displaced directly and velocity is left at zero,
--               so speed caps, knockback and ragdolls have nothing to grab.
--   Blink       CFrame movement saved up and spent in one hop per interval,
--               which looks like teleporting rather than gliding.
--   Pulse       velocity alternating between a burst and a coast, so the
--               average speed stays close to normal while the peaks are fast.
--   WalkSpeed   raises Humanoid.WalkSpeed and nothing else: keeps animations
--               and the game's own movement rules, trivially detectable.
--
-- Vertical:
--   Velocity    the Y component is written directly, which also cancels
--               gravity while you hold nothing.
--   Impulse     the same target through ApplyImpulse.
--   Hover       an altitude is held with CFrame writes: no drift, no physics,
--               and gravity never applies.
--   Jump        holds an altitude by asking the humanoid to jump whenever it
--               falls below it, so the movement is the game's own jump.
--   Bounce      velocity with an oscillation on top, which reads from outside
--               as an ordinary player hopping around.
--   Floor       an invisible anchored part is kept under your feet, so you
--               are genuinely standing on something the entire flight.
-- The two engine appliers live in their own block so their registers are
-- released back to the bootstrap function, which sits at Luau's 200-local
-- ceiling.
local toggleFly: (boolean) -> ()
do
local function applyFlyHorizontal(
    root: BasePart,
    humanoid: Humanoid,
    moveDirection: Vector3,
    deltaTime: number
): ()
    local method: string = flySettings.method
    local currentVelocity: Vector3 = root.AssemblyLinearVelocity
    local target: Vector3 = moveDirection * flySettings.speed

    if method == "WalkSpeed" then
        if not state.flyRuntime.walkSpeed then
            state.flyRuntime.walkSpeed = humanoid.WalkSpeed
        end
        humanoid.WalkSpeed = flySettings.speed
        return
    end

    if method == "Pulse" then
        -- A burst followed by a coast: the same distance covered as a steady
        -- run at the slider value, but never a constant unnatural speed.
        local period: number = math.max(flySettings.burstInterval, 0.05) * 2
        local burst: boolean = (os.clock() % period) < (period * 0.5)
        target = target * (burst and 1.8 or 0.2)
    end

    if method == "CFrame" or method == "Blink" then
        local step: Vector3 = moveDirection * flySettings.speed * deltaTime
        if method == "Blink" then
            local interval: number = math.max(flySettings.burstInterval, 0.05)
            if os.clock() < state.flyRuntime.burstAt then
                step = Vector3.zero
            else
                state.flyRuntime.burstAt = os.clock() + interval
                step = moveDirection * flySettings.speed * interval
            end
        end
        if step.Magnitude > 0.001 and flySettings.wallCheck then
            local raycastParams: RaycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
            local wallHit: RaycastResult? = workspace:Raycast(
                root.Position,
                step + step.Unit * 2,
                raycastParams
            )
            if wallHit then
                step = Vector3.zero
            end
        end
        if step.Magnitude > 0.001 then
            root.CFrame = root.CFrame + step
        end
        -- Position-based flight has to keep its own momentum at zero, or the
        -- leftover velocity carries the character past wherever it stopped.
        root.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
        return
    end

    if method == "Impulse" then
        local difference: Vector3 = (target - currentVelocity)
            * Vector3.new(1, 0, 1)
        -- An impulse every frame fights the solver; only correct once the
        -- body has actually drifted away from the target.
        local threshold: number = moveDirection.Magnitude < 0.01 and 10 or 2
        if difference.Magnitude > threshold then
            root:ApplyImpulse(difference * root.AssemblyMass)
        end
        return
    end

    -- Velocity and Constraint both track the target through the response
    -- multiplier, which is the only setting that can make flight feel heavy.
    local alpha: number = 1 - math.exp(-12 * flySettings.response * deltaTime)
    flySmoothedVelocity = flySmoothedVelocity:Lerp(target, alpha)
    if method == "Constraint" then
        return
    end
    root.AssemblyLinearVelocity = Vector3.new(
        flySmoothedVelocity.X,
        currentVelocity.Y,
        flySmoothedVelocity.Z
    )
end

local function applyFlyVertical(
    root: BasePart,
    humanoid: Humanoid,
    vertical: number,
    deltaTime: number
): ()
    local method: string = flySettings.floatMethod
    local currentVelocity: Vector3 = root.AssemblyLinearVelocity
    local targetY: number = vertical * flySettings.verticalSpeed

    if method == "Floor" then
        local platform: BasePart? = state.flyRuntime.platform
        if not platform or not platform.Parent then
            local newPlatform: BasePart = Instance.new("Part")
            newPlatform.Name = "RTM_FlyPlatform"
            newPlatform.Anchored = true
            newPlatform.CanQuery = false
            newPlatform.CanTouch = false
            newPlatform.Size = Vector3.new(8, 1, 8)
            newPlatform.Transparency = 1
            -- Parented to the camera: it exists for the local physics
            -- simulation only and never shows up as a part in the world.
            newPlatform.Parent = workspace.CurrentCamera
            state.flyRuntime.platform = newPlatform
            platform = newPlatform
        end
        local resolved: BasePart = platform :: BasePart
        -- Descending means getting the floor out of the way for a moment.
        resolved.CFrame = vertical < 0
            and CFrame.new(0, -4096, 0)
            or CFrame.new(root.Position - Vector3.new(0, humanoid.HipHeight + 1.5, 0))
        if vertical > 0 then
            root.AssemblyLinearVelocity = Vector3.new(
                currentVelocity.X,
                targetY,
                currentVelocity.Z
            )
        end
        return
    end

    if method == "Hover" or method == "Jump" then
        local level: number = state.flyRuntime.yLevel or root.Position.Y
        level = level + targetY * deltaTime
        if flySettings.wallCheck then
            local offset: number = level - root.Position.Y
            if math.abs(offset) > 0.001 then
                local raycastParams: RaycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                local ceilingHit: RaycastResult? = workspace:Raycast(
                    root.Position,
                    Vector3.new(0, offset, 0),
                    raycastParams
                )
                if ceilingHit then
                    level = ceilingHit.Position.Y
                        - math.sign(offset) * (humanoid.HipHeight + 0.5)
                end
            end
        end
        state.flyRuntime.yLevel = level
        if method == "Hover" then
            root.AssemblyLinearVelocity = Vector3.new(
                currentVelocity.X,
                0,
                currentVelocity.Z
            )
            root.CFrame = root.CFrame + Vector3.new(0, level - root.Position.Y, 0)
        elseif root.Position.Y < level - 0.5 then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        return
    end

    if method == "Bounce" then
        local period: number = math.max(flySettings.burstInterval, 0.05) * 4
        local rising: boolean = (os.clock() % period) < (period * 0.5)
        targetY = targetY
            + (rising and 1 or -1) * flySettings.verticalSpeed * 0.45
    end

    if method == "Impulse" then
        local difference: number = targetY - currentVelocity.Y
        if math.abs(difference) > 2 then
            root:ApplyImpulse(Vector3.new(0, difference, 0) * root.AssemblyMass)
        end
        return
    end

    root.AssemblyLinearVelocity = Vector3.new(
        currentVelocity.X,
        targetY,
        currentVelocity.Z
    )
end

function toggleFly(enabled: boolean): ()
    disconnectFeatureConnection("Fly")
    removeFlyObjects()
    flySmoothedVelocity = Vector3.zero
    flyTouchVertical = 0
    state.flyRuntime.yLevel = nil
    state.flyRuntime.burstAt = 0
    if state.flyRuntime.platform then
        (state.flyRuntime.platform :: BasePart):Destroy()
        state.flyRuntime.platform = nil
    end

    local _, restoreHumanoid, restoreRoot = getCharacterParts()
    if restoreHumanoid and state.flyRuntime.walkSpeed then
        restoreHumanoid.WalkSpeed = state.flyRuntime.walkSpeed :: number
    end
    state.flyRuntime.walkSpeed = nil

    if not enabled then
        if restoreRoot then
            restoreRoot.AssemblyLinearVelocity = Vector3.zero
        end
        if restoreHumanoid then
            state.platformStandController.set("Fly", false)
            state.platformStandController.apply(restoreHumanoid)
        end
        return
    end

    featureConnections.Fly = TaskManager:Connect(function(deltaTime: number): ()
        local _, humanoid, root = getCharacterParts()
        local camera: Camera? = workspace.CurrentCamera
        if not humanoid or not root or not camera then
            -- A respawn invalidates the held altitude; picking it back up
            -- would teleport the fresh character to the old one's height.
            state.flyRuntime.yLevel = nil
            return
        end

        local method: string = flySettings.method
        local floatMethod: string = flySettings.floatMethod
        -- WalkSpeed steering and the two engines that stand on something need
        -- a humanoid that is still allowed to walk, so PlatformStand is only
        -- honoured where it does not disable the engine that is running.
        local canRagdoll: boolean = method ~= "WalkSpeed"
            and floatMethod ~= "Floor"
            and floatMethod ~= "Jump"
        state.platformStandController.set(
            "Fly",
            canRagdoll and (flySettings.platformStand or method == "CFrame")
        )
        state.platformStandController.apply(humanoid)

        local moveDirection, vertical, cameraForward = getFlyDirection(camera)
        if flySettings.wallCheck and moveDirection.Magnitude > 0.001 then
            local raycastParams: RaycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
            local wallHit: RaycastResult? = workspace:Raycast(
                root.Position,
                moveDirection.Unit * 2.75,
                raycastParams
            )
            if wallHit then
                moveDirection = Vector3.zero
            end
        end

        if method == "Constraint" then
            local velocity, orientation = ensureFlyConstraints(root)
            applyFlyHorizontal(root, humanoid, moveDirection, deltaTime)
            velocity.Enabled = true
            velocity.VectorVelocity = Vector3.new(
                flySmoothedVelocity.X,
                vertical * flySettings.verticalSpeed,
                flySmoothedVelocity.Z
            )
            orientation.Enabled = flySettings.faceCamera
            orientation.CFrame = CFrame.lookAt(Vector3.zero, cameraForward)
            return
        end

        -- Constraints left behind by a mode switch keep driving the character
        -- against whatever engine is running now.
        removeFlyObjects()
        applyFlyHorizontal(root, humanoid, moveDirection, deltaTime)
        applyFlyVertical(root, humanoid, vertical, deltaTime)

        if floatMethod ~= "Floor" and state.flyRuntime.platform then
            (state.flyRuntime.platform :: BasePart):Destroy()
            state.flyRuntime.platform = nil
        end
        if floatMethod ~= "Hover" and floatMethod ~= "Jump" then
            state.flyRuntime.yLevel = nil
        end

        if flySettings.faceCamera and cameraForward.Magnitude > 0.001 then
            root.CFrame = CFrame.lookAt(root.Position, root.Position + cameraForward)
        end
    end)
end
end

-- Hitbox engine rewrite.
--
-- The old implementation had one fixed behaviour (scale visible parts, head
-- pinned to 8 studs, everything forced transparent, collision and mass always
-- stripped) and re-scanned every character on a hard-coded 0.1 s timer. The
-- rewrite makes the whole pipeline configurable while keeping a single,
-- cheap, idempotent sweep:
--
--   * Mode: "Visible" scales the visible body (the classic expanded look),
--     "Root" scales only the invisible HumanoidRootPart (the classic
--     phantom hitbox) and "Hybrid" does both.
--   * Original states are recorded once per part and restored exactly when
--     the feature is disabled or when the mode stops targeting that part,
--     so switching Visible → Root never leaves stale stretched limbs.
--   * Characters are tracked in a weak set and only alive characters are
--     swept; dead/respawned characters drop out automatically instead of
--     being re-applied forever.
--   * Transparency, collision, mass, accessories and the refresh interval
--     are all independent options instead of hard-coded side effects.

type HitboxSettings = {
    mode: string,
    bodyScale: number,
    headSize: number,
    rootSize: number,
    visibleTransparency: number,
    forceVisible: boolean,
    noCollision: boolean,
    massless: boolean,
    excludeAccessories: boolean,
    updateInterval: number,
}

type OriginalHitboxState = {
    size: Vector3,
    transparency: number,
    canCollide: boolean,
    massless: boolean,
}

local hitboxSettings: HitboxSettings = {
    mode = "Visible",
    bodyScale = 2.25,
    headSize = 8,
    rootSize = 12,
    visibleTransparency = 30,
    forceVisible = true,
    noCollision = true,
    massless = true,
    excludeAccessories = true,
    updateInterval = 0.1,
}
local originalHitboxes: {[BasePart]: OriginalHitboxState} =
    setmetatable({}, {__mode = "k"}) :: any
local hitboxCharacters: {[Model]: boolean} =
    setmetatable({}, {__mode = "k"}) :: any

local function restoreHitboxes(): ()
    for part: BasePart, original: OriginalHitboxState in pairs(originalHitboxes) do
        if part.Parent then
            part.Size = original.size
            part.Transparency = original.transparency
            part.CanCollide = original.canCollide
            part.Massless = original.massless
        end
    end
    originalHitboxes = setmetatable({}, {__mode = "k"}) :: any
    hitboxCharacters = setmetatable({}, {__mode = "k"}) :: any
end

local function isScaledBodyPart(part: BasePart): boolean
    if part.Name == "HumanoidRootPart" then
        return false
    end
    if part:FindFirstAncestorOfClass("Tool") then
        return false
    end
    if hitboxSettings.excludeAccessories
        and part:FindFirstAncestorOfClass("Accessory") then
        return false
    end
    return true
end

local function applyHitboxToPart(part: BasePart): ()
    local original: OriginalHitboxState? = originalHitboxes[part]
    if not original then
        original = {
            size = part.Size,
            transparency = part.Transparency,
            canCollide = part.CanCollide,
            massless = part.Massless,
        }
        originalHitboxes[part] = original
    end
    local resolvedOriginal: OriginalHitboxState = original :: OriginalHitboxState

    if part.Name == "HumanoidRootPart" then
        part.Size = Vector3.new(
            hitboxSettings.rootSize,
            hitboxSettings.rootSize,
            hitboxSettings.rootSize
        )
        part.Transparency = 1
    else
        if part.Name == "Head" then
            part.Size = Vector3.new(
                hitboxSettings.headSize,
                hitboxSettings.headSize,
                hitboxSettings.headSize
            )
        else
            part.Size = resolvedOriginal.size * hitboxSettings.bodyScale
        end
        if hitboxSettings.forceVisible then
            part.Transparency = math.min(
                resolvedOriginal.transparency,
                hitboxSettings.visibleTransparency / 100
            )
        end
    end

    part.CanCollide = hitboxSettings.noCollision
        and false
        or resolvedOriginal.canCollide
    part.Massless = hitboxSettings.massless
end

-- Restores every part the current mode no longer targets. Keeps the world
-- clean when the user flips the mode slider mid-flight: switching to "Root"
-- unwinds all stretched visible parts and vice versa.
local function refreshHitboxMode(): ()
    for part: BasePart, original: OriginalHitboxState in pairs(originalHitboxes) do
        if not part.Parent then
            continue
        end
        local isRoot: boolean = part.Name == "HumanoidRootPart"
        local stillTargeted: boolean = isRoot
            and hitboxSettings.mode ~= "Visible"
            or (not isRoot and hitboxSettings.mode ~= "Root")
        if not stillTargeted then
            part.Size = original.size
            part.Transparency = original.transparency
            part.CanCollide = original.canCollide
            part.Massless = original.massless
            originalHitboxes[part] = nil
        end
    end
end

local function sweepHitboxes(): ()
    -- Track every alive enemy character; respawns are picked up on the next
    -- sweep and dead characters drop out of the weak set.
    for _, player: Player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local character: Model = player.Character
            local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 and character.Parent then
                hitboxCharacters[character] = true
            end
        end
    end

    for character: Model in pairs(hitboxCharacters) do
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if character.Parent == nil or not humanoid or humanoid.Health <= 0 then
            hitboxCharacters[character] = nil
            continue
        end
        for _, part: Instance in ipairs(character:GetChildren()) do
            if not part:IsA("BasePart") then
                continue
            end
            local isRoot: boolean = part.Name == "HumanoidRootPart"
            if isRoot then
                if hitboxSettings.mode ~= "Visible" then
                    applyHitboxToPart(part)
                end
            elseif hitboxSettings.mode ~= "Root" and isScaledBodyPart(part) then
                applyHitboxToPart(part)
            end
        end
    end
end

local function toggleHitboxes(enabled: boolean): ()
    disconnectFeatureConnection("Hitboxes")
    restoreHitboxes()

    if not enabled then
        return
    end

    local elapsed: number = 0
    featureConnections.Hitboxes = TaskManager:Connect(function(deltaTime: number): ()
        elapsed = elapsed + deltaTime
        if elapsed < hitboxSettings.updateInterval then
            return
        end
        elapsed = 0
        sweepHitboxes()
    end)
end

local antiVoidPlatform: Part? = nil
local antiVoidLastGroundY: number? = nil
local antiVoidFreefallSeconds: number = 0
local antiVoidPlatformToken: number = 0

local function removeAntiVoidPlatform(): ()
    antiVoidPlatformToken = antiVoidPlatformToken + 1
    if antiVoidPlatform then
        antiVoidPlatform:Destroy()
        antiVoidPlatform = nil
    end
end

local function createAntiVoidPlatform(root: BasePart, humanoid: Humanoid): ()
    removeAntiVoidPlatform()

    local platform: Part = Instance.new("Part")
    platform.Name = "RTM_AntiVoidPlatform"
    platform.Anchored = true
    platform.CanCollide = true
    platform.CanQuery = false
    platform.CanTouch = false
    platform.CastShadow = false
    platform.Size = Vector3.new(42, 1, 42)
    platform.Transparency = 1
    platform.CFrame = CFrame.new(root.Position - Vector3.new(0, 4.25, 0))
    platform.Parent = workspace
    antiVoidPlatform = platform

    local velocity: Vector3 = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.25, 0, velocity.Z * 0.25)
    root.AssemblyAngularVelocity = Vector3.zero
    humanoid:ChangeState(Enum.HumanoidStateType.Landed)

    local token: number = antiVoidPlatformToken
    task.delay(3, function(): ()
        if antiVoidPlatformToken == token then
            removeAntiVoidPlatform()
        end
    end)
end

local function toggleAntiVoid(enabled: boolean): ()
    disconnectFeatureConnection("AntiVoid")
    removeAntiVoidPlatform()
    antiVoidLastGroundY = nil
    antiVoidFreefallSeconds = 0

    if not enabled then
        return
    end

    featureConnections.AntiVoid = TaskManager:Connect(function(deltaTime: number): ()
        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
            return
        end

        if humanoid.FloorMaterial ~= Enum.Material.Air then
            antiVoidLastGroundY = root.Position.Y
            antiVoidFreefallSeconds = 0
            return
        end

        antiVoidFreefallSeconds = antiVoidFreefallSeconds + deltaTime
        local destroyHeight: number = workspace.FallenPartsDestroyHeight
        if destroyHeight ~= destroyHeight then
            destroyHeight = -500
        end

        local nearDestroyLayer: boolean = root.Position.Y <= destroyHeight + 45
        local fellFarFromGround: boolean = antiVoidLastGroundY ~= nil
            and root.Position.Y <= (antiVoidLastGroundY :: number) - 120
            and antiVoidFreefallSeconds >= 1.1
            and root.AssemblyLinearVelocity.Y < -45

        if nearDestroyLayer or fellFarFromGround then
            createAntiVoidPlatform(root, humanoid)
            antiVoidFreefallSeconds = 0
        end
    end)
end

local gravitySettings = {value = 196.2}
local originalGravity = workspace.Gravity

local function toggleGravity(enabled)
    disconnectFeatureConnection("Gravity")

    if not enabled then
        workspace.Gravity = originalGravity
        return
    end

    originalGravity = workspace.Gravity
    featureConnections.Gravity = TaskManager:Connect(function()
        workspace.Gravity = gravitySettings.value
    end)
end

local jumpPowerSettings = {value = 80}
local originalJumpPower = setmetatable({}, {__mode = "k"})

local function restoreJumpPower()
    for humanoid, original in pairs(originalJumpPower) do
        if humanoid and humanoid.Parent then
            humanoid.JumpPower = original.jumpPower
            humanoid.UseJumpPower = original.useJumpPower
        end
    end
    originalJumpPower = setmetatable({}, {__mode = "k"})
end

local function toggleJumpPower(enabled)
    disconnectFeatureConnection("JumpPower")
    restoreJumpPower()

    if not enabled then
        return
    end

    featureConnections.JumpPower = TaskManager:Connect(function()
        local _, humanoid = getCharacterParts()
        if not humanoid then
            return
        end

        if not originalJumpPower[humanoid] then
            originalJumpPower[humanoid] = {
                jumpPower = humanoid.JumpPower,
                useJumpPower = humanoid.UseJumpPower,
            }
        end

        humanoid.UseJumpPower = true
        humanoid.JumpPower = jumpPowerSettings.value
    end)
end

-- Infinite Jump.
--
-- Rewritten: on touch the jump button re-fires `JumpRequest` many times per
-- second while it is held, so every request adding velocity made the module
-- uncontrollable and made it look like it was still on after being switched
-- off. Each mode is now a distinct, rate-limited behaviour.
--
--   Normal  every jump sets the same height. Predictable, does not stack.
--   Impulse the same height reached with a force, so the character stays a
--           normal physics body instead of having its velocity overwritten.
--   Stack   each jump adds to the current climb (the old "Normal"), capped.
--   Rise    hold jump to fly straight up at a steady speed.
--   Fall    jumping mid-air cancels the fall instead of launching you, which
--           is what a fall-mode jump was supposed to do — it used to be an
--           exact copy of Normal, so it never worked at all.
local infiniteJumpSettings = {
    mode = "Normal",
    strength = 50,
    riseSpeed = 75,
    -- Minimum spacing between jumps. Touch fires jump requests continuously;
    -- without this the character leaves the map in a second.
    interval = 0.18,
    stackCeiling = 160,
}
-- Both the enabled flag and the rate limiter live on `state`: bootstrap() is
-- already at Luau's 200 local-register ceiling.
state.infiniteJumpEnabled = false
state.lastInfiniteJumpAt = -math.huge

local function performInfiniteJump(): ()
    -- A disconnected signal can still deliver the event it was already
    -- dispatching, which on touch — where the jump button fires continuously —
    -- kept launching the character after the module had been switched off.
    if not state.infiniteJumpEnabled then
        return
    end

    local _, humanoid, root = getCharacterParts()
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end

    -- Touch cannot tap as deliberately as a keyboard can: the on-screen jump
    -- button repeats for as long as a finger rests on it, so the floor on the
    -- spacing is higher there no matter what the slider says.
    local spacing: number = infiniteJumpSettings.interval
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        spacing = math.max(spacing, 0.25)
    end

    local now: number = os.clock()
    if now - state.lastInfiniteJumpAt < spacing then
        return
    end
    state.lastInfiniteJumpAt = now

    local velocity: Vector3 = root.AssemblyLinearVelocity
    local vertical: number
    if infiniteJumpSettings.mode == "Stack" then
        vertical = math.min(
            velocity.Y + infiniteJumpSettings.strength,
            infiniteJumpSettings.stackCeiling
        )
    elseif infiniteJumpSettings.mode == "Impulse" then
        -- Force instead of a velocity write: the body keeps whatever physics
        -- the game applies to it, which survives checks that watch for
        -- AssemblyLinearVelocity being overwritten.
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        root:ApplyImpulse(
            Vector3.new(0, infiniteJumpSettings.strength - velocity.Y, 0)
                * root.AssemblyMass
        )
        return
    elseif infiniteJumpSettings.mode == "Fall" then
        -- Cancel the fall: kill downward momentum and hold position for an
        -- instant. Jumping again keeps you up without ever launching.
        if velocity.Y >= 0 then
            return
        end
        vertical = 0
    else
        vertical = infiniteJumpSettings.strength
    end

    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    root.AssemblyLinearVelocity = Vector3.new(velocity.X, vertical, velocity.Z)
end

local function toggleInfiniteJump(enabled)
    disconnectFeatureConnection("InfiniteJump")
    disconnectFeatureConnection("InfiniteJumpRise")
    state.infiniteJumpEnabled = false
    state.lastInfiniteJumpAt = -math.huge

    if not enabled then
        return
    end
    state.infiniteJumpEnabled = true

    -- `JumpRequest` is the one jump signal every device raises.
    featureConnections.InfiniteJump = state.onJumpRequest(function(): ()
        if infiniteJumpSettings.mode == "Rise" then
            return
        end
        performInfiniteJump()
    end)

    featureConnections.InfiniteJumpRise = TaskManager:Connect(function(): ()
        if not state.infiniteJumpEnabled
            or infiniteJumpSettings.mode ~= "Rise"
            or not state.isJumpHeld() then
            return
        end

        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        local velocity = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(
            velocity.X,
            infiniteJumpSettings.riseSpeed,
            velocity.Z
        )
    end)
end

local walkSpeedSettings = {value = 32}
local originalWalkSpeed = setmetatable({}, {__mode = "k"})

local function restoreWalkSpeed()
    for humanoid, value in pairs(originalWalkSpeed) do
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = value
        end
    end
    originalWalkSpeed = setmetatable({}, {__mode = "k"})
end

local function toggleWalkSpeed(enabled)
    disconnectFeatureConnection("WalkSpeed")
    restoreWalkSpeed()

    if not enabled then
        return
    end

    featureConnections.WalkSpeed = TaskManager:Connect(function()
        local _, humanoid = getCharacterParts()
        if humanoid then
            if not originalWalkSpeed[humanoid] then
                originalWalkSpeed[humanoid] = humanoid.WalkSpeed
            end
            humanoid.WalkSpeed = walkSpeedSettings.value
        end
    end)
end

type PhysicsSpeedSettings = {
    mode: string,
    speed: number,
    verticalSpeed: number,
    platformStand: boolean,
    customProperties: boolean,
    motorTorque: number,
    wallCheck: boolean,
    autoJump: boolean,
    jumpVelocity: number,
    acceleration: number,
    burstInterval: number,
    airControl: number,
    sprintMultiplier: number,
    sprintKey: Enum.KeyCode,
    preserveMomentum: boolean,
}

type VehicleSeatState = {
    maxSpeed: number,
    torque: number,
    turnSpeed: number,
}

type HingeState = {
    angularVelocity: number,
    motorMaxTorque: number,
}

local physicsSpeedSettings: PhysicsSpeedSettings = {
    mode = "Smooth",
    speed = 50,
    verticalSpeed = 50,
    platformStand = false,
    customProperties = true,
    motorTorque = 50000,
    wallCheck = true,
    autoJump = false,
    jumpVelocity = 45,
    acceleration = 14,
    burstInterval = 0.2,
    airControl = 0.72,
    sprintMultiplier = 1.65,
    sprintKey = Enum.KeyCode.LeftShift,
    preserveMomentum = false,
}
-- The physics-speed helpers are scoped to a block so their registers go
-- back to the bootstrap function, which sits at Luau's 200-local ceiling.
local restorePhysicsMotors: () -> ()
local togglePhysicsSpeed: (boolean) -> ()
do
local physicsSpeedTeleportClock: number = 0
local originalVehicleSeats: {[VehicleSeat]: VehicleSeatState} =
    setmetatable({}, {__mode = "k"}) :: any
local originalMotorHinges: {[HingeConstraint]: HingeState} =
    setmetatable({}, {__mode = "k"}) :: any

function restorePhysicsMotors(): ()
    for seat: VehicleSeat, original: VehicleSeatState in pairs(originalVehicleSeats) do
        if seat.Parent then
            seat.MaxSpeed = original.maxSpeed
            seat.Torque = original.torque
            seat.TurnSpeed = original.turnSpeed
        end
    end
    originalVehicleSeats = setmetatable({}, {__mode = "k"}) :: any

    for hinge: HingeConstraint, original: HingeState in pairs(originalMotorHinges) do
        if hinge.Parent then
            hinge.AngularVelocity = original.angularVelocity
            hinge.MotorMaxTorque = original.motorMaxTorque
        end
    end
    originalMotorHinges = setmetatable({}, {__mode = "k"}) :: any
end

local function getPhysicsSpeedTarget(): (BasePart?, Humanoid?, VehicleSeat?)
    local _, humanoid, root = getCharacterParts()
    if not humanoid or not root then
        return nil, humanoid, nil
    end

    local seatPart: BasePart? = humanoid.SeatPart
    if seatPart and seatPart:IsA("VehicleSeat") then
        return seatPart.AssemblyRootPart or seatPart, humanoid, seatPart
    end
    if seatPart then
        return seatPart.AssemblyRootPart or seatPart, humanoid, nil
    end

    return root.AssemblyRootPart or root, humanoid, nil
end

local function tunePhysicsMotors(seat: VehicleSeat): ()
    local model: Model? = seat:FindFirstAncestorOfClass("Model")
    if not model then
        return
    end

    for _, descendant: Instance in ipairs(model:GetDescendants()) do
        if descendant:IsA("VehicleSeat") then
            local original: VehicleSeatState? = originalVehicleSeats[descendant]
            if not original then
                original = {
                    maxSpeed = descendant.MaxSpeed,
                    torque = descendant.Torque,
                    turnSpeed = descendant.TurnSpeed,
                }
                originalVehicleSeats[descendant] = original
            end
            local resolvedOriginal: VehicleSeatState = original :: VehicleSeatState
            descendant.MaxSpeed = physicsSpeedSettings.speed
            descendant.Torque = math.max(
                resolvedOriginal.torque,
                physicsSpeedSettings.motorTorque
            )
            descendant.TurnSpeed = math.max(
                resolvedOriginal.turnSpeed,
                physicsSpeedSettings.speed * 0.35
            )
        elseif descendant:IsA("HingeConstraint")
            and descendant.ActuatorType == Enum.ActuatorType.Motor then
            local original: HingeState? = originalMotorHinges[descendant]
            if not original then
                original = {
                    angularVelocity = descendant.AngularVelocity,
                    motorMaxTorque = descendant.MotorMaxTorque,
                }
                originalMotorHinges[descendant] = original
            end
            local resolvedOriginal: HingeState = original :: HingeState

            local sign: number = resolvedOriginal.angularVelocity < 0 and -1 or 1
            descendant.AngularVelocity = sign
                * math.max(
                    math.abs(resolvedOriginal.angularVelocity),
                    physicsSpeedSettings.speed / 3
                )
            descendant.MotorMaxTorque = math.max(
                resolvedOriginal.motorMaxTorque,
                physicsSpeedSettings.motorTorque
            )
        end
    end
end

function togglePhysicsSpeed(enabled: boolean): ()
    disconnectFeatureConnection("PhysicsSpeed")
    restorePhysicsMotors()
    physicsSpeedTeleportClock = 0

    state.platformStandController.set("PhysicsSpeed", nil)

    if not enabled then
        return
    end

    featureConnections.PhysicsSpeed =
        TaskManager:Connect(function(deltaTime: number): ()
            local assembly, currentHumanoid, vehicleSeat = getPhysicsSpeedTarget()
            if not assembly or not currentHumanoid then
                return
            end

            state.platformStandController.set(
                "PhysicsSpeed",
                physicsSpeedSettings.platformStand
            )
            state.platformStandController.apply(currentHumanoid)

            if vehicleSeat and physicsSpeedSettings.customProperties then
                tunePhysicsMotors(vehicleSeat)
            end

            local direction: Vector3 = currentHumanoid.MoveDirection
            if vehicleSeat then
                direction = vehicleSeat.CFrame.LookVector * vehicleSeat.ThrottleFloat
            else
                -- Humanoid.MoveDirection reads zero while PlatformStand is on
                -- and on touch clients whose control module is bypassed, which
                -- is exactly why Speed stood still with its own PlatformStand
                -- option enabled. The shared helper answers on every device.
                local camera: Camera? = workspace.CurrentCamera
                local forwardScalar: number, rightScalar: number = state.getMoveInput()
                if camera and (forwardScalar ~= 0 or rightScalar ~= 0) then
                    direction = camera.CFrame.LookVector * forwardScalar
                        + camera.CFrame.RightVector * rightScalar
                end
            end
            direction = Vector3.new(direction.X, 0, direction.Z)
            if direction.Magnitude > 1 then
                direction = direction.Unit
            end

            local wallBlocked: boolean = false
            if physicsSpeedSettings.wallCheck
                and direction.Magnitude > 0.001 then
                local raycastParams: RaycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {
                    currentHumanoid.Parent :: Instance,
                }
                local wallHit: RaycastResult? = workspace:Raycast(
                    assembly.Position,
                    direction.Unit * 2.75,
                    raycastParams
                )
                if wallHit then
                    direction = Vector3.zero
                    wallBlocked = true
                end
            end

            if not vehicleSeat
                and physicsSpeedSettings.autoJump
                and direction.Magnitude > 0.001
                and currentHumanoid.FloorMaterial ~= Enum.Material.Air then
                currentHumanoid.Jump = true
                local jumpVelocity: Vector3 = assembly.AssemblyLinearVelocity
                assembly.AssemblyLinearVelocity = Vector3.new(
                    jumpVelocity.X,
                    math.max(jumpVelocity.Y, physicsSpeedSettings.jumpVelocity),
                    jumpVelocity.Z
                )
            end

            local currentVelocity: Vector3 = assembly.AssemblyLinearVelocity
            local grounded: boolean = currentHumanoid.FloorMaterial ~= Enum.Material.Air
            -- Touch clients hold a placed SPRINT button instead of a key.
            local sprinting: boolean = state.speedSprintHeld == true
                or (not state.isMobile
                    and UserInputService:IsKeyDown(physicsSpeedSettings.sprintKey))
            local resolvedSpeed: number = physicsSpeedSettings.speed
                * (sprinting and physicsSpeedSettings.sprintMultiplier or 1)
            if physicsSpeedSettings.mode == "Adaptive" and not grounded then
                resolvedSpeed *= physicsSpeedSettings.airControl
            end
            local vertical: number = math.clamp(
                currentVelocity.Y,
                -physicsSpeedSettings.verticalSpeed,
                physicsSpeedSettings.verticalSpeed
            )
            local currentHorizontal: Vector3 = Vector3.new(
                currentVelocity.X,
                0,
                currentVelocity.Z
            )
            local keepMomentum: boolean = physicsSpeedSettings.preserveMomentum
                or physicsSpeedSettings.mode == "Adaptive"
            local targetHorizontal: Vector3 = not wallBlocked
                    and direction.Magnitude > 0.001
                    and direction * resolvedSpeed
                or not wallBlocked and keepMomentum and currentHorizontal
                or Vector3.zero
            local targetVelocity: Vector3 = targetHorizontal
                + Vector3.new(0, vertical, 0)

            if physicsSpeedSettings.mode == "Smooth"
                or physicsSpeedSettings.mode == "Adaptive" then
                local alpha: number = 1 - math.exp(
                    -physicsSpeedSettings.acceleration * deltaTime
                )
                local smoothedHorizontal: Vector3 = currentHorizontal:Lerp(
                    targetHorizontal,
                    alpha
                )
                assembly.AssemblyLinearVelocity = smoothedHorizontal
                    + Vector3.new(0, vertical, 0)
            elseif physicsSpeedSettings.mode == "Boost" then
                local correction: Vector3 = targetVelocity - currentVelocity
                assembly:ApplyImpulse(
                    correction
                        * assembly.AssemblyMass
                        * math.clamp(deltaTime * 9, 0, 1)
                )
            elseif physicsSpeedSettings.mode == "CFrame" then
                -- Displacement instead of velocity: a speed cap has nothing to
                -- clamp, and the walk the game already gives us is subtracted
                -- so the total stays at the slider value.
                local extra: number = math.max(
                    resolvedSpeed - currentHumanoid.WalkSpeed,
                    0
                )
                if not wallBlocked and direction.Magnitude > 0.001 then
                    assembly.CFrame = assembly.CFrame
                        + direction * extra * deltaTime
                end
            elseif physicsSpeedSettings.mode == "Pulse" then
                -- Bursts with a coast between them: the average speed stays
                -- close to a normal player's, only the peaks are fast.
                local period: number = math.max(
                    physicsSpeedSettings.burstInterval,
                    0.05
                ) * 2
                local burst: boolean = (os.clock() % period) < (period * 0.5)
                local pulseSpeed: number = burst
                    and resolvedSpeed
                    or currentHumanoid.WalkSpeed
                assembly.AssemblyLinearVelocity = (
                    not wallBlocked and direction * pulseSpeed or Vector3.zero
                ) + Vector3.new(0, vertical, 0)
            elseif physicsSpeedSettings.mode == "Teleport" then
                physicsSpeedTeleportClock = physicsSpeedTeleportClock + deltaTime
                if physicsSpeedTeleportClock >= 0.14 then
                    assembly.CFrame = assembly.CFrame
                        + direction
                            * resolvedSpeed
                            * physicsSpeedTeleportClock
                    physicsSpeedTeleportClock = 0
                end
            end
        end)
end
end

local fovSettings = {value = 90}
state.fovController = state.fovController or {
    owners = {},
    baselines = setmetatable({}, {__mode = "k"}),
    sequence = 0,
}
state.fovController.set = function(ownerId: string, value: number?): ()
    local controller: any = state.fovController
    if value == nil then
        controller.owners[ownerId] = nil
        if next(controller.owners) == nil then
            for camera: Camera, baseline: number in pairs(controller.baselines) do
                if camera.Parent then
                    camera.FieldOfView = baseline
                end
            end
            controller.baselines = setmetatable({}, {__mode = "k"})
        end
        return
    end
    local owner: any = controller.owners[ownerId]
    if not owner then
        controller.sequence += 1
        owner = {sequence = controller.sequence, value = value}
        controller.owners[ownerId] = owner
    else
        owner.value = value
    end
end
state.fovController.apply = function(camera: Camera?): ()
    if not camera then
        return
    end
    local controller: any = state.fovController
    if controller.baselines[camera] == nil then
        controller.baselines[camera] = camera.FieldOfView
    end
    local selected: any = nil
    for _, owner: any in pairs(controller.owners) do
        if not selected or owner.sequence > selected.sequence then
            selected = owner
        end
    end
    if selected then
        camera.FieldOfView = selected.value
    end
end

local function toggleFov(enabled)
    disconnectFeatureConnection("FOV")
    state.fovController.set("Universal", enabled and fovSettings.value or nil)
    if not enabled then
        return
    end

    featureConnections.FOV = TaskManager:Connect(function()
        state.fovController.set("Universal", fovSettings.value)
        state.fovController.apply(workspace.CurrentCamera)
    end)
end

local toggleNoclip: (boolean) -> ()
do
local originalCollision = setmetatable({}, {__mode = "k"})

local function restoreCollision()
    for part, canCollide in pairs(originalCollision) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
    end
    originalCollision = setmetatable({}, {__mode = "k"})
end

function toggleNoclip(enabled: boolean): ()
    disconnectFeatureConnection("Noclip")
    restoreCollision()

    if not enabled then
        return
    end

    featureConnections.Noclip = TaskManager:Connect(function()
        local character = LocalPlayer.Character
        if not character then
            return
        end

        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") then
                if originalCollision[descendant] == nil then
                    originalCollision[descendant] = descendant.CanCollide
                end
                descendant.CanCollide = false
            end
        end
    end)
end
end

local function toggleAntiAfk(enabled)
    disconnectFeatureConnection("AntiAFK")

    if not enabled then
        return
    end

    featureConnections.AntiAFK = LocalPlayer.Idled:Connect(function()
        local virtualUserOk, virtualUser = pcall(function()
            return game:GetService("VirtualUser")
        end)
        if virtualUserOk and virtualUser then
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end
    end)
end

local flingRunning = false
state.isProtectedTarget = function(_targetPlayer: Player): boolean
    return false
end
local antiFlingSettings = {velocityLimit = 120}
local antiFlingSafeCFrame = nil

local function toggleAntiFling(enabled)
    disconnectFeatureConnection("AntiFling")
    antiFlingSafeCFrame = nil

    if not enabled then
        return
    end

    featureConnections.AntiFling = TaskManager:Connect(function()
        if flingRunning then
            return
        end

        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
            return
        end

        local linearSpeed = root.AssemblyLinearVelocity.Magnitude
        local angularSpeed = root.AssemblyAngularVelocity.Magnitude

        if linearSpeed > antiFlingSettings.velocityLimit
            or angularSpeed > antiFlingSettings.velocityLimit then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if antiFlingSafeCFrame then
                root.CFrame = antiFlingSafeCFrame
            end
        elseif humanoid.FloorMaterial ~= Enum.Material.Air
            and linearSpeed < antiFlingSettings.velocityLimit * 0.45 then
            antiFlingSafeCFrame = root.CFrame
        end
    end)
end

local lagSwitchSettings = {incomingLag = 999}
local originalIncomingLag = 0

local function setIncomingReplicationLag(value)
    local success = pcall(function()
        settings():GetService("NetworkSettings").IncomingReplicationLag = value
    end)
    return success
end

local function toggleLagSwitch(enabled)
    disconnectFeatureConnection("LagSwitch")

    if not enabled then
        setIncomingReplicationLag(originalIncomingLag)
        return
    end

    pcall(function()
        originalIncomingLag = settings():GetService(
            "NetworkSettings"
        ).IncomingReplicationLag
    end)

    if not setIncomingReplicationLag(lagSwitchSettings.incomingLag) then
        error("NetworkSettings is not available in this client.")
    end

    featureConnections.LagSwitch = TaskManager:Connect(function()
        setIncomingReplicationLag(lagSwitchSettings.incomingLag)
    end)
end

type UniversalFlingSettings = {
    target: string,
    duration: number,
    power: number,
    returnToStart: boolean,
}

local universalFlingSettings: UniversalFlingSettings = {
    target = "",
    duration = 6,
    power = 1,
    returnToStart = true,
}

findPlayerByText = function(text: string): Player?
    local query: string = string.lower(text)
    if query == "" then
        local _, _, localRoot = getCharacterParts()
        local nearest: Player? = nil
        local nearestDistance: number = math.huge

        if localRoot then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                local root: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart")
                    :: BasePart?
                if player ~= LocalPlayer and root then
                    local distance: number = (root.Position - localRoot.Position).Magnitude
                    if distance < nearestDistance then
                        nearest = player
                        nearestDistance = distance
                    end
                end
            end
        end
        return nearest
    end

    for _, player: Player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local username: string = string.lower(player.Name)
            local displayName: string = string.lower(player.DisplayName)
            if string.sub(username, 1, #query) == query
                or string.sub(displayName, 1, #query) == query then
                return player
            end
        end
    end

    return nil
end

-- Fling.
--
-- Rewritten because the previous version reported "stopped after the 5 second
-- safety limit" the instant it was activated. The loop guarded on
-- `targetPlayer.Parent == Players`, but `Players` here is a `cloneref` handle:
-- the clone never compares equal to the real service that `Parent` returns, so
-- on any executor with `cloneref` the condition was false on the first
-- iteration, the loop body never ran and the routine fell straight through to
-- its timeout message.
--
-- The rewrite drops instance-identity comparisons entirely (a player is in the
-- game while it has a parent), re-reads the local character every iteration so
-- a respawn cannot strand the routine, alternates Stepped/Heartbeat so the
-- velocity actually replicates, and always restores the character.
performFling = function(targetPlayer: Player): ()
    if state.isProtectedTarget(targetPlayer) then
        notify("That player is protected by FriendList.")
        return
    end
    if flingRunning then
        notify("A fling is already running.")
        return
    end

    flingRunning = true
    task.spawn(function(): ()
        local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not humanoid or not root then
            flingRunning = false
            notify("Your character is not ready.")
            return
        end

        local savedCFrame: CFrame = root.CFrame
        local savedAutoRotate: boolean = humanoid.AutoRotate
        local savedCameraSubject: (Humanoid | BasePart)? = workspace.CurrentCamera
            and workspace.CurrentCamera.CameraSubject
            :: (Humanoid | BasePart)?
        local touchedTarget: boolean = false
        local reason: string = "timeout"

        -- The velocity magnitude is what does the flinging: the engine
        -- resolves the collision between two fast-moving assemblies and the
        -- server accepts it because we own our own character.
        local power: number = 9e4 * math.clamp(universalFlingSettings.power, 0.25, 4)
        local duration: number = math.clamp(universalFlingSettings.duration, 1, 20)

        local success: boolean, errorMessage: any = pcall(function(): ()
            local startedAt: number = os.clock()
            local step: number = 0
            local destroyHeight: number = workspace.FallenPartsDestroyHeight
            if destroyHeight ~= destroyHeight then
                destroyHeight = -500
            end
            local voidThreshold: number = destroyHeight + 35

            humanoid.AutoRotate = false
            if humanoid.Sit then
                humanoid.Sit = false
            end

            while os.clock() - startedAt < duration do
                -- A player that left the game has no parent any more; this
                -- replaces the old identity check against the service.
                if targetPlayer.Parent == nil then
                    reason = "left"
                    break
                end

                local targetCharacter: Model? = targetPlayer.Character
                local targetRoot: BasePart? = targetCharacter
                    and targetCharacter:FindFirstChild("HumanoidRootPart")
                    :: BasePart?
                local targetHumanoid: Humanoid? = targetCharacter
                    and targetCharacter:FindFirstChildOfClass("Humanoid")
                    :: Humanoid?
                if not targetRoot or not targetRoot.Parent then
                    reason = "gone"
                    break
                end
                if targetHumanoid and targetHumanoid.Health <= 0 then
                    touchedTarget = true
                    reason = "killed"
                    break
                end
                if targetRoot.Position.Y <= voidThreshold then
                    touchedTarget = true
                    reason = "void"
                    break
                end

                -- Re-read our own parts: a respawn mid-fling replaces them,
                -- and writing to the old ones would silently do nothing.
                local _, liveHumanoid: Humanoid?, liveRoot: BasePart? =
                    getCharacterParts()
                if not liveHumanoid or not liveRoot then
                    reason = "died"
                    break
                end
                if liveHumanoid.Health <= 0 then
                    reason = "died"
                    break
                end
                if liveRoot.Anchored then
                    liveRoot.Anchored = false
                end
                humanoid = liveHumanoid
                root = liveRoot

                step += 1
                -- Orbit the target so the two assemblies keep colliding from
                -- alternating directions instead of resting inside each other.
                local phase: number = (step % 6) / 6 * math.pi * 2
                local vertical: number = (step % 2 == 0) and 1.1 or -1.1
                liveRoot.CFrame = targetRoot.CFrame
                    * CFrame.new(math.cos(phase) * 1.6, vertical, math.sin(phase) * 1.6)
                local sign: number = (step % 2 == 0) and 1 or -1
                liveRoot.AssemblyLinearVelocity =
                    Vector3.new(power * sign, power, power * -sign)
                liveRoot.AssemblyAngularVelocity =
                    Vector3.new(power, power, power)

                -- Stepped writes land before physics, Heartbeat after: doing
                -- both per cycle is what makes the fling replicate reliably.
                RunService.Stepped:Wait()
                if liveRoot.Parent then
                    liveRoot.AssemblyLinearVelocity =
                        Vector3.new(power * -sign, power, power * sign)
                end
                RunService.Heartbeat:Wait()
            end
        end)

        -- Restoration always runs, including after an error.
        local _, finalHumanoid: Humanoid?, finalRoot: BasePart? = getCharacterParts()
        if finalRoot and finalRoot.Parent then
            finalRoot.AssemblyLinearVelocity = Vector3.zero
            finalRoot.AssemblyAngularVelocity = Vector3.zero
            if universalFlingSettings.returnToStart then
                finalRoot.CFrame = savedCFrame + Vector3.new(0, 2, 0)
            end
        end
        if finalHumanoid then
            finalHumanoid.AutoRotate = savedAutoRotate
            finalHumanoid.PlatformStand = false
        end
        if workspace.CurrentCamera then
            workspace.CurrentCamera.CameraSubject =
                savedCameraSubject or finalHumanoid or humanoid
        end

        flingRunning = false
        if not success then
            notify("Fling failed: " .. tostring(errorMessage))
        elseif touchedTarget then
            notify("Fling completed: " .. targetPlayer.Name .. " went down.")
        elseif reason == "left" then
            notify("Fling stopped: " .. targetPlayer.Name .. " left the game.")
        elseif reason == "gone" then
            notify("Fling stopped: the target character disappeared.")
        elseif reason == "died" then
            notify("Fling stopped: your character died.")
        else
            notify(
                "Fling stopped after "
                    .. string.format("%.0f", universalFlingSettings.duration)
                    .. "s. Raise Duration or Power for tougher targets."
            )
        end
    end)
end

state.fullbrightSettings = {
    brightness = 3,
    clockTime = 14,
}
state.originalLighting = nil

state.toggleFullbright = function(enabled)
    disconnectFeatureConnection("Fullbright")

    if not enabled then
        if state.originalLighting then
            Lighting.Brightness = state.originalLighting.brightness
            Lighting.ClockTime = state.originalLighting.clockTime
            Lighting.GlobalShadows = state.originalLighting.globalShadows
            Lighting.FogEnd = state.originalLighting.fogEnd
            Lighting.Ambient = state.originalLighting.ambient
            Lighting.OutdoorAmbient = state.originalLighting.outdoorAmbient
        end
        return
    end

    state.originalLighting = {
        brightness = Lighting.Brightness,
        clockTime = Lighting.ClockTime,
        globalShadows = Lighting.GlobalShadows,
        fogEnd = Lighting.FogEnd,
        ambient = Lighting.Ambient,
        outdoorAmbient = Lighting.OutdoorAmbient,
    }

    featureConnections.Fullbright = TaskManager:Connect(function()
        Lighting.Brightness = state.fullbrightSettings.brightness
        Lighting.ClockTime = state.fullbrightSettings.clockTime
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    end)
end

state.universalToolkit = (function(): any
local originalXrayTransparency: {[BasePart]: number} =
    setmetatable({}, {__mode = "k"}) :: any
local xrayEnabled: boolean = false

local function restoreXray(): ()
    for part: BasePart, transparency: number in pairs(originalXrayTransparency) do
        if part.Parent then
            part.LocalTransparencyModifier = transparency
        end
    end
    originalXrayTransparency = setmetatable({}, {__mode = "k"}) :: any
end

local function toggleXray(enabled: boolean): ()
    disconnectFeatureConnection("Xray")
    xrayEnabled = false
    restoreXray()
    if not enabled then
        return
    end

    xrayEnabled = true
    local function applyToInstance(descendant: Instance): ()
        if not xrayEnabled or not descendant:IsA("BasePart") then
            return
        end
        local localCharacter: Model? = LocalPlayer.Character
        local ancestorModel: Model? = descendant:FindFirstAncestorOfClass("Model")
        if (localCharacter and descendant:IsDescendantOf(localCharacter))
            or descendant:FindFirstAncestorOfClass("Tool")
            or (ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid")) then
            return
        end
        if originalXrayTransparency[descendant] == nil then
            originalXrayTransparency[descendant] = descendant.LocalTransparencyModifier
        end
        descendant.LocalTransparencyModifier = math.max(
            descendant.LocalTransparencyModifier,
            0.72
        )
    end

    featureConnections.Xray = workspace.DescendantAdded:Connect(applyToInstance)
    task.spawn(function(): ()
        for index: number, descendant: Instance in ipairs(workspace:GetDescendants()) do
            if not xrayEnabled then
                return
            end
            applyToInstance(descendant)
            if index % 240 == 0 then
                task.wait()
            end
        end
    end)
end

local highJumpSettings: {velocity: number} = {velocity = 72}

-- High Jump is a one-shot action, not a state.
--
-- Holding it "enabled" made no sense: the whole feature is "press this and
-- jump high". It is now performed once per activation — from the card, from
-- its key slot or from a placed mobile shortcut.
local function performHighJump(): ()
    local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end
    local current: Vector3 = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(
        current.X,
        highJumpSettings.velocity,
        current.Z
    )
    -- Leaving the humanoid in Freefall keeps the landing animation correct.
    if humanoid.FloorMaterial ~= Enum.Material.Air then
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    end
end

local spiderSettings: {climbSpeed: number} = {climbSpeed = 38}
local function toggleSpider(enabled: boolean): ()
    disconnectFeatureConnection("Spider")
    if not enabled then
        return
    end
    featureConnections.Spider = TaskManager:Connect(function(): ()
        local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not character or not humanoid or not root or humanoid.MoveDirection.Magnitude < 0.05 then
            return
        end
        local raycastParams: RaycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = {character}
        local wall: RaycastResult? = workspace:Raycast(
            root.Position,
            humanoid.MoveDirection.Unit * 2.6,
            raycastParams
        )
        if wall and math.abs(wall.Normal.Y) < 0.35 then
            local velocity: Vector3 = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(
                velocity.X,
                spiderSettings.climbSpeed,
                velocity.Z
            )
        end
    end)
end

local safeWalkSettings: {lookAhead: number} = {lookAhead = 2.8}
local function toggleSafeWalk(enabled: boolean): ()
    disconnectFeatureConnection("SafeWalk")
    if not enabled then
        return
    end
    featureConnections.SafeWalk = TaskManager:Connect(function(): ()
        local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not character or not humanoid or not root
            or humanoid.MoveDirection.Magnitude < 0.05
            or humanoid.FloorMaterial == Enum.Material.Air then
            return
        end
        local params: RaycastParams = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {character}
        local probeOrigin: Vector3 = root.Position
            + humanoid.MoveDirection.Unit * safeWalkSettings.lookAhead
        local ground: RaycastResult? = workspace:Raycast(
            probeOrigin,
            Vector3.new(0, -5.2, 0),
            params
        )
        if not ground then
            local velocity: Vector3 = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
        end
    end)
end

local function rejoinCurrentServer(): ()
    local teleportService: TeleportService = cloneReference(
        game:GetService("TeleportService")
    )
    teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end

return {
    toggleXray = toggleXray,
    highJumpSettings = highJumpSettings,
    performHighJump = performHighJump,
    spiderSettings = spiderSettings,
    toggleSpider = toggleSpider,
    safeWalkSettings = safeWalkSettings,
    toggleSafeWalk = toggleSafeWalk,
    rejoinCurrentServer = rejoinCurrentServer,
}
end)()

do
(function(): ()
type ZoomSettings = {
    minDistance: number,
    maxDistance: number,
    unlockFirstPerson: boolean,
}
type ZoomState = {
    minDistance: number,
    maxDistance: number,
    cameraMode: Enum.CameraMode,
}
local zoomSettings: ZoomSettings = {
    minDistance = 0.5,
    maxDistance = 400,
    unlockFirstPerson = true,
}
local originalZoomState: ZoomState? = nil

local function toggleZoomUnlocker(enabled: boolean): ()
    disconnectFeatureConnection("ZoomUnlocker")
    if originalZoomState then
        LocalPlayer.CameraMinZoomDistance = originalZoomState.minDistance
        LocalPlayer.CameraMaxZoomDistance = originalZoomState.maxDistance
        LocalPlayer.CameraMode = originalZoomState.cameraMode
        originalZoomState = nil
    end
    if not enabled then
        return
    end
    originalZoomState = {
        minDistance = LocalPlayer.CameraMinZoomDistance,
        maxDistance = LocalPlayer.CameraMaxZoomDistance,
        cameraMode = LocalPlayer.CameraMode,
    }
    featureConnections.ZoomUnlocker = TaskManager:Connect(function(): ()
        LocalPlayer.CameraMinZoomDistance = math.min(
            zoomSettings.minDistance,
            zoomSettings.maxDistance
        )
        LocalPlayer.CameraMaxZoomDistance = math.max(
            zoomSettings.minDistance,
            zoomSettings.maxDistance
        )
        if zoomSettings.unlockFirstPerson then
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
        elseif originalZoomState then
            LocalPlayer.CameraMode = originalZoomState.cameraMode
        end
    end)
end

state.universalToolkit.zoomSettings = zoomSettings
state.universalToolkit.toggleZoomUnlocker = toggleZoomUnlocker
end)()
end

do
(function(): ()
type InteractionSettings = {
    distance: number,
    instantPrompts: boolean,
    proximityPrompts: boolean,
    clickDetectors: boolean,
}
type PromptState = {distance: number, holdDuration: number}
local interactionSettings: InteractionSettings = {
    distance = 32,
    instantPrompts = false,
    proximityPrompts = true,
    clickDetectors = true,
}
local originalPrompts: {[ProximityPrompt]: PromptState} =
    setmetatable({}, {__mode = "k"}) :: any
local originalClickDetectors: {[ClickDetector]: number} =
    setmetatable({}, {__mode = "k"}) :: any
local interactionExtenderEnabled: boolean = false
local interactionRefreshClock: number = 0

local function refreshInteractionExtender(): ()
    for prompt: ProximityPrompt, original: PromptState in pairs(originalPrompts) do
        if prompt.Parent then
            prompt.MaxActivationDistance = interactionExtenderEnabled
                    and interactionSettings.proximityPrompts
                    and interactionSettings.distance
                or original.distance
            prompt.HoldDuration = interactionExtenderEnabled
                    and interactionSettings.proximityPrompts
                    and interactionSettings.instantPrompts
                    and 0
                or original.holdDuration
        end
    end
    for detector: ClickDetector, originalDistance: number in pairs(originalClickDetectors) do
        if detector.Parent then
            detector.MaxActivationDistance = interactionExtenderEnabled
                    and interactionSettings.clickDetectors
                    and interactionSettings.distance
                or originalDistance
        end
    end
end

local function applyInteractionExtension(instance: Instance): ()
    if not interactionExtenderEnabled then
        return
    end
    if instance:IsA("ProximityPrompt") then
        if originalPrompts[instance] == nil then
            originalPrompts[instance] = {
                distance = instance.MaxActivationDistance,
                holdDuration = instance.HoldDuration,
            }
        end
        local original: PromptState = originalPrompts[instance]
        instance.MaxActivationDistance = interactionSettings.proximityPrompts
                and interactionSettings.distance
            or original.distance
        instance.HoldDuration = interactionSettings.proximityPrompts
                and interactionSettings.instantPrompts
                and 0
            or original.holdDuration
    elseif instance:IsA("ClickDetector") then
        if originalClickDetectors[instance] == nil then
            originalClickDetectors[instance] = instance.MaxActivationDistance
        end
        instance.MaxActivationDistance = interactionSettings.clickDetectors
                and interactionSettings.distance
            or originalClickDetectors[instance]
    end
end

local function restoreInteractionExtender(): ()
    interactionExtenderEnabled = false
    refreshInteractionExtender()
    originalPrompts = setmetatable({}, {__mode = "k"}) :: any
    originalClickDetectors = setmetatable({}, {__mode = "k"}) :: any
end

local function toggleInteractionExtender(enabled: boolean): ()
    disconnectFeatureConnection("InteractExtender")
    disconnectFeatureConnection("InteractExtenderRefresh")
    restoreInteractionExtender()
    interactionRefreshClock = 0
    if not enabled then
        return
    end
    interactionExtenderEnabled = true
    featureConnections.InteractExtender = workspace.DescendantAdded:Connect(
        applyInteractionExtension
    )
    featureConnections.InteractExtenderRefresh = TaskManager:Connect(
        function(deltaTime: number): ()
            interactionRefreshClock += deltaTime
            if interactionRefreshClock >= 0.5 then
                interactionRefreshClock = 0
                refreshInteractionExtender()
            end
        end
    )
    task.spawn(function(): ()
        for index: number, instance: Instance in ipairs(workspace:GetDescendants()) do
            if not interactionExtenderEnabled then
                return
            end
            applyInteractionExtension(instance)
            if index % 240 == 0 then
                task.wait()
            end
        end
    end)
end

state.universalToolkit.interactionSettings = interactionSettings
state.universalToolkit.refreshInteractionExtender = refreshInteractionExtender
state.universalToolkit.toggleInteractionExtender = toggleInteractionExtender
end)()
end

do
(function(): ()
type PhaseDashSettings = {
    mode: string,
    distance: number,
    cooldown: number,
    exitSpeed: number,
    slideSpeed: number,
    collisionPadding: number,
    flashDuration: number,
    preserveVelocity: boolean,
}
local phaseDashSettings: PhaseDashSettings = {
    mode = "Blink",
    distance = 20,
    cooldown = 0.8,
    exitSpeed = 42,
    slideSpeed = 60,
    collisionPadding = 2.25,
    flashDuration = 0.28,
    preserveVelocity = true,
}
local lastPhaseDash: number = -math.huge
local phaseDashEnabled: boolean = false

local function createPhaseFlash(character: Model): ()
    local oldFlash: Instance? = character:FindFirstChild("RTM_PhaseDashFlash")
    if oldFlash then
        oldFlash:Destroy()
    end
    local flash: Highlight = Instance.new("Highlight")
    flash.Name = "RTM_PhaseDashFlash"
    flash.Adornee = character
    flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    flash.FillColor = Theme.AccentViolet
    flash.FillTransparency = 0.42
    flash.OutlineColor = Theme.AccentCyan
    flash.OutlineTransparency = 0.05
    flash.Parent = character
    local fade: Tween = TweenService:Create(
        flash,
        TweenInfo.new(
            math.clamp(phaseDashSettings.flashDuration, 0.05, 1.2),
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        {FillTransparency = 1, OutlineTransparency = 1}
    )
    fade:Play()
    fade.Completed:Once(function(): ()
        if flash.Parent then
            flash:Destroy()
        end
    end)
end

local function performPhaseDash(): ()
    if not phaseDashEnabled then
        return
    end
    local now: number = os.clock()
    if now - lastPhaseDash < phaseDashSettings.cooldown then
        return
    end
    local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
    local camera: Camera? = workspace.CurrentCamera
    if not character or not humanoid or not root or not camera then
        return
    end
    local direction: Vector3 = humanoid.MoveDirection
    if direction.Magnitude < 0.05 then
        direction = Vector3.new(
            camera.CFrame.LookVector.X,
            0,
            camera.CFrame.LookVector.Z
        )
    end
    if direction.Magnitude < 0.05 then
        return
    end
    direction = direction.Unit
    lastPhaseDash = now
    local previousVelocity: Vector3 = root.AssemblyLinearVelocity
    local padding: number = math.clamp(
        phaseDashSettings.collisionPadding,
        0,
        8
    )
    if phaseDashSettings.mode == "Slide" then
        -- Slide: a velocity burst instead of a teleport. No raycast, no wall
        -- stop — the dash pushes the character and the game physics handles
        -- the rest, which keeps the dash usable on uneven terrain.
        root.AssemblyLinearVelocity = direction * phaseDashSettings.slideSpeed
            + Vector3.new(0, previousVelocity.Y, 0)
        createPhaseFlash(character)
        return
    end
    -- Blink: collision-aware teleport along the dash line.
    local params: RaycastParams = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    local collision: RaycastResult? = workspace:Raycast(
        root.Position,
        direction * phaseDashSettings.distance,
        params
    )
    local safeDistance: number = collision
            and math.max(0, collision.Distance - padding)
        or phaseDashSettings.distance
    if safeDistance <= 0.1 then
        return
    end
    root.CFrame = root.CFrame + direction * safeDistance
    if not phaseDashSettings.preserveVelocity then
        root.AssemblyLinearVelocity = direction * phaseDashSettings.exitSpeed
            + Vector3.new(0, previousVelocity.Y, 0)
    end
    createPhaseFlash(character)
end

local function togglePhaseDash(enabled: boolean): ()
    disconnectFeatureConnection("PhaseDash")
    phaseDashEnabled = enabled
    if not enabled then
        return
    end
    -- The dash key is the card's header key slot (see
    -- `state.bindFeatureActivationKey` where the module is declared), so there
    -- is no private input handler and no "Dash key" row in the panel.
end

type SoftLandingSettings = {
    mode: string,
    triggerSpeed: number,
    scanDistance: number,
    landingSpeed: number,
    glideSpeed: number,
    preserveMomentum: boolean,
}
local softLandingSettings: SoftLandingSettings = {
    mode = "Landing",
    triggerSpeed = 62,
    scanDistance = 16,
    landingSpeed = 11,
    glideSpeed = 16,
    preserveMomentum = true,
}

local function toggleSoftLanding(enabled: boolean): ()
    disconnectFeatureConnection("SoftLanding")
    if not enabled then
        return
    end
    featureConnections.SoftLanding = TaskManager:Connect(function(): ()
        local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not character or not humanoid or not root or humanoid.SeatPart then
            return
        end
        local velocity: Vector3 = root.AssemblyLinearVelocity
        if velocity.Y > -softLandingSettings.triggerSpeed then
            return
        end
        local damped: boolean = false
        -- Feather / Auto: cap the fall speed outright, no ground required.
        if softLandingSettings.mode == "Feather"
            or softLandingSettings.mode == "Auto" then
            if velocity.Y < -softLandingSettings.glideSpeed then
                velocity = Vector3.new(
                    velocity.X,
                    -softLandingSettings.glideSpeed,
                    velocity.Z
                )
                damped = true
            end
        end
        -- Landing / Auto: only dampen when ground is actually close.
        if softLandingSettings.mode == "Landing"
            or softLandingSettings.mode == "Auto" then
            local params: RaycastParams = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character}
            local probeDistance: number = math.max(
                softLandingSettings.scanDistance,
                math.abs(velocity.Y) * 0.18
            )
            local ground: RaycastResult? = workspace:Raycast(
                root.Position,
                Vector3.new(0, -probeDistance, 0),
                params
            )
            if ground then
                velocity = Vector3.new(
                    velocity.X,
                    -softLandingSettings.landingSpeed,
                    velocity.Z
                )
                damped = true
            end
        end
        if damped then
            if not softLandingSettings.preserveMomentum then
                velocity = Vector3.new(
                    velocity.X * 0.3,
                    velocity.Y,
                    velocity.Z * 0.3
                )
            end
            root.AssemblyLinearVelocity = velocity
        end
    end)
end

state.universalToolkit.phaseDashSettings = phaseDashSettings
state.universalToolkit.togglePhaseDash = togglePhaseDash
state.universalToolkit.performPhaseDash = performPhaseDash
state.universalToolkit.softLandingSettings = softLandingSettings
state.universalToolkit.toggleSoftLanding = toggleSoftLanding
end)()
end

do
(function(): ()
local FlyFeature = createUniversalFeature(
    "Fly",
    "Preset-based flight with independent vertical control",
    1,
    toggleFly
)
-- Fly is the reference layout for a module customisation panel: grouped under
-- headings, every control carrying a one-line explanation of what it does, and
-- the rarely-touched controls folded away behind a single switch.
local FlyFlightSection: Frame = state.addSectionOption(FlyFeature, "Flight")
local FlyMethodButton: TextButton = addCycleOption(
    FlyFeature,
    "Method",
    {"Velocity", "Constraint", "Impulse", "CFrame", "Blink", "Pulse", "WalkSpeed"},
    1,
    function(value: string): ()
        flySettings.method = value
    end,
    "Sideways engine. Velocity is smooth, CFrame ignores physics, "
        .. "WalkSpeed just runs faster."
)
local FlyFloatButton: TextButton = addCycleOption(
    FlyFeature,
    "Float",
    {"Velocity", "Impulse", "Hover", "Jump", "Bounce", "Floor"},
    1,
    function(value: string): ()
        flySettings.floatMethod = value
    end,
    "What keeps you airborne. Hover locks an altitude, Floor stands you on "
        .. "an invisible part."
)
local FlySpeedRow: Frame = addNumberOption(
    FlyFeature,
    "Horizontal speed",
    flySettings.speed,
    10,
    500,
    function(value: number): ()
        flySettings.speed = value
    end,
    "Studs per second while holding WASD."
)
local FlyVerticalRow: Frame = addNumberOption(
    FlyFeature,
    "Vertical speed",
    flySettings.verticalSpeed,
    10,
    350,
    function(value: number): ()
        flySettings.verticalSpeed = value
    end,
    "Studs per second while rising or descending."
)
local FlyAdvancedButton: TextButton
local FlyAdvancedSection: Frame = state.addSectionOption(FlyFeature, "Advanced")
local FlyResponseRow: Frame = addNumberOption(
    FlyFeature,
    "Response multiplier",
    flySettings.response,
    0.5,
    2,
    function(value: number): ()
        flySettings.response = value
    end,
    "How sharply the flight reacts to input. Higher is twitchier."
)
local FlyBurstRow: Frame = addNumberOption(
    FlyFeature,
    "Burst interval (s)",
    flySettings.burstInterval,
    0.05,
    1,
    function(value: number): ()
        flySettings.burstInterval = value
    end,
    "Cycle length for Blink, Pulse and Bounce. Shorter is smoother."
)
local FlyWallButton: TextButton = addToggleOption(
    FlyFeature,
    "Wall check",
    flySettings.wallCheck,
    function(value: boolean): ()
        flySettings.wallCheck = value
    end,
    "Stop against solid geometry instead of flying through it."
)
local FlyPlatformButton: TextButton = addToggleOption(
    FlyFeature,
    "PlatformStand",
    flySettings.platformStand,
    function(value: boolean): ()
        flySettings.platformStand = value
    end,
    "Ragdoll the character while flying. Smoother, but no animations."
)
local FlyFaceButton: TextButton = addToggleOption(
    FlyFeature,
    "Face camera",
    flySettings.faceCamera,
    function(value: boolean): ()
        flySettings.faceCamera = value
    end,
    "Rotate the character to follow wherever the camera looks."
)
local FlyUpKeyButton: TextButton = addKeyOption(
    FlyFeature,
    "Up key",
    flySettings.upKey,
    function(value: Enum.KeyCode): ()
        flySettings.upKey = value
    end,
    "Hold to gain altitude."
)
local FlyDownKeyButton: TextButton = addKeyOption(
    FlyFeature,
    "Down key",
    flySettings.downKey,
    function(value: Enum.KeyCode): ()
        flySettings.downKey = value
    end,
    "Hold to lose altitude."
)
FlyAdvancedButton = addToggleOption(
    FlyFeature,
    "Advanced settings",
    false,
    function(value: boolean): ()
        -- The heading folds away with the controls it labels.
        setOptionVisible(FlyFeature, FlyAdvancedSection, value)
        setOptionVisible(FlyFeature, FlyResponseRow, value)
        setOptionVisible(FlyFeature, FlyBurstRow, value)
        setOptionVisible(FlyFeature, FlyWallButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyPlatformButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyFaceButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyUpKeyButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyDownKeyButton.Parent :: GuiObject, value)
    end,
    "Reveal response tuning, collision behaviour and key bindings."
)
local FlyMethodRow: GuiObject = FlyMethodButton.Parent :: GuiObject
local FlyFloatRow: GuiObject = FlyFloatButton.Parent :: GuiObject
local FlyAdvancedRow: GuiObject = FlyAdvancedButton.Parent :: GuiObject
-- Explicit order: heading, the everyday controls, the reveal switch, then the
-- advanced heading and its controls (which addToggleOption has already hidden
-- by running its callback with the stored/default `false`).
FlyFlightSection.LayoutOrder = 1
FlyMethodRow.LayoutOrder = 2
FlyFloatRow.LayoutOrder = 3
FlySpeedRow.LayoutOrder = 4
FlyVerticalRow.LayoutOrder = 5
FlyAdvancedRow.LayoutOrder = 6
FlyAdvancedSection.LayoutOrder = 7
FlyResponseRow.LayoutOrder = 8
FlyBurstRow.LayoutOrder = 9
;(FlyWallButton.Parent :: GuiObject).LayoutOrder = 10
;(FlyPlatformButton.Parent :: GuiObject).LayoutOrder = 11
;(FlyFaceButton.Parent :: GuiObject).LayoutOrder = 12
;(FlyUpKeyButton.Parent :: GuiObject).LayoutOrder = 13
;(FlyDownKeyButton.Parent :: GuiObject).LayoutOrder = 14
-- Climbing and descending are holds on a keyboard, so they are holds on a
-- phone too: keep a finger on UP to rise, lift it to level off. They used to
-- latch on tap, which made hovering at a height nearly impossible.
if state.bindMobileActionPlacement then
    state.bindMobileActionPlacement(
        FlyUpKeyButton,
        "UniversalFlyUp",
        "UP",
        function(): () end,
        {
            onPress = function(): ()
                flyTouchVertical = 1
            end,
            onRelease = function(): ()
                if flyTouchVertical == 1 then
                    flyTouchVertical = 0
                end
            end,
        }
    )
    state.bindMobileActionPlacement(
        FlyDownKeyButton,
        "UniversalFlyDown",
        "DOWN",
        function(): () end,
        {
            onPress = function(): ()
                flyTouchVertical = -1
            end,
            onRelease = function(): ()
                if flyTouchVertical == -1 then
                    flyTouchVertical = 0
                end
            end,
        }
    )
end
addFeatureTooltip(
    FlyFeature,
    "Use WASD to move, Space to rise and LeftControl to descend. "
        .. "Method picks how you travel sideways and Float picks what holds "
        .. "you up; if a game blocks one combination, another usually works."
)
end)()
end

do
local FlingFeature = createUniversalFeature(
    "Fling",
    "Fling a player, or the nearest player when blank",
    2,
    function()
        local target = findPlayerByText(universalFlingSettings.target)
        if target then
            performFling(target)
        else
            notify("No matching player was found.")
        end
    end,
    {action = true}
)
addTextOption(FlingFeature, "Target player", universalFlingSettings.target, function(value)
    universalFlingSettings.target = value
end, false)
-- The safety limit used to be a hidden constant, which is why hitting it read
-- like a bug. It is a normal control now.
addNumberOption(
    FlingFeature,
    "Duration (s)",
    universalFlingSettings.duration,
    1,
    20,
    function(value: number): ()
        universalFlingSettings.duration = value
    end
)
addNumberOption(
    FlingFeature,
    "Power",
    universalFlingSettings.power,
    0.25,
    4,
    function(value: number): ()
        universalFlingSettings.power = value
    end
)
addToggleOption(
    FlingFeature,
    "Return to start",
    universalFlingSettings.returnToStart,
    function(value: boolean): ()
        universalFlingSettings.returnToStart = value
    end
)
addFeatureTooltip(
    FlingFeature,
    "Runs until the target goes down or the duration expires, then puts you back."
)
end

do
local HitboxFeature = createUniversalFeature(
    "Hitboxes",
    "Scalable visible and phantom hitboxes for enemy characters",
    3,
    toggleHitboxes
)
addCycleOption(
    HitboxFeature,
    "Mode",
    {"Visible", "Root", "Hybrid"},
    1,
    function(value: string)
        hitboxSettings.mode = value
        refreshHitboxMode()
    end
)
addNumberOption(
    HitboxFeature,
    "Body scale",
    hitboxSettings.bodyScale,
    1,
    5,
    function(value)
        hitboxSettings.bodyScale = value
    end
)
addNumberOption(
    HitboxFeature,
    "Head size",
    hitboxSettings.headSize,
    2,
    12,
    function(value)
        hitboxSettings.headSize = value
    end
)
addNumberOption(
    HitboxFeature,
    "Root size",
    hitboxSettings.rootSize,
    3,
    24,
    function(value)
        hitboxSettings.rootSize = value
    end
)
addNumberOption(
    HitboxFeature,
    "Visible transparency %",
    hitboxSettings.visibleTransparency,
    0,
    60,
    function(value)
        hitboxSettings.visibleTransparency = value
    end
)
addToggleOption(
    HitboxFeature,
    "Reveal parts",
    hitboxSettings.forceVisible,
    function(value)
        hitboxSettings.forceVisible = value
    end
)
addToggleOption(
    HitboxFeature,
    "No collision",
    hitboxSettings.noCollision,
    function(value)
        hitboxSettings.noCollision = value
    end
)
addToggleOption(
    HitboxFeature,
    "Massless",
    hitboxSettings.massless,
    function(value)
        hitboxSettings.massless = value
    end
)
addToggleOption(
    HitboxFeature,
    "Exclude accessories",
    hitboxSettings.excludeAccessories,
    function(value)
        hitboxSettings.excludeAccessories = value
    end
)
addNumberOption(
    HitboxFeature,
    "Update interval (s)",
    hitboxSettings.updateInterval,
    0.03,
    0.5,
    function(value)
        hitboxSettings.updateInterval = value
    end
)
addFeatureTooltip(
    HitboxFeature,
    "Visible scales the body and pins the head; Root expands only the invisible "
        .. "HumanoidRootPart; Hybrid does both. Originals are restored exactly on disable."
)
end

do
local AntiVoidFeature = createUniversalFeature(
    "Anti-Void",
    "Create an invisible rescue platform only when death is imminent",
    4,
    toggleAntiVoid,
    {noOptions = true}
)
addFeatureTooltip(
    AntiVoidFeature,
    "Detects a deep lethal fall and creates a temporary invisible platform beneath you."
)
end

do
local GravityFeature = createUniversalFeature(
    "Gravity",
    "Keep workspace gravity at a custom value",
    5,
    toggleGravity
)
addNumberOption(GravityFeature, "Gravity value", gravitySettings.value, 0, 500, function(value)
    gravitySettings.value = value
end)
end

do
local JumpPowerFeature = createUniversalFeature(
    "Jump Power",
    "Keep character jump power at a custom value",
    6,
    toggleJumpPower
)
addNumberOption(JumpPowerFeature, "Power", jumpPowerSettings.value, 0, 500, function(value)
    jumpPowerSettings.value = value
end)
end

do
local InfiniteJumpFeature = createUniversalFeature(
    "Infinite Jump",
    "Normal, force-based, stacking, hold-to-rise or fall-cancel jumping",
    7,
    toggleInfiniteJump
)
addCycleOption(
    InfiniteJumpFeature,
    "Mode",
    {"Normal", "Impulse", "Stack", "Rise", "Fall"},
    1,
    function(value)
        infiniteJumpSettings.mode = value
    end
)
addNumberOption(
    InfiniteJumpFeature,
    "Jump power",
    infiniteJumpSettings.strength,
    10,
    250,
    function(value)
        infiniteJumpSettings.strength = value
    end
)
addNumberOption(
    InfiniteJumpFeature,
    "Jump interval (s)",
    infiniteJumpSettings.interval,
    0.05,
    0.6,
    function(value)
        infiniteJumpSettings.interval = value
    end
)
addNumberOption(
    InfiniteJumpFeature,
    "Rise speed",
    infiniteJumpSettings.riseSpeed,
    10,
    350,
    function(value)
        infiniteJumpSettings.riseSpeed = value
    end
)
end

do
local WalkSpeedFeature = createUniversalFeature(
    "Walk Speed",
    "Keep character movement speed fixed",
    8,
    toggleWalkSpeed
)
addNumberOption(WalkSpeedFeature, "Speed", walkSpeedSettings.value, 0, 300, function(value)
    walkSpeedSettings.value = value
end)
end

do
(function(): ()
local PhysicsSpeedFeature = createUniversalFeature(
    "Speed",
    "Fast movement for characters and occupied vehicles",
    9,
    togglePhysicsSpeed
)
local SpeedModeButton: TextButton = addCycleOption(
    PhysicsSpeedFeature,
    "Mode",
    {"Adaptive", "Smooth", "Boost", "CFrame", "Pulse", "Teleport"},
    1,
    function(value: string): ()
        physicsSpeedSettings.mode = value
    end
)
local SpeedValueRow: Frame = addNumberOption(
    PhysicsSpeedFeature,
    "Speed",
    physicsSpeedSettings.speed,
    5,
    500,
    function(value: number): ()
        physicsSpeedSettings.speed = value
    end
)
local SpeedVerticalRow: Frame = addNumberOption(
    PhysicsSpeedFeature,
    "Vertical speed",
    physicsSpeedSettings.verticalSpeed,
    0,
    300,
    function(value: number): ()
        physicsSpeedSettings.verticalSpeed = value
    end
)
local SpeedPlatformButton: TextButton = addToggleOption(
    PhysicsSpeedFeature,
    "PlatformStand",
    physicsSpeedSettings.platformStand,
    function(value: boolean): ()
        physicsSpeedSettings.platformStand = value
    end
)
local SpeedMotorRow: Frame = addNumberOption(
    PhysicsSpeedFeature,
    "Motor torque",
    physicsSpeedSettings.motorTorque,
    1000,
    250000,
    function(value: number): ()
        physicsSpeedSettings.motorTorque = value
    end
)
local speedAdvancedVisible: boolean = false
local SpeedCustomButton: TextButton = addToggleOption(
    PhysicsSpeedFeature,
    "Custom properties",
    physicsSpeedSettings.customProperties,
    function(value: boolean): ()
        physicsSpeedSettings.customProperties = value
        setOptionVisible(
            PhysicsSpeedFeature,
            SpeedMotorRow,
            speedAdvancedVisible and value
        )
        if not value then
            restorePhysicsMotors()
        end
    end
)
local SpeedWallButton: TextButton = addToggleOption(
    PhysicsSpeedFeature,
    "Wall check",
    physicsSpeedSettings.wallCheck,
    function(value: boolean): ()
        physicsSpeedSettings.wallCheck = value
    end
)
local SpeedDynamics: any = {}
SpeedDynamics.acceleration = addNumberOption(
    PhysicsSpeedFeature,
    "Acceleration",
    physicsSpeedSettings.acceleration,
    1,
    40,
    function(value: number): ()
        physicsSpeedSettings.acceleration = value
    end
)
SpeedDynamics.burstInterval = addNumberOption(
    PhysicsSpeedFeature,
    "Burst interval (s)",
    physicsSpeedSettings.burstInterval,
    0.05,
    1,
    function(value: number): ()
        physicsSpeedSettings.burstInterval = value
    end
)
SpeedDynamics.airControl = addNumberOption(
    PhysicsSpeedFeature,
    "Air control %",
    physicsSpeedSettings.airControl * 100,
    10,
    150,
    function(value: number): ()
        physicsSpeedSettings.airControl = value / 100
    end
)
SpeedDynamics.sprintMultiplier = addNumberOption(
    PhysicsSpeedFeature,
    "Sprint multiplier",
    physicsSpeedSettings.sprintMultiplier,
    1,
    4,
    function(value: number): ()
        physicsSpeedSettings.sprintMultiplier = value
    end
)
SpeedDynamics.sprintKey = addKeyOption(
    PhysicsSpeedFeature,
    "Sprint key",
    physicsSpeedSettings.sprintKey,
    function(value: Enum.KeyCode): ()
        physicsSpeedSettings.sprintKey = value
    end
)
-- Sprint is a hold, so its mobile button is a hold too: tap the row's key
-- slot to place it, then keep a finger on it to sprint.
if state.bindMobileActionPlacement then
    state.bindMobileActionPlacement(
        SpeedDynamics.sprintKey,
        "UniversalSpeedSprint",
        "SPRINT",
        function(): () end,
        {
            onPress = function(): ()
                state.speedSprintHeld = true
            end,
            onRelease = function(): ()
                state.speedSprintHeld = false
            end,
        }
    )
end
SpeedDynamics.preserveMomentum = addToggleOption(
    PhysicsSpeedFeature,
    "Preserve momentum",
    physicsSpeedSettings.preserveMomentum,
    function(value: boolean): ()
        physicsSpeedSettings.preserveMomentum = value
    end
)
local SpeedJumpRow: Frame = addNumberOption(
    PhysicsSpeedFeature,
    "Auto-jump velocity",
    physicsSpeedSettings.jumpVelocity,
    20,
    120,
    function(value: number): ()
        physicsSpeedSettings.jumpVelocity = value
    end
)
local SpeedAutoJumpButton: TextButton = addToggleOption(
    PhysicsSpeedFeature,
    "Auto jump",
    physicsSpeedSettings.autoJump,
    function(value: boolean): ()
        physicsSpeedSettings.autoJump = value
        setOptionVisible(
            PhysicsSpeedFeature,
            SpeedJumpRow,
            speedAdvancedVisible and value
        )
    end
)
local SpeedAdvancedButton: TextButton = addToggleOption(
    PhysicsSpeedFeature,
    "Advanced settings",
    false,
    function(value: boolean): ()
        speedAdvancedVisible = value
        setOptionVisible(PhysicsSpeedFeature, SpeedVerticalRow, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedPlatformButton.Parent :: GuiObject, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedCustomButton.Parent :: GuiObject, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedMotorRow, value and physicsSpeedSettings.customProperties)
        setOptionVisible(PhysicsSpeedFeature, SpeedWallButton.Parent :: GuiObject, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.acceleration, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.burstInterval, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.airControl, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.sprintMultiplier, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.sprintKey.Parent :: GuiObject, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedDynamics.preserveMomentum.Parent :: GuiObject, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedAutoJumpButton.Parent :: GuiObject, value)
        setOptionVisible(PhysicsSpeedFeature, SpeedJumpRow, value and physicsSpeedSettings.autoJump)
    end
)
local SpeedModeRow: GuiObject = SpeedModeButton.Parent :: GuiObject
local SpeedAdvancedRow: GuiObject = SpeedAdvancedButton.Parent :: GuiObject
SpeedModeRow.LayoutOrder = 1
SpeedValueRow.LayoutOrder = 2
SpeedAdvancedRow.LayoutOrder = 3
addFeatureTooltip(
    PhysicsSpeedFeature,
    "Adaptive changes air authority and retains flow, Smooth accelerates predictably, "
        .. "Boost uses physical impulse, CFrame moves the character without touching its "
        .. "velocity, Pulse alternates bursts with a normal walk, and Teleport advances in "
        .. "short steps. Sprint, momentum, wall safety, auto-jump and vehicle tuning are "
        .. "independently configurable."
)
end)()
end

do
local FovFeature = createUniversalFeature(
    "FOV",
    "Keep the camera field of view fixed",
    10,
    toggleFov
)
addNumberOption(FovFeature, "Field of view", fovSettings.value, 20, 120, function(value)
    fovSettings.value = value
end)
end

do
local NoclipFeature = createUniversalFeature(
    "Noclip",
    "Disable character collisions",
    11,
    toggleNoclip,
    {noOptions = true}
)
addFeatureTooltip(NoclipFeature, "Disables collisions for every local character part. "
    .. "Original collision states are restored when turned off.")
end

do
local AntiAfkFeature = createUniversalFeature(
    "Anti-AFK",
    "Prevent the local idle event from disconnecting",
    13,
    toggleAntiAfk,
    {noOptions = true}
)
addFeatureTooltip(AntiAfkFeature, "Responds only to Roblox's local idle event and "
    .. "disconnects immediately when disabled.")
end

do
local AntiFlingFeature = createUniversalFeature(
    "Anti-Fling",
    "Stop extreme local velocity and return to safety",
    14,
    toggleAntiFling
)
addNumberOption(
    AntiFlingFeature,
    "Velocity limit",
    antiFlingSettings.velocityLimit,
    40,
    1000,
    function(value)
        antiFlingSettings.velocityLimit = value
    end
)
end

do
local FullbrightFeature = createUniversalFeature(
    "Fullbright",
    "Keep the scene bright and remove global shadows",
    15,
    state.toggleFullbright
)
addNumberOption(
    FullbrightFeature,
    "Brightness",
    state.fullbrightSettings.brightness,
    0,
    10,
    function(value)
        state.fullbrightSettings.brightness = value
    end
)
addNumberOption(
    FullbrightFeature,
    "Clock time",
    state.fullbrightSettings.clockTime,
    0,
    24,
    function(value)
        state.fullbrightSettings.clockTime = value
    end
)
end

do
local LagSwitchFeature = createUniversalFeature(
    "Lag Switch",
    "Simulate extreme incoming replication delay",
    16,
    toggleLagSwitch
)
addNumberOption(
    LagSwitchFeature,
    "Incoming lag",
    lagSwitchSettings.incomingLag,
    1,
    999,
    function(value)
        lagSwitchSettings.incomingLag = value
    end
)
end

do
createUniversalFeature(
    "X-Ray",
    "Fade map geometry locally while keeping your character clear",
    18,
    state.universalToolkit.toggleXray,
    {noOptions = true}
)
end

do
local HighJumpFeature = createUniversalFeature(
    "High Jump",
    "Press the key slot to launch a single high jump",
    19,
    state.universalToolkit.performHighJump,
    {action = true, silentAction = true}
)
addNumberOption(
    HighJumpFeature,
    "Jump velocity",
    state.universalToolkit.highJumpSettings.velocity,
    25,
    220,
    function(value: number): ()
        state.universalToolkit.highJumpSettings.velocity = value
    end
)
end

do
local SpiderFeature = createUniversalFeature(
    "Spider",
    "Climb a wall automatically while moving into it",
    20,
    state.universalToolkit.toggleSpider
)
addNumberOption(
    SpiderFeature,
    "Climb speed",
    state.universalToolkit.spiderSettings.climbSpeed,
    10,
    120,
    function(value: number): ()
        state.universalToolkit.spiderSettings.climbSpeed = value
    end
)
end

do
local SafeWalkFeature = createUniversalFeature(
    "Safe Walk",
    "Stop horizontal movement before walking over an edge",
    21,
    state.universalToolkit.toggleSafeWalk
)
addNumberOption(
    SafeWalkFeature,
    "Edge look-ahead",
    state.universalToolkit.safeWalkSettings.lookAhead,
    1.5,
    6,
    function(value: number): ()
        state.universalToolkit.safeWalkSettings.lookAhead = value
    end
)
end

do
createUniversalFeature(
    "Rejoin Server",
    "Reconnect to the current server instance",
    22,
    state.universalToolkit.rejoinCurrentServer,
    {action = true, noOptions = true}
)
end

-- Improve FPS.
--
-- Moved out of the MM2 module: stripping textures, particles, shadows and
-- materials has nothing to do with Murder Mystery 2, and every game benefits.
-- Every change is cached and restored exactly when the module is switched off.
do
-- Wrapped in its own function scope: `bootstrap()` sits at Luau's 200
-- local-register ceiling, and a plain `do` block would still allocate from
-- the same pool.
(function(): ()
local fpsSettings: {[string]: boolean} = {
    textures = true,
    particles = true,
    shadows = true,
    materials = false,
}
local fpsModeEnabled: boolean = false
local fpsVisualCache: any = setmetatable({}, {__mode = "k"})

local function cacheFpsProperty(object: any, property: string): ()
    local data: any = fpsVisualCache[object]
    if not data then
        data = {}
        fpsVisualCache[object] = data
    end
    if data[property] == nil then
        data[property] = object[property]
    end
end

local function applyFpsObject(object: Instance): ()
    local target: any = object
    if fpsSettings.textures and (object:IsA("Decal") or object:IsA("Texture")) then
        cacheFpsProperty(object, "Transparency")
        target.Transparency = 1
    elseif fpsSettings.textures and object:IsA("MeshPart") then
        cacheFpsProperty(object, "TextureID")
        target.TextureID = ""
    end

    if fpsSettings.particles
        and (object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("Smoke")
            or object:IsA("Fire")
            or object:IsA("Sparkles")) then
        cacheFpsProperty(object, "Enabled")
        target.Enabled = false
    end

    if object:IsA("BasePart") then
        if fpsSettings.shadows then
            cacheFpsProperty(object, "CastShadow")
            object.CastShadow = false
        end
        if fpsSettings.materials then
            cacheFpsProperty(object, "Material")
            cacheFpsProperty(object, "Reflectance")
            object.Material = Enum.Material.SmoothPlastic
            object.Reflectance = 0
        end
    end
end

local function restoreFpsObjects(): ()
    for object: any, properties: any in pairs(fpsVisualCache) do
        if object and object.Parent then
            for property: string, value: any in pairs(properties) do
                pcall(function(): ()
                    object[property] = value
                end)
            end
        end
    end
    fpsVisualCache = setmetatable({}, {__mode = "k"})
end

local function toggleImproveFps(enabled: boolean): ()
    fpsModeEnabled = enabled
    disconnectFeatureConnection("ImproveFPS")
    restoreFpsObjects()

    if not enabled then
        return
    end

    -- The initial sweep is chunked so a large map cannot freeze the client.
    task.spawn(function(): ()
        for index: number, object: Instance in ipairs(workspace:GetDescendants()) do
            if not fpsModeEnabled then
                return
            end
            pcall(applyFpsObject, object)
            if index % 250 == 0 then
                task.wait()
            end
        end
    end)
    featureConnections.ImproveFPS = workspace.DescendantAdded:Connect(
        function(object: Instance): ()
            if fpsModeEnabled then
                pcall(applyFpsObject, object)
            end
        end
    )
end
state.toggleImproveFps = toggleImproveFps

local function refreshFps(): ()
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end
local FpsFeature: any = createUniversalFeature(
    "Improve FPS",
    "Apply only the selected reversible optimizations",
    26,
    toggleImproveFps
)
addToggleOption(FpsFeature, "Remove textures", true, function(value: boolean): ()
    fpsSettings.textures = value
    refreshFps()
end)
addToggleOption(FpsFeature, "Disable particles", true, function(value: boolean): ()
    fpsSettings.particles = value
    refreshFps()
end)
addToggleOption(FpsFeature, "Disable shadows", true, function(value: boolean): ()
    fpsSettings.shadows = value
    refreshFps()
end)
addToggleOption(FpsFeature, "Simple materials", false, function(value: boolean): ()
    fpsSettings.materials = value
    refreshFps()
end)
end)()
end

do
local ZoomFeature = createUniversalFeature(
    "Zoom Unlocker",
    "Extend camera zoom and optionally leave forced first person",
    23,
    state.universalToolkit.toggleZoomUnlocker
)
addNumberOption(
    ZoomFeature,
    "Maximum distance",
    state.universalToolkit.zoomSettings.maxDistance,
    25,
    2000,
    function(value: number): ()
        state.universalToolkit.zoomSettings.maxDistance = value
    end
)
addNumberOption(
    ZoomFeature,
    "Minimum distance",
    state.universalToolkit.zoomSettings.minDistance,
    0.5,
    50,
    function(value: number): ()
        state.universalToolkit.zoomSettings.minDistance = value
    end
)
addToggleOption(
    ZoomFeature,
    "Unlock forced first person",
    state.universalToolkit.zoomSettings.unlockFirstPerson,
    function(value: boolean): ()
        state.universalToolkit.zoomSettings.unlockFirstPerson = value
    end
)
end

do
local InteractFeature = createUniversalFeature(
    "Interact Extender",
    "Extend prompt and click interaction range without auto-firing",
    24,
    state.universalToolkit.toggleInteractionExtender
)
addNumberOption(
    InteractFeature,
    "Interaction distance",
    state.universalToolkit.interactionSettings.distance,
    8,
    250,
    function(value: number): ()
        state.universalToolkit.interactionSettings.distance = value
        state.universalToolkit.refreshInteractionExtender()
    end
)
addToggleOption(
    InteractFeature,
    "Instant prompts",
    state.universalToolkit.interactionSettings.instantPrompts,
    function(value: boolean): ()
        state.universalToolkit.interactionSettings.instantPrompts = value
        state.universalToolkit.refreshInteractionExtender()
    end
)
addToggleOption(
    InteractFeature,
    "Proximity prompts",
    state.universalToolkit.interactionSettings.proximityPrompts,
    function(value: boolean): ()
        state.universalToolkit.interactionSettings.proximityPrompts = value
        state.universalToolkit.refreshInteractionExtender()
    end
)
addToggleOption(
    InteractFeature,
    "Click detectors",
    state.universalToolkit.interactionSettings.clickDetectors,
    function(value: boolean): ()
        state.universalToolkit.interactionSettings.clickDetectors = value
        state.universalToolkit.refreshInteractionExtender()
    end
)
end

do
local PhaseDashFeature = createUniversalFeature(
    "Phase Dash",
    "Directional dash: collision-aware blink or a velocity slide",
    25,
    state.universalToolkit.togglePhaseDash
)
addCycleOption(
    PhaseDashFeature,
    "Mode",
    {"Blink", "Slide"},
    1,
    function(value: string): ()
        state.universalToolkit.phaseDashSettings.mode = value
    end
)
addNumberOption(
    PhaseDashFeature,
    "Dash distance",
    state.universalToolkit.phaseDashSettings.distance,
    4,
    80,
    function(value: number): ()
        state.universalToolkit.phaseDashSettings.distance = value
    end
)
addNumberOption(
    PhaseDashFeature,
    "Cooldown",
    state.universalToolkit.phaseDashSettings.cooldown,
    0.1,
    5,
    function(value: number): ()
        state.universalToolkit.phaseDashSettings.cooldown = value
    end
)
addNumberOption(
    PhaseDashFeature,
    "Exit speed",
    state.universalToolkit.phaseDashSettings.exitSpeed,
    0,
    180,
    function(value: number): ()
        state.universalToolkit.phaseDashSettings.exitSpeed = value
    end
)
addNumberOption(
    PhaseDashFeature,
    "Slide speed",
    state.universalToolkit.phaseDashSettings.slideSpeed,
    20,
    250,
    function(value: number): ()
        state.universalToolkit.phaseDashSettings.slideSpeed = value
    end
)
addNumberOption(
    PhaseDashFeature,
    "Collision padding",
    state.universalToolkit.phaseDashSettings.collisionPadding,
    0,
    8,
    function(value: number): ()
        state.universalToolkit.phaseDashSettings.collisionPadding = value
    end
)
addNumberOption(
    PhaseDashFeature,
    "Flash duration (s)",
    state.universalToolkit.phaseDashSettings.flashDuration,
    0.05,
    1.2,
    function(value: number): ()
        state.universalToolkit.phaseDashSettings.flashDuration = value
    end
)
addToggleOption(
    PhaseDashFeature,
    "Preserve velocity",
    state.universalToolkit.phaseDashSettings.preserveVelocity,
    function(value: boolean): ()
        state.universalToolkit.phaseDashSettings.preserveVelocity = value
    end
)
-- The dash key is the card's own key slot, not an option row: one module, one
-- keybind, in the place every other module keeps it. It starts blank like
-- every other slot — the module used to arrive pre-bound to Q for no reason
-- the player could see. On touch, tapping the slot places a DASH button.
state.bindFeatureActivationKey(
    PhaseDashFeature,
    nil,
    state.universalToolkit.performPhaseDash
)
end

do
local SoftLandingFeature = createUniversalFeature(
    "Soft Landing",
    "Dampen dangerous falls near ground or glide the whole descent",
    26,
    state.universalToolkit.toggleSoftLanding
)
addCycleOption(
    SoftLandingFeature,
    "Mode",
    {"Landing", "Feather", "Auto"},
    1,
    function(value: string): ()
        state.universalToolkit.softLandingSettings.mode = value
    end
)
addNumberOption(
    SoftLandingFeature,
    "Trigger fall speed",
    state.universalToolkit.softLandingSettings.triggerSpeed,
    25,
    180,
    function(value: number): ()
        state.universalToolkit.softLandingSettings.triggerSpeed = value
    end
)
addNumberOption(
    SoftLandingFeature,
    "Ground scan distance",
    state.universalToolkit.softLandingSettings.scanDistance,
    5,
    50,
    function(value: number): ()
        state.universalToolkit.softLandingSettings.scanDistance = value
    end
)
addNumberOption(
    SoftLandingFeature,
    "Landing speed",
    state.universalToolkit.softLandingSettings.landingSpeed,
    2,
    35,
    function(value: number): ()
        state.universalToolkit.softLandingSettings.landingSpeed = value
    end
)
addNumberOption(
    SoftLandingFeature,
    "Glide speed",
    state.universalToolkit.softLandingSettings.glideSpeed,
    8,
    40,
    function(value: number): ()
        state.universalToolkit.softLandingSettings.glideSpeed = value
    end
)
addToggleOption(
    SoftLandingFeature,
    "Preserve momentum",
    state.universalToolkit.softLandingSettings.preserveMomentum,
    function(value: boolean): ()
        state.universalToolkit.softLandingSettings.preserveMomentum = value
    end
)
end

do
local ProjectileCalibrationFeature: any = createUniversalFeature(
    "Projectile Calibration",
    "Automatic per-game projectile analytics with tunable ping buckets",
    17,
    function(_enabled: boolean): () end,
    {category = true}
)
state.projectileSettings =
    state.universalProjectileCalibration.settings
addNumberOption(
    ProjectileCalibrationFeature,
    "Bucket width (ms)",
    state.projectileSettings.bucketWidthMs,
    1,
    25,
    function(value: number): ()
        state.projectileSettings.bucketWidthMs = math.round(value)
    end
)
addNumberOption(
    ProjectileCalibrationFeature,
    "Bucket ceiling (ms)",
    state.projectileSettings.maxBucketMs,
    25,
    500,
    function(value: number): ()
        state.projectileSettings.maxBucketMs = math.round(value)
    end
)
addNumberOption(
    ProjectileCalibrationFeature,
    "Sample window (s)",
    state.projectileSettings.sampleWindowSeconds,
    1,
    6,
    function(value: number): ()
        state.projectileSettings.sampleWindowSeconds = value
    end
)
addNumberOption(
    ProjectileCalibrationFeature,
    "Max samples / track",
    state.projectileSettings.maxSamplesPerTrack,
    30,
    600,
    function(value: number): ()
        state.projectileSettings.maxSamplesPerTrack = math.round(value)
    end
)
addNumberOption(
    ProjectileCalibrationFeature,
    "Match radius (studs)",
    state.projectileSettings.matchDistanceStuds,
    10,
    120,
    function(value: number): ()
        state.projectileSettings.matchDistanceStuds = math.round(value)
    end
)
addNumberOption(
    ProjectileCalibrationFeature,
    "Min projectile speed",
    state.projectileSettings.minProjectileSpeed,
    1,
    100,
    function(value: number): ()
        state.projectileSettings.minProjectileSpeed = math.round(value)
    end
)
addActionOption(ProjectileCalibrationFeature, "Show status", function(): ()
    notify(state.universalProjectileCalibration:status())
end)
addActionOption(ProjectileCalibrationFeature, "Save analytics", function(): ()
    if state.universalProjectileCalibration:save("manual") then
        notify("Universal projectile analytics saved in the executor workspace.")
    else
        notify("Universal projectile analytics could not be saved; check F9.")
    end
end)
addActionOption(ProjectileCalibrationFeature, "Delete analytics", function(): ()
    if state.universalProjectileCalibration:delete() then
        notify("Universal projectile analytics deleted for this PlaceId.")
    else
        notify("Universal projectile analytics could not be deleted; check F9.")
    end
end)
addInformationOption(
    ProjectileCalibrationFeature,
    "Runs automatically. Save writes the current session; Delete clears it. MM2 prediction never consumes this dataset."
)
end

end

local function createPageScroll(page, name)
    local scroll = create("ScrollingFrame", {
        Parent = page,
        Name = name,
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = Theme.DefaultOutline,
        ScrollBarThickness = 6,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Size = UDim2.fromScale(1, 1),
    })

    create("UIPadding", {
        Parent = scroll,
        PaddingBottom = UDim.new(0, 18),
        PaddingLeft = UDim.new(0, 18),
        PaddingRight = UDim.new(0, 18),
        PaddingTop = UDim.new(0, 18),
    })

    create("UIListLayout", {
        Parent = scroll,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    return scroll
end

local MovementScroll = createPageScroll(MovementPage, "MovementScroll")
local MM2Scroll = createPageScroll(MM2Page, "MM2Scroll")

local freezeSettings = {mode = "Anchor"}
local originalFreezeState = setmetatable({}, {__mode = "k"})

local function restoreFreezeMovements()
    for humanoid, original in pairs(originalFreezeState) do
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = original.walkSpeed
            humanoid.JumpPower = original.jumpPower
            humanoid.AutoRotate = original.autoRotate
            if original.root and original.root.Parent then
                original.root.Anchored = original.rootAnchored
            end
        end
    end
    originalFreezeState = setmetatable({}, {__mode = "k"})
end

local function toggleFreezeMovements(enabled)
    disconnectFeatureConnection("FreezeMovements")
    restoreFreezeMovements()

    if not enabled then
        return
    end

    featureConnections.FreezeMovements = TaskManager:Connect(function()
        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
            return
        end

        if not originalFreezeState[humanoid] then
            originalFreezeState[humanoid] = {
                walkSpeed = humanoid.WalkSpeed,
                jumpPower = humanoid.JumpPower,
                autoRotate = humanoid.AutoRotate,
                root = root,
                rootAnchored = root.Anchored,
            }
        end

        local original = originalFreezeState[humanoid]
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.AutoRotate = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.Anchored = freezeSettings.mode == "Anchor"
            and true
            or original.rootAnchored
    end)
end

local FreezeFeature = createUniversalFeature(
    "Freeze Movements",
    "Prevent the local character from moving",
    1,
    toggleFreezeMovements,
    {
        parent = MovementScroll,
        registry = movementFeatures,
    }
)
addCycleOption(
    FreezeFeature,
    "Freeze mode",
    {"Anchor", "Humanoid"},
    1,
    function(value)
        freezeSettings.mode = value
    end
)
addInformationOption(
    FreezeFeature,
    "Anchor stops all physics; Humanoid only blocks character controls."
)

local cleanupMM2Runtime = function() end

type GameModule = {
    Name: string,
    PlaceId: number,
    Events: {[string]: any},
    Initialized: boolean,
    init: (runtime: any) -> any,
    destroy: () -> (),
}

type ModuleDiagnostics = {
    uiBindings: number,
    taskBindings: number,
}

state.logBootstrap = function(message: string): ()
    print("[RTM:Bootstrap] " .. message)
end

state.logBootstrapError = function(message: string): ()
    warn("[RTM:Bootstrap] " .. message)
end

local function createGameModuleEnvironment(
    diagnostics: ModuleDiagnostics
): any
    local baseEnvironment: any = getfenv()
    local function recordBinding(callback: (...any) -> any): (...any) -> any
        return function(...: any): any
            diagnostics.uiBindings += 1
            return callback(...)
        end
    end
    local environment: any = {
        game = game,
        workspace = workspace,
        Players = Players,
        UserInputService = UserInputService,
        TweenService = TweenService,
        Lighting = Lighting,
        RunService = RunService,
        HttpService = HttpService,
        CollectionService = CollectionService,
        Stats = Stats,
        LocalPlayer = LocalPlayer,
        PlayerGui = PlayerGui,
        ScreenGui = ScreenGui,
        Theme = Theme,
        -- Game modules ask this whether they are running on the real place or
        -- on a recognised clone, instead of comparing PlaceIds themselves.
        GAME_CHECK = GAME_CHECK,
        -- Game modules style their in-world ESP with the menu's own fonts, so
        -- billboards and labels match the interface instead of inventing a
        -- second look.
        CONTROL_FONT = CONTROL_FONT,
        TITLE_FONT = TITLE_FONT,
        THIN_FONT = THIN_FONT,
        DEFAULT_HEADER_COLOR = DEFAULT_HEADER_COLOR,
        DEFAULT_SURFACE_COLOR = DEFAULT_SURFACE_COLOR,
        DEFAULT_BORDER_COLOR = DEFAULT_BORDER_COLOR,
        state = state,
        configData = configData,
        queueConfigSave = queueConfigSave,
        create = create,
        makeTextLabel = makeTextLabel,
        makeButton = makeButton,
        makeTextBox = makeTextBox,
        notify = notify,
        TaskManager = TaskManager,
        featureConnections = featureConnections,
        disconnectFeatureConnection = disconnectFeatureConnection,
        getCharacterParts = getCharacterParts,
        createUniversalFeature = recordBinding(createUniversalFeature),
        addToggleOption = recordBinding(addToggleOption),
        addActionOption = recordBinding(addActionOption),
        addNumberOption = recordBinding(addNumberOption),
        addCycleOption = recordBinding(addCycleOption),
        addKeyOption = recordBinding(addKeyOption),
        addTextOption = recordBinding(addTextOption),
        addColorOption = recordBinding(addColorOption),
        addInformationOption = addInformationOption,
        addSectionOption = state.addSectionOption,
        setOptionVisible = setOptionVisible,
        findPlayerByText = findPlayerByText,
        performFling = performFling,
        MM2Scroll = MM2Scroll,
        mm2Features = mm2Features,
        vdFeatures = state.vdFeatures,
        mvsdFeatures = state.mvsdFeatures,
        allFeatures = allFeatures,
        cleanupMM2Runtime = cleanupMM2Runtime,
    }
    return setmetatable(environment, {
        __index = baseEnvironment,
    })
end

local function loadGameModule(
    placeId: number
): (GameModule?, any, ModuleDiagnostics, string?)
    local executorEnvironment: any = getfenv()
    local diagnostics: ModuleDiagnostics = {
        uiBindings = 0,
        taskBindings = 0,
    }
    if type(executorEnvironment.loadstring) ~= "function"
        or type(executorEnvironment.setfenv) ~= "function" then
        return nil, nil, diagnostics, "El ejecutor no admite loadstring/setfenv"
    end

    local moduleName: string = GAME_MODULES[placeId]
        or ACTIVE_GAME_MODULE
        or tostring(placeId)
    local moduleUrl: string = REPOSITORY_RAW_BASE
        .. "src/games/"
        .. moduleName
        .. ".luau?nocache="
        .. HttpService:GenerateGUID(false)
    state.logBootstrap("Descargando módulo: " .. moduleUrl)
    local downloadSuccess: boolean, source: any = pcall(function(): string
        return (game :: any):HttpGet(moduleUrl, true)
    end)
    if downloadSuccess and type(source) == "string" then
        local candidate: string = string.lower(source)
        if #source < 64
            or string.find(candidate, "404: not found", 1, true)
            or string.find(candidate, "<!doctype html", 1, true)
            or string.find(candidate, "<html", 1, true) then
            warn("[RTM:Bootstrap] Respuesta remota inválida para " .. moduleName)
            downloadSuccess = false
        end
    end
    if not downloadSuccess or type(source) ~= "string" then
        local readFile: any = executorEnvironment.readfile
        local isFile: any = executorEnvironment.isfile
        local localPath: string = "ARandomMenu/src/games/" .. moduleName .. ".luau"
        if type(readFile) == "function"
            and (type(isFile) ~= "function" or isFile(localPath)) then
            local localSuccess: boolean, localSource: any = pcall(readFile, localPath)
            if localSuccess and type(localSource) == "string" then
                source = localSource
                downloadSuccess = true
                warn("[RTM:Bootstrap] HTTP falló; usando fallback local " .. localPath)
            end
        end
    end
    if not downloadSuccess or type(source) ~= "string" then
        return nil, nil, diagnostics, "Fallo HTTP: " .. tostring(source)
    end
    local normalizedSource: string = string.lower(source)
    if #source < 64
        or string.find(normalizedSource, "404: not found", 1, true)
        or string.find(normalizedSource, "<!doctype html", 1, true)
        or string.find(normalizedSource, "<html", 1, true) then
        return nil, nil, diagnostics, "Respuesta vacía, HTML o 404"
    end
    state.logBootstrap("Descarga correcta (" .. tostring(#source) .. " bytes)")

    local chunk: any, compileError: any =
        executorEnvironment.loadstring(
            source,
            "@src/games/" .. moduleName .. ".luau"
        )
    if type(chunk) ~= "function" then
        return nil, nil, diagnostics,
            "Error de compilación: " .. tostring(compileError)
    end

    local moduleEnvironment: any = createGameModuleEnvironment(diagnostics)
    executorEnvironment.setfenv(chunk, moduleEnvironment)
    local runSuccess: boolean, loadedModule: any = pcall(chunk)
    if not runSuccess then
        return nil, nil, diagnostics,
            "Error ejecutando chunk: " .. tostring(loadedModule)
    end
    if type(loadedModule) ~= "table"
        or type(loadedModule.init) ~= "function"
        or type(loadedModule.destroy) ~= "function" then
        return nil, nil, diagnostics, "El módulo no exporta init/destroy"
    end
    return loadedModule :: GameModule, moduleEnvironment, diagnostics, nil
end

local function registerPlaceModule(
    tabName: string,
    placeId: number
): ()
    -- A clone has its own PlaceId, so registration follows the module that
    -- was resolved for this server (by PlaceId, or by fingerprint).
    if game.PlaceId ~= placeId
        and ACTIVE_GAME_MODULE ~= GAME_MODULES[placeId] then
        return
    end

    state.logBootstrap(
        "PlaceId detectado: "
            .. tostring(game.PlaceId)
            .. " · módulo "
            .. tostring(ACTIVE_GAME_MODULE)
            .. " (" .. ACTIVE_GAME_SOURCE .. ")"
    )
    SectionManager.register(tabName, function(): ()
        local loadedModule: GameModule?, _moduleEnvironment: any,
            diagnostics: ModuleDiagnostics, loadError: string? =
            loadGameModule(placeId)
        if not loadedModule then
            state.logBootstrapError(
                "No se pudo cargar " .. tabName .. ": " .. tostring(loadError)
            )
            error(loadError or "No se pudo cargar el módulo")
        end
        local taskCountBefore: number = TaskManager.nextId
        local featureCountBefore: number = #allFeatures
        local connectionsBefore: {[string]: boolean} = {}
        for connectionName: string in pairs(featureConnections) do
            connectionsBefore[connectionName] = true
        end
        local runtime: any = {
            Menu = {
                Root = Main,
                ScreenGui = ScreenGui,
                Pages = pages,
                Components = state.components,
                Notify = notify,
            },
            State = state,
            TaskManager = TaskManager,
            Diagnostics = diagnostics,
        }
        local initialized: boolean, initError: any = pcall(
            loadedModule.init,
            runtime
        )
        if not initialized then
            loadedModule.Initialized = true
            local rolledBack: boolean, rollbackError: any = pcall(
                loadedModule.destroy
            )
            if not rolledBack then
                state.logBootstrapError(
                    tabName .. " rollback falló: " .. tostring(rollbackError)
                )
            end
            for connectionName: string in pairs(featureConnections) do
                if not connectionsBefore[connectionName] then
                    disconnectFeatureConnection(connectionName)
                end
            end
            for taskId: number, scheduled: ScheduledTask in pairs(TaskManager.tasks) do
                if taskId > taskCountBefore then
                    scheduled.handle:Disconnect()
                end
            end
            for index: number = #allFeatures, featureCountBefore + 1, -1 do
                local feature: any = allFeatures[index]
                if feature.enabled then
                    pcall(feature.onToggle, false)
                end
                if feature.registry then
                    feature.registry[feature.name] = nil
                end
                if feature.row and feature.row.Parent then
                    feature.row:Destroy()
                end
                table.remove(allFeatures, index)
                if state.floatingUi and state.floatingUi.unregisterFeature then
                    state.floatingUi.unregisterFeature(feature)
                end
            end
            state.logBootstrapError(tabName .. " init falló: " .. tostring(initError))
            error(initError)
        end
        diagnostics.taskBindings = TaskManager.nextId - taskCountBefore
        state.activeGameModule = loadedModule
        state.logBootstrap(
            tabName
                .. " activo · UI callbacks="
                .. tostring(diagnostics.uiBindings)
                .. " · Task callbacks="
                .. tostring(diagnostics.taskBindings)
        )
        local function destroyModule(): ()
            local destroyed: boolean, destroyError: any = pcall(
                loadedModule.destroy
            )
            if not destroyed then
                state.logBootstrapError(
                    tabName .. " destroy falló: " .. tostring(destroyError)
                )
            end
        end
        if tabName == "MM2" then
            cleanupMM2Runtime = destroyModule
        elseif tabName == "TRS" then
            state.cleanupTRSRuntime = destroyModule
        elseif tabName == "VD" then
            state.cleanupVDRuntime = destroyModule
        elseif tabName == "MVSD" then
            state.cleanupMVSDRuntime = destroyModule
        end
    end)
end

state.logBootstrap(
    "Inicializando PlaceId="
        .. tostring(game.PlaceId)
        .. " · módulo="
        .. tostring(ACTIVE_GAME_MODULE or "Universal")
)

registerPlaceModule("MM2", GAME_CHECK.MM2)
registerPlaceModule("TRS", GAME_CHECK.TRS)
registerPlaceModule("VD", GAME_CHECK.VD)
registerPlaceModule("MVSD", GAME_CHECK.MVSD)

-- ---------------------------------------------------------------------------
-- Module architecture
-- ---------------------------------------------------------------------------
--
-- Everything above this line is the shell: the window, the cards, the option
-- rows, the keybind registry. Everything below is loaded as separate files —
-- a kernel (`src/core/Framework.luau`), shared libraries (`src/library/*`) and
-- one file per module under `src/modules/<Category>/`.
--
-- Splitting it this way is what makes a module a self-contained declaration
-- instead of another thousand lines in a file that is already at Luau's
-- 200-local ceiling: a module file asks the framework for a card, declares its
-- options, and registers its loops through `Module:Loop`, which are torn down
-- automatically when it is switched off.
--
-- The manifest is downloaded first so the file list lives in the repository
-- rather than in this file; if that download fails the embedded copy below is
-- used, and the validation workflow keeps the two in sync.
state.fetchRepositoryChunk = function(path: string): (any, string?)
    local environment: any = getfenv()
    if type(environment.loadstring) ~= "function" then
        return nil, "El ejecutor no admite loadstring"
    end
    local url: string = REPOSITORY_RAW_BASE
        .. path
        .. "?nocache="
        .. HttpService:GenerateGUID(false)
    local downloaded: boolean, source: any = pcall(function(): string
        return (game :: any):HttpGet(url, true)
    end)
    if downloaded and type(source) == "string" then
        local normalized: string = string.lower(source)
        if #source < 32
            or string.find(normalized, "404: not found", 1, true)
            or string.find(normalized, "<!doctype html", 1, true) then
            downloaded = false
        end
    end
    if not downloaded or type(source) ~= "string" then
        -- Executors that mirror the repository locally keep working offline.
        local readFile: any = environment.readfile
        local isFile: any = environment.isfile
        local localPath: string = "ARandomMenu/" .. path
        if type(readFile) == "function"
            and (type(isFile) ~= "function" or isFile(localPath)) then
            local readOk: boolean, localSource: any = pcall(readFile, localPath)
            if readOk and type(localSource) == "string" then
                source = localSource
                downloaded = true
            end
        end
    end
    if not downloaded or type(source) ~= "string" then
        return nil, "Descarga fallida: " .. path
    end
    local chunk: any, compileError: any =
        environment.loadstring(source, "@" .. path)
    if type(chunk) ~= "function" then
        return nil, "Compilación fallida (" .. path .. "): " .. tostring(compileError)
    end
    if type(environment.setfenv) == "function" and state.frameworkEnvironment then
        environment.setfenv(chunk, state.frameworkEnvironment)
    end
    local ran: boolean, result: any = pcall(chunk)
    if not ran then
        return nil, "Ejecución fallida (" .. path .. "): " .. tostring(result)
    end
    return result, nil
end

do
(function(): ()
local diagnostics: ModuleDiagnostics = {uiBindings = 0, taskBindings = 0}
state.frameworkEnvironment = createGameModuleEnvironment(diagnostics)

-- Kept in step with src/core/Manifest.luau by the validation workflow.
local fallbackManifest: any = {
    version = 1,
    core = {"src/core/Framework.luau"},
    libraries = {"src/library/Entity.luau"},
    modules = {
        {
            path = "src/modules/Utility/FriendList.luau",
            name = "Friend List",
            category = "Utility",
        },
        {
            path = "src/modules/Visuals/PlayerESP.luau",
            name = "Player ESP",
            category = "Visuals",
        },
        {
            path = "src/modules/Combat/KillAura.luau",
            name = "Kill Aura",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/TriggerBot.luau",
            name = "TriggerBot",
            category = "Combat",
        },
        {
            path = "src/modules/Movement/ClickTeleport.luau",
            name = "Click Teleport",
            category = "Movement",
        },
    },
}

local manifest: any, manifestError: string? =
    state.fetchRepositoryChunk("src/core/Manifest.luau")
if type(manifest) ~= "table" or type(manifest.modules) ~= "table" then
    if manifestError then
        state.logBootstrapError("Manifest: " .. manifestError)
    end
    manifest = fallbackManifest
end

local loaded: {any} = {}
local function loadPiece(path: string): any?
    local piece: any, failure: string? = state.fetchRepositoryChunk(path)
    if type(piece) ~= "table" or type(piece.init) ~= "function" then
        state.logBootstrapError(
            "Módulo inválido: " .. path .. " · " .. tostring(failure)
        )
        return nil
    end
    return piece
end

local frameworkPiece: any? = loadPiece(manifest.core[1] or "src/core/Framework.luau")
if not frameworkPiece then
    state.logBootstrapError("Framework no disponible; módulos externos omitidos")
    return
end
local frameworkOk: boolean, framework: any = pcall(
    frameworkPiece.init,
    state.frameworkEnvironment
)
if not frameworkOk or type(framework) ~= "table" then
    state.logBootstrapError("Framework init falló: " .. tostring(framework))
    return
end
table.insert(loaded, frameworkPiece)
state.framework = framework

local entityPiece: any? = loadPiece(
    manifest.libraries[1] or "src/library/Entity.luau"
)
local entityLibrary: any = nil
if entityPiece then
    local entityOk: boolean, library: any = pcall(
        entityPiece.init,
        state.frameworkEnvironment
    )
    if entityOk and type(library) == "table" then
        entityLibrary = library
        table.insert(loaded, entityPiece)
    else
        state.logBootstrapError("Entity init falló: " .. tostring(library))
    end
end
state.entityLibrary = entityLibrary

local context: any = {
    framework = framework,
    entity = entityLibrary,
    host = state.frameworkEnvironment,
}
for _, entry: any in ipairs(manifest.modules) do
    local path: string = type(entry) == "table" and entry.path or tostring(entry)
    local piece: any? = loadPiece(path)
    if piece then
        local started: boolean, failure: any = pcall(piece.init, context)
        if started then
            table.insert(loaded, piece)
            state.logBootstrap("Módulo cargado: " .. path)
        else
            state.logBootstrapError(
                "Módulo falló (" .. path .. "): " .. tostring(failure)
            )
        end
    end
end

state.cleanupFrameworkRuntime = function(): ()
    -- Reverse order: modules first, then the libraries they were holding.
    for index: number = #loaded, 1, -1 do
        local piece: any = loaded[index]
        if type(piece.destroy) == "function" then
            pcall(piece.destroy)
        end
    end
    table.clear(loaded)
    state.framework = nil
    state.entityLibrary = nil
end
end)()
end

local noResultsLabels: {[string]: TextLabel} = {}
for sectionName: string, page: GuiObject in pairs(pages) do
    local label: TextLabel = (makeTextLabel(
        page,
        "No modules match your search",
        13
    ) :: any) :: TextLabel
    label.Name = "NoSearchResults"
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.fromScale(0.5, 0.5)
    label.Size = UDim2.new(1, -50, 0, 40)
    label.TextColor3 = Theme.TextMuted
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Visible = false
    label.ZIndex = 90
    noResultsLabels[sectionName] = label
end

local function refreshSearch(): ()
    local query: string = string.lower(tostring(state.searchQuery or ""))
    query = string.match(query, "^%s*(.-)%s*$") or ""
    local sectionMatches: {[string]: number} = {}
    local sectionTotals: {[string]: number} = {}
    for _, feature: any in ipairs(allFeatures) do
        local sectionName: string = feature.sectionName or "Universal"
        sectionTotals[sectionName] = (sectionTotals[sectionName] or 0) + 1
        local searchable: string = feature.searchText
        local matches: boolean = query == ""
            or string.find(searchable, query, 1, true) ~= nil
        feature.row.Visible = matches
        if matches then
            sectionMatches[sectionName] = (sectionMatches[sectionName] or 0) + 1
        end
        if feature.title then
            if query ~= "" and matches and not feature.enabled then
                feature.title.TextColor3 = Theme.AccentCyan
            else
                applyFeaturePresentation(feature, state.guiStyle == "Default")
            end
        end
    end

    for sectionName: string, label: TextLabel in pairs(noResultsLabels) do
        label.Visible = query ~= ""
            and (sectionTotals[sectionName] or 0) > 0
            and (sectionMatches[sectionName] or 0) == 0
    end

    -- Drop the headers of categories the query emptied out.
    if state.refreshCategoryVisibility then
        state.refreshCategoryVisibility()
    end
end
state.refreshSearch = refreshSearch
local searchRefreshToken: number = 0
trackUiConnection(
    state.shells.defaultSearchBox:GetPropertyChangedSignal("Text"):Connect(
        function(): ()
            state.searchQuery = state.shells.defaultSearchBox.Text
            state.shells.searchClear.Visible = state.searchQuery ~= ""
            searchRefreshToken += 1
            local token: number = searchRefreshToken
            task.delay(0.06, function(): ()
                if token == searchRefreshToken then
                    refreshSearch()
                end
            end)
        end
    )
)

local function buildSettings()
state.settingRows = {} :: {Frame}
local SettingsScroll = create("ScrollingFrame", {
    Parent = SettingsPage,
    Name = "SettingsScroll",
    Active = true,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarImageColor3 = Theme.DefaultOutline,
    ScrollBarThickness = 6,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Size = UDim2.fromScale(1, 1),
})
-- Setting rows are label + control across their full width, so this page is
-- never split into two narrow columns no matter how wide the shell gets.
SettingsScroll:SetAttribute("CardGridSingleColumn", true)

create("UIPadding", {
    Parent = SettingsScroll,
    PaddingBottom = UDim.new(0, 18),
    PaddingLeft = UDim.new(0, 18),
    PaddingRight = UDim.new(0, 18),
    PaddingTop = UDim.new(0, 18),
})

local _SettingsLayout = create("UIListLayout", {
    Parent = SettingsScroll,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

-- Settings rows.
--
-- A row is one line: its name, vertically centred on the left, and its
-- control on the right. The explanatory second line every row used to carry
-- was removed — the names say what they do and the descriptions only made the
-- page twice as tall. `descriptionText` is still accepted so every existing
-- call site (and any game module) keeps working; it is simply not rendered.
local function createSettingRow(
    titleText: string,
    _descriptionText: string,
    height: number?
): (Frame, Frame)
    local rowHeight: number = height or math.max(38, state.layout.cardHeight)
    local row = create("Frame", {
        Parent = getFeatureCardParent(SettingsScroll),
        Name = "Setting_" .. titleText:gsub("%W", ""),
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultSurface
            or Theme.Surface,
        BackgroundTransparency = state.guiStyle == "Default" and 0.58 or 0,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -2, 0, rowHeight),
    })

    local title = makeTextLabel(row, titleText, 12)
    title.Name = "SettingTitle"
    title.FontFace = CONTROL_FONT
    title.AnchorPoint = Vector2.new(0, 0.5)
    title.Position = UDim2.new(0, 14, 0.5, 0)
    title.Size = UDim2.new(0.46, -14, 1, 0)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.TextYAlignment = Enum.TextYAlignment.Center

    local control = create("Frame", {
        Parent = row,
        Name = "SettingControl",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 6, 0.5, 0),
        Size = UDim2.new(0.5, -18, 1, -12),
    })

    create("UICorner", {
        Parent = row,
        CornerRadius = cornerRadius(UI_RADIUS.card),
    })
    create("UIStroke", {
        Parent = row,
        Name = "SettingStroke",
        Color = state.guiStyle == "Default"
            and Theme.DefaultOutline
            or Theme.Outline,
        Transparency = state.guiStyle == "Default" and 0.82 or 0.28,
        Thickness = 1,
    })
    table.insert(state.settingRows, row)
    return (row :: any) :: Frame, (control :: any) :: Frame
end

-- Switch-free toggle rows.
--
-- Blur mode and Interface motion used to carry a switch control. They now
-- behave exactly like a module card: the whole row is the button, a click
-- flips it, and the state is read from the row itself (accent stripe, brighter
-- surface and an ON/OFF caption) instead of from a separate widget.
state.settingRowRepaint = setmetatable({}, {__mode = "k"}) :: any

local function makeToggleSettingRow(
    row: Frame,
    _control: Frame,
    enabled: boolean,
    onToggle: (boolean) -> ()
): (state: boolean) -> ()
    row:SetAttribute("ToggleRow", true)
    local title: TextLabel = row:FindFirstChild("SettingTitle") :: TextLabel
    local stripe: Frame = create("Frame", {
        Parent = row,
        Name = "ActiveStripe",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.DefaultAccent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 2, 1, -14),
        ZIndex = 3,
    }) :: Frame
    create("UICorner", {Parent = stripe, CornerRadius = UDim.new(1, 0)})

    local activation: TextButton = create("TextButton", {
        Parent = row,
        Name = "ActivationTarget",
        Active = true,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        ZIndex = 4,
    }) :: TextButton

    local current: boolean = enabled
    local function paint(): ()
        -- Kept in sync from one place: clicks, restyles and external state
        -- changes all end up here.
        row.BackgroundColor3 = current
            and Theme.DefaultSurfaceHover
            or Theme.DefaultSurface
        row.BackgroundTransparency = current and 0.42 or 0.58
        stripe.BackgroundTransparency = current and 0 or 1
        -- No ON/OFF caption: the accent stripe and the lit surface are the
        -- state, exactly like a module card.
        title.TextColor3 = current and Theme.DefaultText or Theme.DefaultTextMuted
    end
    paint()
    state.settingRowRepaint[row] = paint

    trackUiConnection(activation.MouseButton1Click:Connect(function(): ()
        current = not current
        paint()
        onToggle(current)
    end))
    trackUiConnection(row.MouseEnter:Connect(function(): ()
        TweenService:Create(
            row,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = current and 0.34 or 0.46}
        ):Play()
    end))
    trackUiConnection(row.MouseLeave:Connect(function(): ()
        TweenService:Create(
            row,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = current and 0.42 or 0.58}
        ):Play()
    end))

    -- Returned so an external change (a keybind, a teardown) can push the row
    -- back in sync without going through a click.
    return function(nextState: boolean): ()
        current = nextState
        paint()
    end
end

state.restyleSettings = function(isDefault: boolean): ()
    SettingsScroll.ScrollBarImageColor3 = isDefault
        and Theme.DefaultOutline
        or Color3.fromRGB(100, 100, 100)
    for _, row: Frame in ipairs(state.settingRows) do
        -- Click-to-toggle rows paint their own surface from their state; a
        -- restyle must not reset an enabled row back to the idle colour.
        local repaint: any = row:GetAttribute("ToggleRow") == true
            and state.settingRowRepaint
            and state.settingRowRepaint[row]
        if repaint then
            repaint()
        else
            row.BackgroundColor3 = isDefault and Theme.DefaultSurface or Theme.Surface
            row.BackgroundTransparency = isDefault and 0.58 or 0
        end
        local rowStroke: UIStroke? = row:FindFirstChild("SettingStroke") :: UIStroke?
        if rowStroke then
            rowStroke.Color = isDefault and Theme.DefaultOutline or Theme.Outline
            rowStroke.Transparency = isDefault and 0.82 or 0.28
        end
    end
end

local textRow, textControl = createSettingRow(
    "Text size",
    "Drag the linear control to scale every label"
)
textRow.LayoutOrder = 1
local textScaleRatio: number = (state.textScale - TEXT_SCALE_MINIMUM)
    / (TEXT_SCALE_MAXIMUM - TEXT_SCALE_MINIMUM)
local TextSizeTrack: TextButton = create("TextButton", {
    Parent = textControl,
    Name = "TextSizeTrack",
    Active = true,
    AutoButtonColor = false,
    AnchorPoint = Vector2.new(0, 0.5),
    BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultButtonPressed
        or Color3.fromRGB(45, 45, 49),
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0.5, 0),
    Size = UDim2.new(1, -58, 0, 4),
    Text = "",
}) :: TextButton
create("UICorner", {
    Parent = TextSizeTrack,
    CornerRadius = UDim.new(1, 0),
})
local TextSizeFill: Frame = create("Frame", {
    Parent = TextSizeTrack,
    Name = "Fill",
    BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultButtonHover
        or Color3.fromRGB(238, 238, 242),
    BorderSizePixel = 0,
    Size = UDim2.fromScale(textScaleRatio, 1),
}) :: Frame
create("UICorner", {
    Parent = TextSizeFill,
    CornerRadius = UDim.new(1, 0),
})
local TextSizeKnob: Frame = create("Frame", {
    Parent = TextSizeTrack,
    Name = "Knob",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultText
        or Color3.fromRGB(250, 250, 252),
    BorderSizePixel = 0,
    Position = UDim2.fromScale(textScaleRatio, 0.5),
    Size = UDim2.fromOffset(14, 14),
    ZIndex = TextSizeTrack.ZIndex + 2,
}) :: Frame
create("UICorner", {
    Parent = TextSizeKnob,
    CornerRadius = UDim.new(1, 0),
})
create("UIStroke", {
    Parent = TextSizeKnob,
    Color = Theme.DefaultOutline,
    Transparency = 0.55,
    Thickness = 1,
})
local baseRestyleSettings: (boolean) -> () = state.restyleSettings
state.restyleSettings = function(isDefault: boolean): ()
    baseRestyleSettings(isDefault)
    TextSizeTrack.BackgroundColor3 = isDefault
        and Theme.DefaultButtonPressed
        or Color3.fromRGB(45, 45, 49)
    TextSizeFill.BackgroundColor3 = isDefault
        and Theme.DefaultButtonHover
        or Color3.fromRGB(238, 238, 242)
    TextSizeKnob.BackgroundColor3 = isDefault
        and Theme.DefaultText
        or Color3.fromRGB(250, 250, 252)
end
local TextSizeValue: TextLabel = makeTextLabel(
    textControl,
    tostring(math.round(state.textScale * 100)) .. "%",
    11
) :: TextLabel
TextSizeValue.AnchorPoint = Vector2.new(1, 0.5)
TextSizeValue.Position = UDim2.new(1, 0, 0.5, 0)
TextSizeValue.Size = UDim2.fromOffset(48, 22)
TextSizeValue.TextXAlignment = Enum.TextXAlignment.Right

local blurRow, blurControl = createSettingRow(
    "Blur mode",
    "Blur the game while the menu is visible"
)
blurRow.LayoutOrder = 2

-- No switch: the row is the button, exactly like a module card.
local setBlurRowState = makeToggleSettingRow(
    blurRow,
    blurControl,
    state.blurEnabled,
    function(enabled: boolean): ()
        state.blurEnabled = enabled
        state.setBlurVisible(true)
        configData.ui.blurEnabled = enabled
        queueConfigSave()
        notify(enabled and "Blur mode enabled" or "Blur mode disabled")
    end
)
state.setBlurRowState = setBlurRowState

local motionRow, motionControl = createSettingRow(
    "Interface motion",
    "Smooth transitions for cards, tabs, and menu controls"
)
motionRow.LayoutOrder = 3
local setMotionRowState = makeToggleSettingRow(
    motionRow,
    motionControl,
    state.animationsEnabled,
    function(enabled: boolean): ()
        state.animationsEnabled = enabled
        configData.ui.animationsEnabled = enabled
        -- The hail is motion too, so it must follow this row immediately.
        if state.refreshBlurDecoration then
            pcall(state.refreshBlurDecoration)
        end
        queueConfigSave()
        notify(enabled and "Interface motion enabled" or "Interface motion disabled")
    end
)
state.setMotionRowState = setMotionRowState

-- Menu key: keyboard-only. A touch client has no key to bind and reaches the
-- menu through its floating button, so the row is not built there at all.
local keyRow, keyControl = createSettingRow(
    "Menu key",
    "Choose the key used to show or hide"
)
keyRow.LayoutOrder = 4
keyRow.Visible = not UserInputService.TouchEnabled

local KeybindButton = makeButton(keyControl, state.toggleKey.Name, 13)
KeybindButton.Size = UDim2.fromScale(1, 1)
applyKeySlotStyle(KeybindButton)
state.keybindButton = KeybindButton

local reinjectRow, reinjectControl = createSettingRow(
    "Reinject latest",
    "Download and restart the newest main build"
)
reinjectRow.LayoutOrder = 5
local ReinjectButton: TextButton = makeButton(
    reinjectControl,
    "REINJECT LATEST",
    12
)
ReinjectButton.Size = UDim2.fromScale(1, 1)

local destructRow, destructControl = createSettingRow(
    "Destruct",
    "Disable every function and completely remove the menu from this client"
)
destructRow.LayoutOrder = 6
local DestructButton: TextButton = makeButton(
    destructControl,
    "DESTRUCT",
    12
)
DestructButton.Size = UDim2.fromScale(1, 1)

local gameRow, gameControl = createSettingRow(
    "Game check",
    "Only the matching game-specific module is loaded"
)
gameRow.LayoutOrder = 7
-- Shows *how* the game was recognised, which is what tells you a clone was
-- matched by its structure rather than by its PlaceId.
local gameStatus = makeTextLabel(
    gameControl,
    (GAME_CHECK.MM2Active and "MM2"
        or GAME_CHECK.TRSActive and "TRS"
        or GAME_CHECK.VDActive and "VD"
        or GAME_CHECK.MVSDActive and "MVSD"
        or "Universal only")
        .. " · "
        .. (GAME_CHECK.source == "PlaceId"
            and tostring(game.PlaceId)
            or GAME_CHECK.source),
    12
)
gameStatus.TextXAlignment = Enum.TextXAlignment.Center
gameStatus.Size = UDim2.fromScale(1, 1)

-- Mobile action size.
--
-- The only mobile row left. "Mobile menu icon" always said ON - REQUIRED and
-- could not be changed, and "Mobile action buttons" only offered a reset that
-- holding a button already does, so both were noise. The size is a real value
-- now instead of a four-step preset cycle: type it, or drag the slider.
local mobileSizeRow, mobileSizeControl = createSettingRow(
    "Mobile action size",
    "Exact pixel size for placed mobile shortcuts"
)
mobileSizeRow.LayoutOrder = 8
mobileSizeRow.Visible = UserInputService.TouchEnabled

local MobileSizeTrack: TextButton = create("TextButton", {
    Parent = mobileSizeControl,
    Name = "MobileSizeTrack",
    Active = true,
    AutoButtonColor = false,
    AnchorPoint = Vector2.new(0, 0.5),
    BackgroundColor3 = Theme.DefaultButtonPressed,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0.5, 0),
    Size = UDim2.new(1, -62, 0, 4),
    Text = "",
}) :: TextButton
create("UICorner", {Parent = MobileSizeTrack, CornerRadius = UDim.new(1, 0)})
local MobileSizeFill: Frame = create("Frame", {
    Parent = MobileSizeTrack,
    Name = "Fill",
    BackgroundColor3 = Theme.DefaultButtonHover,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(0, 1),
}) :: Frame
create("UICorner", {Parent = MobileSizeFill, CornerRadius = UDim.new(1, 0)})
local MobileSizeKnob: Frame = create("Frame", {
    Parent = MobileSizeTrack,
    Name = "Knob",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Theme.DefaultText,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0, 0.5),
    Size = UDim2.fromOffset(14, 14),
    ZIndex = 3,
}) :: Frame
create("UICorner", {Parent = MobileSizeKnob, CornerRadius = UDim.new(1, 0)})
local MobileSizeInput: TextBox = makeTextBox(
    mobileSizeControl,
    tostring(state.mobileButtonSize)
)
MobileSizeInput.Name = "MobileSizeValue"
MobileSizeInput.AnchorPoint = Vector2.new(1, 0.5)
MobileSizeInput.Position = UDim2.new(1, 0, 0.5, 0)
MobileSizeInput.Size = UDim2.fromOffset(54, 24)
MobileSizeInput.PlaceholderText = "px"

-- Contribute the Settings/overlay-specific side effects to the shared
-- visibility controller instead of replacing it. `state.setMenuVisible` stays
-- the single entry point and always updates the blur, even if this builder
-- never runs.
state.addMenuVisibilityListener(function(visible: boolean): ()
    -- `FloatingUi` is a local of the floating-UI block, so referring to it by
    -- name from this builder resolved to a nil global and the whole listener
    -- threw (silently: visibility listeners are pcall'd). The published
    -- registry is the one that is actually in scope here.
    local floating: any = state.floatingUi
    if type(floating) ~= "table" then
        return
    end
    local textOverlay: any = floating.overlays and floating.overlays.TextGUI
    if textOverlay and textOverlay.window and textOverlay.window.root then
        textOverlay.window.root.Active = visible
    end
    if visible then
        return
    end
    -- The per-overlay settings windows are closed with the menu. They used to
    -- be listed here by name, but those names are locals of the floating-UI
    -- block: from here they resolved to nil globals, so the list was empty and
    -- the windows stayed on screen. The live registry is authoritative.
    local settingsWindows: any = floating.settingsWindows
    if type(settingsWindows) ~= "table" then
        return
    end
    for _, settingsWindow: any in pairs(settingsWindows) do
        if settingsWindow and settingsWindow.root then
            settingsWindow.root.Visible = false
        end
    end
end)

local function updateTextSizes(): ()
    for _, item in ipairs(registeredText) do
        if item.object and item.object.Parent then
            item.object.TextSize = math.round(
                item.normalSize * TEXT_BASE_MULTIPLIER * state.textScale
            )
        end
    end
end

local textSizeDragInput: InputObject? = nil
local function setTextScaleFromX(pointerX: number): ()
    local width: number = math.max(1, TextSizeTrack.AbsoluteSize.X)
    local ratio: number = math.clamp(
        (pointerX - TextSizeTrack.AbsolutePosition.X) / width,
        0,
        1
    )
    state.textScale = math.round((
        TEXT_SCALE_MINIMUM
            + ratio * (TEXT_SCALE_MAXIMUM - TEXT_SCALE_MINIMUM)
    ) * 100) / 100
    TextSizeFill.Size = UDim2.fromScale(ratio, 1)
    TextSizeKnob.Position = UDim2.fromScale(ratio, 0.5)
    TextSizeValue.Text = tostring(math.round(state.textScale * 100)) .. "%"
    updateTextSizes()
    configData.ui.largeText = nil
    configData.ui.textScale = state.textScale
    configData.ui.textScaleCalibrationVersion = 2
    queueConfigSave()
end
trackUiConnection(TextSizeTrack.InputBegan:Connect(function(input: InputObject): ()
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        textSizeDragInput = input
        setTextScaleFromX(input.Position.X)
    end
end))
trackUiConnection(UserInputService.InputChanged:Connect(function(input: InputObject): ()
    if textSizeDragInput == nil then
        return
    end
    if input == textSizeDragInput
        or input.UserInputType == Enum.UserInputType.MouseMovement then
        setTextScaleFromX(input.Position.X)
    end
end))
trackUiConnection(UserInputService.InputEnded:Connect(function(input: InputObject): ()
    if input == textSizeDragInput
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        textSizeDragInput = nil
    end
end))

local reinjectBusy: boolean = false
trackUiConnection(ReinjectButton.MouseButton1Click:Connect(function(): ()
    if reinjectBusy then
        return
    end
    local compiler: any = executorGlobals.loadstring
    if type(compiler) ~= "function" then
        notify("Reinject unavailable: this executor has no loadstring")
        return
    end
    reinjectBusy = true
    ReinjectButton:SetAttribute("Disabled", true)
    ReinjectButton.Text = "DOWNLOADING…"
    local sourceUrls: {string} = {
        REPOSITORY_RAW_BASE .. "ARandomMenu.luau",
        RUNTIME_SAFETY_SOURCE_URL,
    }
    local sourceOrError: any = nil
    local downloaded: boolean = false
    local downloadFailures: {string} = {}
    for _, candidateUrl: string in ipairs(sourceUrls) do
        local requestUrl: string = candidateUrl
            .. "?reinject=v3&nocache="
            .. HttpService:GenerateGUID(false)
        local requestOk: boolean, bodyOrError: any = pcall(function(): string
            return (game :: any):HttpGet(requestUrl, true)
        end)
        local current: boolean = requestOk
            and type(bodyOrError) == "string"
            and #bodyOrError >= 1024
            and bodyOrError:find(RUNTIME_COMPATIBILITY_MARKER, 1, true) ~= nil
        if current then
            downloaded = true
            sourceOrError = bodyOrError
            break
        end
        table.insert(downloadFailures, tostring(bodyOrError))
    end
    if not downloaded then
        reinjectBusy = false
        ReinjectButton:SetAttribute("Disabled", false)
        ReinjectButton.Text = "REINJECT LATEST"
        notify("Could not download the latest build")
        warn("[Random Testing Menu] Reinject download: "
            .. table.concat(downloadFailures, " | "))
        return
    end
    local compiled: any = nil
    local compileError: any = nil
    local compiledOk: boolean, compileResult: any, returnedError: any = pcall(
        compiler,
        sourceOrError,
        "@ARandomMenu.luau"
    )
    if compiledOk then
        compiled = compileResult
        compileError = returnedError
    else
        compileError = compileResult
    end
    if type(compiled) ~= "function" then
        reinjectBusy = false
        ReinjectButton:SetAttribute("Disabled", false)
        ReinjectButton.Text = "REINJECT LATEST"
        notify("The downloaded build could not be compiled")
        warn("[Random Testing Menu] Reinject compile: " .. tostring(compileError))
        return
    end
    ReinjectButton.Text = "RESTARTING…"
    task.defer(function(): ()
        local executed: boolean, executionError: any = xpcall(
            compiled,
            debug.traceback
        )
        if not executed then
            reinjectBusy = false
            if ReinjectButton.Parent then
                ReinjectButton:SetAttribute("Disabled", false)
                ReinjectButton.Text = "REINJECT LATEST"
            end
            warn("[Random Testing Menu] Reinject runtime: " .. tostring(executionError))
        end
    end)
end))

trackUiConnection(DestructButton.MouseButton1Click:Connect(function(): ()
    DestructButton:SetAttribute("Disabled", true)
    DestructButton.Text = "REMOVING…"
    task.defer(function(): ()
        local destruct: any = state.destruct
        if type(destruct) ~= "function" then
            -- The teardown routine is defined at the very end of bootstrap;
            -- if it is somehow missing, remove the interface anyway instead
            -- of leaving the button stuck on "REMOVING…".
            pcall(function(): ()
                ScreenGui:Destroy()
            end)
            return
        end
        local ok: boolean, failure: any = pcall(destruct)
        if not ok then
            warn("[Random Testing Menu] Destruct: " .. tostring(failure))
            pcall(function(): ()
                ScreenGui:Destroy()
            end)
        end
    end)
end))

-- Mobile action size: exact value, from the field or the slider.
do
local MOBILE_SIZE_MINIMUM: number = 28
local MOBILE_SIZE_MAXIMUM: number = 120

local function applyMobileButtonSize(requested: number, persist: boolean): ()
    local size: number = math.clamp(
        math.round(requested),
        MOBILE_SIZE_MINIMUM,
        MOBILE_SIZE_MAXIMUM
    )
    state.mobileButtonSize = size
    configData.ui.mobileButtonSize = size

    local ratio: number = (size - MOBILE_SIZE_MINIMUM)
        / (MOBILE_SIZE_MAXIMUM - MOBILE_SIZE_MINIMUM)
    MobileSizeFill.Size = UDim2.fromScale(ratio, 1)
    MobileSizeKnob.Position = UDim2.fromScale(ratio, 0.5)
    if not MobileSizeInput:IsFocused() then
        MobileSizeInput.Text = tostring(size)
    end

    -- Every placed button follows immediately, and is pulled back on screen
    -- if the new size pushed it past an edge.
    for _, record: MobileActionRecord in pairs(state.mobileUi.actions) do
        record.button.Size = UDim2.fromOffset(size, size)
        local clamped: Vector2 = state.mobileUi.clampButtonPosition(
            Vector2.new(
                record.button.Position.X.Offset,
                record.button.Position.Y.Offset
            ),
            size
        )
        record.button.Position = UDim2.fromOffset(clamped.X, clamped.Y)
        state.mobileUi.saveActionPosition(record)
    end
    if persist then
        queueConfigSave()
    end
end

local function sizeFromPointer(pointerX: number): number
    local width: number = math.max(1, MobileSizeTrack.AbsoluteSize.X)
    local alpha: number = math.clamp(
        (pointerX - MobileSizeTrack.AbsolutePosition.X) / width,
        0,
        1
    )
    return MOBILE_SIZE_MINIMUM
        + alpha * (MOBILE_SIZE_MAXIMUM - MOBILE_SIZE_MINIMUM)
end

local mobileSizeDrag: InputObject? = nil
trackUiConnection(MobileSizeTrack.InputBegan:Connect(function(
    input: InputObject
): ()
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    mobileSizeDrag = input
    applyMobileButtonSize(sizeFromPointer(input.Position.X), false)
end))
trackUiConnection(UserInputService.InputChanged:Connect(function(
    input: InputObject
): ()
    if mobileSizeDrag
        and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
        applyMobileButtonSize(sizeFromPointer(input.Position.X), false)
    end
end))
trackUiConnection(UserInputService.InputEnded:Connect(function(
    input: InputObject
): ()
    if mobileSizeDrag
        and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
        mobileSizeDrag = nil
        applyMobileButtonSize(state.mobileButtonSize, true)
    end
end))

trackUiConnection(MobileSizeInput.FocusLost:Connect(function(): ()
    local parsed: number? = tonumber(MobileSizeInput.Text)
    if parsed == nil then
        MobileSizeInput.Text = tostring(state.mobileButtonSize)
        notify("Mobile action size: enter a number of pixels.")
        return
    end
    applyMobileButtonSize(parsed, true)
    notify("Mobile action size: " .. tostring(state.mobileButtonSize) .. " px")
end))

applyMobileButtonSize(state.mobileButtonSize, false)
end

trackUiConnection(KeybindButton.MouseButton1Click:Connect(function(): ()
    if state.keyCaptureCancel then
        state.keyCaptureCancel()
    end
    state.waitingForKey = true
    KeybindButton.Text = "PRESS A KEY…"
    setKeySlotCapture(KeybindButton, true)
end))

end

SectionManager.register("Config.", buildSettings)

do
local function initializeWindowInput(): ()
-- The shell is fixed.
--
-- There is no drag surface, no pointer bookkeeping and no persisted window
-- geometry any more: `centerMain()` owns the one position the shell can have.
-- Only the free-floating windows (favourites, overlays, per-overlay settings)
-- are still movable, and they carry their own drag handlers.
--
-- A viewport change recomputes the responsive metrics, which re-centres the
-- shell, re-flows the rail/header/cards through the layout listeners and
-- pulls every floating window back inside the new screen bounds.
local function reflowForViewport(force: boolean?): ()
    task.defer(function(): ()
        if not Main.Parent then
            return
        end
        state.refreshLayout(force)
        if state.floatingUi and state.floatingUi.reclamp then
            state.floatingUi.reclamp()
        end
    end)
end

local viewportConnection: RBXScriptConnection? = nil
local function bindViewport(): ()
    if viewportConnection then
        viewportConnection:Disconnect()
        viewportConnection = nil
    end
    local camera: Camera? = workspace.CurrentCamera
    if not camera then
        return
    end
    viewportConnection = trackUiConnection(
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(function(): ()
            reflowForViewport(false)
        end)
    )
end

bindViewport()
-- The camera can be replaced (respawns, cutscenes, some anti-cheats), which
-- would otherwise leave the menu listening to a dead camera and stuck in the
-- mode it started in.
trackUiConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(
    function(): ()
        bindViewport()
        reflowForViewport(true)
    end
))

state.globalInputBeganConnection = UserInputService.InputBegan:Connect(function(input)
    if state.keyCaptureCallback then
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode ~= Enum.KeyCode.Unknown then
            if input.KeyCode == Enum.KeyCode.Escape then
                if state.keyCaptureCancel then
                    state.keyCaptureCancel()
                end
                return
            end
            local callback = state.keyCaptureCallback
            callback(input.KeyCode)
            task.defer(function(): ()
                if state.keyCaptureCallback == callback then
                    state.keyCaptureCallback = nil
                end
            end)
        end
        return
    end

    if state.waitingForKey then
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode ~= Enum.KeyCode.Unknown then
            if input.KeyCode == Enum.KeyCode.Escape then
                state.waitingForKey = false
                if state.keybindButton then
                    state.keybindButton.Text = state.toggleKey.Name
                    setKeySlotCapture(state.keybindButton, false)
                end
                return
            end
            state.toggleKey = input.KeyCode
            if state.keybindButton then
                state.keybindButton.Text = input.KeyCode.Name
                setKeySlotCapture(state.keybindButton, false)
            end
            configData.ui.toggleKey = input.KeyCode.Name
            queueConfigSave()
            notify("Menu key: " .. input.KeyCode.Name)
            task.defer(function(): ()
                state.waitingForKey = false
            end)
        end
        return
    end

    -- Do not depend on gameProcessed here. Some Roblox experiences consume
    -- RightShift before ordinary scripts see it as unprocessed.
    if UserInputService:GetFocusedTextBox() then
        return
    end

    if input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode == state.toggleKey then
        state.setMenuVisible(not state.visible)
    end
end)
end
initializeWindowInput()

-- One forced pass once the whole shell exists, so every listener (rail,
-- header, cards, grids, floating windows) has applied the same metrics table
-- before the intro curtain lifts.
task.defer(function(): ()
    state.refreshLayout(true)
end)
end

local runtimeCleaned: boolean = false
-- Teardown.
--
-- Every step runs inside its own `pcall`. The previous version was one long
-- unprotected block, so a single failing step (a module cleanup, a stale
-- connection, a toolkit that never finished initializing) aborted the rest of
-- the teardown *and* the `ScreenGui:Destroy()` that follows it — which is
-- exactly how Destruct could leave the menu on screen stuck on "REMOVING…".
-- Now a failure is logged and the teardown carries on.
local function cleanupStep(label: string, step: () -> ()): ()
    local ok: boolean, failure: any = pcall(step)
    if not ok then
        warn("[Random Testing Menu] destruct/" .. label .. ": " .. tostring(failure))
    end
end

local function cleanupRuntime(): ()
    if runtimeCleaned then
        return
    end
    runtimeCleaned = true

    cleanupStep("session", function(): ()
        if type(state.destroySessionTracking) == "function" then
            state.destroySessionTracking()
        end
        state.sessionInfo = nil
        state.getOverlayTarget = nil
    end)

    -- Disabling the features is what actually removes the effects from the
    -- game (flight, ESP, lighting, hitboxes...), so each module is isolated:
    -- one module that throws while switching off cannot keep the others on.
    for _, feature in ipairs(allFeatures) do
        if feature.enabled then
            cleanupStep("feature " .. tostring(feature.name), function(): ()
                feature.onToggle(false)
            end)
            feature.enabled = false
        end
    end

    cleanupStep("held keybinds", function(): ()
        for _, binding: any in pairs(state.shortcutBindings) do
            if binding.hold and binding.pressed and binding.onRelease then
                binding.pressed = false
                binding.onRelease()
            end
        end
        table.clear(state.shortcutBindings)
    end)
    cleanupStep("feature connections", function(): ()
        for name in pairs(featureConnections) do
            disconnectFeatureConnection(name)
        end
    end)
    cleanupStep("tooltips", function(): ()
        for _, connection: RBXScriptConnection in ipairs(state.tooltipConnections) do
            connection:Disconnect()
        end
        table.clear(state.tooltipConnections)
    end)
    cleanupStep("ui connections", function(): ()
        for _, connection: RBXScriptConnection in ipairs(state.uiConnections) do
            connection:Disconnect()
        end
        table.clear(state.uiConnections)
    end)
    cleanupStep("projectile calibration", function(): ()
        local calibration: any = state.universalProjectileCalibration
        if calibration and type(calibration.destroy) == "function" then
            calibration:destroy()
        end
    end)
    cleanupStep("task manager", function(): ()
        TaskManager:Destroy()
    end)
    cleanupStep("global input", function(): ()
        for _, key: string in ipairs({
            "globalInputChangedConnection",
            "globalInputEndedConnection",
            "globalInputBeganConnection",
            "globalShortcutBeganConnection",
            "globalShortcutEndedConnection",
        }) do
            local connection: any = state[key]
            if connection then
                connection:Disconnect()
                state[key] = nil
            end
        end
    end)
    cleanupStep("colour picker", function(): ()
        if colorPicker.inputChanged then
            colorPicker.inputChanged:Disconnect()
        end
        if colorPicker.inputEnded then
            colorPicker.inputEnded:Disconnect()
        end
    end)
    cleanupStep("MM2 runtime", cleanupMM2Runtime)
    for _, key: string in ipairs({
        "cleanupFrameworkRuntime",
        "cleanupTRSRuntime",
        "cleanupVDRuntime",
        "cleanupMVSDRuntime",
    }) do
        local cleanup: any = state[key]
        if type(cleanup) == "function" then
            cleanupStep(key, cleanup)
        end
    end
    cleanupStep("config", saveConfigNow)

    -- Always release the blur, even if it was mid-tween.
    cleanupStep("blur", function(): ()
        suspendBlur()
        if state.destroyBlurDecoration then
            state.destroyBlurDecoration()
        end
        if Blur.Parent then
            Blur:Destroy()
        end
    end)

    state.destructed = true
end

-- The GUI is destroyed even when a cleanup step failed: an interface the user
-- asked to remove must always disappear.
state.destruct = function(): ()
    cleanupStep("runtime", cleanupRuntime)
    cleanupStep("screen gui", function(): ()
        if ScreenGui.Parent then
            ScreenGui:Destroy()
        end
    end)
    -- Belt and braces: anything the runtime parented straight into PlayerGui
    -- under the shared name (an older injection, a re-parented shell) goes too.
    cleanupStep("leftovers", function(): ()
        for _, child: Instance in ipairs(PlayerGui:GetChildren()) do
            if child.Name == GUI_NAME then
                child:Destroy()
            end
        end
        local lighting: Instance? = Lighting:FindFirstChild(BLUR_NAME)
        if lighting then
            lighting:Destroy()
        end
    end)
    print("[Random Testing Menu] Destruct complete.")
end

ScreenGui.AncestryChanged:Connect(function(_: Instance, parent: Instance?): ()
    if not parent then
        cleanupRuntime()
    end
end)

SectionManager.initializeAllAsync()
setTab("Universal")
-- Sync the blur with the initial menu state (the argument is "animate", not
-- the target state) so it matches state.visible instead of being forced off.
state.setBlurVisible(false)
task.defer(saveConfigNow)

print(
    "A Random Menu | Toggle key: "
        .. state.toggleKey.Name
)
end

local initialized: boolean, bootstrapError: any = xpcall(bootstrap, function(message: any): string
    local text: string = tostring(message)
    if debug and type(debug.traceback) == "function" then
        return debug.traceback("[RTM:Bootstrap] " .. text, 2)
    end
    return "[RTM:Bootstrap] " .. text
end)

if not initialized then
    bootstrapFailed = true
    if bootstrapStatusLabel and bootstrapStatusLabel.Parent then
        bootstrapStatusLabel.Text = "Initialization error — check executor console"
        bootstrapStatusLabel.TextColor3 = Color3.fromRGB(230, 105, 105)
    end
    warn("[RTM:Bootstrap] Inicialización detenida:\n" .. tostring(bootstrapError))
end
