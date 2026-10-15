local Module = {Name = "BedFight Round Info", Initialized = false, Connection = nil, Panel = nil}

local function value(name: string): any
    local replicated: ReplicatedStorage = game:GetService("ReplicatedStorage")
    local info: Instance? = replicated:FindFirstChild("GameInfo")
    local item: Instance? = info and info:FindFirstChild(name)
    if item and item:IsA("ValueBase") then return item.Value end
    return item and item:GetAttribute("Value") or nil
end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local env: any = getfenv()
    local enabled: boolean = false
    local status: TextLabel? = nil
    local mode: TextLabel? = nil
    local beds: TextLabel? = nil
    local function clear(): ()
        if Module.Panel then Module.Panel:Destroy() Module.Panel = nil end
        status = nil mode = nil beds = nil
    end
    local function toggle(active: boolean): ()
        enabled = active
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
    end
    env.createUniversalFeature("Round Info", "Status, mode and bed state", 3, toggle, {parent = env.state.bedFightScroll, registry = env.state.bedFightFeatures, categoryName = "Render"})
    Module.Connection = game:GetService("RunService").Heartbeat:Connect(function(): ()
        if not enabled or not status or not mode or not beds then return end
        status.Text = tostring(value("Status") or "—")
        mode.Text = "Mode: " .. tostring(value("GameMode") or "—")
        beds.Text = "Beds: " .. (value("AllBedsBroken") == true and "all broken" or "standing")
    end)
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect() Module.Connection = nil end
    if Module.Panel then Module.Panel:Destroy() Module.Panel = nil end
    Module.Initialized = false
end

return Module
