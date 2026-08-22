--!strict

--[[
    Complete standalone presentation kernel for A Random Menu.
    Game modules only need to call createModule() and add their controls.
]]

local executorEnvironment: any = getfenv()
local cloneReference: (Instance) -> Instance = (
    executorEnvironment.cloneref
    or function(instance: Instance): Instance
        return instance
    end
) :: (Instance) -> Instance

local Players: Players = cloneReference(game:GetService("Players")) :: Players
local UserInputService: UserInputService =
    cloneReference(game:GetService("UserInputService")) :: UserInputService
local TweenService: TweenService =
    cloneReference(game:GetService("TweenService")) :: TweenService
local Lighting: Lighting = cloneReference(game:GetService("Lighting")) :: Lighting
local HttpService: HttpService =
    cloneReference(game:GetService("HttpService")) :: HttpService

local RAW_BASE: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/"
local CACHE_ROOT: string = "ARandomMenu/Assets"
local RUNTIME_COMPATIBILITY_MARKER: string =
    "Initialization error — check executor console"
local RUNTIME_SAFETY_SOURCE_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/4b10e4bfe00aa356afb3e0420a72e745327f6259/ARandomMenu.luau"

export type Theme = {
    Background: Color3,
    Surface: Color3,
    SurfaceHover: Color3,
    SurfaceActive: Color3,
    Accent: Color3,
    Text: Color3,
    MutedText: Color3,
    Outline: Color3,
}

export type AssetSource = {
    url: string,
    fileName: string,
    fallback: string,
}

export type GuiOptions = {
    name: string?,
    title: string?,
    initiallyVisible: boolean?,
    parent: Instance?,
    reinjectUrl: string?,
}

export type FeatureController = {
    row: Frame,
    options: Frame,
    enabled: boolean,
    expanded: boolean,
    addSlider: (
        self: FeatureController,
        label: string,
        minimum: number,
        maximum: number,
        initial: number,
        callback: (number) -> ()
    ) -> (),
    addKeybind: (
        self: FeatureController,
        label: string,
        initial: Enum.KeyCode,
        callback: (Enum.KeyCode) -> ()
    ) -> TextButton,
    setEnabled: (self: FeatureController, enabled: boolean) -> (),
    setExpanded: (self: FeatureController, expanded: boolean) -> (),
}

export type ModuleController = {
    id: string,
    page: ScrollingFrame,
    addToggle: (
        self: ModuleController,
        id: string,
        label: string,
        description: string,
        callback: (boolean) -> ()
    ) -> FeatureController,
    addAction: (
        self: ModuleController,
        id: string,
        label: string,
        description: string,
        callback: () -> ()
    ) -> FeatureController,
}

export type GuiController = {
    screenGui: ScreenGui,
    window: Frame,
    content: Frame,
    modules: {[string]: ModuleController},
    pages: {[string]: ScrollingFrame},
    tabButtons: {[string]: TextButton},
    connections: {RBXScriptConnection},
    featureConnections: {RBXScriptConnection},
    activeTab: string?,
    visible: boolean,
    textScale: number,
    blurEnabled: boolean,
    createModule: (
        self: GuiController,
        id: string,
        label: string,
        layoutOrder: number
    ) -> ModuleController,
    setTab: (self: GuiController, id: string) -> (),
    setTabIcon: (self: GuiController, id: string, assetKey: string) -> (),
    setTextScale: (self: GuiController, scale: number) -> (),
    setVisible: (self: GuiController, visible: boolean) -> (),
    destroy: (self: GuiController) -> (),
}

local THEME: Theme = table.freeze({
    Background = Color3.fromRGB(0, 0, 0),
    Surface = Color3.fromRGB(15, 15, 17),
    SurfaceHover = Color3.fromRGB(29, 29, 33),
    SurfaceActive = Color3.fromRGB(37, 37, 42),
    Accent = Color3.fromRGB(236, 236, 240),
    Text = Color3.fromRGB(246, 246, 248),
    MutedText = Color3.fromRGB(156, 156, 164),
    Outline = Color3.fromRGB(82, 82, 90),
})

-- Every image used by this GUI is visible here. Custom art is downloaded from
-- GitHub and converted with getcustomasset/getsynasset. The Roblox asset IDs
-- are explicit fallbacks for executors without a file asset API.
local ASSETS: {[string]: AssetSource} = table.freeze({
    Header = {
        url = RAW_BASE .. "src/gui/Current/Assets/Header/anime-header.jpg",
        fileName = "anime-header-v1.jpg",
        fallback = "rbxassetid://6031091002",
    },
    CosmicControls = {
        url = RAW_BASE
            .. "src/gui/Current/Assets/Source/cosmic-controls-sheet.png",
        fileName = "cosmic-controls-sheet-v1.png",
        fallback = "rbxassetid://6031094678",
    },
    KeybindPill = {
        url = RAW_BASE .. "src/gui/Current/Assets/Frames/keybind-pill-hd.png",
        fileName = "keybind-pill-hd-v1.png",
        fallback = "",
    },
    MobileToggle = {
        url = RAW_BASE .. "src/gui/Current/Images/menu-toggle.png",
        fileName = "menu-toggle-v3.png",
        fallback = "rbxassetid://6031094678",
    },
    InkScratch = {
        url = RAW_BASE .. "src/gui/Current/Assets/Decorations/ink-scratch.png",
        fileName = "ink-scratch-v1.png",
        fallback = "rbxassetid://6031280882",
    },
    Spinner = {
        url = RAW_BASE .. "src/gui/Current/Assets/Status/spinner_minimal.png",
        fileName = "spinner-minimal-v1.png",
        fallback = "rbxassetid://6031094678",
    },
    IconHome = {
        url = RAW_BASE .. "src/gui/Current/Assets/Icons/home.png",
        fileName = "icon-home-v1.png",
        fallback = "rbxassetid://6026568198",
    },
    IconSearch = {
        url = RAW_BASE .. "src/gui/Current/Assets/Icons/search.png",
        fileName = "icon-search-v1.png",
        fallback = "rbxassetid://6031154871",
    },
    IconSettings = {
        url = RAW_BASE .. "src/gui/Current/Assets/Icons/settings.png",
        fileName = "icon-settings-v1.png",
        fallback = "rbxassetid://6031280882",
    },
    IconTarget = {
        url = RAW_BASE .. "src/gui/Current/Assets/Icons/target_cross.png",
        fileName = "icon-target-v1.png",
        fallback = "rbxassetid://6034287594",
    },
})

