-- MM2 Coin ESP: highlight every pickup in the map, sorted by the coin family
-- the server is actually using this round.
--
-- What the place dump says a pickup is. `ReplicatedStorage/Coins` holds one
-- objects folder per coin family: `CoinObjects` (normal coins: the `Coin` part
-- with `MainCoin`/`DecalPart`/`2Part` meshes and the old `CoinOld`),
-- `CandyObjects` and `_CandiesObjects` (candy meshes `Purple`, `Green`,
-- `Cyan`, `Orange`, `Pink`), `SnowTokenObjects` (the `SnowToken` part),
-- `BeachBallObjects` (`BeachBall` mesh) and `EggObjects` (`CurrencyEgg1..3`
-- plus the rare `*Egg` meshes). In the map the pickup's visible half is
-- tagged `CoinVisual` and carries the attributes `CoinID`, `Collected`,
-- `RoundEnd` and `IsSetup`; the server's half is named `Coin_Server`. The
-- event candies are the same coin model under names such as `Candy2024`,
-- `Candies2022` or `CandyCorn`, and their clickable half is a generic
-- `InteractiveBox` that only counts inside a treat-named model.
--
-- Which family is in use comes from the game itself: the
-- `Remotes/Gameplay/CoinsStarted` remote sends one entry per active bag,
-- keyed by the CoinBags frames `Coin`, `Candy`, `SnowToken`, `BeachBall` and
-- `Egg`, and the Workspace attributes `CurrentEvent`, `isChristmas`,
-- `IsSummer`, `IsEaster` and `isValentines` name the same families before
-- the remote fires.
--
-- The menu lets the player pick which family counts as "in use" (Auto follows
-- the server) and the status line reports every family found on the map.
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

-- The families the game has shipped so far, from `ReplicatedStorage/Coins`
-- and the CoinBags frames.
local FAMILY_COIN: string = "Coin"
local FAMILY_CANDY: string = "Candy"
local FAMILY_SNOW: string = "SnowToken"
local FAMILY_BEACH: string = "BeachBall"
local FAMILY_EGG: string = "Egg"
local FAMILY_HEART: string = "Heart"
local FAMILY_ALL: string = "All"
local FAMILY_AUTO: string = "Auto (server)"

-- Classification order: most specific first, because a SnowToken carries a
-- mesh named `Coin` and `Coin` is only the fallback family.
local FAMILY_ORDER: {string} = {
    FAMILY_EGG,
    FAMILY_BEACH,
    FAMILY_SNOW,
    FAMILY_CANDY,
    FAMILY_HEART,
    FAMILY_COIN,
}

-- Counting order: the classic coins lead, then the event families.
local COUNT_ORDER: {string} = {
    FAMILY_COIN,
    FAMILY_CANDY,
    FAMILY_SNOW,
    FAMILY_BEACH,
    FAMILY_EGG,
    FAMILY_HEART,
}

local FAMILY_NOUNS: {[string]: {string}} = {
    [FAMILY_COIN] = {"coin", "coins"},
    [FAMILY_CANDY] = {"candy", "candies"},
    [FAMILY_SNOW] = {"snowtoken", "snowtokens"},
    [FAMILY_BEACH] = {"beachball", "beachballs"},
    [FAMILY_EGG] = {"egg", "eggs"},
    [FAMILY_HEART] = {"heart", "hearts"},
}

-- What the selector offers. Auto follows the server; All shows everything.
local FAMILY_CHOICES: {string} = {
    FAMILY_AUTO,
    FAMILY_COIN,
    FAMILY_CANDY,
    FAMILY_SNOW,
    FAMILY_BEACH,
    FAMILY_EGG,
    FAMILY_HEART,
    FAMILY_ALL,
}

-- The CoinBags frames the `CoinsStarted` remote keys its table by.
local BAG_TO_FAMILY: {[string]: string} = {
    Coin = FAMILY_COIN,
    Candy = FAMILY_CANDY,
    SnowToken = FAMILY_SNOW,
    BeachBall = FAMILY_BEACH,
    Egg = FAMILY_EGG,
}

