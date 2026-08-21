--!strict
--[[
    Wurst
    An unofficial Roblox port of the Minecraft Wurst Client.
    Standalone, client-sided Roblox GUI.

    Default controls:
      - RightShift: show/hide the menu

    The shell itself is fixed: it is always centred on the screen and its size
    comes from the responsive metrics table (Mobile / Tablet / Desktop). Only
    the floating tool windows and the HUD overlays can be moved.
]]

-- Raised by the xpcall handler at the bottom of the file. The loading intro
-- reads it so its scripted narration and its watchdog never overwrite or hide
-- the initialization error message.
local RUNTIME_COMPATIBILITY_MARKER: string =
    "Initialization error — check executor console"
local RUNTIME_SAFETY_SOURCE_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/4b10e4bfe00aa356afb3e0420a72e745327f6259/ARandomMenu.luau"

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
    ["No Fall"] = "Protection",

    -- Utility
    ["Anti-AFK"] = "Utility",
    ["Fling"] = "Utility",
    ["Gravity"] = "Utility",
    ["Improve FPS"] = "Utility",
    ["Interact Extender"] = "Utility",
    ["Lag Switch"] = "Utility",
    ["Rejoin Server"] = "Utility",

    -- Everything a game module adds is filed here too.
    --
    -- A game module used to get a page of its own, so its cards never needed a
    -- category and every one of them landed in the catch-all. They are modules
    -- like any other now — BedFight's Server Aura is a combat module, its
    -- Scaffold is a movement module — so the taxonomy names them here, in one
    -- table, instead of asking five game files to describe themselves.

    -- MM2
    ["Instant Role Notify"] = "Utility",
    ["Shoot"] = "Combat",
    ["Trajectory Calibration"] = "Combat",
    ["Knife"] = "Combat",
    ["Loop All Interact"] = "Utility",
    ["Silence"] = "Utility",
    ["Auto Play ID"] = "Utility",
    ["Sprint"] = "Movement",
    ["Always Show Timer"] = "Visuals",
    ["Teleport"] = "Movement",
    ["Role Fling"] = "Utility",
    ["Hide Names"] = "Protection",

    -- TRS
    ["Auto Tackle"] = "Combat",
    ["Auto Dribble"] = "Combat",
    ["Auto Pickup"] = "Utility",
    ["Pass Assist"] = "Combat",
    ["Shoot Assist"] = "Combat",
    ["Power Shot"] = "Combat",
    ["Large Shoot"] = "Combat",
    ["Best Goal Visual"] = "Visuals",
    ["Ball Trajectory"] = "Visuals",
    ["Goalkeeper Assist"] = "Combat",
    ["Auto Header"] = "Combat",

    -- VD
    ["Auto Generator"] = "Utility",
    ["Auto Parry / Auto Block"] = "Protection",
    ["Killer Hit Aura"] = "Combat",
    ["Fast Vault Optimizer"] = "Movement",
    ["Cooldown Modifier"] = "Utility",
    ["Damage Boost"] = "Movement",
    ["Noclip (Vaults & Pallets)"] = "Movement",
    ["WalkSpeed Hack"] = "Movement",
    ["Silent Steps / Anti-Sound"] = "Protection",
    ["Killer Proximity Visualizer"] = "Visuals",
    ["Line of Sight ESP"] = "Visuals",
    ["Locker & Hideout Detector"] = "Visuals",
    ["Killer Power Cooldowns"] = "Visuals",
    ["VD Field of View"] = "Visuals",
    ["Optimize Blind / Flash Protection"] = "Protection",
    ["VD Fullbright"] = "Visuals",

    -- MVSD (its ESP is an option of the universal one now)
    ["Silent Aim"] = "Combat",
    ["Auto Shoot"] = "Combat",
    ["Trigger Opportunity"] = "Visuals",

    -- BedFight (beds and generators are options of the universal ESP)
    ["Round Info"] = "Visuals",
    ["Auto Swing"] = "Combat",
    ["Bed Nuker"] = "Combat",
    ["Scaffold"] = "Movement",
    ["Anti Void"] = "Protection",
    ["Server Aura"] = "Combat",
    ["Server Scaffold"] = "Movement",
    ["Server Miner"] = "Utility",
    ["Auto Buy"] = "Utility",
    ["Quick Actions"] = "Utility",
}

-- Height reserved at the foot of the navigation rail for the player card.
local PROFILE_CARD_HEIGHT: number = 62

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
-- needs. All four are drawn in the interface's own greys — a coloured chip per
-- kind turned the board into a paint chart.
--
--   toggle  a square that fills when the module is on.
--   action  a chevron: press it and it goes.
--   hold    two upright bars: live only while a finger is on the key.
--   group   three stacked rules: a container of settings, always running.


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
-- The Universal tab wears the icon of the game you are actually in — the one
-- place a game's identity still shows in the rail now that games do not own
-- tabs. 0 means "this place".
local TAB_GAME_ICONS: {[string]: number} = {
    Universal = 0,
}

-- Drawn icons for the rail entries that are not a game. Spoof keeps its
-- monogram: there is no glyph for "what the server is told about you" that
-- reads at 22px, and inventing one would be worse than two letters.
local TAB_DRAWN_ICONS: {[string]: string} = {
    -- The settings page is registered as "Config.", dot included; keying this
    -- table on "Settings" is why the gear never appeared.
    ["Config."] = "navSettings",
}

