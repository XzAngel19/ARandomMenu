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
        studs = 15,
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

        -- Optimized: cache the coin list and only refresh when dirty.
        -- Pulse every frame (no throttle) — firetouchinterest is cheap
        -- and the server expects per-frame contact for reliable pickup.
        local cachedCoins: {Instance} = {}
        local lastCacheRefresh: number = -math.huge
        local cachedRadiusSq: number = settings.studs * settings.studs

        local function refreshCache(): ()
            local now: number = os.clock()
            if now - lastCacheRefresh < 0.1 then
                return
            end
            lastCacheRefresh = now

            -- Get the coin list from Coin ESP's cache (fast path).
            if type(state.mm2CoinPickups) == "function" then
                local ok: boolean, list: any = pcall(state.mm2CoinPickups)
                if ok and type(list) == "table" and #list > 0 then
                    cachedCoins = list
                    return
                end
            end
            -- Fallback: direct tag scan (slower but reliable).
            local okTagged: boolean, tagged: any = pcall(function(): any
                return game:GetService("CollectionService"):GetTagged("CoinVisual")
            end)
            if okTagged and type(tagged) == "table" then
                cachedCoins = tagged
            end
        end

        local function auraTick(): ()
            local root: BasePart? = characterRoot()
            if not root then
                return
            end

            refreshCache()

            local rootPos: Vector3 = root.Position
            local radius: number = settings.studs
            local radiusSq: number = radius * radius
            local fireTouch = state.fireTouchInterest

            if type(fireTouch) ~= "function" then
                return
            end

            -- Batch touch all coins in range — no per-coin pcall overhead.
            for i: number = 1, #cachedCoins do
                local coin: Instance = cachedCoins[i]
                if coin.Parent and coin:IsA("BasePart") then
                    local coinPart: BasePart = coin :: BasePart
                    local diff: Vector3 = coinPart.Position - rootPos
                    -- Fast squared distance check (avoids sqrt).
                    if diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z <= radiusSq then
                        if stillCollectable(coin) then
                            local touchPart: Instance? = serverPartOf(coin)
                            if touchPart then
                                fireTouch(root, touchPart, 0)
                                fireTouch(root, touchPart, 1)
                            end
                        end
                    end
                end
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

    addNumberOption(CoinsAuraFeature, "Studs", 15, 5, 1000,
        function(value: number): ()
            settings.studs = value
            if CoinsAuraFeature.enabled then
                CoinsAuraFeature:SetStatus(tostring(math.round(value)) .. " studs")
            end
        end,
        "Distance from your character at which coins are touched and collected. Can go up to 1000+ studs. Warning: very high values may cause kicks.", 1)

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
