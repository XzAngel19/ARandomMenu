--!strict
--[[
    A Random Menu
    Standalone, client-sided Roblox GUI.

    Default controls:
      - RightShift: show/hide the menu
      - Drag the DARK title bar or Default side strip to move the fixed-size menu
]]

local bootstrapStatusLabel: TextLabel? = nil
local RUNTIME_COMPATIBILITY_MARKER: string =
    "Initialization error — check executor console"
local RUNTIME_SAFETY_SOURCE_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/4b10e4bfe00aa356afb3e0420a72e745327f6259/ARandomMenu.luau"
local RUNTIME_BUILD_LABEL: string = "loader-v3"

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
local ContentProvider: ContentProvider = cloneReference(
    game:GetService("ContentProvider")
)

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
local REPOSITORY_RAW_BASE =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/"

local GAME_MODULES: {[number]: string} = {
    [142823291] = "MM2",
    [14315258385] = "TRS",
    [93978595733734] = "VD",
    [135856908115931] = "MVSD",
}

local ACTIVE_GAME_MODULE: string? = GAME_MODULES[game.PlaceId]

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
    return game.PlaceId == identifier
end
local DEFAULT_HEADER_COLOR: Color3 = Color3.fromRGB(76, 214, 255)
local DEFAULT_MENU_COLOR: Color3 = Color3.fromRGB(0, 0, 0)
local DEFAULT_SURFACE_COLOR: Color3 = Color3.fromRGB(18, 18, 20)
local DEFAULT_BORDER_COLOR: Color3 = Color3.fromRGB(82, 82, 86)

local Theme: {[string]: Color3} = {
    Background = Color3.fromRGB(0, 0, 0),
    Surface = Color3.fromRGB(18, 18, 20),
    SurfaceRaised = Color3.fromRGB(27, 27, 30),
    SurfaceHover = Color3.fromRGB(35, 35, 38),
    SurfacePressed = Color3.fromRGB(43, 43, 47),
    Accent = Color3.fromRGB(76, 214, 255),
    AccentCyan = Color3.fromRGB(76, 214, 255),
    AccentViolet = Color3.fromRGB(145, 112, 255),
    AccentPink = Color3.fromRGB(255, 93, 174),
    AccentSoft = Color3.fromRGB(35, 86, 104),
    DefaultBackground = Color3.fromRGB(10, 17, 21),
    DefaultSidebar = Color3.fromRGB(15, 25, 29),
    DefaultSurface = Color3.fromRGB(25, 38, 43),
    DefaultSurfaceHover = Color3.fromRGB(38, 56, 62),
    DefaultButton = Color3.fromRGB(28, 101, 137),
    DefaultButtonHover = Color3.fromRGB(38, 126, 164),
    DefaultButtonPressed = Color3.fromRGB(22, 82, 112),
    DefaultOutline = Color3.fromRGB(108, 137, 145),
    DefaultAccent = Color3.fromRGB(112, 218, 205),
    DefaultText = Color3.fromRGB(240, 247, 246),
    DefaultTextMuted = Color3.fromRGB(168, 188, 190),
    Text = Color3.fromRGB(242, 242, 244),
    TextMuted = Color3.fromRGB(164, 164, 169),
    Outline = Color3.fromRGB(89, 89, 94),
    Success = Color3.fromRGB(222, 222, 224),
    Danger = Color3.fromRGB(202, 202, 205),
}
local TITLE_FONT: Font = Font.fromEnum(Enum.Font.Fondamento)
local THIN_FONT: Font = Font.new(
    "rbxasset://fonts/families/GothamSSm.json",
    Enum.FontWeight.Regular,
    Enum.FontStyle.Normal
)
local CONTROL_FONT: Font = Font.new(
    "rbxasset://fonts/families/GothamSSm.json",
    Enum.FontWeight.Medium,
    Enum.FontStyle.Normal
)
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

local Blur = Instance.new("BlurEffect")
Blur.Name = BLUR_NAME
Blur.Size = 0
Blur.Enabled = true
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
    guiStyle = configData.ui.guiStyle == "DARK" and "DARK" or "Default",
    blurEnabled = configData.ui.blurEnabled ~= false,
    textScale = math.clamp(
        tonumber(configData.ui.textScale)
            or (configData.ui.largeText == true and 1.25 or 1.08),
        0.85,
        1.35
    ),
    mobileMenuButtonVisible = true,
    animationsEnabled = configData.ui.animationsEnabled ~= false,
    mobileButtonSize = math.clamp(
        tonumber(configData.ui.mobileButtonSize) or 52,
        42,
        72
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

local function trackUiConnection(
    connection: RBXScriptConnection
): RBXScriptConnection
    table.insert(state.uiConnections, connection)
    return connection
end

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
    manifest = {
        auroraBackground = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Images/aurora-background.jpg",
            fileName = "aurora-background-v1.jpg",
            fallback = "",
            version = 1,
            assetType = "image/jpeg",
        },
        headerAnime = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Header/anime-header.jpg",
            fileName = "anime-header-v1.jpg",
            fallback = "",
            version = 1,
            assetType = "image/jpeg",
        },
        titleLogo = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Typography/title-logo.png",
            fileName = "title-logo-v1.png",
            fallback = "",
        },
        loadingSpinner = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Status/spinner_minimal.png",
            fileName = "loading-spinner-v1.png",
            fallback = "",
        },
        cosmicControls = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Source/cosmic-controls-sheet.png",
            fileName = "cosmic-controls-sheet-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        keybindPill = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Frames/keybind-pill-hd.png",
            fileName = "keybind-pill-hd-v1.png",
            fallback = "",
            version = 1,
            assetType = "image/png",
        },
        crossSmall = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Decorations/cross-small.png",
            fileName = "cross-small-v1.png",
            fallback = "",
        },
        halftoneFade = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Decorations/halftone-fade.png",
            fileName = "halftone-fade-v1.png",
            fallback = "",
        },
        blossomBranch = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Blossoms/blossom_branch_wide.png",
            fileName = "blossom-branch-v1.png",
            fallback = "",
        },
        blossomCorner = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Blossoms/blossom_scatter_right.png",
            fileName = "blossom-corner-v1.png",
            fallback = "",
        },
        search = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/search.png",
            fileName = "icon-search-v1.png",
            fallback = "",
        },
        settings = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/settings.png",
            fileName = "icon-settings-v1.png",
            fallback = "",
        },
        home = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/home.png",
            fileName = "icon-home-v1.png",
            fallback = "",
        },
        user = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/user_large.png",
            fileName = "icon-user-v1.png",
            fallback = "",
        },
        target = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/target_cross.png",
            fileName = "icon-target-v1.png",
            fallback = "",
        },
        visuals = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/eye_visuals.png",
            fileName = "icon-visuals-v1.png",
            fallback = "",
        },
        shield = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/shield.png",
            fileName = "icon-shield-v1.png",
            fallback = "",
        },
        bell = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/bell.png",
            fileName = "icon-bell-v1.png",
            fallback = "",
        },
        warning = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Icons/warning.png",
            fileName = "icon-warning-v1.png",
            fallback = "",
        },
        arrowDown = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Arrows/arrow_down.png",
            fileName = "arrow-down-v1.png",
            fallback = "",
        },
        separator = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Decorations/separator_thin.png",
            fileName = "separator-thin-v1.png",
            fallback = "",
        },
        noticeFrame = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Frames/panel_notice.png",
            fileName = "notice-frame-v1.png",
            fallback = "",
        },
        menuToggle = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Images/menu-toggle.png",
            fileName = "menu-toggle-v3.png",
            fallback = "rbxassetid://6031094678",
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

local function validateImageBytes(bytes: any): (boolean, string?)
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

function AssetManager.readVerifiedCache(path: string): (string?, string?)
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
    local valid: boolean, validationError: string? = validateImageBytes(bytes)
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
                Headers = {Accept = "image/png,image/*;q=0.9,*/*;q=0.1"},
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
            local valid: boolean, validationError: string? =
                validateImageBytes(bytes)
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
        AssetManager.readVerifiedCache(path)
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
            AssetManager.readVerifiedCache(path)
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

function AssetManager.loadAsync(
    logicalName: string,
    target: ImageLabel,
    onResolved: ((boolean) -> ())?
): ()
    task.spawn(function(): ()
        local assetId: string?, loadError: string? = AssetManager.resolve(logicalName)
        local definition: AssetDefinition? = AssetManager.manifest[logicalName]
        if assetId and target.Parent then
            target.Image = assetId
            if target.Image == assetId then
                local preloadOk: boolean = pcall(function(): ()
                    ContentProvider:PreloadAsync({target})
                end)
                if preloadOk and target.Parent and target.Image == assetId then
                    target:SetAttribute("AssetLoaded", true)
                    if onResolved then
                        onResolved(true)
                    end
                    return
                end
                loadError = "PreloadAsync no pudo cargar el recurso asignado"
            else
                loadError = "la propiedad Image no conservo el asset asignado"
            end
        end
        if target.Parent and definition then
            target.Image = definition.fallback
        end
        if onResolved then
            onResolved(false)
        end
        warn(
            "[RTM:Assets] fallback para "
                .. logicalName
                .. ": "
                .. tostring(loadError)
        )
    end)
end

function AssetManager.clear(logicalName: string): (boolean, string?)
    local definition: AssetDefinition? = AssetManager.manifest[logicalName]
    local deleteFile: any = getEnvironmentValue("delfile")
    if not definition then
        return false, "asset desconocido"
    end
    if type(deleteFile) ~= "function" then
        return false, "delfile no está disponible; cambia la versión del filename"
    end
    local path: string = AssetManager.cacheFolder .. "/" .. definition.fileName
    local deleted: boolean, deleteError: any = pcall(deleteFile, path)
    if deleted then
        return true, nil
    end
    return false, tostring(deleteError)
end
state.assetManager = AssetManager
end

local registeredText = {}
local tabButtons = {}
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
    status.BackgroundColor3 = Color3.fromRGB(27, 27, 27)
    status.BackgroundTransparency = isError and 0.05 or 0.2
    status.BorderSizePixel = 0
    status.Font = Enum.Font.Code
    status.Position = UDim2.fromOffset(18, 18)
    status.Size = UDim2.new(1, -36, 0, isError and 150 or 46)
    status.Text = message
    status.TextColor3 = isError
        and Color3.fromRGB(225, 85, 85)
        or Color3.fromRGB(180, 180, 180)
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

local function addRoundedStyle(
    object: GuiObject,
    radius: number,
    strokeTransparency: number?
): (UICorner, UIStroke)
    local corner: UICorner = Instance.new("UICorner")
    corner.Name = "StyleCorner"
    corner.CornerRadius = UDim.new(0, radius)
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

local function registerText(object, normalSize)
    table.insert(registeredText, {
        object = object,
        normalSize = normalSize,
    })

    object.TextSize = math.round(normalSize * state.textScale)
    return object
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
        TextColor3 = Color3.fromRGB(235, 235, 235),
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
            or Color3.fromRGB(240, 240, 240),
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
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
            TweenInfo.new(0.12, Enum.EasingStyle.Quad),
            {BackgroundColor3 = targetColor}
        ):Play()
    end))

    return button :: TextButton
end

local function applyKeySlotStyle(button: TextButton): ImageLabel
    button.ZIndex = math.max(2, button.ZIndex)
    button.TextColor3 = Color3.fromRGB(250, 250, 252)
    button:SetAttribute("ThemeRole", "KeySlot")
    local buttonStroke: UIStroke? = button:FindFirstChildOfClass("UIStroke")
    local frame: ImageLabel = create("ImageLabel", {
        Parent = button,
        Name = "KeySlotFrame",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        ImageColor3 = Color3.fromRGB(244, 244, 248),
        ImageTransparency = 0.06,
        Position = UDim2.fromScale(0.5, 0.5),
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(300, 300, 1870, 420),
        SliceScale = 0.5,
        Size = UDim2.new(1, 10, 1, 10),
        Visible = state.guiStyle == "DARK",
        ZIndex = button.ZIndex - 1,
    }) :: ImageLabel
    state.assetManager.loadAsync(
        "keybindPill",
        frame,
        function(loaded: boolean): ()
            if not loaded or button.Parent == nil then
                return
            end
            local darkStyle: boolean = state.guiStyle == "DARK"
            frame.Visible = darkStyle
            button.BackgroundTransparency = darkStyle and 1 or 0
            if buttonStroke and buttonStroke.Parent then
                buttonStroke.Enabled = not darkStyle
            end
        end
    )
    return frame
end

state.restyleButtons = function(isDefault: boolean): ()
    for _, button: TextButton in ipairs(state.styledButtons) do
        if button.Parent then
            local role: any = button:GetAttribute("ThemeRole")
            if role ~= "Navigation" and role ~= "Icon" and role ~= "Switch" then
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
                    local frame: ImageLabel? =
                        button:FindFirstChild("KeySlotFrame") :: ImageLabel?
                    if frame then
                        frame.Visible = not isDefault
                    end
                    button.BackgroundTransparency = isDefault and 0 or 1
                end
            end
        end
    end
end

local function setKeySlotCapture(button: TextButton, active: boolean): ()
    local frame: ImageLabel? = button:FindFirstChild("KeySlotFrame") :: ImageLabel?
    if frame then
        TweenService:Create(
            frame,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                ImageColor3 = active and Color3.fromRGB(255, 255, 255)
                    or Color3.fromRGB(244, 244, 248),
                ImageTransparency = active and 0 or 0.06,
            }
        ):Play()
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
            or Color3.fromRGB(235, 235, 235),
        TextXAlignment = Enum.TextXAlignment.Center,
    }), 13) :: any) :: TextBox
    addRoundedStyle(textBox, 9, 0.5)
    table.insert(state.styledTextBoxes, textBox)
    trackUiConnection(textBox.Focused:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {BackgroundColor3 = state.guiStyle == "Default"
                and Theme.DefaultButtonHover
                or Theme.SurfaceRaised}
        ):Play()
    end))
    trackUiConnection(textBox.FocusLost:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
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
    Position = UDim2.new(1, -18, 1, -18),
    Size = UDim2.fromOffset(340, 300),
    ZIndex = 300,
}) :: any) :: Frame

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
    toast.Size = UDim2.new(1, 0, 0, 56)
    toast.ZIndex = 301
    toast.Parent = ToastContainer

    create("UICorner", {
        Parent = toast,
        CornerRadius = UDim.new(0, 9),
    })
    create("UIStroke", {
        Parent = toast,
        Color = state.guiStyle == "Default"
            and Theme.DefaultOutline
            or Theme.Outline,
        Transparency = state.guiStyle == "Default" and 0.42 or 0.22,
        Thickness = 1,
    })
    local toastFrame: ImageLabel = (create("ImageLabel", {
        Parent = toast,
        Name = "MangaNoticeFrame",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        ImageColor3 = Color3.fromRGB(220, 220, 222),
        ImageTransparency = 0.56,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(24, 20, 359, 58),
        Size = UDim2.fromScale(1, 1),
        Visible = state.guiStyle ~= "Default",
        ZIndex = 302,
    }) :: any) :: ImageLabel
    state.assetManager.loadAsync("noticeFrame", toastFrame)

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

local function calculateWindowSize(viewport: Vector2): Vector2
    if state.isMobile then
        return Vector2.new(
            math.max(280, math.min(viewport.X - 8, math.round(viewport.X * 0.96))),
            math.max(320, math.min(viewport.Y - 8, math.round(viewport.Y * 0.88)))
        )
    end
    local widthRatio: number = viewport.X >= 1600 and 0.6 or 0.78
    local availableWidth: number = math.min(
        1120,
        viewport.X * widthRatio,
        math.max(420, viewport.X - 36)
    )
    local availableHeight: number = math.min(
        700,
        viewport.Y * 0.82,
        math.max(360, viewport.Y - 36)
    )
    local aspectRatio: number = viewport.X >= 1200 and 1.6 or 1.35
    local width: number = math.min(availableWidth, availableHeight * aspectRatio)
    local height: number = width / aspectRatio
    return Vector2.new(math.round(width), math.round(height))
