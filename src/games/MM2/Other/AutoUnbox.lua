-- MM2 Auto Unbox: opens the game's own mystery boxes through the same remote
-- the shop uses, with the box and the currency chosen in the menu.
--
-- What the place dump says a box is. The box catalogue lives in
-- `ReplicatedStorage/Database/Sync`: `Sync.MysteryBox` (Mystery Box #1/#2,
-- Knife Box #1-#5, Rainbow Box, Gun Box #1-#3) and `Sync.Eggs` (Common Egg).
-- Event boxes live under `SharedServices/EventInfoService1`: the
-- `MysteryBoxes` folder (Christmas2024Box) and one `MysteryBox` module per
-- entry of `EventList` (Summer2025Box, Halloween2025Box). Every box id also
-- appears in `Sync.NewShop` with its `Price` table, whose keys ARE the
-- currencies it accepts: classic boxes take Coins/Gems/Key, the Christmas box
-- takes SnowTokens2024/SnowKey2024, the Summer box BeachBalls2025/SummerKey2025
-- and the Halloween box Candies2025/HalloweenKey2025.
--
-- How the game opens one. The shop calls
-- `Remotes.Shop.OpenCrate:InvokeServer(boxId, "MysteryBox", currency)` (or
-- `("...", "Eggs", currency)` for pets) and gets the rewarded item id back.
-- The reveal is pure client cosmetics: `Remotes.Shop.BoxController:Fire(list)`
-- plays the official opening animation and reports `CrateComplete`, or
-- `Remotes.Shop.EggController:Fire(eggId, petId)` hatches pets. This module
-- replays exactly that flow; it never touches a Robux prompt.
--
-- Which currency to pay with. The round announces the coin family it pays out
-- through `Remotes/Gameplay/CoinsStarted` (bag names `Coin`, `Candy`,
-- `SnowToken`, `BeachBall`, `Egg`), and `Workspace` carries `CurrentEvent`,
-- `isChristmas`, `IsSummer`, `IsEaster` and `isValentines`. Auto maps that
-- family onto the currencies the chosen box accepts.
local Module = {
    Name = "MM2 Auto Unbox",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

type BoxEntry = {
    id: string,
    name: string,
    category: string,
    prices: {[string]: number},
}

local AUTO_CURRENCY: string = "Auto"
local REVEAL_ON: string = "On"
local REVEAL_OFF: string = "Off"
local DEFAULT_BOX_LABEL: string = "Mystery Box #1"

-- The catalogue as the dump ships it, used when the Sync module cannot be
-- required. Order matches the shop: classic boxes, eggs, event boxes.
local FALLBACK_BOXES: {BoxEntry} = {
    {id = "MysteryBox1", name = "Mystery Box #1", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "MysteryBox2", name = "Mystery Box #2", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "KnifeBox1", name = "Knife Box #1", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "KnifeBox2", name = "Knife Box #2", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "KnifeBox3", name = "Knife Box #3", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "KnifeBox4", name = "Knife Box #4", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "KnifeBox5", name = "Knife Box #5", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "MLG Box", name = "Rainbow Box", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "GunBox1", name = "Gun Box #1", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "GunBox2", name = "Gun Box #2", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "GunBox3", name = "Gun Box #3", category = "MysteryBox", prices = {Coins = 1000, Gems = 100, Key = 1}},
    {id = "Egg", name = "Common Egg", category = "Eggs", prices = {Coins = 1000, Gems = 100}},
    {id = "Christmas2024Box", name = "Christmas Box '24", category = "MysteryBox", prices = {SnowTokens2024 = 800, SnowKey2024 = 1}},
    {id = "Summer2025Box", name = "Summer Box '25", category = "MysteryBox", prices = {BeachBalls2025 = 800, SummerKey2025 = 1}},
    {id = "Halloween2025Box", name = "Halloween Box '25", category = "MysteryBox", prices = {Candies2025 = 800, HalloweenKey2025 = 1}},
}

-- Coin family to the currencies that family pays for. Currency names come
-- from `Sync.Currencies`; the order prefers the current year's currency.
local FAMILY_CURRENCIES: {[string]: {string}} = {
    Coin = {"Coins"},
    Candy = {"Candies2025", "Candies2024", "Candies2022"},
    SnowToken = {"SnowTokens2024", "SnowTokens2023", "SnowTokens2022", "SnowTokens2020"},
    BeachBall = {"BeachBalls2025"},
    Egg = {"Eggs2025", "RareEggs2025"},
    Heart = {"Hearts2023"},
}

local BAG_TO_FAMILY: {[string]: string} = {
    Coin = "Coin",
    Candy = "Candy",
    SnowToken = "SnowToken",
    BeachBall = "BeachBall",
    Egg = "Egg",
}

local function lower(value: string): string
    return string.lower(value)
end

local function contains(value: string, needle: string): boolean
    return string.find(value, needle, 1, true) ~= nil
end

local function sortedKeys(map: {[string]: any}): {string}
    local keys: {string} = {}
    for key: string in pairs(map) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Auto Unbox requires the MM2 core module")
    Module.Runtime = runtime

    local settings = {
        boxLabel = DEFAULT_BOX_LABEL,
        currency = AUTO_CURRENCY,
        delay = 1.5,
        maxBoxes = 10,
        reveal = REVEAL_ON,
    }
    local session = {
        opened = 0,
        failures = 0,
        consecutiveFailures = 0,
        nextAt = 0,
        finished = false,
    }
    -- The coin family the server announces; drives the Auto currency.
    local serverFamily: string? = nil

    ---------------------------------------------------------------
    -- Catalogue: every box the game knows, with its display name and
    -- the currencies its price table accepts.
    ---------------------------------------------------------------

    local function safeRequire(instance: Instance?): any?
        if not instance then
            return nil
        end
        local ok: boolean, result: any = pcall(function(): any
            return (state :: any).requireModule(instance)
        end)
        if ok then
            return result
        end
        return nil
    end

    local function priceOf(boxId: string, sync: any): {[string]: number}?
        if type(sync) == "table" and type(sync.NewShop) == "table" then
            local newShop: any = sync.NewShop
            local holders: {any} = {}
            if type(newShop[boxId]) == "table" then
                table.insert(holders, newShop[boxId])
            end
            if type(newShop.Weapons) == "table" and type(newShop.Weapons[boxId]) == "table" then
                table.insert(holders, newShop.Weapons[boxId])
            end
            if type(newShop.MysteryBox) == "table" and type(newShop.MysteryBox[boxId]) == "table" then
                table.insert(holders, newShop.MysteryBox[boxId])
            end
            for _, holder: any in ipairs(holders) do
                if type(holder.Price) == "table" then
                    return holder.Price
                end
            end
        end
        for _, entry: BoxEntry in ipairs(FALLBACK_BOXES) do
            if entry.id == boxId then
                return entry.prices
            end
        end
        return nil
    end

    local function eventBoxModules(): {Instance}
        local found: {Instance} = {}
        local replicated: Instance = game:GetService("ReplicatedStorage")
        local shared: Instance? = replicated:FindFirstChild("SharedServices")
        local service: Instance? = shared and shared:FindFirstChild("EventInfoService1")
        if not service then
            return found
        end
        local direct: Instance? = service:FindFirstChild("MysteryBoxes")
        if direct then
            for _, child: Instance in ipairs(direct:GetChildren()) do
                if child:IsA("ModuleScript") then
                    table.insert(found, child)
                end
            end
        end
        local eventList: Instance? = service:FindFirstChild("EventList")
        if eventList then
            for _, event: Instance in ipairs(eventList:GetChildren()) do
                local boxModule: Instance? = event:FindFirstChild("MysteryBox")
                if boxModule and boxModule:IsA("ModuleScript") then
                    table.insert(found, boxModule)
                end
            end
        end
        return found
    end

    local function buildCatalog(): ({BoxEntry}, {string})
        local catalog: {BoxEntry} = {}
        local seen: {[string]: boolean} = {}
        local function add(entry: BoxEntry): ()
            if seen[entry.id] then
                return
            end
            seen[entry.id] = true
            table.insert(catalog, entry)
        end

        local replicated: Instance = game:GetService("ReplicatedStorage")
        local database: Instance? = replicated:FindFirstChild("Database")
        local sync: any = safeRequire(database and database:FindFirstChild("Sync"))
        if type(sync) == "table" then
            for _, bankName: string in ipairs({"MysteryBox", "Eggs"}) do
                local bank: any = (sync :: any)[bankName]
                if type(bank) == "table" then
                    for id: string, data: any in pairs(bank) do
                        add({
                            id = id,
                            name = (type(data) == "table" and type(data.Name) == "string" and data.Name) or id,
                            category = bankName == "Eggs" and "Eggs" or "MysteryBox",
                            prices = priceOf(id, sync) or {},
                        })
                    end
                end
            end
        end

        -- Event boxes: the module instance name is the box id, its
        -- `ItemData.Name` (or `Name`) is what the shop calls it.
        for _, boxModule: Instance in ipairs(eventBoxModules()) do
            local data: any = safeRequire(boxModule)
            local display: string? = nil
            if type(data) == "table" then
                if type(data.ItemData) == "table" and type(data.ItemData.Name) == "string" then
                    display = data.ItemData.Name
                elseif type(data.Name) == "string" and data.Name ~= boxModule.Name then
                    display = data.Name
                end
            end
            add({
                id = boxModule.Name,
                name = display or boxModule.Name,
                category = "MysteryBox",
                prices = priceOf(boxModule.Name, sync) or {},
            })
        end

        -- Anything the dump knows and the live game has not registered yet is
        -- still worth offering: the remote answers with a nil reward when a
        -- box is not on sale, and that is reported honestly.
        for _, entry: BoxEntry in ipairs(FALLBACK_BOXES) do
            add(entry)
        end

        table.sort(catalog, function(a: BoxEntry, b: BoxEntry): boolean
            return lower(a.name) < lower(b.name)
        end)

        -- Unique labels for the selector.
        local labelCounts: {[string]: number} = {}
        for _, entry: BoxEntry in ipairs(catalog) do
            labelCounts[entry.name] = (labelCounts[entry.name] or 0) + 1
        end
        local labels: {string} = {}
        for _, entry: BoxEntry in ipairs(catalog) do
            if labelCounts[entry.name] > 1 then
                table.insert(labels, entry.name .. " (" .. entry.id .. ")")
            else
                table.insert(labels, entry.name)
            end
        end
        return catalog, labels
    end

    local catalog: {BoxEntry}, boxLabels: {string} = buildCatalog()
    local labelToEntry: {[string]: BoxEntry} = {}
    for index: number, entry: BoxEntry in ipairs(catalog) do
        labelToEntry[boxLabels[index]] = entry
    end
    if not labelToEntry[settings.boxLabel] then
        settings.boxLabel = boxLabels[1] or ""
    end

    local function currentEntry(): BoxEntry?
        return labelToEntry[settings.boxLabel] or catalog[1]
    end

    -- Every currency the catalogue references, so the selector can name the
    -- coin the player is farming right now.
    local currencyChoices: {string} = {AUTO_CURRENCY}
    do
        local seen: {[string]: boolean} = {[AUTO_CURRENCY] = true}
        for _, entry: BoxEntry in ipairs(catalog) do
            for currency: string in pairs(entry.prices) do
                if not seen[currency] then
                    seen[currency] = true
                    table.insert(currencyChoices, currency)
                end
            end
        end
    end

    ---------------------------------------------------------------
    -- Which coin the server is paying out.
    ---------------------------------------------------------------

    local function familyFromWorkspace(): string?
        local ok: boolean, value: any = pcall(function(): any
            return workspace:GetAttribute("CurrentEvent")
        end)
        local eventName: string = ok and lower(tostring(value or "")) or ""
        if contains(eventName, "halloween") then
            return "Candy"
        elseif contains(eventName, "christmas") then
            return "SnowToken"
        elseif contains(eventName, "summer") then
            return "BeachBall"
        elseif contains(eventName, "easter") then
            return "Egg"
        elseif contains(eventName, "valentine") then
            return "Heart"
        end
        for attribute: string, family: string in pairs({
            isValentines = "Heart",
            isChristmas = "SnowToken",
            isChristmasEnding = "SnowToken",
            IsSummer = "BeachBall",
            IsEaster = "Egg",
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

    local function readSyncDatabase(): any
        local replicated: Instance = game:GetService("ReplicatedStorage")
        local database: Instance? = replicated:FindFirstChild("Database")
        return safeRequire(database and database:FindFirstChild("Sync"))
    end

    local function readProfileData(): any
        local replicated: Instance = game:GetService("ReplicatedStorage")
        local modules: Instance? = replicated:FindFirstChild("Modules")
        return safeRequire(modules and modules:FindFirstChild("ProfileData"))
    end

    -- Read the player's real balance for `currency` from MM2's ProfileData
    -- module when available in the live game. Returns nil only when
    -- ProfileData is not present (e.g. offline test harness).
    local function getPlayerCurrencyBalance(currency: string): number?
        if currency == "Robux" then
            return nil
        end
        local profile: any = readProfileData()
        if type(profile) ~= "table" then
            return nil
        end
        local direct: any = profile[currency]
        if type(direct) == "number" then
            return direct
        end
        local materials: any = profile.Materials
        if type(materials) == "table" and type(materials.Owned) == "table" then
            local matOwned: any = materials.Owned[currency]
            if type(matOwned) == "number" then
                return matOwned
            end
        end
        local weapons: any = profile.Weapons
        if type(weapons) == "table" and type(weapons.Owned) == "table" then
            local wepOwned: any = weapons.Owned[currency]
            if type(wepOwned) == "number" then
                return wepOwned
            end
        end
        if type(profile.Coins) == "number"
            or type(profile.Gems) == "number"
            or type(materials) == "table"
            or type(weapons) == "table" then
            return 0
        end
        return nil
    end

    local function canAffordCurrency(entry: BoxEntry, currency: string): boolean
        local price: number? = entry.prices and entry.prices[currency] or nil
        if type(price) ~= "number" or price <= 0 then
            return true
        end
        local balance: number? = getPlayerCurrencyBalance(currency)
        if balance == nil then
            return true
        end
        return balance >= price
    end

    -- Auto: pay with the currency the active coin family fills, then Coins
    -- and Gems, then the box's event currency, and only then a key. When
    -- ProfileData is loaded, prefer a currency the player can actually afford.
    local function autoCurrency(entry: BoxEntry): string?
        local prices: {[string]: number} = entry.prices or {}
        local orderedCandidates: {string} = {}
        local seenCandidate: {[string]: boolean} = {}
        local function pushCandidate(c: string): ()
            if prices[c] and not seenCandidate[c] then
                seenCandidate[c] = true
                table.insert(orderedCandidates, c)
            end
        end
        local family: string? = activeFamily()
        if family then
            for _, currency: string in ipairs(FAMILY_CURRENCIES[family] or {}) do
                pushCandidate(currency)
            end
        end
        for _, currency: string in ipairs({"Coins", "Gems"}) do
            pushCandidate(currency)
        end
        for _, currency: string in ipairs(sortedKeys(prices)) do
            if not contains(lower(currency), "key") then
                pushCandidate(currency)
            end
        end
        for _, currency: string in ipairs(sortedKeys(prices)) do
            pushCandidate(currency)
        end
        for _, currency: string in ipairs(orderedCandidates) do
            if canAffordCurrency(entry, currency) then
                return currency
            end
        end
        return orderedCandidates[1]
    end

    local function resolveCurrency(entry: BoxEntry): (string?, boolean)
        if settings.currency ~= AUTO_CURRENCY then
            if entry.prices and entry.prices[settings.currency] then
                return settings.currency, false
            end
            -- The chosen currency does not open this box; fall back rather
            -- than fire a request the server has to reject.
            return autoCurrency(entry), true
        end
        return autoCurrency(entry), false
    end

    ---------------------------------------------------------------
    -- Opening: the shop's own remote, then the shop's own reveal.
    ---------------------------------------------------------------

    local function shopRemotes(): Instance?
        local replicated: Instance = game:GetService("ReplicatedStorage")
        local remotes: Instance? = replicated:FindFirstChild("Remotes")
        return remotes and remotes:FindFirstChild("Shop") or nil
    end

    local function report(text: string): ()
        local card: any = state.mm2AutoUnboxFeature
        if card then
            card:SetStatus(text)
        end
    end

    local function summary(): string
        local entry: BoxEntry? = currentEntry()
        local currency: string? = entry and resolveCurrency(entry) or nil
        local text: string = (entry and entry.name or "no box")
            .. " · pay " .. (currency or "nothing")
        local family: string? = activeFamily()
        if family then
            text ..= " · server coin: " .. family
        end
        if session.opened > 0 or session.failures > 0 then
            text ..= " · " .. tostring(session.opened) .. " opened"
            if session.failures > 0 then
                text ..= " · " .. tostring(session.failures) .. " failed"
            end
        end
        if session.finished then
            text ..= " · done"
        end
        return text
    end

    -- A universal card has no :Toggle (that belongs to framework modules); it
    -- switches off through its own onToggle plus the shared repaint.
    local function turnCardOff(): ()
        local card: any = state.mm2AutoUnboxFeature
        if not card then
            return
        end
        card.enabled = false
        pcall(function(): ()
            card.onToggle(false)
        end)
        if type(refreshFeatureToggle) == "function" then
            pcall(refreshFeatureToggle, card)
        end
    end

    local function stop(reason: string?): ()
        disconnectFeatureConnection("MM2AutoUnbox")
        if reason then
            notify(reason)
        end
        turnCardOff()
    end

    -- Opening state that deliberately survives toggles. The tick runs every
    -- frame and InvokeServer yields, so without a hard busy flag the next
    -- tick (or a spam of off/on) fires a second OpenCrate while the first
    -- reveal is still on screen; stacked BoxController reveals are the grey
    -- screen that never clears. One opening at a time, and a reveal owns
    -- the screen until its window ends -- toggling cannot bypass either.
    local openingBusy: boolean = false
    local revealUntil: number = 0
    local REVEAL_SECONDS: number = 5

    -- Clean up any stuck MysteryBoxOpen / Unboxing2 dark overlay ScreenGui
    -- left behind in PlayerGui if MM2's MysteryBoxService errored mid-tween.
    local function clearStuckUnboxOverlays(): ()
        pcall(function(): ()
            local playerGui: Instance? = LocalPlayer
                and LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not playerGui then
                return
            end
            for _, gui: Instance in ipairs(playerGui:GetChildren()) do
                if gui.Name == "MysteryBoxOpen" or gui.Name == "Unboxing2" then
                    gui:Destroy()
                elseif gui.Name == "MainGUI" then
                    for _, subName: string in ipairs({"Lobby", "Game"}) do
                        local sub: Instance? = gui:FindFirstChild(subName)
                        local proc: Instance? = sub and sub:FindFirstChild("Processing")
                        if proc and proc:IsA("GuiObject") then
                            (proc :: GuiObject).Visible = false
                        end
                    end
                end
            end
        end)
    end

    local function isValidReward(reward: any, category: string): boolean
        if type(reward) ~= "string" or reward == "" or reward == "false" or reward == "nil" then
            return false
        end
        local sync: any = readSyncDatabase()
        if type(sync) == "table" then
            if category == "Eggs" then
                local pets: any = sync.Pets
                if type(pets) == "table" and next(pets) ~= nil then
                    return pets[reward] ~= nil
                end
            else
                local weapons: any = sync.Weapons
                local items: any = sync.Item
                if type(weapons) == "table" and next(weapons) ~= nil then
                    if weapons[reward] ~= nil then
                        return true
                    end
                    if type(items) == "table" and items[reward] ~= nil then
                        return true
                    end
                    return false
                end
            end
        end
        return true
    end

    -- MysteryBoxService:PlayOpeningAnimation indexes Sync.MysteryBox[boxId]
    -- and Sync.Weapons[reward] AFTER parenting the dark MysteryBoxOpen GUI
    -- to PlayerGui. If an event box is not in Sync.MysteryBox (or reward is
    -- not in Sync.Weapons), PlayOpeningAnimation crashes mid-function and
    -- leaves the dark overlay stuck forever. Check before firing BoxController.
    local function canPlayBoxAnimationSafely(boxId: string, reward: string): boolean
        local sync: any = readSyncDatabase()
        if type(sync) ~= "table" then
            return true
        end
        local weapons: any = sync.Weapons
        if type(weapons) ~= "table" or next(weapons) == nil then
            return true
        end
        if type(weapons[reward]) ~= "table" then
            return false
        end
        local mysteryBoxes: any = sync.MysteryBox
        if type(mysteryBoxes) == "table" and next(mysteryBoxes) ~= nil then
            local boxDef: any = mysteryBoxes[boxId]
            if type(boxDef) ~= "table" or type(boxDef.Contents) ~= "table" then
                return false
            end
        end
        return true
    end

    local function reveal(boxId: string, category: string, reward: any): ()
        local remotes: Instance? = shopRemotes()
        if not remotes then
            return
        end
        if settings.reveal == REVEAL_ON then
            -- The official flow: the game plays the reveal and reports the
            -- crate as complete (the BoxController LocalScript does both).
            if category == "Eggs" then
                revealUntil = os.clock() + REVEAL_SECONDS
                local eggController: Instance? = remotes:FindFirstChild("EggController")
                if eggController then
                    pcall(function(): ()
                        (eggController :: any):Fire(boxId, reward)
                    end)
                end
                return
            elseif canPlayBoxAnimationSafely(boxId, tostring(reward)) then
                revealUntil = os.clock() + REVEAL_SECONDS
                local boxController: Instance? = remotes:FindFirstChild("BoxController")
                if boxController then
                    pcall(function(): ()
                        (boxController :: any):Fire({{MysteryBoxId = boxId, RewardedItemId = reward}})
                    end)
                end
                return
            end
        end
        -- No animation (or event box missing from Sync.MysteryBox which would
        -- crash MysteryBoxService and leave a dark screen): still report the
        -- crate so the server and inventory register the unboxed item cleanly.
        local crateComplete: Instance? = remotes:FindFirstChild("CrateComplete")
        if crateComplete then
            pcall(function(): ()
                (crateComplete :: any):FireServer(reward)
            end)
        end
    end

    local function openOnce(): boolean
        if openingBusy then
            return false
        end
        openingBusy = true
        local entry: BoxEntry? = currentEntry()
        if not entry then
            session.finished = true
            openingBusy = false
            stop("Auto Unbox: no box catalogue found.")
            return false
        end
        local currency: string?, forced: boolean = resolveCurrency(entry)
        if not currency then
            session.finished = true
            openingBusy = false
            stop("Auto Unbox: " .. entry.name .. " has no known price currency.")
            return false
        end
        -- Verify the player actually has enough currency BEFORE calling
        -- OpenCrate or playing any reveal animation. If insufficient, do
        -- nothing and stop immediately without opening imaginary boxes.
        local requiredPrice: number? = entry.prices and entry.prices[currency] or nil
        local currentBalance: number? = getPlayerCurrencyBalance(currency)
        if type(requiredPrice) == "number"
            and requiredPrice > 0
            and type(currentBalance) == "number"
            and currentBalance < requiredPrice then
            clearStuckUnboxOverlays()
            session.finished = true
            openingBusy = false
            report(summary())
            stop(
                "Auto Unbox stopped: not enough "
                    .. tostring(currency)
                    .. " ("
                    .. tostring(currentBalance)
                    .. "/"
                    .. tostring(requiredPrice)
                    .. ") for "
                    .. entry.name
                    .. "."
            )
            return false
        end
        local remotes: Instance? = shopRemotes()
        local openCrate: Instance? = remotes and remotes:FindFirstChild("OpenCrate")
        if not (openCrate and openCrate:IsA("RemoteFunction")) then
            session.finished = true
            openingBusy = false
            stop("Auto Unbox: the game's OpenCrate remote is missing.")
            return false
        end
        local note: string = forced
            and (" · " .. settings.currency .. " rejected, using " .. currency)
            or ""
        local ok: boolean, reward: any = pcall(function(): any
            return (openCrate :: any):InvokeServer(entry.id, entry.category, currency)
        end)
        if ok and isValidReward(reward, entry.category) then
            reveal(entry.id, entry.category, reward)
            session.opened += 1
            session.consecutiveFailures = 0
            report(summary() .. note)
            openingBusy = false
            return true
        end
        clearStuckUnboxOverlays()
        session.failures += 1
        session.consecutiveFailures += 1
        report(summary() .. note)
        openingBusy = false
        if reward == false or session.consecutiveFailures >= 3 then
            session.finished = true
            stop(
                "Auto Unbox stopped: "
                    .. entry.name
                    .. " did not open with "
                    .. tostring(currency)
                    .. ". Not enough currency, or the box is not on sale."
            )
        end
        return false
    end

    local function tick(_deltaTime: number): ()
        if session.finished then
            return
        end
        if session.opened >= math.round(settings.maxBoxes) then
            session.finished = true
            report(summary())
            stop(nil)
            return
        end
        local now: number = os.clock()
        if now < session.nextAt or now < revealUntil or openingBusy then
            return
        end
        openOnce()
        -- Extra settle time while the reveal plays: firing the next
        -- BoxController animation over a running one can leave the screen
        -- black, so a revealed box always gets a longer breather.
        local settle: number = settings.reveal == REVEAL_ON
            and REVEAL_SECONDS or 0
        session.nextAt = os.clock() + settings.delay + settle
    end

    local AutoUnboxFeature: any = createUniversalFeature(
        "Auto Unbox",
        "Opens any mystery box or egg of the game through its own OpenCrate remote, paying with the currency you choose or the coin the server is giving.",
        4,
        function(enabled: boolean): ()
            disconnectFeatureConnection("MM2AutoUnbox")
            if os.clock() >= revealUntil then
                clearStuckUnboxOverlays()
            end
            if not enabled then
                return
            end
            session.opened = 0
            session.failures = 0
            session.consecutiveFailures = 0
            -- Never sooner than a reveal still on screen: re-enabling in
            -- the middle of one must not stack a second BoxController.
            session.nextAt = math.max(os.clock(), revealUntil)
            session.finished = false
            report(summary())
            featureConnections.MM2AutoUnbox = TaskManager:Connect(tick)
        end,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoUnboxFeature = AutoUnboxFeature

    -- The server names the coin family this round pays out; Auto uses it to
    -- pick the currency.
    local startedRemote: Instance? = core.mm2GameplayRemotes
        and core.mm2GameplayRemotes:FindFirstChild("CoinsStarted")
    if startedRemote and startedRemote:IsA("RemoteEvent") then
        featureConnections.MM2AutoUnboxCoinsStarted =
            (startedRemote :: any).OnClientEvent:Connect(function(bagTable: any): ()
                if type(bagTable) == "table" then
                    for bag: any in pairs(bagTable) do
                        local family: string? = BAG_TO_FAMILY[tostring(bag)]
                        if family then
                            serverFamily = family
                        end
                    end
                end
                if state.mm2AutoUnboxFeature then
                    report(summary())
                end
            end)
    end

    local defaultBoxIndex: number = table.find(boxLabels, DEFAULT_BOX_LABEL) or 1
    addCycleOption(
        AutoUnboxFeature,
        "Box to open",
        boxLabels,
        defaultBoxIndex,
        function(value: string): ()
            settings.boxLabel = value
        end,
        "Every box and egg of the game, including the event boxes."
    )
    addCycleOption(
        AutoUnboxFeature,
        "Pay with",
        currencyChoices,
        1,
        function(value: string): ()
            settings.currency = value
        end,
        "Auto pays with the currency the server's current coin fills."
    )
    addCycleOption(
        AutoUnboxFeature,
        "Reveal animation",
        {REVEAL_ON, REVEAL_OFF},
        1,
        function(value: string): ()
            settings.reveal = value
        end,
        "On replays the game's own opening animation and crate report."
    )
    addNumberOption(
        AutoUnboxFeature,
        "Delay between boxes",
        settings.delay,
        0.8,
        5,
        function(value: number): ()
            settings.delay = value
        end
    )
    addNumberOption(
        AutoUnboxFeature,
        "Max boxes per run",
        settings.maxBoxes,
        1,
        50,
        function(value: number): ()
            settings.maxBoxes = value
        end
    )
    addActionOption(
        AutoUnboxFeature,
        "Report boxes and coin",
        function(): ()
            local entry: BoxEntry? = currentEntry()
            local prices: {string} = {}
            if entry then
                for _, currency: string in ipairs(sortedKeys(entry.prices)) do
                    table.insert(prices, currency .. "=" .. tostring(entry.prices[currency]))
                end
            end
            notify(
                "Boxes found: " .. tostring(#catalog)
                    .. " · chosen: " .. (entry and entry.name or "none")
                    .. " (" .. (entry and entry.id or "?") .. ")"
                    .. " · price: " .. (#prices > 0 and table.concat(prices, ", ") or "unknown")
                    .. " · server coin: " .. tostring(activeFamily() or "unknown")
            )
        end
    )
    addInformationOption(
        AutoUnboxFeature,
        "Uses the shop's own OpenCrate remote with the box id and currency the game expects, then the game's own reveal. Robux prompts are never pressed."
    )

    activeCleanup = function(): ()
        state.mm2AutoUnboxFeature = nil
        disconnectFeatureConnection("MM2AutoUnbox")
        disconnectFeatureConnection("MM2AutoUnboxCoinsStarted")
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