local DEFAULT_TAB_ICONS: {[string]: string} = table.freeze({
    Universal = "IconHome",
    Movement = "IconTarget",
    Search = "IconSearch",
    Settings = "IconSettings",
})

local function create<T>(className: string, properties: {[string]: any}): T
    local instance: Instance = Instance.new(className)
    for property: string, value: any in pairs(properties) do
        if property ~= "Parent" then
            (instance :: any)[property] = value
        end
    end
    local parent: Instance? = properties.Parent
    if parent then
        instance.Parent = parent
    end
    return (instance :: any) :: T
end

local function tween(target: Instance, properties: {[string]: any}): ()
    TweenService:Create(
        target,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        properties
    ):Play()
end

local function round(object: GuiObject, radius: number): UICorner
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius),
        Parent = object,
    })
end

local function stroke(
    object: GuiObject,
    transparency: number,
    thickness: number?
): UIStroke
    return create("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = THEME.Outline,
        Thickness = thickness or 1,
        Transparency = transparency,
        Parent = object,
    })
end

local function ensureCacheFolder(): ()
    local isFolder: any = executorEnvironment.isfolder
    local makeFolder: any = executorEnvironment.makefolder
    if type(isFolder) ~= "function" or type(makeFolder) ~= "function" then
        return
    end
    if not isFolder("ARandomMenu") then
        makeFolder("ARandomMenu")
    end
    if not isFolder(CACHE_ROOT) then
        makeFolder(CACHE_ROOT)
    end
end

local function getAssetResolver(): ((string) -> string)?
    local resolver: any = executorEnvironment.getcustomasset
        or executorEnvironment.getsynasset
    return type(resolver) == "function" and resolver or nil
end

local function isSupportedImageBody(body: any): boolean
    if type(body) ~= "string" or #body < 256 then
        return false
    end
    local header: string = body:sub(1, 8)
    local isPng: boolean = header == "\137PNG\r\n\26\n"
    local isJpg: boolean = header:sub(1, 3) == "\255\216\255"
    return isPng or isJpg
end

local function resolveAsset(source: AssetSource): string
    local resolver: ((string) -> string)? = getAssetResolver()
    local writeFile: any = executorEnvironment.writefile
    local isFile: any = executorEnvironment.isfile
    local readFile: any = executorEnvironment.readfile
    if resolver == nil or type(writeFile) ~= "function" then
        return source.fallback
    end
    ensureCacheFolder()
    local path: string = CACHE_ROOT .. "/" .. source.fileName
    local cached: boolean = false
    local checked: boolean = false
    local exists: any = false
    if type(isFile) == "function" then
        checked, exists = pcall(isFile, path)
    end
    if checked and exists == true then
        if type(readFile) == "function" then
            local readOk: boolean, cachedBody: any = pcall(readFile, path)
            cached = readOk and isSupportedImageBody(cachedBody)
        else
            cached = true
        end
    end
    if not cached then
        local downloaded: boolean, body: any = pcall(function(): string
            return (game :: any):HttpGet(source.url, true)
        end)
        if not downloaded or not isSupportedImageBody(body) then
            return source.fallback
        end
        if not pcall(writeFile, path, body) then
            return source.fallback
        end
    end
    local resolved: boolean, asset: any = pcall(resolver, path)
    return resolved and type(asset) == "string" and asset or source.fallback
end

local function loadImage(
    target: ImageLabel | ImageButton,
    key: string,
    onResolved: ((boolean) -> ())?
): ()
    local source: AssetSource? = ASSETS[key]
    if source == nil then
        return
    end
    if source.fallback ~= "" then
        target.Image = source.fallback
    end
    task.spawn(function(): ()
        local asset: string = resolveAsset(source :: AssetSource)
        if asset ~= "" and target.Parent ~= nil then
            target.Image = asset
            if onResolved then
                onResolved(true)
            end
        elseif onResolved then
            onResolved(false)
        end
    end)
end

local function getGuiParent(playerGui: PlayerGui): Instance
    local getHiddenUi: any = executorEnvironment.gethui
    if type(getHiddenUi) == "function" then
        local succeeded: boolean, hiddenUi: any = pcall(getHiddenUi)
        if succeeded and typeof(hiddenUi) == "Instance" then
            return hiddenUi :: Instance
        end
    end
    return playerGui
end

local function makeLabel(
    parent: Instance,
    text: string,
    size: number,
    scale: number,
    registry: {Instance}?
): TextLabel
    local label: TextLabel = create("TextLabel", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        Text = text,
        TextColor3 = THEME.Text,
        TextSize = math.round(size * scale),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = parent,
    })
    label:SetAttribute("BaseTextSize", size)
    if registry then
        table.insert(registry, label)
    end
    return label