end

local initialWindowSize: Vector2 = calculateWindowSize(initialViewport)

local Main: Frame = (create("Frame", {
    Parent = ScreenGui,
    Name = "Main",
    Active = true,
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(initialWindowSize.X, initialWindowSize.Y),
}) :: any) :: Frame

do
local _MainCorner: UICorner, MainStroke: UIStroke = addRoundedStyle(Main, 14, 0.2)
MainStroke.Thickness = 1
MainStroke.Color = Theme.Accent
MainStroke.Transparency = 0.42
local MainStrokeGradient: UIGradient = Instance.new("UIGradient")
MainStrokeGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 62, 76)),
    ColorSequenceKeypoint.new(0.32, Theme.Accent),
    ColorSequenceKeypoint.new(0.61, Theme.AccentViolet),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 91, 109)),
})
MainStrokeGradient.Rotation = 8
MainStrokeGradient.Parent = MainStroke
state.mainStroke = MainStroke
state.mainStrokeGradient = MainStrokeGradient
end

local DefaultPanelBackground: ImageLabel = nil :: any
local Header: Frame = nil :: any
local Content: Frame = nil :: any
local DefaultDragZone: Frame = nil :: any

local function centerMain(): ()
    local camera: Camera? = workspace.CurrentCamera
    local viewport: Vector2 = camera
        and camera.ViewportSize
        or Vector2.new(1280, 720)
    local size: Vector2 = Main.AbsoluteSize

    local savedPosition: any = configData.ui.windowPosition
    if type(savedPosition) == "table" then
        Main.Position = UDim2.fromOffset(
            math.clamp(tonumber(savedPosition[1]) or 0, 0, math.max(0, viewport.X - size.X)),
            math.clamp(tonumber(savedPosition[2]) or 0, 0, math.max(0, viewport.Y - size.Y))
        )
    else
        Main.Position = UDim2.fromOffset(
            math.floor((viewport.X - size.X) / 2),
            math.floor((viewport.Y - size.Y) / 2)
        )
    end
end

task.defer(centerMain)

do
local sidebarWidth: number = state.isMobile and 136 or 172
local DarkShell: CanvasGroup = create("CanvasGroup", {
    Parent = Main,
    Name = "DarkShell",
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Visible = false,
    ZIndex = 2,
}) :: CanvasGroup
local DefaultShell: CanvasGroup = create("CanvasGroup", {
    Parent = Main,
    Name = "DefaultShell",
    BackgroundColor3 = Theme.DefaultBackground,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Visible = true,
    ZIndex = 2,
}) :: CanvasGroup
create("UICorner", {
    Parent = DarkShell,
    CornerRadius = UDim.new(0, 14),
})
create("UICorner", {
    Parent = DefaultShell,
    CornerRadius = UDim.new(0, 14),
})

Header = create("Frame", {
    Parent = DarkShell,
    Name = "DarkHeader",
    Active = true,
    BackgroundColor3 = Color3.fromRGB(7, 7, 8),
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 58),
    ZIndex = 15,
}) :: Frame
Header.ClipsDescendants = true
create("UICorner", {
    Parent = Header,
    CornerRadius = UDim.new(0, 14),
})
create("TextLabel", {
    Parent = Header,
    Name = "Title",
    AnchorPoint = Vector2.new(0, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    FontFace = CONTROL_FONT,
    Position = UDim2.new(0, 20, 0.5, 0),
    Size = UDim2.new(0, state.isMobile and 130 or 280, 0, 28),
    Text = "A RANDOM MENU",
    TextColor3 = Theme.Text,
    TextSize = state.isMobile and 17 or 19,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    ZIndex = 20,
})
create("Frame", {
    Parent = Header,
    Name = "HeaderSeparator",
    AnchorPoint = Vector2.new(0, 1),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 1),
    ZIndex = 19,
})

local DarkTabs: Frame = create("Frame", {
    Parent = DarkShell,
    Name = "DarkNavigation",
    BackgroundColor3 = Color3.fromRGB(11, 11, 13),
    BackgroundTransparency = 0.03,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 58),
    Size = UDim2.new(0, sidebarWidth, 1, -58),
    ZIndex = 10,
}) :: Frame
create("UICorner", {
    Parent = DarkTabs,
    CornerRadius = UDim.new(0, 10),
})
create("UIListLayout", {
    Parent = DarkTabs,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
create("UIPadding", {
    Parent = DarkTabs,
    PaddingLeft = UDim.new(0, 6),
    PaddingRight = UDim.new(0, 6),
    PaddingTop = UDim.new(0, 10),
})

local DarkContentHost: Frame = create("Frame", {
    Parent = DarkShell,
    Name = "DarkContentHost",
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(sidebarWidth, 58),
    Size = UDim2.new(1, -sidebarWidth, 1, -58),
    ZIndex = 3,
}) :: Frame
DarkContentHost.ClipsDescendants = true
create("UICorner", {
    Parent = DarkContentHost,
    CornerRadius = UDim.new(0, 10),
})
create("Frame", {
    Parent = DarkContentHost,
    Name = "DarkReadabilityLayer",
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 4,
})

local DefaultSidebar: Frame = create("Frame", {
    Parent = DefaultShell,
    Name = "DefaultSidebar",
    Active = true,
    BackgroundColor3 = Theme.DefaultSidebar,
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    Size = UDim2.new(0, sidebarWidth, 1, 0),
    ZIndex = 10,
}) :: Frame
create("UICorner", {
    Parent = DefaultSidebar,
    CornerRadius = UDim.new(0, 14),
})
local DefaultSidebarStroke: UIStroke = create("UIStroke", {
    Parent = DefaultSidebar,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    Color = Theme.DefaultOutline,
    Thickness = 1,
    Transparency = 0.62,
}) :: UIStroke
DefaultSidebarStroke.Name = "DefaultSidebarStroke"

local DefaultTabs: Frame = create("Frame", {
    Parent = DefaultSidebar,
    Name = "DefaultNavigation",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 64),
    Size = UDim2.new(1, 0, 1, -76),
    ZIndex = 11,
}) :: Frame
create("UIListLayout", {
    Parent = DefaultTabs,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
create("UIPadding", {
    Parent = DefaultTabs,
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 10),
    PaddingTop = UDim.new(0, 8),
})

local DefaultContentHost: Frame = create("Frame", {
    Parent = DefaultShell,
    Name = "DefaultContentHost",
    BackgroundColor3 = Theme.DefaultBackground,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(sidebarWidth, 0),
    Size = UDim2.new(1, -sidebarWidth, 1, 0),
    ZIndex = 3,
}) :: Frame
DefaultContentHost.ClipsDescendants = true
create("UICorner", {
    Parent = DefaultContentHost,
    CornerRadius = UDim.new(0, 14),
})
DefaultPanelBackground = (create("ImageLabel", {
    Parent = DefaultContentHost,
    Name = "AuroraPanelBackground",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageColor3 = Color3.fromRGB(226, 239, 239),
    ImageTransparency = 0.04,
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 3,
}) :: any) :: ImageLabel
create("Frame", {
    Parent = DefaultContentHost,
    Name = "DefaultReadabilityLayer",
    BackgroundColor3 = Theme.DefaultBackground,
    BackgroundTransparency = 0.46,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 4,
})
state.assetManager.loadAsync("auroraBackground", DefaultPanelBackground)

Content = create("Frame", {
    Parent = DefaultContentHost,
    Name = "SharedPageHost",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 5,
}) :: Frame
Content.ClipsDescendants = true

DefaultDragZone = create("Frame", {
    Parent = DefaultShell,
    Name = "DefaultDragStrip",
    Active = true,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 10),
    ZIndex = 30,
}) :: Frame

state.shells = {
    dark = DarkShell,
    default = DefaultShell,
    darkTabs = DarkTabs,
    defaultTabs = DefaultTabs,
    darkContentHost = DarkContentHost,
    defaultContentHost = DefaultContentHost,
    defaultSidebar = DefaultSidebar,
}
end

local function setTab(tabName: string): ()
    state.activeTab = tabName

    for name, page in pairs(pages) do
        local selectedPage: boolean = name == tabName
        page.Visible = selectedPage
        if selectedPage and page:IsA("CanvasGroup") then
            page.GroupTransparency = 0
        end
    end

    for name: string, button: TextButton in pairs(tabButtons) do
        local selected: boolean = name == tabName
        button:SetAttribute("Selected", selected)
        button.BackgroundColor3 = selected and Theme.SurfaceRaised or Theme.Surface
        button.TextColor3 = selected
            and Color3.fromRGB(255, 255, 255)
            or Theme.TextMuted
        local tabStroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
        if tabStroke then
            tabStroke.Color = selected
                and Color3.fromRGB(220, 220, 222)
                or Theme.Outline
            tabStroke.Transparency = selected and 0.2 or 0.58
        end
        local indicator: Frame? = button:FindFirstChild("SelectionIndicator") :: Frame?
        if indicator then
            TweenService:Create(
                indicator,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad),
                {BackgroundTransparency = selected and 0 or 1}
            ):Play()
        end
    end
    for name: string, button: TextButton in pairs(defaultTabButtons) do
        local selected: boolean = name == tabName
        button:SetAttribute("Selected", selected)
        button.BackgroundColor3 = selected
            and Theme.DefaultSurface
            or Theme.DefaultSidebar
        button.BackgroundTransparency = selected and 0.16 or 1
        button.TextColor3 = selected and Theme.DefaultText or Theme.DefaultTextMuted
        local tabStroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
        if tabStroke then
            tabStroke.Color = Theme.DefaultOutline
            tabStroke.Transparency = selected and 0.54 or 1
        end
    end
end

local function createTab(tabName: string, layoutOrder: number): CanvasGroup
    local button: TextButton = makeButton(state.shells.darkTabs, tabName, 14)
    button.Name = tabName .. "Tab"
    button.LayoutOrder = layoutOrder
    button.Size = UDim2.new(1, -12, 0, state.isMobile and 40 or 44)
    button.BackgroundColor3 = Theme.Surface
    button.TextSize = state.isMobile and 10 or 14
    button.TextXAlignment = Enum.TextXAlignment.Left
    button.ZIndex = 11
    button:SetAttribute("ThemeRole", "Navigation")
    button:SetAttribute("SelectedColor", Theme.SurfaceRaised)
    local indicator: Frame = (create("Frame", {
        Parent = button,
        Name = "SelectionIndicator",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 3, 0, 22),
        ZIndex = button.ZIndex + 1,
    }) :: any) :: Frame
    local indicatorGradient: UIGradient = Instance.new("UIGradient")
    indicatorGradient.Color = ColorSequence.new(
        Color3.fromRGB(100, 100, 104),
        Color3.fromRGB(240, 240, 242)
    )
    indicatorGradient.Parent = indicator
    local indicatorCorner: UICorner = Instance.new("UICorner")
    indicatorCorner.CornerRadius = UDim.new(1, 0)
    indicatorCorner.Parent = indicator
    create("UIPadding", {
        Parent = button,
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 8),
    })
    tabButtons[tabName] = button

    local defaultLabel: string = tabName == "Config." and "Settings" or tabName
    local defaultButton: TextButton = makeButton(
        state.shells.defaultTabs,
        defaultLabel,
        state.isMobile and 11 or 13
    )
    defaultButton.Name = tabName .. "DefaultTab"
    defaultButton.LayoutOrder = layoutOrder
    defaultButton.Size = UDim2.new(1, 0, 0, state.isMobile and 38 or 42)
    defaultButton.BackgroundColor3 = Theme.DefaultSidebar
    defaultButton.BackgroundTransparency = 1
    defaultButton.TextColor3 = Theme.DefaultTextMuted
    defaultButton.TextXAlignment = Enum.TextXAlignment.Left
    defaultButton.ZIndex = 12
    defaultButton:SetAttribute("ThemeRole", "Navigation")
    defaultButton:SetAttribute("SelectedColor", Theme.DefaultSurface)
    defaultButton:SetAttribute("IdleColor", Theme.DefaultSidebar)
    defaultButton:SetAttribute("HoverColor", Theme.DefaultSurfaceHover)
    local defaultPadding: UIPadding = create("UIPadding", {
        Parent = defaultButton,
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 10),
    }) :: UIPadding
    defaultPadding.Name = "DefaultTabPadding"
    defaultTabButtons[tabName] = defaultButton

    local page: CanvasGroup = create("CanvasGroup", {
        Parent = Content,
        Name = tabName .. "Page",
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 5,
    })
    page.ClipsDescendants = true
    create("UICorner", {
        Parent = page,
        CornerRadius = UDim.new(0, 20),
    })
    pages[tabName] = page

    trackUiConnection(button.MouseButton1Click:Connect(function(): ()
        setTab(tabName)
    end))
    trackUiConnection(defaultButton.MouseButton1Click:Connect(function(): ()
        setTab(tabName)
    end))

    return page
end

local UniversalPage = createTab("Universal", 1)
local MovementPage = createTab("Movement", 2)
local MM2Page = createTab("MM2", 3)
createTab("TRS", 4)
createTab("VD", 5)
createTab("MVSD", 6)
local SettingsPage = createTab("Config.", 7)
local function configureGameTabs(): ()
    tabButtons.MM2.Visible = GAME_CHECK.MM2Active
    tabButtons.TRS.Visible = GAME_CHECK.TRSActive
    tabButtons.VD.Visible = GAME_CHECK.VDActive
    tabButtons.MVSD.Visible = GAME_CHECK.MVSDActive
    defaultTabButtons.MM2.Visible = GAME_CHECK.MM2Active
    defaultTabButtons.TRS.Visible = GAME_CHECK.TRSActive
    defaultTabButtons.VD.Visible = GAME_CHECK.VDActive
    defaultTabButtons.MVSD.Visible = GAME_CHECK.MVSDActive

    for _, button: TextButton in pairs(tabButtons) do
        if button.Visible then
            button.Size = UDim2.new(1, -12, 0, state.isMobile and 40 or 44)
        end
    end
    for _, button: TextButton in pairs(defaultTabButtons) do
        if button.Visible then
            button.Size = UDim2.new(1, 0, 0, state.isMobile and 38 or 42)
        end
    end
end

configureGameTabs()

do
local DarkSearchBox: TextBox = makeTextBox(Header, "")
DarkSearchBox.Name = "DarkSearch"
DarkSearchBox.PlaceholderText = state.isMobile and "Search..." or "Search modules..."
DarkSearchBox.AnchorPoint = Vector2.new(1, 0.5)
DarkSearchBox.Position = UDim2.new(1, -18, 0.5, 0)
DarkSearchBox.Size = UDim2.new(0, state.isMobile and 150 or 240, 0, 34)
DarkSearchBox.TextXAlignment = Enum.TextXAlignment.Left
DarkSearchBox.ZIndex = 21
create("UIPadding", {
    Parent = DarkSearchBox,
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 8),
})

local DefaultSearchBox: TextBox = makeTextBox(state.shells.defaultSidebar, "")
DefaultSearchBox.Name = "DefaultSearch"
DefaultSearchBox.PlaceholderText = "Search"
DefaultSearchBox.Position = UDim2.fromOffset(10, 20)
DefaultSearchBox.Size = UDim2.new(1, -20, 0, 34)
DefaultSearchBox.BackgroundColor3 = Theme.DefaultSurface
DefaultSearchBox.BackgroundTransparency = 0.22
DefaultSearchBox.TextColor3 = Theme.DefaultText
DefaultSearchBox.PlaceholderColor3 = Theme.DefaultTextMuted
DefaultSearchBox.TextXAlignment = Enum.TextXAlignment.Left
DefaultSearchBox.ZIndex = 14
create("UIPadding", {
    Parent = DefaultSearchBox,
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 8),
})
state.shells.darkSearchBox = DarkSearchBox
state.shells.defaultSearchBox = DefaultSearchBox
state.searchQuery = ""
end

