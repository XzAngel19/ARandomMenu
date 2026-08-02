--!strict
--[[
    A random Testing Menu # 0001
    Standalone, client-sided Roblox GUI.

    Default controls:
      - RightShift: show/hide the menu
      - Drag the blue title bar to move the menu
      - Drag any border or corner to resize the menu
]]

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
local REPOSITORY_RAW_BASE =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/"

local GAME_MODULES: {[number]: string} = {
    [142823291] = "MM2",
    [14315258385] = "TRS",
}

local ACTIVE_GAME_MODULE: string? = GAME_MODULES[game.PlaceId]

local GAME_CHECK = {
    MM2 = 142823291,
    TRS = 14315258385,
    MM2Active = ACTIVE_GAME_MODULE == "MM2",
    TRSActive = ACTIVE_GAME_MODULE == "TRS",
}

function GAME_CHECK.matches(identifier: number): boolean
    return game.PlaceId == identifier
end
local DEFAULT_HEADER_COLOR: Color3 = Color3.fromRGB(226, 226, 226)
local DEFAULT_MENU_COLOR: Color3 = Color3.fromRGB(6, 6, 7)
local DEFAULT_SURFACE_COLOR: Color3 = Color3.fromRGB(18, 18, 20)
local DEFAULT_BORDER_COLOR: Color3 = Color3.fromRGB(82, 82, 86)

local Theme: {[string]: Color3} = {
    Background = Color3.fromRGB(6, 6, 7),
    Surface = Color3.fromRGB(18, 18, 20),
    SurfaceRaised = Color3.fromRGB(27, 27, 30),
    SurfaceHover = Color3.fromRGB(35, 35, 38),
    SurfacePressed = Color3.fromRGB(43, 43, 47),
    Accent = Color3.fromRGB(226, 226, 226),
    AccentCyan = Color3.fromRGB(232, 232, 234),
    AccentViolet = Color3.fromRGB(196, 196, 200),
    AccentPink = Color3.fromRGB(164, 164, 170),
    AccentSoft = Color3.fromRGB(64, 64, 69),
    Text = Color3.fromRGB(242, 242, 244),
    TextMuted = Color3.fromRGB(164, 164, 169),
    Outline = Color3.fromRGB(89, 89, 94),
    Success = Color3.fromRGB(222, 222, 224),
    Danger = Color3.fromRGB(202, 202, 205),
}
local MINIMUM_SIZE = Vector2.new(560, 350)
local MAXIMUM_SIZE = Vector2.new(1100, 760)
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
ScreenGui:SetAttribute("BuildId", "0001-S15")

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

local lowPerformancePreference: boolean = configData.ui.lowPerformanceMode == true
local state: any = {
    visible = true,
    isMobile = IS_MOBILE_DEVICE,
    blurEnabled = configData.ui.blurEnabled ~= false,
    largeText = configData.ui.largeText == true,
    mobileMenuButtonVisible = true,
    animationsEnabled = configData.ui.animationsEnabled ~= false
        and not lowPerformancePreference,
    animationPreference = configData.ui.animationsEnabled ~= false,
    animatedBlossomsEnabled = configData.ui.animatedBlossomsEnabled ~= false,
    reducedBlossomSpeed = configData.ui.reducedBlossomSpeed == true,
    decorativeTexturesEnabled = configData.ui.decorativeTexturesEnabled ~= false,
    lowPerformanceMode = lowPerformancePreference,
    mobileButtonSize = math.clamp(
        tonumber(configData.ui.mobileButtonSize) or 52,
        42,
        72
    ),
    toggleKey = savedToggleKey,
    waitingForKey = false,
    keyCaptureCallback = nil,
    activeTab = "Universal",
    headerColor = colorFromConfig(configData.ui.headerColor, DEFAULT_HEADER_COLOR),
    menuColor = colorFromConfig(configData.ui.menuColor, DEFAULT_MENU_COLOR),
    hookFunction = (getfenv() :: any).hookfunction,
    hookMetamethod = (getfenv() :: any).hookmetamethod,
    getNamecallMethod = (getfenv() :: any).getnamecallmethod,
    newCClosure = (getfenv() :: any).newcclosure,
    fireTouchInterest = (getfenv() :: any).firetouchinterest,
    requireModule = require,
}

type AssetDefinition = {
    url: string,
    fileName: string,
    fallback: string,
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
        headerAnime = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/header-anime.png",
            fileName = "header-anime-v1.png",
            fallback = "",
        },
        blossomSheet = {
            url = REPOSITORY_RAW_BASE
                .. "src/gui/Current/Assets/Blossoms/blossom-spritesheet.png",
            fileName = "blossom-spritesheet-v1.png",
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
    if string.sub(bytes, 1, 8) ~= "\137PNG\r\n\26\n" then
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

function AssetManager.loadAsync(logicalName: string, target: ImageLabel): ()
    task.spawn(function(): ()
        local assetId: string?, loadError: string? = AssetManager.resolve(logicalName)
        local definition: AssetDefinition? = AssetManager.manifest[logicalName]
        if assetId and target.Parent then
            target.Image = assetId
            if target.Image == assetId then
                return
            end
            loadError = "la propiedad Image no conservó el asset asignado"
        end
        if target.Parent and definition then
            target.Image = definition.fallback
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
        state.loadingLabel.Parent.Visible = total > 0
    end

    if total == 0 then
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
            if completed >= total then
                print(
                    "[RTM:Bootstrap] Carga terminada · fallos="
                        .. tostring(failures)
                )
                task.delay(0.35, function(): ()
                    if state.loadingLabel and state.loadingLabel.Parent then
                        state.loadingLabel.Parent.Visible = false
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

    object.TextSize = state.largeText and normalSize + 4 or normalSize
    return object
end

local function makeTextLabel(parent, text, normalSize)
    return registerText(create("TextLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        Text = text,
        TextColor3 = Color3.fromRGB(235, 235, 235),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }), normalSize or 14)
end

local function makeButton(parent, text, normalSize)
    local button = registerText(create("TextButton", {
        Parent = parent,
        AutoButtonColor = false,
        BackgroundColor3 = DEFAULT_SURFACE_COLOR,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = Color3.fromRGB(240, 240, 240),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    }), normalSize or 14)

    addRoundedStyle(button, 9, 0.48)

    button.MouseEnter:Connect(function()
        if button:GetAttribute("NoHover") or button:GetAttribute("Disabled") then
            return
        end
        TweenService:Create(
            button,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundColor3 = Theme.SurfaceHover}
        ):Play()
    end)

    button.MouseLeave:Connect(function()
        if button:GetAttribute("NoHover") then
            return
        end
        local selectedColor: any = button:GetAttribute("SelectedColor")
        local targetColor: Color3 = button:GetAttribute("Selected")
            and (typeof(selectedColor) == "Color3" and selectedColor or Theme.AccentSoft)
            or DEFAULT_SURFACE_COLOR

        TweenService:Create(
            button,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundColor3 = targetColor}
        ):Play()
    end)

    button.MouseButton1Down:Connect(function(): ()
        if button:GetAttribute("Disabled") then
            return
        end
        TweenService:Create(
            button,
            TweenInfo.new(0.08, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Theme.SurfacePressed}
        ):Play()
    end)

    button.MouseButton1Up:Connect(function(): ()
        if button:GetAttribute("Disabled") then
            return
        end
        local selectedColor: any = button:GetAttribute("SelectedColor")
        local targetColor: Color3 = button:GetAttribute("Selected")
            and (typeof(selectedColor) == "Color3" and selectedColor or Theme.AccentSoft)
            or Theme.SurfaceHover
        TweenService:Create(
            button,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad),
            {BackgroundColor3 = targetColor}
        ):Play()
    end)

    return button
end

local function makeTextBox(parent, defaultText)
    local textBox: TextBox = (registerText(create("TextBox", {
        Parent = parent,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderColor3 = Theme.TextMuted,
        Text = tostring(defaultText),
        TextColor3 = Color3.fromRGB(235, 235, 235),
        TextXAlignment = Enum.TextXAlignment.Center,
    }), 13) :: any) :: TextBox
    addRoundedStyle(textBox, 9, 0.5)
    textBox.Focused:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Theme.SurfaceRaised}
        ):Play()
    end)
    textBox.FocusLost:Connect(function(): ()
        TweenService:Create(
            textBox,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Theme.Surface}
        ):Play()
    end)
    return textBox
end

