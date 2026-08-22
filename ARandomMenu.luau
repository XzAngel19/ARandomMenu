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
--
-- Wurst has no "General": an uncategorised feature belongs to Other, which is
-- a real window with a real name at the pinned commit.
local DEFAULT_FEATURE_CATEGORY: string = "Other"

-- The shared category contract: official Wurst 7 windows, in the exact order
-- ClickGui.init() builds them at 4a22e53d. Every surface that names a
-- category — the framework's taxonomy, the ClickGUI grid, the card factory —
-- resolves against this list and nothing else.
local OFFICIAL_CATEGORIES: {string} = {
    "Combat",
    "Render",
    "Blocks",
    "Movement",
    "Chat",
    "Fun",
    "Items",
    "Other",
}

-- The port's old names, funnelled into official windows until D refiles each
-- card (docs/wurst-categories.md carries the per-card mapping). An alias is a
-- bridge, not a home: it exists so no module ever lands in a window that is
-- not one of Wurst's eight while the per-module moves happen in D's lane.
--   Visuals    → Render    (ESP, lighting, camera — Wurst's Render)
--   Protection → Movement  (NoFall, SafeWalk map there in the Java; the rest
--                           D moves individually)
--   Utility    → Other     (AntiAFK, Reach, AutoReconnect live in Other)
--   Spoof      → Fun       (no Wurst window; Fun is where Wurst keeps the
--                           appearance toys)
local CATEGORY_ALIASES: {[string]: string} = {
    ["Visuals"] = "Render",
    ["Protection"] = "Movement",
    ["Utility"] = "Other",
    ["Spoof"] = "Fun",
    ["General"] = "Other",
    ["Player"] = "Movement",
}

local function normalizeFeatureCategory(name: any): string
    local resolved: string = tostring(name or DEFAULT_FEATURE_CATEGORY)
    if table.find(OFFICIAL_CATEGORIES, resolved) ~= nil then
        return resolved
    end
    return CATEGORY_ALIASES[resolved] or DEFAULT_FEATURE_CATEGORY
end

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
    ["FOV"] = "Render",
    ["Fullbright"] = "Render",
    ["Player ESP"] = "Render",
    ["X-Ray"] = "Render",
    ["Zoom Unlocker"] = "Render",

    -- Protection
    ["Anti-Fling"] = "Movement",
    ["Anti-Void"] = "Movement",
    ["Safe Walk"] = "Movement",
    ["No Fall"] = "Movement",

    -- Utility
    ["Anti-AFK"] = "Other",
    ["Fling"] = "Other",
    ["Gravity"] = "Other",
    ["Improve FPS"] = "Other",
    ["Interact Extender"] = "Other",
    ["Lag Switch"] = "Other",
    ["Rejoin Server"] = "Other",

    -- Everything a game module adds is filed here too.
    --
    -- A game module used to get a page of its own, so its cards never needed a
    -- category and every one of them landed in the catch-all. They are modules
    -- like any other now — BedFight's Server Aura is a combat module, its
    -- Scaffold is a movement module — so the taxonomy names them here, in one
    -- table, instead of asking five game files to describe themselves.

    -- MM2
    ["Instant Role Notify"] = "Other",
    ["Shoot"] = "Combat",
    ["Trajectory Calibration"] = "Combat",
    ["Knife"] = "Combat",
    ["Loop All Interact"] = "Other",
    ["Silence"] = "Other",
    ["Auto Play ID"] = "Other",
    ["Sprint"] = "Movement",
    ["Always Show Timer"] = "Render",
    ["Teleport"] = "Movement",
    ["Role Fling"] = "Other",
    ["Hide Names"] = "Movement",

    -- TRS
    ["Auto Tackle"] = "Combat",
    ["Auto Dribble"] = "Combat",
    ["Auto Pickup"] = "Other",
    ["Pass Assist"] = "Combat",
    ["Shoot Assist"] = "Combat",
    ["Power Shot"] = "Combat",
    ["Large Shoot"] = "Combat",
    ["Best Goal Visual"] = "Render",
    ["Ball Trajectory"] = "Render",
    ["Goalkeeper Assist"] = "Combat",
    ["Auto Header"] = "Combat",

    -- VD
    ["Auto Generator"] = "Other",
    ["Auto Parry / Auto Block"] = "Movement",
    ["Killer Hit Aura"] = "Combat",
    ["Fast Vault Optimizer"] = "Movement",
    ["Cooldown Modifier"] = "Other",
    ["Damage Boost"] = "Movement",
    ["Noclip (Vaults & Pallets)"] = "Movement",
    ["WalkSpeed Hack"] = "Movement",
    ["Silent Steps / Anti-Sound"] = "Movement",
    ["Killer Proximity Visualizer"] = "Render",
    ["Line of Sight ESP"] = "Render",
    ["Locker & Hideout Detector"] = "Render",
    ["Killer Power Cooldowns"] = "Render",
    ["VD Field of View"] = "Render",
    ["Optimize Blind / Flash Protection"] = "Movement",
    ["VD Fullbright"] = "Render",

    -- MVSD (its ESP is an option of the universal one now)
    ["Silent Aim"] = "Combat",
    ["Auto Shoot"] = "Combat",
    ["Trigger Opportunity"] = "Render",

    -- BedFight (beds and generators are options of the universal ESP)
    ["Round Info"] = "Render",
    ["Auto Swing"] = "Combat",
    ["Bed Nuker"] = "Combat",
    ["Scaffold"] = "Movement",
    ["Anti Void"] = "Movement",
    ["Server Aura"] = "Combat",
    ["Server Scaffold"] = "Movement",
    ["Server Miner"] = "Other",
    ["Auto Buy"] = "Other",
    ["Quick Actions"] = "Other",
}

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
    contentPadding: number,
    cardSpacing: number,
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
}

