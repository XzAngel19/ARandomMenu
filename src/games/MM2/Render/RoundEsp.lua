local Module = {
    Name = "MM2 Round ESP",
    PlaceId = 142823291,
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
    assert(type(core) == "table", "MM2 Round ESP requires the MM2 core module")
    Module.Runtime = runtime
    local CoinEffects: any = core.CoinEffects
    local GunEffects: any = core.GunEffects
    local TrapEffects: any = core.TrapEffects
    local clearEffects: any = core.clearEffects
    local createMM2Cham: any = core.createMM2Cham
    local createMM2Marker: any = core.createMM2Marker
    local findDroppedGun: any = core.findDroppedGun
    local findMM2Map: any = core.findMM2Map
    local mm2GameplayRemotes: any = core.mm2GameplayRemotes
    local mm2Settings: any = core.mm2Settings

    local function toggleGunEsp(enabled)
        disconnectFeatureConnection("MM2GunESP")
        clearEffects(GunEffects)

        if not enabled then
            return
        end

        local elapsed = 1
        featureConnections.MM2GunESP = TaskManager:Connect(function(deltaTime)
            elapsed = elapsed + deltaTime
            if elapsed < 0.5 then
                return
            end
            elapsed = 0
            clearEffects(GunEffects)
            local gun = findDroppedGun()
            if gun then
                createMM2Marker(
                    GunEffects,
                    gun,
                    "Gun",
                    mm2Settings.gunColor,
                    mm2Settings.gunTransparency
                )
            end
        end)
    end

    local function toggleTrapEsp(enabled)
        disconnectFeatureConnection("MM2TrapAdded")
        clearEffects(TrapEffects)

        if not enabled then
            return
        end

        local marked = setmetatable({}, {__mode = "k"})
        local function addTrap(object)
            if marked[object] then
                return
            end
            if (object.Name == "TrapVisual" or object.Name == "Trap")
                and (object:IsA("Model") or object:IsA("BasePart")) then
                marked[object] = true
                createMM2Cham(
                    TrapEffects,
                    object,
                    mm2Settings.trapColor,
                    mm2Settings.trapTransparency
                )
            end
        end

        local map = findMM2Map()
        for _, object in ipairs((map or workspace):GetDescendants()) do
            addTrap(object)
        end
        featureConnections.MM2TrapAdded = workspace.DescendantAdded:Connect(addTrap)
    end

    local coinChamsEnabled: boolean = false

    type CoinChamRecord = {
        highlight: Highlight,
        billboard: BillboardGui,
        connections: {RBXScriptConnection},
    }

    local coinBoxes: {[BasePart]: CoinChamRecord} =
        setmetatable({}, {__mode = "k"}) :: any

    local function normalizedCoinName(object: Instance): string
        return string.gsub(string.lower(object.Name), "[^%w]", "")
    end

    local function hasCoinName(object: Instance): boolean
        return string.find(normalizedCoinName(object), "coin", 1, true) ~= nil
    end

    local function isCoinServerName(object: Instance): boolean
        return string.find(
            normalizedCoinName(object),
            "coinserver",
            1,
            true
        ) ~= nil
    end

    local function isLiveCoin(coin: BasePart): boolean
        return coin:IsDescendantOf(workspace)
            and coin:GetAttribute("Delete") ~= true
            and coin:GetAttribute("Collected") ~= true
    end

    local function findCoinPartInContainer(container: Instance): BasePart?
        for _, descendant: Instance in ipairs(container:GetDescendants()) do
            if descendant:IsA("BasePart") and isCoinServerName(descendant) then
                return descendant
            end
        end

        if container:IsA("Model") and container.PrimaryPart then
            return container.PrimaryPart
        end
        for _, preferredName: string in ipairs({
            "CoinVisual",
            "MainCoin",
            "Coin",
        }) do
            local preferred: Instance? =
                container:FindFirstChild(preferredName, true)
            if preferred and preferred:IsA("BasePart") then
                return preferred
            end
        end
        return container:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getCoinServer(object: Instance?): BasePart?
        if not object or object:GetAttribute("Delete") == true then
            return nil
        end

        local coinContainer: Instance? = nil
        local cursor: Instance? = object
        for _index: number = 1, 10 do
            if not cursor or cursor == workspace then
                break
            end
            if cursor:IsA("BasePart") and isCoinServerName(cursor) then
                return isLiveCoin(cursor) and cursor or nil
            end
            if (cursor:IsA("Model") or cursor:IsA("Folder"))
                and hasCoinName(cursor) then
                coinContainer = cursor
            end
            cursor = cursor.Parent
        end

        if coinContainer then
            local containerPart: BasePart? =
                findCoinPartInContainer(coinContainer)
            if containerPart and isLiveCoin(containerPart) then
                return containerPart
            end
        end

        if object:IsA("BasePart") and hasCoinName(object) then
            return isLiveCoin(object) and object or nil
        end

        if object:IsA("TouchTransmitter") or object.Name == "TouchInterest" then
            local parent: Instance? = object.Parent
            if parent and parent:IsA("BasePart") then
                local ancestor: Instance? = parent
                while ancestor and ancestor ~= workspace do
                    if hasCoinName(ancestor) then
                        return isLiveCoin(parent) and parent or nil
                    end
                    ancestor = ancestor.Parent
                end
            end
        end
        return nil
    end

    local function getCoinVisual(coin: BasePart): BasePart
        local mainCoin: Instance? = coin:FindFirstChild("MainCoin", true)
        if mainCoin and mainCoin:IsA("BasePart") then
            return mainCoin
        end
        local coinVisual: Instance? = coin:FindFirstChild("CoinVisual", true)
        if coinVisual and coinVisual:IsA("BasePart") then
            return coinVisual
        end
        return coin
    end

    local function removeCoinBox(coin: BasePart): ()
        local record: CoinChamRecord? = coinBoxes[coin]
        if not record then
            return
        end
        coinBoxes[coin] = nil
        for _, connection: RBXScriptConnection in ipairs(record.connections) do
            connection:Disconnect()
        end
        record.highlight:Destroy()
        record.billboard:Destroy()
    end

    local function clearCoinBoxes(): ()
        for coin: BasePart in pairs(coinBoxes) do
            removeCoinBox(coin)
        end
        clearEffects(CoinEffects)
        coinBoxes = setmetatable({}, {__mode = "k"}) :: any
    end

    local function createCoinBillboard(adornee: BasePart): BillboardGui
        local billboard: BillboardGui = Instance.new("BillboardGui")
        billboard.Name = "Wurst_CoinMarker"
        billboard.Adornee = adornee
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.25, 0)
        billboard.Parent = CoinEffects

        local marker: Frame = Instance.new("Frame")
        marker.Name = "Marker"
        marker.AnchorPoint = Vector2.new(0.5, 0.5)
        marker.BackgroundColor3 = mm2Settings.coinColor
        marker.BackgroundTransparency = 0.18
        marker.BorderSizePixel = 0
        marker.Position = UDim2.fromScale(0.5, 0.5)
        marker.Rotation = 45
        marker.Size = UDim2.fromOffset(20, 20)
        marker.Parent = billboard

        local corner: UICorner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 2)
        corner.Parent = marker

        local stroke: UIStroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 248, 170)
        stroke.Thickness = 2
        stroke.Transparency = 0.08
        stroke.Parent = marker
        return billboard
    end

    local function addCoinBox(object: Instance): ()
        local coin: BasePart? = getCoinServer(object)
        if not coin then
            return
        end

        local visual: BasePart = getCoinVisual(coin)
        local existing: CoinChamRecord? = coinBoxes[coin]
        if existing then
            existing.highlight.Adornee = visual
            existing.billboard.Adornee = visual
            return
        end

        local highlight: Highlight = Instance.new("Highlight")
        highlight.Name = "Wurst_CoinHighlight"
        highlight.Adornee = visual
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = mm2Settings.coinColor
        highlight.FillTransparency = math.clamp(
            mm2Settings.coinTransparency * 0.65,
            0.15,
            0.62
        )
        highlight.OutlineColor = Color3.fromRGB(255, 246, 135)
        highlight.OutlineTransparency = 0.04
        highlight.Parent = coin

        local record: CoinChamRecord = {
            highlight = highlight,
            billboard = createCoinBillboard(visual),
            connections = {},
        }
        coinBoxes[coin] = record
        table.insert(record.connections, coin.AncestryChanged:Connect(function(): ()
            if not isLiveCoin(coin) then
                removeCoinBox(coin)
            end
        end))
        for _, attributeName: string in ipairs({"Collected", "Delete"}) do
            table.insert(
                record.connections,
                coin:GetAttributeChangedSignal(attributeName):Connect(function(): ()
                    if not isLiveCoin(coin) then
                        removeCoinBox(coin)
                    end
                end)
            )
        end
    end

    local function isPotentialCoinObject(object: Instance): boolean
        return hasCoinName(object)
            or object:IsA("TouchTransmitter")
            or object.Name == "TouchInterest"
            or CollectionService:HasTag(object, "CoinVisual")
    end

    local function scanCoins(container: Instance): ()
        if isPotentialCoinObject(container) then
            addCoinBox(container)
        end
        for _, object: Instance in ipairs(container:GetDescendants()) do
            if isPotentialCoinObject(object) then
                addCoinBox(object)
            end
        end
    end

    local function toggleCoinChams(enabled: boolean): ()
        coinChamsEnabled = enabled
        disconnectFeatureConnection("MM2CoinAdded")
        disconnectFeatureConnection("MM2CoinTagged")
        disconnectFeatureConnection("MM2CoinCollected")
        disconnectFeatureConnection("MM2CoinMapAdded")
        clearCoinBoxes()

        if not enabled then
            return
        end

        scanCoins(workspace)
        for _, object: Instance in ipairs(
            CollectionService:GetTagged("CoinVisual")
        ) do
            addCoinBox(object)
        end

        featureConnections.MM2CoinTagged = CollectionService
            :GetInstanceAddedSignal("CoinVisual")
            :Connect(addCoinBox)
        featureConnections.MM2CoinAdded = workspace.DescendantAdded:Connect(function(
            object: Instance
        ): ()
            if isPotentialCoinObject(object) then
                addCoinBox(object)
            end
        end)
        featureConnections.MM2CoinMapAdded = workspace.ChildAdded:Connect(function(
            object: Instance
        ): ()
            task.defer(function(): ()
                if coinChamsEnabled then
                    scanCoins(object)
                end
            end)
        end)

        for _, rescanDelay: number in ipairs({0.5, 1.5, 3}) do
            task.delay(rescanDelay, function(): ()
                if coinChamsEnabled then
                    scanCoins(workspace)
                end
            end)
        end

        local coinCollected: Instance? = mm2GameplayRemotes
            and mm2GameplayRemotes:FindFirstChild("CoinCollected")
        if coinCollected and coinCollected:IsA("RemoteEvent") then
            featureConnections.MM2CoinCollected = coinCollected.OnClientEvent:Connect(
                function(coinId: any): ()
                    for coin: BasePart in pairs(coinBoxes) do
                        if coin:GetAttribute("CoinID") == coinId then
                            removeCoinBox(coin)
                        end
                    end
                end
            )
        end
    end

    registerEspExtra({
        Name = "Coins",
        Default = false,
        Color = mm2Settings.coinColor,
        Tooltip = "Every coin on the map, through walls.",
        Toggle = function(enabled: boolean): ()
            toggleCoinChams(enabled)
        end,
        SetColor = function(colour: Color3): ()
            mm2Settings.coinColor = colour
            if coinChamsEnabled then
                toggleCoinChams(true)
            end
        end,
    })
    registerEspExtra({
        Name = "Traps",
        Default = false,
        Color = mm2Settings.trapColor,
        Tooltip = "The murderer's placed traps.",
        Toggle = function(enabled: boolean): ()
            toggleTrapEsp(enabled)
        end,
        SetColor = function(colour: Color3): ()
            mm2Settings.trapColor = colour
        end,
    })
    registerEspExtra({
        Name = "Sheriff gun",
        Default = false,
        Color = mm2Settings.gunColor,
        Tooltip = "The gun on the floor after the sheriff dies.",
        Toggle = function(enabled: boolean): ()
            toggleGunEsp(enabled)
        end,
        SetColor = function(colour: Color3): ()
            mm2Settings.gunColor = colour
        end,
    })

    activeCleanup = function(): ()
        toggleGunEsp(false)
                toggleTrapEsp(false)
                toggleCoinChams(false)
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
