local Module = {Name = 'BedWars Nuker', Initialized = false, Connection = nil}

local function fire(name: string, payload: any): boolean
    local replicated: ReplicatedStorage = game:GetService("ReplicatedStorage")
    for _, remote: Instance in replicated:GetDescendants() do
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
    local range: number = 20
    local rate: number = 6
    local enabled: boolean = false
    local nextAt: number = 0
    local function update(): ()
        if not enabled or os.clock() < nextAt then return end
        local character: Model? = game:GetService("Players").LocalPlayer.Character
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
        local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root or not humanoid or humanoid.Health <= 0 then return end
        local nearest: BasePart? = nil
        local distance: number = range
        for _, tagged: Instance in game:GetService("CollectionService"):GetTagged("bed") do
            if tagged:IsA("BasePart") then
                local current: number = (tagged.Position - root.Position).Magnitude
                if current < distance then nearest = tagged distance = current end
            end
        end
        if not nearest then return end
        nextAt = os.clock() + 1 / math.max(rate, 0.5)
        local position: Vector3 = nearest.Position
        fire("DamageBlock", {blockRef = {blockPosition = position}, hitPosition = position, hitNormal = (root.Position - position).Unit})
    end
    local feature: any = env.createUniversalFeature("Nuker", "Breaks tagged beds inside range", 3, function(value: boolean): () enabled = value end, {categoryName = "Blocks", registry = env.state.bedWarsFeatures})
    env.addNumberOption(feature, "Range", range, 5, 60, function(value: number): () range = value end)
    env.addNumberOption(feature, "Breaks per second", rate, 1, 20, function(value: number): () rate = value end)
    Module.Connection = game:GetService("RunService").Heartbeat:Connect(update)
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect() Module.Connection = nil end
    Module.Initialized = false
end

return Module