local ToastContainer: Frame = (create("Frame", {
    Parent = ScreenGui,
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
    toast.BackgroundColor3 = Theme.SurfaceRaised
    toast.BackgroundTransparency = 0.04
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
        Color = Theme.Outline,
        Transparency = 0.22,
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
        ZIndex = 302,
    }) :: any) :: ImageLabel
    state.assetManager.loadAsync("noticeFrame", toastFrame)

    local accent: Frame = (create("Frame", {
        Parent = toast,
        BackgroundColor3 = Theme.Accent,
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
    label.TextColor3 = Theme.Text
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
local activeMinimumSize: Vector2 = state.isMobile
    and Vector2.new(
        math.min(330, initialViewport.X),
        math.min(300, initialViewport.Y)
    )
    or MINIMUM_SIZE
local defaultWindowWidth: number = state.isMobile
    and math.max(330, math.floor(initialViewport.X * 0.92))
    or 760
local defaultWindowHeight: number = state.isMobile
    and math.max(300, math.floor(initialViewport.Y * 0.78))
    or 470

local Main: Frame = (create("Frame", {
    Parent = ScreenGui,
    Name = "Main",
    Active = true,
    BackgroundColor3 = state.menuColor,
    BorderSizePixel = 0,
    ClipsDescendants = false,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(
        math.clamp(
            tonumber(configData.ui.windowSize and configData.ui.windowSize[1])
                or defaultWindowWidth,
            activeMinimumSize.X,
            math.min(MAXIMUM_SIZE.X, initialViewport.X)
        ),
        math.clamp(
            tonumber(configData.ui.windowSize and configData.ui.windowSize[2])
                or defaultWindowHeight,
            activeMinimumSize.Y,
            math.min(MAXIMUM_SIZE.Y, initialViewport.Y)
        )
    ),
}) :: any) :: Frame

do
local _MainCorner: UICorner, MainStroke: UIStroke = addRoundedStyle(Main, 20, 0.2)
MainStroke.Thickness = 1
MainStroke.Color = Color3.fromRGB(205, 205, 208)
MainStroke.Transparency = 0.48
local MainStrokeGradient: UIGradient = Instance.new("UIGradient")
MainStrokeGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(72, 72, 76)),
    ColorSequenceKeypoint.new(0.32, Color3.fromRGB(218, 218, 220)),
    ColorSequenceKeypoint.new(0.61, Color3.fromRGB(112, 112, 116)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 193)),
})
MainStrokeGradient.Rotation = 8
MainStrokeGradient.Parent = MainStroke
local MainScale: UIScale = Instance.new("UIScale")
MainScale.Scale = state.animationsEnabled and 0.96 or 1
MainScale.Parent = Main
if state.animationsEnabled then
    TweenService:Create(
        MainScale,
        TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Scale = 1}
    ):Play()
end
end

local BlossomBackground: ImageLabel = (create("ImageLabel", {
    Parent = Main,
    Name = "AnimatedBlossoms",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageColor3 = Color3.fromRGB(220, 220, 222),
    ImageRectOffset = Vector2.new(0, 0),
    ImageRectSize = Vector2.new(600, 211),
    ImageTransparency = 0.84,
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 1,
}) :: any) :: ImageLabel
create("UICorner", {
    Parent = BlossomBackground,
    CornerRadius = UDim.new(0, 20),
})
state.assetManager.loadAsync("blossomSheet", BlossomBackground)

local _BackgroundShade: Frame = (create("Frame", {
    Parent = Main,
    Name = "BackgroundShade",
    BackgroundColor3 = Color3.fromRGB(5, 5, 6),
    BackgroundTransparency = 0.42,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 2,
}) :: any) :: Frame
create("UICorner", {
    Parent = _BackgroundShade,
    CornerRadius = UDim.new(0, 20),
})

local function centerMain()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local size = Main.AbsoluteSize

    local savedPosition = configData.ui.windowPosition
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

local Header = create("Frame", {
    Parent = Main,
    Name = "Header",
    Active = true,
    BackgroundColor3 = Color3.fromRGB(7, 7, 8),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 84),
    ZIndex = 15,
})
Header.ClipsDescendants = true
create("UICorner", {
    Parent = Header,
    CornerRadius = UDim.new(0, 20),
})

do
local HeaderImage: ImageLabel = (create("ImageLabel", {
    Parent = Header,
    Name = "AnimeEyesHeader",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageColor3 = Color3.fromRGB(225, 225, 228),
    ImageTransparency = 0.08,
    ScaleType = Enum.ScaleType.Crop,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 16,
}) :: any) :: ImageLabel
create("UICorner", {
    Parent = HeaderImage,
    CornerRadius = UDim.new(0, 20),
})
local HeaderEdgeFade: UIGradient = Instance.new("UIGradient")
HeaderEdgeFade.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.82),
    NumberSequenceKeypoint.new(0.12, 0.08),
    NumberSequenceKeypoint.new(0.5, 0),
    NumberSequenceKeypoint.new(0.88, 0.08),
    NumberSequenceKeypoint.new(1, 0.82),
})
HeaderEdgeFade.Parent = HeaderImage
state.assetManager.loadAsync("headerAnime", HeaderImage)

local HeaderShade: Frame = (create("Frame", {
    Parent = Header,
    Name = "HeaderShade",
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.38,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 17,
}) :: any) :: Frame
create("UICorner", {
    Parent = HeaderShade,
    CornerRadius = UDim.new(0, 20),
})
local HeaderShadeGradient: UIGradient = Instance.new("UIGradient")
HeaderShadeGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.05),
    NumberSequenceKeypoint.new(0.28, 0.48),
    NumberSequenceKeypoint.new(0.72, 0.48),
    NumberSequenceKeypoint.new(1, 0.05),
})
HeaderShadeGradient.Parent = HeaderShade

local HeaderBlossoms: ImageLabel = (create("ImageLabel", {
    Parent = Header,
    Name = "HeaderBlossoms",
    AnchorPoint = Vector2.new(1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageColor3 = Color3.fromRGB(235, 235, 237),
    ImageTransparency = state.decorativeTexturesEnabled and 0.58 or 1,
    Position = UDim2.new(1, 10, 0, -12),
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.new(0.48, 0, 1, 20),
    ZIndex = 18,
}) :: any) :: ImageLabel
state.assetManager.loadAsync("blossomBranch", HeaderBlossoms)
state.decorativeObjects = {HeaderBlossoms} :: {GuiObject}

local Title = makeTextLabel(Header, "A random Testing Menu # 0001", 18)
Title.Name = "Title"
Title.Font = Enum.Font.GothamMedium
Title.TextXAlignment = Enum.TextXAlignment.Center
Title.Position = UDim2.fromOffset(20, 0)
Title.Size = UDim2.new(1, -40, 1, 0)
Title.TextColor3 = Color3.fromRGB(242, 242, 244)
Title.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
Title.TextStrokeTransparency = 0.9
Title.ZIndex = 19

local HeaderSeparator: Frame = (create("Frame", {
    Parent = Header,
    Name = "MangaSeparator",
    AnchorPoint = Vector2.new(0, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 1),
    ZIndex = 19,
}) :: any) :: Frame
local SeparatorGradient: UIGradient = Instance.new("UIGradient")
SeparatorGradient.Color = ColorSequence.new(
    Color3.fromRGB(82, 82, 86),
    Color3.fromRGB(232, 232, 234)
)
SeparatorGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.2, 0.25),
    NumberSequenceKeypoint.new(0.8, 0.25),
    NumberSequenceKeypoint.new(1, 1),
})
SeparatorGradient.Parent = HeaderSeparator

state.decorativeTweens = {} :: {Tween}
end

local Tabs = create("Frame", {
    Parent = Main,
    Name = "Tabs",
    BackgroundColor3 = Color3.fromRGB(11, 11, 13),
    BackgroundTransparency = 0.03,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 84),
    Size = UDim2.new(1, 0, 0, 48),
    ZIndex = 10,
})
create("UICorner", {
    Parent = Tabs,
    CornerRadius = UDim.new(0, 12),
})

