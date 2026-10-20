local Module = {
    Name = "MM2 Auto Unbox",
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
    assert(type(core) == "table", "MM2 Auto Unbox requires the MM2 core module")
    Module.Runtime = runtime

    local mm2Settings: any = core.mm2Settings
    local MM2_ALL_BOXES: {string} = core.MM2_ALL_BOXES
    local MM2_STANDARD_BOXES: {string} = core.MM2_STANDARD_BOXES
    local MM2_EVENT_BOXES: {string} = core.MM2_EVENT_BOXES
    local MM2_BOX_INTERNAL_NAMES: {[string]: {string}} = core.MM2_BOX_INTERNAL_NAMES

    local autoUnboxEnabled: boolean = false
    local statusText: string = "Idle"
    local lastAttemptAt: number = -math.huge
    local foundRemotes: {Instance} = {}
    local remoteCacheAt: number = -math.huge

    -- Try to locate box-related remotes dynamically
    local function findBoxRemotes(): {Instance}
        if os.clock() - remoteCacheAt < 5 and #foundRemotes > 0 then
            return foundRemotes
        end
        remoteCacheAt = os.clock()
        foundRemotes = {}

        local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
        local remotesFolder: Instance? = replicatedStorage:FindFirstChild("Remotes")
        local shopFolder: Instance? = remotesFolder and remotesFolder:FindFirstChild("Shop")
        local gameplayFolder: Instance? = remotesFolder and remotesFolder:FindFirstChild("Gameplay")

        local candidates: {Instance} = {}

        if shopFolder then
            for _, child in ipairs(shopFolder:GetChildren()) do
                if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                    table.insert(candidates, child)
                end
            end
            -- Deep search
            for _, desc in ipairs(shopFolder:GetDescendants()) do
                if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
                    if not table.find(candidates, desc) then
                        table.insert(candidates, desc)
                    end
                end
            end
        end

        if remotesFolder then
            for _, desc in ipairs(remotesFolder:GetDescendants()) do
                if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
                    local lname = string.lower(desc.Name)
                    if string.find(lname, "box", 1, true) or string.find(lname, "crate", 1, true) or string.find(lname, "unbox", 1, true) or string.find(lname, "shop", 1, true) then
                        if not table.find(candidates, desc) then
                            table.insert(candidates, desc)
                        end
                    end
                end
            end
        end

        -- Global search as fallback
        if #candidates == 0 then
            for _, desc in ipairs(replicatedStorage:GetDescendants()) do
                if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
                    local lname = string.lower(desc.Name)
                    if string.find(lname, "box", 1, true) or string.find(lname, "crate", 1, true) then
                        table.insert(candidates, desc)
                        if #candidates >= 12 then break end
                    end
                end
            end
        end

        foundRemotes = candidates
        return foundRemotes
    end

    local function getBoxInternalCandidates(displayName: string): {string}
        local mapped = MM2_BOX_INTERNAL_NAMES[displayName]
        if mapped then
            return mapped
        end
        -- Generate variants
        local noSpace = string.gsub(displayName, "%s+", "")
        local lowerNoSpace = noSpace
        return {
            displayName,
            noSpace,
            string.gsub(displayName, " ", ""),
            string.gsub(displayName, " Box", "Box"),
            string.gsub(displayName, " Box ", ""),
            displayName .. "Box",
            noSpace .. "Box",
        }
    end

    local function tryUnboxBox(boxDisplayName: string, currency: string?): boolean
        local remotes = findBoxRemotes()
        if #remotes == 0 then
            statusText = "No box remote found"
            return false
        end

        local internalNames = getBoxInternalCandidates(boxDisplayName)
        local currenciesToTry: {string} = {}
        if currency and currency ~= "Auto" then
            table.insert(currenciesToTry, currency)
        end
        -- Always try common currency names
        for _, c in ipairs({"Coins", "Coin", "Diamonds", "Diamond", "MysteryKey", "Key", "SnowToken", "Candy", "BeachBall", "Egg"}) do
            if not table.find(currenciesToTry, c) then
                table.insert(currenciesToTry, c)
            end
        end

        for _, remote: Instance in ipairs(remotes) do
            -- Try different argument patterns observed in MM2 scripts
            for _, boxName in ipairs(internalNames) do
                for _, curr in ipairs(currenciesToTry) do
                    local attempts: {{any}} = {
                        {boxName},
                        {boxName, curr},
                        {boxName, curr, 1},
                        {boxName, 1},
                        {boxName, "Coins"},
                        {curr, boxName},
                    }

                    for _, args in ipairs(attempts) do
                        local ok, result = pcall(function()
                            if remote:IsA("RemoteEvent") then
                                remote:FireServer(table.unpack(args))
                                return true
                            else
                                return remote:InvokeServer(table.unpack(args))
                            end
                        end)
                        if ok then
                            statusText = "Fired " .. remote.Name .. " with " .. boxName .. " (" .. curr .. ")"
                            if mm2Settings.autoUnboxShowStatus then
                                notify("AutoUnbox: attempted " .. boxDisplayName .. " via " .. remote.Name)
                            end
                            return true
                        end
                    end
                end
            end
        end

        statusText = "Failed to unbox " .. boxDisplayName
        return false
    end

    local function getAvailableBoxesFromShopGui(): {string}
        local found: {[string]: boolean} = {}
        local playerGui: PlayerGui? = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return {} end

        -- Try to find MainGUI Shop
        local mainGui: Instance? = playerGui:FindFirstChild("MainGUI")
        local shopGui: Instance? = mainGui and mainGui:FindFirstChild("Shop") or playerGui:FindFirstChild("Shop", true) or mainGui and mainGui:FindFirstChild("Shop", true)

        if shopGui then
            for _, desc in ipairs(shopGui:GetDescendants()) do
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    local txt: string = (desc :: any).Text or ""
                    for _, boxName in ipairs(MM2_ALL_BOXES) do
                        if string.find(string.lower(txt), string.lower(boxName), 1, true) then
                            found[boxName] = true
                        end
                    end
                    -- Also detect internal names like "MysteryBox2"
                    for _, boxName in ipairs(MM2_STANDARD_BOXES) do
                        local internal = string.gsub(boxName, "%s+", "")
                        if string.find(string.lower(txt), string.lower(internal), 1, true) then
                            found[boxName] = true
                        end
                    end
                end
            end
        end

        local list: {string} = {}
        for k in pairs(found) do table.insert(list, k) end
        table.sort(list)
        return list
    end

    local function toggleAutoUnbox(enabled: boolean): ()
        autoUnboxEnabled = enabled
        disconnectFeatureConnection("MM2AutoUnboxLoop")

        if not enabled then
            statusText = "Idle"
            return
        end

        statusText = "Running - Target: " .. tostring(mm2Settings.autoUnboxTarget)

        -- Initial remote scan
        findBoxRemotes()
        local guiBoxes = getAvailableBoxesFromShopGui()
        if #guiBoxes > 0 and mm2Settings.autoUnboxShowStatus then
            notify("Shop GUI boxes detected: " .. table.concat(guiBoxes, ", "))
        end

        local elapsed = 0
        featureConnections.MM2AutoUnboxLoop = TaskManager:Connect(function(dt: number)
            elapsed += dt
            if elapsed < mm2Settings.autoUnboxDelay then return end
            elapsed = 0
            if not autoUnboxEnabled then return end
            if os.clock() - lastAttemptAt < mm2Settings.autoUnboxDelay then return end
            lastAttemptAt = os.clock()

            local target = mm2Settings.autoUnboxTarget
            if target == "Auto" then
                -- Auto: try first affordable? For now pick Mystery Box 2 as default
                target = "Mystery Box 2"
            end

            local ok = tryUnboxBox(target, mm2Settings.autoUnboxCurrency)
            if not ok then
                -- Try to refresh remotes periodically
                if os.clock() - remoteCacheAt > 10 then
                    findBoxRemotes()
                end
            end
        end)
    end

    -- Expose to core for UI
    core.toggleAutoUnbox = toggleAutoUnbox
    core.getAvailableBoxes = function(): {string}
        local dynamic = getAvailableBoxesFromShopGui()
        if #dynamic > 0 then return dynamic end
        return MM2_ALL_BOXES
    end
    core.getStandardBoxes = function(): {string} return MM2_STANDARD_BOXES end
    core.getAllBoxes = function(): {string} return MM2_ALL_BOXES end
    core.getBoxRemotes = findBoxRemotes
    core.tryUnboxBox = tryUnboxBox
    core.getAutoUnboxStatus = function(): string return statusText end
    core.refreshBoxList = getAvailableBoxesFromShopGui

    -- Create UI in MM2 section? We will hook into existing MM2 features via framework if available
    -- For now, register as a toggle in the universal Other? Actually we create a dedicated MM2 module entry
    -- Using the same pattern as other MM2 modules: we need to create features via host.createUniversalFeature if available
    -- But since this module is loaded via Wurst.lua composite, we can create features directly using host functions if they exist

    local hostEnv: any = getfenv()
    local createUniversalFeature: any = hostEnv.createUniversalFeature
    local addToggleOption: any = hostEnv.addToggleOption
    local addCycleOption: any = hostEnv.addCycleOption
    local addActionOption: any = hostEnv.addActionOption
    local addInformationOption: any = hostEnv.addInformationOption
    local addNumberOption: any = hostEnv.addNumberOption

    if type(createUniversalFeature) == "function" then
        local BoxFeature = createUniversalFeature(
            "Auto Unbox",
            "Automatically unboxes selected MM2 boxes. Detects all boxes (Mystery Box 1/2, Knife Box 1-5, Rainbow Box, Gun Boxes, Event Boxes).",
            20,
            function(enabled: boolean) toggleAutoUnbox(enabled) end,
            {parent = hostEnv.MM2Scroll, registry = hostEnv.mm2Features}
        )

        if BoxFeature then
            if type(addCycleOption) == "function" then
                addCycleOption(BoxFeature, "Target Box", MM2_ALL_BOXES, table.find(MM2_ALL_BOXES, mm2Settings.autoUnboxTarget) or 2, function(value: string)
                    mm2Settings.autoUnboxTarget = value
                    if autoUnboxEnabled then
                        statusText = "Running - Target: " .. value
                    end
                end)
                addCycleOption(BoxFeature, "Currency", {"Auto", "Coins", "Diamonds", "MysteryKey", "SnowToken", "Candy", "BeachBall", "Egg", "Shell", "Heart", "Gift"}, 1, function(value: string)
                    mm2Settings.autoUnboxCurrency = value
                end)
            end
            if type(addNumberOption) == "function" then
                addNumberOption(BoxFeature, "Delay", mm2Settings.autoUnboxDelay, 0.2, 5, function(value: number)
                    mm2Settings.autoUnboxDelay = value
                end)
            end
            if type(addToggleOption) == "function" then
                addToggleOption(BoxFeature, "Show status", mm2Settings.autoUnboxShowStatus, function(value: boolean)
                    mm2Settings.autoUnboxShowStatus = value
                end)
            end
            if type(addActionOption) == "function" then
                addActionOption(BoxFeature, "Scan shop GUI", function()
                    local boxes = getAvailableBoxesFromShopGui()
                    if #boxes > 0 then
                        notify("Detected boxes: " .. table.concat(boxes, ", "))
                    else
                        notify("No boxes detected in Shop GUI, using hardcoded list (" .. tostring(#MM2_ALL_BOXES) .. ")")
                    end
                end)
                addActionOption(BoxFeature, "Scan remotes", function()
                    local rems = findBoxRemotes()
                    local names: {string} = {}
                    for _, r in ipairs(rems) do table.insert(names, r.Name .. " (" .. r.ClassName .. ")") end
                    if #names > 0 then
                        notify("Box remotes: " .. table.concat(names, ", "))
                    else
                        notify("No box remotes found yet. Open shop in game first.")
                    end
                end)
                addActionOption(BoxFeature, "Unbox once", function()
                    tryUnboxBox(mm2Settings.autoUnboxTarget, mm2Settings.autoUnboxCurrency)
                end)
            end
            if type(addInformationOption) == "function" then
                addInformationOption(BoxFeature, "Standard boxes cost 1000 Coins / 100 Diamonds / 1 Mystery Key. Event boxes need Snow Tokens/Candies/BeachBalls etc. Auto mode tries to detect current shop currency.")
            end
        end
    end

    activeCleanup = function(): ()
        toggleAutoUnbox(false)
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
