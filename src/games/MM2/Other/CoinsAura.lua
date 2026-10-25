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
        range = 15,
    }

    local savedServerStates: {[BasePart]: {cframe: CFrame, size: Vector3, canCollide: boolean}} = {}

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
    -- MM2 spawns pickups as: CoinContainer -> Coin_Server (Part) -> CoinVisual (Part) -> MainCoin,
    -- or sibling Coin_Server / ServerCoinPart inside a coin model.
    local function serverPartOf(part: Instance): BasePart?
        if part:IsA("BasePart") and (part.Name == "Coin_Server" or part.Name == "ServerCoinPart") then
            return part :: BasePart
        end
        local current: Instance? = part.Parent
        local depth: number = 0
        while current and current ~= workspace and depth < 4 do
            if current:IsA("BasePart") and (current.Name == "Coin_Server" or current.Name == "ServerCoinPart") then
                return current :: BasePart
            end
            if current:IsA("Model") or current:IsA("Folder") then
                local sibling: Instance? = current:FindFirstChild("Coin_Server")
                    or current:FindFirstChild("ServerCoinPart")
                if sibling and sibling:IsA("BasePart") then
                    return sibling :: BasePart
                end
            end
            current = current.Parent
            depth += 1
        end
        if part:IsA("Model") then
            local childServer: Instance? = part:FindFirstChild("Coin_Server", true)
                or part:FindFirstChild("ServerCoinPart", true)
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
                or part:FindFirstChild("ServerCoinPart")
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
        local parent: Instance? = serverPart.Parent
        if parent and parent ~= workspace then
            local siblingVisual: Instance? = parent:FindFirstChild("CoinVisual")
            if siblingVisual and siblingVisual:IsA("BasePart") then
                return siblingVisual :: BasePart
            end
        end
        return nil
    end

    local function rememberServerState(serverPart: BasePart): {cframe: CFrame, size: Vector3, canCollide: boolean}?
        local existing = savedServerStates[serverPart]
        if existing then
            return existing
        end
        local ok: boolean, snap: any = pcall(function(): any
            return {
                cframe = serverPart.CFrame,
                size = serverPart.Size,
                canCollide = serverPart.CanCollide,
            }
        end)
        if ok and type(snap) == "table" then
            savedServerStates[serverPart] = snap
            return snap
        end
        return nil
    end

    local function restoreServerPart(serverPart: BasePart): ()
        local snap = savedServerStates[serverPart]
        if not snap then
            return
        end
        if serverPart and serverPart.Parent then
            pcall(function(): ()
                serverPart.CFrame = snap.cframe
                serverPart.Size = snap.size
                serverPart.CanCollide = snap.canCollide
            end)
        end
        savedServerStates[serverPart] = nil
    end

    local function restoreAllServerParts(): ()
        for serverPart in pairs(savedServerStates) do
            restoreServerPart(serverPart)
        end
        table.clear(savedServerStates)
    end

    -- True world position of the coin (from its saved spawn CFrame or CoinVisual),
    -- never polluted if Coin_Server was pulled to root.CFrame.
    local function trueCoinPosition(serverPart: BasePart): Vector3?
        local snap = savedServerStates[serverPart]
        if snap and snap.cframe then
            local okSnap: boolean, pos: any = pcall(function(): any
                return snap.cframe.Position
            end)
            if okSnap and typeof(pos) == "Vector3" then
                return pos :: Vector3
            end
        end
        local visual: BasePart? = visualPartOf(serverPart)
        if visual and visual ~= serverPart then
            local okVis: boolean, pos: any = pcall(function(): any
                return visual.Position
            end)
            if okVis and typeof(pos) == "Vector3" then
                return pos :: Vector3
            end
        end
        local okPos: boolean, pos: any = pcall(function(): any
            return serverPart.Position
        end)
        if okPos and typeof(pos) == "Vector3" then
            return pos :: Vector3
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

    -- Touch the coin using both physical overlap (pulling invisible Coin_Server
    -- to root.CFrame while keeping CoinVisual fixed) and firetouchinterest.
    -- This ensures executors where firetouchinterest requires bounding-box
    -- intersection still trigger the server's TouchTransmitter immediately.
    local function pulseCoinTouch(root: BasePart, serverPart: BasePart): boolean
        rememberServerState(serverPart)
        local visual: BasePart? = visualPartOf(serverPart)
        local savedVisualCFrame: CFrame? = nil
        if visual and visual ~= serverPart then
            pcall(function(): ()
                savedVisualCFrame = visual.CFrame
            end)
        end

        pcall(function(): ()
            serverPart.CanCollide = false
            if root.CFrame then
                serverPart.CFrame = root.CFrame
            end
        end)

        if visual and savedVisualCFrame then
            pcall(function(): ()
                visual.CFrame = savedVisualCFrame
            end)
        end

        local fireTouch: any = state.fireTouchInterest
        if type(fireTouch) == "function" then
            pcall(fireTouch, root, serverPart, 0)
            pcall(fireTouch, root, serverPart, 1)
            if visual and visual ~= serverPart then
                pcall(fireTouch, root, visual, 0)
                pcall(fireTouch, root, visual, 1)
            end
        end
        return true
    end

    local CoinsAuraFeature: any = nil

    local function toggleCoinsAura(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinsAura")
        restoreAllServerParts()

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
                    rememberServerState(serverPart)
                    table.insert(list, serverPart)
                end
            end

            -- 1. Direct map CoinContainer / CoinAreas / Coins scan.
            if type(core.findMM2Map) == "function" then
                local okMap: boolean, map: any = pcall(core.findMM2Map)
                if okMap and map then
                    for _, containerName: string in ipairs({"CoinContainer", "CoinAreas", "Coins"}) do
                        local okContainer: boolean, container: any = pcall(function(): any
                            return map:FindFirstChild(containerName)
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

            -- 3. Direct CollectionService CoinVisual / ServerCoinPart tag lists.
            local cs: any = game:GetService("CollectionService")
            for _, tagName: string in ipairs({"CoinVisual", "ServerCoinPart"}) do
                local okTagged: boolean, tagged: any = pcall(function(): any
                    return cs:GetTagged(tagName)
                end)
                if okTagged and type(tagged) == "table" then
                    for _, obj: Instance in ipairs(tagged) do
                        addCandidate(obj)
                    end
                end
            end

            cachedServerCoins = list
        end

        local function auraTick(): ()
            local root: BasePart? = characterRoot()
            if not root then
                restoreAllServerParts()
                return
            end

            refreshCache()

            local range: number = math.clamp(tonumber(settings.range) or 15, 4, 100)
            local rangeSq: number = range * range
            local rootPos: Vector3 = root.Position

            -- Collect only coins within Range and sort nearest-first so distant
            -- coins never trigger server touch debounce before close coins.
            local candidates: {{part: BasePart, distSq: number}} = {}
            local inRangeSet: {[BasePart]: boolean} = {}

            for i: number = 1, #cachedServerCoins do
                local serverCoin: BasePart = cachedServerCoins[i]
                if stillCollectable(serverCoin) then
                    local coinPos: Vector3? = trueCoinPosition(serverCoin)
                    if coinPos then
                        local diff: Vector3 = coinPos - rootPos
                        local distSq: number = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z
                        if distSq <= rangeSq then
                            table.insert(candidates, {part = serverCoin, distSq = distSq})
                        end
                    end
                else
                    restoreServerPart(serverCoin)
                end
            end

            table.sort(candidates, function(a, b): boolean
                return a.distSq < b.distSq
            end)

            -- Touch the nearest coins in range (up to 3 closest per frame)
            local limit: number = math.min(#candidates, 3)
            for i: number = 1, limit do
                local coin: BasePart = candidates[i].part
                inRangeSet[coin] = true
                pulseCoinTouch(root, coin)
            end

            -- Restore any coin that moved out of active touch set
            for serverPart in pairs(savedServerStates) do
                if not inRangeSet[serverPart] or not stillCollectable(serverPart) then
                    restoreServerPart(serverPart)
                end
            end

            setStatus(tostring(math.round(range)) .. " studs")
        end

        featureConnections.MM2CoinsAura = TaskManager:Connect(auraTick)
        auraTick()
    end

    CoinsAuraFeature = createUniversalFeature(
        "Coins Aura",
        "Collects nearby coins within Range by pulling the invisible Coin_Server trigger to your root and pulsing firetouchinterest (nearest coin first).",
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
        15,
        4,
        100,
        function(value: number): ()
            settings.range = math.clamp(tonumber(value) or 15, 4, 100)
            if CoinsAuraFeature.enabled then
                CoinsAuraFeature:SetStatus(tostring(math.round(settings.range)) .. " studs")
            end
        end,
        "Effective distance in studs around your character to collect coins (nearest coin first; MM2 server caps coin reach around 10-15 studs).",
        1
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