create("UIListLayout", {
    Parent = Tabs,
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local Content = create("Frame", {
    Parent = Main,
    Name = "Content",
    BackgroundColor3 = state.menuColor,
    BackgroundTransparency = 0.4,
    BorderColor3 = Color3.fromRGB(14, 14, 14),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 132),
    Size = UDim2.new(1, 0, 1, -132),
    ZIndex = 3,
})
Content.ClipsDescendants = true
create("UICorner", {
    Parent = Content,
    CornerRadius = UDim.new(0, 20),
})
local ContentBlossoms: ImageLabel = (create("ImageLabel", {
    Parent = Content,
    Name = "ContentBlossoms",
    AnchorPoint = Vector2.new(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageColor3 = Color3.fromRGB(205, 205, 208),
    ImageTransparency = state.decorativeTexturesEnabled and 0.83 or 1,
    Position = UDim2.fromScale(1, 1),
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.new(0.45, 0, 0.48, 0),
    ZIndex = 4,
}) :: any) :: ImageLabel
state.assetManager.loadAsync("blossomCorner", ContentBlossoms)
table.insert(state.decorativeObjects, ContentBlossoms)

local function setTab(tabName)
    state.activeTab = tabName

    for name, page in pairs(pages) do
        local selectedPage: boolean = name == tabName
        page.Visible = selectedPage
        if selectedPage and page:IsA("CanvasGroup") then
            if state.animationsEnabled then
                page.GroupTransparency = 1
                TweenService:Create(
                    page,
                    TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    {GroupTransparency = 0}
                ):Play()
            else
                page.GroupTransparency = 0
            end
        end
    end

    for name, button in pairs(tabButtons) do
        local selected = name == tabName
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
end

local function createTab(tabName, layoutOrder)
    local button = makeButton(Tabs, tabName, 14)
    button.Name = tabName .. "Tab"
    button.LayoutOrder = layoutOrder
    button.Size = UDim2.new(0.16, -4, 1, 0)
    button.BackgroundColor3 = Theme.Surface
    button.TextSize = state.isMobile and 10 or 14
    button.ZIndex = 11
    button:SetAttribute("SelectedColor", Theme.SurfaceRaised)
    local tabIconName: string = tabName == "Universal" and "home"
        or tabName == "Movement" and "user"
        or tabName == "Config." and "settings"
        or "target"
    local tabIcon: ImageLabel = (create("ImageLabel", {
        Parent = button,
        Name = "TabIcon",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        ImageColor3 = Color3.fromRGB(210, 210, 212),
        ImageTransparency = 0.2,
        Position = UDim2.new(0, 7, 0.5, 0),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.fromOffset(15, 15),
        Visible = not state.isMobile,
        ZIndex = button.ZIndex + 1,
    }) :: any) :: ImageLabel
    state.assetManager.loadAsync(tabIconName, tabIcon)
    local indicator: Frame = (create("Frame", {
        Parent = button,
        Name = "SelectionIndicator",
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = Color3.fromRGB(235, 235, 237),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 1, -2),
        Size = UDim2.new(1, -16, 0, 2),
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
    tabButtons[tabName] = button

    local page = create("CanvasGroup", {
        Parent = Content,
        Name = tabName .. "Page",
        BackgroundColor3 = state.menuColor,
        BackgroundTransparency = 0.46,
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

    button.MouseButton1Click:Connect(function()
        setTab(tabName)
    end)

    return page
end

local UniversalPage = createTab("Universal", 1)
local MovementPage = createTab("Movement", 2)
local MM2Page = createTab("MM2", 3)
createTab("TRS", 4)
local SettingsPage = createTab("Config.", 5)
local tabAreaScale: number = state.isMobile and 0.65 or 0.78

local function configureGameTabs()
    tabButtons.MM2.Visible = GAME_CHECK.MM2Active
    tabButtons.TRS.Visible = GAME_CHECK.TRSActive

    local visibleCount = 3
    if GAME_CHECK.MM2Active then
        visibleCount = visibleCount + 1
    end
    if GAME_CHECK.TRSActive then
        visibleCount = visibleCount + 1
    end
    local tabWidth: number = tabAreaScale / visibleCount
    for _, button in pairs(tabButtons) do
        if button.Visible then
            button.Size = UDim2.new(tabWidth, -4, 1, 0)
        end
    end
end

configureGameTabs()

local SearchBox = makeTextBox(Main, "")
SearchBox.Name = "Search"
SearchBox.PlaceholderText = state.isMobile and "Search..." or "Search modules..."
SearchBox.Position = UDim2.new(tabAreaScale, 8, 0, 92)
SearchBox.Size = UDim2.new(1 - tabAreaScale, -16, 0, 32)
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.ZIndex = 12
create("UIPadding", {
    Parent = SearchBox,
    PaddingLeft = UDim.new(0, 34),
    PaddingRight = UDim.new(0, 8),
})
local SearchIcon: ImageLabel = (create("ImageLabel", {
    Parent = Main,
    Name = "SearchIcon",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "",
    ImageColor3 = Color3.fromRGB(218, 218, 220),
    ImageTransparency = 0.08,
    Position = UDim2.new(tabAreaScale, 16, 0, 98),
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.fromOffset(20, 20),
    ZIndex = 13,
}) :: any) :: ImageLabel
state.assetManager.loadAsync("search", SearchIcon)

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

do
local LoadingPanel: Frame = (create("Frame", {
    Parent = Content,
    Name = "LoadingPanel",
    AnchorPoint = Vector2.new(0.5, 0),
    BackgroundColor3 = Theme.SurfaceRaised,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 0, 0, 14),
    Size = UDim2.fromOffset(250, 44),
    Visible = false,
    ZIndex = 210,
}) :: any) :: Frame
addRoundedStyle(LoadingPanel, 11, 0.32)
local LoadingLabel: TextLabel = (makeTextLabel(
    LoadingPanel,
    "Loading modules 0/0",
    12
) :: any) :: TextLabel
LoadingLabel.Font = Enum.Font.GothamMedium
LoadingLabel.Size = UDim2.fromScale(1, 1)
LoadingLabel.TextColor3 = Theme.Text
LoadingLabel.TextXAlignment = Enum.TextXAlignment.Center
LoadingLabel.ZIndex = 211
state.loadingLabel = LoadingLabel
end

create("UIPadding", {
    Parent = Tabs,
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 7),
    PaddingRight = UDim.new(0, 7),
    PaddingTop = UDim.new(0, 5),
})

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
local allFeatures = {}
local featureConnections = {}
state.tooltipConnections = {} :: {RBXScriptConnection}
state.uiConnections = {} :: {RBXScriptConnection}
state.bindFeatureTooltip = nil :: ((any, string) -> ())?

local function trackUiConnection(
    connection: RBXScriptConnection
): RBXScriptConnection
    table.insert(state.uiConnections, connection)
    return connection
end

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
    Parent = ScreenGui,
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
        BackgroundColor3 = state.headerColor,
        BackgroundTransparency = 0.18,
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
        CornerRadius = UDim.new(1, 0),
    })
    create("UIStroke", {
        Parent = button,
        Color = Color3.fromRGB(225, 235, 255),
        Transparency = 0.28,
        Thickness = 1.5,
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
    state.updateBlossomAnimationState()
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
                    state.updateBlossomAnimationState()
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
            state.updateBlossomAnimationState()
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
    source.Text = "HOLD TO PLACE"
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
        state.updateBlossomAnimationState()
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
local blossomConnection: RBXScriptConnection? = nil
local blossomFrame: number = 0
local blossomElapsed: number = 0
local function updateBlossomAnimationState(): ()
    local shouldAnimate: boolean = state.visible
        and Main.Visible
        and state.animatedBlossomsEnabled
        and not state.lowPerformanceMode
        and BlossomBackground.Parent ~= nil
    BlossomBackground.ImageTransparency = state.animatedBlossomsEnabled and 0.84 or 1
    if not shouldAnimate then
        if blossomConnection then
            blossomConnection:Disconnect()
            blossomConnection = nil
        end
        blossomFrame = 0
        blossomElapsed = 0
        BlossomBackground.ImageRectOffset = Vector2.new(0, 0)
        return
    end
    if blossomConnection then
        return
    end
    blossomConnection = RunService.Heartbeat:Connect(function(deltaTime: number): ()
        blossomElapsed += deltaTime
        local frameDuration: number = state.reducedBlossomSpeed and 0.26 or 0.13
        if blossomElapsed < frameDuration then
            return
        end
        blossomElapsed %= frameDuration
        blossomFrame = (blossomFrame + 1) % 25
        BlossomBackground.ImageRectOffset = Vector2.new(
            (blossomFrame % 5) * 600,
            math.floor(blossomFrame / 5) * 211
        )
    end)
end
state.updateBlossomAnimationState = updateBlossomAnimationState
updateBlossomAnimationState()

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
        or record.container.AbsoluteSize.X < 690

    if singleColumn then
        record.columns[1].Position = UDim2.fromOffset(0, 0)
        record.columns[1].Size = UDim2.new(1, 0, 0, firstHeight)
        record.columns[2].Position = UDim2.fromOffset(0, firstHeight + 10)
        record.columns[2].Size = UDim2.new(1, 0, 0, secondHeight)
        record.root.Size = UDim2.new(
            1,
            -36,
            0,
            firstHeight + secondHeight + 10
        )
    else
        record.columns[1].Position = UDim2.fromOffset(0, 0)
        record.columns[1].Size = UDim2.new(0.5, -5, 0, firstHeight)
        record.columns[2].Position = UDim2.new(0.5, 5, 0, 0)
        record.columns[2].Size = UDim2.new(0.5, -5, 0, secondHeight)
        record.root.Size = UDim2.new(
            1,
            -36,
            0,
            math.max(firstHeight, secondHeight)
        )
    end
end

local function getFeatureCardParent(container: Instance): Instance
    if not container:IsA("ScrollingFrame") then
        return container
    end

    local record: CardGridRecord? = cardGrids[container]
    if not record then
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
            layout.Padding = UDim.new(0, 10)
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
    if state.isMobile then
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
    local targetColor: Color3 = enabled and state.headerColor or Theme.SurfaceRaised
    local knobPosition: UDim2 = enabled
        and UDim2.new(1, -23, 0.5, -9)
        or UDim2.new(0, 5, 0.5, -9)
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
                {Position = knobPosition}
            ):Play()
        end
    else
        button.BackgroundColor3 = targetColor
        if knob then
            knob.Position = knobPosition
        end
    end
end

local function createSwitch(parent: Instance, enabled: boolean): (TextButton, Frame)
    local button: TextButton = (makeButton(parent, "", 1) :: any) :: TextButton
    button.AutoButtonColor = false
    button.Size = UDim2.fromOffset(state.isMobile and 58 or 48, state.isMobile and 34 or 28)
    local switchCorner: UICorner? = button:FindFirstChild("StyleCorner") :: UICorner?
    if switchCorner then
        switchCorner.CornerRadius = UDim.new(1, 0)
    end
    local switchStroke: UIStroke? = button:FindFirstChild("StyleStroke") :: UIStroke?
    if switchStroke then
        switchStroke.Transparency = 0.3
    end

    local knobSize: number = state.isMobile and 22 or 18
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
    setSwitchVisual(button, knob, enabled, false)
    return button, knob
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
            {BackgroundTransparency = feature.enabled and 0.08 or 1}
        ):Play()
    end
    if feature.stroke then
        TweenService:Create(
            feature.stroke,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad),
            {
                Color = feature.enabled and Theme.AccentSoft or Theme.Outline,
                Transparency = feature.enabled and 0.12 or 0.42,
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
    button.BackgroundColor3 = Theme.AccentSoft

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

local function selectFeatureIcon(name: string, description: string): string
    local searchable: string = string.lower(name .. " " .. description)
    if string.find(searchable, "visual", 1, true)
        or string.find(searchable, "esp", 1, true)
        or string.find(searchable, "cham", 1, true) then
        return "visuals"
    end
    if string.find(searchable, "target", 1, true)
        or string.find(searchable, "aim", 1, true)
        or string.find(searchable, "shoot", 1, true)
        or string.find(searchable, "gun", 1, true) then
        return "target"
    end
    if string.find(searchable, "player", 1, true)
        or string.find(searchable, "friend", 1, true)
        or string.find(searchable, "character", 1, true) then
        return "user"
    end
    if string.find(searchable, "protect", 1, true)
        or string.find(searchable, "anti", 1, true)
        or string.find(searchable, "shield", 1, true) then
        return "shield"
    end
    if string.find(searchable, "notify", 1, true)
        or string.find(searchable, "alert", 1, true) then
        return "bell"
    end
    if string.find(searchable, "warning", 1, true)
        or string.find(searchable, "error", 1, true)
        or string.find(searchable, "danger", 1, true) then
        return "warning"
    end
    return "settings"
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
        collapsedHeight = state.isMobile and 86 or 76,
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
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, feature.collapsedHeight),
    }) :: any) :: Frame
    feature.row = row
    create("UICorner", {
        Parent = row,
        CornerRadius = UDim.new(0, 10),
    })
    local cardStroke: UIStroke = (create("UIStroke", {
        Parent = row,
        Color = Theme.Outline,
        Transparency = 0.42,
        Thickness = 1,
    }) :: any) :: UIStroke
    feature.stroke = cardStroke

    local activeStripe: Frame = (create("Frame", {
        Parent = row,
        Name = "MangaActiveStripe",
        BackgroundColor3 = Color3.fromRGB(228, 228, 230),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 10),
        Size = UDim2.new(0, 3, 1, -20),
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
    feature.activeStripe = activeStripe

    local featureIcon: ImageLabel = (create("ImageLabel", {
        Parent = row,
        Name = "FeatureIcon",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        ImageColor3 = Color3.fromRGB(218, 218, 220),
        ImageTransparency = 0.12,
        Position = UDim2.fromOffset(12, 16),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.fromOffset(26, 26),
        ZIndex = 4,
    }) :: any) :: ImageLabel
    state.assetManager.loadAsync(selectFeatureIcon(name, description), featureIcon)

    local title: TextLabel = (makeTextLabel(row, name, 14) :: any) :: TextLabel
    title.Font = Enum.Font.GothamBold
    title.Position = UDim2.fromOffset(48, 9)
    title.Size = UDim2.new(1, -146, 0, 24)
    title.TextColor3 = Theme.Text
    feature.title = title

    local subtitle: TextLabel =
        (makeTextLabel(row, description, 11) :: any) :: TextLabel
    subtitle.Name = "Description"
    subtitle.Position = UDim2.fromOffset(48, 34)
    subtitle.Size = UDim2.new(1, -146, 0, 30)
    subtitle.TextColor3 = Theme.TextMuted
    subtitle.TextTruncate = Enum.TextTruncate.AtEnd
    subtitle.TextWrapped = true

    local toggle: TextButton
    local toggleKnob: Frame? = nil
    if feature.isAction then
        toggle = (makeButton(row, "RUN", 11) :: any) :: TextButton
        toggle.BackgroundColor3 = Theme.AccentSoft
        toggle.Size = UDim2.fromOffset(state.isMobile and 68 or 58, 30)
    else
        local createdToggle: TextButton, createdKnob: Frame =
            createSwitch(row, false)
        toggle = createdToggle
        toggleKnob = createdKnob
    end
    toggle.Name = "Toggle"
    toggle.AnchorPoint = Vector2.new(1, 0)
    toggle.Position = UDim2.new(1, -44, 0, 12)
    toggle.Visible = not feature.isCategory
    feature.toggle = toggle
    feature.toggleKnob = toggleKnob

    local arrow: TextButton =
        (makeButton(row, "", state.isMobile and 17 or 14) :: any) :: TextButton
    arrow.Name = "Expand"
    arrow.AnchorPoint = Vector2.new(1, 0)
    arrow.BackgroundTransparency = 1
    arrow.Position = UDim2.new(1, -10, 0, 12)
    arrow.Size = UDim2.fromOffset(state.isMobile and 38 or 30, 30)
    arrow.TextColor3 = Theme.TextMuted
    arrow.Visible = configuration.noOptions ~= true
    feature.arrow = arrow
    local arrowIcon: ImageLabel = (create("ImageLabel", {
        Parent = arrow,
        Name = "ArrowIcon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "",
        ImageColor3 = Theme.TextMuted,
        Position = UDim2.fromScale(0.5, 0.5),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.fromOffset(16, 16),
        ZIndex = arrow.ZIndex + 1,
    }) :: any) :: ImageLabel
    state.assetManager.loadAsync("arrowDown", arrowIcon)

    trackUiConnection(row.MouseEnter:Connect(function(): ()
        if feature.enabled then
            return
        end
        TweenService:Create(
            row,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Theme.SurfaceHover}
        ):Play()
        TweenService:Create(
            cardStroke,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {Transparency = 0.22}
        ):Play()
    end))
    trackUiConnection(row.MouseLeave:Connect(function(): ()
        TweenService:Create(
            row,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Theme.Surface}
        ):Play()
        TweenService:Create(
            cardStroke,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad),
            {Transparency = feature.enabled and 0.12 or 0.42}
        ):Play()
    end))

    local options: Frame = (create("Frame", {
        Parent = row,
        Name = "Options",
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, feature.collapsedHeight),
        Size = UDim2.new(1, -20, 0, 0),
        Visible = false,
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
    create("UIListLayout", {
        Parent = options,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local function updateExpandedSize(animate: boolean?): ()
        local visibleOptions: number = 0
        for _, optionRow: GuiObject in ipairs(feature.optionRows) do
            if optionRow.Visible then
                visibleOptions += 1
            end
        end
        local optionsHeight: number = visibleOptions * 44 + 14
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
            TweenService:Create(
                arrow,
                TweenInfo.new(0.2, Enum.EasingStyle.Quart),
                {Rotation = feature.expanded and 45 or 0}
            ):Play()
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
            arrow.Rotation = feature.expanded and 45 or 0
            options.Visible = feature.expanded
        end
    end
    feature.updateExpandedSize = updateExpandedSize

    trackUiConnection(arrow.MouseButton1Click:Connect(function(): ()
        feature.expanded = not feature.expanded
        updateExpandedSize(true)
    end))

    trackUiConnection(toggle.MouseButton1Click:Connect(function(): ()
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
    end))

    registry[name] = feature
    table.insert(allFeatures, feature)
    if state.bindFeatureTooltip then
        state.bindFeatureTooltip(feature, description)
    end

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
        BackgroundColor3 = Theme.SurfaceRaised,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        LayoutOrder = feature.optionCount,
        Size = UDim2.new(1, 0, 0, 38),
    }) :: any) :: Frame
    create("UICorner", {
        Parent = option,
        CornerRadius = UDim.new(0, 7),
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
    button.BackgroundColor3 = Theme.AccentSoft
    button.Position = UDim2.new(0.72, 0, 0, 0)
    button.Size = UDim2.new(0.28, 0, 1, 0)
    trackUiConnection(button.MouseButton1Click:Connect(function(): ()
        runActionButton(
            button,
            "RUN",
            callback,
            labelText .. " completado",
            "[Random Testing Menu] " .. labelText
        )
    end))
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

    button.MouseButton1Click:Connect(function()
        if state.isMobile then
            return
        end
        button.Text = "PRESIONA UNA TECLA…"
        button.BackgroundColor3 = state.headerColor
        state.keyCaptureCallback = function(keyCode)
            button.Text = keyCode.Name
            button.BackgroundColor3 = DEFAULT_SURFACE_COLOR
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
            Parent = ScreenGui,
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
    Parent = ScreenGui,
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

local function addFeatureTooltip(feature: any, text: string): ()
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
    speed: number,
    verticalSpeed: number,
    acceleration: number,
    navigation: string,
    mode: string,
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
    speed = 70,
    verticalSpeed = 50,
    acceleration = 8,
    navigation = "Camera",
    mode = "Velocity",
    platformStand = true,
    faceCamera = true,
    upKey = Enum.KeyCode.Space,
    downKey = Enum.KeyCode.LeftControl,
}
local flySmoothedVelocity: Vector3 = Vector3.zero
local flyImpulseClock: number = 0
local flyTeleportClock: number = 0
local originalFlyPlatformStand: boolean? = nil

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
    if flySettings.navigation == "World" then
        horizontal = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            horizontal = horizontal + Vector3.new(0, 0, -1)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            horizontal = horizontal + Vector3.new(0, 0, 1)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            horizontal = horizontal + Vector3.new(1, 0, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            horizontal = horizontal + Vector3.new(-1, 0, 0)
        end
    elseif horizontal.Magnitude <= 0.001 then
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
    if UserInputService:IsKeyDown(flySettings.upKey) then
        vertical = vertical + 1
    end
    if UserInputService:IsKeyDown(flySettings.downKey) then
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
    flyImpulseClock = 0
    flyTeleportClock = 0

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
        local alpha: number = 1 - math.exp(-flySettings.acceleration * deltaTime)
        flySmoothedVelocity = flySmoothedVelocity:Lerp(targetVelocity, alpha)

        velocity.Enabled = flySettings.mode == "Velocity"
        velocity.VectorVelocity = flySmoothedVelocity

        orientation.Enabled = flySettings.faceCamera
        orientation.CFrame = CFrame.lookAt(Vector3.zero, cameraForward)

        if flySettings.mode == "Impulse" then
            local correction: Vector3 =
                flySmoothedVelocity - root.AssemblyLinearVelocity
            root:ApplyImpulse(
                correction * root.AssemblyMass * math.clamp(deltaTime * 10, 0, 1)
            )
        elseif flySettings.mode == "CFrame" then
            root.CFrame = root.CFrame + flySmoothedVelocity * deltaTime
            root.AssemblyLinearVelocity = Vector3.zero
        elseif flySettings.mode == "TP" then
            flyTeleportClock = flyTeleportClock + deltaTime
            if flyTeleportClock >= 0.12 then
                root.CFrame = root.CFrame + flySmoothedVelocity * flyTeleportClock
                root.AssemblyLinearVelocity = Vector3.zero
                flyTeleportClock = 0
            end
        elseif flySettings.mode == "Pulse" then
            flyImpulseClock = flyImpulseClock + deltaTime
            if flyImpulseClock >= 0.18 then
                local correction: Vector3 =
                    flySmoothedVelocity - root.AssemblyLinearVelocity
                root:ApplyImpulse(correction * root.AssemblyMass)
                flyImpulseClock = 0
            end
        end
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
    mode = "Velocity",
    speed = 50,
    verticalSpeed = 50,
    platformStand = false,
    customProperties = true,
    motorTorque = 50000,
}
local physicsSpeedTeleportClock: number = 0
local physicsSpeedPulseClock: number = 0
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
    physicsSpeedPulseClock = 0

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

            local currentVelocity: Vector3 = assembly.AssemblyLinearVelocity
            local vertical: number = math.clamp(
                currentVelocity.Y,
                -physicsSpeedSettings.verticalSpeed,
                physicsSpeedSettings.verticalSpeed
            )
            local targetVelocity: Vector3 = direction * physicsSpeedSettings.speed
                + Vector3.new(0, vertical, 0)

            if physicsSpeedSettings.mode == "Velocity" then
                assembly.AssemblyLinearVelocity = targetVelocity
            elseif physicsSpeedSettings.mode == "Impulse" then
                local correction: Vector3 = targetVelocity - currentVelocity
                assembly:ApplyImpulse(
                    correction
                        * assembly.AssemblyMass
                        * math.clamp(deltaTime * 9, 0, 1)
                )
            elseif physicsSpeedSettings.mode == "CFrame" then
                assembly.CFrame = assembly.CFrame
                    + direction * physicsSpeedSettings.speed * deltaTime
            elseif physicsSpeedSettings.mode == "TP" then
                physicsSpeedTeleportClock = physicsSpeedTeleportClock + deltaTime
                if physicsSpeedTeleportClock >= 0.14 then
                    assembly.CFrame = assembly.CFrame
                        + direction
                            * physicsSpeedSettings.speed
                            * physicsSpeedTeleportClock
                    physicsSpeedTeleportClock = 0
                end
            elseif physicsSpeedSettings.mode == "Pulse" then
                physicsSpeedPulseClock = physicsSpeedPulseClock + deltaTime
                if physicsSpeedPulseClock >= 0.2 then
                    local correction: Vector3 = targetVelocity - currentVelocity
                    assembly:ApplyImpulse(correction * assembly.AssemblyMass)
                    physicsSpeedPulseClock = 0
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

do
local FlyFeature = createUniversalFeature(
    "Fly",
    "Multi-mode flight with independent horizontal and vertical control",
    1,
    toggleFly
)
addCycleOption(
    FlyFeature,
    "Mode",
    {"Velocity", "Impulse", "CFrame", "TP", "Pulse"},
    1,
    function(value)
        flySettings.mode = value
    end
)
addNumberOption(FlyFeature, "Speed", flySettings.speed, 10, 500, function(value)
    flySettings.speed = value
end)
addNumberOption(
    FlyFeature,
    "Vertical speed",
    flySettings.verticalSpeed,
    10,
    300,
    function(value)
        flySettings.verticalSpeed = value
    end
)
addNumberOption(
    FlyFeature,
    "Acceleration",
    flySettings.acceleration,
    1,
    30,
    function(value)
        flySettings.acceleration = value
    end
)
addCycleOption(FlyFeature, "Direction", {"Camera", "World"}, 1, function(value)
    flySettings.navigation = value
end)
addToggleOption(FlyFeature, "PlatformStand", flySettings.platformStand, function(value)
    flySettings.platformStand = value
end)
addToggleOption(FlyFeature, "Face camera", flySettings.faceCamera, function(value)
    flySettings.faceCamera = value
end)
addKeyOption(FlyFeature, "Up key", flySettings.upKey, function(value)
    flySettings.upKey = value
end)
addKeyOption(FlyFeature, "Down key", flySettings.downKey, function(value)
    flySettings.downKey = value
end)
addFeatureTooltip(
    FlyFeature,
    "Velocity holds a smooth target speed. Impulse corrects speed with physics forces. "
        .. "CFrame moves every frame. TP moves in short steps. Pulse applies controlled bursts."
)
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
local PhysicsSpeedFeature = createUniversalFeature(
    "Speed",
    "Control local assembly and occupied vehicle physics",
    9,
    togglePhysicsSpeed
)
addCycleOption(
    PhysicsSpeedFeature,
    "Mode",
    {"Velocity", "Impulse", "CFrame", "TP", "Pulse"},
    1,
    function(value)
        physicsSpeedSettings.mode = value
    end
)
addNumberOption(
    PhysicsSpeedFeature,
    "Speed",
    physicsSpeedSettings.speed,
    5,
    500,
    function(value)
        physicsSpeedSettings.speed = value
    end
)
addNumberOption(
    PhysicsSpeedFeature,
    "Vertical speed",
    physicsSpeedSettings.verticalSpeed,
    0,
    300,
    function(value)
        physicsSpeedSettings.verticalSpeed = value
    end
)
addToggleOption(
    PhysicsSpeedFeature,
    "PlatformStand",
    physicsSpeedSettings.platformStand,
    function(value)
        physicsSpeedSettings.platformStand = value
    end
)
addToggleOption(
    PhysicsSpeedFeature,
    "Custom properties",
    physicsSpeedSettings.customProperties,
    function(value)
        physicsSpeedSettings.customProperties = value
        if not value then
            restorePhysicsMotors()
        end
    end
)
addNumberOption(
    PhysicsSpeedFeature,
    "Motor torque",
    physicsSpeedSettings.motorTorque,
    1000,
    250000,
    function(value)
        physicsSpeedSettings.motorTorque = value
    end
)
addFeatureTooltip(
    PhysicsSpeedFeature,
    "Velocity sets assembly speed. Impulse accelerates with forces. CFrame and TP move "
        .. "directly. Pulse boosts in bursts. Custom properties tunes VehicleSeat and hinge motors."
)
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
    local query: string = string.lower(SearchBox.Text)
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
                and Theme.AccentCyan
                or Theme.Text
        end
    end

    for sectionName: string, label: TextLabel in pairs(noResultsLabels) do
        label.Visible = query ~= ""
            and (sectionTotals[sectionName] or 0) > 0
            and (sectionMatches[sectionName] or 0) == 0
    end
end
state.refreshSearch = refreshSearch
trackUiConnection(SearchBox:GetPropertyChangedSignal("Text"):Connect(refreshSearch))

local function buildSettings()
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
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, height or 62),
    })

    local title = makeTextLabel(row, titleText, 14)
    title.Font = Enum.Font.GothamBold
    title.Position = UDim2.fromOffset(14, 7)
    title.Size = UDim2.new(0.46, -14, 0, 24)

    local description = makeTextLabel(row, descriptionText, 11)
    description.TextColor3 = Color3.fromRGB(160, 160, 160)
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
        Color = Theme.Outline,
        Transparency = 0.42,
        Thickness = 1,
    })
    return (row :: any) :: Frame, (control :: any) :: Frame
