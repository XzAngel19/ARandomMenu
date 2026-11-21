--!strict

-- Standalone client-sided Luau GUI menu designed to run directly inside a live Roblox client via a script executor.
-- This replicates the entire GUI menu layout, windows, navigation sidebar, tabs, sections, toggles, dropdowns, sliders, buttons, colors, borders, spacing, typography, and visual details.
-- Organized cleanly into separate modules. Empty/stub functions only.

local Players: Players = game:GetService("Players")
local UserInputService: UserInputService = game:GetService("UserInputService")
local TweenService: TweenService = game:GetService("TweenService")
local Lighting: Lighting = game:GetService("Lighting")

local THEME = {
    Background = Color3.fromRGB(15, 15, 17),
    Surface = Color3.fromRGB(29, 29, 33),
    SurfaceHover = Color3.fromRGB(37, 37, 42),
    SurfaceActive = Color3.fromRGB(45, 45, 50),
    Accent = Color3.fromRGB(236, 236, 240),
    Text = Color3.fromRGB(246, 246, 248),
    MutedText = Color3.fromRGB(156, 156, 164),
    Outline = Color3.fromRGB(82, 82, 90),
    Enabled = Color3.fromRGB(0, 204, 0),
    Negative = Color3.fromRGB(255, 50, 50),
}