-- Sidebar monograms.
--
-- The navigation rail collapses to icons on small viewports, so every tab
-- carries a two-character monogram that is legible at 22px. Plain ASCII on
-- purpose: a glyph font would have to be downloaded and could fail to load.
local TAB_MONOGRAMS: {[string]: string} = {
    ["Universal"] = "UN",
    ["Spoof"] = "SP",
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
-- Vape's shell is closer to a terminal than to a phone app: small radii, hard
-- edges, and contrast carried by the fill rather than by soft corners. These
-- are the four radii the whole interface is built from.
local UI_RADIUS: {[string]: number} = {
    shell = 8,
    panel = 5,
    card = 4,
    control = 3,
    chip = 3,
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

-- Content stamp of every file packed into runtime/bundle.luau. Written by
-- `tools/bundle.py`; the gate fails if it drifts from the sources. Used as
-- `?v=` so the CDN and the executor can cache a URL that still changes the
-- moment the content does.
local SOURCE_STAMP: string = "73c30170e989eed1"
-- The clock starts here, when the bootstrap chunk begins running.
--
-- It used to start inside the module loader, which is near the *end* of the
-- work: it reported a third of a second while the player watched the window
-- being built for however long that takes. Everything between these two
-- points is now the "gui" phase.
local BOOT_STARTED_AT: number = os.clock()
local BOOT_FINGERPRINT_SECONDS: number = 0
local PENDING_FINGERPRINT: boolean = false

-- The product's own name, in one place.
--
-- Everything a player reads — the wordmark, the log prefix, the notification
-- title — comes from here, so the next rename is one line and not a hundred
-- and twenty.
--
-- Three names deliberately do *not* follow it. `guiName`, `blurName` and
-- `storageFolder` are not branding: the first two are the instance names a
-- game can enumerate under CoreGui and Lighting, so naming them after the
-- product would announce the menu to anything scanning for it, and the third
-- is a folder on disk that already holds every existing player's saved
-- configs. Renaming it would silently orphan all of them.
local PRODUCT = {
    name = "Wurst",
    version = "2.1",
    -- Prefixes every console line as `[Wurst:Bootstrap]` and friends.
    logPrefix = "Wurst",
    guiName = "RandomTestingMenu0001",
    blurName = "RandomTestingMenu0001Blur",
    storageFolder = "RandomTestingMenu0001",
}


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

local GUI_NAME = PRODUCT.guiName
local BLUR_NAME = PRODUCT.blurName
local CONFIG_FOLDER = PRODUCT.storageFolder
local CONFIG_PROFILE_FOLDER = CONFIG_FOLDER .. "/Profiles"
local CONFIG_FILE = CONFIG_PROFILE_FOLDER
    .. "/Game_"
    .. tostring(game.GameId > 0 and game.GameId or game.PlaceId)
    .. ".Config"
local REPOSITORY_RAW_BASE = RUNTIME_RAW_BASE

local GAME_MODULES: {[number]: string} = {
    [71480482338212] = "BedFight",
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
PENDING_FINGERPRINT = ACTIVE_GAME_MODULE == nil
if not ACTIVE_GAME_MODULE then
    -- One look, no wait. A clone that has already replicated is recognised
    -- here; one that is still streaming is picked up later, off the path that
    -- builds the window. Waiting three seconds for markers that never arrive
    -- was a blank screen in every game that is not one of the five PlaceIds.
    local fingerprintAt: number = os.clock()
    local detected: string?, score: number = detectGameModuleByStructure()
    BOOT_FINGERPRINT_SECONDS = os.clock() - fingerprintAt
    if detected then
        ACTIVE_GAME_MODULE = detected
        ACTIVE_GAME_SOURCE = "fingerprint " .. tostring(score) .. " markers"
        PENDING_FINGERPRINT = false
    end
end

local GAME_CHECK = {
    MM2 = 142823291,
    BedFight = 71480482338212,
    TRS = 14315258385,
    VD = 93978595733734,
    MVSD = 135856908115931,
    MM2Active = ACTIVE_GAME_MODULE == "MM2",
    TRSActive = ACTIVE_GAME_MODULE == "TRS",
    VDActive = ACTIVE_GAME_MODULE == "VD",
    MVSDActive = ACTIVE_GAME_MODULE == "MVSD",
    BedFightActive = ACTIVE_GAME_MODULE == "BedFight",
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
-- Colour tokens.
--
-- One set, not two. There used to be `Surface` and `DefaultSurface`, `Text` and
-- `DefaultText`, `Outline` and `DefaultOutline` — leftovers from a second GUI
-- style that no longer exists. Half the menu read one set and half read the
-- other, so changing a colour either had to be done twice or only took in half
-- the window.
--
-- The defaults are the Wurst Client's own: background #404040, accent #101010,
-- text #F0F0F0. The magenta most Wurst screenshots show is a theme its user
-- picked, not what the client ships with.
--
-- `accent` paints chrome — title bars, borders, slider fills. `enabled` paints
-- a module that is on. They are two tokens rather than one because Wurst
-- separates them too, and for the same reason: filling every enabled row with
-- the colour that already paints eight title bars is unreadable.
export type ThemeShape = {
    opacity: number,
    tooltipOpacity: number,
    radius: number,
    rowHeight: number,
    borderThickness: number,
    maxHeight: number,
    scale: number,
}

local THEME_PRESETS: {[string]: {[string]: Color3}} = {
    -- What Wurst looks like out of the box.
    Wurst = {
        background = Color3.fromRGB(64, 64, 64),
        sidebar = Color3.fromRGB(48, 48, 48),
        surface = Color3.fromRGB(64, 64, 64),
        surfaceRaised = Color3.fromRGB(74, 74, 74),
        surfaceHover = Color3.fromRGB(86, 86, 86),
        surfacePressed = Color3.fromRGB(96, 96, 96),
        button = Color3.fromRGB(56, 56, 56),
        buttonHover = Color3.fromRGB(72, 72, 72),
        buttonPressed = Color3.fromRGB(84, 84, 84),
        outline = Color3.fromRGB(16, 16, 16),
        accent = Color3.fromRGB(16, 16, 16),
        accentDim = Color3.fromRGB(36, 36, 36),
        accentFaint = Color3.fromRGB(56, 56, 56),
        accentSoft = Color3.fromRGB(40, 40, 40),
        accentText = Color3.fromRGB(240, 240, 240),
        -- Green at half alpha over #404040 is what a Wurst player actually
        -- sees on an enabled hack; the token is that result, because our rows
        -- are drawn opaque.
        enabled = Color3.fromRGB(32, 175, 32),
        enabledText = Color3.fromRGB(240, 240, 240),
        text = Color3.fromRGB(240, 240, 240),
        textMuted = Color3.fromRGB(168, 168, 168),
        tooltip = Color3.fromRGB(24, 24, 24),
    },
    -- The palette this menu shipped with before the port.
    Monochrome = {
        background = Color3.fromRGB(8, 8, 9),
        sidebar = Color3.fromRGB(13, 13, 14),
        surface = Color3.fromRGB(26, 26, 28),
        surfaceRaised = Color3.fromRGB(32, 32, 35),
        surfaceHover = Color3.fromRGB(40, 40, 44),
        surfacePressed = Color3.fromRGB(48, 48, 52),
        button = Color3.fromRGB(32, 32, 35),
        buttonHover = Color3.fromRGB(46, 46, 50),
        buttonPressed = Color3.fromRGB(56, 56, 61),
        outline = Color3.fromRGB(92, 92, 98),
        accent = Color3.fromRGB(236, 236, 238),
        accentDim = Color3.fromRGB(196, 196, 202),
        accentFaint = Color3.fromRGB(160, 160, 168),
        accentSoft = Color3.fromRGB(52, 52, 56),
        accentText = Color3.fromRGB(8, 8, 9),
        enabled = Color3.fromRGB(236, 236, 238),
        enabledText = Color3.fromRGB(8, 8, 9),
        text = Color3.fromRGB(245, 245, 247),
        textMuted = Color3.fromRGB(158, 158, 166),
        tooltip = Color3.fromRGB(16, 16, 18),
    },
}

-- Read by every widget. Mutated in place by `ThemeEngine.Apply`, never
-- replaced, because half the menu captured a reference to it at build time.
local Theme: {[string]: Color3} = {}
for token: string, value: Color3 in pairs(THEME_PRESETS.Wurst) do
    Theme[token] = value
end
-- Semantic colours are not theme tokens and no preset may set them. They label
-- game data — health, a failure, a role — and a theme that recolours "murderer"
-- is a theme that lies.
Theme.positive = Color3.fromRGB(126, 196, 138)
Theme.negative = Color3.fromRGB(214, 106, 106)

local ThemeEngine = {
    name = "Wurst",
    presets = THEME_PRESETS,
    tokens = Theme,
    shape = {
        opacity = 0.86,
        tooltipOpacity = 0.95,
        radius = 4,
        rowHeight = 22,
        borderThickness = 1,
        maxHeight = 340,
        scale = 1,
    } :: ThemeShape,
}

-- Instance -> list of {property, token}. Weak keys, so a window that is
-- destroyed stops being repainted without anything having to unregister it.
local themeBindings: any = setmetatable({}, {__mode = "k"})
local themeListeners: {(string) -> ()} = {}

-- A widget that reads `Theme.surface` once and copies it into a property is
-- painted for the life of that instance. Binding instead records the intent, so
-- switching preset repaints what is already on screen.
function ThemeEngine.Bind(
    instance: Instance,
    property: string,
    token: string
): Instance
    local record: any = themeBindings[instance]
    if not record then
        record = {}
        themeBindings[instance] = record
    end
    table.insert(record, {property = property, token = token})
    local value: Color3? = Theme[token]
    if value then
        (instance :: any)[property] = value
    end
    return instance
end

function ThemeEngine.OnChange(callback: (string) -> ()): ()
    table.insert(themeListeners, callback)
end

function ThemeEngine.Apply(name: string): boolean
    local preset: {[string]: Color3}? = THEME_PRESETS[name]
    if not preset then
        return false
    end
    for token: string, value: Color3 in pairs(preset :: {[string]: Color3}) do
        Theme[token] = value
    end
    ThemeEngine.name = name
    for instance: any, record: any in pairs(themeBindings) do
        for _, binding: any in ipairs(record) do
            local value: Color3? = Theme[binding.token]
            if value then
                -- One dead instance must not stop the repaint of every
                -- instance after it in the table.
                pcall(function(): ()
                    instance[binding.property] = value
                end)
            end
        end
    end
    for _, listener: (string) -> () in ipairs(themeListeners) do
        pcall(listener, name)
    end
    return true
end

local DEFAULT_HEADER_COLOR: Color3 = Theme.text
local DEFAULT_MENU_COLOR: Color3 = Theme.background
local DEFAULT_SURFACE_COLOR: Color3 = Theme.surface
local DEFAULT_BORDER_COLOR: Color3 = Theme.outline

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

-- `state` is the one table every downloaded file reads the menu through.
--
-- Note the ordering: it does not exist yet where the game is detected above,
-- so `activeGameName` is published a few lines below this table rather than
-- beside the detection. Writing it there assigned a *global* named `state`,
-- which is nil to everything that matters.
local state: any = {
    -- The shell starts hidden. There is no intro to watch while the menu
    -- builds itself, so the launcher appearing is the signal that it is ready
    -- — press it and the window is already complete.
    visible = false,
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
-- The *name* of the recognised game. `state.activeGameModule` is already
-- taken, by the loaded module table itself, and reusing the key would have
-- meant one of the two silently winning.
state.activeGameName = ACTIVE_GAME_MODULE
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
            warn("[" .. PRODUCT.name .. "] layout listener: " .. tostring(failure))
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

-- Opening and closing the window.
--
-- It used to appear and disappear on a boolean, which reads as a glitch rather
-- than as a window: nothing tells the eye where it came from. It scales in
-- from 96% with a slight overshoot instead — the same gesture the other menus
-- in this account use for their panels, and short enough (0.17s) that it never
-- gets in the way of a player who is toggling it mid-fight. Closing is faster
-- than opening, because waiting to hide something is worse than waiting to see
-- it, and the frame is only hidden once the tween has finished so the shrink
-- is actually visible.
--
-- `Animations` in Config. turns the whole thing off, in which case this is the
-- boolean it always was.
local menuScaleToken: number = 0
local function setMenuVisibleCore(visible: boolean): ()
    state.visible = visible
    local frame: Frame? = state.mainFrame
    local scale: UIScale? = state.mainScale
    menuScaleToken += 1
    local token: number = menuScaleToken
    if frame and scale and state.animationsEnabled then
        if visible then
            (scale :: UIScale).Scale = 0.96;
            (frame :: Frame).Visible = true
            TweenService:Create(
                scale :: UIScale,
                TweenInfo.new(0.17, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                {Scale = 1}
            ):Play()
        else
            TweenService:Create(
                scale :: UIScale,
                TweenInfo.new(0.11, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
                {Scale = 0.955}
            ):Play()
            task.delay(0.12, function(): ()
                -- A newer toggle may have re-opened the window in the meantime.
                if token == menuScaleToken and not state.visible and frame.Parent then
                    (frame :: Frame).Visible = false
                end
            end)
        end
    elseif frame then
        if scale then
            (scale :: UIScale).Scale = 1
        end
        (frame :: Frame).Visible = visible
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
        -- Monocraft: a Minecraft-shaped OFL font, kept in the repository so
        -- the picker has one pixel face that is not a Roblox built-in.
        minecraftFont = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Typography/Monocraft.otf",
            fileName = "monocraft-v1.otf",
            fallback = "",
            version = 1,
            assetType = "font/otf",
        },
        brandLogo = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Brand/menu-logo.jpg",
            fileName = "brand-logo-v1.jpg",
            fallback = "",
            version = 1,
            assetType = "image/jpeg",
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
        print("[" .. PRODUCT.logPrefix .. ":Assets] caché no reutilizable: " .. tostring(cacheError))
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
            "[" .. PRODUCT.logPrefix .. ":Assets] fuente fallback para "
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
            "[" .. PRODUCT.logPrefix .. ":Assets] Font.new fallback para "
                .. logicalName
                .. ": "
                .. tostring(fontFace)
        )
        return fallbackFont
    end
    print("[" .. PRODUCT.logPrefix .. ":Assets] fuente cargada: " .. logicalName)
    return fontFace
end

    VALVE_FONT = AssetManager.resolveFont(
        "valveFont",
        CONTROL_FONT,
        Enum.FontWeight.Bold,
        Enum.FontStyle.Normal
    )

-- Resolving an image means a download, a file write and a getcustomasset
-- call, so it happens off the bootstrap thread and the caller keeps whatever
-- it was already showing until the id arrives.
-- Interface fonts.
--
-- Everything the menu draws goes through three faces — a bold one for titles,
-- a semibold one for controls and a regular one for body text — and all three
-- are built from one family, so choosing a font here re-skins the whole
-- interface without touching a single call site.
state.customFontAssets = {
    ["Minecraft (Monocraft)"] = "minecraftFont",
    ["Candy Fruits"] = "candyFont",
    ["Valve"] = "valveFont",
}

state.listInterfaceFonts = function(): {string}
    local names: {string} = {"Menu default"}
    -- Read from the engine rather than a hard-coded list: a client with newer
    -- faces should offer them, and one with fewer should not lie about them.
    for _, item: EnumItem in ipairs(Enum.Font:GetEnumItems()) do
        if item ~= Enum.Font.Unknown then
            table.insert(names, item.Name)
        end
    end
    for name: string in pairs(state.customFontAssets) do
        table.insert(names, name)
    end
    table.sort(names, function(first: string, second: string): boolean
        if first == "Menu default" then
            return true
        end
        if second == "Menu default" then
            return false
        end
        return first < second
    end)
    return names
end

state.resolveInterfaceFont = function(name: string): Font?
    if name == "Menu default" then
        return Font.new(
            "rbxasset://fonts/families/BuilderSans.json",
            Enum.FontWeight.Regular,
            Enum.FontStyle.Normal
        )
    end
    local customAsset: string? = state.customFontAssets[name]
    if customAsset then
        -- Downloaded, cached and turned into an asset id by the same path the
        -- decorative fonts already use; falls back to the current face.
        return AssetManager.resolveFont(
            customAsset,
            CONTROL_FONT,
            Enum.FontWeight.Regular,
            Enum.FontStyle.Normal
        )
    end
    local enumOk: boolean, enumItem: any = pcall(function(): any
        return (Enum.Font :: any)[name]
    end)
    if not enumOk or typeof(enumItem) ~= "EnumItem" then
        return nil
    end
    local fontOk: boolean, face: any = pcall(Font.fromEnum, enumItem)
    if not fontOk then
        return nil
    end
    return face :: Font
end

state.applyInterfaceFont = function(name: string, persist: boolean?): ()
    local base: Font? = state.resolveInterfaceFont(name)
    if not base then
        return
    end
    local resolvedBase: Font = base :: Font
    local family: string = resolvedBase.Family
    local style: Enum.FontStyle = resolvedBase.Style
    -- A Roblox family is a JSON manifest listing one file per weight; a font
    -- the repository ships is a single file with a single weight (Monocraft is
    -- Regular 400 and nothing else). Asking such a file for Bold gets you
    -- either a synthetic smear or nothing at all, so single-file faces are used
    -- at the one weight they have and the hierarchy comes from size alone.
    local hasWeights: boolean =
        string.find(family, "fonts/families/", 1, true) ~= nil
    local titleWeight: Enum.FontWeight = hasWeights
        and Enum.FontWeight.Bold
        or resolvedBase.Weight
    local controlWeight: Enum.FontWeight = hasWeights
        and Enum.FontWeight.SemiBold
        or resolvedBase.Weight
    local bodyWeight: Enum.FontWeight = hasWeights
        and Enum.FontWeight.Regular
        or resolvedBase.Weight
    TITLE_FONT = Font.new(family, titleWeight, style)
    CONTROL_FONT = Font.new(family, controlWeight, style)
    THIN_FONT = Font.new(family, bodyWeight, style)
    VALVE_FONT = CONTROL_FONT

    -- Each label keeps the weight it was designed with, so headings stay
    -- heavier than body text in whichever family was picked.
    for _, descendant: Instance in ipairs(ScreenGui:GetDescendants()) do
        if descendant:IsA("TextLabel")
            or descendant:IsA("TextButton")
            or descendant:IsA("TextBox") then
            local current: Font = (descendant :: any).FontFace
            local weight: Enum.FontWeight = hasWeights
                and current.Weight
                or resolvedBase.Weight
            local ok: boolean = pcall(function(): ()
                (descendant :: any).FontFace = Font.new(family, weight, current.Style)
            end)
            if not ok then
                (descendant :: any).FontFace = resolvedBase
            end
        end
    end

    if persist ~= false then
        configData.values.interfaceFont = name
        queueConfigSave()
    end
end

state.applyAssetImage = function(
    logicalName: string,
    image: ImageLabel,
    onApplied: (() -> ())?
): ()
    task.spawn(function(): ()
        local assetId: string?, failure: string? = AssetManager.resolve(logicalName)
        if not assetId then
            warn("[" .. PRODUCT.logPrefix .. ":Assets] " .. logicalName .. ": " .. tostring(failure))
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
    status.BackgroundColor3 = Theme.surface
    status.BackgroundTransparency = isError and 0.05 or 0.2
    status.BorderSizePixel = 0
    status.FontFace = CONTROL_FONT
    status.Position = UDim2.fromOffset(18, 18)
    status.Size = UDim2.new(1, -36, 0, isError and 150 or 46)
    status.Text = message
    status.TextColor3 = isError
        and Theme.negative
        or Theme.text
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
        "[" .. PRODUCT.name .. "] "
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
            print("[" .. PRODUCT.logPrefix .. ":Bootstrap] Inicializando sección " .. sectionName)
            local success: boolean, errorMessage: string? =
                SectionManager.initialize(sectionName)
            if not success then
                failures += 1
                warn(
                    "[" .. PRODUCT.logPrefix .. ":Bootstrap] Sección "
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
                    "[" .. PRODUCT.logPrefix .. ":Bootstrap] Carga terminada · fallos="
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
    stroke.Color = Theme.outline
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

-- The box wins.
--
-- Every label the helpers build clips to its frame, because text that spills
-- out of its box is the one failure this interface will not have. The cost is
-- that a frame shorter than the font's line box shaves the bottom off the
-- glyphs — the tail of the "g" in "Settings" was cut off in the page header,
-- and it happens with any face taller than the one a height was tuned for.
--
-- So the requested size is capped by the room the object actually has. 1.2 is
-- the tallest line box among the faces the typeface picker offers, and text
-- that does not fit comes out a point or two smaller instead of shaved. A
-- label sized in scale has no measurable height until it is laid out, so it
-- keeps the requested size until the next refresh pass, when AbsoluteSize is
-- real.
local function fitTextSize(object: any, requested: number): number
    local height: number = object.AbsoluteSize.Y
    if height <= 0 then
        local vertical: UDim = object.Size.Y
        height = vertical.Scale == 0 and vertical.Offset or 0
    end
    if height <= 0 then
        return requested
    end
    return math.max(7, math.min(requested, math.floor((height - 2) / 1.2)))
end
state.fitTextSize = fitTextSize

-- Sets the logical size of an already-registered label and applies it with
-- the current text scale.
state.setTextMetric = function(object: any, normalSize: number): ()
    local entry: any = state.registeredTextIndex[object]
    if entry then
        entry.normalSize = normalSize
    end
    object.TextSize = fitTextSize(
        object,
        math.round(normalSize * TEXT_BASE_MULTIPLIER * state.textScale)
    )
end

local function makeTextLabel(
    parent: Instance,
    text: string,
    normalSize: number?
): TextLabel
    -- Text is contained by default. A label that is fine in BuilderSans runs
    -- straight out of its box in Code or Bangers, and the fix cannot be "pick
    -- a shorter word": every label clips to its frame and ends in an ellipsis.
    return registerText(create("TextLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        FontFace = THIN_FONT,
        Text = text,
        TextColor3 = Theme.text,
        TextTruncate = Enum.TextTruncate.AtEnd,
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
        ClipsDescendants = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundColor3 = isDefaultStyle
            and Theme.button
            or DEFAULT_SURFACE_COLOR,
        BorderSizePixel = 0,
        FontFace = CONTROL_FONT,
        Text = text,
        TextColor3 = isDefaultStyle
            and Theme.text
            or Theme.text,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    }), normalSize or 14)

    addRoundedStyle(button, 9, 0.48)
    button:SetAttribute(
        "IdleColor",
        isDefaultStyle and Theme.button or DEFAULT_SURFACE_COLOR
    )
    button:SetAttribute(
        "HoverColor",
        isDefaultStyle and Theme.buttonHover or Theme.surfaceHover
    )
    button:SetAttribute(
        "PressedColor",
        isDefaultStyle and Theme.buttonPressed or Theme.surfacePressed
    )
    table.insert(state.styledButtons, button)

    trackUiConnection(button.MouseEnter:Connect(function()
        if button:GetAttribute("NoHover") or button:GetAttribute("Disabled") then
            return
        end
        local configuredHover: any = button:GetAttribute("HoverColor")
        local hoverColor: Color3 = typeof(configuredHover) == "Color3"
            and configuredHover
            or Theme.surfaceHover
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
            and (typeof(selectedColor) == "Color3" and selectedColor or Theme.accentSoft)
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
            or Theme.surfacePressed
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
            and (typeof(selectedColor) == "Color3" and selectedColor or Theme.accentSoft)
            or (typeof(configuredHover) == "Color3"
                and configuredHover
                or Theme.surfaceHover)
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
    local frame: Frame? = button:FindFirstChild("SwitchTrack") :: Frame?
    local core: Frame? = frame and frame:FindFirstChild("Knob") :: Frame?
    if not frame or not core then
        return
    end
    local stroke: UIStroke? = frame:FindFirstChild("MarkStroke") :: UIStroke?
    local targetSize: UDim2 = enabled
        and UDim2.fromScale(0.62, 0.62)
        or UDim2.fromScale(0, 0)
    local targetTransparency: number = enabled and 0.05 or 1
    if animate and state.animationsEnabled then
        TweenService:Create(core, TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quart), {
            Size = targetSize,
            BackgroundTransparency = targetTransparency,
        }):Play()
    else
        core.Size = targetSize
        core.BackgroundTransparency = targetTransparency
    end
    if stroke then
        stroke.Transparency = enabled and 0.15 or 0.45
    end
end

-- State mark.
--
-- Not a switch. A sliding pill is a phone control: it is wide, it is loud, it
-- repeats on every row, and at this size the knob is the only thing you can
-- read. This is a square that is either empty or filled — the same shape the
-- module cards use for their own state — drawn in the interface's own greys,
-- with no colour of its own.
local function createToggleSwitch(
    parent: Instance,
    enabled: boolean,
    width: number?
): TextButton
    local markSize: number = math.clamp(width or 15, 12, 18)
    local button: TextButton = create("TextButton", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClipsDescendants = true,
        Parent = parent,
        Active = true,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        -- The hit area stays finger-sized even though the mark is small.
        Size = UDim2.fromOffset(math.max(markSize + 14, 28), 30),
        Text = "",
    }) :: TextButton
    local frame: Frame = create("Frame", {
        Parent = button,
        Name = "SwitchTrack",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.text,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(markSize, markSize),
        ZIndex = button.ZIndex + 1,
    }) :: Frame
    create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
    create("UIStroke", {
        Parent = frame,
        Name = "MarkStroke",
        Color = Theme.outline,
        Transparency = 0.45,
        Thickness = 1,
    })
    -- The inner block is what fills; keeping it separate from the outline lets
    -- the mark grow into place instead of blinking on.
    local core: Frame = create("Frame", {
        Parent = frame,
        Name = "Knob",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.text,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0, 0),
        ZIndex = frame.ZIndex + 1,
    }) :: Frame
    create("UICorner", {Parent = core, CornerRadius = UDim.new(0, 2)})
    setToggleSwitch(button, enabled, false)
    return button
end

local function applyKeySlotStyle(button: TextButton): ()
    button.ZIndex = math.max(2, button.ZIndex)
    button.BackgroundColor3 = Theme.surface
    button.BackgroundTransparency = 0.54
    button.TextColor3 = Theme.textMuted
    button:SetAttribute("ThemeRole", "KeySlot")
    button:SetAttribute("IdleColor", Theme.surface)
    button:SetAttribute("HoverColor", Theme.surfaceHover)
    button:SetAttribute("PressedColor", Theme.buttonPressed)
    local buttonStroke: UIStroke? = button:FindFirstChildOfClass("UIStroke")
    if buttonStroke then
        buttonStroke.Color = Theme.outline
        buttonStroke.Transparency = 0.78
    end
end

-- The options handle: three stacked lines.
--
-- The reference interface marks "this module has settings" with a small
-- hamburger, and that reads as a control at a glance; the three dots this menu
-- used before read as "truncated text" and were mistaken for a cut-off label.
-- Text glyphs are avoided on purpose — the interface typeface is swappable, so
-- a literal "≡" would change shape with the font. Three frames do not.
state.applyLinesGlyph = function(
    button: TextButton,
    dimmed: boolean,
    active: boolean?
): ()
    button.Text = ""
    local existing: Instance? = button:FindFirstChild("LinesGlyph")
    local glyph: Frame
    if existing and existing:IsA("Frame") then
        glyph = existing :: Frame
    else
        glyph = create("Frame", {
            Parent = button,
            Name = "LinesGlyph",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(12, 8),
            ZIndex = button.ZIndex + 1,
        }) :: Frame
        for index: number = 1, 3 do
            local bar: Frame = create("Frame", {
                Parent = glyph,
                Name = "Line" .. tostring(index),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Theme.text,
                BorderSizePixel = 0,
                Position = UDim2.new(0.5, 0, 0, (index - 1) * 3.5 + 0.5),
                -- The middle line is shorter, which is what stops the mark
                -- from reading as a solid block at 12px.
                Size = UDim2.fromOffset(index == 2 and 9 or 12, 1),
                ZIndex = button.ZIndex + 2,
            }) :: Frame
            create("UICorner", {Parent = bar, CornerRadius = UDim.new(1, 0)})
        end
    end
    local barTransparency: number = dimmed and 0.74 or (active and 0.02 or 0.3)
    for _, bar: Instance in ipairs(glyph:GetChildren()) do
        if bar:IsA("Frame") then
            bar.BackgroundTransparency = barTransparency
        end
    end
end

state.restyleButtons = function(isDefault: boolean): ()
    for _, button: TextButton in ipairs(state.styledButtons) do
        if button.Parent then
            local role: any = button:GetAttribute("ThemeRole")
            if role ~= "Navigation" and role ~= "Icon" then
                local idleColor: Color3 = isDefault
                    and Theme.button
                    or DEFAULT_SURFACE_COLOR
                button:SetAttribute("IdleColor", idleColor)
                button:SetAttribute(
                    "HoverColor",
                    isDefault and Theme.buttonHover or Theme.surfaceHover
                )
                button:SetAttribute(
                    "PressedColor",
                    isDefault and Theme.buttonPressed or Theme.surfacePressed
                )
                if button:GetAttribute("Selected") ~= true then
                    button.BackgroundColor3 = idleColor
                end
                button.TextColor3 = isDefault and Theme.text or Theme.text
                local stroke: UIStroke? =
                    button:FindFirstChild("StyleStroke") :: UIStroke?
                if stroke then
                    stroke.Enabled = true
                    stroke.Color = isDefault and Theme.outline or Theme.outline
                    stroke.Transparency = isDefault and 0.32 or 0.48
                end
                if role == "KeySlot" then
                    button.BackgroundColor3 = Theme.surface
                    button.BackgroundTransparency = 0.54
                    button.TextColor3 = Theme.textMuted
                    local keyStroke: UIStroke? =
                        button:FindFirstChild("StyleStroke") :: UIStroke?
                    if keyStroke then
                        keyStroke.Color = Theme.outline
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
                and Theme.buttonPressed
                or Theme.surface,
            TextColor3 = active
                and Theme.text
                or Theme.textMuted,
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
            and Theme.buttonPressed
            or Theme.surface,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        -- A text box holds whatever is typed into it, which is unbounded by
        -- definition, so it clips and truncates rather than spilling.
        ClipsDescendants = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
        FontFace = THIN_FONT,
        PlaceholderColor3 = isDefaultStyle
            and Theme.textMuted
            or Theme.textMuted,
        Text = tostring(defaultText),
        TextColor3 = isDefaultStyle
            and Theme.text
            or Theme.text,
        TextXAlignment = Enum.TextXAlignment.Center,
    }), 13) :: any) :: TextBox
    addRoundedStyle(textBox, 9, 0.5)
    table.insert(state.styledTextBoxes, textBox)
    trackUiConnection(textBox.Focused:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {BackgroundColor3 = state.guiStyle == "Default"
                and Theme.buttonHover
                or Theme.surfaceRaised}
        ):Play()
    end))
    trackUiConnection(textBox.FocusLost:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(UI_MOTION.base, Enum.EasingStyle.Quad),
            {BackgroundColor3 = state.guiStyle == "Default"
                and Theme.buttonPressed
                or Theme.surface}
        ):Play()
    end))
    return textBox
