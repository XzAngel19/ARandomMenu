local Module = {
    Name = "MM2 Coin ESP",
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
    assert(type(core) == "table", "MM2 Coin ESP requires the MM2 core module")
    Module.Runtime = runtime

    local CoinEffects: any = core.CoinEffects
    local clearEffects: any = core.clearEffects
    local mm2Settings: any = core.mm2Settings
    local findCoinContainer: any = core.findCoinContainer
    local getCoinTypeFromInstance: any = core.getCoinTypeFromInstance
    local normalizeCoinType: any = core.normalizeCoinType
    local isPotentialCoinObject: any = core.isPotentialCoinObject
    local isCoinLikeName: any = core.isCoinLikeName
    local getCoinServer: any = core.getCoinServer
    local isLiveCoin: any = core.isLiveCoin
    local findCoinPartInContainer: any = core.findCoinPartInContainer
    local getAllCoinTypesDetected: any = core.getAllCoinTypesDetected
    local shouldShowCoinType: any = core.shouldShowCoinType
    local normalizedCoinName: any = core.normalizedCoinName
    local findMM2Map: any = core.findMM2Map

    local coinChamsEnabled: boolean = false
    local detectedTypesCache: {string} = {}
    local lastDetectAt: number = -math.huge

    type CoinChamRecord = {
        highlight: Highlight,
        billboard: BillboardGui,
        connections: {RBXScriptConnection},
        coinType: string?,
        root: Instance,
    }

    local coinBoxes: {[BasePart]: CoinChamRecord} = setmetatable({}, {__mode = "k"}) :: any

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
            pcall(function() connection:Disconnect() end)
        end
        if record.highlight then pcall(function() record.highlight:Destroy() end) end
        if record.billboard then pcall(function() record.billboard:Destroy() end) end
    end

    local function clearCoinBoxes(): ()
        for coin: BasePart in pairs(coinBoxes) do
            removeCoinBox(coin)
        end
        clearEffects(CoinEffects)
        coinBoxes = setmetatable({}, {__mode = "k"}) :: any
    end

    local function createCoinBillboard(adornee: BasePart, coinType: string?): BillboardGui
        local billboard: BillboardGui = Instance.new("BillboardGui")
        billboard.Name = "Wurst_CoinMarker_" .. (coinType or "Coin")
        billboard.Adornee = adornee
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.Size = UDim2.fromOffset(42, 22)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
        billboard.Parent = CoinEffects

        local marker: Frame = Instance.new("Frame")
        marker.Name = "Marker"
        marker.BackgroundColor3 = mm2Settings.coinColor
        marker.BackgroundTransparency = 0.18
        marker.BorderSizePixel = 0
        marker.Size = UDim2.fromScale(1, 1)
        marker.Parent = billboard

        local corner: UICorner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = marker

        local stroke: UIStroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 248, 170)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.08
        stroke.Parent = marker

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.Text = coinType or "Coin"
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextStrokeTransparency = 0.2
        label.TextScaled = true
        label.Parent = marker

        return billboard
    end

    local function resolveCoinTypeForInstance(rootInstance: Instance, coinPart: BasePart): string?
        -- Try direct attribute on root, then on part, then name
        local t = getCoinTypeFromInstance(rootInstance)
        if t then return t end
        t = getCoinTypeFromInstance(coinPart)
        if t then return t end
        -- Check parent chain for type
        local cur: Instance? = coinPart.Parent
        for _ = 1, 6 do
            if not cur then break end
            local ct = getCoinTypeFromInstance(cur)
            if ct then return ct end
            cur = cur.Parent
        end
        -- Fallback: guess from name
        local norm = normalizeCoinType(rootInstance.Name) or normalizeCoinType(coinPart.Name)
        return norm or "Coin"
    end

    local function addCoinBox(object: Instance): ()
        local coin: BasePart? = getCoinServer(object)
        if not coin then
            -- Also try if object itself is a coin container model with CoinID attribute
            if object:IsA("Model") or object:IsA("Folder") then
                local ct = getCoinTypeFromInstance(object)
                if ct then
                    local part = findCoinPartInContainer(object)
                    if part and isLiveCoin(part) then
                        coin = part
                    end
                end
            end
            if not coin then return end
        end

        -- Determine type for filtering
        local rootForType: Instance = object
        -- If object is TouchTransmitter, use parent model as root
        if object:IsA("TouchTransmitter") or object.Name == "TouchInterest" then
            local p = object.Parent
            if p and p.Parent then
                rootForType = p.Parent
            elseif p then
                rootForType = p
            end
        else
            -- Walk up to find container model that has CoinID
            local cur: Instance? = object
            for _ = 1, 8 do
                if not cur then break end
                if cur:GetAttribute("CoinID") ~= nil or cur:FindFirstChild("CoinType") then
                    rootForType = cur
                    break
                end
                cur = cur.Parent
            end
        end

        local coinType = resolveCoinTypeForInstance(rootForType, coin)
        if not shouldShowCoinType(coinType) then
            -- If already exists but now filtered out, remove
            if coinBoxes[coin] then removeCoinBox(coin) end
            return
        end

        local visual: BasePart = getCoinVisual(coin)
        local existing: CoinChamRecord? = coinBoxes[coin]
        if existing then
            -- Update if type changed or adornee changed
            existing.highlight.Adornee = visual
            existing.billboard.Adornee = visual
            if existing.coinType ~= coinType then
                existing.coinType = coinType
                local lbl = existing.billboard:FindFirstChild("Marker", true)
                if lbl then
                    local txt = lbl:FindFirstChildOfClass("TextLabel")
                    if txt then txt.Text = coinType or "Coin" end
                end
            end
            return
        end

        local highlight: Highlight = Instance.new("Highlight")
        highlight.Name = "Wurst_CoinHighlight"
        highlight.Adornee = visual
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = mm2Settings.coinColor
        highlight.FillTransparency = math.clamp(mm2Settings.coinTransparency * 0.65, 0.15, 0.62)
        highlight.OutlineColor = Color3.fromRGB(255, 246, 135)
        highlight.OutlineTransparency = 0.04
        highlight.Parent = coin

        local billboard = createCoinBillboard(visual, coinType)

        local record: CoinChamRecord = {
            highlight = highlight,
            billboard = billboard,
            connections = {},
            coinType = coinType,
            root = rootForType,
        }
        coinBoxes[coin] = record

        table.insert(record.connections, coin.AncestryChanged:Connect(function()
            if not isLiveCoin(coin) then
                removeCoinBox(coin)
            end
        end))
        for _, attrName in ipairs({"Collected", "Delete", "CollectedBy"}) do
            table.insert(record.connections, coin:GetAttributeChangedSignal(attrName):Connect(function()
                if not isLiveCoin(coin) then
                    removeCoinBox(coin)
                end
            end))
        end
        -- Also watch root removal
        if rootForType ~= coin then
            table.insert(record.connections, rootForType.AncestryChanged:Connect(function()
                if not rootForType.Parent then
                    removeCoinBox(coin)
                end
            end))
        end
    end

    local function scanCoins(container: Instance): ()
        if isPotentialCoinObject(container) then
            addCoinBox(container)
        end
        for _, obj: Instance in ipairs(container:GetDescendants()) do
            if isPotentialCoinObject(obj) then
                addCoinBox(obj)
            end
        end
    end

    local function refreshDetectedTypes(forceNotify: boolean?): ()
        if os.clock() - lastDetectAt < 1 and not forceNotify then return end
        lastDetectAt = os.clock()
        local types = getAllCoinTypesDetected()
        detectedTypesCache = types
        if #types > 0 and mm2Settings.coinAutoDetect then
            if forceNotify then
                notify("Detected coin types: " .. table.concat(types, ", "))
            end
            -- If Auto mode and we detected, we keep showing them; user can see status via status text
            if core.updateCoinStatus then
                pcall(core.updateCoinStatus, types)
            end
        end
    end

    local function toggleCoinChams(enabled: boolean): ()
        coinChamsEnabled = enabled
        disconnectFeatureConnection("MM2CoinAdded")
        disconnectFeatureConnection("MM2CoinTagged")
        disconnectFeatureConnection("MM2CoinCollected")
        disconnectFeatureConnection("MM2CoinMapAdded")
        disconnectFeatureConnection("MM2CoinContainerWatcher")
        disconnectFeatureConnection("MM2CoinTypeScanner")
        clearCoinBoxes()

        if not enabled then
            return
        end

        -- Initial scan
        scanCoins(workspace)
        local container = findCoinContainer()
        if container then
            scanCoins(container)
        end

        for _, obj: Instance in ipairs(CollectionService:GetTagged("CoinVisual")) do
            addCoinBox(obj)
        end

        refreshDetectedTypes(true)

        featureConnections.MM2CoinTagged = CollectionService:GetInstanceAddedSignal("CoinVisual"):Connect(addCoinBox)
        featureConnections.MM2CoinAdded = workspace.DescendantAdded:Connect(function(obj: Instance)
            if isPotentialCoinObject(obj) then
                addCoinBox(obj)
            end
        end)
        featureConnections.MM2CoinMapAdded = workspace.ChildAdded:Connect(function(obj: Instance)
            task.defer(function()
                if coinChamsEnabled then
                    scanCoins(obj)
                    refreshDetectedTypes(false)
                end
            end)
        end)

        -- Periodic rescan for new maps and type detection
        local elapsed = 0
        featureConnections.MM2CoinTypeScanner = TaskManager:Connect(function(dt: number)
            elapsed += dt
            if elapsed < 1.2 then return end
            elapsed = 0
            if coinChamsEnabled then
                local c = findCoinContainer()
                if c then
                    -- Only scan container children to be cheap
                    for _, child in ipairs(c:GetChildren()) do
                        if isPotentialCoinObject(child) then addCoinBox(child) end
                    end
                end
                refreshDetectedTypes(false)
            end
        end)

        -- Initial delayed rescans
        for _, delay in ipairs({0.5, 1.5, 3}) do
            task.delay(delay, function()
                if coinChamsEnabled then
                    scanCoins(workspace)
                    local cont = findCoinContainer()
                    if cont then scanCoins(cont) end
                    refreshDetectedTypes(false)
                end
            end)
        end

        local gameplayRemotes = core.mm2GameplayRemotes
        local coinCollected: Instance? = gameplayRemotes and gameplayRemotes:FindFirstChild("CoinCollected")
        if coinCollected and coinCollected:IsA("RemoteEvent") then
            featureConnections.MM2CoinCollected = coinCollected.OnClientEvent:Connect(function(coinId: any, current: any, max: any)
                -- Remove by CoinID attribute matching
                for coin: BasePart in pairs(coinBoxes) do
                    local attr = coin:GetAttribute("CoinID")
                    if attr == coinId then
                        removeCoinBox(coin)
                    else
                        -- Also check root model attribute
                        local rec = coinBoxes[coin]
                        if rec and rec.root then
                            local rAttr = rec.root:GetAttribute("CoinID")
                            if rAttr == coinId then
                                removeCoinBox(coin)
                            end
                        end
                    end
                end
                -- If bag full, optionally notify
                if type(current) == "number" and type(max) == "number" and current >= max then
                    if mm2Settings.coinAutoDetect then
                        -- Bag full, will reset soon
                    end
                end
            end)
        end
    end

    -- Expose for settings UI
    core.toggleCoinChams = toggleCoinChams
    core.getDetectedCoinTypes = function(): {string}
        return detectedTypesCache
    end
    core.refreshCoinTypes = function(): {string}
        refreshDetectedTypes(true)
        return detectedTypesCache
    end
    core.updateCoinStatus = nil -- placeholder for UI hook
    core.coinBoxesCount = function(): number
        local c = 0
        for _ in pairs(coinBoxes) do c += 1 end
        return c
    end

    -- Provider registration
    local unregister = {}
    local itemEsp = services and services.itemEsp
    assert(itemEsp and type(itemEsp.register) == "function", "MM2 Coin ESP requires the provider service")

    for _, provider in ipairs({
        {
            name = "Coin ESP",
            tooltip = "Highlights MM2 coins with support for all seasonal types (Coin, SnowToken, Candy, BeachBall, Egg, etc.). Auto-detects current currency.",
            setEnabled = toggleCoinChams,
        },
    }) do
        local release = itemEsp.register(provider)
        if release then table.insert(unregister, release) end
    end

    -- Enhanced UI: create a dedicated MM2 Coin feature with options for type selection, auto-detect, colors
    local hostEnv: any = getfenv()
    local createUniversalFeature: any = hostEnv.createUniversalFeature
    local addToggleOption: any = hostEnv.addToggleOption
    local addCycleOption: any = hostEnv.addCycleOption
    local addActionOption: any = hostEnv.addActionOption
    local addInformationOption: any = hostEnv.addInformationOption
    local addColorOption: any = hostEnv.addColorOption
    local addNumberOption: any = hostEnv.addNumberOption

    if type(createUniversalFeature) == "function" then
        local CoinFeature = createUniversalFeature(
            "Coin ESP Config",
            "Configure coin ESP: choose which seasonal currency to highlight, auto-detect current server type, colors.",
            19,
            function(_enabled: boolean) end,
            {category = true, parent = hostEnv.MM2Scroll, registry = hostEnv.mm2Features}
        )

        if CoinFeature then
            local coinTypeList = core.MM2_COIN_TYPE_LIST or {"Auto", "All", "Coin", "SnowToken", "Candy", "BeachBall", "Egg"}
            local defaultIndex = table.find(coinTypeList, mm2Settings.coinTypeFilter) or 1

            if type(addCycleOption) == "function" then
                addCycleOption(CoinFeature, "Coin type", coinTypeList, defaultIndex, function(value: string)
                    mm2Settings.coinTypeFilter = value
                    -- Refresh ESP if enabled
                    if coinChamsEnabled then
                        toggleCoinChams(false)
                        task.wait(0.1)
                        toggleCoinChams(true)
                    end
                end)
            end
            if type(addToggleOption) == "function" then
                addToggleOption(CoinFeature, "Auto-detect", mm2Settings.coinAutoDetect, function(value: boolean)
                    mm2Settings.coinAutoDetect = value
                end)
                addToggleOption(CoinFeature, "Show all in Auto", mm2Settings.coinShowAllInAuto, function(value: boolean)
                    mm2Settings.coinShowAllInAuto = value
                    if coinChamsEnabled then
                        toggleCoinChams(false)
                        task.wait(0.1)
                        toggleCoinChams(true)
                    end
                end)
            end
            if type(addColorOption) == "function" then
                addColorOption(CoinFeature, "Coin color", mm2Settings.coinColor, function(value: Color3)
                    mm2Settings.coinColor = value
                    if coinChamsEnabled then
                        -- Update existing highlights
                        for _, rec in pairs(coinBoxes) do
                            if rec.highlight then rec.highlight.FillColor = value end
                            local marker = rec.billboard and rec.billboard:FindFirstChild("Marker")
                            if marker then marker.BackgroundColor3 = value end
                        end
                    end
                end)
            end
            if type(addNumberOption) == "function" then
                addNumberOption(CoinFeature, "Coin transparency", mm2Settings.coinTransparency * 10, 0, 10, function(value: number)
                    mm2Settings.coinTransparency = value / 10
                    if coinChamsEnabled then
                        for _, rec in pairs(coinBoxes) do
                            if rec.highlight then
                                rec.highlight.FillTransparency = math.clamp(mm2Settings.coinTransparency * 0.65, 0.15, 0.62)
                            end
                        end
                    end
                end)
            end
            if type(addActionOption) == "function" then
                addActionOption(CoinFeature, "Refresh detected types", function()
                    local types = getAllCoinTypesDetected()
                    if #types > 0 then
                        notify("Detected: " .. table.concat(types, ", ") .. " | Count: " .. tostring(core.coinBoxesCount()))
                    else
                        notify("No coin types detected. Map may not be loaded.")
                    end
                end)
                addActionOption(CoinFeature, "Rescan coins", function()
                    if coinChamsEnabled then
                        toggleCoinChams(false)
                        task.wait(0.1)
                        toggleCoinChams(true)
                        notify("Rescanned coins: " .. tostring(core.coinBoxesCount()))
                    else
                        notify("Enable Coin ESP first")
                    end
                end)
            end
            if type(addInformationOption) == "function" then
                addInformationOption(CoinFeature, "Coin types: Coin (normal), SnowToken (Christmas), Candy (Halloween), BeachBall (Summer), Egg (Easter), Gift, Heart, Shell, Log. Auto mode detects what the server spawns. Use All to show everything.")
            end
        end
    end

    activeCleanup = function(): ()
        for _, release in ipairs(unregister) do pcall(release) end
        table.clear(unregister)
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
