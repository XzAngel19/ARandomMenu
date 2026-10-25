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
        range = 100,
    }

    local function readAttribute(instance: Instance?, attrName: string): any
        if not instance then
            return nil
        end
        local ok: boolean, value: any = pcall(function(): any
            return instance:GetAttribute(attrName)
        end)
        if ok then
            return value
        end
        return nil
    end

    -- Resolve the Coin_Server BasePart that holds the server TouchTransmitter.
    -- MM2 spawns pickups as: CoinContainer -> Coin_Server (Part) -> CoinVisual (Part) -> MainCoin.
    local function serverPartOf(part: Instance): BasePart?
        if part:IsA("BasePart") and part.Name == "Coin_Server" then
            return part :: BasePart
        end
        local current: Instance? = part.Parent
        local depth: number = 0
        while current and current ~= workspace and depth < 4 do
            if current:IsA("BasePart") and current.Name == "Coin_Server" then
                return current :: BasePart
            end
            current = current.Parent
            depth += 1
        end
        if part:IsA("Model") then
            local childServer: Instance? = part:FindFirstChild("Coin_Server", true)
            if childServer and childServer:IsA("BasePart") then
                return childServer :: BasePart
            end
            local anyPart: Instance? = part:FindFirstChildWhichIsA("BasePart", true)
            if anyPart then
                return anyPart :: BasePart
            end
        end
        if part:IsA("BasePart") then
            local childServer: Instance? = part:FindFirstChild("Coin_Server")
            if childServer and childServer:IsA("BasePart") then
                return childServer :: BasePart
            end
            return part :: BasePart
        end
        return nil
    end

    local function visualPartOf(serverPart: BasePart): BasePart?
        local visual: Instance? = serverPart:FindFirstChild("CoinVisual")
        if visual and visual:IsA("BasePart") then
            return visual :: BasePart
        end
        return nil
    end

    -- Check both Coin_Server and CoinVisual so a collected or deleted pickup
    -- is skipped immediately before the container removes the instance.
    local function stillCollectable(part: Instance): boolean
        if not part or not part.Parent then
            return false
        end
        local server: BasePart? = serverPartOf(part)
        if not server or not server.Parent then
            return false
        end
        if readAttribute(server, "Collected") == true
            or readAttribute(server, "Delete") == true then
            return false
        end
        local visual: BasePart? = visualPartOf(server)
        if visual and (
            readAttribute(visual, "Collected") == true
            or readAttribute(visual, "Delete") == true
        ) then
            return false
        end
        if part ~= server and (
            readAttribute(part, "Collected") == true
            or readAttribute(part, "Delete") == true
        ) then
            return false
        end
        return true
    end

    local function characterRoot(): BasePart?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if humanoid and humanoid.Health <= 0 then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function pulseCoinTouch(root: BasePart, serverPart: BasePart): boolean
        local fireTouch: any = state.fireTouchInterest
        if type(fireTouch) ~= "function" then
            return false
        end
        pcall(fireTouch, root, serverPart, 0)
        pcall(fireTouch, root, serverPart, 1)
        local visual: BasePart? = visualPartOf(serverPart)
        if visual and visual ~= serverPart then
            local hasVisualTouch: boolean = false
            pcall(function(): ()
                hasVisualTouch = visual:FindFirstChildOfClass("TouchTransmitter") ~= nil
            end)
            if hasVisualTouch then
                pcall(fireTouch, root, visual, 0)
                pcall(fireTouch, root, visual, 1)
            end
        end
        return true
    end

    local CoinsAuraFeature: any = nil

    local function toggleCoinsAura(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinsAura")

        if not enabled then
            if CoinsAuraFeature then
                CoinsAuraFeature:SetStatus(nil)
            end
            return
        end

        local cachedServerCoins: {BasePart} = {}
        local lastCacheRefresh: number = -math.huge
        local lastStatus: string? = nil

        local function setStatus(text: string): ()
            if text == lastStatus then
                return
            end
            lastStatus = text
            if CoinsAuraFeature then
                CoinsAuraFeature:SetStatus(text)
            end
        end

        local function refreshCache(): ()
            local now: number = os.clock()
            if now - lastCacheRefresh < 0.15 then
                return
            end
            lastCacheRefresh = now

            local seen: {[BasePart]: boolean} = {}
            local list: {BasePart} = {}

            local function addCandidate(candidate: Instance?): ()
                if not candidate or not stillCollectable(candidate) then
                    return
                end
                local serverPart: BasePart? = serverPartOf(candidate)
                if serverPart and not seen[serverPart] then
                    seen[serverPart] = true
                    table.insert(list, serverPart)
                end
            end

            -- 1. Direct map CoinContainer scan: sees every Coin_Server on the active map
            --    even at the far end of the map, with O(coins) cost.
            if type(core.findMM2Map) == "function" then
                local okMap: boolean, map: any = pcall(core.findMM2Map)
                if okMap and map then
                    local okContainer: boolean, container: any = pcall(function(): any
                        return map:FindFirstChild("CoinContainer")
                    end)
                    if okContainer and container then
                        local okChildren: boolean, children: any = pcall(function(): any
                            return container:GetChildren()
                        end)
                        if okChildren and type(children) == "table" then
                            for _, child: Instance in ipairs(children) do
                                addCandidate(child)
                            end
                        end
                    end
                end
            end

            -- 2. Shared Coin ESP pickup detector (3 signatures: CoinVisual tag,
            --    CoinID attribute, Coin_Server/CoinVisual structure).
            if type(state.mm2CoinPickups) == "function" then
                local okPickups: boolean, pickups: any = pcall(state.mm2CoinPickups)
                if okPickups and type(pickups) == "table" then
                    for _, pickup: Instance in ipairs(pickups) do
                        addCandidate(pickup)
                    end
                end
            end

            -- 3. Direct CollectionService CoinVisual tag list.
            local okTagged: boolean, tagged: any = pcall(function(): any
                return game:GetService("CollectionService"):GetTagged("CoinVisual")
            end)
            if okTagged and type(tagged) == "table" then
                for _, obj: Instance in ipairs(tagged) do
                    addCandidate(obj)
                end
            end

            cachedServerCoins = list
        end

        local function auraTick(): ()
            local root: BasePart? = characterRoot()
            if not root then
                return
            end

            refreshCache()

            local range: number = math.clamp(tonumber(settings.range) or 100, 5, 1000)
            local rangeSq: number = range * range
            local rootPos: Vector3 = root.Position

            for i: number = 1, #cachedServerCoins do
                local serverCoin: BasePart = cachedServerCoins[i]
                if stillCollectable(serverCoin) then
                    local okPos: boolean, coinPos: any = pcall(function(): any
                        return serverCoin.Position
                    end)
                    if okPos and typeof(coinPos) == "Vector3" then
                        local diff: Vector3 = (coinPos :: Vector3) - rootPos
                        if diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z <= rangeSq then
                            pulseCoinTouch(root, serverCoin)
                        end
                    end
                end
            end

            setStatus(tostring(math.round(range)) .. " studs")
        end

        featureConnections.MM2CoinsAura = TaskManager:Connect(auraTick)
        auraTick()
    end

    CoinsAuraFeature = createUniversalFeature(
        "Coins Aura",
        "Detects coins within Range across the map and pulses firetouchinterest from your character root to Coin_Server without teleporting.",
        7,
        toggleCoinsAura,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2CoinsAuraFeature = CoinsAuraFeature

    addNumberOption(
        CoinsAuraFeature,
        "Range",
        100,
        5,
        1000,
        function(value: number): ()
            settings.range = math.clamp(tonumber(value) or 100, 5, 1000)
            if CoinsAuraFeature.enabled then
                CoinsAuraFeature:SetStatus(tostring(math.round(settings.range)) .. " studs")
            end
        end,
        "Distance in studs around your character to detect and pulse coins (up to 1000 studs across the entire map).",
        5
    )

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