end

state.restyleTextBoxes = function(isDefault: boolean): ()
    for _, textBox: TextBox in ipairs(state.styledTextBoxes) do
        if textBox.Parent then
            textBox.BackgroundColor3 = isDefault
                and Theme.buttonPressed
                or Theme.surface
            textBox.TextColor3 = isDefault and Theme.text or Theme.text
            textBox.PlaceholderColor3 = isDefault
                and Theme.textMuted
                or Theme.textMuted
            local stroke: UIStroke? =
                textBox:FindFirstChild("StyleStroke") :: UIStroke?
            if stroke then
                stroke.Color = isDefault and Theme.outline or Theme.outline
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
    print("[" .. PRODUCT.name .. "] " .. text)
    toastSequence += 1

    local toast: CanvasGroup = Instance.new("CanvasGroup")
    toast.Name = "Toast"
    toast.AutomaticSize = Enum.AutomaticSize.Y
    toast.BackgroundColor3 = state.guiStyle == "Default"
        and Theme.surface
        or Theme.surfaceRaised
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
            and Theme.outline
            or Theme.outline,
        Transparency = state.guiStyle == "Default" and 0.42 or 0.22,
        Thickness = 1,
    })
    local accent: Frame = (create("Frame", {
        Parent = toast,
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.accent
            or Theme.accent,
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
        and Theme.text
        or Theme.text
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
    BackgroundColor3 = Theme.background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(initialWindowSize.X, initialWindowSize.Y),
    ZIndex = 1,
}) :: any) :: Frame

-- The window scales from its own centre when it opens; the scale lives here so
-- the visibility controller (defined before the window exists) can reach it.
state.mainScale = create("UIScale", {
    Parent = Main,
    Name = "ShellScale",
    Scale = 1,
})

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
MainStroke.Color = Theme.outline
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
    BackgroundColor3 = Theme.sidebar,
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
    BackgroundColor3 = Theme.sidebar,
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
    BackgroundColor3 = Theme.outline,
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
BrandMark.BackgroundColor3 = Theme.surface
BrandMark.BackgroundTransparency = 0.42
BrandMark.FontFace = CONTROL_FONT
BrandMark.Position = layout.sidebarCollapsed
    and UDim2.fromScale(0.5, 0.5)
    or UDim2.new(0, layout.sidebarPadding, 0.5, 0)
BrandMark.Size = UDim2.fromOffset(layout.navIconSize + 4, layout.navIconSize + 4)
BrandMark.TextColor3 = Theme.text
BrandMark.TextXAlignment = Enum.TextXAlignment.Center
BrandMark.ZIndex = 14
create("UICorner", {Parent = BrandMark, CornerRadius = cornerRadius(UI_RADIUS.chip)})
create("UIStroke", {
    Parent = BrandMark,
    Color = Theme.outline,
    Transparency = 0.7,
    Thickness = 1,
})
-- The brand mark is the close control: pressing the logo above the tab list
-- puts the menu away, and the launcher brings it back. One obvious place to
-- press, in the corner the eye already goes to.
local BrandButton: TextButton = create("TextButton", {
    TextTruncate = Enum.TextTruncate.AtEnd,
    ClipsDescendants = true,
    Parent = BrandMark,
    Name = "BrandButton",
    Active = true,
    AutoButtonColor = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Text = "",
    ZIndex = 17,
}) :: TextButton
trackUiConnection(BrandButton.MouseButton1Click:Connect(function(): ()
    state.setMenuVisible(false)
end))
trackUiConnection(BrandButton.MouseEnter:Connect(function(): ()
    BrandMark.BackgroundTransparency = 0.18
end))
trackUiConnection(BrandButton.MouseLeave:Connect(function(): ()
    BrandMark.BackgroundTransparency = 0.42
end))