local function computeLayoutMetrics(
    _viewport: Vector2,
    touchEnabled: boolean
): LayoutMetrics
    local mode: string = "Desktop"
    if touchEnabled then
        mode = "Mobile"
    end
    local mobile: boolean = mode == "Mobile"
    return {
        mode = mode,
        compact = mobile,
        touch = touchEnabled,
        contentPadding = 10,
        cardSpacing = 2,
        cardHeight = 22,
        cardCorner = UI_RADIUS.card,
        controlHeight = 20,
        optionRowHeight = 22,
        switchWidth = 26,
        switchHeight = 14,
        iconButton = 16,
        keySlotWidth = 34,
        touchTarget = touchEnabled and 32 or 24,
        titleFontSize = 11.5,
        bodyFontSize = 11.5,
        captionFontSize = 9,
        scrollBar = 3,
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
local SOURCE_STAMP: string = "2270d614a5ca5b7e"
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
    version = "0.1 Beta",
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
        radius = 0,
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

-- One token, repainted live. ThemeEngine.Apply is a whole preset; the UI
-- Settings window edits Background, Accent and Text one at a time, the way
-- Wurst's ClickGUI settings do, and each edit has to reach everything that
-- bound the token without waiting for a preset switch.
function ThemeEngine.Set(token: string, value: Color3): ()
    Theme[token] = value
    for instance: any, record: any in pairs(themeBindings) do
        for _, binding: any in ipairs(record) do
            if binding.token == token then
                pcall(function(): ()
                    instance[binding.property] = value
                end)
            end
        end
    end
    for _, listener: (string) -> () in ipairs(themeListeners) do
        pcall(listener, ThemeEngine.name)
    end
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
        -- Every copy, not just the first: a reinject that raced its own
        -- cleanup could stack two shells, and destroying one of them left
        -- the other drawing a second logo and a second pill forever.
        local existing = location:FindFirstChild(GUI_NAME)
        while existing do
            existing:Destroy()
            existing = location:FindFirstChild(GUI_NAME)
        end
    end
end

findExistingGui()

-- Older builds parented a BlurEffect under this name; a reinject must not
-- leave a stale one dimming the game, so the name is still swept even though
-- this build never creates one. Wurst puts nothing between the player and
-- the game except its own windows.
local oldBlur = Lighting:FindFirstChild(BLUR_NAME)
if oldBlur then
    oldBlur:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
-- Roblox machine-translates every label for a non-English client unless told
-- otherwise, which is how the menu showed "Otras razones", "Desactivado" and
-- "Hacer zoom". One flag at the root covers every descendant: the interface
-- speaks Wurst's English, always. (VD's in-world billboards set their own.)
ScreenGui.AutoLocalize = false
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

-- Wurst's own default binds: right-ctrl opens the ClickGUI, right-shift opens
-- Navigator. The menu key used to default to RightShift here; a stored key
-- still wins, so nobody's muscle memory changes under them — only a fresh
-- install gets Wurst's pair. The `or` is for the test harness, whose Enum
-- stand-in does not carry RightControl yet (noted in docs/requests/A.md).
local savedToggleKey = (Enum.KeyCode :: any).RightControl
    or Enum.KeyCode.RightShift
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
    mobileMenuButtonVisible = true,
    toggleKey = savedToggleKey,
    waitingForKey = false,
    keyCaptureCallback = nil,
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
-- Settings that used to be rows on the old Config. page. The page is gone —
-- Wurst has no text-scale or launcher-size settings — but the stored values
-- keep applying so an existing install does not change under its player the
-- day the rows disappeared. The blur went entirely, controller and all.
state.textScale = configData.ui.textScaleCalibrationVersion == 2
    and math.clamp(
        tonumber(configData.ui.textScale) or 1,
        TEXT_SCALE_MINIMUM,
        TEXT_SCALE_MAXIMUM
    )
    or 1