local FAMILY_PHRASES: {[string]: {string}} = {
    [FAMILY_EGG] = {"egg", "eggs"},
    [FAMILY_BEACH] = {"beachball", "beach ball", "beachballs", "beach balls"},
    [FAMILY_SNOW] = {"snowtoken", "snow token", "snowtokens", "snow tokens", "snowball", "snow ball"},
    [FAMILY_CANDY] = {"candy", "candies", "candied", "candycorn", "candy corn"},
    [FAMILY_HEART] = {"heart", "hearts"},
    [FAMILY_COIN] = {"coin", "maincoin", "coinvisual", "coin_server", "coinold", "decalpart"},
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

-- Picks the family a set of names describes. `haystack` is every relevant
-- instance name (model, parts, meshes) joined and lowered.
local function classifyFamily(haystack: string): string
    for _, family: string in ipairs(FAMILY_ORDER) do
        for _, phrase: string in ipairs(FAMILY_PHRASES[family]) do
            if contains(haystack, phrase) then
                return family
            end
        end
    end
    return FAMILY_COIN
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

    local settings = {
        family = FAMILY_AUTO,
    }
    -- Set by the `CoinsStarted` remote and by the Workspace event attributes.
    local serverFamily: string? = nil

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
        for _, partName: string in ipairs(COIN_PARTS) do
            if name == partName then
                return true
            end
        end
        -- `OldCoin`, `Coin_1`, anything the game names after a coin.
        return contains(lower(name), "coin")
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
            local name: string = lower(current.Name)
            if contains(name, "candy") or contains(name, "candies") or contains(name, "candied") then
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
        -- `Coin`, `Candy2024`, `Candies2022`, `SnowToken`, `BeachBall`,
        -- `CurrencyEgg`: a model named after any family is the pickup itself.
        local name: string = lower(object.Name)
        for _, phrases: {string} in pairs(FAMILY_PHRASES) do
            for _, phrase: string in ipairs(phrases) do
                if contains(name, phrase) then
                    return true
                end
            end
        end
        return hasCoinTag(object)
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

    -- Family of one pickup: every name from its model down to its meshes.
    local function familyOf(adornee: Instance): string
        local names: {string} = {adornee.Name}
        local current: Instance? = adornee.Parent
        for _ = 1, COIN_ANCESTOR_DEPTH do
            if not current or current == workspace then
                break
            end
            table.insert(names, current.Name)
            current = current.Parent
        end
        local ok: boolean, descendants: any = pcall(function(): any
            return adornee:GetDescendants()
        end)
        if ok and type(descendants) == "table" then
            for _, object: Instance in ipairs(descendants) do
                table.insert(names, object.Name)
            end
        end
        return classifyFamily(lower(table.concat(names, " ")))
    end

    -- The family the server says is in play: the `CoinsStarted` table first,
    -- then the Workspace event attributes.
    local function familyFromWorkspace(): string?
        local ok: boolean, value: any = pcall(function(): any
            return workspace:GetAttribute("CurrentEvent")
        end)
        local eventName: string = ok and lower(tostring(value or "")) or ""
        if contains(eventName, "halloween") then
            return FAMILY_CANDY
        elseif contains(eventName, "christmas") then
            return FAMILY_SNOW
        elseif contains(eventName, "summer") then
            return FAMILY_BEACH
        elseif contains(eventName, "easter") then
            return FAMILY_EGG
        elseif contains(eventName, "valentine") then
            return FAMILY_HEART
        end
        for attribute: string, family: string in pairs({
            isValentines = FAMILY_HEART,
            isChristmas = FAMILY_SNOW,
            isChristmasEnding = FAMILY_SNOW,
            IsSummer = FAMILY_BEACH,
            IsEaster = FAMILY_EGG,
        }) do
            local okAttr: boolean, flag: any = pcall(function(): any
                return workspace:GetAttribute(attribute)
            end)
            if okAttr and flag == true then
                return family
            end
        end
        return nil
    end

    local function activeFamily(): string?
        return serverFamily or familyFromWorkspace()
    end

    local function collectAll(): ({[Instance]: string}, {[string]: number})
        local found: {[Instance]: string} = {}
        local counts: {[string]: number} = {}
        local ok: boolean, descendants: any = pcall(function(): any
            return workspace:GetDescendants()
        end)
        if not ok or type(descendants) ~= "table" then
            return found, counts
        end
        for _, object: Instance in ipairs(descendants) do
            local adornee: Instance? = pickupAdornee(object)
            if adornee and not found[adornee] then
                local family: string = familyOf(adornee)
                found[adornee] = family
                counts[family] = (counts[family] or 0) + 1
            end
        end
        return found, counts
    end

    -- Only the families that count as "in use" are highlighted. The status
    -- still reports every family found on the map.
    local function wanted(family: string): boolean
        local choice: string = settings.family
        if choice == FAMILY_ALL then
            return true
        end
        if choice == FAMILY_AUTO then
            local active: string? = activeFamily()
            -- Nothing detected yet: show everything instead of nothing.
            return active == nil or family == active
        end
        return family == choice
    end

    local function describe(counts: {[string]: number}): string
        local parts: {string} = {}
        for _, family: string in ipairs(COUNT_ORDER) do
            local amount: number = counts[family] or 0
            if amount > 0 then
                local nouns: {string} = FAMILY_NOUNS[family]
                table.insert(parts, tostring(amount) .. " " .. (amount == 1 and nouns[1] or nouns[2]))
            end
        end
        if #parts == 0 then
            return "no coins yet"
        end
        return table.concat(parts, " · ")
    end

    local function toggleCoinEsp(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinRefresh")
        disconnectFeatureConnection("MM2CoinCollected")
        disconnectFeatureConnection("MM2CoinAdded")
        disconnectFeatureConnection("MM2CoinRemoved")
        disconnectFeatureConnection("MM2CoinsStarted")
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

        local function setStatus(counts: {[string]: number}): ()
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
            local found: {[Instance]: string}, counts: {[string]: number} = collectAll()
            local visible: {[Instance]: boolean} = {}
            for object: Instance, family: string in pairs(found) do
                if wanted(family) then
                    visible[object] = true
                end
            end
            local changed: boolean = false
            for object: Instance in pairs(visible) do
                if not marked[object] then
                    marked[object] = true
                    changed = true
                end
            end
            for object: Instance in pairs(marked) do
                if not visible[object] then
                    marked[object] = nil
                    changed = true
                end
            end
            if changed then
                clearEffects(CoinEffects)
                for object: Instance in pairs(visible) do
                    createMM2Cham(
                        CoinEffects,
                        object,
                        mm2Settings.coinColor,
                        mm2Settings.coinTransparency
                    )
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

        -- The server names the active bag: follow it when the selector is on
        -- Auto. This is the coin the round is paying out.
        local started: Instance? = core.mm2GameplayRemotes
            and core.mm2GameplayRemotes:FindFirstChild("CoinsStarted")
        if started and started:IsA("RemoteEvent") then
            featureConnections.MM2CoinsStarted =
                (started :: any).OnClientEvent:Connect(function(bagTable: any): ()
                    if type(bagTable) == "table" then
                        for bag: any in pairs(bagTable) do
                            local family: string? = BAG_TO_FAMILY[tostring(bag)]
                            if family then
                                serverFamily = family
                            end
                        end
                    end
                    dirty = true
                end)
        end

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
        "Highlights every coin, candy, snow token, beach ball and egg on the map and reports how many of each family exist.",
        3,
        toggleCoinEsp,
        {
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2CoinFeature = CoinFeature

    addCycleOption(
        CoinFeature,
        "Coin in use",
        FAMILY_CHOICES,
        1,
        function(value: string): ()
            settings.family = value
            if CoinFeature.enabled then
                toggleCoinEsp(true)
            end
        end,
        "Auto follows the coin family the server announces through CoinsStarted."
    )
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
    addActionOption(
        CoinFeature,
        "Report server coin",
        function(): ()
            local active: string? = activeFamily()
            local _found: {[Instance]: string}, counts: {[string]: number} = collectAll()
            notify(
                "Server coin: " .. (active or "unknown")
                    .. " · on the map: " .. describe(counts)
            )
        end
    )
    addInformationOption(
        CoinFeature,
        "Pickups are found through the game's own CoinVisual tag and the Coin_Server parts, then classified into Coin, Candy, SnowToken, BeachBall, Egg and Heart by their names and meshes. Auto highlights the family the server announces on CoinsStarted."
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