local BrandIcon: ImageLabel = create("ImageLabel", {
    Parent = BrandMark,
    Name = "BrandIcon",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.fromScale(1, 1),
    -- Under the button, so the logo is decoration and the press still lands.
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
local BrandName: TextLabel = makeTextLabel(BrandRow, PRODUCT.name, 10)
BrandName.Name = "BrandName"
BrandName.AnchorPoint = Vector2.new(0, 0.5)
BrandName.FontFace = CONTROL_FONT
BrandName.Position = UDim2.new(0, layout.sidebarPadding + layout.navIconSize + 12, 0.5, 0)
BrandName.Size = UDim2.new(1, -(layout.sidebarPadding * 2 + layout.navIconSize + 12), 0, 18)
BrandName.TextColor3 = Theme.textMuted
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
    BackgroundColor3 = Theme.background,
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
-- Tall enough for a descender at the largest text scale, so the title is not
-- the label that has to be shrunk to fit.
HeaderTitle.Size = UDim2.new(
    1,
    -(layout.contentPadding * 2 + layout.searchWidth + 10),
    0,
    26
)
HeaderTitle.TextColor3 = Theme.text
HeaderTitle.TextTruncate = Enum.TextTruncate.AtEnd
HeaderTitle.ZIndex = 23
local HeaderRule: Frame = create("Frame", {
    Parent = DefaultHeader,
    Name = "HeaderRule",
    AnchorPoint = Vector2.new(0, 1),
    BackgroundColor3 = Theme.outline,
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

-- What a rail entry is called on screen.
--
-- In one place because the rail row and the page header have to agree, and
-- because the board's name is not fixed: it is the game's when a game module
-- was recognised.
state.tabLabel = function(tabName: string): string
    if tabName == "Config." then
        return "Settings"
    end
    if tabName == "Universal"
        and type(ACTIVE_GAME_MODULE) == "string"
        and ACTIVE_GAME_MODULE ~= "" then
        return ACTIVE_GAME_MODULE
    end
    return tabName
end

local function setTab(tabName: string): ()
    local previousTab: string? = state.activeTab
    state.activeTab = tabName

    for name, page in pairs(pages) do
        local selectedPage: boolean = name == tabName
        page.Visible = selectedPage
        -- The page you switched to rises the last few pixels into place. It is
        -- 10px and 0.16s: enough to say "this is a different page", not enough
        -- to be a transition anyone has to sit through. Switching to the page
        -- you are already on does nothing.
        if selectedPage
            and state.animationsEnabled
            and previousTab ~= nil
            and previousTab ~= tabName then
            page.Position = UDim2.fromOffset(0, 10)
            TweenService:Create(
                page,
                TweenInfo.new(
                    UI_MOTION.base,
                    Enum.EasingStyle.Quart,
                    Enum.EasingDirection.Out
                ),
                {Position = UDim2.fromOffset(0, 0)}
            ):Play()
        elseif selectedPage then
            page.Position = UDim2.fromOffset(0, 0)
        end
    end

    local headerTitle: TextLabel? = state.shells.headerTitle
    if headerTitle then
        headerTitle.Text = state.tabLabel(tabName)
    end

    for name: string, button: TextButton in pairs(defaultTabButtons) do
        local selected: boolean = name == tabName
        button:SetAttribute("Selected", selected)
        button.BackgroundColor3 = selected
            and Theme.surface
            or Theme.sidebar
        button.BackgroundTransparency = selected and 0.34 or 1
        button.TextColor3 = selected and Theme.text or Theme.textMuted
        local navLabel: TextLabel? = button:FindFirstChild("NavLabel") :: TextLabel?
        if navLabel then
            navLabel.TextColor3 = selected
                and Theme.text
                or Theme.textMuted
        end
        local tabStroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
        if tabStroke then
            tabStroke.Color = Theme.outline
            tabStroke.Transparency = selected and 0.78 or 1
        end
        -- The monogram chip is the only thing left when the rail collapses,
        -- so it carries the selection state too.
        local monogram: TextLabel? = button:FindFirstChild("Monogram") :: TextLabel?
        if monogram then
            monogram.TextColor3 = selected
                and Theme.text
                or Theme.textMuted
            monogram.BackgroundTransparency = selected and 0.28 or 0.62
        end
        -- Selected rows get an accent tick on their leading edge: a compact
        -- selection cue that survives the icon-only rail. It grows into place
        -- from nothing rather than blinking on, which is what makes the rail
        -- feel like one control instead of three lamps.
        local marker: Frame? = button:FindFirstChild("SelectionMarker") :: Frame?
        if marker then
            local fullHeight: number = math.max(10, state.layout.navRowHeight - 12)
            if not state.animationsEnabled then
                marker.Visible = selected
                marker.Size = UDim2.fromOffset(2, fullHeight)
            elseif selected then
                marker.Visible = true
                marker.Size = UDim2.fromOffset(2, 0)
                TweenService:Create(
                    marker,
                    TweenInfo.new(
                        UI_MOTION.base,
                        Enum.EasingStyle.Back,
                        Enum.EasingDirection.Out
                    ),
                    {Size = UDim2.fromOffset(2, fullHeight)}
                ):Play()
            else
                TweenService:Create(
                    marker,
                    TweenInfo.new(
                        UI_MOTION.fast,
                        Enum.EasingStyle.Quart,
                        Enum.EasingDirection.In
                    ),
                    {Size = UDim2.fromOffset(2, 0)}
                ):Play()
            end
        end
    end
end

local function createTab(tabName: string, layoutOrder: number): Frame
    local layout: LayoutMetrics = state.layout
    -- The board's own label follows the game: "Universal" is what it is
    -- called when nothing recognised this place.
    local defaultLabel: string = state.tabLabel(tabName)
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
    defaultButton.BackgroundColor3 = Theme.sidebar
    defaultButton.BackgroundTransparency = 1
    defaultButton.TextColor3 = Theme.textMuted
    defaultButton.TextXAlignment = Enum.TextXAlignment.Left
    defaultButton.ZIndex = 12
    defaultButton:SetAttribute("ThemeRole", "Navigation")
    defaultButton:SetAttribute("SelectedColor", Theme.surface)
    defaultButton:SetAttribute("IdleColor", Theme.sidebar)
    defaultButton:SetAttribute("HoverColor", Theme.surfaceHover)
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
        BackgroundColor3 = Theme.accent,
        BorderSizePixel = 0,
        -- Flush with the row's own left edge. It used to hang six pixels
        -- outside the button, which put it in the rail's gutter and made it
        -- the first thing to disappear once buttons started clipping.
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(2, math.max(10, layout.navRowHeight - 12)),
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
    monogram.BackgroundColor3 = Theme.surface
    monogram.BackgroundTransparency = 0.62
    monogram.FontFace = CONTROL_FONT
    monogram.Position = UDim2.new(0, 0, 0.5, 0)
    monogram.Size = UDim2.fromOffset(layout.navIconSize, layout.navIconSize)
    monogram.TextColor3 = Theme.textMuted
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
            -- `rbxthumb://type=GameIcon` only resolves for the place the
            -- client is currently connected to; every other tab came up blank.
            -- The icon of another game has to be asked for by asset id, which
            -- is a web call, so it runs off the bootstrap thread and falls
            -- back to the thumbnail service and then to the monogram.
            task.spawn(function(): ()
                local infoOk: boolean, info: any = pcall(function(): any
                    -- Fetched here rather than kept as another bootstrap
                    -- local: this function is at Luau's 200-register ceiling.
                    return (game:GetService("MarketplaceService") :: any)
                        :GetProductInfo(resolvedId, Enum.InfoType.Asset)
                end)
                local iconAssetId: number = infoOk
                        and type(info) == "table"
                        and tonumber(info.IconImageAssetId)
                    or 0
                if not tabIcon.Parent then
                    return
                end
                if iconAssetId > 0 then
                    tabIcon.Image = "rbxassetid://" .. tostring(iconAssetId)
                    monogram.Text = ""
                    return
                end
                if resolvedId == game.PlaceId then
                    tabIcon.Image = "rbxthumb://type=GameIcon&id="
                        .. tostring(resolvedId)
                        .. "&w=150&h=150"
                    monogram.Text = ""
                end
            end)
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
    navLabel.TextColor3 = Theme.textMuted
    navLabel.TextTruncate = Enum.TextTruncate.AtEnd
    navLabel.Visible = not layout.sidebarCollapsed
    navLabel.ZIndex = 13

    defaultTabButtons[tabName] = defaultButton

    local page: Frame = create("Frame", {
        Parent = Content,
        Name = tabName .. "Page",
        BackgroundColor3 = Theme.background,
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
            -- Only the selected row's tick has a height; resizing all of them
            -- on a viewport change would light up the whole rail.
            marker.Size = button:GetAttribute("Selected") == true
                and UDim2.fromOffset(2, math.max(10, metrics.navRowHeight - 16))
                or UDim2.fromOffset(2, 0)
        end
    end
end)

-- Three entries, and one of them is the whole menu.
--
-- Games used to own a tab each, then categories did, and both were the same
-- mistake in different clothes: a rail full of pages that were only ever a
-- filter over one list of cards. There is one board now. It carries every
-- module the client has — the menu's own and whatever the game module added —
-- grouped under a header per category, which is the grouping that was doing
-- the work all along.
--
-- The board is called "Universal" in a game nobody wrote a module for, and
-- takes the game's own name when there is one: the rail says MM2 because in
-- MM2 the board *is* MM2 plus everything else.
local UniversalPage = createTab("Universal", 1)
createTab("Spoof", 2)
local SettingsPage = createTab("Config.", 3)

for _, button: TextButton in pairs(defaultTabButtons) do
    button.Size = UDim2.new(1, 0, 0, state.layout.navRowHeight)
end

do
-- Search lives in the page header, not in the rail: on a phone the rail is
-- only wide enough for the monogram chips.
local searchLayout: LayoutMetrics = state.layout
-- The search field is a clipping frame with the box inside it, not a bare
-- TextBox. A TextBox does not contain its own text: switch the interface to a
-- wide face like Code and the query used to run straight out of the field and
-- across the header. The frame owns the edge, the fill and the clip; the box
-- only owns the text.
local DefaultSearchFrame: Frame = create("Frame", {
    Parent = state.shells.defaultHeader,
    Name = "DefaultSearchFrame",
    AnchorPoint = Vector2.new(1, 0.5),
    BackgroundColor3 = Theme.surface,
    BackgroundTransparency = 0.28,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.new(1, -searchLayout.contentPadding, 0.5, 0),
    Size = UDim2.fromOffset(searchLayout.searchWidth, searchLayout.searchHeight),
    ZIndex = 24,
}) :: Frame
create("UICorner", {
    Parent = DefaultSearchFrame,
    Name = "SearchCorner",
    CornerRadius = cornerRadius(UI_RADIUS.control),
})
create("UIStroke", {
    Parent = DefaultSearchFrame,
    Name = "SearchStroke",
    Color = Theme.outline,
    Transparency = 0.66,
    Thickness = 1,
})

local DefaultSearchBox: TextBox = makeTextBox(DefaultSearchFrame, "")
DefaultSearchBox.Name = "DefaultSearch"
DefaultSearchBox.PlaceholderText = "Search modules"
DefaultSearchBox.AnchorPoint = Vector2.new(1, 0.5)
DefaultSearchBox.BackgroundTransparency = 1
DefaultSearchBox.Position = UDim2.new(1, -8, 0.5, 0)
DefaultSearchBox.Size = UDim2.new(1, -32, 1, -6)
DefaultSearchBox.TextColor3 = Theme.text
DefaultSearchBox.PlaceholderColor3 = Theme.textMuted:Lerp(
    Theme.surface,
    0.42
)
DefaultSearchBox.TextXAlignment = Enum.TextXAlignment.Left
DefaultSearchBox.TextYAlignment = Enum.TextYAlignment.Center
DefaultSearchBox.ZIndex = 25
do
    local boxCorner: UICorner? =
        DefaultSearchBox:FindFirstChild("StyleCorner") :: UICorner?
    if boxCorner then
        boxCorner:Destroy()
    end
    local boxStroke: UIStroke? =
        DefaultSearchBox:FindFirstChild("StyleStroke") :: UIStroke?
    if boxStroke then
        boxStroke:Destroy()
    end
end
-- Keeps the glyphs off the frame's own edge at any text size.
create("UITextSizeConstraint", {
    Parent = DefaultSearchBox,
    MaxTextSize = math.max(searchLayout.searchHeight - 12, 11),
    MinTextSize = 8,
})

local SearchClear: TextButton = makeButton(DefaultSearchFrame, "x", 9)
SearchClear.Name = "ClearSearch"
SearchClear.AnchorPoint = Vector2.new(0, 0.5)
SearchClear.BackgroundTransparency = 1
SearchClear.Position = UDim2.new(0, 4, 0.5, 0)
SearchClear.Size = UDim2.fromOffset(22, 22)
SearchClear.TextTransparency = 0.45
SearchClear.Visible = false
SearchClear.ZIndex = 26
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
    -- The frame is what moves and resizes now; the box fills it.
    DefaultSearchFrame.Position = UDim2.new(1, -metrics.contentPadding, 0.5, 0)
    DefaultSearchFrame.Size =
        UDim2.fromOffset(metrics.searchWidth, metrics.searchHeight)
    local sizeCap: UITextSizeConstraint? =
        DefaultSearchBox:FindFirstChildOfClass("UITextSizeConstraint")
    if sizeCap then
        sizeCap.MaxTextSize = math.max(metrics.searchHeight - 12, 11)
    end
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
    ScrollBarImageColor3 = Theme.outline,
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

-- The Spoof page.
--
-- Its own page rather than a category of the board, because nothing on it is
-- an advantage: it changes how the game looks to you — whose avatar you are
-- wearing, which animations your character plays, which emote it is doing —
-- and mixing that with the modules that change what you can *do* would make
-- both lists harder to read.
--
-- The scroll is published on `state` and the modules that fill it are ordinary
-- downloaded modules (`src/modules/Spoof/`), so the shell knows nothing about
-- them beyond where to put their cards.
do
    local spoofPage: Frame? = pages.Spoof
    if spoofPage then
        local spoofScroll: ScrollingFrame = create("ScrollingFrame", {
            Parent = spoofPage,
            Name = "SpoofScroll",
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, 0),
            ScrollBarImageColor3 = Theme.outline,
            ScrollBarThickness = 6,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Size = UDim2.fromScale(1, 1),
        }) :: ScrollingFrame
        create("UIPadding", {
            Parent = spoofScroll,
            PaddingBottom = UDim.new(0, 18),
            PaddingLeft = UDim.new(0, 18),
            PaddingRight = UDim.new(0, 18),
            PaddingTop = UDim.new(0, 18),
        })
        create("UIListLayout", {
            Parent = spoofScroll,
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 9),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        state.spoofScroll = spoofScroll
    end
end

-- Game modules still ask for "their" page by name. There is no such page any
-- more: every card goes on the one board, where the grid groups it under a
-- header for its category.
state.universalScroll = UniversalScroll
state.trsScroll = UniversalScroll
state.vdScroll = UniversalScroll
state.mvsdScroll = UniversalScroll
state.bedFightScroll = UniversalScroll

-- No intro.
--
-- There used to be a staged curtain here: a wordmark, a ring, a status line
-- narrating each loading stage, a progress bar and a hold on "Ready" before it
-- lifted. All of it was time the player spent watching the menu talk about
-- itself. Vape does not do this and neither do we any more — the menu builds
-- itself hidden, and the launcher button appearing on screen *is* the signal
-- that it is ready.
--
-- The two entry points other code calls are kept as no-ops rather than deleted
-- so the loader, the module runner and the watchdog do not each need to know
-- whether an intro exists.
state.loadingLabel = nil
state.loadingProgressFill = nil
state.finishLoadingIntro = function(_failureCount: number): ()
end

-- Make the shell usable before any optional feature/module initialization runs.
-- A later runtime error must never leave every page hidden.
UniversalScroll.Visible = true
UniversalScroll.CanvasSize = UDim2.fromOffset(0, 0)
setTab("Universal")
print("[" .. PRODUCT.logPrefix .. ":Bootstrap] GUI base visible; construyendo funciones universales")

local universalFeatures = {}
local movementFeatures = {}
-- Published for the features that used to be written inside this file: a card
-- files itself under the same registry it always did.
state.movementFeatures = movementFeatures
local mm2Features = {}
state.trsFeatures = {}
-- Spoof modules keep their own registry and their own page.
state.spoofFeatures = {}
state.vdFeatures = {}
state.bedFightFeatures = {}
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
                warn("[" .. PRODUCT.name .. "] card layout: " .. tostring(failure))
            end
        end
    end
end)
state.tooltipConnections = {} :: {RBXScriptConnection}

do
local MobileMenuButton = create("TextButton", {
    TextTruncate = Enum.TextTruncate.AtEnd,
    ClipsDescendants = true,
    Parent = ScreenGui,
    Name = "MobileMenuButton",
    AutoButtonColor = false,
    BackgroundColor3 = Theme.surface,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    FontFace = CONTROL_FONT,
    Position = UDim2.new(1, -18, 0, 18),
    AnchorPoint = Vector2.new(1, 0),
    Size = UDim2.fromOffset(52, 52),
    Text = "RTM",
    TextColor3 = Theme.text,
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
    Color = Theme.outline,
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

-- The launcher can be moved.
--
-- It lives over the game, which means it can sit exactly where a game put its
-- own button. Press and drag moves it; a press that does not travel is still a
-- press, so tapping it opens the menu as before. Where it ends up is saved.
do
    local dragInput: InputObject? = nil
    local dragStart: Vector2 = Vector2.zero
    local startPosition: UDim2 = MobileMenuButton.Position
    local travelled: number = 0

    local storedX: number? = tonumber(configData.ui.launcherX)
    local storedY: number? = tonumber(configData.ui.launcherY)
    if storedX and storedY then
        MobileMenuButton.Position = UDim2.fromOffset(storedX, storedY)
        MobileMenuButton.AnchorPoint = Vector2.new(0, 0)
    end

    -- The launcher answers a finger.
    --
    -- A button that floats over the game and never reacts to being touched
    -- reads as part of the game's own HUD. It dips under the press and springs
    -- back on release, which is the one place in this interface where a bit of
    -- bounce belongs: it is a physical-looking object sitting on the screen.
    local launcherScale: UIScale = create("UIScale", {
        Parent = MobileMenuButton,
        Name = "LauncherScale",
        Scale = 1,
    }) :: UIScale

    local function pressLauncher(pressed: boolean): ()
        if not state.animationsEnabled then
            launcherScale.Scale = 1
            return
        end
        TweenService:Create(
            launcherScale,
            TweenInfo.new(
                pressed and UI_MOTION.fast or 0.34,
                pressed and Enum.EasingStyle.Quart or Enum.EasingStyle.Back,
                Enum.EasingDirection.Out
            ),
            {Scale = pressed and 0.9 or 1}
        ):Play()
    end

    trackUiConnection(MobileMenuButton.InputBegan:Connect(function(
        input: InputObject
    ): ()
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        dragInput = input
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        startPosition = MobileMenuButton.Position
        travelled = 0
        pressLauncher(true)
    end))

    trackUiConnection(UserInputService.InputChanged:Connect(function(
        input: InputObject
    ): ()
        if not dragInput then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local pointer: Vector2 = Vector2.new(input.Position.X, input.Position.Y)
        local delta: Vector2 = pointer - dragStart
        travelled = math.max(travelled, delta.Magnitude)
        if travelled < 6 then
            -- Below the threshold this is still a tap, not a drag.
            return
        end
        -- Anchored top-left while dragging so the maths is in one space.
        MobileMenuButton.AnchorPoint = Vector2.new(0, 0)
        local viewport: Vector2 = ScreenGui.AbsoluteSize
        local size: Vector2 = MobileMenuButton.AbsoluteSize
        local baseX: number = startPosition.X.Scale * viewport.X + startPosition.X.Offset
        local baseY: number = startPosition.Y.Scale * viewport.Y + startPosition.Y.Offset
        MobileMenuButton.Position = UDim2.fromOffset(
            math.clamp(math.round(baseX + delta.X), 0, math.max(viewport.X - size.X, 0)),
            math.clamp(math.round(baseY + delta.Y), 0, math.max(viewport.Y - size.Y, 0))
        )
    end))

    trackUiConnection(UserInputService.InputEnded:Connect(function(
        input: InputObject
    ): ()
        if input ~= dragInput then
            return
        end
        dragInput = nil
        pressLauncher(false)
        if travelled >= 6 then
            -- Dropped, so it settles against the nearer side rather than
            -- floating in the middle of the view, where it covers the game and
            -- is easy to hit by accident. The overshoot is what makes it read
            -- as "it went home" instead of "it teleported".
            local viewport: Vector2 = ScreenGui.AbsoluteSize
            local size: Vector2 = MobileMenuButton.AbsoluteSize
            local currentX: number = MobileMenuButton.Position.X.Offset
            local currentY: number = MobileMenuButton.Position.Y.Offset
            local margin: number = 14
            local nearestX: number = currentX + size.X * 0.5 < viewport.X * 0.5
                and margin
                or math.max(margin, viewport.X - size.X - margin)
            local restingY: number = math.clamp(
                currentY,
                margin,
                math.max(margin, viewport.Y - size.Y - margin)
            )
            local resting: UDim2 = UDim2.fromOffset(
                math.round(nearestX),
                math.round(restingY)
            )
            if state.animationsEnabled then
                TweenService:Create(
                    MobileMenuButton,
                    TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                    {Position = resting}
                ):Play()
            else
                MobileMenuButton.Position = resting
            end
            configData.ui.launcherX = resting.X.Offset
            configData.ui.launcherY = resting.Y.Offset
            queueConfigSave()
        end
    end))

    trackUiConnection(MobileMenuButton.MouseButton1Click:Connect(function(): ()
        -- A drag ends with a click too; only an untravelled press opens.
        if travelled >= 6 then
            return
        end
        state.setMenuVisible(not state.visible)
    end))
end

-- The launcher is the way back in, so it only exists while the menu is out of
-- sight. It used to sit on top of the open window, which made it look like a
-- second, broken close button.
local function refreshLauncherVisibility(): ()
    -- Touch devices only.
    --
    -- A phone has no key to press, so the button floating over the game is the
    -- only way back in — and its presence is also how you know the menu
    -- finished loading, since there is no intro any more. A machine with a
    -- keyboard has the menu key for both jobs, and there the button is nothing
    -- but a permanent circle sitting on top of the game, so it is never shown.
    MobileMenuButton.Visible = state.isMobile and not state.visible
end
refreshLauncherVisibility()
state.addMenuVisibilityListener(function(): ()
    refreshLauncherVisibility()
end)

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

-- Two buckets, not one.
--
-- Heartbeat fires *after* the frame has been drawn, so anything that draws an
-- overlay from the camera's position is always one frame behind the world and
-- visibly swims when the player turns. Work that reads or writes the game
-- belongs on Heartbeat; work that draws belongs on RenderStepped, which runs
-- before the frame it is drawing into.
local TaskManager = {
    tasks = {} :: {[number]: ScheduledTask},
    renderTasks = {} :: {[number]: ScheduledTask},
    nextId = 0,
    connection = nil :: RBXScriptConnection?,
    renderConnection = nil :: RBXScriptConnection?,
}

function TaskManager:Connect(
    callback: (...any) -> (),
    phase: string?
): TaskHandle
    self.nextId += 1
    local taskId: number = self.nextId
    local bucket: {[number]: ScheduledTask} = phase == "render"
        and self.renderTasks
        or self.tasks
    local handle: TaskHandle
    handle = {
        Connected = true,
        Disconnect = function(selfHandle: TaskHandle): ()
            if not selfHandle.Connected then
                return
            end
            selfHandle.Connected = false
            bucket[taskId] = nil
        end,
    }
    bucket[taskId] = {
        callback = callback,
        handle = handle,
        failures = 0,
    }
    return handle
end

function TaskManager:Destroy(): ()
    for _, bucket: {[number]: ScheduledTask} in
        ipairs({self.tasks, self.renderTasks})
    do
        for taskId: number, scheduled: ScheduledTask in pairs(bucket) do
            scheduled.handle.Connected = false
            bucket[taskId] = nil
        end
    end
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    if self.renderConnection then
        self.renderConnection:Disconnect()
        self.renderConnection = nil
    end
end

local function runBucket(
    bucket: {[number]: ScheduledTask},
    deltaTime: number
): ()
    for taskId: number, scheduled: ScheduledTask in pairs(bucket) do
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
                    "[" .. PRODUCT.name .. "] scheduled task "
                        .. tostring(taskId)
                        .. " failed: "
                        .. tostring(message)
                )
                -- Three throws in a row is a task that is never going to
                -- work; leaving it connected turns one broken module into a
                -- warning every frame for the rest of the session.
                if scheduled.failures >= 3 then
                    scheduled.handle:Disconnect()
                end
            end
        end
    end
end

TaskManager.connection = RunService.Heartbeat:Connect(function(
    deltaTime: number
): ()
    runBucket(TaskManager.tasks, deltaTime)
end)

TaskManager.renderConnection = RunService.RenderStepped:Connect(function(
    deltaTime: number
): ()
    runBucket(TaskManager.renderTasks, deltaTime)
end)


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

    Main.BackgroundColor3 = Theme.background
    state.mainStroke.Color = Theme.outline
    state.mainStroke.Transparency = 1
    for _, page: Frame in pairs(pages) do
        page.BackgroundColor3 = Theme.background
        page.BackgroundTransparency = 1
        for _, descendant: Instance in ipairs(page:GetDescendants()) do
            if descendant:IsA("ScrollingFrame") then
                descendant.ScrollBarImageColor3 = Theme.outline
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

    -- The grid is sized in pixels, never in scale.
    --
    -- Inside a ScrollingFrame a child of `UDim2.new(1, 0, ...)` resolves its
    -- width against the canvas, and UIPadding shifts that canvas without
    -- shrinking it: the board therefore ended up one whole gutter wider than
    -- the visible window, the second column ran under the scroll bar, and the
    -- options button of every card on that side was cut off by the shell's
    -- edge — the missing slice of menu the screenshot shows. Measuring the
    -- window and sizing the root in offset is the only version that cannot
    -- overflow, on any device, at any viewport.
    local windowWidth: number = record.container.AbsoluteWindowSize.X
    if windowWidth <= 0 then
        windowWidth = record.container.AbsoluteSize.X - layout.scrollBar
    end
    if windowWidth <= 0 then
        -- First frame: nothing has been measured yet, so fall back to what the
        -- metrics say the content column will be. The AbsoluteSize listener
        -- corrects it as soon as the engine reports a real size.
        windowWidth = layout.shellWidth - layout.sidebarWidth - 1
    end
    local innerWidth: number =
        math.max(160, math.floor(windowWidth - layout.contentPadding * 2))
    record.root.Size = UDim2.fromOffset(innerWidth, 0)

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
    headerLabel.TextColor3 = Theme.textMuted
    headerLabel.TextTransparency = 0.12

    local headerRule: Frame = create("Frame", {
        Parent = header,
        Name = "CategoryRule",
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.outline,
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
        -- The grid is measured, not scaled, so it has to re-measure whenever
        -- the window it lives in changes width: a viewport change, the rail
        -- collapsing, or the scroll bar appearing the first time the canvas
        -- overflows (which narrows the window by its own thickness).
        local measured: CardGridRecord = record :: CardGridRecord
        trackUiConnection(
            container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function(): ()
                updateCardGrid(measured)
            end)
        )
        pcall(function(): ()
            trackUiConnection(
                container:GetPropertyChangedSignal("AbsoluteWindowSize")
                    :Connect(function(): ()
                        updateCardGrid(measured)
                    end)
            )
        end)
        updateCardGrid(measured)
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


local function applyFeaturePresentation(feature: any, isDefault: boolean): ()
    -- One skin, one place. A restyle used to repaint the card with its own
    -- copy of the rules, which is how the stripe ended up pink on action cards
    -- and violet on headings while the card code said otherwise.
    if feature.kind == "hold" then
        feature.enabled = feature.active == true
    end
    if state.applyCardSkin then
        state.applyCardSkin(feature, false)
    end
    if feature.subtitle then
        feature.subtitle.TextColor3 = isDefault
            and Theme.textMuted
            or Theme.textMuted
    end
    if feature.options then
        feature.options.BackgroundTransparency = 1
    end
    if feature.arrow then
        feature.arrow.TextColor3 = isDefault
            and Theme.textMuted
            or Theme.textMuted
    end
    if feature.shortcutButton then
        feature.shortcutButton.BackgroundColor3 = isDefault
            and Theme.surface
            or Theme.surfaceRaised
        -- A container's slot is inert, so it stays a faint placeholder
        -- instead of being repainted as an interactive key slot.
        local inertSlot: boolean = feature.kind == "group"
        feature.shortcutButton.BackgroundTransparency = inertSlot
            and 0.86
            or (isDefault and 0.54 or 1)
        feature.shortcutButton.TextTransparency = inertSlot and 1 or 0
        feature.shortcutButton.TextColor3 = isDefault
            and Theme.text
            or Theme.text
    end
end
state.restyleAllFeatures = function(isDefault: boolean): ()
    for _, feature: any in ipairs(allFeatures) do
        applyFeaturePresentation(feature, isDefault)
    end
end

-- Card skin.
--
-- The card *is* the control. Nothing is bolted onto it — no switch, no chip,
-- no marker under the name — because a list of forty modules only stays
-- readable if each row is one shape whose surface, weight and edge already say
-- what it is and what it is doing:
--
--   toggle  a row that lifts. Off it is a hairline-separated line of muted
--           text on near-black; on, the surface rises a step, the name goes
--           white and a two-pixel edge lights the left side.
--   action  a slab. It carries a whisper of an outline on all four sides and
--           its name is always white, because a button has no "off"; pressing
--           it flashes the surface once.
--   hold    the same slab, seated one step darker, which rises to the toggle's
--           lit state for exactly as long as the key is down.
--   group   not a control at all: no surface, no outline, no hover — a heading
--           with a rule under it and its options below.
--
-- Everything is near-black through grey; the only "colour" in the interface is
-- how light a grey is.
state.applyCardSkin = function(feature: any, hovered: boolean?): ()
    local row: Frame? = feature.row
    if not row then
        return
    end
    local resolvedRow: Frame = row :: Frame
    local isHovered: boolean = hovered == true
    local isOn: boolean = feature.enabled == true

    local surface: number
    local titleTransparency: number = 0
    local titleColor: Color3 = Theme.text
    local outline: number = 1
    local edge: number = 1
    local rule: number = 0.86

    if feature.isCategory then
        -- A heading, not a button: flat, and the rule under it groups the
        -- options that belong to it.
        surface = 1
        titleColor = Theme.text
        titleTransparency = 0.3
        rule = 0.55
    elseif feature.isAction then
        surface = isHovered and 0.36 or 0.56
        outline = 0.74
        rule = 1
    elseif feature.isHoldAction then
        surface = isOn and 0.18 or (isHovered and 0.46 or 0.66)
        outline = isOn and 0.66 or 0.82
        titleColor = isOn and Theme.text or Theme.textMuted
        edge = isOn and 0.2 or 1
        rule = 1
    else
        surface = isOn and 0.18 or (isHovered and 0.5 or 0.74)
        titleColor = isOn and Theme.text or Theme.textMuted
        edge = isOn and 0.2 or 1
        rule = isOn and 1 or 0.72
    end

    local motion: TweenInfo = TweenInfo.new(
        UI_MOTION.base,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    local animate: boolean = state.animationsEnabled == true
    if animate then
        TweenService:Create(resolvedRow, motion, {
            BackgroundColor3 = Theme.surface,
            BackgroundTransparency = surface,
        }):Play()
    else
        resolvedRow.BackgroundColor3 = Theme.surface
        resolvedRow.BackgroundTransparency = surface
    end

    if feature.title then
        local titleLabel: TextLabel = feature.title :: TextLabel
        titleLabel.TextColor3 = titleColor
        titleLabel.TextTransparency = titleTransparency
    end
    if feature.stroke then
        local cardStroke: UIStroke = feature.stroke :: UIStroke
        cardStroke.Color = Theme.outline
        cardStroke.Transparency = outline
    end
    if feature.activeStripe then
        local stripe: Frame = feature.activeStripe :: Frame
        stripe.BackgroundColor3 = Theme.text
        if animate then
            TweenService:Create(stripe, motion, {BackgroundTransparency = edge}):Play()
        else
            stripe.BackgroundTransparency = edge
        end
    end
    if feature.cardRule then
        (feature.cardRule :: Frame).BackgroundTransparency = rule
    end
end

local function refreshFeatureToggle(feature: any): ()
    if feature.isCategory or feature.isAction then
        -- Neither has an on/off state, but both still need their skin applied
        -- once so a restyle does not leave them looking like a dead toggle.
        state.applyCardSkin(feature, false)
        if state.floatingUi then
            state.floatingUi.refreshFeature(feature)
        end
        return
    end
    -- A hold module has no enabled state: what it shows is whether its key is
    -- being held right now.
    if feature.isHoldAction then
        feature.enabled = feature.active == true
    end
    state.applyCardSkin(feature, false)
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
        and Theme.buttonHover
        or Theme.accentSoft

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
            button.BackgroundColor3 = success and Theme.accentSoft or Theme.negative
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
                and Theme.accentSoft
                or Theme.surface
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

    -- One place that takes a key.
    --
    -- A key is only ever taken after the slot has been *clicked*: the slot
    -- shows "..." and the next key press lands here. Hovering used to be
    -- enough, and that was a bug — the pointer resting over a slot turned
    -- every keystroke into a rebind. Pressing the key that is already bound
    -- clears the binding, so the slot never needs a second control.
    binding.assign = function(keyCode: Enum.KeyCode): boolean
        local cleared: boolean = keyCode == binding.key
        binding.key = cleared and Enum.KeyCode.Unknown or keyCode
        setShortcutPressed(binding, false)
        configData.values[optionKey] = binding.key.Name
        queueConfigSave()
        refreshButtonText()
        return not cleared
    end

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
            binding.assign(keyCode)
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


-- ---------------------------------------------------------------------------
-- Game bridge
-- ---------------------------------------------------------------------------
--
-- What a game module contributes to a universal module, instead of building a
-- second one of its own.
--
-- MM2 is the worked example. It used to ship a whole "Player ESP" card —
-- boxes, chams, per-role colours, coins, traps — living on the MM2 page next
-- to the universal Player ESP, which did all the same drawing and knew none of
-- the roles. Two implementations of one idea, and only one of them had the
-- corner boxes, the skeleton, the tracers and the name plates.
--
-- Now a game module registers what only *it* can know:
--
--   * a role provider — the list of roles in this game, a colour for each and
--     a function that answers "what is this player". Every drawing path in the
--     universal ESP asks it for the colour, so roles work with corner boxes,
--     full boxes, chams, tracers, health bars and name tags at once;
--   * ESP extras — the objects only this game has (MM2's coins and traps, its
--     dropped gun). Each one becomes a toggle and a colour row inside the
--     universal ESP card, and the game module keeps its own implementation.
--
-- Everything here is optional: an unsupported game registers nothing and the
-- universal ESP looks exactly as it always did.
state.gameBridge = {
    roleProvider = nil :: any,
    extras = {} :: {any},
    listeners = {} :: {(string, any) -> ()},
}

state.onGameBridge = function(listener: (string, any) -> ()): ()
    table.insert(state.gameBridge.listeners, listener)
    -- Replay what is already registered: a game module can be loaded before or
    -- after the module that consumes it, and neither may care.
    if state.gameBridge.roleProvider then
        pcall(listener, "roles", state.gameBridge.roleProvider)
    end
    for _, extra: any in ipairs(state.gameBridge.extras) do
        pcall(listener, "extra", extra)
    end
end

state.registerRoleProvider = function(provider: any): ()
    if type(provider) ~= "table" or type(provider.Get) ~= "function" then
        return
    end
    state.gameBridge.roleProvider = provider
    for _, listener: (string, any) -> () in ipairs(state.gameBridge.listeners) do
        pcall(listener, "roles", provider)
    end
end

state.registerEspExtra = function(extra: any): ()
    if type(extra) ~= "table" or type(extra.Name) ~= "string" then
        return
    end
    table.insert(state.gameBridge.extras, extra)
    for _, listener: (string, any) -> () in ipairs(state.gameBridge.listeners) do
        pcall(listener, "extra", extra)
    end
end

-- Asked by anything that wants to colour a player by role (the ESP, and the
-- target readouts that follow it). Returns nil in a game with no roles.
state.playerRole = function(player: Player): string?
    local provider: any = state.gameBridge.roleProvider
    if not provider then
        return nil
    end
    local ok: boolean, role: any = pcall(provider.Get, player)
    if ok and type(role) == "string" and role ~= "" then
        return role
    end
    return nil
end


state.featureTooltip = create("TextLabel", {
    TextTruncate = Enum.TextTruncate.AtEnd,
    ClipsDescendants = true,
    Parent = PopupLayer,
    Name = "FeatureTooltip",
    Active = false,
    AutomaticSize = Enum.AutomaticSize.None,
    BackgroundColor3 = Theme.surface,
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


-- Overwritten by the Friend List module the moment it loads; this is the
-- answer for the seconds before that, and for a client where the module fails
-- to download.
state.isProtectedTarget = function(_targetPlayer: Player): boolean
    return false
end


-- The one shared board. The name stays because every downloaded game module
-- still asks for `MM2Scroll`.
local MM2Scroll: ScrollingFrame = UniversalScroll


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
    print("[" .. PRODUCT.logPrefix .. ":Bootstrap] " .. message)
end

-- The build used to be printed on the intro; the intro carries no words now,
-- so it goes to the console where a bug report can still quote it.
print("[RTM] build loader-v3")

state.logBootstrapError = function(message: string): ()
    warn("[" .. PRODUCT.logPrefix .. ":Bootstrap] " .. message)
end

-- The option builders, once src/library/Widgets.luau has been downloaded.
--
-- Nil until then, which is why the widget library is the very first thing the
-- loader fetches: a module that builds its panel against a half-filled
-- environment fails in the middle of drawing it, and a card with no controls
-- is worse than no card.
local widgetBuilders: any = nil

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
        -- The product's identity, so nothing downstream retypes a name
        -- or a folder that the shell already owns.
        PRODUCT = PRODUCT,
        Theme = Theme,
        -- The engine, so a library can bind an instance to a token instead of
        -- copying a colour into it once and going stale at the next preset.
        ThemeEngine = ThemeEngine,
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
        -- Both of these existed in the shell from the start and neither was
        -- ever published here. Five modules called `addFeatureTooltip` while
        -- building their card, got nil, and died mid-init — five cards that
        -- simply were not in the menu, on every client, for a week. Rejoin
        -- Server calls `cloneReference` only when its button is pressed, so it
        -- loaded fine and broke on the click instead.
        addFeatureTooltip = addFeatureTooltip,
        cloneReference = cloneReference,

        -- The primitives the widget library builds its controls out of. They
        -- are shell-owned — one `create`, one set of design tokens, one config
        -- store — and a game module drawing its own interface uses the same
        -- ones, which is why they are published rather than passed.
        PopupLayer = PopupLayer,
        UI_RADIUS = UI_RADIUS,
        UI_MOTION = UI_MOTION,
        cornerRadius = cornerRadius,
        setKeySlotCapture = setKeySlotCapture,
        -- The Config. page frame and the helper that files a row into the
        -- right column of a card grid: the settings page fills a layout the
        -- shell owns rather than laying itself out.
        SettingsPage = SettingsPage,
        getFeatureCardParent = getFeatureCardParent,
        -- Where this runtime came from, for the page that shows it and
        -- re-injects it.
        REPOSITORY_RAW_BASE = REPOSITORY_RAW_BASE,
        RUNTIME_SAFETY_SOURCE_URL = RUNTIME_SAFETY_SOURCE_URL,
        RUNTIME_COMPATIBILITY_MARKER = RUNTIME_COMPATIBILITY_MARKER,
        SOURCE_STAMP = SOURCE_STAMP,
        -- Text scale bounds, so a slider cannot offer a size the rest of the
        -- interface refuses to render.
        TEXT_BASE_MULTIPLIER = TEXT_BASE_MULTIPLIER,
        TEXT_SCALE_MINIMUM = TEXT_SCALE_MINIMUM,
        TEXT_SCALE_MAXIMUM = TEXT_SCALE_MAXIMUM,
        registeredText = registeredText,
        -- The window frame and the viewport the shell measured at start: the
        -- mobile layer hides the window while a shortcut is being placed and
        -- keeps a placed button inside the screen.
        Main = Main,
        initialViewport = initialViewport,
        -- Used by the floating overlays: the profile card's fixed height, the
        -- readout typeface, and the tab switcher a favourite jumps through.
        -- What the card factory builds a card out of: the taxonomy that files
        -- it under a section, the default board, and the registries it joins.
        FEATURE_CATEGORIES = FEATURE_CATEGORIES,
        DEFAULT_FEATURE_CATEGORY = DEFAULT_FEATURE_CATEGORY,
        UniversalScroll = UniversalScroll,
        universalFeatures = universalFeatures,
        movementFeatures = movementFeatures,
        applyFeaturePresentation = applyFeaturePresentation,
        refreshFeatureToggle = refreshFeatureToggle,
        PROFILE_CARD_HEIGHT = PROFILE_CARD_HEIGHT,
        VALVE_FONT = VALVE_FONT,
        setTab = setTab,
        trackUiConnection = trackUiConnection,
        createToggleSwitch = createToggleSwitch,
        setToggleSwitch = setToggleSwitch,
        applyKeySlotStyle = applyKeySlotStyle,
        beginKeyCapture = beginKeyCapture,
        bindActionShortcut = bindActionShortcut,
        runActionButton = runActionButton,
        colorFromConfig = colorFromConfig,
        colorToConfig = colorToConfig,
        -- The game bridge: how a game module teaches the universal modules
        -- about its roles and its own objects.
        registerRoleProvider = state.registerRoleProvider,
        registerEspExtra = state.registerEspExtra,
        onGameBridge = state.onGameBridge,
        playerRole = state.playerRole,
        findPlayerByText = findPlayerByText,
        performFling = performFling,
        MM2Scroll = MM2Scroll,
        mm2Features = mm2Features,
        vdFeatures = state.vdFeatures,
        bedFightFeatures = state.bedFightFeatures,
        mvsdFeatures = state.mvsdFeatures,
        allFeatures = allFeatures,
        cleanupMM2Runtime = cleanupMM2Runtime,
    }
    -- Every option builder, under the exact name a module calls it with. They
    -- arrive from the widget library rather than from this file, so the loop
    -- is what keeps the environment and the library from drifting apart: a
    -- builder added there needs no line here.
    --
    -- A builder missing from this table takes the rest of a module's panel
    -- down with it — that is how Kill Aura once rendered a "Weapon" heading
    -- and nothing under it, back when multi-select lists were listed by hand
    -- and one name was forgotten.
    for builderName: string, builder: any in pairs(widgetBuilders or {}) do
        environment[builderName] = recordBinding(builder)
    end
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
        .. ".luau?v="
        .. SOURCE_STAMP
    state.logBootstrap("Descargando módulo: " .. moduleUrl)
    local downloadSuccess: boolean, source: any = false, nil
    if type(state.fetchRepositorySource) == "function" then
        local fetched: string?, fetchError: string? =
            state.fetchRepositorySource("src/games/" .. moduleName .. ".luau")
        if fetched then
            source = fetched
            downloadSuccess = true
        else
            source = fetchError
        end
    else
        downloadSuccess, source = pcall(function(): string
            return (game :: any):HttpGet(moduleUrl, true)
        end)
    end
    if downloadSuccess and type(source) == "string" then
        local candidate: string = string.lower(source)
        if #source < 64
            or string.find(candidate, "404: not found", 1, true)
            or string.find(candidate, "<!doctype html", 1, true)
            or string.find(candidate, "<html", 1, true) then
            warn("[" .. PRODUCT.logPrefix .. ":Bootstrap] Respuesta remota inválida para " .. moduleName)
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
                warn("[" .. PRODUCT.logPrefix .. ":Bootstrap] HTTP falló; usando fallback local " .. localPath)
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
        elseif tabName == "BedFight" then
            state.cleanupBedFightRuntime = destroyModule
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
registerPlaceModule("BedFight", GAME_CHECK.BedFight)

if PENDING_FINGERPRINT then
    task.spawn(function(): ()
        local attempts: number = 0
        while attempts < 6 do
            attempts += 1
            task.wait(0.5)
            local detected: string?, score: number = detectGameModuleByStructure()
            if detected then
                ACTIVE_GAME_MODULE = detected
                ACTIVE_GAME_SOURCE = "fingerprint " .. tostring(score) .. " markers"
                state.activeGameName = detected
                GAME_CHECK.MM2Active = detected == "MM2"
                GAME_CHECK.TRSActive = detected == "TRS"
                GAME_CHECK.VDActive = detected == "VD"
                GAME_CHECK.MVSDActive = detected == "MVSD"
                GAME_CHECK.BedFightActive = detected == "BedFight"
                GAME_CHECK.source = ACTIVE_GAME_SOURCE
                PENDING_FINGERPRINT = false
                registerPlaceModule(detected, GAME_CHECK[detected] or 0)
                SectionManager.initialize(detected)
                break
            end
        end
    end)
end

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
--
-- Delivery: prefer one stamped bundle (shell + bundle = two requests). The
-- gate refuses a bundle whose stamp does not match the sources. If the bundle
-- is missing or stale, fall back to a bounded parallel download of the same
-- files, then loadstring+init in manifest order so behaviour is identical.
state.boot = {
    stamp = SOURCE_STAMP,
    bundle = nil :: {[string]: string}?,
    sources = {} :: {[string]: string},
    timing = {} :: {[string]: number},
    started = BOOT_STARTED_AT,
}
-- Everything before the loader: the window, the rail, the boards, the mobile
-- layer. It is measured as one block because it is one straight line of work.
state.boot.timing.gui = os.clock() - BOOT_STARTED_AT

state.markBoot = function(phase: string, startedAt: number): ()
    state.boot.timing[phase] = os.clock() - startedAt
end

state.summarizeBoot = function(): ()
    local timing: any = state.boot.timing
    local total: number = os.clock() - (state.boot.started or os.clock())
    print(string.format(
        "[" .. PRODUCT.logPrefix .. ":Timing] fingerprint %.2fs · gui %.2fs · bundle %.2fs · manifest %.2fs · widgets %.2fs · framework %.2fs · libraries %.2fs · modules %.2fs (%d/%d) · game module %.2fs · total %.2fs",
        BOOT_FINGERPRINT_SECONDS,
        tonumber(timing.gui) or 0,
        tonumber(timing.bundle) or 0,
        tonumber(timing.manifest) or 0,
        tonumber(timing.widgets) or 0,
        tonumber(timing.framework) or 0,
        tonumber(timing.libraries) or 0,
        tonumber(timing.modules) or 0,
        tonumber(timing.moduleCount) or 0,
        tonumber(timing.moduleTotal) or 0,
        tonumber(timing.game) or 0,
        total
    ))
end

-- Reject a response that is technically a 200 but is not a source file:
-- GitHub answers a bad path with a plain-text "404: Not Found" and a captive
-- portal answers everything with HTML.
--
-- Only the head of the response is examined. Lowercasing and scanning the
-- whole thing meant half a megabyte of copying to answer a question about the
-- first line, and it made any file that merely *mentions* `<html` anywhere in
-- its own source unloadable — a trap with no warning attached.
state.sourceLooksValid = function(source: any, minimum: number): boolean
    if type(source) ~= "string" or #source < minimum then
        return false
    end
    local head: string = string.lower(string.sub(source, 1, 512))
    return string.find(head, "404: not found", 1, true) == nil
        and string.find(head, "<!doctype html", 1, true) == nil
        and string.find(head, "<html", 1, true) == nil
end

state.httpGetPath = function(path: string): (string?, string?)
    local url: string = REPOSITORY_RAW_BASE .. path .. "?v=" .. SOURCE_STAMP
    local ok: boolean, body: any = pcall(function(): string
        return (game :: any):HttpGet(url, true)
    end)
    if ok and state.sourceLooksValid(body, 32) then
        return body :: string, nil
    end
    return nil, tostring(body)
end

state.ensureSourceFolders = function(path: string): ()
    local environment: any = getfenv()
    if type(environment.makefolder) ~= "function" then
        return
    end
    pcall(environment.makefolder, "ARandomMenu")
    local cursor: string = "ARandomMenu"
    for segment: string in string.gmatch(path, "([^/]+)/") do
        cursor = cursor .. "/" .. segment
        pcall(environment.makefolder, cursor)
    end
end

state.readCachedSource = function(path: string): string?
    local environment: any = getfenv()
    local readFile: any = environment.readfile
    local isFile: any = environment.isfile
    if type(readFile) ~= "function" then
        return nil
    end
    local stampFile: string = "ARandomMenu/.stamp"
    if type(isFile) == "function" then
        local stampOk: boolean, stampExists: any = pcall(isFile, stampFile)
        if not stampOk or not stampExists then
            return nil
        end
    end
    local stampOk: boolean, stampBody: any = pcall(readFile, stampFile)
    if not stampOk or stampBody ~= SOURCE_STAMP then
        return nil
    end
    local localPath: string = "ARandomMenu/" .. path
    if type(isFile) == "function" then
        local fileOk: boolean, exists: any = pcall(isFile, localPath)
        if not fileOk or not exists then
            return nil
        end
    end
    local readOk: boolean, source: any = pcall(readFile, localPath)
    if readOk and state.sourceLooksValid(source, 32) then
        return source :: string
    end
    return nil
end

state.writeCachedSource = function(path: string, source: string): ()
    local environment: any = getfenv()
    local writeFile: any = environment.writefile
    if type(writeFile) ~= "function" then
        return
    end
    state.ensureSourceFolders(path)
    pcall(writeFile, "ARandomMenu/" .. path, source)
    pcall(writeFile, "ARandomMenu/.stamp", SOURCE_STAMP)
end

state.fetchRepositorySource = function(path: string): (string?, string?)
    local bundled: any = state.boot.bundle and state.boot.bundle[path]
    if type(bundled) == "string" then
        state.boot.sources[path] = bundled
        return bundled, nil
    end
    local remembered: string? = state.boot.sources[path]
    if remembered then
        return remembered, nil
    end
    local cached: string? = state.readCachedSource(path)
    if cached then
        state.boot.sources[path] = cached
        return cached, nil
    end
    local downloaded: string?, downloadError: string? = state.httpGetPath(path)
    if downloaded then
        state.boot.sources[path] = downloaded
        state.writeCachedSource(path, downloaded)
        return downloaded, nil
    end
    local environment: any = getfenv()
    local readFile: any = environment.readfile
    local isFile: any = environment.isfile
    local localPath: string = "ARandomMenu/" .. path
    if type(readFile) == "function"
        and (type(isFile) ~= "function" or isFile(localPath)) then
        local readOk: boolean, localSource: any = pcall(readFile, localPath)
        if readOk and state.sourceLooksValid(localSource, 32) then
            state.boot.sources[path] = localSource
            return localSource :: string, nil
        end
    end
    return nil, downloadError or ("Descarga fallida: " .. path)
end

state.compileRepositorySource = function(path: string, source: string): (any, string?)
    local environment: any = getfenv()
    if type(environment.loadstring) ~= "function" then
        return nil, "El ejecutor no admite loadstring"
    end
    local chunk: any, compileError: any = environment.loadstring(source, "@" .. path)
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

state.fetchRepositoryChunk = function(path: string): (any, string?)
    local source: string?, sourceError: string? = state.fetchRepositorySource(path)
    if not source then
        return nil, sourceError
    end
    return state.compileRepositorySource(path, source :: string)
end

state.downloadSourcesParallel = function(paths: {string}): ()
    local pending: number = #paths
    if pending == 0 then
        return
    end
    local index: number = 0
    local workers: number = math.min(8, pending)
    local timedOut: boolean = false
    for _ = 1, workers do
        task.spawn(function(): ()
            while not timedOut do
                index += 1
                local current: number = index
                if current > #paths then
                    return
                end
                local path: string = paths[current]
                if not state.boot.sources[path] then
                    -- pcall'd, and the counter moves either way. A throw in
                    -- one file used to kill its worker with the count still
                    -- owing, which stalled the whole load for the full twelve
                    -- seconds before the recovery below even started.
                    local ok: boolean, source: any = pcall(
                        state.fetchRepositorySource,
                        path
                    )
                    if ok and type(source) == "string" then
                        state.boot.sources[path] = source
                    end
                end
                pending -= 1
            end
        end)
    end
    local deadline: number = os.clock() + 12
    while pending > 0 and os.clock() < deadline do
        task.wait(0.03)
    end
    if pending > 0 then
        timedOut = true
        -- Finish the job on this thread. The result has to be *kept*: this
        -- used to call the fetch and drop what it returned, so every file the
        -- workers had not reached was downloaded here, thrown away, and then
        -- downloaded a third time by the loader.
        for _, path: string in ipairs(paths) do
            if not state.boot.sources[path] then
                local source: string? = state.fetchRepositorySource(path)
                if source then
                    state.boot.sources[path] = source
                end
            end
        end
    end
end

do
(function(): ()
local diagnostics: ModuleDiagnostics = {uiBindings = 0, taskBindings = 0}
state.frameworkEnvironment = createGameModuleEnvironment(diagnostics)

-- Kept in step with src/core/Manifest.luau by the validation workflow.
local fallbackManifest: any = {
    version = 1,
    widgets = "src/library/Widgets.luau",
    core = {"src/core/Framework.luau"},
    libraries = {
        "src/library/Entity.luau",
        "src/library/Weapons.luau",
        "src/library/Render.luau",
        "src/library/Cards.luau",
        "src/library/WindowManager.luau",
        "src/library/FloatingWindows.luau",
        "src/library/SettingsPage.luau",
        "src/library/MobileActions.luau",
    },
    modules = {
        {path = "src/modules/Utility/FriendList.luau", name = "Friend List", category = "Utility"},
        {path = "src/modules/Visuals/ItemRender.luau", name = "Item Render", category = "Visuals"},
        {path = "src/modules/Visuals/PlayerESP.luau", name = "Player ESP", category = "Visuals"},
        {path = "src/modules/Combat/KillAura.luau", name = "Kill Aura", category = "Combat"},
        {path = "src/modules/Utility/RemoteLogger.luau", name = "Remote Logger", category = "Utility"},
        {path = "src/modules/Movement/ClickTeleport.luau", name = "Click Teleport", category = "Movement"},
        {path = "src/modules/Combat/AutoClicker.luau", name = "Auto Clicker", category = "Combat"},
        {path = "src/modules/Combat/TriggerBot.luau", name = "TriggerBot", category = "Combat"},
        {path = "src/modules/Visuals/XRay.luau", name = "X-Ray", category = "Visuals"},
        {path = "src/modules/Movement/HighJump.luau", name = "High Jump", category = "Movement"},
        {path = "src/modules/Movement/Spider.luau", name = "Spider", category = "Movement"},
        {path = "src/modules/Protection/SafeWalk.luau", name = "Safe Walk", category = "Protection"},
        {path = "src/modules/Utility/RejoinServer.luau", name = "Rejoin Server", category = "Utility"},
        {path = "src/modules/Visuals/ZoomUnlocker.luau", name = "Zoom Unlocker", category = "Visuals"},
        {path = "src/modules/Utility/InteractExtender.luau", name = "Interact Extender", category = "Utility"},
        {path = "src/modules/Movement/PhaseDash.luau", name = "Phase Dash", category = "Movement"},
        {path = "src/modules/Protection/NoFall.luau", name = "No Fall", category = "Protection"},
        {path = "src/modules/Movement/Fly.luau", name = "Fly", category = "Movement"},
        {path = "src/modules/Movement/VehicleSpeed.luau", name = "Vehicle Speed", category = "Movement"},
        {path = "src/modules/Protection/AntiVoid.luau", name = "Anti-Void", category = "Protection"},
        {path = "src/modules/Utility/Gravity.luau", name = "Gravity", category = "Utility"},
        {path = "src/modules/Movement/JumpPower.luau", name = "Jump Power", category = "Movement"},
        {path = "src/modules/Movement/InfiniteJump.luau", name = "Infinite Jump", category = "Movement"},
        {path = "src/modules/Visuals/FieldOfView.luau", name = "FOV", category = "Visuals"},
        {path = "src/modules/Movement/Noclip.luau", name = "Noclip", category = "Movement"},
        {path = "src/modules/Utility/AntiAfk.luau", name = "Anti-AFK", category = "Utility"},
        {path = "src/modules/Protection/AntiFling.luau", name = "Anti-Fling", category = "Protection"},
        {path = "src/modules/Utility/LagSwitch.luau", name = "Lag Switch", category = "Utility"},
        {path = "src/modules/Utility/Fling.luau", name = "Fling", category = "Utility"},
        {path = "src/modules/Utility/ImproveFps.luau", name = "Improve FPS", category = "Utility"},
        {path = "src/modules/Visuals/Fullbright.luau", name = "Fullbright", category = "Visuals"},
        {path = "src/modules/Movement/FreezeMovements.luau", name = "Freeze Movements", category = "Movement"},
        {path = "src/modules/Movement/Speed.luau", name = "Speed", category = "Movement"},
        {path = "src/modules/Combat/Hitboxes.luau", name = "Hitboxes", category = "Combat"},
        {path = "src/modules/Combat/ProjectileCalibration.luau", name = "Projectile Calibration", category = "Combat"},
        {path = "src/modules/Spoof/Disguise.luau", name = "Disguise", category = "Spoof"},
        {path = "src/modules/Spoof/AnimationChanger.luau", name = "Animation Changer", category = "Spoof"},
        {path = "src/modules/Spoof/EmotePlayer.luau", name = "Emote Player", category = "Spoof"},
    },
}

local bundleAt: number = os.clock()
local packed: any, packedError: string? = state.fetchRepositoryChunk("runtime/bundle.luau")
if type(packed) == "table"
    and packed.stamp == SOURCE_STAMP
    and type(packed.files) == "table" then
    state.boot.bundle = packed.files
    state.logBootstrap("Bundle aceptado · stamp=" .. SOURCE_STAMP)
else
    if packedError then
        state.logBootstrapError("Bundle: " .. packedError)
    elseif type(packed) == "table" then
        state.logBootstrapError(
            "Bundle stamp mismatch: got "
                .. tostring(packed.stamp)
                .. " expected "
                .. SOURCE_STAMP
        )
    end
    state.boot.bundle = nil
end
state.markBoot("bundle", bundleAt)

local manifestAt: number = os.clock()
local manifest: any, manifestError: string? =
    state.fetchRepositoryChunk("src/core/Manifest.luau")
if type(manifest) ~= "table" or type(manifest.modules) ~= "table" then
    if manifestError then
        state.logBootstrapError("Manifest: " .. manifestError)
    end
    manifest = fallbackManifest
end
state.markBoot("manifest", manifestAt)

local loadList: {string} = {}
table.insert(loadList, manifest.widgets or "src/library/Widgets.luau")
for _, path: string in ipairs(manifest.core or {}) do
    table.insert(loadList, path)
end
for _, path: string in ipairs(manifest.libraries or {}) do
    table.insert(loadList, path)
end
for _, entry: any in ipairs(manifest.modules or {}) do
    table.insert(loadList, type(entry) == "table" and entry.path or tostring(entry))
end
if not state.boot.bundle then
    state.downloadSourcesParallel(loadList)
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

local widgetsAt: number = os.clock()
local widgetPath: string = manifest.widgets or "src/library/Widgets.luau"
local widgetPiece: any? = loadPiece(widgetPath)
if widgetPiece then
    local widgetOk: boolean, builders: any = pcall(
        widgetPiece.init,
        state.frameworkEnvironment
    )
    if widgetOk and type(builders) == "table" then
        table.insert(loaded, widgetPiece)
        widgetBuilders = builders
        for builderName: string, builder: any in pairs(builders) do
            state.frameworkEnvironment[builderName] = function(...: any): any
                diagnostics.uiBindings += 1
                return builder(...)
            end
        end
    else
        state.logBootstrapError("Widgets init falló: " .. tostring(builders))
    end
end
state.markBoot("widgets", widgetsAt)
if not widgetBuilders then
    state.logBootstrapError(
        "Sin librería de controles; los módulos no pueden construir sus paneles"
    )
    notify("No se pudo cargar la librería de controles")
    state.summarizeBoot()
    return
end

local frameworkAt: number = os.clock()
local frameworkPiece: any? = loadPiece(manifest.core[1] or "src/core/Framework.luau")
if not frameworkPiece then
    state.logBootstrapError("Framework no disponible; módulos externos omitidos")
    state.summarizeBoot()
    return
end
local frameworkOk: boolean, framework: any = pcall(
    frameworkPiece.init,
    state.frameworkEnvironment
)
if not frameworkOk or type(framework) ~= "table" then
    state.logBootstrapError("Framework init falló: " .. tostring(framework))
    state.summarizeBoot()
    return
end
table.insert(loaded, frameworkPiece)
state.framework = framework
state.markBoot("framework", frameworkAt)

local librariesAt: number = os.clock()
local libraries: any = {}
for _, path: string in ipairs(manifest.libraries or {}) do
    local piece: any? = loadPiece(path)
    if not piece then
        continue
    end
    local startedOk: boolean, library: any = pcall(
        piece.init,
        state.frameworkEnvironment
    )
    if not startedOk or type(library) ~= "table" then
        state.logBootstrapError(
            "Librería falló (" .. path .. "): " .. tostring(library)
        )
        continue
    end
    table.insert(loaded, piece)
    local key: string = string.lower(
        string.match(path, "([^/]+)%.luau$") or path
    )
    libraries[key] = library
end
-- The card factory is a library too, and it arrives after the environment was
-- built. Folding it into the same table the option builders use means the one
-- install path covers both, here and in every environment a game module gets
-- later.
local cardLibrary: any = libraries.cards
if cardLibrary and type(cardLibrary.createUniversalFeature) == "function" then
    widgetBuilders.createUniversalFeature = cardLibrary.createUniversalFeature
    state.frameworkEnvironment.createUniversalFeature = function(...: any): any
        diagnostics.uiBindings += 1
        return cardLibrary.createUniversalFeature(...)
    end
else
    state.logBootstrapError("Sin fábrica de tarjetas; ningún módulo puede crear su tarjeta")
    notify("No se pudo cargar la fábrica de tarjetas")
    return
end

local entityLibrary: any = libraries.entity
state.weaponLibrary = libraries.weapons
state.renderLibrary = libraries.render
state.markBoot("libraries", librariesAt)

local context: any = {
    framework = framework,
    entity = entityLibrary,
    weapons = libraries.weapons,
    render = libraries.render,
    libraries = libraries,
    host = state.frameworkEnvironment,
}
local modulesAt: number = os.clock()
local moduleCount: number = 0
for _, entry: any in ipairs(manifest.modules) do
    local path: string = type(entry) == "table" and entry.path or tostring(entry)
    local piece: any? = loadPiece(path)
    if piece then
        local started: boolean, failure: any = pcall(piece.init, context)
        if started then
            table.insert(loaded, piece)
            moduleCount += 1
            state.logBootstrap("Módulo cargado: " .. path)
        else
            state.logBootstrapError(
                "Módulo falló (" .. path .. "): " .. tostring(failure)
            )
        end
    end
end
state.boot.timing.moduleCount = moduleCount
state.boot.timing.moduleTotal = #manifest.modules
state.markBoot("modules", modulesAt)

-- A module that fails to start is a card that is simply not there, and the
-- only trace was one `warn` among the loading chatter. Five of thirty-eight
-- went missing on a real client for a week before anyone counted them.
if moduleCount < #manifest.modules then
    local missing: number = #manifest.modules - moduleCount
    state.logBootstrapError(
        tostring(missing)
            .. " de "
            .. tostring(#manifest.modules)
            .. " módulos no arrancaron; busca \"Módulo falló\" más arriba"
    )
    notify(tostring(missing) .. " módulos no cargaron — revisa la consola")
end

state.cleanupFrameworkRuntime = function(): ()
    for index: number = #loaded, 1, -1 do
        local piece: any = loaded[index]
        if type(piece.destroy) == "function" then
            pcall(piece.destroy)
        end
    end
    table.clear(loaded)
    state.framework = nil
    state.renderLibrary = nil
end
state.summarizeBoot()
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
    label.TextColor3 = Theme.textMuted
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Visible = false
    label.ZIndex = 90
    noResultsLabels[sectionName] = label
end

local function refreshSearch(): ()
    local query: string = string.lower(tostring(state.searchQuery or ""))
    query = string.match(query, "^%s*(.-)%s*$") or ""
    -- One board means one count: a card's registry ("MM2", "BedFight") used to
    -- name the page it lived on, and there is no such page any more.
    local totalMatches: number = 0
    for _, feature: any in ipairs(allFeatures) do
        local searchable: string = feature.searchText
        local matches: boolean = query == ""
            or string.find(searchable, query, 1, true) ~= nil
        feature.row.Visible = matches
        if matches then
            totalMatches += 1
        end
        if feature.title then
            if query ~= "" and matches and not feature.enabled then
                feature.title.TextColor3 = Theme.accent
            else
                applyFeaturePresentation(feature, state.guiStyle == "Default")
            end
        end
    end

    for sectionName: string, label: TextLabel in pairs(noResultsLabels) do
        label.Visible = sectionName == "Universal"
            and #allFeatures > 0
            and totalMatches == 0
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

-- The Config. page is `src/library/SettingsPage.luau`. It publishes its
-- builder when it loads; this only says which tab it fills and when.
--
-- Raising here is deliberate: `SectionManager.initialize` catches it and
-- prints it on the page itself, which is a far better answer than a tab that
-- opens onto nothing.
SectionManager.register("Config.", function(): ()
    local builder: any = state.buildSettingsPage
    if type(builder) ~= "function" then
        error("src/library/SettingsPage.luau no se cargó")
    end
    builder()
end)

-- Restore the saved typeface once the interface exists. A repository font is a
-- download, so this waits its turn on its own thread rather than holding the
-- menu closed while it arrives.
do
    local savedFont: string = tostring(configData.values.interfaceFont or "")
    if savedFont ~= "" and savedFont ~= "Menu default" then
        task.spawn(function(): ()
            state.applyInterfaceFont(savedFont, false)
        end)
    end
end

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
        warn("[" .. PRODUCT.name .. "] destruct/" .. label .. ": " .. tostring(failure))
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
        -- Two connections the picker keeps alive between openings, so the drag
        -- keeps tracking once the pointer leaves the saturation square. The
        -- picker belongs to the widget library, which may never have loaded.
        local picker: any = state.colorPicker
        if not picker then
            return
        end
        if picker.inputChanged then
            picker.inputChanged:Disconnect()
        end
        if picker.inputEnded then
            picker.inputEnded:Disconnect()
        end
    end)
    cleanupStep("MM2 runtime", cleanupMM2Runtime)
    for _, key: string in ipairs({
        "cleanupFrameworkRuntime",
        "cleanupTRSRuntime",
        "cleanupVDRuntime",
        "cleanupMVSDRuntime",
        "cleanupBedFightRuntime",
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
    print("[" .. PRODUCT.name .. "] Destruct complete.")
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
    PRODUCT.name
        .. " v"
        .. PRODUCT.version
        .. " | Toggle key: "
        .. state.toggleKey.Name
)
-- On a keyboard the launcher is not drawn, so this toast is the only thing
-- that says the menu is loaded and which key opens it.
if not state.isMobile then
    notify("Menu ready — press " .. state.toggleKey.Name)
end
end

local initialized: boolean, bootstrapError: any = xpcall(bootstrap, function(message: any): string
    local text: string = tostring(message)
    if debug and type(debug.traceback) == "function" then
        return debug.traceback("[" .. PRODUCT.logPrefix .. ":Bootstrap] " .. text, 2)
    end
    return "[" .. PRODUCT.logPrefix .. ":Bootstrap] " .. text
end)

if not initialized then
    -- Nowhere on screen to say it any more: the intro that used to carry the
    -- message is gone, so the console is the report.
    warn("[" .. PRODUCT.logPrefix .. ":Bootstrap] Inicialización detenida:\n" .. tostring(bootstrapError))
end