state.animationsEnabled = configData.ui.animationsEnabled ~= false
-- Free-form pixel size, only sanity-clamped.
state.mobileButtonSize = math.clamp(
    tonumber(configData.ui.mobileButtonSize) or 52,
    28,
    120
)
configData.ui.guiStyle = nil
-- Schema 2: the Wurst rebuild. Values an older build stored contradict the
-- port — window geometry for windows that no longer exist (the "WurstLogo |
-- Emote Player" pile-up was two eras' saved positions coinciding), Max
-- height sliders stored before the official 200 default existed, and the
-- WurstLogo colours from the ghost-chip era. One flag, one sweep;
-- everything falls back to Wurst's own defaults and persists fresh.
if configData.ui.wurstSchema ~= 2 then
    configData.ui.wurstSchema = 2
    configData.ui.windows = {}
    configData.values["ClickGUI.Maxheight"] = nil
    configData.values["ClickGUI.Maxsettingsheight"] = nil
    configData.values["ClickGUI.Opacity"] = nil
    configData.values["ClickGUI.Tooltipopacity"] = nil
    configData.values["WurstLogo.Background"] = nil
    configData.values["WurstLogo.Text"] = nil
    configData.values["WurstLogo.Visibility"] = nil
    queueConfigSave()
end
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
        and previous.cardHeight == nextLayout.cardHeight then
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

-- There is no blur controller any more. The old menu dimmed the whole game
-- behind a BlurEffect while it was open, with a hail layer drawn on top;
-- Wurst draws its windows over the untouched game and nothing else, so the
-- effect, its tween, its suspension hooks and its decoration registry are
-- gone. The one thing that survives is the sweep above that removes a stale
-- effect left by an older build.

-- Authoritative menu visibility entry point. Subsystems (mobile buttons,
-- floating windows) attach their own side effects as listeners as soon as they
-- are built, so this is safe to call at any point during startup.
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
local function setMenuVisibleCore(visible: boolean): ()
    state.visible = visible
    for _, listener: (boolean) -> () in ipairs(menuVisibilityListeners) do
        pcall(listener, visible)
    end
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
        -- Wurst's own wordmark, vendored from Wurst-Imperium/Wurst7 at the
        -- pinned commit and checksummed by the gate. The transparent 505x128
        -- sausage, not icon.png — that one is the same mark on an opaque black
        -- square, built to be a repository avatar, and it renders as a black
        -- brick anywhere with a background behind it.
        wurstLogo = {
            url = REPOSITORY_RAW_BASE .. "assets/wurst/wurst_128.png",
            fileName = "wurst-logo-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        -- The bitmap font atlas the text contract renders through: Monocraft
        -- rasterised into a fixed-cell grid by tools/make_font_atlas.py.
        -- OFL; the licence ships beside the OTF it was rendered from.
        bitmapFontAtlas = {
            url = REPOSITORY_RAW_BASE .. "assets/font/monocraft-16.png",
            fileName = "monocraft-16-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        -- The old menu's artwork — brand logo, nav icons, banners — is gone
        -- from this registry. Nothing draws it any more, and a registry entry
        -- for an image nobody shows is a download waiting to be wrong.
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
            -- A label built without an explicit face has no FontFace to read
            -- a weight from; it simply takes the resolved base.
            local current: Font? = (descendant :: any).FontFace
            if current then
                local weight: Enum.FontWeight = hasWeights
                    and (current :: Font).Weight
                    or resolvedBase.Weight
                local ok: boolean = pcall(function(): ()
                    (descendant :: any).FontFace =
                        Font.new(family, weight, (current :: Font).Style)
                end)
                if not ok then
                    (descendant :: any).FontFace = resolvedBase
                end
            else
                (descendant :: any).FontFace = resolvedBase
            end
        end
    end

    if persist ~= false then
        configData.values.interfaceFont = name
        queueConfigSave()
    end
end

-- The raw resolve, for consumers that are not ImageLabels — the bitmap
-- font atlas wants the asset id itself.
state.resolveAsset = function(logicalName: string): (string?, string?)
    return AssetManager.resolve(logicalName)
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

function SectionManager.initialize(sectionName: string): (boolean, string?)
    local entry = SectionManager.entries[sectionName]
    if not entry or entry.loaded or entry.loading then
        return entry ~= nil and entry.loaded == true, nil
    end

    entry.loading = true

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
        return true, nil
    end

    warn(
        "[" .. PRODUCT.name .. "] "
            .. sectionName
            .. " failed to initialize: "
            .. tostring(errorMessage)
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

    if total == 0 then
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
            if completed >= total then
                print(
                    "[" .. PRODUCT.logPrefix .. ":Bootstrap] Carga terminada · fallos="
                        .. tostring(failures)
                )
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

    -- Belt to the root flag's braces: every text object the menu builds
    -- refuses machine translation individually, so a label parented outside
    -- the main ScreenGui (billboards, overlays) is covered too.
    if object:IsA("TextLabel")
        or object:IsA("TextButton")
        or object:IsA("TextBox") then
        object.AutoLocalize = false
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
--
-- Except that Wurst has no rounded surface anywhere, so since the port this
-- returns zero for every caller: one change squared every button, text box,
-- toast and dropdown at once instead of hunting corners one by one. The
-- helper keeps its name and signature because forty call sites describe a
-- shape with it; the shape is now a rectangle. The two survivors that stay
-- genuinely round — the Roblox pill and the phone fallback circle — use
-- UDim.new(1, 0) directly and never came through here.
local function cornerRadius(_radius: number): UDim
    return UDim.new(0, 0)
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

-- ---------------------------------------------------------------------------
-- Bitmap text contract
-- ---------------------------------------------------------------------------
--
-- Wurst's every label is Minecraft's 8 px bitmap font on a 9 px line. This
-- port does not rasterise that font yet — Monocraft, the vendored pixel
-- face, stands in — but ClickGUI surfaces ask *here* for their text, so the
-- day an atlas renderer exists it replaces the inside of `make` and no call
-- site moves. The metrics are the contract: 16 px glyphs on an 18 px line
-- with a 12 px advance — 8/9/6 logical at the GUI scale 2 the interface is
-- drawn at. `width` is the packing estimate the content-sized windows use.
state.bitmapText = {
    size = 16,
    lineHeight = 18,
    -- The packing estimate the content-sized windows use. The atlas's real
    -- advance is 11 (Monocraft's, below); packing keeps the rounder 12 so a
    -- window is never a pixel too narrow for the estimate that sized it.
    advance = 12,
    -- Minecraft's font ascent is 7 of its 8 logical rows: 14 at the GUI
    -- scale 2 the interface is drawn at. Surfaces mixing glyph sizes align
    -- to this, scaled by TextSize / 16.
    ascent = 14,
    -- What the atlas actually holds. Monocraft is the committed OFL
    -- fallback; the exact Minecraft 1.18.1 providers are fetched explicitly
    -- through tools/fetch_minecraft_font.py into a gitignored local cache.
    -- While this says fallback, nothing may claim "Minecraft exact".
    source = "monocraft-fallback",
    -- The rasterised truth: Monocraft baked into a fixed-cell grid by
    -- tools/make_font_atlas.py. These numbers are that tool's output and
    -- change only when the atlas is regenerated.
    atlas = {
        ready = false,
        image = nil :: string?,
        size = 16,
        first = 32,
        last = 126,
        columns = 16,
        cellWidth = 11,
        cellHeight = 17,
        advance = 11,
        -- Codepoints outside the grid render as this cell ("?"), the way
        -- Minecraft substitutes its missing glyph instead of collapsing
        -- the advance and shifting everything after it.
        fallbackGlyph = 63,
    },
    onReady = {} :: {() -> ()},
    -- The renderer's own meter, because "pooling works" is a claim and
    -- these are the numbers behind it: draws that ran, draws skipped by
    -- signature, glyphs created versus reused, and the cost of the last
    -- draw in milliseconds.
    stats = {
        draws = 0,
        skipped = 0,
        glyphsCreated = 0,
        glyphsReused = 0,
        lastDrawMs = 0,
    },
    -- Live draw records, weak-keyed by holder: what was asked for, so the
    -- atlas resolving re-renders every surface without any of them
    -- registering by hand.
    _live = setmetatable({}, {__mode = "k"}) :: any,
    -- Labels already adopted, weak-keyed: adopt is idempotent and a
    -- sweep may visit the same instance twice.
    _adopted = setmetatable({}, {__mode = "k"}) :: any,
    width = function(text: any): number
        return #tostring(text) * 12
    end,
    make = function(properties: any): TextLabel
        local resolved: any = {}
        for key: string, value: any in pairs(properties or {}) do
            resolved[key] = value
        end
        resolved.FontFace = CONTROL_FONT
        resolved.TextSize = resolved.TextSize or 16
        if resolved.TextTruncate == nil then
            resolved.TextTruncate = Enum.TextTruncate.AtEnd
        end
        return (create("TextLabel", resolved) :: any) :: TextLabel
    end,
}

-- One codepoint at a time, UTF-8 when the text is valid UTF-8 and raw
-- bytes when it is not — a fallback glyph per byte beats an error, and
-- executors feed this strings from anywhere.
state.bitmapText.eachCode = function(text: string, visit: (number) -> ()): ()
    if utf8.len(text) ~= nil then
        for _, code: number in utf8.codes(text) do
            visit(code)
        end
    else
        for position: number = 1, #text do
            visit(string.byte(text, position) or 63)
        end
    end
end

local function contractAdvanceFor(atlas: any, code: number, scale: number): number
    local advances: any = atlas.advances
    local specific: any = advances and (advances[code] or advances[tostring(code)])
    return (tonumber(specific) or atlas.advance) * scale
end

-- The width draw() will actually occupy: atlas advances when the atlas is
-- live, the packing estimate until then. Newlines reset the caret; the
-- widest line wins. Honours per-glyph advances when the atlas carries
-- them — Minecraft's font is variable-width.
state.bitmapText.measure = function(segments: {any}, textSize: number?): number
    local contract: any = state.bitmapText
    local atlas: any = contract.atlas
    local scale: number = (tonumber(textSize) or 16) / contract.size
    local widest: number = 0
    local x: number = 0
    for _, segment: any in ipairs(segments) do
        contract.eachCode(tostring(segment.text or ""), function(code: number): ()
            if code == 10 then
                x = 0
            else
                if atlas.ready then
                    x += contractAdvanceFor(atlas, code, scale)
                else
                    x += contract.advance * scale
                end
                widest = math.max(widest, x)
            end
        end)
    end
    return widest
end

-- Text on the Wurst contract. Segments carry their own colours (the
-- HackList's muted bracket without RichText); options:
--
--   Name       replaces a previous draw of the same name in the parent
--   TextSize   16 default (the 8-logical Minecraft size at GUI scale 2)
--   ZIndex     base depth; shadow sits at +1, ink at +2
--   align      "Left" | "Center" | "Right" — where the holder anchors
--   shadow     Minecraft's drop shadow: same glyphs at +2,+2 in the text
--              colour quartered, under the ink
--   maxWidth   clip: glyphs past it are not drawn, the holder clips
--
-- Glyph ImageLabels are pooled per holder: a redraw reuses them in place,
-- resizes the pool by the difference, and a draw whose signature has not
-- changed does nothing at all. Nothing here recreates per frame.
state.bitmapText.draw = function(
    parent: Instance,
    segments: {any},
    options: any
): Frame
    local startedAt: number = os.clock()
    local contract: any = state.bitmapText
    local resolvedOptions: any = options or {}
    local name: string = tostring(resolvedOptions.Name or "BitmapText")
    local textSize: number = tonumber(resolvedOptions.TextSize) or 16
    local zIndex: number = tonumber(resolvedOptions.ZIndex) or 20
    local align: string = tostring(resolvedOptions.align or "Left")
    local shadow: boolean = resolvedOptions.shadow == true
    local maxWidth: number? = tonumber(resolvedOptions.maxWidth)
    local transparency: number = tonumber(resolvedOptions.transparency) or 0
    local atlas: any = contract.atlas

    -- The signature is the draw: same text, colours, size, mode and
    -- layout means the pixels are already right and the call costs a
    -- string compare.
    local parts: {string} = {
        tostring(textSize), align, tostring(shadow),
        tostring(maxWidth), tostring(atlas.ready),
        tostring(transparency),
    }
    for _, segment: any in ipairs(segments) do
        local color: Color3 = segment.color or Theme.text
        table.insert(parts, tostring(segment.text or ""))
        table.insert(parts, string.format(
            "%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5)
        ))
    end
    local signature: string = table.concat(parts, "\1")

    local holder: any = (parent :: any):FindFirstChild(name)
    local record: any = holder and contract._live[holder]
    if holder and not record then
        -- Same name, not ours — an old TextLabel a migration replaced.
        holder:Destroy()
        holder = nil
    end
    if not holder then
        holder = create("Frame", {
            Parent = parent,
            Name = name,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        })
        record = {glyphs = {} :: {ImageLabel}, fallback = nil :: TextLabel?}
        contract._live[holder] = record
    end
    record.request = {parent = parent, segments = segments, options = resolvedOptions}

    holder.ZIndex = zIndex
    if resolvedOptions.AnchorPoint or resolvedOptions.Position then
        holder.AnchorPoint = resolvedOptions.AnchorPoint or Vector2.new(0, 0.5)
        holder.Position = resolvedOptions.Position or UDim2.new(0, 0, 0.5, 0)
    elseif align == "Right" then
        holder.AnchorPoint = Vector2.new(1, 0.5)
        holder.Position = UDim2.new(1, 0, 0.5, 0)
    elseif align == "Center" then
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.Position = UDim2.new(0.5, 0, 0.5, 0)
    else
        holder.AnchorPoint = Vector2.new(0, 0.5)
        holder.Position = UDim2.new(0, 0, 0.5, 0)
    end

    if record.signature == signature then
        contract.stats.skipped += 1
        return holder :: Frame
    end
    record.signature = signature

    local used: number = 0
    local function nextGlyph(): ImageLabel
        used += 1
        local glyph: ImageLabel? = record.glyphs[used]
        if glyph then
            contract.stats.glyphsReused += 1
        else
            glyph = (create("ImageLabel", {
                Parent = holder,
                Name = "G",
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
            }) :: any) :: ImageLabel
            -- Pixelated, when the engine offers it: a pixel font
            -- bilinear-blurred is worse than no atlas at all.
            pcall(function(): ()
                (glyph :: any).ResampleMode = Enum.ResamplerMode.Pixelated
            end)
            record.glyphs[used] = glyph
            contract.stats.glyphsCreated += 1
        end
        (glyph :: ImageLabel).Visible = true
        return glyph :: ImageLabel
    end

    local width: number = 0
    local height: number = 0
    if atlas.ready and atlas.image then
        if record.fallback then
            (record.fallback :: TextLabel).Visible = false
        end
        local scale: number = textSize / atlas.size
        local glyphWidth: number = atlas.cellWidth * scale
        local glyphHeight: number = atlas.cellHeight * scale
        local lineAdvance: number = contract.lineHeight * (textSize / contract.size)
        local shadowOffset: number = 2 * scale
        local x: number = 0
        local y: number = 0
        local lineCount: number = 1
        local function blit(code: number, paint: Color3, dx: number, dy: number, z: number): ()
            local index: number = code - atlas.first
            local glyph: ImageLabel = nextGlyph()
            glyph.Image = atlas.image
            glyph.ImageColor3 = paint
            glyph.ImageTransparency = transparency
            glyph.ImageRectOffset = Vector2.new(
                (index % atlas.columns) * atlas.cellWidth,
                (index // atlas.columns) * atlas.cellHeight
            )
            glyph.ImageRectSize = Vector2.new(atlas.cellWidth, atlas.cellHeight)
            glyph.Position = UDim2.fromOffset(dx, dy)
            glyph.Size = UDim2.fromOffset(glyphWidth, glyphHeight)
            glyph.ZIndex = z
        end
        for _, segment: any in ipairs(segments) do
            local color: Color3 = segment.color or Theme.text
            -- Minecraft's shadow is the text colour quartered, one logical
            -- pixel down-right — 2 px at the scale everything draws at.
            local shade: Color3 = Color3.new(
                color.R * 0.25, color.G * 0.25, color.B * 0.25
            )
            contract.eachCode(tostring(segment.text or ""), function(code: number): ()
                if code == 10 then
                    x = 0
                    y += lineAdvance
                    lineCount += 1
                    return
                end
                local advance: number = contractAdvanceFor(atlas, code, scale)
                if maxWidth ~= nil and x + advance > maxWidth then
                    return
                end
                if code ~= 32 then
                    local mapped: number = code
                    if code < atlas.first or code > atlas.last then
                        mapped = atlas.fallbackGlyph
                    end
                    if shadow then
                        blit(mapped, shade, x + shadowOffset, y + shadowOffset, zIndex + 1)
                    end
                    blit(mapped, color, x, y, zIndex + 2)
                end
                x += advance
                width = math.max(width, x)
            end)
        end
        height = glyphHeight + (lineCount - 1) * lineAdvance
    else
        local composed: {string} = {}
        local estimated: number = 0
        for _, segment: any in ipairs(segments) do
            local text: string = tostring(segment.text or "")
                :gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
            local color: Color3 = segment.color or Theme.text
            table.insert(composed, string.format(
                '<font color="#%02X%02X%02X">%s</font>',
                math.floor(color.R * 255 + 0.5),
                math.floor(color.G * 255 + 0.5),
                math.floor(color.B * 255 + 0.5),
                text
            ))
            estimated += #tostring(segment.text or "")
        end
        local fallback: TextLabel? = record.fallback
        if not fallback then
            fallback = contract.make({
                Parent = holder,
                Name = "Fallback",
                BackgroundTransparency = 1,
                RichText = true,
                Size = UDim2.new(1, 0, 1, 0),
                TextColor3 = Theme.text,
            })
            record.fallback = fallback
            -- Inoculated against adoption: this label IS the renderer.
            contract._adopted[fallback] = true
        end
        local label: TextLabel = fallback :: TextLabel
        label.Visible = true
        label.Text = table.concat(composed)
        label.TextSize = textSize
        label.TextTransparency = transparency
        label.TextXAlignment = align == "Right" and Enum.TextXAlignment.Right
            or align == "Center" and Enum.TextXAlignment.Center
            or Enum.TextXAlignment.Left
        label.ZIndex = zIndex + 1
        width = estimated * math.floor(textSize * 0.75)
        height = math.floor(textSize * 1.125)
    end

    for index: number = used + 1, #record.glyphs do
        (record.glyphs[index] :: ImageLabel).Visible = false
    end

    if maxWidth ~= nil then
        width = math.min(width, maxWidth)
    end
    holder.ClipsDescendants = maxWidth ~= nil
    holder.Size = UDim2.fromOffset(width, height)
    holder:SetAttribute("MeasuredWidth", width)
    contract.stats.draws += 1
    contract.stats.lastDrawMs = (os.clock() - startedAt) * 1000
    return holder :: Frame
end

-- Explicit teardown for a surface that is done with its line: the pool
-- dies with the holder, the weak registry lets go on its own.
state.bitmapText.release = function(holder: Instance?): ()
    if holder then
        state.bitmapText._live[holder] = nil
        holder:Destroy()
    end
end

-- Adopt an existing TextLabel or TextButton: its vector text goes
-- invisible and pooled glyphs draw inside it instead, following the
-- label's own Text / TextColor3 / TextSize / TextXAlignment live. The
-- instance keeps its name, its Text and its TextBounds, so everything
-- that reads a label as metadata — width packing, the suites, the
-- Show rules — keeps working while the pixels come from the atlas.
-- ClipsDescendants stands in for TextTruncate. TextBoxes are refused:
-- hiding typed text under a caret is not a migration, it is a bug.
-- Idempotent per label; the glyphs, the registry entry and the signal
-- connections all die with the label's own Destroy.
state.bitmapText.adopt = function(label: any, options: any?): ()
    local contract: any = state.bitmapText
    if label == nil
        or type(label.IsA) ~= "function"
        or label:IsA("TextBox")
        or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
        return
    end
    if label:GetAttribute("NoBitmap") == true then
        return
    end
    if contract._adopted[label] then
        return
    end
    -- Never adopt the renderer's own output: the fallback label inside a
    -- draw holder would otherwise be adopted, hidden, and redrawn into
    -- itself forever.
    if label.Parent ~= nil and contract._live[label.Parent] ~= nil then
        return
    end
    local resolvedOptions: any = options or {}
    contract._adopted[label] = true
    label.TextTransparency = 1
    label.ClipsDescendants = true
    local function paint(): ()
        if label.Parent == nil then
            return
        end
        local alignment: any = label.TextXAlignment
        contract.draw(label, {
            {text = label.Text, color = label.TextColor3},
        }, {
            Name = "Glyphs",
            TextSize = label.TextSize,
            ZIndex = (tonumber(label.ZIndex) or 1) + 1,
            align = alignment == Enum.TextXAlignment.Right and "Right"
                or alignment == Enum.TextXAlignment.Center and "Center"
                or "Left",
            shadow = resolvedOptions.shadow == true,
        })
    end
    paint()
    -- The signals belong to the label, so Destroy disconnects them; no
    -- separate tracking needed, and no leak survives the surface. The
    -- harness's mock instances may not carry every property signal —
    -- adoption still paints once there.
    pcall(function(): ()
        label:GetPropertyChangedSignal("Text"):Connect(paint)
        label:GetPropertyChangedSignal("TextColor3"):Connect(paint)
        label:GetPropertyChangedSignal("TextSize"):Connect(paint)
    end)
end

-- Adopt every current and future text object under a root — the one
-- call that migrates a settings window whose rows are still being
-- built. Returns a disconnectable so the caller can park it with the
-- window's own cleanup; a stub when the environment lacks
-- DescendantAdded, so callers never branch.
state.bitmapText.adoptTree = function(root: Instance, options: any?): any
    local contract: any = state.bitmapText
    pcall(function(): ()
        for _, descendant: Instance in ipairs(root:GetDescendants()) do
            contract.adopt(descendant, options)
        end
    end)
    local connected: boolean, connection: any = pcall(function(): any
        return root.DescendantAdded:Connect(function(descendant: Instance): ()
            contract.adopt(descendant, options)
        end)
    end)
    if connected and connection then
        return connection
    end
    return {
        Connected = false,
        Disconnect = function(): () end,
    }
end


-- The atlas arrives like every other asset: downloaded, verified, turned
-- into an id off the boot thread. Three honest states, told apart at
-- runtime: "minecraft-exact" only when a locally generated 1.18.1 atlas
-- is really loaded (never committed — tools/fetch_minecraft_font.py
-- --update builds it from the verified official jar), the Monocraft
-- fallback when only the committed OFL atlas resolves, "unavailable"
-- when neither does and the vector stand-in keeps the menu readable.
-- One line of warning each, never a spam loop. Every live draw
-- re-renders itself the moment glyphs land — the signatures all carry
-- atlas.ready, so the redraws do real work exactly once — and onReady
-- still fires for surfaces that rebuild more than their glyphs.

-- The plug for a locally generated exact atlas: image plus metrics in
-- the same shape the Monocraft atlas ships. Nothing in the repo calls
-- it with Mojang data; a user who ran the official downloader can.
state.bitmapText.loadExactAtlas = function(image: string, metrics: any): ()
    local atlas: any = state.bitmapText.atlas
    if type(image) ~= "string" or type(metrics) ~= "table" then
        return
    end
    for _, key: string in ipairs({
        "size", "first", "last", "columns", "cellWidth", "cellHeight", "advance",
    }) do
        if tonumber(metrics[key]) then
            atlas[key] = tonumber(metrics[key])
        end
    end
    -- Per-codepoint advances, when the metrics carry them: Minecraft's
    -- font is variable-width and the renderer honours that the moment
    -- the numbers exist.
    if type(metrics.advances) == "table" then
        atlas.advances = metrics.advances
    end
    atlas.image = image
    atlas.ready = true
    state.bitmapText.source = "minecraft-exact"
    for holder: any, record: any in pairs(state.bitmapText._live) do
        if holder.Parent ~= nil and record.request ~= nil then
            pcall(function(): ()
                state.bitmapText.draw(
                    record.request.parent,
                    record.request.segments,
                    record.request.options
                )
            end)
        end
    end
    for _, listener: () -> () in ipairs(state.bitmapText.onReady) do
        pcall(listener)
    end
end

task.spawn(function(): ()
    if type(state.resolveAsset) ~= "function" then
        state.bitmapText.source = "unavailable"
        return
    end
    -- An exact atlas, if a local build registered one. Unknown keys are
    -- an error path in the asset manager, so the probe is pcall'd and
    -- silent — absence is the normal case, not a warning.
    local exactId: string? = nil
    pcall(function(): ()
        exactId = (state.resolveAsset("minecraftFontAtlas"))
    end)
    if exactId then
        state.bitmapText.atlas.image = exactId
        state.bitmapText.atlas.ready = true
        state.bitmapText.source = "minecraft-exact"
    else
        local assetId: string?, atlasError: string? =
            state.resolveAsset("bitmapFontAtlas")
        if not assetId then
            state.bitmapText.source = "unavailable"
            warn("[" .. PRODUCT.logPrefix .. ":Assets] no bitmap atlas ("
                .. tostring(atlasError)
                .. "); text renders on the vector stand-in")
            return
        end
        state.bitmapText.atlas.image = assetId
        state.bitmapText.atlas.ready = true
        state.bitmapText.source = "monocraft-fallback"
        print("[" .. PRODUCT.logPrefix
            .. ":Assets] Minecraft-exact atlas not present; rendering with "
            .. "the Monocraft fallback (OFL)")
    end
    for holder: any, record: any in pairs(state.bitmapText._live) do
        if holder.Parent ~= nil and record.request ~= nil then
            pcall(function(): ()
                state.bitmapText.draw(
                    record.request.parent,
                    record.request.segments,
                    record.request.options
                )
            end)
        end
    end
    for _, listener: () -> () in ipairs(state.bitmapText.onReady) do
        pcall(listener)
    end
end)

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
    create("UIStroke", {
        Parent = frame,
        Name = "MarkStroke",
        Color = Theme.outline,
        Transparency = 0.45,
        Thickness = 1,
    })
    -- The inner block is what fills; keeping it separate from the outline lets
    -- the mark grow into place instead of blinking on.
    local _core: Frame = create("Frame", {
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
            local _bar: Frame = create("Frame", {
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
    local _accent: Frame = (create("Frame", {
        Parent = toast,
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.accent
            or Theme.accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 4, 1, 0),
        ZIndex = 302,
    }) :: any) :: Frame

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



-- The ClickGUI has no central window. Cards are created in a hidden bin and
-- immediately moved into their category window by ClickGui.place.
local CardBin: Frame = (create("Frame", {
    Parent = ScreenGui,
    Name = "CardBin",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Visible = false,
}) :: any) :: Frame

-- Compatibility shims: old pages used one scrolling frame per game. The
-- ClickGUI has no pages, so every card starts in CardBin and is moved into a
-- category window. Game modules still name a parent, so these aliases keep
-- them working until they are migrated to CreateModule.
state.universalScroll = CardBin
state.trsScroll = CardBin
state.vdScroll = CardBin
state.mvsdScroll = CardBin
state.bedFightScroll = CardBin
state.spoofScroll = CardBin

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
    Text = "≡",
    TextColor3 = Theme.text,
    TextSize = 20,
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
-- No brand image on the launcher any more: menu-logo.jpg was the previous
-- product's art, and this circle only exists as the fallback way in when the
-- pill failed to arrive. The glyph matches the pill's own button.

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
-- Published so the pill can re-run it once it takes over as the launcher: the
-- fallback circle has to disappear the moment something better exists, and come
-- back if it does not.
state.refreshLauncher = refreshLauncherVisibility
refreshLauncherVisibility()
state.addMenuVisibilityListener(function(): ()
    refreshLauncherVisibility()
end)

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


-- Cards are created in a hidden bin and moved into ClickGUI windows. The old
-- responsive grid that balanced two columns inside a scrolling page is gone.
local function getFeatureCardParent(_container: Instance): Instance
    return CardBin
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
    if feature.options then
        feature.options.BackgroundTransparency = 1
    end
    -- The settings arrow keeps its own token binding (`enabled`, the colour
    -- Wurst draws its triangles in); nothing here may overwrite it.
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
-- An enabled module fills its whole row with the `enabled` token, the way
-- Wurst does, rather than lighting a two-pixel stripe down its left edge. With
-- thirty-eight modules the question "what is on" has to be answerable from
-- across the room, and a stripe is not an answer — it was legible only once you
-- were already reading the row you were asking about.
--
-- `enabled` is a separate token from `accent` for the same reason Wurst keeps
-- "Enabled hacks" separate from "Accent": the accent already paints every title
-- bar, and filling forty rows with it would leave nothing to look at.
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
    -- Which token the row is painted with, as opposed to how transparent it is.
    local fill: Color3 = Theme.surface

    if feature.isCategory then
        -- A heading, not a button: flat text on the window body.
        surface = 1
        titleColor = Theme.text
        titleTransparency = 0.3
    elseif feature.isAction then
        surface = isHovered and 0.3 or 0.5
    elseif feature.isHoldAction then
        -- A hold card is lit for exactly as long as the key is down, so it uses
        -- the same fill as a toggle: while it is on it *is* on.
        fill = isOn and Theme.enabled or Theme.surface
        surface = isOn and 0 or (isHovered and 0.3 or 0.5)
        titleColor = isOn and Theme.enabledText or Theme.text
    else
        fill = isOn and Theme.enabled or Theme.surface
        surface = isOn and 0 or (isHovered and 0.3 or 0.5)
        titleColor = isOn and Theme.enabledText or Theme.text
    end

    -- Instant, on purpose. Wurst repaints a row the frame it changes; the
    -- wipe this used to tween was the old menu's motion, not Wurst's.
    resolvedRow.BackgroundColor3 = fill
    resolvedRow.BackgroundTransparency = surface

    if feature.drawTitle then
        -- The bitmap-contract row: recolouring is a pooled redraw, not a
        -- property write. Same frame, same instances, new tint.
        feature.drawTitle(titleColor, titleTransparency)
    elseif feature.title then
        local titleLabel: TextLabel = feature.title :: TextLabel
        titleLabel.TextColor3 = titleColor
        titleLabel.TextTransparency = titleTransparency
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
    button: TextButton?,
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
        -- pcall, not trust: indexing Enum.KeyCode with a corrupt stored
        -- name throws, and a broken store must fall back to unbound.
        local resolved: boolean, savedKey: any = pcall(function(): any
            return (Enum.KeyCode :: any)[savedName]
        end)
        if resolved and savedKey then
            binding.key = savedKey
        end
    end
    state.shortcutBindings[shortcutId] = binding

    -- Desktop rows no longer carry a key slot — Wurst rows are a name and at
    -- most the settings arrow, and keys are managed in the Keybinds window —
    -- so the button is optional and everything that painted it is guarded.
    local function refreshButtonText(): ()
        if not button then
            return
        end
        (button :: TextButton).Text = shortcutSlotText(binding);
        (button :: TextButton):SetAttribute("CaptureIdleText", (button :: TextButton).Text)
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
        if button and state.bindMobileActionPlacement then
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

    if button then
        trackUiConnection((button :: TextButton).MouseButton1Click:Connect(function(): ()
            beginKeyCapture(button, function(keyCode: Enum.KeyCode): ()
                binding.assign(keyCode)
            end)
        end))
    end
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

create("UIPadding", {
    Parent = state.featureTooltip,
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
    PaddingTop = UDim.new(0, 5),
})

state.tooltipToken = 0

-- Wurst's tooltip is the same bitmap font as everything else. The
-- TextLabel stays as the box and the metadata carrier — the Tooltip
-- opacity slider writes its BackgroundTransparency, and its Text is
-- still the truth — but the visible glyphs come from the contract,
-- word-wrapped by real advances. The anchor arrives in screen pixels
-- (AbsolutePosition) while the layer positions in logical offsets
-- under the ClickGUI's UIScale; the manager's converters keep the two
-- apart instead of mixing them like the 5.5-px-per-char guess did.
local function showFeatureTooltip(row: Frame, text: string, pointer: Vector2?): ()
    state.tooltipToken = state.tooltipToken + 1
    state.featureTooltip.Text = text
    state.featureTooltip.TextTransparency = 1

    local bitmap: any = state.bitmapText
    local innerLimit: number = 488
    -- Word wrap by measured width: words accumulate while they fit,
    -- and a single over-long word breaks rather than overflowing.
    local lines: {string} = {}
    local current: string = ""
    for word: string in string.gmatch(tostring(text), "%S+") do
        local candidate: string = current == "" and word or (current .. " " .. word)
        if bitmap.measure({{text = candidate}}, 16) <= innerLimit or current == "" then
            current = candidate
        else
            table.insert(lines, current)
            current = word
        end
    end
    if current ~= "" then
        table.insert(lines, current)
    end
    if #lines == 0 then
        lines = {""}
    end
    local wrapped: string = table.concat(lines, "\n")
    local measured: number = bitmap.measure({{text = wrapped}}, 16)
    local width: number = math.clamp(measured + 24, 210, 520)
    local height: number = math.max(30, #lines * bitmap.lineHeight + 12)
    state.featureTooltip.Size = UDim2.fromOffset(width, height)
    bitmap.draw(state.featureTooltip, {
        {text = wrapped, color = Color3.fromRGB(205, 205, 205)},
    }, {
        Name = "Glyphs",
        TextSize = 16,
        ZIndex = 251,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
    })

    local manager: any = state.windows
    local viewport: Vector2
    if manager and type(manager.LogicalViewport) == "function" then
        viewport = manager.LogicalViewport()
    else
        local camera: Camera? = workspace.CurrentCamera
        viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    end
    local anchor: Vector2 = pointer
        or Vector2.new(
            row.AbsolutePosition.X + 16,
            row.AbsolutePosition.Y + row.AbsoluteSize.Y * 0.5
        )
    if manager and type(manager.ScreenToLogical) == "function" then
        anchor = manager.ScreenToLogical(anchor)
    end
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
-- still asks for `MM2Scroll`. It is now an alias to CardBin.
local MM2Scroll: Frame = CardBin

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
print("[" .. PRODUCT.logPrefix .. "] build loader-v3")

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
        SettingsPage = CardBin,
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
        initialViewport = initialViewport,
        -- Used by the floating overlays: the profile card's fixed height, the
        -- readout typeface, and the tab switcher a favourite jumps through.
        -- What the card factory builds a card out of: the taxonomy that files
        -- it under a section, the default board, and the registries it joins.
        FEATURE_CATEGORIES = FEATURE_CATEGORIES,
        DEFAULT_FEATURE_CATEGORY = DEFAULT_FEATURE_CATEGORY,
        -- The shared category contract: the eight official windows and the
        -- resolver every surface files a card through. A module may still
        -- say "Visuals"; the resolver decides which official window that is
        -- until D refiles it properly.
        OFFICIAL_CATEGORIES = OFFICIAL_CATEGORIES,
        normalizeFeatureCategory = normalizeFeatureCategory,
        universalFeatures = universalFeatures,
        movementFeatures = movementFeatures,
        applyFeaturePresentation = applyFeaturePresentation,
        refreshFeatureToggle = refreshFeatureToggle,
        VALVE_FONT = VALVE_FONT,
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
                Root = CardBin,
                ScreenGui = ScreenGui,
                Pages = {},
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
                -- A popped-out settings window belongs to its feature; a
                -- feature that goes takes the window, or the window leaks
                -- with the option rows still parented inside it.
                if feature.settingsWindow then
                    pcall(function(): ()
                        feature.settingsWindow:Destroy()
                    end)
                    feature.settingsWindow = nil
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
        "src/library/ClickGui.luau",
        "src/library/FloatingWindows.luau",
        "src/library/SettingsPage.luau",
        "src/library/MobileActions.luau",
        "src/library/Furniture.luau",
    },
    modules = {
        {path = "src/modules/Utility/FriendList.luau", name = "Friend List", category = "Other"},
        {path = "src/modules/Visuals/ItemRender.luau", name = "ItemESP", category = "Render"},
        {path = "src/modules/Visuals/PlayerESP.luau", name = "PlayerESP", category = "Render"},
        {path = "src/modules/Combat/KillAura.luau", name = "Killaura", category = "Combat"},
        {path = "src/modules/Utility/RemoteLogger.luau", name = "Remote Logger", category = "Other"},
        {path = "src/modules/Movement/ClickTeleport.luau", name = "Click Teleport", category = "Movement"},
        {path = "src/modules/Combat/AutoClicker.luau", name = "Auto Clicker", category = "Combat"},
        {path = "src/modules/Combat/TriggerBot.luau", name = "TriggerBot", category = "Combat"},
        {path = "src/modules/Visuals/XRay.luau", name = "X-Ray", category = "Render"},
        {path = "src/modules/Movement/HighJump.luau", name = "HighJump", category = "Movement"},
        {path = "src/modules/Movement/Spider.luau", name = "Spider", category = "Movement"},
        {path = "src/modules/Protection/SafeWalk.luau", name = "SafeWalk", category = "Movement"},
        {path = "src/modules/Utility/RejoinServer.luau", name = "Rejoin Server", category = "Other"},
        {path = "src/modules/Visuals/ZoomUnlocker.luau", name = "Zoom", category = "Render"},
        {path = "src/modules/Utility/InteractExtender.luau", name = "Interact Extender", category = "Other"},
        {path = "src/modules/Movement/PhaseDash.luau", name = "Phase Dash", category = "Movement"},
        {path = "src/modules/Protection/NoFall.luau", name = "NoFall", category = "Movement"},
        {path = "src/modules/Movement/Fly.luau", name = "Flight", category = "Movement"},
        {path = "src/modules/Movement/VehicleSpeed.luau", name = "Vehicle Speed", category = "Movement"},
        {path = "src/modules/Protection/AntiVoid.luau", name = "Anti-Void", category = "Movement"},
        {path = "src/modules/Utility/Gravity.luau", name = "Gravity", category = "Movement"},
        {path = "src/modules/Movement/JumpPower.luau", name = "Jump Power", category = "Movement"},
        {path = "src/modules/Movement/InfiniteJump.luau", name = "Infinite Jump", category = "Movement"},
        {path = "src/modules/Visuals/FieldOfView.luau", name = "FOV", category = "Render"},
        {path = "src/modules/Movement/Noclip.luau", name = "Noclip", category = "Movement"},
        {path = "src/modules/Utility/AntiAfk.luau", name = "AntiAFK", category = "Other"},
        {path = "src/modules/Protection/AntiFling.luau", name = "Anti-Fling", category = "Combat"},
        {path = "src/modules/Utility/LagSwitch.luau", name = "Lag Switch", category = "Movement"},
        {path = "src/modules/Utility/Fling.luau", name = "Fling", category = "Combat"},
        {path = "src/modules/Utility/ImproveFps.luau", name = "Improve FPS", category = "Other"},
        {path = "src/modules/Visuals/Fullbright.luau", name = "Fullbright", category = "Render"},
        {path = "src/modules/Movement/FreezeMovements.luau", name = "Freeze Movements", category = "Movement"},
        {path = "src/modules/Movement/Speed.luau", name = "SpeedHack", category = "Movement"},
        {path = "src/modules/Combat/Hitboxes.luau", name = "Hitboxes", category = "Combat"},
        {path = "src/modules/Combat/ProjectileCalibration.luau", name = "Projectile Calibration", category = "Render"},
        {path = "src/modules/Spoof/Disguise.luau", name = "Disguise", category = "Fun"},
        {path = "src/modules/Spoof/AnimationChanger.luau", name = "Animation Changer", category = "Fun"},
        {path = "src/modules/Spoof/EmotePlayer.luau", name = "Emote Player", category = "Fun"},
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

-- Config. tab was old UI; UI Settings is a window (phase 4), not a tab


-- Restore the saved typeface once the interface exists — and when nothing is
-- saved, default to Monocraft. Wurst ships no TTF at all: every label in the
-- real client is Minecraft's bitmap font, and Monocraft is the closest face
-- this repository vendors. applyInterfaceFont only swaps once the download
-- has resolved, so an executor without getcustomasset simply keeps
-- BuilderSans — the safe fallback, never a blank label.
do
    local savedFont: string = tostring(configData.values.interfaceFont or "")
    if savedFont == "" or savedFont == "Menu default" then
        savedFont = "Minecraft (Monocraft)"
    end
    task.spawn(function(): ()
        state.applyInterfaceFont(savedFont, false)
    end)
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
        if not ScreenGui.Parent then
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
