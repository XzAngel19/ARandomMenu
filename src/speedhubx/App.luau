--!nocheck
--[[
    Speed Hub X — App
    ==================
    Builds the whole overlay exactly as shown in the reference
    screenshot:

      * top-left "Supa Tech V2: Off" status pill
      * floating draggable red "S" tile (left edge)
      * the main window — title bar ("Speed Hub X | Version: 3.7.0"),
        close button, right-edge red accent strip, sidebar navigation
        (Home / Main / Farming / Killer / Misc) and the page host
      * Main page: Skill / Aim / Body sections with toggles and the
        "Choose Aim Part" dropdown
      * bottom-centre "CAN YOU EVEN SEE ME?" watermark

    RightControl toggles the whole interface.  The × button destroys it.
    All feature behaviour is delegated to the stub hooks in
    Features/*.luau, which are intentionally empty.
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require("Theme")
local Util = require("Util")
local Components = require("Components")
local Icons = require("Icons")
local Shared = require("Features/Shared")
local FeatureHome = require("Features/Home")
local FeatureMain = require("Features/Main")
local FeatureFarming = require("Features/Farming")
local FeatureKiller = require("Features/Killer")
local FeatureMisc = require("Features/Misc")

local M = Theme.Metrics
local C = Theme.Colors
local F = Theme.Fonts

local App = {}

---------------------------------------------------------------------------
-- Small chrome pieces
---------------------------------------------------------------------------
local function makeSupaPill(gui, connections)
    local pill = Util.create("TextButton", {
        Name = "SupaTechPill",
        Text = "",
        AutoButtonColor = false,
        BackgroundColor3 = C.ChromeBlack,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Position = M.SupaPillPosition,
        Size = M.SupaPillSize,
        Corner = 5,
        ZIndex = 30,
    })
    pill.Parent = gui

    Util.create("Frame", {
        Name = "StatusDot",
        BackgroundColor3 = C.StatusOff,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 9, 0.5, 0),
        Size = UDim2.fromOffset(8, 8),
        Corner = 999,
        ZIndex = 31,
    }).Parent = pill

    local label = Util.create("TextLabel", {
        Name = "Label",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 22, 0, 0),
        Size = UDim2.new(1, -28, 1, 0),
        Font = F.Pill,
        Text = "Supa Tech V2: Off",
        TextSize = M.SupaPillTextSize,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 31,
    })
    label.Parent = pill

    pill.MouseButton1Click:Connect(function()
        Shared.State.SupaTechV2Enabled = not Shared.State.SupaTechV2Enabled
        Shared.onSupaTechV2Toggle(Shared.State.SupaTechV2Enabled)
    end)

    return pill
end

local function makeFloatingLogo(gui, connections)
    local logo = Util.create("TextButton", {
        Name = "SupaTechLogo",
        Text = "",
        AutoButtonColor = false,
        BackgroundColor3 = C.LogoBackground,
        BorderSizePixel = 0,
        Position = M.LogoPosition,
        Size = UDim2.fromOffset(M.LogoSize, M.LogoSize),
        Corner = M.LogoCorner,
        ZIndex = 30,
    })
    logo.Parent = gui

    local s = Util.create("TextLabel", {
        Name = "Glyph",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -10),
        Font = F.Black,
        Text = "S",
        TextSize = 46,
        TextColor3 = C.White,
        Rotation = -2,
        ZIndex = 31,
        Stroke = { Color = C.LogoStroke, Thickness = 2.4, Transparency = 0.1 },
        Gradient = { Color = { Color3.fromRGB(255, 64, 64), Color3.fromRGB(168, 15, 15) }, Rotation = 90 },
    })
    s.Parent = logo

    -- two dripping streaks under the S
    Util.create("Frame", {
        BackgroundColor3 = Color3.fromRGB(190, 22, 22),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 30, 0, 52),
        Size = UDim2.new(0, 4.5, 0, 13),
        Corner = 2,
        ZIndex = 31,
    }).Parent = logo
    Util.create("Frame", {
        BackgroundColor3 = Color3.fromRGB(150, 14, 14),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 44, 0, 54),
        Size = UDim2.new(0, 3.5, 0, 9),
        Corner = 2,
        ZIndex = 31,
    }).Parent = logo

    logo.MouseButton1Click:Connect(function()
        Shared.onLogoClicked()
    end)

    Util.makeDraggable(logo, logo, connections)
    return logo
end

local function makeWatermark(gui)
    local bar = Util.create("Frame", {
        Name = "Watermark",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = M.WatermarkPosition,
        Size = UDim2.fromOffset(M.WatermarkWidth, M.WatermarkHeight),
        BackgroundColor3 = C.WatermarkBarB,
        BorderSizePixel = 0,
        Corner = 3,
        Active = false,
        Gradient = { Color = { C.WatermarkBarA, C.WatermarkBarB, C.WatermarkBarA }, Rotation = 0 },
        ZIndex = 25,
    })
    bar.Parent = gui

    Util.create("TextLabel", {
        Name = "Text",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Font = F.Black,
        Text = "CAN YOU EVEN SEE ME?",
        TextSize = M.WatermarkTextSize,
        TextColor3 = C.White,
        ZIndex = 26,
        Stroke = { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.1, Transparency = 0.2 },
    }).Parent = bar

    return bar
end

---------------------------------------------------------------------------
-- Page builders
---------------------------------------------------------------------------
local function buildHomePage(page)
    -- Brand block ---------------------------------------------------------
    local logo = Util.create("Frame", {
        Name = "BrandLogo",
        BackgroundColor3 = C.LogoBackground,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 0, 6),
        Size = UDim2.fromOffset(64, 64),
        Corner = 14,
        ZIndex = 4,
    })
    logo.Parent = page

    local glyph = Util.create("TextLabel", {
        Name = "Glyph",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Font = F.Black,
        Text = "S",
        TextSize = 38,
        TextColor3 = C.White,
        ZIndex = 5,
        Stroke = { Color = C.LogoStroke, Thickness = 2, Transparency = 0.15 },
        Gradient = { Color = { Color3.fromRGB(255, 64, 64), Color3.fromRGB(168, 15, 15) }, Rotation = 90 },
    })
    glyph.Parent = logo

    Util.create("TextLabel", {
        Name = "Wordmark",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 88, 0, 6),
        Size = UDim2.new(1, -88, 0, 38),
        Font = F.Black,
        Text = "Speed Hub X",
        TextSize = 28,
        TextColor3 = Color3.fromRGB(246, 246, 246),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
    }).Parent = page

    Util.create("TextLabel", {
        Name = "Version",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 88, 0, 42),
        Size = UDim2.new(1, -88, 0, 20),
        Font = F.Body,
        Text = "Version: 3.7.0",
        TextSize = 14,
        TextColor3 = C.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
    }).Parent = page

    -- Info rows ----------------------------------------------------------
    Components.infoRow(page, { label = "Version", value = "3.7.0" }, UDim2.new(0, 0, 0, 96))
    Components.infoRow(page, { label = "Status", value = "Supa Tech V2: Off" }, UDim2.new(0, 0, 0, 150))
    Components.infoRow(page, { label = "Watermark", value = "Visible" }, UDim2.new(0, 0, 0, 204))
    Components.infoRow(page, { label = "Config", value = "Not saved" }, UDim2.new(0, 0, 0, 258))

    -- Action buttons -----------------------------------------------------
    Components.buttonRow(page, {
        title = "Save Configuration",
        subtitle = "Persist the current UI state (stub)",
        buttonText = "Save",
        onClick = function()
            FeatureHome.onSaveConfig()
            Shared.saveConfig()
        end,
    }, UDim2.new(0, 0, 0, 330))

    Components.buttonRow(page, {
        title = "Reload Interface",
        subtitle = "Destroy and rebuild the menu (UI only)",
        buttonText = "Reload",
        onClick = function()
            FeatureHome.onReloadInterface()
            task.defer(function()
                App.restart()
            end)
        end,
    }, UDim2.new(0, 0, 0, 404))
end

local function buildMainPage(page)
    -- Offsets measured from the reference screenshot (window-local):
    --   Skill header 0 · rows 43/121 · Aim header 197 · dropdown 253 ·
    --   Aimlock 321 · Body header 407 · rows 457/535/613
    Components.sectionHeader(page, "Skill", UDim2.new(0, 0, 0, 0))
    Components.toggleRow(page, {
        title = "Auto Ultimate",
        subtitle = "This is Meaning Auto Use Ultimate",
        defaultOn = true,
        onChanged = FeatureMain.onAutoUltimateToggle,
    }, UDim2.new(0, 0, 0, 43))
    Components.toggleRow(page, {
        title = "Auto Dash",
        subtitle = "This is Meaning Auto Use Dash",
        defaultOn = true,
        onChanged = FeatureMain.onAutoDashToggle,
    }, UDim2.new(0, 0, 0, 121))

    Components.sectionHeader(page, "Aim", UDim2.new(0, 0, 0, 197))
    Components.dropdownRow(page, {
        label = "Choose Aim Part",
        value = "Head",
        options = { "Head", "Torso", "HumanoidRootPart", "Left Leg", "Right Leg", "Random" },
        panelHost = page,
        onChanged = FeatureMain.onAimPartChanged,
    }, UDim2.new(0, 0, 0, 253))
    Components.toggleRow(page, {
        title = "Aimlock",
        subtitle = "Aimlock = Lock Camera Player",
        defaultOn = false,
        onChanged = FeatureMain.onAimlockToggle,
    }, UDim2.new(0, 0, 0, 321))

    Components.sectionHeader(page, "Body", UDim2.new(0, 0, 0, 407))
    Components.toggleRow(page, {
        title = "Anti-Knockback",
        subtitle = "BETA",
        defaultOn = false,
        onChanged = FeatureMain.onAntiKnockbackToggle,
    }, UDim2.new(0, 0, 0, 457))
    Components.toggleRow(page, {
        title = "Anti-Stun",
        subtitle = "BETA",
        defaultOn = false,
        onChanged = FeatureMain.onAntiStunToggle,
    }, UDim2.new(0, 0, 0, 535))
    Components.toggleRow(page, {
        title = "Anti-Busy",
        subtitle = "BETA",
        defaultOn = false,
        onChanged = FeatureMain.onAntiBusyToggle,
    }, UDim2.new(0, 0, 0, 613))
end

local function buildEmptyPage(page, tabName, iconBuilder, subtitle)
    Components.emptyState(page, {
        iconBuilder = iconBuilder,
        title = tabName,
        subtitle = subtitle,
    })
end

---------------------------------------------------------------------------
-- Bootstrap
---------------------------------------------------------------------------
local activeGui = nil
local activeConnections = nil

function App.start()
    local parent = Util.getGuiParent()
    Util.destroyPrevious(parent)

    local connections = {}
    activeConnections = connections

    -- ScreenGui -----------------------------------------------------------
    local gui = Instance.new("ScreenGui")
    gui.Name = Theme.WindowName .. ".ScreenGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 100
    Util.protectGui(gui)
    gui.Parent = parent
    activeGui = gui

    -- Chrome ---------------------------------------------------------------
    makeSupaPill(gui, connections)
    makeFloatingLogo(gui, connections)
    makeWatermark(gui)

    -- Window ---------------------------------------------------------------
    local window = Components.makeWindow({
        rootConnections = connections,
        onClose = function()
            App.destroy()
        end,
    })
    window.Root.Parent = gui

    -- Pages -----------------------------------------------------------------
    local pages = {}
    local function page(name)
        local p = Components.makePage(window.Pages, name)
        pages[name] = p
        return p
    end

    buildHomePage(page("Home"))
    buildMainPage(page("Main"))
    buildEmptyPage(page("Farming"), "Farming", Icons.pickaxe,
        "No Farming modules are registered in this build. Wire your own modules to Features/Farming.luau — every callback is a stub.")
    buildEmptyPage(page("Killer"), "Killer", Icons.fist,
        "No Killer modules are registered in this build. Wire your own modules to Features/Killer.luau — every callback is a stub.")
    buildEmptyPage(page("Misc"), "Misc", Icons.mountains,
        "Nothing here yet. Wire your own modules to Features/Misc.luau — every callback is a stub.")

    -- Sidebar navigation -----------------------------------------------------
    local navDefs = {
        { id = "Home",    label = "Home",    icon = Icons.scanFace },
        { id = "Main",    label = "Main",    icon = Icons.house },
        { id = "Farming", label = "Farming", icon = Icons.pickaxe },
        { id = "Killer",  label = "Killer",  icon = Icons.fist },
        { id = "Misc",    label = "Misc",    icon = Icons.mountains },
    }

    local navButtons = {}

    local function selectTab(id)
        Shared.State.CurrentTab = id
        for name, p in pairs(pages) do
            p.Visible = (name == id)
        end
        for name, button in pairs(navButtons) do
            button.SetActive(name == id)
        end
        -- Close any expanded dropdown when switching tabs.
        if Components._openDropdown then
            Components._openDropdown()
        end
    end

    for order, def in ipairs(navDefs) do
        local button = Components.navButton(window.Sidebar, {
            id = def.id,
            label = def.label,
            iconBuilder = def.icon,
            order = order - 1,
            onSelected = selectTab,
        })
        navButtons[def.id] = button
    end

    -- Default to Main, exactly as captured in the reference screenshot.
    selectTab("Main")

    -- RightControl toggles the whole interface (UI only).
    local toggleConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.KeyCode == Enum.KeyCode.RightControl then
            gui.Enabled = not gui.Enabled
        end
    end)
    table.insert(connections, toggleConn)

    return gui
end

function App.destroy()
    Shared.unload() -- stub; tear your own logic down there
    if activeConnections then
        for _, connection in ipairs(activeConnections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        activeConnections = nil
    end
    if activeGui then
        activeGui:Destroy()
        activeGui = nil
    end
end

function App.restart()
    App.destroy()
    App.start()
end

return App