local UniversalScroll = create("ScrollingFrame", {
    Parent = UniversalPage,
    Name = "UniversalScroll",
    Active = true,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
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
    ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
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
    ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
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
    ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
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
local LoadingCurtain: CanvasGroup = (create("CanvasGroup", {
    Parent = Main,
    Name = "LoadingIntro",
    Active = true,
    BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultBackground
        or Color3.fromRGB(4, 4, 6),
    BackgroundTransparency = state.guiStyle == "Default" and 0 or 0.02,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 500,
}) :: any) :: CanvasGroup
create("UICorner", {
    Parent = LoadingCurtain,
    CornerRadius = UDim.new(0, 10),
})

local LoadingSpinner: ImageLabel = create("ImageLabel", {
    Parent = LoadingCurtain,
    Name = "Spinner",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageColor3 = state.guiStyle == "Default"
        and Theme.DefaultAccent
        or Color3.fromRGB(224, 224, 228),
    Position = UDim2.fromScale(0.5, 0.37),
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.fromOffset(state.isMobile and 48 or 58, state.isMobile and 48 or 58),
    ZIndex = 503,
}) :: ImageLabel
state.assetManager.loadAsync("loadingSpinner", LoadingSpinner)

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

local LoadingTitle: TextLabel = makeTextLabel(
    LoadingCurtain,
    "A Random Menu",
    state.isMobile and 28 or 34
) :: TextLabel
LoadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
LoadingTitle.FontFace = state.guiStyle == "Default" and CONTROL_FONT or TITLE_FONT
LoadingTitle.Position = UDim2.fromScale(0.5, 0.52)
LoadingTitle.Size = UDim2.new(0.8, 0, 0, 48)
LoadingTitle.TextColor3 = state.guiStyle == "Default"
    and Theme.DefaultText
    or Theme.Text
LoadingTitle.TextXAlignment = Enum.TextXAlignment.Center
LoadingTitle.ZIndex = 503

local LoadingLabel: TextLabel = (makeTextLabel(
    LoadingCurtain,
    "Preparing modules · " .. RUNTIME_BUILD_LABEL,
    12
) :: any) :: TextLabel
LoadingLabel.AnchorPoint = Vector2.new(0.5, 0)
LoadingLabel.FontFace = THIN_FONT
LoadingLabel.Position = UDim2.fromScale(0.5, 0.61)
LoadingLabel.Size = UDim2.new(0.72, 0, 0, 28)
LoadingLabel.TextColor3 = state.guiStyle == "Default"
    and Theme.DefaultTextMuted
    or Theme.TextMuted
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
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.69),
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

local loadingIntroFinished: boolean = false
state.finishLoadingIntro = function(failureCount: number): ()
    if loadingIntroFinished or not LoadingCurtain.Parent then
        return
    end
    loadingIntroFinished = true
    if failureCount > 0 then
        LoadingLabel.Text = tostring(failureCount) .. " module(s) loaded with warnings"
    else
        LoadingLabel.Text = "Ready"
    end
    LoadingProgressFill.Size = UDim2.fromScale(1, 1)
    task.delay(0.22, function(): ()
        if not LoadingCurtain.Parent then
            return
        end
        local exitTween: Tween = TweenService:Create(
            LoadingCurtain,
            TweenInfo.new(
                0.38,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out
            ),
            {GroupTransparency = 1}
        )
        exitTween:Play()
        exitTween.Completed:Once(function(): ()
            LoadingSpinnerTween:Cancel()
            LoadingCurtain:Destroy()
        end)
    end)
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
local allFeatures = {}
local featureConnections = {}
state.tooltipConnections = {} :: {RBXScriptConnection}
state.bindFeatureTooltip = nil :: ((any, string) -> ())?

type MobileActionRecord = {
    id: string,
    label: string,
    button: TextButton,
    callback: () -> (),
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
    restoreMenu: boolean,
}

do
local mobileActions: {[string]: MobileActionRecord} = {}
local pendingMobilePlacement: PendingMobilePlacement? = nil

local MobilePlacementOverlay: Frame = (create("Frame", {
    Parent = PopupLayer,
    Name = "MobilePlacementOverlay",
    Active = true,
    BackgroundColor3 = Color3.fromRGB(5, 8, 14),
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
MobilePlacementLabel.Font = Enum.Font.GothamBold
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
    requestedPosition: Vector2?
): MobileActionRecord?
    if not state.isMobile then
        return nil
    end

    local existing: MobileActionRecord? = mobileActions[id]
    if existing then
        existing.callback = callback
        existing.label = label
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
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(selectedPosition.X, selectedPosition.Y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        Text = label,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
        Visible = not state.visible,
        ZIndex = 180,
    }) :: TextButton
    create("UICorner", {
        Parent = button,
        CornerRadius = UDim.new(0, 12),
    })
    create("UIStroke", {
        Parent = button,
        Color = Color3.fromRGB(215, 215, 218),
        Transparency = 0.34,
        Thickness = 1,
    })
    create("UITextSizeConstraint", {
        Parent = button,
        MaxTextSize = 13,
        MinTextSize = 8,
    })

    local record: MobileActionRecord = {
        id = id,
        label = label,
        button = button,
        callback = callback,
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
        record.holdToken += 1
        local token: number = record.holdToken
        task.delay(0.85, function(): ()
            if mobileActions[id] == record
                and record.activeInput == input
                and not record.moved
                and record.holdToken == token then
                record.activeInput = nil
                removeMobileAction(id)
            end
        end)
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
        if record.moved then
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
                        TweenInfo.new(0.12, Enum.EasingStyle.Quad),
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
    callback: () -> ()
): ()
    if not state.isMobile then
        return
    end
    if mobileActions[id] then
        removeMobileAction(id)
        return
    end

    pendingMobilePlacement = {
        id = id,
        label = label,
        callback = callback,
        restoreMenu = state.visible,
    }
    MobilePlacementLabel.Text = "TOUCH TO PLACE " .. string.upper(label)
        .. "\nHOLD THE CIRCLE LATER TO REMOVE IT"
    MobilePlacementOverlay.Visible = true
    Main.Visible = false
    Blur.Size = 0

    local placement: PendingMobilePlacement =
        pendingMobilePlacement :: PendingMobilePlacement
    task.delay(8, function(): ()
        if pendingMobilePlacement == placement then
            pendingMobilePlacement = nil
            MobilePlacementOverlay.Visible = false
            if placement.restoreMenu then
                if state.setMenuVisible then
                    state.setMenuVisible(true)
                else
                    Main.Visible = true
                end
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
        Vector2.new(input.Position.X, input.Position.Y)
    )
    if placement.restoreMenu then
        if state.setMenuVisible then
            state.setMenuVisible(true)
        else
            Main.Visible = true
        end
    end
    notify(placement.label .. " mobile button placed.")
end))

local function bindMobileActionPlacement(
    source: TextButton,
    id: string,
    label: string,
    callback: () -> ()
): ()
    if not state.isMobile then
        return
    end
    source.Text = "ADD"
    local activeInput: InputObject? = nil
    local startPosition: Vector2 = Vector2.zero
    local holdToken: number = 0

    trackUiConnection(source.InputBegan:Connect(function(input: InputObject): ()
        if input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        activeInput = input
        startPosition = Vector2.new(input.Position.X, input.Position.Y)
        holdToken += 1
        local token: number = holdToken
        task.delay(0.62, function(): ()
            if activeInput == input and holdToken == token then
                local current: Vector2 = Vector2.new(
                    input.Position.X,
                    input.Position.Y
                )
                if (current - startPosition).Magnitude < 10 then
                    activeInput = nil
                    beginMobileActionPlacement(id, label, callback)
                end
            end
        end)
    end))
    trackUiConnection(source.InputEnded:Connect(function(input: InputObject): ()
        if activeInput == input then
            activeInput = nil
            holdToken += 1
        end
    end))

    if ensureMobileConfig()[id] ~= nil then
        createMobileAction(id, label, callback, nil)
    end
end
state.bindMobileActionPlacement = bindMobileActionPlacement

local MobileMenuButton = create("TextButton", {
    Parent = ScreenGui,
    Name = "MobileMenuButton",
    AutoButtonColor = false,
    BackgroundColor3 = Color3.fromRGB(17, 21, 29),
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Position = UDim2.new(1, -18, 0, 18),
    AnchorPoint = Vector2.new(1, 0),
    Size = UDim2.fromOffset(52, 52),
    Text = "RTM",
    TextColor3 = Color3.fromRGB(240, 240, 240),
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
    Color = Color3.fromRGB(225, 235, 255),
    Transparency = 0.22,
    Thickness = 1.5,
})
local MobileMenuImage = create("ImageLabel", {
    Parent = MobileMenuButton,
    Name = "Icon",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ScaleType = Enum.ScaleType.Crop,
    Position = UDim2.fromOffset(3, 3),
    Size = UDim2.new(1, -6, 1, -6),
    ZIndex = 191,
}) :: ImageLabel
create("UICorner", {
    Parent = MobileMenuImage,
    CornerRadius = UDim.new(1, 0),
})

-- The RTM text remains visible while the cached icon is prepared asynchronously.
state.assetManager.loadAsync("menuToggle", MobileMenuImage)

trackUiConnection(MobileMenuButton.MouseButton1Click:Connect(function(): ()
    if state.setMenuVisible then
        state.setMenuVisible(not state.visible)
    else
        state.visible = not state.visible
        Main.Visible = state.visible
        setMobileActionVisibility(state.visible)
    end
end))

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
do
local function applyGuiStyle(styleName: string, animate: boolean): ()
    local normalizedStyle: string = styleName == "DARK" and "DARK" or "Default"
    local isDefault: boolean = normalizedStyle == "Default"
    local activeShell: CanvasGroup = isDefault
        and state.shells.default
        or state.shells.dark
    local inactiveShell: CanvasGroup = isDefault
        and state.shells.dark
        or state.shells.default
    local contentHost: Frame = isDefault
        and state.shells.defaultContentHost
        or state.shells.darkContentHost

    state.guiStyle = normalizedStyle
    Content.Parent = contentHost
    Content.Position = UDim2.fromScale(0, 0)
    Content.Size = UDim2.fromScale(1, 1)
    inactiveShell.Visible = false
    activeShell.Visible = true
    activeShell.GroupTransparency = state.animationsEnabled and animate and 1 or 0
    if activeShell.GroupTransparency > 0 then
        TweenService:Create(
            activeShell,
            TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {GroupTransparency = 0}
        ):Play()
    end

    Main.BackgroundColor3 = isDefault and Theme.DefaultBackground or Theme.Background
    state.mainStrokeGradient.Enabled = not isDefault
    state.mainStroke.Color = isDefault and Theme.DefaultOutline or Theme.Accent
    state.mainStroke.Transparency = isDefault and 0.5 or 0.42
    DefaultPanelBackground.ImageTransparency = 0.04
    for _, page: CanvasGroup in pairs(pages) do
        page.BackgroundColor3 = isDefault and Theme.DefaultBackground or Theme.Background
        page.BackgroundTransparency = isDefault and 1 or 0
        for _, descendant: Instance in ipairs(page:GetDescendants()) do
            if descendant:IsA("ScrollingFrame") then
                descendant.ScrollBarImageColor3 = isDefault
                    and Theme.DefaultOutline
                    or Color3.fromRGB(100, 100, 100)
            end
        end
    end
    for _, button: TextButton in pairs(tabButtons) do
        button.BackgroundTransparency = 0
    end
    if state.restyleButtons then
        state.restyleButtons(isDefault)
    end
    if state.restyleTextBoxes then
        state.restyleTextBoxes(isDefault)
    end
    if state.restyleAllFeatures then
        state.restyleAllFeatures(isDefault)
    end
    if state.restyleSettings then
        state.restyleSettings(isDefault)
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

type CardGridRecord = {
    container: ScrollingFrame,
    root: Frame,
    columns: {Frame},
    layouts: {UIListLayout},
    counts: {number},
}

local cardGrids: {[ScrollingFrame]: CardGridRecord} =
    setmetatable({}, {__mode = "k"}) :: any

local function updateCardGrid(record: CardGridRecord): ()
    local firstHeight: number = record.layouts[1].AbsoluteContentSize.Y
    local secondHeight: number = record.layouts[2].AbsoluteContentSize.Y
    local singleColumn: boolean = state.isMobile
        or state.guiStyle == "Default"
        or record.container.AbsoluteSize.X < 690
    local contentHeight: number

    if singleColumn then
        record.columns[1].Position = UDim2.fromOffset(0, 0)
        record.columns[1].Size = UDim2.new(1, 0, 0, firstHeight)
        record.columns[2].Position = UDim2.fromOffset(0, firstHeight + 10)
        record.columns[2].Size = UDim2.new(1, 0, 0, secondHeight)
        contentHeight = firstHeight + secondHeight + 10
    else
        record.columns[1].Position = UDim2.fromOffset(0, 0)
        record.columns[1].Size = UDim2.new(0.5, -5, 0, firstHeight)
        record.columns[2].Position = UDim2.new(0.5, 5, 0, 0)
        record.columns[2].Size = UDim2.new(0.5, -5, 0, secondHeight)
        contentHeight = math.max(firstHeight, secondHeight)
    end
    record.root.Size = UDim2.new(1, -36, 0, contentHeight)
    record.container.CanvasSize = UDim2.fromOffset(0, contentHeight + 54)
end

local function redistributeCardGrid(record: CardGridRecord): ()
    local cards: {GuiObject} = {}
    for _, column: Frame in ipairs(record.columns) do
        for _, child: Instance in ipairs(column:GetChildren()) do
            if child:IsA("GuiObject") then
                table.insert(cards, child)
            end
        end
    end
    table.sort(cards, function(left: GuiObject, right: GuiObject): boolean
        if left.LayoutOrder == right.LayoutOrder then
            return left.Name < right.Name
        end
        return left.LayoutOrder < right.LayoutOrder
    end)
    record.counts[1] = 0
    record.counts[2] = 0
    local oneColumn: boolean = state.isMobile or state.guiStyle == "Default"
    for index: number, card: GuiObject in ipairs(cards) do
        local columnIndex: number = oneColumn and 1 or ((index - 1) % 2) + 1
        card.Parent = record.columns[columnIndex]
        record.counts[columnIndex] += 1
    end
end

state.refreshCardGrids = function(): ()
    for _, record: CardGridRecord in pairs(cardGrids) do
        redistributeCardGrid(record)
        updateCardGrid(record)
    end
end

