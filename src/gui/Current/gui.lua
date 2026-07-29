--!strict
--[[
    A random Testing Menu # 0001
    Standalone, client-sided Roblox GUI.

    Default controls:
      - RightShift: show/hide the menu
      - Drag the blue title bar to move the menu
      - Drag any border or corner to resize the menu
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "RandomTestingMenu0001"
local BLUR_NAME = "RandomTestingMenu0001Blur"
local CONFIG_FOLDER = "RandomTestingMenu0001"
local CONFIG_PROFILE_FOLDER = CONFIG_FOLDER .. "/Profiles"
local CONFIG_FILE = CONFIG_PROFILE_FOLDER
    .. "/Game_"
    .. tostring(game.GameId > 0 and game.GameId or game.PlaceId)
    .. ".Config"

local GAME_CHECK = {
    MM2 = 142823291,
    TRS = 14315258385,
}

function GAME_CHECK.matches(identifier)
    return game.GameId == identifier or game.PlaceId == identifier
end

GAME_CHECK.MM2Active = GAME_CHECK.matches(GAME_CHECK.MM2)
GAME_CHECK.TRSActive = GAME_CHECK.matches(GAME_CHECK.TRS)

local DEFAULT_HEADER_COLOR = Color3.fromRGB(37, 76, 115)
local DEFAULT_MENU_COLOR = Color3.fromRGB(36, 36, 36)
local DEFAULT_SURFACE_COLOR = Color3.fromRGB(29, 29, 29)
local DEFAULT_BORDER_COLOR = Color3.fromRGB(76, 76, 76)

local MINIMUM_SIZE = Vector2.new(560, 350)
local MAXIMUM_SIZE = Vector2.new(1100, 760)

local configData = {
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
ScreenGui:SetAttribute("BuildId", "0001-S7")

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

local state = {
    visible = true,
    blurEnabled = configData.ui.blurEnabled ~= false,
    largeText = configData.ui.largeText == true,
    toggleKey = savedToggleKey,
    waitingForKey = false,
    keyCaptureCallback = nil,
    activeTab = "Universal",
    headerColor = colorFromConfig(configData.ui.headerColor, DEFAULT_HEADER_COLOR),
    menuColor = colorFromConfig(configData.ui.menuColor, DEFAULT_MENU_COLOR),
}

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

function SectionManager.initialize(sectionName)
    local entry = SectionManager.entries[sectionName]
    if not entry or entry.loaded or entry.loading then
        return
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
        return
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
        BorderColor3 = DEFAULT_BORDER_COLOR,
        BorderSizePixel = 1,
        Font = Enum.Font.Gotham,
        Text = text,
        TextColor3 = Color3.fromRGB(240, 240, 240),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    }), normalSize or 14)

    button.MouseEnter:Connect(function()
        if button:GetAttribute("NoHover") then
            return
        end
        TweenService:Create(
            button,
            TweenInfo.new(0.1, Enum.EasingStyle.Linear),
            {BackgroundColor3 = Color3.fromRGB(43, 43, 43)}
        ):Play()
    end)

    button.MouseLeave:Connect(function()
        if button:GetAttribute("NoHover") then
            return
        end
        local targetColor = button:GetAttribute("Selected")
            and state.headerColor
            or DEFAULT_SURFACE_COLOR

        TweenService:Create(
            button,
            TweenInfo.new(0.1, Enum.EasingStyle.Linear),
            {BackgroundColor3 = targetColor}
        ):Play()
    end)

    return button
end

local function makeTextBox(parent, defaultText)
    return registerText(create("TextBox", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(18, 18, 18),
        BorderColor3 = DEFAULT_BORDER_COLOR,
        BorderSizePixel = 1,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderColor3 = Color3.fromRGB(130, 130, 130),
        Text = tostring(defaultText),
        TextColor3 = Color3.fromRGB(235, 235, 235),
        TextXAlignment = Enum.TextXAlignment.Center,
    }), 13)
end

local function notify(message)
    print("[Random Testing Menu] " .. tostring(message))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Random Testing Menu",
            Text = tostring(message),
            Duration = 4,
        })
    end)
end

local Main = create("Frame", {
    Parent = ScreenGui,
    Name = "Main",
    Active = true,
    BackgroundColor3 = state.menuColor,
    BorderColor3 = Color3.fromRGB(12, 12, 12),
    BorderSizePixel = 2,
    ClipsDescendants = true,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(
        math.clamp(
            tonumber(configData.ui.windowSize and configData.ui.windowSize[1]) or 760,
            MINIMUM_SIZE.X,
            MAXIMUM_SIZE.X
        ),
        math.clamp(
            tonumber(configData.ui.windowSize and configData.ui.windowSize[2]) or 470,
            MINIMUM_SIZE.Y,
            MAXIMUM_SIZE.Y
        )
    ),
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
    BackgroundColor3 = state.headerColor,
    BorderColor3 = Color3.fromRGB(12, 12, 12),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 52),
    ZIndex = 15,
})

local Title = makeTextLabel(Header, "A random Testing Menu # 0001", 18)
Title.Name = "Title"
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Center
Title.Position = UDim2.fromOffset(10, 0)
Title.Size = UDim2.new(1, -20, 1, 0)
Title.ZIndex = 16

local Tabs = create("Frame", {
    Parent = Main,
    Name = "Tabs",
    BackgroundColor3 = Color3.fromRGB(23, 23, 23),
    BorderColor3 = Color3.fromRGB(12, 12, 12),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 52),
    Size = UDim2.new(1, 0, 0, 44),
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
    BorderColor3 = Color3.fromRGB(14, 14, 14),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 96),
    Size = UDim2.new(1, 0, 1, -96),
})

local function setTab(tabName)
    state.activeTab = tabName

    for name, page in pairs(pages) do
        page.Visible = name == tabName
    end

    for name, button in pairs(tabButtons) do
        local selected = name == tabName
        button:SetAttribute("Selected", selected)
        button.BackgroundColor3 = selected and state.headerColor or DEFAULT_SURFACE_COLOR
        button.TextColor3 = selected
            and Color3.fromRGB(255, 255, 255)
            or Color3.fromRGB(205, 205, 205)
    end

    SectionManager.initialize(tabName)
end

