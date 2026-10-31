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
local RESCAN_PERIOD: number = 2

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
    local mm2Settings: any = core.mm2Settings
    local collectionService: any = game:GetService("CollectionService")

    local settings = {
        family = FAMILY_AUTO,
    }
    -- Set by the `CoinsStarted` remote and by the Workspace event attributes.
    local serverFamily: string? = nil
    -- Raw signature counts from the last scan, for the report action.
    local lastRaw = {tagged = 0, coinId = 0, named = 0}

    -- Native per-pickup marker: ONE small BoxHandleAdornment per
    -- pickup, sized exactly to the visible coin mesh. No labels and
    -- no per-frame Lua: a hundred markers cost the engine one
    -- adornment each and nothing else. The adornment renders through
    -- walls regardless of the holder's transparency.
    local coinTags: {[Instance]: {box: Instance}} = {}
    -- Pickup -> family, kept between scans for the tag text.
    local lastFamilies: {[Instance]: string} = {}
    -- Parts currently carrying a tag, for tests and the report action.
    state.mm2CoinTagParts = {}

    local function clearTags(): ()
        for part: Instance, entry in pairs(coinTags) do
            coinTags[part] = nil
            pcall(function(): ()
                entry.box:Destroy()
            end)
        end
        table.clear(lastFamilies)
        state.mm2CoinTagParts = {}
    end

    local function attribute(object: Instance, name: string): any
        return object:GetAttribute(name)
    end

    local function hasTag(object: Instance): boolean
        return collectionService:HasTag(object, COIN_TAG)
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

    -- The volatile Collected/Delete flags are checked by passesFiltersCached;
    -- this static half rejects anything outside the map or inside a character.
    local function passesFilters(part: Instance): boolean
        if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
            return false
        end
        local current: Instance? = part.Parent
        while current and current ~= workspace do
            if current:FindFirstChildOfClass("Humanoid") then
                return false
            end
            current = current.Parent
        end
        return true
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

    -- Family of one pickup: its mesh children only. With no specific
    -- word, the round's family applies (a round pays a single kind of
    -- pickup), falling back to the classic coin.
    local familyCache: {[Instance]: string} = {}
    local function familyOf(part: Instance): string
        local cached: string? = familyCache[part]
        if cached then
            return cached
        end
        local names: {string} = {}
        for _, object: Instance in ipairs(part:GetDescendants()) do
            table.insert(names, object.Name)
        end
        local haystack: string = lower(table.concat(names, " "))
        -- A round pays a single kind of pickup, and event pickups are
        -- built on the classic coin template (MainCoin/DecalPart meshes
        -- with an event look). So when the server announces an event
        -- family, plain coin mesh names must NOT drag the pickup back
        -- to Coin -- that mismatch is what left Auto showing nothing
        -- while the map was full of candies.
        local active: string? = activeFamily()
        for _, family: string in ipairs(FAMILY_ORDER) do
            if family ~= FAMILY_COIN or active == nil or active == FAMILY_COIN then
                for _, phrase: string in ipairs(FAMILY_PHRASES[family]) do
                    if contains(haystack, phrase) then
                        -- Cache only the non-Coin mesh families:
                        -- they win over the server family in every
                        -- scan, so they can never go stale. A Coin
                        -- mesh classification is NOT cached -- when
                        -- the server announces an event family, the
                        -- coin template must reclassify to it.
                        if family ~= FAMILY_COIN then
                            familyCache[part] = family
                        end
                        return family
                    end
                end
            end
        end
        return active or FAMILY_COIN
    end

    -- Every real pickup on the map, merged from the three signatures.
    -- (v84 tried a "cheap" rescan -- tag list plus previously-known
    -- parts -- and in the live game the ESP stopped reporting coins
    -- entirely; the mock suite passed, the game did not. The full
    -- scan below is the behaviour that demonstrably works in game.
    -- The cost is kept down elsewhere: Auto Farm's polls are cached
    -- (1.5 s), the family classification is cached, and the ancestor
    -- walk inside passesFilters is cached per part.)
    local filterCache: {[Instance]: boolean} = {}
    local function collectAll(): ({[Instance]: string}, {[string]: number})
        local found: {[Instance]: string} = {}
        local counts: {[string]: number} = {}
        lastRaw = {tagged = 0, coinId = 0, named = 0}

        -- The attribute half of the filter is volatile (Collected
        -- flips when a coin is taken) and is always re-read; only
        -- the static half (in the workspace, not inside a character)
        -- is cached -- a pickup's ancestry never changes.
        local function passesFiltersCached(part: Instance): boolean
            if attribute(part, "Collected") == true
                or attribute(part, "Delete") == true then
                return false
            end
            local cached: boolean? = filterCache[part]
            if cached ~= nil then
                return cached
            end
            local result: boolean = passesFilters(part)
            filterCache[part] = result
            return result
        end

        local function consider(part: Instance?): ()
            if not part then
                return
            end
            local visual: Instance? = visualOf(part)
            if not visual or found[visual] then
                return
            end
            if not passesFiltersCached(visual) then
                return
            end
            local family: string = familyOf(visual)
            found[visual] = family
            counts[family] = (counts[family] or 0) + 1
        end

        -- Signature 1: the game's own tag list.
        local tagged: {Instance} = collectionService:GetTagged(COIN_TAG)
        lastRaw.tagged = #tagged
        for _, object: Instance in ipairs(tagged) do
            if object:IsA("BasePart") then consider(object) end
        end

        -- Signatures 2 and 3: CoinID and exact spawn names from one scan.
        for _, object: Instance in ipairs(workspace:GetDescendants()) do
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

    -- Shared with Auto Farm: the pickup parts of the family in use.
    -- CACHED: this used to run a full collectAll() per call, and Auto
    -- Farm polls every 0.4 s -- each poll re-scanned every descendant
    -- of Workspace and hitch-spiked the frame. The cache refreshes on
    -- the ESP's own scans, or at most every 0.5 s when polled.
    local pickupCache: {at: number, list: {Instance}} = {at = -math.huge, list = {}}
    local function refreshPickupCache(found: {[Instance]: string}): ()
        local list: {Instance} = {}
        for part: Instance, family: string in pairs(found) do
            if wanted(family) then
                table.insert(list, part)
            end
        end
        pickupCache = {at = os.clock(), list = list}
    end
    state.mm2CoinPickups = function(): {Instance}
        if os.clock() - pickupCache.at < 0.5 then
            return pickupCache.list
        end
        local found: {[Instance]: string} = collectAll()
        refreshPickupCache(found)
        return pickupCache.list
    end

    local function toggleCoinEsp(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinRefresh")
        disconnectFeatureConnection("MM2CoinCollected")
        disconnectFeatureConnection("MM2CoinsStarted")
        disconnectFeatureConnection("MM2CoinTagAdded")
        disconnectFeatureConnection("MM2CoinTagRemoved")
        disconnectFeatureConnection("MM2CoinAdded")
        clearEffects(CoinEffects)
        clearTags()

        if not enabled then
            local card: any = state.mm2CoinFeature
            if card then
                card:SetStatus(nil)
            end
            return
        end

        local elapsed: number = 0
        local lastStatus: string? = nil
        local dirty: boolean = true

        local function setStatus(text: string): ()

            if text == lastStatus then
                return
            end
            lastStatus = text
            local card: any = state.mm2CoinFeature
            if card then
                card:SetStatus(text)
            end
        end

        -- The visible mesh of a pickup: MainCoin under the CoinVisual
        -- holder (the Candy / coin itself), falling back to the pickup
        -- part. The box takes THIS part's exact size, so the marker is
        -- as small as the candy on screen -- never the big invisible
        -- Coin_Server touch volume.
        local function visualOf(part: Instance): BasePart
            local main: Instance? = part:FindFirstChild("MainCoin", true)
            if main and main:IsA("BasePart") then return main :: BasePart end
            local visual: Instance? = part:FindFirstChild("CoinVisual", true)
            if visual and visual:IsA("BasePart") then return visual :: BasePart end
            return part :: BasePart
        end

        -- One small adornment per visible pickup. Creation happens
        -- once per pickup; between rescans Lua does nothing at all.
        local tagsDirty: boolean = true
        -- Opacity guard: the setting's old default (0.8, from the
        -- full-model Highlight era) made a candy-sized adornment
        -- effectively invisible -- v82-v85 "detected nothing" while
        -- the farm, using the same list, walked to the coins fine.
        -- Cap the marker at 0.6 transparency whatever is saved.
        local function markerTransparency(): number
            return math.clamp(mm2Settings.coinTransparency, 0, 0.6)
        end

        -- Creates the box for one pickup. Called only when the pickups change.
        local function makeTag(part: Instance): any
            local visual: BasePart = visualOf(part)
            local box: BoxHandleAdornment = Instance.new("BoxHandleAdornment")
            box.Name = "WurstCoinBox"
            box.AlwaysOnTop = true
            box.ZIndex = 5
            box.Adornee = visual
            box.Color3 = mm2Settings.coinColor
            box.Transparency = markerTransparency()
            box.Size = visual.Size * 1.3
            box.Parent = part
            return {box = box}
        end

        -- v139: reconciliation runs when the pickup set changes, not every
        -- frame. drawOverlay used to allocate a `seen` table and walk every coin
        -- 60 times a second even when nothing had moved, which showed up as GC
        -- spikes with ~100 coins on the map. A BoxHandleAdornment follows its
        -- Adornee by itself, so the per-frame work was pure waste.
        local function syncTags(): ()
            for part: Instance in pairs(lastFamilies) do
                if part.Parent and not coinTags[part] then
                    coinTags[part] = makeTag(part)
                    tagsDirty = true
                end
            end
            for part: Instance, entry: any in pairs(coinTags) do
                if not part.Parent or not lastFamilies[part] then
                    coinTags[part] = nil
                    pcall(function(): ()
                        entry.box:Destroy()
                    end)
                    tagsDirty = true
                end
            end
            if tagsDirty then
                tagsDirty = false
                local published: {[Instance]: boolean} = {}
                for part: Instance in pairs(coinTags) do
                    published[part] = true
                end
                state.mm2CoinTagParts = published
            end
        end

        -- Per-frame work is now only the colour refresh, twice a second.
        local lastTagColourAt: number = -math.huge
        local function drawOverlay(): ()
            local now: number = os.clock()
            if now - lastTagColourAt < 0.5 then
                return
            end
            lastTagColourAt = now
            for part: Instance, entry: any in pairs(coinTags) do
                if not part.Parent then
                    coinTags[part] = nil
                    entry.box:Destroy()
                    tagsDirty = true
                else
                    pcall(function(): ()
                        entry.box.Color3 = mm2Settings.coinColor
                        entry.box.Transparency = markerTransparency()
                    end)
                end
            end
            if tagsDirty then
                tagsDirty = false
                local published: {[Instance]: boolean} = {}
                for part: Instance in pairs(coinTags) do
                    published[part] = true
                end
                state.mm2CoinTagParts = published
            end
        end

        -- One pickup, cham(s) on its visible geometry only.
        local function refresh(): ()
            local found: {[Instance]: string}, counts: {[string]: number} = collectAll()
            local visible: {[Instance]: boolean} = {}
            table.clear(lastFamilies)
            for object: Instance, family: string in pairs(found) do
                if wanted(family) then
                    visible[object] = true
                    lastFamilies[object] = family
                end
            end
            -- Auto follows the server family, but a mismatch between
            -- the classification and the announcement must not blank
            -- the ESP: fall back to showing every pickup found.
            if settings.family == FAMILY_AUTO and activeFamily() ~= nil then
                local anyWanted: boolean = false
                for object: Instance in pairs(visible) do
                    anyWanted = true
                    break
                end
                if not anyWanted then
                    for object: Instance, family: string in pairs(found) do
                        visible[object] = true
                        lastFamilies[object] = family
                    end
                end
            end
            refreshPickupCache(found)
            syncTags()
            local shown: number = 0
            for _ in pairs(visible) do
                shown += 1
            end
            local foundTotal: number = 0
            for _ in pairs(found) do
                foundTotal += 1
            end
            if foundTotal == 0 then
                setStatus(string.format(
                    "no coins yet (tag %d · id %d · named %d)",
                    lastRaw.tagged, lastRaw.coinId, lastRaw.named))
            else
                setStatus(describe(counts) .. " · " .. shown .. " shown")
            end
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
                -- v139: the only per-frame work left is the colour refresh
                -- (twice a second). BoxHandleAdornments follow their Adornee
                -- inside the engine; the reconciliation lives in refresh().
                drawOverlay()
                elapsed += deltaTime
                if not dirty and elapsed < RESCAN_PERIOD then
                    return
                end
                elapsed = 0
                refresh()
            end
        , nil, "Coin ESP")
    end

    local CoinFeature: any = createUniversalFeature(
        "Coin ESP",
        "Draws one small box, exactly the size of the coin, candy, snow token, beach ball or egg mesh, on every real pickup and reports how many of each family exist.",
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
    addInformationOption(
        CoinFeature,
        "Pickups are recognised by the game's own signatures only: the CoinVisual tag, the CoinID attribute and the exact server/visual part pair. Each pickup gets a single BoxHandleAdornment sized exactly to its visible mesh (no labels), so a hundred coins cost no per-frame Lua. Auto follows the family the server announces on CoinsStarted."
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
