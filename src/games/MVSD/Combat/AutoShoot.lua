local Module = {Name = "MVSD Auto Shoot", Initialized = false, Connections = {}}

local function disconnectAll(): ()
    for _, connection: RBXScriptConnection in Module.Connections do connection:Disconnect() end
    table.clear(Module.Connections)
end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local environment: any = getfenv()
    local players: Players = game:GetService("Players")
    local input: VirtualInputManager = game:GetService("VirtualInputManager")
    local localPlayer: Player = players.LocalPlayer
    local enabled: boolean = false
    local teamCheck: boolean = true
    local radius: number = 180
    local delay: number = 0.04
    local nextShot: number = 0
    local function valid(player: Player): BasePart?
        if player == localPlayer or player:GetAttribute("Died") == true or player:GetAttribute("Game") ~= localPlayer:GetAttribute("Game") then return nil end
        if teamCheck and player:GetAttribute("Team") == localPlayer:GetAttribute("Team") then return nil end
        local character: Model? = player.Character
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not humanoid or humanoid.Health <= 0 then return nil end
        return character:FindFirstChild("Head") :: BasePart? or character:FindFirstChild("HumanoidRootPart") :: BasePart?
    end
    local function update(): ()
        if not enabled or os.clock() < nextShot then return end
        local camera: Camera? = workspace.CurrentCamera
        if not camera then return end
        local center: Vector2 = camera.ViewportSize / 2
        for _, player: Player in players:GetPlayers() do
            local part: BasePart? = valid(player)
            if part then
                local point: Vector3, visible: boolean = camera:WorldToViewportPoint(part.Position)
                if visible and point.Z > 0 and (Vector2.new(point.X, point.Y) - center).Magnitude <= radius then
                    nextShot = os.clock() + delay
                    input:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                    task.defer(function(): () input:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0) end)
                    break
                end
            end
        end
    end
    local feature: any = environment.createUniversalFeature("Auto Shoot", "Fires when an opponent enters the crosshair radius", 3, function(value: boolean): () enabled = value end, {parent = environment.state.mvsdScroll, registry = environment.state.mvsdFeatures})
    environment.addToggleOption(feature, "Team check", true, function(value: boolean): () teamCheck = value end)
    environment.addNumberOption(feature, "FOV radius", 180, 20, 520, function(value: number): () radius = value end)
    environment.addNumberOption(feature, "Shot delay", 0.04, 0, 1, function(value: number): () delay = value end)
    table.insert(Module.Connections, game:GetService("RunService").Heartbeat:Connect(update))
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    disconnectAll()
    Module.Initialized = false
end

return Module
