local Module = {Name = 'BedWars Fast Place', Initialized = false, Connection = nil}

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
    local block: string = "wool_white"
    local rate: number = 8
    local enabled: boolean = false
    local nextAt: number = 0
    local function update(): ()
        if not enabled or os.clock() < nextAt then return end
        local player: Player = game:GetService("Players").LocalPlayer
        local character: Model? = player.Character
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
        local camera: Camera? = workspace.CurrentCamera
        if not character or not humanoid or humanoid.Health <= 0 or not camera then return end
        local params: RaycastParams = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {character}
        local hit: RaycastResult? = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 20, params)
        if not hit then return end
        nextAt = os.clock() + 1 / math.max(rate, 0.5)
        fire("PlaceBlock", {mouseBlockInfo = {placementPosition = hit.Position}, blockType = block, blockData = 0, position = hit.Position})
    end
    local feature: any = env.createUniversalFeature("Fast Place", "Places the selected block at the aimed position", 2, function(value: boolean): () enabled = value end, {categoryName = "Blocks", registry = env.state.bedWarsFeatures})
    env.addNumberOption(feature, "Blocks per second", rate, 1, 20, function(value: number): () rate = value end)
    Module.Connection = game:GetService("RunService").Heartbeat:Connect(update)
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect() Module.Connection = nil end
    Module.Initialized = false
end

return Module
