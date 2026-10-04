local Module = {Name = "BedWars Auto Tool", Initialized = false, Connection = nil}

local function fire(name: string, payload: any): boolean
    for _, remote: Instance in game:GetService("ReplicatedStorage"):GetDescendants() do
        if remote.Name == name then
            if remote:IsA("RemoteEvent") then remote:FireServer(payload) return true end
            if remote:IsA("RemoteFunction") then remote:InvokeServer(payload) return true end
        end
    end
    return false
end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local env: any = getfenv()
    local enabled: boolean = false
    local player: Player = game:GetService("Players").LocalPlayer
    local function update(): ()
        if not enabled then return end
        local inventories: Instance? = game:GetService("ReplicatedStorage"):FindFirstChild("Inventories")
        local inventory: Instance? = inventories and inventories:FindFirstChild(player.Name)
        if not inventory then return end
        for _, item: Instance in inventory:GetChildren() do
            if item.Name:find("pickaxe") or item.Name:find("axe") then
                fire("SetInvItem", {hand = item})
                return
            end
        end
    end
    env.createUniversalFeature("Auto Tool", "Puts the matching item in hand before you need it", 6, function(value: boolean): () enabled = value end, {categoryName = "Other", registry = env.state.bedWarsFeatures})
    Module.Connection = game:GetService("RunService").Heartbeat:Connect(update)
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect() Module.Connection = nil end
    Module.Initialized = false
end

return Module