end

local function makeButton(
    parent: Instance,
    text: string,
    size: number,
    scale: number,
    registry: {Instance}?
): TextButton
    local button: TextButton = create("TextButton", {
        TextTruncate = Enum.TextTruncate.AtEnd,
        AutoButtonColor = false,
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = THEME.Text,
        TextSize = math.round(size * scale),
        Parent = parent,
    })
    button:SetAttribute("BaseTextSize", size)
    if registry then
        table.insert(registry, button)
    end
    round(button, 8)
    stroke(button, 0.52)
    return button
end

local function applyKeySlotStyle(button: TextButton): ImageLabel
    button.ZIndex = math.max(2, button.ZIndex)
    local corner: UICorner? = button:FindFirstChildOfClass("UICorner")
    local buttonStroke: UIStroke? = button:FindFirstChildOfClass("UIStroke")
    local frame: ImageLabel = create("ImageLabel", {
        Name = "KeySlotFrame",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = ASSETS.KeybindPill.fallback,
        ImageColor3 = THEME.Text,
        ImageTransparency = 0.06,
        Position = UDim2.fromScale(0.5, 0.5),
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(300, 300, 1870, 420),
        SliceScale = 0.5,
        Size = UDim2.new(1, 10, 1, 10),
        ZIndex = button.ZIndex - 1,
        Parent = button,
    })
    loadImage(frame, "KeybindPill", function(loaded: boolean): ()
        if not loaded or button.Parent == nil then
            return
        end
        button.BackgroundTransparency = 1
        if corner and corner.Parent then
            corner:Destroy()
        end
        if buttonStroke and buttonStroke.Parent then
            buttonStroke:Destroy()
        end
    end)
    return frame
end

local function getPointer(input: InputObject): Vector2
    return Vector2.new(input.Position.X, input.Position.Y)
end

local Gui = {
    Assets = ASSETS,
    Theme = THEME,
}

