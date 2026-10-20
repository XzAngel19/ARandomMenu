-- MM2 Coin ESP: highlights ONLY the real pickups the game itself spawns.
--
-- How the game marks a real pickup (from its own CoinVisualizer script):
-- every live pickup is a BasePart tagged "CoinVisual" by CollectionService.
-- In the map each pickup hangs from a container under an invisible
-- server part; the tagged part is its visible half, with mesh children
-- such as MainCoin / DecalPart / 2Part or the event look of the season.
-- CoinVisualizer reads GetTagged("CoinVisual"), skips the ones whose
-- "Collected" attribute is true and destroys the ones marked "Delete".
--
-- This module does exactly that and nothing else. There is NO name-based
-- detection: no part name and no model name is ever treated as a pickup,
-- and the highlight is placed on
-- the tagged part itself -- never on a parent model or container. The old
-- name heuristics lit containers such as CoinContainer (every coin in the
-- map inside one giant yellow highlight) and counted dozens of fakes.
--
-- The family of a tagged part (Coin, Candy, SnowToken, BeachBall, Egg,
-- Heart) is read from the part's own mesh children; when the meshes say
-- nothing specific, the family the server announced applies, because a
-- round only pays one kind of pickup. The server family comes from the
-- Remotes/Gameplay/CoinsStarted bag table (Coin, Candy, SnowToken,
-- BeachBall, Egg) and from the Workspace event attributes.
local Module = {
    Name = "MM2 Coin ESP",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

-- The one and only tag the game puts on a real pickup.
local COIN_TAG: string = "CoinVisual"

local FAMILY_COIN: string = "Coin"
local FAMILY_CANDY: string = "Candy"
local FAMILY_SNOW: string = "SnowToken"
local FAMILY_BEACH: string = "BeachBall"
local FAMILY_EGG: string = "Egg"
local FAMILY_HEART: string = "Heart"
local FAMILY_ALL: string = "All"
local FAMILY_AUTO: string = "Auto (server)"

-- Most specific first: a SnowToken can carry a mesh named Coin.
local FAMILY_ORDER: {string} = {
    FAMILY_EGG,
    FAMILY_BEACH,
    FAMILY_SNOW,
    FAMILY_CANDY,
    FAMILY_HEART,
    FAMILY_COIN,
}

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

local BAG_TO_FAMILY: {[string]: string} = {
    Coin = FAMILY_COIN,
    Candy = FAMILY_CANDY,
    SnowToken = FAMILY_SNOW,
    BeachBall = FAMILY_BEACH,
    Egg = FAMILY_EGG,
}

-- Words read ONLY from the tagged part and its own mesh children (never
-- from parents: a container name must not reclassify every coin inside).
local FAMILY_PHRASES: {[string]: {string}} = {
    [FAMILY_EGG] = {"egg", "eggs"},
    [FAMILY_BEACH] = {"beachball", "beach ball", "beachballs", "beach balls"},
    [FAMILY_SNOW] = {"snowtoken", "snow token", "snowtokens", "snow tokens", "snowball", "snow ball"},
    [FAMILY_CANDY] = {"candy", "candies", "candied", "candycorn", "candy corn"},
    [FAMILY_HEART] = {"heart", "hearts"},
    -- Note: the tagged part is always named CoinVisual, whatever family it
    -- pays, so that name itself must never classify a part as a plain coin.
    [FAMILY_COIN] = {"maincoin", "coinold", "decalpart"},
}

-- Safety-net rescan; the tag signals do the real work.
local RESCAN_PERIOD: number = 5

local function lower(value: string): string
    return string.lower(value)
end

local function contains(value: string, needle: string): boolean
    return string.find(value, needle, 1, true) ~= nil
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

    local function attribute(object: Instance, name: string): any
        local ok: boolean, value: any = pcall(function(): any
            return object:GetAttribute(name)
        end)
        if ok then
            return value
        end
        return nil
    end

    -- A real pickup, exactly as the game's CoinVisualizer defines it: a
    -- tagged BasePart still in the workspace, not collected, not deleted,
    -- and not part of a character.
    local function isRealPickup(object: Instance): boolean
        if not object:IsA("BasePart") then
            return false
        end
        local ok: boolean, tagged: boolean = pcall(function(): boolean
            return collectionService:HasTag(object, COIN_TAG)
        end)
        if not ok or not tagged then
            return false
        end
        if not object:IsDescendantOf(workspace) then
            return false
        end
        if attribute(object, "Collected") == true or attribute(object, "Delete") == true then
            return false
        end
        local current: Instance? = object.Parent
        while current and current ~= workspace do
            local humanoid: Instance? = current:FindFirstChildOfClass("Humanoid")
            if humanoid then
                return false
            end
            current = current.Parent
        end
        return true
    end

    -- Family of one tagged part: its own name and its mesh children only.
    -- With no specific word, the round's family applies (a round pays a
    -- single kind of pickup), falling back to the classic coin.
    local function familyOf(part: Instance): string
        local names: {string} = {part.Name}
        local ok: boolean, descendants: any = pcall(function(): any
            return part:GetDescendants()
        end)
        if ok and type(descendants) == "table" then
            for _, object: Instance in ipairs(descendants) do
                table.insert(names, object.Name)
            end
        end
        local haystack: string = lower(table.concat(names, " "))
        for _, family: string in ipairs(FAMILY_ORDER) do
            for _, phrase: string in ipairs(FAMILY_PHRASES[family]) do
                if contains(haystack, phrase) then
                    return family
                end
            end
        end
        return serverFamily or FAMILY_COIN
    end

    -- The family the server says is in play: the `CoinsStarted` table first,
    -- then the Workspace event attributes.
    local function familyFromWorkspace(): string?
        local eventName: string = lower(tostring(attribute(workspace, "CurrentEvent") or ""))
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
        for attrName: string, family: string in pairs({
            isValentines = FAMILY_HEART,
            isChristmas = FAMILY_SNOW,
            isChristmasEnding = FAMILY_SNOW,
            IsSummer = FAMILY_BEACH,
            IsEaster = FAMILY_EGG,
        }) do
            if attribute(workspace, attrName) == true then
                return family
            end
        end
        return nil
    end

    local function activeFamily(): string?
        return serverFamily or familyFromWorkspace()
    end

    -- Every real pickup on the map, straight from CollectionService.
    local function collectAll(): ({[Instance]: string}, {[string]: number})
        local found: {[Instance]: string} = {}
        local counts: {[string]: number} = {}
        local ok: boolean, tagged: any = pcall(function(): any
            return collectionService:GetTagged(COIN_TAG)
        end)
        if not ok or type(tagged) ~= "table" then
            return found, counts
        end
        for _, object: Instance in ipairs(tagged) do
            if isRealPickup(object) and not found[object] then
                local family: string = familyOf(object)
                found[object] = family
                counts[family] = (counts[family] or 0) + 1
            end
        end
        return found, counts
    end

    local function wanted(family: string): boolean
        local choice: string = settings.family
        if choice == FAMILY_ALL then
            return true
        end
        if choice == FAMILY_AUTO then
            local active: string? = activeFamily()
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
        disconnectFeatureConnection("MM2CoinsStarted")
        disconnectFeatureConnection("MM2CoinTagAdded")
        disconnectFeatureConnection("MM2CoinTagRemoved")
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

        -- One Highlight per tagged part, on the part itself. Nothing else
        -- is ever drawn, so a container can never flood the screen.
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

        -- The exact signals the game itself uses: a pickup appears when it
        -- gets the tag and disappears when the tag (or the part) goes away.
        featureConnections.MM2CoinTagAdded =
            collectionService:GetInstanceAddedSignal(COIN_TAG):Connect(function(object: Instance): ()
                if isRealPickup(object) then
                    dirty = true
                end
            end)
        featureConnections.MM2CoinTagRemoved =
            collectionService:GetInstanceRemovedSignal(COIN_TAG):Connect(function(): ()
                dirty = true
            end)

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
                refresh()
            end
        )
    end

    local CoinFeature: any = createUniversalFeature(
        "Coin ESP",
        "Highlights the real coin, candy, snow token, beach ball and egg pickups of the map and reports how many of each family exist.",
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
            local _found: {[Instance]: string}, counts: {[string]: number} = collectAll()
            notify(
                "Server coin: " .. (activeFamily() or "unknown")
                    .. " · on the map: " .. describe(counts)
            )
        end
    )
    addInformationOption(
        CoinFeature,
        "Pickups are found only through the game's own CoinVisual tag (CollectionService:GetTagged), the same list the game's CoinVisualizer uses. Highlights sit on the tagged part itself, never on a parent model or container. Auto highlights the family the server announces on CoinsStarted."
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