end

local textRow, textControl = createSettingRow(
    "Text size",
    "Use larger text throughout the menu"
)
textRow.LayoutOrder = 1

local TextSizeButton = makeButton(
    textControl,
    state.largeText and "LARGE" or "NORMAL",
    13
)
TextSizeButton.Size = UDim2.fromScale(1, 1)
TextSizeButton:SetAttribute("Selected", state.largeText)
TextSizeButton.BackgroundColor3 = state.largeText
    and state.headerColor
    or DEFAULT_SURFACE_COLOR

local blurRow, blurControl = createSettingRow(
    "Blur mode",
    "Blur the game while the menu is visible"
)
blurRow.LayoutOrder = 2

local BlurButton: TextButton, BlurKnob: Frame =
    createSwitch(blurControl, state.blurEnabled)
BlurButton.AnchorPoint = Vector2.new(1, 0.5)
BlurButton.Position = UDim2.new(1, 0, 0.5, 0)

local animationRow, animationControl = createSettingRow(
    "Interface animations",
    "Disable decorative motion while keeping control feedback"
)
animationRow.LayoutOrder = 3
local AnimationButton: TextButton, AnimationKnob: Frame =
    createSwitch(animationControl, state.animationPreference)
AnimationButton.AnchorPoint = Vector2.new(1, 0.5)
AnimationButton.Position = UDim2.new(1, 0, 0.5, 0)