local function getFeatureCardParent(container: Instance): Instance
    if not container:IsA("ScrollingFrame") then
        return container
    end

    local record: CardGridRecord? = cardGrids[container]
    if not record then
        container.AutomaticCanvasSize = Enum.AutomaticSize.None
        local oldLayout: UIListLayout? =
            container:FindFirstChildOfClass("UIListLayout")
        if oldLayout then
            oldLayout:Destroy()
        end

        local root: Frame = Instance.new("Frame")
        root.Name = "ResponsiveCardGrid"
        root.BackgroundTransparency = 1
        root.BorderSizePixel = 0
        root.Position = UDim2.fromOffset(18, 18)
        root.Size = UDim2.new(1, -36, 0, 0)
        root.Parent = container

        local columns: {Frame} = {}
        local layouts: {UIListLayout} = {}
        for columnIndex: number = 1, 2 do
            local column: Frame = Instance.new("Frame")
            column.Name = "Column" .. tostring(columnIndex)
            column.BackgroundTransparency = 1
            column.BorderSizePixel = 0
            column.Size = UDim2.new(0.5, -5, 0, 0)
            column.Parent = root
            columns[columnIndex] = column

            local layout: UIListLayout = Instance.new("UIListLayout")
            layout.FillDirection = Enum.FillDirection.Vertical
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            layout.Padding = UDim.new(0, 7)
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Parent = column
            layouts[columnIndex] = layout
        end

        record = {
            container = container,
            root = root,
            columns = columns,
            layouts = layouts,
            counts = {0, 0},
        }
        cardGrids[container] = record
        for _, layout: UIListLayout in ipairs(layouts) do
            trackUiConnection(
                layout:GetPropertyChangedSignal("AbsoluteContentSize")
                    :Connect(function(): ()
                        updateCardGrid(record :: CardGridRecord)
                    end)
            )
        end
        trackUiConnection(
            container:GetPropertyChangedSignal("AbsoluteSize"):Connect(
                function(): ()
                    updateCardGrid(record :: CardGridRecord)
                end
            )
        )
        updateCardGrid(record)
    end

    local selectedColumn: number
    if state.isMobile or state.guiStyle == "Default" then
        selectedColumn = 1
    else
        selectedColumn = record.counts[1] <= record.counts[2] and 1 or 2
    end
    record.counts[selectedColumn] += 1
    return record.columns[selectedColumn]
end

local function setSwitchVisual(
    button: TextButton,
    knob: Frame?,
    enabled: boolean,
    animate: boolean?
): ()
    button:SetAttribute("Selected", enabled)
    local isDefault: boolean = state.guiStyle == "Default"
    local targetColor: Color3 = enabled
        and (isDefault and Theme.DefaultButtonHover or state.headerColor)
        or (isDefault and Theme.DefaultButton or Theme.SurfaceRaised)
    local knobSize: number = state.isMobile and 20 or 18
    local knobPosition: UDim2 = enabled
        and UDim2.new(1, -(knobSize + 4), 0.5, -math.floor(knobSize / 2))
        or UDim2.new(0, 4, 0.5, -math.floor(knobSize / 2))
    if animate then
        TweenService:Create(
            button,
            TweenInfo.new(0.18, Enum.EasingStyle.Quart),
            {BackgroundColor3 = targetColor}
        ):Play()
        if knob then
            TweenService:Create(
                knob,
                TweenInfo.new(0.18, Enum.EasingStyle.Quart),
                {
                    Position = knobPosition,
                    BackgroundColor3 = isDefault
                        and Theme.DefaultText
                        or Theme.Text,
                }
            ):Play()
        end
    else
        button.BackgroundColor3 = targetColor
        if knob then
            knob.Position = knobPosition
            knob.BackgroundColor3 = isDefault and Theme.DefaultText or Theme.Text
        end
    end
    local switchStroke: UIStroke? =
        button:FindFirstChild("StyleStroke") :: UIStroke?
    if switchStroke then
        switchStroke.Color = isDefault and Theme.DefaultOutline or Theme.Outline
        switchStroke.Transparency = enabled and 0.16 or 0.34
    end
end

local function createSwitch(parent: Instance, enabled: boolean): (TextButton, Frame)
    local button: TextButton = (makeButton(parent, "", 1) :: any) :: TextButton
    button.AutoButtonColor = false
    button:SetAttribute("ThemeRole", "Switch")
    button:SetAttribute("NoHover", true)
    button:SetAttribute("NoPressEffect", true)
    button.Size = UDim2.fromOffset(state.isMobile and 50 or 46, state.isMobile and 28 or 26)
    local switchCorner: UICorner? = button:FindFirstChild("StyleCorner") :: UICorner?
    if switchCorner then
        switchCorner.CornerRadius = UDim.new(1, 0)
    end
    local switchStroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
    if switchStroke then
        switchStroke.Transparency = 0.3
    end

    local knobSize: number = state.isMobile and 20 or 18
    local knob: Frame = (create("Frame", {
        Parent = button,
        Name = "Knob",
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(knobSize, knobSize),
    }) :: any) :: Frame
    create("UICorner", {
        Parent = knob,
        CornerRadius = UDim.new(1, 0),
    })
    create("UIStroke", {
        Parent = knob,
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 0.55,
        Thickness = 1,
    })
    setSwitchVisual(button, knob, enabled, false)
    return button, knob
end

local function applyFeaturePresentation(feature: any, isDefault: boolean): ()
    local enabled: boolean = feature.enabled == true
    if feature.row then
        feature.row.BackgroundColor3 = isDefault
            and (enabled and Theme.DefaultSurfaceHover or Theme.DefaultSurface)
            or (enabled and Color3.fromRGB(31, 31, 35) or Theme.Background)
        feature.row.BackgroundTransparency = isDefault
            and (enabled and 0.12 or 0.28)
            or (enabled and 0.08 or 1)
    end
    if feature.stroke then
        feature.stroke.Color = isDefault
            and Theme.DefaultOutline
            or (enabled and Color3.fromRGB(225, 225, 230) or Theme.Outline)
        feature.stroke.Transparency = isDefault
            and (enabled and 0.34 or 0.62)
            or (enabled and 0.18 or 1)
    end
    if feature.activeStripe then
        feature.activeStripe.BackgroundColor3 = isDefault
            and Theme.DefaultAccent
            or Color3.fromRGB(228, 228, 230)
        feature.activeStripe.BackgroundTransparency = enabled and 0 or 1
    end
    if feature.activeStripeGradient then
        feature.activeStripeGradient.Enabled = not isDefault
    end
    if feature.title then
        feature.title.TextColor3 = isDefault and Theme.DefaultText or Theme.Text
    end
    if feature.subtitle then
        feature.subtitle.TextColor3 = isDefault
            and Theme.DefaultTextMuted
            or Theme.TextMuted
    end
    if feature.options then
        feature.options.BackgroundColor3 = isDefault
            and Theme.DefaultBackground
            or Theme.Background
        feature.options.BackgroundTransparency = isDefault and 0.18 or 0.66
    end
    if feature.arrow then
        feature.arrow.TextColor3 = isDefault
            and Theme.DefaultTextMuted
            or Theme.TextMuted
    end
    if feature.toggle then
        if feature.isAction then
            feature.toggle.BackgroundColor3 = isDefault
                and Theme.DefaultButtonHover
                or Theme.AccentSoft
            feature.toggle.TextColor3 = isDefault
                and Theme.DefaultText
                or Theme.Text
        elseif not feature.isCategory then
            setSwitchVisual(feature.toggle, feature.toggleKnob, enabled, false)
        end
    end
    if feature.shortcutButton then
        local slotFrame: ImageLabel? =
            feature.shortcutButton:FindFirstChild("KeySlotFrame") :: ImageLabel?
        if slotFrame then
            slotFrame.Visible = not isDefault
        end
        feature.shortcutButton.BackgroundColor3 = isDefault
            and Theme.DefaultButton
            or Theme.SurfaceRaised
        feature.shortcutButton.BackgroundTransparency = isDefault and 0 or 1
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
    setSwitchVisual(
        feature.toggle,
        feature.toggleKnob,
        feature.enabled,
        true
    )
    if feature.activeStripe then
        TweenService:Create(
            feature.activeStripe,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad),
            {BackgroundTransparency = feature.enabled and 0 or 1}
        ):Play()
    end
    if feature.row then
        TweenService:Create(
            feature.row,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad),
            {
                BackgroundColor3 = feature.enabled
                    and (state.guiStyle == "Default"
                        and Theme.DefaultSurfaceHover
                        or Color3.fromRGB(31, 31, 35))
                    or (state.guiStyle == "Default"
                        and Theme.DefaultSurface
                        or Theme.Background),
                BackgroundTransparency = state.guiStyle == "Default"
                    and (feature.enabled and 0.12 or 0.28)
                    or (feature.enabled and 0.08 or 1),
            }
        ):Play()
    end
    if feature.title then
        TweenService:Create(
            feature.title,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad),
            {TextColor3 = state.guiStyle == "Default"
                and Theme.DefaultText
                or (feature.enabled and Color3.fromRGB(255, 255, 255) or Theme.Text)}
        ):Play()
    end
    if feature.stroke then
        TweenService:Create(
            feature.stroke,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad),
            {
                Color = feature.enabled
                    and (state.guiStyle == "Default"
                        and Theme.DefaultOutline
                        or Color3.fromRGB(225, 225, 230))
                    or (state.guiStyle == "Default"
                        and Theme.DefaultOutline
                        or Theme.Outline),
                Transparency = state.guiStyle == "Default"
                    and (feature.enabled and 0.34 or 0.62)
                    or (feature.enabled and 0.18 or 1),
            }
        ):Play()
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
            notify("Error en " .. errorPrefix)
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

local function compactShortcutLabel(label: string): string
    local compact: string = string.upper(label:gsub("[^%w]", ""))
    if compact == "" then
        return "ACT"
    end
    return string.sub(compact, 1, 6)
end

