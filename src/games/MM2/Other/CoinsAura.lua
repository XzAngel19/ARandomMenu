local Module = {
    Name = "MM2 Coins Aura",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Coins Aura requires the MM2 core module")
    Module.Runtime = runtime

    local settings = {
        radius = 15,
    }

    -- Resolve the Coin_Server part that actually pays for a pickup.
    -- Coin ESP hands out the visual part; the server part is either
    -- the part itself (Name == "Coin_Server") or its parent.
    local function serverPartOf(part: Instance): Instance?
        if part.Name == "Coin_Server" then
            return part
        end
        local parent: Instance? = part.Parent
        if parent and parent.Name == "Coin_Server" then
            return parent
        end
        return part
    end

    -- A coin that was already taken keeps its entry in the throttled
    -- scan for a moment. Check the attribute/parent so a collected
    -- coin stops being a target at once.
    local function stillCollectable(part: Instance): boolean
        if not part.Parent then
            return false
        end
        local server: Instance? = serverPartOf(part)
        local collected: any = nil
        pcall(function(): ()
            collected = (server :: any):GetAttribute("Collected")
        end)
        return collected ~= true
    end

    -- Pulse the touch between our root and the coin's server part,
    -- exactly like AutoFarm's arrive-pulse and Teleport's
    -- touchDroppedGun: fire 0 then 1 so the server sees the full
    -- Touched/TouchEnded pair.
    local function touchCoin(root: BasePart, coin: Instance): boolean
        if type(state.fireTouchInterest) ~= "function" then
            return false
        end
        local touchPart: Instance? = serverPartOf(coin)
        if not touchPart then
            return false
        end
        pcall(state.fireTouchInterest, root, touchPart, 0)
        pcall(state.fireTouchInterest, root, touchPart, 1)
        return true
    end

    local function characterRoot(): BasePart?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function toggleCoinsAura(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinsAura")

        if not enabled then
            return
        end

        local lastPulseAt: number = -math.huge

        local function auraTick(): ()
            local root: BasePart? = characterRoot()
            if not root then
                return
            end

            -- Throttle the pulse: 0.25 s matches AutoFarm's
            -- lastTouchPulse interval and avoids hammering the server
            -- with touch events every frame.
            local now: number = os.clock()
            if now - lastPulseAt < 0.25 then
                return
            end

            -- Get the coin list from Coin ESP's cache, or fall back
            -- to a direct CollectionService scan.
            local coins: {Instance} = {}
            if type(state.mm2CoinPickups) == "function" then
                local ok: boolean, list: any = pcall(state.mm2CoinPickups)
                if ok and type(list) == "table" then
                    coins = list
                end
            end
            if #coins == 0 then
                local okTagged: boolean, tagged: any = pcall(function(): any
                    return game:GetService("CollectionService"):GetTagged("CoinVisual")
                end)
                if okTagged and type(tagged) == "table" then
                    coins = tagged
                end
            end

            local rootPos: Vector3 = root.Position
            local radius: number = settings.radius
            local pulsed: boolean = false
            for _, coin: Instance in ipairs(coins) do
                if not stillCollectable(coin) then
                    continue
                end
                local coinPos: Vector3? = nil
                pcall(function(): ()
                    if coin:IsA("BasePart") then
                        coinPos = (coin :: BasePart).Position
                    end
                end)
                if not coinPos then
                    continue
                end
                if (coinPos - rootPos).Magnitude <= radius then
                    touchCoin(root, coin)
                    pulsed = true
                end
            end

            if pulsed then
                lastPulseAt = now
            end
        end

        featureConnections.MM2CoinsAura =
            TaskManager:Connect(auraTick)
        auraTick()
    end

    local CoinsAuraFeature: any = createUniversalFeature(
        "Coins Aura",
        "Pulses the touch between your character and every coin within the aura radius, collecting them without moving.",
        7,
        toggleCoinsAura,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2CoinsAuraFeature = CoinsAuraFeature

    addNumberOption(CoinsAuraFeature, "Aura Radius", 15, 5, 50,
        function(value: number): ()
            settings.radius = value
            if CoinsAuraFeature.enabled then
                CoinsAuraFeature:SetStatus(tostring(math.round(value)) .. " studs")
            end
        end,
        "Distance from your character at which coins are touched and collected. Higher values reach more coins at once.", 1)

    activeCleanup = function(): ()
        toggleCoinsAura(false)
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