local blossomRow: Frame, blossomControl: Frame = createSettingRow(
    "Animated blossoms",
    "Play the manga blossom background while the menu is visible"
)
blossomRow.LayoutOrder = 4
local BlossomButton: TextButton, BlossomKnob: Frame =
    createSwitch(blossomControl, state.animatedBlossomsEnabled)
BlossomButton.AnchorPoint = Vector2.new(1, 0.5)
BlossomButton.Position = UDim2.new(1, 0, 0.5, 0)

local blossomSpeedRow: Frame, blossomSpeedControl: Frame = createSettingRow(
    "Reduced blossom speed",
    "Use approximately four frames per second"
)
blossomSpeedRow.LayoutOrder = 5
local BlossomSpeedButton: TextButton, BlossomSpeedKnob: Frame =
    createSwitch(blossomSpeedControl, state.reducedBlossomSpeed)
BlossomSpeedButton.AnchorPoint = Vector2.new(1, 0.5)
BlossomSpeedButton.Position = UDim2.new(1, 0, 0.5, 0)

local texturesRow: Frame, texturesControl: Frame = createSettingRow(
    "Decorative textures",
    "Show blossom ornaments and light grunge details"
)
texturesRow.LayoutOrder = 6
local TexturesButton: TextButton, TexturesKnob: Frame =
    createSwitch(texturesControl, state.decorativeTexturesEnabled)
