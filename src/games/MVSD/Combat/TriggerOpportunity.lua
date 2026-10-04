local Module = {Name = "MVSD Trigger Opportunity", Initialized = false, Connections = {}}

local function disconnectAll(): ()
    for _, connection: RBXScriptConnection in Module.Connections do connection:Disconnect() end
    table.clear(Module.Connections)
end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local environment: any = getfenv()
    local players: Players = game:GetService("Players")
    local localPlayer: Player = players.LocalPlayer
    local enabled: boolean = false
    local tolerance: number = 11
    local enteredAt: number? = nil
    local cueDelay: number = 0
    local function update(): ()
        if not enabled then enteredAt = nil return end
        local camera: Camera? = workspace.CurrentCamera
        if not camera then return end
        local center: Vector2 = camera.ViewportSize / 2
        local found: boolean = false
        for _, player: Player in players:GetPlayers() do
            local character: Model? = player.Character
            local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
            local part: BasePart? = character and character:FindFirstChild("Head") :: BasePart?
            if player ~= localPlayer and humanoid and humanoid.Health > 0 and part and player:GetAttribute("Game") == localPlayer:GetAttribute("Game") and player:GetAttribute("Team") ~= localPlayer:GetAttribute("Team") then
                local point: Vector3, visible: boolean = camera:WorldToViewportPoint(part.Position)
                if visible and point.Z > 0 and (Vector2.new(point.X, point.Y) - center).Magnitude <= tolerance then found = true break end
            end
        end
        if found then
            enteredAt = enteredAt or os.clock()
            if os.clock() - (enteredAt :: number) >= cueDelay then
                environment.notify("MVSD · SHOT WINDOW")
                enteredAt = os.clock() + 0.75
            end
        else
            enteredAt = nil
        end
    end
    local feature: any = environment.createUniversalFeature("Trigger Opportunity", "Notifies when an opponent overlaps the center reticle", 4, function(value: boolean): () enabled = value end, {parent = environment.state.mvsdScroll, registry = environment.state.mvsdFeatures})
    environment.addNumberOption(feature, "Reticle tolerance", 11, 2, 40, function(value: number): () tolerance = value end)
    environment.addNumberOption(feature, "Cue delay", 0, 0, 0.5, function(value: number): () cueDelay = value end)
    table.insert(Module.Connections, game:GetService("RunService").Heartbeat:Connect(update))
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    disconnectAll()
    Module.Initialized = false
end

return Module
