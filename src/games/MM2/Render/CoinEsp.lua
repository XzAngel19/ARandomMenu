-- MM2 coins: highlight every coin in the map and report how many exist.
-- Client-side only: it reads the map, it never talks to a remote. The folder
-- and the colour settings already lived in MM2/base.lua as leftovers of the
-- old monolith; this module is what uses them again.
local Module = {
    Name = "MM2 Coin ESP",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

-- The containers the game puts the collectible coins in. The same names are
-- how base.lua recognises a map model, so a hit here is a hit there.
local COIN_CONTAINERS: {string} = {
    "CoinContainer",
    "CoinAreas",
    "Coins",
}

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
    local findMM2Map: any = core.findMM2Map
    local mm2Settings: any = core.mm2Settings

    local function collectInto(container: Instance, found: {[Instance]: boolean}): ()
        for _, child: Instance in ipairs(container:GetChildren()) do
            if child:IsA("BasePart") then
                found[child] = true
            elseif child:IsA("Model") then
                if child:FindFirstChildWhichIsA("BasePart", true) then
                    found[child] = true
                end
            elseif child:IsA("Folder") then
                collectInto(child, found)
            end
        end
        if container:IsA("BasePart") then
            found[container] = true
        end
    end

    local function coinObjects(): {[Instance]: boolean}
        local found: {[Instance]: boolean} = {}
        local map: Instance? = findMM2Map()
        if not map then
            return found
        end
        for _, containerName: string in ipairs(COIN_CONTAINERS) do
            local container: Instance? = map:FindFirstChild(containerName, true)
            if container then
                collectInto(container, found)
            end
        end
        return found
    end

    local function countOf(set: {[Instance]: boolean}): number
        local count: number = 0
        for _ in pairs(set) do
            count += 1
        end
        return count
    end

    local function toggleCoinEsp(enabled: boolean): ()
        disconnectFeatureConnection("MM2CoinRefresh")
        clearEffects(CoinEffects)

        if not enabled then
            local card: any = state.mm2CoinFeature
            if card then
                card:SetStatus(nil)
            end
            return
        end

        local marked: {[Instance]: boolean} = {}
        local elapsed: number = 1
        local lastCount: number = -1

        local function refresh(): ()
            local found: {[Instance]: boolean} = coinObjects()
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
            local count: number = countOf(found)
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
            if count ~= lastCount then
                lastCount = count
                local card: any = state.mm2CoinFeature
                if card then
                    card:SetStatus(
                        count == 0 and "no coins" or (tostring(count) .. " coins")
                    )
                end
            end
        end

        refresh()
        featureConnections.MM2CoinRefresh = TaskManager:Connect(
            function(deltaTime: number): ()
                elapsed += deltaTime
                if elapsed < 0.75 then
                    return
                end
                elapsed = 0
                refresh()
            end
        )
    end

    local CoinFeature: any = createUniversalFeature(
        "Coin ESP",
        "Highlights every coin the current map has, and reports how many there are.",
        3,
        toggleCoinEsp,
        {
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2CoinFeature = CoinFeature
    -- One switch: the card. A second "Coin ESP" row inside a card called
    -- "Coin ESP" is how the old menu ended up with controls that could be ON
    -- while the feature was OFF.
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
        "Only coins that exist in the map are counted; the status shows the live number."
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
