local Module = {Name = "BedFight Auto Swing", Initialized = false, Connection = nil}

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local env: any = getfenv()
    local enabled: boolean = false
    local rate: number = 9
    local nextAt: number = 0
    local function update(): ()
        if not enabled or os.clock() < nextAt then return end
        nextAt = os.clock() + 1 / math.max(rate, 0.5)
        local weapons: any = env.state.weaponLibrary
        if weapons then weapons:Swing() end
    end
    local feature: any = env.createUniversalFeature("Auto Swing", "Presses the game's own sword button on a timer", 4, function(value: boolean): () enabled = value end, {parent = env.state.bedFightScroll, registry = env.state.bedFightFeatures, categoryName = "Combat"})
    env.addNumberOption(feature, "Swings per second", rate, 1, 20, function(value: number): () rate = value end)
    Module.Connection = game:GetService("RunService").Heartbeat:Connect(update)
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect() Module.Connection = nil end
    Module.Initialized = false
end

return Module