local function bindActionShortcut(
    button: TextButton,
    shortcutId: string,
    label: string,
    callback: () -> ()
): ()
    local optionKey: string = "Shortcut." .. shortcutId:gsub("%W", "")
    local shortcutKey: Enum.KeyCode = Enum.KeyCode.Unknown
    local savedName: any = configData.values[optionKey]
    if type(savedName) == "string" and savedName ~= "" then
        local savedKey: Enum.KeyCode? = Enum.KeyCode[savedName]
        if savedKey then
            shortcutKey = savedKey
        end
    end

    local function refreshButtonText(): ()
        if state.isMobile then
            button.Text = "ADD"
        else
            button.Text = shortcutKey == Enum.KeyCode.Unknown
                and "KEY"
                or shortcutKey.Name
        end
    end

    refreshButtonText()
    if state.isMobile then
        if state.bindMobileActionPlacement then
            state.bindMobileActionPlacement(
                button,
                "Shortcut" .. shortcutId:gsub("%W", ""),
                compactShortcutLabel(label),
                callback
            )
        end
        return
    end

    trackUiConnection(button.MouseButton1Click:Connect(function(): ()
        button.Text = "..."
        setKeySlotCapture(button, true)
        state.keyCaptureCallback = function(keyCode: Enum.KeyCode): ()
            shortcutKey = keyCode
            setKeySlotCapture(button, false)
            configData.values[optionKey] = keyCode.Name
            queueConfigSave()
            refreshButtonText()
        end
    end))
    trackUiConnection(UserInputService.InputBegan:Connect(function(
        input: InputObject,
        gameProcessed: boolean
    ): ()
        if gameProcessed
            or shortcutKey == Enum.KeyCode.Unknown
            or state.keyCaptureCallback
            or UserInputService:GetFocusedTextBox() then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == shortcutKey then
            task.spawn(callback)
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

    local feature: any = {
        name = name,
        description = description,
        enabled = false,
        expanded = false,
        isAction = configuration.action == true,
        isCategory = configuration.category == true,
        optionCount = 0,
        optionRows = {},
        collapsedHeight = state.isMobile and 56 or 52,
        onToggle = onToggle,
        configKey = configKey,
        sectionName = sectionName,
        tooltipText = description,
        tooltipBound = false,
    }

    local requestedParent: Instance =
        configuration.parent or UniversalScroll
    local row: Frame = (create("Frame", {
        Parent = getFeatureCardParent(requestedParent),
        Name = name:gsub("%W", "") .. "Feature",
        Active = true,
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultSurface
            or Theme.Background,
        BackgroundTransparency = state.guiStyle == "Default" and 0.28 or 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, feature.collapsedHeight),
    }) :: any) :: Frame
    feature.row = row
    create("UICorner", {
        Parent = row,
        CornerRadius = UDim.new(0, 12),
    })
    local cardStroke: UIStroke = (create("UIStroke", {
        Parent = row,
        Color = state.guiStyle == "Default"
            and Theme.DefaultOutline
            or Theme.Outline,
        Transparency = state.guiStyle == "Default" and 0.62 or 1,
        Thickness = 1,
    }) :: any) :: UIStroke
    feature.stroke = cardStroke

    local activeStripe: Frame = (create("Frame", {
        Parent = row,
        Name = "ActiveAccent",
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultAccent
            or Color3.fromRGB(228, 228, 230),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 7),
        Size = UDim2.new(0, 3, 1, -14),
        ZIndex = 3,
    }) :: any) :: Frame
    local stripeCorner: UICorner = Instance.new("UICorner")
    stripeCorner.CornerRadius = UDim.new(1, 0)
    stripeCorner.Parent = activeStripe
    local stripeGradient: UIGradient = Instance.new("UIGradient")
    stripeGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(92, 92, 96)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(238, 238, 240)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 132)),
    })
    stripeGradient.Rotation = 90
    stripeGradient.Parent = activeStripe
    stripeGradient.Enabled = state.guiStyle ~= "Default"
    feature.activeStripe = activeStripe
    feature.activeStripeGradient = stripeGradient

    local title: TextLabel = (makeTextLabel(row, name, 12) :: any) :: TextLabel
    title.FontFace = CONTROL_FONT
    title.Position = UDim2.fromOffset(16, 0)
    title.Size = UDim2.new(1, -136, 0, feature.collapsedHeight)
    title.TextColor3 = state.guiStyle == "Default"
        and Theme.DefaultText
        or Theme.Text
    feature.title = title

    local subtitle: TextLabel =
        (makeTextLabel(row, description, 11) :: any) :: TextLabel
    subtitle.Name = "Description"
    subtitle.Position = UDim2.fromOffset(16, 34)
    subtitle.Size = UDim2.new(1, -118, 0, 30)
    subtitle.TextColor3 = state.guiStyle == "Default"
        and Theme.DefaultTextMuted
        or Theme.TextMuted
    subtitle.TextTruncate = Enum.TextTruncate.AtEnd
    subtitle.TextWrapped = true
    subtitle.Visible = false
    feature.subtitle = subtitle

    local headerControlTop: number = if state.isMobile then 10 else 9
    local toggle: TextButton
    local toggleKnob: Frame? = nil
    if feature.isAction then
        toggle = (makeButton(row, "RUN", 11) :: any) :: TextButton
        toggle.BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultButtonHover
            or Theme.AccentSoft
        toggle.Size = UDim2.fromOffset(state.isMobile and 52 or 46, state.isMobile and 28 or 24)
    else
        local createdToggle: TextButton, createdKnob: Frame =
            createSwitch(row, false)
        toggle = createdToggle
        toggleKnob = createdKnob
    end
    toggle.Name = "Toggle"
    toggle.AnchorPoint = Vector2.new(1, 0)
    toggle.Position = UDim2.new(1, -36, 0, headerControlTop)
    toggle.Visible = not feature.isCategory
    feature.toggle = toggle
    feature.toggleKnob = toggleKnob

    local arrow: TextButton =
        (makeButton(row, "•••", state.isMobile and 16 or 13) :: any) :: TextButton
    arrow.Name = "Expand"
    arrow:SetAttribute("ThemeRole", "Icon")
    arrow:SetAttribute("NoPressEffect", true)
    arrow.AnchorPoint = Vector2.new(1, 0)
    arrow.BackgroundTransparency = 1
    arrow.Position = UDim2.new(1, -7, 0, headerControlTop)
    arrow.Size = UDim2.fromOffset(state.isMobile and 28 or 24, state.isMobile and 28 or 24)
    arrow.TextColor3 = state.guiStyle == "Default"
        and Theme.DefaultTextMuted
        or Theme.TextMuted
    arrow.Visible = configuration.noOptions ~= true
    feature.arrow = arrow

    trackUiConnection(row.MouseEnter:Connect(function(): ()
        if feature.enabled then
            return
        end
        TweenService:Create(
            row,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {
                BackgroundColor3 = state.guiStyle == "Default"
                    and Theme.DefaultSurfaceHover
                    or Theme.SurfaceHover,
                BackgroundTransparency = state.guiStyle == "Default" and 0.12 or 0.78,
            }
        ):Play()
    end))
    trackUiConnection(row.MouseLeave:Connect(function(): ()
        TweenService:Create(
            row,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {
                BackgroundColor3 = feature.enabled
                    and (state.guiStyle == "Default"
                        and Theme.DefaultSurfaceHover
                        or Color3.fromRGB(31, 31, 35))
                    or (state.guiStyle == "Default"
                        and Theme.DefaultSurface
                        or Theme.Background),
                BackgroundTransparency = state.guiStyle == "Default"
                    and (feature.enabled and 0.12 or 0.28)
                    or (feature.enabled and 0.08 or 1),
            }
        ):Play()
    end))

    local options: Frame = (create("Frame", {
        Parent = row,
        Name = "Options",
        Active = true,
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultBackground
            or Theme.Background,
        BackgroundTransparency = state.guiStyle == "Default" and 0.18 or 0.66,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, feature.collapsedHeight),
        Size = UDim2.new(1, -20, 0, 0),
        Visible = false,
        ZIndex = row.ZIndex + 10,
    }) :: any) :: Frame
    feature.options = options
    create("UICorner", {
        Parent = options,
        CornerRadius = UDim.new(0, 8),
    })
    create("UIPadding", {
        Parent = options,
        PaddingBottom = UDim.new(0, 7),
        PaddingLeft = UDim.new(0, 7),
        PaddingRight = UDim.new(0, 7),
        PaddingTop = UDim.new(0, 7),
    })
    local optionsLayout: UIListLayout = (create("UIListLayout", {
        Parent = options,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }) :: any) :: UIListLayout

    local function updateExpandedSize(animate: boolean?): ()
        local visibleOptions: number = 0
        for _, optionRow: GuiObject in ipairs(feature.optionRows) do
            if optionRow.Visible then
                visibleOptions += 1
            end
        end
        local measuredHeight: number = optionsLayout.AbsoluteContentSize.Y
        if visibleOptions > 0 and measuredHeight <= 0 then
            measuredHeight = visibleOptions * 38
                + math.max(0, visibleOptions - 1) * 6
        end
        local optionsHeight: number = measuredHeight + 14
        local targetOptionsSize: UDim2 = UDim2.new(1, -20, 0, optionsHeight)
        local targetRowSize: UDim2 = UDim2.new(
            1,
            0,
            0,
            feature.expanded
                and feature.collapsedHeight + optionsHeight + 10
                or feature.collapsedHeight
        )
        if feature.expanded then
            options.Visible = true
        end
        if animate and state.animationsEnabled then
            TweenService:Create(
                options,
                TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                {Size = targetOptionsSize}
            ):Play()
            TweenService:Create(
                row,
                TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                {Size = targetRowSize}
            ):Play()
            arrow.TextColor3 = state.guiStyle == "Default"
                and (feature.expanded and Theme.DefaultText or Theme.DefaultTextMuted)
                or (feature.expanded and Theme.Text or Theme.TextMuted)
            if not feature.expanded then
                task.delay(0.21, function(): ()
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
        feature.expanded = not feature.expanded
        updateExpandedSize(true)
    end))

    local function activateFeature(): ()
        if feature.isCategory then
            return
        end
        if feature.isAction then
            runActionButton(
                toggle,
                "RUN",
                feature.onToggle,
                name .. " ejecutado",
                "[Random Testing Menu] " .. name
            )
            return
        end

        local requestedState: boolean = not feature.enabled
        local success: boolean, errorMessage: any = pcall(
            feature.onToggle,
            requestedState
        )
        if success then
            feature.enabled = requestedState
            configData.states[feature.configKey] = requestedState
            queueConfigSave()
            notify(name .. (requestedState and " activado" or " desactivado"))
        else
            warn("[Random Testing Menu] " .. name .. ": " .. tostring(errorMessage))
            feature.enabled = false
            pcall(feature.onToggle, false)
            notify("No se pudo cambiar " .. name)
        end
        refreshFeatureToggle(feature)
    end
    feature.activate = activateFeature

    trackUiConnection(toggle.MouseButton1Click:Connect(activateFeature))
    if not feature.isCategory then
        local shortcutButton: TextButton =
            (makeButton(row, "KEY", 9) :: any) :: TextButton
        shortcutButton.Name = "Shortcut"
        shortcutButton.AnchorPoint = Vector2.new(1, 0)
        shortcutButton.BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultButton
            or Theme.SurfaceRaised
        shortcutButton.Position = UDim2.new(1, -84, 0, headerControlTop)
        shortcutButton.Size = UDim2.fromOffset(
            state.isMobile and 48 or 44,
            state.isMobile and 30 or 27
        )
        applyKeySlotStyle(shortcutButton)
        shortcutButton.TextScaled = true
        create("UITextSizeConstraint", {
            Parent = shortcutButton,
            MaxTextSize = 9,
            MinTextSize = 7,
        })
        feature.shortcutButton = shortcutButton
        bindActionShortcut(
            shortcutButton,
            feature.configKey,
            name,
            activateFeature
        )
    end

    registry[name] = feature
    table.insert(allFeatures, feature)
    applyFeaturePresentation(feature, state.guiStyle == "Default")

    if not feature.isAction
        and not feature.isCategory
        and configData.states[feature.configKey] == true then
        task.defer(function(): ()
            local success: boolean, errorMessage: any = pcall(
                feature.onToggle,
                true
            )
            if success then
                feature.enabled = true
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

local function createOptionRow(feature: any, labelText: string): Frame
    feature.optionCount += 1
    local option: Frame = (create("Frame", {
        Parent = feature.options,
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = feature.optionCount,
        Size = UDim2.new(1, 0, 0, 38),
        ZIndex = feature.options.ZIndex + 1,
    }) :: any) :: Frame
    create("UICorner", {
        Parent = option,
        CornerRadius = UDim.new(0, 7),
    })
    create("Frame", {
        Parent = option,
        Name = "OptionDivider",
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = Theme.Outline,
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        ZIndex = option.ZIndex + 1,
    })
    table.insert(feature.optionRows, option)

    local label: TextLabel =
        (makeTextLabel(option, labelText, 11) :: any) :: TextLabel
    label.Position = UDim2.fromOffset(10, 0)
    label.Size = UDim2.new(0.52, -10, 1, 0)
    label.TextColor3 = Theme.TextMuted

    feature.updateExpandedSize()
    return option
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
    callback: (boolean) -> ()
): TextButton
    local optionKey: string =
        feature.configKey .. "." .. labelText:gsub("%W", "")
    local enabled: boolean? = configData.states[optionKey]
    if enabled == nil then
        enabled = defaultValue == true
    end

    local option: Frame = createOptionRow(feature, labelText)
    local button: TextButton, knob: Frame =
        createSwitch(option, enabled :: boolean)
    button.AnchorPoint = Vector2.new(1, 0.5)
    button.Position = UDim2.new(1, -8, 0.5, 0)

    trackUiConnection(button.MouseButton1Click:Connect(function(): ()
        enabled = not enabled
        setSwitchVisual(button, knob, enabled :: boolean, true)
        configData.states[optionKey] = enabled
        callback(enabled :: boolean)
        queueConfigSave()
        notify(labelText .. ((enabled :: boolean) and " activado" or " desactivado"))
    end))

    callback(enabled :: boolean)
    return button
