--!strict

local environment: any = getfenv()
local cloneReference: (Instance) -> Instance = (
    environment.cloneref
    or function(instance: Instance): Instance
        return instance
    end
) :: (Instance) -> Instance

local Players: Players = cloneReference(game:GetService("Players")) :: Players
local UserInputService: UserInputService =
    cloneReference(game:GetService("UserInputService")) :: UserInputService
local TweenService: TweenService =
    cloneReference(game:GetService("TweenService")) :: TweenService

export type Theme = {
    Background: Color3,
    Surface: Color3,
    SurfaceHover: Color3,
    Accent: Color3,
    Text: Color3,
    MutedText: Color3,
    Outline: Color3,
}

export type GuiOptions = {
    name: string?,
    title: string?,
    theme: Theme?,
    backgroundImage: string?,
    menuIcon: string?,
    initiallyVisible: boolean?,
}

export type GuiController = {
    screenGui: ScreenGui,
    window: Frame,
    content: Frame,
    pages: {[string]: ScrollingFrame},
    tabButtons: {[string]: TextButton},
    connections: {RBXScriptConnection},
    activeTab: string?,
    visible: boolean,
    isMobile: boolean,
    addTab: (
        self: GuiController,
        id: string,
        label: string,
        layoutOrder: number
    ) -> ScrollingFrame,
    setTab: (self: GuiController, id: string) -> (),
    setVisible: (self: GuiController, visible: boolean) -> (),
    destroy: (self: GuiController) -> (),
}