TexturesButton.AnchorPoint = Vector2.new(1, 0.5)
TexturesButton.Position = UDim2.new(1, 0, 0.5, 0)

local lowPerformanceRow: Frame, lowPerformanceControl: Frame = createSettingRow(
    "Low performance mode",
    "Use one static frame and disable complex transitions"
)
lowPerformanceRow.LayoutOrder = 7
local LowPerformanceButton: TextButton, LowPerformanceKnob: Frame =
    createSwitch(lowPerformanceControl, state.lowPerformanceMode)
LowPerformanceButton.AnchorPoint = Vector2.new(1, 0.5)
LowPerformanceButton.Position = UDim2.new(1, 0, 0.5, 0)

local keyRow, keyControl = createSettingRow(
    "Menu key",
    "Choose the key used to show or hide"
)
keyRow.LayoutOrder = 8

local KeybindButton = makeButton(keyControl, state.toggleKey.Name, 13)
KeybindButton.Size = UDim2.fromScale(1, 1)
state.keybindButton = KeybindButton

local headerColorRow: Frame, headerColorControl: Frame = createSettingRow(
    "Accent color",
    "ColorPicker for selections, tabs and active switches"
)
headerColorRow.LayoutOrder = 9
local HeaderColorButton: TextButton =
    (makeButton(headerColorControl, "PICK COLOR", 12) :: any) :: TextButton
HeaderColorButton.BackgroundColor3 = state.headerColor
HeaderColorButton.Size = UDim2.fromScale(1, 1)

local menuColorRow: Frame, menuColorControl: Frame = createSettingRow(
    "Panel color",
    "ColorPicker for the main dark surface"
)
menuColorRow.LayoutOrder = 10
local MenuColorButton: TextButton =
    (makeButton(menuColorControl, "PICK COLOR", 12) :: any) :: TextButton
MenuColorButton.BackgroundColor3 = state.menuColor
MenuColorButton.Size = UDim2.fromScale(1, 1)
local resetRow, resetControl = createSettingRow(
    "Reset appearance",
    "Restore the default grey and dark blue colors"
)
resetRow.LayoutOrder = 11