local function createTab(tabName, layoutOrder)
    local button = makeButton(Tabs, tabName, 14)
    button.Name = tabName .. "Tab"
    button.LayoutOrder = layoutOrder
    button.Size = UDim2.new(0.16, 0, 1, 0)
    button.BorderColor3 = Color3.fromRGB(10, 10, 10)
    button.BorderSizePixel = 1
    tabButtons[tabName] = button

    local page = create("Frame", {
        Parent = Content,
        Name = tabName .. "Page",
        BackgroundColor3 = state.menuColor,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
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
    local tabWidth = 0.8 / visibleCount
    for _, button in pairs(tabButtons) do
        if button.Visible then
            button.Size = UDim2.new(tabWidth, 0, 1, 0)
        end
    end
end

configureGameTabs()

local SearchBox = makeTextBox(Main, "")
SearchBox.Name = "Search"
SearchBox.PlaceholderText = "Search..."
SearchBox.Position = UDim2.new(0.8, 8, 0, 58)
SearchBox.Size = UDim2.new(0.2, -16, 0, 32)
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.ZIndex = 12

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

local universalFeatures = {}
local movementFeatures = {}
local mm2Features = {}
state.trsFeatures = {}
local allFeatures = {}
local featureConnections = {}
local tooltipConnections: {RBXScriptConnection} = {}

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

local function refreshFeatureToggle(feature)
    if feature.isCategory then
        return
    end
    feature.toggle.Text = feature.enabled and "ON" or "OFF"
    feature.toggle:SetAttribute("Selected", feature.enabled)
    feature.toggle.BackgroundColor3 = feature.enabled
        and state.headerColor
        or DEFAULT_SURFACE_COLOR
end

local function createUniversalFeature(
    name: string,
    description: string,
    layoutOrder: number,
    onToggle: any,
    configuration: any?
): any
    configuration = configuration or {}
    local registry = configuration.registry or universalFeatures
    local sectionName = configuration.section
        or (registry == mm2Features and "MM2")
        or (registry == state.trsFeatures and "TRS")
        or (registry == movementFeatures and "Movement")
        or "Universal"
    local configKey = configuration.configKey
        or (sectionName .. "." .. name:gsub("%W", ""))

    local feature = {
        name = name,
        description = description,
        enabled = false,
        expanded = false,
        isAction = configuration.action == true,
        isCategory = configuration.category == true,
        optionCount = 0,
        optionRows = {},
        collapsedHeight = 60,
        onToggle = onToggle,
        configKey = configKey,
    }

    local row = create("Frame", {
        Parent = configuration.parent or UniversalScroll,
        Name = name:gsub("%W", "") .. "Feature",
        BackgroundColor3 = Color3.fromRGB(31, 31, 31),
        BorderColor3 = DEFAULT_BORDER_COLOR,
        BorderSizePixel = 1,
        ClipsDescendants = true,
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, -4, 0, feature.collapsedHeight),
    })
    feature.row = row

    local title = makeTextLabel(row, name, 14)
    title.Font = Enum.Font.GothamBold
    title.Position = UDim2.fromOffset(14, 6)
    title.Size = UDim2.new(1, feature.isCategory and -70 or -178, 0, 24)

    local descriptionLabel = makeTextLabel(row, description, 11)
    descriptionLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
    descriptionLabel.Position = UDim2.fromOffset(14, 29)
    descriptionLabel.Size = UDim2.new(1, feature.isCategory and -70 or -178, 0, 21)

    local toggle = makeButton(row, feature.isAction and "RUN" or "OFF", 12)
    toggle.Name = "Toggle"
    toggle.Position = UDim2.new(1, -142, 0, 12)
    toggle.Size = UDim2.fromOffset(86, 36)
    toggle.Visible = not feature.isCategory
    feature.toggle = toggle

    local arrow = makeButton(row, "▼", 14)
    arrow.Name = "Expand"
    arrow.Position = UDim2.new(1, -48, 0, 12)
    arrow.Size = UDim2.fromOffset(34, 36)
    arrow.Visible = configuration.noOptions ~= true
    feature.arrow = arrow

    local options = create("Frame", {
        Parent = row,
        Name = "Options",
        BackgroundColor3 = Color3.fromRGB(25, 25, 25),
        BorderColor3 = Color3.fromRGB(61, 61, 61),
        BorderSizePixel = 1,
        Position = UDim2.fromOffset(10, feature.collapsedHeight),
        Size = UDim2.new(1, -20, 0, 0),
        Visible = false,
    })
    feature.options = options

    create("UIPadding", {
        Parent = options,
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 6),
    })

    create("UIListLayout", {
        Parent = options,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local function updateExpandedSize()
        local visibleOptions = 0
        for _, optionRow in ipairs(feature.optionRows) do
            if optionRow.Visible then
                visibleOptions = visibleOptions + 1
            end
        end
        local optionsHeight = visibleOptions * 39 + 12
        options.Size = UDim2.new(1, -20, 0, optionsHeight)
        row.Size = UDim2.new(
            1,
            -4,
            0,
            feature.expanded
                and feature.collapsedHeight + optionsHeight + 10
                or feature.collapsedHeight
        )
        options.Visible = feature.expanded
        arrow.Text = feature.expanded and "▲" or "▼"
    end
    feature.updateExpandedSize = updateExpandedSize

    arrow.MouseButton1Click:Connect(function()
        feature.expanded = not feature.expanded
        updateExpandedSize()
    end)

    toggle.MouseButton1Click:Connect(function()
        if feature.isCategory then
            return
        end
        if feature.isAction then
            local success, errorMessage = pcall(feature.onToggle)
            if not success then
                warn("[Random Testing Menu] " .. name .. ": " .. tostring(errorMessage))
            end
            return
        end

        local requestedState = not feature.enabled
        local success, errorMessage = pcall(function()
            feature.onToggle(requestedState)
        end)

        if success then
            feature.enabled = requestedState
            configData.states[feature.configKey] = requestedState
            queueConfigSave()
        else
            warn("[Random Testing Menu] " .. name .. ": " .. tostring(errorMessage))
            feature.enabled = false
            pcall(function()
                feature.onToggle(false)
            end)
        end

        refreshFeatureToggle(feature)
    end)

    registry[name] = feature
    table.insert(allFeatures, feature)

    if not feature.isAction
        and not feature.isCategory
        and configData.states[feature.configKey] == true then
        task.defer(function()
            local success, errorMessage = pcall(function()
                feature.onToggle(true)
            end)
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
    feature.optionCount = feature.optionCount + 1

    local option = create("Frame", {
        Parent = feature.options,
        BackgroundColor3 = Color3.fromRGB(30, 30, 30),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        LayoutOrder = feature.optionCount,
        Size = UDim2.new(1, 0, 0, 34),
    })
    create("UICorner", {
        Parent = option,
        CornerRadius = UDim.new(0, 4),
    })
    table.insert(feature.optionRows, option)

    local label = makeTextLabel(option, labelText, 12)
    label.Position = UDim2.fromOffset(10, 0)
    label.Size = UDim2.new(0.48, -10, 1, 0)

    feature.updateExpandedSize()
    return option :: Frame
end

local function setOptionVisible(feature: any, option: GuiObject, visible: boolean): ()
    option.Visible = visible
    feature.updateExpandedSize()
end

local function addToggleOption(
    feature: any,
    labelText: string,
    defaultValue: boolean,
    callback: (boolean) -> ()
): TextButton
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local enabled = configData.states[optionKey]
    if enabled == nil then
        enabled = defaultValue == true
    end

    local option = createOptionRow(feature, labelText)
    local button = makeButton(option, enabled and "ON" or "OFF", 11)
    button.Position = UDim2.new(0.72, 0, 0, 0)
    button.Size = UDim2.new(0.28, 0, 1, 0)
    button.BackgroundColor3 = enabled and state.headerColor or DEFAULT_SURFACE_COLOR

    button.MouseButton1Click:Connect(function()
        enabled = not enabled
        button.Text = enabled and "ON" or "OFF"
        button.BackgroundColor3 = enabled and state.headerColor or DEFAULT_SURFACE_COLOR
        configData.states[optionKey] = enabled
        callback(enabled)
        queueConfigSave()
    end)

    callback(enabled)
    return button :: TextButton
end

local function addActionOption(
    feature: any,
    labelText: string,
    callback: () -> ()
): TextButton
    local option = createOptionRow(feature, labelText)
    local button = makeButton(option, "RUN", 11)
    button.Position = UDim2.new(0.72, 0, 0, 0)
    button.Size = UDim2.new(0.28, 0, 1, 0)
    button.MouseButton1Click:Connect(function()
        local success, message = pcall(callback)
        if not success then
            warn("[Random Testing Menu] " .. labelText .. ": " .. tostring(message))
        end
    end)
    return button :: TextButton
end

local function addNumberOption(
    feature: any,
    labelText: string,
    defaultValue: number,
    minimum: number,
    maximum: number,
    callback: (number) -> ()
): TextBox
    local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
    local storedValue = tonumber(configData.values[optionKey])
    local initialValue = math.clamp(
        storedValue or defaultValue,
        minimum,
        maximum
    )
    local option = createOptionRow(feature, labelText)
    local box = makeTextBox(option, initialValue)
    box.Position = UDim2.new(0.5, 0, 0, 0)
    box.Size = UDim2.new(0.25, -4, 1, 0)

    local apply = makeButton(option, "SET", 11)
    apply.Position = UDim2.new(0.75, 4, 0, 0)
    apply.Size = UDim2.new(0.25, -4, 1, 0)

    local function commit()
        local number = math.clamp(
            tonumber(box.Text) or defaultValue,
            minimum,
            maximum
        )
        box.Text = tostring(number)
        callback(number)
        configData.values[optionKey] = number
        queueConfigSave()
    end

    apply.MouseButton1Click:Connect(commit)
    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            commit()
        end
    end)

    callback(initialValue)
    return box :: TextBox
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
        button.Text = "PRESS A KEY..."
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
    local option = createOptionRow(feature, "")
    local label = makeTextLabel(option, text, 11)
    label.TextColor3 = Color3.fromRGB(155, 155, 155)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Position = UDim2.fromOffset(4, 0)
    label.Size = UDim2.new(1, -8, 1, 0)
end

local FeatureTooltip: TextLabel = create("TextLabel", {
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
    Parent = FeatureTooltip,
    CornerRadius = UDim.new(0, 4),
})

create("UIPadding", {
    Parent = FeatureTooltip,
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
    PaddingTop = UDim.new(0, 5),
})

local tooltipToken: number = 0

local function showFeatureTooltip(row: Frame, text: string, pointer: Vector2?): ()
    tooltipToken = tooltipToken + 1
    FeatureTooltip.Text = text

    local width: number = math.clamp(#text * 5.5 + 24, 210, 520)
    local lineCount: number = math.max(1, math.ceil((#text * 5.5) / (width - 20)))
    local height: number = math.max(30, lineCount * 15 + 12)
    FeatureTooltip.Size = UDim2.fromOffset(width, height)

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

    FeatureTooltip.Position = UDim2.fromOffset(x, y)
    FeatureTooltip.Visible = true
end

local function hideFeatureTooltip(): ()
    tooltipToken = tooltipToken + 1
    FeatureTooltip.Visible = false
end

local function addFeatureTooltip(feature: any, text: string): ()
    local row: Frame = feature.row :: Frame

    table.insert(tooltipConnections, row.MouseEnter:Connect(function(): ()
        showFeatureTooltip(row, text, UserInputService:GetMouseLocation())
    end))

    table.insert(tooltipConnections, row.MouseLeave:Connect(function(): ()
        hideFeatureTooltip()
    end))

    table.insert(tooltipConnections, row.InputBegan:Connect(function(input: InputObject): ()
        if input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        showFeatureTooltip(row, text, Vector2.new(input.Position.X, input.Position.Y))
        local token: number = tooltipToken
        task.delay(2.5, function(): ()
            if tooltipToken == token then
                hideFeatureTooltip()
            end
        end)
    end))
end

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

    featureConnections.Fly = RunService.RenderStepped:Connect(function(deltaTime: number): ()
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
    featureConnections.Hitboxes = RunService.Heartbeat:Connect(function(deltaTime: number): ()
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

    featureConnections.AntiVoid = RunService.Heartbeat:Connect(function(deltaTime: number): ()
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
    featureConnections.Gravity = RunService.Heartbeat:Connect(function()
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

    featureConnections.JumpPower = RunService.Heartbeat:Connect(function()
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

    featureConnections.InfiniteJumpRise = RunService.RenderStepped:Connect(function()
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

    featureConnections.WalkSpeed = RunService.Heartbeat:Connect(function()
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
        RunService.Heartbeat:Connect(function(deltaTime: number): ()
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

    featureConnections.FOV = RunService.RenderStepped:Connect(function()
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

    featureConnections.Noclip = RunService.Stepped:Connect(function()
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

    featureConnections.AntiFling = RunService.Heartbeat:Connect(function()
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

    featureConnections.LagSwitch = RunService.Heartbeat:Connect(function()
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

local function findPlayerByText(text: string): Player?
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

local function performFling(targetPlayer: Player): ()
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

    featureConnections.Fullbright = RunService.Heartbeat:Connect(function()
        Lighting.Brightness = fullbrightSettings.brightness
        Lighting.ClockTime = fullbrightSettings.clockTime
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    end)
end

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

local GravityFeature = createUniversalFeature(
    "Gravity",
    "Keep workspace gravity at a custom value",
    5,
    toggleGravity
)
addNumberOption(GravityFeature, "Gravity value", gravitySettings.value, 0, 500, function(value)
    gravitySettings.value = value
end)

local JumpPowerFeature = createUniversalFeature(
    "Jump Power",
    "Keep character jump power at a custom value",
    6,
    toggleJumpPower
)
addNumberOption(JumpPowerFeature, "Power", jumpPowerSettings.value, 0, 500, function(value)
    jumpPowerSettings.value = value
end)

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

local WalkSpeedFeature = createUniversalFeature(
    "Walk Speed",
    "Keep character movement speed fixed",
    8,
    toggleWalkSpeed
)
addNumberOption(WalkSpeedFeature, "Speed", walkSpeedSettings.value, 0, 300, function(value)
    walkSpeedSettings.value = value
end)

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

local FovFeature = createUniversalFeature(
    "FOV",
    "Keep the camera field of view fixed",
    10,
    toggleFov
)
addNumberOption(FovFeature, "Field of view", fovSettings.value, 20, 120, function(value)
    fovSettings.value = value
end)

local NoclipFeature = createUniversalFeature(
    "Noclip",
    "Disable character collisions",
    11,
    toggleNoclip,
    {noOptions = true}
)
addFeatureTooltip(NoclipFeature, "Disables collisions for every local character part. "
    .. "Original collision states are restored when turned off.")

local CtrlClickFeature = createUniversalFeature(
    "CTRL + Click Teleport",
    "Teleport to the position under the cursor",
    12,
    toggleCtrlClickTeleport,
    {noOptions = true}
)
addFeatureTooltip(CtrlClickFeature, "Hold LeftControl and click a reachable world position.")

local AntiAfkFeature = createUniversalFeature(
    "Anti-AFK",
    "Prevent the local idle event from disconnecting",
    13,
    toggleAntiAfk,
    {noOptions = true}
)
addFeatureTooltip(AntiAfkFeature, "Responds only to Roblox's local idle event and "
    .. "disconnects immediately when disabled.")

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

    featureConnections.FreezeMovements = RunService.Stepped:Connect(function()
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

local function buildMM2Features()
local MM2Effects = create("Folder", {
    Parent = ScreenGui,
    Name = "MM2Effects",
})
local RoleEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "RoleESP",
})
local GunEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "GunESP",
})
local TrapEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "TrapESP",
})
local CoinEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "CoinChams",
})

local mm2RoundData = {}
local mm2RoleRemoteAvailable = false
local mm2GameplayRemotes = nil

pcall(function()
    mm2GameplayRemotes = game:GetService("ReplicatedStorage")
        :WaitForChild("Remotes", 5)
        :WaitForChild("Gameplay", 5)
    local getCurrentPlayerData = mm2GameplayRemotes:FindFirstChild(
        "GetCurrentPlayerData"
    )
    if getCurrentPlayerData and getCurrentPlayerData:IsA("RemoteFunction") then
        mm2RoleRemoteAvailable = true
        mm2RoundData = getCurrentPlayerData:InvokeServer() or {}
    end
end)

local mm2Settings = {
    hideSelf = false,
    autoGetGunDelay = 0.25,
    shootMode = "Manual",
    shootKey = Enum.KeyCode.Q,
    shootTarget = "",
    getGunKey = Enum.KeyCode.G,
    instantRoleNotify = false,
    roleEspAll = false,
    roleEspInnocent = false,
    roleEspMurderer = false,
    roleEspSheriff = false,
    innocentColor = Color3.fromRGB(35, 120, 60),
    innocentTransparency = 0.62,
    deadColor = Color3.fromRGB(105, 105, 105),
    deadTransparency = 0.58,
    murdererColor = Color3.fromRGB(145, 25, 25),
    murdererTransparency = 0.55,
    sheriffColor = Color3.fromRGB(45, 65, 155),
    sheriffTransparency = 0.55,
    heroColor = Color3.fromRGB(180, 145, 25),
    heroTransparency = 0.55,
    coinColor = Color3.fromRGB(230, 220, 65),
    coinTransparency = 0.8,
    trapColor = Color3.fromRGB(145, 25, 25),
    trapTransparency = 0.7,
    gunColor = Color3.fromRGB(160, 65, 215),
    gunTransparency = 0.5,
    autoPlayId = "",
}

local friendSettings = {
    names = {},
    protectRobloxFriends = true,
    friendUserIds = {},
}

local function refreshFriendProtection()
    friendSettings.friendUserIds = {}
    if friendSettings.protectRobloxFriends then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local success, friend = pcall(
                    LocalPlayer.IsFriendsWith,
                    LocalPlayer,
                    player.UserId
                )
                if success and friend then
                    friendSettings.friendUserIds[player.UserId] = true
                end
            end
        end
    end
end

state.isProtectedTarget = function(player)
    if not player or player == LocalPlayer then
        return true
    end
    if friendSettings.friendUserIds[player.UserId] then
        return true
    end
    local name = string.lower(player.Name)
    local displayName = string.lower(player.DisplayName)
    return friendSettings.names[name] == true
        or friendSettings.names[displayName] == true
end

featureConnections.MM2FriendPlayerAdded = Players.PlayerAdded:Connect(function()
    task.defer(refreshFriendProtection)
end)
task.spawn(refreshFriendProtection)

local function clearEffects(folder)
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("ObjectValue") and child.Value then
            child.Value:Destroy()
        end
        child:Destroy()
    end
end

local function findMM2Role(toolName, excludedPlayer)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= excludedPlayer then
            local backpack = player:FindFirstChildOfClass("Backpack")
            if backpack and backpack:FindFirstChild(toolName) then
                return player
            end
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= excludedPlayer
            and player.Character
            and player.Character:FindFirstChild(toolName) then
            return player
        end
    end

    return nil
end

local function playerFromRoundKey(key, data)
    if typeof(key) == "Instance" and key:IsA("Player") then
        return key
    end

    local player = Players:FindFirstChild(tostring(key))
    if player then
        return player
    end

    if type(data) == "table" then
        if data.Name then
            player = Players:FindFirstChild(tostring(data.Name))
        end
        if not player and data.UserId then
            local userId = tonumber(data.UserId)
            if userId then
                local success, resolvedPlayer = pcall(
                    Players.GetPlayerByUserId,
                    Players,
                    userId
                )
                player = success and resolvedPlayer or nil
            end
        end
    end

    return player
end

local function findPlayerByRoundRole(role)
    for key, data in pairs(mm2RoundData) do
        if type(data) == "table" and data.Role == role then
            local player = playerFromRoundKey(key, data)
            if player then
                return player
            end
        end
    end
    return nil
end

local function hasActiveRoundRoles()
    if not mm2RoleRemoteAvailable then
        return findMM2Role("Knife") ~= nil or findMM2Role("Gun") ~= nil
    end

    -- A table containing only Innocents can be residual countdown/lobby data.
    -- Requiring a round-defining role keeps every cham off in the lobby.
    for key, data in pairs(mm2RoundData) do
        if playerFromRoundKey(key, data)
            and type(data) == "table"
            and (data.Role == "Murderer"
                or data.Role == "Sheriff"
                or data.Role == "Hero") then
            return true
        end
    end
    return false
end

local function findMurderer()
    if mm2RoleRemoteAvailable then
        return findPlayerByRoundRole("Murderer")
    end
    return findMM2Role("Knife")
end

local function findSheriff()
    if mm2RoleRemoteAvailable then
        return findPlayerByRoundRole("Sheriff")
            or findPlayerByRoundRole("Hero")
    end
    return findMM2Role("Gun")
end

local function findMM2Map()
    for _, object in ipairs(workspace:GetChildren()) do
        if object:FindFirstChild("CoinContainer")
            and object:FindFirstChild("Spawns") then
            return object
        end
    end
    return nil
end

local function findDroppedGun()
    local map = findMM2Map()
    return (map and map:FindFirstChild("GunDrop", true))
        or workspace:FindFirstChild("GunDrop", true)
end

local function createMM2Marker(folder, adornee, labelText, color, transparency)
    local highlight = Instance.new("Highlight")
    highlight.Name = labelText .. "Highlight"
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.FillTransparency = transparency or 0.68
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0
    highlight.Parent = adornee

    local highlightReference = Instance.new("ObjectValue")
    highlightReference.Name = labelText .. "HighlightReference"
    highlightReference.Value = highlight
    highlightReference.Parent = folder

    local head = adornee:IsA("Model")
        and (adornee:FindFirstChild("Head")
            or adornee:FindFirstChild("HumanoidRootPart"))
        or adornee

    if head and head:IsA("BasePart") then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = labelText .. "Label"
        billboard.Adornee = head
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(130, 28)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.Parent = head

        local billboardReference = Instance.new("ObjectValue")
        billboardReference.Name = labelText .. "LabelReference"
        billboardReference.Value = billboard
        billboardReference.Parent = folder

        local text = Instance.new("TextLabel")
        text.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        text.BackgroundTransparency = 0.2
        text.BorderColor3 = color
        text.BorderSizePixel = 1
        text.Font = Enum.Font.GothamBold
        text.Size = UDim2.fromScale(1, 1)
        text.Text = labelText
        text.TextColor3 = color
        text.TextSize = 13
        text.Parent = billboard
    end
end

local function createMM2Cham(folder, adornee, color, transparency)
    local highlight = Instance.new("Highlight")
    highlight.Name = "RTMCham"
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.FillTransparency = transparency
    highlight.OutlineColor = color
    highlight.OutlineTransparency = math.clamp(transparency + 0.15, 0, 1)
    highlight.Parent = adornee

    local reference = Instance.new("ObjectValue")
    reference.Name = "ChamReference"
    reference.Value = highlight
    reference.Parent = folder
end

local function rebuildRoleEsp()
    clearEffects(RoleEffects)
    if not hasActiveRoundRoles() then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and not (mm2Settings.hideSelf and player == LocalPlayer) then
            local role = nil
            if mm2RoleRemoteAvailable then
                for key, data in pairs(mm2RoundData) do
                    if playerFromRoundKey(key, data) == player then
                        role = type(data) == "table" and data.Role or nil
                        break
                    end
                end
            elseif player == findMurderer() then
                role = "Murderer"
            elseif player == findSheriff() then
                role = "Sheriff"
            else
                role = "Innocent"
            end

            if role == "Innocent" then
                local backpack = player:FindFirstChildOfClass("Backpack")
                local heldGun = player.Character:FindFirstChild("Gun")
                    or (backpack and backpack:FindFirstChild("Gun"))
                if heldGun then
                    role = "Hero"
                end
            end

            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            local isDead = humanoid and humanoid.Health <= 0
            local show = mm2Settings.roleEspAll
                and ((role == "Innocent" and mm2Settings.roleEspInnocent)
                or (role == "Murderer" and mm2Settings.roleEspMurderer)
                or ((role == "Sheriff" or role == "Hero")
                    and mm2Settings.roleEspSheriff))

            if show and isDead then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.deadColor,
                    mm2Settings.deadTransparency
                )
            elseif show and role == "Murderer" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.murdererColor,
                    mm2Settings.murdererTransparency
                )
            elseif show and role == "Sheriff" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.sheriffColor,
                    mm2Settings.sheriffTransparency
                )
            elseif show and role == "Hero" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.heroColor,
                    mm2Settings.heroTransparency
                )
            elseif show and role == "Innocent" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.innocentColor,
                    mm2Settings.innocentTransparency
                )
            end
        end
    end
end

local function refreshRoleEspConnection()
    disconnectFeatureConnection("MM2RoleESP")
    clearEffects(RoleEffects)

    if not mm2Settings.roleEspAll
        or not (mm2Settings.roleEspInnocent
            or mm2Settings.roleEspMurderer
            or mm2Settings.roleEspSheriff) then
        return
    end

    rebuildRoleEsp()
    local elapsed = 0
    featureConnections.MM2RoleESP = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed >= 0.75 then
            elapsed = 0
            rebuildRoleEsp()
        end
    end)
end

local function toggleRoleEsp(enabled)
    mm2Settings.roleEspAll = enabled
    refreshRoleEspConnection()
end

local function toggleInnocentEsp(enabled)
    mm2Settings.roleEspInnocent = enabled
    refreshRoleEspConnection()
end

local function toggleMurdererEsp(enabled)
    mm2Settings.roleEspMurderer = enabled
    refreshRoleEspConnection()
end

local function toggleSheriffEsp(enabled)
    mm2Settings.roleEspSheriff = enabled
    refreshRoleEspConnection()
end

local roleNotificationSent = false

if mm2GameplayRemotes then
    local playerDataChanged = mm2GameplayRemotes:FindFirstChild("PlayerDataChanged")
    if playerDataChanged and playerDataChanged:IsA("RemoteEvent") then
        featureConnections.MM2PlayerDataChanged = playerDataChanged.OnClientEvent:Connect(function(newData)
            mm2RoundData = type(newData) == "table" and newData or {}
            rebuildRoleEsp()

            local roundActive = hasActiveRoundRoles()
            if not roundActive then
                roleNotificationSent = false
            elseif mm2Settings.instantRoleNotify and not roleNotificationSent then
                local murderer = findMurderer()
                local sheriff = findSheriff()
                if murderer and sheriff then
                    roleNotificationSent = true
                    notify(
                        "Roles ready - Murderer: "
                            .. murderer.Name
                            .. " | Sheriff/Hero: "
                            .. sheriff.Name
                    )
                end
            end
        end)
    end
end

local function toggleGunEsp(enabled)
    disconnectFeatureConnection("MM2GunESP")
    clearEffects(GunEffects)

    if not enabled then
        return
    end

    local elapsed = 1
    featureConnections.MM2GunESP = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.5 then
            return
        end
        elapsed = 0
        clearEffects(GunEffects)
        local gun = findDroppedGun()
        if gun then
            createMM2Marker(
                GunEffects,
                gun,
                "Dropped Gun",
                mm2Settings.gunColor,
                mm2Settings.gunTransparency
            )
        end
    end)
end

local function toggleTrapEsp(enabled)
    disconnectFeatureConnection("MM2TrapAdded")
    clearEffects(TrapEffects)

    if not enabled then
        return
    end

    local marked = setmetatable({}, {__mode = "k"})
    local function addTrap(object)
        if marked[object] then
            return
        end
        if (object.Name == "TrapVisual" or object.Name == "Trap")
            and (object:IsA("Model") or object:IsA("BasePart")) then
            marked[object] = true
            createMM2Cham(
                TrapEffects,
                object,
                mm2Settings.trapColor,
                mm2Settings.trapTransparency
            )
        end
    end

    local map = findMM2Map()
    for _, object in ipairs((map or workspace):GetDescendants()) do
        addTrap(object)
    end
    featureConnections.MM2TrapAdded = workspace.DescendantAdded:Connect(addTrap)
end

local coinChamsEnabled = false
local coinBoxes = setmetatable({}, {__mode = "k"})

local function getCoinServer(object)
    if not object or object:GetAttribute("Delete") == true then
        return nil
    end
    if object:IsA("BasePart") and object.Name == "Coin_Server" then
        return object
    end
    if object.Name == "CoinVisual" then
        local parent = object.Parent
        if parent and parent:IsA("BasePart") and parent.Name == "Coin_Server" then
            return parent
        end
        if object:IsA("BasePart") then
            return object
        end
    end
    return nil
end

local function addCoinBox(object)
    local coin = getCoinServer(object)
    if not coin or coinBoxes[coin] or coin:GetAttribute("Collected") then
        return
    end

    local box = Instance.new("BoxHandleAdornment")
    box.Name = "RTM_CoinBox"
    box.Adornee = coin
    box.AlwaysOnTop = true
    box.Color3 = mm2Settings.coinColor
    box.Size = Vector3.new(2.35, 2.35, 2.35)
    box.Transparency = mm2Settings.coinTransparency
    box.ZIndex = 5
    box.Parent = CoinEffects
    coinBoxes[coin] = box
end

local function toggleCoinChams(enabled)
    coinChamsEnabled = enabled
    disconnectFeatureConnection("MM2CoinAdded")
    disconnectFeatureConnection("MM2CoinTagged")
    disconnectFeatureConnection("MM2CoinCollected")
    clearEffects(CoinEffects)
    coinBoxes = setmetatable({}, {__mode = "k"})

    if not enabled then
        return
    end

    local collectionService = game:GetService("CollectionService")
    for _, object in ipairs(collectionService:GetTagged("CoinVisual")) do
        addCoinBox(object)
    end
    for _, object in ipairs(workspace:GetDescendants()) do
        if object.Name == "Coin_Server" or object.Name == "CoinVisual" then
            addCoinBox(object)
        end
    end

    featureConnections.MM2CoinTagged = collectionService
        :GetInstanceAddedSignal("CoinVisual")
        :Connect(addCoinBox)
    featureConnections.MM2CoinAdded = workspace.DescendantAdded:Connect(function(object)
        if object.Name == "Coin_Server" or object.Name == "CoinVisual" then
            addCoinBox(object)
        end
    end)

    local coinCollected = mm2GameplayRemotes
        and mm2GameplayRemotes:FindFirstChild("CoinCollected")
    if coinCollected and coinCollected:IsA("RemoteEvent") then
        featureConnections.MM2CoinCollected = coinCollected.OnClientEvent:Connect(
            function(coinId)
                for coin, box in pairs(coinBoxes) do
                    if coin:GetAttribute("CoinID") == coinId then
                        box:Destroy()
                        coinBoxes[coin] = nil
                    end
                end
            end
        )
    end
end

local autoGetGunBusy = false

local function toggleAutoGetGun(enabled)
    disconnectFeatureConnection("MM2AutoGetGun")
    autoGetGunBusy = false

    if not enabled then
        return
    end

    local elapsed = 0
    featureConnections.MM2AutoGetGun = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.5 or autoGetGunBusy then
            return
        end
        elapsed = 0

        local character = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local gunDrop = findDroppedGun()
        if not character or not gunDrop
            or (backpack and backpack:FindFirstChild("Gun"))
            or character:FindFirstChild("Gun") then
            return
        end

        autoGetGunBusy = true
        task.spawn(function()
            local savedCFrame = character:GetPivot()
            character:PivotTo(gunDrop:GetPivot() + Vector3.new(0, 2, 0))
            task.wait(mm2Settings.autoGetGunDelay)
            if character.Parent then
                character:PivotTo(savedCFrame)
            end
            autoGetGunBusy = false
        end)
    end)
end

local function toggleInstantRoleNotify(enabled)
    mm2Settings.instantRoleNotify = enabled
    if enabled and findMurderer() and findSheriff() then
        -- Do not repeat the alert when this option is enabled mid-round.
        roleNotificationSent = true
    end
end

local function toggleLoopAllInteract(enabled)
    disconnectFeatureConnection("MM2LoopInteract")
    if not enabled then
        return
    end

    local activeMap = nil
    local interactables = {}
    local elapsed = 0
    featureConnections.MM2LoopInteract = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.5 then
            return
        end
        elapsed = 0

        local map = findMM2Map()
        if map ~= activeMap then
            activeMap = map
            interactables = {}
            if map then
                for _, object in ipairs(map:GetDescendants()) do
                    if object:IsA("ProximityPrompt")
                        or object:IsA("ClickDetector") then
                        table.insert(interactables, object)
                    end
                end
            end
        end

        for _, object in ipairs(interactables) do
            if object:IsDescendantOf(activeMap) then
                if object:IsA("ProximityPrompt")
                    and object.Enabled
                    and type(fireproximityprompt) == "function" then
                    pcall(fireproximityprompt, object)
                elseif object:IsA("ClickDetector")
                    and type(fireclickdetector) == "function" then
                    pcall(fireclickdetector, object)
                end
            end
        end
    end)
end

local mutedRadioSounds = setmetatable({}, {__mode = "k"})
local mutedTrapSounds = setmetatable({}, {__mode = "k"})

local function restoreMutedSounds(cache)
    for sound, volume in pairs(cache) do
        if sound and sound.Parent then
            sound.Volume = volume
        end
    end
end

local function toggleMuteOtherRadios(enabled)
    disconnectFeatureConnection("MM2MuteRadios")
    restoreMutedSounds(mutedRadioSounds)
    mutedRadioSounds = setmetatable({}, {__mode = "k"})

    if not enabled then
        return
    end

    local function muteRadio(sound)
        if not sound:IsA("Sound") then
            return
        end
        local owner = nil
        local ancestor = sound.Parent
        while ancestor and not owner do
            owner = Players:GetPlayerFromCharacter(ancestor)
            ancestor = ancestor.Parent
        end
        if not owner or owner == LocalPlayer then
            return
        end
        local lowerName = string.lower(sound.Name)
        local parentName = sound.Parent and string.lower(sound.Parent.Name) or ""
        if string.find(lowerName, "radio", 1, true)
            or string.find(lowerName, "music", 1, true)
            or string.find(parentName, "radio", 1, true) then
            if mutedRadioSounds[sound] == nil then
                mutedRadioSounds[sound] = sound.Volume
            end
            sound.Volume = 0
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            for _, object in ipairs(player.Character:GetDescendants()) do
                muteRadio(object)
            end
        end
    end
    featureConnections.MM2MuteRadios = workspace.DescendantAdded:Connect(muteRadio)
end

local function toggleMuteTrapSounds(enabled)
    disconnectFeatureConnection("MM2MuteTraps")
    restoreMutedSounds(mutedTrapSounds)
    mutedTrapSounds = setmetatable({}, {__mode = "k"})

    if not enabled then
        return
    end

    local function muteTrap(sound)
        if not sound:IsA("Sound") then
            return
        end
        local ancestor = sound:FindFirstAncestor("Trap")
            or sound:FindFirstAncestor("TrapVisual")
        local parentName = sound.Parent and string.lower(sound.Parent.Name) or ""
        if ancestor or string.find(parentName, "trap", 1, true) then
            if mutedTrapSounds[sound] == nil then
                mutedTrapSounds[sound] = sound.Volume
            end
            sound.Volume = 0
        end
    end

    local map = findMM2Map()
    for _, object in ipairs((map or workspace):GetDescendants()) do
        muteTrap(object)
    end
    featureConnections.MM2MuteTraps = workspace.DescendantAdded:Connect(muteTrap)
end

local AutoPlaySound = Instance.new("Sound")
AutoPlaySound.Name = "RTM_MM2_AutoPlay"
AutoPlaySound.Looped = true
AutoPlaySound.Volume = 0.6
AutoPlaySound.Parent = game:GetService("SoundService")

local function toggleAutoPlayId(enabled)
    AutoPlaySound:Stop()
    if not enabled then
        return
    end

    local numericId = string.match(mm2Settings.autoPlayId, "%d+")
    if not numericId then
        error("Enter a valid Roblox audio ID first.")
    end
    AutoPlaySound.SoundId = "rbxassetid://" .. numericId
    AutoPlaySound:Play()
end

local sprintTrailObjects = {}

local function toggleSprintTrail(enabled)
    disconnectFeatureConnection("MM2SprintTrail")
    for _, object in ipairs(sprintTrailObjects) do
        if object and object.Parent then
            object:Destroy()
        end
    end
    sprintTrailObjects = {}

    if not enabled then
        return
    end

    featureConnections.MM2SprintTrail = RunService.Heartbeat:Connect(function()
        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
            return
        end

        local trail = root:FindFirstChild("RTM_SprintTail")
        if not trail then
            local left = Instance.new("Attachment")
            left.Name = "RTM_SprintLeft"
            left.Position = Vector3.new(-0.8, -0.5, 0.75)
            left.Parent = root

            local right = Instance.new("Attachment")
            right.Name = "RTM_SprintRight"
            right.Position = Vector3.new(0.8, -0.5, 0.75)
            right.Parent = root

            trail = Instance.new("Trail")
            trail.Name = "RTM_SprintTail"
            trail.Attachment0 = left
            trail.Attachment1 = right
            trail.Color = ColorSequence.new(
                Color3.fromRGB(255, 220, 55),
                Color3.fromRGB(175, 115, 20)
            )
            trail.Lifetime = 0.38
            trail.LightEmission = 0.25
            trail.FaceCamera = true
            trail.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(1, 1),
            })
            trail.Parent = root
            sprintTrailObjects = {trail, left, right}
        end
        trail.Enabled = humanoid.MoveDirection.Magnitude > 0.05
    end)
