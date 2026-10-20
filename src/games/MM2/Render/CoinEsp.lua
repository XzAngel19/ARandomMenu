-- MM2 Coin ESP: highlights ONLY the real pickups the game itself spawns.
--
-- A real pickup carries three exact signatures from the game's own code,
-- and this module accepts a part when ANY of them matches -- never a
-- generic name search:
--
--   1. The CollectionService tag "CoinVisual". The game's CoinVisualizer
--      script animates exactly GetTagged("CoinVisual"), skips the parts
--      whose "Collected" attribute is true and destroys the "Delete" ones.
--   2. The "CoinID" attribute. The same script keys every pickup by
--      GetAttribute("CoinID") when CoinCollected fires, so only a real
--      pickup carries it.
--   3. The exact spawn structure from the place: an invisible server part
--      named Coin_Server whose visible child is named CoinVisual, with the
--      mesh children (MainCoin / DecalPart / 2Part, or the event look of
--      the season) under it.
--
-- The highlight always sits on the visible CoinVisual part itself -- never
-- on a parent model or container. (An earlier version walked up to the
-- container model and painted the whole map yellow, and counted every
-- part with "coin" in its name; that detection is gone.)
--
-- The family of a pickup (Coin, Candy, SnowToken, BeachBall, Egg, Heart)
-- is read from its own mesh children; when the meshes say nothing
-- specific, the family the server announced applies, because a round only
-- pays one kind of pickup. Candies replace coins during Halloween with
-- this same spawn system ([1](https://murder-mystery-2.fandom.com/wiki/Halloween_Event_2025)),
-- so a candy round is found by the same signatures. The server family
-- comes from the Remotes/Gameplay/CoinsStarted bag table (Coin, Candy,
-- SnowToken, BeachBall, Egg) and the Workspace event attributes.
local Module = {
    Name = "MM2 Coin ESP",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

-- The exact signatures of a real pickup.
local COIN_TAG: string = "CoinVisual"
local VISUAL_NAME: string = "CoinVisual"
local SERVER_NAME: string = "Coin_Server"

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

-- Words read ONLY from the pickup's own mesh children (never from
-- parents: a container name must not reclassify every coin inside).
-- The tagged part itself is always named CoinVisual, whatever family it
-- pays, so that name must never classify a part as a plain coin either.
local FAMILY_PHRASES: {[string]: {string}} = {
    [FAMILY_EGG] = {"egg", "eggs"},
    [FAMILY_BEACH] = {"beachball", "beach ball", "beachballs", "beach balls"},
    [FAMILY_SNOW] = {"snowtoken", "snow token", "snowtokens", "snow tokens", "snowball", "snow ball"},
    [FAMILY_CANDY] = {"candy", "candies", "candied", "candycorn", "candy corn"},
    [FAMILY_HEART] = {"heart", "hearts"},
    [FAMILY_COIN] = {"maincoin", "coinold", "decalpart"},
}

-- Safety-net rescan; the signals do the real work.
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
    -- Raw signature counts from the last scan, for the report action.
    local lastRaw = {tagged = 0, coinId = 0, named = 0}

    local function attribute(object: Instance, name: string): any
        local ok: boolean, value: any = pcall(function(): any
            return object:GetAttribute(name)
        end)
        if ok then
            return value
        end
        return nil
    end

    local function hasTag(object: Instance): boolean
        local ok: boolean, tagged: boolean = pcall(function(): boolean
            return collectionService:HasTag(object, COIN_TAG)
        end)
        return ok and tagged == true
    end

    -- The visible half of a pickup. A server part resolves to its
    -- CoinVisual child; anything else is used as-is. Parents are NEVER
    -- walked: the container must stay dark.
    local function visualOf(part: Instance): Instance?
        if part.Name == SERVER_NAME then
            local child: Instance? = part:FindFirstChild(VISUAL_NAME)
            if child and child:IsA("BasePart") then
                return child
            end
            return nil
        end
        return part
    end

    -- Filters that are safe to fail open: if an engine call errors, the
    -- signature that found the part is trusted instead of dropping it.
    local function passesFilters(part: Instance): boolean
        if not part:IsA("BasePart") then
            return false
        end
        if attribute(part, "Collected") == true or attribute(part, "Delete") == true then
            return false
        end
        local okDesc: boolean, inside: boolean = pcall(function(): boolean
            return part:IsDescendantOf(workspace)
        end)
        if okDesc and not inside then
            return false
        end
        -- A character is never a pickup, whatever it carries.
        local current: Instance? = part.Parent
        while current and current ~= workspace do
            local okHum: boolean, humanoid: Instance? = pcall(function(): Instance?
                return current:FindFirstChildOfClass("Humanoid")
            end)
            if okHum and humanoid then
                return false
            end
            current = current.Parent
        end
        return true
    end

    -- Family of one pickup: its mesh children only. With no specific
    -- word, the round's family applies (a round pays a single kind of
    -- pickup), falling back to the classic coin.
    local function familyOf(part: Instance): string
        local names: {string} = {}
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

    -- Every real pickup on the map, merged from the three signatures.
    local function collectAll(): ({[Instance]: string}, {[string]: number})
        local found: {[Instance]: string} = {}
        local counts: {[string]: number} = {}
        lastRaw = {tagged = 0, coinId = 0, named = 0}

        local function consider(part: Instance?): ()
            if not part then
                return
            end
            local visual: Instance? = visualOf(part)
            if not visual or found[visual] then
                return
            end
            if not passesFilters(visual) then
                return
            end
            local family: string = familyOf(visual)
            found[visual] = family
            counts[family] = (counts[family] or 0) + 1
        end

        -- Signature 1: the game's own tag list.
        local okTagged: boolean, tagged: any = pcall(function(): any
            return collectionService:GetTagged(COIN_TAG)
        end)
        if okTagged and type(tagged) == "table" then
            lastRaw.tagged = #tagged
            for _, object: Instance in ipairs(tagged) do
                if object:IsA("BasePart") then
                    consider(object)
                end
            end
        end

        -- Signatures 2 and 3: the CoinID attribute and the exact spawn
        -- part names, from one workspace scan.
        local okScan: boolean, descendants: any = pcall(function(): any
            return workspace:GetDescendants()
        end)
        if okScan and type(descendants) == "table" then
            for _, object: Instance in ipairs(descendants) do
                if object:IsA("BasePart") then
                    if attribute(object, "CoinID") ~= nil then
                        lastRaw.coinId += 1
                        consider(object)
                    elseif object.Name == VISUAL_NAME or object.Name == SERVER_NAME then
                        lastRaw.named += 1
                        consider(object)
                    end
                end
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
        disconnectFeatureConnection("MM2CoinAdded")
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

        -- Roblox does not render a Highlight on a part whose Transparency
        -- is above ~0.01, and a pickup's tagged part is an invisible
        -- holder (Transparency = 1 in the place) whose visible geometry
        -- is its mesh children. So the cham goes on every VISIBLE
        -- BasePart of the pickup: the holder itself when it is opaque,
        -- its mesh descendants, and -- when the holder carries no
        -- visible geometry at all -- the visible parts of its parent
        -- group, provided that group is pickup-sized (a container of
        -- many coins is never painted).
        local function drawPickup(visual: Instance): ()
            local drew: boolean = false
            local function drawPart(part: Instance): ()
                createMM2Cham(
                    CoinEffects,
                    part,
                    mm2Settings.coinColor,
                    mm2Settings.coinTransparency
                )
                drew = true
            end
            local function isVisible(part: Instance): boolean
                local transparency: any = (part :: any).Transparency
                return type(transparency) ~= "number" or transparency <= 0.9
            end
            local function drawVisibleIn(root: Instance): ()
                if root:IsA("BasePart") and isVisible(root) then
                    drawPart(root)
                end
                local ok: boolean, descendants: any = pcall(function(): any
                    return root:GetDescendants()
                end)
                if ok and type(descendants) == "table" then
                    for _, object: Instance in ipairs(descendants) do
                        if object:IsA("BasePart") and isVisible(object) then
                            drawPart(object)
                        end
                    end
                end
            end
            drawVisibleIn(visual)
            if not drew then
                local parent: Instance? = visual.Parent
                if parent and parent ~= workspace then
                    local ok: boolean, descendants: any = pcall(function(): any
                        return parent:GetDescendants()
                    end)
                    if ok and type(descendants) == "table" then
                        local baseParts: number = 0
                        for _, object: Instance in ipairs(descendants) do
                            if object:IsA("BasePart") then
                                baseParts += 1
                            end
                        end
                        if baseParts <= 24 then
                            drawVisibleIn(parent)
                        end
                    end
                end
            end
            if not drew then
                drawPart(visual)
            end
        end

        -- One pickup, cham(s) on its visible geometry only.
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
                    drawPickup(object)
                end
            end
            setStatus(counts)
            dirty = false
        end

        -- A pickup appears: watch the tag signal (the game's own) and new
        -- workspace parts carrying one of the exact signatures.
        featureConnections.MM2CoinTagAdded =
            collectionService:GetInstanceAddedSignal(COIN_TAG):Connect(function(): ()
                dirty = true
            end)
        featureConnections.MM2CoinTagRemoved =
            collectionService:GetInstanceRemovedSignal(COIN_TAG):Connect(function(): ()
                dirty = true
            end)
        featureConnections.MM2CoinAdded = workspace.DescendantAdded:Connect(function(object: Instance): ()
            if object:IsA("BasePart")
                and (object.Name == VISUAL_NAME or object.Name == SERVER_NAME
                    or attribute(object, "CoinID") ~= nil or hasTag(object))
            then
                dirty = true
            end
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
                    .. " · signatures: tag=" .. tostring(lastRaw.tagged)
                    .. " coinId=" .. tostring(lastRaw.coinId)
                    .. " named=" .. tostring(lastRaw.named)
            )
        end
    )
    addInformationOption(
        CoinFeature,
        "Pickups are recognised by the game's own signatures only: the CoinVisual tag, the CoinID attribute and the exact server/visual part pair. Highlights sit on the visible part itself, never on a parent model or container. Auto highlights the family the server announces on CoinsStarted."
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