local ResetButton = makeButton(resetControl, "RESET", 13)
ResetButton.Size = UDim2.fromScale(1, 1)

local gameRow, gameControl = createSettingRow(
    "Game check",
    "Only the matching game-specific module is loaded"
)
gameRow.LayoutOrder = 12
local gameStatus = makeTextLabel(
    gameControl,
    GAME_CHECK.MM2Active and "MM2 · 142823291"
        or GAME_CHECK.TRSActive and "TRS · 14315258385"
        or "Universal only",
    12
)
gameStatus.TextXAlignment = Enum.TextXAlignment.Center
gameStatus.Size = UDim2.fromScale(1, 1)

local deviceRow, deviceControl = createSettingRow(
    "Device profile",
    "Automatically selected from touch and keyboard capabilities"
)
deviceRow.LayoutOrder = 13
local deviceStatus = makeTextLabel(
    deviceControl,
    state.isMobile and "MOBILE · TOUCH" or "DESKTOP · KEYBOARD",
    12
)
deviceStatus.TextXAlignment = Enum.TextXAlignment.Center
deviceStatus.Size = UDim2.fromScale(1, 1)

local mobileIconRow, mobileIconControl = createSettingRow(
    "Mobile menu icon",
    "Dog shortcut stays available so the menu cannot become unreachable"
)
mobileIconRow.LayoutOrder = 14
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
    "Circle size for placed Shoot and Grab Gun actions"
)
mobileSizeRow.LayoutOrder = 15
mobileSizeRow.Visible = UserInputService.TouchEnabled
local MobileSizeButton = makeButton(
    mobileSizeControl,
    tostring(state.mobileButtonSize) .. " PX",
    13
)
MobileSizeButton.Size = UDim2.fromScale(1, 1)

local mobileResetRow, mobileResetControl = createSettingRow(
    "Mobile action buttons",
    "Hold an action option to place; hold its circle to remove"
)
mobileResetRow.LayoutOrder = 16
mobileResetRow.Visible = UserInputService.TouchEnabled
local MobileResetButton = makeButton(
    mobileResetControl,
    "RESET PLACED",
    13
)
MobileResetButton.Size = UDim2.fromScale(1, 1)

local helpText = makeTextLabel(
    getFeatureCardParent(SettingsScroll),
    "Build 0001-S15 | Active game module: "
        .. (GAME_CHECK.MM2Active and "MM2"
            or GAME_CHECK.TRSActive and "TRS"
            or "Universal")
        .. (state.isMobile
            and " | Hold Manual Shoot or Get Gun to place a touch action."
            or " | Drag the header to move and any border to resize."),
    11
)
helpText.LayoutOrder = 17
helpText.TextColor3 = Color3.fromRGB(145, 145, 145)
helpText.TextXAlignment = Enum.TextXAlignment.Center
helpText.Size = UDim2.new(1, -4, 0, 30)

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
    state.updateBlossomAnimationState()
end
state.setMenuVisible = setMenuVisible

local function updateTextSizes()
    for _, item in ipairs(registeredText) do
        if item.object and item.object.Parent then
            item.object.TextSize = state.largeText
                and item.normalSize + 4
                or item.normalSize
        end
    end
end

TextSizeButton.MouseButton1Click:Connect(function()
    state.largeText = not state.largeText
    TextSizeButton.Text = state.largeText and "LARGE" or "NORMAL"
    TextSizeButton:SetAttribute("Selected", state.largeText)
    TextSizeButton.BackgroundColor3 = state.largeText
        and state.headerColor
        or DEFAULT_SURFACE_COLOR
    updateTextSizes()
    configData.ui.largeText = state.largeText
    queueConfigSave()
end)

trackUiConnection(BlurButton.MouseButton1Click:Connect(function(): ()
    state.blurEnabled = not state.blurEnabled
    setSwitchVisual(BlurButton, BlurKnob, state.blurEnabled, true)
    setBlurVisible(true)
    configData.ui.blurEnabled = state.blurEnabled
    queueConfigSave()
    notify(state.blurEnabled and "Desenfoque activado" or "Desenfoque desactivado")
end))

trackUiConnection(AnimationButton.MouseButton1Click:Connect(function(): ()
    state.animationPreference = not state.animationPreference
    state.animationsEnabled = state.animationPreference
        and not state.lowPerformanceMode
    setSwitchVisual(
        AnimationButton,
        AnimationKnob,
        state.animationPreference,
        true
    )
    for _, tween: Tween in ipairs(state.decorativeTweens or {}) do
        if state.animationsEnabled then
            tween:Play()
        else
            tween:Pause()
        end
    end
    configData.ui.animationsEnabled = state.animationPreference
    queueConfigSave()
    notify(
        state.animationPreference
            and "Animaciones decorativas activadas"
            or "Animaciones decorativas desactivadas"
    )
end))

local function updateDecorativeTextures(): ()
    for _, object: GuiObject in ipairs(state.decorativeObjects or {}) do
        if not object:IsA("ImageLabel") then
            continue
        end
        if object.Name == "HeaderBlossoms" then
            object.ImageTransparency = state.decorativeTexturesEnabled
                and (state.lowPerformanceMode and 0.72 or 0.58)
                or 1
        else
            object.ImageTransparency = state.decorativeTexturesEnabled
                and not state.lowPerformanceMode
                and 0.83
                or 1
        end
    end
end

trackUiConnection(BlossomButton.MouseButton1Click:Connect(function(): ()
    state.animatedBlossomsEnabled = not state.animatedBlossomsEnabled
    setSwitchVisual(
        BlossomButton,
        BlossomKnob,
        state.animatedBlossomsEnabled,
        true
    )
    configData.ui.animatedBlossomsEnabled = state.animatedBlossomsEnabled
    state.updateBlossomAnimationState()
    queueConfigSave()
end))

trackUiConnection(BlossomSpeedButton.MouseButton1Click:Connect(function(): ()
    state.reducedBlossomSpeed = not state.reducedBlossomSpeed
    setSwitchVisual(
        BlossomSpeedButton,
        BlossomSpeedKnob,
        state.reducedBlossomSpeed,
        true
    )
    configData.ui.reducedBlossomSpeed = state.reducedBlossomSpeed
    queueConfigSave()
end))

trackUiConnection(TexturesButton.MouseButton1Click:Connect(function(): ()
    state.decorativeTexturesEnabled = not state.decorativeTexturesEnabled
    setSwitchVisual(
        TexturesButton,
        TexturesKnob,
        state.decorativeTexturesEnabled,
        true
    )
    configData.ui.decorativeTexturesEnabled = state.decorativeTexturesEnabled
    updateDecorativeTextures()
    queueConfigSave()
end))

trackUiConnection(LowPerformanceButton.MouseButton1Click:Connect(function(): ()
    state.lowPerformanceMode = not state.lowPerformanceMode
    state.animationsEnabled = state.animationPreference
        and not state.lowPerformanceMode
    setSwitchVisual(
        LowPerformanceButton,
        LowPerformanceKnob,
        state.lowPerformanceMode,
        true
    )
    for _, tween: Tween in ipairs(state.decorativeTweens or {}) do
        if state.animationsEnabled then
            tween:Play()
        else
            tween:Pause()
        end
    end
    configData.ui.lowPerformanceMode = state.lowPerformanceMode
    updateDecorativeTextures()
    state.updateBlossomAnimationState()
    queueConfigSave()
end))

updateDecorativeTextures()

MobileIconButton.MouseButton1Click:Connect(function(): ()
    if not UserInputService.TouchEnabled then
        return
    end
    notify("The mobile menu icon remains enabled so the menu is always reachable.")
end)

MobileSizeButton.MouseButton1Click:Connect(function(): ()
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
end)

MobileResetButton.MouseButton1Click:Connect(function(): ()
    if not UserInputService.TouchEnabled then
        return
    end
    state.mobileUi.resetActions()
end)

KeybindButton.MouseButton1Click:Connect(function()
    state.waitingForKey = true
    KeybindButton.Text = "PRESIONA UNA TECLA…"
    KeybindButton.BackgroundColor3 = state.headerColor
end)