end
local function addActionOption(
    feature: any,
    labelText: string,
    callback: () -> ()
): TextButton
    local option = createOptionRow(feature, labelText)
    local button = makeButton(option, "RUN", 11)
    button.BackgroundColor3 = state.guiStyle == "Default"
        and Theme.DefaultButtonHover
        or Theme.AccentSoft
    button.Position = UDim2.new(0.72, 0, 0, 0)
    button.Size = UDim2.new(0.28, 0, 1, 0)
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
    shortcutButton.Position = UDim2.new(0.55, 0, 0, 0)
    shortcutButton.Size = UDim2.new(0.15, 0, 1, 0)
    applyKeySlotStyle(shortcutButton)
    shortcutButton.TextScaled = true
    create("UITextSizeConstraint", {
        Parent = shortcutButton,
        MaxTextSize = 9,
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
    callback: (number) -> ()
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

    local option: Frame = createOptionRow(feature, labelText)
    local slider: TextButton = (create("TextButton", {
        Parent = option,
        Name = "Slider",
        Active = true,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(0.5, -6, 1, 0),
        Text = "",
    }) :: any) :: TextButton

    local track: Frame = (create("Frame", {
        Parent = slider,
        Name = "Track",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 4, 0.5, 0),
        Size = UDim2.new(1, -88, 0, state.isMobile and 7 or 5),
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

    local knobSize: number = state.isMobile and 18 or 14
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
    valueInput.Size = UDim2.fromOffset(76, 30)
    valueInput.TextColor3 = Theme.Text
    valueInput.TextXAlignment = Enum.TextXAlignment.Center
    valueInput.TextTruncate = Enum.TextTruncate.AtEnd

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
            notify(labelText .. ": valor numérico inválido")
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
local function addCycleOption(
    feature: any,
    labelText: string,
    values: {string},
    initialIndex: number?,
    callback: (string) -> ()
): TextButton
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local storedValue = configData.values[optionKey]
    local option = createOptionRow(feature, labelText)
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
    button.Position = UDim2.new(0.5, 0, 0, 0)
    button.Size = UDim2.new(0.5, 0, 1, 0)

    button.MouseButton1Click:Connect(function()
        index = index % #values + 1
        button.Text = values[index]
        callback(values[index])
        configData.values[optionKey] = values[index]
        queueConfigSave()
    end)

    callback(values[index])
    return button :: TextButton
end

local function addKeyOption(
    feature: any,
    labelText: string,
    defaultKey: Enum.KeyCode,
    callback: (Enum.KeyCode) -> ()
): TextButton
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local savedKey = nil
    local savedName = configData.values[optionKey]
    if type(savedName) == "string" and savedName ~= "" then
        pcall(function()
            savedKey = Enum.KeyCode[savedName]
        end)
    end
    local initialKey = savedKey or defaultKey
    local option = createOptionRow(feature, labelText)
    local button = makeButton(option, initialKey.Name, 11)
    button.Position = UDim2.new(0.5, 0, 0, 0)
    button.Size = UDim2.new(0.5, 0, 1, 0)
    applyKeySlotStyle(button)

    button.MouseButton1Click:Connect(function()
        if state.isMobile then
            return
        end
        button.Text = "PRESIONA UNA TECLA…"
        setKeySlotCapture(button, true)
        state.keyCaptureCallback = function(keyCode)
            button.Text = keyCode.Name
            setKeySlotCapture(button, false)
            callback(keyCode)
            configData.values[optionKey] = keyCode.Name
            queueConfigSave()
        end
    end)

    callback(initialKey)
    return button :: TextButton
end

local function addTextOption(
    feature: any,
    labelText: string,
    defaultText: string,
    callback: (string) -> (),
    persist: boolean?
): TextBox
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local shouldPersist = persist ~= false
    local initialText = shouldPersist and configData.values[optionKey] or nil
    if initialText == nil then
        initialText = defaultText or ""
    end
    local option = createOptionRow(feature, labelText)
    local box = makeTextBox(option, initialText)
    box.PlaceholderText = "Enter value"
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Position = UDim2.new(0.5, 0, 0, 0)
    box.Size = UDim2.new(0.5, 0, 1, 0)

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
            BackgroundColor3 = Color3.fromRGB(22, 22, 22),
            BorderColor3 = Color3.fromRGB(72, 72, 72),
            BorderSizePixel = 1,
            Position = UDim2.new(0.5, -170, 0.5, -135),
            Size = UDim2.fromOffset(340, 270),
            Visible = false,
            ZIndex = 80,
        })
        create("UICorner", {
            Parent = panel,
            CornerRadius = UDim.new(0, 8),
        })

        local title = makeTextLabel(panel, "COLOR", 14)
        title.Font = Enum.Font.GothamBold
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
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
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
            BorderColor3 = Color3.fromRGB(15, 15, 15),
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
            BorderColor3 = Color3.fromRGB(15, 15, 15),
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

local function addColorOption(feature, labelText, defaultColor, callback)
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local color = colorFromConfig(configData.values[optionKey], defaultColor)
    local option = createOptionRow(feature, labelText)
    local swatch = makeButton(option, "", 10)
    swatch.AutoButtonColor = false
    swatch:SetAttribute("NoHover", true)
    swatch.Position = UDim2.new(1, -34, 0, 3)
    swatch.Size = UDim2.fromOffset(28, 28)
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
    BackgroundColor3 = Color3.fromRGB(15, 15, 15),
    BackgroundTransparency = 0.04,
    BorderColor3 = Color3.fromRGB(58, 58, 58),
    BorderSizePixel = 1,
    Font = Enum.Font.Gotham,
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
    CornerRadius = UDim.new(0, 4),
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
    preset: string,
    speed: number,
    verticalSpeed: number,
    response: number,
    wallCheck: boolean,
    platformStand: boolean,
    faceCamera: boolean,
    upKey: Enum.KeyCode,
    downKey: Enum.KeyCode,
}

local findPlayerByText: (string) -> Player? = function(_text: string): Player?
    return nil
end
local performFling: (Player) -> () = function(_target: Player): () end

do
local flySettings: FlySettings = {
    preset = "Balanced",
    speed = 70,
    verticalSpeed = 56,
    response = 1,
    wallCheck = true,
    platformStand = true,
    faceCamera = true,
    upKey = Enum.KeyCode.Space,
    downKey = Enum.KeyCode.LeftControl,
}
local flySmoothedVelocity: Vector3 = Vector3.zero
local originalFlyPlatformStand: boolean? = nil
local flyTouchVertical: number = 0

local function removeFlyObjects(): ()
    local _, humanoid, root = getCharacterParts()
    if humanoid and originalFlyPlatformStand ~= nil then
        humanoid.PlatformStand = originalFlyPlatformStand
    end
    originalFlyPlatformStand = nil

    if not root then
        return
    end

    for _, name in ipairs({
        "RTM_FlyAttachment",
        "RTM_FlyVelocity",
        "RTM_FlyOrientation",
    } :: {string}) do
        local object: Instance? = root:FindFirstChild(name)
        if object then
            object:Destroy()
        end
    end
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

    return velocity :: LinearVelocity, orientation :: AlignOrientation
end

local function getFlyDirection(
    humanoid: Humanoid,
    camera: Camera
): (Vector3, Vector3)
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

    local horizontal: Vector3 = humanoid.MoveDirection
    if horizontal.Magnitude <= 0.001 then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            horizontal = horizontal + cameraForward
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            horizontal = horizontal - cameraForward
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            horizontal = horizontal + cameraRight
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            horizontal = horizontal - cameraRight
        end
    end

    if horizontal.Magnitude > 1 then
        horizontal = horizontal.Unit
    end

    local vertical: number = 0
    if UserInputService:IsKeyDown(flySettings.upKey)
        or flyTouchVertical > 0 then
        vertical = vertical + 1
    end
    if UserInputService:IsKeyDown(flySettings.downKey)
        or flyTouchVertical < 0 then
        vertical = vertical - 1
    end

    local targetVelocity: Vector3 = horizontal * flySettings.speed
        + Vector3.new(0, vertical * flySettings.verticalSpeed, 0)
    return targetVelocity, cameraForward
end

local function toggleFly(enabled: boolean): ()
    disconnectFeatureConnection("Fly")
    removeFlyObjects()
    flySmoothedVelocity = Vector3.zero
    flyTouchVertical = 0

    if not enabled then
        return
    end

    featureConnections.Fly = TaskManager:Connect(function(deltaTime: number): ()
        local _, humanoid, root = getCharacterParts()
        local camera: Camera? = workspace.CurrentCamera
        if not humanoid or not root or not camera then
            return
        end

        if originalFlyPlatformStand == nil then
            originalFlyPlatformStand = humanoid.PlatformStand
        end
        humanoid.PlatformStand = flySettings.platformStand

        local velocity, orientation = ensureFlyConstraints(root)
        local targetVelocity, cameraForward = getFlyDirection(humanoid, camera)
        if flySettings.wallCheck then
            local horizontalVelocity: Vector3 = Vector3.new(
                targetVelocity.X,
                0,
                targetVelocity.Z
            )
            if horizontalVelocity.Magnitude > 0.001 then
                local raycastParams: RaycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                local wallHit: RaycastResult? = workspace:Raycast(
                    root.Position,
                    horizontalVelocity.Unit * 2.75,
                    raycastParams
                )
                if wallHit then
                    targetVelocity = Vector3.new(0, targetVelocity.Y, 0)
                end
            end
        end
        local presetResponse: number = flySettings.preset == "Direct" and 28
            or flySettings.preset == "Precise" and 7
            or 12
        local alpha: number = 1 - math.exp(
            -presetResponse * flySettings.response * deltaTime
        )
        flySmoothedVelocity = flySmoothedVelocity:Lerp(targetVelocity, alpha)

        velocity.Enabled = true
        velocity.VectorVelocity = flySmoothedVelocity

        orientation.Enabled = flySettings.faceCamera
        orientation.CFrame = CFrame.lookAt(Vector3.zero, cameraForward)

    end)
end

type HitboxSettings = {
    bodyScale: number,
    visibleTransparency: number,
}

type OriginalHitboxState = {
    size: Vector3,
    transparency: number,
    canCollide: boolean,
    massless: boolean,
}

local hitboxSettings: HitboxSettings = {
    bodyScale = 2.25,
    visibleTransparency = 30,
}
local originalHitboxes: {[BasePart]: OriginalHitboxState} =
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
end

local function isVisibleCharacterPart(part: BasePart): boolean
    return part.Name ~= "HumanoidRootPart"
        and not part:FindFirstAncestorOfClass("Accessory")
        and not part:FindFirstAncestorOfClass("Tool")
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

    if part.Name == "Head" then
        part.Size = Vector3.new(8, 8, 8)
    else
        part.Size = resolvedOriginal.size * hitboxSettings.bodyScale
    end

    part.Transparency = math.min(
        resolvedOriginal.transparency,
        hitboxSettings.visibleTransparency / 100
    )
    part.CanCollide = false
    part.Massless = true
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
        if elapsed < 0.1 then
            return
        end
        elapsed = 0

        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                for _, part: Instance in ipairs(player.Character:GetChildren()) do
                    if part:IsA("BasePart") and isVisibleCharacterPart(part) then
                        applyHitboxToPart(part)
                    end
                end
            end
        end
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

local infiniteJumpSettings = {
    mode = "Rise",
    strength = 50,
    riseSpeed = 75,
}

local function toggleInfiniteJump(enabled)
    disconnectFeatureConnection("InfiniteJump")
    disconnectFeatureConnection("InfiniteJumpRise")

    if not enabled then
        return
    end

    featureConnections.InfiniteJump = UserInputService.InputBegan:Connect(function(
        input,
        processed
    )
        if processed
            or input.KeyCode ~= Enum.KeyCode.Space
            or UserInputService:GetFocusedTextBox()
            or infiniteJumpSettings.mode == "Rise" then
            return
        end

        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
            return
        end

        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        local currentVelocity = root.AssemblyLinearVelocity

        local nextVerticalVelocity
        if infiniteJumpSettings.mode == "Normal" then
            -- The regular soon.lua-style jump: each press adds another
            -- configurable amount of upward velocity.
            nextVerticalVelocity = currentVelocity.Y + infiniteJumpSettings.strength
        else
            -- Fall mode mirrors the abrupt velocity replacement from Inf Jump.lua.
            nextVerticalVelocity = infiniteJumpSettings.strength
        end

        root.AssemblyLinearVelocity = Vector3.new(
            currentVelocity.X,
            nextVerticalVelocity,
            currentVelocity.Z
        )
    end)

    featureConnections.InfiniteJumpRise = TaskManager:Connect(function()
        if infiniteJumpSettings.mode ~= "Rise"
            or not UserInputService:IsKeyDown(Enum.KeyCode.Space)
            or UserInputService:GetFocusedTextBox() then
            return
        end

        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
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
    airControl = 0.72,
    sprintMultiplier = 1.65,
    sprintKey = Enum.KeyCode.LeftShift,
    preserveMomentum = false,
}
local physicsSpeedTeleportClock: number = 0
local originalPhysicsPlatformStand: boolean? = nil
local originalVehicleSeats: {[VehicleSeat]: VehicleSeatState} =
    setmetatable({}, {__mode = "k"}) :: any
local originalMotorHinges: {[HingeConstraint]: HingeState} =
    setmetatable({}, {__mode = "k"}) :: any

local function restorePhysicsMotors(): ()
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

local function togglePhysicsSpeed(enabled: boolean): ()
    disconnectFeatureConnection("PhysicsSpeed")
    restorePhysicsMotors()
    physicsSpeedTeleportClock = 0

    local _, humanoid = getCharacterParts()
    if humanoid and originalPhysicsPlatformStand ~= nil then
        humanoid.PlatformStand = originalPhysicsPlatformStand
    end
    originalPhysicsPlatformStand = nil

    if not enabled then
        return
    end

    featureConnections.PhysicsSpeed =
        TaskManager:Connect(function(deltaTime: number): ()
            local assembly, currentHumanoid, vehicleSeat = getPhysicsSpeedTarget()
            if not assembly or not currentHumanoid then
                return
            end

            if originalPhysicsPlatformStand == nil then
                originalPhysicsPlatformStand = currentHumanoid.PlatformStand
            end
            currentHumanoid.PlatformStand = physicsSpeedSettings.platformStand

            if vehicleSeat and physicsSpeedSettings.customProperties then
                tunePhysicsMotors(vehicleSeat)
            end

            local direction: Vector3 = currentHumanoid.MoveDirection
            if vehicleSeat then
                direction = vehicleSeat.CFrame.LookVector * vehicleSeat.ThrottleFloat
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
            local sprinting: boolean = not state.isMobile
                and UserInputService:IsKeyDown(physicsSpeedSettings.sprintKey)
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

local fovSettings = {value = 90}
local originalFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70

local function toggleFov(enabled)
    disconnectFeatureConnection("FOV")

    if not enabled then
        if workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = originalFov
        end
        return
    end

    if workspace.CurrentCamera then
        originalFov = workspace.CurrentCamera.FieldOfView
    end

    featureConnections.FOV = TaskManager:Connect(function()
        if workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = fovSettings.value
        end
    end)
end

local originalCollision = setmetatable({}, {__mode = "k"})

local function restoreCollision()
    for part, canCollide in pairs(originalCollision) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
    end
    originalCollision = setmetatable({}, {__mode = "k"})
end

local function toggleNoclip(enabled)
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

local function toggleCtrlClickTeleport(enabled)
    disconnectFeatureConnection("CtrlClickTeleport")

    if not enabled then
        return
    end

    featureConnections.CtrlClickTeleport = UserInputService.InputBegan:Connect(
        function(input, processed)
            if processed
                or input.UserInputType ~= Enum.UserInputType.MouseButton1
                or not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                return
            end

            local _, _, root = getCharacterParts()
            local mouse = LocalPlayer:GetMouse()
            if root and mouse and mouse.Hit then
                root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
            end
        end
    )
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
}

local universalFlingSettings: UniversalFlingSettings = {
    target = "",
}
local MAX_FLING_SECONDS: number = 5

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
    task.spawn(function()
        local character, humanoid, root = getCharacterParts()
        local targetCharacter: Model? = targetPlayer.Character
        local targetRoot: BasePart? = targetCharacter
            and targetCharacter:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        local targetHumanoid: Humanoid? = targetCharacter
            and targetCharacter:FindFirstChildOfClass("Humanoid")
            :: Humanoid?

        if not character or not humanoid or not root or not targetRoot then
            flingRunning = false
            notify("The selected target is not available.")
            return
        end

        local savedCFrame: CFrame = root.CFrame
        local savedCameraSubject: (Humanoid | BasePart)? = workspace.CurrentCamera
            and workspace.CurrentCamera.CameraSubject
            :: (Humanoid | BasePart)?
        local mover: LinearVelocity? = nil
        local spinner: AngularVelocity? = nil
        local moverAttachment: Attachment? = nil
        local targetReachedVoid: boolean = false

        local success: boolean, errorMessage: any = pcall(function(): ()
            local newAttachment: Attachment = Instance.new("Attachment")
            newAttachment.Name = "RTM_FlingAttachment"
            newAttachment.Parent = root
            moverAttachment = newAttachment

            local newMover: LinearVelocity = Instance.new("LinearVelocity")
            newMover.Name = "RTM_FlingVelocity"
            newMover.Attachment0 = newAttachment
            newMover.MaxForce = math.huge
            newMover.RelativeTo = Enum.ActuatorRelativeTo.World
            newMover.VectorVelocity = Vector3.new(9e5, 9e5, 9e5)
            newMover.Parent = root
            mover = newMover

            local newSpinner: AngularVelocity = Instance.new("AngularVelocity")
            newSpinner.Name = "RTM_FlingAngular"
            newSpinner.Attachment0 = newAttachment
            newSpinner.MaxTorque = math.huge
            newSpinner.RelativeTo = Enum.ActuatorRelativeTo.World
            newSpinner.AngularVelocity = Vector3.new(9e5, 9e5, 9e5)
            newSpinner.Parent = root
            spinner = newSpinner

            local startedAt: number = os.clock()
            local step: number = 0
            local destroyHeight: number = workspace.FallenPartsDestroyHeight
            if destroyHeight ~= destroyHeight then
                destroyHeight = -500
            end
            local voidThreshold: number = destroyHeight + 35

            while os.clock() - startedAt < MAX_FLING_SECONDS
                and targetPlayer.Parent == Players
                and targetRoot.Parent do
                if targetRoot.Position.Y <= voidThreshold
                    or (targetHumanoid and targetHumanoid.Health <= 0) then
                    targetReachedVoid = true
                    break
                end

                step = step + 1
                local phase: number = (step % 8) / 8 * math.pi * 2
                local offset: CFrame = CFrame.new(
                    math.cos(phase) * 1.35,
                    (step % 2 == 0) and 0.75 or -0.75,
                    math.sin(phase) * 1.35
                )
                root.CFrame = targetRoot.CFrame * offset
                root.AssemblyLinearVelocity = Vector3.new(
                    step % 2 == 0 and 9e5 or -9e5,
                    9e5,
                    step % 2 == 0 and -9e5 or 9e5
                )
                root.AssemblyAngularVelocity = Vector3.new(9e5, 9e5, 9e5)
                RunService.Heartbeat:Wait()
            end
        end)

        if mover then
            mover:Destroy()
        end
        if spinner then
            spinner:Destroy()
        end
        if moverAttachment then
            moverAttachment:Destroy()
        end
        if root and root.Parent then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = savedCFrame + Vector3.new(0, 2, 0)
        end
        if workspace.CurrentCamera then
            workspace.CurrentCamera.CameraSubject = savedCameraSubject or humanoid
        end

        flingRunning = false
        if success and targetReachedVoid then
            notify("Fling completed: " .. targetPlayer.Name .. " reached the void.")
        elseif success then
            notify("Fling stopped after the 5 second safety limit.")
        else
            notify("Fling failed: " .. tostring(errorMessage))
        end
    end)
end

local fullbrightSettings = {
    brightness = 3,
    clockTime = 14,
}
local originalLighting = nil

local function toggleFullbright(enabled)
    disconnectFeatureConnection("Fullbright")

    if not enabled then
        if originalLighting then
            Lighting.Brightness = originalLighting.brightness
            Lighting.ClockTime = originalLighting.clockTime
            Lighting.GlobalShadows = originalLighting.globalShadows
            Lighting.FogEnd = originalLighting.fogEnd
            Lighting.Ambient = originalLighting.ambient
            Lighting.OutdoorAmbient = originalLighting.outdoorAmbient
        end
        return
    end

    originalLighting = {
        brightness = Lighting.Brightness,
        clockTime = Lighting.ClockTime,
        globalShadows = Lighting.GlobalShadows,
        fogEnd = Lighting.FogEnd,
        ambient = Lighting.Ambient,
        outdoorAmbient = Lighting.OutdoorAmbient,
    }

    featureConnections.Fullbright = TaskManager:Connect(function()
        Lighting.Brightness = fullbrightSettings.brightness
        Lighting.ClockTime = fullbrightSettings.clockTime
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    end)
end

state.universalToolkit = (function(): any
type EspSettings = {
    includeTeam: boolean,
    fillTransparency: number,
}

local espSettings: EspSettings = {
    includeTeam = false,
    fillTransparency = 0.72,
}
local espClock: number = 0

local function clearPlayerEsp(): ()
    for _, player: Player in ipairs(Players:GetPlayers()) do
        local character: Model? = player.Character
        local highlight: Instance? = character and character:FindFirstChild("RTM_PlayerESP")
        if highlight then
            highlight:Destroy()
        end
    end
end

local function togglePlayerEsp(enabled: boolean): ()
    disconnectFeatureConnection("PlayerESP")
    clearPlayerEsp()
    espClock = 0
    if not enabled then
        return
    end

    featureConnections.PlayerESP = TaskManager:Connect(function(deltaTime: number): ()
        espClock += deltaTime
        if espClock < 0.35 then
            return
        end
        espClock = 0
        for _, player: Player in ipairs(Players:GetPlayers()) do
            local character: Model? = player.Character
            local shouldShow: boolean = player ~= LocalPlayer
                and character ~= nil
                and (espSettings.includeTeam or player.Team ~= LocalPlayer.Team)
            local existing: Highlight? = character
                and character:FindFirstChild("RTM_PlayerESP") :: Highlight?
            if shouldShow and character then
                local highlight: Highlight = existing or Instance.new("Highlight")
                highlight.Name = "RTM_PlayerESP"
                highlight.Adornee = character
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.FillColor = Theme.AccentCyan
                highlight.FillTransparency = espSettings.fillTransparency
                highlight.OutlineColor = Color3.fromRGB(244, 249, 255)
                highlight.OutlineTransparency = 0.08
                highlight.Parent = character
            elseif existing then
                existing:Destroy()
            end
        end
    end)
end

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
local function toggleHighJump(enabled: boolean): ()
    disconnectFeatureConnection("HighJump")
    if not enabled then
        return
    end
    featureConnections.HighJump = UserInputService.JumpRequest:Connect(function(): ()
        local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if humanoid and root and humanoid.FloorMaterial ~= Enum.Material.Air then
            local current: Vector3 = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(
                current.X,
                highJumpSettings.velocity,
                current.Z
            )
        end
    end)
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
    espSettings = espSettings,
    togglePlayerEsp = togglePlayerEsp,
    toggleXray = toggleXray,
    highJumpSettings = highJumpSettings,
    toggleHighJump = toggleHighJump,
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
    distance: number,
    cooldown: number,
    exitSpeed: number,
    preserveVelocity: boolean,
    key: Enum.KeyCode,
}
local phaseDashSettings: PhaseDashSettings = {
    distance = 20,
    cooldown = 0.8,
    exitSpeed = 42,
    preserveVelocity = true,
    key = Enum.KeyCode.Q,
}
local lastPhaseDash: number = -math.huge

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
        TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
    local params: RaycastParams = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    local collision: RaycastResult? = workspace:Raycast(
        root.Position,
        direction * phaseDashSettings.distance,
        params
    )
    local safeDistance: number = collision
            and math.max(0, collision.Distance - 2.25)
        or phaseDashSettings.distance
    if safeDistance <= 0.1 then
        return
    end
    lastPhaseDash = now
    local previousVelocity: Vector3 = root.AssemblyLinearVelocity
    root.CFrame = root.CFrame + direction * safeDistance
    if not phaseDashSettings.preserveVelocity then
        root.AssemblyLinearVelocity = direction * phaseDashSettings.exitSpeed
            + Vector3.new(0, previousVelocity.Y, 0)
    end
    createPhaseFlash(character)
end

local function togglePhaseDash(enabled: boolean): ()
    disconnectFeatureConnection("PhaseDash")
    if not enabled then
        return
    end
    featureConnections.PhaseDash = UserInputService.InputBegan:Connect(function(
        input: InputObject,
        gameProcessed: boolean
    ): ()
        if gameProcessed or UserInputService:GetFocusedTextBox() then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == phaseDashSettings.key then
            performPhaseDash()
        end
    end)
end

type SoftLandingSettings = {
    triggerSpeed: number,
    scanDistance: number,
    landingSpeed: number,
}
local softLandingSettings: SoftLandingSettings = {
    triggerSpeed = 62,
    scanDistance = 16,
    landingSpeed = 11,
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
            root.AssemblyLinearVelocity = Vector3.new(
                velocity.X,
                -softLandingSettings.landingSpeed,
                velocity.Z
            )
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
local FlyPresetButton: TextButton = addCycleOption(
    FlyFeature,
    "Preset",
    {"Balanced", "Direct", "Precise"},
    1,
    function(value: string): ()
        flySettings.preset = value
    end
)
local FlySpeedRow: Frame = addNumberOption(
    FlyFeature,
    "Horizontal speed",
    flySettings.speed,
    10,
    500,
    function(value: number): ()
        flySettings.speed = value
    end
)
local FlyVerticalRow: Frame = addNumberOption(
    FlyFeature,
    "Vertical speed",
    flySettings.verticalSpeed,
    10,
    350,
    function(value: number): ()
        flySettings.verticalSpeed = value
    end
)
local FlyResponseRow: Frame = addNumberOption(
    FlyFeature,
    "Response multiplier",
    flySettings.response,
    0.5,
    2,
    function(value: number): ()
        flySettings.response = value
    end
)
local FlyWallButton: TextButton = addToggleOption(
    FlyFeature,
    "Wall check",
    flySettings.wallCheck,
    function(value: boolean): ()
        flySettings.wallCheck = value
    end
)
local FlyPlatformButton: TextButton = addToggleOption(
    FlyFeature,
    "PlatformStand",
    flySettings.platformStand,
    function(value: boolean): ()
        flySettings.platformStand = value
    end
)
local FlyFaceButton: TextButton = addToggleOption(
    FlyFeature,
    "Face camera",
    flySettings.faceCamera,
    function(value: boolean): ()
        flySettings.faceCamera = value
    end
)
local FlyUpKeyButton: TextButton = addKeyOption(
    FlyFeature,
    "Up key",
    flySettings.upKey,
    function(value: Enum.KeyCode): ()
        flySettings.upKey = value
    end
)
local FlyDownKeyButton: TextButton = addKeyOption(
    FlyFeature,
    "Down key",
    flySettings.downKey,
    function(value: Enum.KeyCode): ()
        flySettings.downKey = value
    end
)
local FlyAdvancedButton: TextButton = addToggleOption(
    FlyFeature,
    "Advanced settings",
    false,
    function(value: boolean): ()
        setOptionVisible(FlyFeature, FlyResponseRow, value)
        setOptionVisible(FlyFeature, FlyWallButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyPlatformButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyFaceButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyUpKeyButton.Parent :: GuiObject, value)
        setOptionVisible(FlyFeature, FlyDownKeyButton.Parent :: GuiObject, value)
    end
)
local FlyPresetRow: GuiObject = FlyPresetButton.Parent :: GuiObject
local FlyAdvancedRow: GuiObject = FlyAdvancedButton.Parent :: GuiObject
FlyPresetRow.LayoutOrder = 1
FlySpeedRow.LayoutOrder = 2
FlyVerticalRow.LayoutOrder = 3
FlyAdvancedRow.LayoutOrder = 4
if state.bindMobileActionPlacement then
    state.bindMobileActionPlacement(
        FlyUpKeyButton,
        "UniversalFlyUp",
        "UP",
        function(): ()
            flyTouchVertical = flyTouchVertical == 1 and 0 or 1
        end
    )
    state.bindMobileActionPlacement(
        FlyDownKeyButton,
        "UniversalFlyDown",
        "DOWN",
        function(): ()
            flyTouchVertical = flyTouchVertical == -1 and 0 or -1
        end
    )
end
addFeatureTooltip(
    FlyFeature,
    "Use WASD to move, Space to rise and LeftControl to descend. "
        .. "The safe velocity preset handles orientation and acceleration automatically."
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
addFeatureTooltip(
    FlingFeature,
    "Runs until the target reaches the void or five seconds pass. Duration is automatic."
)
end

do
local HitboxFeature = createUniversalFeature(
    "Hitboxes",
    "Extend visible character parts instead of an invisible root block",
    3,
    toggleHitboxes
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
    "Visible transparency %",
    hitboxSettings.visibleTransparency,
    0,
    60,
    function(value)
        hitboxSettings.visibleTransparency = value
    end
)
addFeatureTooltip(
    HitboxFeature,
    "The real head is fixed at 8 studs. Arms, legs and torso keep their appearance "
        .. "and are scaled visibly; HumanoidRootPart is never used."
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
    "Choose continuous, accumulated, or fall-style jumping",
    7,
    toggleInfiniteJump
)
addCycleOption(
    InfiniteJumpFeature,
    "Mode",
    {"Rise", "Normal", "Fall"},
    1,
    function(value)
        infiniteJumpSettings.mode = value
    end
)
addNumberOption(
    InfiniteJumpFeature,
    "Normal / Fall power",
    infiniteJumpSettings.strength,
    10,
    250,
    function(value)
        infiniteJumpSettings.strength = value
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
    {"Adaptive", "Smooth", "Boost", "Teleport"},
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
    "Adaptive changes air authority and retains flow. Smooth accelerates predictably, Boost "
        .. "uses physical impulse, and Teleport advances in short steps. Sprint, momentum, "
        .. "wall safety, auto-jump, and vehicle tuning are independently configurable."
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
local CtrlClickFeature = createUniversalFeature(
    "CTRL + Click Teleport",
    "Teleport to the position under the cursor",
    12,
    toggleCtrlClickTeleport,
    {noOptions = true}
)
addFeatureTooltip(CtrlClickFeature, "Hold LeftControl and click a reachable world position.")
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
    toggleFullbright
)
addNumberOption(
    FullbrightFeature,
    "Brightness",
    fullbrightSettings.brightness,
    0,
    10,
    function(value)
        fullbrightSettings.brightness = value
    end
)
addNumberOption(
    FullbrightFeature,
    "Clock time",
    fullbrightSettings.clockTime,
    0,
    24,
    function(value)
        fullbrightSettings.clockTime = value
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
local PlayerEspFeature = createUniversalFeature(
    "Player ESP",
    "Technical outline for visible and hidden players",
    17,
    state.universalToolkit.togglePlayerEsp
)
addToggleOption(
    PlayerEspFeature,
    "Include team",
    state.universalToolkit.espSettings.includeTeam,
    function(value: boolean): ()
        state.universalToolkit.espSettings.includeTeam = value
    end
)
addNumberOption(
    PlayerEspFeature,
    "Fill transparency %",
    state.universalToolkit.espSettings.fillTransparency * 100,
    0,
    100,
    function(value: number): ()
        state.universalToolkit.espSettings.fillTransparency = value / 100
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
    "Apply a stronger grounded jump without changing global gravity",
    19,
    state.universalToolkit.toggleHighJump
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
    "Collision-aware directional blink with a technical phase flash",
    25,
    state.universalToolkit.togglePhaseDash
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
addToggleOption(
    PhaseDashFeature,
    "Preserve velocity",
    state.universalToolkit.phaseDashSettings.preserveVelocity,
    function(value: boolean): ()
        state.universalToolkit.phaseDashSettings.preserveVelocity = value
    end
)
local PhaseDashKeyButton: TextButton = addKeyOption(
    PhaseDashFeature,
    "Dash key",
    state.universalToolkit.phaseDashSettings.key,
    function(value: Enum.KeyCode): ()
        state.universalToolkit.phaseDashSettings.key = value
    end
)
local PhaseDashAction: TextButton = addActionOption(
    PhaseDashFeature,
    "Dash now",
    state.universalToolkit.performPhaseDash
)
if state.bindMobileActionPlacement then
    state.bindMobileActionPlacement(
        PhaseDashAction,
        "UniversalPhaseDash",
        "DASH",
        state.universalToolkit.performPhaseDash
    )
end
end

do
local SoftLandingFeature = createUniversalFeature(
    "Soft Landing",
    "Detect nearby ground and damp dangerous downward velocity",
    26,
    state.universalToolkit.toggleSoftLanding
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
        ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
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

    local moduleName: string = GAME_MODULES[placeId] or tostring(placeId)
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
    if game.PlaceId ~= placeId then
        return
    end

    state.logBootstrap("PlaceId detectado: " .. tostring(game.PlaceId))
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
    local sectionMatches: {[string]: number} = {}
    local sectionTotals: {[string]: number} = {}
    for _, feature: any in ipairs(allFeatures) do
        local sectionName: string = feature.sectionName or "Universal"
        sectionTotals[sectionName] = (sectionTotals[sectionName] or 0) + 1
        local searchable: string = string.lower(
            feature.name .. " " .. feature.description
        )
        for _, object: Instance in ipairs(feature.row:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                searchable ..= " " .. string.lower(object.Text)
            end
        end
        local matches: boolean = query == ""
            or string.find(searchable, query, 1, true) ~= nil
        feature.row.Visible = matches
        if matches then
            sectionMatches[sectionName] = (sectionMatches[sectionName] or 0) + 1
        end
        if feature.title then
            feature.title.TextColor3 = query ~= "" and matches
                and (state.guiStyle == "Default"
                    and Theme.DefaultAccent
                    or Theme.AccentCyan)
                or (state.guiStyle == "Default"
                    and Theme.DefaultText
                    or Theme.Text)
        end
    end

    for sectionName: string, label: TextLabel in pairs(noResultsLabels) do
        label.Visible = query ~= ""
            and (sectionTotals[sectionName] or 0) > 0
            and (sectionMatches[sectionName] or 0) == 0
    end
end
state.refreshSearch = refreshSearch
local synchronizingSearch: boolean = false
local function updateSearchFrom(source: TextBox, target: TextBox): ()
    if synchronizingSearch then
        return
    end
    synchronizingSearch = true
    state.searchQuery = source.Text
    if target.Text ~= source.Text then
        target.Text = source.Text
    end
    synchronizingSearch = false
    refreshSearch()
end
trackUiConnection(
    state.shells.darkSearchBox:GetPropertyChangedSignal("Text"):Connect(
        function(): ()
            updateSearchFrom(
                state.shells.darkSearchBox,
                state.shells.defaultSearchBox
            )
        end
    )
)
trackUiConnection(
    state.shells.defaultSearchBox:GetPropertyChangedSignal("Text"):Connect(
        function(): ()
            updateSearchFrom(
                state.shells.defaultSearchBox,
                state.shells.darkSearchBox
            )
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
    ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
    ScrollBarThickness = 6,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Size = UDim2.fromScale(1, 1),
})

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

local function createSettingRow(
    titleText: string,
    descriptionText: string,
    height: number?
): (Frame, Frame)
    local row = create("Frame", {
        Parent = getFeatureCardParent(SettingsScroll),
        BackgroundColor3 = state.guiStyle == "Default"
            and Theme.DefaultSurface
            or Theme.Surface,
        BackgroundTransparency = state.guiStyle == "Default" and 0.18 or 0,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, height or 62),
    })

    local title = makeTextLabel(row, titleText, 15)
    title.Font = Enum.Font.GothamBold
    title.Position = UDim2.fromOffset(14, 7)
    title.Size = UDim2.new(0.46, -14, 0, 24)

    local description = makeTextLabel(row, descriptionText, 12)
    description.TextColor3 = Color3.fromRGB(176, 176, 182)
    description.Position = UDim2.fromOffset(14, 30)
    description.Size = UDim2.new(0.48, -14, 0, 22)

    local control = create("Frame", {
        Parent = row,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 8, 0, 8),
        Size = UDim2.new(0.5, -22, 1, -16),
    })

    create("UICorner", {
        Parent = row,
        CornerRadius = UDim.new(0, 10),
    })
    create("UIStroke", {
        Parent = row,
        Name = "SettingStroke",
        Color = state.guiStyle == "Default"
            and Theme.DefaultOutline
            or Theme.Outline,
        Transparency = state.guiStyle == "Default" and 0.48 or 0.28,
        Thickness = 1,
    })
    table.insert(state.settingRows, row)
    return (row :: any) :: Frame, (control :: any) :: Frame
end

state.restyleSettings = function(isDefault: boolean): ()
    SettingsScroll.ScrollBarImageColor3 = isDefault
        and Theme.DefaultOutline
        or Color3.fromRGB(100, 100, 100)
    for _, row: Frame in ipairs(state.settingRows) do
        row.BackgroundColor3 = isDefault and Theme.DefaultSurface or Theme.Surface
        row.BackgroundTransparency = isDefault and 0.18 or 0
        local rowStroke: UIStroke? = row:FindFirstChild("SettingStroke") :: UIStroke?
        if rowStroke then
            rowStroke.Color = isDefault and Theme.DefaultOutline or Theme.Outline
            rowStroke.Transparency = isDefault and 0.48 or 0.28
        end
    end
end

local guiRow: Frame, guiControl: Frame = createSettingRow(
    "GUI style",
    "Switch instantly between the dark and aurora layouts"
)
guiRow.LayoutOrder = 1
local DarkGuiButton: TextButton = makeButton(guiControl, "DARK", 12)
DarkGuiButton.Position = UDim2.fromScale(0, 0)
DarkGuiButton.Size = UDim2.new(0.5, -4, 1, 0)
DarkGuiButton:SetAttribute("SelectedColor", Theme.AccentSoft)
local DefaultGuiButton: TextButton = makeButton(guiControl, "DEFAULT", 12)
DefaultGuiButton.Position = UDim2.new(0.5, 4, 0, 0)
DefaultGuiButton.Size = UDim2.new(0.5, -4, 1, 0)
DefaultGuiButton:SetAttribute("SelectedColor", Theme.AccentSoft)

local function updateGuiStyleButtons(): ()
    local darkSelected: boolean = state.guiStyle == "DARK"
    local idleColor: Color3 = darkSelected
        and Theme.SurfaceRaised
        or Theme.DefaultSurface
    local hoverColor: Color3 = darkSelected
        and Theme.SurfaceHover
        or Theme.DefaultSurfaceHover
    DarkGuiButton:SetAttribute("SelectedColor", Theme.AccentSoft)
    DefaultGuiButton:SetAttribute("SelectedColor", Theme.DefaultAccent)
    DarkGuiButton:SetAttribute("IdleColor", idleColor)
    DefaultGuiButton:SetAttribute("IdleColor", idleColor)
    DarkGuiButton:SetAttribute("HoverColor", hoverColor)
    DefaultGuiButton:SetAttribute("HoverColor", hoverColor)
    DarkGuiButton:SetAttribute("Selected", darkSelected)
    DefaultGuiButton:SetAttribute("Selected", not darkSelected)
    DarkGuiButton.BackgroundColor3 = darkSelected
        and Theme.AccentSoft
        or idleColor
    DefaultGuiButton.BackgroundColor3 = darkSelected
        and idleColor
        or Theme.DefaultAccent
    DarkGuiButton.TextColor3 = darkSelected
        and Theme.Text
        or Theme.DefaultTextMuted
    DefaultGuiButton.TextColor3 = darkSelected
        and Theme.TextMuted
        or Theme.DefaultBackground
end
updateGuiStyleButtons()

local textRow, textControl = createSettingRow(
    "Text size",
    "Drag the linear control to scale every label"
)
textRow.LayoutOrder = 2
local textScaleRatio: number = (state.textScale - 0.85) / 0.5
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
    Color = Color3.fromRGB(120, 120, 126),
    Transparency = 0.12,
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
blurRow.LayoutOrder = 3

local BlurButton: TextButton, BlurKnob: Frame =
    createSwitch(blurControl, state.blurEnabled)
BlurButton.AnchorPoint = Vector2.new(1, 0.5)
BlurButton.Position = UDim2.new(1, 0, 0.5, 0)

local motionRow, motionControl = createSettingRow(
    "Interface motion",
    "Smooth transitions for cards, tabs, and menu controls"
)
motionRow.LayoutOrder = 4
local MotionButton: TextButton, MotionKnob: Frame =
    createSwitch(motionControl, state.animationsEnabled)
MotionButton.AnchorPoint = Vector2.new(1, 0.5)
MotionButton.Position = UDim2.new(1, 0, 0.5, 0)

local keyRow, keyControl = createSettingRow(
    "Menu key",
    "Choose the key used to show or hide"
)
keyRow.LayoutOrder = 5

local KeybindButton = makeButton(keyControl, state.toggleKey.Name, 13)
KeybindButton.Size = UDim2.fromScale(1, 1)
applyKeySlotStyle(KeybindButton)
state.keybindButton = KeybindButton

local reinjectRow, reinjectControl = createSettingRow(
    "Reinject latest",
    "Download and restart the newest main build"
)
reinjectRow.LayoutOrder = 6
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
destructRow.LayoutOrder = 7
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
gameRow.LayoutOrder = 8
local gameStatus = makeTextLabel(
    gameControl,
    GAME_CHECK.MM2Active and "MM2 · 142823291"
        or GAME_CHECK.TRSActive and "TRS · 14315258385"
        or GAME_CHECK.VDActive and "VD · 93978595733734"
        or GAME_CHECK.MVSDActive and "MVSD · 135856908115931"
        or "Universal only",
    12
)
gameStatus.TextXAlignment = Enum.TextXAlignment.Center
gameStatus.Size = UDim2.fromScale(1, 1)

local mobileIconRow, mobileIconControl = createSettingRow(
    "Mobile menu icon",
    "Dog shortcut stays available so the menu cannot become unreachable"
)
mobileIconRow.LayoutOrder = 9
mobileIconRow.Visible = UserInputService.TouchEnabled
local MobileIconButton = makeButton(
    mobileIconControl,
    "ON - REQUIRED",
    13
)
MobileIconButton.Size = UDim2.fromScale(1, 1)
MobileIconButton:SetAttribute(
    "Selected",
    UserInputService.TouchEnabled and state.mobileMenuButtonVisible
)
MobileIconButton.BackgroundColor3 = UserInputService.TouchEnabled
        and state.mobileMenuButtonVisible
        and state.headerColor
    or DEFAULT_SURFACE_COLOR

local mobileSizeRow, mobileSizeControl = createSettingRow(
    "Mobile action size",
    "Size for placed mobile shortcuts"
)
mobileSizeRow.LayoutOrder = 10
mobileSizeRow.Visible = UserInputService.TouchEnabled
local MobileSizeButton = makeButton(
    mobileSizeControl,
    tostring(state.mobileButtonSize) .. " PX",
    13
)
MobileSizeButton.Size = UDim2.fromScale(1, 1)

local mobileResetRow, mobileResetControl = createSettingRow(
    "Mobile action buttons",
    "Hold ADD to place; hold a shortcut to remove it"
)
mobileResetRow.LayoutOrder = 11
mobileResetRow.Visible = UserInputService.TouchEnabled
local MobileResetButton = makeButton(
    mobileResetControl,
    "RESET PLACED",
    13
)
MobileResetButton.Size = UDim2.fromScale(1, 1)

local function setBlurVisible(animate)
    local targetSize = state.visible and state.blurEnabled and 16 or 0

    if animate then
        TweenService:Create(
            Blur,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = targetSize}
        ):Play()
    else
        Blur.Size = targetSize
    end
end
state.setBlurVisible = setBlurVisible

local function setMenuVisible(visible: boolean): ()
    state.visible = visible
    Main.Visible = visible
    state.mobileUi.setActionVisibility(visible)
    setBlurVisible(true)
end
state.setMenuVisible = setMenuVisible

local function updateTextSizes(): ()
    for _, item in ipairs(registeredText) do
        if item.object and item.object.Parent then
            item.object.TextSize = math.round(item.normalSize * state.textScale)
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
    state.textScale = math.round((0.85 + ratio * 0.5) * 100) / 100
    TextSizeFill.Size = UDim2.fromScale(ratio, 1)
    TextSizeKnob.Position = UDim2.fromScale(ratio, 0.5)
    TextSizeValue.Text = tostring(math.round(state.textScale * 100)) .. "%"
    updateTextSizes()
    configData.ui.largeText = nil
    configData.ui.textScale = state.textScale
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

local function selectGuiStyle(styleName: string): ()
    local normalizedStyle: string = styleName == "Default" and "Default" or "DARK"
    if state.guiStyle == normalizedStyle then
        return
    end
    state.applyGuiStyle(normalizedStyle, true)
    configData.ui.guiStyle = normalizedStyle
    updateGuiStyleButtons()
    queueConfigSave()
    notify(normalizedStyle == "Default"
        and "GUI Default activada"
        or "GUI DARK activada")
end

trackUiConnection(DarkGuiButton.MouseButton1Click:Connect(function(): ()
    selectGuiStyle("DARK")
end))
trackUiConnection(DefaultGuiButton.MouseButton1Click:Connect(function(): ()
    selectGuiStyle("Default")
end))

trackUiConnection(BlurButton.MouseButton1Click:Connect(function(): ()
    state.blurEnabled = not state.blurEnabled
    setSwitchVisual(BlurButton, BlurKnob, state.blurEnabled, true)
    setBlurVisible(true)
    configData.ui.blurEnabled = state.blurEnabled
    queueConfigSave()
    notify(state.blurEnabled and "Desenfoque activado" or "Desenfoque desactivado")
end))

trackUiConnection(MotionButton.MouseButton1Click:Connect(function(): ()
    state.animationsEnabled = not state.animationsEnabled
    setSwitchVisual(MotionButton, MotionKnob, state.animationsEnabled, true)
    configData.ui.animationsEnabled = state.animationsEnabled
    queueConfigSave()
end))

local reinjectBusy: boolean = false
trackUiConnection(ReinjectButton.MouseButton1Click:Connect(function(): ()
    if reinjectBusy then
        return
    end
    local compiler: any = executorGlobals.loadstring
    if type(compiler) ~= "function" then
        notify("Reinject no disponible: el ejecutor no admite loadstring")
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
        notify("No se pudo descargar la versión más reciente")
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
        notify("La versión descargada no pudo compilarse")
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
        if state.destruct then
            state.destruct()
        end
    end)
end))

trackUiConnection(MobileIconButton.MouseButton1Click:Connect(function(): ()
    if not UserInputService.TouchEnabled then
        return
    end
    notify("The mobile menu icon remains enabled so the menu is always reachable.")
end))

trackUiConnection(MobileSizeButton.MouseButton1Click:Connect(function(): ()
    if not UserInputService.TouchEnabled then
        return
    end
    local sizes: {number} = {42, 52, 62, 72}
    local nextSize: number = sizes[1]
    for index: number, size: number in ipairs(sizes) do
        if state.mobileButtonSize == size then
            nextSize = sizes[(index % #sizes) + 1]
            break
        end
    end
    state.mobileButtonSize = nextSize
    configData.ui.mobileButtonSize = nextSize
    MobileSizeButton.Text = tostring(nextSize) .. " PX"
    for _, record: MobileActionRecord in pairs(state.mobileUi.actions) do
        record.button.Size = UDim2.fromOffset(nextSize, nextSize)
        local clamped: Vector2 = state.mobileUi.clampButtonPosition(
            Vector2.new(
                record.button.Position.X.Offset,
                record.button.Position.Y.Offset
            ),
            nextSize
        )
        record.button.Position = UDim2.fromOffset(clamped.X, clamped.Y)
        state.mobileUi.saveActionPosition(record)
    end
    queueConfigSave()
end))

trackUiConnection(MobileResetButton.MouseButton1Click:Connect(function(): ()
    if not UserInputService.TouchEnabled then
        return
    end
    state.mobileUi.resetActions()
end))

trackUiConnection(KeybindButton.MouseButton1Click:Connect(function(): ()
    state.waitingForKey = true
    KeybindButton.Text = "PRESIONA UNA TECLA…"
    setKeySlotCapture(KeybindButton, true)
end))

end

SectionManager.register("Config.", buildSettings)

do
local function initializeWindowInput(): ()
local dragging: boolean = false
local dragInput: InputObject? = nil
local dragStart: Vector2 = Vector2.zero
local dragStartPosition: Vector2 = Vector2.zero

local function getPointerPosition(input: InputObject?): Vector2
    if input and input.UserInputType == Enum.UserInputType.Touch then
        return Vector2.new(input.Position.X, input.Position.Y)
    end
    return UserInputService:GetMouseLocation()
end

local function viewportSize(): Vector2
    local camera: Camera? = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function clampMainPosition(position: Vector2): Vector2
    local screenSize: Vector2 = viewportSize()
    local mainSize: Vector2 = Main.AbsoluteSize
    return Vector2.new(
        math.clamp(position.X, 0, math.max(0, screenSize.X - mainSize.X)),
        math.clamp(position.Y, 0, math.max(0, screenSize.Y - mainSize.Y))
    )
end

local function saveWindowGeometry(): ()
    configData.ui.windowPosition = {
        Main.Position.X.Offset,
        Main.Position.Y.Offset,
    }
    configData.ui.windowSize = nil
    queueConfigSave()
end

local function bindDragHandle(handle: GuiObject): ()
    trackUiConnection(handle.InputBegan:Connect(function(input: InputObject): ()
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input.UserInputType == Enum.UserInputType.Touch
                and input
                or dragInput
            dragStart = getPointerPosition(input)
            dragStartPosition = Vector2.new(
                Main.Position.X.Offset,
                Main.Position.Y.Offset
            )
        end
    end))

    trackUiConnection(handle.InputChanged:Connect(function(input: InputObject): ()
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))
end

bindDragHandle(Header)
bindDragHandle(DefaultDragZone)

state.globalInputChangedConnection = UserInputService.InputChanged:Connect(function(
    input: InputObject
): ()
    if dragging and input == dragInput then
        local delta: Vector2 = getPointerPosition(input) - dragStart
        local nextPosition: Vector2 = clampMainPosition(
            dragStartPosition + delta
        )
        Main.Position = UDim2.fromOffset(nextPosition.X, nextPosition.Y)
    end
end)

state.globalInputEndedConnection = UserInputService.InputEnded:Connect(function(
    input: InputObject
): ()
    if dragging
        and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
        dragging = false
        dragInput = nil
        saveWindowGeometry()
    end
end)

local camera: Camera? = workspace.CurrentCamera
if camera then
    trackUiConnection(camera:GetPropertyChangedSignal("ViewportSize"):Connect(
        function(): ()
            task.defer(function(): ()
                if not Main.Parent then
                    return
                end
                local resized: Vector2 = calculateWindowSize(viewportSize())
                Main.Size = UDim2.fromOffset(resized.X, resized.Y)
                local clamped: Vector2 = clampMainPosition(Vector2.new(
                    Main.Position.X.Offset,
                    Main.Position.Y.Offset
                ))
                Main.Position = UDim2.fromOffset(clamped.X, clamped.Y)
            end)
        end
    ))
end

state.globalInputBeganConnection = UserInputService.InputBegan:Connect(function(input)
    if state.keyCaptureCallback then
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode ~= Enum.KeyCode.Unknown then
            local callback = state.keyCaptureCallback
            state.keyCaptureCallback = nil
            callback(input.KeyCode)
        end
        return
    end

    if state.waitingForKey then
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode ~= Enum.KeyCode.Unknown then
            state.toggleKey = input.KeyCode
            state.waitingForKey = false
            if state.keybindButton then
                state.keybindButton.Text = input.KeyCode.Name
                setKeySlotCapture(state.keybindButton, false)
            end
            configData.ui.toggleKey = input.KeyCode.Name
            queueConfigSave()
            notify("Tecla del menú: " .. input.KeyCode.Name)
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
        if state.setMenuVisible then
            state.setMenuVisible(not state.visible)
        else
            state.visible = not state.visible
            Main.Visible = state.visible
        end
    end
end)
end
initializeWindowInput()
end

local runtimeCleaned: boolean = false
local function cleanupRuntime(): ()
    if runtimeCleaned then
        return
    end
    runtimeCleaned = true
        for _, feature in ipairs(allFeatures) do
            if feature.enabled then
                pcall(function()
                    feature.onToggle(false)
                end)
                feature.enabled = false
            end
        end

        for name in pairs(featureConnections) do
            disconnectFeatureConnection(name)
        end
        for _, connection: RBXScriptConnection in ipairs(state.tooltipConnections) do
            connection:Disconnect()
        end
        table.clear(state.tooltipConnections)
        for _, connection: RBXScriptConnection in ipairs(state.uiConnections) do
            connection:Disconnect()
        end
        table.clear(state.uiConnections)

        TaskManager:Destroy()
        if state.globalInputChangedConnection then
            state.globalInputChangedConnection:Disconnect()
        end
        if state.globalInputEndedConnection then
            state.globalInputEndedConnection:Disconnect()
        end
        if state.globalInputBeganConnection then
            state.globalInputBeganConnection:Disconnect()
        end
        if colorPicker.inputChanged then
            colorPicker.inputChanged:Disconnect()
        end
        if colorPicker.inputEnded then
            colorPicker.inputEnded:Disconnect()
        end
        cleanupMM2Runtime()
        if state.cleanupTRSRuntime then
            state.cleanupTRSRuntime()
        end
        if state.cleanupVDRuntime then
            state.cleanupVDRuntime()
        end
        if state.cleanupMVSDRuntime then
            state.cleanupMVSDRuntime()
        end
        saveConfigNow()

        if Blur.Parent then
            Blur:Destroy()
        end
end

state.destruct = function(): ()
    cleanupRuntime()
    if ScreenGui.Parent then
        ScreenGui:Destroy()
    end
end

ScreenGui.AncestryChanged:Connect(function(_: Instance, parent: Instance?): ()
    if not parent then
        cleanupRuntime()
    end
end)

SectionManager.initializeAllAsync()
setTab("Universal")
if state.setBlurVisible then
    state.setBlurVisible(false)
end
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
    if bootstrapStatusLabel and bootstrapStatusLabel.Parent then
        bootstrapStatusLabel.Text = "Initialization error — check executor console"
        bootstrapStatusLabel.TextColor3 = Color3.fromRGB(230, 105, 105)
    end
    warn("[RTM:Bootstrap] Inicialización detenida:\n" .. tostring(bootstrapError))
end