end

local sprintSpeedOriginal = setmetatable({}, {__mode = "k"})

local function toggleSprint(enabled)
    disconnectFeatureConnection("MM2Sprint")
    for humanoid, speed in pairs(sprintSpeedOriginal) do
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = speed
        end
    end
    sprintSpeedOriginal = setmetatable({}, {__mode = "k"})

    if not enabled then
        return
    end

    featureConnections.MM2Sprint = RunService.Heartbeat:Connect(function()
        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root then
            return
        end
        if sprintSpeedOriginal[humanoid] == nil then
            sprintSpeedOriginal[humanoid] = humanoid.WalkSpeed
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            humanoid.WalkSpeed = 30
            local direction = humanoid.MoveDirection
            if direction.Magnitude > 0.05 then
                local velocity = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(
                    direction.X * 30,
                    velocity.Y,
                    direction.Z * 30
                )
            end
        elseif humanoid.WalkSpeed == 30 then
            humanoid.WalkSpeed = sprintSpeedOriginal[humanoid]
        else
            sprintSpeedOriginal[humanoid] = humanoid.WalkSpeed
        end
    end)
end

local dualKnifeClone = nil

local function toggleDualEffect(enabled)
    disconnectFeatureConnection("MM2DualEffect")
    if dualKnifeClone then
        dualKnifeClone:Destroy()
        dualKnifeClone = nil
    end

    if not enabled then
        return
    end

    local elapsed = 1
    featureConnections.MM2DualEffect = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.35 then
            return
        end
        elapsed = 0

        local character = LocalPlayer.Character
        local knife = character and character:FindFirstChild("Knife")
        local handle = knife and knife:FindFirstChild("Handle")
        local leftHand = character
            and (character:FindFirstChild("LeftHand")
                or character:FindFirstChild("Left Arm"))

        if not handle or not leftHand then
            if dualKnifeClone then
                dualKnifeClone:Destroy()
                dualKnifeClone = nil
            end
            return
        end
        if dualKnifeClone and dualKnifeClone.Parent then
            return
        end

        dualKnifeClone = handle:Clone()
        dualKnifeClone.Name = "RTM_DualKnife"
        dualKnifeClone.Anchored = false
        dualKnifeClone.CanCollide = false
        dualKnifeClone.CanTouch = false
        dualKnifeClone.CanQuery = false
        dualKnifeClone.Massless = true
        for _, object in ipairs(dualKnifeClone:GetDescendants()) do
            if object:IsA("Script") or object:IsA("LocalScript")
                or object:IsA("TouchTransmitter")
                or object:IsA("JointInstance")
                or object:IsA("WeldConstraint") then
                object:Destroy()
            end
        end
        dualKnifeClone.CFrame = leftHand.CFrame * CFrame.Angles(0, 0, math.rad(90))
        dualKnifeClone.Parent = character

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = leftHand
        weld.Part1 = dualKnifeClone
        weld.Parent = dualKnifeClone
    end)
end

local fpsSettings = {
    textures = true,
    particles = true,
    shadows = true,
    materials = false,
}
local fpsModeEnabled = false
local fpsVisualCache = setmetatable({}, {__mode = "k"})

local function cacheFpsProperty(object, property)
    local data = fpsVisualCache[object]
    if not data then
        data = {}
        fpsVisualCache[object] = data
    end
    if data[property] == nil then
        data[property] = object[property]
    end
end

local function applyFpsObject(object)
    if fpsSettings.textures and (object:IsA("Decal") or object:IsA("Texture")) then
        cacheFpsProperty(object, "Transparency")
        object.Transparency = 1
    elseif fpsSettings.textures and object:IsA("MeshPart") then
        cacheFpsProperty(object, "TextureID")
        object.TextureID = ""
    end

    if fpsSettings.particles
        and (object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("Smoke")
            or object:IsA("Fire")
            or object:IsA("Sparkles")) then
        cacheFpsProperty(object, "Enabled")
        object.Enabled = false
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

local function restoreFpsObjects()
    for object, properties in pairs(fpsVisualCache) do
        if object and object.Parent then
            for property, value in pairs(properties) do
                pcall(function()
                    object[property] = value
                end)
            end
        end
    end
    fpsVisualCache = setmetatable({}, {__mode = "k"})
end

local function toggleImproveFps(enabled)
    fpsModeEnabled = enabled
    disconnectFeatureConnection("MM2ImproveFPS")
    restoreFpsObjects()

    if not enabled then
        return
    end

    task.spawn(function()
        for index, object in ipairs(workspace:GetDescendants()) do
            if not fpsModeEnabled then
                return
            end
            applyFpsObject(object)
            if index % 250 == 0 then
                task.wait()
            end
        end
    end)
    featureConnections.MM2ImproveFPS = workspace.DescendantAdded:Connect(function(object)
        if fpsModeEnabled then
            applyFpsObject(object)
        end
    end)
end

local TimerDisplay = create("Frame", {
    Parent = ScreenGui,
    Name = "MM2RoundTimer",
    BackgroundColor3 = Color3.fromRGB(24, 24, 24),
    BackgroundTransparency = 0.12,
    BorderColor3 = state.headerColor,
    BorderSizePixel = 1,
    Position = UDim2.new(1, -205, 0, 58),
    Size = UDim2.fromOffset(180, 34),
    Visible = false,
    ZIndex = 30,
})
local TimerText = makeTextLabel(TimerDisplay, "ROUND 0:00", 14)
TimerText.Font = Enum.Font.GothamBold
TimerText.TextXAlignment = Enum.TextXAlignment.Center
TimerText.Size = UDim2.fromScale(1, 1)
TimerText.ZIndex = 31
local timerEndsAt = nil
local timerRemotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
local timerGameplay = timerRemotes and timerRemotes:FindFirstChild("Gameplay")
local timerRoundStart = timerGameplay and timerGameplay:FindFirstChild("RoundStart")
local timerRoundEnd = timerGameplay and timerGameplay:FindFirstChild("RoundEndFade")

if timerRoundStart and timerRoundStart:IsA("RemoteEvent") then
    featureConnections.MM2TimerTrackerStart = timerRoundStart.OnClientEvent:Connect(
        function(duration)
            duration = tonumber(duration)
            timerEndsAt = duration and os.clock() + duration or nil
        end
    )
end
if timerRoundEnd and timerRoundEnd:IsA("RemoteEvent") then
    featureConnections.MM2TimerTrackerEnd = timerRoundEnd.OnClientEvent:Connect(function()
        timerEndsAt = nil
        TimerDisplay.Visible = false
    end)
end

local function toggleAlwaysShowTimer(enabled)
    disconnectFeatureConnection("MM2AlwaysTimer")
    TimerDisplay.Visible = false

    if not enabled then
        return
    end

    local getTimer = timerRemotes and timerRemotes:FindFirstChild("GetTimer", true)
    if getTimer and getTimer:IsA("RemoteFunction") then
        task.spawn(function()
            pcall(function()
                local remaining = tonumber(getTimer:InvokeServer())
                if remaining and remaining > 0 then
                    timerEndsAt = os.clock() + remaining
                end
            end)
        end)
    end

    local elapsed = 1
    featureConnections.MM2AlwaysTimer = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.1 then
            return
        end
        elapsed = 0

        local remaining = timerEndsAt and math.max(0, math.ceil(timerEndsAt - os.clock()))
        TimerDisplay.Visible = remaining ~= nil and remaining > 0
        if TimerDisplay.Visible then
            local minutes = math.floor(remaining / 60)
            TimerText.Text = string.format("ROUND %d:%02d", minutes, remaining % 60)
            TimerText.TextColor3 = remaining <= 30
                and Color3.fromRGB(190, 55, 55)
                or Color3.fromRGB(220, 220, 220)
        end
    end)
end

local function getSelectedShootTarget()
    local target
    if mm2Settings.shootMode == "Custom"
        and mm2Settings.shootTarget ~= "" then
        target = findPlayerByText(mm2Settings.shootTarget)
    else
        target = findMurderer()
    end
    return state.isProtectedTarget(target) and nil or target
end

local function fireGunAtTarget(target)
    local character, humanoid = getCharacterParts()
    if not target or not target.Character then
        notify("No selected shoot target was found.")
        return
    end
    if not character or not humanoid then
        notify("Your character is not available.")
        return
    end

    local gun = character:FindFirstChild("Gun")
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not gun and backpack then
        gun = backpack:FindFirstChild("Gun")
        if gun then
            humanoid:EquipTool(gun)
            task.wait()
        end
    end

    gun = character:FindFirstChild("Gun") or gun
    local remote = gun and gun:FindFirstChild("Shoot", true)
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    local originPart = character:FindFirstChild("RightHand")
        or (gun and gun:FindFirstChild("Handle"))
        or character:FindFirstChild("HumanoidRootPart")

    if not remote
        or not remote:IsA("RemoteEvent")
        or not targetRoot
        or not originPart then
        notify("The gun remote or target is unavailable.")
        return
    end

    local predictedPosition = targetRoot.Position
        + targetRoot.AssemblyLinearVelocity * 0.12
    remote:FireServer(
        CFrame.new(originPart.Position),
        CFrame.new(predictedPosition)
    )
    notify("Shot sent toward " .. target.Name)
end

local function shootMurderer()
    fireGunAtTarget(getSelectedShootTarget())
end