function Gui.new(options: GuiOptions?): GuiController
    local resolved: GuiOptions = options or {}
    local player: Player = Players.LocalPlayer
    local playerGui: PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui
    local isMobile: boolean = UserInputService.TouchEnabled
        and not UserInputService.KeyboardEnabled
    local camera: Camera? = workspace.CurrentCamera
    local viewport: Vector2 = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local width: number = math.floor(viewport.X * (isMobile and 0.94 or 0.72))
    local height: number = math.floor(viewport.Y * (isMobile and 0.84 or 0.78))
    local textObjects: {Instance} = {}
    local capturingKeybind: boolean = false

    local screenGui: ScreenGui = create("ScreenGui", {
        Name = resolved.name or "ARandomMenuGui",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = resolved.parent or getGuiParent(playerGui),
    })
    local blur: BlurEffect = create("BlurEffect", {
        Name = "ARandomMenuBlur",
        Enabled = true,
        Size = 14,
        Parent = Lighting,
    })
    local window: Frame = create("Frame", {
        Name = "Window",
        Active = true,
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(
            math.max(0, math.floor((viewport.X - width) / 2)),
            math.max(0, math.floor((viewport.Y - height) / 2))
        ),
        Size = UDim2.fromOffset(width, height),
        Parent = screenGui,
    })
    round(window, 18)
    local windowStroke: UIStroke = stroke(window, 0.28, 1.2)
    windowStroke.Color = Color3.fromRGB(188, 188, 194)

    local header: Frame = create("Frame", {
        Name = "Header",
        Active = true,
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, 82),
        ZIndex = 20,
        Parent = window,
    })
    local headerImage: ImageLabel = create("ImageLabel", {
        Name = "HeaderImage",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = ASSETS.Header.fallback,
        ImageColor3 = Color3.fromRGB(220, 220, 224),
        ImageTransparency = 0.2,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 21,
        Parent = header,
    })
    loadImage(headerImage, "Header")
    create("Frame", {
        Name = "HeaderShade",
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 22,
        Parent = header,
    })
    local title: TextLabel = makeLabel(
        header,
        resolved.title or "A Random Menu",
        isMobile and 25 or 31,
        1,
        textObjects
    )
    title.Font = Enum.Font.Fondamento
    title.Position = UDim2.fromOffset(26, 2)
    title.Size = UDim2.new(1, -52, 1, -16)
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    title.TextStrokeTransparency = 0.25
    title.ZIndex = 24

    local ornament: ImageLabel = create("ImageLabel", {
        Name = "CosmicDivider",
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = ASSETS.CosmicControls.fallback,
        ImageColor3 = THEME.Text,
        ImageRectOffset = Vector2.new(666, 298),
        ImageRectSize = Vector2.new(171, 48),
        ImageTransparency = 0.12,
        Position = UDim2.new(0.5, 0, 1, -2),
        ScaleType = Enum.ScaleType.Stretch,
        Size = UDim2.new(0.56, 0, 0, 30),
        ZIndex = 23,
        Parent = header,
    })
    loadImage(ornament, "CosmicControls")

    local tabs: ScrollingFrame = create("ScrollingFrame", {
        Name = "Tabs",
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Color3.fromRGB(8, 8, 9),
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 82),
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        Size = UDim2.new(1, 0, 0, 46),
        ZIndex = 10,
        Parent = window,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabs,
    })
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = tabs,
    })
    local tabDivider: ImageLabel = create("ImageLabel", {
        Name = "TabDivider",
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = ASSETS.InkScratch.fallback,
        ImageColor3 = THEME.Outline,
        ImageRectOffset = Vector2.new(0, 0),
        ImageRectSize = Vector2.new(489, 124),
        ImageTransparency = 0.35,
        Position = UDim2.new(0.5, 0, 0, 126),
        ScaleType = Enum.ScaleType.Stretch,
        Size = UDim2.new(0.82, 0, 0, 14),
        ZIndex = 4,
        Parent = window,
    })
    loadImage(tabDivider, "InkScratch")
    local content: Frame = create("Frame", {
        Name = "Content",
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 128),
        Size = UDim2.new(1, 0, 1, -128),
        ZIndex = 3,
        Parent = window,
    })

    local controller: GuiController = {
        screenGui = screenGui,
        window = window,
        content = content,
        modules = {},
        pages = {},
        tabButtons = {},
        connections = {},
        featureConnections = {},
        activeTab = nil,
        visible = resolved.initiallyVisible ~= false,
        textScale = 1.08,
        blurEnabled = true,
        createModule = nil :: any,
        setTab = nil :: any,
        setTabIcon = nil :: any,
        setTextScale = nil :: any,
        setVisible = nil :: any,
        destroy = nil :: any,
    }

    function controller:setTab(id: string): ()
        if self.pages[id] == nil then
            return
        end
        self.activeTab = id
        for pageId: string, page: ScrollingFrame in pairs(self.pages) do
            page.Visible = pageId == id
        end
        for buttonId: string, button: TextButton in pairs(self.tabButtons) do
            local selected: boolean = buttonId == id
            button:SetAttribute("Selected", selected)
            tween(button, {
                BackgroundColor3 = selected and THEME.SurfaceActive or THEME.Surface,
                TextColor3 = selected and THEME.Text or THEME.MutedText,
            })
            local indicator: Frame? = button:FindFirstChild("Indicator") :: Frame?
            if indicator then
                tween(indicator, {BackgroundTransparency = selected and 0 or 1})
            end
            local icon: ImageLabel? = button:FindFirstChild("TabIcon") :: ImageLabel?
            if icon then
                tween(icon, {
                    ImageColor3 = selected and THEME.Text or THEME.MutedText,
                })
            end
        end
    end

    function controller:setTabIcon(id: string, assetKey: string): ()
        local button: TextButton? = self.tabButtons[id]
        local source: AssetSource? = ASSETS[assetKey]
        if button == nil or source == nil then
            return
        end
        local existing: Instance? = button:FindFirstChild("TabIcon")
        if existing then
            existing:Destroy()
        end
        local icon: ImageLabel = create("ImageLabel", {
            Name = "TabIcon",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = (source :: AssetSource).fallback,
            ImageColor3 = self.activeTab == id and THEME.Text or THEME.MutedText,
            Position = UDim2.new(0, 10, 0.5, 0),
            ScaleType = Enum.ScaleType.Fit,
            Size = UDim2.fromOffset(16, 16),
            ZIndex = button.ZIndex + 1,
            Parent = button,
        })
        loadImage(icon, assetKey)
        button.TextXAlignment = Enum.TextXAlignment.Left
        local padding: UIPadding? = button:FindFirstChildOfClass("UIPadding")
        if padding == nil then
            create("UIPadding", {
                PaddingLeft = UDim.new(0, 32),
                Parent = button,
            })
        end
    end

    function controller:setTextScale(scale: number): ()
        local nextScale: number = math.clamp(scale, 0.85, 1.35)
        if math.abs(nextScale - self.textScale) < 0.0001 then
            return
        end
        self.textScale = nextScale
        for index: number = #textObjects, 1, -1 do
            local textObject: Instance = textObjects[index]
            if textObject.Parent == nil then
                table.remove(textObjects, index)
            else
                local baseSize: any = textObject:GetAttribute("BaseTextSize")
                if type(baseSize) == "number" then
                    (textObject :: any).TextSize = math.round(baseSize * nextScale)
                end
            end
        end
    end

    function controller:createModule(
        id: string,
        label: string,
        layoutOrder: number
    ): ModuleController
        assert(self.modules[id] == nil, "Duplicate module: " .. id)
        local tabButton: TextButton = makeButton(
            tabs,
            label,
            13,
            self.textScale,
            textObjects
        )
        tabButton.Name = id .. "Tab"
        tabButton.LayoutOrder = layoutOrder
        tabButton.Size = UDim2.fromOffset(isMobile and 106 or 124, 42)
        tabButton.TextColor3 = THEME.MutedText
        tabButton.ZIndex = 11
        local indicator: Frame = create("Frame", {
            Name = "Indicator",
            AnchorPoint = Vector2.new(0, 1),
            BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 9, 1, -2),
            Size = UDim2.new(1, -18, 0, 2),
            Parent = tabButton,
        })
        round(indicator, 2)
        local page: ScrollingFrame = create("ScrollingFrame", {
            Name = id .. "Page",
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = THEME.Background,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, 0),
            ScrollBarImageColor3 = THEME.MutedText,
            ScrollBarThickness = 4,
            Size = UDim2.fromScale(1, 1),
            Visible = false,
            Parent = content,
        })
        create("UIPadding", {
            PaddingBottom = UDim.new(0, 18),
            PaddingLeft = UDim.new(0, 18),
            PaddingRight = UDim.new(0, 18),
            PaddingTop = UDim.new(0, 18),
            Parent = page,
        })
        create("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = page,
        })

        local module: ModuleController = {
            id = id,
            page = page,
            addToggle = nil :: any,
            addAction = nil :: any,
        }

        local function createFeature(
            featureId: string,
            featureLabel: string,
            description: string,
            isAction: boolean,
            callback: any
        ): FeatureController
            local row: Frame = create("Frame", {
                Name = featureId .. "Feature",
                Active = true,
                BackgroundColor3 = THEME.Background,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Size = UDim2.new(1, 0, 0, 54),
                Parent = page,
            })
            round(row, 10)
            local rowStroke: UIStroke = stroke(row, 1)
            local activeStripe: Frame = create("Frame", {
                Name = "ActiveStripe",
                BackgroundColor3 = THEME.Accent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, 7),
                Size = UDim2.new(0, 3, 0, 40),
                Parent = row,
            })
            round(activeStripe, 3)
            local featureTitle: TextLabel = makeLabel(
                row,
                featureLabel,
                13,
                controller.textScale,
                textObjects
            )
            featureTitle.Font = Enum.Font.GothamMedium
            featureTitle.Position = UDim2.fromOffset(16, 0)
            featureTitle.Size = UDim2.new(1, -148, 0, 31)
            local featureDescription: TextLabel = makeLabel(
                row,
                description,
                11,
                controller.textScale,
                textObjects
            )
            featureDescription.Position = UDim2.fromOffset(16, 27)
            featureDescription.Size = UDim2.new(1, -148, 0, 21)
            featureDescription.TextColor3 = THEME.MutedText
            featureDescription.TextTruncate = Enum.TextTruncate.AtEnd

            local toggle: TextButton = makeButton(
                row,
                isAction and "RUN" or "",
                10,
                controller.textScale,
                textObjects
            )
            toggle.Name = "Toggle"
            toggle.AnchorPoint = Vector2.new(1, 0.5)
            toggle.Position = UDim2.new(1, -40, 0, 27)
            toggle.Size = isAction and UDim2.fromOffset(48, 25) or UDim2.fromOffset(42, 24)
            local toggleKnob: Frame? = nil
            if not isAction then
                toggleKnob = create("Frame", {
                    Name = "Knob",
                    AnchorPoint = Vector2.new(0, 0.5),
                    BackgroundColor3 = THEME.Text,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 4, 0.5, 0),
                    Size = UDim2.fromOffset(16, 16),
                    Parent = toggle,
                })
                round(toggleKnob :: Frame, 8)
            end
            local more: TextButton = makeButton(
                row,
                "•••",
                12,
                controller.textScale,
                textObjects
            )
            more.Name = "More"
            more.AnchorPoint = Vector2.new(1, 0.5)
            more.BackgroundTransparency = 1
            more.Position = UDim2.new(1, -7, 0, 27)
            more.Size = UDim2.fromOffset(27, 27)
            more.TextColor3 = THEME.MutedText

            local optionsFrame: Frame = create("Frame", {
                Name = "Options",
                BackgroundColor3 = THEME.Surface,
                BackgroundTransparency = 0.45,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(10, 56),
                Size = UDim2.new(1, -20, 0, 0),
                Visible = false,
                Parent = row,
            })
            round(optionsFrame, 8)
            create("UIPadding", {
                PaddingBottom = UDim.new(0, 7),
                PaddingLeft = UDim.new(0, 9),
                PaddingRight = UDim.new(0, 9),
                PaddingTop = UDim.new(0, 7),
                Parent = optionsFrame,
            })
            local optionsLayout: UIListLayout = create("UIListLayout", {
                Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = optionsFrame,
            })
            local feature: FeatureController = {
                row = row,
                options = optionsFrame,
                enabled = false,
                expanded = false,
                addSlider = nil :: any,
                addKeybind = nil :: any,
                setEnabled = nil :: any,
                setExpanded = nil :: any,
            }
            local resizing: boolean = false

            local function refreshEnabled(): ()
                local enabled: boolean = feature.enabled
                tween(row, {
                    BackgroundColor3 = enabled and THEME.SurfaceActive or THEME.Background,
                    BackgroundTransparency = enabled and 0.06 or 1,
                })
                tween(rowStroke, {
                    Color = enabled and THEME.Accent or THEME.Outline,
                    Transparency = enabled and 0.14 or 1,
                })
                tween(activeStripe, {BackgroundTransparency = enabled and 0 or 1})
                tween(featureTitle, {
                    TextColor3 = enabled and Color3.new(1, 1, 1) or THEME.Text,
                })
                if toggleKnob then
                    tween(toggle, {
                        BackgroundColor3 = enabled and THEME.Accent or THEME.Surface,
                    })
                    tween(toggleKnob :: Frame, {
                        BackgroundColor3 = enabled and THEME.Background or THEME.Text,
                        Position = enabled
                            and UDim2.new(1, -20, 0.5, 0)
                            or UDim2.new(0, 4, 0.5, 0),
                    })
                end
            end

            function feature:setEnabled(enabled: boolean): ()
                if isAction then
                    return
                end
                self.enabled = enabled
                refreshEnabled()
            end

            function feature:setExpanded(expanded: boolean): ()
                self.expanded = expanded
                local optionsHeight: number = optionsLayout.AbsoluteContentSize.Y + 14
                self.options.Visible = expanded
                self.options.Size = UDim2.new(1, -20, 0, expanded and optionsHeight or 0)
                self.row.Size = UDim2.new(1, 0, 0, expanded and 64 + optionsHeight or 54)
                more.TextColor3 = expanded and THEME.Text or THEME.MutedText
            end

            function feature:addSlider(
                sliderLabel: string,
                minimum: number,
                maximum: number,
                initial: number,
                sliderCallback: (number) -> ()
            ): ()
                assert(maximum > minimum, "Slider maximum must exceed minimum")
                local value: number = math.clamp(initial, minimum, maximum)
                local option: Frame = create("Frame", {
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 38),
                    Parent = optionsFrame,
                })
                local optionLabel: TextLabel = makeLabel(
                    option,
                    sliderLabel,
                    10,
                    controller.textScale,
                    textObjects
                )
                optionLabel.Size = UDim2.new(0.38, 0, 1, 0)
                local valueLabel: TextLabel = makeLabel(
                    option,
                    tostring(math.round(value)),
                    10,
                    controller.textScale,
                    textObjects
                )
                valueLabel.AnchorPoint = Vector2.new(1, 0)
                valueLabel.Position = UDim2.new(1, 0, 0, 0)
                valueLabel.Size = UDim2.fromOffset(42, 38)
                valueLabel.TextXAlignment = Enum.TextXAlignment.Right
                local track: TextButton = create("TextButton", {
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    AutoButtonColor = false,
                    BackgroundColor3 = Color3.fromRGB(50, 50, 55),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0.4, 0, 0.5, -2),
                    Size = UDim2.new(0.6, -50, 0, 4),
                    Text = "",
                    Parent = option,
                })
                round(track, 3)
                local ratio: number = (value - minimum) / (maximum - minimum)
                local fill: Frame = create("Frame", {
                    BackgroundColor3 = THEME.Accent,
                    BorderSizePixel = 0,
                    Size = UDim2.fromScale(ratio, 1),
                    Parent = track,
                })
                round(fill, 3)
                local knob: Frame = create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    BackgroundColor3 = THEME.Text,
                    BorderSizePixel = 0,
                    Position = UDim2.fromScale(ratio, 0.5),
                    Size = UDim2.fromOffset(12, 12),
                    Parent = track,
                })
                round(knob, 6)
                local dragInput: InputObject? = nil
                local function update(pointerX: number): ()
                    local nextRatio: number = math.clamp(
                        (pointerX - track.AbsolutePosition.X)
                            / math.max(1, track.AbsoluteSize.X),
                        0,
                        1
                    )
                    value = minimum + (maximum - minimum) * nextRatio
                    fill.Size = UDim2.fromScale(nextRatio, 1)
                    knob.Position = UDim2.fromScale(nextRatio, 0.5)
                    valueLabel.Text = tostring(math.round(value))
                    sliderCallback(value)
                end
                table.insert(controller.featureConnections, track.InputBegan:Connect(function(
                    input: InputObject
                ): ()
                    if input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch then
                        dragInput = input
                        update(input.Position.X)
                    end
                end))
                table.insert(controller.featureConnections,
                    UserInputService.InputChanged:Connect(function(input: InputObject): ()
                        if dragInput and (input == dragInput
                            or input.UserInputType == Enum.UserInputType.MouseMovement) then
                            update(input.Position.X)
                        end
                    end)
                )
                table.insert(controller.featureConnections,
                    UserInputService.InputEnded:Connect(function(input: InputObject): ()
                        if input == dragInput
                            or input.UserInputType == Enum.UserInputType.MouseButton1
                            or input.UserInputType == Enum.UserInputType.Touch then
                            dragInput = nil
                        end
                    end)
                )
            end

            function feature:addKeybind(
                keybindLabel: string,
                initial: Enum.KeyCode,
                keybindCallback: (Enum.KeyCode) -> ()
            ): TextButton
                local selected: Enum.KeyCode = initial
                local capturing: boolean = false
                local option: Frame = create("Frame", {
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 38),
                    Parent = optionsFrame,
                })
                local optionLabel: TextLabel = makeLabel(
                    option,
                    keybindLabel,
                    11,
                    controller.textScale,
                    textObjects
                )
                optionLabel.Size = UDim2.new(0.48, 0, 1, 0)
                local keyButton: TextButton = makeButton(
                    option,
                    selected.Name,
                    11,
                    controller.textScale,
                    textObjects
                )
                keyButton.AnchorPoint = Vector2.new(1, 0.5)
                keyButton.Position = UDim2.new(1, -4, 0.5, 0)
                keyButton.Size = UDim2.new(0.45, 0, 0, 30)
                local keyFrame: ImageLabel = applyKeySlotStyle(keyButton)
                table.insert(controller.featureConnections,
                    keyButton.MouseButton1Click:Connect(function(): ()
                        capturing = true
                        capturingKeybind = true
                        keyButton.Text = "PRESS A KEY…"
                        tween(keyFrame, {
                            ImageColor3 = Color3.new(1, 1, 1),
                            ImageTransparency = 0,
                        })
                    end)
                )
                table.insert(controller.featureConnections,
                    UserInputService.InputBegan:Connect(function(
                        input: InputObject,
                        _processed: boolean
                    ): ()
                        if not capturing
                            or input.UserInputType ~= Enum.UserInputType.Keyboard
                            or input.KeyCode == Enum.KeyCode.Unknown then
                            return
                        end
                        capturing = false
                        selected = input.KeyCode
                        keyButton.Text = selected.Name
                        tween(keyFrame, {
                            ImageColor3 = THEME.Text,
                            ImageTransparency = 0.06,
                        })
                        keybindCallback(selected)
                        task.defer(function(): ()
                            capturingKeybind = false
                        end)
                    end)
                )
                keybindCallback(selected)
                return keyButton
            end

            table.insert(controller.connections, more.MouseButton1Click:Connect(function(): ()
                feature:setExpanded(not feature.expanded)
            end))
            table.insert(controller.connections, toggle.MouseButton1Click:Connect(function(): ()
                if isAction then
                    task.spawn(callback)
                    return
                end
                local requested: boolean = not feature.enabled
                local succeeded: boolean, message: any = pcall(callback, requested)
                feature.enabled = succeeded and requested or false
                if not succeeded then
                    warn("[ARandomMenu] " .. featureLabel .. ": " .. tostring(message))
                end
                refreshEnabled()
            end))
            table.insert(controller.connections, row.MouseEnter:Connect(function(): ()
                if not feature.enabled then
                    tween(row, {
                        BackgroundColor3 = THEME.SurfaceHover,
                        BackgroundTransparency = 0.24,
                    })
                end
            end))
            table.insert(controller.connections, row.MouseLeave:Connect(refreshEnabled))
            table.insert(controller.connections,
                optionsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(
                    function(): ()
                        if feature.expanded and not resizing then
                            resizing = true
                            feature:setExpanded(true)
                            resizing = false
                        end
                    end
                )
            )
            return feature
        end

        function module:addToggle(
            featureId: string,
            featureLabel: string,
            description: string,
            callback: (boolean) -> ()
        ): FeatureController
            return createFeature(featureId, featureLabel, description, false, callback)
        end

        function module:addAction(
            featureId: string,
            featureLabel: string,
            description: string,
            callback: () -> ()
        ): FeatureController
            return createFeature(featureId, featureLabel, description, true, callback)
        end

        self.modules[id] = module
        self.pages[id] = page
        self.tabButtons[id] = tabButton
        local defaultIcon: string? = DEFAULT_TAB_ICONS[id]
        if defaultIcon then
            self:setTabIcon(id, defaultIcon)
        end
        table.insert(self.connections, tabButton.MouseButton1Click:Connect(function(): ()
            self:setTab(id)
        end))
        table.insert(self.connections, tabButton.MouseEnter:Connect(function(): ()
            if self.activeTab ~= id then
                tween(tabButton, {BackgroundColor3 = THEME.SurfaceHover})
            end
        end))
        table.insert(self.connections, tabButton.MouseLeave:Connect(function(): ()
            if self.activeTab ~= id then
                tween(tabButton, {BackgroundColor3 = THEME.Surface})
            end
        end))
        if self.activeTab == nil then
            self:setTab(id)
        elseif id ~= "Settings" and self.activeTab == "Settings" then
            self:setTab(id)
        end
        return module
    end

    function controller:setVisible(visible: boolean): ()
        self.visible = visible
        window.Visible = visible
        blur.Enabled = visible and self.blurEnabled
        blur.Size = (visible and self.blurEnabled) and 14 or 0
    end

    function controller:destroy(): ()
        capturingKeybind = false
        for _, connection: RBXScriptConnection in ipairs(self.featureConnections) do
            connection:Disconnect()
        end
        table.clear(self.featureConnections)
        for _, connection: RBXScriptConnection in ipairs(self.connections) do
            connection:Disconnect()
        end
        table.clear(self.connections)
        table.clear(textObjects)
        if blur.Parent then
            blur:Destroy()
        end
        if screenGui.Parent then
            screenGui:Destroy()
        end
    end

    local settings: ModuleController = controller:createModule(
        "Settings",
        "Settings",
        999
    )
    local textSetting: FeatureController = settings:addAction(
        "TextSize",
        "Text size",
        "Drag the linear bar to resize all interface text",
        function(): () end
    )
    local textToggle: Instance? = textSetting.row:FindFirstChild("Toggle")
    if textToggle and textToggle:IsA("GuiObject") then
        textToggle.Visible = false
    end
    local textMore: Instance? = textSetting.row:FindFirstChild("More")
    if textMore and textMore:IsA("GuiObject") then
        textMore.Visible = false
    end
    textSetting:addSlider("Scale", 85, 135, 108, function(value: number): ()
        controller:setTextScale(value / 100)
    end)
    task.defer(function(): ()
        textSetting:setExpanded(true)
    end)

    local blurSetting: FeatureController = settings:addToggle(
        "BlurMode",
        "Blur mode",
        "Blur the game while the menu is visible",
        function(enabled: boolean): ()
            controller.blurEnabled = enabled
            blur.Enabled = controller.visible and enabled
            blur.Size = (controller.visible and enabled) and 14 or 0
        end
    )
    blurSetting:setEnabled(true)

    local menuKey: Enum.KeyCode = Enum.KeyCode.RightShift
    local menuKeySetting: FeatureController = settings:addAction(
        "MenuKey",
        "Menu key",
        "Choose the key used to show or hide this interface",
        function(): () end
    )
    local menuKeyAction: Instance? = menuKeySetting.row:FindFirstChild("Toggle")
    if menuKeyAction and menuKeyAction:IsA("GuiObject") then
        menuKeyAction.Visible = false
    end
    menuKeySetting:addKeybind(
        "Show / hide",
        menuKey,
        function(selected: Enum.KeyCode): ()
            menuKey = selected
        end
    )
    task.defer(function(): ()
        menuKeySetting:setExpanded(true)
    end)

    local reinjectButton: TextButton? = nil
    local reinjecting: boolean = false
    local _reinjectSetting: FeatureController = settings:addAction(
        "Reinject",
        "Reinject latest",
        "Download and restart the newest main build",
        function(): ()
            if reinjecting then
                return
            end
            local compiler: any = executorEnvironment.loadstring
            if type(compiler) ~= "function" then
                warn("[ARandomMenu] Reinject requires loadstring support")
                return
            end
            reinjecting = true
            if reinjectButton then
                reinjectButton.Text = "DOWNLOADING…"
            end
            local sourceUrls: {string} = {
                resolved.reinjectUrl or (RAW_BASE .. "ARandomMenu.luau"),
                RUNTIME_SAFETY_SOURCE_URL,
            }
            local downloaded: boolean = false
            local sourceOrError: any = nil
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
                    and bodyOrError:find(
                        RUNTIME_COMPATIBILITY_MARKER,
                        1,
                        true
                    ) ~= nil
                if current then
                    downloaded = true
                    sourceOrError = bodyOrError
                    break
                end
                table.insert(downloadFailures, tostring(bodyOrError))
            end
            if not downloaded then
                reinjecting = false
                if reinjectButton then
                    reinjectButton.Text = "REINJECT"
                end
                warn("[ARandomMenu] Reinject download: "
                    .. table.concat(downloadFailures, " | "))
                return
            end
            local compiledOk: boolean, compiledOrError: any, returnedError: any = pcall(
                compiler,
                sourceOrError,
                "@ARandomMenu.luau"
            )
            if not compiledOk or type(compiledOrError) ~= "function" then
                reinjecting = false
                if reinjectButton then
                    reinjectButton.Text = "REINJECT"
                end
                warn("[ARandomMenu] Reinject compile: "
                    .. tostring(compiledOk and returnedError or compiledOrError))
                return
            end
            if reinjectButton then
                reinjectButton.Text = "RESTARTING…"
            end
            controller:destroy()
            task.defer(function(): ()
                local executed: boolean, executionError: any = xpcall(
                    compiledOrError,
                    debug.traceback
                )
                if not executed then
                    warn("[ARandomMenu] Reinject runtime: " .. tostring(executionError))
                end
            end)
        end
    )
    reinjectButton = _reinjectSetting.row:FindFirstChild("Toggle") :: TextButton?
    if reinjectButton then
        reinjectButton.Text = "REINJECT"
        reinjectButton.Size = UDim2.fromOffset(86, 27)
    end

    local dragging: boolean = false
    local dragInput: InputObject? = nil
    local dragOrigin: Vector2 = Vector2.zero
    local windowOrigin: Vector2 = Vector2.zero
    table.insert(controller.connections, header.InputBegan:Connect(function(
        input: InputObject
    ): ()
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        dragging = true
        dragInput = input
        dragOrigin = getPointer(input)
        windowOrigin = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
    end))
    table.insert(controller.connections, UserInputService.InputChanged:Connect(function(
        input: InputObject
    ): ()
        local matches: boolean = dragInput ~= nil
            and (((dragInput :: InputObject).UserInputType == Enum.UserInputType.Touch
                and input == dragInput)
                or input.UserInputType == Enum.UserInputType.MouseMovement)
        if not dragging or not matches then
            return
        end
        local currentCamera: Camera? = workspace.CurrentCamera
        local currentViewport: Vector2 = currentCamera
            and currentCamera.ViewportSize
            or viewport
        local nextPosition: Vector2 = windowOrigin + (getPointer(input) - dragOrigin)
        window.Position = UDim2.fromOffset(
            math.clamp(nextPosition.X, 0, math.max(0, currentViewport.X - window.AbsoluteSize.X)),
            math.clamp(nextPosition.Y, 0, math.max(0, currentViewport.Y - window.AbsoluteSize.Y))
        )
    end))
    table.insert(controller.connections, UserInputService.InputEnded:Connect(function(
        input: InputObject
    ): ()
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragInput = nil
        end
    end))
    table.insert(controller.connections, UserInputService.InputBegan:Connect(function(
        input: InputObject,
        processed: boolean
    ): ()
        if capturingKeybind or processed then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == menuKey then
            controller:setVisible(not controller.visible)
        end
    end))

    if isMobile then
        local menuButton: ImageButton = create("ImageButton", {
            Name = "MobileMenuButton",
            AnchorPoint = Vector2.new(1, 0),
            AutoButtonColor = false,
            BackgroundColor3 = THEME.Surface,
            BorderSizePixel = 0,
            Image = ASSETS.MobileToggle.fallback,
            Position = UDim2.new(1, -18, 0, 18),
            ScaleType = Enum.ScaleType.Crop,
            Size = UDim2.fromOffset(52, 52),
            ClipsDescendants = true,
            ZIndex = 100,
            Parent = screenGui,
        })
        round(menuButton, 26)
        stroke(menuButton, 0.18, 1.2)
        loadImage(menuButton, "MobileToggle")
        table.insert(controller.connections, menuButton.Activated:Connect(
            function(): ()
                controller:setVisible(not controller.visible)
            end
        ))
    end

    local spinner: ImageLabel = create("ImageLabel", {
        Name = "LoadingSpinner",
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = ASSETS.Spinner.fallback,
        ImageColor3 = THEME.MutedText,
        Position = UDim2.new(1, -16, 0, 41),
        Size = UDim2.fromOffset(18, 18),
        ZIndex = 25,
        Parent = header,
    })
    loadImage(spinner, "Spinner")
    task.spawn(function(): ()
        local elapsed: number = 0
        while elapsed < 6 and spinner.Parent ~= nil do
            elapsed += task.wait(0.05)
            spinner.Rotation = (spinner.Rotation + 9) % 360
        end
        if spinner.Parent ~= nil then
            spinner:Destroy()
        end
    end)

    controller:setVisible(resolved.initiallyVisible ~= false)
    return controller
end

return table.freeze(Gui)
