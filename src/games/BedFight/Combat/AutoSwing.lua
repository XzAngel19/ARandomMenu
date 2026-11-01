local Module = {Name = "BedFight Auto Swing", Initialized = false, Connection = nil}

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local env: any = getfenv()
    local rate: number = 9
    local nextAt: number = 0
    local function update(): ()
        local now: number = os.clock()
        if now < nextAt then return end
        nextAt = now + 1 / math.max(rate, 0.5)
        local weapons: any = env.state.weaponLibrary
        if weapons then weapons:Swing() end
    end
    local feature: any = env.createUniversalFeature("Auto Swing", "Presses the game's own sword button on a timer", 4, function(enabled: boolean): ()
        if Module.Connection then Module.Connection:Disconnect(); Module.Connection = nil end
        if enabled then
            nextAt = 0
            Module.Connection = game:GetService("RunService").Heartbeat:Connect(update)
        end
    end, {parent = env.state.bedFightScroll, registry = env.state.bedFightFeatures, categoryName = "Exploits"})
    env.addNumberOption(feature, "Swings per second", rate, 1, 20, function(value: number): () rate = value end)
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if Module.Connection then Module.Connection:Disconnect() Module.Connection = nil end
    Module.Initialized = false
end

return Module
