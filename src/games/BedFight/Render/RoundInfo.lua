local Module = {Name = "BedFight Round Info", Initialized = false, Connection = nil, Panel = nil}

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local env: any = getfenv()
    local replicated: ReplicatedStorage = game:GetService("ReplicatedStorage")
    local status: TextLabel? = nil
    local mode: TextLabel? = nil
    local beds: TextLabel? = nil

    local function value(name: string): any
        local info: Instance? = replicated:FindFirstChild("GameInfo")
        local item: Instance? = info and info:FindFirstChild(name)
        if item and item:IsA("ValueBase") then return item.Value end
        return item and item:GetAttribute("Value") or nil
    end
    local function clear(): ()
        if Module.Connection then Module.Connection:Disconnect(); Module.Connection = nil end
        if Module.Panel then Module.Panel:Destroy(); Module.Panel = nil end
        status, mode, beds = nil, nil, nil
    end
    local function refresh(): ()
        local statusText: string = tostring(value("Status") or "—")
        local modeText: string = "Mode: " .. tostring(value("GameMode") or "—")
        local bedsText: string = "Beds: " .. (value("AllBedsBroken") == true and "all broken" or "standing")
        if status.Text ~= statusText then status.Text = statusText end
        if mode.Text ~= modeText then mode.Text = modeText end
        if beds.Text ~= bedsText then beds.Text = bedsText end
    end
    local function toggle(active: boolean): ()
        clear()
        if not active then return end
        local root: Frame = env.create("Frame", {Parent = env.ScreenGui, Name = "BedFightInfo", AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(14, 14, 16), BackgroundTransparency = 0.15, BorderSizePixel = 0, Position = UDim2.new(1, -18, 0, 90), Size = UDim2.fromOffset(196, 64), ZIndex = 60})
        env.create("UICorner", {Parent = root, CornerRadius = UDim.new(0, 4)})
        status = env.makeTextLabel(root, "", 12)
        mode = env.makeTextLabel(root, "", 10)
        beds = env.makeTextLabel(root, "", 10)
        status.Position = UDim2.fromOffset(10, 5) status.Size = UDim2.new(1, -20, 0, 21)
        mode.Position = UDim2.fromOffset(10, 25) mode.Size = UDim2.new(1, -20, 0, 18)
        beds.Position = UDim2.fromOffset(10, 42) beds.Size = UDim2.new(1, -20, 0, 18)
        Module.Panel = root
        refresh()
        local elapsed: number = 0
        Module.Connection = game:GetService("RunService").Heartbeat:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.2 then return end
            elapsed %= 0.2
            refresh()
        end)
    end
    env.createUniversalFeature("Round Info", "Status, mode and bed state", 3, toggle, {parent = env.state.bedFightScroll, registry = env.state.bedFightFeatures, categoryName = "Render"})
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect(); Module.Connection = nil end
    if Module.Panel then Module.Panel:Destroy(); Module.Panel = nil end
    Module.Initialized = false
end

return Module
