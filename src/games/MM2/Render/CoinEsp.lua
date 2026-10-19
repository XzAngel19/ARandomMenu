-- MM2 coins and candies: highlight every pickup in the map and report how many
-- of each exist. Client-side only: it reads the world, it never calls a remote.
--
-- How a pickup is recognised. The place dump names the coin's two parts
-- `CoinVisual` (the visible half) and `Coin_Server` (the server's half), and
-- lists ~100 of each. The event candies are the same coin model with another
-- decal, so they carry the same part names; their models are named `Candy`,
-- `Candy2020`, `CandyToy2021`, `Candies2022`, `Candies2024`, `CandyCorn`...
-- The old module only looked inside three folders (`CoinContainer`,
-- `CoinAreas`, `Coins`) that the live game does not populate, which is why the
-- candy on screen was never highlighted.
local Module = {
    Name = "MM2 Coin ESP",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

-- CollectionService tags: names the game itself attaches to a pickup. A tag
-- survives a rename, a name does not.
local COIN_TAGS: {string} = {
    "CoinVisual",
    "ServerCoinPart",
    "Coin",
}

-- Part names a pickup is made of.
local COIN_PARTS: {string} = {
    "CoinVisual",
    "Coin_Server",
    "ServerCoinPart",
    "MainCoin",
    "Coin",
}

-- How far up a coin part is walked to reach the model that owns it.
local COIN_ANCESTOR_DEPTH: number = 2
-- A full rescan, in case the game moved a pickup without adding or removing it.
local RESCAN_PERIOD: number = 5

local function lower(value: string): string
    return string.lower(value)
end

local function contains(value: string, needle: string): boolean
    return string.find(value, needle, 1, true) ~= nil
end

-- "Candy", "Candy2020", "CandyToy2022", "Candies2024", "Candied", "CandyCorn".
local function isCandyName(name: string): boolean
    local value: string = lower(name)
    return contains(value, "candy")
        or contains(value, "candies")
        or contains(value, "candied")
end

-- "Coin", "CoinOld", "CoinBag", "MainCoin", "Coins", "Coin_1".
local function isCoinName(name: string): boolean
    return contains(lower(name), "coin")
end

-- A model that holds one of the pickup parts without being named after it.
local function hasPickupPart(model: Instance): boolean
    for _, partName: string in ipairs({"CoinVisual", "Coin_Server", "ServerCoinPart"}) do
        local part: Instance? = model:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            return true
        end
    end
    return false
end

local function listContains(list: {string}, value: string): boolean
    for _, entry: string in ipairs(list) do
        if entry == value then
            return true
        end
    end
    return false
end

-- "Candy 1", "Candy_2": a numbered copy of a known name.
local function isNumberedVariant(list: {string}, value: string): boolean
    local stripped: string = string.gsub(value, "[_%s]%d+$", "")
    return stripped ~= value and listContains(list, stripped)
end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Coin ESP requires the MM2 core module")
    Module.Runtime = runtime
    local CoinEffects: any = core.CoinEffects
    local clearEffects: any = core.clearEffects
    local createMM2Cham: any = core.createMM2Cham
    local mm2Settings: any = core.mm2Settings
    local collectionService: any = game:GetService("CollectionService")

    local function hasCoinTag(object: Instance): boolean
        for _, tag: string in ipairs(COIN_TAGS) do
            local ok: boolean, tagged: boolean = pcall(function(): boolean
                return collectionService:HasTag(object, tag)
            end)
            if ok and tagged then
                return true
            end
        end
        return false
    end

    -- A character or an NPC is never a pickup, whatever its parts are called.
    local function insideCharacter(object: Instance): boolean
        local current: Instance? = object
        for _ = 1, COIN_ANCESTOR_DEPTH + 1 do
            if not current then
                return false
            end
            if current:FindFirstChildOfClass("Humanoid") then
                return true
            end
            current = current.Parent
        end
        return false
    end

    local function isCoinPart(object: Instance): boolean
        if not object:IsA("BasePart") then
            return false
        end
        if hasCoinTag(object) then
            return true
        end
        local name: string = object.Name
        return listContains(COIN_PARTS, name)
            or isNumberedVariant(COIN_PARTS, name)
            or isCoinName(name)
    end

    -- A candy's clickable part is a generic `InteractiveBox`: accept it only
    -- inside a model named like a treat, or it would light every door.
    local function isCandyBox(part: Instance): boolean
        if part.Name ~= "InteractiveBox" or not part:IsA("BasePart") then
            return false
        end
        local current: Instance? = part.Parent
        for _ = 1, COIN_ANCESTOR_DEPTH do
            if not current or current == workspace then
                return false
            end
            if isCandyName(current.Name) then
                return true
            end
            current = current.Parent
        end
        return false
    end

    local function isPickupModel(object: Instance): boolean
        if not object:IsA("Model") then
            return false
        end
        if insideCharacter(object) then
            return false
        end
        local name: string = object.Name
        return isCoinName(name) or isCandyName(name) or hasCoinTag(object) or hasPickupPart(object)
    end

    -- The thing to highlight: the model that holds the part when there is one,
    -- so a two-part coin lights up once instead of once per part.
    local function pickupAdornee(object: Instance): Instance?
        if insideCharacter(object) then
            return nil
        end
        if isCoinPart(object) or isCandyBox(object) then
            local current: Instance = object
            for _ = 1, COIN_ANCESTOR_DEPTH do
                local parent: Instance? = current.Parent
                if not parent or parent == workspace then
                    break
                end
                if not parent:IsA("Model") then
                    break
                end
                current = parent
            end
            return current
        end
        if isPickupModel(object) then
            if object:FindFirstChildWhichIsA("BasePart") then
                return object
            end
        end
        return nil
    end

    local function collectAll(): {[Instance]: boolean}
        local found: {[Instance]: boolean} = {}
        local ok: boolean, descendants: any = pcall(function(): any
            return workspace:GetDescendants()
        end)
        if not ok or type(descendants) ~= "table" then
            return found
        end
        for _, object: Instance in ipairs(descendants) do
            local adornee: Instance? = pickupAdornee(object)
            if adornee then
                found[adornee] = true
            end
        end
        return found
    end

    local function describe(counts: {coins: number, candies: number}): string
        local total: number = counts.coins + counts.candies
        if total == 0 then
            return "no coins yet"
        end
        local parts: {string} = {}
        if counts.coins > 0 then
            table.insert(parts, tostring(counts.coins) .. (counts.coins == 1 and " coin" or " coins"))
        end
        if counts.candies > 0 then
            table.insert(parts, tostring(counts.candies)
                .. (counts.candies == 1 and " candy" or " candies"))
        end
        return table.concat(parts, " · ")
    end

    local function toggleCoinEsp(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinRefresh")
        disconnectFeatureConnection("MM2CoinCollected")
        disconnectFeatureConnection("MM2CoinAdded")
        disconnectFeatureConnection("MM2CoinRemoved")
        for index: number = 1, #COIN_TAGS do
            disconnectFeatureConnection("MM2CoinTagAdded" .. tostring(index))
            disconnectFeatureConnection("MM2CoinTagRemoved" .. tostring(index))
        end
        clearEffects(CoinEffects)

        if not enabled then
            local card: any = state.mm2CoinFeature
            if card then
                card:SetStatus(nil)
            end
            return
        end

        local marked: {[Instance]: boolean} = {}
        local elapsed: number = 0
        local lastStatus: string? = nil
        local dirty: boolean = true

        local function setStatus(counts: {coins: number, candies: number}): ()
            local text: string = describe(counts)
            if text == lastStatus then
                return
            end
            lastStatus = text
            local card: any = state.mm2CoinFeature
            if card then
                card:SetStatus(text)
            end
        end

        -- Redraws only when the set changed: one Highlight per pickup, never
        -- per part, and no work while the map stands still.
        local function refresh(): ()
            local found: {[Instance]: boolean} = collectAll()
            local changed: boolean = false
            for object: Instance in pairs(found) do
                if not marked[object] then
                    marked[object] = true
                    changed = true
                end
            end
            for object: Instance in pairs(marked) do
                if not found[object] then
                    marked[object] = nil
                    changed = true
                end
            end
            if changed then
                clearEffects(CoinEffects)
                for object: Instance in pairs(found) do
                    createMM2Cham(
                        CoinEffects,
                        object,
                        mm2Settings.coinColor,
                        mm2Settings.coinTransparency
                    )
                end
            end
            local counts: {coins: number, candies: number} = {coins = 0, candies = 0}
            for object: Instance in pairs(found) do
                if isCandyName(object.Name) then
                    counts.candies += 1
                else
                    counts.coins += 1
                end
            end
            setStatus(counts)
            dirty = false
        end

        -- The game adds and removes pickups all the time: react to that and
        -- keep the full scan as a safety net, not as the main loop.
        local added: any = workspace.DescendantAdded:Connect(function(object: Instance): ()
            if pickupAdornee(object) then
                dirty = true
            end
        end)
        local removed: any = workspace.DescendantRemoving:Connect(function(object: Instance): ()
            -- Do not touch `marked` here: refresh compares the set it finds
            -- against `marked`, and the old highlight is only dropped when the
            -- diff really sees the pickup gone.
            if marked[object] then
                dirty = true
                return
            end
            for adornee: Instance in pairs(marked) do
                if not adornee:IsDescendantOf(workspace) then
                    dirty = true
                    return
                end
            end
        end)
        featureConnections.MM2CoinAdded = added
        featureConnections.MM2CoinRemoved = removed

        -- Tag signals: a part can be named `Part` and only become a coin when
        -- the game tags it, after it is already in the workspace.
        for index: number = 1, #COIN_TAGS do
            local tag: string = COIN_TAGS[index]
            local tagAdded: any = collectionService:GetInstanceAddedSignal(tag):Connect(function(): ()
                dirty = true
            end)
            local tagRemoved: any = collectionService:GetInstanceRemovedSignal(tag):Connect(function(): ()
                dirty = true
            end)
            featureConnections["MM2CoinTagAdded" .. tostring(index)] = tagAdded
            featureConnections["MM2CoinTagRemoved" .. tostring(index)] = tagRemoved
        end

        -- A collection is the one moment the map changed for sure: refresh on
        -- the next frame instead of waiting for the scan window.
        local remotes: any = core.mm2GameplayRemotes
        local collected: Instance? = remotes and remotes:FindFirstChild("CoinCollected")
        if collected and collected:IsA("RemoteEvent") then
            featureConnections.MM2CoinCollected =
                (collected :: any).OnClientEvent:Connect(function(): ()
                    dirty = true
                end)
        end

        refresh()
        featureConnections.MM2CoinRefresh = TaskManager:Connect(
            function(deltaTime: number): ()
                elapsed += deltaTime
                if not dirty and elapsed < RESCAN_PERIOD then
                    return
                end
                elapsed = 0
                dirty = true
                refresh()
            end
        )
    end

    local CoinFeature: any = createUniversalFeature(
        "Coin ESP",
        "Highlights every coin or candy in the map and reports how many of each exist.",
        3,
        toggleCoinEsp,
        {
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2CoinFeature = CoinFeature
    -- One switch: the card. A second row called like the card is how the old
    -- menu ended up with controls that could be ON while the feature was OFF.
    addColorOption(
        CoinFeature,
        "Coin colour",
        mm2Settings.coinColor,
        function(value: Color3): ()
            mm2Settings.coinColor = value
            if CoinFeature.enabled then
                toggleCoinEsp(true)
            end
        end
    )
    addNumberOption(
        CoinFeature,
        "Coin transparency",
        mm2Settings.coinTransparency,
        0,
        1,
        function(value: number): ()
            mm2Settings.coinTransparency = value
            if CoinFeature.enabled then
                toggleCoinEsp(true)
            end
        end
    )
    addInformationOption(
        CoinFeature,
        "Found by the game's own CoinVisual/Coin_Server parts and by the coin, candy and candies names; one highlight per pickup."
    )

    activeCleanup = function(): ()
        state.mm2CoinFeature = nil
        toggleCoinEsp(false)
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
    activeCleanup = function(): ()
    end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