local function applyHeaderColor(color: Color3): ()
    state.headerColor = color
    Theme.Accent = color
    configData.ui.headerColor = colorToConfig(color)
    queueConfigSave()

    for tabName, button in pairs(tabButtons) do
        if tabName == state.activeTab then
            button.BackgroundColor3 = Theme.SurfaceRaised
        end
    end

    if state.blurEnabled then
        setSwitchVisual(BlurButton, BlurKnob, true, false)
    end

    if state.largeText then
        TextSizeButton.BackgroundColor3 = color
    end

    if state.waitingForKey then
        KeybindButton.BackgroundColor3 = color
    end

    for _, record: MobileActionRecord in pairs(state.mobileUi.actions) do
        record.button.BackgroundColor3 = color
    end
    if UserInputService.TouchEnabled and state.mobileMenuButtonVisible then
        MobileIconButton.BackgroundColor3 = color
    end

    for _, object: Instance in ipairs(ScreenGui:GetDescendants()) do
        if object:IsA("TextButton") and object:GetAttribute("Selected") == true then
            object.BackgroundColor3 = color
        elseif object:IsA("Frame") and object.Name == "Fill"
            and object.Parent and object.Parent.Name == "Track" then
            object.BackgroundColor3 = color
        end
    end
end

local function applyMenuColor(color: Color3): ()
    state.menuColor = color
    configData.ui.menuColor = colorToConfig(color)
    queueConfigSave()
    Main.BackgroundColor3 = color
    Content.BackgroundColor3 = color

    for _, page in pairs(pages) do
        page.BackgroundColor3 = color
    end
end

trackUiConnection(HeaderColorButton.MouseButton1Click:Connect(function(): ()
    colorPicker.open(state.headerColor, function(color: Color3): ()
        applyHeaderColor(color)
        HeaderColorButton.BackgroundColor3 = color
        notify("Color de acento actualizado")
    end)
end))

trackUiConnection(MenuColorButton.MouseButton1Click:Connect(function(): ()
    colorPicker.open(state.menuColor, function(color: Color3): ()
        applyMenuColor(color)
        MenuColorButton.BackgroundColor3 = color
        notify("Color del panel actualizado")
    end)
end))

trackUiConnection(ResetButton.MouseButton1Click:Connect(function(): ()
    applyHeaderColor(DEFAULT_HEADER_COLOR)
    applyMenuColor(DEFAULT_MENU_COLOR)
    HeaderColorButton.BackgroundColor3 = DEFAULT_HEADER_COLOR
    MenuColorButton.BackgroundColor3 = DEFAULT_MENU_COLOR
    notify("Apariencia restaurada")
end))
end

SectionManager.register("Config.", buildSettings)

do
local function initializeWindowInput(): ()
local dragging = false
local dragInput
local dragStart
local dragStartPosition

local function getPointerPosition(input)
    if input and input.UserInputType == Enum.UserInputType.Touch then
        return input.Position
    end
    return UserInputService:GetMouseLocation()
end

local function saveWindowGeometry()
    configData.ui.windowPosition = {
        Main.Position.X.Offset,
        Main.Position.Y.Offset,
    }
    configData.ui.windowSize = {
        Main.Size.X.Offset,
        Main.Size.Y.Offset,
    }
    queueConfigSave()
end

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = getPointerPosition(input)
        dragStartPosition = Vector2.new(
            Main.Position.X.Offset,
            Main.Position.Y.Offset
        )

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                saveWindowGeometry()
            end
        end)
    end
end)

Header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

local resizeState = nil

local function viewportSize()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function startResize(mode, input)
    resizeState = {
        mode = mode,
        startPointer = getPointerPosition(input),
        startPosition = Vector2.new(
            Main.Position.X.Offset,
            Main.Position.Y.Offset
        ),
        startSize = Main.AbsoluteSize,
    }

    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            resizeState = nil
            saveWindowGeometry()
        end
    end)
end

local function addResizeHandle(name, mode, position, size)
    local handle = create("Frame", {
        Parent = Main,
        Name = name,
        Active = true,
        BackgroundColor3 = Color3.fromRGB(115, 115, 115),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
        ZIndex = 20,
    })

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            startResize(mode, input)
        end
    end)

    return handle
end

local ResizeTopHandle = addResizeHandle(
    "ResizeTop",
    "top",
    UDim2.fromOffset(9, 0),
    UDim2.new(1, -18, 0, 5)
)
ResizeTopHandle.ZIndex = 14
addResizeHandle(
    "ResizeBottom",
    "bottom",
    UDim2.new(0, 9, 1, -5),
    UDim2.new(1, -18, 0, 5)
)
addResizeHandle(
    "ResizeLeft",
    "left",
    UDim2.fromOffset(0, 9),
    UDim2.new(0, 5, 1, -18)
)
addResizeHandle(
    "ResizeRight",
    "right",
    UDim2.new(1, -5, 0, 9),
    UDim2.new(0, 5, 1, -18)
)
addResizeHandle(
    "ResizeTopLeft",
    "top-left",
    UDim2.fromOffset(0, 0),
    UDim2.fromOffset(10, 10)
)
addResizeHandle(
    "ResizeTopRight",
    "top-right",
    UDim2.new(1, -10, 0, 0),
    UDim2.fromOffset(10, 10)
)
addResizeHandle(
    "ResizeBottomLeft",
    "bottom-left",
    UDim2.new(0, 0, 1, -10),
    UDim2.fromOffset(10, 10)
)
addResizeHandle(
    "ResizeBottomRight",
    "bottom-right",
    UDim2.new(1, -10, 1, -10),
    UDim2.fromOffset(10, 10)
)

local function updateResize(pointerPosition)
    if not resizeState then
        return
    end

    local mode = resizeState.mode
    local delta = pointerPosition - resizeState.startPointer
    local startSize = resizeState.startSize
    local startPosition = resizeState.startPosition
    local screenSize = viewportSize()

    local newWidth = startSize.X
    local newHeight = startSize.Y
    local newX = startPosition.X
    local newY = startPosition.Y

    if string.find(mode, "right", 1, true) then
        newWidth = math.clamp(
            startSize.X + delta.X,
            activeMinimumSize.X,
            math.min(MAXIMUM_SIZE.X, screenSize.X)
        )
    elseif string.find(mode, "left", 1, true) then
        newWidth = math.clamp(
            startSize.X - delta.X,
            activeMinimumSize.X,
            math.min(MAXIMUM_SIZE.X, screenSize.X)
        )
        newX = startPosition.X + (startSize.X - newWidth)
    end

    if string.find(mode, "bottom", 1, true) then
        newHeight = math.clamp(
            startSize.Y + delta.Y,
            activeMinimumSize.Y,
            math.min(MAXIMUM_SIZE.Y, screenSize.Y)
        )
    elseif string.find(mode, "top", 1, true) then
        newHeight = math.clamp(
            startSize.Y - delta.Y,
            activeMinimumSize.Y,
            math.min(MAXIMUM_SIZE.Y, screenSize.Y)
        )
        newY = startPosition.Y + (startSize.Y - newHeight)
    end

    newX = math.clamp(newX, 0, math.max(0, screenSize.X - newWidth))
    newY = math.clamp(newY, 0, math.max(0, screenSize.Y - newHeight))

    Main.Position = UDim2.fromOffset(newX, newY)
    Main.Size = UDim2.fromOffset(newWidth, newHeight)
end

state.globalInputChangedConnection = UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = getPointerPosition(input) - dragStart
        local screenSize = viewportSize()
        local mainSize = Main.AbsoluteSize

        Main.Position = UDim2.fromOffset(
            math.clamp(
                dragStartPosition.X + delta.X,
                0,
                math.max(0, screenSize.X - mainSize.X)
            ),
            math.clamp(
                dragStartPosition.Y + delta.Y,
                0,
                math.max(0, screenSize.Y - mainSize.Y)
            )
        )
    end

    if resizeState
        and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
        updateResize(getPointerPosition(input))
    end
end)

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
                state.keybindButton.BackgroundColor3 = DEFAULT_SURFACE_COLOR
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
            state.updateBlossomAnimationState()
        end
    end
end)
end
initializeWindowInput()
end

ScreenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then
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
        if blossomConnection then
            blossomConnection:Disconnect()
            blossomConnection = nil
        end
        if state.globalInputChangedConnection then
            state.globalInputChangedConnection:Disconnect()
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
        saveConfigNow()

        if Blur.Parent then
            Blur:Destroy()
        end
    end
end)

SectionManager.initializeAllAsync()
setTab("Universal")
if state.setBlurVisible then
    state.setBlurVisible(false)
end
task.defer(saveConfigNow)

print(
    "A random Testing Menu # 0001 | Build 0001-S16 | Toggle key: "
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
    warn("[RTM:Bootstrap] Inicialización detenida:\n" .. tostring(bootstrapError))
end
