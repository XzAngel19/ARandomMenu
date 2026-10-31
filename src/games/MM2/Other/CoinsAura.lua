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

    -- Maximum coin pickup distance accepted by the MM2 server (~15 studs).
    local MAX_SERVER_REACH: number = 15
    local MAX_SERVER_REACH_SQ: number = MAX_SERVER_REACH * MAX_SERVER_REACH
    local TICK_INTERVAL: number = 0.08
    local CACHE_INTERVAL: number = 0.5

    local savedCFrames: {[BasePart]: CFrame} = {}
    local savedPositions: {[BasePart]: Vector3} = {}
    local activeCoin: BasePart? = nil

    local function rememberCoin(serverPart: BasePart): Vector3?
        local pos: Vector3? = savedPositions[serverPart]
        if pos then
            return pos
        end
        local cf: CFrame = serverPart.CFrame
        savedCFrames[serverPart] = cf
        savedPositions[serverPart] = cf.Position
        return cf.Position
    end

    local function restoreCoin(serverPart: BasePart?): ()
        if not serverPart then
            return
        end
        local cf: CFrame? = savedCFrames[serverPart]
        if cf and serverPart.Parent then
            pcall(function(): ()
                serverPart.CFrame = cf
            end)
        end
        if activeCoin == serverPart then
            activeCoin = nil
        end
    end

    local function restoreAllCoins(): ()
        for serverPart, cf in pairs(savedCFrames) do
            if serverPart and serverPart.Parent then
                pcall(function(): ()
                    serverPart.CFrame = cf
                end)
            end
        end
        table.clear(savedCFrames)
        table.clear(savedPositions)
        activeCoin = nil
    end

    local function isCoinCollectable(serverPart: BasePart): boolean
        if not serverPart or not serverPart.Parent then
            return false
        end
        if serverPart:GetAttribute("Collected") == true
            or serverPart:GetAttribute("Delete") == true then
            return false
        end
        local visual: Instance? = serverPart:FindFirstChild("CoinVisual")
        if visual and (
            visual:GetAttribute("Collected") == true
            or visual:GetAttribute("Delete") == true
        ) then
            return false
        end
        return true
    end

    -- Detach CoinVisual's WeldConstraint once before pulling Coin_Server so
    -- moving Coin_Server never triggers rigid-body weld recalculation or
    -- fights CoinVisualizer's PreSimulation spin.
    local function detachVisualWeld(serverPart: BasePart): ()
        local visual: Instance? = serverPart:FindFirstChild("CoinVisual")
        if not visual or not visual:IsA("BasePart") then
            return
        end
        local vPart: BasePart = visual :: BasePart
        vPart.Anchored = true
        local weld: Instance? = vPart:FindFirstChildOfClass("WeldConstraint")
        if weld then
            (weld :: WeldConstraint).Enabled = false
        end
    end

    local function pulseCoinTouch(root: BasePart, serverPart: BasePart): ()
        rememberCoin(serverPart)
        detachVisualWeld(serverPart)
        serverPart.CanCollide = false
        serverPart.CFrame = root.CFrame
        local fireTouch: any = state.fireTouchInterest
        if type(fireTouch) == "function" then
            pcall(fireTouch, root, serverPart, 0)
            pcall(fireTouch, root, serverPart, 1)
        end
    end

    local CoinsAuraFeature: any = nil

    local function toggleCoinsAura(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinsAura")
        restoreAllCoins()

        if not enabled then
            if CoinsAuraFeature then
                CoinsAuraFeature:SetStatus(nil)
            end
            return
        end

        local cachedCoins: {BasePart} = {}
        local lastCacheAt: number = -math.huge
        local lastTickAt: number = -math.huge

        if CoinsAuraFeature then
            CoinsAuraFeature:SetStatus("Max reach")
        end

        local function refreshCoins(now: number): ()
            if now - lastCacheAt < CACHE_INTERVAL then
                return
            end
            lastCacheAt = now

            local list: {BasePart} = {}
            local seen: {[BasePart]: boolean} = {}

            local function addCoin(candidate: Instance?): ()
                if not candidate then
                    return
                end
                local serverPart: BasePart? = nil
                if candidate:IsA("BasePart") then
                    if candidate.Name == "Coin_Server" or candidate.Name == "ServerCoinPart" then
                        serverPart = candidate :: BasePart
                    elseif candidate.Parent and candidate.Parent:IsA("BasePart")
                        and (candidate.Parent.Name == "Coin_Server" or candidate.Parent.Name == "ServerCoinPart") then
                        serverPart = candidate.Parent :: BasePart
                    else
                        serverPart = candidate :: BasePart
                    end
                elseif candidate:IsA("Model") then
                    local child: Instance? = candidate:FindFirstChild("Coin_Server")
                        or candidate:FindFirstChildWhichIsA("BasePart")
                    if child and child:IsA("BasePart") then
                        serverPart = child :: BasePart
                    end
                end
                if serverPart and not seen[serverPart] and isCoinCollectable(serverPart) then
                    seen[serverPart] = true
                    rememberCoin(serverPart)
                    list[#list + 1] = serverPart
                end
            end

            if type(core.findMM2Map) == "function" then
                local map: Instance? = core.findMM2Map()
                if map then
                    local container: Instance? = map:FindFirstChild("CoinContainer")
                        or map:FindFirstChild("CoinAreas")
                        or map:FindFirstChild("Coins")
                    if container then
                        for _, child: Instance in ipairs(container:GetChildren()) do
                            addCoin(child)
                        end
                    end
                end
            end

            if #list == 0 and type(state.mm2CoinPickups) == "function" then
                local okPickups: boolean, pickups: any = pcall(state.mm2CoinPickups)
                if okPickups and type(pickups) == "table" then
                    for _, pickup: Instance in ipairs(pickups) do
                        addCoin(pickup)
                    end
                end
            end

            cachedCoins = list
        end

        local function auraTick(): ()
            local now: number = os.clock()
            if now - lastTickAt < TICK_INTERVAL then
                return
            end
            lastTickAt = now

            local character: Model? = LocalPlayer and LocalPlayer.Character
            local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not root then
                if activeCoin then
                    restoreCoin(activeCoin)
                end
                return
            end
            local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if humanoid and humanoid.Health <= 0 then
                if activeCoin then
                    restoreCoin(activeCoin)
                end
                return
            end

            refreshCoins(now)

            local rootPos: Vector3 = root.Position
            local bestCoin: BasePart? = nil
            local bestDistSq: number = MAX_SERVER_REACH_SQ

            for i: number = 1, #cachedCoins do
                local coin: BasePart = cachedCoins[i]
                if isCoinCollectable(coin) then
                    local coinPos: Vector3? = savedPositions[coin] or rememberCoin(coin)
                    if coinPos then
                        local diff: Vector3 = coinPos - rootPos
                        local distSq: number = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z
                        if distSq <= bestDistSq then
                            bestDistSq = distSq
                            bestCoin = coin
                        end
                    end
                elseif coin == activeCoin then
                    restoreCoin(coin)
                end
            end

            if activeCoin and activeCoin ~= bestCoin then
                restoreCoin(activeCoin)
            end

            if bestCoin then
                activeCoin = bestCoin
                pcall(pulseCoinTouch, root, bestCoin)
            end
        end

        featureConnections.MM2CoinsAura = TaskManager:Connect(auraTick, nil, "MM2 Coins Aura")
        auraTick()
    end

    CoinsAuraFeature = createUniversalFeature(
        "Coins Aura",
        "Automatically collects nearby coins at the maximum reach allowed by the MM2 server with minimal CPU usage.",
        7,
        toggleCoinsAura,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2CoinsAuraFeature = CoinsAuraFeature

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
