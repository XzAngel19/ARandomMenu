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

    -- Cham models: one cloned mesh per pickup geometry part, living in a
    -- folder in the workspace and following the original every frame.
    -- A Highlight never rendered here (the pickup holders are invisible,
    -- Transparency = 1, and Highlights skip transparent parts), so each
    -- coin gets a real neon copy of itself instead.
    local chamFolder: Instance? = nil
    local chamClones: {{source: Instance, clone: Instance}} = {}
    -- Geometry part -> its clone, for tests and the report action.
    state.mm2CoinChamSources = {}

    local function clearChams(): ()
        for _, entry in ipairs(chamClones) do
            pcall(function(): ()
                entry.clone:Destroy()
            end)
        end
        table.clear(chamClones)
        state.mm2CoinChamSources = {}
        if chamFolder then
            pcall(function(): ()
                (chamFolder :: Instance):Destroy()
            end)
            chamFolder = nil
        end
    end

    -- Native per-pickup tags: a BillboardGui label and a
    -- BoxHandleAdornment parented straight onto the pickup part.
    -- Adornments and billboards render regardless of the part's own
    -- transparency (the holders are Transparency = 1) and through
    -- walls, with no dependency on any menu library or projection
    -- math -- this is the part that must always be visible.
    local coinTags: {[Instance]: {gui: Instance, label: Instance, box: Instance}} = {}
    -- Pickup -> family, kept between scans for the tag text.
    local lastFamilies: {[Instance]: string} = {}
    -- Parts currently carrying a tag, for tests and the report action.
    state.mm2CoinTagParts = {}

    local function clearTags(): ()
        for part: Instance, entry in pairs(coinTags) do
            coinTags[part] = nil
            pcall(function(): ()
                entry.gui:Destroy()
            end)
            pcall(function(): ()
                entry.box:Destroy()
            end)
        end
        table.clear(lastFamilies)
        state.mm2CoinTagParts = {}
    end

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
        clearChams()
        clearTags()

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

        -- The geometry of one pickup: its mesh parts (what the player
        -- actually sees), else its plain parts, else -- when the holder
        -- carries no geometry at all -- the geometry of its parent
        -- group, provided that group is pickup-sized (a container of
        -- many coins is never cloned).
        local function geometryOf(visual: Instance): {Instance}
            local meshes: {Instance} = {}
            local parts: {Instance} = {}
            local function harvest(root: Instance): ()
                if root:IsA("BasePart") then
                    table.insert(parts, root)
                    if root:IsA("MeshPart") then
                        table.insert(meshes, root)
                    end
                end
                local ok: boolean, descendants: any = pcall(function(): any
                    return root:GetDescendants()
                end)
                if ok and type(descendants) == "table" then
                    for _, object: Instance in ipairs(descendants) do
                        -- The invisible server holder is never geometry.
                        if object:IsA("BasePart") and object.Name ~= SERVER_NAME then
                            table.insert(parts, object)
                            if object:IsA("MeshPart") then
                                table.insert(meshes, object)
                            end
                        end
                    end
                end
            end
            harvest(visual)
            if #meshes == 0 and #parts <= 1 then
                local parent: Instance? = visual.Parent
                if parent and parent ~= workspace then
                    local ok: boolean, descendants: any = pcall(function(): any
                        return parent:GetDescendants()
                    end)
                    if ok and type(descendants) == "table" then
                        local total: number = 0
                        for _, object: Instance in ipairs(descendants) do
                            if object:IsA("BasePart") then
                                total += 1
                            end
                        end
                        if total > 0 and total <= 24 then
                            table.clear(meshes)
                            table.clear(parts)
                            harvest(parent)
                        end
                    end
                end
            end
            if #meshes > 0 then
                return meshes
            end
            return parts
        end

        -- A cham model of the coin itself: clone each geometry part,
        -- strip everything inside it, force it neon in the coin colour
        -- and slightly larger than the original, so a glowing copy of
        -- the coin sits exactly where the coin is.
        local function buildChams(visible: {[Instance]: boolean}): ()
            clearChams()
            local folder: Instance = Instance.new("Folder")
            folder.Name = "WurstCoinChams"
            folder.Parent = workspace
            chamFolder = folder
            local transparency: number = math.clamp(mm2Settings.coinTransparency, 0, 0.6)
            for visual: Instance in pairs(visible) do
                for _, source: Instance in ipairs(geometryOf(visual)) do
                    local ok: boolean, clone: any = pcall(function(): any
                        return (source :: any):Clone()
                    end)
                    if ok and clone then
                        for _, child: Instance in ipairs(clone:GetDescendants()) do
                            pcall(function(): ()
                                child:Destroy()
                            end)
                        end
                        clone.Name = "CoinCham"
                        clone.Anchored = true
                        clone.CanCollide = false
                        clone.CanQuery = false
                        clone.CanTouch = false
                        clone.Color = mm2Settings.coinColor
                        clone.Transparency = transparency
                        pcall(function(): ()
                            clone.Material = Enum.Material.Neon
                        end)
                        pcall(function(): ()
                            clone.Size = clone.Size * 1.07
                        end)
                        clone.CFrame = (source :: any).CFrame
                        clone.Parent = folder
                        table.insert(chamClones, {source = source, clone = clone})
                        state.mm2CoinChamSources[source] = clone
                    end
                end
            end
        end

        -- Coins spin and bob: every clone follows its original.
        local function syncChams(): ()
            for index: number = #chamClones, 1, -1 do
                local entry = chamClones[index]
                if not entry.source.Parent then
                    pcall(function(): ()
                        entry.clone:Destroy()
                    end)
                    state.mm2CoinChamSources[entry.source] = nil
                    table.remove(chamClones, index)
                else
                    entry.clone.CFrame = (entry.source :: any).CFrame
                end
            end
        end

        -- Label + adornment box for every visible pickup, parented to
        -- the pickup part itself: Roblox draws both no matter how
        -- transparent the holder is, and AlwaysOnTop puts them through
        -- walls. The text refresh is throttled; the instances follow
        -- their parts on their own.
        local tagClock: number = 0
        local function drawOverlay(forceText: boolean?): ()
            local camera: any = nil
            local okCam: boolean, foundCam: any = pcall(function(): any
                return workspace.CurrentCamera
            end)
            if okCam then
                camera = foundCam
            end
            local origin: any = camera and camera.CFrame and camera.CFrame.Position
            tagClock += 1
            local refreshText: boolean = forceText == true or tagClock % 15 == 0
            local seen: {[Instance]: boolean} = {}
            for part: Instance, family: string in pairs(lastFamilies) do
                if part.Parent then
                    seen[part] = true
                    local entry = coinTags[part]
                    if not entry then
                        local okMake: boolean, created: any = pcall(function(): any
                            local gui: Instance = Instance.new("BillboardGui")
                            gui.Name = "WurstCoinTag"
                            gui.AlwaysOnTop = true
                            gui.LightInfluence = 0
                            gui.Size = UDim2.fromOffset(96, 22)
                            gui.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
                            local label: Instance = Instance.new("TextLabel")
                            label.Name = "Text"
                            label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                            label.BackgroundTransparency = 0.45
                            label.BorderSizePixel = 0
                            label.Size = UDim2.fromScale(1, 1)
                            label.TextColor3 = mm2Settings.coinColor
                            label.TextScaled = true
                            label.TextStrokeTransparency = 0.4
                            label.Parent = gui
                            local box: Instance = Instance.new("BoxHandleAdornment")
                            box.Name = "WurstCoinBox"
                            box.AlwaysOnTop = true
                            box.ZIndex = 5
                            box.Adornee = part
                            box.Color3 = mm2Settings.coinColor
                            box.Transparency = 0.35
                            local okSize: boolean, partSize: any = pcall(function(): any
                                return (part :: any).Size
                            end)
                            if okSize and partSize then
                                box.Size = partSize
                            end
                            gui.Parent = part
                            box.Parent = part
                            return {gui = gui, label = label, box = box}
                        end)
                        if okMake and created then
                            entry = created
                            coinTags[part] = entry
                        end
                    end
                    if entry and refreshText then
                        local nouns: {string} = FAMILY_NOUNS[family] or FAMILY_NOUNS[FAMILY_COIN]
                        local text: string = nouns[1]
                        local position: any = (part :: any).Position
                        if origin and position then
                            local okDist: boolean, dist: any = pcall(function(): any
                                return (position - origin).Magnitude
                            end)
                            if okDist and type(dist) == "number" then
                                text = "[" .. tostring(math.round(dist)) .. "] " .. text
                            end
                        end
                        pcall(function(): ()
                            entry.label.Text = text
                            entry.label.TextColor3 = mm2Settings.coinColor
                            entry.box.Color3 = mm2Settings.coinColor
                        end)
                    end
                end
            end
            for part: Instance in pairs(coinTags) do
                if not seen[part] then
                    local entry = coinTags[part]
                    coinTags[part] = nil
                    pcall(function(): ()
                        entry.gui:Destroy()
                    end)
                    pcall(function(): ()
                        entry.box:Destroy()
                    end)
                end
            end
            -- Publish which parts carry tags right now.
            local published: {[Instance]: boolean} = {}
            for part: Instance in pairs(coinTags) do
                published[part] = true
            end
            state.mm2CoinTagParts = published
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
                buildChams(visible)
            end
            drawOverlay(true)
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
                -- The clones follow their coins every frame; the scan
                -- itself only runs when something changed (plus the
                -- safety-net rescan).
                syncChams()
                drawOverlay()
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
        "Puts a glowing cham model of each real coin, candy, snow token, beach ball and egg on the map and reports how many of each family exist.",
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
                    .. " · tags drawn=" .. tostring((function(): number
                        local n: number = 0
                        for _ in pairs(state.mm2CoinTagParts or {}) do
                            n += 1
                        end
                        return n
                    end)())
            )
        end
    )
    addInformationOption(
        CoinFeature,
        "Pickups are recognised by the game's own signatures only: the CoinVisual tag, the CoinID attribute and the exact server/visual part pair. Each pickup gets a cloned cham model of its own mesh (neon, in the coin colour) that follows it; containers are never cloned. Auto follows the family the server announces on CoinsStarted."
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
