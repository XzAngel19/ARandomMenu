export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "AirWalk",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local LocalPlayer: Player = host.LocalPlayer
    local UserInputService: UserInputService = host.UserInputService
    local RunService: RunService = host.RunService
    local world: Workspace = host.workspace
    local create: any = host.create

    local platform: Part? = nil
    local gui: Frame? = nil
    local airY: number? = nil
    local trackedCharacter: Model? = nil
    local connections: {RBXScriptConnection} = {}
    local held: {[string]: {[any]: boolean}} = {
        Up = {},
        Down = {},
    }

    local VERTICAL_SPEED: number = 22

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function footOffsetOf(humanoid: Humanoid, root: BasePart): number
        local hip: number = humanoid.HipHeight
        if hip <= 0 then hip = 2 end
        return hip + root.Size.Y * 0.5 + 0.5
    end

    local function destroyPlatform(): ()
        if platform then platform:Destroy(); platform = nil end
    end

    local function destroyGui(): ()
        if gui then gui:Destroy(); gui = nil end
    end

    local function clearConnections(): ()
        for _, conn: RBXScriptConnection in ipairs(connections) do
            conn:Disconnect()
        end
        table.clear(connections)
        table.clear(held.Up)
        table.clear(held.Down)
    end

    local function setHold(direction: string, source: any, isDown: boolean): ()
        local bucket: {[any]: boolean}? = held[direction]
        if not bucket then
            return
        end
        bucket[source] = isDown and true or nil
    end

    local function isDirectionHeld(direction: string): boolean
        local bucket: {[any]: boolean}? = held[direction]
        return bucket ~= nil and next(bucket) ~= nil
    end

    local function ensurePlatform(): Part
        if platform and platform.Parent then return platform end
        local p: Part = Instance.new("Part")
        p.Name = "Wurst_AirWalkPlatform"
        p.Anchored = true
        p.CanCollide = true
        p.CanQuery = false
        p.CanTouch = false
        p.CastShadow = false
        p.Size = Vector3.new(16, 1, 16)
        p.Transparency = 1
        p.Parent = world
        platform = p
        return p
    end

    local airWalk: any
    airWalk = framework.Categories.Exploits:CreateModule({
        Name = "AirWalk",
        Category = "Exploits",
        ConfigKey = "Universal.AirWalk",
        Order = 11,
        Tooltip = "Stay in the air with every jump and walk in mid-air. Space to go up, Shift to go down, with mobile Up/Down buttons.",
        Function = function(enabled: boolean): ()
            clearConnections()
            destroyGui()
            destroyPlatform()
            airY = nil
            trackedCharacter = nil

            if not enabled then
                airWalk:SetStatus(nil)
                return
            end

            airWalk:SetStatus("Active")

            local function connect(signal: any, callback: any): ()
                table.insert(connections, signal:Connect(callback))
            end

            connect(UserInputService.InputBegan, function(event: InputObject, processed: boolean): ()
                if processed or UserInputService:GetFocusedTextBox() then
                    return
                end
                if event.UserInputType == Enum.UserInputType.Keyboard then
                    if event.KeyCode == Enum.KeyCode.Space then
                        setHold("Up", "Space", true)
                    elseif event.KeyCode == Enum.KeyCode.LeftShift
                        or event.KeyCode == Enum.KeyCode.RightShift then
                        setHold("Down", event.KeyCode, true)
                    end
                end
            end)

            connect(UserInputService.InputEnded, function(event: InputObject): ()
                if event.UserInputType == Enum.UserInputType.Keyboard then
                    if event.KeyCode == Enum.KeyCode.Space then
                        setHold("Up", "Space", false)
                    elseif event.KeyCode == Enum.KeyCode.LeftShift
                        or event.KeyCode == Enum.KeyCode.RightShift then
                        setHold("Down", event.KeyCode, false)
                    end
                elseif event.UserInputType == Enum.UserInputType.Touch then
                    setHold("Up", event, false)
                    setHold("Down", event, false)
                end
            end)

            if UserInputService.WindowFocusReleased then
                connect(UserInputService.WindowFocusReleased, function(): ()
                    table.clear(held.Up)
                    table.clear(held.Down)
                end)
            end
            if UserInputService.TextBoxFocused then
                connect(UserInputService.TextBoxFocused, function(): ()
                    table.clear(held.Up)
                    table.clear(held.Down)
                end)
            end

            if UserInputService.TouchEnabled and type(create) == "function" and host.ScreenGui then
                gui = create("Frame", {
                    Name = "AirWalkControls",
                    Parent = host.ScreenGui,
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    ZIndex = 30,
                })
                local function makeMobileButton(name: string, text: string, at: UDim2, size: UDim2): any
                    local object: any = create("TextButton", {
                        Name = name,
                        Parent = gui,
                        Position = at,
                        Size = size,
                        Text = text,
                        Font = Enum.Font.Code,
                        TextSize = 18,
                        TextColor3 = Color3.new(1, 1, 1),
                        BackgroundColor3 = Color3.fromRGB(25, 25, 25),
                        BackgroundTransparency = 0.3,
                        BorderSizePixel = 1,
                        BorderColor3 = Color3.fromRGB(120, 120, 120),
                        AutoButtonColor = true,
                        ZIndex = 31,
                    })
                    if host.ThemeEngine then
                        host.ThemeEngine.Bind(object, "BackgroundColor3", "background")
                        host.ThemeEngine.Bind(object, "TextColor3", "text")
                    end
                    return object
                end

                for _, name: string in ipairs({"Up", "Down"}) do
                    local btn: any = makeMobileButton(
                        name,
                        if name == "Up" then "+" else "−",
                        UDim2.new(1, -70, 1, if name == "Up" then -152 else -96),
                        UDim2.fromOffset(48, 48)
                    )
                    connect(btn.InputBegan, function(event: InputObject): ()
                        if event.UserInputType == Enum.UserInputType.Touch
                            or event.UserInputType == Enum.UserInputType.MouseButton1 then
                            setHold(name, event, true)
                        end
                    end)
                    connect(btn.InputEnded, function(event: InputObject): ()
                        if event.UserInputType == Enum.UserInputType.Touch
                            or event.UserInputType == Enum.UserInputType.MouseButton1 then
                            setHold(name, event, false)
                        end
                    end)
                end
            end

            connect(RunService.Heartbeat, function(dt: number): ()
                local character: Model?, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not character or not humanoid or not root or humanoid.Health <= 0 then
                    destroyPlatform()
                    airY = nil
                    trackedCharacter = nil
                    return
                end

                local stepDt: number = if type(dt) == "number" and dt > 0 and dt < 0.5 then dt else (1 / 60)
                local offset: number = footOffsetOf(humanoid, root)
                local currentFootY: number = root.Position.Y - offset

                if trackedCharacter ~= character or airY == nil then
                    trackedCharacter = character
                    airY = currentFootY
                end

                local keyUp: boolean = false
                local keyDown: boolean = false
                if not UserInputService:GetFocusedTextBox() then
                    keyUp = UserInputService:IsKeyDown(Enum.KeyCode.Space)
                    keyDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
                end

                local goingUp: boolean = keyUp or isDirectionHeld("Up")
                local goingDown: boolean = keyDown or isDirectionHeld("Down")

                local part: Part = ensurePlatform()
                if goingDown and not goingUp then
                    airY = currentFootY - VERTICAL_SPEED * stepDt - 1.4
                    local vel: Vector3 = root.AssemblyLinearVelocity
                    if vel.Y > -VERTICAL_SPEED then
                        root.AssemblyLinearVelocity = Vector3.new(vel.X, -VERTICAL_SPEED, vel.Z)
                    end
                elseif goingUp and not goingDown then
                    airY = math.max(airY :: number, currentFootY) + VERTICAL_SPEED * stepDt
                    local vel: Vector3 = root.AssemblyLinearVelocity
                    if vel.Y < VERTICAL_SPEED then
                        root.AssemblyLinearVelocity = Vector3.new(vel.X, VERTICAL_SPEED, vel.Z)
                    end
                else
                    -- Lock to the highest point reached on any jump.
                    if currentFootY > (airY :: number) then airY = currentFootY end
                end
                if not part.CanCollide then part.CanCollide = true end
                part.CFrame = CFrame.new(root.Position.X, airY :: number, root.Position.Z)
            end)

            airWalk:Clean(function(): ()
                clearConnections()
                destroyGui()
                destroyPlatform()
                airY = nil
                trackedCharacter = nil
            end)
        end,
    })

    activeCleanup = function(): ()
        clearConnections()
        destroyGui()
        destroyPlatform()
        if airWalk and airWalk.Enabled then
            airWalk:Toggle(false)
        end
    end

    Module.Initialized = true
    return airWalk
end

function Module.destroy(): ()
    if activeCleanup then
        activeCleanup()
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