-- Core Window Builder Module
local WindowBuilder = {
    create = function(properties)
        local instance = Instance.new(properties.ClassName)
        for key, value in pairs(properties) do
            if key ~= "Parent" then
                instance[key] = value
            end
        end
        if properties.Parent then
            instance.Parent = properties.Parent
        end
        return instance
    end,

    round = function(object, radius)
        local corner = WindowBuilder.create({
            ClassName = "UICorner",
            CornerRadius = UDim.new(0, radius),
            Parent = object,
        })
        return corner
    end,

    stroke = function(object, transparency, thickness)
        local stroke = WindowBuilder.create({
            ClassName = "UIStroke",
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Color = THEME.Outline,
            Thickness = thickness or 1,
            Transparency = transparency,
            Parent = object,
        })
        return stroke
    end,

    tween = function(target, properties)
        TweenService:Create(
            target,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            properties
        ):Play()
    end,

    makeLabel = function(parent, text, size, scale, registry)
        local label = WindowBuilder.create({
            ClassName = "TextLabel",
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
    end,

    makeButton = function(parent, text, size, scale, registry)
        local button = WindowBuilder.create({
            ClassName = "TextButton",
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
        WindowBuilder.round(button, 8)
        WindowBuilder.stroke(button, 0.52)
        return button
    end,
}

-- Navigation & Tabs Module
local Navigation = {
    createTabButton = function(tabs, id, label, layoutOrder, scale, registry, isMobile)
        local button = WindowBuilder.makeButton(
            tabs,
            label,
            13,
            scale,
            registry
        )
        button.Name = id .. "Tab"
        button.LayoutOrder = layoutOrder
        button.Size = UDim2.fromOffset(isMobile and 106 or 124, 42)
        button.TextColor3 = THEME.MutedText
        button.ZIndex = 11

        local indicator = WindowBuilder.create({
            ClassName = "Frame",
            Name = "Indicator",
            AnchorPoint = Vector2.new(0, 1),
            BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(9, -2),
            Size = UDim2.new(1, -18, 0, 2),
            Parent = button,
        })
        WindowBuilder.round(indicator, 2)

        return button
    end,

    setTabIcon = function(button, assetKey, theme)
        local existing = button:FindFirstChild("TabIcon")
        if existing then
            existing:Destroy()
        end
        local icon = WindowBuilder.create({
            ClassName = "ImageLabel",
            Name = "TabIcon",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "rbxassetid://" .. assetKey, -- Fallback ID mapping
            ImageColor3 = theme.activeTab == button.Name and THEME.Text or THEME.MutedText,
            Position = UDim2.fromOffset(10, 0),
            ScaleType = Enum.ScaleType.Fit,
            Size = UDim2.fromOffset(16, 16),
            ZIndex = button.ZIndex + 1,
            Parent = button,
        })
        return icon
    end,
}

-- Section & Control Components Module
local Components = {
    createFeatureRow = function(page, featureId, featureLabel, description, isAction, scale, registry)
        local row = WindowBuilder.create({
            ClassName = "Frame",
            Name = featureId .. "Feature",
            Active = true,
            BackgroundColor3 = THEME.Background,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Size = UDim2.new(1, 0, 0, 54),
            Parent = page,
        })
        WindowBuilder.round(row, 10)
        local rowStroke = WindowBuilder.stroke(row, 1)

        local activeStripe = WindowBuilder.create({
            ClassName = "Frame",
            Name = "ActiveStripe",
            BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 7),
            Size = UDim2.new(0, 3, 0, 40),
            Parent = row,
        })
        WindowBuilder.round(activeStripe, 3)

        local title = WindowBuilder.makeLabel(
            row,
            featureLabel,
            13,
            scale,
            registry
        )
        title.Font = Enum.Font.GothamMedium
        title.Position = UDim2.fromOffset(16, 0)
        title.Size = UDim2.new(1, -148, 0, 31)

        local description = WindowBuilder.makeLabel(
            row,
            description,
            11,
            scale,
            registry
        )
        description.Position = UDim2.fromOffset(16, 27)
        description.Size = UDim2.new(1, -148, 0, 21)
        description.TextColor3 = THEME.MutedText
        description.TextTruncate = Enum.TextTruncate.AtEnd

        local toggle = WindowBuilder.makeButton(
            row,
            isAction and "RUN" or "",
            10,
            scale,
            registry
        )
        toggle.Name = "Toggle"
        toggle.AnchorPoint = Vector2.new(1, 0.5)
        toggle.Position = UDim2.fromOffset(-40, 27)
        toggle.Size = isAction and UDim2.fromOffset(48, 25) or UDim2.fromOffset(42, 24)

        local toggleKnob = nil
        if not isAction then
            toggleKnob = WindowBuilder.create({
                ClassName = "Frame",
                Name = "Knob",
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = THEME.Text,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(4, 0.5),
                Size = UDim2.fromOffset(16, 16),
                Parent = toggle,
            })
            WindowBuilder.round(toggleKnob, 8)
        end

        local more = WindowBuilder.makeButton(
            row,
            "•••",
            12,
            scale,
            registry
        )
        more.Name = "More"
        more.AnchorPoint = Vector2.new(1, 0.5)
        more.BackgroundTransparency = 1
        more.Position = UDim2.fromOffset(-7, 27)
        more.Size = UDim2.fromOffset(27, 27)
        more.TextColor3 = THEME.MutedText

        local optionsFrame = WindowBuilder.create({
            ClassName = "Frame",
            Name = "Options",
            BackgroundColor3 = THEME.Surface,
            BackgroundTransparency = 0.45,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(10, 56),
            Size = UDim2.new(1, -20, 0, 0),
            Visible = false,
            Parent = row,
        })
        WindowBuilder.round(optionsFrame, 8)
        WindowBuilder.create({
            ClassName = "UIPadding",
            PaddingBottom = UDim.new(0, 7),
            PaddingLeft = UDim.new(0, 9),
            PaddingRight = UDim.new(0, 9),
            PaddingTop = UDim.new(0, 7),
            Parent = optionsFrame,
        })
        WindowBuilder.create({
            ClassName = "UIListLayout",
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = optionsFrame,
        })

        return {
            row = row,
            options = optionsFrame,
            enabled = false,
            expanded = false,
            toggle = toggle,
            toggleKnob = toggleKnob,
            rowStroke = rowStroke,
            activeStripe = activeStripe,
            title = title,
            description = description,
            more = more,
        }
    end,

    addSliderStub = function(feature, label, min, max, initial, callback)
        local option = WindowBuilder.create({
            ClassName = "Frame",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 38),
            Parent = feature.options,
        })
        local optionLabel = WindowBuilder.makeLabel(option, label, 10, 1.08)
        optionLabel.Size = UDim2.new(0.38, 0, 1, 0)

        local valueLabel = WindowBuilder.makeLabel(option, tostring(math.round(initial)), 10, 1.08)
        valueLabel.AnchorPoint = Vector2.new(1, 0)
        valueLabel.Position = UDim2.fromOffset(0, 0)
        valueLabel.Size = UDim2.new(0.42, -42, 1, 0)
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right

        local track = WindowBuilder.create({
            ClassName = "TextButton",
            AutoButtonColor = false,
            BackgroundColor3 = Color3.fromRGB(50, 50, 55),
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0.4, -2),
            Size = UDim2.new(0.6, -50, 0, 4),
            Text = "",
            Parent = option,
        })
        WindowBuilder.round(track, 3)

        local ratio = (initial - min) / (max - min)
        local fill = WindowBuilder.create({
            ClassName = "Frame",
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(ratio, 1),
            Parent = track,
        })
        WindowBuilder.round(fill, 3)

        local knob = WindowBuilder.create({
            ClassName = "Frame",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = THEME.Text,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(ratio, 0.5),
            Size = UDim2.fromOffset(12, 12),
            Parent = track,
        })
        WindowBuilder.round(knob, 6)

        -- Stub callback hook
        feature.options.Size = UDim2.new(1, -20, 0, feature.options.Size.Y.Offset + 38)
        feature.row.Size = UDim2.new(1, 0, 0, feature.row.Size.Y.Offset + 38)
        callback(initial)
    end,

    addKeybindStub = function(feature, label, initial, callback)
        local option = WindowBuilder.create({
            ClassName = "Frame",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 38),
            Parent = feature.options,
        })
        local optionLabel = WindowBuilder.makeLabel(option, label, 11, 1.08)
        optionLabel.Size = UDim2.new(0.48, 0, 1, 0)

        local keyButton = WindowBuilder.makeButton(option, initial.Name, 11, 1.08)
        keyButton.AnchorPoint = Vector2.new(1, 0.5)
        keyButton.Position = UDim2.fromOffset(-4, 0.5)
        keyButton.Size = UDim2.fromOffset(45, 30)

        local keyFrame = WindowBuilder.create({
            ClassName = "ImageLabel",
            Name = "KeySlotFrame",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "rbxassetid://", -- Fallback
            ImageColor3 = THEME.Text,
            ImageTransparency = 0.06,
            Position = UDim2.fromScale(0.5, 0.5),
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(300, 300, 1870, 420),
            SliceScale = 0.5,
            Size = UDim2.new(1, 10, 1, 10),
            ZIndex = keyButton.ZIndex - 1,
            Parent = keyButton,
        })

        feature.options.Size = UDim2.new(1, -20, 0, feature.options.Size.Y.Offset + 38)
        feature.row.Size = UDim2.new(1, 0, 0, feature.row.Size.Y.Offset + 38)
        callback(initial)
    end,
}