local shootFeatureActive = false
local shootHookInstalled = false
local shootHookOriginal = nil
local manualShotRequested = false
local shootToolConnections = setmetatable({}, {__mode = "k"})
local knifeSettings = {
    redirect = false,
    aura = false,
    swingRange = 13,
    attackRange = 13,
    maxTargets = 10,
    showTarget = true,
    targetParticles = false,
}
local knifeAuraForced = false
local knifeAuraTarget = nil
local knifeAuraVisuals = {}

local function getEquippedWeapon(name, tag)
    local character = LocalPlayer.Character
    if not character then
        return nil
    end
    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool")
            and (object.Name == name
                or game:GetService("CollectionService"):HasTag(object, tag)) then
            return object
        end
    end
    return nil
end

local function findDamageTargets(maxDistance, maxTargets)
    local _, _, localRoot = getCharacterParts()
    if not localRoot then
        return {}
    end

    local found = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local humanoid = player.Character
            and player.Character:FindFirstChildOfClass("Humanoid")
        local root = player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        if player ~= LocalPlayer
            and not state.isProtectedTarget(player)
            and humanoid
            and humanoid.Health > 0
            and root then
            local distance = (root.Position - localRoot.Position).Magnitude
            if distance <= (maxDistance or math.huge) then
                table.insert(found, {
                    player = player,
                    distance = distance,
                })
            end
        end
    end
    table.sort(found, function(left, right)
        return left.distance < right.distance
    end)

    local targets = {}
    for index = 1, math.min(#found, maxTargets or 1) do
        table.insert(targets, found[index].player)
    end
    return targets
end

local function findNearestDamageTarget(maxDistance)
    return findDamageTargets(maxDistance, 1)[1]
end

local function clearKnifeAuraVisuals()
    for player, visual in pairs(knifeAuraVisuals) do
        if visual.box then
            visual.box:Destroy()
        end
        if visual.particles then
            visual.particles:Destroy()
        end
        knifeAuraVisuals[player] = nil
    end
end

local function updateKnifeAuraVisuals(targets)
    local wanted = {}
    for _, player in ipairs(targets) do
        wanted[player] = true
    end

    for player, visual in pairs(knifeAuraVisuals) do
        if not wanted[player] or not player.Character then
            if visual.box then
                visual.box:Destroy()
            end
            if visual.particles then
                visual.particles:Destroy()
            end
            knifeAuraVisuals[player] = nil
        end
    end

    for _, player in ipairs(targets) do
        local root = player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            local visual = knifeAuraVisuals[player] or {}
            knifeAuraVisuals[player] = visual

            if knifeSettings.showTarget and not visual.box then
                local box = Instance.new("BoxHandleAdornment")
                box.Name = "RTM_KnifeAuraTarget"
                box.Adornee = root
                box.AlwaysOnTop = true
                box.ZIndex = 20
                box.Size = Vector3.new(4.5, 6, 2.5)
                box.Color3 = Color3.fromRGB(180, 45, 35)
                box.Transparency = 0.48
                box.Parent = ScreenGui
                visual.box = box
            elseif not knifeSettings.showTarget and visual.box then
                visual.box:Destroy()
                visual.box = nil
            end

            if knifeSettings.targetParticles and not visual.particles then
                local particles = Instance.new("ParticleEmitter")
                particles.Name = "RTM_KnifeAuraParticles"
                particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
                particles.Color = ColorSequence.new(
                    Color3.fromRGB(220, 55, 40),
                    Color3.fromRGB(110, 20, 20)
                )
                particles.LightEmission = 0.35
                particles.Lifetime = NumberRange.new(0.25, 0.45)
                particles.Rate = 14
                particles.Speed = NumberRange.new(0.5, 1.5)
                particles.SpreadAngle = Vector2.new(180, 180)
                particles.Parent = root
                visual.particles = particles
            elseif not knifeSettings.targetParticles and visual.particles then
                visual.particles:Destroy()
                visual.particles = nil
            end
        end
    end
end

local function redirectedKnifeCFrame()
    local knife = getEquippedWeapon("Knife", "Weapon_Knife")
    local target = knifeAuraForced and knifeAuraTarget
        or findNearestDamageTarget()
    if state.isProtectedTarget(target) then
        target = nil
    end
    local localRoot = LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetRoot = target
        and target.Character
        and target.Character:FindFirstChild("HumanoidRootPart")
    if not knife or not localRoot or not targetRoot then
        return nil
    end

    local throwSpeed = tonumber(knife:GetAttribute("ThrowSpeed")) or 96
    local travelTime = math.clamp(
        (targetRoot.Position - localRoot.Position).Magnitude / throwSpeed,
        0,
        0.75
    )
    return CFrame.new(
        targetRoot.Position + targetRoot.AssemblyLinearVelocity * travelTime
    )
end

local function redirectedTargetCFrame()
    local target = getSelectedShootTarget()
    local root = target
        and target.Character
        and target.Character:FindFirstChild("HumanoidRootPart")
    if root then
        return CFrame.new(root.Position + root.AssemblyLinearVelocity * 0.12)
    end
    return nil
end

local function installShootRedirectHook()
    if shootHookInstalled then
        return true
    end
    if type(hookfunction) ~= "function" then
        return false
    end

    local success = pcall(function()
        local weaponService = require(
            game:GetService("ReplicatedStorage")
                :WaitForChild("ClientServices")
                :WaitForChild("WeaponService")
        )

        shootHookOriginal = hookfunction(
            weaponService.GetMouseTargetCFrame,
            function(self, ...)
                local gun = getEquippedWeapon("Gun", "Weapon_Gun")
                local knife = getEquippedWeapon("Knife", "Weapon_Knife")

                if gun
                    and shootFeatureActive
                    and (mm2Settings.shootMode == "Redirect"
                        or manualShotRequested) then
                    local targetCFrame = redirectedTargetCFrame()
                    if targetCFrame then
                        return targetCFrame
                    end
                end
                if knife and (knifeSettings.redirect or knifeAuraForced) then
                    local targetCFrame = redirectedKnifeCFrame()
                    if targetCFrame then
                        return targetCFrame
                    end
                end
                return shootHookOriginal(self, ...)
            end
        )
        shootHookInstalled = true
    end)

    return success and shootHookInstalled
end

local function toggleKnifeRedirect(enabled)
    knifeSettings.redirect = enabled
    if enabled then
        installShootRedirectHook()
    end
end

local function toggleKnifeAura(enabled)
    knifeSettings.aura = enabled
    disconnectFeatureConnection("MM2KnifeAura")
    knifeAuraForced = false
    knifeAuraTarget = nil
    clearKnifeAuraVisuals()
    if not enabled then
        return
    end

    installShootRedirectHook()
    local elapsed = 0
    local targetIndex = 0
    featureConnections.MM2KnifeAura = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.14 then
            return
        end
        elapsed = 0

        local targets = findDamageTargets(
            knifeSettings.attackRange,
            knifeSettings.maxTargets
        )
        updateKnifeAuraVisuals(targets)
        if #targets == 0 then
            return
        end
        targetIndex = targetIndex % #targets + 1
        local target = targets[targetIndex]

        local character, humanoid, localRoot = getCharacterParts()
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local knife = getEquippedWeapon("Knife", "Weapon_Knife")
            or (backpack and backpack:FindFirstChild("Knife"))
        local targetRoot = target.Character
            and target.Character:FindFirstChild("HumanoidRootPart")
        if not knife
            or not character
            or not humanoid
            or not localRoot
            or not targetRoot
            or (targetRoot.Position - localRoot.Position).Magnitude
                > knifeSettings.swingRange then
            return
        end
        if knife.Parent == backpack then
            humanoid:EquipTool(knife)
            task.wait()
        end

        knifeAuraForced = true
        knifeAuraTarget = target
        local handle = knife:FindFirstChild("Handle")
        if handle and type(firetouchinterest) == "function" then
            pcall(firetouchinterest, handle, targetRoot, 0)
            knife:Activate()
            pcall(firetouchinterest, handle, targetRoot, 1)
        else
            knife:Activate()
        end
        task.delay(0.12, function()
            if knifeAuraTarget == target then
                knifeAuraForced = false
                knifeAuraTarget = nil
            end
        end)
    end)
end

local function disconnectShootTools()
    for tool, connection in pairs(shootToolConnections) do
        if connection then
            connection:Disconnect()
        end
        shootToolConnections[tool] = nil
    end
end

local function connectRedirectFallbackTool(tool)
    if shootToolConnections[tool]
        or not tool:IsA("Tool")
        or not (tool.Name == "Gun" or tool:HasTag("Weapon_Gun")) then
        return
    end

    shootToolConnections[tool] = tool.Activated:Connect(function()
        if shootFeatureActive and mm2Settings.shootMode == "Redirect" then
            fireGunAtTarget(getSelectedShootTarget())
        end
    end)
end

local function triggerManualShot()
    local character, humanoid = getCharacterParts()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local gun = character and character:FindFirstChild("Gun")
        or (backpack and backpack:FindFirstChild("Gun"))

    if gun and humanoid and shootHookInstalled then
        if gun.Parent == backpack then
            humanoid:EquipTool(gun)
            task.wait()
        end
        manualShotRequested = true
        gun:Activate()
        task.delay(0.2, function()
            manualShotRequested = false
        end)
    else
        shootMurderer()
    end
end

local function toggleShootMurderer(enabled)
    disconnectFeatureConnection("MM2ShootKey")
    disconnectFeatureConnection("MM2ShootMonitor")
    disconnectShootTools()
    shootFeatureActive = enabled

    if not enabled then
        return
    end

    installShootRedirectHook()

    featureConnections.MM2ShootKey = UserInputService.InputBegan:Connect(function(
        input,
        processed
    )
        if not processed
            and not UserInputService:GetFocusedTextBox()
            and (mm2Settings.shootMode == "Manual"
                or mm2Settings.shootMode == "Custom")
            and input.KeyCode == mm2Settings.shootKey then
            triggerManualShot()
        end
    end)

    featureConnections.MM2ShootMonitor = RunService.Heartbeat:Connect(function()
        if mm2Settings.shootMode ~= "Redirect" or shootHookInstalled then
            return
        end

        local character = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        for _, container in ipairs({character, backpack}) do
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    connectRedirectFallbackTool(child)
                end
            end
        end
    end)
end