local DEFAULT_THEME: Theme = table.freeze({
    Background = Color3.fromRGB(14, 18, 26),
    Surface = Color3.fromRGB(25, 31, 42),
    SurfaceHover = Color3.fromRGB(35, 44, 58),
    Accent = Color3.fromRGB(49, 110, 163),
    Text = Color3.fromRGB(242, 246, 252),
    MutedText = Color3.fromRGB(158, 172, 190),
    Outline = Color3.fromRGB(71, 84, 103),
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

local function tween(
    target: Instance,
    duration: number,
    properties: {[string]: any}
): ()
    TweenService:Create(
        target,
        TweenInfo.new(
            duration,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out
        ),
        properties
    ):Play()
end

local Gui = {}

function Gui.new(options: GuiOptions?): GuiController
    local resolved: GuiOptions = options or {}
    local theme: Theme = resolved.theme or DEFAULT_THEME
    local player: Player = Players.LocalPlayer
    local playerGui: PlayerGui =
        player:WaitForChild("PlayerGui") :: PlayerGui
    local isMobile: boolean = UserInputService.TouchEnabled
        and not UserInputService.KeyboardEnabled
    local camera: Camera? = workspace.CurrentCamera
    local viewport: Vector2 = camera
        and camera.ViewportSize
        or Vector2.new(1280, 720)
    local width: number = isMobile
        and math.max(320, math.floor(viewport.X * 0.92))
        or 760
    local height: number = isMobile
        and math.max(290, math.floor(viewport.Y * 0.78))
        or 470

    local screenGui: ScreenGui = create("ScreenGui", {
        Name = resolved.name or "ARandomMenuGui",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = playerGui,
    })
    local window: Frame = create("Frame", {
        Name = "Window",
        Active = true,
        BackgroundColor3 = theme.Background,
        BorderColor3 = theme.Outline,
        BorderSizePixel = 1,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(
            math.max(0, math.floor((viewport.X - width) / 2)),
            math.max(0, math.floor((viewport.Y - height) / 2))
        ),
        Size = UDim2.fromOffset(
            math.min(width, viewport.X),
            math.min(height, viewport.Y)
        ),
        Parent = screenGui,
    })

    if resolved.backgroundImage and resolved.backgroundImage ~= "" then
        create("ImageLabel", {
            Name = "Background",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = resolved.backgroundImage,
            ImageColor3 = Color3.fromRGB(180, 207, 232),
            ImageTransparency = 0.43,
            ScaleType = Enum.ScaleType.Crop,
            Size = UDim2.fromScale(1, 1),
            Parent = window,
        })
        create("Frame", {
            Name = "BackgroundShade",
            BackgroundColor3 = theme.Background,
            BackgroundTransparency = 0.28,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Parent = window,
        })
    end

    local header: Frame = create("Frame", {
        Name = "Header",
        Active = true,
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 52),
        ZIndex = 10,
        Parent = window,
    })
    create("TextLabel", {
        Name = "Title",
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Size = UDim2.new(1, -28, 1, 0),
        Position = UDim2.fromOffset(14, 0),
        Text = resolved.title or "A random Testing Menu # 0001",
        TextColor3 = theme.Text,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 11,
        Parent = header,
    })

    local tabs: Frame = create("Frame", {
        Name = "Tabs",
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 52),
        Size = UDim2.new(1, 0, 0, 44),
        ZIndex = 8,
        Parent = window,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabs,
    })
    local content: Frame = create("Frame", {
        Name = "Content",
        BackgroundColor3 = theme.Background,
        BackgroundTransparency = 0.22,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 96),
        Size = UDim2.new(1, 0, 1, -96),
        ZIndex = 3,
        Parent = window,
    })

    local controller: GuiController = {
        screenGui = screenGui,
        window = window,
        content = content,
        pages = {},
        tabButtons = {},
        connections = {},
        activeTab = nil,
        visible = resolved.initiallyVisible ~= false,
        isMobile = isMobile,
        addTab = nil :: any,
        setTab = nil :: any,
        setVisible = nil :: any,
        destroy = nil :: any,
    }

    function controller:addTab(
        id: string,
        label: string,
        layoutOrder: number
    ): ScrollingFrame
        assert((self.pages :: any)[id] == nil, "Duplicate tab: " .. id)
        local button: TextButton = create("TextButton", {
            Name = id .. "Tab",
            AutoButtonColor = false,
            BackgroundColor3 = theme.Surface,
            BorderColor3 = theme.Outline,
            BorderSizePixel = 1,
            Font = Enum.Font.Gotham,
            LayoutOrder = layoutOrder,
            Size = UDim2.new(0, 140, 1, 0),
            Text = label,
            TextColor3 = theme.Text,
            TextSize = 13,
            ZIndex = 9,
            Parent = tabs,
        })
        local page: ScrollingFrame = create("ScrollingFrame", {
            Name = id .. "Page",
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, 0),
            ScrollBarImageColor3 = theme.MutedText,
            ScrollBarThickness = 5,
            Size = UDim2.fromScale(1, 1),
            Visible = false,
            ZIndex = 4,
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
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 9),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = page,
        })

        self.pages[id] = page
        self.tabButtons[id] = button
        table.insert(self.connections, button.MouseEnter:Connect(function(): ()
            if self.activeTab ~= id then
                tween(button, 0.14, {BackgroundColor3 = theme.SurfaceHover})
            end
        end))
        table.insert(self.connections, button.MouseLeave:Connect(function(): ()
            if self.activeTab ~= id then
                tween(button, 0.14, {BackgroundColor3 = theme.Surface})
            end
        end))
        table.insert(self.connections, button.MouseButton1Click:Connect(function(): ()
            self:setTab(id)
        end))

        local count: number = 0
        for _ in pairs(self.tabButtons) do
            count += 1
        end
        for _, tabButton: TextButton in pairs(self.tabButtons) do
            tabButton.Size = UDim2.new(1 / count, 0, 1, 0)
        end
        if self.activeTab == nil then
            self:setTab(id)
        end
        return page
    end

    function controller:setTab(id: string): ()
        if not self.pages[id] then
            return
        end
        self.activeTab = id
        for pageId: string, page: ScrollingFrame in pairs(self.pages) do
            page.Visible = pageId == id
        end
        for buttonId: string, button: TextButton in pairs(self.tabButtons) do
            tween(
                button,
                0.16,
                {
                    BackgroundColor3 = buttonId == id
                        and theme.Accent
                        or theme.Surface,
                }
            )
        end
    end

    function controller:setVisible(visible: boolean): ()
        self.visible = visible
        window.Visible = visible
    end

    function controller:destroy(): ()
        for _, connection: RBXScriptConnection in ipairs(self.connections) do
            connection:Disconnect()
        end
        table.clear(self.connections)
        if screenGui.Parent then
            screenGui:Destroy()
        end
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
        dragOrigin = Vector2.new(input.Position.X, input.Position.Y)
        windowOrigin = Vector2.new(
            window.Position.X.Offset,
            window.Position.Y.Offset
        )
    end))
    table.insert(controller.connections, UserInputService.InputChanged:Connect(
        function(input: InputObject): ()
            local matchingInput: boolean = dragInput ~= nil
                and (
                    (
                        dragInput.UserInputType == Enum.UserInputType.Touch
                        and input == dragInput
                    )
                    or (
                        dragInput.UserInputType
                            == Enum.UserInputType.MouseButton1
                        and input.UserInputType
                            == Enum.UserInputType.MouseMovement
                    )
                )
            if not dragging or not matchingInput then
                return
            end
            local pointer: Vector2 = Vector2.new(
                input.Position.X,
                input.Position.Y
            )
            local delta: Vector2 = pointer - dragOrigin
            local currentCamera: Camera? = workspace.CurrentCamera
            local currentViewport: Vector2 = currentCamera
                and currentCamera.ViewportSize
                or viewport
            window.Position = UDim2.fromOffset(
                math.clamp(
                    windowOrigin.X + delta.X,
                    0,
                    math.max(0, currentViewport.X - window.AbsoluteSize.X)
                ),
                math.clamp(
                    windowOrigin.Y + delta.Y,
                    0,
                    math.max(0, currentViewport.Y - window.AbsoluteSize.Y)
                )
            )
        end
    ))
    table.insert(controller.connections, UserInputService.InputEnded:Connect(
        function(input: InputObject): ()
            if input == dragInput then
                dragging = false
                dragInput = nil
            end
        end
    ))

    if isMobile then
        local menuButton: ImageButton = create("ImageButton", {
            Name = "MobileMenuButton",
            AnchorPoint = Vector2.new(1, 0),
            AutoButtonColor = false,
            BackgroundColor3 = theme.Surface,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            Image = resolved.menuIcon or "",
            Position = UDim2.new(1, -18, 0, 18),
            ScaleType = Enum.ScaleType.Crop,
            Size = UDim2.fromOffset(52, 52),
            ZIndex = 30,
            Parent = screenGui,
        })
        create("UICorner", {
            CornerRadius = UDim.new(1, 0),
            Parent = menuButton,
        })
        create("UIStroke", {
            Color = theme.Text,
            Transparency = 0.25,
            Thickness = 1.5,
            Parent = menuButton,
        })
        table.insert(
            controller.connections,
            menuButton.MouseButton1Click:Connect(function(): ()
                controller:setVisible(not controller.visible)
            end)
        )
    end

    controller:setVisible(resolved.initiallyVisible ~= false)
    return controller
end

return table.freeze(Gui)
