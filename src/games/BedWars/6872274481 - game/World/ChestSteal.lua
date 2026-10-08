local Module = {Name = "BedWars Chest Steal", Initialized = false, Connection = nil}

local function fire(name: string): boolean
    for _, remote: Instance in game:GetService("ReplicatedStorage"):GetDescendants() do
        if remote.Name == name then
            if remote:IsA("RemoteEvent") then remote:FireServer() return true end
            if remote:IsA("RemoteFunction") then remote:InvokeServer() return true end
        end
    end
    return false
end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local env: any = getfenv()
    local enabled: boolean = false
    local nextAt: number = 0
    local function update(): ()
        if not enabled or os.clock() < nextAt then return end
        nextAt = os.clock() + 0.5
        fire("Inventory/SetObservedChest")
    end
    env.createUniversalFeature("Chest Steal", "Opens nearby chests without walking to them", 5, function(value: boolean): () enabled = value end, {categoryName = "Other", registry = env.state.bedWarsFeatures})
    Module.Connection = game:GetService("RunService").Heartbeat:Connect(update)
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect() Module.Connection = nil end
    Module.Initialized = false
end

return Module