local function teleportToMap()
    local map = findMM2Map()
    local spawns = map and map:FindFirstChild("Spawns")
    local character = LocalPlayer.Character
    if not spawns or not character then
        notify("No active MM2 map was found.")
        return
    end

    local spawnList = spawns:GetChildren()
    local target = spawnList[math.random(1, math.max(1, #spawnList))]
    if target and target:IsA("BasePart") then
        character:PivotTo(target.CFrame + Vector3.new(0, 3, 0))
    end
end

local function teleportToLobby()
    local lobby = workspace:FindFirstChild("Lobby")
    local spawns = lobby and lobby:FindFirstChild("Spawns")
    local spawn = spawns and spawns:FindFirstChildWhichIsA("SpawnLocation")
    local character = LocalPlayer.Character
    if spawn and character then
        character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
    else
        notify("The MM2 lobby spawn was not found.")
    end
end

local function teleportToDroppedGun()
    local gunDrop = findDroppedGun()
    local character = LocalPlayer.Character
    if gunDrop and character then
        local savedCFrame = character:GetPivot()
        character:PivotTo(gunDrop:GetPivot() + Vector3.new(0, 2, 0))
        task.wait(mm2Settings.autoGetGunDelay)
        if character.Parent then
            character:PivotTo(savedCFrame)
        end
    else
        notify("No dropped gun was found.")
    end
end

local InstantRolesFeature = createUniversalFeature(
    "Instant Role Notify",
    "Notify roles once at the beginning of each round",
    1,
    toggleInstantRoleNotify,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local RoleEspFeature = createUniversalFeature(
    "Player ESP",
    "Role highlights, coins, and traps",
    2,
    toggleRoleEsp,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addCycleOption(RoleEspFeature, "Local player", {"Show", "Hide"}, 1, function(value)
    mm2Settings.hideSelf = value == "Hide"
end)
addToggleOption(RoleEspFeature, "Innocent ESP", false, toggleInnocentEsp)
addColorOption(RoleEspFeature, "Innocent ESP color", mm2Settings.innocentColor, function(value)
    mm2Settings.innocentColor = value
end)
addNumberOption(RoleEspFeature, "Innocent transparency", 6.2, 0, 10, function(value)
    mm2Settings.innocentTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addColorOption(RoleEspFeature, "Dead ESP color", mm2Settings.deadColor, function(value)
    mm2Settings.deadColor = value
end)
addNumberOption(RoleEspFeature, "Dead transparency", 5.8, 0, 10, function(value)
    mm2Settings.deadTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addToggleOption(RoleEspFeature, "Murderer ESP", false, toggleMurdererEsp)
addColorOption(RoleEspFeature, "Murderer color", mm2Settings.murdererColor, function(value)
    mm2Settings.murdererColor = value
end)
addNumberOption(RoleEspFeature, "Murderer transparency", 5.5, 0, 10, function(value)
    mm2Settings.murdererTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addToggleOption(RoleEspFeature, "Sheriff ESP", false, toggleSheriffEsp)
addColorOption(RoleEspFeature, "Sheriff color", mm2Settings.sheriffColor, function(value)
    mm2Settings.sheriffColor = value
end)
addNumberOption(RoleEspFeature, "Sheriff transparency", 5.5, 0, 10, function(value)
    mm2Settings.sheriffTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addColorOption(RoleEspFeature, "Hero color", mm2Settings.heroColor, function(value)
    mm2Settings.heroColor = value
end)
addNumberOption(RoleEspFeature, "Hero transparency", 5.5, 0, 10, function(value)
    mm2Settings.heroTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addToggleOption(RoleEspFeature, "Coin Chams", false, toggleCoinChams)
addColorOption(RoleEspFeature, "Coin color", mm2Settings.coinColor, function(value)
    mm2Settings.coinColor = value
    if coinChamsEnabled then
        toggleCoinChams(true)
    end
end)
addNumberOption(RoleEspFeature, "Coin transparency", 8, 0, 10, function(value)
    mm2Settings.coinTransparency = value / 10
    if coinChamsEnabled then
        toggleCoinChams(true)
    end
end)
addToggleOption(RoleEspFeature, "Trap ESP", false, toggleTrapEsp)
addColorOption(RoleEspFeature, "Trap color", mm2Settings.trapColor, function(value)
    mm2Settings.trapColor = value
end)
addNumberOption(RoleEspFeature, "Trap transparency", 7, 0, 10, function(value)
    mm2Settings.trapTransparency = value / 10
end)

local GunVisualsFeature = createUniversalFeature(
    "Gun Visuals",
    "Highlight the dropped sheriff gun",
    3,
    toggleGunEsp,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addColorOption(GunVisualsFeature, "Gun color", mm2Settings.gunColor, function(value)
    mm2Settings.gunColor = value
end)
addNumberOption(GunVisualsFeature, "Gun transparency", 5, 0, 10, function(value)
    mm2Settings.gunTransparency = value / 10
end)

local ShootFeature = createUniversalFeature(
    "Shoot",
    "Manual key, gun redirect, or custom target",
    4,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
local ShootKeyButton
local ShootTargetBox
local function refreshShootOptions()
    if ShootKeyButton then
        setOptionVisible(
            ShootFeature,
            ShootKeyButton.Parent,
            mm2Settings.shootMode == "Manual"
                or mm2Settings.shootMode == "Custom"
        )
    end
    if ShootTargetBox then
        setOptionVisible(
            ShootFeature,
            ShootTargetBox.Parent,
            mm2Settings.shootMode == "Custom"
        )
    end
end
addCycleOption(
    ShootFeature,
    "Mode",
    {"Manual", "Redirect", "Custom"},
    1,
    function(value)
        mm2Settings.shootMode = value
        refreshShootOptions()
    end
)
ShootKeyButton = addKeyOption(
    ShootFeature,
    "Manual key",
    mm2Settings.shootKey,
    function(value)
        mm2Settings.shootKey = value
    end
)
ShootTargetBox = addTextOption(ShootFeature, "Target player", "", function(value)
    mm2Settings.shootTarget = value
end, false)
refreshShootOptions()
toggleShootMurderer(true)

local KnifeFeature = createUniversalFeature(
    "Knife",
    "Knife-only redirect and short-range aura",
    5,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addToggleOption(KnifeFeature, "Redirect", false, toggleKnifeRedirect)
addToggleOption(KnifeFeature, "Knife Aura", false, toggleKnifeAura)
addNumberOption(KnifeFeature, "Swing range", 13, 3, 30, function(value)
    knifeSettings.swingRange = value
end)
addNumberOption(KnifeFeature, "Attack range", 13, 3, 50, function(value)
    knifeSettings.attackRange = value
end)
addNumberOption(KnifeFeature, "Max targets", 10, 1, 12, function(value)
    knifeSettings.maxTargets = math.floor(value)
end)
addToggleOption(KnifeFeature, "Show target", true, function(value)
    knifeSettings.showTarget = value
    if not value and not knifeSettings.targetParticles then
        clearKnifeAuraVisuals()
    end
end)
addToggleOption(KnifeFeature, "Target particles", false, function(value)
    knifeSettings.targetParticles = value
    if not value and not knifeSettings.showTarget then
        clearKnifeAuraVisuals()
    end
end)

createUniversalFeature(
    "Loop All Interact",
    "Continuously activate prompts and click detectors",
    6,
    toggleLoopAllInteract,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local SilenceFeature = createUniversalFeature(
    "Silence",
    "Radio and trap audio controls",
    7,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addToggleOption(SilenceFeature, "Other radios", false, toggleMuteOtherRadios)
addToggleOption(SilenceFeature, "Trap sounds", false, toggleMuteTrapSounds)

local AutoPlayFeature = createUniversalFeature(
    "Auto Play ID",
    "Loop a local Roblox audio asset",
    8,
    toggleAutoPlayId,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addTextOption(AutoPlayFeature, "Play ID", mm2Settings.autoPlayId, function(value)
    mm2Settings.autoPlayId = value
    if AutoPlaySound.Playing then
        local numericId = string.match(value, "%d+")
        if numericId then
            AutoPlaySound.SoundId = "rbxassetid://" .. numericId
            AutoPlaySound:Play()
        end
    end
end)

createUniversalFeature(
    "Show Sprint Tail",
    "Show the local visual tail used by Sprint",
    9,
    toggleSprintTrail,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

createUniversalFeature(
    "Sprint",
    "Hold LeftShift for 30 movement speed",
    10,
    toggleSprint,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

createUniversalFeature(
    "Use Dual Effect",
    "Create a client-only second knife in the left hand",
    11,
    toggleDualEffect,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
local FpsFeature = createUniversalFeature(
    "Improve FPS",
    "Apply only the selected reversible optimizations",
    12,
    toggleImproveFps,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addToggleOption(FpsFeature, "Remove textures", true, function(value)
    fpsSettings.textures = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
addToggleOption(FpsFeature, "Disable particles", true, function(value)
    fpsSettings.particles = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
addToggleOption(FpsFeature, "Disable shadows", true, function(value)
    fpsSettings.shadows = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
addToggleOption(FpsFeature, "Simple materials", false, function(value)
    fpsSettings.materials = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
createUniversalFeature(
    "Always Show Timer",
    "Show the RoundStart timer above the coin bag",
    13,
    toggleAlwaysShowTimer,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local TeleportFeature = createUniversalFeature(
    "Teleport",
    "Map, lobby, and temporary gun pickup",
    14,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addActionOption(TeleportFeature, "Teleport to Map", teleportToMap)
addActionOption(TeleportFeature, "Teleport to Lobby", teleportToLobby)
addActionOption(TeleportFeature, "Get Gun", teleportToDroppedGun)
addKeyOption(TeleportFeature, "Get Gun key", mm2Settings.getGunKey, function(value)
    mm2Settings.getGunKey = value
end)
featureConnections.MM2GetGunKey = UserInputService.InputBegan:Connect(
    function(input, gameProcessed)
        if gameProcessed
            or state.keyCaptureCallback
            or UserInputService:GetFocusedTextBox() then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == mm2Settings.getGunKey then
            task.spawn(teleportToDroppedGun)
        end
    end
)
addToggleOption(TeleportFeature, "Auto Get Gun", false, toggleAutoGetGun)
addNumberOption(
    TeleportFeature,
    "Gun pickup delay",
    mm2Settings.autoGetGunDelay,
    0.05,
    2,
    function(value)
        mm2Settings.autoGetGunDelay = value
    end
)

local FlingGroup = createUniversalFeature(
    "Fling",
    "Role-based fling actions",
    15,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addActionOption(FlingGroup, "Fling Murderer", function()
    local target = findMurderer()
    if target then
        performFling(target)
    else
        notify("No murderer was found.")
    end
end)
addActionOption(FlingGroup, "Fling Sheriff", function()
    local target = findSheriff()
    if target then
        performFling(target)
    else
        notify("No sheriff or hero was found.")
    end
end)
addActionOption(FlingGroup, "Fling All Innocents", function()
    task.spawn(function()
        for key, data in pairs(mm2RoundData) do
            if type(data) == "table" and data.Role == "Innocent" then
                local target = playerFromRoundKey(key, data)
                if target and target ~= LocalPlayer then
                    performFling(target)
                    repeat
                        task.wait(0.05)
                    until not flingRunning
                end
            end
        end
    end)
end)

local FriendFeature = createUniversalFeature(
    "FriendList",
    "Protect listed players from targeting and damage helpers",
    16,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addTextOption(FriendFeature, "Protected names", "", function(value)
    friendSettings.names = {}
    for name in string.gmatch(string.lower(value), "[^,%s]+") do
        friendSettings.names[name] = true
    end
end)
addToggleOption(FriendFeature, "Protect Roblox friends", true, function(value)
    friendSettings.protectRobloxFriends = value
    task.spawn(refreshFriendProtection)
end)
addInformationOption(
    FriendFeature,
    "Separate names with commas. Shoot, Knife Aura and Fling will ignore them."
)

createUniversalFeature(
    "Get All Emotes",
    "Inject shop and unavailable MM2 emotes into the local profile",
    17,
    function()
        local profileData = require(
            game:GetService("ReplicatedStorage")
                :WaitForChild("Modules")
                :WaitForChild("ProfileData")
        )
        local sync = require(
            game:GetService("ReplicatedStorage")
                :WaitForChild("Database")
                :WaitForChild("Sync")
        )
        profileData.Emotes = profileData.Emotes or {}
        profileData.Emotes.Owned = profileData.Emotes.Owned or {}
        local owned = {}
        for _, emoteName in ipairs(profileData.Emotes.Owned) do
            owned[emoteName] = true
        end
        local count = 0
        for emoteName, emoteData in pairs(sync.Emotes or {}) do
            local isMM2Emote = type(emoteData) == "table"
                and emoteData.AnimationID ~= nil
                and (type(emoteData.Price) == "number"
                    or emoteData.Price == "NotForSale")
            if isMM2Emote and not owned[emoteName] then
                owned[emoteName] = true
                count = count + 1
                table.insert(profileData.Emotes.Owned, emoteName)
            end
        end

        local emoteModule = require(
            game:GetService("ReplicatedStorage")
                :WaitForChild("Modules")
                :WaitForChild("EmoteModule")
        )
        local emoteGui = emoteModule.EmoteGUI or _G.EmoteFrame
        if emoteGui then
            emoteModule.EmoteGUI = emoteGui
            emoteModule.GenerateEmotes(profileData.Emotes.Owned, emoteGui)
        end
        if type(_G.UpdateEmotes) == "function" then
            _G.UpdateEmotes()
        end
        notify("Injected " .. count .. " missing MM2 emotes locally.")
    end,
    {
        action = true,
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local hiddenNameLabels = setmetatable({}, {__mode = "k"})
local function toggleHideNames(enabled)
    disconnectFeatureConnection("MM2HideNames")
    if not enabled then
        for label, originalText in pairs(hiddenNameLabels) do
            if label and label.Parent and label.Text == "Anon" then
                label.Text = originalText
            end
        end
        hiddenNameLabels = setmetatable({}, {__mode = "k"})
        return
    end

    local elapsed = 1
    featureConnections.MM2HideNames = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.25 then
            return
        end
        elapsed = 0

        local names = {}
        for _, player in ipairs(Players:GetPlayers()) do
            names[player.Name] = true
            names[player.DisplayName] = true
            names["@" .. player.Name] = true
            names[player.DisplayName .. " (@" .. player.Name .. ")"] = true
        end
        local roots = {}
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            table.insert(roots, playerGui)
        end
        pcall(function()
            local robloxGui = game:GetService("CoreGui"):FindFirstChild("RobloxGui")
            local playerList = robloxGui
                and robloxGui:FindFirstChild("PlayerList", true)
            if playerList then
                table.insert(roots, playerList)
            end
        end)

        for _, root in ipairs(roots) do
            for _, object in ipairs(root:GetDescendants()) do
                if (object:IsA("TextLabel") or object:IsA("TextButton"))
                    and names[object.Text] then
                    if hiddenNameLabels[object] == nil then
                        hiddenNameLabels[object] = object.Text
                    end
                    object.Text = "Anon"
                end
            end
        end
    end)
end

createUniversalFeature(
    "Hide Names",
    "Replace player names in local UI and leaderboards with Anon",
    18,
    toggleHideNames,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

cleanupMM2Runtime = function()
    toggleShootMurderer(false)
    toggleKnifeAura(false)
    toggleKnifeRedirect(false)
    toggleHideNames(false)
    toggleAutoGetGun(false)
    toggleCoinChams(false)
    toggleTrapEsp(false)
    toggleMuteOtherRadios(false)
    toggleMuteTrapSounds(false)
    if AutoPlaySound then
        AutoPlaySound:Stop()
        AutoPlaySound:Destroy()
    end
end
end

if GAME_CHECK.MM2Active then
    SectionManager.register("MM2", buildMM2Features)
end

local function buildTRSFeatures()
    local settings = {
        tackleRange = 8,
        tackleLead = 0.12,
        tackleAimlock = true,
        tackleBox = true,
        opponentsOnly = true,
        dribbleRange = 10,
        dribblePrediction = 0.18,
        dribblePreempt = true,
        dribbleStyle = "Normal",
        power = false,
        powerValue = 1,
        shootKey = Enum.KeyCode.G,
        powerShotKey = Enum.KeyCode.T,
        longShotKey = Enum.KeyCode.R,
        shootGoalRange = 120,
        powerShotRange = 120,
        shootTargetHeight = 4,
        goalVisualRange = 100,
        goalVisualSize = 2.5,
        goalVisualCurve = 5,
        goalVisualLine = true,
        pickupMode = "Automatic",
        pickupKey = Enum.KeyCode.H,
        pickupReach = 18,
        pickupMaxHeight = 12,
        pickupReportedDistance = 2.8,
        pickupDelay = 0.1,
        pickupDeke = true,
        passMode = "Manual",
        passKey = Enum.KeyCode.V,
        passRange = 150,
        passPressureRange = 9,
        passForwardOnly = true,
        trajectoryTime = 2.4,
        goalkeeperRange = 32,
        goalkeeperMinSpeed = 8,
        goalkeeperHighBall = 5,
        headerRange = 7,
        headerGoalRange = 50,
    }
    local tackleBox = nil
    local dribbleBox = nil
    local lastTackle = 0
    local lastDribble = 0
    local lastPass = 0
    local lastPickup = 0
    local lastShot = 0
    local nativeShotContext = nil
    local nativeHeaderContext = nil
    local shotHookInstalled = false
    local originalNamecall = nil
    local pickupRemote = nil
    local trajectoryParts = {}
    local landingMarker = nil
    local lastGoalkeeperAction = 0
    local lastHeaderAction = 0
    local goalVisualObjects = {}

    local function getWorldBools()
        return workspace:FindFirstChild("Bools")
    end

    local function boolEnabled(folder, name)
        local value = folder and folder:FindFirstChild(name)
        return value and value.Value == true
    end

    local function isLocalGoalkeeper(worldBools)
        local apg = worldBools and worldBools:FindFirstChild("APG")
        local hpg = worldBools and worldBools:FindFirstChild("HPG")
        return (apg and apg.Value == LocalPlayer)
            or (hpg and hpg.Value == LocalPlayer)
    end

    local function getOpponentGoal()
        if LocalPlayer.TeamColor == BrickColor.new(23) then
            return workspace:FindFirstChild("HomeGoalDetector")
        end
        if LocalPlayer.TeamColor == BrickColor.new(141) then
            return workspace:FindFirstChild("AwayGoalDetector")
        end
        return nil
    end

    local function getOwnGoal()
        if LocalPlayer.TeamColor == BrickColor.new(23) then
            return workspace:FindFirstChild("AwayGoalDetector")
        end
        if LocalPlayer.TeamColor == BrickColor.new(141) then
            return workspace:FindFirstChild("HomeGoalDetector")
        end
        return nil
    end

    local function localActionBlocked(character, checkDribble)
        local localBools = character and character:FindFirstChild("Bools")
        local worldBools = getWorldBools()
        if not localBools
            or boolEnabled(localBools, "Tackled")
            or boolEnabled(localBools, "Tackling")
            or boolEnabled(localBools, "Debounce")
            or boolEnabled(localBools, "iframe")
            or boolEnabled(worldBools, "Penalty")
            or boolEnabled(worldBools, "Kickoff")
            or boolEnabled(worldBools, "FreeKick") then
            return true
        end
        if checkDribble
            and (boolEnabled(localBools, "dribbleDebounce")
                or boolEnabled(localBools, "dribbleDelay")) then
            return true
        end
        return false
    end

    local function getBall()
        local ball = workspace:FindFirstChild("ball")
        if ball and ball:IsA("BasePart") then
            return ball
        end
        return nil
    end

    local function getBallOwner()
        local ball = getBall()
        local creator = ball and ball:FindFirstChild("creator")
        if ball
            and ball:FindFirstChild("playerWeld")
            and creator
            and creator:IsA("ObjectValue")
            and creator.Value
            and creator.Value:IsA("Player") then
            return creator.Value, ball
        end
        return nil, ball
    end

    local function clearTackleBox()
        if tackleBox then
            tackleBox:Destroy()
            tackleBox = nil
        end
    end

    local function showTackleTarget(player)
        if not settings.tackleBox then
            clearTackleBox()
            return
        end
        local root = player
            and player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then
            clearTackleBox()
            return
        end
        if not tackleBox then
            tackleBox = Instance.new("BoxHandleAdornment")
            tackleBox.Name = "RTM_TRS_BallCarrier"
            tackleBox.AlwaysOnTop = true
            tackleBox.ZIndex = 20
            tackleBox.Size = Vector3.new(4.5, 6, 2.5)
            tackleBox.Color3 = Color3.fromRGB(35, 150, 125)
            tackleBox.Transparency = 0.45
            tackleBox.Parent = ScreenGui
        end
        tackleBox.Adornee = root
    end

    local function clearDribbleBox()
        if dribbleBox then
            dribbleBox:Destroy()
            dribbleBox = nil
        end
    end

    local function showDribbleThreat(player)
        local root = player
            and player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then
            clearDribbleBox()
            return
        end
        if not dribbleBox then
            dribbleBox = Instance.new("BoxHandleAdornment")
            dribbleBox.Name = "RTM_TRS_DribbleThreat"
            dribbleBox.AlwaysOnTop = true
            dribbleBox.ZIndex = 21
            dribbleBox.Size = Vector3.new(4.5, 6, 2.5)
            dribbleBox.Color3 = Color3.fromRGB(215, 125, 35)
            dribbleBox.Transparency = 0.35
            dribbleBox.Parent = ScreenGui
        end
        dribbleBox.Adornee = root
    end

    local function validCarrier(owner)
        if not owner
            or owner == LocalPlayer
            or state.isProtectedTarget(owner)
            or not owner.Character then
            return false
        end
        if settings.opponentsOnly and owner.TeamColor == LocalPlayer.TeamColor then
            return false
        end
        local humanoid = owner.Character:FindFirstChildOfClass("Humanoid")
        return humanoid ~= nil and humanoid.Health > 0
    end

    local function findDribbleThreat(root, rangeOverride, predictionOverride)
        local triggerRange = rangeOverride or settings.dribbleRange
        local usePrediction = predictionOverride
        if usePrediction == nil then
            usePrediction = settings.dribblePreempt
        end
        local bestPlayer = nil
        local bestDistance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local targetRoot = character
                and character:FindFirstChild("HumanoidRootPart")
            local targetHumanoid = character
                and character:FindFirstChildOfClass("Humanoid")
            if player ~= LocalPlayer
                and player.TeamColor ~= LocalPlayer.TeamColor
                and targetRoot
                and targetHumanoid
                and targetHumanoid.Health > 0 then
                local offset = root.Position - targetRoot.Position
                local distance = offset.Magnitude
                if distance <= triggerRange + 4 and distance > 0.05 then
                    local targetBools = character:FindFirstChild("Bools")
                    local tackling = boolEnabled(targetBools, "Tackling")
                        or boolEnabled(targetBools, "TackleDebounce")
                    local relativeVelocity = targetRoot.AssemblyLinearVelocity
                        - root.AssemblyLinearVelocity
                    local closingSpeed = -offset.Unit:Dot(relativeVelocity)
                    local futureOffset = offset
                        - relativeVelocity * settings.dribblePrediction
                    local predictedDistance = futureOffset.Magnitude
                    local facing = targetRoot.CFrame.LookVector:Dot(offset.Unit) > 0.05
                    local imminent = usePrediction
                        and facing
                        and closingSpeed > 2
                        and predictedDistance <= triggerRange
                    if (tackling or imminent)
                        and distance < bestDistance then
                        bestPlayer = player
                        bestDistance = distance
                    end
                end
            end
        end
        return bestPlayer, bestDistance
    end

    local function pointToSegmentDistance(point, startPoint, endPoint)
        local segment = endPoint - startPoint
        local lengthSquared = segment:Dot(segment)
        if lengthSquared <= 0.001 then
            return (point - startPoint).Magnitude
        end
        local alpha = math.clamp(
            (point - startPoint):Dot(segment) / lengthSquared,
            0,
            1
        )
        return (point - (startPoint + segment * alpha)).Magnitude
    end

    local function getBestPassTarget(root)
        local opponentGoal = getOpponentGoal()
        local worldBools = getWorldBools()
        local apg = worldBools and worldBools:FindFirstChild("APG")
        local hpg = worldBools and worldBools:FindFirstChild("HPG")
        local currentGoalDistance = opponentGoal
            and (root.Position - opponentGoal.Position).Magnitude
            or 0
        local bestPlayer = nil
        local bestScore = -math.huge

        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local targetRoot = character
                and character:FindFirstChild("HumanoidRootPart")
            local targetHumanoid = character
                and character:FindFirstChildOfClass("Humanoid")
            if player ~= LocalPlayer
                and player.TeamColor == LocalPlayer.TeamColor
                and (not apg or apg.Value ~= player)
                and (not hpg or hpg.Value ~= player)
                and targetRoot
                and targetHumanoid
                and targetHumanoid.Health > 0 then
                local distance = (targetRoot.Position - root.Position).Magnitude
                local targetGoalDistance = opponentGoal
                    and (targetRoot.Position - opponentGoal.Position).Magnitude
                    or currentGoalDistance
                local progress = currentGoalDistance - targetGoalDistance
                if distance <= settings.passRange
                    and (not settings.passForwardOnly or progress > 1) then
                    local blockers = 0
                    for _, opponent in ipairs(Players:GetPlayers()) do
                        local opponentRoot = opponent.Character
                            and opponent.Character:FindFirstChild("HumanoidRootPart")
                        if opponent.TeamColor ~= LocalPlayer.TeamColor
                            and opponentRoot
                            and pointToSegmentDistance(
                                opponentRoot.Position,
                                root.Position,
                                targetRoot.Position
                            ) < 4.5 then
                            blockers = blockers + 1
                        end
                    end
                    local score = progress - distance * 0.08 - blockers * 18
                    if score > bestScore then
                        bestScore = score
                        bestPlayer = player
                    end
                end
            end
        end
        return bestPlayer
    end

    local function getGoalCandidates(goal, targetHeight)
        if not goal or not goal:IsA("BasePart") then
            return {}
        end

        local modelName = goal.Name == "HomeGoalDetector"
            and "HomeGoal"
            or "AwayGoal"
        local goalModel = workspace:FindFirstChild(modelName)
        local targets = goalModel and goalModel:FindFirstChild("Targets")
        local positions = {}
        if targets then
            for _, target in ipairs(targets:GetChildren()) do
                if target:IsA("BasePart") then
                    table.insert(positions, target.Position)
                end
            end
        end

        local center = goal.Position + Vector3.new(0, targetHeight, 0)
        if #positions < 3 then
            positions = {
                center - goal.CFrame.RightVector * 5,
                center,
                center + goal.CFrame.RightVector * 5,
            }
        else
            table.sort(positions, function(a, b)
                return (a - goal.Position):Dot(goal.CFrame.RightVector)
                    < (b - goal.Position):Dot(goal.CFrame.RightVector)
            end)
            positions = {
                positions[1],
                positions[math.ceil(#positions / 2)],
                positions[#positions],
            }
        end
        return positions
    end

    local function goalPathBlocked(startPosition, targetPosition, character, goal)
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local excluded = {}
        if character then
            table.insert(excluded, character)
        end
        local ball = getBall()
        if ball then
            table.insert(excluded, ball)
        end
        local goalModel = workspace:FindFirstChild(
            goal.Name == "HomeGoalDetector" and "HomeGoal" or "AwayGoal"
        )
        if goalModel then
            table.insert(excluded, goalModel)
        end
        rayParams.FilterDescendantsInstances = excluded
        rayParams.IgnoreWater = true
        local result = workspace:Raycast(
            startPosition,
            targetPosition - startPosition,
            rayParams
        )
        return result ~= nil
            and (result.Position - targetPosition).Magnitude > 4
    end

    local function selectGoalTarget(goal, startPosition, targetHeight, character)
        local candidates = getGoalCandidates(goal, targetHeight)
        if #candidates == 0 then
            return nil, candidates, {}
        end

        local modelName = goal.Name == "HomeGoalDetector"
            and "HomeGoal"
            or "AwayGoal"
        local worldBools = getWorldBools()
        local goalkeeperValue = worldBools
            and worldBools:FindFirstChild(
                modelName == "HomeGoal" and "HPG" or "APG"
            )
        local goalkeeper = goalkeeperValue and goalkeeperValue.Value
        local goalkeeperRoot = goalkeeper
            and goalkeeper.Character
            and goalkeeper.Character:FindFirstChild("HumanoidRootPart")
        local blocked = {}
        local bestPosition = candidates[2] or candidates[1]
        local bestScore = -math.huge
        for index, position in ipairs(candidates) do
            blocked[index] = goalPathBlocked(
                startPosition,
                position,
                character,
                goal
            )
            local separation = goalkeeperRoot
                and (position - goalkeeperRoot.Position).Magnitude
                or 8
            local score = separation - (blocked[index] and 1000 or 0)
            if index == 2 then
                score = score + 0.25
            end
            if score > bestScore then
                bestScore = score
                bestPosition = position
            end
        end
        return bestPosition, candidates, blocked
    end

    local function toggleAutoTackle(enabled)
        disconnectFeatureConnection("TRSAutoTackle")
        clearTackleBox()
        if not enabled then
            return
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local action = remotes and remotes:FindFirstChild("Action")
        local disarm = remotes and remotes:FindFirstChild("SoftDisPlayer")
        featureConnections.TRSAutoTackle = RunService.Heartbeat:Connect(function()
            local owner, ball = getBallOwner()
            local character, humanoid, root = getCharacterParts()
            local targetRoot = validCarrier(owner)
                and owner.Character:FindFirstChild("HumanoidRootPart")
            if not ball
                or not character
                or not humanoid
                or not root
                or not targetRoot then
                clearTackleBox()
                return
            end

            local predictedTarget = targetRoot.Position
                + targetRoot.AssemblyLinearVelocity * settings.tackleLead
            local offset = predictedTarget - root.Position
            local distance = offset.Magnitude
            if distance > settings.tackleRange then
                clearTackleBox()
                return
            end
            showTackleTarget(owner)

            if settings.tackleAimlock and distance > 0.1 then
                root.CFrame = CFrame.lookAt(
                    root.Position,
                    Vector3.new(predictedTarget.X, root.Position.Y, predictedTarget.Z)
                )
            end
            if os.clock() - lastTackle < 0.85 then
                return
            end

            local bools = character:FindFirstChild("Bools")
            if localActionBlocked(character, false)
                or boolEnabled(bools, "TackleDebounce")
                or not action
                or not action:IsA("RemoteEvent") then
                return
            end

            lastTackle = os.clock()
            action:FireServer("TackIe")
            local velocity = Instance.new("BodyVelocity")
            velocity.Name = "RTM_TRS_TackleVelocity"
            velocity.MaxForce = Vector3.new(50000000, 0, 50000000)
            velocity.Velocity = (
                distance > 0.1 and offset.Unit or root.CFrame.LookVector
            ) * 42
            velocity.Parent = root
            game:GetService("Debris"):AddItem(velocity, 0.32)

            if disarm and disarm:IsA("RemoteEvent") then
                for _, delayTime in ipairs({0.06, 0.16}) do
                    task.delay(delayTime, function()
                        local currentOwner, currentBall = getBallOwner()
                        if currentOwner == owner
                            and currentBall
                            and (targetRoot.Position - root.Position).Magnitude
                                <= settings.tackleRange + 2 then
                            disarm:FireServer(
                                owner,
                                (root.Position - currentBall.Position).Magnitude,
                                false,
                                currentBall.Size
                            )
                        end
                    end)
                end
            end
        end)
    end

    local function toggleAutoDribble(enabled)
        disconnectFeatureConnection("TRSAutoDribble")
        clearDribbleBox()
        if not enabled then
            return
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local action = remotes and remotes:FindFirstChild("Action")
        local passRemote = remotes and remotes:FindFirstChild("Pass")
        featureConnections.TRSAutoDribble = RunService.Heartbeat:Connect(function()
            local owner, ball = getBallOwner()
            local character, humanoid, root = getCharacterParts()
            if owner ~= LocalPlayer
                or not character
                or not humanoid
                or not root
                or not action
                or not action:IsA("RemoteEvent")
                or os.clock() - lastDribble < 0.52
                or localActionBlocked(character, true)
                or isLocalGoalkeeper(getWorldBools()) then
                clearDribbleBox()
                return
            end

            local threat = findDribbleThreat(root)
            if not threat then
                clearDribbleBox()
                return
            end
            showDribbleThreat(threat)
            lastDribble = os.clock()
            if settings.dribbleStyle == "Assist" then
                local teammate = getBestPassTarget(root)
                if teammate and passRemote and passRemote:IsA("RemoteEvent") then
                    passRemote:FireServer(teammate, ball.CFrame)
                end
            else
                action:FireServer("Deke")
            end
        end)
    end

    local function installShotHook()
        if shotHookInstalled then
            return true
        end
        if type(hookmetamethod) ~= "function"
            or type(getnamecallmethod) ~= "function" then
            return false
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local shoot = remotes
            and (remotes:FindFirstChild("ShootTheBaII")
                or remotes:FindFirstChild("ShootTheBall"))
        if not shoot then
            return false
        end
        local callback = function(self, ...)
            local method = getnamecallmethod()
            if self == shoot and method == "FireServer" then
                local arguments = {...}
                local context = nativeShotContext or nativeHeaderContext
                local ball = getBall()
                if context and ball and context.target then
                    local offset = context.target - ball.Position
                    if offset.Magnitude > 0.1 then
                        local direction = offset.Unit
                        local magnitude = typeof(arguments[4]) == "Vector3"
                            and arguments[4].Magnitude
                            or 1
                        arguments[1] = direction
                        arguments[4] = direction * math.max(magnitude, 1)
                        arguments[7] = context.curve
                        arguments[10] = context.side
                        if context.kind == "Power" or context.kind == "Long" then
                            arguments[3] = math.max(
                                tonumber(arguments[3]) or 0,
                                1
                            )
                            arguments[9] = true
                        end
                    end
                    if context == nativeShotContext then
                        nativeShotContext = nil
                    else
                        nativeHeaderContext = nil
                    end
                elseif settings.power and getBallOwner() == LocalPlayer then
                    arguments[3] = settings.powerValue
                end
                return originalNamecall(self, unpack(arguments))
            end
            return originalNamecall(self, ...)
        end
        if type(newcclosure) == "function" then
            callback = newcclosure(callback)
        end
        originalNamecall = hookmetamethod(game, "__namecall", callback)
        shotHookInstalled = originalNamecall ~= nil
        return shotHookInstalled
    end

    local function toggleMaxPower(enabled)
        settings.power = enabled
        if enabled and not installShotHook() then
            settings.power = false
            error("This executor does not support the local ShootTheBall hook.")
        end
    end

    local function getMobileButton(name)
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local mobile = playerGui and playerGui:FindFirstChild("MobileCTRL")
        local frame = mobile and mobile:FindFirstChild("TouchControlFrame")
        local jumpButton = frame and frame:FindFirstChild("JumpButton")
        if name == "JumpButton" then
            return jumpButton
        end
        return jumpButton and jumpButton:FindFirstChild(name)
    end

    local function fireNativeSignal(signal)
        if not signal then
            return false
        end
        if type(firesignal) == "function" then
            firesignal(signal)
            return true
        end
        if type(getconnections) == "function" then
            local fired = false
            for _, connection in ipairs(getconnections(signal)) do
                if connection.Fire then
                    connection:Fire()
                    fired = true
                elseif connection.Function then
                    task.spawn(connection.Function)
                    fired = true
                end
            end
            return fired
        end
        return false
    end

    local function fireGoalShot(kind, showFailure)
        local owner, ball = getBallOwner()
        local character, humanoid, root = getCharacterParts()
        local goal = getOpponentGoal()
        if owner ~= LocalPlayer
            or not ball
            or not character
            or not humanoid
            or not root
            or not goal
            or localActionBlocked(character, false)
            or isLocalGoalkeeper(getWorldBools())
            or os.clock() - lastShot < 0.18 then
            return false
        end

        local goalDistance = (root.Position - goal.Position).Magnitude
        local maximumRange = kind == "Normal"
            and settings.shootGoalRange
            or kind == "Power" and settings.powerShotRange
            or math.huge
        if goalDistance > maximumRange then
            if showFailure then
                notify(
                    kind == "Normal"
                        and "Shoot Assist: move closer to the opponent goal."
                        or "Power Shot: move closer to the opponent goal."
                )
            end
            return false
        end
        local powerDebounce = LocalPlayer:FindFirstChild("PowerShootDebounce")
        if kind ~= "Normal" and powerDebounce and powerDebounce.Value then
            if showFailure then
                notify(kind .. " Shot: power shot is still on cooldown.")
            end
            return false
        end

        local grabTick = character:FindFirstChild("GrabTick")
        if grabTick
            and tonumber(grabTick.Value)
            and tick() - grabTick.Value <= 0.35 then
            return false
        end

        local targetPosition = selectGoalTarget(
            goal,
            ball.Position,
            settings.shootTargetHeight,
            character
        )
        local direction = targetPosition and (targetPosition - ball.Position)
        if not direction or direction.Magnitude <= 0.1 then
            return false
        end

        local localTarget = goal.CFrame:PointToObjectSpace(targetPosition)
        local side = localTarget.X >= 0 and "Right" or "Left"
        local curve = side
        local bools = character:FindFirstChild("Bools")
        local curveValue = bools and bools:FindFirstChild("Curve")
        if curveValue then
            curveValue.Value = curve
        end

        if not installShotHook() then
            if showFailure then
                notify("Native shot redirect requires hookmetamethod.")
            end
            return false
        end
        local button = kind == "Normal"
            and getMobileButton("JumpButton")
            or getMobileButton("PowerShoot")
        if not button then
            if showFailure then
                notify("TRS MobileCTRL shot button was not found.")
            end
            return false
        end

        nativeHeaderContext = nil
        nativeShotContext = {
            target = targetPosition,
            curve = curve,
            side = side,
            kind = kind,
        }
        lastShot = os.clock()
        local fired = false
        if kind == "Normal" then
            fired = fireNativeSignal(button.MouseButton1Down)
            if fired then
                task.delay(0.62, function()
                    if button.Parent then
                        fireNativeSignal(button.MouseButton1Up)
                    end
                end)
            end
        else
            fired = fireNativeSignal(button.MouseButton1Click)
        end
        if not fired then
            nativeShotContext = nil
            if showFailure then
                notify("The executor cannot fire native GUI signals.")
            end
            return false
        end
        local context = nativeShotContext
        task.delay(2, function()
            if nativeShotContext == context then
                nativeShotContext = nil
            end
        end)
        return true
    end

    local function connectShotKey(connectionName, keySetting, kind)
        disconnectFeatureConnection(connectionName)
        featureConnections[connectionName] = UserInputService.InputBegan:Connect(
            function(input, processed)
                if processed
                    or state.keyCaptureCallback
                    or UserInputService:GetFocusedTextBox() then
                    return
                end
                if input.UserInputType == Enum.UserInputType.Keyboard
                    and input.KeyCode == settings[keySetting] then
                    fireGoalShot(kind, true)
                end
            end
        )
    end

    local function toggleShootAssist(enabled)
        disconnectFeatureConnection("TRSShootKey")
        if enabled then
            connectShotKey("TRSShootKey", "shootKey", "Normal")
        end
    end

    local function togglePowerShot(enabled)
        disconnectFeatureConnection("TRSPowerShotKey")
        if enabled then
            connectShotKey("TRSPowerShotKey", "powerShotKey", "Power")
        end
    end

    local function toggleLongShot(enabled)
        disconnectFeatureConnection("TRSLongShotKey")
        if enabled then
            connectShotKey("TRSLongShotKey", "longShotKey", "Long")
        end
    end

    local function clearGoalVisual()
        if goalVisualObjects.folder then
            goalVisualObjects.folder:Destroy()
        end
        goalVisualObjects = {}
    end

    local function createGoalVisual()
        if goalVisualObjects.folder and goalVisualObjects.folder.Parent then
            return
        end

        local folder = Instance.new("Folder")
        folder.Name = "RTM_TRS_GoalVisual"
        folder.Parent = workspace
        local origin = Instance.new("Part")
        origin.Name = "RTM_TRS_GoalVisualOrigin"
        origin.Anchored = true
        origin.CanCollide = false
        origin.CanQuery = false
        origin.CanTouch = false
        origin.Transparency = 1
        origin.Size = Vector3.one * 0.1
        origin.Parent = folder

        local originAttachment = Instance.new("Attachment")
        originAttachment.Parent = origin
        local markers = {}
        local attachments = {}
        local billboards = {}
        local labels = {}
        for index = 1, 3 do
            local marker = Instance.new("Part")
            marker.Name = "RTM_TRS_GoalEntry" .. index
            marker.Anchored = true
            marker.CanCollide = false
            marker.CanQuery = false
            marker.CanTouch = false
            marker.CastShadow = false
            marker.Shape = Enum.PartType.Ball
            marker.Material = Enum.Material.Neon
            marker.Transparency = 1
            marker.Parent = folder
            local attachment = Instance.new("Attachment")
            attachment.Parent = marker
            local billboard = Instance.new("BillboardGui")
            billboard.Adornee = marker
            billboard.AlwaysOnTop = true
            billboard.Enabled = false
            billboard.Size = UDim2.fromOffset(100, 28)
            billboard.StudsOffset = Vector3.new(0, 2.1, 0)
            billboard.Parent = marker
            local label = Instance.new("TextLabel")
            label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            label.BackgroundTransparency = 0.2
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamBold
            label.Size = UDim2.fromScale(1, 1)
            label.TextColor3 = Color3.new(1, 1, 1)
            label.TextSize = 11
            label.Parent = billboard
            markers[index] = marker
            attachments[index] = attachment
            billboards[index] = billboard
            labels[index] = label
        end

        local beam = Instance.new("Beam")
        beam.Name = "RTM_TRS_GoalAimLine"
        beam.Attachment0 = originAttachment
        beam.Attachment1 = attachments[2]
        beam.FaceCamera = true
        beam.Segments = 24
        beam.Width0 = 0.09
        beam.Width1 = 0.05
        beam.Transparency = NumberSequence.new(0.16)
        beam.Parent = origin

        goalVisualObjects.folder = folder
        goalVisualObjects.origin = origin
        goalVisualObjects.markers = markers
        goalVisualObjects.attachments = attachments
        goalVisualObjects.billboards = billboards
        goalVisualObjects.labels = labels
        goalVisualObjects.beam = beam
    end

    local function hideGoalVisual()
        for _, marker in ipairs(goalVisualObjects.markers or {}) do
            marker.Transparency = 1
        end
        if goalVisualObjects.beam then
            goalVisualObjects.beam.Enabled = false
        end
        for _, billboard in ipairs(goalVisualObjects.billboards or {}) do
            billboard.Enabled = false
        end
    end

    local function toggleGoalTargetVisual(enabled)
        disconnectFeatureConnection("TRSGoalTargetVisual")
        clearGoalVisual()
        if not enabled then
            return
        end

        createGoalVisual()
        local elapsed = 1
        featureConnections.TRSGoalTargetVisual = RunService.Heartbeat:Connect(
            function(deltaTime)
                elapsed = elapsed + deltaTime
                if elapsed < 0.06 then
                    return
                end
                elapsed = 0

                local owner, ball = getBallOwner()
                local character, _, root = getCharacterParts()
                local goal = getOpponentGoal()
                if owner ~= LocalPlayer
                    or not ball
                    or not root
                    or not goal
                    or (root.Position - goal.Position).Magnitude
                        > settings.goalVisualRange then
                    hideGoalVisual()
                    return
                end

                local targetPosition, candidates, blocked = selectGoalTarget(
                    goal,
                    ball.Position,
                    settings.shootTargetHeight,
                    character
                )
                if not targetPosition then
                    hideGoalVisual()
                    return
                end

                local goalDistance = (root.Position - goal.Position).Magnitude

                goalVisualObjects.origin.Position = ball.Position
                local bestIndex = 1
                for index, position in ipairs(candidates) do
                    local isBest = (position - targetPosition).Magnitude < 0.1
                    if isBest then
                        bestIndex = index
                    end
                    local marker = goalVisualObjects.markers[index]
                    local billboard = goalVisualObjects.billboards[index]
                    local label = goalVisualObjects.labels[index]
                    local color = blocked[index]
                        and Color3.fromRGB(190, 55, 55)
                        or isBest and Color3.fromRGB(45, 190, 95)
                        or Color3.fromRGB(225, 175, 35)
                    marker.Position = position
                    marker.Size = Vector3.one * settings.goalVisualSize
                    marker.Color = color
                    marker.Transparency = isBest and 0.15 or 0.42
                    billboard.Enabled = true
                    label.Text = blocked[index] and "BLOCKED"
                        or isBest and "BEST"
                        or index == 1 and "LEFT"
                        or index == 2 and "CENTER"
                        or "RIGHT"
                    label.TextColor3 = color
                end
                goalVisualObjects.beam.Attachment1 =
                    goalVisualObjects.attachments[bestIndex]
                goalVisualObjects.beam.Enabled = settings.goalVisualLine
                goalVisualObjects.beam.Color = ColorSequence.new(
                    goalDistance <= settings.shootGoalRange
                        and Color3.fromRGB(45, 190, 95)
                        or Color3.fromRGB(225, 175, 35)
                )
                goalVisualObjects.beam.CurveSize0 = settings.goalVisualCurve
                goalVisualObjects.beam.CurveSize1 = -settings.goalVisualCurve
            end
        )
    end

    local function performAssistedPass(showFailure)
        local owner, ball = getBallOwner()
        local character, humanoid, root = getCharacterParts()
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local passRemote = remotes and remotes:FindFirstChild("Pass")
        if owner ~= LocalPlayer
            or not ball
            or not character
            or not humanoid
            or not root
            or localActionBlocked(character, false)
            or isLocalGoalkeeper(getWorldBools())
            or not passRemote
            or not passRemote:IsA("RemoteEvent")
            or os.clock() - lastPass < 0.7 then
            return false
        end

        local grabTick = character:FindFirstChild("GrabTick")
        if grabTick
            and tonumber(grabTick.Value)
            and tick() - grabTick.Value <= 0.35 then
            return false
        end

        local target = getBestPassTarget(root)
        if not target then
            if showFailure then
                notify("Pass Assist: no safe teammate was found.")
            end
            return false
        end

        lastPass = os.clock()
        passRemote:FireServer(target, ball.CFrame)
        return true
    end

    local function togglePassAssist(enabled)
        disconnectFeatureConnection("TRSPassKey")
        disconnectFeatureConnection("TRSPassPressure")
        if not enabled then
            return
        end

        featureConnections.TRSPassKey = UserInputService.InputBegan:Connect(
            function(input, processed)
                if processed
                    or state.keyCaptureCallback
                    or UserInputService:GetFocusedTextBox() then
                    return
                end
                if input.UserInputType == Enum.UserInputType.Keyboard
                    and input.KeyCode == settings.passKey then
                    performAssistedPass(true)
                end
            end
        )

        local elapsed = 1
        featureConnections.TRSPassPressure = RunService.Heartbeat:Connect(
            function(deltaTime)
                if settings.passMode ~= "Under pressure" then
                    return
                end
                elapsed = elapsed + deltaTime
                if elapsed < 0.08 then
                    return
                end
                elapsed = 0

                local owner = getBallOwner()
                local _, _, root = getCharacterParts()
                if owner ~= LocalPlayer or not root then
                    return
                end
                local threat, distance = findDribbleThreat(
                    root,
                    settings.passPressureRange,
                    true
                )
                if threat and distance <= settings.passPressureRange then
                    performAssistedPass(false)
                end
            end
        )
    end

    local function getPickupRemote()
        if pickupRemote and pickupRemote.Parent then
            return pickupRemote
        end
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        if not remotes then
            return nil
        end
        for _, remote in ipairs(remotes:GetChildren()) do
            if remote:IsA("RemoteEvent")
                and remote:GetAttribute("Attribute") ~= nil then
                pickupRemote = remote
            end
        end
        return pickupRemote
    end

    local function performAutoPickup(showFailure)
        local ball = getBall()
        local character, humanoid, root = getCharacterParts()
        local worldBools = getWorldBools()
        local remote = getPickupRemote()
        if not ball
            or ball:FindFirstChild("playerWeld")
            or not character
            or not humanoid
            or humanoid.Health <= 0
            or not root
            or isLocalGoalkeeper(worldBools)
            or boolEnabled(worldBools, "cantGrab")
            or boolEnabled(worldBools, "Penalty")
            or localActionBlocked(character, false)
            or not remote
            or os.clock() - lastPickup < settings.pickupDelay then
            return false
        end

        local offset = ball.Position - root.Position
        local distance = offset.Magnitude
        if distance > settings.pickupReach
            or offset.Y > settings.pickupMaxHeight then
            if showFailure then
                notify("Auto Pickup: the ball is outside the configured reach or height.")
            end
            return false
        end

        lastPickup = os.clock()
        local grabTick = character:FindFirstChild("GrabTick")
        if grabTick and grabTick:IsA("NumberValue") then
            grabTick.Value = tick()
        end
        remote:FireServer(
            math.min(distance, settings.pickupReportedDistance)
        )

        if settings.pickupDeke then
            task.delay(0.06, function()
                local owner = getBallOwner()
                local currentCharacter = LocalPlayer.Character
                local localBools = currentCharacter
                    and currentCharacter:FindFirstChild("Bools")
                local remotes = game:GetService("ReplicatedStorage")
                    :FindFirstChild("Remotes")
                local action = remotes and remotes:FindFirstChild("Action")
                if owner == LocalPlayer
                    and not boolEnabled(localBools, "dribbleDebounce")
                    and action
                    and action:IsA("RemoteEvent") then
                    action:FireServer("Deke")
                end
            end)
        end
        return true
    end

    local function toggleAutoPickup(enabled)
        disconnectFeatureConnection("TRSPickupKey")
        disconnectFeatureConnection("TRSPickupLoop")
        if not enabled then
            return
        end

        featureConnections.TRSPickupKey = UserInputService.InputBegan:Connect(
            function(input, processed)
                if processed
                    or state.keyCaptureCallback
                    or UserInputService:GetFocusedTextBox() then
                    return
                end
                if input.UserInputType == Enum.UserInputType.Keyboard
                    and input.KeyCode == settings.pickupKey then
                    performAutoPickup(true)
                end
            end
        )

        local elapsed = 1
        featureConnections.TRSPickupLoop = RunService.Heartbeat:Connect(
            function(deltaTime)
                if settings.pickupMode ~= "Automatic" then
                    return
                end
                elapsed = elapsed + deltaTime
                if elapsed >= 0.05 then
                    elapsed = 0
                    performAutoPickup(false)
                end
            end
        )
    end

    local function clearTrajectory()
        for _, part in ipairs(trajectoryParts) do
            if part then
                part:Destroy()
            end
        end
        trajectoryParts = {}
        if landingMarker then
            landingMarker:Destroy()
            landingMarker = nil
        end
    end

    local function getTrajectoryPart(index)
        if trajectoryParts[index] then
            return trajectoryParts[index]
        end
        local part = Instance.new("Part")
        part.Name = "RTM_TRS_Trajectory"
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(35, 190, 155)
        part.Transparency = 0.2
        part.Size = Vector3.new(0.08, 0.08, 1)
        part.Parent = workspace
        trajectoryParts[index] = part
        return part
    end

    local function toggleTrajectory(enabled)
        disconnectFeatureConnection("TRSTrajectory")
        clearTrajectory()
        if not enabled then
            return
        end

        local elapsed = 1
        featureConnections.TRSTrajectory = RunService.Heartbeat:Connect(
            function(deltaTime)
                elapsed = elapsed + deltaTime
                if elapsed < 0.08 then
                    return
                end
                elapsed = 0

                local ball = getBall()
                if not ball then
                    for _, part in ipairs(trajectoryParts) do
                        part.Transparency = 1
                    end
                    if landingMarker then
                        landingMarker.Transparency = 1
                    end
                    return
                end

                local velocity = ball.AssemblyLinearVelocity
                local position = ball.Position
                local gravity = Vector3.new(0, -workspace.Gravity, 0)
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                local excluded = {ball}
                if LocalPlayer.Character then
                    table.insert(excluded, LocalPlayer.Character)
                end
                rayParams.FilterDescendantsInstances = excluded
                rayParams.IgnoreWater = true

                local steps = 20
                local stepTime = settings.trajectoryTime / steps
                local hitPosition = nil
                local used = 0
                for index = 1, steps do
                    local timeValue = index * stepTime
                    local nextPosition = ball.Position
                        + velocity * timeValue
                        + gravity * (0.5 * timeValue * timeValue)
                    local result = workspace:Raycast(
                        position,
                        nextPosition - position,
                        rayParams
                    )
                    if result then
                        nextPosition = result.Position
                        hitPosition = result.Position
                    end

                    local segment = getTrajectoryPart(index)
                    local distance = (nextPosition - position).Magnitude
                    segment.Transparency = 0.2
                    segment.Size = Vector3.new(0.08, 0.08, math.max(distance, 0.05))
                    segment.CFrame = CFrame.lookAt(
                        (position + nextPosition) / 2,
                        nextPosition
                    )
                    used = index
                    position = nextPosition
                    if result then
                        break
                    end
                end
                for index = used + 1, #trajectoryParts do
                    trajectoryParts[index].Transparency = 1
                end

                if not landingMarker then
                    landingMarker = Instance.new("Part")
                    landingMarker.Name = "RTM_TRS_LandingPoint"
                    landingMarker.Anchored = true
                    landingMarker.CanCollide = false
                    landingMarker.CanQuery = false
                    landingMarker.CanTouch = false
                    landingMarker.CastShadow = false
                    landingMarker.Shape = Enum.PartType.Cylinder
                    landingMarker.Material = Enum.Material.Neon
                    landingMarker.Color = Color3.fromRGB(235, 185, 40)
                    landingMarker.Size = Vector3.new(0.12, 3, 3)
                    landingMarker.Parent = workspace
                end
                landingMarker.Transparency = hitPosition and 0.35 or 1
                if hitPosition then
                    landingMarker.CFrame = CFrame.new(hitPosition + Vector3.new(0, 0.08, 0))
                        * CFrame.Angles(0, 0, math.rad(90))
                end
            end
        )
    end

    local function toggleGoalkeeperAssist(enabled)
        disconnectFeatureConnection("TRSGoalkeeper")
        if not enabled then
            return
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local action = remotes and remotes:FindFirstChild("Action")
        featureConnections.TRSGoalkeeper = RunService.Heartbeat:Connect(function()
            local ball = getBall()
            local character, humanoid, root = getCharacterParts()
            local worldBools = getWorldBools()
            local ownGoal = getOwnGoal()
            if not isLocalGoalkeeper(worldBools)
                or not ball
                or not character
                or not humanoid
                or not root
                or not ownGoal
                or not action
                or not action:IsA("RemoteEvent")
                or getBallOwner() == LocalPlayer
                or os.clock() - lastGoalkeeperAction < 1.1 then
                return
            end

            local distance = (ball.Position - root.Position).Magnitude
            local velocity = ball.AssemblyLinearVelocity
            local speed = velocity.Magnitude
            if distance > settings.goalkeeperRange
                or speed < settings.goalkeeperMinSpeed
                or (root.Position - ball.Position):Dot(velocity) <= 0
                or (ownGoal.Position - ball.Position):Dot(velocity) <= 0 then
                return
            end

            local travelTime = math.clamp(distance / speed, 0.05, 0.65)
            local predicted = ball.Position
                + velocity * travelTime
                + Vector3.new(
                    0,
                    -0.5 * workspace.Gravity * travelTime * travelTime,
                    0
                )
            local localPoint = root.CFrame:PointToObjectSpace(predicted)
            if math.abs(localPoint.X) > 13
                or localPoint.Y < -2
                or localPoint.Y > 11 then
                return
            end
            lastGoalkeeperAction = os.clock()
            if localPoint.Y >= settings.goalkeeperHighBall
                and math.abs(localPoint.X) < 4 then
                action:FireServer("GKJump")
            elseif localPoint.X > 2 then
                action:FireServer("RightDive", root.CFrame)
            elseif localPoint.X < -2 then
                action:FireServer("LeftDive", root.CFrame)
            else
                action:FireServer("FrontDive")
            end
        end)
    end

    local function toggleAutoHeader(enabled)
        disconnectFeatureConnection("TRSAutoHeader")
        if not enabled then
            nativeHeaderContext = nil
            return
        end

        featureConnections.TRSAutoHeader = RunService.Heartbeat:Connect(function()
            local owner, ball = getBallOwner()
            local character, humanoid, root = getCharacterParts()
            local worldBools = getWorldBools()
            local opponentGoal = getOpponentGoal()
            local ownGoal = getOwnGoal()
            if not ball
                or owner == LocalPlayer
                or not character
                or not humanoid
                or not root
                or not opponentGoal
                or not ownGoal
                or isLocalGoalkeeper(worldBools)
                or os.clock() - lastHeaderAction < 1.1
                or localActionBlocked(character, false) then
                return
            end

            local distance = (ball.Position - root.Position).Magnitude
            local relativeHeight = ball.Position.Y - root.Position.Y
            local attacking = (root.Position - opponentGoal.Position).Magnitude
                <= settings.headerGoalRange
            local defending = (root.Position - ownGoal.Position).Magnitude
                <= settings.headerGoalRange
            if distance > settings.headerRange
                or relativeHeight < 1.2
                or relativeHeight > 9
                or (not attacking and not defending) then
                return
            end

            local targetPosition = nil
            if defending then
                local teammate = getBestPassTarget(root)
                local teammateRoot = teammate
                    and teammate.Character
                    and teammate.Character:FindFirstChild("HumanoidRootPart")
                if teammateRoot then
                    targetPosition = teammateRoot.Position
                        + teammateRoot.AssemblyLinearVelocity * 0.15
                end
            else
                targetPosition = selectGoalTarget(
                    opponentGoal,
                    ball.Position,
                    settings.shootTargetHeight,
                    character
                )
            end
            if not targetPosition or not installShotHook() then
                return
            end

            local localPoint = root.CFrame:PointToObjectSpace(targetPosition)
            local side = localPoint.X >= 0 and "Right" or "Left"
            nativeShotContext = nil
            nativeHeaderContext = {
                target = targetPosition,
                curve = side,
                side = side,
                kind = "Header",
            }
            local button = getMobileButton("Header")
            if not button or not fireNativeSignal(button.MouseButton1Click) then
                nativeHeaderContext = nil
                return
            end
            lastHeaderAction = os.clock()
            local context = nativeHeaderContext
            task.delay(2, function()
                if nativeHeaderContext == context then
                    nativeHeaderContext = nil
                end
            end)
        end)
    end

    local TackleFeature = createUniversalFeature(
        "Auto Tackle",
        "Track only the ball carrier, face them, tackle, and retry the steal",
        1,
        toggleAutoTackle,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(TackleFeature, "Reach", 8, 3, 16, function(value)
        settings.tackleRange = value
    end)
    addNumberOption(TackleFeature, "Movement prediction", 0.12, 0, 0.3, function(value)
        settings.tackleLead = value
    end)
    addToggleOption(TackleFeature, "Aimlock", true, function(value)
        settings.tackleAimlock = value
    end)
    addToggleOption(TackleFeature, "Show carrier", true, function(value)
        settings.tackleBox = value
        if not value then
            clearTackleBox()
        end
    end)
    addToggleOption(TackleFeature, "Opponents only", true, function(value)
        settings.opponentsOnly = value
    end)
    addInformationOption(
        TackleFeature,
        "Reach: 3-16 studs. Prediction: 0-0.30 s. Recommended: 8 / 0.12."
    )

    local DribbleFeature = createUniversalFeature(
        "Auto Dribble",
        "React to real tackles and predict fast incoming tackle attempts",
        2,
        toggleAutoDribble,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(DribbleFeature, "Reaction reach", 10, 4, 16, function(value)
        settings.dribbleRange = value
    end)
    addNumberOption(DribbleFeature, "Prediction time", 0.18, 0, 0.35, function(value)
        settings.dribblePrediction = value
    end)
    addToggleOption(DribbleFeature, "Predict incoming tackles", true, function(value)
        settings.dribblePreempt = value
    end)
    addCycleOption(
        DribbleFeature,
        "Style",
        {"Normal", "Assist"},
        1,
        function(value)
            settings.dribbleStyle = value
        end
    )
    addInformationOption(
        DribbleFeature,
        "Normal uses the original Deke. Assist passes to a safe teammate. Orange box = incoming tackle."
    )

    local PickupFeature = createUniversalFeature(
        "Auto Pickup",
        "Use TRS's pickup remote for nearby loose balls with height and delay limits",
        3,
        toggleAutoPickup,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addCycleOption(
        PickupFeature,
        "Mode",
        {"Automatic", "Manual"},
        1,
        function(value)
            settings.pickupMode = value
        end
    )
    addKeyOption(PickupFeature, "Pickup key", settings.pickupKey, function(value)
        settings.pickupKey = value
    end)
    addNumberOption(PickupFeature, "Pickup reach", 18, 3, 180, function(value)
        settings.pickupReach = value
    end)
    addNumberOption(PickupFeature, "Maximum ball height", 12, 2, 50, function(value)
        settings.pickupMaxHeight = value
    end)
    addNumberOption(PickupFeature, "Reported distance", 2.8, 0.5, 10, function(value)
        settings.pickupReportedDistance = value
    end)
    addNumberOption(PickupFeature, "Fire delay", 0.1, 0.05, 0.5, function(value)
        settings.pickupDelay = value
    end)
    addToggleOption(PickupFeature, "Deke after pickup", true, function(value)
        settings.pickupDeke = value
    end)
    addInformationOption(
        PickupFeature,
        "Reach: 3-180. Height: 2-50. Reported distance: 0.5-10. Delay: 0.05-0.50 s."
    )

    local PassFeature = createUniversalFeature(
        "Pass Assist",
        "Choose a safe forward teammate manually or when a tackle is incoming",
        4,
        togglePassAssist,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addCycleOption(
        PassFeature,
        "Mode",
        {"Manual", "Under pressure"},
        1,
        function(value)
            settings.passMode = value
        end
    )
    addKeyOption(PassFeature, "Pass key", settings.passKey, function(value)
        settings.passKey = value
    end)
    addNumberOption(PassFeature, "Maximum pass range", 150, 30, 190, function(value)
        settings.passRange = value
    end)
    addNumberOption(PassFeature, "Pressure reach", 9, 4, 15, function(value)
        settings.passPressureRange = value
    end)
    addToggleOption(PassFeature, "Forward teammates only", true, function(value)
        settings.passForwardOnly = value
    end)
    addToggleOption(PassFeature, "Maximum power", false, toggleMaxPower)
    addNumberOption(PassFeature, "Maximum power value", 1, 0.85, 1, function(value)
        settings.powerValue = value
    end)
    addInformationOption(
        PassFeature,
        "Pass range: 30-190. Pressure: 4-15. Maximum power affects your normal shots."
    )

    local ShootFeature = createUniversalFeature(
        "Shoot Assist",
        "Use TRS's native mobile shot and redirect only its target and curve",
        5,
        toggleShootAssist,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addKeyOption(ShootFeature, "Shot key", settings.shootKey, function(value)
        settings.shootKey = value
    end)
    addNumberOption(ShootFeature, "Goal range", 120, 60, 180, function(value)
        settings.shootGoalRange = value
    end)
    addInformationOption(
        ShootFeature,
        "Range: 60-180 studs. Key: G. Native charge/release; only aim and curve are changed."
    )

    local PowerShotFeature = createUniversalFeature(
        "Power Shot",
        "Full-power curved shot from a practical attacking distance",
        6,
        togglePowerShot,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addKeyOption(PowerShotFeature, "Power shot key", settings.powerShotKey, function(value)
        settings.powerShotKey = value
    end)
    addNumberOption(PowerShotFeature, "Goal range", 120, 50, 180, function(value)
        settings.powerShotRange = value
    end)
    addInformationOption(
        PowerShotFeature,
        "Range: 50-180 studs. Key: T. Activates TRS's native mobile PowerShoot button."
    )

    local LongShotFeature = createUniversalFeature(
        "Large Shoot",
        "Activate the native mobile PowerShoot and redirect it from any distance",
        7,
        toggleLongShot,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addKeyOption(LongShotFeature, "Long shot key", settings.longShotKey, function(value)
        settings.longShotKey = value
    end)
    addInformationOption(
        LongShotFeature,
        "Key: R. No artificial bar check; the native PowerShoot callback controls the shot."
    )

    local GoalVisualFeature = createUniversalFeature(
        "Best Goal Visual",
        "Show left, center, and right entries; prefer the clearest side away from the keeper",
        8,
        toggleGoalTargetVisual,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(GoalVisualFeature, "Display range", 100, 25, 180, function(value)
        settings.goalVisualRange = value
    end)
    addNumberOption(GoalVisualFeature, "Target margin size", 2.5, 0.5, 6, function(value)
        settings.goalVisualSize = value
    end)
    addNumberOption(GoalVisualFeature, "Visual curve", 5, -20, 20, function(value)
        settings.goalVisualCurve = value
    end)
    addToggleOption(GoalVisualFeature, "Show aim line", true, function(value)
        settings.goalVisualLine = value
    end)
    addInformationOption(
        GoalVisualFeature,
        "Range: 25-180. Margin: 0.5-6. Curve: -20 to 20. Green means a clear shot."
    )

    local TrajectoryFeature = createUniversalFeature(
        "Ball Trajectory",
        "Show the predicted flight path and first landing point",
        9,
        toggleTrajectory,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(TrajectoryFeature, "Prediction time", 2.4, 0.8, 4, function(value)
        settings.trajectoryTime = value
    end)
    addInformationOption(
        TrajectoryFeature,
        "Prediction window: 0.8-4.0 seconds. Twenty reusable segments prevent FPS drops."
    )

    local GoalkeeperFeature = createUniversalFeature(
        "Goalkeeper Assist",
        "Predict shots toward your own goal and choose Dive, FrontDive, or GKJump",
        10,
        toggleGoalkeeperAssist,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(GoalkeeperFeature, "Assist range", 32, 12, 45, function(value)
        settings.goalkeeperRange = value
    end)
    addNumberOption(GoalkeeperFeature, "Minimum ball speed", 8, 4, 30, function(value)
        settings.goalkeeperMinSpeed = value
    end)
    addNumberOption(GoalkeeperFeature, "High ball height", 5, 3, 9, function(value)
        settings.goalkeeperHighBall = value
    end)
    addInformationOption(
        GoalkeeperFeature,
        "Range: 12-45 studs. Ball speed: 4-30. High threshold: 3-9 studs."
    )

    local HeaderFeature = createUniversalFeature(
        "Auto Header",
        "Use the native mobile Header; near your own goal redirect it to a teammate",
        11,
        toggleAutoHeader,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(HeaderFeature, "Ball reach", 7, 3, 10, function(value)
        settings.headerRange = value
    end)
    addNumberOption(HeaderFeature, "Goal activation range", 50, 25, 60, function(value)
        settings.headerGoalRange = value
    end)
    addInformationOption(
        HeaderFeature,
        "Ball reach: 3-10. Goal zone: 25-60. PassBV remains controlled by the native button."
    )

    state.cleanupTRSRuntime = function()
        settings.power = false
        nativeShotContext = nil
        nativeHeaderContext = nil
        disconnectFeatureConnection("TRSAutoTackle")
        disconnectFeatureConnection("TRSAutoDribble")
        disconnectFeatureConnection("TRSPickupKey")
        disconnectFeatureConnection("TRSPickupLoop")
        disconnectFeatureConnection("TRSPassKey")
        disconnectFeatureConnection("TRSPassPressure")
        disconnectFeatureConnection("TRSShootKey")
        disconnectFeatureConnection("TRSPowerShotKey")
        disconnectFeatureConnection("TRSLongShotKey")
        disconnectFeatureConnection("TRSTrajectory")
        disconnectFeatureConnection("TRSGoalTargetVisual")
        disconnectFeatureConnection("TRSGoalkeeper")
        disconnectFeatureConnection("TRSAutoHeader")
        clearTackleBox()
        clearDribbleBox()
        clearTrajectory()
        clearGoalVisual()
    end
end

if GAME_CHECK.TRSActive then
    SectionManager.register("TRS", buildTRSFeatures)
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local query = string.lower(SearchBox.Text)
    for _, feature in ipairs(allFeatures) do
        local searchable = string.lower(feature.name .. " " .. feature.description)
        for _, object in ipairs(feature.row:GetDescendants()) do
            if object:IsA("TextLabel") then
                searchable = searchable .. " " .. string.lower(object.Text)
            end
        end
        feature.row.Visible = query == ""
            or string.find(searchable, query, 1, true) ~= nil
    end
end)

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

local SettingsLayout = create("UIListLayout", {
    Parent = SettingsScroll,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local function createSettingRow(titleText, descriptionText, height)
    local row = create("Frame", {
        Parent = SettingsScroll,
        BackgroundColor3 = Color3.fromRGB(31, 31, 31),
        BorderColor3 = DEFAULT_BORDER_COLOR,
        BorderSizePixel = 1,
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

    return row, control
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

local BlurButton = makeButton(blurControl, state.blurEnabled and "ON" or "OFF", 13)
BlurButton.Size = UDim2.fromScale(1, 1)
BlurButton:SetAttribute("Selected", state.blurEnabled)
BlurButton.BackgroundColor3 = state.blurEnabled
    and state.headerColor
    or DEFAULT_SURFACE_COLOR

local keyRow, keyControl = createSettingRow(
    "Menu key",
    "Choose the key used to show or hide"
)
keyRow.LayoutOrder = 3

local KeybindButton = makeButton(keyControl, state.toggleKey.Name, 13)
KeybindButton.Size = UDim2.fromScale(1, 1)
state.keybindButton = KeybindButton

local headerColorRow, headerColorControl = createSettingRow(
    "Header color",
    "RGB color for the top bar",
    70
)
headerColorRow.LayoutOrder = 4

local headerInputs = {}
for index, value in ipairs(colorToConfig(state.headerColor)) do
    local box = makeTextBox(headerColorControl, value)
    box.Name = ({"R", "G", "B"})[index]
    box.Position = UDim2.new((index - 1) * 0.18, 0, 0, 0)
    box.Size = UDim2.new(0.16, 0, 1, 0)
    box.PlaceholderText = box.Name
    headerInputs[index] = box
end

local ApplyHeaderColor = makeButton(headerColorControl, "APPLY", 12)
ApplyHeaderColor.Position = UDim2.new(0.58, 0, 0, 0)
ApplyHeaderColor.Size = UDim2.new(0.42, 0, 1, 0)

local menuColorRow, menuColorControl = createSettingRow(
    "Menu color",
    "RGB color for the dark main panel",
    70
)
menuColorRow.LayoutOrder = 5

local menuInputs = {}
for index, value in ipairs(colorToConfig(state.menuColor)) do
    local box = makeTextBox(menuColorControl, value)
    box.Name = ({"R", "G", "B"})[index]
    box.Position = UDim2.new((index - 1) * 0.18, 0, 0, 0)
    box.Size = UDim2.new(0.16, 0, 1, 0)
    box.PlaceholderText = box.Name
    menuInputs[index] = box
end

local ApplyMenuColor = makeButton(menuColorControl, "APPLY", 12)
ApplyMenuColor.Position = UDim2.new(0.58, 0, 0, 0)
ApplyMenuColor.Size = UDim2.new(0.42, 0, 1, 0)

local resetRow, resetControl = createSettingRow(
    "Reset appearance",
    "Restore the default grey and dark blue colors"
)
resetRow.LayoutOrder = 6

local ResetButton = makeButton(resetControl, "RESET", 13)
ResetButton.Size = UDim2.fromScale(1, 1)

local gameRow, gameControl = createSettingRow(
    "Game check",
    "Only the matching game-specific module is loaded"
)
gameRow.LayoutOrder = 7
local gameStatus = makeTextLabel(
    gameControl,
    GAME_CHECK.MM2Active and "MM2 · 142823291"
        or GAME_CHECK.TRSActive and "TRS · 14315258385"
        or "Universal only",
    12
)
gameStatus.TextXAlignment = Enum.TextXAlignment.Center
gameStatus.Size = UDim2.fromScale(1, 1)

local helpText = makeTextLabel(
    SettingsScroll,
    "Build 0001-S7 | Active game module: "
        .. (GAME_CHECK.MM2Active and "MM2"
            or GAME_CHECK.TRSActive and "TRS"
            or "Universal")
        .. " | Drag the header to move and any border to resize.",
    11
)
helpText.LayoutOrder = 8
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

local function setMenuVisible(visible)
    state.visible = visible
    Main.Visible = visible
    setBlurVisible(true)
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

BlurButton.MouseButton1Click:Connect(function()
    state.blurEnabled = not state.blurEnabled
    BlurButton.Text = state.blurEnabled and "ON" or "OFF"
    BlurButton:SetAttribute("Selected", state.blurEnabled)
    BlurButton.BackgroundColor3 = state.blurEnabled
        and state.headerColor
        or DEFAULT_SURFACE_COLOR
    setBlurVisible(true)
    configData.ui.blurEnabled = state.blurEnabled
    queueConfigSave()
end)

KeybindButton.MouseButton1Click:Connect(function()
    state.waitingForKey = true
    KeybindButton.Text = "PRESS A KEY..."
    KeybindButton.BackgroundColor3 = state.headerColor
end)

local function clampColorNumber(value)
    return math.clamp(math.floor(tonumber(value) or 0), 0, 255)
end

local function colorFromInputs(inputs)
    return Color3.fromRGB(
        clampColorNumber(inputs[1].Text),
        clampColorNumber(inputs[2].Text),
        clampColorNumber(inputs[3].Text)
    )
end

local function writeColorInputs(inputs, color)
    inputs[1].Text = tostring(math.round(color.R * 255))
    inputs[2].Text = tostring(math.round(color.G * 255))
    inputs[3].Text = tostring(math.round(color.B * 255))
end

local function applyHeaderColor(color)
    state.headerColor = color
    configData.ui.headerColor = colorToConfig(color)
    queueConfigSave()
    Header.BackgroundColor3 = color

    for tabName, button in pairs(tabButtons) do
        if tabName == state.activeTab then
            button.BackgroundColor3 = color
        end
    end

    if state.blurEnabled then
        BlurButton.BackgroundColor3 = color
    end

    if state.largeText then
        TextSizeButton.BackgroundColor3 = color
    end

    if state.waitingForKey then
        KeybindButton.BackgroundColor3 = color
    end

    for _, feature in ipairs(allFeatures) do
        if feature.enabled then
            feature.toggle.BackgroundColor3 = color
        end
    end
end

local function applyMenuColor(color)
    state.menuColor = color
    configData.ui.menuColor = colorToConfig(color)
    queueConfigSave()
    Main.BackgroundColor3 = color
    Content.BackgroundColor3 = color

    for _, page in pairs(pages) do
        page.BackgroundColor3 = color
    end
end

ApplyHeaderColor.MouseButton1Click:Connect(function()
    applyHeaderColor(colorFromInputs(headerInputs))
end)

ApplyMenuColor.MouseButton1Click:Connect(function()
    applyMenuColor(colorFromInputs(menuInputs))
end)

ResetButton.MouseButton1Click:Connect(function()
    applyHeaderColor(DEFAULT_HEADER_COLOR)
    applyMenuColor(DEFAULT_MENU_COLOR)
    writeColorInputs(headerInputs, DEFAULT_HEADER_COLOR)
    writeColorInputs(menuInputs, DEFAULT_MENU_COLOR)
end)
end

SectionManager.register("Config.", buildSettings)

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
            MINIMUM_SIZE.X,
            math.min(MAXIMUM_SIZE.X, screenSize.X)
        )
    elseif string.find(mode, "left", 1, true) then
        newWidth = math.clamp(
            startSize.X - delta.X,
            MINIMUM_SIZE.X,
            math.min(MAXIMUM_SIZE.X, screenSize.X)
        )
        newX = startPosition.X + (startSize.X - newWidth)
    end

    if string.find(mode, "bottom", 1, true) then
        newHeight = math.clamp(
            startSize.Y + delta.Y,
            MINIMUM_SIZE.Y,
            math.min(MAXIMUM_SIZE.Y, screenSize.Y)
        )
    elseif string.find(mode, "top", 1, true) then
        newHeight = math.clamp(
            startSize.Y - delta.Y,
            MINIMUM_SIZE.Y,
            math.min(MAXIMUM_SIZE.Y, screenSize.Y)
        )
        newY = startPosition.Y + (startSize.Y - newHeight)
    end

    newX = math.clamp(newX, 0, math.max(0, screenSize.X - newWidth))
    newY = math.clamp(newY, 0, math.max(0, screenSize.Y - newHeight))

    Main.Position = UDim2.fromOffset(newX, newY)
    Main.Size = UDim2.fromOffset(newWidth, newHeight)
end

local GlobalInputChangedConnection = UserInputService.InputChanged:Connect(function(input)
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

local GlobalInputBeganConnection = UserInputService.InputBegan:Connect(function(input)
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
        for _, connection: RBXScriptConnection in ipairs(tooltipConnections) do
            connection:Disconnect()
        end
        table.clear(tooltipConnections)

        if GlobalInputChangedConnection then
            GlobalInputChangedConnection:Disconnect()
        end
        if GlobalInputBeganConnection then
            GlobalInputBeganConnection:Disconnect()
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

setTab("Universal")
if state.setBlurVisible then
    state.setBlurVisible(false)
end
task.defer(saveConfigNow)

print(
    "A random Testing Menu # 0001 | Build 0001-S7 | Toggle key: "
        .. state.toggleKey.Name
)