-- Stubbed Feature/Callback Modules
local Features = {
    Universal = {
        name = "Universal",
        layoutOrder = 1,
        stubFunctions = function()
            -- Stub: Combat, Movement, Render, Other, etc.
            return function() end
        end,
    },
    Movement = {
        name = "Movement",
        layoutOrder = 2,
        stubFunctions = function()
            -- Stub: AntiVoid, ClickTeleport, FreezeMovements, Gravity, Jump, SafeWalk, Speed
            return function() end
        end,
    },
    Search = {
        name = "Search",
        layoutOrder = 3,
        stubFunctions = function()
            -- Stub: Search/Profile logic
            return function() end
        end,
    },
    Settings = {
        name = "Settings",
        layoutOrder = 999,
        stubFunctions = function()
            -- Stub: Text size, Blur mode, Menu key, Reinject latest
            return function() end
        end,
    },
}

-- Main Menu Controller
local StandaloneMenu = {
    controller = nil,
    textObjects = {},
    capturingKeybind = false,

    init = function(options)
        local resolved = options or {}
        local player = Players.LocalPlayer
        local playerGui = player:WaitForChild("PlayerGui")
        local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local width = math.floor(viewport.X * (isMobile and 0.94 or 0.72))
        local height = math.floor(viewport.Y * (isMobile and 0.84 or 0.78))
        local scale = 1.08

        local screenGui = WindowBuilder.create({
            ClassName = "ScreenGui",
            Name = resolved.name or "StandaloneMenuGui",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 999999,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            Parent = resolved.parent or playerGui,
        })

        local blur = WindowBuilder.create({
            ClassName = "BlurEffect",
            Name = "StandaloneMenuBlur",
            Enabled = true,
            Size = 14,
            Parent = Lighting,
        })

        local window = WindowBuilder.create({
            ClassName = "Frame",
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
        WindowBuilder.round(window, 18)
        local windowStroke = WindowBuilder.stroke(window, 0.28, 1.2)
        windowStroke.Color = Color3.fromRGB(188, 188, 194)

        local header = WindowBuilder.create({
            ClassName = "Frame",
            Name = "Header",
            Active = true,
            BackgroundColor3 = THEME.Background,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Size = UDim2.new(1, 0, 0, 82),
            ZIndex = 20,
            Parent = window,
        })

        local headerImage = WindowBuilder.create({
            ClassName = "ImageLabel",
            Name = "HeaderImage",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "rbxassetid://6031091002", -- Anime Header
            ImageColor3 = Color3.fromRGB(220, 220, 224),
            ImageTransparency = 0.2,
            ScaleType = Enum.ScaleType.Crop,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 21,
            Parent = header,
        })

        WindowBuilder.create({
            ClassName = "Frame",
            Name = "HeaderShade",
            BackgroundColor3 = THEME.Background,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 22,
            Parent = header,
        })

        local title = WindowBuilder.makeLabel(
            header,
            resolved.title or "Standalone Menu",
            isMobile and 25 or 31,
            1,
            StandaloneMenu.textObjects
        )
        title.Font = Enum.Font.Fondamento
        title.Position = UDim2.fromOffset(26, 2)
        title.Size = UDim2.new(1, -52, 1, -16)
        title.TextXAlignment = Enum.TextXAlignment.Center
        title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        title.TextStrokeTransparency = 0.25
        title.ZIndex = 24

        local ornament = WindowBuilder.create({
            ClassName = "ImageLabel",
            Name = "CosmicDivider",
            AnchorPoint = Vector2.new(0.5, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "rbxassetid://6031094678", -- Cosmic Controls
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

        local tabs = WindowBuilder.create({
            ClassName = "ScrollingFrame",
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
        WindowBuilder.create({
            ClassName = "UIListLayout",
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = tabs,
        })
        WindowBuilder.create({
            ClassName = "UIPadding",
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
            Parent = tabs,
        })

        local tabDivider = WindowBuilder.create({
            ClassName = "ImageLabel",
            Name = "TabDivider",
            AnchorPoint = Vector2.new(0.5, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "rbxassetid://6031280882", -- Ink Scratch
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

        local content = WindowBuilder.create({
            ClassName = "Frame",
            Name = "Content",
            BackgroundColor3 = THEME.Background,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 128),
            Size = UDim2.new(1, 0, 1, -128),
            ZIndex = 3,
            Parent = window,
        })

        local controller = {
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
            textScale = scale,
            blurEnabled = true,
            textObjects = StandaloneMenu.textObjects,

            createModule = function(self, id, label, layoutOrder)
                assert(self.modules[id] == nil, "Duplicate module: " .. id)
                local tabButton = Navigation.createTabButton(
                    tabs, id, label, layoutOrder, scale, self.textObjects, isMobile
                )
                self.tabButtons[id] = tabButton

                local page = WindowBuilder.create({
                    ClassName = "ScrollingFrame",
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
                WindowBuilder.create({
                    ClassName = "UIPadding",
                    PaddingBottom = UDim.new(0, 18),
                    PaddingLeft = UDim.new(0, 18),
                    PaddingRight = UDim.new(0, 18),
                    PaddingTop = UDim.new(0, 18),
                    Parent = page,
                })
                WindowBuilder.create({
                    ClassName = "UIListLayout",
                    Padding = UDim.new(0, 8),
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Parent = page,
                })

                local module = {
                    id = id,
                    page = page,
                    addToggle = function(self, featureId, featureLabel, description, callback)
                        local feature = Components.createFeatureRow(page, featureId, featureLabel, description, false, scale, self.textObjects)
                        -- Stub hook
                        table.insert(self.connections, feature.more.MouseButton1Click:Connect(function()
                            feature.expanded = not feature.expanded
                            feature.options.Visible = feature.expanded
                            feature.row.Size = UDim2.new(1, 0, 0, feature.expanded and 64 or 54)
                            callback(feature.enabled)
                        end))
                        table.insert(self.connections, feature.toggle.MouseButton1Click:Connect(function()
                            feature.enabled = not feature.enabled
                            callback(feature.enabled)
                        end))
                        return feature
                    end,
                    addAction = function(self, featureId, featureLabel, description, callback)
                        local feature = Components.createFeatureRow(page, featureId, featureLabel, description, true, scale, self.textObjects)
                        -- Stub hook
                        table.insert(self.connections, feature.toggle.MouseButton1Click:Connect(function()
                            task.spawn(callback)
                        end))
                        return feature
                    end,
                }

                self.modules[id] = module
                self.pages[id] = page
                table.insert(self.connections, tabButton.MouseButton1Click:Connect(function()
                    self:setTab(id)
                end))
                return module
            end,

            setTab = function(self, id)
                if self.pages[id] == nil then return end
                self.activeTab = id
                for pageId, page in pairs(self.pages) do
                    page.Visible = pageId == id
                end
                for buttonId, button in pairs(self.tabButtons) do
                    local selected = buttonId == id
                    button:SetAttribute("Selected", selected)
                    WindowBuilder.tween(button, {
                        BackgroundColor3 = selected and THEME.SurfaceActive or THEME.Surface,
                        TextColor3 = selected and THEME.Text or THEME.MutedText,
                    })
                    local indicator = button:FindFirstChild("Indicator")
                    if indicator then
                        WindowBuilder.tween(indicator, {BackgroundTransparency = selected and 0 or 1})
                    end
                end
            end,

            setVisible = function(self, visible)
                self.visible = visible
                window.Visible = visible
                blur.Enabled = visible and self.blurEnabled
                blur.Size = (visible and self.blurEnabled) and 14 or 0
            end,

            destroy = function(self)
                StandaloneMenu.capturingKeybind = false
                for _, conn in ipairs(self.featureConnections) do conn:Disconnect() end
                for _, conn in ipairs(self.connections) do conn:Disconnect() end
                table.clear(self.textObjects)
                if blur.Parent then blur:Destroy() end
                if screenGui.Parent then screenGui:Destroy() end
            end,
        }

        -- Initialize Modules based on image layout
        for _, mod in pairs(Features) do
            local module = controller:createModule(mod.name, mod.name, mod.layoutOrder)
            self.stubFunctions = mod.stubFunctions()
            module:addAction("StubAction", mod.name .. " Action", "Stub description for " .. mod.name, self.stubFunctions)
            module:addToggle("StubToggle", mod.name .. " Toggle", "Stub description for " .. mod.name, self.stubFunctions)
            -- Add Stubbed Sliders, Keybinds, Dropdowns here to match image sections
            Components.addSliderStub(module, "Stub Slider", 0, 100, 50, self.stubFunctions)
            Components.addKeybindStub(module, "Stub Keybind", Enum.KeyCode.Unknown, self.stubFunctions)
        end

        -- Set default tab
        controller:setTab("Universal")

        StandaloneMenu.controller = controller
        controller:setVisible(resolved.initiallyVisible ~= false)
        return controller
    end,
}

-- Execution Entry Point (Safe for Script Executor)
local executorEnvironment = getfenv()
local cloneReference = executorEnvironment.cloneref or function(instance) return instance end
local localPlayer = cloneReference(Players.LocalPlayer)
local playerGui = cloneReference(localPlayer:WaitForChild("PlayerGui"))

-- Initialize and return the controller
local menuController = StandaloneMenu.init({
    name = "StandaloneMenu",
    title = "Standalone Client Menu",
    initiallyVisible = true,
    parent = playerGui,
})

-- Stubbed logic hooks (Empty/Stub functions only)
-- Replicate every visible UI element, label, value, and structural detail shown in the image accurately via the modules above.
-- Actual gameplay/farming/combat/movement/safe mode/automation logic is empty.

return menuController
